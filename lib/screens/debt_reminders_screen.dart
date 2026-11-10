// lib/screens/debt_reminders_screen.dart
//
// 📅 مواعيد المطالبة: كل المواعيد (أو مواعيد عميل واحد)، وإعداد ظهورها عند التشغيل،
// ونافذة «مطالبات اليوم» التي تظهر عند تشغيل البرنامج.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/database_service.dart';
import '../services/debt_reminders.dart';
import '../services/settings_manager.dart';
import '../services/whatsapp/claim_message.dart'; // 📨 مطالبة رسمية عبر واتساب
import '../widgets/app_dialog_shell.dart'; // 🪟 شكل النوافذ الموحّد
import '../widgets/debt_reminder_editor.dart';
import '../widgets/settings_kit.dart';
import '../wa_messages/wa_widgets.dart'; // 💬 إرسال آلي
import 'customer_details_screen.dart';
import '../wa_messages/wa_access.dart';

const _accent = Color(0xFF4F46E5);
String _money(num v) => NumberFormat('#,##0', 'en_US').format(v);

Future<void> _openCustomer(BuildContext context, int id) async {
  final c = await DatabaseService().getCustomerById(id);
  if (c == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailsScreen(customer: c)));
}

DebtReminder _blank({List<ReminderMember>? members}) {
  final now = DateTime.now();
  return DebtReminder(
    startYear: now.month == 12 ? now.year + 1 : now.year,
    startMonth: (now.month % 12) + 1,
    members: members,
  );
}

class DebtRemindersScreen extends StatefulWidget {
  const DebtRemindersScreen({super.key, this.customerId, this.customerName});
  final int? customerId;
  final String? customerName;

  @override
  State<DebtRemindersScreen> createState() => _DebtRemindersScreenState();
}

class _DebtRemindersScreenState extends State<DebtRemindersScreen> {
  List<DebtReminder> _items = const [];
  Map<int, double> _balances = const {};
  bool _loading = true;
  bool _enabled = true;
  String _freq = 'daily';
  int _dueToday = 0;
  int _paidRecently = 0;
  int _grace = DebtReminders.defaultGraceDays;

  bool get _forCustomer => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await DebtReminders.list(customerId: widget.customerId);
    final bal = await DebtReminders.balances([for (final r in items) ...r.members.map((m) => m.customerId)]);
    final en = await DebtReminders.enabled();
    final fq = await DebtReminders.frequency();
    final gr = await DebtReminders.graceDays();
    final due = await DebtReminders.dueTodayDetailed(includeSnoozed: true);
    if (!mounted) return;
    setState(() {
      _items = items;
      _balances = bal;
      _enabled = en;
      _freq = fq;
      _grace = gr;
      _dueToday = due.due.length;
      _paidRecently = due.paidRecently.length;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final r = await showDebtReminderEditor(
      context,
      initial: _blank(
        members: _forCustomer
            ? [ReminderMember(customerId: widget.customerId!, customerName: widget.customerName ?? '')]
            : null,
      ),
    );
    if (r == null) return;
    await DebtReminders.save(r);
    if (mounted) setToast(context, 'حُفظ الموعد — ${r.describe()}');
    _load();
  }

  Future<void> _edit(DebtReminder r) async {
    final e = await showDebtReminderEditor(context, initial: r);
    if (e == null) return;
    await DebtReminders.save(e);
    _load();
  }

  Future<void> _delete(DebtReminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الموعد؟'),
        content: Text('لن يُعرض تنبيه «${r.shownTitle}» بعد الآن (${r.members.length} عميل). لا يتأثر أي رصيد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kSetRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف الموعد'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DebtReminders.delete(r.id!);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: _forCustomer ? 'مواعيد المطالبة بالسداد — ${widget.customerName ?? ''}' : 'مواعيد المطالبة بالسداد',
      icon: Icons.event_repeat_rounded,
      subtitle: 'أيام محددة من الشهر والعملاء المطلوب مطالبتهم — يُعرض التنبيه عند تشغيل البرنامج',
      loading: _loading,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('موعد جديد'),
      ),
      children: [
        if (!_forCustomer) _settingsCard(),
        if (!_forCustomer) _graceCard(),
        if (_items.isEmpty)
          const SetBanner(
            'لا توجد مواعيد مطالبة. لإضافة موعد اختر «موعد جديد»، وحدّد أيام المطالبة (مثل 1 و2 و5)، ثم أضف العملاء.',
            icon: Icons.event_busy_rounded,
          )
        else
          for (final r in _items)
            _ReminderCard(
              r: r,
              balances: _balances,
              onEdit: () => _edit(r),
              onDelete: () => _delete(r),
              onToggle: () async {
                await DebtReminders.setActive(r.id!, !r.active);
                _load();
              },
              onOpen: (id) => _openCustomer(context, id).then((_) => _load()),
            ),
        const SizedBox(height: 70),
      ],
    );
  }

  Widget _graceCard() => SetCard(
        title: 'مهلة الإعفاء لمن سدّد حديثاً',
        subtitle: 'الإعداد العام لجميع المواعيد، ويمكن تخصيصه لموعد بعينه من «تعديل»',
        icon: Icons.price_check_rounded,
        color: kSetGreen,
        child: DebtGracePicker(
          value: _grace,
          onChanged: (v) async {
            final n = v ?? DebtReminders.defaultGraceDays;
            await DebtReminders.setGraceDays(n);
            await _load();
          },
        ),
      );

  Widget _settingsCard() => SetCard(
        title: 'التنبيه عند تشغيل البرنامج',
        subtitle: (_dueToday == 0 ? 'لا مطالبات مستحقة اليوم' : 'المستحق مطالبتهم اليوم: $_dueToday عميل') +
            (_paidRecently == 0 ? '' : ' — المُعفَون لسدادهم حديثاً: $_paidRecently'),
        icon: Icons.notifications_active_outlined,
        color: _accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SetSwitch(
            title: 'عرض المطالبات المستحقة',
            subtitle: 'تشمل العملاء المدينين فقط',
            value: _enabled,
            color: _accent,
            onChanged: (v) async {
              await DebtReminders.setEnabled(v);
              setState(() => _enabled = v);
            },
          ),
          const SizedBox(height: 6),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _enabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !_enabled,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in const [('daily', 'عند أول تشغيل في اليوم'), ('startup', 'عند كل تشغيل')])
                  ChoiceChip(
                    label: Text(f.$2),
                    selected: _freq == f.$1,
                    showCheckmark: false,
                    selectedColor: _accent.withValues(alpha: 0.12),
                    side: BorderSide(color: _freq == f.$1 ? _accent : kSetBorder),
                    labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _freq == f.$1 ? _accent : kSetText),
                    onSelected: (_) async {
                      await DebtReminders.setFrequency(f.$1);
                      setState(() => _freq = f.$1);
                    },
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final due = await DebtReminders.dueToday(includeSnoozed: true);
                    if (!mounted) return;
                    if (due.isEmpty) {
                      setToast(context, 'لا مطالبات مستحقة اليوم');
                      return;
                    }
                    await showDueRemindersDialog(context, due);
                    _load();
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('عرض المطالبات المستحقة اليوم'),
                ),
              ]),
            ),
          ),
        ]),
      );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.r,
    required this.balances,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onOpen,
  });
  final DebtReminder r;
  final Map<int, double> balances;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final void Function(int customerId) onOpen;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = r.nextDate(now);
    final owing = r.members.where((m) => (balances[m.customerId] ?? 0.0) > 0.5).length;
    final total = r.members.fold<double>(0, (s, m) => s + (m.amount ?? balances[m.customerId] ?? 0.0));
    final (String status, Color c) = !r.active
        ? ('موقوف', kSetMuted)
        : owing == 0
            ? ('مسدَّد — لا مطالبة', kSetGreen)
            : r.isDueOn(now)
                ? ('مستحق اليوم', kSetRed)
                : next == null
                    ? ('منتهٍ', kSetMuted)
                    : ('الموعد القادم ${DateFormat('yyyy/MM/dd').format(next)}', _accent);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSetBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: c),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(r.shownTitle,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kSetText)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                    child: Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(r.describe(), style: const TextStyle(color: kSetMuted, height: 1.5)),
                if (r.graceDays != null)
                  Text(r.graceText(0), style: const TextStyle(fontSize: 12.5, color: kSetGreen)),
                Text('${r.members.length} عميل • المدينون منهم $owing • المبلغ المستحق ${_money(total)}',
                    style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
                if ((r.note ?? '').isNotEmpty)
                  Text(r.note!, style: const TextStyle(fontSize: 12.5, color: kSetMuted, fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final m in r.members.take(12))
                    ActionChip(
                      avatar: Icon(Icons.person_outline,
                          size: 16, color: (balances[m.customerId] ?? 0.0) > 0.5 ? kSetRed : kSetGreen),
                      label: Text(
                          '${m.customerName}  ${_money(m.amount ?? balances[m.customerId] ?? 0.0)}'),
                      tooltip: 'فتح حساب ${m.customerName}',
                      onPressed: () => onOpen(m.customerId),
                    ),
                  if (r.members.length > 12)
                    Chip(label: Text('+${r.members.length - 12}')),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 4, children: [
                  TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('تعديل')),
                  TextButton.icon(
                    onPressed: onToggle,
                    icon: Icon(r.active ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
                    label: Text(r.active ? 'إيقاف' : 'تفعيل'),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: kSetRed),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('حذف'),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ نافذة «مطالبات اليوم» عند التشغيل ═══════════════════════════

Future<void> showDueRemindersDialog(BuildContext context, List<DueReminder> due) =>
    showDialog<void>(context: context, builder: (_) => _DueDialog(due: due));

class _DueDialog extends StatefulWidget {
  const _DueDialog({required this.due});
  final List<DueReminder> due;

  @override
  State<_DueDialog> createState() => _DueDialogState();
}

class _DueDialogState extends State<_DueDialog> {
  final _done = <int, String>{}; // معرّف الشخص في الموعد ← ما حدث له
  Map<int, String> _phones = const {}; // العميل ← هاتفه
  Map<int, String> _invoiceNo = const {}; // معرّف الفاتورة ← رقمها المطبوع (لا المعرّف الداخلي)
  String _company = '';

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final ids = {for (final d in widget.due) d.member.customerId}.toList();
      final db = await DatabaseService().database;
      final phones = <int, String>{};
      for (var i = 0; i < ids.length; i += 500) {
        final part = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
        final r = await db.rawQuery(
            'SELECT id, phone FROM customers WHERE id IN (${List.filled(part.length, '?').join(',')})', part);
        for (final x in r) {
          final ph = '${x['phone'] ?? ''}'.trim();
          if (ph.isNotEmpty) phones[x['id'] as int] = ph;
        }
      }
      final invIds = {for (final d in widget.due) if (d.member.invoiceId != null) d.member.invoiceId!}.toList();
      final invNo = <int, String>{};
      if (invIds.isNotEmpty) {
        final r = await db.rawQuery(
            'SELECT id, invoice_number FROM invoices WHERE id IN (${List.filled(invIds.length, '?').join(',')})', invIds);
        for (final x in r) {
          final n = '${x['invoice_number'] ?? ''}'.trim();
          if (n.isNotEmpty) invNo[x['id'] as int] = n;
        }
      }
      final company = (await SettingsManager.getAppSettings()).invoiceDesign.companyName;
      if (!mounted) return;
      setState(() {
        _phones = phones;
        _invoiceNo = invNo;
        _company = company.replaceAll(RegExp(r'ـ+'), '').trim(); // بلا تطويل الزخرفة
      });
    } catch (_) {}
  }

  /// 💬 إرسال آلي (الخادم أو WhatsApp Desktop) عبر صندوق الصادر.
  Future<void> _autoSend(List<DueReminder> list) async {
    final n = await showWaSendDialog(
      context,
      [for (final d in list) WaRecipient(d.member.customerId, d.member.customerName, _phones[d.member.customerId])],
      source: 'reminder',
    );
    if (n > 0 && mounted) {
      setState(() {
        for (final d in list) {
          if (_phones.containsKey(d.member.customerId)) _done[d.member.id!] = 'أُضيف إلى إرسال واتساب الآلي';
        }
      });
    }
  }

  Future<void> _whatsApp(DueReminder d) async {
    final phone = WhatsAppLink.normalizePhone(_phones[d.member.customerId]);
    if (phone == null) return;
    final text = ClaimMessage.build(
      customerName: d.member.customerName,
      company: _company,
      balance: d.balance,
      amount: d.member.amount,
      lastPaid: d.lastPaid,
      invoiceNumber: d.member.invoiceId == null ? null : _invoiceNo[d.member.invoiceId],
    );
    final ok = await WhatsAppLink.open(phone, text);
    if (!mounted) return;
    setToast(context, ok ? 'فُتح واتساب برسالة المطالبة' : 'تعذّر فتح واتساب — نُسخت الرسالة، الصقها يدوياً', error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.due;
    final total = list.fold<double>(0, (s, d) => s + (d.member.amount ?? d.balance));
    final withPhone = list.where((d) => _phones.containsKey(d.member.customerId)).length;
    return AppDialogShell(
      icon: Icons.notifications_active_rounded,
      color: _accent,
      title: 'المطالبات المستحقة اليوم',
      subtitle: 'تذكير بمواعيد المطالبة بالسداد التي حلّ موعدها',
      onClose: () => Navigator.pop(context),
      maxWidth: 660,
      headerExtra: Wrap(spacing: 8, runSpacing: 8, children: [
        HeaderStat(value: '${list.length}', label: 'مطالبة اليوم', icon: Icons.people_alt_rounded),
        HeaderStat(value: _money(total), label: 'دينار مستحق', icon: Icons.payments_rounded),
        if (withPhone > 0) HeaderStat(value: '$withPhone', label: 'برقم واتساب', icon: Icons.chat_rounded),
      ]),
      body: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(14),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _row(list[i]),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => const DebtRemindersScreen()));
          },
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('إدارة مواعيد المطالبة'),
        ),
        const Spacer(),
        if (WaAccess.sendNow && withPhone > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D), minimumSize: const Size(0, 46)),
              onPressed: () => _autoSend([for (final d in list) if (_done[d.member.id] == null) d]),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text('إرسال آلي للكل ($withPhone)'),
            ),
          ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size(110, 46)),
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }

  Widget _row(DueReminder d) {
    final r = d.reminder;
    final m = d.member;
    final done = _done[m.id];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: done == null ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kSetBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(m.customerName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kSetText)),
            ),
            Text('${_money(m.amount ?? d.balance)} د.ع',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kSetRed)),
          ]),
          const SizedBox(height: 2),
          Text(
            [
              if ((r.title ?? '').trim().isNotEmpty) r.title!.trim(),
              if (m.amount != null) 'رصيده الحالي ${_money(d.balance)}',
              // الرقم المطبوع على الفاتورة (لا المعرّف الداخلي)
              if (m.invoiceId != null && _invoiceNo[m.invoiceId] != null) 'فاتورة رقم ${_invoiceNo[m.invoiceId]}',
              d.lastPaid == null ? 'لا سداد سابق' : 'آخر سداد ${DateFormat('yyyy/MM/dd').format(d.lastPaid!)}',
              r.daysText(),
              if ((r.note ?? '').isNotEmpty) r.note!,
            ].join(' • '),
            style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.5),
          ),
          const SizedBox(height: 4),
          if (done != null)
            Text(done, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kSetGreen))
          else
            Wrap(spacing: 4, children: [
              TextButton.icon(
                onPressed: () => _openCustomer(context, m.customerId),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('فتح حساب العميل'),
              ),
              if (_phones.containsKey(m.customerId))
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF15803D)),
                  onPressed: () => _whatsApp(d),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text('مطالبة عبر واتساب'),
                ),
              if (_phones.containsKey(m.customerId) && WaAccess.sendNow)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF15803D)),
                  onPressed: () => _autoSend([d]),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('إرسال آلي'),
                ),
              TextButton.icon(
                onPressed: () async {
                  await DebtReminders.snoozeMemberToTomorrow(m.id!);
                  setState(() => _done[m.id!] = 'أُجّلت المطالبة إلى الغد');
                },
                icon: const Icon(Icons.snooze_rounded, size: 18),
                label: const Text('تأجيل إلى الغد'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: kSetMuted),
                onPressed: () async {
                  await DebtReminders.setMemberActive(m.id!, false);
                  setState(() => _done[m.id!] = 'استُبعد من هذا الموعد');
                },
                icon: const Icon(Icons.person_remove_outlined, size: 18),
                label: const Text('استبعاد من الموعد'),
              ),
            ]),
        ]),
      ),
    );
  }
}
