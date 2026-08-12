// screens/yearly_report_screen.dart
// شاشة التقرير السنوي
import 'package:flutter/material.dart';
import '../services/reports_service.dart';
import 'package:intl/intl.dart';

class YearlyReportScreen extends StatefulWidget {
  const YearlyReportScreen({super.key});

  @override
  State<YearlyReportScreen> createState() => _YearlyReportScreenState();
}

class _YearlyReportScreenState extends State<YearlyReportScreen> {
  final ReportsService _reportsService = ReportsService();
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  late int _selectedYear;
  
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    
    try {
      final data = await _reportsService.getYearlyReport(year: _selectedYear);
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('التقرير السنوي'),
        backgroundColor: const Color(0xFF3F51B5),
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
          // اختيار السنة
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF3F51B5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () {
                    setState(() => _selectedYear--);
                    _loadReport();
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_selectedYear',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: () {
                    if (_selectedYear < DateTime.now().year) {
                      setState(() => _selectedYear++);
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
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F51B5)))
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
                              // ملخص السنة
                              _buildSectionTitle('ملخص السنة'),
                              const SizedBox(height: 12),
                              _buildSummaryCards(),
                              const SizedBox(height: 20),
                              
                              // مقارنة مع السنة الماضية
                              _buildSectionTitle('مقارنة مع السنة الماضية'),
                              const SizedBox(height: 12),
                              _buildComparisonCard(),
                              const SizedBox(height: 20),
                              
                              // المبيعات الشهرية
                              _buildSectionTitle('المبيعات الشهرية'),
                              const SizedBox(height: 12),
                              _buildMonthlySalesChart(),
                              const SizedBox(height: 20),
                              
                              // أفضل المنتجات
                              _buildSectionTitle('أفضل 20 منتج'),
                              const SizedBox(height: 12),
                              _buildTopProductsList(),
                              const SizedBox(height: 20),
                              
                              // أفضل العملاء
                              _buildSectionTitle('أفضل 20 عميل'),
                              const SizedBox(height: 12),
                              _buildTopCustomersList(),
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
    final newCustomers = _reportData!['newCustomersCount'] as int? ?? 0;
    
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'عدد الفواتير',
                value: '${summary['invoiceCount']}',
                icon: Icons.receipt_long,
                color: const Color(0xFF607D8B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'العملاء الجدد',
                value: '$newCustomers',
                icon: Icons.person_add,
                color: const Color(0xFF00BCD4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'إجمالي التكلفة',
                value: '${_fmt(summary['totalCost'])} د.ع',
                icon: Icons.money_off,
                color: const Color(0xFFF44336),
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

  Widget _buildMonthlySalesChart() {
    final monthlySales = _reportData!['monthlySales'] as List<Map<String, dynamic>>;
    
    // إيجاد أعلى قيمة للتطبيع
    double maxSales = 0;
    for (var month in monthlySales) {
      final sales = (month['totalSales'] as num?)?.toDouble() ?? 0;
      if (sales > maxSales) maxSales = sales;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // الرسم البياني البسيط
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: monthlySales.map((month) {
                final sales = (month['totalSales'] as num?)?.toDouble() ?? 0;
                final height = maxSales > 0 ? (sales / maxSales) * 150 : 0.0;
                final monthNum = month['month'] as int;
                
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3F51B5),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$monthNum',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // جدول المبيعات الشهرية
          ...monthlySales.map((month) {
            final monthName = month['monthName'] as String;
            final sales = (month['totalSales'] as num?)?.toDouble() ?? 0;
            final profit = (month['netProfit'] as num?)?.toDouble() ?? 0;
            
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text(monthName)),
                  Expanded(
                    child: Text(
                      '${_fmt(sales)} د.ع',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    '${_fmt(profit)} د.ع',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }).toList(),
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
            trailing: Text(
              '${_fmt(customer['total_purchases'] ?? 0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
            ),
          );
        },
      ),
    );
  }
}
