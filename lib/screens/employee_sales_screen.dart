// lib/screens/employee_sales_screen.dart
//
// 👷 تقرير «مبيعات الموظفين»: لكل موظف في الفترة: الفواتير، صافي المبيعات، النقد والدين،
// المرتجعات، متوسط الفاتورة، وحصته — والربح لمن له صلاحية رؤية الكلفة والأرباح.
// الأرقام من محرك التقارير الموحّد (services/reports/employee_sales.dart) — قراءة فقط.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show PeriodBar;
import '../services/database_service.dart';
import '../services/reports/employee_sales.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'invoice_details_screen.dart';
import 'report_parts.dart' show openReport;

class EmployeeSalesScreen extends StatefulWidget {
  const EmployeeSalesScreen({super.key});
  @override
  State<EmployeeSalesScreen> createState() => _EmployeeSalesScreenState();
}

class _EmployeeSalesScreenState extends State<EmployeeSalesScreen> {
  final _svc = ReportsService();
  DateTime? _from;
  late DateTime _to;
  String _source = ReportSource.all;
  bool _loading = true;
  String? _error;
  int _token = 0;

  SalesFacts? _facts;
  Map<int, String> _creators = const {};
  EmployeeSalesReport? _report;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    _load();
  }

  Future<void> _load() async {
    final t = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _svc.reportSourceFilter = _source;
      final facts = await _svc.loadFacts(from: _from, to: _to);
      final db = await DatabaseService().database;
      final creators = await EmployeeSalesReport.creators(db, facts);
      final names = await EmployeeSalesReport.displayNames(db);
      final report = EmployeeSalesReport.group(facts, creatorOf: creators, names: names);
      if (!mounted || t != _token) return;
      setState(() {
        _facts = facts;
        _creators = creators;
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || t != _token) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReportScaffold(
      title: 'مبيعات الموظفين',
      subtitle: 'من باع كم: الفواتير، صافي المبيعات، النقد والدين، والمرتجعات',
      icon: Icons.badge_rounded,
      actions: [
        SourceMenu(
            value: _source,
            onChanged: (v) {
              _source = v;
              _load();
            }),
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      header: PeriodBar(
        from: _from,
        to: _to,
        onChanged: (f, t) {
          _from = f;
          _to = t;
          _load();
        },
      ),
      loading: _loading,
      children: _loading ? null : _content(),
    );
  }

  List<Widget> _content() {
    final r = _report;
    if (_error != null || r == null) {
      return [EmptyReport(title: 'تعذّر تحميل التقرير', text: _error, icon: Icons.error_outline_rounded)];
    }
    if (r.rows.isEmpty) {
      return const [EmptyReport(title: 'لا مبيعات في هذه الفترة', icon: Icons.badge_outlined)];
    }
    final canProfit = repCanSeeProfit();
    final t = r.total;
    final top = r.rows.fold<double>(0, (m, e) => e.totals.netSales > m ? e.totals.netSales : m);
    return [
      SetCard(
        title: 'الفترة',
        icon: Icons.summarize_rounded,
        color: kRepTeal,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: KpiGrid(minTileWidth: 200, children: [
          KpiTile(label: 'صافي المبيعات', value: t.netSales, icon: Icons.payments_rounded, color: kRepTeal, emphasis: true),
          KpiTile(label: 'الفواتير', value: t.invoiceCount.toDouble(), money: false, icon: Icons.receipt_long_rounded),
          KpiTile(
              label: 'موظفون باعوا',
              value: r.rows.where((e) => e.username.isNotEmpty).length.toDouble(),
              money: false,
              icon: Icons.groups_rounded),
          if (canProfit) KpiTile(label: 'الربح', value: t.profit, icon: Icons.trending_up_rounded, color: kSetGreen),
        ]),
      ),
      SetCard(
        title: 'الموظفون',
        subtitle: 'اضغط موظفاً لترى فواتيره',
        icon: Icons.leaderboard_rounded,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(children: [
          for (var i = 0; i < r.rows.length; i++) _row(i, r.rows[i], t, top, canProfit),
        ]),
      ),
      if (r.rows.any((e) => e.username.isEmpty))
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            '«غير مسجّل»: فواتير قديمة حُفظت قبل أن يسجّل البرنامج اسم من أنشأها.',
            style: TextStyle(fontSize: 12, color: kSetMuted),
          ),
        ),
    ];
  }

  Widget _row(int i, EmployeeSales e, SalesTotals all, double top, bool canProfit) {
    final s = e.totals;
    final share = all.netSales.abs() > 0.0001 ? s.netSales / all.netSales * 100 : 0.0;
    final parts = <String>[
      '${s.invoiceCount} فاتورة',
      'نقد ${repMoney(s.cashSales)}',
      'دين ${repMoney(s.creditSales)}',
      if (s.totalReturns > 0.5) 'مرتجع ${repMoney(s.totalReturns)}',
      if (s.invoiceCount > 0) 'متوسط ${repMoney(s.averageInvoice)}',
      'الحصة ${repPercent(share)}',
      if (canProfit) 'الربح ${repMoney(s.profit)} (${repPercent(s.margin)})',
    ];
    return RankRow(
      rank: i + 1,
      title: e.name,
      subtitle: parts.join(' • '),
      value: s.netSales,
      fraction: top > 0 ? (s.netSales / top).clamp(0, 1).toDouble() : 0,
      color: e.username.isEmpty ? kSetMuted : kRepTeal,
      onTap: () => _showInvoices(e),
    );
  }

  Future<void> _showInvoices(EmployeeSales e) async {
    final f = _facts;
    if (f == null) return;
    final list = EmployeeSalesReport.invoicesOf(f, _creators, e.username);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('فواتير ${e.name} (${list.length})',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('لا فواتير — الرقم من مرتجعات أو تعديلات فقط'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, k) {
                      final inv = list[k];
                      return ListTile(
                        dense: true,
                        leading: Icon(inv.isCash ? Icons.payments_rounded : Icons.account_balance_wallet_rounded,
                            color: inv.isCash ? kSetGreen : kSetOrange),
                        title: Text('${inv.displayNumber} — ${inv.customerName}'),
                        subtitle: Text('${repDate(inv.date)} • ${inv.paymentType}'),
                        trailing: Text(repMoney(inv.netSales), style: const TextStyle(fontWeight: FontWeight.w800)),
                        onTap: () => openReport(context, InvoiceDetailsScreen(invoiceId: inv.id)),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
