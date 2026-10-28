// lib/radar/radar_screen.dart
//
// 📡 «رادار التاجر»: صفحة واحدة لصاحب المحل — الربح الحقيقي، التنبيهات، السيولة
// المتوقعة، من يُتابَع بالتحصيل أولاً، وماذا يُشترى. كل رقم محسوب من بيانات
// البرنامج (لا ذكاء اصطناعي)، وكل تنبيه يعرض العمليات التي بُني عليها.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../accounting/screens/acc_ui.dart' show AccColors, fmtMoney;
import '../erp/erp_common.dart' show fmtQty;
import 'radar_engine.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF4F6FA);
const _cHigh = Color(0xFFB91C1C);
const _cMid = Color(0xFFC2410C);
const _cInfo = Color(0xFF2563EB);
const _cGood = Color(0xFF047857);

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});
  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  final _engine = RadarEngine();
  // يُنشأ في initState: الإنشاء الكسول كان يحدث أول مرة داخل dispose (حين لا تُستعمل
  // التبويبات في التخطيط العريض) ⇒ «Looking up a deactivated widget's ancestor is unsafe»
  late final TabController _tabs;

  Future<RadarKpis>? _kpis;
  Future<List<RadarAlert>>? _alerts;
  Future<CashFlows>? _flows;
  Future<List<CollectionTarget>>? _collect;
  Future<List<BuySuggestion>>? _buy;

  // سيناريوهات السيولة
  double _delay = 0, _salesChange = 0, _usdChange = 0;
  final _purchaseCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _purchaseCtl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _kpis = _engine.kpis();
      _alerts = _engine.alerts();
      _flows = _engine.cashFlows();
      _collect = _engine.collectionTargets();
      _buy = _engine.buySuggestions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 230,
            foregroundColor: Colors.white,
            backgroundColor: AccColors.navy,
            title: const Text('رادار التاجر', style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [IconButton(tooltip: 'تحديث', onPressed: _reload, icon: const Icon(Icons.refresh_rounded))],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AccColors.navyDark, AccColors.navy, Color(0xFF0E7490)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 86, 16, 54),
                child: _kpiStrip(),
              ),
            ),
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              indicatorColor: AccColors.cyan,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(icon: Icon(Icons.policy_rounded, size: 20), text: 'المحقق المالي'),
                Tab(icon: Icon(Icons.water_drop_rounded, size: 20), text: 'السيولة المتوقعة'),
                Tab(icon: Icon(Icons.phone_in_talk_rounded, size: 20), text: 'التحصيل'),
                Tab(icon: Icon(Icons.shopping_cart_checkout_rounded, size: 20), text: 'الشراء الذكي'),
              ],
            ),
          ),
        ],
        body: TabBarView(controller: _tabs, children: [
          _alertsTab(),
          _cashTab(),
          _collectTab(),
          _buyTab(),
        ]),
      ),
    );
  }

  // ───────────────────────── المؤشرات ─────────────────────────

  Widget _kpiStrip() {
    return FutureBuilder<RadarKpis>(
      future: _kpis,
      builder: (context, s) {
        final k = s.data;
        Widget kpi(String label, String value, {String? sub, Color? subColor}) => Container(
              width: 175,
              margin: const EdgeInsetsDirectional.only(end: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                ),
                if (sub != null)
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subColor ?? Colors.white60, fontSize: 11.5)),
              ]),
            );
        if (k == null) {
          return const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)));
        }
        final diff = k.margin30 - k.marginPrev30;
        return ListView(scrollDirection: Axis.horizontal, children: [
          kpi('الربح الحقيقي (30 يوماً)', fmtMoneyCompact(k.profit30), sub: 'من مبيعات ${fmtMoneyCompact(k.revenue30)}'),
          kpi('هامش الربح', '${k.margin30.toStringAsFixed(1)}%',
              sub: '${diff >= 0 ? '▲' : '▼'} ${diff.abs().toStringAsFixed(1)} عن الشهر السابق',
              subColor: diff >= 0 ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
          kpi('ديون العملاء', fmtMoneyCompact(k.receivables),
              sub: 'منها أقدم من 90 يوماً ${fmtMoneyCompact(k.overdue90)}',
              subColor: k.overdue90 > 0 ? const Color(0xFFFCD34D) : null),
          kpi('النقد في الصناديق', fmtMoneyCompact(k.cashNow), sub: 'من دفتر المحاسبة'),
        ]);
      },
    );
  }

  // ───────────────────────── المحقق المالي ─────────────────────────

  Widget _alertsTab() {
    return FutureBuilder<List<RadarAlert>>(
      future: _alerts,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _error('${s.error}');
        final list = s.data ?? const [];
        if (list.isEmpty) {
          return _empty(Icons.verified_rounded, 'لا شيء يحتاج انتباهك الآن',
              'فحصتُ هامش الربح، والبيع تحت الكلفة، والخصومات، والديون، والمرتجعات، والمخزون — كلها ضمن المعتاد.', _cGood);
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
          itemCount: list.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              final high = list.where((a) => a.level == RadarLevel.high).length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${list.length} تنبيه${high > 0 ? ' — $high عاجل' : ''} • محسوبة من بيانات البرنامج، اضغط أي تنبيه لترى العمليات',
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
              );
            }
            return _AlertCard(alert: list[i - 1]);
          },
        );
      },
    );
  }

  // ───────────────────────── السيولة ─────────────────────────

  Widget _cashTab() {
    return FutureBuilder<CashFlows>(
      future: _flows,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _error('${s.error}');
        final f = s.data!;
        final purchase = double.tryParse(_purchaseCtl.text.replaceAll(',', '')) ?? 0;
        final proj = RadarEngine.project(f,
            delayPct: _delay, salesChangePct: _salesChange, usdChangePct: _usdChange, newPurchase: purchase);
        final worst = proj.map((p) => p.end).reduce((a, b) => a < b ? a : b);
        return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
          if (!f.hasLedger)
            _banner('لا توجد حركات صناديق مرحّلة في دفتر المحاسبة بعد — التوقع يحتاج سجل النقد. تأكد أن المحاسبة مفعّلة وأن الترحيل يعمل.',
                _cMid, Icons.info_outline_rounded),
          if (worst < 0)
            _banner('قد تواجه عجزاً في النقد يصل إلى ${fmtMoney(-worst)} خلال الفترة القادمة بهذه الافتراضات. '
                'راجع مواعيد تحصيل الديون قبل أي شراء كبير.', _cHigh, Icons.warning_amber_rounded),
          Row(children: [
            for (final p in proj) Expanded(child: _projCard(p, f.cashNow)),
          ]),
          const SizedBox(height: 14),
          _card(
            title: 'ماذا لو؟',
            icon: Icons.tune_rounded,
            child: Column(children: [
              _slider('تأخر التحصيل', _delay, 0, 80, '%', (v) => setState(() => _delay = v)),
              _slider('تغيّر المبيعات', _salesChange, -50, 50, '%', (v) => setState(() => _salesChange = v)),
              if (f.duesUsd.isNotEmpty)
                _slider('تغيّر سعر الدولار', _usdChange, -20, 30, '%', (v) => setState(() => _usdChange = v)),
              const SizedBox(height: 8),
              TextField(
                controller: _purchaseCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'شراء جديد أدفعه الآن (دينار)',
                  prefixIcon: const Icon(Icons.local_shipping_rounded),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _card(
            title: 'على ماذا بُني التوقع',
            icon: Icons.fact_check_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv('النقد في الصناديق الآن', fmtMoney(f.cashNow)),
              _kv('متوسط المبيعات النقدية اليومية', fmtMoney(f.salesIn)),
              _kv('متوسط تحصيل الديون اليومي', fmtMoney(f.collectionsIn)),
              _kv('متوسط الدفع للموردين اليومي', fmtMoney(f.suppliersOut)),
              _kv('متوسط المصاريف والمدفوعات الأخرى اليومية', fmtMoney(f.otherOut)),
              _kv('مقبوضات أخرى يومية', fmtMoney(f.otherIn)),
              _kv('ديون العملاء (أقصى ما يُحصَّل)', fmtMoney(f.receivables)),
              _kv('مستحقات موردين بتاريخ استحقاق (دينار)', fmtMoney(f.duesIqd.fold<double>(0, (s, d) => s + d.$2))),
              if (f.duesUsd.isNotEmpty)
                _kv('مستحقات موردين بالدولار', '\$${fmtMoney(f.duesUsd.fold<double>(0, (s, d) => s + d.$2))}'
                    '${f.usdRate > 0 ? ' × ${fmtMoney(f.usdRate)}' : ' (لا سعر دولار مسجّل)'}'),
              const SizedBox(height: 8),
              Text(
                'المعدلات من حركات الصناديق الفعلية آخر ${f.spanDays} يوماً (بلا التحويل بين الصناديق ولا الأرصدة الافتتاحية). '
                'دفع الموردين = الأكبر بين معدلك المعتاد والمستحقات المسجلة حتى ذلك اليوم. '
                'هذا تقدير يساعد القرار وليس وعداً: يتغيّر إذا تغيّر نمط البيع أو التحصيل.',
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _projCard(CashProjection p, double now) {
    final bad = p.end < 0;
    final c = bad ? _cHigh : (p.end < now * 0.3 ? _cMid : _cGood);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('بعد ${p.days} يوماً', style: const TextStyle(color: _muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(fmtMoneyCompact(p.end), style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 8),
        _flowBar(p.inflow, p.outflow),
        const SizedBox(height: 6),
        Text('▲ يدخل ${fmtMoneyCompact(p.inflow)}', style: const TextStyle(fontSize: 11.5, color: _cGood)),
        Text('▼ يخرج ${fmtMoneyCompact(p.outflow)}', style: const TextStyle(fontSize: 11.5, color: _cHigh)),
        Text('منه للموردين ${fmtMoneyCompact(p.suppliers)}', style: const TextStyle(fontSize: 11, color: _muted)),
      ]),
    );
  }

  Widget _flowBar(double a, double b) {
    final t = a + b;
    final fa = t <= 0 ? 0.5 : a / t;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Row(children: [
          Expanded(flex: (fa * 1000).round().clamp(1, 999).toInt(), child: Container(color: _cGood)),
          Expanded(flex: ((1 - fa) * 1000).round().clamp(1, 999).toInt(), child: Container(color: _cHigh)),
        ]),
      ),
    );
  }

  Widget _slider(String label, double v, double min, double max, String unit, ValueChanged<double> on) => Row(children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(
          child: Slider(value: v, min: min, max: max, divisions: ((max - min) / 5).round(), label: '${v.round()}$unit', onChanged: on),
        ),
        SizedBox(
          width: 52,
          child: Text('${v >= 0 && min < 0 ? '+' : ''}${v.round()}$unit',
              textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]);

  // ───────────────────────── التحصيل ─────────────────────────

  Widget _collectTab() {
    return FutureBuilder<List<CollectionTarget>>(
      future: _collect,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _error('${s.error}');
        final list = s.data ?? const [];
        if (list.isEmpty) return _empty(Icons.celebration_rounded, 'لا ديون على العملاء', 'كل العملاء مسددون.', _cGood);
        final total = list.fold<double>(0, (s, t) => s + t.balance);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
          itemCount: list.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${list.length} عميلاً عليهم ${fmtMoney(total)} — مرتبون حسب الأولوية: حجم الدين، عمر أقدم دين، الانقطاع عن السداد، وتجاوز السقف.',
                  style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.5),
                ),
              );
            }
            return _collectCard(list[i - 1], i);
          },
        );
      },
    );
  }

  Widget _collectCard(CollectionTarget t, int rank) {
    final c = t.score >= 70 ? _cHigh : (t.score >= 45 ? _cMid : _cInfo);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
      child: Row(children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(value: t.score / 100, strokeWidth: 5, color: c, backgroundColor: c.withValues(alpha: 0.12)),
            Text('${t.score}', style: TextStyle(fontWeight: FontWeight.w900, color: c)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$rank. ', style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
              Expanded(child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 15))),
              Text(fmtMoney(t.balance), style: TextStyle(fontWeight: FontWeight.w900, color: c)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final r in t.reasons.skip(1))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
                  child: Text(r, style: const TextStyle(fontSize: 11.5, color: _muted)),
                ),
            ]),
          ]),
        ),
        if ((t.phone ?? '').trim().isNotEmpty) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'تذكير عبر واتساب',
            onPressed: () => _whatsApp(t),
            icon: const Icon(Icons.chat_rounded, color: Color(0xFF16A34A)),
          ),
          IconButton(
            tooltip: 'اتصال',
            onPressed: () => launchUrl(Uri.parse('tel:${t.phone!.trim()}')),
            icon: const Icon(Icons.call_rounded, color: _cInfo),
          ),
        ],
      ]),
    );
  }

  Future<void> _whatsApp(CollectionTarget t) async {
    var p = (t.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (p.startsWith('00')) p = p.substring(2);
    if (p.startsWith('0')) p = '964${p.substring(1)}';
    if (p.length == 10 && p.startsWith('7')) p = '964$p';
    final msg = 'السلام عليكم ${t.name}،\nنذكّركم بأن الرصيد المستحق في حسابكم لدينا ${fmtMoney(t.balance)} دينار.\n'
        'نرجو التكرم بتسديده أو التواصل معنا لترتيب موعد. مع الشكر.';
    final ok = await launchUrl(Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح واتساب')));
    }
  }

  // ───────────────────────── الشراء الذكي ─────────────────────────

  Widget _buyTab() {
    return FutureBuilder<List<BuySuggestion>>(
      future: _buy,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return _error('${s.error}');
        final list = s.data ?? const [];
        if (list.isEmpty) {
          return _empty(Icons.inventory_rounded, 'المخزون يكفي', 'لا توجد مادة يُتوقع أن تنقص خلال 30 يوماً بحسب بيعك الأخير.', _cGood);
        }
        final total = list.fold<double>(0, (s, b) => s + b.value);
        return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
          Row(children: [
            Expanded(
              child: Text(
                '${list.length} مادة يُتوقع أن تنقص خلال 30 يوماً • كلفة الشراء المقترح ${fmtMoney(total)}',
                style: const TextStyle(color: _muted, fontSize: 12.5),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                final text = [
                  'طلب شراء مقترح:',
                  for (final b in list) '- ${b.name}: ${fmtQty(b.suggestQty)} ${b.unit}',
                ].join('\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخت القائمة — الصقها للمورد')));
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('نسخ القائمة'),
            ),
          ]),
          const SizedBox(height: 6),
          for (final b in list) _buyCard(b),
          const SizedBox(height: 8),
          const Text(
            'الكمية = بيعك الشهري في آخر 3 أشهر × معامل موسم هذا الشهر (من مبيعات السنوات السابقة) + 20% أمان − الرصيد الحالي. '
            'المسودة لا تُرسل لأحد ولا تُنشئ فاتورة شراء.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ]);
      },
    );
  }

  Widget _buyCard(BuySuggestion b) {
    final urgent = (b.coverDays ?? 999) < 7;
    final c = urgent ? _cHigh : ((b.coverDays ?? 999) < 15 ? _cMid : _cInfo);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
      child: Row(children: [
        Container(
          width: 46,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(b.coverDays == null ? '—' : b.coverDays!.toStringAsFixed(0),
                style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 16)),
            Text('يوم', style: TextStyle(fontSize: 10, color: c)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink))),
              if (b.seasonIndex >= 1.15)
                _tag('موسم ↑ ×${b.seasonIndex.toStringAsFixed(1)}', _cMid)
              else if (b.seasonIndex <= 0.85)
                _tag('موسم ↓ ×${b.seasonIndex.toStringAsFixed(1)}', _cInfo),
            ]),
            const SizedBox(height: 4),
            Text(
              'الرصيد ${fmtQty(b.stock)} • يبيع ${fmtQty(b.recentMonthly)} شهرياً • المتوقع ${fmtQty(b.forecast30)}',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${fmtQty(b.suggestQty)} ${b.unit}', style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
          if (b.cost > 0) Text(fmtMoneyCompact(b.value), style: const TextStyle(fontSize: 11.5, color: _muted)),
        ]),
      ]),
    );
  }

  // ───────────────────────── عناصر مشتركة ─────────────────────────

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
      );

  Widget _card({required String title, required IconData icon, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: AccColors.navy, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink)),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: _muted, fontSize: 13))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
        ]),
      );

  Widget _banner(String t, Color c, IconData i) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text(t, style: TextStyle(color: c, height: 1.5, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _empty(IconData i, String t, String sub, Color c) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 60, color: c),
            const SizedBox(height: 12),
            Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 6),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.5)),
          ]),
        ),
      );

  Widget _error(String e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText('تعذّر الحساب: $e', style: const TextStyle(color: _cHigh)),
        ),
      );
}

/// بطاقة تنبيه قابلة للفتح: لماذا + ماذا أفعل + العمليات التي بُني عليها
class _AlertCard extends StatefulWidget {
  const _AlertCard({required this.alert});
  final RadarAlert alert;
  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.alert;
    final c = switch (a.level) { RadarLevel.high => _cHigh, RadarLevel.medium => _cMid, RadarLevel.info => _cInfo };
    final icon = switch (a.level) {
      RadarLevel.high => Icons.error_rounded,
      RadarLevel.medium => Icons.warning_amber_rounded,
      RadarLevel.info => Icons.lightbulb_rounded,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: _open ? 0.5 : 0.25)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: _open ? 0.10 : 0.04), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: a.items.isEmpty ? null : () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: c, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: _ink))),
              if (a.items.isNotEmpty)
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(Icons.expand_more_rounded, color: _muted),
                ),
            ]),
            const SizedBox(height: 8),
            Text(a.body, style: const TextStyle(color: _ink, height: 1.55)),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.subdirectory_arrow_left_rounded, size: 18, color: c),
              const SizedBox(width: 4),
              Expanded(child: Text(a.action, style: TextStyle(color: c, fontWeight: FontWeight.w700, height: 1.5))),
            ]),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(children: [
                  const Divider(height: 1, color: _line),
                  for (final it in a.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                            if (it.sub != null) Text(it.sub!, style: const TextStyle(fontSize: 12, color: _muted)),
                          ]),
                        ),
                        Text(it.value, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
                      ]),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
