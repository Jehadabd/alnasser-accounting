// screens/monthly_report_screen.dart
// شاشة التقرير الشهري المفصل
import 'package:flutter/material.dart';
import '../services/reports_service.dart';
import 'package:intl/intl.dart';
import 'transactions_list_dialog.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  final ReportsService _reportsService = ReportsService();
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  late int _selectedYear;
  late int _selectedMonth;
  
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    
    try {
      final data = await _reportsService.getMonthlyDetailedReport(
        year: _selectedYear,
        month: _selectedMonth,
      );
      
      setState(() {
        _reportData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل التقرير: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('التقرير الشهري'),
        backgroundColor: const Color(0xFF673AB7),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
          ),
        ],
      ),
      body: Column(
        children: [
          // اختيار الشهر
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF673AB7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      if (_selectedMonth == 1) {
                        _selectedMonth = 12;
                        _selectedYear--;
                      } else {
                        _selectedMonth--;
                      }
                    });
                    _loadReport();
                  },
                ),
                GestureDetector(
                  onTap: _showMonthPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_getMonthName(_selectedMonth)} $_selectedYear',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: () {
                    final now = DateTime.now();
                    if (_selectedYear < now.year || 
                        (_selectedYear == now.year && _selectedMonth < now.month)) {
                      setState(() {
                        if (_selectedMonth == 12) {
                          _selectedMonth = 1;
                          _selectedYear++;
                        } else {
                          _selectedMonth++;
                        }
                      });
                      _loadReport();
                    }
                  },
                ),
              ],
            ),
          ),
          
          // المحتوى
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF673AB7)))
                : _reportData == null
                    ? const Center(child: Text('لا توجد بيانات'))
                    : RefreshIndicator(
                        onRefresh: _loadReport,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ملخص المبيعات
                              _buildSectionTitle('ملخص المبيعات'),
                              const SizedBox(height: 12),
                              _buildSummaryCards(),
                              const SizedBox(height: 20),
                              
                              // تحليل الاتجاه
                              _buildSectionTitle('تحليل الاتجاه'),
                              const SizedBox(height: 12),
                              _buildTrendCard(),
                              const SizedBox(height: 20),
                              
                              // مقارنة مع الشهر الماضي
                              _buildSectionTitle('مقارنة مع الشهر الماضي'),
                              const SizedBox(height: 12),
                              _buildComparisonCard(),
                              const SizedBox(height: 20),
                              
                              // أفضل المنتجات
                              _buildSectionTitle('أفضل 10 منتجات'),
                              const SizedBox(height: 12),
                              _buildTopProductsList(),
                              const SizedBox(height: 20),
                              
                              // أفضل العملاء
                              _buildSectionTitle('أفضل 10 عملاء'),
                              const SizedBox(height: 12),
                              _buildTopCustomersList(),
                              const SizedBox(height: 20),
                              
                              // العملاء الجدد
                              _buildSectionTitle('العملاء الجدد'),
                              const SizedBox(height: 12),
                              _buildNewCustomersCard(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2C3E50),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final summary = _reportData!['summary'] as Map<String, dynamic>;
    final profitPercent = (_reportData!['profitPercent'] as num?)?.toDouble() ?? 0.0;
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'إجمالي المبيعات',
                value: '${_fmt(summary['totalSales'])} د.ع',
                icon: Icons.shopping_cart,
                color: const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'إجمالي المرتجعات',
                value: '${_fmt(_reportData!['totalReturns'] ?? 0)} د.ع',
                icon: Icons.remove_shopping_cart,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'صافي الربح',
                value: '${_fmt(summary['netProfit'])} د.ع',
                icon: Icons.trending_up,
                color: const Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'نسبة الربح',
                value: '${profitPercent.toStringAsFixed(1)}%',
                icon: Icons.percent,
                color: const Color(0xFF9C27B0),
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard() {
    final trend = _reportData!['trend'] as Map<String, dynamic>;
    final trendArabic = trend['trendArabic'] as String? ?? 'غير محدد';
    final avgDailySales = (trend['averageDailySales'] as num?)?.toDouble() ?? 0.0;
    final changePercent = (trend['changePercent'] as num?)?.toDouble() ?? 0.0;
    
    Color trendColor;
    IconData trendIcon;
    if (trend['trend'] == 'increasing') {
      trendColor = Colors.green;
      trendIcon = Icons.trending_up;
    } else if (trend['trend'] == 'decreasing') {
      trendColor = Colors.red;
      trendIcon = Icons.trending_down;
    } else {
      trendColor = Colors.orange;
      trendIcon = Icons.trending_flat;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trendColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: trendColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(trendIcon, color: trendColor, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الاتجاه: $trendArabic',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: trendColor),
                ),
                const SizedBox(height: 4),
                Text(
                  'متوسط المبيعات اليومية: ${_fmt(avgDailySales)} د.ع',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard() {
    final comparison = _reportData!['comparison'] as Map<String, dynamic>;
    final changes = comparison['changes'] as Map<String, dynamic>;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          _buildComparisonRow('المبيعات', changes['salesChange'] ?? 0.0),
          const Divider(),
          _buildComparisonRow('الأرباح', changes['profitChange'] ?? 0.0),
          const Divider(),
          _buildComparisonRow('عدد الفواتير', changes['invoiceCountChange'] ?? 0.0),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String title, double changePercent) {
    final isPositive = changePercent >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isPositive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isPositive ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  '${changePercent.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsList() {
    final topProducts = _reportData!['topProducts'] as List<Map<String, dynamic>>;
    
    if (topProducts.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topProducts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final product = topProducts[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2196F3).withOpacity(0.1),
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Color(0xFF2196F3), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              product['product_name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('الكمية: ${_fmt(product['total_quantity'] ?? 0)}'),
            trailing: Text(
              '${_fmt(product['total_sales'] ?? 0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2196F3)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopCustomersList() {
    final topCustomers = _reportData!['topCustomers'] as List<Map<String, dynamic>>;
    
    if (topCustomers.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topCustomers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final customer = topCustomers[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              customer['customer_name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('${customer['invoice_count'] ?? 0} فاتورة'),
            trailing: Text(
              '${_fmt(customer['total_purchases'] ?? 0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewCustomersCard() {
    final newCustomersCount = _reportData!['newCustomersCount'] as int? ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00BCD4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add, color: Color(0xFF00BCD4), size: 32),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'العملاء الجدد هذا الشهر',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              Text(
                '$newCustomersCount عميل',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00BCD4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMonthPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر الشهر'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final isSelected = month == _selectedMonth;
              return InkWell(
                onTap: () {
                  setState(() => _selectedMonth = month);
                  Navigator.pop(context);
                  _loadReport();
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF673AB7) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getMonthName(month),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
