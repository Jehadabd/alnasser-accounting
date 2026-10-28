// lib/screens/report_parts.dart
//
// 🧩 أجزاء مشتركة لتقريري اليوم والأسبوع (وما يشبههما): تحميل بيانات الفترة
// مع فترتي مقارنة، المؤشرات، دوائر التوزيع، الديون اليدوية، المواد والعملاء
// الأعلى، وقائمة الفواتير. كل الأرقام من المحرك الموحّد (SalesFacts).

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'invoice_details_screen.dart';
import 'person_month_details_screen.dart';
import 'product_report_details_screen.dart';
import 'transactions_list_dialog.dart';

double pctChange(double cur, double prev) => prev == 0 ? (cur > 0 ? 100 : (cur < 0 ? -100 : 0)) : (cur - prev) / prev.abs() * 100;

const kArabicWeekdays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
String repWeekday(DateTime d) => kArabicWeekdays[d.weekday - 1];
String repTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
double _n(Object? v) => (v as num?)?.toDouble() ?? 0.0;

void openReport(BuildContext context, Widget page) => Navigator.push(context, accRoute(page));

/// بيانات فترة + فترتي مقارنة (السابقة مباشرة، وأخرى اختيارية).
class PeriodData {
  PeriodData._({
    required this.from,
    required this.to,
    required this.facts,
    required this.summary,
    required this.prev,
    required this.prev2,
    required this.categories,
  });

  final DateTime from;
  final DateTime to;
  final SalesFacts facts;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> prev;
  final Map<String, dynamic>? prev2;
  final List<CategoryAgg> categories;

  SalesTotals get totals => facts.totals();
  bool get isEmpty =>
      facts.invoices.isEmpty &&
      facts.returns.isEmpty &&
      _n(summary['manualDebtCount']) == 0 &&
      _n(summary['manualPaymentCount']) == 0 &&
      _n(summary['manualPaymentReturnCount']) == 0;

  static Future<PeriodData> load(
    ReportsService svc, {
    required DateTime from,
    required DateTime to,
    required DateTime prevFrom,
    required DateTime prevTo,
    DateTime? prev2From,
    DateTime? prev2To,
  }) async {
    final facts = await svc.loadFacts(from: from, to: to);
    final summary = await svc.getPeriodSummary(startDate: from, endDate: to);
    final prev = await svc.getPeriodSummary(startDate: prevFrom, endDate: prevTo);
    final prev2 = (prev2From != null && prev2To != null)
        ? await svc.getPeriodSummary(startDate: prev2From, endDate: prev2To)
        : null;
    List<CategoryAgg> cats = const [];
    try {
      final all = await svc.getCategories();
      cats = facts.byCategory({for (final c in all) c.id: c.name},
          parents: {for (final c in all) c.id: c.parentId}, rollupToRoot: true)
        ..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
    } catch (_) {}
    return PeriodData._(
      from: from,
      to: to,
      facts: facts,
      summary: summary,
      prev: prev,
      prev2: prev2,
      categories: cats,
    );
  }
}

/// مؤشرات الفترة مع التغيّر عن الفترة السابقة.
Widget periodKpis(PeriodData d, {required String prevLabel, required bool canProfit, VoidCallback? onReturns}) {
  final s = d.summary, p = d.prev;
  final sales = _n(s['totalSales']);
  final cash = _n(s['cashSales']);
  final credit = _n(s['creditSales']);
  final down = (_n(s['paidAmount']) - cash).clamp(0, double.infinity).toDouble();
  String pct(double v) => sales > 0 ? '${(v / sales * 100).toStringAsFixed(1)}% من المبيعات' : '—';
  return SetCard(
    title: 'الفواتير',
    subtitle: 'التغيّر مقارنة بـ$prevLabel',
    icon: Icons.receipt_long_rounded,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    child: KpiGrid(minTileWidth: 210, children: [
      KpiTile(
        label: 'المبيعات',
        value: sales,
        icon: Icons.point_of_sale_rounded,
        emphasis: true,
        delta: pctChange(sales, _n(p['totalSales'])),
        hint: '${_n(s['invoiceCount']).toInt()} فاتورة • متوسط ${repMoney(_n(s['averageInvoice']))}',
      ),
      if (canProfit)
        KpiTile(
          label: 'الربح',
          value: _n(s['netProfit']),
          icon: Icons.trending_up_rounded,
          color: kSetGreen,
          emphasis: true,
          delta: pctChange(_n(s['netProfit']), _n(p['netProfit'])),
          hint: 'هامش ${repPercent(_n(s['profitMargin']))}',
        ),
      KpiTile(label: 'نقد', value: cash, icon: Icons.payments_rounded, color: kRepTeal, hint: pct(cash)),
      KpiTile(
        label: 'آجل (دين)',
        value: credit,
        icon: Icons.schedule_rounded,
        color: kSetOrange,
        hint: down > 0 ? '${pct(credit)} • دُفع منه ${repMoney(down)}' : pct(credit),
      ),
      KpiTile(
        label: 'الراجع',
        value: _n(s['totalReturns']),
        icon: Icons.keyboard_return_rounded,
        color: kRepPurple,
        deltaInverse: true,
        delta: pctChange(_n(s['totalReturns']), _n(p['totalReturns'])),
        hint: _n(s['editReturns']) > 0
            ? 'و${repMoney(_n(s['editReturns']))} بتعديل الفواتير (منقوصة من المبيعات)'
            : 'التفاصيل',
        onTap: onReturns,
      ),
      KpiTile(label: 'صافي المبيعات', value: _n(s['netSales']), icon: Icons.account_balance_wallet_rounded, hint: 'بعد الراجع'),
      if (canProfit) KpiTile(label: 'الكلفة', value: _n(s['totalCost']), icon: Icons.price_change_rounded, color: kRepAmber),
      KpiTile(label: 'العملاء', value: _n(s['customerCount']), money: false, icon: Icons.groups_rounded, color: kSetBlue),
    ]),
  );
}

/// دوائر: طريقة الدفع + الأقسام.
Widget distributionCard(PeriodData d) {
  final s = d.summary;
  final manual = _n(s['totalManualDebt']);
  final top = d.categories.take(6).toList();
  final rest = d.categories.skip(6).fold<double>(0, (a, c) => a + c.netRevenue);
  final payment = DonutChart(
    centerTitle: 'المبيعات',
    slices: [
      DonutSlice('نقد', _n(s['cashSales']), kRepTeal),
      DonutSlice('آجل', _n(s['creditSales']), kSetOrange),
      if (manual > 0) DonutSlice('دين يدوي', manual, kRepPurple, hint: 'خارج الفواتير'),
    ],
  );
  final categories = DonutChart(
    centerTitle: 'مبيعات المواد',
    slices: [
      for (var i = 0; i < top.length; i++)
        DonutSlice(top[i].categoryId == null ? 'عام / غير مصنّف' : top[i].name, top[i].netRevenue,
            kRepPalette[i % kRepPalette.length],
            hint: '${top[i].productCount} مادة'),
      if (rest > 0) DonutSlice('أقسام أخرى', rest, kRepPalette.last),
    ],
  );
  return SetCard(
    title: 'توزيع المبيعات',
    subtitle: 'طريقة الدفع، والأقسام (قيمة المواد قبل خصم الفاتورة والتحميل)',
    icon: Icons.donut_large_rounded,
    color: kRepTeal,
    child: Padding(
      padding: const EdgeInsets.only(top: 10),
      child: twoCols(payment, categories, gap: 24, breakpoint: 860, divider: true),
    ),
  );
}

/// الديون والتسديدات اليدوية (خارج الفواتير) مع قوائمها.
Widget manualCard(BuildContext context, PeriodData d,
    {required String periodTitle, required String source, required bool canProfit}) {
  final s = d.summary;
  final debt = _n(s['totalManualDebt']);
  final profit = _n(s['manualDebtProfit']);
  return SetCard(
    title: 'خارج الفواتير',
    subtitle: 'ديون أُضيفت يدوياً، وتسديدات لا ترتبط بفاتورة',
    icon: Icons.edit_note_rounded,
    color: kRepPurple,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    child: KpiGrid(minTileWidth: 230, children: [
      KpiTile(
        label: 'إضافة دين يدوي',
        value: debt,
        icon: Icons.person_add_alt_1_rounded,
        color: kSetOrange,
        hint: '${_n(s['manualDebtCount']).toInt()} معاملة — اضغط للقائمة',
        onTap: () => TransactionsListDialog.showDebtAdditions(
            context: context, startDate: d.from, endDate: d.to, periodTitle: periodTitle, sourceFilter: source),
      ),
      KpiTile(
        label: 'تسديد ديون يدوي',
        value: _n(s['totalManualPayment']),
        icon: Icons.price_check_rounded,
        color: kRepTeal,
        hint: '${_n(s['manualPaymentCount']).toInt()} معاملة — اضغط للقائمة',
        onTap: () => TransactionsListDialog.showDebtPayments(
            context: context, startDate: d.from, endDate: d.to, periodTitle: periodTitle, sourceFilter: source),
      ),
      KpiTile(
        label: 'تسديد دين راجع',
        value: _n(s['totalManualPaymentReturn']),
        icon: Icons.assignment_return_rounded,
        color: const Color(0xFFE91E63),
        hint: '${_n(s['manualPaymentReturnCount']).toInt()} معاملة — اضغط للقائمة',
        onTap: () => TransactionsListDialog.showDebtPaymentReturns(
            context: context, startDate: d.from, endDate: d.to, periodTitle: periodTitle, sourceFilter: source),
      ),
      if (canProfit)
        KpiTile(
          label: 'ربح الدين اليدوي (تقديري)',
          value: profit,
          icon: Icons.percent_rounded,
          color: kSetGreen,
          hint: debt > 0 ? '${(profit / debt * 100).toStringAsFixed(0)}% ثابتة من الإعدادات' : 'نسبة ثابتة من الإعدادات',
        ),
    ]),
  );
}

/// مقارنة الفترة بفترة أو فترتين.
Widget compareCard(PeriodData d,
    {required String title, required String prevLabel, String? prev2Label, required bool canProfit, String? subtitle}) {
  final s = d.summary, p = d.prev, p2 = d.prev2;
  final rows = <(String, String, bool, bool)>[
    ('المبيعات', 'totalSales', true, false),
    if (canProfit) ('الربح', 'netProfit', true, false),
    ('عدد الفواتير', 'invoiceCount', false, false),
    ('نقد', 'cashSales', true, false),
    ('آجل', 'creditSales', true, false),
    ('الراجع', 'totalReturns', true, true),
  ];
  const st = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: kSetMuted);
  Widget cell(Widget c, {int flex = 3}) =>
      Expanded(flex: flex, child: Align(alignment: AlignmentDirectional.centerStart, child: c));
  Widget val(double v, bool money, {bool muted = false}) => money
      ? MoneyLabel(v, size: 13.5, bold: !muted, color: muted ? kSetMuted : null)
      : Text(repQty(v), style: TextStyle(fontWeight: muted ? FontWeight.w500 : FontWeight.w800, color: muted ? kSetMuted : kSetText));
  return SetCard(
    title: title,
    subtitle: subtitle,
    icon: Icons.compare_arrows_rounded,
    color: kSetBlue,
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(children: [
          cell(const Text('', style: st)),
          cell(const Text('الآن', style: st)),
          cell(Text(prevLabel, style: st)),
          cell(const Text('التغيّر', style: st), flex: 2),
          if (p2 != null) ...[
            cell(Text(prev2Label ?? '', style: st)),
            cell(const Text('التغيّر', style: st), flex: 2),
          ],
        ]),
      ),
      for (final r in rows)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
          child: Row(children: [
            cell(Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText))),
            cell(val(_n(s[r.$2]), r.$3)),
            cell(val(_n(p[r.$2]), r.$3, muted: true)),
            cell(DeltaChip(pctChange(_n(s[r.$2]), _n(p[r.$2])), inverse: r.$4), flex: 2),
            if (p2 != null) ...[
              cell(val(_n(p2[r.$2]), r.$3, muted: true)),
              cell(DeltaChip(pctChange(_n(s[r.$2]), _n(p2[r.$2])), inverse: r.$4), flex: 2),
            ],
          ]),
        ),
    ]),
  );
}

/// عمودان في الشاشات العريضة، وتحت بعض في الضيقة.
Widget twoCols(Widget a, Widget b, {double gap = 14, double breakpoint = 900, bool divider = false}) => LayoutBuilder(
      builder: (context, c) => c.maxWidth < breakpoint
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, if (divider) const Divider(height: 28), b])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: a),
              SizedBox(width: gap),
              Expanded(child: b),
            ]),
    );

Widget _toggle(bool value, ValueChanged<bool> onChanged) => SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('مبيعاً')),
        ButtonSegment(value: true, label: Text('ربحاً')),
      ],
      selected: {value},
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelectionChanged: (s) => onChanged(s.first),
    );

/// المواد الأعلى (مبيعاً/ربحاً).
class TopProductsCard extends StatefulWidget {
  const TopProductsCard({super.key, required this.facts, required this.canProfit, this.limit = 10});
  final SalesFacts facts;
  final bool canProfit;
  final int limit;
  @override
  State<TopProductsCard> createState() => _TopProductsCardState();
}

class _TopProductsCardState extends State<TopProductsCard> {
  bool _byProfit = false;
  @override
  Widget build(BuildContext context) {
    final byProfit = widget.canProfit && _byProfit;
    final list = widget.facts.byProduct()
      ..sort((a, b) => byProfit ? b.profit.compareTo(a.profit) : b.netRevenue.compareTo(a.netRevenue));
    final rows = list.take(widget.limit).toList();
    double v(ProductAgg p) => byProfit ? p.profit : p.netRevenue;
    final maxV = rows.fold<double>(0, (m, p) => v(p).abs() > m ? v(p).abs() : m);
    return SetCard(
      title: 'المواد الأعلى',
      subtitle: '${list.length} مادة بيعت • الكمية بالوحدة الأساسية',
      icon: Icons.inventory_2_rounded,
      color: kRepAmber,
      trailing: widget.canProfit ? _toggle(_byProfit, (x) => setState(() => _byProfit = x)) : null,
      child: rows.isEmpty
          ? const EmptyReport(title: 'لا مبيعات مواد', icon: Icons.inventory_2_outlined)
          : Column(children: [
              for (var i = 0; i < rows.length; i++)
                RankRow(
                  rank: i + 1,
                  title: rows[i].name,
                  subtitle: [
                    '${repQty(rows[i].netQty)} ${rows[i].baseUnit}',
                    '${rows[i].invoiceCount} فاتورة',
                    if (widget.canProfit && !byProfit) 'ربح ${repMoney(rows[i].profit)}',
                    if (byProfit) 'مبيعات ${repMoney(rows[i].netRevenue)}',
                  ].join(' • '),
                  value: v(rows[i]),
                  fraction: maxV > 0 ? v(rows[i]).abs() / maxV : 0,
                  color: byProfit ? kSetGreen : kRepAmber,
                  onTap: () => openReport(context, ProductReportDetailsScreen(productId: rows[i].productId, productName: rows[i].name)),
                ),
            ]),
    );
  }
}

/// العملاء الأعلى (شراءً/ربحاً) — الضغط يفتح فواتيره في شهر بداية الفترة.
class TopCustomersCard extends StatefulWidget {
  const TopCustomersCard({super.key, required this.facts, required this.canProfit, required this.monthOf, this.limit = 10});
  final SalesFacts facts;
  final bool canProfit;
  final DateTime monthOf;
  final int limit;
  @override
  State<TopCustomersCard> createState() => _TopCustomersCardState();
}

class _TopCustomersCardState extends State<TopCustomersCard> {
  bool _byProfit = false;
  @override
  Widget build(BuildContext context) {
    final byProfit = widget.canProfit && _byProfit;
    final list = widget.facts.byCustomer()
      ..sort((a, b) => byProfit ? b.totals.profit.compareTo(a.totals.profit) : b.totals.netSales.compareTo(a.totals.netSales));
    final rows = list.take(widget.limit).toList();
    double v(CustomerAgg c) => byProfit ? c.totals.profit : c.totals.netSales;
    final maxV = rows.fold<double>(0, (m, c) => v(c).abs() > m ? v(c).abs() : m);
    return SetCard(
      title: 'العملاء الأعلى',
      subtitle: '${list.length} عميل اشترى',
      icon: Icons.people_alt_rounded,
      color: kSetBlue,
      trailing: widget.canProfit ? _toggle(_byProfit, (x) => setState(() => _byProfit = x)) : null,
      child: rows.isEmpty
          ? const EmptyReport(title: 'لا عملاء', icon: Icons.people_outline_rounded)
          : Column(children: [
              for (var i = 0; i < rows.length; i++)
                RankRow(
                  rank: i + 1,
                  title: rows[i].name,
                  subtitle: [
                    '${rows[i].totals.invoiceCount} فاتورة',
                    if (rows[i].totals.creditSales > 0) 'آجل ${repMoney(rows[i].totals.creditSales)}',
                    if (widget.canProfit && !byProfit) 'ربح ${repMoney(rows[i].totals.profit)}',
                    if (byProfit) 'مشتريات ${repMoney(rows[i].totals.netSales)}',
                  ].join(' • '),
                  value: v(rows[i]),
                  fraction: maxV > 0 ? v(rows[i]).abs() / maxV : 0,
                  color: byProfit ? kSetGreen : kSetBlue,
                  onTap: () => openReport(
                      context,
                      PersonMonthDetailsScreen.fromReport(
                        customerId: rows[i].customerId,
                        name: rows[i].name,
                        year: widget.monthOf.year,
                        month: widget.monthOf.month,
                      )),
                ),
            ]),
    );
  }
}

/// قائمة فواتير الفترة + مستندات المرتجع.
class InvoicesListCard extends StatefulWidget {
  const InvoicesListCard({super.key, required this.facts, required this.canProfit, this.showDay = false});
  final SalesFacts facts;
  final bool canProfit;

  /// إظهار اسم اليوم مع الوقت (تقرير الأسبوع).
  final bool showDay;
  @override
  State<InvoicesListCard> createState() => _InvoicesListCardState();
}

class _InvoicesListCardState extends State<InvoicesListCard> {
  int _filter = 0; // 0 الكل، 1 نقد، 2 آجل
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final all = List.of(widget.facts.invoices)..sort((a, b) => b.date.compareTo(a.date));
    final list = [
      for (final i in all)
        if (_filter == 0 || (_filter == 1 && i.isCash) || (_filter == 2 && !i.isCash)) i
    ];
    final shown = _all ? list : list.take(25).toList();
    final returns = widget.facts.returns;
    const st = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: kSetMuted);
    Widget c(Widget w, {int flex = 2, bool numeric = true}) => Expanded(
          flex: flex,
          child: Align(alignment: numeric ? Alignment.center : AlignmentDirectional.centerStart, child: w),
        );
    return SetCard(
      title: 'الفواتير',
      subtitle: '${all.length} فاتورة — اضغط على فاتورة لتفاصيلها',
      icon: Icons.list_alt_rounded,
      trailing: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('الكل')),
          ButtonSegment(value: 1, label: Text('نقد')),
          ButtonSegment(value: 2, label: Text('آجل')),
        ],
        selected: {_filter},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: (s) => setState(() => _filter = s.first),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: list.isEmpty && returns.isEmpty
          ? const EmptyReport(title: 'لا فواتير', icon: Icons.receipt_long_outlined)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (list.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kSetBorder))),
                  child: Row(children: [
                    c(const Text('الوقت', style: st), flex: widget.showDay ? 3 : 2, numeric: false),
                    c(const Text('الفاتورة / العميل', style: st), flex: 5, numeric: false),
                    c(const Text('الدفع', style: st)),
                    c(const Text('المجموع', style: st)),
                    if (widget.canProfit) c(const Text('الربح', style: st)),
                  ]),
                ),
              for (var k = 0; k < shown.length; k++)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => openReport(context, InvoiceDetailsScreen(invoiceId: shown[k].id)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    decoration: BoxDecoration(
                      color: k.isOdd ? const Color(0xFFF8FAFC) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      c(
                          Text(
                            widget.showDay
                                ? '${repWeekday(shown[k].date)} ${repTime(shown[k].date)}'
                                : repTime(shown[k].date),
                            style: const TextStyle(fontSize: 12.5, color: kSetMuted),
                          ),
                          flex: widget.showDay ? 3 : 2,
                          numeric: false),
                      c(
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(shown[k].customerName,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
                            Text(
                              [
                                shown[k].displayNumber,
                                if (shown[k].returnAmount > 0) 'راجع ${repMoney(shown[k].returnAmount)}',
                                if (shown[k].discount > 0) 'خصم ${repMoney(shown[k].discount)}',
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: kSetMuted),
                            ),
                          ]),
                          flex: 5,
                          numeric: false),
                      c(_PayPill(cash: shown[k].isCash)),
                      c(MoneyLabel(shown[k].total, size: 13.5)),
                      if (widget.canProfit) c(MoneyLabel(shown[k].profit, size: 13, color: kSetGreen)),
                    ]),
                  ),
                ),
              if (list.length > shown.length)
                TextButton(
                  onPressed: () => setState(() => _all = true),
                  child: Text('عرض الكل (${list.length})'),
                ),
              if (returns.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 14, 8, 6),
                  child: Text('مستندات مرتجع المبيعات', style: TextStyle(fontWeight: FontWeight.w800, color: kRepPurple)),
                ),
                for (final r in returns)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(children: [
                      const Icon(Icons.keyboard_return_rounded, size: 18, color: kRepPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${r.number} • ${r.customerName} • ${r.refundModeArabic}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      MoneyLabel(-r.total, size: 13.5),
                    ]),
                  ),
              ],
            ]),
    );
  }
}

class _PayPill extends StatelessWidget {
  const _PayPill({required this.cash});
  final bool cash;
  @override
  Widget build(BuildContext context) {
    final c = cash ? kRepTeal : kSetOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Text(cash ? 'نقد' : 'آجل', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
    );
  }
}
