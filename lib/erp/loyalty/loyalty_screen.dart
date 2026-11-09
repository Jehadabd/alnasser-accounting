// lib/erp/loyalty/loyalty_screen.dart
//
// 🎁 «برنامج الولاء»: الإعدادات (نقاط أو أختام، المكافأة)، الأعضاء وأرصدتهم، صرف مكافأة،
// بطاقة PDF برمز QR، ورسالة واتساب لحاملي البطاقات. الانضمام يضيفه الموظف (لا انضمام ذاتي).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';

import '../../owner/wa_auto/wa_auto_reminder.dart';
import '../../wa_messages/wa_rules.dart' show WaMessageOptions;
import '../../wa_messages/wa_widgets.dart';
import '../../widgets/settings_kit.dart';
import '../erp_common.dart';
import '../pickers.dart';
import 'loyalty_card_pdf.dart';
import 'loyalty_models.dart';
import 'loyalty_store.dart';

final _n = NumberFormat('#,##0', 'en');

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});
  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final _store = LoyaltyStore();
  LoyaltySettings? _s;
  List<LoyaltyRow>? _rows;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _store.settings();
      final rows = await _store.members();
      if (mounted) {
        setState(() {
          _s = s;
          _rows = rows;
        });
      }
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  Future<void> _join() async {
    final p = await Pickers.customer(context, title: 'إضافة عضو');
    if (p == null) return;
    try {
      final card = await _store.join(p.id);
      if (mounted) setToast(context, 'انضم ${p.name} — البطاقة $card');
      await _load();
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  Future<void> _editSettings() async {
    final s = await showDialog<LoyaltySettings>(context: context, builder: (_) => _SettingsDialog(initial: _s!));
    if (s == null) return;
    await _store.saveSettings(s);
    await _load();
  }

  Future<void> _redeem(LoyaltyRow r) async {
    final s = _s!;
    final ok = await confirmDialog(context, 'صرف مكافأة لـ${r.member.name}',
        '«${s.rewardText}»\nيُخصم ${s.unitsPerReward} ${s.unitName} من رصيده. طبّق المكافأة في الفاتورة بنفسك (خصم أو هدية).',
        ok: 'صرف');
    if (!ok) return;
    try {
      await _store.redeem(r);
      if (mounted) setToast(context, 'صُرفت المكافأة');
      await _load();
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  Future<void> _card(LoyaltyRow r) async {
    final bytes = await buildLoyaltyCardPdf(
        member: r.member, shopName: await WaAutoReminder.shopName(), balance: r.balance, settings: _s!);
    await Printing.sharePdf(bytes: bytes, filename: 'بطاقة ولاء - ${r.member.name}.pdf');
  }

  Future<void> _message(List<LoyaltyRow> rows) async {
    await showWaSendDialog(
      context,
      [for (final r in rows) WaRecipient(r.member.customerId, r.member.name, r.member.phone)],
      source: 'loyalty',
      requireDebt: false,
      initial: const WaMessageOptions(template: 'مرحباً {الاسم}،\nشكراً لأنك من أعضاء بطاقة الولاء لدى {المحل}.\n', address: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final rows = _rows;
    final shown = rows == null
        ? const <LoyaltyRow>[]
        : [for (final r in rows) if (_q.isEmpty || r.member.name.contains(_q) || r.member.cardNo.contains(_q)) r];
    return SettingsScaffold(
      title: 'برنامج الولاء',
      icon: Icons.loyalty_rounded,
      subtitle: 'نقاط أو أختام من المبيعات، ومكافأة تلقائية حين يكتمل الرصيد',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      floatingActionButton: s?.enabled == true
          ? FloatingActionButton.extended(onPressed: _join, icon: const Icon(Icons.person_add_rounded), label: const Text('عضو'))
          : null,
      children: [
        if (s == null)
          const LinearProgressIndicator()
        else ...[
          SetCard(
            title: s.enabled ? 'مفعّل' : 'مطفأ',
            icon: Icons.tune_rounded,
            color: s.enabled ? kSetGreen : kSetMuted,
            trailing: TextButton(onPressed: _editSettings, child: const Text('الإعدادات')),
            child: Text(
              s.mode == LoyaltyMode.points
                  ? 'نقطة لكل ${_n.format(s.filsPerPoint / 100)} دينار صافٍ • المكافأة كل ${s.rewardCost} نقطة: ${s.rewardText}'
                  : 'ختم لكل فاتورة من ${_n.format(s.stampMinFils / 100)} دينار • المكافأة كل ${s.stampsPerReward} ختم: ${s.rewardText}',
              style: const TextStyle(height: 1.6),
            ),
          ),
          const SizedBox(height: 8),
          const SetBanner(
            'الرصيد يُحسب من مبيعات العضو الصافية منذ انضمامه (بعد المرتجعات والتعديلات) — لا يُكتب يدوياً. '
            'صرف المكافأة يُسجَّل هنا فقط؛ طبّقها في الفاتورة خصماً أو هدية.',
          ),
          const SizedBox(height: 10),
          if (rows != null && rows.isNotEmpty)
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو رقم البطاقة', isDense: true),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _message([for (final r in shown) if (r.member.active) r]),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('رسالة للأعضاء'),
              ),
            ]),
          const SizedBox(height: 8),
          if (rows == null)
            const LinearProgressIndicator()
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(s.enabled ? 'لا أعضاء بعد — اضغط «عضو»' : 'فعّل البرنامج من «الإعدادات»')),
            )
          else
            for (final r in shown) _memberTile(r, s),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _memberTile(LoyaltyRow r, LoyaltySettings s) {
    final b = r.balance;
    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (b.rewardsAvailable > 0 ? kSetGreen : kSetNavy).withValues(alpha: 0.12),
          child: Icon(b.rewardsAvailable > 0 ? Icons.card_giftcard_rounded : Icons.loyalty_rounded,
              color: b.rewardsAvailable > 0 ? kSetGreen : kSetNavy),
        ),
        title: Text(r.member.name, style: TextStyle(fontWeight: FontWeight.w800, color: r.member.active ? null : kSetMuted)),
        subtitle: Text([
          'بطاقة ${r.member.cardNo}',
          '${b.available} ${s.unitName}',
          b.rewardsAvailable > 0 ? '${b.rewardsAvailable} مكافأة متاحة' : 'باقي ${b.toNextReward} للمكافأة',
          if (!r.member.active) 'موقوف',
        ].join(' • ')),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'redeem':
                await _redeem(r);
              case 'card':
                await _card(r);
              case 'msg':
                await _message([r]);
              case 'toggle':
                await _store.setActive(r.member.customerId, !r.member.active);
                await _load();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'redeem', enabled: b.rewardsAvailable > 0, child: const Text('صرف مكافأة')),
            const PopupMenuItem(value: 'card', child: Text('البطاقة (PDF)')),
            const PopupMenuItem(value: 'msg', child: Text('رسالة واتساب')),
            PopupMenuItem(value: 'toggle', child: Text(r.member.active ? 'إيقاف العضوية' : 'إعادة تفعيل')),
          ],
        ),
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.initial});
  final LoyaltySettings initial;
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late LoyaltySettings _s = widget.initial;
  late final _perPoint = TextEditingController(text: _n.format(_s.filsPerPoint / 100));
  late final _cost = TextEditingController(text: '${_s.rewardCost}');
  late final _stampMin = TextEditingController(text: _n.format(_s.stampMinFils / 100));
  late final _stamps = TextEditingController(text: '${_s.stampsPerReward}');
  late final _reward = TextEditingController(text: _s.rewardText);

  @override
  void dispose() {
    for (final c in [_perPoint, _cost, _stampMin, _stamps, _reward]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, int def) => int.tryParse(c.text.replaceAll(',', '').trim()) ?? def;

  void _done() {
    final perPoint = ((parseMoney(_perPoint.text) ?? 0) * 100).round();
    final stampMin = ((parseMoney(_stampMin.text) ?? 0) * 100).round();
    Navigator.pop(
      context,
      _s.copyWith(
        filsPerPoint: perPoint > 0 ? perPoint : _s.filsPerPoint,
        rewardCost: _int(_cost, _s.rewardCost).clamp(1, 1000000),
        stampMinFils: stampMin >= 0 ? stampMin : _s.stampMinFils,
        stampsPerReward: _int(_stamps, _s.stampsPerReward).clamp(1, 1000),
        rewardText: _reward.text.trim().isEmpty ? _s.rewardText : _reward.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('إعدادات برنامج الولاء'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('مفعّل'),
                value: _s.enabled,
                onChanged: (v) => setState(() => _s = _s.copyWith(enabled: v)),
              ),
              SegmentedButton<LoyaltyMode>(
                segments: const [
                  ButtonSegment(value: LoyaltyMode.points, label: Text('نقاط')),
                  ButtonSegment(value: LoyaltyMode.stamps, label: Text('أختام')),
                ],
                selected: {_s.mode},
                onSelectionChanged: (m) => setState(() => _s = _s.copyWith(mode: m.first)),
              ),
              const SizedBox(height: 8),
              if (_s.mode == LoyaltyMode.points) ...[
                TextField(controller: _perPoint, decoration: const InputDecoration(labelText: 'نقطة لكل (دينار صافٍ)'), keyboardType: TextInputType.number),
                TextField(controller: _cost, decoration: const InputDecoration(labelText: 'المكافأة كل (نقطة)'), keyboardType: TextInputType.number),
              ] else ...[
                TextField(controller: _stampMin, decoration: const InputDecoration(labelText: 'ختم لكل فاتورة من (دينار)'), keyboardType: TextInputType.number),
                TextField(controller: _stamps, decoration: const InputDecoration(labelText: 'المكافأة كل (ختم)'), keyboardType: TextInputType.number),
              ],
              TextField(controller: _reward, decoration: const InputDecoration(labelText: 'المكافأة (نص)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: _done, child: const Text('حفظ')),
        ],
      );
}
