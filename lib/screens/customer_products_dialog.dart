// screens/customer_products_dialog.dart
// شاشة عرض تفصيل المنتجات المشتراة من عميل معين
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/reports_service.dart';

class CustomerProductsDialog extends StatefulWidget {
  final int customerId;
  final String customerName;
  final int year;
  final int? month;

  const CustomerProductsDialog({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.year,
    this.month,
  });

  @override
  State<CustomerProductsDialog> createState() => _CustomerProductsDialogState();
}

class _CustomerProductsDialogState extends State<CustomerProductsDialog> {
  final ReportsService _reportsService = ReportsService();
  List<CustomerProductBreakdown> _products = [];
  bool _isLoading = true;
  String _sortBy = 'profit'; // profit, amount, quantity
  bool _sortDescending = true;
  
  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final products = await _reportsService.getCustomerProductsBreakdown(
        customerId: widget.customerId,
        year: widget.year,
        month: widget.month,
      );
      
      setState(() {
        _products = products;
        _sortProducts();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  void _sortProducts() {
    switch (_sortBy) {
      case 'profit':
        _products.sort((a, b) => _sortDescending 
            ? b.totalProfit.compareTo(a.totalProfit)
            : a.totalProfit.compareTo(b.totalProfit));
        break;
      case 'amount':
        _products.sort((a, b) => _sortDescending 
            ? b.totalAmount.compareTo(a.totalAmount)
            : a.totalAmount.compareTo(b.totalAmount));
        break;
      case 'quantity':
        _products.sort((a, b) => _sortDescending 
            ? b.baseQuantity.compareTo(a.baseQuantity)
            : a.baseQuantity.compareTo(b.baseQuantity));
        break;
    }
  }

  void _changeSortBy(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortDescending = !_sortDescending;
      } else {
        _sortBy = sortBy;
        _sortDescending = true;
      }
      _sortProducts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final periodText = widget.month != null 
        ? '${widget.year}-${widget.month.toString().padLeft(2, '0')}'
        : 'سنة ${widget.year}';
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المبيعات التراكمية - ${widget.customerName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          periodText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Sort buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  const Text('ترتيب حسب: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  _buildSortChip('الربح', 'profit'),
                  const SizedBox(width: 8),
                  _buildSortChip('المبلغ', 'amount'),
                  const SizedBox(width: 8),
                  _buildSortChip('الكمية', 'quantity'),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('لا توجد مشتريات في هذه الفترة'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            return _buildProductCard(product, index + 1);
                          },
                        ),
            ),
            
            // Summary
            if (!_isLoading && _products.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem(
                      'إجمالي المبلغ',
                      '${_fmt(_products.fold(0.0, (sum, p) => sum + p.totalAmount))} د.ع',
                      Colors.blue,
                    ),
                    _buildSummaryItem(
                      'إجمالي الربح',
                      '${_fmt(_products.fold(0.0, (sum, p) => sum + p.totalProfit))} د.ع',
                      Colors.green,
                    ),
                    _buildSummaryItem(
                      'عدد المنتجات',
                      '${_products.length}',
                      Colors.orange,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, String value) {
    final isSelected = _sortBy == value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (isSelected)
            Icon(
              _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
            ),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => _changeSortBy(value),
      selectedColor: const Color(0xFF2196F3).withOpacity(0.2),
    );
  }

  Widget _buildProductCard(CustomerProductBreakdown product, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2196F3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product.productName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'المبلغ',
                    '${_fmt(product.totalAmount)} د.ع',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoBox(
                    'الربح',
                    '${_fmt(product.totalProfit)} د.ع',
                    product.totalProfit >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الكمية',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.quantityFormatted,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
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

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
