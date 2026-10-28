// lib/screens/debt_reminders_screen.dart
//
// 📅 مواعيد المطالبة: كل المواعيد (أو مواعيد عميل واحد)، وإعداد ظهورها عند التشغيل،
// ونافذة «مطالبات اليوم» التي تظهر عند تشغيل البرنامج.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../services/database_service.dart';
import '../services/debt_reminders.dart';
import '../widgets/debt_reminder_editor.dart';
import '../widgets/settings_kit.dart';
import 'customer_details_screen.dart';

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
    final due = await DebtReminders.dueToday(includeSnoozed: true);
    if (!mounted) return;
    setState(() {
      _items = items;
      _balances = bal;
      _enabled = en;
      _freq = fq;
      _dueToday = due.length;
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
        content: Text('لن يظهر تذكير «${r.shownTitle}» بعد الآن (${r.members.length} شخص). الديون نفسها لا تتأثر.'),
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
      title: _forCustomer ? 'مواعيد المطالبة — ${widget.customerName ?? ''}' : 'مواعيد المطالبة',
      icon: Icons.event_repeat_rounded,
      subtitle: 'أيام تختارها وأشخاص تطالبهم — يظهر التذكير عند تشغيل البرنامج',
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
        if (_items.isEmpty)
          const SetBanner(
            'لا مواعيد بعد. اضغط «موعد جديد»، اختر الأيام (مثل 1 و2 و5) ثم أضف الأشخاص.',
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

  Widget _settingsCard() => SetCard(
        title: 'الظهور عند التشغيل',
        subtitle: _dueToday == 0 ? 'لا مطالبات اليوم' : 'مستحق اليوم: $_dueToday شخص',
        icon: Icons.notifications_active_outlined,
        color: _accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SetSwitch(
            title: 'إظهار مطالبات اليوم',
            subtitle: 'تظهر فقط لمن ما زال عليه دين',
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
                for (final f in const [('daily', 'أول تشغيل في اليوم'), ('startup', 'عند كل تشغيل')])
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
                  label: const Text('عرض مطالبات اليوم الآن'),
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
            ? ('سدّدوا — لا تذكير', kSetGreen)
            : r.isDueOn(now)
                ? ('مستحق اليوم', kSetRed)
                : next == null
                    ? ('انتهى', kSetMuted)
                    : ('القادم ${DateFormat('yyyy/MM/dd').format(next)}', _accent);
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
                Text('${r.members.length} شخص • عليهم دين $owing • المطلوب ${_money(total)}',
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

  @override
  Widget build(BuildContext context) {
    final list = widget.due;
    final total = list.fold<double>(0, (s, d) => s + (d.member.amount ?? d.balance));
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 660),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 8, 16),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.06),
              border: const Border(bottom: BorderSide(color: kSetBorder)),
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: _accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.notifications_active_rounded, color: _accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('مطالبات اليوم (${list.length})',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kSetText)),
                  Text('المجموع المطلوب ${_money(total)} دينار', style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
                ]),
              ),
              IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: kSetMuted)),
            ]),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(14),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _row(list[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(children: [
              TextButton.icon(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(builder: (_) => const DebtRemindersScreen()));
                },
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('إدارة المواعيد'),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size(110, 46)),
                onPressed: () => Navigator.pop(context),
                child: const Text('تم'),
              ),
            ]),
          ),
        ]),
      ),
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
              if (m.amount != null) 'رصيده الآن ${_money(d.balance)}',
              if (m.invoiceId != null) 'فاتورة #${m.invoiceId}',
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
                label: const Text('فتح الحساب'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await DebtReminders.snoozeMemberToTomorrow(m.id!);
                  setState(() => _done[m.id!] = 'سيُذكَّر غداً');
                },
                icon: const Icon(Icons.snooze_rounded, size: 18),
                label: const Text('ذكّرني غداً'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: kSetMuted),
                onPressed: () async {
                  await DebtReminders.setMemberActive(m.id!, false);
                  setState(() => _done[m.id!] = 'لن يُذكَّر به في هذا الموعد');
                },
                icon: const Icon(Icons.person_remove_outlined, size: 18),
                label: const Text('إيقافه من الموعد'),
              ),
            ]),
        ]),
      ),
    );
  }
}
