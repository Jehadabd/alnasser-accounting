// widgets/invoice_summary_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InvoiceSummaryCard extends StatelessWidget {
  final double totalBeforeDiscount;
  final double total;
  final double paidAmount;
  final double remainingAmount;
  final String paymentType;
  final bool isDebt;
  final double? debtAmount;

  const InvoiceSummaryCard({
    Key? key,
    required this.totalBeforeDiscount,
    required this.total,
    required this.paidAmount,
    required this.remainingAmount,
    required this.paymentType,
    this.isDebt = false,
    this.debtAmount,
  }) : super(key: key);

  String formatNumber(num value) => NumberFormat('#,##0.##', 'en_US').format(value);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[100],
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'المبلغ الإجمالي قبل الخصم:  ${formatNumber(totalBeforeDiscount)} دينار',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'المبلغ الإجمالي:  ${formatNumber(total)} دينار',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'المبلغ المسدد:    ${formatNumber(paidAmount)} دينار',
                style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 4),
            Text(
                'المتبقي:         ${formatNumber(remainingAmount)} دينار',
                style: const TextStyle(color: Colors.red)),
            if (isDebt && debtAmount != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                    'أصبح الدين: ${formatNumber(debtAmount!)} دينار',
                    style: const TextStyle(color: Colors.black87)),
              ),
          ],
        ),
      ),
    );
  }
}
