// lib/wa_messages/wa_send_screen.dart
//
// ✉️ «إرسال الآن»: تختار عملاء (بحث، المتأخرون، الكل) والرسالة، فيبدأ الإرسال في الخلفية.
// و«سجل الرسائل»: كل ما أُرسل وما فشل ولماذا.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../owner/wa_auto/wa_auto_reminder.dart';
import '../widgets/settings_kit.dart';
import 'wa_message_log.dart';
import 'wa_outbox.dart';
import 'wa_rules.dart';
import 'wa_widgets.dart';

class WaSendNowScreen extends StatefulWidget {
  const WaSendNowScreen({super.key});
  @override
  State<WaSendNowScreen> createState() => _WaSendNowScreenState();
}

class _WaSendNowScreenState extends State<WaSendNowScreen> {
  Set<int> _ids = {};
  List<WaTarget> _all = const [];
  WaMessageOptions _o = const WaMessageOptions();
  WaAutoSettings? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await WaAutoReminder.load();
    final all = await WaAutoReminder.withPhones();
    if (mounted) {
      setState(() {
        _s = s;
        _all = all;
      });
    }
  }

  Future<void> _pick() async {
    final s = await showWaCustomerPicker(context, initial: _ids, title: 'من تصله الآن', debtorsOnly: true);
    if (s != null) setState(() => _ids = s);
  }

  void _send() {
    final s = _s!;
    if (!s.enabled || !s.riskAccepted) {
      _toast('فعّل الإرسال الآلي أولاً من «طريقة الإرسال والأمان»');
      return;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final n = WaOutbox.enqueue([
      for (final t in _all)
        if (_ids.contains(t.id))
          WaJob(
            customerId: t.id,
            name: t.name,
            phone: t.phone,
            source: 'manual',
            ruleId: 'manual-$stamp',
            ruleName: 'إرسال يدوي',
            options: _o,
          ),
    ]);
    _toast(n == 0 ? 'لا جديد للإرسال' : 'بدأ الإرسال لـ $n — يتابع في الخلفية، ويمكنك إغلاق الشاشة');
    setState(() => _ids = {});
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SettingsScaffold(title: 'إرسال الآن', icon: Icons.send_rounded, loading: true);
    final chosen = [for (final t in _all) if (_ids.contains(t.id)) t];
    final total = chosen.fold<double>(0, (a, t) => a + t.debt);
    return SettingsScaffold(
      title: 'إرسال الآن',
      icon: Icons.send_rounded,
      subtitle: 'تختار من تصله المطالبة ومتى: الآن',
      children: [
        const WaOutboxCard(),
        SetCard(
          title: '1. لمن؟',
          icon: Icons.groups_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: _pick,
                icon: const Icon(Icons.person_search_rounded),
                label: Text('اختيار العملاء (${_ids.length})'),
              ),
              if (_ids.isNotEmpty)
                TextButton(onPressed: () => setState(() => _ids = {}), child: const Text('إلغاء الاختيار')),
            ]),
            const SizedBox(height: 8),
            if (chosen.isNotEmpty)
              Text('${chosen.length} عميل • ${NumberFormat('#,##0', 'en').format(total.round())} دينار',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            const Text('تصل المطالبة لمن عليه دين لحظة الإرسال فقط.', style: TextStyle(fontSize: 12, color: kWaMuted)),
          ]),
        ),
        const SizedBox(height: 12),
        SetCard(
          title: '2. الرسالة',
          icon: Icons.edit_note_rounded,
          child: WaOptionsEditor(value: _o, viaServer: s.viaServer, onChanged: (o) => setState(() => _o = o)),
        ),
        const SizedBox(height: 12),
        SetPrimaryButton(
          label: _ids.isEmpty ? 'اختر عملاء أولاً' : 'أرسل الآن (${_ids.length})',
          icon: Icons.send_rounded,
          color: kWaGreen,
          onPressed: _ids.isEmpty ? null : _send,
        ),
        const SizedBox(height: 8),
        Text(
          s.viaServer
              ? 'يرسل الخادم في الخلفية بفاصل ${s.minDelay}–${s.maxDelay} ثانية بين الرسائل.'
              : 'البرنامج يفتح WhatsApp Desktop ويضغط «إرسال» — لا تستعمل الحاسبة حتى ينتهي.',
          style: const TextStyle(fontSize: 12, color: kWaMuted),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ═════════════════════ سجل الرسائل ═════════════════════

class WaLogScreen extends StatefulWidget {
  const WaLogScreen({super.key, this.customerId});
  final int? customerId;
  @override
  State<WaLogScreen> createState() => _WaLogScreenState();
}

class _WaLogScreenState extends State<WaLogScreen> {
  List<WaLogEntry>? _list;
  String _filter = 'all';
  static final _n = NumberFormat('#,##0', 'en');
  static final _d = DateFormat('yyyy/MM/dd HH:mm', 'en');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await WaMessageLog.recent(limit: 500, customerId: widget.customerId);
    if (mounted) setState(() => _list = l);
  }

  static String _source(WaLogEntry e) => switch (e.source) {
        'rule' => 'قاعدة: ${e.ruleName}',
        'manual' => 'إرسال يدوي',
        'reminder' => 'مواعيد المطالبة',
        'card' => 'من حساب العميل',
        'loyalty' => 'برنامج الولاء',
        'invoice' => 'فاتورة (PDF)',
        'statement' => 'كشف حساب (PDF)',
        'voucher' => 'وصل / سند (PDF)',
        'doc' => 'مستند (PDF)',
        'auto_doc' => 'إرسال تلقائي عند الحفظ',
        'legacy' => 'التذكير الشهري (قديم)',
        _ => e.source,
      };

  @override
  Widget build(BuildContext context) {
    final all = _list;
    final l = all == null
        ? null
        : [for (final e in all) if (_filter == 'all' || e.status == _filter) e];
    return SettingsScaffold(
      title: 'سجل الرسائل',
      icon: Icons.history_rounded,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      children: [
        Wrap(spacing: 8, children: [
          for (final f in const [('all', 'الكل'), ('sent', 'أُرسلت'), ('failed', 'فشلت'), ('skipped', 'تُخطّيت')])
            ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
        ]),
        const SizedBox(height: 10),
        if (l == null)
          const LinearProgressIndicator()
        else if (l.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا شيء بعد')))
        else
          for (final e in l)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                e.sent ? Icons.check_circle_rounded : (e.status == 'skipped' ? Icons.remove_circle_outline : Icons.error_outline_rounded),
                color: e.sent ? kWaGreen : (e.status == 'skipped' ? kWaMuted : const Color(0xFFB91C1C)),
              ),
              title: Text(e.name.isEmpty ? 'عميل #${e.customerId ?? '-'}' : e.name),
              subtitle: Text([
                _d.format(e.at),
                _source(e),
                '${_n.format(e.amount.round())} دينار',
                if (e.attach.isNotEmpty) e.attach,
                if (e.error != null) e.error!,
              ].join(' • ')),
            ),
        const SizedBox(height: 40),
      ],
    );
  }
}
