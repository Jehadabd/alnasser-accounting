// lib/screens/day_close_screen.dart
//
// 🧾 إقفال اليوم — ما يجب أن يكون في الدرج، ومطابقته مع المعدود:
//   رصيد البداية + المقبوض نقداً − المدفوع نقداً ± سندات الصناديق = المتوقع.
//   المعدود − المتوقع = الفرق (زيادة أو نقص).
// المصدر: كل الأجهزة / هذا الجهاز / المزامنة (من رأس الشاشة). الأرقام من المحرك
// الموحّد (CashFlow) — للقراءة فقط: لا يكتب في القاعدة، ورصيد البداية والمعدود
// لا يُحفظان (للطباعة فقط).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../erp/report_export.dart';
import '../erp/sales/doc_pdf.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'report_parts.dart';
import 'transactions_list_dialog.dart';

class DayCloseScreen extends StatefulWidget {
  const DayCloseScreen({super.key, this.initialDate});
  final DateTime? initialDate;

  @override
  State<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends State<DayCloseScreen> {
  final _svc = ReportsService();
  final _opening = TextEditingController();
  final _counted = TextEditingController();
  late DateTime _day;
  String _source = ReportSource.all;
  SalesFacts? _facts;
  Map<String, dynamic>? _summary;
  CashFlow? _cash;
  bool _loading = true;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime.now();
    _day = DateTime(d.year, d.month, d.day);
    if (_day.isAfter(_today)) _day = _today;
    _opening.addListener(_redraw);
    _counted.addListener(_redraw);
    _load();
  }

  @override
  void dispose() {
    _opening.dispose();
    _counted.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _load() async {
    final t = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _svc.reportSourceFilter = _source;
      final facts = await _svc.loadFacts(from: _day, to: _day);
      final summary = await _svc.getPeriodSummary(startDate: _day, endDate: _day);
      final cash = await _svc.cashFlow(facts, from: _day, to: _day);
      if (!mounted || t != _token) return;
      setState(() {
        _facts = facts;
        _summary = summary;
        _cash = cash;
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

  void _go(DateTime d) {
    _day = DateTime(d.year, d.month, d.day);
    _load();
  }

  static double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;
  bool get _hasCount => _counted.text.trim().isNotEmpty;
  double get _expected => _num(_opening) + (_cash?.drawerNet ?? 0);
  double get _diff => _num(_counted) - _expected;

  String get _sourceLabel => switch (_source) {
        ReportSource.thisDevice => 'هذا الجهاز',
        ReportSource.sync => 'المزامنة',
        _ => 'كل الأجهزة',
      };

  @override
  Widget build(BuildContext context) {
    return ReportScaffold(
      title: 'إقفال اليوم',
      subtitle: 'ما يجب أن يكون في الدرج، ومطابقته مع المعدود',
      icon: Icons.point_of_sale_rounded,
      actions: [
        SourceMenu(
            value: _source,
            onChanged: (v) {
              _source = v;
              _load();
            }),
        IconButton(
          tooltip: 'طباعة / PDF',
          onPressed: _loading || _cash == null ? null : _print,
          icon: const Icon(Icons.print_rounded),
        ),
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      header: PeriodNavigator(
        label: '${repWeekday(_day)} ${repDate(_day)}',
        caption: _day == _today ? 'اليوم — لم ينتهِ بعد' : null,
        onPrev: () => _go(_day.subtract(const Duration(days: 1))),
        onNext: () => _go(DateTime(_day.year, _day.month, _day.day + 1)),
        onPick: () async {
          final d = await pickReportDay(context, _day);
          if (d != null) _go(d);
        },
        canNext: _day.isBefore(_today),
        trailing: _day == _today
            ? null
            : TextButton.icon(
                onPressed: () => _go(_today),
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('اليوم'),
              ),
      ),
      loading: _loading,
      children: _loading ? null : _content(),
    );
  }

  List<Widget> _content() {
    final c = _cash, s = _summary, f = _facts;
    if (_error != null || c == null || s == null || f == null) {
      return [EmptyReport(title: 'تعذّر تحميل الإقفال', text: _error, icon: Icons.error_outline_rounded)];
    }
    double n(String k) => (s[k] as num?)?.toDouble() ?? 0;
    final credit = n('creditSales');
    final down = (n('paidAmount') - n('cashSales')).clamp(0, double.infinity).toDouble();
    return [
      KpiGrid(minTileWidth: 210, children: [
        KpiTile(
          label: 'المتوقع في الدرج',
          value: _expected,
          icon: Icons.inventory_rounded,
          emphasis: true,
          color: kSetNavy,
          hint: _num(_opening) > 0 ? 'رصيد البداية ${repMoney(_num(_opening))} + صافي اليوم' : 'صافي حركة اليوم',
        ),
        KpiTile(label: 'المقبوض نقداً', value: c.salesCashIn + c.voucherIn, icon: Icons.south_west_rounded, color: kSetGreen),
        KpiTile(label: 'المدفوع نقداً', value: c.salesCashOut + c.voucherOut, icon: Icons.north_east_rounded, color: kSetRed),
        if (_hasCount)
          KpiTile(
            label: _diff.abs() < 1 ? 'مطابق' : (_diff > 0 ? 'زيادة في الدرج' : 'نقص في الدرج'),
            value: _diff.abs(),
            icon: _diff.abs() < 1 ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            emphasis: true,
            color: _diff.abs() < 1 ? kSetGreen : (_diff > 0 ? kSetOrange : kSetRed),
            hint: 'المعدود ${repMoney(_num(_counted))}',
          ),
      ]),
      const SizedBox(height: 14),
      _countCard(),
      SetCard(
        title: 'المقبوض نقداً',
        subtitle: 'كل مبلغ دخل الدرج اليوم',
        icon: Icons.south_west_rounded,
        color: kSetGreen,
        child: Column(children: [
          const SizedBox(height: 4),
          _line('فواتير نقدية', c.cashInvoices, c.cashInvoicesCount,
              hint: c.laterEditsAdjust.abs() >= 1 ? 'بمبلغها قبل تعديلات لاحقة' : null),
          _line('مدفوع عند البيع من فواتير آجلة', c.downPayments, c.downPaymentsCount),
          _line('فواتير آجلة سابقة حُوّلت إلى نقد', c.conversions, c.conversionsCount),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => TransactionsListDialog.showDebtPayments(
                context: context, startDate: _day, endDate: _day, periodTitle: repDate(_day), sourceFilter: _source),
            child: _line('تسديد ديون نقدي', c.debtPayments, c.debtPaymentsCount, hint: 'اضغط للقائمة'),
          ),
          _line('سندات قبض لتعديل فواتير سابقة', c.editReceipts, c.editReceiptsCount),
          if (c.vouchersIncluded) _line('سندات الصناديق (قبض، إيراد، تحويل من البنك)', c.voucherIn, c.voucherInCount),
          const Divider(height: 18),
          ReportLine('= المقبوض', c.salesCashIn + c.voucherIn, bold: true, color: kSetGreen),
        ]),
      ),
      SetCard(
        title: 'المدفوع نقداً',
        subtitle: 'كل مبلغ خرج من الدرج اليوم',
        icon: Icons.north_east_rounded,
        color: kSetRed,
        child: Column(children: [
          const SizedBox(height: 4),
          _line('مرتجعات مبيعات نقداً', c.cashRefunds, c.cashRefundsCount),
          _line('سندات صرف لتعديل فواتير سابقة', c.editRefunds, c.editRefundsCount),
          if (c.vouchersIncluded) _line('سندات الصناديق (مصروف، صرف، تحويل للبنك)', c.voucherOut, c.voucherOutCount),
          const Divider(height: 18),
          ReportLine('= المدفوع', c.salesCashOut + c.voucherOut, bold: true, color: kSetRed),
        ]),
      ),
      SetCard(
        title: 'للعلم — لا يدخل الدرج',
        subtitle: 'حركات اليوم التي لا تحرّك النقد',
        icon: Icons.info_outline_rounded,
        color: kSetMuted,
        child: Column(children: [
          const SizedBox(height: 4),
          ReportLine('مبيعات اليوم (صافي)', n('netSales'), hint: '${n('invoiceCount').toInt()} فاتورة'),
          ReportLine('بيع آجل لم يُدفع', (credit - down).clamp(0, double.infinity).toDouble()),
          ReportLine('ديون يدوية أُضيفت', n('totalManualDebt'), hint: '${n('manualDebtCount').toInt()} معاملة'),
          if (c.nonCashPayments.abs() >= 1)
            ReportLine('تسديدات غير نقدية (خصم، صك، تسوية، بنك)', c.nonCashPayments, hint: '${c.nonCashPaymentsCount} حركة'),
          if (n('totalManualPaymentReturn').abs() >= 1)
            ReportLine('مرتجعات على الحساب (دين راجع)', n('totalManualPaymentReturn')),
          if (n('totalDiscount').abs() >= 1) ReportLine('خصومات الفواتير', n('totalDiscount')),
        ]),
      ),
      SetBanner(
        [
          'كيف يُحسب: الفاتورة النقدية في يومها، والآجلة بما دُفع عند البيع، والآجلة التي حُوّلت إلى نقد لاحقاً في يوم التحويل.',
          'تسديد الدين يُعدّ نقداً إلا إذا سُجّل خصماً أو صكاً أو تسوية أو على صندوق بنك.',
          if (!c.vouchersIncluded) 'سندات الصناديق (مصاريف، قبض، صرف) تُحسب مع «كل الأجهزة» فقط لأنها لا تحمل اسم الجهاز.',
          'مدفوعات الموردين والمشتريات غير محسوبة هنا.',
        ].join('\n'),
      ),
    ];
  }

  Widget _line(String label, double v, int count, {String? hint}) {
    if (v.abs() < 1 && count == 0) return const SizedBox.shrink();
    return ReportLine(label, v, hint: [if (count > 0) '$count حركة', if (hint != null) hint].join(' • '));
  }

  Widget _countCard() {
    InputDecoration deco(String label, String help) => InputDecoration(
          labelText: label,
          helperText: help,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
          suffixText: 'د.ع',
        );
    return SetCard(
      title: 'عدّ الدرج',
      subtitle: 'اكتب رصيد البداية وما عددته الآن — لا يُحفظ، للطباعة والمطابقة فقط',
      icon: Icons.calculate_rounded,
      color: kSetBlue,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _opening,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textDirection: TextDirection.ltr,
              decoration: deco('رصيد بداية الدرج', 'ما كان في الدرج صباحاً'),
            ),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _counted,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textDirection: TextDirection.ltr,
              decoration: deco('المعدود فعلاً', 'ما في الدرج الآن'),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _print() async {
    final c = _cash;
    final s = _summary;
    if (c == null || s == null) return;
    String m(double v) => repMoney(v);
    final rows = <List<String>>[];
    void add(String label, double v, int count, {bool out = false}) {
      if (v.abs() < 1 && count == 0) return;
      rows.add(['${rows.length + 1}', label, count > 0 ? '$count' : '', out ? '− ${m(v)}' : m(v)]);
    }

    add('فواتير نقدية', c.cashInvoices, c.cashInvoicesCount);
    add('مدفوع عند البيع من فواتير آجلة', c.downPayments, c.downPaymentsCount);
    add('فواتير آجلة حُوّلت إلى نقد', c.conversions, c.conversionsCount);
    add('تسديد ديون نقدي', c.debtPayments, c.debtPaymentsCount);
    add('سندات قبض لتعديل فواتير', c.editReceipts, c.editReceiptsCount);
    if (c.vouchersIncluded) add('سندات الصناديق (داخل)', c.voucherIn, c.voucherInCount);
    add('مرتجعات مبيعات نقداً', c.cashRefunds, c.cashRefundsCount, out: true);
    add('سندات صرف لتعديل فواتير', c.editRefunds, c.editRefundsCount, out: true);
    if (c.vouchersIncluded) add('سندات الصناديق (خارج)', c.voucherOut, c.voucherOutCount, out: true);

    try {
      final bytes = await DocPdf.build(
        title: 'إقفال اليوم',
        number: repDate(_day),
        date: _day,
        partyLabel: 'المصدر',
        partyName: _sourceLabel,
        infos: [
          MapEntry('رصيد بداية الدرج', m(_num(_opening))),
          MapEntry('صافي حركة اليوم', m(c.drawerNet)),
          MapEntry('المتوقع في الدرج', m(_expected)),
          if (_hasCount) MapEntry('المعدود فعلاً', m(_num(_counted))),
          if (_hasCount) MapEntry(_diff.abs() < 1 ? 'الفرق' : (_diff > 0 ? 'زيادة' : 'نقص'), m(_diff.abs())),
        ],
        headers: const ['#', 'البند', 'العدد', 'المبلغ'],
        rows: rows,
        total: _expected,
        showWords: false,
      );
      if (mounted) await ReportExport.openPdf(context, bytes, 'إقفال ${repDate(_day).replaceAll('/', '-')}');
    } catch (e) {
      if (mounted) setToast(context, 'تعذّرت الطباعة: $e', error: true);
    }
  }
}
