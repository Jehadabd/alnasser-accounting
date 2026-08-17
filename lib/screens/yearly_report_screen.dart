// screens/yearly_report_screen.dart
// شاشة التقرير السنوي التفاعلية والشاملة
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' as intl;
import '../services/reports_service.dart';

class YearlyReportScreen extends StatefulWidget {
  const YearlyReportScreen({super.key});

  @override
  State<YearlyReportScreen> createState() => _YearlyReportScreenState();
}

class _YearlyReportScreenState extends State<YearlyReportScreen>
    with SingleTickerProviderStateMixin {
  final ReportsService _reportsService = ReportsService();
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  bool _onlyThisDevice = false;
  late int _selectedYear;
  int _activeTabIndex = 0; // 0: Overview, 1: Monthly Chart, 2: Categories, 3: Products, 4: Customers

  // فلاتر البحث والمخطط البياني
  String _productSearchQuery = '';
  String _customerSearchQuery = '';
  int? _hoveredMonthIndex;
  String _selectedChartMetric = 'sales'; // 'sales', 'profit', 'cost', 'invoices'

  final intl.NumberFormat _nf = intl.NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  String _getArabicMonthName(int m) {
    const names = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    if (m >= 1 && m <= 12) return names[m - 1];
    return 'شهر $m';
  }

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      _reportsService.filterOnlyThisDevice = _onlyThisDevice;
      final data = await _reportsService.getYearlyReport(year: _selectedYear);
      if (mounted) {
        setState(() {
          _reportData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل التقرير السنوي: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showYearPickerModal() {
    final currentYear = DateTime.now().year;
    final years = List<int>.generate(15, (index) => currentYear - index);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'اختر السنة المالية',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: years.length,
                  itemBuilder: (context, index) {
                    final year = years[index];
                    final isSelected = year == _selectedYear;
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor: isSelected ? const Color(0xFF4F46E5).withOpacity(0.1) : null,
                      leading: Icon(
                        Icons.calendar_today,
                        color: isSelected ? const Color(0xFF4F46E5) : Colors.grey[500],
                      ),
                      title: Text(
                        '$year',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF334155),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Color(0xFF4F46E5))
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        if (year != _selectedYear) {
                          setState(() => _selectedYear = year);
                          _loadReport();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Modern Slate background
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1E1B4B), // Premium Dark Indigo
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const FaIcon(FontAwesomeIcons.chartLine, color: Colors.amberAccent, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'التقرير السنوي الشامل',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        actions: [
          // Filter Device Selector Pill
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _onlyThisDevice = !_onlyThisDevice;
                  _loadReport();
                });
              },
              child: Row(
                children: [
                  Icon(
                    _onlyThisDevice ? Icons.laptop : Icons.hub,
                    color: _onlyThisDevice ? Colors.amberAccent : Colors.tealAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _onlyThisDevice ? 'هذا الجهاز' : 'كل الأجهزة',
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadReport,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // Header Controls Banner (Year Stepper & Quick Action)
          _buildTopBanner(),

          // Interactive Tab Switcher
          _buildTabBar(),

          // Main View Content
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _reportData == null
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadReport,
                        color: const Color(0xFF4F46E5),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _buildActiveTabContent(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // Header Banner with Gradient, Year Picker and Metrics Quick Bar
  Widget _buildTopBanner() {
    final invoiceCount = _reportData != null
        ? ((_reportData!['summary'] as Map<String, dynamic>?)?['invoiceCount'] as num?)?.toInt() ?? 0
        : 0;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Year Navigator Stepper
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() => _selectedYear--);
                      _loadReport();
                    },
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70, size: 18),
                    tooltip: 'السنة السابقة',
                  ),
                  GestureDetector(
                    onTap: _showYearPickerModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Text(
                            '$_selectedYear',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.amberAccent, size: 22),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _selectedYear < DateTime.now().year
                        ? () {
                            setState(() => _selectedYear++);
                            _loadReport();
                          }
                        : null,
                    icon: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: _selectedYear < DateTime.now().year ? Colors.white70 : Colors.white24,
                      size: 18,
                    ),
                    tooltip: 'السنة القادمة',
                  ),
                ],
              ),

              // Status badge / Quick Summary Pill
              if (_reportData != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF34D399).withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insights_rounded, color: Color(0xFF34D399), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'إجمالي ${_fmt(invoiceCount)} فاتورة',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Interactive Tab Bar
  Widget _buildTabBar() {
    final tabs = [
      {'title': 'ملخص السنة', 'icon': Icons.dashboard_customize_rounded},
      {'title': 'المبيعات الشهرية', 'icon': Icons.show_chart_rounded},
      {'title': 'التصنيفات', 'icon': Icons.pie_chart_rounded},
      {'title': 'أفضل المنتجات', 'icon': Icons.shopping_bag_rounded},
      {'title': 'أفضل العملاء', 'icon': Icons.people_alt_rounded},
    ];

    return Container(
      color: Colors.white,
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _activeTabIndex == index;
          final tab = tabs[index];
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: InkWell(
              onTap: () => setState(() => _activeTabIndex = index),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      tab['icon'] as IconData,
                      size: 17,
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tab['title'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Active Tab View Dispatcher
  Widget _buildActiveTabContent() {
    switch (_activeTabIndex) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildMonthlyTab();
      case 2:
        return _buildCategoryTab();
      case 3:
        return _buildProductsTab();
      case 4:
        return _buildCustomersTab();
      default:
        return _buildOverviewTab();
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 1: OVERVIEW TAB (Hero Cards, Single Row Small Metrics, YoY Comparison)
  // ---------------------------------------------------------------------------
  Widget _buildOverviewTab() {
    final summary = _reportData!['summary'] as Map<String, dynamic>;
    final profitPercent = (_reportData!['profitPercent'] as num?)?.toDouble() ?? 0.0;
    final totalReturns = (_reportData!['totalReturns'] as num?)?.toDouble() ?? 0.0;
    final newCustomers = _reportData!['newCustomersCount'] as int? ?? 0;
    final invoiceCount = (summary['invoiceCount'] as num?)?.toInt() ?? 0;
    final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0.0;
    final netProfit = (summary['netProfit'] as num?)?.toDouble() ?? 0.0;
    final totalCost = (summary['totalCost'] as num?)?.toDouble() ?? 0.0;

    final avgInvoiceValue = invoiceCount > 0 ? (totalSales / invoiceCount) : 0.0;
    final avgDailySales = totalSales / 365.0;

    // Highlight Month
    final monthlySales = (_reportData!['monthlySales'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    Map<String, dynamic>? bestSalesMonth;
    Map<String, dynamic>? bestProfitMonth;
    double maxSales = -1;
    double maxProfit = -9999999;

    for (var m in monthlySales) {
      final s = (m['totalSales'] as num?)?.toDouble() ?? 0;
      final p = (m['netProfit'] as num?)?.toDouble() ?? 0;
      if (s > maxSales) {
        maxSales = s;
        bestSalesMonth = m;
      }
      if (p > maxProfit) {
        maxProfit = p;
        bestProfitMonth = m;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          _buildSectionHeader('مؤشرات الأداء الرئيسية (KPIs)', Icons.analytics_outlined),
          const SizedBox(height: 12),

          // Primary Gradient Cards (Sales & Profit)
          Row(
            children: [
              Expanded(
                child: _buildHeroGradientCard(
                  title: 'إجمالي المبيعات',
                  value: '${_fmt(totalSales)} د.ع',
                  subtitle: 'المعدل اليومي: ${_fmt(avgDailySales)} د.ع',
                  gradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  icon: Icons.point_of_sale_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeroGradientCard(
                  title: 'صافي الأرباح',
                  value: '${_fmt(netProfit)} د.ع',
                  subtitle: 'هامش الربح: ${profitPercent.toStringAsFixed(1)}%',
                  gradient: const [Color(0xFF059669), Color(0xFF047857)],
                  icon: Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Single Horizontal Row of Small Metrics Cards (السطر الموحد للكروت الصغيرة)
          LayoutBuilder(
            builder: (context, constraints) {
              final tiles = [
                _buildMetricTile(
                  title: 'التكلفة الإجمالية',
                  value: '${_fmt(totalCost)} د.ع',
                  icon: Icons.money_off_rounded,
                  color: const Color(0xFFDC2626),
                  bgTint: const Color(0xFFFEF2F2),
                ),
                _buildMetricTile(
                  title: 'إجمالي المرتجعات',
                  value: '${_fmt(totalReturns)} د.ع',
                  icon: Icons.replay_rounded,
                  color: const Color(0xFFD97706),
                  bgTint: const Color(0xFFFFFBEB),
                ),
                _buildMetricTile(
                  title: 'عدد الفواتير',
                  value: '$invoiceCount فاتورة',
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF4F46E5),
                  bgTint: const Color(0xFFEEF2FF),
                ),
                _buildMetricTile(
                  title: 'متوسط قيمة الفاتورة',
                  value: '${_fmt(avgInvoiceValue)} د.ع',
                  icon: Icons.calculate_rounded,
                  color: const Color(0xFF0891B2),
                  bgTint: const Color(0xFFECFEFF),
                ),
                _buildMetricTile(
                  title: 'العملاء الجدد',
                  value: '$newCustomers عميل',
                  icon: Icons.person_add_alt_1_rounded,
                  color: const Color(0xFF7C3AED),
                  bgTint: const Color(0xFFF5F3FF),
                ),
                _buildMetricTile(
                  title: 'نسبة الربحية للتكلفة',
                  value: totalCost > 0 ? '${((netProfit / totalCost) * 100).toStringAsFixed(1)}%' : '0%',
                  icon: Icons.pie_chart_outline_rounded,
                  color: const Color(0xFF059669),
                  bgTint: const Color(0xFFECFDF5),
                ),
              ];

              if (constraints.maxWidth > 850) {
                // سطر موحد أفقي متكامل لكافة المربعات الصغيرة
                return Row(
                  children: tiles.map((t) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(height: 84, child: t),
                    ),
                  )).toList(),
                );
              } else {
                return GridView.count(
                  crossAxisCount: constraints.maxWidth > 550 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.2,
                  children: tiles,
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // Year-Over-Year Comparison Section
          _buildSectionHeader('مقارنة النمو مع السنة الماضية', Icons.compare_arrows_rounded),
          const SizedBox(height: 12),
          _buildYoYComparisonCard(),
          const SizedBox(height: 24),

          // Peak Highlights (أفضل الأسباب والشؤون)
          _buildSectionHeader('أبرز الإنجازات الشهرية', Icons.star_rounded),
          const SizedBox(height: 12),
          Row(
            children: [
              if (bestSalesMonth != null) ...[
                Expanded(
                  child: _buildHighlightBadgeCard(
                    badgeTitle: 'الشهر الأعلى مبيعات',
                    monthName: bestSalesMonth['monthName'] as String,
                    value: '${_fmt(bestSalesMonth['totalSales'] ?? 0)} د.ع',
                    icon: Icons.emoji_events_rounded,
                    color: Colors.amber[800]!,
                    bgColor: Colors.amber[50]!,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              if (bestProfitMonth != null) ...[
                Expanded(
                  child: _buildHighlightBadgeCard(
                    badgeTitle: 'الشهر الأعلى أرباحاً',
                    monthName: bestProfitMonth['monthName'] as String,
                    value: '${_fmt(bestProfitMonth['netProfit'] ?? 0)} د.ع',
                    icon: Icons.workspace_premium_rounded,
                    color: const Color(0xFF047857),
                    bgColor: const Color(0xFFECFDF5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),

          // Payment Methods Breakdown
          _buildSectionHeader('توزيع طرق الدفع والسداد', Icons.payments_rounded),
          const SizedBox(height: 12),
          _buildPaymentBreakdownCard(),
        ],
      ),
    );
  }

  String _timeGranularity = 'monthly'; // 'monthly', 'weekly', 'daily'
  int _selectedDailyMonth = DateTime.now().month;
  List<Map<String, dynamic>> _dailySalesData = [];
  bool _isLoadingDaily = false;

  Future<void> _loadDailyDataIfNeeded() async {
    if (_timeGranularity == 'daily') {
      setState(() => _isLoadingDaily = true);
      try {
        final data = await _reportsService.getDailySalesForMonth(
          year: _selectedYear,
          month: _selectedDailyMonth,
        );
        if (mounted) {
          setState(() {
            _dailySalesData = data;
            _isLoadingDaily = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingDaily = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 2: MONTHLY TRENDS & CURVED LINE CHART TAB (تحليل التوجهات الشهرية للسنة)
  // ---------------------------------------------------------------------------
  Widget _buildMonthlyTab() {
    final monthlySales = (_reportData!['monthlySales'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Calculate Global Max Monetary Value for proportional scaling in compareAll mode
    double globalMaxMonetary = 1.0;
    for (var m in monthlySales) {
      final s = (m['totalSales'] as num?)?.toDouble() ?? 0.0;
      final c = (m['totalCost'] as num?)?.toDouble() ?? 0.0;
      final p = (m['netProfit'] as num?)?.toDouble() ?? 0.0;
      if (s > globalMaxMonetary) globalMaxMonetary = s;
      if (c > globalMaxMonetary) globalMaxMonetary = c;
      if (p > globalMaxMonetary) globalMaxMonetary = p;
    }

    // Colors per metric
    Color lineColor;
    Color areaColor;
    switch (_selectedChartMetric) {
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

    // If no month is selected yet, default to highest sales month or current month
    int activeMonthIndex = _hoveredMonthIndex ?? 7; // Default to Month 8 (August) if available
    if (activeMonthIndex >= monthlySales.length) activeMonthIndex = 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('تحليل التوجهات الشهرية لسنة $_selectedYear', Icons.show_chart_rounded),
          const SizedBox(height: 12),

          // Metric Selector Switcher Buttons + Compare All Mode
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                _buildChartMetricButton('sales', 'المبيعات', Icons.shopping_cart),
                _buildChartMetricButton('cost', 'التكلفة', Icons.money_off),
                _buildChartMetricButton('profit', 'الأرباح', Icons.trending_up),
                _buildChartMetricButton('invoices', 'الفواتير', Icons.receipt),
                _buildChartMetricButton('compareAll', 'مقارنة المنحنيات', Icons.multiline_chart),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Real Curved Line & Area Chart Container
          Container(
            height: 290,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                if (_selectedChartMetric == 'compareAll') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem('المبيعات', const Color(0xFF2563EB)),
                      const SizedBox(width: 16),
                      _buildLegendItem('التكلفة', const Color(0xFFDC2626)),
                      const SizedBox(width: 16),
                      _buildLegendItem('الأرباح', const Color(0xFF059669)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child: CurvedLineChartWidget(
                    monthlySales: monthlySales,
                    dailySales: (_reportData!['dailySales'] as List?)?.cast<Map<String, dynamic>>() ?? [],
                    selectedMetric: _selectedChartMetric,
                    selectedMonthIndex: activeMonthIndex,
                    lineColor: lineColor,
                    areaColor: areaColor,
                    globalMaxMonetary: globalMaxMonetary,
                    onSelectMonth: (idx) {
                      if (idx != null) {
                        setState(() {
                          _hoveredMonthIndex = idx;
                        });
                      }
                    },
                    fmt: _fmt,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Selected Month Highlight Spotlight Banner (دائمة الظهور لشهر المؤشر)
          if (monthlySales.isNotEmpty && activeMonthIndex < monthlySales.length) ...[
            Builder(builder: (context) {
              final selM = monthlySales[activeMonthIndex];
              final sSales = (selM['totalSales'] as num?)?.toDouble() ?? 0;
              final sProfit = (selM['netProfit'] as num?)?.toDouble() ?? 0;
              final sCost = (selM['totalCost'] as num?)?.toDouble() ?? 0;
              final sInv = (selM['invoiceCount'] as num?)?.toInt() ?? 0;
              final sMargin = sSales > 0 ? (sProfit / sSales) * 100 : 0.0;
              final monthName = selM['monthName'] as String? ?? 'شهر ${activeMonthIndex + 1}';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF818CF8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.stars_rounded, color: Color(0xFF4F46E5), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'تفاصيل $monthName',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1B4B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text('المبيعات: ${_fmt(sSales)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
                        Expanded(child: Text('الأرباح: ${_fmt(sProfit)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: Text('التكلفة: ${_fmt(sCost)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)))),
                        Expanded(child: Text('الفواتير: $sInv (نسبة الربح ${sMargin.toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)))),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // Detailed Breakdown List Cards
          _buildSectionHeader('جدول التفاصيل الشهرية السنوية', Icons.table_chart_rounded),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: monthlySales.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final month = monthlySales[index];
              final monthName = month['monthName'] as String;
              final sales = (month['totalSales'] as num?)?.toDouble() ?? 0;
              final profit = (month['netProfit'] as num?)?.toDouble() ?? 0;
              final cost = (month['totalCost'] as num?)?.toDouble() ?? 0;
              final invCount = (month['invoiceCount'] as num?)?.toInt() ?? 0;
              final margin = sales > 0 ? (profit / sales) * 100 : 0.0;
              final isSelected = activeMonthIndex == index;

              return GestureDetector(
                onTap: () => setState(() => _hoveredMonthIndex = isSelected ? null : index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${month['month']}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : const Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  monthName,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$invCount فاتورة',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _selectedChartMetric == 'invoices' ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'مبيعات: ${_fmt(sales)} د.ع',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: const Color(0xFF2563EB),
                                    fontWeight: _selectedChartMetric == 'sales' ? FontWeight.w900 : FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'أرباح: ${_fmt(profit)} د.ع (${margin.toStringAsFixed(1)}%)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: const Color(0xFF059669),
                                    fontWeight: _selectedChartMetric == 'profit' ? FontWeight.w900 : FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'التكلفة: ${_fmt(cost)} د.ع',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: const Color(0xFFDC2626),
                                    fontWeight: _selectedChartMetric == 'cost' ? FontWeight.w900 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChartMetricButton(String key, String label, IconData icon) {
    final isSelected = _selectedChartMetric == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedChartMetric = key;
          _hoveredMonthIndex = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? Colors.white : const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGranularityButton(String key, String label) {
    final isSelected = _timeGranularity == key;
    return GestureDetector(
      onTap: () {
        if (_timeGranularity != key) {
          setState(() {
            _timeGranularity = key;
            _hoveredMonthIndex = null;
          });
          _loadDailyDataIfNeeded();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: CATEGORY ANALYSIS TAB
  // ---------------------------------------------------------------------------
  Widget _buildCategoryTab() {
    final categories = (_reportData!['categoryBreakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final summary = _reportData!['summary'] as Map<String, dynamic>;
    final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 1.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('توزيع المبيعات حسب تصنيف البضاعة', Icons.pie_chart_rounded),
          const SizedBox(height: 12),

          if (categories.isEmpty)
            _buildEmptySection('لا توجد بيانات تصنيفات مسجلة لهذه السنة')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final catName = cat['category_name'] as String;
                final sales = (cat['total_sales'] as num?)?.toDouble() ?? 0.0;
                final count = (cat['invoice_count'] as num?)?.toInt() ?? 0;
                final qty = (cat['total_quantity'] as num?)?.toDouble() ?? 0.0;
                final percentage = totalSales > 0 ? (sales / totalSales) * 100 : 0.0;

                final colors = [
                  const Color(0xFF4F46E5),
                  const Color(0xFF059669),
                  const Color(0xFFD97706),
                  const Color(0xFF2563EB),
                  const Color(0xFF7C3AED),
                  const Color(0xFF0891B2),
                  const Color(0xFFDC2626),
                ];
                final color = colors[index % colors.length];

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.category_rounded, color: color, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                catName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${percentage.toStringAsFixed(1)}%',
                              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (percentage / 100).clamp(0.01, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.grey[100],
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('المبيعات: ${_fmt(sales)} د.ع', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                          Text('الكمية: ${_fmt(qty)}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          Text('$count فاتورة', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: TOP PRODUCTS TAB (With Search Filter)
  // ---------------------------------------------------------------------------
  Widget _buildProductsTab() {
    final topProducts = (_reportData!['topProducts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final filtered = topProducts.where((p) {
      final name = (p['product_name'] ?? '').toString().toLowerCase();
      return name.contains(_productSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Search Input Bar
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: TextField(
            onChanged: (val) => setState(() => _productSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'ابحث في قائمة المنتجات الأكثر مبيعاً...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
              fillColor: const Color(0xFFF1F5F9),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? _buildEmptySection('لا توجد منتجات تطابق البحث')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final name = item['product_name']?.toString() ?? 'منتج غير معروف';
                    final sales = (item['total_sales'] as num?)?.toDouble() ?? 0.0;
                    final qty = (item['total_quantity'] as num?)?.toDouble() ?? 0.0;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: index < 3 ? const Color(0xFFF59E0B).withOpacity(0.15) : const Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: index < 3 ? const Color(0xFFD97706) : const Color(0xFF4F46E5),
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
                                  name,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'الكمية المباعة: ${_fmt(qty)}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${_fmt(sales)} د.ع',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 5: TOP CUSTOMERS TAB (With Search Filter)
  // ---------------------------------------------------------------------------
  Widget _buildCustomersTab() {
    final topCustomers = (_reportData!['topCustomers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final filtered = topCustomers.where((c) {
      final name = (c['customer_name'] ?? '').toString().toLowerCase();
      return name.contains(_customerSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Search Input Bar
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: TextField(
            onChanged: (val) => setState(() => _customerSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'ابحث في قائمة أكثر العملاء شراءً...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
              fillColor: const Color(0xFFF1F5F9),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? _buildEmptySection('لا يوجد عملاء يطابقون البحث')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final name = item['customer_name']?.toString() ?? 'عميل غير معروف';
                    final purchases = (item['total_purchases'] as num?)?.toDouble() ?? 0.0;
                    final count = (item['invoice_count'] as num?)?.toInt() ?? 0;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: index < 3 ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFFECFDF5),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: index < 3 ? const Color(0xFF047857) : const Color(0xFF059669),
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
                                  name,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$count فواتير شراء',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${_fmt(purchases)} د.ع',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // HELPER COMPONENTS & CARDS
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroGradientCard({
    required String title,
    required String value,
    required String subtitle,
    required List<Color> gradient,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              Icon(icon, color: Colors.white70, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgTint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bgTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYoYComparisonCard() {
    final comparison = _reportData!['comparison'] as Map<String, dynamic>? ?? {};
    final changes = comparison['changes'] as Map<String, dynamic>? ?? {};

    final salesChange = (changes['salesChange'] as num?)?.toDouble() ?? 0.0;
    final profitChange = (changes['profitChange'] as num?)?.toDouble() ?? 0.0;
    final countChange = (changes['invoiceCountChange'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _buildYoYRow('المبيعات السنوية', salesChange),
          const Divider(height: 20),
          _buildYoYRow('صافي الأرباح', profitChange),
          const Divider(height: 20),
          _buildYoYRow('عدد الفواتير', countChange),
        ],
      ),
    );
  }

  Widget _buildYoYRow(String title, double percent) {
    final isPositive = percent >= 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 16,
                color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 4),
              Text(
                '${percent.abs().toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightBadgeCard({
    required String badgeTitle,
    required String monthName,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  badgeTitle,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            monthName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdownCard() {
    final payments = (_reportData!['paymentBreakdown'] as Map?)?.cast<String, double>() ?? {};
    final total = payments.values.fold(0.0, (sum, v) => sum + v);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: payments.entries.map((e) {
          final pName = e.key;
          final val = e.value;
          final pct = total > 0 ? (val / total) * 100 : 0.0;
          final isCash = pName.contains('نقد');

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  isCash ? Icons.money_rounded : Icons.credit_card_rounded,
                  color: isCash ? const Color(0xFF059669) : const Color(0xFFD97706),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                ),
                Text(
                  '${_fmt(val)} د.ع',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptySection(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.inbox_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF4F46E5)),
          SizedBox(height: 16),
          Text(
            'جاري تحليل البيانات السنوية وحساب المؤشرات...',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.calendar_month_outlined, size: 64, color: Color(0xFF94A3B8)),
          const SizedBox(height: 16),
          Text(
            'لا توجد فواتير أو مبيعات مسجلة لسنة $_selectedYear',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 📈 WIDGET & CUSTOM PAINTER: INTERACTIVE CURVED LINE / AREA CHART
// =============================================================================

class CurvedLineChartWidget extends StatefulWidget {
  final List<Map<String, dynamic>> monthlySales;
  final List<Map<String, dynamic>> dailySales;
  final String selectedMetric;
  final int? selectedMonthIndex;
  final Color lineColor;
  final Color areaColor;
  final double globalMaxMonetary;
  final Function(int?) onSelectMonth;
  final String Function(num) fmt;

  const CurvedLineChartWidget({
    super.key,
    required this.monthlySales,
    required this.dailySales,
    required this.selectedMetric,
    required this.selectedMonthIndex,
    required this.lineColor,
    required this.areaColor,
    required this.globalMaxMonetary,
    required this.onSelectMonth,
    required this.fmt,
  });

  @override
  State<CurvedLineChartWidget> createState() => _CurvedLineChartWidgetState();
}

class _CurvedLineChartWidgetState extends State<CurvedLineChartWidget> {
  int? _hoveredDayIndex;

  void _handleTouch(Offset localPosition, double width, int totalDays) {
    const double marginX = 24.0;
    final double availW = width - (marginX * 2);
    final double dx = localPosition.dx - marginX;
    if (availW > 0 && totalDays > 0) {
      int clickedDayIdx = ((dx / availW) * (totalDays - 1)).round();
      if (clickedDayIdx < 0) clickedDayIdx = 0;
      if (clickedDayIdx >= totalDays) clickedDayIdx = totalDays - 1;

      setState(() {
        _hoveredDayIndex = clickedDayIdx;
      });

      // Update parent month index based on hovered day's month
      if (widget.dailySales.length > clickedDayIdx) {
        final mNum = (widget.dailySales[clickedDayIdx]['monthNum'] as int?) ?? 1;
        widget.onSelectMonth(mNum - 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataset = widget.dailySales.isNotEmpty ? widget.dailySales : widget.monthlySales;

    if (dataset.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    final salesValues = dataset.map((m) => (m['totalSales'] as num?)?.toDouble() ?? 0.0).toList();
    final costValues = dataset.map((m) => (m['totalCost'] as num?)?.toDouble() ?? 0.0).toList();
    final profitValues = dataset.map((m) => (m['netProfit'] as num?)?.toDouble() ?? 0.0).toList();
    final invoiceValues = dataset.map((m) => (m['invoiceCount'] as num?)?.toDouble() ?? 0.0).toList();
    final periodTitles = dataset.map((m) => (m['dateFormatted'] ?? m['monthName'] ?? '').toString()).toList();

    List<double> selectedValues;
    if (widget.selectedMetric == 'profit') {
      selectedValues = profitValues;
    } else if (widget.selectedMetric == 'cost') {
      selectedValues = costValues;
    } else if (widget.selectedMetric == 'invoices') {
      selectedValues = invoiceValues;
    } else {
      selectedValues = salesValues;
    }

    // Default selected day index to 15th August if available
    int activeDayIndex = _hoveredDayIndex ?? 226; // ~15 August
    if (activeDayIndex >= dataset.length) activeDayIndex = math.max(0, dataset.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) => _handleTouch(event.localPosition, constraints.maxWidth, dataset.length),
          child: GestureDetector(
            onTapDown: (details) => _handleTouch(details.localPosition, constraints.maxWidth, dataset.length),
            onPanStart: (details) => _handleTouch(details.localPosition, constraints.maxWidth, dataset.length),
            onPanUpdate: (details) => _handleTouch(details.localPosition, constraints.maxWidth, dataset.length),
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: LineChartPainter(
                values: selectedValues,
                salesValues: salesValues,
                costValues: costValues,
                profitValues: profitValues,
                invoiceValues: invoiceValues,
                periodTitles: periodTitles,
                dataset: dataset,
                selectedMetric: widget.selectedMetric,
                selectedIndex: activeDayIndex,
                lineColor: widget.lineColor,
                areaColor: widget.areaColor,
                globalMaxMonetary: widget.globalMaxMonetary,
                fmt: widget.fmt,
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
  final List<Map<String, dynamic>> dataset;
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
    required this.dataset,
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

  void _drawCurve(Canvas canvas, Size size, List<Offset> points, Color color, {bool fillArea = false, double marginYBottom = 32.0, double marginYTop = 36.0, double chartH = 100}) {
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
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double marginX = 24.0;
    final double marginYTop = 36.0;
    final double marginYBottom = 32.0;

    final double chartW = size.width - (marginX * 2);
    final double chartH = size.height - marginYTop - marginYBottom;

    double maxV;
    if (selectedMetric == 'compareAll') {
      maxV = globalMaxMonetary > 0 ? globalMaxMonetary : 1.0;
    } else {
      maxV = values.reduce(math.max);
      if (maxV == 0) maxV = 1.0;
    }

    // 1. Draw horizontal Y-Grid Lines (3 grid lines)
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1;

    for (int i = 0; i <= 3; i++) {
      final y = marginYTop + (chartH / 3) * i;
      canvas.drawLine(Offset(marginX, y), Offset(size.width - marginX, y), gridPaint);
    }

    // 2. Compute and Draw Curves
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

    // 3. Draw Crosshair
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < mainPoints.length) {
      final p = mainPoints[selectedIndex!];

      final crosshairPaint = Paint()
        ..color = lineColor.withOpacity(0.4)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      double startY = marginYTop;
      while (startY < size.height - marginYBottom) {
        canvas.drawLine(
          Offset(p.dx, startY),
          Offset(p.dx, math.min(startY + 4, size.height - marginYBottom)),
          crosshairPaint,
        );
        startY += 8;
      }
    }

    // 4. Draw Month Labels (ش1 .. ش12) at Month Boundaries
    final textStyle = const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600);

    for (int m = 1; m <= 12; m++) {
      int firstDayIdx = 0;
      for (int i = 0; i < dataset.length; i++) {
        if ((dataset[i]['monthNum'] as int?) == m) {
          firstDayIdx = i;
          break;
        }
      }

      if (firstDayIdx < mainPoints.length) {
        final p = mainPoints[firstDayIdx];
        final tp = TextPainter(
          text: TextSpan(text: 'ش$m', style: textStyle),
          textDirection: TextDirection.rtl,
        );
        tp.layout();
        tp.paint(canvas, Offset(p.dx - (tp.width / 2), size.height - marginYBottom + 8));
      }
    }

    // 5. Draw Selected Day Node & Rich Tooltip Box
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < mainPoints.length) {
      final p = mainPoints[selectedIndex!];
      final i = selectedIndex!;

      final dotPaint = Paint()..color = lineColor;
      final whiteDotPaint = Paint()..color = Colors.white;

      // Outer Glowing Aura Ring
      canvas.drawCircle(p, 10, Paint()..color = lineColor.withOpacity(0.25));
      canvas.drawCircle(p, 6, dotPaint);
      canvas.drawCircle(p, 3, whiteDotPaint);

      // Build Rich Tooltip Window
      final pTitle = periodTitles.length > i ? periodTitles[i] : 'اليوم $i';
      final sVal = salesValues.length > i ? salesValues[i] : 0.0;
      final pVal = profitValues.length > i ? profitValues[i] : 0.0;
      final cVal = costValues.length > i ? costValues[i] : 0.0;
      final invVal = invoiceValues.length > i ? invoiceValues[i].toInt() : 0;

      final TextPainter tooltipPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '  $pTitle  \n',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: '• المبيعات: ${fmt(sVal)} د.ع\n',
              style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 10, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '• الأرباح: ${fmt(pVal)} د.ع\n',
              style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 10, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '• التكلفة: ${fmt(cVal)} د.ع\n',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 10, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: '• الفواتير: $invVal فاتورة',
              style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        textDirection: TextDirection.rtl,
      );
      tooltipPainter.layout();

      final tooltipW = tooltipPainter.width + 20;
      final tooltipH = tooltipPainter.height + 14;

      // Smart Overflow Box Positioning
      double tooltipX = p.dx + 12;
      if (tooltipX + tooltipW > size.width - 8) {
        tooltipX = p.dx - tooltipW - 12;
      }

      double tooltipY = p.dy - (tooltipH / 2);
      if (tooltipY < marginYTop) tooltipY = marginYTop;
      if (tooltipY + tooltipH > size.height - marginYBottom) {
        tooltipY = size.height - marginYBottom - tooltipH;
      }

      // Draw Dark Slate Tooltip Container
      final rRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipW, tooltipH),
        const Radius.circular(12),
      );

      canvas.drawRRect(
        rRect.shift(const Offset(0, 4)),
        Paint()..color = Colors.black.withOpacity(0.3),
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
          ..strokeWidth = 1.5,
      );

      tooltipPainter.paint(canvas, Offset(tooltipX + 10, tooltipY + 7));
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
