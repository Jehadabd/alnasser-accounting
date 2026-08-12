import 'package:flutter/material.dart';
import '../../widgets/formatters.dart';

class UnitHierarchyWidget extends StatelessWidget {
  final bool isWeighable;
  final String baseUnitName; // e.g. "piece", "kg"
  final TextEditingController baseCostController;
  final TextEditingController baseWeightController; // only if isWeighable
  final List<Map<String, dynamic>> hierarchyItems; // e.g. [{"unit": "carton", "qty": 10}]
  final Function(Map<String, dynamic>) onAddItem;
  final Function(int) onRemoveItem;
  final Function(int, String, String) onUpdateItem;

  const UnitHierarchyWidget({
    super.key,
    required this.isWeighable,
    required this.baseUnitName,
    required this.baseCostController,
    required this.baseWeightController,
    required this.hierarchyItems,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onUpdateItem,
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
              'هرمية الوحدات والأسعار',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
            ),
            const SizedBox(height: 16),
            
            // --- الوحدة الأساسية ---
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                   Row(
                    children: [
                      const Icon(Icons.circle, size: 12),
                      const SizedBox(width: 8),
                      Text(
                        'الوحدة الأساسية: ${isWeighable ? 'قطعة (وزنية)' : baseUnitName == 'piece' ? 'قطعة' : baseUnitName}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: baseCostController,
                          decoration: const InputDecoration(
                            labelText: 'تكلفة الوحدة الأساسية',
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                           inputFormatters: [ThousandSeparatorDecimalInputFormatter()],
                        ),
                      ),
                      if (isWeighable) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: baseWeightController,
                            decoration: const InputDecoration(
                              labelText: 'وزن القطعة (كغم)',
                              hintText: 'مثال: 1.2',
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
             // --- الوحدات الكبرى ---
             Text(
              'الوحدات الكبرى',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            
            if (hierarchyItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('لا توجد وحدات كبرى (يباع بالمفرد فقط)', style: TextStyle(color: Colors.grey)),
              ),
              
            ...hierarchyItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final prevUnit = idx == 0 ? (isWeighable ? 'قطعة' : 'قطعة') : hierarchyItems[idx - 1]['unit_name'];
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: item['unit_name'],
                        decoration: const InputDecoration(labelText: 'اسم الوحدة', isDense: true),
                        items: ['باكيت', 'كرتون', 'صندوق', 'كيس', 'ربطة', 'سيت']
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (val) => onUpdateItem(idx, val!, item['quantity'].toString()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: item['quantity'].toString(),
                         decoration: InputDecoration(
                            labelText: 'يحتوي على كم $prevUnit؟',
                            isDense: true,
                          ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) => onUpdateItem(idx, item['unit_name'] ?? '', val),
                      ),
                    ),
                     IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      color: Colors.red,
                      onPressed: () => onRemoveItem(idx),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => onAddItem({'unit_name': 'باكيت', 'quantity': 10}),
              icon: const Icon(Icons.add),
              label: const Text('إضافة مستوى وحدة (مثل كرتون)'),
            ),
            
            if (isWeighable && hierarchyItems.isNotEmpty)
               Padding(
                 padding: const EdgeInsets.only(top: 16.0),
                 child: Container(
                   padding: const EdgeInsets.all(12),
                   color: Colors.blue.withOpacity(0.05),
                   child: Row(
                     children: [
                       const Icon(Icons.info_outline, color: Colors.blue),
                       const SizedBox(width: 8),
                       const Expanded(child: Text('سيقوم النظام بحساب الوزن الإجمالي لكل وحدة تلقائياً بناءً على وزن القطعة الأساسية.')),
                     ],
                   ),
                 ),
               )
          ],
        ),
      ),
    );
  }
}
