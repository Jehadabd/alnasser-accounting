// lib/services/exit_backup.dart
//
// 💾 نسخة احتياطية عند الخروج من البرنامج (الحاسبة: ويندوز/ماك/لينكس).
//
// الإعداد (الإعدادات ← النسخ الاحتياطي): اسألني دائماً (الافتراضي) / احفظ دائماً / لا تحفظ.
// المحفوظ: قاعدة البيانات مضغوطة (.tar.xz) — الحزمة نفسها التي تُرفع لتيليجرام ودروب بوكس:
// لقطة متّسقة، فحص سلامتها، ضغط متحقق منه بفكّه ومقارنته بايتاً ببايت (BackupPackage).
// تُستعاد من: الإعدادات ← استعادة قاعدة البيانات من ملف.
//
// قواعد الأمان:
//   • القاعدة الحية لا تُلمس: العمل كله على لقطة في مجلد مؤقت.
//   • الملف يُنسخ إلى مجلد المستخدم ثم يُتحقق أن حجمه = حجم الأصل؛ غير ذلك يُحذف
//     الناقص ويُبلَّغ المستخدم (لا يبقى ملف ناقص يُظن أنه نسخة).
//   • أي فشل لا يحبس المستخدم: يُسأل «إغلاق دون نسخة أم البقاء؟».
//   • الطرفية (على قاعدة حاسبة السيرفر) والوضع التجريبي: لا نسخ من هنا.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../lan/lan_settings.dart';
import 'backup_package.dart';
import 'demo_mode.dart';

enum ExitBackupMode { ask, always, never }

class ExitBackup {
  ExitBackup._();

  static const _modeKey = 'exit_backup_mode_v1';
  static const _dirKey = 'exit_backup_dir_v1';

  /// الميزة على الحاسبة فقط (على الهاتف لا «إغلاق نافذة»، ومجلدات أندرويد محمية).
  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static Future<ExitBackupMode> mode() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_modeKey);
      return ExitBackupMode.values.firstWhere((m) => m.name == v, orElse: () => ExitBackupMode.ask);
    } catch (_) {
      return ExitBackupMode.ask;
    }
  }

  static Future<void> setMode(ExitBackupMode m) async {
    await (await SharedPreferences.getInstance()).setString(_modeKey, m.name);
  }

  static Future<String?> folder() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_dirKey);
      return (v == null || v.trim().isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setFolder(String path) async {
    await (await SharedPreferences.getInstance()).setString(_dirKey, path);
  }

  /// يفتح نافذة اختيار مجلد. null = ألغى.
  static Future<String?> pickFolder({String? initial}) async {
    try {
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد حفظ النسخة الاحتياطية',
        initialDirectory: initial,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _folderOk(String? path) async {
    if (path == null) return false;
    try {
      return await Directory(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// يُستدعى عند طلب إغلاق البرنامج. true = أغلِق، false = ابقَ مفتوحاً.
  static Future<bool> onExit(BuildContext context) async {
    if (!supported || DemoMode.isOn || AppNetworkMode.isClient) return true;
    final m = await mode();
    if (m == ExitBackupMode.never) return true;
    final dir = await folder();
    if (!context.mounted) return true;

    if (m == ExitBackupMode.always && await _folderOk(dir)) {
      if (!context.mounted) return true;
      return _saveThenDecide(context, dir!);
    }

    // اسألني (أو «احفظ دائماً» بلا مجلد صالح بعد)
    final choice = await showDialog<_ExitChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExitBackupDialog(initialFolder: dir, alwaysMissingFolder: m == ExitBackupMode.always),
    );
    if (choice == null || choice.action == _ExitAction.stay) return false;
    if (choice.action == _ExitAction.skip) {
      if (choice.remember) await setMode(ExitBackupMode.never);
      return true;
    }
    await setFolder(choice.folder!);
    if (choice.remember) await setMode(ExitBackupMode.always);
    if (!context.mounted) return true;
    return _saveThenDecide(context, choice.folder!);
  }

  /// يحفظ مع نافذة تقدّم. نجح ⇒ true. فشل ⇒ يسأل: إغلاق دون نسخة أم البقاء.
  static Future<bool> _saveThenDecide(BuildContext context, String dir) async {
    final progress = ValueNotifier<double>(0);
    String? savedPath;
    Object? error;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _ProgressDialog(progress: progress)),
    );
    try {
      savedPath = await saveTo(dir, onProgress: (v) => progress.value = v);
    } catch (e) {
      error = e;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (!context.mounted) return true;
    if (savedPath != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('حُفظت النسخة: $savedPath'),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return true;
    }
    final close = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تعذّر حفظ النسخة الاحتياطية'),
        content: Text('$error', style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('البقاء في البرنامج')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إغلاق دون نسخة'),
          ),
        ],
      ),
    );
    return close ?? false;
  }

  /// يصنع الحزمة المضغوطة المتحقق منها وينسخها إلى [dir]. يُرجع مسار الملف.
  /// يرمي Exception برسالة عربية عند أي فشل (ولا يترك ملفاً ناقصاً).
  static Future<String> saveTo(String dir, {void Function(double p)? onProgress}) async {
    if (!await _folderOk(dir)) throw Exception('المجلد غير موجود: $dir');
    final pkg = await BackupPackage.build(onProgress: (v) => onProgress?.call(v * 0.95));
    File? out;
    try {
      final name = 'نسخة_الناصر_${p.basename(pkg.file.path)}';
      out = File(p.join(dir, name));
      await pkg.file.copy(out.path);
      final want = await pkg.length();
      final got = await out.length();
      if (got != want) {
        throw Exception('النسخة المحفوظة ناقصة ($got من $want بايت) — ربما امتلأ القرص');
      }
      onProgress?.call(1);
      return out.path;
    } catch (e) {
      // ملف ناقص لا يبقى ليُظن أنه نسخة سليمة
      try {
        if (out != null && await out.exists()) {
          final want = await pkg.length();
          if (await out.length() != want) await out.delete();
        }
      } catch (_) {}
      if (e is FileSystemException) {
        throw Exception('تعذّر الكتابة في المجلد: ${e.osError?.message ?? e.message}');
      }
      rethrow;
    } finally {
      await pkg.dispose();
    }
  }
}

enum _ExitAction { save, skip, stay }

class _ExitChoice {
  const _ExitChoice(this.action, {this.folder, this.remember = false});
  final _ExitAction action;
  final String? folder;
  final bool remember;
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress});
  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.save_alt_rounded, color: Color(0xFF0F3460)),
        SizedBox(width: 10),
        Text('جارٍ حفظ النسخة الاحتياطية'),
      ]),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: v <= 0 ? null : v, minHeight: 10),
          ),
          const SizedBox(height: 10),
          Text('${(v * 100).clamp(0, 100).toStringAsFixed(0)}٪ — لا تُطفئ الحاسبة حتى ينتهي',
              style: const TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }
}

/// نافذة «حفظ نسخة احتياطية قبل الخروج؟» مع اختيار المجلد وتذكّر الاختيار.
class _ExitBackupDialog extends StatefulWidget {
  const _ExitBackupDialog({required this.initialFolder, required this.alwaysMissingFolder});
  final String? initialFolder;
  final bool alwaysMissingFolder;

  @override
  State<_ExitBackupDialog> createState() => _ExitBackupDialogState();
}

class _ExitBackupDialogState extends State<_ExitBackupDialog> {
  static const _navy = Color(0xFF0F3460);
  String? _folder;
  bool _remember = false;

  @override
  void initState() {
    super.initState();
    _folder = widget.initialFolder;
  }

  Future<void> _choose() async {
    final f = await ExitBackup.pickFolder(initial: _folder);
    if (f != null && mounted) setState(() => _folder = f);
  }

  Future<void> _save() async {
    var f = _folder;
    if (f == null || !await Directory(f).exists()) {
      await _choose();
      f = _folder;
      if (f == null || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pop(context, _ExitChoice(_ExitAction.save, folder: f, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.backup_rounded, color: _navy),
          SizedBox(width: 10),
          Expanded(child: Text('حفظ نسخة احتياطية قبل الخروج؟')),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              widget.alwaysMissingFolder
                  ? 'الإعداد «احفظ دائماً» يحتاج مجلداً للحفظ. اختر المجلد مرة واحدة.'
                  : 'تُحفظ قاعدة البيانات كاملة مضغوطة في المجلد الذي تختاره، وتُستعاد من الإعدادات عند الحاجة.',
              style: const TextStyle(height: 1.6, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            Material(
              color: _navy.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _choose,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.folder_rounded, color: Color(0xFFB45309)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _folder ?? 'لم يُختر مجلد بعد',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: _folder == null ? Colors.black45 : _navy, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('تغيير', style: TextStyle(color: _navy, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              title: const Text('تذكّر اختياري ولا تسألني مرة أخرى'),
              subtitle: const Text('يُغيَّر من الإعدادات ← النسخ الاحتياطي', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, const _ExitChoice(_ExitAction.stay)),
            child: const Text('إلغاء'),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () => Navigator.pop(context, _ExitChoice(_ExitAction.skip, remember: _remember)),
              child: Text('خروج دون نسخة', style: TextStyle(color: Colors.red.shade700)),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF047857),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _save,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('حفظ ثم خروج'),
            ),
          ]),
        ],
      ),
    );
  }
}
