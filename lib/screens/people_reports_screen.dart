// screens/people_reports_screen.dart
//
// 👥 تقارير الأشخاص — من اشترى، وكم، وكم ربحنا منه، لأي فترة:
//   • الفترة + مصدر البيانات + بحث + ترتيب.
//   • مؤشرات: عملاء نشطون، المبيعات، الربح، المرتجعات، ديون الحاليين.
//   • قائمة العملاء: الفواتير، المبيعات، الربح (السالب أحمر)، الدين الحالي، آخر شراء.
// الضغط على عميل يفتح تقريره: السنوات ← الأشهر ← الفواتير.

import 'dart:async';

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show PeriodBar, accRoute;
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'person_details_screen.dart';

enum _Sort { sales, profit, invoices, recent, debt, name }

class PeopleReportsScreen extends StatefulWidget {
  const PeopleReportsScreen({super.key});

  @override
  State<PeopleReportsScreen> createState() => _PeopleReportsScreenState();
}

class _Person {
  _Person({required this.key, required this.id, required this.name, this.phone, this.debt = 0, this.agg});
  final String key;
  final int? id;
  final String name;
  final String? phone;
  final double debt;
  final CustomerAgg? agg;

  double get sales => agg?.totals.netSales ?? 0;
  double get profit => agg?.totals.profit ?? 0;
  int get invoices => agg?.totals.invoiceCount ?? 0;
  double get returns => agg?.totals.totalReturns ?? 0;
  DateTime? get last => agg?.lastInvoice;
}

class _PeopleReportsScreenState extends State<PeopleReportsScreen> {
  final _rs = ReportsService();
  final _search = TextEditingController();
  Timer? _debounce;

  DateTime? _from;
  DateTime _to = DateTime.now();
  String _source = ReportSource.all;
  _Sort _sort = _Sort.sales;
  bool _includeInactive = false;

  bool _loading = true;
  List<_Person> _people = const [];
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() => _loading = true);
    try {
      final dbs = DatabaseService();
      try {
        await dbs.updateOldInvoicesWithCustomerIds(); // ربط الفواتير القديمة بعملائها بالاسم
      } catch (_) {}
      _rs.reportSourceFilter = _source;
      final facts = await _rs.loadFacts(from: _from, to: _to);
      final db = await dbs.database;
      final rows = await db.rawQuery('''
        SELECT id, name, phone, COALESCE(current_total_debt, 0) AS debt
        FROM customers WHERE COALESCE(is_deleted, 0) = 0''');
      final byId = {for (final r in rows) (r['id'] as num).toInt(): r};
      final seen = <int>{};
      final people = <_Person>[];
      for (final a in facts.byCustomer()) {
        final r = a.customerId == null ? null : byId[a.customerId];
        if (a.customerId != null) seen.add(a.customerId!);
        people.add(_Person(
          key: a.key,
          id: a.customerId != null && a.customerId! > 0 ? a.customerId : null,
          name: (r?['name'] as String?) ?? a.name,
          phone: r?['phone'] as String?,
          debt: (r?['debt'] as num?)?.toDouble() ?? 0,
          agg: a,
        ));
      }
      for (final r in rows) {
        final id = (r['id'] as num).toInt();
        if (seen.contains(id)) continue;
        people.add(_Person(
          key: 'id:$id',
          id: id,
          name: (r['name'] as String?) ?? '',
          phone: r['phone'] as String?,
          debt: (r['debt'] as num?)?.toDouble() ?? 0,
        ));
      }
      if (!mounted || token != _token) return;
      setState(() {
        _people = people;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      setToast(context, 'تعذّر تحميل التقرير: $e', error: true);
    }
  }

  List<_Person> get _shown {
    final q = _search.text.trim().toLowerCase();
    final list = _people.where((p) {
      if (!_includeInactive && p.agg == null) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || (p.phone ?? '').contains(q);
    }).toList();
    int cmp(_Person a, _Person b) => switch (_sort) {
          _Sort.sales => b.sales.compareTo(a.sales),
          _Sort.profit => b.profit.compareTo(a.profit),
          _Sort.invoices => b.invoices.compareTo(a.invoices),
          _Sort.recent => (b.last ?? DateTime(1970)).compareTo(a.last ?? DateTime(1970)),
          _Sort.debt => b.debt.compareTo(a.debt),
          _Sort.name => a.name.compareTo(b.name),
        };
    return list..sort(cmp);
  }

  @override
  Widget build(BuildContext context) {
    final profit = repCanSeeProfit();
    final shown = _loading ? const <_Person>[] : _shown;
    final active = shown.where((p) => p.agg != null).toList();
    final sales = active.fold<double>(0, (s, p) => s + p.sales);
    final prof = active.fold<double>(0, (s, p) => s + p.profit);
    final returns = active.fold<double>(0, (s, p) => s + p.returns);
    final debt = shown.fold<double>(0, (s, p) => s + (p.debt > 0 ? p.debt : 0));
    final maxSales = active.fold<double>(0, (m, p) => p.sales > m ? p.sales : m);

    return ReportScaffold(
      title: 'تقارير الأشخاص',
      subtitle: _from == null ? 'كل الفترات' : '${repDate(_from!)} — ${repDate(_to)}',
      icon: Icons.people_alt_rounded,
      actions: [
        SourceMenu(
          value: _source,
          onChanged: (v) {
            setState(() => _source = v);
            _load();
          },
        ),
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      header: _filters(profit),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        KpiGrid(minTileWidth: 190, children: [
                          KpiTile(
                            label: 'عملاء اشتروا',
                            value: active.length.toDouble(),
                            money: false,
                            icon: Icons.groups_rounded,
                            hint: _includeInactive ? 'من ${shown.length}' : null,
                          ),
                          KpiTile(label: 'صافي المبيعات', value: sales, icon: Icons.point_of_sale_rounded, color: kSetBlue, emphasis: true),
                          if (profit)
                            KpiTile(
                              label: 'الربح',
                              value: prof,
                              icon: Icons.trending_up_rounded,
                              color: kSetGreen,
                              hint: sales.abs() > 0 ? 'هامش ${repPercent(prof / sales * 100)}' : null,
                            ),
                          if (returns > 0)
                            KpiTile(label: 'المرتجعات', value: returns, icon: Icons.assignment_return_rounded, color: kSetRed),
                          KpiTile(
                            label: 'ديونهم الحالية',
                            value: debt,
                            icon: Icons.account_balance_wallet_rounded,
                            color: kSetOrange,
                            hint: 'الرصيد اليوم (لا يتبع الفترة)',
                          ),
                        ]),
                        const SizedBox(height: 14),
                        Text('العملاء (${shown.length})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kSetText)),
                        const SizedBox(height: 8),
                      ]),
                    ),
                  ),
                ),
              ),
              if (shown.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyReport(
                    title: 'لا يوجد عملاء مطابقون',
                    text: 'غيّر الفترة أو البحث، أو فعّل «إظهار من لم يشترِ».',
                    icon: Icons.person_search_rounded,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  sliver: SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: _PersonRow(
                          p: shown[i],
                          showProfit: profit,
                          fraction: maxSales <= 0 ? 0 : shown[i].sales / maxSales,
                          onTap: () => Navigator.push(
                            context,
                            accRoute(PersonDetailsScreen.fromReport(
                              customerId: shown[i].id,
                              name: shown[i].name,
                              phone: shown[i].phone,
                            )),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
    );
  }

  Widget _filters(bool profit) {
    final sorts = <(_Sort, String)>[
      (_Sort.sales, 'المبيعات'),
      if (profit) (_Sort.profit, 'الربح'),
      (_Sort.invoices, 'الفواتير'),
      (_Sort.recent, 'آخر شراء'),
      (_Sort.debt, 'الدين'),
      (_Sort.name, 'الاسم'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PeriodBar(
        from: _from,
        to: _to,
        onChanged: (f, t) {
          setState(() {
            _from = f;
            _to = t;
          });
          _load();
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الهاتف…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _search.clear()),
                      ),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() {});
                });
              },
            ),
          ),
          FilterChip(
            label: const Text('إظهار من لم يشترِ'),
            selected: _includeInactive,
            onSelected: (v) => setState(() => _includeInactive = v),
          ),
          const SizedBox(width: 6),
          const Text('ترتيب:', style: TextStyle(color: kSetMuted, fontWeight: FontWeight.w600)),
          for (final s in sorts)
            ChoiceChip(
              label: Text(s.$2),
              selected: _sort == s.$1,
              showCheckmark: false,
              onSelected: (_) => setState(() => _sort = s.$1),
            ),
        ]),
      ),
    ]);
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.p, required this.showProfit, required this.fraction, required this.onTap});
  final _Person p;
  final bool showProfit;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = p.agg == null;
    final initial = p.name.trim().isEmpty ? '?' : p.name.trim().characters.first;
    Widget cell(String label, Widget value, {double width = 120}) => SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: kSetMuted)),
            const SizedBox(height: 2),
            value,
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: inactive ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSetBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 280,
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: inactive
                            ? null
                            : const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]),
                        color: inactive ? const Color(0xFFE2E8F0) : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(initial,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: inactive ? kSetMuted : Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                        Text(
                          [
                            if (p.phone != null && p.phone!.isNotEmpty) p.phone!,
                            if (p.last != null) 'آخر شراء ${repDate(p.last!)}',
                            if (p.id == null) 'بلا بطاقة',
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: kSetMuted),
                        ),
                      ]),
                    ),
                  ]),
                ),
                cell('الفواتير', Text(repQty(p.invoices), style: const TextStyle(fontWeight: FontWeight.w800)), width: 70),
                cell('المبيعات', MoneyLabel(p.sales)),
                if (showProfit) cell('الربح', MoneyLabel(p.profit, color: kSetGreen)),
                if (p.returns > 0) cell('مرتجع', MoneyLabel(-p.returns, bold: false), width: 100),
                cell('الدين الحالي', MoneyLabel(p.debt, color: p.debt > 0 ? kSetOrange : kSetMuted)),
              ]),
              if (!inactive) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    minHeight: 4,
                    color: kSetBlue,
                    backgroundColor: const Color(0xFFF1F5F9),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
