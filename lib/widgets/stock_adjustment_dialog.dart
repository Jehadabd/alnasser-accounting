// lib/widgets/stock_adjustment_dialog.dart
// نافذة تعديل المخزون مع النظام الهرمي للوحدات

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../widgets/formatters.dart';

/// نافذة تعديل المخزون للمنتج
/// تعرض الوحدات الهرمية وتسمح بإضافة أو طرح الكمية
class StockAdjustmentDialog extends StatefulWidget {
  final Product product;

  const StockAdjustmentDialog({super.key, required this.product});

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  
  String _selectedUnit = '';
  String _adjustmentType = 'add'; // 'add' or 'subtract'
  double _calculatedBaseQty = 0;
  List<UnitLevel> _unitLevels = [];
  
  final _db = DatabaseService();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _buildUnitLevels();
  }

  /// بناء قائمة الوحدات مع معامل التحويل
  void _buildUnitLevels() {
    _unitLevels = [];
    
    // الوحدة الأساسية
    String baseUnitName = widget.product.unit == 'piece' ? 'قطعة' : 
                         (widget.product.unit == 'meter' ? 'متر' : widget.product.unit);
    _unitLevels.add(UnitLevel(name: baseUnitName, conversionFactor: 1.0));
    
    // الوحدات الهرمية
    final hierarchy = widget.product.getUnitHierarchyList();
    double cumulativeFactor = 1.0;
    
    for (var item in hierarchy) {
      final unitName = item['unit_name']?.toString() ?? '';
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      
      if (unitName.isNotEmpty && quantity > 0) {
        cumulativeFactor *= quantity;
        _unitLevels.add(UnitLevel(name: unitName, conversionFactor: cumulativeFactor));
      }
    }
    
    // اختر الوحدة الأساسية افتراضياً
    if (_unitLevels.isNotEmpty) {
      _selectedUnit = _unitLevels.first.name;
    }
  }

  /// حساب الكمية بالوحدة الأساسية
  void _calculateBaseQuantity() {
    final inputQty = double.tryParse(_quantityController.text.replaceAll(',', '')) ?? 0;
    final selectedLevel = _unitLevels.firstWhere(
      (u) => u.name == _selectedUnit,
      orElse: () => UnitLevel(name: '', conversionFactor: 1),
    );
    
    setState(() {
      _calculatedBaseQty = inputQty * selectedLevel.conversionFactor;
    });
  }

  /// حفظ التعديل
  Future<void> _saveAdjustment() async {
    if (_calculatedBaseQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال كمية صحيحة'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      double adjustmentValue = _adjustmentType == 'add' ? _calculatedBaseQty : -_calculatedBaseQty;
      
      // إذا كان الطرح سيؤدي لمخزون سالب، نمنعه
      final newStock = widget.product.stockQuantity + adjustmentValue;
      if (newStock < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يمكن طرح أكثر من الكمية المتوفرة'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSaving = false);
        return;
      }

      // تحديث المخزون في قاعدة البيانات
      await _db.adjustProductStock(
        productId: widget.product.id!,
        quantityChange: adjustmentValue,
        note: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_adjustmentType == 'add' 
              ? 'تم إضافة ${_formatNum(_calculatedBaseQty)} ${_unitLevels.first.name} للمخزون'
              : 'تم طرح ${_formatNum(_calculatedBaseQty)} ${_unitLevels.first.name} من المخزون'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  String _formatNum(double val) => NumberFormat('#,##0.##', 'en_US').format(val);

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseUnit = _unitLevels.isNotEmpty ? _unitLevels.first.name : 'قطعة';
    final newStock = widget.product.stockQuantity + 
        (_adjustmentType == 'add' ? _calculatedBaseQty : -_calculatedBaseQty);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2, color: Color(0xFF4CAF50)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('تعديل المخزون', style: TextStyle(fontSize: 18)),
                Text(
                  widget.product.name,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الرصيد الحالي
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory, color: Color(0xFF2196F3)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('الرصيد الحالي', style: TextStyle(color: Color(0xFF2196F3), fontSize: 12)),
                        Text(
                          '${_formatNum(widget.product.stockQuantity)} $baseUnit',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2196F3)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // نوع التعديل
              Row(
                children: [
                  Expanded(
                    child: _buildTypeButton(
                      'إضافة',
                      Icons.add_circle,
                      'add',
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTypeButton(
                      'طرح',
                      Icons.remove_circle,
                      'subtract',
                      Colors.red,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // اختيار الوحدة
              const Text('اختر الوحدة', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _unitLevels.map((level) {
                  final isSelected = _selectedUnit == level.name;
                  return ActionChip(
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(level.name),
                        if (level.conversionFactor > 1)
                          Text(
                            '= ${_formatNum(level.conversionFactor)} $baseUnit',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                    backgroundColor: isSelected ? const Color(0xFF5D5FEF) : Colors.grey[200],
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onPressed: () {
                      setState(() => _selectedUnit = level.name);
                      _calculateBaseQuantity();
                    },
                  );
                }).toList(),
              ),
              
              const SizedBox(height: 20),
              
              // إدخال الكمية
              TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                onChanged: (_) => _calculateBaseQuantity(),
                decoration: InputDecoration(
                  labelText: 'الكمية',
                  hintText: 'أدخل الكمية...',
                  prefixIcon: const Icon(Icons.numbers),
                  suffixText: _selectedUnit,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
              
              // عرض التحويل إذا كانت الوحدة ليست الأساسية
              if (_calculatedBaseQty > 0 && _selectedUnit != baseUnit) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calculate, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '= ${_formatNum(_calculatedBaseQty)} $baseUnit',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              
              // ملاحظة (اختياري)
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  hintText: 'سبب التعديل...',
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // الرصيد الجديد المتوقع
              if (_calculatedBaseQty > 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: newStock >= 0 
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: newStock >= 0 
                          ? const Color(0xFF4CAF50).withOpacity(0.3)
                          : Colors.red.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        newStock >= 0 ? Icons.check_circle : Icons.error,
                        color: newStock >= 0 ? const Color(0xFF4CAF50) : Colors.red,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الرصيد الجديد',
                            style: TextStyle(
                              color: newStock >= 0 ? const Color(0xFF4CAF50) : Colors.red,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '${_formatNum(newStock)} $baseUnit',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: newStock >= 0 ? const Color(0xFF4CAF50) : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving || _calculatedBaseQty <= 0 ? null : _saveAdjustment,
          icon: _isSaving 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: Text(_adjustmentType == 'add' ? 'إضافة للمخزون' : 'طرح من المخزون'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _adjustmentType == 'add' ? Colors.green : Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildTypeButton(String label, IconData icon, String type, Color color) {
    final isSelected = _adjustmentType == type;
    return InkWell(
      onTap: () => setState(() => _adjustmentType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// فئة مساعدة لتمثيل مستوى الوحدة
class UnitLevel {
  final String name;
  final double conversionFactor;

  UnitLevel({required this.name, required this.conversionFactor});
}
