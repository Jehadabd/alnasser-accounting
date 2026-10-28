// screens/person_month_details_screen.dart
//
// 👤 شهر واحد لعميل: مؤشرات الشهر، فواتيره (برقمها التجاري وربحها الصحيح)،
// حركات حسابه، وما اشتراه من مواد. الضغط على فاتورة يفتح تفصيلها.
// (كان ربح الفاتورة هنا = مبلغها كله لأن الكلفة كانت تُقرأ بمفاتيح خاطئة.)

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../models/customer.dart';
import '../models/transaction.dart';
import '../services/database_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'invoice_details_screen.dart';

class PersonMonthDetailsScreen extends StatefulWidget {
  /// التوافق مع الاستدعاء القديم.
  PersonMonthDetailsScreen({super.key, required Customer customer, required this.year, required this.month})
      : customerId = customer.id,
        name = customer.name;

  const PersonMonthDetailsScreen.fromReport({
    super.key,
    required this.customerId,
    required this.name,
    required this.year,
    required this.month,
  });

  final int? customerId;
  final String name;
  final int year;
  final int month;

  @override
  State<PersonMonthDetailsScreen> createState() => _PersonMonthDetailsScreenState();
}

class _PersonMonthDetailsScreenState extends State<PersonMonthDetailsScreen> with SingleTickerProviderStateMixin {
  // يُنشأ في initState: الإنشاء الكسول كان يحدث أول مرة داخل dispose (حين لا تُستعمل
  // التبويبات في التخطيط العريض) ⇒ «Looking up a deactivated widget's ancestor is unsafe»
  late final TabController _tabs;
  bool _loading = true;
  SalesFacts? _facts;
  List<DebtTransaction> _tx = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final facts = await ReportsService().loadFacts(
        customerId: widget.customerId,
        customerName: widget.customerId == null ? widget.name : null,
        from: DateTime(widget.year, widget.month, 1),
        to: DateTime(widget.year, widget.month + 1, 0),
      );
      final tx = widget.customerId == null
          ? const <DebtTransaction>[]
          : await DatabaseService().getCustomerTransactionsForMonth(widget.customerId!, widget.year, widget.month);
      if (!mounted) return;
      setState(() {
        _facts = facts;
        _tx = tx;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      setToast(context, 'تعذّر تحميل بيانات الشهر: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profit = repCanSeeProfit();
    final f = _facts;
    return ReportScaffold(
      title: widget.name,
      subtitle: repMonth(widget.year, widget.month),
      icon: Icons.event_note_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      loading: _loading,
      body: _loading
          ? null
          : f == null
              ? const EmptyReport(title: 'تعذّر تحميل بيانات الشهر', text: 'اضغط «تحديث» للمحاولة مجدداً.', icon: Icons.error_outline_rounded)
              : NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: _kpis(f, profit)),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: kSetBorder),
                          ),
                          child: TabBar(
                            controller: _tabs,
                            labelColor: kSetNavy,
                            unselectedLabelColor: kSetMuted,
                            indicatorColor: kSetNavy,
                            indicatorSize: TabBarIndicatorSize.label,
                            dividerColor: Colors.transparent,
                            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                            tabs: [
                              Tab(text: 'الفواتير (${f.invoices.length})'),
                              Tab(text: 'حركات الحساب (${_tx.length})'),
                              const Tab(text: 'المواد'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              body: TabBarView(controller: _tabs, children: [
                _invoicesTab(f, profit),
                _txTab(),
                _productsTab(f, profit),
              ]),
            ),
    );
  }

  Widget _kpis(SalesFacts f, bool profit) {
    final t = f.totals();
    final remaining = t.sales - t.paid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: KpiGrid(minTileWidth: 170, children: [
        KpiTile(label: 'المشتريات', value: t.netSales, icon: Icons.shopping_cart_rounded, color: kSetBlue, emphasis: true),
        if (profit)
          KpiTile(
            label: 'الربح',
            value: t.profit,
            icon: Icons.trending_up_rounded,
            color: kSetGreen,
            hint: t.netSales.abs() > 0 ? 'هامش ${repPercent(t.margin)}' : null,
          ),
        KpiTile(label: 'الفواتير', value: t.invoiceCount.toDouble(), money: false, icon: Icons.receipt_long_rounded, color: kRepPurple),
        KpiTile(label: 'المدفوع منها', value: t.paid, icon: Icons.payments_rounded, color: kRepTeal),
        KpiTile(label: 'بقي على الحساب', value: remaining, icon: Icons.schedule_rounded, color: kSetOrange),
        if (t.totalReturns > 0)
          KpiTile(label: 'المرتجعات', value: t.totalReturns, icon: Icons.assignment_return_rounded, color: kSetRed),
      ]),
    );
  }

  Widget _wrap(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          for (final c in children)
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180), child: c)),
        ],
      );

  Widget _invoicesTab(SalesFacts f, bool profit) {
    if (f.invoices.isEmpty && f.returns.isEmpty) {
      return _wrap(const [EmptyReport(title: 'لا فواتير في هذا الشهر', icon: Icons.receipt_long_outlined)]);
    }
    return _wrap([
      for (final i in f.invoices.reversed)
        _InvoiceCard(
          inv: i,
          showProfit: profit,
          onTap: () => Navigator.push(context, accRoute(InvoiceDetailsScreen(invoiceId: i.id))),
        ),
      for (final r in f.returns)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kSetRed.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.assignment_return_rounded, color: kSetRed),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مرتجع مبيعات رقم ${r.number}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                Text(
                  '${repDate(r.date)} • ${r.refundModeArabic}${r.originalInvoiceId == null ? '' : ' • من فاتورة #${r.originalInvoiceId}'}',
                  style: const TextStyle(fontSize: 12, color: kSetMuted),
                ),
              ]),
            ),
            MoneyLabel(-r.total),
          ]),
        ),
    ]);
  }

  Widget _txTab() {
    if (_tx.isEmpty) {
      return _wrap([
        EmptyReport(
          title: 'لا حركات حساب في هذا الشهر',
          text: widget.customerId == null ? 'هذا زبون بلا بطاقة، فلا حساب دين له.' : null,
          icon: Icons.account_balance_wallet_outlined,
        ),
      ]);
    }
    return _wrap([for (final t in _tx) _TxRow(t: t)]);
  }

  Widget _productsTab(SalesFacts f, bool profit) {
    final list = f.byProduct()..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
    if (list.isEmpty) return _wrap(const [EmptyReport(title: 'لا مواد في هذا الشهر', icon: Icons.inventory_2_outlined)]);
    final max = list.first.netRevenue;
    return _wrap([
      SetCard(
        title: 'ما اشتراه في ${repMonth(widget.year, widget.month)}',
        subtitle: '${list.length} مادة — الكمية بالوحدة الأساسية',
        icon: Icons.inventory_2_rounded,
        color: kSetGreen,
        child: Column(children: [
          for (var i = 0; i < list.length; i++)
            RankRow(
              rank: i + 1,
              title: list[i].name,
              subtitle:
                  '${repQty(list[i].netQty)} ${list[i].baseUnit}${profit ? ' • ربح ${repMoney(list[i].profit)}' : ''}',
              value: list[i].netRevenue,
              fraction: max <= 0 ? 0 : list[i].netRevenue / max,
              color: kSetGreen,
            ),
        ]),
      ),
    ]);
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.inv, required this.showProfit, required this.onTap});
  final SalesInvoiceFact inv;
  final bool showProfit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = inv.total - inv.paid;
    Widget pill(String t, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
          child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
        );
    Widget cell(String label, Widget v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: kSetMuted)),
          v,
        ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kSetBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: inv.isCash ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: inv.isCash ? kSetGreen : kSetOrange),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('فاتورة ${inv.displayNumber}',
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontWeight: FontWeight.w900, color: kSetText)),
                      pill(inv.paymentType.isEmpty ? '—' : inv.paymentType, inv.isCash ? kSetGreen : kSetOrange),
                    ]),
                    Text('${repDate(inv.date)} • ${inv.items.where((i) => i.kind == SalesItemKind.sale).length} صنف',
                        style: const TextStyle(fontSize: 12, color: kSetMuted)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: kSetMuted),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 22, runSpacing: 8, children: [
                cell('المجموع', MoneyLabel(inv.total)),
                if (inv.discount > 0) cell('الخصم', MoneyLabel(-inv.discount, bold: false)),
                if (inv.loadingFee > 0) cell('أجور التحميل', MoneyLabel(inv.loadingFee, bold: false)),
                if (inv.returnAmount > 0) cell('الراجع', MoneyLabel(-inv.returnAmount, bold: false)),
                if (!inv.isCash) cell('المدفوع', MoneyLabel(inv.paid, bold: false)),
                if (!inv.isCash) cell('المتبقي', MoneyLabel(remaining, color: remaining > 0 ? kSetOrange : kSetGreen)),
                if (showProfit) cell('الربح', MoneyLabel(inv.profit, color: kSetGreen)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.t});
  final DebtTransaction t;

  String get _label => switch (t.transactionType) {
        'manual_debt' || 'debt_addition' => 'إضافة دين',
        'opening_balance' => 'رصيد افتتاحي',
        'manual_payment' || 'payment' || 'debt_payment' => 'تسديد',
        'invoice_debt' || 'invoice_debt_sync' => 'دين فاتورة',
        _ => t.amountChanged >= 0 ? 'إضافة على الحساب' : 'تنزيل من الحساب',
      };

  @override
  Widget build(BuildContext context) {
    final up = t.amountChanged > 0;
    final c = up ? kSetOrange : kSetGreen;
    final note = [t.description, t.transactionNote].whereType<String>().where((s) => s.trim().isNotEmpty).join(' — ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kSetBorder)),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
          child: Icon(up ? Icons.north_east_rounded : Icons.south_west_rounded, color: c, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_label, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
            Text(
              [repDate(t.transactionDate), if (note.isNotEmpty) note].join(' • '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: kSetMuted),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          MoneyLabel(t.amountChanged.abs(), color: c),
          if (t.newBalanceAfterTransaction != null)
            Text('الرصيد ${repMoney(t.newBalanceAfterTransaction!)}', style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
        ]),
      ]),
    );
  }
}
