// lib/services/invoice_safety/debt_to_cash_dialog.dart
//
// 🔁 نافذة تحويل فاتورة دين محفوظة إلى «نقد» (DebtToCashSettlement):
// تعرض دين الفاتورة ورصيد العميل وما سُدّد منها سابقاً بوصولات (مقترحاً، قابلاً للتعديل)،
// وما سيُقبض الآن، وكيف ستُحفظ. تحلّ محل التأكيد القديم (DebtToCashConfirm.ask) ومعها
// تحذيره من وصل قبض بالمبلغ نفسه.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../models/invoice.dart';
import 'debt_to_cash_confirm.dart';
import 'debt_to_cash_settlement.dart';

class DebtToCashDialog {
  DebtToCashDialog._();

  static final _nf = NumberFormat('#,##0.##', 'en_US');

  /// يعيد «ما سُدّد منها سابقاً» الذي وافق عليه المستخدم، أو null إن ألغى.
  static Future<double?> ask(BuildContext context, Invoice invoice, DebtToCashPlan plan) async {
    String? dupDate;
    try {
      dupDate = (await DebtToCashConfirm.check(invoice, 'نقد'))?.samePaymentDate;
    } catch (_) {}
    if (!context.mounted) return null;
    final ctrl = TextEditingController(text: _nf.format(plan.suggestedPrepaid));
    try {
      return await showDialog<double>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
          final typed = double.tryParse(ctrl.text.replaceAll(',', '').trim());
          final valid = typed != null && typed >= 0 && typed <= plan.recordedDebt + 0.001;
          final s = valid ? plan.clampPrepaid(typed) : 0.0;
          final now = plan.collectNow(s);
          return AlertDialog(
            title: const Text('تحويل الفاتورة إلى نقد'),
            content: SizedBox(
              width: 440,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('دين هذه الفاتورة في حساب العميل: ${_nf.format(plan.recordedDebt)}'),
                Text('رصيد العميل كله الآن: ${_nf.format(plan.customerBalance)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'سُدّد منها سابقاً بوصولات قبض',
                    helperText: 'المقترح ${_nf.format(plan.suggestedPrepaid)} — بين 0 و ${_nf.format(plan.recordedDebt)}',
                    errorText: valid ? null : 'اكتب مبلغاً بين 0 و ${_nf.format(plan.recordedDebt)}',
                  ),
                  onChanged: (_) => setD(() {}),
                ),
                const SizedBox(height: 12),
                Text(
                  now >= 0 ? 'يُقبض الآن نقداً: ${_nf.format(now)}' : 'يُردّ للعميل الآن: ${_nf.format(-now)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(s >= 0.5
                    ? 'تُحفظ «آجل — مسددة بالكامل»: ${_nf.format(s)} سُدّدت بوصولات، والباقي يُقبض الآن.'
                    : 'تُحفظ نقداً: الإجمالي كله يُقبض الآن.'),
                if (dupDate != null && s < 0.5) ...[
                  const SizedBox(height: 10),
                  Text(
                    '⚠️ يوجد وصل قبض بمبلغ دين هذه الفاتورة نفسه بتاريخ $dupDate. إن كان ثمنها فاكتب مبلغه أعلاه، '
                    'وإلا سيُطرح مرتين.',
                    style: const TextStyle(color: Colors.red, height: 1.5),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, s) : null,
                child: const Text('حفظ'),
              ),
            ],
          );
        }),
      );
    } finally {
      ctrl.dispose();
    }
  }
}
