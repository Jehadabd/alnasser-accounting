// screens/inventory_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../models/monthly_overview.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/settings_manager.dart';
import '../models/app_settings.dart';
import 'transactions_list_dialog.dart';
import 'material_inventory_screen.dart';
import '../widgets/app_side_nav.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  final ReportsService _reportsService = ReportsService();
  late TabController _tabController;
  AppSettings? _appSettings;

  // بيانات الجرد الشهري
  Map<String, MonthlyOverview> _monthlySummaries = {};
  Map<String, List<Map<String, dynamic>>> _dailySalesPerMonth = {};
  Map<String, String> _selectedMetricPerMonth = {};
  Map<String, int?> _hoveredDayIndexPerMonth = {};

  // بيانات المقارنة
  MonthlyOverview? _currentMonth;
  MonthlyOverview? _lastMonth;

  // الشهر المختار للتحليلات
  late int _selectedYear;
  late int _selectedMonth;
  String get _selectedMonthKey => '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

  // بيانات أفضل العملاء والمنتجات
  List<Map<String, dynamic>> _topCustomersBySales = [];
  List<Map<String, dynamic>> _topCustomersByProfit = [];
  List<Map<String, dynamic>> _topProductsBySales = [];
  List<Map<String, dynamic>> _topProductsByProfit = [];

  bool _isLoading = true;
  double _manualDebtProfitPercent = 15.0; // القيمة الافتراضية

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      // تحميل الجرد الشهري
      final summaries = await _db.getMonthlySalesSummary();
      
      // تحميل الإعدادات لنسبة الربح المثبتة
      final settings = await SettingsManager.getAppSettings();
      _appSettings = settings;

      // تحديد الشهر الحالي والماضي للمقارنة
      final now = DateTime.now();
      final currentMonthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final lastMonthDate = DateTime(now.year, now.month - 1, 1);
      final lastMonthKey = '${lastMonthDate.year}-${lastMonthDate.month.toString().padLeft(2, '0')}';

      // تحميل أفضل العملاء والمنتجات للشهر المختار
      final topCustomersSales = await _db.getTopCustomersBySales(limit: 10, year: _selectedYear, month: _selectedMonth);
      final topCustomersProfit = await _db.getTopCustomersByProfit(limit: 10, year: _selectedYear, month: _selectedMonth);
      final topProductsSales = await _db.getTopProductsBySales(limit: 10, year: _selectedYear, month: _selectedMonth);
      final topProductsProfit = await _db.getTopProductsByProfit(limit: 10, year: _selectedYear, month: _selectedMonth);

      // تحميل المبيعات اليومية لكل شهر المخطط التفاعلي
      final Map<String, List<Map<String, dynamic>>> dailySalesPerMonth = {};
      for (final monthKey in summaries.keys) {
        final parts = monthKey.split('-');
        if (parts.length >= 2) {
          final y = int.tryParse(parts[0]) ?? now.year;
          final m = int.tryParse(parts[1]) ?? now.month;
          final rep = await _reportsService.getMonthlyDetailedReport(year: y, month: m);
          dailySalesPerMonth[monthKey] = (rep['dailySales'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        }
      }

      setState(() {
        _monthlySummaries = summaries;
        _dailySalesPerMonth = dailySalesPerMonth;
        _currentMonth = summaries[currentMonthKey];
        _lastMonth = summaries[lastMonthKey];
        _topCustomersBySales = topCustomersSales;
        _topCustomersByProfit = topCustomersProfit;
        _topProductsBySales = topProductsSales;
        _topProductsByProfit = topProductsProfit;
        _manualDebtProfitPercent = settings.manualDebtProfitPercentage;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('الجرد والتحليلات'),
        backgroundColor: const Color(0xFF3F51B5),
        elevation: 0,
        actions: [],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'الجرد الشهري', icon: Icon(Icons.calendar_month, size: 20)),
            Tab(text: 'المقارنة', icon: Icon(Icons.compare_arrows, size: 20)),
            Tab(text: 'أفضل عملاء (شراء)', icon: Icon(Icons.people, size: 20)),
            Tab(text: 'أفضل عملاء (ربح)', icon: Icon(Icons.emoji_events, size: 20)),
            Tab(text: 'أفضل منتجات', icon: Icon(Icons.inventory_2, size: 20)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3F51B5)))
          : Row(
              children: [
                if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
                  const AppSideNav(currentRoute: '/reports'),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMonthlyInventoryTab(),
                      _buildComparisonTab(),
                      _buildTopCustomersBySalesTab(),
                      _buildTopCustomersByProfitTab(),
                      _buildTopProductsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }


  // ==================== تبويب الجرد الشهري ====================
  Widget _buildMonthlyInventoryTab() {
    final sortedMonthYears = _monthlySummaries.keys.toList();
    sortedMonthYears.sort((a, b) {
      final aDate = DateTime.parse('${a.split('-')[0]}-${a.split('-')[1].padLeft(2, '0')}-01');
      final bDate = DateTime.parse('${b.split('-')[0]}-${b.split('-')[1].padLeft(2, '0')}-01');
      return bDate.compareTo(aDate);
    });

    final now = DateTime.now();

    if (_monthlySummaries.isEmpty) {
      return const Center(child: Text('لا توجد بيانات مبيعات متاحة.'));
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedMonthYears.length,
        itemBuilder: (context, index) {
          final monthYear = sortedMonthYears[index];
          final summary = _monthlySummaries[monthYear]!;
          final date = DateTime.parse('${monthYear.split('-')[0]}-${monthYear.split('-')[1].padLeft(2, '0')}-01');
          final isCurrentMonth = date.year == now.year && date.month == now.month;

          return _buildMonthCard(monthYear, summary, isCurrentMonth);
        },
      ),
    );
  }

  Widget _buildMonthCard(String monthYear, MonthlyOverview summary, bool isCurrentMonth) {
    // ═══════════════════════════════════════════════════════════════════════════
    // حسابات تفصيلية شاملة للجرد الشهري
    // ═══════════════════════════════════════════════════════════════════════════
    
    // === بيانات الفواتير ===
    // دين الفواتير = creditSales - إضافة الدين اليدوية
    final invoiceCreditSales = summary.creditSales - summary.totalManualDebt;
    final invoiceCreditSalesPositive = invoiceCreditSales > 0 ? invoiceCreditSales : 0.0;
    
    // إجمالي مبيعات الفواتير = نقد + دين الفواتير
    final totalInvoiceSales = summary.cashSales + invoiceCreditSalesPositive;
    
    // نسب الفواتير (نقد + دين = 100%)
    final cashPercentOfInvoices = totalInvoiceSales > 0 ? (summary.cashSales / totalInvoiceSales * 100) : 0.0;
    final creditPercentOfInvoices = totalInvoiceSales > 0 ? (invoiceCreditSalesPositive / totalInvoiceSales * 100) : 0.0;
    
    // نسبة ربح الفواتير
    final invoiceProfitPercent = summary.totalSales > 0 ? (summary.netProfit / summary.totalSales * 100) : 0.0;
    
    // === بيانات المعاملات اليدوية ===
    // إضافة دين يدوية (manual_debt + opening_balance)
    final manualDebtAmount = summary.totalManualDebt;
    
    // ربح المعاملات اليدوية (${_manualDebtProfitPercent.toStringAsFixed(0)}%)
    final manualProfit = summary.manualDebtProfit;
    
    // === الإجماليات الشاملة ===
    // إجمالي المبيعات الشامل = مبيعات الفواتير + إضافة الدين اليدوية
    final totalSalesAll = summary.totalSales + manualDebtAmount;
    
    // إجمالي الأرباح الشامل = أرباح الفواتير + أرباح المعاملات اليدوية
    final totalProfitAll = summary.netProfit + manualProfit;
    final totalProfitPercentAll = totalSalesAll > 0 ? (totalProfitAll / totalSalesAll * 100) : 0.0;
    
    // إجمالي الدين الشامل = دين الفواتير + إضافة دين يدوية
    final totalDebtAll = invoiceCreditSalesPositive + manualDebtAmount;

    final dailySales = _dailySalesPerMonth[monthYear] ?? [];
    final selectedMetric = _selectedMetricPerMonth[monthYear] ?? 'sales';
    final hoveredIdx = _hoveredDayIndexPerMonth[monthYear];

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isCurrentMonth ? const Color(0xFF3F51B5).withOpacity(0.4) : Colors.grey.withOpacity(0.2), width: 2),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: isCurrentMonth
                ? [const Color(0xFF3F51B5).withOpacity(0.08), const Color(0xFF3F51B5).withOpacity(0.02)]
                : [Colors.grey.withOpacity(0.06), Colors.grey.withOpacity(0.01)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ═══════════════════════════════════════════════════════════════════
            // عنوان الشهر
            // ═══════════════════════════════════════════════════════════════════
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCurrentMonth ? const Color(0xFF3F51B5).withOpacity(0.15) : Colors.grey.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.calendar_month, color: isCurrentMonth ? const Color(0xFF3F51B5) : Colors.grey[600], size: 28),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(monthYear, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isCurrentMonth ? const Color(0xFF3F51B5) : Colors.grey[700])),
                    if (isCurrentMonth) Text('الشهر الحالي', style: TextStyle(fontSize: 12, color: const Color(0xFF3F51B5), fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),

            // ═══════════════════════════════════════════════════════════════════
            // القسم الأول: بيانات الفواتير الرئيسية (سطر واحد يتأقلم ديناميكياً مع الشاشة)
            // ═══════════════════════════════════════════════════════════════════
            _buildSectionHeader('🧾 بيانات الفواتير الرئيسية', const Color(0xFF2196F3)),
            const SizedBox(height: 10),

            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 850;

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: _buildCompactHeaderPill('مبيعات الفواتير', '${formatCurrency(summary.totalSales)} د.ع', Icons.shopping_cart, null, const Color(0xFF2196F3))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCompactHeaderPill('تكلفة الفواتير', '${formatCurrency(summary.totalCost)} د.ع', Icons.money_off, null, const Color(0xFFF44336))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCompactHeaderPill('أرباح الفواتير', '${formatCurrency(summary.netProfit)} د.ع', Icons.trending_up, '${invoiceProfitPercent.toStringAsFixed(1)}%', const Color(0xFF4CAF50))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCompactHeaderPill('عدد الفواتير', '${summary.invoiceCount} فاتورة', Icons.receipt_long, null, const Color(0xFF607D8B))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCompactHeaderPill('نقد (فواتير)', '${formatCurrency(summary.cashSales)} د.ع', Icons.payments, '${cashPercentOfInvoices.toStringAsFixed(1)}%', const Color(0xFF4CAF50))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildCompactHeaderPill('دين (فواتير)', '${formatCurrency(invoiceCreditSalesPositive)} د.ع', Icons.credit_card, '${creditPercentOfInvoices.toStringAsFixed(1)}%', const Color(0xFFFF9800))),
                      if (summary.totalReturns > 0) ...[
                        const SizedBox(width: 8),
                        Expanded(child: _buildCompactHeaderPill('الراجع', '${formatCurrency(summary.totalReturns)} د.ع', Icons.keyboard_return, null, const Color(0xFF9C27B0))),
                      ],
                    ],
                  );
                }

                return SizedBox(
                  height: 75,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildMiniMetricCard('مبيعات الفواتير', '${formatCurrency(summary.totalSales)} د.ع', Icons.shopping_cart, const Color(0xFF2196F3)),
                      const SizedBox(width: 8),
                      _buildMiniMetricCard('تكلفة الفواتير', '${formatCurrency(summary.totalCost)} د.ع', Icons.money_off, const Color(0xFFF44336)),
                      const SizedBox(width: 8),
                      _buildMiniMetricCard('أرباح الفواتير', '${formatCurrency(summary.netProfit)} د.ع (${invoiceProfitPercent.toStringAsFixed(1)}%)', Icons.trending_up, const Color(0xFF4CAF50)),
                      const SizedBox(width: 8),
                      _buildMiniMetricCard('عدد الفواتير', '${summary.invoiceCount} فاتورة', Icons.receipt_long, const Color(0xFF607D8B)),
                      const SizedBox(width: 8),
                      _buildMiniMetricCard('نقد الفواتير', '${formatCurrency(summary.cashSales)} د.ع (${cashPercentOfInvoices.toStringAsFixed(1)}%)', Icons.payments, const Color(0xFF4CAF50)),
                      const SizedBox(width: 8),
                      _buildMiniMetricCard('دين الفواتير', '${formatCurrency(invoiceCreditSalesPositive)} د.ع (${creditPercentOfInvoices.toStringAsFixed(1)}%)', Icons.credit_card, const Color(0xFFFF9800)),
                      if (summary.totalReturns > 0) ...[
                        const SizedBox(width: 8),
                        _buildMiniMetricCard('إجمالي المرتجعات', '${formatCurrency(summary.totalReturns)} د.ع', Icons.keyboard_return, const Color(0xFF9C27B0)),
                      ],
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // ═══════════════════════════════════════════════════════════════════
            // المخطط البياني الخطي التفاعلي لأيام الشهر (Interactive Daily Chart)
            // ═══════════════════════════════════════════════════════════════════
            if (dailySales.isNotEmpty) ...[
              _buildMonthTrendChartCard(monthYear, dailySales, selectedMetric, hoveredIdx),
              const SizedBox(height: 16),
            ],

            // ═══════════════════════════════════════════════════════════════════
            // القسم الثاني: المعاملات اليدوية والإجماليات (سطر واحد يتأقلم ديناميكياً)
            // ═══════════════════════════════════════════════════════════════════
            _buildSectionHeader('✋ المعاملات اليدوية والإجماليات', const Color(0xFFE91E63)),
            const SizedBox(height: 10),

            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 850;

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(
                        child: _buildSingleRowPillItem(
                          Icons.person_add,
                          'إضافة دين يدوي',
                          '${formatCurrency(manualDebtAmount)} د.ع',
                          '${summary.manualDebtCount} معاملة',
                          const Color(0xFFE91E63),
                          () => _showDebtAdditions(monthYear),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSingleRowPillItem(
                          Icons.account_balance_wallet,
                          'ربح دين يدوي',
                          '${formatCurrency(manualProfit)} د.ع',
                          '${_manualDebtProfitPercent.toStringAsFixed(0)}%',
                          const Color(0xFF00BCD4),
                          null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSingleRowPillItem(
                          Icons.remove_circle,
                          'تسديد ديون يدوية',
                          '${formatCurrency(summary.totalDebtPayments)} د.ع',
                          '${summary.manualPaymentCount} معاملة',
                          const Color(0xFF009688),
                          () => _showDebtPayments(monthYear),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSingleRowPillItem(
                          Icons.assessment,
                          'إجمالي الأرباح الشامل',
                          '${formatCurrency(totalProfitAll)} د.ع',
                          '${totalProfitPercentAll.toStringAsFixed(1)}%',
                          const Color(0xFF8BC34A),
                          null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSingleRowPillItem(
                          Icons.shopping_bag,
                          'إجمالي المبيعات الشامل',
                          '${formatCurrency(totalSalesAll)} د.ع',
                          'شامل الكل',
                          const Color(0xFF673AB7),
                          null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSingleRowPillItem(
                          Icons.account_balance,
                          'إجمالي الديون الشامل',
                          '${formatCurrency(totalDebtAll)} د.ع',
                          'فواتير + يدوي',
                          const Color(0xFFFF5722),
                          null,
                        ),
                      ),
                    ],
                  );
                }

                return SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildSingleRowPillItem(
                        Icons.person_add,
                        'إضافة دين يدوي',
                        '${formatCurrency(manualDebtAmount)} د.ع',
                        '${summary.manualDebtCount} معاملة',
                        const Color(0xFFE91E63),
                        () => _showDebtAdditions(monthYear),
                      ),
                      const SizedBox(width: 8),
                      _buildSingleRowPillItem(
                        Icons.account_balance_wallet,
                        'ربح دين يدوي',
                        '${formatCurrency(manualProfit)} د.ع',
                        '${_manualDebtProfitPercent.toStringAsFixed(0)}%',
                        const Color(0xFF00BCD4),
                        null,
                      ),
                      const SizedBox(width: 8),
                      _buildSingleRowPillItem(
                        Icons.remove_circle,
                        'تسديد ديون يدوية',
                        '${formatCurrency(summary.totalDebtPayments)} د.ع',
                        '${summary.manualPaymentCount} معاملة',
                        const Color(0xFF009688),
                        () => _showDebtPayments(monthYear),
                      ),
                      const SizedBox(width: 8),
                      _buildSingleRowPillItem(
                        Icons.assessment,
                        'إجمالي الأرباح الشامل',
                        '${formatCurrency(totalProfitAll)} د.ع',
                        '${totalProfitPercentAll.toStringAsFixed(1)}%',
                        const Color(0xFF8BC34A),
                        null,
                      ),
                      const SizedBox(width: 8),
                      _buildSingleRowPillItem(
                        Icons.shopping_bag,
                        'إجمالي المبيعات الشامل',
                        '${formatCurrency(totalSalesAll)} د.ع',
                        'شامل الكل',
                        const Color(0xFF673AB7),
                        null,
                      ),
                      const SizedBox(width: 8),
                      _buildSingleRowPillItem(
                        Icons.account_balance,
                        'إجمالي الديون الشامل',
                        '${formatCurrency(totalDebtAll)} د.ع',
                        'فواتير + يدوي',
                        const Color(0xFFFF5722),
                        null,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  // بطاقة معلومات بحجم أكبر وأوضح
  Widget _buildCompactInfoItem(IconData icon, String title, String value, String? badge, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: Text(badge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
        ],
      ),
    );
  }
  
  // بطاقة قابلة للضغط بحجم أكبر
  Widget _buildCompactClickableItem(IconData icon, String title, String value, String subtitle, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 6),
                Icon(Icons.touch_app, color: color.withOpacity(0.5), size: 16),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
  
  // عنوان قسم
  Widget _buildSectionHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // بطاقة معلومات كبيرة مع نسبة مئوية
  Widget _buildLargeInfoItem(IconData icon, String title, String value, String? percent, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              if (percent != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: Text(percent, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // بطاقة قابلة للضغط كبيرة
  Widget _buildLargeClickableItem(IconData icon, String title, String value, String subtitle, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 6),
                Icon(Icons.touch_app, color: color.withOpacity(0.5), size: 16),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }


  // ==================== تبويب المقارنة المطوّر ====================
  Widget _buildComparisonTab() {
    if (_currentMonth == null && _lastMonth == null) {
      return const Center(child: Text('لا توجد بيانات كافية للمقارنة'));
    }

    final now = DateTime.now();
    final currentMonthName = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final lastMonthDate = DateTime(now.year, now.month - 1, 1);
    final lastMonthName = '${lastMonthDate.year}-${lastMonthDate.month.toString().padLeft(2, '0')}';

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // عنوان المقارنة البارز والجذاب
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(children: [
                    const Icon(Icons.calendar_month_rounded, color: Colors.amberAccent, size: 34),
                    const SizedBox(height: 8),
                    Text(currentMonthName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                    const Text('الشهر الحالي', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.compare_arrows_rounded, size: 30, color: Colors.amberAccent),
                  ),
                  Column(children: [
                    const Icon(Icons.history_toggle_off_rounded, color: Colors.tealAccent, size: 34),
                    const SizedBox(height: 8),
                    Text(lastMonthName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                    const Text('الشهر الماضي', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // كروت المقارنة المطورة
            _buildComparisonRow('إجمالي المبيعات', _currentMonth?.totalSales ?? 0, _lastMonth?.totalSales ?? 0, Icons.shopping_cart, const Color(0xFF2563EB)),
            _buildComparisonRow('صافي الأرباح', _currentMonth?.netProfit ?? 0, _lastMonth?.netProfit ?? 0, Icons.trending_up, const Color(0xFF059669)),
            _buildComparisonRow('إجمالي التكلفة', _currentMonth?.totalCost ?? 0, _lastMonth?.totalCost ?? 0, Icons.money_off, const Color(0xFFDC2626)),
            _buildComparisonRow('عدد الفواتير', (_currentMonth?.invoiceCount ?? 0).toDouble(), (_lastMonth?.invoiceCount ?? 0).toDouble(), Icons.receipt_long, const Color(0xFF7C3AED), isCount: true),
            _buildComparisonRow('البيع بالنقد', _currentMonth?.cashSales ?? 0, _lastMonth?.cashSales ?? 0, Icons.payments, const Color(0xFF059669)),
            _buildComparisonRow('البيع بالدين', _currentMonth?.creditSales ?? 0, _lastMonth?.creditSales ?? 0, Icons.credit_card, const Color(0xFFD97706)),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonRow(String title, double current, double last, IconData icon, Color color, {bool isCount = false}) {
    final diff = current - last;
    final percentChange = last > 0 ? ((diff / last) * 100) : (current > 0 ? 100.0 : 0.0);
    final isPositive = diff >= 0;
    final totalVal = math.max(1.0, current + last);
    final currentRatio = (current / totalVal).clamp(0.05, 0.95);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                      const SizedBox(width: 4),
                      Text(
                        '${percentChange.abs().toStringAsFixed(1)}%',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الشهر الحالي', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(isCount ? current.toInt().toString() : '${formatCurrency(current)} د.ع', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('الشهر الماضي', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(isCount ? last.toInt().toString() : '${formatCurrency(last)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF64748B))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // شريط التقدم المرئي بين الشهرين
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(
                      flex: (currentRatio * 100).toInt(),
                      child: Container(color: color),
                    ),
                    Expanded(
                      flex: ((1 - currentRatio) * 100).toInt(),
                      child: Container(color: Colors.grey[300]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ==================== widget اختيار الشهر ====================
  Widget _buildMonthSelector() {
    final months = _monthlySummaries.keys.toList();
    months.sort((a, b) => b.compareTo(a)); // ترتيب تنازلي

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, color: Color(0xFF3F51B5)),
          const SizedBox(width: 12),
          const Text('الشهر:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: _selectedMonthKey,
              isExpanded: true,
              underline: const SizedBox(),
              items: months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (value) {
                if (value != null) {
                  final parts = value.split('-');
                  setState(() {
                    _selectedYear = int.parse(parts[0]);
                    _selectedMonth = int.parse(parts[1]);
                  });
                  _loadAllData();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== تبويب أفضل العملاء (شراء) ====================
  Widget _buildTopCustomersBySalesTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _topCustomersBySales.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return _buildMonthSelector();
          if (index == 1) {
            return Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2196F3), Color(0xFF1976D2)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people, color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text('أفضل 10 عملاء - الأكثر شراءً ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                ],
              ),
            );
          }
          if (_topCustomersBySales.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات لهذا الشهر')));
          }
          final customerIndex = index - 2;
          if (customerIndex >= _topCustomersBySales.length) return const SizedBox();
          final customer = _topCustomersBySales[customerIndex];
          return _buildCustomerRankCard(customerIndex + 1, customer['name'] ?? '', customer['total_sales'] ?? 0, 'إجمالي المشتريات', const Color(0xFF2196F3));
        },
      ),
    );
  }

  // ==================== تبويب أفضل العملاء (ربح) ====================
  Widget _buildTopCustomersByProfitTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _topCustomersByProfit.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return _buildMonthSelector();
          if (index == 1) {
            return Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF388E3C)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text('أفضل 10 عملاء - الأكثر ربحية ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                ],
              ),
            );
          }
          if (_topCustomersByProfit.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات لهذا الشهر')));
          }
          final customerIndex = index - 2;
          if (customerIndex >= _topCustomersByProfit.length) return const SizedBox();
          final customer = _topCustomersByProfit[customerIndex];
          return _buildCustomerRankCard(customerIndex + 1, customer['name'] ?? '', customer['total_profit'] ?? 0, 'صافي الربح', const Color(0xFF4CAF50));
        },
      ),
    );
  }

  Widget _buildCustomerRankCard(int rank, String name, num value, String label, Color color) {
    Color rankColor;
    IconData rankIcon;
    if (rank == 1) {
      rankColor = const Color(0xFFFFD700);
      rankIcon = Icons.looks_one;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
      rankIcon = Icons.looks_two;
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32);
      rankIcon = Icons.looks_3;
    } else {
      rankColor = Colors.grey;
      rankIcon = Icons.tag;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: rankColor.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: rankColor, width: 2),
          ),
          child: Center(
            child: rank <= 3
                ? Icon(rankIcon, color: rankColor, size: 28)
                : Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: rankColor)),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Text('${formatCurrency(value)} د.ع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      ),
    );
  }


  // ==================== تبويب أفضل المنتجات ====================
  Widget _buildTopProductsTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // اختيار الشهر
            _buildMonthSelector(),

            // أفضل المنتجات مبيعاً
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text('أفضل 10 منتجات - الأكثر مبيعاً ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_topProductsBySales.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات لهذا الشهر'))
            else
              ...List.generate(_topProductsBySales.length, (index) {
                final product = _topProductsBySales[index];
                return _buildProductRankCard(index + 1, product['name'] ?? '', product['total_quantity'] ?? 0, product['unit'] ?? '', 'الكمية المباعة', const Color(0xFF9C27B0));
              }),

            const SizedBox(height: 24),

            // أفضل المنتجات ربحاً
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFF9800), Color(0xFFF57C00)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.monetization_on, color: Colors.white, size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text('أفضل 10 منتجات - الأكثر ربحية ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_topProductsByProfit.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات لهذا الشهر'))
            else
              ...List.generate(_topProductsByProfit.length, (index) {
                final product = _topProductsByProfit[index];
                return _buildProductProfitCard(index + 1, product['name'] ?? '', product['total_profit'] ?? 0, 'صافي الربح', const Color(0xFFFF9800));
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildProductRankCard(int rank, String name, num quantity, String unit, String label, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color))),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        trailing: Text('${formatCurrency(quantity)} $unit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
      ),
    );
  }

  Widget _buildProductProfitCard(int rank, String name, num profit, String label, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color))),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        trailing: Text('${formatCurrency(profit)} د.ع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
      ),
    );
  }


  // ==================== دوال مساعدة ====================
  Widget _buildInfoItem(IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildClickableInfoItem(IconData icon, String title, String value, String subtitle, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 4),
              Icon(Icons.touch_app, color: color.withOpacity(0.5), size: 10),
            ]),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
            Text(subtitle, style: TextStyle(fontSize: 9, color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showDebtAdditions(String monthYear) {
    final year = int.parse(monthYear.split('-')[0]);
    final month = int.parse(monthYear.split('-')[1]);
    final startDate = DateTime(year, month, 1);
    final endDate = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    TransactionsListDialog.showDebtAdditions(context: context, startDate: startDate, endDate: endDate, periodTitle: monthYear);
  }

  void _showDebtPayments(String monthYear) {
    final year = int.parse(monthYear.split('-')[0]);
    final month = int.parse(monthYear.split('-')[1]);
    final startDate = DateTime(year, month, 1);
    final endDate = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    TransactionsListDialog.showDebtPayments(context: context, startDate: startDate, endDate: endDate, periodTitle: monthYear);
  }

  // كروت الفواتير الهيدر المتأقلمة ديناميكياً في سطر واحد
  Widget _buildCompactHeaderPill(String title, String value, IconData icon, String? badge, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.28), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    title,
                    style: TextStyle(fontSize: 11, color: Colors.grey[800], fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
                  child: Text(badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                ),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // كروت الفواتير الكبيرة والديناميكية التكيّفية
  Widget _buildDynamicGridCard(String title, String value, IconData icon, String? badge, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
          ),
        ],
      ),
    );
  }

  // كروت السطر الواحد للمعاملات اليدوية والإجماليات
  Widget _buildSingleRowPillItem(IconData icon, String title, String value, String subtitle, Color color, VoidCallback? onTap) {
    final card = Container(
      width: 175,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(Icons.touch_app, color: color.withOpacity(0.6), size: 12),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
          ),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      );
    }
    return card;
  }

  Widget _buildMiniMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 155,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthTrendChartCard(String monthYear, List<Map<String, dynamic>> dailySales, String selectedMetric, int? hoveredIdx) {
    double globalMaxMonetary = 1.0;
    for (var d in dailySales) {
      final s = (d['totalSales'] as num?)?.toDouble() ?? 0.0;
      final c = (d['totalCost'] as num?)?.toDouble() ?? 0.0;
      final p = (d['netProfit'] as num?)?.toDouble() ?? 0.0;
      if (s > globalMaxMonetary) globalMaxMonetary = s;
      if (c > globalMaxMonetary) globalMaxMonetary = c;
      if (p > globalMaxMonetary) globalMaxMonetary = p;
    }

    Color lineColor;
    Color areaColor;
    switch (selectedMetric) {
      case 'profit':
        lineColor = const Color(0xFF059669);
        areaColor = const Color(0xFF10B981);
        break;
      case 'cost':
        lineColor = const Color(0xFFDC2626);
        areaColor = const Color(0xFFEF4444);
        break;
      case 'invoices':
        lineColor = const Color(0xFF7C3AED);
        areaColor = const Color(0xFF8B5CF6);
        break;
      case 'compareAll':
        lineColor = const Color(0xFF4F46E5);
        areaColor = const Color(0xFF6366F1);
        break;
      case 'sales':
      default:
        lineColor = const Color(0xFF2563EB);
        areaColor = const Color(0xFF3B82F6);
        break;
    }

    int activeDayIndex = hoveredIdx ?? 0;
    if (activeDayIndex >= dailySales.length) activeDayIndex = math.max(0, dailySales.length - 1);

    final NumberFormat nf = NumberFormat('#,##0', 'en_US');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('تحليل التوجهات التفاعلي لأيام الشهر', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Row(
                children: [
                  _buildMetricPill(monthYear, 'sales', 'مبيعات', Icons.shopping_cart, selectedMetric),
                  const SizedBox(width: 4),
                  _buildMetricPill(monthYear, 'cost', 'تكلفة', Icons.money_off, selectedMetric),
                  const SizedBox(width: 4),
                  _buildMetricPill(monthYear, 'profit', 'ربح', Icons.trending_up, selectedMetric),
                  const SizedBox(width: 4),
                  _buildMetricPill(monthYear, 'invoices', 'فواتير', Icons.receipt, selectedMetric),
                  const SizedBox(width: 4),
                  _buildMetricPill(monthYear, 'compareAll', 'مقارنة', Icons.multiline_chart, selectedMetric),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: CurvedLineChartWidget(
              dailySales: dailySales,
              selectedMetric: selectedMetric,
              selectedDayIndex: activeDayIndex,
              lineColor: lineColor,
              areaColor: areaColor,
              globalMaxMonetary: globalMaxMonetary,
              onSelectDay: (idx) {
                if (idx != null) {
                  setState(() => _hoveredDayIndexPerMonth[monthYear] = idx);
                }
              },
              fmt: (v) => nf.format(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String monthYear, String metricKey, String label, IconData icon, String currentMetric) {
    final isSel = currentMetric == metricKey;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedMetricPerMonth[monthYear] = metricKey;
          _hoveredDayIndexPerMonth[monthYear] = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF3F51B5) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 11, color: isSel ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.w600, color: isSel ? Colors.white : const Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 📈 WIDGET & CUSTOM PAINTER FOR INVENTORY SCREEN
// =============================================================================

class CurvedLineChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> dailySales;
  final String selectedMetric;
  final int? selectedDayIndex;
  final Color lineColor;
  final Color areaColor;
  final double globalMaxMonetary;
  final Function(int?) onSelectDay;
  final String Function(num) fmt;

  const CurvedLineChartWidget({
    super.key,
    required this.dailySales,
    required this.selectedMetric,
    required this.selectedDayIndex,
    required this.lineColor,
    required this.areaColor,
    required this.globalMaxMonetary,
    required this.onSelectDay,
    required this.fmt,
  });

  void _handleTouch(Offset localPosition, double width, int totalDays) {
    const double marginX = 24.0;
    final double availW = width - (marginX * 2);
    final double dx = localPosition.dx - marginX;
    if (availW > 0 && totalDays > 0) {
      int clickedDayIdx = ((dx / availW) * (totalDays - 1)).round();
      if (clickedDayIdx < 0) clickedDayIdx = 0;
      if (clickedDayIdx >= totalDays) clickedDayIdx = totalDays - 1;
      onSelectDay(clickedDayIdx);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dailySales.isEmpty) {
      return const Center(child: Text('لا توجد بيانات لهذا الشهر'));
    }

    final salesValues = dailySales.map((d) => (d['totalSales'] as num?)?.toDouble() ?? 0.0).toList();
    final costValues = dailySales.map((d) => (d['totalCost'] as num?)?.toDouble() ?? 0.0).toList();
    final profitValues = dailySales.map((d) => (d['netProfit'] as num?)?.toDouble() ?? 0.0).toList();
    final invoiceValues = dailySales.map((d) => (d['invoiceCount'] as num?)?.toDouble() ?? 0.0).toList();
    final periodTitles = dailySales.map((d) => (d['dateFormatted'] ?? d['dayName'] ?? '').toString()).toList();

    List<double> selectedValues;
    if (selectedMetric == 'profit') {
      selectedValues = profitValues;
    } else if (selectedMetric == 'cost') {
      selectedValues = costValues;
    } else if (selectedMetric == 'invoices') {
      selectedValues = invoiceValues;
    } else {
      selectedValues = salesValues;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) => _handleTouch(event.localPosition, constraints.maxWidth, dailySales.length),
          child: GestureDetector(
            onTapDown: (details) => _handleTouch(details.localPosition, constraints.maxWidth, dailySales.length),
            onPanStart: (details) => _handleTouch(details.localPosition, constraints.maxWidth, dailySales.length),
            onPanUpdate: (details) => _handleTouch(details.localPosition, constraints.maxWidth, dailySales.length),
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: LineChartPainter(
                values: selectedValues,
                salesValues: salesValues,
                costValues: costValues,
                profitValues: profitValues,
                invoiceValues: invoiceValues,
                periodTitles: periodTitles,
                selectedMetric: selectedMetric,
                selectedIndex: selectedDayIndex,
                lineColor: lineColor,
                areaColor: areaColor,
                globalMaxMonetary: globalMaxMonetary,
                fmt: fmt,
              ),
            ),
          ),
        );
      },
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> values;
  final List<double> salesValues;
  final List<double> costValues;
  final List<double> profitValues;
  final List<double> invoiceValues;
  final List<String> periodTitles;
  final String selectedMetric;
  final int? selectedIndex;
  final Color lineColor;
  final Color areaColor;
  final double globalMaxMonetary;
  final String Function(num) fmt;

  LineChartPainter({
    required this.values,
    required this.salesValues,
    required this.costValues,
    required this.profitValues,
    required this.invoiceValues,
    required this.periodTitles,
    required this.selectedMetric,
    required this.selectedIndex,
    required this.lineColor,
    required this.areaColor,
    required this.globalMaxMonetary,
    required this.fmt,
  });

  List<Offset> _computePoints(List<double> dataList, double maxV, double marginX, double marginYTop, double chartW, double chartH) {
    final points = <Offset>[];
    for (int i = 0; i < dataList.length; i++) {
      final x = marginX + (i / (dataList.length - 1)) * chartW;
      final normY = maxV > 0 ? (dataList[i] / maxV).clamp(0.0, 1.0) : 0.0;
      final y = marginYTop + chartH - (normY * chartH);
      points.add(Offset(x, y));
    }
    return points;
  }

  void _drawCurve(Canvas canvas, Size size, List<Offset> points, Color color, {bool fillArea = false, double marginYBottom = 28.0, double marginYTop = 20.0, double chartH = 100}) {
    if (points.isEmpty) return;

    final path = Path();
    final areaPath = Path();

    path.moveTo(points[0].dx, points[0].dy);
    areaPath.moveTo(points[0].dx, size.height - marginYBottom);
    areaPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlP1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlP2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);

      path.cubicTo(controlP1.dx, controlP1.dy, controlP2.dx, controlP2.dy, p1.dx, p1.dy);
      areaPath.cubicTo(controlP1.dx, controlP1.dy, controlP2.dx, controlP2.dy, p1.dx, p1.dy);
    }

    areaPath.lineTo(points.last.dx, size.height - marginYBottom);
    areaPath.close();

    if (fillArea) {
      final areaGradient = Paint()
        ..shader = LinearGradient(
          colors: [
            color.withOpacity(0.30),
            color.withOpacity(0.01),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, marginYTop, size.width, chartH))
        ..style = PaintingStyle.fill;
      canvas.drawPath(areaPath, areaGradient);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double marginX = 24.0;
    final double marginYTop = 20.0;
    final double marginYBottom = 28.0;

    final double chartW = size.width - (marginX * 2);
    final double chartH = size.height - marginYTop - marginYBottom;

    double maxV;
    if (selectedMetric == 'compareAll') {
      maxV = globalMaxMonetary > 0 ? globalMaxMonetary : 1.0;
    } else {
      maxV = values.reduce(math.max);
      if (maxV == 0) maxV = 1.0;
    }

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = marginYTop + (chartH / 3) * i;
      canvas.drawLine(Offset(marginX, y), Offset(size.width - marginX, y), gridPaint);
    }

    final mainPoints = _computePoints(values, maxV, marginX, marginYTop, chartW, chartH);

    if (selectedMetric == 'compareAll') {
      final sPoints = _computePoints(salesValues, globalMaxMonetary, marginX, marginYTop, chartW, chartH);
      final cPoints = _computePoints(costValues, globalMaxMonetary, marginX, marginYTop, chartW, chartH);
      final pPoints = _computePoints(profitValues, globalMaxMonetary, marginX, marginYTop, chartW, chartH);

      _drawCurve(canvas, size, sPoints, const Color(0xFF2563EB), fillArea: true, marginYBottom: marginYBottom, marginYTop: marginYTop, chartH: chartH);
      _drawCurve(canvas, size, cPoints, const Color(0xFFDC2626), fillArea: false, marginYBottom: marginYBottom, marginYTop: marginYTop, chartH: chartH);
      _drawCurve(canvas, size, pPoints, const Color(0xFF059669), fillArea: false, marginYBottom: marginYBottom, marginYTop: marginYTop, chartH: chartH);
    } else {
      _drawCurve(canvas, size, mainPoints, lineColor, fillArea: true, marginYBottom: marginYBottom, marginYTop: marginYTop, chartH: chartH);
    }

    // Crosshair (Vertical & Horizontal Dashed Lines)
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < mainPoints.length) {
      final p = mainPoints[selectedIndex!];

      final crosshairPaint = Paint()
        ..color = lineColor.withOpacity(0.45)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      // Vertical Dashed Line
      double startY = marginYTop;
      while (startY < size.height - marginYBottom) {
        canvas.drawLine(
          Offset(p.dx, startY),
          Offset(p.dx, math.min(startY + 4, size.height - marginYBottom)),
          crosshairPaint,
        );
        startY += 8;
      }

      // Horizontal Dashed Line
      double startX = marginX;
      while (startX < size.width - marginX) {
        canvas.drawLine(
          Offset(startX, p.dy),
          Offset(math.min(startX + 4, size.width - marginX), p.dy),
          crosshairPaint,
        );
        startX += 8;
      }
    }

    // X-Axis Day Labels
    final textStyle = const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.w600);

    for (int i = 0; i < mainPoints.length; i++) {
      final dayNum = i + 1;
      final isSel = selectedIndex == i;

      bool showLabel = (dayNum == 1 || dayNum % 5 == 0 || dayNum == mainPoints.length || isSel);

      if (showLabel) {
        final p = mainPoints[i];
        final tp = TextPainter(
          text: TextSpan(
            text: '$dayNum',
            style: isSel ? textStyle.copyWith(color: lineColor, fontWeight: FontWeight.bold) : textStyle,
          ),
          textDirection: TextDirection.rtl,
        );
        tp.layout();
        tp.paint(canvas, Offset(p.dx - (tp.width / 2), size.height - marginYBottom + 6));
      }
    }

    // Tooltip & Selected Point Node
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < mainPoints.length) {
      final p = mainPoints[selectedIndex!];
      final i = selectedIndex!;

      final dotPaint = Paint()..color = lineColor;
      final whiteDotPaint = Paint()..color = Colors.white;

      canvas.drawCircle(p, 9, Paint()..color = lineColor.withOpacity(0.25));
      canvas.drawCircle(p, 5, dotPaint);
      canvas.drawCircle(p, 2.5, whiteDotPaint);

      final pTitle = periodTitles.length > i ? periodTitles[i] : 'اليوم ${i + 1}';
      final sVal = salesValues.length > i ? salesValues[i] : 0.0;
      final pVal = profitValues.length > i ? profitValues[i] : 0.0;
      final cVal = costValues.length > i ? costValues[i] : 0.0;
      final invVal = invoiceValues.length > i ? invoiceValues[i].toInt() : 0;

      final TextPainter tooltipPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '  $pTitle  \n',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: '• المبيعات: ${fmt(sVal)} د.ع\n',
              style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 9.5, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '• الأرباح: ${fmt(pVal)} د.ع\n',
              style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 9.5, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '• التكلفة: ${fmt(cVal)} د.ع\n',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 9.5, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '• الفواتير: $invVal فاتورة',
              style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 9.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        textDirection: TextDirection.rtl,
      );
      tooltipPainter.layout();

      final tooltipW = tooltipPainter.width + 16;
      final tooltipH = tooltipPainter.height + 12;

      double tooltipX = p.dx + 10;
      if (tooltipX + tooltipW > size.width - 8) {
        tooltipX = p.dx - tooltipW - 10;
      }

      double tooltipY = p.dy - (tooltipH / 2);
      if (tooltipY < marginYTop) tooltipY = marginYTop;
      if (tooltipY + tooltipH > size.height - marginYBottom) {
        tooltipY = size.height - marginYBottom - tooltipH;
      }

      final rRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipW, tooltipH),
        const Radius.circular(10),
      );

      canvas.drawRRect(
        rRect.shift(const Offset(0, 3)),
        Paint()..color = Colors.black.withOpacity(0.25),
      );

      canvas.drawRRect(
        rRect,
        Paint()..color = const Color(0xFF0F172A),
      );

      canvas.drawRRect(
        rRect,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      tooltipPainter.paint(canvas, Offset(tooltipX + 8, tooltipY + 6));
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.selectedMetric != selectedMetric ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.globalMaxMonetary != globalMaxMonetary;
  }
}
