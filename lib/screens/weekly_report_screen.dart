// screens/weekly_report_screen.dart
import 'package:flutter/material.dart';
import '../services/ai_chat_service.dart';
import '../services/database_service.dart';
import '../services/reports_service.dart';
import 'package:intl/intl.dart';
import 'transactions_list_dialog.dart';

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  late final AIChatService _aiChatService;
  late final ReportsService _reportsService;
  Map<String, dynamic>? _reportData;
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topCustomers = [];
  Map<String, dynamic>? _comparison; // مقارنة مع الأسبوع الماضي
  Map<String, dynamic>? _trend; // تحليل الاتجاه
  bool _isLoading = true;
  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _aiChatService = AIChatService(DatabaseService());
    _reportsService = ReportsService();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final today = DateTime.now();
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      final endOfWeek = startOfWeekDay.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      
      // الأسبوع الماضي للمقارنة
      final prevWeekStart = startOfWeekDay.subtract(const Duration(days: 7));
      final prevWeekEnd = startOfWeekDay.subtract(const Duration(seconds: 1));
      
      final data = await _aiChatService.getWeeklyReport();
      final topProducts = await _reportsService.getTopProductsInPeriod(
        startDate: startOfWeekDay,
        endDate: endOfWeek,
        limit: 5,
      );
      final topCustomers = await _reportsService.getTopCustomersInPeriod(
        startDate: startOfWeekDay,
        endDate: endOfWeek,
        limit: 5,
      );
      final comparison = await _reportsService.comparePeriods(
        currentStart: startOfWeekDay,
        currentEnd: endOfWeek,
        previousStart: prevWeekStart,
        previousEnd: prevWeekEnd,
      );
      final trend = await _reportsService.analyzeSalesTrend(
        startDate: startOfWeekDay,
        endDate: endOfWeek,
      );
      
      setState(() {
        _reportData = data;
        _topProducts = topProducts;
        _topCustomers = topCustomers;
        _comparison = comparison;
        _trend = trend;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تحميل التقرير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final dateRangeStr = '${DateFormat('yyyy-MM-dd', 'ar').format(startOfWeek)} - ${DateFormat('yyyy-MM-dd', 'ar').format(endOfWeek)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('تقرير الأسبوع', style: TextStyle(fontSize: 24)),
        centerTitle: true,
        backgroundColor: const Color(0xFF9C27B0),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF9C27B0),
              ),
            )
          : _reportData == null
              ? const Center(
                  child: Text(
                    'لا توجد بيانات',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadReport,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // عنوان الفترة
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
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
                          child: Column(
                            children: [
                              const Icon(
                                Icons.date_range,
                                size: 40,
                                color: Color(0xFF9C27B0),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                dateRangeStr,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2C3E50),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'تقرير مفصل لمبيعات الأسبوع',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // المبيعات والأرباح
                        _buildSectionTitle('المبيعات والأرباح'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                title: 'إجمالي المبيعات',
                                value: '${_fmt(_reportData!['totalSales'])} د.ع',
                                icon: Icons.shopping_cart,
                                color: const Color(0xFF2196F3),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                title: 'صافي الربح',
                                value: '${_fmt(_reportData!['netProfit'])} د.ع',
                                icon: Icons.trending_up,
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStatCard(
                          title: 'إجمالي التكلفة',
                          value: '${_fmt(_reportData!['totalCost'])} د.ع',
                          icon: Icons.money_off,
                          color: const Color(0xFFF44336),
                        ),
                        const SizedBox(height: 20),

                        // نوع المبيعات
                        _buildSectionTitle('تصنيف المبيعات'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                title: 'البيع بالنقد',
                                value: '${_fmt(_reportData!['cashSales'])} د.ع',
                                icon: Icons.payments,
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                title: 'البيع بالدين',
                                value: '${_fmt(_reportData!['creditSales'])} د.ع',
                                icon: Icons.credit_card,
                                color: const Color(0xFFFF9800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStatCard(
                          title: 'إجمالي الراجع',
                          value: '${_fmt(_reportData!['totalReturns'])} د.ع',
                          icon: Icons.keyboard_return,
                          color: const Color(0xFF9C27B0),
                        ),
                        const SizedBox(height: 20),

                        // المعاملات المالية
                        _buildSectionTitle('المعاملات المالية'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildClickableStatCard(
                                title: 'إضافة دين',
                                value: '${_fmt(_reportData!['totalManualDebt'])} د.ع',
                                subtitle: '${_reportData!['manualDebtCount']} معاملة',
                                icon: Icons.add_circle,
                                color: const Color(0xFFFF5722),
                                onTap: () => _showDebtAdditions(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildClickableStatCard(
                                title: 'تسديد دين',
                                value: '${_fmt(_reportData!['totalManualPayment'])} د.ع',
                                subtitle: '${_reportData!['manualPaymentCount']} معاملة',
                                icon: Icons.remove_circle,
                                color: const Color(0xFF4CAF50),
                                onTap: () => _showDebtPayments(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ربح المعاملات اليدوية
                        if ((_reportData!['manualDebtProfit'] as num? ?? 0) > 0) ...[
                          _buildSectionTitle('أرباح إضافية'),
                          const SizedBox(height: 12),
                          _buildStatCard(
                            title: 'ربح المعاملات اليدوية',
                            value: '${_fmt(_reportData!['manualDebtProfit'])} د.ع',
                            icon: Icons.account_balance_wallet,
                            color: const Color(0xFF00BCD4),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // إحصائيات إضافية
                        _buildSectionTitle('إحصائيات إضافية'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                title: 'عدد الفواتير',
                                value: '${_reportData!['invoiceCount']} فاتورة',
                                icon: Icons.receipt_long,
                                color: const Color(0xFF607D8B),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                title: 'نسبة الربح',
                                value: '${_getProfitPercent().toStringAsFixed(1)}%',
                                icon: Icons.percent,
                                color: const Color(0xFF9C27B0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // متوسطات
                        if (_reportData!['invoiceCount'] > 0) ...[
                          _buildSectionTitle('المتوسطات'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  title: 'متوسط المبيعات/فاتورة',
                                  value: '${_fmt(_reportData!['totalSales'] / _reportData!['invoiceCount'])} د.ع',
                                  icon: Icons.calculate,
                                  color: const Color(0xFF00BCD4),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  title: 'متوسط الربح/فاتورة',
                                  value: '${_fmt(_reportData!['netProfit'] / _reportData!['invoiceCount'])} د.ع',
                                  icon: Icons.analytics,
                                  color: const Color(0xFF8BC34A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],

                        // تحليل الاتجاه
                        if (_trend != null) ...[
                          _buildSectionTitle('تحليل الاتجاه'),
                          const SizedBox(height: 12),
                          _buildTrendCard(),
                          const SizedBox(height: 20),
                        ],

                        // مقارنة مع الأسبوع الماضي
                        if (_comparison != null) ...[
                          _buildSectionTitle('مقارنة مع الأسبوع الماضي'),
                          const SizedBox(height: 12),
                          _buildComparisonCard(),
                          const SizedBox(height: 20),
                        ],

                        // أفضل 5 منتجات
                        if (_topProducts.isNotEmpty) ...[
                          _buildSectionTitle('أفضل 5 منتجات هذا الأسبوع'),
                          const SizedBox(height: 12),
                          _buildTopProductsList(),
                          const SizedBox(height: 20),
                        ],

                        // أفضل 5 عملاء
                        if (_topCustomers.isNotEmpty) ...[
                          _buildSectionTitle('أفضل 5 عملاء هذا الأسبوع'),
                          const SizedBox(height: 12),
                          _buildTopCustomersList(),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  double _getProfitPercent() {
    if (_reportData == null) return 0.0;
    final totalSales = (_reportData!['totalSales'] as num?)?.toDouble() ?? 0.0;
    final netProfit = (_reportData!['netProfit'] as num?)?.toDouble() ?? 0.0;
    if (totalSales <= 0) return 0.0;
    return (netProfit / totalSales) * 100;
  }

  Widget _buildTrendCard() {
    final trendArabic = _trend!['trendArabic'] as String? ?? 'غير محدد';
    final changePercent = (_trend!['changePercent'] as num?)?.toDouble() ?? 0.0;
    final avgDailySales = (_trend!['averageDailySales'] as num?)?.toDouble() ?? 0.0;
    
    Color trendColor;
    IconData trendIcon;
    if (_trend!['trend'] == 'increasing') {
      trendColor = Colors.green;
      trendIcon = Icons.trending_up;
    } else if (_trend!['trend'] == 'decreasing') {
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
                if (changePercent.abs() > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'التغير: ${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 14, color: trendColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard() {
    final changes = _comparison!['changes'] as Map<String, dynamic>;
    final salesChange = (changes['salesChange'] as num?)?.toDouble() ?? 0.0;
    final profitChange = (changes['profitChange'] as num?)?.toDouble() ?? 0.0;
    final invoiceChange = (changes['invoiceCountChange'] as num?)?.toDouble() ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          _buildComparisonRow('المبيعات', salesChange),
          const Divider(),
          _buildComparisonRow('الأرباح', profitChange),
          const Divider(),
          _buildComparisonRow('عدد الفواتير', invoiceChange),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topProducts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final product = _topProducts[index];
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topCustomers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final customer = _topCustomers[index];
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

  Widget _buildStatCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // بطاقة قابلة للضغط لعرض تفاصيل المعاملات
  Widget _buildClickableStatCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.touch_app, color: color.withOpacity(0.5), size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(اضغط للتفاصيل)',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // عرض معاملات إضافة الدين
  void _showDebtAdditions() {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfWeekDay.add(const Duration(days: 7));
    
    TransactionsListDialog.showDebtAdditions(
      context: context,
      startDate: startOfWeekDay,
      endDate: endOfWeek,
      periodTitle: 'الأسبوع',
    );
  }

  // عرض معاملات تسديد الدين
  void _showDebtPayments() {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfWeekDay.add(const Duration(days: 7));
    
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: startOfWeekDay,
      endDate: endOfWeek,
      periodTitle: 'الأسبوع',
    );
  }
}
