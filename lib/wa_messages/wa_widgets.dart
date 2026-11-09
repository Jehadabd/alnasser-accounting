// lib/wa_messages/wa_widgets.dart
//
// 🧩 أجزاء مشتركة لشاشات رسائل واتساب: اختيار العملاء، خيارات الرسالة، بطاقة الإرسال
// الجاري، ونافذة «أرسل الآن» لعميل أو أكثر (من حساب العميل أو مواعيد المطالبة).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../widgets/settings_kit.dart';
import 'wa_outbox.dart';
import 'wa_rules.dart';

const kWaGreen = Color(0xFF047857);
const kWaMuted = Color(0xFF64748B);
final _n = NumberFormat('#,##0', 'en');

// ═════════════════════ اختيار العملاء ═════════════════════

/// يعيد المختارين، أو null عند الإلغاء.
Future<Set<int>?> showWaCustomerPicker(BuildContext context,
    {required Set<int> initial, String title = 'اختيار العملاء', bool debtorsOnly = false}) async {
  final all = await WaAutoReminder.withPhones();
  if (!context.mounted) return null;
  return showDialog<Set<int>>(
    context: context,
    builder: (_) => _PickDialog(
      all: debtorsOnly ? [for (final t in all) if (t.debt > 0) t] : all,
      initial: initial,
      title: title,
    ),
  );
}

class _PickDialog extends StatefulWidget {
  const _PickDialog({required this.all, required this.initial, required this.title});
  final List<WaTarget> all;
  final Set<int> initial;
  final String title;
  @override
  State<_PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<_PickDialog> {
  late final Set<int> _sel = {...widget.initial};
  String _q = '';
  int _late = 0; // 0 = الكل، وإلا: متأخر N شهراً فأكثر

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final list = [
      for (final t in widget.all)
        if ((q.isEmpty || t.name.contains(q) || t.phone.contains(q)) && (_late == 0 || (t.lateMonths ?? -1) >= _late)) t
    ];
    return AlertDialog(
      title: Text('${widget.title} (${_sel.length} مختار)'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الرقم', border: OutlineInputBorder(), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in const [0, 1, 2, 3, 6])
              ChoiceChip(
                label: Text(m == 0 ? 'الكل' : 'بلا تسديد $m ${m == 1 ? 'شهر' : (m == 2 ? 'شهرين' : 'أشهر')}+'),
                selected: _late == m,
                onSelected: (_) => setState(() => _late = m),
              ),
            ActionChip(
              avatar: const Icon(Icons.done_all_rounded, size: 18),
              label: Text('تحديد الظاهرين (${list.length})'),
              onPressed: () => setState(() => _sel.addAll(list.map((t) => t.id))),
            ),
          ]),
          const SizedBox(height: 6),
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
                        onChanged: (v) => setState(() => v == true ? _sel.add(t.id) : _sel.remove(t.id)),
                        title: Text(t.name),
                        subtitle: Text('${t.phone} • ${t.debt > 0 ? '${_n.format(t.debt.round())} دينار' : 'لا دين'}'
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

// ═════════════════════ خيارات الرسالة ═════════════════════

/// نص الرسالة (فارغ = الافتراضي) + العنوان + الكشف. [onChanged] مع كل تغيير.
class WaOptionsEditor extends StatefulWidget {
  const WaOptionsEditor({super.key, required this.value, required this.onChanged, this.viaServer = true});
  final WaMessageOptions value;
  final ValueChanged<WaMessageOptions> onChanged;
  final bool viaServer;
  @override
  State<WaOptionsEditor> createState() => _WaOptionsEditorState();
}

class _WaOptionsEditorState extends State<WaOptionsEditor> {
  late final _tpl = TextEditingController(text: widget.value.template);
  late bool _own = widget.value.template.trim().isNotEmpty;

  @override
  void dispose() {
    _tpl.dispose();
    super.dispose();
  }

  void _emit(WaMessageOptions o) => widget.onChanged(o);

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SetSwitch(
        title: 'نص خاص بهذه الرسالة',
        subtitle: _own ? 'المتغيرات: {الاسم} {المبلغ} {المحل} {العنوان} {التاريخ}' : 'يستعمل النص الافتراضي',
        value: _own,
        onChanged: (on) {
          setState(() => _own = on);
          _emit(v.copyWith(template: on ? (_tpl.text.trim().isEmpty ? WaAutoSettings.defaultTemplate : _tpl.text) : ''));
          if (on && _tpl.text.trim().isEmpty) _tpl.text = WaAutoSettings.defaultTemplate;
        },
      ),
      if (_own) ...[
        TextField(
          controller: _tpl,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'النص', border: OutlineInputBorder(), isDense: true),
          onChanged: (t) => _emit(v.copyWith(template: t)),
        ),
        const SizedBox(height: 8),
      ],
      SetSwitch(
        title: 'إضافة عنوان المحل',
        subtitle: 'من «الرسالة وعنوان المحل»',
        value: v.address,
        onChanged: (on) => _emit(v.copyWith(address: on)),
      ),
      const SizedBox(height: 6),
      const Text('كشف حساب ملخّص منذ آخر مرة كان رصيده صفراً:', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      SegmentedButton<WaAttach>(
        segments: const [
          ButtonSegment(value: WaAttach.none, label: Text('بلا كشف')),
          ButtonSegment(value: WaAttach.text, label: Text('نص في الرسالة'), icon: Icon(Icons.notes_rounded)),
          ButtonSegment(value: WaAttach.pdf, label: Text('ملف PDF'), icon: Icon(Icons.picture_as_pdf_rounded)),
        ],
        selected: {v.attach},
        onSelectionChanged: (s) => _emit(v.copyWith(attach: s.first)),
      ),
      if (v.attach == WaAttach.pdf && !widget.viaServer)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('WhatsApp Desktop لا يرسل ملفات: سيصل الكشف نصاً. للملف استعمل «الخادم».',
              style: TextStyle(fontSize: 12, color: Color(0xFFB45309))),
        ),
    ]);
  }
}

// ═════════════════════ الإرسال الجاري ═════════════════════

class WaOutboxCard extends StatefulWidget {
  const WaOutboxCard({super.key});
  @override
  State<WaOutboxCard> createState() => _WaOutboxCardState();
}

class _WaOutboxCardState extends State<WaOutboxCard> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    WaOutbox.state.addListener(_on);
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && WaOutbox.running) setState(() {});
    });
  }

  @override
  void dispose() {
    WaOutbox.state.removeListener(_on);
    _t?.cancel();
    super.dispose();
  }

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final r = WaOutbox.state.value;
    if (!r.running && r.note == null) return const SizedBox.shrink();
    final left = r.nextAt?.difference(DateTime.now()).inSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SetCard(
        title: r.running ? 'الإرسال جارٍ' : 'آخر إرسال',
        icon: r.running ? Icons.sync_rounded : Icons.flag_rounded,
        color: r.running ? kWaGreen : kSetNavy,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.running && r.total > 0) LinearProgressIndicator(value: r.done / r.total, minHeight: 8),
          const SizedBox(height: 8),
          Text('أُرسل ${r.sent} • فشل ${r.failed} • تُخطّي ${r.skipped} • من ${r.total}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (r.current != null) Text('الآن: ${r.current}'),
          if (left != null && left > 0) Text('الرسالة التالية بعد $left ثانية'),
          if (r.note != null) Text(r.note!, style: const TextStyle(color: kWaMuted)),
          if (r.running) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
                onPressed: () {
                  WaOutbox.stop();
                  setState(() {});
                },
                icon: const Icon(Icons.stop_circle_rounded),
                label: const Text('إيقاف'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ═════════════════════ «أرسل الآن» لعميل أو أكثر ═════════════════════

class WaRecipient {
  const WaRecipient(this.customerId, this.name, this.phone);
  final int customerId;
  final String name;
  final String? phone;
}

/// نافذة خيارات ثم إرسال تلقائي. [source]: 'card' أو 'reminder' أو 'manual'. يعيد عدد المضاف.
Future<int> showWaSendDialog(BuildContext context, List<WaRecipient> people, {String source = 'manual'}) async {
  if (!WaAutoReminder.allowed) {
    _toast(context, 'الإرسال الآلي لمدير البرنامج فقط');
    return 0;
  }
  final s = await WaAutoReminder.load();
  if (!context.mounted) return 0;
  if (!s.enabled || !s.riskAccepted) {
    _toast(context, 'فعّل الإرسال الآلي أولاً: الإعدادات ← رسائل واتساب للزبائن ← طريقة الإرسال والأمان');
    return 0;
  }
  final ok = [
    for (final p in people)
      if (WaAutoReminder.normalizePhone(p.phone) != null) p,
  ];
  if (ok.isEmpty) {
    _toast(context, 'لا يوجد رقم واتساب صالح');
    return 0;
  }
  var o = const WaMessageOptions();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        icon: const Icon(Icons.chat_rounded, color: kWaGreen, size: 32),
        title: Text(ok.length == 1 ? 'مطالبة واتساب: ${ok.first.name}' : 'مطالبة واتساب لـ ${ok.length} عميل'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (ok.length < people.length)
                Text('${people.length - ok.length} بلا رقم صالح — لن تصلهم.',
                    style: const TextStyle(color: Color(0xFFB45309))),
              WaOptionsEditor(value: o, viaServer: s.viaServer, onChanged: (v) => set(() => o = v)),
              const SizedBox(height: 8),
              Text(s.viaServer ? 'يرسل الخادم في الخلفية.' : 'البرنامج يفتح WhatsApp Desktop ويضغط «إرسال» — لا تستعمل الحاسبة حتى ينتهي.',
                  style: const TextStyle(fontSize: 12, color: kWaMuted)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kWaGreen),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('أرسل الآن'),
          ),
        ],
      ),
    ),
  );
  if (go != true) return 0;
  final n = WaOutbox.enqueue([
    for (final p in ok)
      WaJob(
        customerId: p.customerId,
        name: p.name,
        phone: WaAutoReminder.normalizePhone(p.phone)!,
        source: source,
        ruleId: '$source-${DateTime.now().millisecondsSinceEpoch}',
        options: o,
      ),
  ]);
  if (context.mounted) _toast(context, n == 0 ? 'في قائمة الإرسال بالفعل' : 'أُضيف $n إلى الإرسال — يتابع في الخلفية');
  return n;
}

void _toast(BuildContext context, String m) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));
