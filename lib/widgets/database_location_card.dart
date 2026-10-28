// lib/widgets/database_location_card.dart
//
// 📂 مكان قاعدة البيانات: المسار الوحيد الذي يفتحه البرنامج، مع زر «فتح المجلد»
// و«نسخ المسار»، وشرح كيف تضع قاعدة جاهزة مكانها، وما هي المجلدات الأخرى.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/database/core/database_config.dart';
import '../services/demo_mode.dart';
import 'settings_kit.dart';

class DatabaseLocationCard extends StatefulWidget {
  const DatabaseLocationCard({super.key});

  @override
  State<DatabaseLocationCard> createState() => _DatabaseLocationCardState();
}

class _DatabaseLocationCardState extends State<DatabaseLocationCard> {
  String? _path;
  int? _size;
  String? _docs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    try {
      final path = await DatabaseConfig.getDatabasePath();
      final f = File(path);
      final size = await f.exists() ? await f.length() : null;
      String? docs;
      try {
        docs = (await getApplicationDocumentsDirectory()).path;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _path = path;
          _size = size;
          _docs = docs;
        });
      }
    } catch (_) {}
  }

  Future<void> _openFolder() async {
    final path = _path;
    if (path == null) return;
    try {
      if (Platform.isWindows) {
        // يفتح المجلد ويحدّد الملف داخله
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [p.dirname(path)]);
      }
    } catch (e) {
      if (mounted) setToast(context, 'تعذّر فتح المجلد: $e', error: true);
    }
  }

  void _copy() {
    if (_path == null) return;
    Clipboard.setData(ClipboardData(text: _path!));
    setToast(context, 'نُسخ مسار قاعدة البيانات');
  }

  String _fmtSize(int b) => b > 1048576 ? '${(b / 1048576).toStringAsFixed(1)} ميجابايت' : '${(b / 1024).toStringAsFixed(0)} كيلوبايت';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final path = _path;
    final isMobile = Platform.isAndroid || Platform.isIOS;
    return SetCard(
      title: 'مكان قاعدة البيانات',
      subtitle: 'الملف الوحيد الذي يقرأ منه البرنامج ويكتب فيه',
      icon: Icons.folder_open_rounded,
      color: const Color(0xFF0F766E),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        if (DemoMode.isOn)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SetBanner('الوضع التجريبي مفعّل: المسار أدناه للقاعدة التجريبية، لا لقاعدتك الحقيقية.',
                kind: SetBannerKind.warn),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF99F6E4)),
          ),
          child: Row(children: [
            const Icon(Icons.storage_rounded, color: Color(0xFF0F766E)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SelectableText(path ?? '...',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 13, fontWeight: FontWeight.w700, color: kSetText)),
                if (_size != null)
                  Text('الحجم: ${_fmtSize(_size!)}', style: const TextStyle(fontSize: 12, color: kSetMuted)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!isMobile)
            FilledButton.icon(
              onPressed: path == null ? null : _openFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('فتح المجلد'),
            ),
          OutlinedButton.icon(
            onPressed: path == null ? null : _copy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('نسخ المسار'),
          ),
        ]),
        const SizedBox(height: 12),
        const SetBanner(
          'لوضع قاعدة جاهزة عندك: استعمل «استعادة قاعدة البيانات من ملف» أدناه (الأسهل والأضمن).\n'
          'أو يدوياً: أغلق البرنامج، ضع ملفك في هذا المجلد باسم debt_book.db، واحذف الملفين '
          'debt_book.db-wal و debt_book.db-shm إن وُجدا، ثم افتح البرنامج.\n'
          'عند الفتح يُكمل البرنامج تلقائياً كل جدول أو عمود ينقص القاعدة، أو ينشئ قاعدة جديدة إن لم يجد ملفاً.',
        ),
        if (_docs != null) ...[
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('مجلدات أخرى قد تراها (ليست قاعدة البيانات)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            children: [
              _other(Icons.backup_rounded, 'نسخ احتياطية تلقائية عند الإغلاق', p.join(_docs!, 'دفتر_ديوني_نسخ_احتياطية')),
              _other(Icons.manage_search_rounded, 'فهرس البحث الذكي (يُعاد بناؤه، لا بيانات فيه)', p.join(_docs!, 'smart_search.db')),
              if (path != null)
                _other(Icons.restore_rounded, 'نسخة احتياطية للاستعادة عند تلف القاعدة',
                    p.join(p.dirname(path), '.dart_tool', 'sqflite_common_ffi', 'databases', 'debt_book_backup.db')),
            ],
          ),
        ],
      ]),
    );
  }

  Widget _other(IconData icon, String title, String path) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20, color: kSetMuted),
        title: Text(title, style: const TextStyle(fontSize: 12.5)),
        subtitle: SelectableText(path, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11.5)),
      );
}
