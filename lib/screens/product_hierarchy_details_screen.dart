// screens/product_hierarchy_details_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/product_cost_service.dart';

class ProductHierarchyDetailsScreen extends StatelessWidget {
  final Product product;

  const ProductHierarchyDetailsScreen({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    final unitHierarchy = product.getUnitHierarchyList();
    final unitCosts = product.getUnitCostsMap();
    final allUnitLevels = product.getAllUnitLevels();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text('تفاصيل ${product.name}', style: const TextStyle(fontSize: 24)),
        centerTitle: true,
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معلومات المنتج الأساسية
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.inventory,
                            color: Colors.blue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'الوحدة الأساسية: ${product.unit == 'piece' ? 'قطعة' : 'متر'}',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // النظام الهرمي للوحدات
            if (unitHierarchy.isNotEmpty) ...[
              Text(
                'النظام الهرمي للوحدات',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // عرض التسلسل الهرمي
              ...unitHierarchy.asMap().entries.map((entry) {
                int idx = entry.key;
                var item = entry.value;
                String prevUnit = idx == 0 ? 'قطعة' : unitHierarchy[idx - 1]['unit_name'];
                String currentUnit = item['unit_name'];
                int quantity = (item['quantity'] as num).toInt(); // Fix: Convert num to int safely
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_upward,
                            color: Colors.green[600],
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentUnit,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'يحتوي على $quantity $prevUnit',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$quantity',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
            
            const SizedBox(height: 20),
            
            // تكلفة الوحدات
            Text(
              'تكلفة الوحدات',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF4CAF50),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // عرض تكلفة كل وحدة
            ...allUnitLevels.map((unitName) {
              final cost = unitCosts[unitName];
              final displayName = unitName == 'قطعة' ? 'قطعة' : unitName;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.attach_money,
                          color: Colors.orange[600],
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              cost != null ? 'التكلفة محسوبة' : 'التكلفة غير محددة',
                              style: TextStyle(
                                fontSize: 14,
                                color: cost != null ? Colors.green[600] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: cost != null ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cost != null ? '${cost.toStringAsFixed(2)} د.ع' : 'غير محدد',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: cost != null ? Colors.green[600] : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
            
            const SizedBox(height: 20),
            
            // ملخص النظام
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملخص النظام',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF4CAF50),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildSummaryRow('عدد مستويات الوحدات', '${allUnitLevels.length}'),
                    _buildSummaryRow('الوحدة الأساسية', product.unit == 'piece' ? 'قطعة' : 'متر'),
                    _buildSummaryRow('أعلى وحدة', unitHierarchy.isNotEmpty ? unitHierarchy.last['unit_name'] : 'لا يوجد'),
                    _buildSummaryRow('حالة التكلفة', _getCostStatusText(unitCosts)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  String _getCostStatusText(Map<String, double> unitCosts) {
    if (unitCosts.isEmpty) return 'غير محدد';
    if (unitCosts.containsKey('قطعة') && unitCosts['قطعة'] != null) {
      return 'مكتمل';
    }
    return 'جزئي';
  }
}
