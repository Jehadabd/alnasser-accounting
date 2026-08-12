// screens/inventory_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/monthly_overview.dart';
import 'package:intl/intl.dart';
import '../services/settings_manager.dart';
import '../models/app_settings.dart';
import 'transactions_list_dialog.dart';
import 'material_inventory_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  late TabController _tabController;

  // بيانات الجرد الشهري
  Map<String, MonthlyOverview> _monthlySummaries = {};

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

      setState(() {
        _monthlySummaries = summaries;
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
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMonthlyInventoryTab(),
                _buildComparisonTab(),
                _buildTopCustomersBySalesTab(),
                _buildTopCustomersByProfitTab(),
                _buildTopProductsTab(),
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

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 20),
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
                ? [const Color(0xFF3F51B5).withOpacity(0.12), const Color(0xFF3F51B5).withOpacity(0.05)]
                : [Colors.grey.withOpacity(0.08), Colors.grey.withOpacity(0.02)],
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
            // القسم الأول: بيانات الفواتير (تفصيلي)
            // ═══════════════════════════════════════════════════════════════════
            _buildSectionHeader('🧾 الفواتير', const Color(0xFF2196F3)),
            const SizedBox(height: 10),
            
            // مبيعات الفواتير + أرباح الفواتير
            Row(children: [
              Expanded(child: _buildCompactInfoItem(Icons.shopping_cart, 'مبيعات الفواتير', '${formatCurrency(summary.totalSales)} د.ع', null, const Color(0xFF2196F3))),
              const SizedBox(width: 8),
              Expanded(child: _buildCompactInfoItem(Icons.trending_up, 'أرباح الفواتير', '${formatCurrency(summary.netProfit)} د.ع', '${invoiceProfitPercent.toStringAsFixed(1)}%', const Color(0xFF4CAF50))),
            ]),
            const SizedBox(height: 8),
            
            // تكلفة الفواتير + عدد الفواتير
            Row(children: [
              Expanded(child: _buildCompactInfoItem(Icons.money_off, 'تكلفة الفواتير', '${formatCurrency(summary.totalCost)} د.ع', null, const Color(0xFFF44336))),
              const SizedBox(width: 8),
              Expanded(child: _buildCompactInfoItem(Icons.receipt_long, 'عدد الفواتير', '${summary.invoiceCount} فاتورة', null, const Color(0xFF607D8B))),
            ]),
            const SizedBox(height: 8),
            
            // نقد الفواتير + دين الفواتير (النسب = 100%)
            Row(children: [
              Expanded(child: _buildCompactInfoItem(Icons.payments, 'نقد (فواتير)', '${formatCurrency(summary.cashSales)} د.ع', '${cashPercentOfInvoices.toStringAsFixed(1)}%', const Color(0xFF4CAF50))),
              const SizedBox(width: 8),
              Expanded(child: _buildCompactInfoItem(Icons.credit_card, 'دين (فواتير)', '${formatCurrency(invoiceCreditSalesPositive)} د.ع', '${creditPercentOfInvoices.toStringAsFixed(1)}%', const Color(0xFFFF9800))),
            ]),
            
            // الراجع (إن وجد)
            if (summary.totalReturns > 0) ...[
              const SizedBox(height: 8),
              _buildCompactInfoItem(Icons.keyboard_return, 'الراجع', '${formatCurrency(summary.totalReturns)} د.ع', null, const Color(0xFF9C27B0)),
            ],
            
            // ═══════════════════════════════════════════════════════════════════
            // القسم الثاني: المعاملات اليدوية (تفصيلي)
            // ═══════════════════════════════════════════════════════════════════
            // ═══════════════════════════════════════════════════════════════════
            // القسم الثاني: المعاملات اليدوية (تفصيلي)
            // ═══════════════════════════════════════════════════════════════════
            const SizedBox(height: 16),
            _buildSectionHeader('✋ المعاملات اليدوية', const Color(0xFFE91E63)),
            const SizedBox(height: 10),
            
            // إضافة دين يدوية + ربح المعاملات اليدوية
            Row(children: [
              Expanded(
                child: _buildCompactClickableItem(
                  Icons.person_add, 
                  'إضافة دين يدوية', 
                  '${formatCurrency(manualDebtAmount)} د.ع', 
                  '${summary.manualDebtCount} معاملة',
                  const Color(0xFFE91E63), 
                  () => _showDebtAdditions(monthYear),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildCompactInfoItem(Icons.account_balance_wallet, 'ربح يدوي (${_manualDebtProfitPercent.toStringAsFixed(0)}%)', '${formatCurrency(manualProfit)} د.ع', null, const Color(0xFF00BCD4))),
            ]),
            const SizedBox(height: 8),
            
            // تسديد الديون
            _buildCompactClickableItem(
              Icons.remove_circle, 
              'تسديد الديون', 
              '${formatCurrency(summary.totalDebtPayments)} د.ع', 
              '${summary.manualPaymentCount} معاملة',
              const Color(0xFF009688), 
              () => _showDebtPayments(monthYear),
            ),
            
            // ═══════════════════════════════════════════════════════════════════
            // القسم الثالث: الإجماليات الشاملة
            // ═══════════════════════════════════════════════════════════════════
            const SizedBox(height: 16),
            _buildSectionHeader('📊 الإجماليات الشاملة', const Color(0xFF673AB7)),
            const SizedBox(height: 10),
            
            // إجمالي المبيعات الشامل + إجمالي الأرباح الشامل
            Row(children: [
              Expanded(child: _buildCompactInfoItem(Icons.shopping_bag, 'إجمالي المبيعات', '${formatCurrency(totalSalesAll)} د.ع', null, const Color(0xFF673AB7))),
              const SizedBox(width: 8),
              Expanded(child: _buildCompactInfoItem(Icons.assessment, 'إجمالي الأرباح', '${formatCurrency(totalProfitAll)} د.ع', '${totalProfitPercentAll.toStringAsFixed(1)}%', const Color(0xFF8BC34A))),
            ]),
            const SizedBox(height: 8),
            
            // إجمالي الدين الشامل + إجمالي التسديد
            Row(children: [
              Expanded(child: _buildCompactInfoItem(Icons.account_balance, 'إجمالي الدين', '${formatCurrency(totalDebtAll)} د.ع', null, const Color(0xFFFF5722))),
              const SizedBox(width: 8),
              Expanded(child: _buildCompactInfoItem(Icons.check_circle, 'إجمالي التسديد', '${formatCurrency(summary.totalDebtPayments)} د.ع', null, const Color(0xFF009688))),
            ]),
            

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


  // ==================== تبويب المقارنة ====================
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
            // عنوان المقارنة
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(children: [
                    const Icon(Icons.calendar_today, color: Color(0xFF3F51B5), size: 30),
                    const SizedBox(height: 8),
                    Text(currentMonthName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Text('الشهر الحالي', style: TextStyle(color: Colors.grey)),
                  ]),
                  const Icon(Icons.compare_arrows, size: 40, color: Color(0xFF3F51B5)),
                  Column(children: [
                    const Icon(Icons.history, color: Color(0xFF607D8B), size: 30),
                    const SizedBox(height: 8),
                    Text(lastMonthName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Text('الشهر الماضي', style: TextStyle(color: Colors.grey)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // جدول المقارنة
            _buildComparisonRow('إجمالي المبيعات', _currentMonth?.totalSales ?? 0, _lastMonth?.totalSales ?? 0, Icons.shopping_cart, const Color(0xFF2196F3)),
            _buildComparisonRow('صافي الأرباح', _currentMonth?.netProfit ?? 0, _lastMonth?.netProfit ?? 0, Icons.trending_up, const Color(0xFF4CAF50)),
            _buildComparisonRow('إجمالي التكلفة', _currentMonth?.totalCost ?? 0, _lastMonth?.totalCost ?? 0, Icons.money_off, const Color(0xFFF44336)),
            _buildComparisonRow('عدد الفواتير', (_currentMonth?.invoiceCount ?? 0).toDouble(), (_lastMonth?.invoiceCount ?? 0).toDouble(), Icons.receipt_long, const Color(0xFF607D8B), isCount: true),
            _buildComparisonRow('البيع بالنقد', _currentMonth?.cashSales ?? 0, _lastMonth?.cashSales ?? 0, Icons.payments, const Color(0xFF4CAF50)),
            _buildComparisonRow('البيع بالدين', _currentMonth?.creditSales ?? 0, _lastMonth?.creditSales ?? 0, Icons.credit_card, const Color(0xFFFF9800)),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonRow(String title, double current, double last, IconData icon, Color color, {bool isCount = false}) {
    final diff = current - last;
    final percentChange = last > 0 ? ((diff / last) * 100) : (current > 0 ? 100 : 0);
    final isPositive = diff >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // الشهر الحالي
                Column(
                  children: [
                    Text(isCount ? current.toInt().toString() : '${formatCurrency(current)} د.ع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                    const Text('الحالي', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                // الفرق
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPositive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: isPositive ? Colors.green : Colors.red),
                      const SizedBox(width: 4),
                      Text('${percentChange.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, color: isPositive ? Colors.green : Colors.red)),
                    ],
                  ),
                ),
                // الشهر الماضي
                Column(
                  children: [
                    Text(isCount ? last.toInt().toString() : '${formatCurrency(last)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                    const Text('الماضي', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
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
}
