// lib/widgets/invoice_range_dialog.dart
//
// 🧾 «من أين نبدأ إرسال الفواتير إلى تيليجرام؟» — تُسأل مرة واحدة فقط على هذا الجهاز.
// الاختيار يُحفظ نقطةَ بداية ثابتة؛ بعدها كل رفع يرسل ما لم يُرسل بعد (سجل telegram_sent
// يمنع التكرار ويعيد تلقائياً ما فشل)، فلا يعود السؤال.
// لكل خيار عدد الفواتير التي سيرسلها فعلاً، ليعرف المستخدم ثقل «الكل» قبل اختياره.

import 'package:flutter/material.dart';

import 'app_dialog_shell.dart';

const _tg = Color(0xFF229ED9);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);

/// مفاتيح الخيارات التي تعيدها النافذة.
abstract final class InvoiceRange {
  static const day = '24h';
  static const week = 'week';
  static const all = 'all';
  static const fromNow = 'now';

  /// تاريخ البداية لكل خيار (الكل = تاريخ قديم جداً).
  static DateTime startOf(String key, DateTime now) => switch (key) {
        day => now.subtract(const Duration(days: 1)),
        week => now.subtract(const Duration(days: 7)),
        all => DateTime(2000),
        _ => now,
      };
}

class InvoiceRangeDialog extends StatefulWidget {
  const InvoiceRangeDialog({super.key, required this.countSince});

  /// عدد الفواتير غير المرسلة بعد تاريخ ما.
  final Future<int> Function(DateTime after) countSince;

  @override
  State<InvoiceRangeDialog> createState() => _InvoiceRangeDialogState();
}

class _InvoiceRangeDialogState extends State<InvoiceRangeDialog> {
  String _choice = InvoiceRange.day;
  final _now = DateTime.now();
  late final Map<String, Future<int>> _counts = {
    for (final k in const [InvoiceRange.day, InvoiceRange.week, InvoiceRange.all])
      k: widget.countSince(InvoiceRange.startOf(k, _now)).catchError((_) => -1),
  };

  static const _options = [
    (InvoiceRange.day, Icons.today_rounded, 'آخر 24 ساعة', 'فواتير اليوم وأمس القريب'),
    (InvoiceRange.week, Icons.date_range_rounded, 'آخر أسبوع', 'فواتير الأيام السبعة الماضية'),
    (InvoiceRange.all, Icons.all_inbox_rounded, 'كل الفواتير', 'كل ما لم يُرسل من قبل — قد يطول أول مرة'),
    (InvoiceRange.fromNow, Icons.fast_forward_rounded, 'من الآن فقط', 'لا يُرسل القديم؛ الجديدة فقط من الرفع القادم'),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AppDialogShell(
        icon: Icons.receipt_long_rounded,
        color: _tg,
        title: 'من أين نبدأ إرسال الفواتير؟',
        subtitle: 'سؤال لمرة واحدة فقط — بعدها تُرسل الفواتير الجديدة تلقائياً مع كل رفع',
        maxWidth: 520,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final o in _options) ...[
              _Option(
                icon: o.$2,
                title: o.$3,
                desc: o.$4,
                selected: _choice == o.$1,
                count: _counts[o.$1],
                onTap: () => setState(() => _choice = o.$1),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 16, color: _muted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'لا تُرسل فاتورة مرتين. وما يفشل إرساله يُعاد تلقائياً في الرفع التالي.',
                  style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
                ),
              ),
            ]),
          ]),
        ),
        actions: [
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _tg, minimumSize: const Size(140, 46)),
            onPressed: () => Navigator.pop(context, _choice),
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('اعتمد وتابع الرفع'),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;
  final Future<int>? count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? _tg.withValues(alpha: 0.07) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? _tg : _line, width: selected ? 1.6 : 1),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? _tg : _tg.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: selected ? Colors.white : _tg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _text)),
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(fontSize: 12, color: _muted, height: 1.4)),
                ]),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                FutureBuilder<int>(
                  future: count,
                  builder: (_, s) {
                    if (!s.hasData) {
                      return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final n = s.data!;
                    if (n < 0) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (selected ? _tg : _muted).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(n == 0 ? 'لا شيء' : '$n فاتورة',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? _tg : _muted)),
                    );
                  },
                ),
              ],
              const SizedBox(width: 8),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? _tg : const Color(0xFFCBD5E1), size: 22),
            ]),
          ),
        ),
      ),
    );
  }
}
