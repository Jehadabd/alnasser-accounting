// lib/owner/founders_screen.dart
//
// 👷 تقارير المؤسسين (حساب المالك): لوحة إحصاءات كاملة + تفاصيل كل مؤسس.
//   • اللوحة: رصيد النقاط، مؤشرات الفترة، النقاط شهرياً، الترتيب، أحدث الفواتير، بطاقات المؤسسين.
//   • التفاصيل: رصيده ومؤشراته، رسمه الشهري، أهم عملائه، فواتيره، وحركات النقاط
//     (إضافة / خصم / صرف جائزة).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../accounting/screens/acc_ui.dart' show accRoute;
import '../screens/create_invoice_screen.dart';
import '../services/database_service.dart';
import '../widgets/report_kit.dart';
import 'founder_service.dart';

const _kGold = Color(0xFFD97706);
const _kGoldSoft = Color(0xFFFFFBEB);
final _dayFmt = DateFormat('yyyy/MM/dd', 'en_US');
final _monthFmt = DateFormat('MM/yy', 'en_US');

String _pts(double v) =>
    v == v.roundToDouble() ? NumberFormat('#,##0', 'en_US').format(v) : NumberFormat('#,##0.##', 'en_US').format(v);

// ═════════════════════════════ الفترة ═════════════════════════════

enum FounderPeriod { all, month, quarter, year, custom }

class _Range {
  const _Range(this.from, this.to, this.label);
  final DateTime? from;
  final DateTime? to;
  final String label;
}

_Range _rangeOf(FounderPeriod p, DateTimeRange? custom) {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  switch (p) {
    case FounderPeriod.all:
      return const _Range(null, null, 'كل الفترات');
    case FounderPeriod.month:
      return _Range(DateTime(now.year, now.month, 1), tomorrow, 'هذا الشهر');
    case FounderPeriod.quarter:
      return _Range(DateTime(now.year, now.month - 2, 1), tomorrow, 'آخر 3 أشهر');
    case FounderPeriod.year:
      return _Range(DateTime(now.year, 1, 1), tomorrow, 'هذه السنة');
    case FounderPeriod.custom:
      if (custom == null) return const _Range(null, null, 'كل الفترات');
      return _Range(custom.start, DateTime(custom.end.year, custom.end.month, custom.end.day + 1),
          '${_dayFmt.format(custom.start)} — ${_dayFmt.format(custom.end)}');
  }
}

/// النقاط لكل شهر من آخر 12 شهراً
(List<double>, List<String>) _monthly(Iterable<FounderInvoice> invs) {
  final now = DateTime.now();
  final months = [for (var i = 11; i >= 0; i--) DateTime(now.year, now.month - i, 1)];
  final values = List<double>.filled(12, 0);
  for (final inv in invs) {
    for (var i = 0; i < 12; i++) {
      final m = months[i];
      if (inv.date.year == m.year && inv.date.month == m.month) {
        values[i] += inv.points;
        break;
      }
    }
  }
  return ([for (final v in values) FounderService.round2(v)], [for (final m in months) _monthFmt.format(m)]);
}

double _sumPoints(Iterable<FounderInvoice> l) => l.fold(0.0, (s, i) => s + i.points);
double _sumNet(Iterable<FounderInvoice> l) => l.fold(0.0, (s, i) => s + i.net);

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.value, required this.label, required this.onChanged});
  final FounderPeriod value;
  final String label;
  final ValueChanged<FounderPeriod> onChanged;

  static const _items = {
    FounderPeriod.all: 'الكل',
    FounderPeriod.month: 'هذا الشهر',
    FounderPeriod.quarter: '3 أشهر',
    FounderPeriod.year: 'هذه السنة',
    FounderPeriod.custom: 'فترة محددة',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final e in _items.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: value == e.key,
                    avatar: e.key == FounderPeriod.custom ? const Icon(Icons.date_range_rounded, size: 16) : null,
                    onSelected: (_) => onChanged(e.key),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: kSetMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

Future<DateTimeRange?> _pickRange(BuildContext context, DateTimeRange? current) => showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: current,
      helpText: 'اختر الفترة',
    );

// ═════════════════════════════ اللوحة ═════════════════════════════

class FoundersScreen extends StatefulWidget {
  const FoundersScreen({super.key});

  @override
  State<FoundersScreen> createState() => _FoundersScreenState();
}

class _FoundersScreenState extends State<FoundersScreen> {
  List<FounderStats> _all = [];
  double _shopSales = 0;
  double _rate = FounderService.defaultRateFallback;
  bool _loading = true;
  String? _error;
  FounderPeriod _period = FounderPeriod.month;
  DateTimeRange? _custom;
  final _search = TextEditingController();

  _Range get _range => _rangeOf(_period, _custom);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _all.isEmpty;
      _error = null;
    });
    try {
      final all = await FounderService.loadAll();
      final r = _range;
      final sales = await FounderService.allSales(r.from, r.to);
      final rate = await FounderService.defaultRate();
      if (!mounted) return;
      setState(() {
        _all = all;
        _shopSales = sales;
        _rate = rate;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setPeriod(FounderPeriod p) async {
    if (p == FounderPeriod.custom) {
      final r = await _pickRange(context, _custom);
      if (r == null) return;
      _custom = r;
    }
    setState(() => _period = p);
    final rr = _range;
    final sales = await FounderService.allSales(rr.from, rr.to);
    if (mounted) setState(() => _shopSales = sales);
  }

  Future<void> _editRate() async {
    final v = await _askNumber(context, 'النقاط لكل 100,000', 'المعدل الافتراضي للفواتير الجديدة', _rate);
    if (v == null || v < 0) return;
    await FounderService.setDefaultRate(v);
    if (!mounted) return;
    setState(() => _rate = v);
    setToast(context, 'المعدل الافتراضي الآن ${_pts(v)} نقطة لكل 100,000');
  }

  Future<void> _addFounder() async {
    final name = await _askText(context, 'مؤسس جديد', 'اسم المؤسس / الفني');
    if (name == null || name.trim().isEmpty) return;
    await FounderService.ensureFounder(name.trim());
    await _load();
  }

  void _open(FounderStats f) =>
      Navigator.push(context, accRoute(FounderDetailsScreen(founderName: f.name))).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final r = _range;
    return ReportScaffold(
      title: 'تقارير المؤسسين',
      subtitle: 'نقاط المؤسسين والفنيين ومبيعاتهم',
      icon: Icons.engineering_rounded,
      loading: _loading,
      onRefresh: _load,
      header: _PeriodBar(value: _period, label: r.label, onChanged: _setPeriod),
      actions: [
        IconButton(tooltip: 'النقاط لكل 100,000', onPressed: _editRate, icon: const Icon(Icons.tune_rounded)),
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFounder,
        backgroundColor: _kGold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('مؤسس جديد'),
      ),
      children: _error != null
          ? [SetBanner('تعذّر تحميل البيانات: $_error', kind: SetBannerKind.error)]
          : _all.isEmpty
              ? [
                  _hero(r),
                  const EmptyReport(
                    title: 'لا يوجد مؤسسون بعد',
                    text: 'أضف مؤسساً من الزر بالأسفل، أو اكتب اسمه في الفاتورة (زر «المؤسس» أعلى شاشة الفاتورة).',
                    icon: Icons.engineering_rounded,
                  ),
                ]
              : [_balances(), _hero(r), _kpis(r), _chartCard(), _boards(r), _cardsSection(r)],
    );
  }

  // ── أرصدة كل المؤسسين: أول ما يظهر ──
  Widget _balances() {
    final q = _search.text.trim();
    final list = _all.where((f) => q.isEmpty || f.name.contains(q) || f.phone.contains(q)).toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));
    final total = _all.fold(0.0, (s, f) => s + f.balance);
    return SetCard(
      title: 'رصيد نقاط كل مؤسس',
      subtitle: '${_all.length} مؤسساً • مجموع الأرصدة ${_pts(total)} نقطة • اضغط أي مؤسس لتفاصيله',
      icon: Icons.account_balance_wallet_rounded,
      color: _kGold,
      child: Column(children: [
        SizedBox(
          height: 40,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو الهاتف',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: _kGoldSoft,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: kSetBorder),
            itemBuilder: (_, i) {
              final f = list[i];
              final c = f.balance > 0 ? _kGold : (f.balance < 0 ? kSetRed : kSetMuted);
              return InkWell(
                onTap: () => _open(f),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 30,
                      child: Text('${i + 1}', style: const TextStyle(color: kSetMuted, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800, color: kSetText)),
                        Text(
                          '${f.invoices.length} فاتورة'
                          '${f.lastInvoice != null ? ' • آخر فاتورة ${_dayFmt.format(f.lastInvoice!)}' : ''}'
                          '${f.paidOut > 0 ? ' • صُرف/خُصم ${_pts(f.paidOut)}' : ''}',
                          style: const TextStyle(fontSize: 11.5, color: kSetMuted),
                        ),
                      ]),
                    ),
                    Text(_pts(f.balance),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
                    const SizedBox(width: 4),
                    const Text('نقطة', style: TextStyle(fontSize: 11, color: kSetMuted)),
                    const Icon(Icons.chevron_left_rounded, color: kSetMuted),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── الرأس ──
  Widget _hero(_Range r) {
    final balance = _all.fold(0.0, (s, f) => s + f.balance);
    final active = _all.where((f) => f.inRange(r.from, r.to).isNotEmpty).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3460), Color(0xFF1B5E8C), Color(0xFF92400E)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x330F3460), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Row(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFDE68A), size: 36),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('رصيد نقاط كل المؤسسين', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(_pts(balance),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _heroPill(Icons.groups_rounded, '${_all.length} مؤسس'),
              _heroPill(Icons.bolt_rounded, '$active نشط في «${r.label}»'),
              InkWell(
                onTap: _editRate,
                borderRadius: BorderRadius.circular(20),
                child: _heroPill(Icons.stars_rounded, '${_pts(_rate)} نقطة لكل 100,000', editable: true),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _heroPill(IconData icon, String text, {bool editable = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: const Color(0xFFFDE68A)),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          if (editable) ...[const SizedBox(width: 4), const Icon(Icons.edit_rounded, size: 13, color: Colors.white70)],
        ]),
      );

  // ── المؤشرات ──
  Widget _kpis(_Range r) {
    final invs = [for (final f in _all) ...f.inRange(r.from, r.to)];
    final points = _sumPoints(invs);
    final sales = _sumNet(invs);
    final avg = invs.isEmpty ? 0.0 : sales / invs.length;
    final share = _shopSales <= 0 ? 0.0 : sales / _shopSales * 100;
    final paid = _all.fold(0.0, (s, f) => s + f.paidOut);
    final returns = invs.fold(0.0, (s, i) => s + i.returns);
    final active = _all.where((f) => f.inRange(r.from, r.to).isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: KpiGrid(minTileWidth: 210, children: [
        KpiTile(label: 'نقاط الفترة', value: FounderService.round2(points), icon: Icons.stars_rounded, color: _kGold, money: false, emphasis: true),
        KpiTile(label: 'مبيعات المؤسسين', value: sales, icon: Icons.payments_rounded, color: kSetGreen, hint: 'صافي بعد المرتجع'),
        KpiTile(label: 'فواتير المؤسسين', value: invs.length.toDouble(), icon: Icons.receipt_long_rounded, color: kSetBlue, money: false),
        KpiTile(label: 'متوسط الفاتورة', value: avg, icon: Icons.analytics_rounded, color: kRepPurple),
        KpiTile(
          label: 'من مبيعات المحل %',
          value: FounderService.round2(share),
          icon: Icons.pie_chart_rounded,
          color: kRepTeal,
          money: false,
          hint: 'من ${repMoney(_shopSales)}',
        ),
        KpiTile(label: 'مرتجع على فواتيرهم', value: returns, icon: Icons.assignment_return_rounded, color: kSetRed),
        KpiTile(
            label: 'نقاط مصروفة ومخصومة',
            value: FounderService.round2(paid),
            icon: Icons.redeem_rounded,
            color: kSetOrange,
            money: false,
            hint: 'جوائز + خصم يدوي + تسديد دين راجع'),
        KpiTile(label: 'مؤسسون نشطون', value: active.toDouble(), icon: Icons.groups_rounded, color: kSetNavy, money: false, hint: 'من ${_all.length}'),
      ]),
    );
  }

  // ── الرسم ──
  Widget _chartCard() {
    final (values, labels) = _monthly([for (final f in _all) ...f.invoices]);
    return SetCard(
      title: 'النقاط شهرياً',
      subtitle: 'آخر 12 شهراً — كل المؤسسين',
      icon: Icons.bar_chart_rounded,
      color: _kGold,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: MiniBars(
          values: values,
          labels: labels,
          tooltips: [for (var i = 0; i < 12; i++) '${labels[i]}: ${_pts(values[i])} نقطة'],
          color: _kGold,
          highlight: 11,
        ),
      ),
    );
  }

  // ── الترتيب + أحدث الفواتير ──
  Widget _boards(_Range r) {
    final ranked = [
      for (final f in _all) (f, _sumPoints(f.inRange(r.from, r.to)), _sumNet(f.inRange(r.from, r.to))),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final top = ranked.where((e) => e.$2 > 0).take(8).toList();
    final maxPts = top.isEmpty ? 1.0 : top.first.$2;
    final recent = ([for (final f in _all) ...f.inRange(r.from, r.to)]..sort((a, b) => b.date.compareTo(a.date))).take(8).toList();

    final board = SetCard(
      title: 'الأعلى نقاطاً',
      subtitle: r.label,
      icon: Icons.leaderboard_rounded,
      color: _kGold,
      child: top.isEmpty
          ? const EmptyReport(title: 'لا نقاط في هذه الفترة', icon: Icons.leaderboard_rounded)
          : Column(children: [
              for (var i = 0; i < top.length; i++)
                RankRow(
                  rank: i + 1,
                  title: top[i].$1.name,
                  subtitle: 'مبيعات ${repMoney(top[i].$3)}',
                  value: top[i].$2,
                  fraction: top[i].$2 / maxPts,
                  color: _kGold,
                  trailing: _PointsBadge(top[i].$2),
                  onTap: () => _open(top[i].$1),
                ),
            ]),
    );
    final latest = SetCard(
      title: 'أحدث فواتير المؤسسين',
      subtitle: r.label,
      icon: Icons.schedule_rounded,
      color: kSetBlue,
      child: recent.isEmpty
          ? const EmptyReport(title: 'لا فواتير في هذه الفترة', icon: Icons.receipt_long_rounded)
          : Column(children: [for (final inv in recent) _InvoiceRow(inv, showFounder: true)]),
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 820) return Column(children: [board, latest]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: board),
        const SizedBox(width: 14),
        Expanded(child: latest),
      ]);
    });
  }

  // ── بطاقات المؤسسين ──
  Widget _cardsSection(_Range r) {
    final q = _search.text.trim();
    final list = _all.where((f) => q.isEmpty || f.name.contains(q) || f.phone.contains(q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
        child: Row(children: [
          const Text('كل المؤسسين', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kSetText)),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو الهاتف',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kSetBorder)),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kSetBorder)),
                ),
              ),
            ),
          ),
        ]),
      ),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final f in list) SizedBox(width: w, child: _FounderCard(f: f, range: r, onTap: () => _open(f))),
        ]);
      }),
    ]);
  }
}

class _PointsBadge extends StatelessWidget {
  const _PointsBadge(this.points);
  final double points;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: _kGoldSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFDE68A))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.stars_rounded, size: 14, color: _kGold),
          const SizedBox(width: 4),
          Text(_pts(points), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF92400E))),
        ]),
      );
}

class _FounderCard extends StatefulWidget {
  const _FounderCard({required this.f, required this.range, required this.onTap});
  final FounderStats f;
  final _Range range;
  final VoidCallback onTap;
  @override
  State<_FounderCard> createState() => _FounderCardState();
}

class _FounderCardState extends State<_FounderCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final inv = f.inRange(widget.range.from, widget.range.to);
    final pts = _sumPoints(inv);
    final sales = _sumNet(inv);
    final last = f.lastInvoice;
    final idle = last == null ? null : DateTime.now().difference(last).inDays;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _hover ? _kGold.withValues(alpha: 0.5) : kSetBorder),
          boxShadow: [
            BoxShadow(
              color: (_hover ? _kGold : const Color(0xFF0F172A)).withValues(alpha: _hover ? 0.16 : 0.05),
              blurRadius: _hover ? 20 : 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  _Avatar(f.name, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: kSetText)),
                      const SizedBox(height: 2),
                      Text(
                        last == null
                            ? 'لا فواتير بعد'
                            : 'آخر فاتورة ${_dayFmt.format(last)}${idle != null && idle > 30 ? ' • منذ $idle يوماً' : ''}',
                        style: TextStyle(fontSize: 11.5, color: idle != null && idle > 30 ? kSetOrange : kSetMuted),
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('الرصيد', style: TextStyle(fontSize: 11, color: kSetMuted)),
                    Text(_pts(f.balance), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _kGold)),
                  ]),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _miniStat('نقاط الفترة', _pts(pts), Icons.stars_rounded, _kGold),
                  _miniStat('المبيعات', repMoney(sales), Icons.payments_rounded, kSetGreen),
                  _miniStat('الفواتير', '${inv.length}', Icons.receipt_long_rounded, kSetBlue),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color c) => Expanded(
        child: Container(
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(height: 2),
            FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 13.5))),
            Text(label, style: const TextStyle(fontSize: 10.5, color: kSetMuted)),
          ]),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, {this.size = 44});
  final String name;
  final double size;
  static const _palette = [
    Color(0xFF0F3460),
    Color(0xFFB45309),
    Color(0xFF047857),
    Color(0xFF6D28D9),
    Color(0xFF0F766E),
    Color(0xFFB91C1C),
  ];
  @override
  Widget build(BuildContext context) {
    final c = _palette[name.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c, Color.alphaBlend(Colors.white30, c)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(name.isEmpty ? '?' : name.characters.first,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.42)),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow(this.inv, {this.showFounder = false});
  final FounderInvoice inv;
  final bool showFounder;

  Future<void> _openInvoice(BuildContext context) async {
    final invoice = await DatabaseService().getInvoiceById(inv.id);
    if (invoice == null || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => CreateInvoiceScreen(existingInvoice: invoice, isViewOnly: true)));
  }

  @override
  Widget build(BuildContext context) {
    final changed = inv.adjustments != 0 || inv.returns != 0;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openInvoice(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: kSetBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.receipt_long_rounded, color: kSetBlue, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(showFounder ? '${inv.founder} — ${inv.customer}' : inv.customer,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
              Text(
                '#${inv.number} • ${_dayFmt.format(inv.date)} • ${_pts(inv.rate)} لكل 100 ألف'
                '${changed ? ' • الأصل ${repMoney(inv.total)}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: kSetMuted),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            MoneyLabel(inv.net, size: 13.5),
            const SizedBox(height: 2),
            _PointsBadge(inv.points),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════════ تفاصيل مؤسس ═════════════════════════════

class FounderDetailsScreen extends StatefulWidget {
  const FounderDetailsScreen({super.key, required this.founderName});
  final String founderName;
  @override
  State<FounderDetailsScreen> createState() => _FounderDetailsScreenState();
}

class _FounderDetailsScreenState extends State<FounderDetailsScreen> {
  FounderStats? _f;
  bool _loading = true;
  FounderPeriod _period = FounderPeriod.all;
  DateTimeRange? _custom;
  int _tab = 0; // 0 الفواتير، 1 حركات النقاط

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await FounderService.loadAll();
    if (!mounted) return;
    setState(() {
      _f = all.where((f) => f.name == widget.founderName).firstOrNull ?? FounderStats(name: widget.founderName);
      _loading = false;
    });
  }

  Future<void> _setPeriod(FounderPeriod p) async {
    if (p == FounderPeriod.custom) {
      final r = await _pickRange(context, _custom);
      if (r == null) return;
      _custom = r;
    }
    setState(() => _period = p);
  }

  Future<void> _move({required bool payout, bool deduct = false}) async {
    final f = _f!;
    final r = await showDialog<(double, String)>(
        context: context, builder: (_) => _MoveDialog(payout: payout, balance: f.balance, startDeduct: deduct));
    if (r == null) return;
    await FounderService.addMove(f, r.$1, r.$2, payout: payout);
    await _load();
    if (mounted) setToast(context, payout ? 'سُجّل صرف ${_pts(r.$1.abs())} نقطة' : 'سُجّلت الحركة');
  }

  Future<void> _editInfo() async {
    final f = _f!;
    final id = f.id ?? await FounderService.ensureFounder(f.name);
    if (id == null || !mounted) return;
    final phone = TextEditingController(text: f.phone);
    final notes = TextEditingController(text: f.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('بيانات ${f.name}'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف', prefixIcon: Icon(Icons.phone_rounded))),
            const SizedBox(height: 10),
            TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes_rounded))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      await FounderService.updateInfo(id, phone: phone.text.trim(), notes: notes.text.trim());
      await _load();
    }
    phone.dispose();
    notes.dispose();
  }

  Future<void> _delete() async {
    final f = _f!;
    if (f.invoices.isNotEmpty) {
      setToast(context, 'لا يمكن الحذف: للمؤسس ${f.invoices.length} فاتورة. أزل اسمه منها أولاً.', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المؤسس'),
        content: Text('يُحذف «${f.name}» وكل حركات نقاطه اليدوية. لا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kSetRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await FounderService.delete(f);
    if (!mounted) return;
    if (err != null) {
      setToast(context, err, error: true);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final r = _rangeOf(_period, _custom);
    return ReportScaffold(
      title: widget.founderName,
      subtitle: 'تفاصيل المؤسس ونقاطه',
      icon: Icons.engineering_rounded,
      loading: _loading,
      onRefresh: _load,
      header: _PeriodBar(value: _period, label: r.label, onChanged: _setPeriod),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'المزيد',
          onSelected: (v) {
            if (v == 'info') _editInfo();
            if (v == 'delete') _delete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'info', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('الهاتف والملاحظات'))),
            PopupMenuItem(
                value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: kSetRed), title: Text('حذف المؤسس'))),
          ],
        ),
      ],
      children: f == null ? const [SizedBox.shrink()] : [_header(f), _kpis(f, r), _chart(f), _middle(f, r), _tabs(f, r)],
    );
  }

  Widget _header(FounderStats f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0F3460), Color(0xFF1B5E8C)], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _Avatar(f.name, size: 62),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.name, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_rounded, size: 14, color: Colors.white60),
                const SizedBox(width: 4),
                Text(f.phone.isEmpty ? 'بلا هاتف' : f.phone, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white70)),
                if (f.phone.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'نسخ',
                    icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.white60),
                    onPressed: () => Clipboard.setData(ClipboardData(text: f.phone)),
                  ),
              ]),
              if (f.notes.isNotEmpty) Text(f.notes, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('رصيد النقاط', style: TextStyle(color: Colors.white70)),
              Text(_pts(f.balance), style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 34, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(width: 16),
            Column(mainAxisSize: MainAxisSize.min, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _kGold),
                // يُسمح بالصرف حتى لو صار الرصيد سالباً (سُلفة على نقاطه القادمة)
                onPressed: () => _move(payout: true),
                icon: const Icon(Icons.redeem_rounded, size: 18),
                label: const Text('صرف نقاط'),
              ),
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                  onPressed: () => _move(payout: false, deduct: true),
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                  label: const Text('خصم نقاط'),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                  onPressed: () => _move(payout: false),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('إضافة'),
                ),
              ]),
            ]),
          ]),
        ],
      ),
    );
  }

  Widget _kpis(FounderStats f, _Range r) {
    final inv = f.inRange(r.from, r.to);
    final pts = _sumPoints(inv);
    final sales = _sumNet(inv);
    final returns = inv.fold(0.0, (s, i) => s + i.returns);
    final customers = inv.map((i) => i.customer).toSet().length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: KpiGrid(minTileWidth: 200, children: [
        KpiTile(label: 'نقاط ${r.label}', value: FounderService.round2(pts), icon: Icons.stars_rounded, color: _kGold, money: false, emphasis: true),
        KpiTile(label: 'المبيعات', value: sales, icon: Icons.payments_rounded, color: kSetGreen, hint: 'صافي بعد المرتجع'),
        KpiTile(label: 'الفواتير', value: inv.length.toDouble(), icon: Icons.receipt_long_rounded, color: kSetBlue, money: false),
        KpiTile(label: 'متوسط الفاتورة', value: inv.isEmpty ? 0 : sales / inv.length, icon: Icons.analytics_rounded, color: kRepPurple),
        KpiTile(label: 'العملاء', value: customers.toDouble(), icon: Icons.people_alt_rounded, color: kRepTeal, money: false),
        KpiTile(label: 'مرتجع على فواتيره', value: returns, icon: Icons.assignment_return_rounded, color: kSetRed),
        KpiTile(
            label: 'كل النقاط المكتسبة',
            value: FounderService.round2(f.earnedAll),
            icon: Icons.workspace_premium_rounded,
            color: _kGold,
            money: false),
        KpiTile(
          label: 'نقاط مصروفة ومخصومة',
          value: FounderService.round2(f.paidOut),
          icon: Icons.redeem_rounded,
          color: kSetOrange,
          money: false,
          hint: f.paidOut <= 0
              ? null
              : [
                  if (f.rewardsOut > 0) 'جوائز ${_pts(f.rewardsOut)}',
                  if (f.returnsOut > 0) 'دين راجع ${_pts(f.returnsOut)}',
                  if (f.paidOut - f.rewardsOut - f.returnsOut > 0.005)
                    'خصم يدوي ${_pts(f.paidOut - f.rewardsOut - f.returnsOut)}',
                ].join(' • '),
        ),
        if (f.addedAndCarried.abs() >= 0.01)
          KpiTile(
            label: 'إضافات وفروق منقولة',
            value: FounderService.round2(f.addedAndCarried),
            icon: Icons.add_circle_outline_rounded,
            color: kSetGreen,
            money: false,
            hint: 'المكتسب + هذه − المصروف = الرصيد',
          ),
      ]),
    );
  }

  Widget _chart(FounderStats f) {
    final (values, labels) = _monthly(f.invoices);
    return SetCard(
      title: 'نقاطه شهرياً',
      subtitle: 'آخر 12 شهراً',
      icon: Icons.bar_chart_rounded,
      color: _kGold,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: MiniBars(
          values: values,
          labels: labels,
          tooltips: [for (var i = 0; i < 12; i++) '${labels[i]}: ${_pts(values[i])} نقطة'],
          color: _kGold,
          highlight: 11,
        ),
      ),
    );
  }

  Widget _middle(FounderStats f, _Range r) {
    final inv = f.inRange(r.from, r.to);
    final byCustomer = <String, (double, double, int)>{};
    for (final i in inv) {
      final o = byCustomer[i.customer] ?? (0.0, 0.0, 0);
      byCustomer[i.customer] = (o.$1 + i.net, o.$2 + i.points, o.$3 + 1);
    }
    final top = byCustomer.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final maxSales = top.isEmpty || top.first.value.$1 <= 0 ? 1.0 : top.first.value.$1;

    final rates = <double, int>{};
    for (final i in inv) {
      rates[i.rate] = (rates[i.rate] ?? 0) + 1;
    }
    final rateList = rates.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final customersCard = SetCard(
      title: 'أهم عملائه',
      subtitle: r.label,
      icon: Icons.people_alt_rounded,
      color: kRepTeal,
      child: top.isEmpty
          ? const EmptyReport(title: 'لا فواتير في هذه الفترة', icon: Icons.people_alt_rounded)
          : Column(children: [
              for (var i = 0; i < top.length && i < 6; i++)
                RankRow(
                  rank: i + 1,
                  title: top[i].key,
                  subtitle: '${top[i].value.$3} فاتورة • ${_pts(top[i].value.$2)} نقطة',
                  value: top[i].value.$1,
                  fraction: top[i].value.$1 / maxSales,
                  color: kRepTeal,
                ),
            ]),
    );
    final ratesCard = SetCard(
      title: 'معدلات النقاط المستعملة',
      subtitle: 'نقاط لكل 100,000 في فواتيره',
      icon: Icons.tune_rounded,
      color: kRepPurple,
      child: rateList.isEmpty
          ? const EmptyReport(title: 'لا فواتير في هذه الفترة', icon: Icons.tune_rounded)
          : Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in rateList)
                Chip(
                  avatar: const Icon(Icons.stars_rounded, size: 16, color: _kGold),
                  label: Text('${_pts(e.key)} لكل 100 ألف — ${e.value} فاتورة'),
                  backgroundColor: _kGoldSoft,
                  side: const BorderSide(color: Color(0xFFFDE68A)),
                ),
            ]),
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 820) return Column(children: [customersCard, ratesCard]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: customersCard),
        const SizedBox(width: 14),
        Expanded(flex: 2, child: ratesCard),
      ]);
    });
  }

  Widget _tabs(FounderStats f, _Range r) {
    final inv = f.inRange(r.from, r.to);
    return SetCard(
      title: _tab == 0 ? 'الفواتير (${inv.length})' : 'حركات النقاط اليدوية (${f.moves.length})',
      icon: _tab == 0 ? Icons.receipt_long_rounded : Icons.swap_vert_rounded,
      color: kSetNavy,
      trailing: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: Text('الفواتير'), icon: Icon(Icons.receipt_long_rounded, size: 16)),
          ButtonSegment(value: 1, label: Text('الحركات'), icon: Icon(Icons.swap_vert_rounded, size: 16)),
        ],
        selected: {_tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _tab == 0
            ? (inv.isEmpty
                ? const EmptyReport(key: ValueKey('e0'), title: 'لا فواتير في هذه الفترة', icon: Icons.receipt_long_rounded)
                : Column(key: const ValueKey('t0'), children: [for (final i in inv) _InvoiceRow(i)]))
            : (f.moves.isEmpty
                ? const EmptyReport(
                    key: ValueKey('e1'),
                    title: 'لا حركات يدوية',
                    text: 'استعمل «صرف نقاط» أو «إضافة / خصم» أعلى الصفحة.',
                    icon: Icons.swap_vert_rounded)
                : Column(key: const ValueKey('t1'), children: [for (final m in f.moves) _moveTile(m)])),
      ),
    );
  }

  Widget _moveTile(FounderMove m) {
    final c = m.points >= 0 ? kSetGreen : (m.isPayout ? _kGold : (m.isReturnDeduction ? const Color(0xFFE91E63) : kSetRed));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: c.withValues(alpha: 0.12),
        child: Icon(
            m.isPayout
                ? Icons.redeem_rounded
                : (m.isReturnDeduction
                    ? Icons.assignment_return_rounded
                    : (m.points >= 0 ? Icons.add_rounded : Icons.remove_rounded)),
            color: c),
      ),
      title: Text(m.reason, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(_dayFmt.format(m.at)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${m.points >= 0 ? '+' : ''}${_pts(m.points)}',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: m.points >= 0 ? kSetGreen : kSetRed)),
        if (m.deletable)
          IconButton(
            tooltip: 'حذف الحركة',
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: kSetMuted),
            onPressed: () async {
              await FounderService.deleteMove(m.id);
              await _load();
            },
          ),
      ]),
    );
  }
}

// ═════════════════════════════ نوافذ صغيرة ═════════════════════════════

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.payout, required this.balance, this.startDeduct = false});
  final bool payout;
  final double balance;
  final bool startDeduct;
  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  final _points = TextEditingController();
  final _reason = TextEditingController();
  late bool _add = !widget.startDeduct;

  @override
  void dispose() {
    _points.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_points.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    // يُسمح بالسالب: تحذير فقط، لا منع
    final after = FounderService.round2(widget.balance + (widget.payout || !_add ? -_value : _value));
    final negative = _value > 0 && after < 0;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Icon(widget.payout ? Icons.redeem_rounded : Icons.exposure_rounded, color: _kGold),
        const SizedBox(width: 8),
        Flexible(child: Text(widget.payout ? 'صرف نقاط (جائزة / مكافأة)' : 'إضافة أو خصم نقاط')),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.payout) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('إضافة'), icon: Icon(Icons.add_rounded)),
                ButtonSegment(value: false, label: Text('خصم'), icon: Icon(Icons.remove_rounded)),
              ],
              selected: {_add},
              onSelectionChanged: (s) => setState(() => _add = s.first),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _points,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'عدد النقاط',
              prefixIcon: const Icon(Icons.stars_rounded),
              helperText: 'الرصيد الحالي ${_pts(widget.balance)} ← بعد الحفظ ${_pts(after)}'
                  '${negative ? ' (سالب — مسموح)' : ''}',
              helperStyle: TextStyle(color: negative ? kSetOrange : null, fontWeight: negative ? FontWeight.w700 : null),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            decoration: InputDecoration(
              labelText: widget.payout ? 'ماذا صُرف؟ (اختياري)' : 'السبب (اختياري)',
              prefixIcon: const Icon(Icons.notes_rounded),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed:
              _value <= 0 ? null : () => Navigator.pop(context, (widget.payout || _add ? _value : -_value, _reason.text)),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

Future<double?> _askNumber(BuildContext context, String title, String label, double initial) async {
  final c = TextEditingController(text: _pts(initial));
  final r = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.stars_rounded)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.'))), child: const Text('حفظ')),
      ],
    ),
  );
  c.dispose();
  return r;
}

Future<String?> _askText(BuildContext context, String title, String label) async {
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.engineering_rounded)),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('إضافة')),
      ],
    ),
  );
  c.dispose();
  return r;
}
