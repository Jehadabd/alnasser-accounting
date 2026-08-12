// screens/product_year_details_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import 'product_month_details_screen.dart';
import 'package:intl/intl.dart';
import 'product_customers_dialog.dart';

class ProductYearDetailsScreen extends StatefulWidget {
  final Product product;
  final int year;

  const ProductYearDetailsScreen({
    super.key,
    required this.product,
    required this.year,
  });

  @override
  State<ProductYearDetailsScreen> createState() =>
      _ProductYearDetailsScreenState();
}

class _ProductYearDetailsScreenState extends State<ProductYearDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  Map<int, double> _monthlySales = {};
  Map<int, double> _monthlyProfit = {};
  bool _isLoading = true;
  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadMonthlyData();
  }

  Future<void> _loadMonthlyData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final monthlySales = await _databaseService.getProductMonthlySales(
        widget.product.id!,
        widget.year,
      );
      final monthlyProfit = await _databaseService.getProductMonthlyProfit(
        widget.product.id!,
        widget.year,
      );
      setState(() {
        _monthlySales = monthlySales;
        _monthlyProfit = monthlyProfit;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تحميل البيانات: $e'),
          ),
        );
      }
    }
  }

  String getNumericMonthLabel(int year, int month) {
    return '${year}-${month.toString().padLeft(2, '0')}';
  }

  void _showCustomersBuying() {
    showDialog(
      context: context,
      builder: (context) => ProductCustomersDialog(
        productId: widget.product.id!,
        productName: widget.product.name,
        year: widget.year,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          '${widget.product.name} - سنة ${widget.year}',
          style: const TextStyle(fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMonthlyData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
              ),
            )
          : _monthlySales.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_month,
                        size: 80,
                        color: Color(0xFFCCCCCC),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'لا توجد مبيعات في هذه السنة',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // زر العملاء المشترين
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _showCustomersBuying,
                          icon: const Icon(Icons.people),
                          label: const Text('العملاء المشترين (تفصيل العملاء)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // قائمة الأشهر
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadMonthlyData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: 12, // 12 شهر
                          itemBuilder: (context, index) {
                            final month = index + 1;
                            final quantity = _monthlySales[month] ?? 0.0;
                            final profit = _monthlyProfit[month] ?? 0.0;
                            return _buildMonthCard(month, quantity, profit);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMonthCard(int month, double quantity, double profit) {
    final monthName = getNumericMonthLabel(widget.year, month);
    final hasSales = quantity > 0;

    return Card(
      elevation: hasSales ? 4 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: hasSales
            ? BorderSide(
                color: const Color(0xFF4CAF50).withOpacity(0.3), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: hasSales
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductMonthDetailsScreen(
                      product: widget.product,
                      year: widget.year,
                      month: month,
                    ),
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: hasSales
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF4CAF50).withOpacity(0.1),
                      const Color(0xFF4CAF50).withOpacity(0.05),
                    ],
                  )
                : null,
            color: hasSales ? null : Colors.grey.withOpacity(0.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasSales
                          ? const Color(0xFF4CAF50).withOpacity(0.1)
                          : Colors.grey.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.calendar_month,
                      color: hasSales ? const Color(0xFF4CAF50) : Colors.grey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          monthName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: hasSales
                                ? const Color(0xFF4CAF50)
                                : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasSales
                              ? '${_fmt(quantity)} ${widget.product.translatedUnit}'
                              : 'لا توجد مبيعات',
                          style: TextStyle(
                            fontSize: 14,
                            color: hasSales ? Colors.grey[600] : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hasSales) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.shopping_cart,
                        title: 'الكمية المباعة',
                        value:
                            '${_fmt(quantity)} ${widget.product.translatedUnit}',
                        color: const Color(0xFF2196F3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.trending_up,
                        title: 'الربح',
                        value: '${_fmt(profit)} د.ع',
                        color: const Color(0xFF4CAF50),
                      ),
                    ),
                  ],
                ),
              ],
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
