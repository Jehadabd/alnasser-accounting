// lib/screens/report_trend_card.dart
//
// 📈 «تحليل التوجهات» في شاشة التقارير — بنفس شكل «المبيعات الشهرية» في التقرير
// السنوي السابق: أزرار المقياس (المبيعات، التكلفة، الأرباح، الفواتير، مقارنة
// المنحنيات)، منحنى بنافذة تفاصيل، بطاقة «تفاصيل» للنقطة المختارة، وجدول الأشهر.
//   • يوم واحد ⇒ ساعة بساعة. حتى 400 يوم ⇒ يوماً بيوم. أطول ⇒ شهراً بشهر.
//   • شكل الرسم يختاره المستخدم: منحنى (صعود ونزول) أو أعمدة (درج) — ويُحفظ.
//   • «افتح هذا اليوم/الشهر» يعرض تلك الفترة في الشاشة نفسها.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/reports_service.dart';
import '../widgets/report_kit.dart';
import '../widgets/trend_chart.dart';
import 'report_parts.dart' show repWeekday;

class ReportTrendCard extends StatefulWidget {
  const ReportTrendCard({
    super.key,
    required this.facts,
    required this.from,
    required this.to,
    required this.canProfit,
    required this.onOpenRange,
  });

  final SalesFacts facts;
  final DateTime from;
  final DateTime to;
  final bool canProfit;

  /// عرض فترة أخرى (يوم أو شهر) في الشاشة نفسها.
  final void Function(DateTime from, DateTime to) onOpenRange;

  @override
  State<ReportTrendCard> createState() => _ReportTrendCardState();
}

enum _Unit { hour, day, month }

class _Slot {
  _Slot(this.point, this.from, this.to);
  final TrendPoint point;
  final DateTime? from; // الفترة التي تفتحها النقطة (null للساعة)
  final DateTime? to;
}

class _ReportTrendCardState extends State<ReportTrendCard> {
  static const _prefKey = 'reports_chart_style'; // line | bars
  static const _indigo = Color(0xFF4F46E5);

  String _metric = TrendMetric.sales;
  bool _bars = false;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  Future<void> _loadStyle() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_prefKey);
      if (mounted && v != null) setState(() => _bars = v == 'bars');
    } catch (_) {}
  }

  Future<void> _setStyle(bool bars) async {
    setState(() => _bars = bars);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, bars ? 'bars' : 'line');
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant ReportTrendCard old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to || old.facts != widget.facts) _selected = null;
  }

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
  static String _dm(DateTime d) => '${d.day}/${d.month}';

  int get _days => _d(widget.to).difference(_d(widget.from)).inDays + 1;

  _Unit get _unit => _days <= 1 ? _Unit.hour : (_days <= 400 ? _Unit.day : _Unit.month);

  TrendPoint _pt(String title, String? axis, SalesTotals? t) => TrendPoint(
        title: title,
        axisLabel: axis,
        sales: t?.netSales ?? 0,
        cost: t?.cost ?? 0,
        profit: t?.profit ?? 0,
        invoices: t?.invoiceCount ?? 0,
      );

  List<_Slot> _slots() {
    final f = widget.facts;
    final from = _d(widget.from), to = _d(widget.to);
    if (_unit == _Unit.hour) {
          final by = <int, SalesTotals>{};
          for (final i in f.invoices) {
            by.putIfAbsent(i.date.hour, SalesTotals.new).addInvoice(i);
          }
          for (final e in f.edits) {
            by.putIfAbsent(e.date.hour, SalesTotals.new).addEdit(e);
          }
          if (by.isEmpty) return [];
          final hs = by.keys.toList()..sort();
          return [
            for (var h = hs.first; h <= hs.last; h++)
              _Slot(_pt('الساعة ${h.toString().padLeft(2, '0')}:00', '$h', by[h]), null, null)
          ];
        }
    if (_unit == _Unit.day) {
          final by = f.byDay();
          final n = _days;
          final longRange = n > 62;
          final step = n <= 16 ? 1 : (n / 10).ceil();
          final out = <_Slot>[];
          for (var i = 0; i < n; i++) {
            final d = DateTime(from.year, from.month, from.day + i);
            final axis = longRange ? (d.day == 1 || i == 0 ? 'ش${d.month}' : null) : (i % step == 0 ? _dm(d) : null);
            out.add(_Slot(_pt('${repWeekday(d)} ${_dm(d)}', axis, by[SalesFacts.day(d)]), d, d));
          }
          return out;
        }
    {
          final by = f.byMonth();
          final out = <_Slot>[];
          var m = DateTime(from.year, from.month, 1);
          while (!m.isAfter(to)) {
            final end = DateTime(m.year, m.month + 1, 0);
            out.add(_Slot(_pt(repMonth(m.year, m.month), '${m.month}/${m.year % 100}', by[SalesFacts.monthKey(m)]), m,
                end.isAfter(to) ? to : end));
            m = DateTime(m.year, m.month + 1, 1);
          }
          return out;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canProfit = widget.canProfit;
    if (!canProfit && (_metric == TrendMetric.cost || _metric == TrendMetric.profit)) _metric = TrendMetric.sales;
    final slots = _slots();
    if (slots.isEmpty) return const SizedBox.shrink();
    final points = [for (final s in slots) s.point];
    var sel = _selected ?? -1;
    if (sel < 0 || sel >= points.length) {
      // آخر نقطة فيها حركة
      sel = points.lastIndexWhere((p) => p.invoices > 0 || p.sales.abs() > 0.5);
      if (sel < 0) sel = points.length - 1;
    }
    final unitWord = switch (_unit) { _Unit.hour => 'ساعة بساعة', _Unit.day => 'يوماً بيوم', _Unit.month => 'شهراً بشهر' };
    final lineColor = TrendMetric.line(_metric);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // العنوان + شكل الرسم
        Row(children: [
          const Icon(Icons.show_chart_rounded, size: 20, color: _indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text('تحليل التوجهات — $unitWord',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.show_chart_rounded, size: 18), tooltip: 'منحنى (صعود ونزول)'),
              ButtonSegment(value: true, icon: Icon(Icons.bar_chart_rounded, size: 18), tooltip: 'أعمدة'),
            ],
            selected: {_bars},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _setStyle(s.first),
          ),
        ]),
        const SizedBox(height: 12),

        // أزرار المقياس
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(children: [
            _metricButton(TrendMetric.sales, 'المبيعات', Icons.shopping_cart),
            if (canProfit) _metricButton(TrendMetric.cost, 'التكلفة', Icons.money_off),
            if (canProfit) _metricButton(TrendMetric.profit, 'الأرباح', Icons.trending_up),
            _metricButton(TrendMetric.invoices, 'الفواتير', Icons.receipt),
            if (!_bars) _metricButton(TrendMetric.compareAll, 'مقارنة المنحنيات', Icons.multiline_chart),
          ]),
        ),
        const SizedBox(height: 16),

        // الرسم
        Container(
          height: 290,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(children: [
            if (!_bars && _metric == TrendMetric.compareAll) ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _legend('المبيعات', const Color(0xFF2563EB)),
                if (canProfit) ...[
                  const SizedBox(width: 16),
                  _legend('التكلفة', const Color(0xFFDC2626)),
                  const SizedBox(width: 16),
                  _legend('الأرباح', const Color(0xFF059669)),
                ],
              ]),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _bars
                  ? MiniBars(
                      values: [
                        for (final p in points)
                          switch (_metric) {
                            TrendMetric.profit => p.profit,
                            TrendMetric.cost => p.cost,
                            TrendMetric.invoices => p.invoices.toDouble(),
                            _ => p.sales,
                          }
                      ],
                      labels: [for (final p in points) p.axisLabel ?? ''],
                      tooltips: [for (final p in points) _tooltip(p)],
                      color: _metric == TrendMetric.compareAll ? TrendMetric.line(TrendMetric.sales) : lineColor,
                      height: 240,
                      highlight: sel,
                      showEveryLabel: 1,
                      onTap: (i) => setState(() => _selected = i),
                    )
                  : TrendLineChart(
                      points: points,
                      metric: _metric,
                      canProfit: canProfit,
                      selected: sel,
                      onSelect: (i) => setState(() => _selected = i),
                    ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        _spotlight(slots[sel]),
        if (_unit != _Unit.hour) ...[
          const SizedBox(height: 10),
          _summaryChips(slots),
        ],
        if (_unit != _Unit.hour) ..._monthsTable(),
      ]),
    );
  }

  String _tooltip(TrendPoint p) => [
        p.title,
        'المبيعات ${repMoney(p.sales)}',
        if (widget.canProfit) 'الأرباح ${repMoney(p.profit)}',
        if (widget.canProfit) 'التكلفة ${repMoney(p.cost)}',
        '${p.invoices} فاتورة',
      ].join('\n');

  Widget _metricButton(String key, String label, IconData icon) {
    final on = _metric == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _metric = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: on ? _indigo : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: on ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: on ? FontWeight.bold : FontWeight.w600,
                    color: on ? Colors.white : const Color(0xFF64748B),
                  )),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _legend(String label, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
      ]);

  /// بطاقة «تفاصيل» النقطة المختارة — كما في التقرير السنوي.
  Widget _spotlight(_Slot s) {
    final p = s.point;
    final margin = p.sales.abs() > 0.5 ? p.profit / p.sales * 100 : 0.0;
    final canOpen = s.from != null && !(s.from == _d(widget.from) && s.to == _d(widget.to));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF818CF8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.stars_rounded, color: _indigo, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('تفاصيل ${p.title}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1B4B))),
          ),
          if (canOpen)
            TextButton.icon(
              onPressed: () => widget.onOpenRange(s.from!, s.to!),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: Text(_unit == _Unit.month ? 'افتح هذا الشهر' : 'افتح هذا اليوم'),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: Text('المبيعات: ${repMoney(p.sales)} د.ع',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
          if (widget.canProfit)
            Expanded(
                child: Text('الأرباح: ${repMoney(p.profit)} د.ع',
                    style: TextStyle(fontWeight: FontWeight.bold, color: p.profit < 0 ? kSetRed : const Color(0xFF059669)))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          if (widget.canProfit)
            Expanded(
                child: Text('التكلفة: ${repMoney(p.cost)} د.ع',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)))),
          Expanded(
              child: Text(
                  'الفواتير: ${p.invoices}${widget.canProfit ? ' (نسبة الربح ${margin.toStringAsFixed(1)}%)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)))),
        ]),
      ]),
    );
  }

  Widget _chip(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kSetBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: kSetMuted),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kSetText)),
        ]),
      );

  Widget _summaryChips(List<_Slot> slots) {
    final daily = _unit == _Unit.day;
    // الأيام المنقضية فقط (لا تُحسب أيام المستقبل «بلا فواتير»)
    final today = _d(DateTime.now());
    final past = [for (final s in slots) if (s.from == null || !s.from!.isAfter(today)) s.point];
    if (past.isEmpty) return const SizedBox.shrink();
    var best = 0;
    for (var i = 1; i < past.length; i++) {
      if (past[i].sales > past[best].sales) best = i;
    }
    final sum = past.fold<double>(0, (s, p) => s + p.sales);
    final zero = past.where((p) => p.invoices == 0).length;
    return Wrap(spacing: 10, runSpacing: 8, children: [
      if (past[best].sales > 0)
        _chip(Icons.emoji_events_rounded, daily ? 'أفضل يوم' : 'أفضل شهر', '${past[best].title} — ${repMoney(past[best].sales)}'),
      _chip(Icons.av_timer_rounded, daily ? 'متوسط اليوم' : 'متوسط الشهر', repMoney(sum / past.length)),
      _chip(Icons.event_busy_rounded, daily ? 'أيام بلا فواتير' : 'أشهر بلا فواتير', '$zero من ${past.length}'),
    ]);
  }

  /// جدول الأشهر (عند فترة تشمل شهرين فأكثر) — الضغط يفتح الشهر.
  List<Widget> _monthsTable() {
    final from = _d(widget.from), to = _d(widget.to);
    if (from.year == to.year && from.month == to.month) return const [];
    final by = widget.facts.byMonth();
    final rows = <(DateTime, DateTime, SalesTotals)>[];
    var m = DateTime(from.year, from.month, 1);
    while (!m.isAfter(to)) {
      final s = m.isBefore(from) ? from : m;
      final e0 = DateTime(m.year, m.month + 1, 0);
      rows.add((s, e0.isAfter(to) ? to : e0, by[SalesFacts.monthKey(m)] ?? SalesTotals()));
      m = DateTime(m.year, m.month + 1, 1);
    }
    return [
      const SizedBox(height: 18),
      const Row(children: [
        Icon(Icons.table_chart_rounded, size: 20, color: _indigo),
        SizedBox(width: 8),
        Text('جدول التفاصيل الشهرية', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
      ]),
      const SizedBox(height: 12),
      for (final r in rows) ...[
        _monthRow(r.$1, r.$2, r.$3),
        const SizedBox(height: 8),
      ],
    ];
  }

  Widget _monthRow(DateTime s, DateTime e, SalesTotals t) {
    final margin = t.netSales.abs() > 0.5 ? t.profit / t.netSales * 100 : 0.0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.onOpenRange(s, e),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
              child: Center(
                child: Text('${s.month}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _indigo)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(repMonth(s.year, s.month),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                    child: Text('${t.invoiceCount} فاتورة',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  Text('مبيعات: ${repMoney(t.netSales)} د.ع',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w700)),
                  if (widget.canProfit)
                    Text('ربح: ${repMoney(t.profit)} د.ع',
                        style: TextStyle(
                            fontSize: 12, color: t.profit < 0 ? kSetRed : const Color(0xFF059669), fontWeight: FontWeight.w700)),
                  if (widget.canProfit)
                    Text('هامش ${margin.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8)),
          ]),
        ),
      ),
    );
  }
}
