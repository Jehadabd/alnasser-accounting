// lib/screens/period_extras.dart
//
// ➕ إضافات تُوضع داخل شاشات التقارير الموجودة (اليوم، الأسبوع، الشهر، السنة،
// الفترة المخصصة) بدل شاشة منفصلة:
//   • «ماذا حدث؟» — جمل قصيرة تشرح الأرقام (period_insights.dart).
//   • «المال الفعلي» — المقبوض فعلاً وتغيّر الديون، والضغط يشرح كيف حُسب كل رقم،
//     مع شرح المبيعات والربح بأسطر جمع.
// المقارنة عادلة: الفترة التي لم تنتهِ تُقارن بنفس عدد أيامها من الفترة السابقة،
// واليوم/الأسبوع بمعدل آخر 4. يحمّل بياناته بنفسه — للقراءة فقط.

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import 'day_close_screen.dart';
import 'invoice_details_screen.dart';
import 'period_insights.dart';
import 'report_parts.dart';
import 'returns_report_screen.dart';
import 'transactions_list_dialog.dart';

enum ExtrasKind { day, week, month, year, custom }

class PeriodExtras extends StatefulWidget {
  const PeriodExtras({
    super.key,
    required this.kind,
    required this.from,
    required this.to,
    required this.title,
    this.source = ReportSource.all,
    this.showInsights = true,
  });

  final ExtrasKind kind;
  final DateTime from;

  /// نهاية الفترة الطبيعية (قد تكون بعد اليوم: الأسبوع/الشهر الحالي).
  final DateTime to;

  /// اسم الفترة كما في الشاشة (يظهر في نوافذ الشرح).
  final String title;
  final String source;

  /// السنة لها «رؤى» خاصة بها، فتُخفى هناك.
  final bool showInsights;

  @override
  State<PeriodExtras> createState() => _PeriodExtrasState();
}

class _PeriodExtrasState extends State<PeriodExtras> {
  final _svc = ReportsService();
  PeriodData? _d;
  CashFlow? _cash;
  CashFlow? _prevCash;
  String _prevLabel = '';
  List<PeriodInsight> _insights = const [];
  bool _loading = true;
  String? _error;
  int _token = 0;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _today() => _day(DateTime.now());
  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  static int _span(DateTime a, DateTime b) => _day(b).difference(_day(a)).inDays + 1;

  DateTime get _from => _day(widget.from);
  DateTime get _to => _min(_day(widget.to), _today());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PeriodExtras old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to || old.source != widget.source || old.kind != widget.kind) {
      _load();
    }
  }

  /// الفترة السابقة بنفس عدد الأيام المنقضية.
  ({DateTime pFrom, DateTime pTo, String pLabel}) _prev(DateTime from, DateTime to, bool inProgress) {
    final same = inProgress ? ' (نفس الأيام)' : '';
    final k = widget.kind;
    if (k == ExtrasKind.day) {
      final w = _addDays(from, -7);
      return (pFrom: w, pTo: w, pLabel: '${repWeekday(from)} الماضي');
    }
    if (k == ExtrasKind.week) {
      final s = _addDays(from, -7);
      return (pFrom: s, pTo: _addDays(s, _span(from, to) - 1), pLabel: 'الأسبوع الماضي$same');
    }
    if (k == ExtrasKind.month) {
      // نفس اليوم من الشهر الماضي (أو آخره إن كان أقصر)
      final pTo = _min(DateTime(from.year, from.month - 1, to.day), DateTime(from.year, from.month, 0));
      return (pFrom: DateTime(from.year, from.month - 1, 1), pTo: pTo, pLabel: 'الشهر الماضي$same');
    }
    if (k == ExtrasKind.year) {
      final pTo = _min(DateTime(from.year - 1, to.month, to.day), DateTime(from.year - 1, to.month + 1, 0));
      return (pFrom: DateTime(from.year - 1, 1, 1), pTo: pTo, pLabel: 'السنة الماضية$same');
    }
    final n = _span(from, to);
    final pTo = _addDays(from, -1);
    return (pFrom: _addDays(pTo, -(n - 1)), pTo: pTo, pLabel: 'الفترة السابقة ($n يوم)');
  }

  Future<void> _load() async {
    final t = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _svc.reportSourceFilter = widget.source;
      final from = _from, to = _to;
      if (to.isBefore(from)) {
        if (mounted && t == _token) setState(() => _loading = false);
        return;
      }
      final inProgress = _day(widget.to).isAfter(to);
      final pr = _prev(from, to, inProgress);
      final d = await PeriodData.load(_svc, from: from, to: to, prevFrom: pr.pFrom, prevTo: pr.pTo);
      final cash = await _svc.cashFlow(d.facts, from: from, to: to);
      final prevFacts = await _svc.loadFacts(from: pr.pFrom, to: pr.pTo);
      final prevCash = await _svc.cashFlow(prevFacts, from: pr.pFrom, to: pr.pTo);

      var insights = const <PeriodInsight>[];
      if (widget.showInsights) {
        // المعتاد: اليوم/الأسبوع = معدل آخر 4 (بنفس الأيام)، غيرهما = الفترة السابقة
        var baseNet = (d.prev['netSales'] as num?)?.toDouble() ?? 0;
        var baseLabel = pr.pLabel;
        final weekly = widget.kind == ExtrasKind.day || widget.kind == ExtrasKind.week;
        if (weekly) {
          var sum = 0.0;
          for (var k = 1; k <= 4; k++) {
            final m = await _svc.getPeriodSummary(startDate: _addDays(from, -7 * k), endDate: _addDays(to, -7 * k));
            sum += (m['netSales'] as num?)?.toDouble() ?? 0;
          }
          baseNet = sum / 4;
          baseLabel = widget.kind == ExtrasKind.day ? 'معدل آخر 4 أيام ${repWeekday(from)}' : 'معدل آخر 4 أسابيع';
        }
        final names = <int, String>{};
        final parents = <int, int?>{};
        try {
          for (final c in await _svc.getCategories()) {
            names[c.id] = c.name;
            parents[c.id] = c.parentId;
          }
        } catch (_) {}
        var absent = <AbsentCustomer>[];
        if (!inProgress && (widget.kind == ExtrasKind.week || widget.kind == ExtrasKind.month)) {
          absent = await _absentCustomers(d.facts, from);
        }
        insights = buildPeriodInsights(
          s: d.summary,
          prev: d.prev,
          prevLabel: pr.pLabel,
          baseNet: baseNet,
          baseLabel: baseLabel,
          facts: d.facts,
          prevFacts: prevFacts,
          catNames: names,
          catParents: parents,
          cash: cash,
          canProfit: repCanSeeProfit(),
          inProgress: inProgress,
          dayMode: widget.kind == ExtrasKind.day,
          yearMode: widget.kind == ExtrasKind.year || (widget.kind == ExtrasKind.custom && _span(from, to) > 62),
          absent: absent,
        );
      }
      if (!mounted || t != _token) return;
      setState(() {
        _d = d;
        _cash = cash;
        _prevCash = prevCash;
        _prevLabel = pr.pLabel;
        _insights = insights;
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

  /// عملاء (ببطاقة) اشتروا في فترتين على الأقل من الثلاث السابقة وبثلاث فواتير، ولم يشتروا في هذه.
  Future<List<AbsentCustomer>> _absentCustomers(SalesFacts cur, DateTime from) async {
    final week = widget.kind == ExtrasKind.week;
    final hFrom = week ? _addDays(from, -21) : DateTime(from.year, from.month - 3, 1);
    final hist = await _svc.loadFacts(from: hFrom, to: _addDays(from, -1));
    int periodOf(DateTime d) {
      final x = _day(d);
      return week
          ? (from.difference(x).inDays - 1) ~/ 7
          : (from.year * 12 + from.month) - (x.year * 12 + x.month) - 1;
    }

    final now = {for (final i in cur.invoices) if ((i.customerId ?? 0) > 0) i.customerId!};
    final map = <int, AbsentCustomer>{};
    for (final i in hist.invoices) {
      final id = i.customerId ?? 0;
      if (id <= 0 || now.contains(id)) continue;
      final a = map.putIfAbsent(id, () => AbsentCustomer(id, i.customerName));
      a.sales += i.netSales;
      a.invoices++;
      a.periods.add(periodOf(i.date));
    }
    final list = map.values.where((a) => a.periods.length >= 2 && a.invoices >= 3).toList()
      ..sort((a, b) => b.sales.compareTo(a.sales));
    return list.take(5).toList();
  }

  // ─────────────────────────── العرض ───────────────────────────

  static double _n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble() ?? 0.0;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SetCard(
        title: widget.showInsights ? 'ماذا حدث؟' : 'المال الفعلي',
        subtitle: 'جارٍ تحليل الفترة…',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF7C3AED),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: LinearProgressIndicator(minHeight: 3),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SetBanner('تعذّر تحليل الفترة: $_error', kind: SetBannerKind.error),
      );
    }
    final d = _d, c = _cash;
    if (d == null || c == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showInsights) PeriodInsightsCard(items: _insights),
      _moneyCard(d, c),
    ]);
  }

  Widget _moneyCard(PeriodData d, CashFlow c) {
    final canProfit = repCanSeeProfit();
    final end = c.debtEnd;
    final prev = _prevCash;
    return SetCard(
      title: 'المال الفعلي',
      subtitle: 'ما دخل الصندوق وما تغيّر في الديون — اضغط على أي رقم لترى كيف حُسب',
      icon: Icons.account_balance_wallet_rounded,
      color: kRepTeal,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KpiGrid(minTileWidth: 240, children: [
          KpiTile(
            label: 'المقبوض فعلاً',
            value: c.netCollected,
            icon: Icons.payments_rounded,
            emphasis: true,
            color: kRepTeal,
            delta: prev == null ? null : pctChange(c.netCollected, prev.netCollected),
            hint: 'نقد الفواتير + تسديد الديون − المردود • مقارنة بـ$_prevLabel',
            onTap: () => _explainCash(c),
          ),
          KpiTile(
            label: c.debtChange > 0.5 ? 'الديون زادت' : (c.debtChange < -0.5 ? 'الديون نقصت' : 'تغيّر الديون'),
            value: c.debtChange.abs(),
            icon: Icons.account_balance_rounded,
            emphasis: true,
            color: c.debtChange > 0.5 ? kSetOrange : const Color(0xFF475569),
            hint: end != null
                ? 'مجموع الديون في نهاية الفترة ${repMoney(end)}'
                : 'زاد ${repMoney(c.debtIncrease)} • نقص ${repMoney(-c.debtDecrease)}',
            onTap: () => _explainDebts(c),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 4, children: [
          TextButton.icon(
            onPressed: () => _explainSales(d),
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: const Text('كيف حُسب صافي المبيعات؟'),
          ),
          if (canProfit)
            TextButton.icon(
              onPressed: () => _explainProfit(d),
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: const Text('كيف حُسب الربح؟'),
            ),
        ]),
      ]),
    );
  }

  // ─────────────────────────── «كيف حُسب؟» ───────────────────────────

  void _explain({
    required String title,
    required IconData icon,
    required Color color,
    required String what,
    required List<Widget> lines,
    List<String> notes = const [],
    List<(String, IconData, VoidCallback)> actions = const [],
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kSetText)),
                    Text(widget.title, style: const TextStyle(fontSize: 12, color: kSetMuted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text(what, style: const TextStyle(color: kSetMuted, height: 1.6)),
              const Divider(height: 24),
              ...lines,
              for (final n in notes) Padding(padding: const EdgeInsets.only(top: 10), child: SetBanner(n)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in actions)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        a.$3();
                      },
                      icon: Icon(a.$2, size: 18),
                      label: Text(a.$1),
                    ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  void _explainSales(PeriodData d) {
    final s = d.summary;
    final gross = _n(s, 'grossSales'), disc = _n(s, 'totalDiscount'), load = _n(s, 'totalLoadingFees');
    final total = _n(s, 'totalSales');
    final adj = total - (gross - disc + load);
    final invRet = _n(s, 'invoiceReturns'), docRet = _n(s, 'salesReturns');
    final edits = _n(s, 'editReturns');
    final from = _from, to = _to;
    _explain(
      title: 'صافي المبيعات',
      icon: Icons.point_of_sale_rounded,
      color: kSetNavy,
      what: 'مجموع الفواتير المحفوظة في الفترة بعد الخصم وأجور التحميل والتعديلات، ناقص ما رجع منها. '
          'الفاتورة تُحسب في يوم تاريخها، والمعلّقة والمحذوفة لا تُحسب.',
      lines: [
        ReportLine('مجموع المواد قبل الخصم', gross, icon: Icons.inventory_2_rounded),
        if (disc.abs() >= 1) ReportLine('− خصم الفواتير', -disc),
        if (load.abs() >= 1) ReportLine('+ أجور التحميل', load),
        if (adj.abs() >= 1) ReportLine('± تسويات بعد الحفظ', adj, hint: 'الفرق بين مجموع البنود ومجموع الفواتير المحفوظ'),
        ReportLine('= مجموع الفواتير', total, bold: true, hint: '${_n(s, 'invoiceCount').toInt()} فاتورة'),
        if (invRet.abs() >= 1) ReportLine('− راجع مسجّل على الفواتير', -invRet),
        if (docRet.abs() >= 1) ReportLine('− مستندات مرتجع المبيعات', -docRet, hint: '${_n(s, 'salesReturnsCount').toInt()} مستند'),
        const Divider(height: 18),
        ReportLine('= صافي المبيعات', _n(s, 'netSales'), bold: true, color: kSetNavy),
      ],
      notes: [
        if (edits > 0)
          'و${repMoney(edits)} أُرجعت بحذف مواد من فواتير بعد حفظها — منقوصة من «مجموع الفواتير» أعلاه أصلاً، '
              'فلا تُطرح مرة ثانية.',
      ],
      actions: [
        ('المرتجعات', Icons.keyboard_return_rounded, () => openReport(context, ReturnsReportScreen(from: from, to: to))),
      ],
    );
  }

  void _explainProfit(PeriodData d) {
    final s = d.summary;
    final profit = _n(s, 'netProfit');
    final manual = _n(s, 'manualDebtProfit');
    final manualDebt = _n(s, 'totalManualDebt');
    final losses = d.facts.invoices.where((i) => i.profit < -0.5).toList()..sort((a, b) => a.profit.compareTo(b.profit));
    _explain(
      title: 'الربح المؤكد',
      icon: Icons.trending_up_rounded,
      color: kSetGreen,
      what: 'صافي المبيعات ناقص كلفة المواد المباعة. الكلفة من سعر الكلفة المحفوظ مع كل سطر فاتورة، وإن لم يُحفظ '
          'فكلفة المادة الحالية، وإن لم توجد فنسبة الربح الافتراضية من الإعدادات.',
      lines: [
        ReportLine('صافي المبيعات', _n(s, 'netSales')),
        ReportLine('− كلفة المواد المباعة', -_n(s, 'totalCost'), hint: 'بعد إرجاع كلفة البضاعة العائدة'),
        const Divider(height: 18),
        ReportLine('= الربح المؤكد', profit,
            bold: true, color: kSetGreen, hint: 'هامش ${repPercent(_n(s, 'profitMargin'))}'),
        if (manual.abs() >= 1) ...[
          const SizedBox(height: 8),
          ReportLine('ربح الدين اليدوي (تقديري)', manual,
              icon: Icons.percent_rounded,
              hint: manualDebt > 0
                  ? '${(manual / manualDebt * 100).toStringAsFixed(0)}% ثابتة من الإعدادات على ديون يدوية ${repMoney(manualDebt)} — غير داخل أعلاه'
                  : 'غير داخل أعلاه'),
          ReportLine('الربح مع التقديري', profit + manual, bold: true),
        ],
        if (losses.isNotEmpty) ...[
          const Divider(height: 22),
          Text('فواتير بيعت بأقل من الكلفة (${losses.length})',
              style: const TextStyle(fontWeight: FontWeight.w800, color: kSetRed)),
          for (final i in losses.take(15))
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openReport(context, InvoiceDetailsScreen(invoiceId: i.id)),
              child: ReportLine('${i.displayNumber} • ${i.customerName}', i.profit,
                  icon: Icons.warning_amber_rounded, color: kSetRed, hint: 'مجموعها ${repMoney(i.total)} • اضغط للفاتورة'),
            ),
        ],
      ],
      notes: const ['الربح المؤكد لا يشمل ربح الديون اليدوية لأنه نسبة تقديرية، لا كلفة مواد حقيقية.'],
    );
  }

  void _explainCash(CashFlow c) {
    final from = _from, to = _to;
    Widget line(String label, double v, int n, {String? hint}) =>
        ReportLine(label, v, hint: [if (n > 0) '$n حركة', if (hint != null) hint].join(' • '));
    _explain(
      title: 'المقبوض فعلاً',
      icon: Icons.payments_rounded,
      color: kRepTeal,
      what: 'المال الذي دخل من البيع والديون في أيام الفترة، ناقص ما رُدّ نقداً. البيع الآجل لا يُحسب حتى يُسدَّد.',
      lines: [
        if (c.cashInvoices.abs() >= 1 || c.cashInvoicesCount > 0)
          line('فواتير نقدية', c.cashInvoices, c.cashInvoicesCount,
              hint: c.laterEditsAdjust.abs() >= 1 ? 'بمبلغها قبل تعديلات لاحقة (${repMoney(c.laterEditsAdjust)})' : null),
        if (c.downPayments.abs() >= 1) line('مدفوع عند البيع من فواتير آجلة', c.downPayments, c.downPaymentsCount),
        if (c.conversions.abs() >= 1)
          line('فواتير آجلة سابقة حُوّلت إلى نقد', c.conversions, c.conversionsCount, hint: 'ما أُلغي من دينها يوم التحويل'),
        if (c.debtPayments.abs() >= 1) line('تسديد ديون نقدي', c.debtPayments, c.debtPaymentsCount),
        if (c.editReceipts.abs() >= 1) line('سندات قبض لتعديل فواتير سابقة', c.editReceipts, c.editReceiptsCount),
        ReportLine('= المقبوض', c.salesCashIn, bold: true),
        if (c.cashRefunds.abs() >= 1) line('− مرتجعات مبيعات نقداً', -c.cashRefunds, c.cashRefundsCount),
        if (c.editRefunds.abs() >= 1) line('− سندات صرف لتعديل فواتير سابقة', -c.editRefunds, c.editRefundsCount),
        const Divider(height: 18),
        ReportLine('= المقبوض الصافي', c.netCollected, bold: true, color: kRepTeal),
        if (c.nonCashPayments.abs() >= 1) ...[
          const SizedBox(height: 8),
          ReportLine('تسديدات غير نقدية (خصم، صك، تسوية، بنك)', c.nonCashPayments,
              icon: Icons.info_outline_rounded, hint: '${c.nonCashPaymentsCount} حركة — أنقصت الديون ولم تدخل الصندوق'),
        ],
      ],
      notes: [
        if (c.laterConvertedCount > 0)
          '${c.laterConvertedCount} فاتورة نقدية الآن (${repMoney(c.laterConvertedTotal)}) كانت آجلة وحُوّلت إلى نقد بعد يومها: '
              'يُحسب يوم الفاتورة ما دُفع عند البيع فقط، والباقي يوم التحويل.',
        'تسديد الدين يُعدّ نقداً إلا إذا سُجّل خصماً أو صكاً أو تسوية أو على صندوق بنك. '
            'مرتجع المبيعات على الحساب ليس تسديداً.',
        'مصاريف الصناديق وسندات القبض والصرف تظهر في «إقفال اليوم».',
      ],
      actions: [
        (
          'قائمة التسديدات',
          Icons.price_check_rounded,
          () => TransactionsListDialog.showDebtPayments(
              context: context, startDate: from, endDate: to, periodTitle: widget.title, sourceFilter: widget.source)
        ),
        if (AuthService().hasPermission(AppPermissions.repDaily))
          ('إقفال اليوم', Icons.point_of_sale_rounded, () => openReport(context, DayCloseScreen(initialDate: to))),
      ],
    );
  }

  void _explainDebts(CashFlow c) {
    final groups = c.debtGroups.values.toList()..sort((a, b) => b.net.abs().compareTo(a.net.abs()));
    final start = c.debtStart;
    _explain(
      title: 'تغيّر الديون',
      icon: Icons.account_balance_rounded,
      color: kSetOrange,
      what: 'كل حركة في دفتر ديون العملاء خلال الفترة: ما زاد الديون (بيع آجل، دين يدوي…) وما أنقصها '
          '(تسديد، مرتجع، تحويل فاتورة إلى نقد…). من الدفتر نفسه، فنهاية الفترة = مجموع أرصدة العملاء ذلك اليوم.',
      lines: [
        if (start != null) ReportLine('الديون في بداية الفترة', start, icon: Icons.flag_rounded),
        for (final g in groups)
          ReportLine(g.label, g.net,
              hint: [
                '${g.count} حركة',
                if (g.up > 0.5 && g.down < -0.5) 'زاد ${repMoney(g.up)} ونقص ${repMoney(-g.down)}',
              ].join(' • ')),
        const Divider(height: 18),
        ReportLine(c.debtChange >= 0 ? '= زادت الديون' : '= نقصت الديون', c.debtChange, bold: true, color: kSetOrange),
        if (c.debtEnd != null) ReportLine('الديون في نهاية الفترة', c.debtEnd!, bold: true, icon: Icons.outlined_flag_rounded),
      ],
      notes: [
        if (start == null) 'رصيد البداية والنهاية يظهر مع «كل الأجهزة» فقط؛ هنا حركات المصدر المختار.',
        'العملاء المحذوفون وحركاتهم المحذوفة لا تُحسب.',
      ],
    );
  }
}
