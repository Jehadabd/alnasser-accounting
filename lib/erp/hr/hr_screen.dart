// lib/erp/hr/hr_screen.dart
//
// 👥 «الموارد البشرية» (للمدير، مطفأة حتى تُفعَّل): الموظفون، الحضور اليومي، السلف،
// الرواتب الشهرية، ومسابقات المبيعات (ترتيب من تقرير مبيعات الموظفين نفسه).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../accounting/vouchers_service.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/reports/employee_sales.dart';
import '../../services/reports_service.dart';
import '../../widgets/settings_kit.dart';
import '../erp_common.dart';
import '../pickers.dart';
import 'hr_models.dart';
import 'hr_store.dart';
import '../../services/save_lock.dart'; // 🔒 قفل الحفظ

final _n = NumberFormat('#,##0', 'en');
String _m(int fils) => _n.format((fils / 100).round());
final _t = DateFormat('HH:mm', 'en');

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  final _store = HrStore();
  bool? _enabled;
  int _tab = 0;
  List<HrEmployee> _emps = const [];

  bool get _admin => AuthService().currentUser?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await _store.enabled();
    final e = on ? await _store.employees() : const <HrEmployee>[];
    if (mounted) {
      setState(() {
        _enabled = on;
        _emps = e;
      });
    }
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط: القفل يُؤخذ قبل أي انتظار ويغطي الشاشة حتى ينتهي
  Future<void> _editEmployee([HrEmployee? e]) async {
    await SaveLock.run(() => _editEmployeeUnlocked(e));
  }

  Future<void> _editEmployeeUnlocked([HrEmployee? e]) async {
    final r = await showDialog<HrEmployee>(context: context, builder: (_) => _EmployeeDialog(employee: e));
    if (r == null) return;
    try {
      await _store.saveEmployee(r);
      await _load();
    } catch (err) {
      if (mounted) setToast(context, '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_admin) {
      return const SettingsScaffold(title: 'الموارد البشرية', icon: Icons.groups_2_rounded, children: [SetBanner('للمدير فقط', kind: SetBannerKind.warn)]);
    }
    final on = _enabled;
    return SettingsScaffold(
      title: 'الموارد البشرية',
      icon: Icons.groups_2_rounded,
      subtitle: 'الموظفون، الحضور، السلف، الرواتب، والمسابقات',
      actions: [
        if (on == true)
          IconButton(
            tooltip: 'إطفاء الميزة',
            onPressed: () async {
              await _store.setEnabled(false);
              await _load();
            },
            icon: const Icon(Icons.power_settings_new_rounded),
          ),
      ],
      floatingActionButton: on == true && _tab == 0
          ? FloatingActionButton.extended(onPressed: _editEmployee, icon: const Icon(Icons.person_add_rounded), label: const Text('موظف'))
          : null,
      children: [
        if (on == null)
          const LinearProgressIndicator()
        else if (!on) ...[
          const SetBanner('الميزة مطفأة. تفعيلها يضيف جداول خاصة بها فقط، ولا يغيّر شيئاً في الحسابات حتى تصرف سلفة أو راتباً.'),
          const SizedBox(height: 12),
          SetPrimaryButton(
            label: 'تفعيل الموارد البشرية',
            icon: Icons.power_rounded,
            onPressed: () async {
              await _store.setEnabled(true);
              await _load();
            },
          ),
        ] else ...[
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('الموظفون')),
              ButtonSegment(value: 1, label: Text('الحضور')),
              ButtonSegment(value: 2, label: Text('السلف')),
              ButtonSegment(value: 3, label: Text('الرواتب')),
              ButtonSegment(value: 4, label: Text('المسابقات')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 12),
          switch (_tab) {
            0 => _EmployeesTab(emps: _emps, onEdit: _editEmployee),
            1 => _AttendanceTab(store: _store, emps: _emps.where((e) => e.active).toList()),
            2 => _AdvancesTab(store: _store, emps: _emps),
            3 => _PayrollTab(store: _store, emps: _emps.where((e) => e.active).toList()),
            _ => _CompetitionsTab(store: _store, emps: _emps),
          },
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

// ═════════════════════ أدوات الصرف ═════════════════════

/// يختار الصندوق وحساب المصروف (رواتب). null عند الإلغاء.
Future<({int box, int account})?> _pickPayment(BuildContext context) async {
  final boxes = await VouchersService().cashBoxes();
  if (!context.mounted) return null;
  if (boxes.isEmpty) {
    setToast(context, 'لا صناديق — أضف صندوقاً من المحاسبة', error: true);
    return null;
  }
  CashBox? box = boxes.first;
  final acc = await Pickers.account(context, title: 'حساب مصروف الرواتب', type: 'expense');
  if (acc == null || !context.mounted) return null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('من أي صندوق؟'),
        content: DropdownButton<CashBox>(
          value: box,
          isExpanded: true,
          items: [for (final b in boxes) DropdownMenuItem(value: b, child: Text(b.name))],
          onChanged: (b) => set(() => box = b),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
        ],
      ),
    ),
  );
  if (ok != true || box == null) return null;
  return (box: box!.id, account: acc.id);
}

// ═════════════════════ التبويبات ═════════════════════

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab({required this.emps, required this.onEdit});
  final List<HrEmployee> emps;
  final void Function(HrEmployee) onEdit;
  @override
  Widget build(BuildContext context) => emps.isEmpty
      ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا موظفون — اضغط «موظف»')))
      : Column(children: [
          for (final e in emps)
            Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.badge_rounded),
                title: Text(e.name, style: TextStyle(fontWeight: FontWeight.w800, color: e.active ? null : kSetMuted)),
                subtitle: Text([if (e.job.isNotEmpty) e.job, 'الراتب ${_m(e.salaryFils)}', if (e.username != null) 'دخول: ${e.username}', if (!e.active) 'موقوف']
                    .join(' • ')),
                onTap: () => onEdit(e),
              ),
            ),
        ]);
}

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab({required this.store, required this.emps});
  final HrStore store;
  final List<HrEmployee> emps;
  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  DateTime _day = DateTime.now();
  Map<int, Map<String, Object?>> _rows = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.store.attendanceOn(_day);
    if (mounted) setState(() => _rows = r);
  }

  bool get _today => HrStore.day(_day) == HrStore.day(DateTime.now());

  void _go(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(onPressed: () => _go(-1), icon: const Icon(Icons.chevron_right_rounded)),
          Expanded(child: Text(HrStore.day(_day), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(
              onPressed: _today ? null : () => _go(1),
              icon: const Icon(Icons.chevron_left_rounded)),
        ]),
        for (final e in widget.emps)
          Builder(builder: (_) {
            final r = _rows[e.id];
            final inAt = DateTime.tryParse('${r?['in_at'] ?? ''}');
            final outAt = DateTime.tryParse('${r?['out_at'] ?? ''}');
            final mins = workedMinutes(inAt, outAt);
            return ListTile(
              title: Text(e.name),
              subtitle: Text(inAt == null
                  ? 'لم يحضر'
                  : 'حضور ${_t.format(inAt)}${outAt == null ? '' : ' • انصراف ${_t.format(outAt)}'}'
                      '${mins == null ? '' : ' • ${mins ~/ 60} س ${mins % 60} د'}'),
              trailing: _today
                  ? FilledButton.tonal(
                      onPressed: () async {
                        final what = await widget.store.punch(e.id!);
                        if (context.mounted) setToast(context, '$what: ${e.name}');
                        await _load();
                      },
                      child: Text(inAt == null ? 'حضور' : 'انصراف'),
                    )
                  : null,
            );
          }),
      ]);
}

class _AdvancesTab extends StatefulWidget {
  const _AdvancesTab({required this.store, required this.emps});
  final HrStore store;
  final List<HrEmployee> emps;
  @override
  State<_AdvancesTab> createState() => _AdvancesTabState();
}

class _AdvancesTabState extends State<_AdvancesTab> {
  List<HrAdvance> _list = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await widget.store.advances();
    if (mounted) setState(() => _list = l);
  }

  String _name(int id) => widget.emps.firstWhere((e) => e.id == id, orElse: () => HrEmployee(name: '#$id', salaryFils: 0)).name;

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط: القفل يُؤخذ قبل أي انتظار ويغطي الشاشة حتى ينتهي
  Future<void> _add() async {
    await SaveLock.run(() => _addUnlocked());
  }

  Future<void> _addUnlocked() async {
    final active = widget.emps.where((e) => e.active).toList();
    if (active.isEmpty) return;
    HrEmployee e = active.first;
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('سلفة جديدة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<HrEmployee>(
              value: e,
              isExpanded: true,
              items: [for (final x in active) DropdownMenuItem(value: x, child: Text(x.name))],
              onChanged: (x) => set(() => e = x ?? e),
            ),
            TextField(controller: amount, decoration: const InputDecoration(labelText: 'المبلغ'), keyboardType: TextInputType.number),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('صرف من الصندوق')),
          ],
        ),
      ),
    );
    final fils = ((parseMoney(amount.text) ?? 0) * 100).round();
    final text = note.text;
    amount.dispose();
    note.dispose();
    if (ok != true || !mounted) return;
    final pay = await _pickPayment(context);
    if (pay == null) return;
    try {
      await widget.store.payAdvance(e: e, amountFils: fils, cashBoxId: pay.box, accountId: pay.account, note: text);
      if (mounted) setToast(context, 'صُرفت السلفة وسُجّل سند المصروف');
      await _load();
    } catch (err) {
      if (mounted) setToast(context, '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('سلفة')),
        ),
        const SizedBox(height: 8),
        for (final a in _list)
          ListTile(
            leading: Icon(a.payslipId == null ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
                color: a.payslipId == null ? kSetOrange : kSetGreen),
            title: Text('${_name(a.employeeId)} — ${_m(a.amountFils)}'),
            subtitle: Text('${HrStore.day(a.date)} • ${a.payslipId == null ? 'تُخصم من الراتب القادم' : 'خُصمت'}${a.note.isEmpty ? '' : ' • ${a.note}'}'),
          ),
      ]);
}

class _PayrollTab extends StatefulWidget {
  const _PayrollTab({required this.store, required this.emps});
  final HrStore store;
  final List<HrEmployee> emps;
  @override
  State<_PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<_PayrollTab> {
  String _month = Payslip.monthKey(DateTime.now());
  Map<int, Map<String, Object?>> _paid = const {};
  List<HrAdvance> _adv = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.store.payslips(_month);
    final a = await widget.store.advances();
    if (mounted) {
      setState(() {
        _paid = p;
        _adv = a;
      });
    }
  }

  void _shift(int m) {
    final p = _month.split('-');
    _month = Payslip.monthKey(DateTime(int.parse(p[0]), int.parse(p[1]) + m, 1));
    _load();
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط: القفل يُؤخذ قبل أي انتظار ويغطي الشاشة حتى ينتهي
  Future<void> _pay(HrEmployee e) async {
    await SaveLock.run(() => _payUnlocked(e));
  }

  Future<void> _payUnlocked(HrEmployee e) async {
    final bonus = TextEditingController(text: '0');
    final ded = TextEditingController(text: '0');
    final adv = Payslip.openAdvances(_adv, e.id!, _month);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final p = Payslip(
          employeeId: e.id!,
          month: _month,
          baseFils: e.salaryFils,
          bonusFils: ((parseMoney(bonus.text) ?? 0) * 100).round(),
          deductionFils: ((parseMoney(ded.text) ?? 0) * 100).round(),
          advancesFils: adv,
        );
        return AlertDialog(
          title: Text('راتب ${e.name} — $_month'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('الأساسي: ${_m(e.salaryFils)}'),
            TextField(controller: bonus, decoration: const InputDecoration(labelText: 'مكافأة'), keyboardType: TextInputType.number, onChanged: (_) => set(() {})),
            TextField(controller: ded, decoration: const InputDecoration(labelText: 'خصم (غياب، تأخير...)'), keyboardType: TextInputType.number, onChanged: (_) => set(() {})),
            Text('السلف المخصومة: ${_m(adv)}'),
            const Divider(),
            Text('الصافي: ${_m(p.netFils)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            if (p.error != null) Text(p.error!, style: const TextStyle(color: kSetRed)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: p.error != null ? null : () => Navigator.pop(ctx, true), child: const Text('صرف')),
          ],
        );
      }),
    );
    final p = Payslip(
      employeeId: e.id!,
      month: _month,
      baseFils: e.salaryFils,
      bonusFils: ((parseMoney(bonus.text) ?? 0) * 100).round(),
      deductionFils: ((parseMoney(ded.text) ?? 0) * 100).round(),
      advancesFils: adv,
    );
    bonus.dispose();
    ded.dispose();
    if (go != true || !mounted) return;
    final pay = await _pickPayment(context);
    if (pay == null) return;
    try {
      await widget.store.payPayslip(e: e, p: p, cashBoxId: pay.box, accountId: pay.account);
      if (mounted) setToast(context, 'صُرف راتب ${e.name}');
      await _load();
    } catch (err) {
      if (mounted) setToast(context, '$err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_right_rounded)),
          Expanded(child: Text(_month, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_left_rounded)),
        ]),
        for (final e in widget.emps)
          ListTile(
            leading: Icon(_paid.containsKey(e.id) ? Icons.check_circle_rounded : Icons.payments_outlined,
                color: _paid.containsKey(e.id) ? kSetGreen : kSetNavy),
            title: Text(e.name),
            subtitle: Text(_paid.containsKey(e.id)
                ? 'صُرف ${_m((_paid[e.id]!['net_fils'] as num).toInt())} (سلف ${_m((_paid[e.id]!['advances_fils'] as num).toInt())})'
                : 'الأساسي ${_m(e.salaryFils)} • سلف مفتوحة ${_m(Payslip.openAdvances(_adv, e.id!, _month))}'),
            trailing: _paid.containsKey(e.id) ? null : FilledButton.tonal(onPressed: () => _pay(e), child: const Text('صرف')),
          ),
      ]);
}

class _CompetitionsTab extends StatefulWidget {
  const _CompetitionsTab({required this.store, required this.emps});
  final HrStore store;
  final List<HrEmployee> emps;
  @override
  State<_CompetitionsTab> createState() => _CompetitionsTabState();
}

class _CompetitionsTabState extends State<_CompetitionsTab> {
  List<Map<String, Object?>> _list = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await widget.store.competitions();
    if (mounted) setState(() => _list = l);
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط: القفل يُؤخذ قبل أي انتظار ويغطي الشاشة حتى ينتهي
  Future<void> _add() async {
    await SaveLock.run(() => _addUnlocked());
  }

  Future<void> _addUnlocked() async {
    final title = await askText(context, 'عنوان المسابقة', label: 'مثل: أفضل بائع لشهر 11');
    if (title == null || !mounted) return;
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (range == null || !mounted) return;
    final prize = await askText(context, 'الجائزة', label: 'مثل: 50,000 دينار') ?? '';
    try {
      await widget.store.addCompetition(title, range.start, range.end, prize);
      await _load();
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  Future<void> _board(Map<String, Object?> c) async {
    final from = DateTime.parse('${c['from_day']}');
    final to = DateTime.parse('${c['to_day']}');
    final facts = await ReportsService().loadFacts(from: from, to: to);
    final db = await DatabaseService().database;
    final r = EmployeeSalesReport.group(facts,
        creatorOf: await EmployeeSalesReport.creators(db, facts), names: await EmployeeSalesReport.displayNames(db));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${c['title']} — الترتيب'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${c['from_day']} ← ${c['to_day']}${(c['prize'] ?? '').toString().isEmpty ? '' : ' • الجائزة: ${c['prize']}'}'),
            const SizedBox(height: 8),
            for (var i = 0; i < r.rows.length; i++)
              if (r.rows[i].username.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(r.rows[i].name),
                  trailing: Text(_n.format(r.rows[i].totals.netSales.round())),
                ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('الترتيب بصافي المبيعات من تقرير «مبيعات الموظفين» نفسه (حسب اسم دخول كل موظف).',
            style: TextStyle(fontSize: 12, color: kSetMuted)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.emoji_events_rounded), label: const Text('مسابقة')),
        ),
        for (final c in _list)
          ListTile(
            leading: const Icon(Icons.emoji_events_rounded, color: kSetOrange),
            title: Text('${c['title']}'),
            subtitle: Text('${c['from_day']} ← ${c['to_day']}'),
            onTap: () => _board(c),
          ),
      ]);
}

class _EmployeeDialog extends StatefulWidget {
  const _EmployeeDialog({this.employee});
  final HrEmployee? employee;
  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final _name = TextEditingController(text: widget.employee?.name ?? '');
  late final _phone = TextEditingController(text: widget.employee?.phone ?? '');
  late final _job = TextEditingController(text: widget.employee?.job ?? '');
  late final _salary = TextEditingController(text: _n.format((widget.employee?.salaryFils ?? 0) / 100));
  late final _user = TextEditingController(text: widget.employee?.username ?? '');
  late bool _active = widget.employee?.active ?? true;

  @override
  void dispose() {
    for (final c in [_name, _phone, _job, _salary, _user]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.employee == null ? 'موظف جديد' : 'تعديل الموظف'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
            TextField(controller: _job, decoration: const InputDecoration(labelText: 'الوظيفة')),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'الهاتف'), keyboardType: TextInputType.phone),
            TextField(controller: _salary, decoration: const InputDecoration(labelText: 'الراتب الشهري'), keyboardType: TextInputType.number),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'اسم دخوله في البرنامج (للمسابقات، اختياري)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('على رأس العمل'), value: _active, onChanged: (v) => setState(() => _active = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              HrEmployee(
                id: widget.employee?.id,
                name: _name.text,
                phone: _phone.text,
                job: _job.text,
                salaryFils: ((parseMoney(_salary.text) ?? 0) * 100).round(),
                username: _user.text,
                active: _active,
                startDate: widget.employee?.startDate,
              ),
            ),
            child: const Text('حفظ'),
          ),
        ],
      );
}
