// lib/wa_messages/wa_rules_screen.dart
//
// 📏 «القواعد التلقائية»: قائمة القواعد، وتعديل قاعدة، ومعاينة «من تصله الآن».

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../widgets/settings_kit.dart';
import 'wa_outbox.dart';
import 'wa_rules.dart';
import 'wa_scheduler.dart';
import 'wa_widgets.dart';

class WaRulesScreen extends StatefulWidget {
  const WaRulesScreen({super.key});
  @override
  State<WaRulesScreen> createState() => _WaRulesScreenState();
}

class _WaRulesScreenState extends State<WaRulesScreen> {
  List<WaRule>? _rules;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await WaRules.load();
    if (mounted) setState(() => _rules = r);
  }

  Future<void> _edit([WaRule? r]) async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => WaRuleEditorScreen(rule: r?.copy())));
    if (saved == true) await _load();
  }

  Future<void> _toggle(WaRule r, bool on) async {
    r.enabled = on;
    await WaRules.upsert(r);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    return SettingsScaffold(
      title: 'القواعد التلقائية',
      icon: Icons.rule_rounded,
      subtitle: 'لمن، ومتى، وبأي رسالة — ترسل وحدها ما دام البرنامج مفتوحاً',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('قاعدة جديدة'),
      ),
      children: [
        const SetBanner(
          'مثال: «من لم يسدّد منذ 3 أشهر ⇐ رسالة مطالبة مع كشف PDF، مرة واحدة حتى يسدّد». '
          'القاعدة تفحص كل 5 دقائق؛ من سدّد بعد رسالتها تعود له بعد المدة نفسها من تسديده.',
        ),
        const SizedBox(height: 12),
        if (rules == null)
          const LinearProgressIndicator()
        else if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('لا قواعد بعد — اضغط «قاعدة جديدة»', style: TextStyle(color: kWaMuted))),
          )
        else
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetCard(
                title: r.name,
                icon: r.auto ? Icons.bolt_rounded : Icons.how_to_reg_rounded,
                color: r.enabled ? kWaGreen : kWaMuted,
                trailing: Switch(value: r.enabled, onChanged: (v) => _toggle(r, v)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(r.summary, style: const TextStyle(fontSize: 12.5, height: 1.6, color: kWaMuted)),
                  Text(
                      'الرسالة: ${r.options.template.trim().isEmpty ? 'النص الافتراضي' : 'نص خاص'}'
                      '${r.options.address ? ' + العنوان' : ''}'
                      '${switch (r.options.attach) { WaAttach.none => '', WaAttach.text => ' + كشف نصي', WaAttach.pdf => ' + كشف PDF' }}',
                      style: const TextStyle(fontSize: 12.5, color: kWaMuted)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    TextButton.icon(onPressed: () => _edit(r), icon: const Icon(Icons.edit_rounded), label: const Text('تعديل')),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => WaRulePreviewScreen(rule: r))),
                      icon: const Icon(Icons.groups_rounded),
                      label: const Text('من تصله الآن؟'),
                    ),
                  ]),
                ]),
              ),
            ),
        const SizedBox(height: 80),
      ],
    );
  }
}

// ═════════════════════ تعديل قاعدة ═════════════════════

class WaRuleEditorScreen extends StatefulWidget {
  const WaRuleEditorScreen({super.key, this.rule});
  final WaRule? rule;
  @override
  State<WaRuleEditorScreen> createState() => _WaRuleEditorScreenState();
}

class _WaRuleEditorScreenState extends State<WaRuleEditorScreen> {
  late final WaRule _r = widget.rule ?? WaRule(id: WaRule.newId(), name: 'مطالبة المتأخرين');
  late final _name = TextEditingController(text: _r.name);
  late final _late = TextEditingController(text: '${_r.lateValue}');
  late final _min = TextEditingController(text: NumberFormat('#,##0', 'en').format(_r.minDebt.round()));
  late final _every = TextEditingController(text: '${_r.repeatDays}');
  bool _viaServer = true;

  bool get _isNew => widget.rule == null;

  @override
  void initState() {
    super.initState();
    WaAutoReminder.load().then((s) {
      if (mounted) setState(() => _viaServer = s.viaServer);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _late, _min, _every]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, int def) => int.tryParse(c.text.replaceAll(',', '').trim()) ?? def;

  Future<void> _save() async {
    _r
      ..name = _name.text.trim().isEmpty ? 'قاعدة' : _name.text.trim()
      ..lateValue = _int(_late, 0).clamp(0, 3650)
      ..minDebt = (double.tryParse(_min.text.replaceAll(',', '').trim()) ?? 1).clamp(1, 1e12).toDouble()
      ..repeatDays = _int(_every, 30).clamp(1, 365);
    if ((_r.audience == WaAudience.selected) && _r.ids.isEmpty) {
      _toast('اختر العملاء أولاً');
      return;
    }
    await WaRules.upsert(_r);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القاعدة'),
        content: Text('حذف «${_r.name}»؟ سجل ما أُرسل بها يبقى.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await WaRules.remove(_r.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pick() async {
    final s = await showWaCustomerPicker(context,
        initial: _r.ids, title: _r.audience == WaAudience.except ? 'من لا تصله' : 'من تصله');
    if (s != null) setState(() => _r.ids = s);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: _isNew ? 'قاعدة جديدة' : 'تعديل قاعدة',
      icon: Icons.rule_rounded,
      actions: [
        if (!_isNew) IconButton(tooltip: 'حذف', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
      ],
      bottom: Padding(
        padding: const EdgeInsets.all(12),
        child: SetPrimaryButton(label: 'حفظ القاعدة', icon: Icons.save_rounded, onPressed: _save),
      ),
      children: [
        SetCard(
          title: 'الاسم والتشغيل',
          icon: Icons.label_rounded,
          child: Column(children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم القاعدة', border: OutlineInputBorder(), isDense: true),
            ),
            SetSwitch(title: 'مفعّلة', value: _r.enabled, onChanged: (v) => setState(() => _r.enabled = v)),
            SetSwitch(
              title: 'إرسال تلقائي بلا تدخل',
              subtitle: _r.auto
                  ? 'حين يحين الموعد ترسل وحدها — مثل التنبيهات'
                  : 'حين يحين الموعد تظهر القائمة وتنتظر موافقتك (مرة في اليوم)',
              value: _r.auto,
              onChanged: (v) => setState(() => _r.auto = v),
            ),
            if (_r.auto && !_viaServer)
              const Text(
                'تنبيه: الطريقة الحالية WhatsApp Desktop — يفتح واتساب ويضغط «إرسال» وأنت تعمل. للتلقائي الكامل اختر «الخادم».',
                style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'لمن؟',
          icon: Icons.groups_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in WaAudience.values)
                ChoiceChip(
                  label: Text(switch (a) {
                    WaAudience.all => 'كل المدينين',
                    WaAudience.selected => 'عملاء أختارهم',
                    WaAudience.except => 'الكل عدا عملاء',
                    WaAudience.dueReminders => 'مواعيد المطالبة اليوم',
                  }),
                  selected: _r.audience == a,
                  onSelected: (_) => setState(() => _r.audience = a),
                ),
            ]),
            const SizedBox(height: 8),
            if (_r.audience == WaAudience.selected || _r.audience == WaAudience.except)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.person_search_rounded),
                  label: Text('${_r.audience == WaAudience.except ? 'المستثنون' : 'المختارون'} (${_r.ids.length})'),
                ),
              ),
            if (_r.audience == WaAudience.dueReminders)
              const Text('من حلّ موعده اليوم في «مواعيد المطالبة بالسداد» (سجل الديون ← التحصيل والتقارير).',
                  style: TextStyle(fontSize: 12, color: kWaMuted)),
            const SizedBox(height: 10),
            TextField(
              controller: _min,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'أقل دين تصل معه الرسالة (دينار)', border: OutlineInputBorder(), isDense: true),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'شرط التأخر',
          icon: Icons.hourglass_bottom_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('لم يسدّد منذ'),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _late,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'day', label: Text('يوم')), ButtonSegment(value: 'month', label: Text('شهر'))],
                selected: {_r.lateUnit},
                onSelectionChanged: (s) => setState(() => _r.lateUnit = s.first),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              '0 = كل من عليه دين. التأخر يُحسب من آخر تسديد على الدين القائم، أو من بداية الدين إن لم يسدّد بعدها '
              '(الوصل والخصم والمرتجع على الحساب تسديد). مثال: أخذ ديناً اليوم و«3 أشهر» ⇐ تصله بعد 3 أشهر إن لم يسدّد شيئاً.',
              style: TextStyle(fontSize: 12, height: 1.6, color: kWaMuted),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'متى؟',
          icon: Icons.event_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SetSwitch(
              title: 'أي يوم',
              subtitle: _r.days.isEmpty ? 'ترسل في اليوم الذي يتحقق فيه الشرط' : 'فقط في الأيام المختارة من الشهر',
              value: _r.days.isEmpty,
              onChanged: (v) => setState(() => _r.days = v ? [] : [5]),
            ),
            if (_r.days.isNotEmpty)
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (var d = 1; d <= 31; d++) _dayChip(d, '$d'),
                _dayChip(0, 'آخر الشهر'),
              ]),
            const SizedBox(height: 8),
            Row(children: [
              const Text('الساعة:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _r.hour,
                items: [
                  const DropdownMenuItem(value: -1, child: Text('أي ساعة')),
                  for (var h = 0; h < 24; h++)
                    DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00 فما بعد')),
                ],
                onChanged: (v) => setState(() => _r.hour = v ?? -1),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('التكرار:', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final rp in WaRepeat.values)
                ChoiceChip(
                  label: Text(switch (rp) {
                    WaRepeat.once => 'مرة واحدة حتى يسدّد',
                    WaRepeat.monthly => 'مرة كل شهر',
                    WaRepeat.everyDays => 'كل عدد أيام',
                  }),
                  selected: _r.repeat == rp,
                  onSelected: (_) => setState(() => _r.repeat = rp),
                ),
              if (_r.repeat == WaRepeat.everyDays)
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _every,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'كل (يوم)', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: 'الرسالة',
          icon: Icons.edit_note_rounded,
          child: WaOptionsEditor(
            value: _r.options,
            viaServer: _viaServer,
            onChanged: (o) => setState(() => _r.options = o),
          ),
        ),
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _dayChip(int d, String label) => FilterChip(
        label: Text(label),
        selected: _r.days.contains(d),
        visualDensity: VisualDensity.compact,
        onSelected: (on) => setState(() {
          if (on) {
            _r.days = [..._r.days, d];
          } else if (_r.days.length > 1) {
            _r.days = [..._r.days]..remove(d);
          }
        }),
      );
}

// ═════════════════════ معاينة: من تصله الآن ═════════════════════

class WaRulePreviewScreen extends StatefulWidget {
  const WaRulePreviewScreen({super.key, required this.rule});
  final WaRule rule;
  @override
  State<WaRulePreviewScreen> createState() => _WaRulePreviewScreenState();
}

class _WaRulePreviewScreenState extends State<WaRulePreviewScreen> {
  List<WaFacts>? _list;
  static final _n = NumberFormat('#,##0', 'en');

  @override
  void initState() {
    super.initState();
    WaRulesEngine.targets(widget.rule).then((l) {
      if (mounted) setState(() => _list = l);
    });
  }

  Future<void> _sendNow() async {
    final l = _list ?? const <WaFacts>[];
    final s = await WaAutoReminder.load();
    if (!mounted) return;
    if (!s.enabled || !s.riskAccepted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('فعّل الإرسال الآلي أولاً من «طريقة الإرسال والأمان»')));
      return;
    }
    final n = WaOutbox.enqueue(WaRulesEngine.jobs(widget.rule, l));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('أُضيف $n إلى الإرسال')));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rule;
    final l = _list;
    final dueNow = WaRuleEval.isDueNow(r, DateTime.now());
    return SettingsScaffold(
      title: 'من تصله الآن؟',
      icon: Icons.groups_rounded,
      subtitle: r.name,
      children: [
        SetBanner(
          dueNow
              ? 'موعد القاعدة الآن: ${r.auto ? 'ترسل وحدها خلال دقائق' : 'تظهر لك القائمة للموافقة'}.'
              : 'ليس موعدها الآن (${r.daysText} • ${r.hourText}). هؤلاء تصلهم حين يحين الموعد إن بقي الشرط.',
        ),
        const SizedBox(height: 12),
        const WaOutboxCard(),
        if (l == null)
          const LinearProgressIndicator()
        else ...[
          Text('${l.length} عميل', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 6),
          for (final p in l)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_rounded),
              title: Text(p.name),
              subtitle: Text('${_n.format(p.debt.round())} دينار'
                  '${p.since == null ? '' : ' • بلا تسديد منذ ${DateFormat('yyyy/MM/dd', 'en').format(p.since!)}'}'),
            ),
          if (l.isNotEmpty) ...[
            const SizedBox(height: 10),
            SetPrimaryButton(
              label: 'أرسل لهم الآن (${l.length})',
              icon: Icons.send_rounded,
              color: kWaGreen,
              onPressed: _sendNow,
            ),
          ],
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}
