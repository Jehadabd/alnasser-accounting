// screens/person_year_details_screen.dart
import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/database_service.dart';
import 'person_month_details_screen.dart';
import '../models/person_data.dart' show PersonMonthData;
import 'package:intl/intl.dart';
import 'customer_products_dialog.dart';

class PersonYearDetailsScreen extends StatefulWidget {
  final Customer customer;
  final int year;

  const PersonYearDetailsScreen({
    super.key,
    required this.customer,
    required this.year,
  });

  @override
  State<PersonYearDetailsScreen> createState() =>
      _PersonYearDetailsScreenState();
}

class _PersonYearDetailsScreenState extends State<PersonYearDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  Map<int, PersonMonthData> _monthlyData = {};
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
      final monthlyData = await _databaseService.getCustomerMonthlyData(
        widget.customer.id!,
        widget.year,
      );
      setState(() {
        _monthlyData = monthlyData;
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

  void _showCumulativeSales() {
    showDialog(
      context: context,
      builder: (context) => CustomerProductsDialog(
        customerId: widget.customer.id!,
        customerName: widget.customer.name,
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
          '${widget.customer.name} - سنة ${widget.year}',
          style: const TextStyle(fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF2196F3),
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
                color: Color(0xFF2196F3),
              ),
            )
          : _monthlyData.isEmpty
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
                        'لا توجد تعاملات في هذه السنة',
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
                    // زر المبيعات التراكمية
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _showCumulativeSales,
                          icon: const Icon(Icons.analytics),
                          label: const Text('المبيعات التراكمية (تفصيل المنتجات)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
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
                            final monthData = _monthlyData[month];
                            return _buildMonthCard(month, monthData);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMonthCard(int month, PersonMonthData? monthData) {
    final monthName = getNumericMonthLabel(widget.year, month);
    final hasData = monthData != null &&
        (monthData.totalProfit > 0 || monthData.totalSales > 0);

    return Card(
      elevation: hasData ? 4 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: hasData
            ? BorderSide(
                color: const Color(0xFF2196F3).withOpacity(0.3), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: hasData
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PersonMonthDetailsScreen(
                      customer: widget.customer,
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
            gradient: hasData
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF2196F3).withOpacity(0.1),
                      const Color(0xFF2196F3).withOpacity(0.05),
                    ],
                  )
                : null,
            color: hasData ? null : Colors.grey.withOpacity(0.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasData
                          ? const Color(0xFF2196F3).withOpacity(0.1)
                          : Colors.grey.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.calendar_month,
                      color: hasData ? const Color(0xFF2196F3) : Colors.grey,
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
                            color:
                                hasData ? const Color(0xFF2196F3) : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasData
                              ? '${monthData!.totalInvoices} فاتورة'
                              : 'لا توجد تعاملات',
                          style: TextStyle(
                            fontSize: 14,
                            color: hasData ? Colors.grey[600] : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hasData) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.trending_up,
                        title: 'الربح',
                        value:
                            '${monthData!.totalProfit >= 0 ? _fmt(monthData.totalProfit) : _fmt(-monthData.totalProfit)} د.ع',
                        color: const Color(0xFF4CAF50),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.shopping_cart,
                        title: 'المبيعات',
                        value: '${_fmt(monthData.totalSales)} د.ع',
                        color: const Color(0xFF2196F3),
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
