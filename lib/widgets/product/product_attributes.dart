import 'package:flutter/material.dart';

class ProductAttributesWidget extends StatelessWidget {
  final bool isWeighable;
  final bool hasExpiry;
  final ValueChanged<bool> onWeighableChanged;
  final ValueChanged<bool> onExpiryChanged;

  const ProductAttributesWidget({
    super.key,
    required this.isWeighable,
    required this.hasExpiry,
    required this.onWeighableChanged,
    required this.onExpiryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خصائص المنتج',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('هل يباع بالوزن؟'),
              subtitle: const Text('مثل: الدجاج، الرز، اللحوم'),
              value: isWeighable,
              onChanged: onWeighableChanged,
              secondary: const Icon(Icons.monitor_weight_outlined),
              activeColor: Theme.of(context).primaryColor,
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('تاريخ انتهاء الصلاحية؟'),
              subtitle: const Text('مثل: الأدوية، المواد الغذائية'),
              value: hasExpiry,
              onChanged: onExpiryChanged,
              secondary: const Icon(Icons.calendar_today_outlined),
              activeColor: Theme.of(context).primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
