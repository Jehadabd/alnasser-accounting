// lib/widgets/exit_backup_tile.dart
//
// 💾 الإعدادات ← النسخ الاحتياطي: «نسخة احتياطية عند الخروج» (ExitBackup).
// يُحفظ فوراً عند التغيير (إعداد هذا الجهاز).

import 'package:flutter/material.dart';

import '../services/exit_backup.dart';

class ExitBackupTile extends StatefulWidget {
  const ExitBackupTile({super.key});

  @override
  State<ExitBackupTile> createState() => _ExitBackupTileState();
}

class _ExitBackupTileState extends State<ExitBackupTile> {
  static const _navy = Color(0xFF0F3460);
  ExitBackupMode _mode = ExitBackupMode.ask;
  String? _folder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await ExitBackup.mode();
    final f = await ExitBackup.folder();
    if (mounted) {
      setState(() {
        _mode = m;
        _folder = f;
      });
    }
  }

  Future<void> _setMode(ExitBackupMode m) async {
    if (m == ExitBackupMode.always && _folder == null) {
      final f = await ExitBackup.pickFolder();
      if (f == null) return; // «احفظ دائماً» بلا مجلد لا معنى له
      await ExitBackup.setFolder(f);
      _folder = f;
    }
    await ExitBackup.setMode(m);
    if (mounted) setState(() => _mode = m);
  }

  Future<void> _chooseFolder() async {
    final f = await ExitBackup.pickFolder(initial: _folder);
    if (f == null) return;
    await ExitBackup.setFolder(f);
    if (mounted) setState(() => _folder = f);
  }

  Future<void> _saveNow() async {
    final f = _folder;
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final path = await ExitBackup.saveTo(f);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.green, content: Text('حُفظت النسخة: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ExitBackup.supported) {
      return const Text('هذه الميزة على الحاسبة فقط.', style: TextStyle(color: Colors.black54));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
        'عند إغلاق البرنامج تُحفظ قاعدة البيانات كاملة مضغوطة (.tar.xz) في المجلد الذي تختاره. '
        'تُستعاد من «استعادة قاعدة البيانات من ملف».',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
      const SizedBox(height: 10),
      SegmentedButton<ExitBackupMode>(
        segments: const [
          ButtonSegment(value: ExitBackupMode.ask, icon: Icon(Icons.help_outline_rounded), label: Text('اسألني')),
          ButtonSegment(value: ExitBackupMode.always, icon: Icon(Icons.save_rounded), label: Text('احفظ دائماً')),
          ButtonSegment(value: ExitBackupMode.never, icon: Icon(Icons.block_rounded), label: Text('لا تحفظ')),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => _setMode(s.first),
      ),
      const SizedBox(height: 12),
      Material(
        color: _navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _chooseFolder,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.folder_rounded, color: Color(0xFFB45309)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _folder ?? 'مجلد الحفظ: لم يُختر بعد (يُسأل عنه عند أول حفظ)',
                  textDirection: _folder == null ? TextDirection.rtl : TextDirection.ltr,
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
      if (_folder != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _busy ? null : _saveNow,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_alt_rounded),
            label: const Text('احفظ نسخة الآن'),
          ),
        ),
      ],
    ]);
  }
}
