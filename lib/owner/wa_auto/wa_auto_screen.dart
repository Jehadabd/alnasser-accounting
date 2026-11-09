// lib/owner/wa_auto/wa_auto_screen.dart
//
// 👑💬 شاشة «تذكير الديون الشهري عبر واتساب» — حساب المالك ومدير البرنامج فقط.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../widgets/settings_kit.dart';
import 'wa_auto_reminder.dart';
import 'wa_desktop.dart';
import 'wa_server_client.dart';
import 'wa_server_screen.dart';
import 'wa_usage_banner.dart';
import 'wa_usage_mark.dart';

class WaAutoScreen extends StatefulWidget {
  const WaAutoScreen({super.key});

  @override
  State<WaAutoScreen> createState() => _WaAutoScreenState();
}

class _WaAutoScreenState extends State<WaAutoScreen> {
  WaAutoSettings? _s;
  final _min = TextEditingController();
  final _tpl = TextEditingController();
  final _minDelay = TextEditingController();
  final _maxDelay = TextEditingController();
  final _perDay = TextEditingController();
  final _loadWait = TextEditingController();
  ({List<WaTarget> targets, int noPhone, int badPhone})? _debtors;
  List<WaTarget> _targets = const [];
  final _testPhone = TextEditingController();
  bool _testing = false;
  String? _testResult;
  Map<String, Map<String, dynamic>> _log = {};
  String _shop = '';
  bool _dirty = false;
  Timer? _tick;

  static final _n = NumberFormat('#,##0', 'en');

  @override
  void initState() {
    super.initState();
    _load();
    WaAutoReminder.state.addListener(_onRun);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && WaAutoReminder.running) setState(() {}); // العدّ التنازلي
    });
  }

  @override
  void dispose() {
    WaAutoReminder.state.removeListener(_onRun);
    _tick?.cancel();
    for (final c in [_min, _tpl, _minDelay, _maxDelay, _perDay, _loadWait, _testPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onRun() {
    if (!mounted) return;
    if (!WaAutoReminder.running) _refresh();
    setState(() {});
  }

  Future<void> _load() async {
    final s = await WaAutoReminder.load();
    _min.text = _n.format(s.minDebt.round());
    _tpl.text = s.template;
    _minDelay.text = '${s.minDelay}';
    _maxDelay.text = '${s.maxDelay}';
    _perDay.text = '${s.maxPerDay}';
    _loadWait.text = '${s.loadWait}';
    _shop = await WaAutoReminder.shopName();
    if (!mounted) return;
    setState(() => _s = s);
    await _refresh();
  }

  Future<void> _refresh() async {
    final s = _s;
    if (s == null) return;
    final d = await WaAutoReminder.debtors(s.minDebt);
    final t = await WaAutoReminder.targets(s);
    final log = await WaAutoReminder.monthLog();
    if (mounted) {
      setState(() {
        _debtors = d;
        _targets = t;
        _log = log;
      });
    }
  }

  int _int(TextEditingController c, int def) => int.tryParse(c.text.replaceAll(',', '').trim()) ?? def;

  WaAutoSettings _fromFields(WaAutoSettings s) => s.copyWith(
        minDebt: double.tryParse(_min.text.replaceAll(',', '').trim()) ?? s.minDebt,
        template: _tpl.text.trim().isEmpty ? WaAutoSettings.defaultTemplate : _tpl.text,
        minDelay: _int(_minDelay, s.minDelay),
        maxDelay: _int(_maxDelay, s.maxDelay),
        maxPerDay: _int(_perDay, s.maxPerDay),
        loadWait: _int(_loadWait, s.loadWait),
      );

  Future<void> _save([WaAutoSettings? next]) async {
    final s = _fromFields(next ?? _s!);
    await WaAutoReminder.save(s);
    final reloaded = await WaAutoReminder.load();
    if (!mounted) return;
    setState(() {
      _s = reloaded;
      _dirty = false;
      _minDelay.text = '${reloaded.minDelay}';
      _maxDelay.text = '${reloaded.maxDelay}';
      _perDay.text = '${reloaded.maxPerDay}';
      _loadWait.text = '${reloaded.loadWait}';
    });
    await _refresh();
  }

  Future<void> _enable(bool on) async {
    if (on && !(_s!.riskAccepted)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 36),
          title: const Text('إرسال آلي من رقم واتساب عادي'),
          content: const Text(
            'هذه ليست طريقة رسمية من واتساب. واتساب قد يقيّد أو يحظر الرقم إن رأى رسائل آلية كثيرة، '
            'خاصة إن أبلغ عنها المستلمون.\n\n'
            'البرنامج يقلل الخطر (فاصل عشوائي، حد يومي، رسالة واحدة في الشهر لكل زبون)، لكنه لا يلغيه.\n\n'
            'أثناء الإرسال لا تستعمل الحاسبة: البرنامج يفتح واتساب ويضغط «إرسال» بنفسه.',
            style: TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB45309)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('أفهم الخطر وأتحمّله'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await WaUsageMark.record(_s!.via); // 🔖 علامة دائمة لا يمحوها الإطفاء
      await _save(_s!.copyWith(enabled: true, riskAccepted: true));
      return;
    }
    if (on) await WaUsageMark.record(_s!.via);
    await _save(_s!.copyWith(enabled: on));
  }

  Future<void> _start({int? limit}) async {
    if (_dirty) await _save();
    if (!mounted) return;
    final pending = _targets.where((t) => _log['${t.id}']?['s'] != 'sent').length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(limit == null ? 'بدء الإرسال' : 'تجربة على $limit زبائن'),
        content: Text(
          '${limit == null ? 'سيُرسل لـ $pending زبوناً (ضمن الحد اليومي).' : 'سيُرسل لأول $limit ممن لم يُذكَّروا هذا الشهر.'}\n\n'
          '${_s!.viaServer ? 'يرسل الخادم في الخلفية.' : 'تأكد أن WhatsApp Desktop مفتوح ومسجّل الدخول. لا تستعمل الحاسبة حتى ينتهي.'}\n'
          'للإيقاف: ارجع إلى هذه الشاشة واضغط «إيقاف».',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ابدأ')),
        ],
      ),
    );
    if (ok != true) return;
    unawaited(WaAutoReminder.run(limit: limit));
  }

  int get _sentCount => _log.values.where((v) => v['s'] == 'sent').length;

  static const _overdueChoices = [0, 1, 2, 3, 4, 6, 12];
  static String _overdueLabel(int m) => m == 0 ? 'كل من عليه دين' : 'لم يسدّد منذ $m ${m <= 2 ? (m == 1 ? 'شهر' : 'شهرين') : (m <= 10 ? 'أشهر' : 'شهراً')} فأكثر';

  /// إرسال يدوي للمتأخرين N شهراً — لا يغيّر الإعدادات المحفوظة.
  Future<void> _sendLate() async {
    if (_dirty) await _save();
    if (!mounted) return;
    final s = _s!;
    var months = s.overdueMonths > 0 ? s.overdueMonths : 3;
    var all = !s.onlySelected;
    Future<int> count() async =>
        (await WaAutoReminder.pending(s.copyWith(overdueMonths: months, onlySelected: !all))).length;
    var n = await count();
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> update() async {
            final v = await count();
            if (ctx.mounted) set(() => n = v);
          }

          return AlertDialog(
            title: const Text('إرسال للمتأخرين عن التسديد'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in _overdueChoices.where((m) => m > 0))
                  ChoiceChip(
                    label: Text('$m ${m == 1 ? 'شهر' : (m == 2 ? 'شهرين' : 'أشهر')}+'),
                    selected: months == m,
                    onSelected: (_) {
                      months = m;
                      update();
                    },
                  ),
              ]),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('كل المدينين برقم صالح'),
                subtitle: Text(all ? 'فوق الحد الأدنى للدين' : 'من اخترتهم فقط'),
                value: all,
                onChanged: (v) {
                  all = v;
                  update();
                },
              ),
              const SizedBox(height: 6),
              Text('سيُرسل لـ $n زبوناً (لم يُذكَّروا هذا الشهر، ضمن الحد اليومي).',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(s.viaServer ? 'يرسل الخادم في الخلفية.' : 'تأكد أن WhatsApp Desktop مفتوح. لا تستعمل الحاسبة حتى ينتهي.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: n == 0 ? null : () => Navigator.pop(ctx, true), child: const Text('ابدأ')),
            ],
          );
        },
      ),
    );
    if (go != true) return;
    unawaited(WaAutoReminder.run(overdue: months, allDebtors: all));
  }

  Future<void> _test() async {
    if (_dirty) await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final err = await WaAutoReminder.sendTest(_testPhone.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = err == null ? 'ضُغط «إرسال» في واتساب ✓ — تأكد من وصولها على الرقم الآخر' : 'لم تُرسل: $err';
    });
  }

  Future<void> _pick() async {
    final all = await WaAutoReminder.withPhones();
    if (!mounted) return;
    final chosen = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _PickDialog(all: all, initial: _s!.selected),
    );
    if (chosen != null) await _save(_s!.copyWith(selected: chosen));
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return const SettingsScaffold(title: 'تذكير الديون عبر واتساب', icon: Icons.chat_rounded, loading: true);
    }
    final run = WaAutoReminder.state.value;
    return SettingsScaffold(
      title: 'تذكير الديون عبر واتساب',
      icon: Icons.chat_rounded,
      subtitle: 'رسالة شهرية لكل مدين باسمه ومبلغه — من WhatsApp Desktop أو من خادمك',
      children: [
        const WaUsageBanner(),
        const SetBanner(
          'للمالك ولأصحاب اشتراك المزامنة. الإرسال من رقم واتساب عادي ليس طريقة رسمية: قد يُقيَّد الرقم. '
          'لا يتغيّر أي دين أو معاملة — البرنامج يقرأ المبلغ فقط.',
          kind: SetBannerKind.warn,
        ),
        const SizedBox(height: 12),
        if (run.running || run.note != null) ...[_runCard(run), const SizedBox(height: 12)],
        SetCard(
          title: 'التشغيل',
          icon: Icons.power_settings_new_rounded,
          child: Column(children: [
            SetSwitch(
              title: 'تفعيل التذكير عبر واتساب',
              subtitle: s.riskAccepted ? 'وافقت على الخطر' : 'يطلب موافقتك على الخطر أول مرة',
              value: s.enabled,
              onChanged: run.running ? null : _enable,
            ),
            SetSwitch(
              title: 'يبدأ وحده في يوم الإرسال',
              subtitle: 'عند فتح البرنامج في يوم الإرسال: عدّ تنازلي 60 ثانية ثم يبدأ (تستطيع إلغاءه)',
              value: s.autoStart,
              onChanged: !s.enabled || run.running ? null : (v) => _save(s.copyWith(autoStart: v)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('يوم الإرسال:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: s.day,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('آخر يوم في الشهر')),
                  for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('يوم $d')),
                ],
                onChanged: run.running ? null : (v) => _save(s.copyWith(day: v ?? 0)),
              ),
              const SizedBox(width: 20),
              const Text('الساعة:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: s.hour,
                items: [
                  const DropdownMenuItem(value: -1, child: Text('عند فتح البرنامج')),
                  for (var h = 0; h < 24; h++)
                    DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00 فما بعد')),
                ],
                onChanged: run.running ? null : (v) => _save(s.copyWith(hour: v ?? -1)),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('اختر ساعة لا تعمل فيها على الحاسبة (بعد الإغلاق مثلاً) — البرنامج يجب أن يبقى مفتوحاً',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ),
            SetSwitch(
              title: 'إرجاع البرنامج إلى المقدمة بعد كل رسالة',
              subtitle: 'واتساب يظهر بضع ثوانٍ لكل رسالة ثم تعود شاشة البرنامج (وفيها زر «إيقاف»)',
              value: s.refocus,
              onChanged: run.running ? null : (v) => _save(s.copyWith(refocus: v)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'طريقة الإرسال',
          icon: Icons.alt_route_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'desktop', label: Text('WhatsApp Desktop'), icon: Icon(Icons.desktop_windows_rounded)),
                ButtonSegment(value: 'server', label: Text('الخادم'), icon: Icon(Icons.dns_rounded)),
              ],
              selected: {s.via},
              onSelectionChanged: run.running ? null : (v) => _save(s.copyWith(via: v.first)),
            ),
            const SizedBox(height: 8),
            Text(
              s.viaServer
                  ? 'يرسل الخادم في الخلفية من رقم المحل المرتبط به — تستطيع استعمال الحاسبة أثناء الإرسال، ويعمل من أي جهاز.'
                  : (WaDesktop.supported
                      ? 'البرنامج يفتح WhatsApp Desktop ويضغط «إرسال» بنفسه — لا تستعمل الحاسبة أثناء الإرسال.'
                      : 'WhatsApp Desktop يعمل على ويندوز فقط — اختر «الخادم» على هذا الجهاز.'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            if (s.viaServer) ...[
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const WaServerScreen()));
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('إعدادات الخادم والربط'),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'من يُذكَّر',
          icon: Icons.groups_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('عملاء أختارهم'), icon: Icon(Icons.checklist_rounded)),
                ButtonSegment(value: false, label: Text('كل مدين فوق حد'), icon: Icon(Icons.groups_rounded)),
              ],
              selected: {s.onlySelected},
              onSelectionChanged: run.running ? null : (v) => _save(s.copyWith(onlySelected: v.first)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('شرط التأخر:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _overdueChoices.contains(s.overdueMonths) ? s.overdueMonths : 0,
                  items: [
                    for (final m in _overdueChoices) DropdownMenuItem(value: m, child: Text(_overdueLabel(m))),
                  ],
                  onChanged: run.running ? null : (v) => _save(s.copyWith(overdueMonths: v ?? 0)),
                ),
              ),
            ]),
            const Text(
              'التأخر = أشهر كاملة منذ آخر تسديد على الدين القائم (أو منذ بدايته إن لم يسدّد بعدها). '
              'الوصل والخصم والمرتجع على الحساب تُحسب تسديداً.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            if (s.onlySelected) ...[
              OutlinedButton.icon(
                onPressed: run.running ? null : _pick,
                icon: const Icon(Icons.person_search_rounded),
                label: Text('اختيار العملاء (${s.selected.length} مختار)'),
              ),
              const SizedBox(height: 6),
              const Text('تصل الرسالة للمختار فقط إن كان عليه دين أكبر من صفر لحظة الإرسال.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              _stat('سيصلهم التذكير (مختارون عليهم دين)', _targets.length, const Color(0xFF047857)),
              _stat('أُرسل لهم هذا الشهر', _sentCount, const Color(0xFF0F3460)),
            ] else ...[
              _field(_min, 'الحد الأدنى للدين (دينار)', number: true),
              const SizedBox(height: 10),
              if (_debtors == null)
                const LinearProgressIndicator()
              else ...[
                _stat('مدينون برقم صالح', _debtors!.targets.length, const Color(0xFF047857)),
                _stat('أُرسل لهم هذا الشهر', _sentCount, const Color(0xFF0F3460)),
                _stat('مدينون بلا رقم هاتف (لن تصلهم)', _debtors!.noPhone, const Color(0xFFB45309)),
                if (_debtors!.badPhone > 0)
                  _stat('رقم غير صالح (لن تصلهم)', _debtors!.badPhone, const Color(0xFFB91C1C)),
              ],
            ],
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'نص الرسالة',
          icon: Icons.edit_note_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('المتغيرات: {الاسم} {المبلغ} {المحل} {التاريخ} — التحية في أولها تتنوع بين الزبائن تلقائياً',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            _field(_tpl, 'النص', lines: 5),
            const SizedBox(height: 10),
            Text(_targets.isEmpty ? 'معاينة (مثال):' : 'معاينة (أول زبون):',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
              child: Text(
                WaAutoReminder.render(
                    _tpl.text.trim().isEmpty ? WaAutoSettings.defaultTemplate : _tpl.text,
                    _targets.isEmpty ? WaTarget(id: 0, name: 'أحمد', phone: '', debt: 125000) : _targets.first,
                    _shop),
                style: const TextStyle(height: 1.6),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'الأمان والسرعة',
          icon: Icons.shield_outlined,
          child: Column(children: [
            Row(children: [
              Expanded(child: _field(_minDelay, 'أقل فاصل (ثانية)', number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(_maxDelay, 'أكثر فاصل (ثانية)', number: true)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_perDay, 'حد الرسائل في اليوم', number: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(_loadWait, 'مهلة تحميل المحادثة (ثانية)', number: true)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        // 🧪 رسالة تجربة لرقمك الثاني أو قريب — بلا عميل ولا سجل
        SetCard(
          title: 'رسالة تجربة',
          icon: Icons.science_outlined,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('تُرسل الرسالة بالنص أعلاه باسم «تجربة» ومبلغ 125,000 إلى الرقم الذي تكتبه — لا تُسجَّل ولا تخص أي عميل.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _testPhone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'رقم التجربة (مثل 07701234567)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: !s.enabled || run.running || _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: const Text('أرسل تجربة'),
              ),
            ]),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(_testResult!,
                  style: TextStyle(
                      color: _testResult!.startsWith('ضُغط') ? const Color(0xFF047857) : const Color(0xFFB91C1C))),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        if (_dirty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SetPrimaryButton(label: 'حفظ التعديلات', icon: Icons.save_rounded, onPressed: () => _save()),
          ),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: !s.enabled || run.running ? null : () => _start(limit: 5),
            icon: const Icon(Icons.science_outlined),
            label: const Text('تجربة على 5 زبائن'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
            onPressed: !s.enabled || run.running ? null : () => _start(),
            icon: const Icon(Icons.send_rounded),
            label: const Text('أرسل الآن لمن لم يُذكَّر'),
          ),
          OutlinedButton.icon(
            onPressed: !s.enabled || run.running ? null : _sendLate,
            icon: const Icon(Icons.schedule_send_rounded),
            label: const Text('أرسل للمتأخرين…'),
          ),
        ]),
        const SizedBox(height: 16),
        if (_log.isNotEmpty) _logCard(),
      ],
    );
  }

  Widget _runCard(WaRunState r) {
    final left = r.nextAt?.difference(DateTime.now()).inSeconds;
    return SetCard(
      title: r.running ? 'الإرسال جارٍ' : 'آخر تشغيل',
      icon: r.running ? Icons.sync_rounded : Icons.flag_rounded,
      color: r.running ? const Color(0xFF047857) : const Color(0xFF0F3460),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r.running && r.total > 0)
          LinearProgressIndicator(value: (r.sent + r.failed + r.skipped) / r.total, minHeight: 8),
        const SizedBox(height: 8),
        Text('أُرسل ${r.sent} • فشل ${r.failed} • تُخطّي ${r.skipped} • من ${r.total}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        if (r.current != null) Text('الآن: ${r.current}'),
        if (left != null && left > 0) Text('الرسالة التالية بعد $left ثانية'),
        if (r.note != null) Text(r.note!, style: const TextStyle(color: Color(0xFF64748B))),
        if (r.running) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () {
              WaAutoReminder.stop();
              setState(() {});
            },
            icon: const Icon(Icons.stop_circle_rounded),
            label: const Text('إيقاف'),
          ),
        ],
      ]),
    );
  }

  Widget _logCard() {
    final names = {for (final t in _debtors?.targets ?? const <WaTarget>[]) '${t.id}': t.name};
    final entries = _log.entries.toList()..sort((a, b) => '${b.value['t']}'.compareTo('${a.value['t']}'));
    return SetCard(
      title: 'سجل هذا الشهر (${entries.length})',
      icon: Icons.history_rounded,
      child: Column(children: [
        for (final e in entries.take(60))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              e.value['s'] == 'sent' ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: e.value['s'] == 'sent' ? const Color(0xFF047857) : const Color(0xFFB91C1C),
            ),
            title: Text(names[e.key] ?? 'عميل #${e.key}'),
            subtitle: Text([
              '${_n.format(e.value['a'] ?? 0)} دينار',
              '${e.value['t']}'.replaceFirst('T', ' ').split('.').first,
              if (e.value['e'] != null) '${e.value['e']}',
            ].join(' • ')),
          ),
      ]),
    );
  }

  Widget _stat(String label, int v, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('$v', style: TextStyle(fontWeight: FontWeight.w900, color: c, fontSize: 15)),
        ]),
      );

  Widget _field(TextEditingController c, String label, {bool number = false, int lines = 1}) => TextField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? TextInputType.number : TextInputType.multiline,
        onChanged: (_) => setState(() => _dirty = true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      );
}

/// 🕒 مُجدول التذكير: يفحص كل دقيقة ما دام البرنامج مفتوحاً — في يوم الإرسال وبعد الساعة
/// المختارة يظهر عدّ تنازلي 60 ثانية ثم يبدأ (أو «ليس اليوم»). للمالك ومدير البرنامج على
/// الشاشة الأولى فقط، وإن فُعّل «يبدأ وحده».
class WaAutoScheduler {
  WaAutoScheduler._();
  static Timer? _timer;
  static bool _busy = false;
  static BuildContext? _context; // آخر شاشة رئيسية (بعد تبديل المستخدم تُستبدل)

  static void start(BuildContext context, {required bool primarySeat}) {
    if (!primarySeat) return;
    _context = context;
    // 🛰️ الخادم: إيقاظه عند فتح البرنامج يبقي الربط نشطاً ويعيد الجلسة إن مُسحت
    if (_timer == null && WaAutoReminder.allowed) {
      unawaited(() async {
        try {
          if ((await WaAutoReminder.load()).viaServer) await WaServerClient.ensureReady();
        } catch (_) {}
      }());
    }
    unawaited(_tick());
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  static Future<void> _tick() async {
    final context = _context;
    if (_busy || context == null || !context.mounted) return;
    _busy = true;
    try {
      await _check(context);
    } catch (e) {
      debugPrint('💬 تذكير واتساب: $e');
    } finally {
      _busy = false;
    }
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _check(BuildContext context) async {
    if (!WaAutoReminder.allowed || WaAutoReminder.running) return;
    final s = await WaAutoReminder.load();
    if (!s.enabled || !s.riskAccepted || !s.autoStart) return;
    if (!WaAutoReminder.isDueNow(s, DateTime.now()) || await WaAutoReminder.snoozedToday()) return;
    if (await WaAutoReminder.sentToday() >= s.maxPerDay) return;
    final pending = await WaAutoReminder.pending(s);
    if (pending.isEmpty || !context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CountdownDialog(count: pending.length),
    );
    if (!context.mounted) return;
    if (go != true) {
      await WaAutoReminder.snoozeToday();
      return;
    }
    unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => const WaAutoScreen())));
    await WaAutoReminder.run();
  }
}

class _CountdownDialog extends StatefulWidget {
  const _CountdownDialog({required this.count});
  final int count;
  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  int _left = 60;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _t?.cancel();
        Navigator.pop(context, true);
        return;
      }
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.chat_rounded, color: Color(0xFF047857), size: 34),
        title: const Text('تذكير الديون الشهري عبر واتساب'),
        content: Text(
          'سيبدأ الإرسال لـ ${widget.count} زبوناً بعد $_left ثانية.\n\n'
          'تأكد أن WhatsApp Desktop مفتوح، ولا تستعمل الحاسبة أثناء الإرسال.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ليس اليوم')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ابدأ الآن')),
        ],
      );
}

/// اختيار العملاء الذين تصلهم الرسالة (من لهم رقم صالح).
class _PickDialog extends StatefulWidget {
  const _PickDialog({required this.all, required this.initial});
  final List<WaTarget> all;
  final Set<int> initial;
  @override
  State<_PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<_PickDialog> {
  late final Set<int> _sel = {...widget.initial};
  String _q = '';
  static final _n = NumberFormat('#,##0', 'en');

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final list = q.isEmpty ? widget.all : widget.all.where((t) => t.name.contains(q) || t.phone.contains(q)).toList();
    return AlertDialog(
      title: Text('من تصله الرسالة؟ (${_sel.length} مختار)'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الرقم', border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.all.isEmpty
                ? const Center(child: Text('لا يوجد عميل له رقم هاتف صالح'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final t = list[i];
                      return CheckboxListTile(
                        dense: true,
                        value: _sel.contains(t.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _sel.add(t.id);
                          } else {
                            _sel.remove(t.id);
                          }
                        }),
                        title: Text(t.name),
                        subtitle: Text('${t.phone} • ${t.debt > 0 ? '${_n.format(t.debt.round())} دينار' : 'لا دين — لن تصله'}'
                            '${t.lateMonths != null && t.lateMonths! > 0 ? ' • بلا تسديد منذ ${t.lateMonths} شهر' : ''}'),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => setState(_sel.clear), child: const Text('إلغاء الكل')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        FilledButton(onPressed: () => Navigator.pop(context, _sel), child: const Text('حفظ الاختيار')),
      ],
    );
  }
}
