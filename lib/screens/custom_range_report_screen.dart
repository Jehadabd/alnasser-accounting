// lib/screens/custom_range_report_screen.dart
//
// 📊 التقارير — شاشة واحدة لأي فترة: يوم، أسبوع، شهر، سنة، أو من تاريخ إلى تاريخ
// (حلّت محل تقارير اليوم والأسبوع والشهر والسنة المنفصلة). تحتوي:
//   • مؤشرات الفواتير، «ماذا حدث؟»، والمال الفعلي (المقبوض وتغيّر الديون).
//   • المبيعات حسب نوع البيع، ومرتجعات المبيعات منفصلة.
//   • تحليل التوجهات بمنحنى التقرير السنوي (ساعة/يوم/شهر) أو أعمدة — يختارها المستخدم.
//   • التوزيع، خارج الفواتير، أثر سعر الدولار، المقارنة، المواد والعملاء، الفواتير.
// المقارنة حسب نوع الفترة: يوم ← أمس ونفس اليوم من الأسبوع الماضي، شهر لم ينتهِ ←
// نفس الأيام من الشهر الماضي، سنة لم تنتهِ ← نفس الأيام من السنة الماضية، غيرها ←
// الفترة السابقة بنفس الطول.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/reports_service.dart';
import '../widgets/currency_impact_card.dart';
import '../widgets/report_kit.dart';
import 'period_extras.dart';
import 'product_report_details_screen.dart';
import 'report_channels.dart';
import 'report_parts.dart';
import 'report_trend_card.dart';
import 'returns_report_screen.dart';

class CustomRangeReportScreen extends StatefulWidget {
  const CustomRangeReportScreen({super.key, this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  /// هل يملك المستخدم أي صلاحية تقارير مبيعات؟
  static bool allowed() {
    final a = AuthService();
    return a.hasPermission(AppPermissions.repDaily) ||
        a.hasPermission(AppPermissions.repWeekly) ||
        a.hasPermission(AppPermissions.repMonthly) ||
        a.hasPermission(AppPermissions.repYearly) ||
        a.hasPermission(AppPermissions.repCustom);
  }

  @override
  State<CustomRangeReportScreen> createState() => _CustomRangeReportScreenState();
}

class _CustomRangeReportScreenState extends State<CustomRangeReportScreen> {
  final _svc = ReportsService();
  late DateTime _from;
  late DateTime _to;
  String _source = ReportSource.all;
  PeriodData? _data;
  CurrencyImpact? _impact;
  bool _loading = true;
  String? _error;
  int _token = 0;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
  static DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  DateTime get _today => _d(DateTime.now());

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = _d(widget.from ?? DateTime(now.year, now.month, 1));
    _to = _d(widget.to ?? now);
    if (_to.isAfter(_today)) _to = _today;
    if (_to.isBefore(_from)) _to = _from;
    if (CustomRangeReportScreen.allowed()) {
      _load();
    } else {
      _loading = false;
    }
  }

  int get _days => _to.difference(_from).inDays + 1;

  // ─────────────────────────── نوع الفترة ───────────────────────────

  /// يوم / أسبوع (سبت–جمعة) / شهر / سنة كاملة (أو حتى اليوم) — وإلا فترة حرة.
  ExtrasKind get _kind {
    if (_from == _to) return ExtrasKind.day;
    final ws = SalesFacts.weekStart(_from);
    final we = _add(ws, 6);
    if (_from == ws && (_to == we || (_to == _today && _to.isBefore(we)))) return ExtrasKind.week;
    final me = DateTime(_from.year, _from.month + 1, 0);
    if (_from.day == 1 && (_to == me || (_to == _today && _to.isBefore(me) && _to.month == _from.month && _to.year == _from.year))) {
      return ExtrasKind.month;
    }
    final ye = DateTime(_from.year, 12, 31);
    if (_from.month == 1 && _from.day == 1 && (_to == ye || (_to == _today && _to.year == _from.year))) {
      return ExtrasKind.year;
    }
    return ExtrasKind.custom;
  }

  /// نهاية الفترة الطبيعية (الشهر/الأسبوع/السنة الحالية تنتهي بعد اليوم).
  DateTime get _naturalEnd {
    final k = _kind;
    if (k == ExtrasKind.week) return _add(SalesFacts.weekStart(_from), 6);
    if (k == ExtrasKind.month) return DateTime(_from.year, _from.month + 1, 0);
    if (k == ExtrasKind.year) return DateTime(_from.year, 12, 31);
    return _to;
  }

  bool get _inProgress => _naturalEnd.isAfter(_to);

  /// فترة المقارنة: (من، إلى، اسمها) + مقارنة ثانية لليوم والشهر.
  ({DateTime pFrom, DateTime pTo, String pLabel, DateTime? p2From, DateTime? p2To, String? p2Label}) _prev() {
    final k = _kind;
    final same = _inProgress ? ' (نفس الأيام)' : '';
    if (k == ExtrasKind.day) {
      final y = _add(_from, -1), w = _add(_from, -7);
      return (pFrom: y, pTo: y, pLabel: 'أمس', p2From: w, p2To: w, p2Label: '${repWeekday(_from)} الماضي');
    }
    if (k == ExtrasKind.week) {
      final s = _add(_from, -7);
      return (pFrom: s, pTo: _add(s, _days - 1), pLabel: 'الأسبوع السابق$same', p2From: null, p2To: null, p2Label: null);
    }
    if (k == ExtrasKind.month) {
      final pTo = _min(DateTime(_from.year, _from.month - 1, _to.day), DateTime(_from.year, _from.month, 0));
      final p2To = _min(DateTime(_from.year - 1, _from.month, _to.day), DateTime(_from.year - 1, _from.month + 1, 0));
      return (
        pFrom: DateTime(_from.year, _from.month - 1, 1),
        pTo: pTo,
        pLabel: 'الشهر الماضي$same',
        p2From: DateTime(_from.year - 1, _from.month, 1),
        p2To: p2To,
        p2Label: 'نفس الشهر ${_from.year - 1}',
      );
    }
    if (k == ExtrasKind.year) {
      final pTo = _min(DateTime(_from.year - 1, _to.month, _to.day), DateTime(_from.year - 1, _to.month + 1, 0));
      return (pFrom: DateTime(_from.year - 1, 1, 1), pTo: pTo, pLabel: 'السنة الماضية$same', p2From: null, p2To: null, p2Label: null);
    }
    final pTo = _add(_from, -1);
    return (
      pFrom: _add(pTo, -(_days - 1)),
      pTo: pTo,
      pLabel: 'الفترة السابقة بنفس الطول',
      p2From: null,
      p2To: null,
      p2Label: null,
    );
  }

  // ─────────────────────────── التحميل ───────────────────────────

  Future<void> _load() async {
    final t = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _svc.reportSourceFilter = _source;
      final p = _prev();
      final data = await PeriodData.load(_svc,
          from: _from, to: _to, prevFrom: p.pFrom, prevTo: p.pTo, prev2From: p.p2From, prev2To: p.p2To);
      CurrencyImpact? impact;
      try {
        impact = await _svc.currencyImpact(from: _from, to: _to);
      } catch (_) {}
      if (!mounted || t != _token) return;
      setState(() {
        _data = data;
        _impact = impact;
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

  void _set(DateTime from, DateTime to) {
    _from = _d(from);
    _to = _d(to).isAfter(_today) ? _today : _d(to);
    if (_to.isBefore(_from)) _to = _from;
    _load();
  }

  /// ◀ ▶ بحسب نوع الفترة: يوم/أسبوع/شهر/سنة كاملة، وإلا بنفس الطول.
  void _shift(int dir) {
    final k = _kind;
    if (k == ExtrasKind.day) {
      _set(_add(_from, dir), _add(_from, dir));
    } else if (k == ExtrasKind.week) {
      final s = _add(SalesFacts.weekStart(_from), 7 * dir);
      _set(s, _add(s, 6));
    } else if (k == ExtrasKind.month) {
      final s = DateTime(_from.year, _from.month + dir, 1);
      _set(s, DateTime(s.year, s.month + 1, 0));
    } else if (k == ExtrasKind.year) {
      final y = _from.year + dir;
      _set(DateTime(y, 1, 1), DateTime(y, 12, 31));
    } else {
      final n = _days;
      _set(_add(_from, n * dir), _add(_to, n * dir));
    }
  }

  bool get _canNext => _naturalEnd.isBefore(_today);

  Future<void> _pick() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: _today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'اختر الفترة',
      saveText: 'عرض التقرير',
      fieldStartLabelText: 'من',
      fieldEndLabelText: 'إلى',
    );
    if (r != null) _set(r.start, r.end);
  }

  Future<void> _pickDay() async {
    final d = await pickReportDay(context, _from);
    if (d != null) _set(d, d);
  }

  // اختيارات سريعة
  List<(String, DateTime, DateTime)> get _presets {
    final t = _today;
    final ws = SalesFacts.weekStart(t);
    final m0 = DateTime(t.year, t.month, 1);
    final pm0 = DateTime(t.year, t.month - 1, 1);
    return [
      ('اليوم', t, t),
      ('أمس', _add(t, -1), _add(t, -1)),
      ('هذا الأسبوع', ws, t),
      ('الأسبوع الماضي', _add(ws, -7), _add(ws, -1)),
      ('هذا الشهر', m0, t),
      ('الشهر الماضي', pm0, DateTime(t.year, t.month, 0)),
      ('آخر 30 يوماً', _add(t, -29), t),
      ('آخر 3 أشهر', DateTime(t.year, t.month - 2, 1), t),
      ('هذه السنة', DateTime(t.year, 1, 1), t),
      ('السنة الماضية', DateTime(t.year - 1, 1, 1), DateTime(t.year - 1, 12, 31)),
    ];
  }

  String get _label {
    final k = _kind;
    if (k == ExtrasKind.day) return '${repWeekday(_from)} ${repDate(_from)}';
    if (k == ExtrasKind.month) return repMonth(_from.year, _from.month);
    if (k == ExtrasKind.year) return 'سنة ${_from.year}';
    return '${repDate(_from)} — ${repDate(_to)}';
  }

  String get _caption {
    final k = _kind;
    if (k == ExtrasKind.day) {
      if (_from == _today) return 'اليوم';
      if (_from == _add(_today, -1)) return 'أمس';
      return 'يوم واحد';
    }
    if (k == ExtrasKind.week) return _inProgress ? 'هذا الأسبوع — حتى ${repWeekday(_to)}' : 'أسبوع (سبت — جمعة)';
    if (k == ExtrasKind.month) return _inProgress ? 'هذا الشهر — حتى ${repDate(_to)}' : 'شهر كامل';
    if (k == ExtrasKind.year) return _inProgress ? 'هذه السنة — حتى ${repDate(_to)}' : 'سنة كاملة';
    return '$_days ${_days == 1 ? 'يوم' : 'يوماً'} — ◀ ▶ تنقل بنفس الطول';
  }

  // ─────────────────────────── البناء ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final canProfit = repCanSeeProfit();
    return ReportScaffold(
      title: 'التقارير',
      subtitle: 'يوم، أسبوع، شهر، سنة، أو من تاريخ إلى تاريخ',
      icon: Icons.insights_rounded,
      actions: [
        SourceMenu(
            value: _source,
            onChanged: (v) {
              _source = v;
              _load();
            }),
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      header: Column(mainAxisSize: MainAxisSize.min, children: [
        PeriodNavigator(
          label: _label,
          caption: _caption,
          onPrev: () => _shift(-1),
          onNext: () => _shift(1),
          onPick: _kind == ExtrasKind.day ? _pickDay : _pick,
          canNext: _canNext,
          trailing: Wrap(spacing: 6, children: [
            OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.today_rounded, size: 18),
              label: const Text('يوم'),
            ),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: const Text('من … إلى …'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (label, f, t) in _presets)
              ChoiceChip(
                label: Text(label),
                selected: _from == f && _to == t,
                onSelected: (_) => _set(f, t),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ),
      ]),
      loading: _loading,
      children: _loading ? null : _content(canProfit),
    );
  }

  List<Widget> _content(bool canProfit) {
    if (!CustomRangeReportScreen.allowed()) {
      return const [
        EmptyReport(
          title: 'لا صلاحية للتقارير',
          text: 'اطلب من المدير صلاحية تقارير المبيعات.',
          icon: Icons.lock_outline_rounded,
        ),
      ];
    }
    final d = _data;
    if (_error != null || d == null) {
      return [EmptyReport(title: 'تعذّر تحميل التقرير', text: _error, icon: Icons.error_outline_rounded)];
    }
    if (d.isEmpty) {
      return [
        EmptyReport(
          title: 'لا حركة في $_label',
          text: 'لا فواتير ولا مرتجعات ولا ديون أو تسديدات يدوية. استخدم ◀ أو اختر فترة أخرى.',
          icon: Icons.event_busy_rounded,
        ),
      ];
    }
    final p = _prev();
    void openReturns() => openReport(context, ReturnsReportScreen(from: _from, to: _to));
    final impact = _impact;
    return [
      periodKpis(d, prevLabel: p.pLabel, canProfit: canProfit, onReturns: openReturns),
      // 💡 ماذا حدث؟ + المال الفعلي (المقبوض وتغيّر الديون)
      PeriodExtras(
          key: ValueKey('extras-$_from-$_to-$_source'),
          kind: _kind,
          from: _from,
          to: _naturalEnd,
          title: _label,
          source: _source),
      SalesChannelsCard(from: _from, to: _to, facts: d.facts, canProfit: canProfit, onReturns: openReturns),
      // 📈 تحليل التوجهات (منحنى التقرير السنوي أو أعمدة)
      ReportTrendCard(
        facts: d.facts,
        from: _from,
        to: _to,
        canProfit: canProfit,
        onOpenRange: _set,
      ),
      distributionCard(d),
      manualCard(context, d, periodTitle: _label, source: _source, canProfit: canProfit),
      // 💱 أثر سعر الدولار في الفترة
      if (impact != null)
        CurrencyImpactCard(
          impact: impact,
          showProfit: canProfit,
          onProductTap: (id, name) =>
              Navigator.push(context, accRoute(ProductReportDetailsScreen(productId: id, productName: name))),
        ),
      compareCard(d,
          title: 'المقارنة',
          prevLabel: p.pLabel,
          prev2Label: p.p2Label,
          canProfit: canProfit,
          subtitle: _inProgress ? 'الفترة لم تنتهِ — المقارنة بنفس عدد الأيام' : null),
      twoCols(
        TopProductsCard(facts: d.facts, canProfit: canProfit),
        TopCustomersCard(facts: d.facts, canProfit: canProfit, monthOf: _from),
      ),
      InvoicesListCard(facts: d.facts, canProfit: canProfit, showDay: _kind != ExtrasKind.day),
    ];
  }
}
