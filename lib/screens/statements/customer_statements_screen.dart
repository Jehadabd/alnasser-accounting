// lib/screens/statements/customer_statements_screen.dart
//
// 📄 كشوفات حساب العميل في شاشة واحدة:
//   • كشف الحساب: شامل / من آخر رصيد صفر / فترة — تفصيلي أو ملخص
//   • الكشف التجاري: كم سحب بالدين وبالنقد، بالفواتير وباليد، وكم سدّد، وكل فاتورة

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection; // TextDirection من Flutter

import '../../accounting/screens/acc_ui.dart';
import '../../services/invoice_edit_log.dart';
import 'statement_engine.dart';
import 'statement_pdf.dart';

enum StatementTab { account, commercial }

const _navy = AccColors.navy;
const _debt = Color(0xFFB42318); // دين
const _pay = Color(0xFF067647); // تسديد
const _inv = Color(0xFF1D4ED8); // فاتورة
const _line = Color(0xFFE4E9F1);
const _paper = Colors.white;
const _ink = Color(0xFF1B2433);
const _muted = Color(0xFF667085);

final _nf = NumberFormat('#,##0', 'en_US');
String _m(num v) => _nf.format(v);

class CustomerStatementsScreen extends StatefulWidget {
  const CustomerStatementsScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.initialTab = StatementTab.account,
  });
  final int customerId;
  final String customerName;
  final StatementTab initialTab;

  @override
  State<CustomerStatementsScreen> createState() => _CustomerStatementsScreenState();
}

class _CustomerStatementsScreenState extends State<CustomerStatementsScreen> {
  late StatementTab _tab = widget.initialTab;
  StmtPeriodKind _pk = StmtPeriodKind.sinceZero;
  StmtDetail _detail = StmtDetail.detailed;
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  StatementResult? _acc;
  CommercialResult? _com;
  Object? _error;
  bool _loading = true;
  bool _printing = false;
  int _loadSeq = 0;
  final Set<int> _open = {}; // أسطر فواتير مفتوحة (تفصيلي)

  StmtPeriod get _period {
    switch (_pk) {
      case StmtPeriodKind.all:
        return const StmtPeriod.all();
      case StmtPeriodKind.sinceZero:
        return const StmtPeriod.sinceZero();
      case StmtPeriodKind.range:
        return StmtPeriod.range(_from, _to);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final my = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tab == StatementTab.account) {
        final r = await StatementEngine.account(
            customerId: widget.customerId, customerName: widget.customerName, period: _period, detail: _detail);
        if (!mounted || my != _loadSeq) return;
        setState(() {
          _acc = r;
          _open.clear();
          _loading = false;
        });
      } else {
        final r = await StatementEngine.commercial(
            customerId: widget.customerId, customerName: widget.customerName, period: _period);
        if (!mounted || my != _loadSeq) return;
        setState(() {
          _com = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || my != _loadSeq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      if (_tab == StatementTab.account && _acc != null) {
        final bytes = await buildAccountStatementPdf(_acc!);
        final path = await deliverStatementPdf(bytes, 'كشف_حساب_${widget.customerName}');
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حُفظ الكشف وفُتح: $path')));
        }
      } else if (_tab == StatementTab.commercial && _com != null) {
        final bytes = await buildCommercialStatementPdf(_com!);
        final path = await deliverStatementPdf(bytes, 'كشف_تجاري_${widget.customerName}');
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حُفظ الكشف وفُتح: $path')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذّرت الطباعة: $e'), backgroundColor: _debt));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        _from = d;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = d;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccColors.bg,
        appBar: accAppBar(
          widget.customerName,
          icon: Icons.receipt_long_rounded,
          subtitle: _tab == StatementTab.account ? 'كشف الحساب' : 'الكشف التجاري',
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _navy),
                onPressed: _loading || _printing ? null : _print,
                icon: _printing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_rounded, size: 19),
                label: const Text('طباعة'),
              ),
            ),
          ],
        ),
        body: Column(children: [
          _controls(),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  // ─────────────────────────── شريط الاختيارات ───────────────────────────

  Widget _controls() {
    Widget chip(String t, bool sel, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: ChoiceChip(
            avatar: icon == null ? null : Icon(icon, size: 16, color: sel ? Colors.white : _navy),
            label: Text(t),
            selected: sel,
            showCheckmark: false,
            selectedColor: _navy,
            labelStyle: TextStyle(color: sel ? Colors.white : _ink, fontWeight: FontWeight.w600),
            side: BorderSide(color: sel ? _navy : _line),
            backgroundColor: _paper,
            onSelected: (_) => onTap(),
          ),
        );
    Widget dateBtn(DateTime d, bool isFrom) => OutlinedButton.icon(
          onPressed: () => _pickDate(isFrom),
          icon: const Icon(Icons.event_rounded, size: 17),
          label: Text('${isFrom ? 'من' : 'إلى'} ${stmtDate(d)}'),
          style: OutlinedButton.styleFrom(foregroundColor: _navy, side: const BorderSide(color: _line)),
        );
    return Container(
      color: _paper,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: SegmentedButton<StatementTab>(
              segments: const [
                ButtonSegment(value: StatementTab.account, label: Text('كشف الحساب'), icon: Icon(Icons.list_alt_rounded)),
                ButtonSegment(
                    value: StatementTab.commercial, label: Text('الكشف التجاري'), icon: Icon(Icons.storefront_rounded)),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _tab = s.first);
                _load();
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip('من آخر رصيد صفر', _pk == StmtPeriodKind.sinceZero, () {
              setState(() => _pk = StmtPeriodKind.sinceZero);
              _load();
            }, icon: Icons.restart_alt_rounded),
            chip('فترة محددة', _pk == StmtPeriodKind.range, () {
              setState(() => _pk = StmtPeriodKind.range);
              _load();
            }, icon: Icons.date_range_rounded),
            chip('شامل', _pk == StmtPeriodKind.all, () {
              setState(() => _pk = StmtPeriodKind.all);
              _load();
            }, icon: Icons.all_inclusive_rounded),
            if (_tab == StatementTab.account) ...[
              Container(width: 1, height: 26, color: _line, margin: const EdgeInsets.symmetric(horizontal: 8)),
              chip('تفصيلي', _detail == StmtDetail.detailed, () {
                setState(() => _detail = StmtDetail.detailed);
                _load();
              }),
              chip('ملخص', _detail == StmtDetail.summary, () {
                setState(() => _detail = StmtDetail.summary);
                _load();
              }),
            ],
          ]),
        ),
        if (_pk == StmtPeriodKind.range) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [dateBtn(_from, true), dateBtn(_to, false)]),
        ],
        if (_tab == StatementTab.account)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _detail == StmtDetail.detailed
                  ? 'تفصيلي: كل حركة، ومواد كل فاتورة، وما عُدّل عليها.'
                  : 'ملخص: سطر واحد لكل فاتورة بصافي أثرها، بلا عمليات التعديل.',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: _debt, size: 40),
          const SizedBox(height: 8),
          Text('تعذّر بناء الكشف: $_error', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ]),
      );
    }
    return _tab == StatementTab.account ? _accountView(_acc!) : _commercialView(_com!);
  }

  // ─────────────────────────── شريط الرصيد ───────────────────────────
  //
  // العنصر الوحيد اللافت في الشاشة: من أين بدأ الرصيد، وما دخل وما خرج، وإلى أين انتهى.

  Widget _flow({required String period, required double opening, required double debit, required double credit, required double closing}) {
    Widget part(String label, String value, Color color, {bool big = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 2),
            Text(value,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: big ? 24 : 16,
                    fontWeight: big ? FontWeight.w900 : FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        );
    Widget op(String s, Color c) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(s, style: TextStyle(fontSize: 20, color: c, fontWeight: FontWeight.w300)),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(period, style: const TextStyle(fontSize: 12.5, color: _muted)),
        const SizedBox(height: 8),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, runSpacing: 8, children: [
          part('بداية الفترة', _m(opening), _ink),
          op('+', _debt),
          part('دين', _m(debit), _debt),
          op('−', _pay),
          part('تسديد', _m(credit), _pay),
          op('=', _navy),
          part('الرصيد المستحق', _m(closing), closing > 0.5 ? _debt : _pay, big: true),
        ]),
      ]),
    );
  }

  // ─────────────────────────── كشف الحساب ───────────────────────────

  Widget _accountView(StatementResult s) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: s.rows.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _flow(period: s.periodText, opening: s.opening, debit: s.debit, credit: s.credit, closing: s.closing);
        }
        if (i == 1) {
          return s.rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('لا حركات في هذه الفترة', style: TextStyle(color: _muted))),
                )
              : _ledgerHeader();
        }
        return _ledgerRow(s, i - 2);
      },
    );
  }

  Widget _ledgerHeader() => const Padding(
        padding: EdgeInsets.fromLTRB(26, 8, 26, 4),
        child: Row(children: [
          SizedBox(width: 78, child: Text('التاريخ', style: TextStyle(fontSize: 12, color: _muted))),
          Expanded(child: Text('البيان', style: TextStyle(fontSize: 12, color: _muted))),
          SizedBox(width: 110, child: Text('المبلغ', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: _muted))),
          SizedBox(width: 110, child: Text('الرصيد', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: _muted))),
        ]),
      );

  Color _kindColor(StmtKind k, double amount) {
    switch (k) {
      case StmtKind.invoice:
        return _inv;
      case StmtKind.invoiceEdit:
        return const Color(0xFF7A5AF8);
      default:
        return amount >= 0 ? _debt : _pay;
    }
  }

  Widget _ledgerRow(StatementResult s, int idx) {
    final r = s.rows[idx];
    final c = _kindColor(r.kind, r.amount);
    final expandable = s.detail == StmtDetail.detailed && r.showInvoiceBody && r.invoice != null;
    final open = _open.contains(idx);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 3, color: c), // الحافة الملونة = نوع الحركة
          Expanded(child: Column(children: [
        InkWell(
          onTap: expandable ? () => setState(() => open ? _open.remove(idx) : _open.add(idx)) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 78,
                child: Text(stmtDate(r.date),
                    style: const TextStyle(fontSize: 12.5, color: _muted, fontFeatures: [FontFeature.tabularFigures()])),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(r.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: _ink, fontSize: 14)),
                    ),
                    if (expandable)
                      Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: _muted),
                  ]),
                  if ((r.note ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(r.note!, style: const TextStyle(fontSize: 12.5, color: _muted)),
                    ),
                ]),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  r.amount == 0 ? '0' : '${r.amount > 0 ? '+' : '−'}${_m(r.amount.abs())}',
                  textAlign: TextAlign.end,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: r.amount >= 0 ? _debt : _pay,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(_m(r.balanceAfter),
                    textAlign: TextAlign.end,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: _ink, fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        ),
        if (expandable && open) _invoiceBody(r.invoice!),
      ])),
        ]),
      ),
    );
  }

  Widget _invoiceBody(StmtInvoice inv) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in inv.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(l.name, style: const TextStyle(fontSize: 13))),
              Text('${NumberFormat('#,##0.###', 'en_US').format(l.qty)} ${l.unit} × ${_m(l.price)}',
                  style: const TextStyle(fontSize: 12.5, color: _muted)),
              SizedBox(
                width: 100,
                child: Text(_m(l.total),
                    textAlign: TextAlign.end, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13)),
              ),
            ]),
          ),
        if (inv.discount > 0 || inv.loadingFee > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [if (inv.discount > 0) 'خصم ${_m(inv.discount)}', if (inv.loadingFee > 0) 'أجور ${_m(inv.loadingFee)}']
                  .join('   '),
              style: const TextStyle(fontSize: 12.5, color: _muted),
            ),
          ),
        if (inv.edits.isNotEmpty) ...[
          const Divider(height: 14),
          const Text('ما عُدّل على الفاتورة بعد حفظها',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
          for (final e in inv.edits)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                _kindTag(e.kind),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${e.productName}: ${NumberFormat('#,##0.###', 'en_US').format(e.qtyBefore)} ← '
                    '${NumberFormat('#,##0.###', 'en_US').format(e.qtyAfter)} ${e.unit}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Text('${e.amountDelta >= 0 ? '+' : '−'}${_m(e.amountDelta.abs())}',
                    textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _kindTag(String kind) {
    final c = kind == InvoiceEditLog.kindAdd
        ? _inv
        : (kind == InvoiceEditLog.kindReturn ? const Color(0xFFB54708) : const Color(0xFF7A5AF8));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
      child: Text(kind, style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w700)),
    );
  }

  // ─────────────────────────── الكشف التجاري ───────────────────────────

  Widget _commercialView(CommercialResult r) {
    Widget kv(String k, String v, {Color? color, bool strong = false, String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: TextStyle(fontSize: 13.5, color: _ink, fontWeight: strong ? FontWeight.w700 : null)),
                if (hint != null) Text(hint, style: const TextStyle(fontSize: 11.5, color: _muted)),
              ]),
            ),
            Text(v,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: strong ? 16 : 14,
                    fontWeight: FontWeight.w800,
                    color: color ?? _ink,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    Widget block(String title, IconData icon, Color c, List<Widget> children) => Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: _paper,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 19, color: c),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
            ]),
            const Divider(height: 14),
            ...children,
          ]),
        );

    final blocks = [
      block('سحب بالدين', Icons.credit_card_rounded, _debt, [
        kv('فواتير بالدين', _m(r.debtInvoicesTotal), strong: true, hint: '${r.debtInvoices.length} فاتورة'),
        kv('مسدد على الفواتير نفسها', _m(r.debtInvoicesPaid), color: _muted),
        kv('المتبقي منها على حسابه', _m(r.debtInvoicesRemaining), color: _debt),
        kv('معاملات دين يدوية', _m(r.manualDebt), strong: true, hint: '${r.manualDebtCount} معاملة'),
      ]),
      block('سحب بالنقد', Icons.payments_rounded, _inv, [
        kv('فواتير نقد', _m(r.cashInvoicesTotal), strong: true, hint: '${r.cashInvoices.length} فاتورة'),
        kv('معاملات نقد يدوية', 'لا يوجد', color: _muted, hint: 'النقد يُسجَّل بالفواتير فقط'),
        if (r.cashReturnsCount > 0)
          kv('مرتجع رُدّ له نقداً', _m(r.cashReturns), hint: '${r.cashReturnsCount} سند — من الصندوق'),
      ]),
      block('ما نزل من حسابه', Icons.south_west_rounded, _pay, [
        kv('تسديدات', _m(r.payments), strong: true, color: _pay, hint: '${r.paymentCount} تسديد'),
        if (r.discounts > 0) kv('خصومات مسموحة', _m(r.discounts)),
        if (r.returnsCredit > 0) kv('مرتجعات نزلت من حسابه', _m(r.returnsCredit)),
        if (r.otherCount > 0) kv('تصحيحات وأرصدة', _m(r.other), hint: '${r.otherCount} حركة'),
      ]),
    ];

    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      _flow(
        period: r.periodText,
        opening: r.opening,
        debit: r.windowDebit,
        credit: r.windowCredit,
        closing: r.closing,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 980 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
          final w = (c.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [for (final b in blocks) SizedBox(width: w, child: b)]);
        }),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Expanded(
              child: Text('مجموع ما سحبه في الفترة (دين + نقد)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            Text(_m(r.totalWithdrawn),
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
        ),
      ),
      if (r.editReturns > 0 || r.editAdds > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'تعديلات على هذه الفواتير بعد حفظها: '
            '${r.editAdds > 0 ? 'إضافات ${_m(r.editAdds)}' : ''}'
            '${r.editAdds > 0 && r.editReturns > 0 ? '، ' : ''}'
            '${r.editReturns > 0 ? 'مرتجعات ${_m(r.editReturns)}' : ''}'
            ' — محسوبة داخل إجمالي كل فاتورة.',
            style: const TextStyle(fontSize: 12.5, color: _muted),
          ),
        ),
      _invoiceList('فواتير الدين', r.debtInvoices, true),
      _invoiceList('فواتير النقد', r.cashInvoices, false),
    ]);
  }

  Widget _invoiceList(String title, List<StmtInvoice> list, bool debt) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text('$title — ${list.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
        ),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text('لا توجد في هذه الفترة', style: TextStyle(color: _muted)),
          )
        else
          for (final i in list)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                title: Row(children: [
                  SizedBox(
                    width: 84,
                    child: Text(stmtDate(i.date), style: const TextStyle(fontSize: 12.5, color: _muted)),
                  ),
                  Expanded(
                    child: Text('فاتورة ${i.number}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                  ),
                  Text(_m(i.total),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontWeight: FontWeight.w800, color: debt ? _debt : _inv)),
                ]),
                subtitle: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 84),
                  child: Text(
                    [
                      '${i.lines.length} مادة',
                      if (debt && i.paid > 0) 'مسدد ${_m(i.paid)}',
                      if (debt) 'متبقٍ ${_m(i.remaining)}',
                      if (i.editReturns > 0) 'مرتجع ${_m(i.editReturns)}',
                      if (i.editAdds > 0) 'إضافة ${_m(i.editAdds)}',
                    ].join('  •  '),
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
                children: [_invoiceBody(i)],
              ),
            ),
      ]),
    );
  }
}
