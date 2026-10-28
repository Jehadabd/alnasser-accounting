// screens/person_details_screen.dart
//
// 👤 تقرير عميل: كل الفترات ← سنة (أشهرها برسم وبطاقات) ← شهر (فواتيره).
// قراءة واحدة لفواتير العميل من المحرك الموحّد: مجموع السنة = مجموع أشهرها
// = مجموع فواتيرها (كانت كل شاشة تحسب بطريقة فلا تتطابق).

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../models/customer.dart';
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'person_month_details_screen.dart';

class PersonDetailsScreen extends StatefulWidget {
  /// التوافق مع الاستدعاء القديم ببطاقة العميل.
  PersonDetailsScreen({super.key, required Customer customer})
      : customerId = customer.id,
        name = customer.name,
        phone = customer.phone;

  const PersonDetailsScreen.fromReport({super.key, required this.customerId, required this.name, this.phone});

  final int? customerId;
  final String name;
  final String? phone;

  @override
  State<PersonDetailsScreen> createState() => _PersonDetailsScreenState();
}

class _PersonDetailsScreenState extends State<PersonDetailsScreen> {
  bool _loading = true;
  SalesFacts? _facts;
  Map<String, Object?>? _customer;
  int? _year;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final facts = await ReportsService().loadFacts(
        customerId: widget.customerId,
        customerName: widget.customerId == null ? widget.name : null,
      );
      Map<String, Object?>? customer;
      if (widget.customerId != null) {
        final db = await DatabaseService().database;
        final r = await db.query('customers', where: 'id = ?', whereArgs: [widget.customerId], limit: 1);
        customer = r.isEmpty ? null : r.first;
      }
      if (!mounted) return;
      final years = facts.byYear().keys.toList()..sort((a, b) => b.compareTo(a));
      setState(() {
        _facts = facts;
        _customer = customer;
        _year ??= years.isEmpty ? null : years.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      setToast(context, 'تعذّر تحميل تقرير العميل: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profit = repCanSeeProfit();
    return ReportScaffold(
      title: widget.name,
      subtitle: 'تقرير العميل',
      icon: Icons.person_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      loading: _loading,
      onRefresh: _load,
      children: _loading
          ? null
          : _facts == null
              ? const [EmptyReport(title: 'تعذّر تحميل تقرير العميل', text: 'اضغط «تحديث» للمحاولة مجدداً.', icon: Icons.error_outline_rounded)]
              : [
              _hero(),
              _allTime(profit),
              if (_year != null) ...[
                _yearChips(),
                _yearCard(_year!, profit),
                _topProducts(_year!, profit),
              ] else
                const EmptyReport(
                  title: 'لا فواتير لهذا العميل',
                  text: 'لم تُسجَّل له أي فاتورة محفوظة بعد.',
                  icon: Icons.receipt_long_outlined,
                ),
            ],
    );
  }

  Widget _hero() {
    final c = _customer;
    final phone = (c?['phone'] as String?) ?? widget.phone;
    final address = c?['address'] as String?;
    final debt = (c?['current_total_debt'] as num?)?.toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF0F3460), Color(0xFF1B6CA8)]),
        boxShadow: const [BoxShadow(color: Color(0x330F3460), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(children: [
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
          child: Text(widget.name.trim().isEmpty ? '?' : widget.name.trim().characters.first,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Wrap(spacing: 14, runSpacing: 4, children: [
              if (phone != null && phone.isNotEmpty) _info(Icons.phone_rounded, phone),
              if (address != null && address.isNotEmpty) _info(Icons.location_on_rounded, address),
              if (widget.customerId == null) _info(Icons.info_outline_rounded, 'زبون بلا بطاقة (بالاسم فقط)'),
            ]),
          ]),
        ),
        if (debt != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              const Text('الدين الحالي', style: TextStyle(fontSize: 11.5, color: kSetMuted)),
              MoneyLabel(debt, size: 17, color: debt > 0 ? kSetOrange : kSetGreen),
            ]),
          ),
      ]),
    );
  }

  Widget _info(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 15, color: Colors.white70),
        const SizedBox(width: 4),
        Text(t, textDirection: TextDirection.rtl, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      ]);

  Widget _allTime(bool profit) {
    final t = _facts!.totals();
    final last = _facts!.invoices.isEmpty ? null : _facts!.invoices.last.date;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: KpiGrid(minTileWidth: 180, children: [
        KpiTile(label: 'صافي المشتريات (كل الفترات)', value: t.netSales, icon: Icons.shopping_cart_rounded, color: kSetBlue, emphasis: true),
        if (profit)
          KpiTile(
            label: 'الربح منه',
            value: t.profit,
            icon: Icons.trending_up_rounded,
            color: kSetGreen,
            hint: t.netSales.abs() > 0 ? 'هامش ${repPercent(t.margin)}' : null,
          ),
        KpiTile(
          label: 'الفواتير',
          value: t.invoiceCount.toDouble(),
          money: false,
          icon: Icons.receipt_long_rounded,
          color: kRepPurple,
          hint: last == null ? null : 'آخرها ${repDate(last)}',
        ),
        KpiTile(label: 'متوسط الفاتورة', value: t.averageInvoice, icon: Icons.functions_rounded, color: kRepTeal),
        if (t.totalReturns > 0)
          KpiTile(label: 'المرتجعات', value: t.totalReturns, icon: Icons.assignment_return_rounded, color: kSetRed),
      ]),
    );
  }

  Widget _yearChips() {
    final years = _facts!.byYear();
    final keys = years.keys.toList()..sort((a, b) => b.compareTo(a));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final y in keys)
          ChoiceChip(
            label: Text('$y  •  ${repMoney(years[y]!.netSales)}'),
            selected: _year == y,
            showCheckmark: false,
            onSelected: (_) => setState(() => _year = y),
          ),
      ]),
    );
  }

  Widget _yearCard(int year, bool profit) {
    final months = _facts!.byMonth();
    SalesTotals m(int i) => months['$year-${i.toString().padLeft(2, '0')}'] ?? SalesTotals();
    final yt = _facts!.byYear()[year] ?? SalesTotals();
    return SetCard(
      title: 'سنة $year',
      subtitle:
          '${yt.invoiceCount} فاتورة • ${repMoney(yt.netSales)} د.ع${profit ? ' • ربح ${repMoney(yt.profit)}' : ''}',
      icon: Icons.calendar_month_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        MiniBars(
          values: [for (var i = 1; i <= 12; i++) m(i).netSales],
          labels: [for (var i = 1; i <= 12; i++) '$i'],
          tooltips: [for (var i = 1; i <= 12; i++) 'شهر $i\n${repMoney(m(i).netSales)} د.ع • ${m(i).invoiceCount} فاتورة'],
          color: kSetBlue,
          height: 150,
          onTap: (i) => _openMonth(year, i + 1),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 600 ? 3 : 2);
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 1; i <= 12; i++)
              SizedBox(width: w, child: _MonthTile(month: i, t: m(i), showProfit: profit, onTap: m(i).isEmpty ? null : () => _openMonth(year, i))),
          ]);
        }),
      ]),
    );
  }

  Widget _topProducts(int year, bool profit) {
    final items = [
      for (final i in _facts!.invoices)
        if (i.date.year == year) ...i.items
    ];
    final map = <String, (String, double, double, double, String)>{};
    for (final it in items) {
      final cur = map[it.productKey] ?? (it.productName, 0.0, 0.0, 0.0, it.baseUnit);
      map[it.productKey] = (cur.$1, cur.$2 + it.baseQty, cur.$3 + it.revenue, cur.$4 + it.profit, cur.$5);
    }
    final list = map.values.toList()..sort((a, b) => b.$3.compareTo(a.$3));
    if (list.isEmpty) return const SizedBox.shrink();
    final max = list.first.$3;
    return SetCard(
      title: 'أكثر ما اشتراه في $year',
      subtitle: '${list.length} مادة',
      icon: Icons.inventory_2_rounded,
      color: kSetGreen,
      child: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 760 ? 2 : 1;
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(spacing: 16, children: [
          for (var i = 0; i < list.length && i < 12; i++)
            SizedBox(
              width: w,
              child: RankRow(
                rank: i + 1,
                title: list[i].$1,
                subtitle: '${repQty(list[i].$2)} ${list[i].$5}${profit ? ' • ربح ${repMoney(list[i].$4)}' : ''}',
                value: list[i].$3,
                fraction: max <= 0 ? 0 : list[i].$3 / max,
                color: kSetGreen,
              ),
            ),
        ]);
      }),
    );
  }

  void _openMonth(int year, int month) {
    Navigator.push(
      context,
      accRoute(PersonMonthDetailsScreen.fromReport(
        customerId: widget.customerId,
        name: widget.name,
        year: year,
        month: month,
      )),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({required this.month, required this.t, required this.showProfit, required this.onTap});
  final int month;
  final SalesTotals t;
  final bool showProfit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = onTap == null;
    return Material(
      color: empty ? const Color(0xFFF8FAFC) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kSetBorder)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('شهر $month', style: TextStyle(fontWeight: FontWeight.w900, color: empty ? const Color(0xFFB8C2CF) : kSetText)),
              const Spacer(),
              if (!empty) const Icon(Icons.chevron_right_rounded, size: 18, color: kSetMuted),
            ]),
            const SizedBox(height: 4),
            if (empty)
              const Text('لا تعاملات', style: TextStyle(fontSize: 12, color: Color(0xFFB8C2CF)))
            else ...[
              MoneyLabel(t.netSales),
              Text('${t.invoiceCount} فاتورة${t.totalReturns > 0 ? ' • مرتجع ${repMoney(t.totalReturns)}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
              if (showProfit)
                Text('ربح ${repMoney(t.profit)}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.profit < 0 ? kSetRed : kSetGreen)),
            ],
          ]),
        ),
      ),
    );
  }
}
