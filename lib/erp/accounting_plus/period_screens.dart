// lib/erp/accounting_plus/period_screens.dart
//
// 🔒 تثبيت الإدخالات وإقفال السنة • 💱 إعادة تقييم العملة • 🗂️ الحسابات النوعية
// • 📝 الملاحظات والحاسبة • 🏛️ مركز المحاسبة المتقدمة.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../../models/app_user.dart';
import '../currency_service.dart';
import '../erp_common.dart';
import '../erp_ui.dart';
import '../pickers.dart';
import '../report_export.dart';
import 'accounting_plus_service.dart';
import 'currency_voucher_screens.dart';

// ═══════════════════════════ التثبيت والإقفال ═══════════════════════════

class PeriodCloseScreen extends StatefulWidget {
  const PeriodCloseScreen({super.key});
  @override
  State<PeriodCloseScreen> createState() => _PeriodCloseScreenState();
}

class _PeriodCloseScreenState extends State<PeriodCloseScreen> {
  final _svc = FiscalCloseService();
  DateTime? _lock;
  List<Map<String, Object?>> _closings = const [];
  final Map<int, double> _drift = {};
  int _year = DateTime.now().year - 1;
  List<ClosingLine> _preview = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await PeriodLock.lockDate();
    final c = await _svc.closings();
    final drift = <int, double>{};
    for (final x in c) {
      final y = x['year'] as int;
      drift[y] = await _svc.driftAfterClose(y);
    }
    final p = await _svc.preview(_year);
    if (!mounted) return;
    setState(() {
      _lock = l;
      _closings = c;
      _drift
        ..clear()
        ..addAll(drift);
      _preview = p;
    });
  }

  Future<void> _setLock() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _lock ?? DateTime(now.year, now.month, 1),
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 1)),
      helpText: 'تثبيت كل ما قبل هذا التاريخ',
    );
    if (d == null || !mounted) return;
    final ok = await confirmDialog(context, 'تثبيت الإدخالات',
        'لن يُسمح بإضافة أو تعديل أو حذف أي مستند بتاريخ قبل ${fmtDate(d)} (فواتير، سندات، مستندات مخزنية، أسعار صرف...).');
    if (!ok) return;
    await PeriodLock.setLockDate(d);
    _load();
  }

  Future<void> _clearLock() async {
    final ok = await confirmDialog(context, 'إلغاء التثبيت', 'السماح بتعديل كل الفترات السابقة؟', color: ErpColors.orange);
    if (!ok) return;
    await PeriodLock.setLockDate(null);
    _load();
  }

  Future<void> _close() async {
    final net = FiscalCloseService.netProfit(_preview);
    var lockAfter = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('إقفال السنة المالية $_year'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('سيُسجَّل قيد إقفال بتاريخ 31/12/$_year يصفّر ${_preview.length} حساب إيرادات ومصاريف '
                'ويرحّل ${net >= 0 ? 'صافي الربح' : 'صافي الخسارة'} ${fmtMoney(net.abs())} إلى الأرباح المحتجزة.'),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: lockAfter,
              onChanged: (v) => setS(() => lockAfter = v ?? true),
              title: Text('تثبيت كل ما قبل 1/1/${_year + 1}'),
              subtitle: const Text('موصى به: يمنع تعديل سنة مقفلة'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إقفال')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.close(_year, lockAfter: lockAfter);
      if (mounted) showOk(context, 'أُقفلت السنة $_year');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopen(int year) async {
    final ok = await confirmDialog(
        context, 'إعادة فتح $year', 'سيُحذف قيد الإقفال. يمكنك إعادة الإقفال بعد التصحيح.', color: ErpColors.orange);
    if (!ok) return;
    try {
      await _svc.reopen(year);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final net = FiscalCloseService.netProfit(_preview);
    final closed = _closings.any((c) => c['year'] == _year);
    final years = [for (var y = DateTime.now().year - 1; y >= DateTime.now().year - 10; y--) y];
    return ErpPage(
      title: 'تثبيت الإدخالات وإقفال السنة',
      subtitle: 'حماية الفترات المُراجَعة وترحيل الأرباح',
      icon: Icons.lock_clock_rounded,
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ErpSection(
          title: 'تثبيت الإدخالات',
          icon: Icons.lock_rounded,
          color: _lock == null ? ErpColors.muted : ErpColors.green,
          child: Row(children: [
            Icon(_lock == null ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 42, color: _lock == null ? ErpColors.muted : ErpColors.green),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _lock == null ? 'لا يوجد تثبيت — كل الفترات قابلة للتعديل' : 'مثبّت: كل ما قبل ${fmtDate(_lock!)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.icon(onPressed: _setLock, icon: const Icon(Icons.edit_calendar), label: const Text('تحديد تاريخ')),
            if (_lock != null) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: _clearLock, child: const Text('إلغاء التثبيت')),
            ],
          ]),
        ),
        ErpSection(
          title: 'إقفال السنة المالية',
          icon: Icons.event_available_rounded,
          color: ErpColors.purple,
          trailing: DropdownButton<int>(
            value: _year,
            items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (v) {
              if (v == null) return;
              _year = v;
              _load();
            },
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              StatCard(
                  label: net >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                  value: fmtMoney(net.abs()),
                  icon: net >= 0 ? Icons.trending_up : Icons.trending_down,
                  color: net >= 0 ? ErpColors.green : ErpColors.red),
              StatCard(label: 'حسابات ستُقفل', value: '${_preview.length}', icon: Icons.list_alt, color: ErpColors.blue),
            ]),
            const SizedBox(height: 10),
            if (_preview.isNotEmpty)
              SimpleTable(
                headers: const ['الرمز', 'الحساب', 'النوع', 'الرصيد'],
                numericColumns: const {3},
                rows: [
                  for (final l in _preview) [l.account.code, l.account.name, l.account.typeLabel, fmtMoney(l.balance)],
                ],
              ),
            const SizedBox(height: 10),
            if (closed)
              const StatusBadge('هذه السنة مقفلة', color: ErpColors.green)
            else
              PrimaryButton(
                  label: 'إقفال $_year',
                  icon: Icons.lock_rounded,
                  color: ErpColors.purple,
                  busy: _busy,
                  onPressed: _preview.isEmpty ? null : _close),
          ]),
        ),
        ErpSection(
          title: 'السنوات المقفلة',
          icon: Icons.history_rounded,
          child: _closings.isEmpty
              ? const Text('لا توجد سنوات مقفلة', style: TextStyle(color: ErpColors.muted))
              : Column(children: [
                  for (final c in _closings)
                    ListTile(
                      leading: const Icon(Icons.verified_rounded, color: ErpColors.green),
                      title: Text('${c['year']} — ${d0(c['net_profit']) >= 0 ? 'ربح' : 'خسارة'} ${fmtMoney(d0(c['net_profit']).abs())}'),
                      subtitle: (_drift[c['year']] ?? 0).abs() > 0.5
                          ? Text('⚠ تغيّرت أرصدتها بعد الإقفال بمقدار ${fmtMoney(_drift[c['year']]!)} — أعد فتحها وأقفلها مجدداً',
                              style: const TextStyle(color: ErpColors.red))
                          : Text('بواسطة ${c['created_by'] ?? ''} • ${fmtDate(parseDate(c['created_at']))}'),
                      trailing: TextButton(onPressed: () => _reopen(c['year'] as int), child: const Text('إعادة فتح')),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ إعادة تقييم العملة ═══════════════════════════

class FxRevaluationScreen extends StatefulWidget {
  const FxRevaluationScreen({super.key});
  @override
  State<FxRevaluationScreen> createState() => _FxRevaluationScreenState();
}

class _FxRevaluationScreenState extends State<FxRevaluationScreen> {
  final _svc = FxRevaluationService();
  DateTime _date = DateTime.now();
  double _rate = 0;
  List<FxRevalRow> _rows = const [];
  List<Map<String, Object?>> _hist = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await erpDb();
      final r = await CurrencyService.rateAt(db, 'USD', _date);
      final rows = await _svc.preview(_date, rate: r);
      final h = await _svc.history();
      if (!mounted) return;
      setState(() {
        _rate = r;
        _rows = rows;
        _hist = h;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _post() async {
    if (!await PeriodLock.guard(context, _date)) return;
    if (!mounted) return;
    final total = _rows.fold<double>(0, (s, r) => s + r.diff);
    final ok = await confirmDialog(
      context,
      'قيد فروقات العملة',
      'سيُسجَّل قيد بتاريخ ${fmtDate(_date)}: ${total >= 0 ? 'خسارة' : 'ربح'} فروقات ${fmtMoney(total.abs())} دينار.\n'
          'أرصدة الموردين بالدولار لا تتغير — فقط قيمتها بالدينار في الدفاتر.',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _svc.post(_date, rate: _rate);
      if (mounted) showOk(context, 'سُجِّل قيد إعادة التقييم');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0, (s, r) => s + r.diff);
    return ErpPage(
      title: 'إعادة تقييم العملة',
      subtitle: 'تقييم ذمم الموردين بالدولار بسعر الصرف الحالي',
      icon: Icons.currency_exchange_rounded,
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'سعر الدولار', value: fmtMoney(_rate), icon: Icons.attach_money, color: ErpColors.green),
        StatCard(label: 'موردون متأثرون', value: '${_rows.length}', icon: Icons.people_outline, color: ErpColors.blue),
        StatCard(
            label: total >= 0 ? 'خسارة فروقات' : 'ربح فروقات',
            value: fmtMoney(total.abs()),
            icon: Icons.swap_vert,
            color: total >= 0 ? ErpColors.red : ErpColors.green),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        ErpSection(
          title: 'التاريخ',
          icon: Icons.event,
          child: Row(children: [
            DateButton(label: 'بتاريخ', value: _date, onChanged: (d) {
              _date = d;
              _load();
            }),
            const Spacer(),
            PrimaryButton(
                label: 'تسجيل القيد', icon: Icons.done_all, busy: _busy, onPressed: _rows.isEmpty ? null : _post),
          ]),
        ),
        ErpSection(
          title: 'الموردون',
          icon: Icons.table_chart_outlined,
          child: _rows.isEmpty
              ? const Text('لا توجد فروقات — كل الأرصدة مقيّمة بالسعر الحالي', style: TextStyle(color: ErpColors.muted))
              : SimpleTable(
                  headers: const ['المورد', 'الرصيد \$', 'القيمة الدفترية', 'القيمة بالسعر الحالي', 'الفرق'],
                  numericColumns: const {1, 2, 3, 4},
                  rows: [
                    for (final r in _rows)
                      [r.name, fmtMoney(r.usd), fmtMoney(r.bookIqd), fmtMoney(r.targetIqd), fmtMoney(r.diff)],
                  ],
                  footer: ['الإجمالي', '', '', '', fmtMoney(total)],
                ),
        ),
        ErpSection(
          title: 'قيود سابقة',
          icon: Icons.history,
          child: _hist.isEmpty
              ? const Text('لا يوجد', style: TextStyle(color: ErpColors.muted))
              : Column(children: [
                  for (final h in _hist)
                    ListTile(
                      dense: true,
                      title: Text('قيد #${h['entry_number']} — ${fmtDate(parseDate(h['entry_date']))}'),
                      subtitle: Text('المجموع ${fmtMoney(d0(h['total']))}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: ErpColors.red),
                        onPressed: () async {
                          final ok = await confirmDialog(context, 'حذف القيد', 'حذف قيد إعادة التقييم هذا؟',
                              color: ErpColors.red);
                          if (!ok) return;
                          try {
                            await _svc.deleteEntry(h['source_id'] as int);
                            _load();
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        },
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════ الحسابات النوعية ═══════════════════════════

class AccountGroupsScreen extends StatefulWidget {
  const AccountGroupsScreen({super.key});
  @override
  State<AccountGroupsScreen> createState() => _AccountGroupsScreenState();
}

class _AccountGroupsScreenState extends State<AccountGroupsScreen> {
  final _svc = AccountGroupsService();
  List<Map<String, Object?>> _groups = const [];
  int? _sel;
  DateTime _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to = DateTime.now();
  List<Map<String, Object?>> _report = const [];
  List<Account> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await _svc.groups();
    if (!mounted) return;
    setState(() => _groups = g);
    if (_sel == null && g.isNotEmpty) _sel = g.first['id'] as int;
    await _loadGroup();
  }

  Future<void> _loadGroup() async {
    if (_sel == null) return;
    final ids = await _svc.members(_sel!);
    final all = await Ledger().allAccounts();
    final rep = await _svc.report(_sel!, _from, _to);
    if (!mounted) return;
    setState(() {
      _members = all.where((a) => ids.contains(a.id)).toList();
      _report = rep;
    });
  }

  Future<void> _newGroup() async {
    final name = await askText(context, 'مجموعة حسابات جديدة', label: 'الاسم (مثل: مصاريف السيارات)');
    if (name == null) return;
    try {
      _sel = await _svc.save(name: name);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _addMember() async {
    if (_sel == null) return;
    final a = await Pickers.account(context, excludeControl: false);
    if (a == null) return;
    final ids = [..._members.map((m) => m.id), a.id];
    await _svc.setMembers(_sel!, ids);
    _loadGroup();
  }

  Future<void> _removeMember(Account a) async {
    await _svc.setMembers(_sel!, _members.where((m) => m.id != a.id).map((m) => m.id).toList());
    _loadGroup();
  }

  @override
  Widget build(BuildContext context) {
    final totalDr = _report.fold<double>(0, (s, r) => s + d0(r['debit']));
    final totalCr = _report.fold<double>(0, (s, r) => s + d0(r['credit']));
    final g = _groups.where((x) => x['id'] == _sel).toList();
    final title = g.isEmpty ? 'الحسابات النوعية' : '${g.first['name']}';
    List<List<String>> rows() => [
          for (final r in _report)
            [
              '${r['code']}',
              '${r['name']}',
              fmtMoney(d0(r['opening'])),
              fmtMoney(d0(r['debit'])),
              fmtMoney(d0(r['credit'])),
              fmtMoney(d0(r['closing'])),
            ],
        ];
    return ErpPage(
      title: 'الحسابات النوعية',
      subtitle: 'جمّع حسابات من فروع مختلفة في تقرير واحد',
      icon: Icons.workspaces_rounded,
      actions: [
        ...exportActions(context,
            title: title,
            headers: () => ['الرمز', 'الحساب', 'أول المدة', 'مدين', 'دائن', 'الرصيد'],
            rows: rows,
            subtitle: () => '${fmtDate(_from)} — ${fmtDate(_to)}'),
        IconButton(onPressed: _newGroup, icon: const Icon(Icons.add, color: Colors.white), tooltip: 'مجموعة جديدة'),
      ],
      headerExtra: SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final x in _groups)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text('${x['name']} (${x['n']})'),
                selected: _sel == x['id'],
                onSelected: (_) {
                  _sel = x['id'] as int;
                  _loadGroup();
                  setState(() {});
                },
              ),
            ),
        ]),
      ),
      body: _groups.isEmpty
          ? const EmptyState('أنشئ مجموعة حسابات من زر + في الأعلى', icon: Icons.workspaces_outline)
          : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              ErpSection(
                title: 'حسابات المجموعة',
                icon: Icons.account_tree_outlined,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton.icon(onPressed: _addMember, icon: const Icon(Icons.add), label: const Text('إضافة حساب')),
                  IconButton(
                    tooltip: 'حذف المجموعة',
                    icon: const Icon(Icons.delete_outline, color: ErpColors.red),
                    onPressed: () async {
                      final ok = await confirmDialog(context, 'حذف المجموعة', 'حذف «$title»؟ (الحسابات نفسها لا تتأثر)',
                          color: ErpColors.red);
                      if (!ok) return;
                      await _svc.delete(_sel!);
                      _sel = null;
                      _load();
                    },
                  ),
                ]),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in _members)
                    InputChip(label: Text('${m.code} ${m.name}'), onDeleted: () => _removeMember(m)),
                  if (_members.isEmpty) const Text('لا توجد حسابات', style: TextStyle(color: ErpColors.muted)),
                ]),
              ),
              ErpSection(
                title: 'التقرير',
                icon: Icons.analytics_outlined,
                trailing: Wrap(spacing: 8, children: [
                  DateButton(label: 'من', value: _from, onChanged: (d) {
                    _from = d;
                    _loadGroup();
                  }),
                  DateButton(label: 'إلى', value: _to, onChanged: (d) {
                    _to = d;
                    _loadGroup();
                  }),
                ]),
                child: SimpleTable(
                  headers: const ['الرمز', 'الحساب', 'أول المدة', 'مدين', 'دائن', 'الرصيد'],
                  numericColumns: const {2, 3, 4, 5},
                  rows: rows(),
                  footer: ['', 'الإجمالي', '', fmtMoney(totalDr), fmtMoney(totalCr), ''],
                ),
              ),
            ]),
    );
  }
}

// ═══════════════════════════ الملاحظات والحاسبة ═══════════════════════════

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _svc = ErpNotesService();
  List<Map<String, Object?>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _svc.list();
    if (mounted) setState(() => _rows = r);
  }

  Future<void> _edit([Map<String, Object?>? n]) async {
    final title = TextEditingController(text: '${n?['title'] ?? ''}');
    final body = TextEditingController(text: '${n?['body'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == null ? 'ملاحظة جديدة' : 'تعديل الملاحظة'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextBox(controller: title, label: 'العنوان'),
            const SizedBox(height: 8),
            TextBox(controller: body, label: 'النص', maxLines: 8),
          ]),
        ),
        actions: [
          if (n != null)
            TextButton(
              onPressed: () async {
                await _svc.delete(n['id'] as int);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('حذف', style: TextStyle(color: ErpColors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              await _svc.save(id: n?['id'] as int?, title: title.text, body: body.text);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFFFFF8E1), Color(0xFFE3F2FD), Color(0xFFE8F5E9), Color(0xFFFCE4EC), Color(0xFFEDE7F6)];
    return ErpPage(
      title: 'الملاحظات',
      subtitle: 'مذكرات سريعة للمحل',
      icon: Icons.sticky_note_2_rounded,
      actions: [
        IconButton(
          tooltip: 'الحاسبة',
          icon: const Icon(Icons.calculate_rounded, color: Colors.white),
          onPressed: () => showCalculator(context),
        ),
      ],
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: _rows.isEmpty
          ? const EmptyState('لا توجد ملاحظات', icon: Icons.sticky_note_2_outlined)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280, mainAxisExtent: 180, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final n = _rows[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _edit(n),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      Expanded(
                          child: Text('${n['body'] ?? ''}', overflow: TextOverflow.fade, style: const TextStyle(height: 1.4))),
                      Text(fmtDate(parseDate(n['updated_at'])), style: const TextStyle(fontSize: 11, color: ErpColors.muted)),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

/// حاسبة بسيطة (مثل «الحاسبة» في الإداري): + − × ÷ ٪ مع سجل.
Future<void> showCalculator(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _CalculatorDialog());

class _CalculatorDialog extends StatefulWidget {
  const _CalculatorDialog();
  @override
  State<_CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<_CalculatorDialog> {
  String _display = '0';
  double? _acc;
  String? _op;
  bool _fresh = true;
  final _tape = <String>[];

  double get _cur => double.tryParse(_display) ?? 0;

  String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
    return v.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  void _digit(String d) => setState(() {
        if (_fresh || _display == '0') {
          _display = d == '.' ? '0.' : d;
          _fresh = false;
        } else {
          if (d == '.' && _display.contains('.')) return;
          _display += d;
        }
      });

  double _apply(double a, String op, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? double.nan : a / b;
    }
    return b;
  }

  void _setOp(String op) => setState(() {
        if (_acc != null && _op != null && !_fresh) {
          _acc = _apply(_acc!, _op!, _cur);
          _display = _fmt(_acc!);
        } else {
          _acc = _cur;
        }
        _op = op;
        _fresh = true;
      });

  void _equals() => setState(() {
        if (_acc == null || _op == null) return;
        final r = _apply(_acc!, _op!, _cur);
        _tape.insert(0, '${_fmt(_acc!)} $_op ${_fmt(_cur)} = ${r.isNaN ? 'خطأ' : _fmt(r)}');
        _display = r.isNaN ? '0' : _fmt(r);
        _acc = null;
        _op = null;
        _fresh = true;
      });

  void _percent() => setState(() {
        if (_acc != null) {
          _display = _fmt(_acc! * _cur / 100);
        } else {
          _display = _fmt(_cur / 100);
        }
      });

  @override
  Widget build(BuildContext context) {
    Widget btn(String t, {Color? color, VoidCallback? onTap, int flex = 1}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Material(
              color: color ?? const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap ?? () => _digit(t),
                child: SizedBox(
                  height: 54,
                  child: Center(
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: color == null ? ErpColors.text : Colors.white)),
                  ),
                ),
              ),
            ),
          ),
        );
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [ErpColors.navy, ErpColors.blue]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_op == null ? '' : '${_fmt(_acc ?? 0)} $_op', style: const TextStyle(color: Colors.white70)),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(_display,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(children: [
                Row(children: [
                  btn('C', color: ErpColors.red, onTap: () => setState(() {
                        _display = '0';
                        _acc = null;
                        _op = null;
                        _fresh = true;
                      })),
                  btn('⌫', color: ErpColors.muted, onTap: () => setState(() {
                        _display = _display.length <= 1 ? '0' : _display.substring(0, _display.length - 1);
                      })),
                  btn('%', color: ErpColors.purple, onTap: _percent),
                  btn('÷', color: ErpColors.orange, onTap: () => _setOp('÷')),
                ]),
                Row(children: [btn('7'), btn('8'), btn('9'), btn('×', color: ErpColors.orange, onTap: () => _setOp('×'))]),
                Row(children: [btn('4'), btn('5'), btn('6'), btn('−', color: ErpColors.orange, onTap: () => _setOp('−'))]),
                Row(children: [btn('1'), btn('2'), btn('3'), btn('+', color: ErpColors.orange, onTap: () => _setOp('+'))]),
                Row(children: [
                  btn('0', flex: 2),
                  btn('.'),
                  btn('=', color: ErpColors.green, onTap: _equals),
                ]),
              ]),
            ),
            if (_tape.isNotEmpty) ...[
              const Divider(),
              SizedBox(
                height: 90,
                child: ListView(children: [
                  for (final t in _tape)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(t, style: const TextStyle(color: ErpColors.muted)),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════ مركز المحاسبة المتقدمة ═══════════════════════════

class AccountingPlusHubScreen extends StatelessWidget {
  const AccountingPlusHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return ErpPage(
      title: 'المحاسبة المتقدمة',
      subtitle: 'عملات • سندات مركّبة • قوالب • إقفال • فروقات صرف • حسابات نوعية',
      icon: Icons.account_balance_rounded,
      body: HubGrid(tiles: [
        HubTile('العملات وأسعار الصرف', Icons.currency_exchange_rounded, ErpColors.green, () => go(const CurrenciesScreen()),
            subtitle: 'سعر لكل تاريخ', permission: AppPermissions.currencies),
        HubTile('سند قيد مركّب', Icons.account_tree_rounded, ErpColors.navy, () => go(const CompoundVouchersScreen()),
            subtitle: 'عدة حسابات وعملات', permission: AppPermissions.accountingPost),
        HubTile('قوالب السندات', Icons.bookmarks_rounded, ErpColors.blue, () => go(const VoucherTemplatesScreen()),
            subtitle: 'سندات متكررة بنقرة', permission: AppPermissions.accountingPost),
        HubTile('تثبيت وإقفال السنة', Icons.lock_clock_rounded, ErpColors.purple, () => go(const PeriodCloseScreen()),
            subtitle: 'حماية الفترات', permission: AppPermissions.periodClose),
        HubTile('إعادة تقييم العملة', Icons.swap_horiz_rounded, ErpColors.orange, () => go(const FxRevaluationScreen()),
            subtitle: 'ذمم الموردين بالدولار', permission: AppPermissions.periodClose),
        HubTile('الحسابات النوعية', Icons.workspaces_rounded, ErpColors.cyan, () => go(const AccountGroupsScreen()),
            permission: AppPermissions.accounting),
        HubTile('الملاحظات', Icons.sticky_note_2_rounded, ErpColors.gold, () => go(const NotesScreen())),
        HubTile('الحاسبة', Icons.calculate_rounded, ErpColors.muted, () => showCalculator(context)),
      ]),
    );
  }
}
