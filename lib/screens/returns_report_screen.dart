// screens/returns_report_screen.dart
//
// ↩️ المرتجعات — كل ما رجع من المبيعات في فترة، بأنواعه الثلاثة:
//   1) مستندات «مرتجع مبيعات» (من شاشة المرتجع): بضاعة عادت للمخزن.
//   2) «الراجع» المسجّل على الفاتورة نفسها (حقل الراجع).
//   3) فواتير أُنقص مبلغها بعد حفظها (من سجل لقطات الفاتورة) — لمطابقة الصندوق.
// مع شرح صريح: «ميزان المراجعة» ليس مرتجعات، بل قائمة محاسبية.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show PeriodBar;
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'invoice_details_screen.dart';
import 'invoice_history_screen.dart';
import 'report_parts.dart' show openReport, repTime;

class ReturnsReportScreen extends StatefulWidget {
  const ReturnsReportScreen({super.key, this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  @override
  State<ReturnsReportScreen> createState() => _ReturnsReportScreenState();
}

double _n(Object? v) => (v as num?)?.toDouble() ?? 0.0;

class _ReturnsReportScreenState extends State<ReturnsReportScreen> {
  final _svc = ReportsService();
  DateTime? _from;
  late DateTime _to;
  String _source = ReportSource.all;
  bool _loading = true;
  String? _error;
  int _token = 0;

  SalesFacts? _facts;
  List<Map<String, dynamic>> _edits = const [];
  bool _showHelp = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = widget.from ?? DateTime(now.year, now.month, 1);
    _to = widget.to ?? now;
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
      final edits = await _svc.getCashReturnsInPeriod(startDate: _from ?? DateTime(2000), endDate: _to);
      edits.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
      if (!mounted || t != _token) return;
      setState(() {
        _facts = facts;
        _edits = edits;
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
    final canProfit = repCanSeeProfit();
    return ReportScaffold(
      title: 'المرتجعات',
      subtitle: 'كل ما رجع من المبيعات: مستندات المرتجع، الراجع على الفواتير، والتخفيض بعد الحفظ',
      icon: Icons.keyboard_return_rounded,
      actions: [
        SourceMenu(value: _source, onChanged: (v) {
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
      children: _loading ? null : _content(canProfit),
    );
  }

  List<Widget> _content(bool canProfit) {
    final f = _facts;
    if (_error != null || f == null) {
      return [EmptyReport(title: 'تعذّر تحميل المرتجعات', text: _error, icon: Icons.error_outline_rounded)];
    }
    final t = f.totals();
    final onInvoices = [for (final i in f.invoices) if (i.returnAmount > 0) i]..sort((a, b) => b.date.compareTo(a.date));
    final docs = List.of(f.returns)..sort((a, b) => b.date.compareTo(a.date));
    final editsTotal = _edits.fold<double>(0, (s, e) => s + _n(e['amount_returned']));
    final all = t.invoiceReturns + t.salesReturns + editsTotal;
    final profitHit = t.invoiceReturns + (t.salesReturns - t.salesReturnsCost);
    return [
      _helpCard(),
      SetCard(
        title: 'الملخص',
        subtitle: t.sales > 0 ? 'الراجع = ${repPercent(t.totalReturns / t.sales * 100)} من مبيعات الفترة' : null,
        icon: Icons.summarize_rounded,
        color: kRepPurple,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrid(minTileWidth: 210, children: [
            KpiTile(label: 'كل ما رجع', value: all, icon: Icons.keyboard_return_rounded, color: kRepPurple, emphasis: true),
            KpiTile(
              label: 'مستندات مرتجع',
              value: t.salesReturns,
              icon: Icons.assignment_return_rounded,
              color: kRepPurple,
              hint: '${t.salesReturnsCount} مستند • البضاعة عادت للمخزن',
            ),
            KpiTile(
              label: 'الراجع على الفواتير',
              value: t.invoiceReturns,
              icon: Icons.receipt_long_rounded,
              color: kSetOrange,
              hint: '${onInvoices.length} فاتورة',
            ),
            KpiTile(
              label: 'تخفيض بعد الحفظ',
              value: editsTotal,
              icon: Icons.edit_rounded,
              color: kSetBlue,
              hint: '${_edits.length} تعديل • منقوص من المبيعات أصلاً',
            ),
            if (canProfit)
              KpiTile(
                label: 'أثرها على الربح',
                value: -profitHit,
                icon: Icons.trending_down_rounded,
                color: kSetRed,
                hint: 'الراجع على الفواتير + (المستندات − كلفة بضاعتها)',
              ),
          ]),
          if (all > 0) ...[
            const SizedBox(height: 16),
            DonutChart(
              centerTitle: 'المرتجعات',
              slices: [
                DonutSlice('مستندات مرتجع', t.salesReturns, kRepPurple),
                DonutSlice('الراجع على الفواتير', t.invoiceReturns, kSetOrange),
                DonutSlice('تخفيض بعد الحفظ', editsTotal, kSetBlue),
              ],
            ),
          ],
        ]),
      ),
      _docsCard(docs, canProfit),
      _onInvoicesCard(onInvoices),
      _editsCard(),
    ];
  }

  Widget _helpCard() {
    Widget row(IconData i, Color c, String title, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(i, size: 18, color: c),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                Text(text, style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.5)),
              ]),
            ),
          ]),
        );
    return SetCard(
      title: 'المرتجعات ≠ ميزان المراجعة',
      subtitle: 'ما الذي تعرضه هذه الشاشة؟',
      icon: Icons.help_outline_rounded,
      color: kSetBlue,
      trailing: TextButton(
        onPressed: () => setState(() => _showHelp = !_showHelp),
        child: Text(_showHelp ? 'إخفاء' : 'اشرح لي'),
      ),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 200),
        crossFadeState: _showHelp ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'هنا ما رجع من المبيعات فقط. «ميزان المراجعة» في القوائم المالية شيء آخر تماماً: ليس فيه مرتجعات.',
            style: TextStyle(color: kSetMuted),
          ),
        ),
        secondChild: Column(children: [
          const SizedBox(height: 6),
          row(Icons.assignment_return_rounded, kRepPurple, 'مستند مرتجع مبيعات',
              'تُنشئه من شاشة «مرتجع المبيعات»: العميل أعاد بضاعة، فتعود للمخزن ويُرجع له المبلغ نقداً أو يُنقص من دينه.'),
          row(Icons.receipt_long_rounded, kSetOrange, 'الراجع على الفاتورة',
              'المبلغ المكتوب في خانة «الراجع» داخل الفاتورة نفسها. يُطرح من مبيعات الفاتورة وربحها.'),
          row(Icons.edit_rounded, kSetBlue, 'تخفيض فاتورة بعد حفظها',
              'فاتورة عُدّلت بعد الحفظ فنقص مجموعها (حذف مادة أو تقليل كمية). يُعرض لمطابقة الصندوق: مالٌ خرج من الدرج بعد البيع.'),
          row(Icons.balance_rounded, kSetNavy, 'ميزان المراجعة (ليس مرتجعات)',
              'قائمة محاسبية في «القوائم المالية»: رصيد كل حساب (الصندوق، العملاء، الموردين، المبيعات…) مديناً ودائناً، '
                  'ليتأكد المحاسب أن القيود متوازنة. اسمه من «مراجعة الحسابات» لا من «الإرجاع».'),
        ]),
      ),
    );
  }

  Widget _docsCard(List<SalesReturnFact> docs, bool canProfit) => SetCard(
        title: 'مستندات مرتجع المبيعات',
        subtitle: '${docs.length} مستند',
        icon: Icons.assignment_return_rounded,
        color: kRepPurple,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: docs.isEmpty
            ? const EmptyReport(title: 'لا مستندات مرتجع في الفترة', icon: Icons.assignment_return_outlined)
            : Column(children: [
                for (final r in docs)
                  ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    shape: const Border(),
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: kRepPurple.withValues(alpha: 0.12),
                      child: const Icon(Icons.keyboard_return_rounded, size: 18, color: kRepPurple),
                    ),
                    title: Text('${r.number} — ${r.customerName}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      [
                        '${repDate(r.date)} ${repTime(r.date)}',
                        r.refundModeArabic,
                        '${r.items.length} مادة',
                        if (canProfit) 'أثر الربح ${repMoney(-r.profitImpact)}',
                      ].join(' • '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: MoneyLabel(r.total),
                    children: [
                      for (final it in r.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text(it.productName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Text('${repQty(it.soldQty.abs())} ${it.saleType}', style: const TextStyle(color: kSetMuted)),
                            const SizedBox(width: 14),
                            SizedBox(width: 110, child: Align(alignment: AlignmentDirectional.centerEnd, child: MoneyLabel(it.revenue.abs(), size: 13))),
                          ]),
                        ),
                      if ((r.notes ?? '').trim().isNotEmpty)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('ملاحظة: ${r.notes}', style: const TextStyle(fontSize: 12, color: kSetMuted)),
                        ),
                      if (r.originalInvoiceId != null)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => openReport(context, InvoiceDetailsScreen(invoiceId: r.originalInvoiceId!)),
                            icon: const Icon(Icons.receipt_long_rounded, size: 18),
                            label: const Text('فتح الفاتورة الأصلية'),
                          ),
                        ),
                    ],
                  ),
              ]),
      );

  Widget _onInvoicesCard(List<SalesInvoiceFact> list) => SetCard(
        title: 'الراجع المسجّل على الفواتير',
        subtitle: '${list.length} فاتورة فيها «راجع»',
        icon: Icons.receipt_long_rounded,
        color: kSetOrange,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: list.isEmpty
            ? const EmptyReport(title: 'لا فواتير فيها راجع', icon: Icons.receipt_long_outlined)
            : Column(children: [
                for (final i in list)
                  _Line(
                    icon: Icons.receipt_long_rounded,
                    color: kSetOrange,
                    title: '${i.displayNumber} — ${i.customerName}',
                    subtitle: '${repDate(i.date)} • مجموع الفاتورة ${repMoney(i.total)} • ${i.paymentType}',
                    amount: -i.returnAmount,
                    onTap: () => openReport(context, InvoiceDetailsScreen(invoiceId: i.id)),
                  ),
              ]),
      );

  Widget _editsCard() => SetCard(
        title: 'فواتير أُنقص مبلغها بعد الحفظ',
        subtitle: 'لمطابقة الصندوق — الضغط يفتح سجل تعديلات الفاتورة',
        icon: Icons.edit_rounded,
        color: kSetBlue,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: _edits.isEmpty
            ? const EmptyReport(title: 'لا تخفيضات بعد الحفظ', icon: Icons.edit_off_rounded)
            : Column(children: [
                for (final e in _edits)
                  _Line(
                    icon: Icons.history_rounded,
                    color: kSetBlue,
                    title: 'فاتورة ${e['invoice_number'] ?? e['invoice_id']} — ${e['customer_name'] ?? 'بدون اسم'}',
                    subtitle: [
                      _fmtDate(e['date']),
                      '${repMoney(_n(e['before_total']))} ← ${repMoney(_n(e['after_total']))}',
                      if ('${e['payment_type'] ?? ''}'.isNotEmpty) '${e['payment_type']}',
                      'بواسطة ${e['created_by'] ?? 'غير معروف'}',
                      if ('${e['notes'] ?? ''}'.trim().isNotEmpty) '${e['notes']}',
                    ].join(' • '),
                    amount: -_n(e['amount_returned']),
                    onTap: e['invoice_id'] is int
                        ? () => openReport(
                            context,
                            InvoiceHistoryScreen(
                              invoiceId: e['invoice_id'] as int,
                              customerName: e['customer_name'] as String?,
                            ))
                        : null,
                  ),
              ]),
      );

  static String _fmtDate(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '' : '${repDate(d)} ${repTime(d)}';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.title, required this.subtitle, required this.amount, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final double amount;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(children: [
            CircleAvatar(radius: 17, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kSetMuted)),
              ]),
            ),
            const SizedBox(width: 8),
            MoneyLabel(amount),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: kSetMuted, size: 20),
            ],
          ]),
        ),
      );
}
