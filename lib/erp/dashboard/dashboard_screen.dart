// lib/erp/dashboard/dashboard_screen.dart
//
// 📈 لوحة المؤشرات (مثل «لوحة التحكم» في سهل): مبيعات وأرباح اليوم والشهر،
// الديون، الصناديق، الاستحقاقات، النواقص، أفضل المواد، ورسم مبيعات آخر 14 يوماً.
// قراءة فقط — الأرقام من نفس خدمات التقارير الحالية حتى تطابق شاشاتها.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../../accounting/vouchers_service.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/reports_service.dart';
import '../currency_service.dart';
import '../debts/due_items_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../inventory/inventory_reports.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  Map<String, dynamic> _today = const {};
  Map<String, dynamic> _month = const {};
  List<Map<String, dynamic>> _daily = const [];
  List<Map<String, dynamic>> _top = const [];
  double _ar = 0, _apIqd = 0, _apUsd = 0, _usdRate = 0;
  int _debtors = 0;
  Map<String, double> _due = const {};
  int _lowStock = 0;
  List<CashBox> _boxes = const [];
  Map<int, double> _boxBal = const {};

  bool get _showProfit => AuthService().hasPermission(AppPermissions.viewCostProfit);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final rs = ReportsService();
    try {
      final today = await rs.getPeriodSummary(startDate: now, endDate: now);
      final month = await rs.getPeriodSummary(startDate: DateTime(now.year, now.month, 1), endDate: now);
      final daily = await rs.getDailySalesInPeriod(startDate: now.subtract(const Duration(days: 13)), endDate: now);
      final top = await rs.getTopProductsInPeriod(startDate: DateTime(now.year, now.month, 1), endDate: now, limit: 6);
      final db = await erpDb();
      final c = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN current_total_debt > 0 THEN current_total_debt ELSE 0 END), 0) AS ar,
               COALESCE(SUM(CASE WHEN current_total_debt > 0 THEN 1 ELSE 0 END), 0) AS n
        FROM customers WHERE COALESCE(is_deleted, 0) = 0''');
      final s = await db.rawQuery(
          'SELECT COALESCE(SUM(total_debt_iqd), 0) AS iqd, COALESCE(SUM(total_debt_usd), 0) AS usd FROM suppliers');
      final rate = await CurrencyService.rateAt(db, 'USD', now);
      Map<String, double> due = const {};
      try {
        due = await DueItemsService().dashboard();
      } catch (_) {}
      var low = 0;
      try {
        low = (await InventoryReports().limits('below_min')).length;
      } catch (_) {}
      final vs = VouchersService();
      final boxes = await vs.cashBoxes();
      final bal = await vs.cashBoxBalances();
      if (!mounted) return;
      setState(() {
        _today = today;
        _month = month;
        _daily = daily;
        _top = top;
        _ar = d0(c.first['ar']);
        _debtors = ((c.first['n'] as num?) ?? 0).toInt();
        _apIqd = d0(s.first['iqd']);
        _apUsd = d0(s.first['usd']);
        _usdRate = rate;
        _due = due;
        _lowStock = low;
        _boxes = boxes;
        _boxBal = bal;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final user = AuthService().currentUser?.username ?? '';
    return ErpPage(
      title: 'لوحة المؤشرات',
      subtitle: '$greet${user.isEmpty ? '' : ' يا $user'} • ${fmtDate(DateTime.now())}',
      icon: Icons.dashboard_rounded,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white))],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 30), children: [
                _heroRow(),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (_, c) {
                  final wide = c.maxWidth > 900;
                  final chart = _card('مبيعات آخر 14 يوماً', Icons.bar_chart_rounded, ErpColors.blue, _chart());
                  final top = _card('أفضل المواد هذا الشهر', Icons.emoji_events_rounded, ErpColors.gold, _topList());
                  return wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 3, child: chart),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: top),
                        ])
                      : Column(children: [chart, const SizedBox(height: 16), top]);
                }),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  StatCard(
                      label: 'ديون العملاء',
                      value: fmtMoney(_ar),
                      hint: '$_debtors عميل مدين',
                      icon: Icons.people_alt_rounded,
                      color: ErpColors.red),
                  StatCard(
                      label: 'ديون الموردين',
                      value: fmtMoney(_apIqd),
                      hint: _apUsd.abs() > 0.009 ? '+ \$${fmtMoney(_apUsd)} (≈ ${fmtMoney(_apUsd * _usdRate)})' : null,
                      icon: Icons.local_shipping_rounded,
                      color: ErpColors.orange),
                  StatCard(
                      label: 'استحقاقات متأخرة',
                      value: fmtMoney(_due['overdue'] ?? 0),
                      hint: 'هذا الأسبوع ${fmtMoney(_due['week'] ?? 0)}',
                      icon: Icons.event_busy_rounded,
                      color: ErpColors.purple),
                  StatCard(
                      label: 'مواد تحت الحد الأدنى',
                      value: '$_lowStock',
                      icon: Icons.warning_amber_rounded,
                      color: _lowStock > 0 ? ErpColors.red : ErpColors.green),
                  StatCard(label: 'سعر الدولار', value: fmtMoney(_usdRate), icon: Icons.attach_money_rounded, color: ErpColors.green),
                ]),
                const SizedBox(height: 16),
                if (_boxes.isNotEmpty && AuthService().hasPermission(AppPermissions.accounting))
                  _card(
                    'الصناديق',
                    Icons.account_balance_wallet_rounded,
                    ErpColors.navy,
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (final b in _boxes)
                        Container(
                          width: 200,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ErpColors.bg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.name, style: const TextStyle(color: ErpColors.muted)),
                            const SizedBox(height: 4),
                            Text(fmtMoney(_boxBal[b.id] ?? 0),
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: (_boxBal[b.id] ?? 0) < 0 ? ErpColors.red : ErpColors.navy)),
                          ]),
                        ),
                    ]),
                  ),
              ]),
            ),
    );
  }

  Widget _heroRow() {
    final todaySales = _n(_today, 'totalSales');
    final monthSales = _n(_month, 'totalSales');
    final cards = <Widget>[
      _hero('مبيعات اليوم', fmtMoney(todaySales), '${_today['invoiceCount'] ?? 0} فاتورة', Icons.today_rounded,
          const [Color(0xFF0F3460), Color(0xFF1B6CA8)]),
      if (_showProfit)
        _hero('ربح اليوم', fmtMoney(_n(_today, 'netProfit')),
            todaySales > 0 ? 'هامش ${(_n(_today, 'netProfit') / todaySales * 100).toStringAsFixed(1)}%' : '',
            Icons.trending_up_rounded, const [Color(0xFF0E7C61), Color(0xFF2BB673)]),
      _hero('مبيعات الشهر', fmtMoney(monthSales), 'نقد ${fmtMoney(_n(_month, 'cashSales'))} • آجل ${fmtMoney(_n(_month, 'creditSales'))}',
          Icons.calendar_month_rounded, const [Color(0xFF5B3CC4), Color(0xFF8E6CF0)]),
      if (_showProfit)
        _hero('ربح الشهر', fmtMoney(_n(_month, 'netProfit')), 'مرتجعات ${fmtMoney(_n(_month, 'totalReturns'))}',
            Icons.savings_rounded, const [Color(0xFFB7791F), Color(0xFFE0A93B)]),
    ];
    return Wrap(spacing: 12, runSpacing: 12, children: cards);
  }

  Widget _hero(String label, String value, String hint, IconData icon, List<Color> colors) => Container(
        width: 250,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: colors.first.withOpacity(.3), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );

  Widget _card(String title, IconData icon, Color color, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ErpColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _chart() {
    final now = DateTime.now();
    final days = [for (var i = 13; i >= 0; i--) DateTime(now.year, now.month, now.day).subtract(Duration(days: i))];
    final byDay = <String, double>{};
    for (final r in _daily) {
      byDay['${r['date']}'] = (r['total_sales'] as num?)?.toDouble() ?? 0;
    }
    String k(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final values = [for (final d in days) byDay[k(d)] ?? 0.0];
    final maxV = values.fold<double>(0, math.max);
    return SizedBox(
      height: 200,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Tooltip(
              message: '${fmtDate(days[i])}\n${fmtMoney(values[i])}',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                AnimatedContainer(
                  duration: Duration(milliseconds: 300 + i * 30),
                  height: maxV <= 0 ? 2 : math.max(2, 160 * values[i] / maxV),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: i == days.length - 1
                          ? const [Color(0xFF0E7C61), Color(0xFF2BB673)]
                          : const [Color(0xFF0F3460), Color(0xFF1B6CA8)],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${days[i].day}', style: const TextStyle(fontSize: 10, color: ErpColors.muted)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _topList() {
    if (_top.isEmpty) return const Text('لا توجد مبيعات هذا الشهر', style: TextStyle(color: ErpColors.muted));
    final maxV = _top.fold<double>(0, (m, r) => math.max(m, (r['total_sales'] as num?)?.toDouble() ?? 0));
    return Column(children: [
      for (var i = 0; i < _top.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: i == 0 ? ErpColors.gold : ErpColors.bg,
                child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: i == 0 ? Colors.white : ErpColors.text)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('${_top[i]['product_name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(fmtMoney((_top[i]['total_sales'] as num?)?.toDouble() ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: maxV <= 0 ? 0 : ((_top[i]['total_sales'] as num?)?.toDouble() ?? 0) / maxV,
                minHeight: 6,
                backgroundColor: ErpColors.bg,
                color: i == 0 ? ErpColors.gold : ErpColors.blue,
              ),
            ),
          ]),
        ),
    ]);
  }
}
