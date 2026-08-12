// screens/product_customers_dialog.dart
// شاشة عرض تفصيل العملاء المشترين لمنتج معين
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/reports_service.dart';

class ProductCustomersDialog extends StatefulWidget {
  final int productId;
  final String productName;
  final int year;
  final int? month;

  const ProductCustomersDialog({
    super.key,
    required this.productId,
    required this.productName,
    required this.year,
    this.month,
  });

  @override
  State<ProductCustomersDialog> createState() => _ProductCustomersDialogState();
}

class _ProductCustomersDialogState extends State<ProductCustomersDialog> {
  final ReportsService _reportsService = ReportsService();
  List<ProductCustomerBreakdown> _customers = [];
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
      final customers = await _reportsService.getProductCustomersBreakdown(
        productId: widget.productId,
        year: widget.year,
        month: widget.month,
      );
      
      setState(() {
        _customers = customers;
        _sortCustomers();
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

  void _sortCustomers() {
    switch (_sortBy) {
      case 'profit':
        _customers.sort((a, b) => _sortDescending 
            ? b.totalProfit.compareTo(a.totalProfit)
            : a.totalProfit.compareTo(b.totalProfit));
        break;
      case 'amount':
        _customers.sort((a, b) => _sortDescending 
            ? b.totalAmount.compareTo(a.totalAmount)
            : a.totalAmount.compareTo(b.totalAmount));
        break;
      case 'quantity':
        _customers.sort((a, b) => _sortDescending 
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
      _sortCustomers();
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
                color: const Color(0xFF4CAF50),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'العملاء المشترين - ${widget.productName}',
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
                  : _customers.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('لا توجد مبيعات في هذه الفترة'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _customers.length,
                          itemBuilder: (context, index) {
                            final customer = _customers[index];
                            return _buildCustomerCard(customer, index + 1);
                          },
                        ),
            ),
            
            // Summary
            if (!_isLoading && _customers.isNotEmpty)
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
                      '${_fmt(_customers.fold(0.0, (sum, c) => sum + c.totalAmount))} د.ع',
                      Colors.blue,
                    ),
                    _buildSummaryItem(
                      'إجمالي الربح',
                      '${_fmt(_customers.fold(0.0, (sum, c) => sum + c.totalProfit))} د.ع',
                      Colors.green,
                    ),
                    _buildSummaryItem(
                      'عدد العملاء',
                      '${_customers.length}',
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
      selectedColor: const Color(0xFF4CAF50).withOpacity(0.2),
    );
  }

  Widget _buildCustomerCard(ProductCustomerBreakdown customer, int index) {
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
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.customerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (customer.customerPhone != null)
                        Text(
                          customer.customerPhone!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
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
                    '${_fmt(customer.totalAmount)} د.ع',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoBox(
                    'الربح',
                    '${_fmt(customer.totalProfit)} د.ع',
                    customer.totalProfit >= 0 ? Colors.green : Colors.red,
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
                    customer.quantityFormatted,
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
