// screens/product_reports_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/product.dart';
import '../models/invoice_item.dart';
import 'product_details_screen.dart';
import 'product_hierarchy_details_screen.dart';
import 'package:intl/intl.dart';

class ProductReportsScreen extends StatefulWidget {
  const ProductReportsScreen({super.key});

  @override
  State<ProductReportsScreen> createState() => _ProductReportsScreenState();
}

class _ProductReportsScreenState extends State<ProductReportsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<ProductReportData> _products = [];
  List<ProductReportData> _filteredProducts = [];
  bool _isLoading = true;
  bool _onlyThisDevice = false;
  final TextEditingController _searchController = TextEditingController();

  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  final ScrollController _scrollController = ScrollController();
  int _offset = 0;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadProductReports();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadProductReports(isLoadMore: true);
      }
    }
  }

  void _onSearchChanged() {
    _loadProductReports();
  }

  void _filterProducts() {
    // تم إلغاء فلترة الذاكرة العشوائية واستبدالها بالبحث المباشر في قاعدة البيانات
  }

  Future<void> _loadProductReports({bool isLoadMore = false}) async {
    if (isLoadMore) {
      setState(() { _isLoadingMore = true; });
    } else {
      setState(() { 
        _isLoading = true; 
        _offset = 0;
        _hasMore = true;
      });
    }

    try {
      _databaseService.reportsService.filterOnlyThisDevice = _onlyThisDevice;
      final products = await _databaseService.getPaginatedProductsForReports(
        limit: _limit,
        offset: _offset,
        searchQuery: _searchController.text.trim(),
        onlyThisDevice: _onlyThisDevice,
      );
      
      if (products.length < _limit) {
        _hasMore = false;
      }
      
      final List<ProductReportData> newReports = [];

      for (final product in products) {
        final salesData = await _databaseService.getProductSalesData(product.id!);

        newReports.add(ProductReportData(
          product: product,
          totalQuantitySold: salesData['totalQuantity'] ?? 0.0,
          totalProfit: salesData['totalProfit'] ?? 0.0,
          totalSales: salesData['totalSales'] ?? 0.0,
          averageSellingPrice: salesData['averageSellingPrice'] ?? 0.0,
          totalCost: salesData['totalCost'] ?? 0.0,
          profitMargin: salesData['profitMargin'] ?? 0.0,
        ));
      }

      setState(() {
        if (isLoadMore) {
          _products.addAll(newReports);
        } else {
          _products = newReports;
        }
        _filteredProducts = _products; // لأن البحث يتم الآن في الداتابيز
        _offset += _limit;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('تقرير البضاعة', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF673AB7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Row(
            children: [
              Text(_onlyThisDevice ? 'فقط هذا الجهاز' : 'تقارير شاملة', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
              Switch(
                value: _onlyThisDevice,
                onChanged: (val) {
                  setState(() {
                    _onlyThisDevice = val;
                    _loadProductReports();
                  });
                },
                activeColor: Colors.white,
                inactiveTrackColor: Colors.white30,
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProductReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
              ),
            )
          : Column(
              children: [
                // حقل البحث
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'البحث في المنتجات...',
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: Color(0xFF4CAF50)),
                      suffixIcon: Icon(Icons.filter_list, color: Color(0xFF4CAF50)),
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                // قائمة المنتجات
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2,
                                size: 80,
                                color: Color(0xFFCCCCCC),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد منتجات',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadProductReports,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _filteredProducts.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filteredProducts.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(
                                    child: CircularProgressIndicator(color: Color(0xFF673AB7)),
                                  ),
                                );
                              }
                              final productData = _filteredProducts[index];
                              return _buildProductCard(productData);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildProductCard(ProductReportData product) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailsScreen(
                product: product.product,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.withOpacity(0.1),
                Colors.blue.withOpacity(0.05),
              ],
            ),
          ),
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
                          product.product.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الكمية المباعة: ${_fmt(product.totalQuantitySold)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.trending_up,
                      title: 'الربح',
                      value:
                          '${product.totalProfit >= 0 ? _fmt(product.totalProfit) : _fmt(-product.totalProfit)} د.ع',
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.shopping_cart,
                      title: 'المبيعات',
                      value: '${_fmt(product.totalSales)} د.ع',
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.percent,
                      title: 'نسبة الربح',
                      value: '${product.profitMargin.toStringAsFixed(1)}%',
                      color: product.profitMargin >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.info_outline,
                      title: 'الوحدة',
                      value: product.product.unit == 'piece' ? 'قطعة' : 'متر',
                      color: const Color(0xFF9C27B0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.price_change,
                      title: 'التكلفة الإجمالية',
                      value: '${_fmt(product.totalCost)} د.ع',
                      color: const Color(0xFFF44336),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.attach_money,
                      title: 'متوسط سعر البيع',
                      value: '${_fmt(product.averageSellingPrice)} د.ع',
                      color: const Color(0xFFFF9800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // زر عرض تفاصيل النظام الهرمي
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProductHierarchyDetailsScreen(
                          product: product.product,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_tree),
                  label: const Text('عرض النظام الهرمي'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class ProductReportData {
  final Product product;
  final double totalQuantitySold;
  final double totalProfit;
  final double totalSales;
  final double averageSellingPrice;
  final double totalCost;
  final double profitMargin;

  ProductReportData({
    required this.product,
    required this.totalQuantitySold,
    required this.totalProfit,
    required this.totalSales,
    required this.averageSellingPrice,
    required this.totalCost,
    required this.profitMargin,
  });
}
