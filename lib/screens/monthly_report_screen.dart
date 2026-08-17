// screens/monthly_report_screen.dart
// شاشة التقرير الشهري التفاعلية والشاملة
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' as intl;
import '../services/reports_service.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  final ReportsService _reportsService = ReportsService();
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  bool _onlyThisDevice = false;
  late int _selectedYear;
  late int _selectedMonth;

  int? _hoveredDayIndex;
  String _selectedChartMetric = 'sales'; // 'sales', 'profit', 'cost', 'invoices', 'compareAll'

  final intl.NumberFormat _nf = intl.NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  String _getMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return 'شهر $month';
  }

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
      _reportsService.filterOnlyThisDevice = _onlyThisDevice;
      final data = await _reportsService.getMonthlyDetailedReport(
        year: _selectedYear,
        month: _selectedMonth,
      );

      setState(() {
        _reportData = data;
        _isLoading = false;
        _hoveredDayIndex = null;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل التقرير الشهري: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1E1B4B),
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
              child: const FaIcon(FontAwesomeIcons.chartPie, color: Colors.amberAccent, size: 18),
            ),
            const SizedBox(width: 12),
            const Text(
              'التقرير الشهري المفصل',
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
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadReport,
          ),
        ],
      ),
      body: Column(
        children: [
          // Month Selector Header Stepper
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1B4B),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${_getMonthName(_selectedMonth)} $_selectedYear',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                  onPressed: () {
                    final now = DateTime.now();
                    if (_selectedYear < now.year || (_selectedYear == now.year && _selectedMonth < now.month)) {
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

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
                : _reportData == null
                    ? const Center(child: Text('لا توجد بيانات لهذا الشهر'))
                    : RefreshIndicator(
                        onRefresh: _loadReport,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Single-row Compact Secondary Metrics
                              _buildMetricsRow(),
                              const SizedBox(height: 16),

                              // Interactive Daily Curved Line Chart
                              _buildDailyTrendChartCard(),
                              const SizedBox(height: 16),

                              // Spotlight Banner for Selected Day
                              _buildDaySpotlightBanner(),
                              const SizedBox(height: 16),

                              // Month Comparison Card
                              _buildSectionHeader('مقارنة مع الشهر السابق', Icons.compare_arrows_rounded),
                              const SizedBox(height: 10),
                              _buildComparisonCard(),
                              const SizedBox(height: 20),

                              // Top 10 Products List
                              _buildSectionHeader('أفضل 10 منتجات مباعة في الشهر', Icons.star_rounded),
                              const SizedBox(height: 10),
                              _buildTopProductsList(),
                              const SizedBox(height: 20),

                              // Top 10 Customers List
                              _buildSectionHeader('أفضل 10 عملاء للشهر', Icons.person_rounded),
                              const SizedBox(height: 10),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4F46E5), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COMPACT METRICS ROW (Single Horizontal Row)
  // ---------------------------------------------------------------------------
  Widget _buildMetricsRow() {
    final summary = _reportData!['summary'] as Map<String, dynamic>? ?? {};
    final profitPercent = (_reportData!['profitPercent'] as num?)?.toDouble() ?? 0.0;
    final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0.0;
    final totalCost = (summary['totalCost'] as num?)?.toDouble() ?? 0.0;
    final netProfit = (summary['netProfit'] as num?)?.toDouble() ?? 0.0;
    final totalReturns = (_reportData!['totalReturns'] as num?)?.toDouble() ?? 0.0;
    final invoiceCount = (summary['invoiceCount'] as num?)?.toInt() ?? 0;
    final avgInvoiceValue = invoiceCount > 0 ? totalSales / invoiceCount : 0.0;

    final items = [
      _MetricTileData('إجمالي المبيعات', '${_fmt(totalSales)} د.ع', Icons.shopping_cart, const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
      _MetricTileData('التكلفة الإجمالية', '${_fmt(totalCost)} د.ع', Icons.money_off, const Color(0xFFDC2626), const Color(0xFFFEF2F2)),
      _MetricTileData('صافي الربح', '${_fmt(netProfit)} د.ع', Icons.trending_up, const Color(0xFF059669), const Color(0xFFECFDF5)),
      _MetricTileData('إجمالي المرتجعات', '${_fmt(totalReturns)} د.ع', Icons.remove_shopping_cart, const Color(0xFFD97706), const Color(0xFFFFFBEB)),
      _MetricTileData('نسبة الربح', '${profitPercent.toStringAsFixed(1)}%', Icons.percent, const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
      _MetricTileData('عدد الفواتير', '$invoiceCount فاتورة', Icons.receipt_long, const Color(0xFF0284C7), const Color(0xFFF0F9FF)),
      _MetricTileData('متوسط الفاتورة', '${_fmt(avgInvoiceValue)} د.ع', Icons.analytics, const Color(0xFF0D9488), const Color(0xFFF0FDF4)),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;

      if (isWide) {
        return Row(
          children: items.map((tile) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildCompactMetricCard(tile),
              ),
            );
          }).toList(),
        );
      }

      return SizedBox(
        height: 80,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            return SizedBox(
              width: 155,
              child: _buildCompactMetricCard(items[index]),
            );
          },
        ),
      );
    });
  }

  Widget _buildCompactMetricCard(_MetricTileData tile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: tile.bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tile.color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: tile.color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(tile.icon, color: tile.color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  tile.title,
                  style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    tile.value,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: tile.color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERACTIVE DAILY TREND CHART CARD (المخطط التفاعلي لأيام الشهر)
  // ---------------------------------------------------------------------------
  Widget _buildDailyTrendChartCard() {
    final dailySales = (_reportData!['dailySales'] as List?)?.cast<Map<String, dynamic>>() ?? [];

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

    int activeDayIndex = _hoveredDayIndex ?? 0;
    if (activeDayIndex >= dailySales.length) activeDayIndex = math.max(0, dailySales.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('تحليل التوجهات اليومية لشهر ${_getMonthName(_selectedMonth)}', Icons.show_chart_rounded),
        const SizedBox(height: 10),

        // Metric Selector Switcher Buttons
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
        const SizedBox(height: 12),

        // Curved Line & Area Chart Container
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
                  dailySales: dailySales,
                  selectedMetric: _selectedChartMetric,
                  selectedDayIndex: activeDayIndex,
                  lineColor: lineColor,
                  areaColor: areaColor,
                  globalMaxMonetary: globalMaxMonetary,
                  onSelectDay: (idx) {
                    if (idx != null) {
                      setState(() => _hoveredDayIndex = idx);
                    }
                  },
                  fmt: _fmt,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChartMetricButton(String key, String label, IconData icon) {
    final isSelected = _selectedChartMetric == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedChartMetric = key;
          _hoveredDayIndex = null;
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

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // Spotlight Banner for Selected Day
  Widget _buildDaySpotlightBanner() {
    final dailySales = (_reportData!['dailySales'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    int activeDayIndex = _hoveredDayIndex ?? 0;
    if (activeDayIndex >= dailySales.length) activeDayIndex = math.max(0, dailySales.length - 1);

    if (dailySales.isEmpty || activeDayIndex >= dailySales.length) return const SizedBox();

    final selD = dailySales[activeDayIndex];
    final sSales = (selD['totalSales'] as num?)?.toDouble() ?? 0;
    final sProfit = (selD['netProfit'] as num?)?.toDouble() ?? 0;
    final sCost = (selD['totalCost'] as num?)?.toDouble() ?? 0;
    final sInv = (selD['invoiceCount'] as num?)?.toInt() ?? 0;
    final sMargin = sSales > 0 ? (sProfit / sSales) * 100 : 0.0;
    final dateStr = selD['dateFormatted'] as String? ?? 'يوم ${activeDayIndex + 1}';

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
            children: [
              const Icon(Icons.stars_rounded, color: Color(0xFF4F46E5), size: 20),
              const SizedBox(width: 8),
              Text(
                'تفاصيل $dateStr',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1B4B)),
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
  }

  // Comparison with Previous Month Card
  Widget _buildComparisonCard() {
    final comparison = _reportData!['comparison'] as Map<String, dynamic>? ?? {};
    final changes = comparison['changes'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          _buildComparisonRow('المبيعات مقارنة بالشهر السابق', (changes['salesChange'] as num?)?.toDouble() ?? 0.0),
          const Divider(),
          _buildComparisonRow('الأرباح مقارنة بالشهر السابق', (changes['profitChange'] as num?)?.toDouble() ?? 0.0),
          const Divider(),
          _buildComparisonRow('عدد الفواتير مقارنة بالشهر السابق', (changes['invoiceCountChange'] as num?)?.toDouble() ?? 0.0),
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
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 4),
                Text(
                  '${changePercent.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Top 10 Products
  Widget _buildTopProductsList() {
    final topProducts = (_reportData!['topProducts'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (topProducts.isEmpty) {
      return const Center(child: Text('لا توجد بيانات للمنتجات هذا الشهر'));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topProducts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final product = topProducts[index];
          final sales = (product['total_sales'] as num?)?.toDouble() ?? 0;
          final qty = (product['total_quantity'] as num?)?.toDouble() ?? 0;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFEEF2FF),
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              product['product_name']?.toString() ?? 'منتج غير معروف',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text('الكمية المباعة: ${_fmt(qty)}'),
            trailing: Text(
              '${_fmt(sales)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2563EB), fontSize: 14),
            ),
          );
        },
      ),
    );
  }

  // Top 10 Customers
  Widget _buildTopCustomersList() {
    final topCustomers = (_reportData!['topCustomers'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (topCustomers.isEmpty) {
      return const Center(child: Text('لا توجد بيانات للعملاء هذا الشهر'));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topCustomers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final customer = topCustomers[index];
          final purchases = (customer['total_purchases'] as num?)?.toDouble() ?? 0;
          final invCount = customer['invoice_count'] ?? 0;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFECFDF5),
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              customer['customer_name']?.toString() ?? 'عميل غير معروف',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text('$invCount فاتورة'),
            trailing: Text(
              '${_fmt(purchases)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF059669), fontSize: 14),
            ),
          );
        },
      ),
    );
  }

  void _showMonthPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('اختر الشهر والسنـة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          height: 320,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.8,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
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
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getMonthName(month),
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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

class _MetricTileData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  _MetricTileData(this.title, this.value, this.icon, this.color, this.bgColor);
}

// =============================================================================
// 📈 WIDGET & CUSTOM PAINTER: INTERACTIVE DAILY CURVED LINE CHART FOR MONTH
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

    // 3. Draw Crosshair (Vertical & Horizontal Lines under cursor)
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < mainPoints.length) {
      final p = mainPoints[selectedIndex!];

      final crosshairPaint = Paint()
        ..color = lineColor.withOpacity(0.4)
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

    // 4. Draw Day Labels on X-Axis (e.g. 1, 5, 10, 15, 20, 25, 30)
    final textStyle = const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600);

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
        tp.paint(canvas, Offset(p.dx - (tp.width / 2), size.height - marginYBottom + 8));
      }
    }

    // 5. Draw Selected Day Node & Rich Floating Tooltip Box
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
