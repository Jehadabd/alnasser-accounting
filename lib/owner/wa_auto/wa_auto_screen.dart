// lib/owner/wa_auto/wa_auto_screen.dart
//
// 👑💬 شاشة «تذكير الديون الشهري عبر واتساب» — حساب المالك ومدير البرنامج فقط.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../widgets/settings_kit.dart';
import 'wa_auto_reminder.dart';

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
    for (final c in [_min, _tpl, _minDelay, _maxDelay, _perDay, _loadWait]) {
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
    final log = await WaAutoReminder.monthLog();
    if (mounted) {
      setState(() {
        _debtors = d;
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
      await _save(_s!.copyWith(enabled: true, riskAccepted: true));
      return;
    }
    await _save(_s!.copyWith(enabled: on));
  }

  Future<void> _start({int? limit}) async {
    if (_dirty) await _save();
    if (!mounted) return;
    final pending = (_debtors?.targets.length ?? 0) - _sentCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(limit == null ? 'بدء الإرسال' : 'تجربة على $limit زبائن'),
        content: Text(
          '${limit == null ? 'سيُرسل لـ ${pending < 0 ? 0 : pending} زبوناً (ضمن الحد اليومي).' : 'سيُرسل لأول $limit ممن لم يُذكَّروا هذا الشهر.'}\n\n'
          'تأكد أن WhatsApp Desktop مفتوح ومسجّل الدخول.\n'
          'لا تستعمل الحاسبة حتى ينتهي. للإيقاف: ارجع إلى هذه الشاشة واضغط «إيقاف».',
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
      subtitle: 'رسالة شهرية لكل مدين باسمه ومبلغه — من WhatsApp Desktop على هذه الحاسبة',
      children: [
        const SetBanner(
          'ميزة حساب المالك. الإرسال من رقم واتساب عادي ليس طريقة رسمية: قد يُقيَّد الرقم. '
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
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'من يُذكَّر',
          icon: Icons.groups_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            if (_debtors != null && _debtors!.targets.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('معاينة (أول زبون):', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  WaAutoReminder.render(
                      _tpl.text.trim().isEmpty ? WaAutoSettings.defaultTemplate : _tpl.text, _debtors!.targets.first, _shop),
                  style: const TextStyle(height: 1.6),
                ),
              ),
            ],
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
        ]),
        const SizedBox(height: 16),
        if (_log.isNotEmpty) _logCard(),
      ],
    );
  }

  Widget _runCard(WaRunState r) {
    final left = r.nextAt == null ? null : r.nextAt!.difference(DateTime.now()).inSeconds;
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

/// 🕒 عند فتح البرنامج: إن كان اليوم يوم الإرسال وفُعّل «يبدأ وحده» ⇒ عدّ تنازلي 60 ثانية
/// ثم يبدأ الإرسال (أو «ليس اليوم»). للمالك ومدير البرنامج على الشاشة الأولى فقط.
Future<void> offerWaAutoOnStartup(BuildContext context, {required bool primarySeat}) async {
  if (!primarySeat || !WaAutoReminder.allowed || WaAutoReminder.running) return;
  final s = await WaAutoReminder.load();
  if (!s.enabled || !s.riskAccepted || !s.autoStart) return;
  if (!WaAutoReminder.isDueDay(s, DateTime.now()) || await WaAutoReminder.snoozedToday()) return;
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
  unawaited(WaAutoReminder.run());
  unawaited(Navigator.push(context, MaterialPageRoute(builder: (_) => const WaAutoScreen())));
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
