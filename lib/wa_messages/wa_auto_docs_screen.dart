// lib/wa_messages/wa_auto_docs_screen.dart
//
// 🤖 «الإرسال التلقائي للعملاء»: تختار عملاء، ولكل واحد ما يصله تلقائياً عبر الخادم لحظة
// الحفظ (wa_auto_docs.dart). رقم العميل يُؤكَّد هنا مرة واحدة.

import 'package:flutter/material.dart';

import '../erp/pickers.dart';
import '../owner/wa_auto/wa_auto_reminder.dart';
import '../widgets/settings_kit.dart';
import 'wa_auto_docs.dart';
import 'wa_doc_sender.dart';
import 'wa_phone_book.dart';

class WaAutoDocsScreen extends StatefulWidget {
  const WaAutoDocsScreen({super.key});
  @override
  State<WaAutoDocsScreen> createState() => _WaAutoDocsScreenState();
}

class _WaAutoDocsScreenState extends State<WaAutoDocsScreen> {
  List<WaAutoDocSub>? _subs;
  final Map<int, String?> _phones = {};
  String? _block;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subs = await WaAutoDocs.all();
    for (final s in subs) {
      _phones[s.customerId] = await WaPhoneBook.phoneOf(WaPhoneBook.keyOf(s.customerId, s.name));
    }
    final block = await WaDocSender.blockReason();
    if (mounted) {
      setState(() {
        _subs = subs;
        _block = block;
      });
    }
  }

  Future<void> _add() async {
    final p = await Pickers.customer(context, title: 'عميل يصله الإرسال التلقائي');
    if (p == null || !mounted) return;
    final existing = _subs?.where((s) => s.customerId == p.id).firstOrNull;
    await _edit(p.id, p.name, existing?.kinds ?? {WaAutoDocKind.invoice, WaAutoDocKind.receipt}, p.phone);
  }

  Future<void> _edit(int id, String name, Set<WaAutoDocKind> kinds, String? phoneHint) async {
    final saved = await WaPhoneBook.phoneOf(WaPhoneBook.keyOf(id, name));
    final phone = saved ?? await WaDocSender.resolvePhone(phone: phoneHint, customerId: id, customerName: name);
    if (!mounted) return;
    final r = await showDialog<({String phone, Set<WaAutoDocKind> kinds})>(
      context: context,
      builder: (_) => _SubDialog(name: name, phone: phone, kinds: kinds),
    );
    if (r == null) return;
    try {
      await WaAutoDocs.save(id, name.trim(), r.phone, r.kinds);
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
    await _load();
  }

  Future<void> _remove(WaAutoDocSub s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إيقاف الإرسال التلقائي لـ ${s.name}؟'),
        content: const Text('لا يُرسل له شيء تلقائياً بعد الآن. رقمه المؤكَّد يبقى في «الأرقام المؤكَّدة».'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إيقاف')),
        ],
      ),
    );
    if (ok != true) return;
    await WaAutoDocs.remove(s.customerId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final subs = _subs;
    return SettingsScaffold(
      title: 'الإرسال التلقائي للعملاء',
      icon: Icons.auto_mode_rounded,
      subtitle: 'فواتير ووصولات تصل لحظة الحفظ',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('عميل'),
      ),
      children: [
        const SetHero(
          icon: Icons.auto_mode_rounded,
          title: 'بلا ضغطة إرسال',
          text: 'اختر العميل وما يصله: عند حفظ فاتورته أو وصل تسديده يُرسل الملف نفسه الذي يُطبع إلى واتساب '
              'عبر الخادم مباشرة. النتيجة في الإشعار أعلى الشاشة و«سجل الرسائل».',
          color: kSetGreen,
        ),
        if (_block != null) SetBanner('⚠️ الإرسال متوقف الآن: $_block', kind: SetBannerKind.warn),
        const SetBanner(
          'لا يُرسل إلا لرقم أكّدته هنا. لا يُرسل مستند فيه دين إن لم يطابق رصيد العميل معاملاته. '
          'وصل القبض الذي يجمع أكثر من عميل لا يُرسل (فيه أرصدة غيره).',
        ),
        const SizedBox(height: 12),
        if (subs == null)
          const LinearProgressIndicator()
        else if (subs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: Text('لا عملاء بعد — اضغط «عميل» لإضافة أول عميل', style: TextStyle(color: kSetMuted)),
            ),
          )
        else
          for (final s in subs) _subCard(s),
        const SizedBox(height: 70),
      ],
    );
  }

  Widget _subCard(WaAutoDocSub s) {
    final phone = _phones[s.customerId];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: phone == null ? kSetRed.withValues(alpha: 0.35) : kSetBorder),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _edit(s.customerId, s.name, s.kinds, phone),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: kSetGreen.withValues(alpha: 0.12),
                child: Text(s.name.isEmpty ? '؟' : s.name.characters.first,
                    style: const TextStyle(color: kSetGreen, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: kSetText)),
                  const SizedBox(height: 2),
                  Text(phone ?? 'لا رقم مؤكَّد — لا يُرسل له شيء',
                      textDirection: phone == null ? null : TextDirection.ltr,
                      style: TextStyle(fontSize: 12.5, color: phone == null ? kSetRed : kSetMuted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final k in WaAutoDocKind.values)
                      if (s.kinds.contains(k))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: kSetGreen.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(k.label,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kSetGreen)),
                        ),
                  ]),
                ]),
              ),
              IconButton(
                tooltip: 'إيقاف',
                icon: const Icon(Icons.delete_outline_rounded, color: kSetMuted),
                onPressed: () => _remove(s),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// رقم العميل (يُؤكَّد هنا) وما يصله تلقائياً.
class _SubDialog extends StatefulWidget {
  const _SubDialog({required this.name, required this.phone, required this.kinds});
  final String name;
  final String? phone;
  final Set<WaAutoDocKind> kinds;
  @override
  State<_SubDialog> createState() => _SubDialogState();
}

class _SubDialogState extends State<_SubDialog> {
  late final _phone = TextEditingController(text: widget.phone ?? '');
  late final Set<WaAutoDocKind> _kinds = {...widget.kinds};
  String? _err;

  void _save() {
    final p = WaAutoReminder.normalizePhone(_phone.text);
    if (p == null) {
      setState(() => _err = 'رقم غير صالح — مثل 07701234567');
      return;
    }
    if (_kinds.isEmpty) {
      setState(() => _err = 'اختر مستنداً واحداً على الأقل');
      return;
    }
    Navigator.pop(context, (phone: p, kinds: _kinds));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        icon: const Icon(Icons.auto_mode_rounded, color: kSetGreen, size: 32),
        title: Text('الإرسال التلقائي — ${widget.name}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'رقم واتساب (يُؤكَّد بالحفظ)',
                  helperText: 'تأكد منه: كل ما يُرسل تلقائياً يذهب إلى هذا الرقم بلا سؤال',
                  errorText: _err,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              const Text('ما يصله تلقائياً عند الحفظ', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final k in WaAutoDocKind.values)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _kinds.contains(k),
                  onChanged: (v) => setState(() => v == true ? _kinds.add(k) : _kinds.remove(k)),
                  title: Text(k.label),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kSetGreen),
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('حفظ'),
          ),
        ],
      );
}
