import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import 'dart:convert';

class MaterialInventoryScreen extends StatefulWidget {
  const MaterialInventoryScreen({super.key});

  @override
  State<MaterialInventoryScreen> createState() => _MaterialInventoryScreenState();
}

class _MaterialInventoryScreenState extends State<MaterialInventoryScreen> {
  final DatabaseService _db = DatabaseService();
  bool _isLoading = true;
  List<Product> _products = [];
  double _totalInventoryValue = 0.0;
  
  // للبحث
  String _searchQuery = '';
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() => _isLoading = true);
    try {
      final allProducts = await _db.getAllProducts();
      // تصفية المنتجات التي لها كمية في المخزن
      final productsWithStock = allProducts.where((p) => p.stockQuantity != 0).toList();
      
      double totalValue = 0;
      for (var p in productsWithStock) {
        // حساب القيمة: الكمية * التكلفة الأساسية
        // ملاحظة: stockQuantity هي بالوحدة الأساسية (قطعة)
        // costPrice هو سعر تكلفة القطعة الواحدة
        double cost = p.costPrice ?? 0.0;
        // نستخدم سعر التكلفة الفعلي فقط. إذا كان صفراً، فالقيمة صفر.
        totalValue += p.stockQuantity * cost;
      }

      setState(() {
        _products = productsWithStock;
        _filteredProducts = productsWithStock;
        _totalInventoryValue = totalValue;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل المخزون: $e')),
        );
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products.where((p) => 
          p.name.toLowerCase().contains(query.toLowerCase())
        ).toList();
      }
    });
  }

  /// تحويل الكمية الإجمالية إلى صيغة هرمية (كرتون، باكيت، قطعة)
  String _formatQuantityHierarchy(double totalQuantity, Product product) {
    if (product.unitHierarchy == null || product.unitHierarchy!.isEmpty) {
      return '';
    }

    try {
      // 1. ترتيب الوحدات من الأكبر للأصغر
      final List<dynamic> hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"')) as List<dynamic>;
      
      List<Map<String, dynamic>> sortedUnits = [];
      double accumulatedMultiplier = 1.0;
      
      sortedUnits.add({
        'name': 'قطعة', 
        'multiplier': 1.0
      });

      for (var unit in hierarchy) {
        String name = unit['unit_name'] ?? unit['name'] ?? '';
        double qty = 1.0;
        if (unit['quantity'] is num) {
          qty = (unit['quantity'] as num).toDouble();
        } else {
           qty = double.tryParse(unit['quantity'].toString()) ?? 1.0;
        }
        
        accumulatedMultiplier *= qty;
        
        if (name.isNotEmpty && qty > 1) {
             sortedUnits.add({
              'name': name,
              'multiplier': accumulatedMultiplier
            });
        }
      }
      
      sortedUnits.sort((a, b) => (b['multiplier'] as double).compareTo(a['multiplier'] as double));
      
      List<String> parts = [];
      double remaining = totalQuantity;
      
      for (var unit in sortedUnits) {
        double multiplier = unit['multiplier'];
        if (multiplier <= 1 && unit['name'] != 'قطعة' && unit['name'] != product.unit) continue;
        
        if (remaining >= multiplier && multiplier > 0) {
           if (multiplier == 1) {
              if (remaining > 0) {
                 String qtyStr = NumberFormat('#,##0.##', 'en_US').format(remaining);
                 parts.add('$qtyStr ${unit['name']}');
                 remaining = 0;
              }
           } else {
             int count = (remaining / multiplier).floor();
             if (count > 0) {
               parts.add('$count ${unit['name']}');
               remaining -= (count * multiplier);
             }
           }
        }
      }
      
      if (remaining > 0) {
         String qtyStr = NumberFormat('#,##0.##', 'en_US').format(remaining);
         parts.add('$qtyStr قطعة');
      }

      if (parts.isEmpty) return '0';
      return parts.join(' و ');

    } catch (e) {
      print('Hierarchy Format Error: $e');
      return '';
    }
  }
  
  String _formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('جرد المواد'),
        backgroundColor: const Color(0xFF3F51B5),
        elevation: 0,
      ),
      body: Column(
        children: [
          // شريط البحث
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF3F51B5),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'بحث عن مادة...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF3F51B5)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              ),
              onChanged: _filterProducts,
            ),
          ),
          
          // ملخص القيمة
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF3F51B5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                const Text('إجمالي قيمة المواد في المخزن', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  '${_formatCurrency(_totalInventoryValue)} د.ع',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'عدد المواد: ${_products.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          
          // القائمة
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _filteredProducts.isEmpty
                    ? const Center(child: Text('لا توجد مواد', style: TextStyle(fontSize: 18, color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          // حساب التكلفة الإجمالية لهذا المنتج
                          double cost = product.costPrice ?? 0.0;
                          final totalCost = product.stockQuantity * cost;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          product.name,
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F5E9),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          '${_formatCurrency(totalCost)} د.ع',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.layers, size: 20, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                             // السطر الأول: الإجمالي بالوحدة الأساسية
                                             Text(
                                              '${_formatCurrency(product.stockQuantity)} ${product.unit}',
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            ),
                                            // السطر الثاني: التفصيل (يساوي ...)
                                            if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4.0),
                                                child: Text(
                                                  '= ${_formatQuantityHierarchy(product.stockQuantity, product)}',
                                                  style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.price_check, size: 20, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        'تكلفة الوحدة: ${cost > 0 ? _formatCurrency(cost) : "غير محدد"}',
                                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
