// lib/widgets/line_discount_dialog.dart
//
// 🏷️ خصم سطر الفاتورة: نسبة % أو مبلغ من سعر الوحدة، أو هدية مجانية، أو بلا خصم.
// يعيد السعر قبل الخصم والسعر الصافي؛ الصافي هو ما تُحسب عليه الفاتورة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'formatters.dart';

class LineDiscountResult {
  const LineDiscountResult({required this.listPrice, required this.net, this.type, this.value});

  /// سعر الوحدة قبل الخصم
  final double listPrice;

  /// سعر الوحدة الصافي (بعد الخصم؛ صفر للهدية)
  final double net;

  /// 'percent' | 'amount' | 'gift' | null (بلا خصم)
  final String? type;
  final double? value;
}

/// يحسب الصافي من السعر والخصم (مقرّب لفلسين)
double lineNetPrice(double listPrice, String? type, double value) {
  if (type == 'gift') return 0;
  if (type == null || value <= 0) return listPrice;
  final off = type == 'percent' ? listPrice * value / 100 : value;
  final net = listPrice - off;
  return net <= 0 ? 0 : (net * 100).roundToDouble() / 100;
}

Future<LineDiscountResult?> showLineDiscountDialog(
  BuildContext context, {
  required double listPrice,
  String? type,
  double? value,
}) {
  final fmt = NumberFormat('#,##0.##', 'en_US');
  final priceCtrl = TextEditingController(text: listPrice > 0 ? fmt.format(listPrice) : '');
  final valueCtrl = TextEditingController(text: (value != null && value > 0) ? fmt.format(value) : '');
  var mode = type ?? 'percent';

  double parse(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '')) ?? 0;

  return showDialog<LineDiscountResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final price = parse(priceCtrl);
      final v = parse(valueCtrl);
      final effectiveType = mode == 'none' ? null : mode;
      final net = lineNetPrice(price, effectiveType, v);
      final valid = price > 0 &&
          (mode == 'gift' || mode == 'none' || (v > 0 && (mode == 'percent' ? v < 100 : v < price)));

      LineDiscountResult result() => LineDiscountResult(
            listPrice: price,
            net: net,
            type: mode == 'none' ? null : mode,
            value: (mode == 'percent' || mode == 'amount') ? v : null,
          );

      return AlertDialog(
        title: const Text('خصم هذا الصنف'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'percent', label: Text('نسبة %')),
                ButtonSegment(value: 'amount', label: Text('مبلغ')),
                ButtonSegment(value: 'gift', icon: Icon(Icons.card_giftcard, size: 16), label: Text('هدية')),
                ButtonSegment(value: 'none', label: Text('بلا خصم')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => setD(() => mode = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
              decoration: const InputDecoration(labelText: 'سعر الوحدة قبل الخصم', border: OutlineInputBorder()),
              onChanged: (_) => setD(() {}),
            ),
            if (mode == 'percent' || mode == 'amount') ...[
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                decoration: InputDecoration(
                  labelText: mode == 'percent' ? 'نسبة الخصم %' : 'مبلغ الخصم من سعر الوحدة',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setD(() {}),
                onSubmitted: (_) {
                  if (valid) Navigator.pop(ctx, result());
                },
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: valid ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                !valid
                    ? (price <= 0 ? 'اكتب سعر الوحدة' : 'اكتب خصماً أقل من السعر')
                    : mode == 'gift'
                        ? '🎁 هدية مجانية: تخرج من المخزون بسعر صفر، ويظهر سعرها الأصلي في الفاتورة'
                        : mode == 'none'
                            ? 'بلا خصم: السعر ${fmt.format(price)}'
                            : 'السعر ${fmt.format(price)}  ←  الصافي ${fmt.format(net)}  (خصم ${fmt.format(price - net)} للوحدة)',
                style: TextStyle(color: valid ? Colors.green.shade800 : Colors.black54, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: valid ? () => Navigator.pop(ctx, result()) : null, child: const Text('تطبيق')),
        ],
      );
    }),
  );
}
