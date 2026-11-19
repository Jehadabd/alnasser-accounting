// lib/screens/diagnostics/problem_report.dart
//
// 🚩 «أبلغ عن مشكلة»: لما لا يرافقه خطأ يمكن التقاطه — زر لم يعمل، رقم غير صحيح، شاشة فارغة.
// Ctrl+Shift+E في أي شاشة (أو زر «أبلغ عن مشكلة» في تشخيص الأخطاء): تُلتقط صورة الشاشة
// الحالية أولاً، ثم يكتب المستخدم ما حدث، فيُسجَّل البلاغ مع الصورة واسم الشاشة وآخر الشاشات.
// الصورة تبقى على هذا الجهاز فقط (alnaser_logs\reports) — آخر 30 صورة.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/diagnostics/error_journal.dart';
import '../../widgets/settings_kit.dart';

/// يحيط بكل الشاشات (main.dart) لالتقاط صورة الشاشة.
final GlobalKey problemReportBoundary = GlobalKey(debugLabel: 'problem_report_boundary');

Future<Uint8List?> _screenshot() async {
  try {
    final ro = problemReportBoundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    final img = await ro.toImage(pixelRatio: 1.0);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

bool _open = false;

/// يفتح نافذة البلاغ (بعد التقاط صورة الشاشة كما هي الآن).
Future<void> showProblemReport(BuildContext context) async {
  if (_open) return;
  _open = true;
  try {
    final screen = ErrorJournal.currentScreen;
    final png = await _screenshot();
    if (!context.mounted) return;
    final text = TextEditingController();
    var attach = png != null;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          icon: const Icon(Icons.flag_rounded, color: kSetOrange, size: 34),
          title: const Text('أبلغ عن مشكلة'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('اكتب ما حدث بالضبط — يُحفظ في «تشخيص الأخطاء» مع اسم الشاشة وصورتها.',
                    style: TextStyle(fontSize: 13, color: kSetMuted, height: 1.5)),
                const SizedBox(height: 10),
                TextField(
                  controller: text,
                  autofocus: true,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'مثلاً: ضغطت «حفظ» في الفاتورة ولم يحدث شيء',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (screen != null) ...[
                  const SizedBox(height: 8),
                  Text('الشاشة: $screen', style: const TextStyle(fontSize: 12, color: kSetMuted)),
                ],
                if (png != null) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: attach,
                    onChanged: (v) => setS(() => attach = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('إرفاق صورة الشاشة', style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text('تبقى على هذا الجهاز فقط', style: TextStyle(fontSize: 11.5)),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: attach ? 1 : 0.3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Image.memory(png, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kSetOrange),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.flag_rounded),
              label: const Text('سجّل البلاغ'),
            ),
          ],
        ),
      ),
    );
    final desc = text.text;
    text.dispose();
    if (saved != true) return;
    final path = (attach && png != null) ? await ErrorJournal.saveAttachment(png) : null;
    ErrorJournal.recordReport(desc, attachment: path, screen: screen);
    if (context.mounted) setToast(context, 'سُجّل البلاغ — تجده في «تشخيص الأخطاء»');
  } finally {
    _open = false;
  }
}
