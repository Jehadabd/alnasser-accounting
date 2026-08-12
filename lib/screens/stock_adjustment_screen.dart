// lib/screens/stock_adjustment_screen.dart
// شاشة تعديل المخزون - اختيار منتج ثم تعديل الكمية

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../widgets/stock_adjustment_dialog.dart';

class StockAdjustmentScreen extends StatefulWidget {
  const StockAdjustmentScreen({super.key});

  @override
  State<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends State<StockAdjustmentScreen> {
  final _db = DatabaseService();
  final _searchController = TextEditingController();
  
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final products = await _db.getAllProducts();
      setState(() {
        _allProducts = products;
        _filteredProducts = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل المنتجات: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _filterProducts(String query) {
    if (query.isEmpty) {
      setState(() => _filteredProducts = _allProducts);
      return;
    }
    
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        return p.name.toLowerCase().contains(lowerQuery) ||
               (p.barcode?.toLowerCase().contains(lowerQuery) ?? false) ||
               p.id.toString().contains(query);
      }).toList();
    });
  }

  Future<void> _showAdjustmentDialog(Product product) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StockAdjustmentDialog(product: product),
    );
    
    if (result == true) {
      // Reload products to show updated stock
      await _loadProducts();
    }
  }

  String _formatNum(double val) => NumberFormat('#,##0.##', 'en_US').format(val);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('تعديل المخزون'),
        backgroundColor: const Color(0xFF9C27B0),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProducts,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF9C27B0),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _filterProducts,
              decoration: InputDecoration(
                hintText: 'ابحث عن منتج بالاسم أو الباركود أو الرقم...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _filterProducts('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          
          // Products Count
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'المنتجات (${_filteredProducts.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9C27B0),
                  ),
                ),
                const Spacer(),
                const Text(
                  'اضغط على منتج لتعديل مخزونه',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          
          // Products List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'لا توجد منتجات'
                                  : 'لا توجد نتائج للبحث',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return _buildProductCard(product);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final hasHierarchy = product.getUnitHierarchyList().isNotEmpty;
    final baseUnit = product.unit == 'piece' ? 'قطعة' : 
                    (product.unit == 'meter' ? 'متر' : product.unit);
    
    // Calculate stock status
    Color stockColor;
    String stockStatus;
    if (product.stockQuantity <= 0) {
      stockColor = Colors.red;
      stockStatus = 'نفاد';
    } else if (product.alertQuantity != null && product.stockQuantity <= product.alertQuantity!) {
      stockColor = Colors.orange;
      stockStatus = 'منخفض';
    } else {
      stockColor = Colors.green;
      stockStatus = 'متوفر';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showAdjustmentDialog(product),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF9C27B0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.inventory_2, color: Color(0xFF9C27B0)),
              ),
              const SizedBox(width: 16),
              
              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: stockColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            stockStatus,
                            style: TextStyle(
                              color: stockColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '#${product.id}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        if (product.barcode != null && product.barcode!.isNotEmpty) ...[
                          const Text(' • ', style: TextStyle(color: Colors.grey)),
                          Text(
                            product.barcode!,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                        if (hasHierarchy) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.account_tree, size: 12, color: Colors.blue),
                                const SizedBox(width: 4),
                                Text(
                                  '${product.getUnitHierarchyList().length + 1} وحدات',
                                  style: const TextStyle(color: Colors.blue, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              
              // Stock Quantity
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatNum(product.stockQuantity),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: stockColor,
                    ),
                  ),
                  Text(
                    baseUnit,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
              
              // Arrow
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
