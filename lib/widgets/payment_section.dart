// widgets/payment_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'formatters.dart';

class PaymentSection extends StatelessWidget {
  final String paymentType;
  final Function(String?) onPaymentTypeChanged;
  final TextEditingController paidAmountController;
  final bool isViewOnly;
  final double discount;
  final Function(String) onDiscountChanged;
  final TextEditingController discountController;
  final bool showPaidAmountField;
  final void Function(String)? onPaidAmountChanged;

  const PaymentSection({
    Key? key,
    required this.paymentType,
    required this.onPaymentTypeChanged,
    required this.paidAmountController,
    required this.isViewOnly,
    required this.discount,
    required this.onDiscountChanged,
    required this.discountController,
    this.showPaidAmountField = false,
    this.onPaidAmountChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Radio<String>(
              value: 'نقد',
              groupValue: paymentType,
              onChanged: isViewOnly ? null : onPaymentTypeChanged,
            ),
            const Text('نقد'),
            const SizedBox(width: 24),
            Radio<String>(
              value: 'دين',
              groupValue: paymentType,
              onChanged: isViewOnly ? null : onPaymentTypeChanged,
            ),
            const Text('دين'),
          ],
        ),
        if (paymentType == 'دين' && showPaidAmountField)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextFormField(
              controller: paidAmountController,
              decoration:
                  const InputDecoration(labelText: 'المبلغ المسدد (اختياري)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                ThousandSeparatorDecimalInputFormatter(),
              ],
              enabled: !isViewOnly && paymentType == 'دين',
              onChanged: (v) => onPaidAmountChanged?.call(v.replaceAll(',', '')),
            ),
          ),
        const SizedBox(height: 24.0),
        TextFormField(
          decoration:
              const InputDecoration(labelText: 'الخصم (مبلغ وليس نسبة)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            ThousandSeparatorDecimalInputFormatter(),
          ],
          onChanged: isViewOnly
              ? null
              : (v) => onDiscountChanged(v.replaceAll(',', '')),
          controller: discountController,
          enabled: !isViewOnly,
        ),
      ],
    );
  }
}
