// lib/erp/control/control_screens.dart
//
// 🛡️ شاشات الرقابة:
//   • ControlHubScreen       — مركز «الرقابة والأدوات المالية».
//   • CashCountsScreen       — سجل عدّ الدرج: العجز والزيادة لكل محاسب، ومراجعة المدير.
//   • ReducingEditsScreen    — فواتير أُنقصت بعد طباعتها (ومن عدّلها).
//   • ApprovalsScreen        — سجل موافقات المدير وإعداداتها.
//   • LandedCostsScreen      — سجل مصاريف الشحن المحمّلة على كلفة المواد.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney, fmtDate, showError, showOk, PeriodBar;
import '../erp_common.dart';
import '../erp_ui.dart';
import 'approval_gate.dart';
import 'bank_rec_screen.dart';
import 'branch_profit_screen.dart';
import 'break_even_screen.dart';
import 'cash_count_service.dart';
import 'control_common.dart';
import 'fixed_assets_screens.dart';
import 'landed_cost_service.dart';
import 'print_audit.dart';
import 'purchase_suggestions_screen.dart';

DateTime _monthStart() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, 1);
}

String _dt(DateTime d) =>
    '${fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void _go(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

// ════════════════════════════════════════════════════════════════════
// المركز
// ════════════════════════════════════════════════════════════════════

class ControlHubScreen extends StatefulWidget {
  const ControlHubScreen({super.key});
  @override
  State<ControlHubScreen> createState() => _ControlHubScreenState();
}

class _ControlHubScreenState extends State<ControlHubScreen> {
  int _pendingCounts = 0;

  @override
  void initState() {
    super.initState();
    CashCountService.pendingCount().then((n) {
      if (mounted) setState(() => _pendingCounts = n);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'الرقابة والأدوات المالية',
      subtitle: 'حماية النقد، الكلفة الحقيقية، وقرارات صاحب العمل',
      icon: Icons.shield_rounded,
      body: HubSections(sections: [
          HubSection('حماية النقد', [
            HubTile('سجل عدّ الدرج', Icons.point_of_sale_rounded, ErpColors.green, () => _go(context, const CashCountsScreen()),
                subtitle: _pendingCounts > 0 ? '$_pendingCounts بانتظار المراجعة' : 'العجز والزيادة لكل محاسب'),
            HubTile('فواتير أُنقصت بعد طباعتها', Icons.print_disabled_rounded, ErpColors.red,
                () => _go(context, const ReducingEditsScreen()),
                subtitle: 'تعديلات خفّضت فاتورة بعد تسليمها'),
            HubTile('موافقات المدير', Icons.admin_panel_settings_rounded, ErpColors.orange,
                () => _go(context, const ApprovalsScreen()),
                subtitle: 'تاريخ سابق، تحت الكلفة، خصم كبير'),
          ]),
          HubSection('قرارات صاحب العمل', [
            HubTile('نقطة التعادل اليومية', Icons.flag_rounded, ErpColors.navy, () => _go(context, const BreakEvenScreen()),
                subtitle: 'كم يجب أن تبيع يومياً لتغطي مصاريفك'),
            HubTile('اقتراح طلبية شراء', Icons.add_shopping_cart_rounded, ErpColors.blue,
                () => _go(context, const PurchaseSuggestionsScreen()),
                subtitle: 'ماذا تطلب ومن أي مورد وبأي كمية'),
            HubTile('ربحية الفروع', Icons.store_mall_directory_rounded, ErpColors.purple,
                () => _go(context, const BranchProfitScreen()),
                subtitle: 'ربح كل فرع بعد مصاريفه'),
          ]),
          HubSection('الدفاتر', [
            HubTile('الأصول الثابتة والإهلاك', Icons.domain_rounded, ErpColors.gold, () => _go(context, const FixedAssetsScreen()),
                subtitle: 'سجل الأصول وإهلاكها الشهري'),
            HubTile('مطابقة كشف البنك', Icons.account_balance_rounded, ErpColors.cyan, () => _go(context, const BankRecListScreen()),
                subtitle: 'طابق حركات البنك مع كشفه'),
            HubTile('مصاريف الشحن على الكلفة', Icons.local_shipping_rounded, ErpColors.muted,
                () => _go(context, const LandedCostsScreen()),
                subtitle: 'ما حُمّل على كلفة المواد'),
          ]),
        ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// سجل عدّ الدرج
// ════════════════════════════════════════════════════════════════════

class CashCountsScreen extends StatefulWidget {
  const CashCountsScreen({super.key});
  @override
  State<CashCountsScreen> createState() => _CashCountsScreenState();
}

class _CashCountsScreenState extends State<CashCountsScreen> {
  DateTime? _from = _monthStart();
  DateTime _to = DateTime.now();
  String? _status;
  List<CashCount> _rows = const [];
  bool _admin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    currentIsAdmin().then((a) {
      if (mounted) setState(() => _admin = a);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await CashCountService.list(from: _from, to: _to, status: _status);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  Color _color(CashCount c) => c.status == CashCountStatus.voided
      ? ErpColors.muted
      : (c.matched ? ErpColors.green : (c.isOver ? ErpColors.orange : ErpColors.red));

  Future<void> _review(CashCount c) async {
    final note = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('مراجعة عدّ ${c.no} — ${c.countedBy}'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'يوم ${fmtDate(c.day)}${c.boxName == null ? '' : ' • ${c.boxName}'}\n'
              'المتوقع ${fmtMoney(c.expected)} • المعدود ${fmtMoney(c.counted)}\n'
              '${c.matched ? 'مطابق' : (c.isOver ? 'زيادة' : 'عجز')} ${fmtMoney(c.diff.abs())}',
              style: const TextStyle(height: 1.7),
            ),
            if (!c.matched) ...[
              const SizedBox(height: 10),
              const Text(
                '«اعتماد وترحيل» يسجّل قيداً بالفرق على حساب «فروقات الصندوق» ويعدّل رصيد الصندوق في الدفتر ليطابق المعدود. '
                '«اعتماد فقط» يبقيه سجلاً بلا أي قيد.',
                style: TextStyle(fontSize: 12.5, color: ErpColors.muted, height: 1.5),
              ),
            ],
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة المراجعة (اختياري)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'void'),
            style: TextButton.styleFrom(foregroundColor: ErpColors.red),
            child: const Text('إلغاء العدّ'),
          ),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'approve'), child: const Text('اعتماد فقط')),
          if (!c.matched)
            FilledButton(onPressed: () => Navigator.pop(ctx, 'post'), child: const Text('اعتماد وترحيل الفرق')),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (r == null || !mounted) return;
    try {
      if (r == 'void') {
        final reason = await askText(context, 'سبب إلغاء العدّ', label: 'السبب');
        if (reason == null || reason.trim().isEmpty) return;
        await CashCountService.voidCount(c.id, reason);
      } else {
        await CashCountService.review(c.id, post: r == 'post', note: text);
      }
      if (mounted) showOk(context, 'تم');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _voidReviewed(CashCount c) async {
    final reason = await askText(context, 'سبب إلغاء العدّ', label: 'السبب');
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await CashCountService.voidCount(c.id, reason);
      if (mounted) showOk(context, 'أُلغي العدّ — يُحذف قيده (إن وُجد) في الترحيل التالي');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = CashCountService.summarize(_rows);
    final filters = <(String?, String)>[
      (null, 'الكل'),
      (CashCountStatus.pending, 'بانتظار المراجعة'),
      (CashCountStatus.posted, 'مرحّل'),
      (CashCountStatus.approved, 'معتمد بلا قيد'),
      (CashCountStatus.voided, 'ملغى'),
    ];
    return ErpPage(
      title: 'سجل عدّ الدرج',
      subtitle: 'العجز والزيادة لكل محاسب — الحفظ من «إقفال اليوم»',
      icon: Icons.point_of_sale_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      body: Column(children: [
        PeriodBar(
            from: _from,
            to: _to,
            onChanged: (f, t) {
              _from = f;
              _to = t;
              _load();
            }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            for (final f in filters)
              ChoiceChip(
                label: Text(f.$2),
                selected: _status == f.$1,
                onSelected: (_) {
                  setState(() => _status = f.$1);
                  _load();
                },
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState('لا أعداد محفوظة في الفترة.\nاحفظ العدّ من «إقفال اليوم».', icon: Icons.point_of_sale_rounded)
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      if (summary.isNotEmpty)
                        ErpSection(
                          title: 'حسب المحاسب',
                          icon: Icons.people_alt_rounded,
                          child: SimpleTable(
                            headers: const ['المحاسب', 'الأعداد', 'مرات العجز', 'مجموع العجز', 'مرات الزيادة', 'مجموع الزيادة', 'الصافي'],
                            numericColumns: const {1, 2, 3, 4, 5, 6},
                            rows: [
                              for (final s in summary)
                                [
                                  s.user,
                                  '${s.counts}',
                                  '${s.shortCount}',
                                  fmtMoney(s.shortTotal),
                                  '${s.overCount}',
                                  fmtMoney(s.overTotal),
                                  fmtMoney(s.net),
                                ],
                            ],
                          ),
                        ),
                      ErpSection(
                        title: 'الأعداد (${_rows.length})',
                        icon: Icons.list_alt_rounded,
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        child: Column(children: [
                          for (final c in _rows)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _color(c).withValues(alpha: 0.12),
                                child: Text('${c.no}', style: TextStyle(color: _color(c), fontSize: 12)),
                              ),
                              title: Text(
                                  '${fmtDate(c.day)} — ${c.countedBy} — ${c.matched ? 'مطابق' : (c.isOver ? 'زيادة' : 'عجز')} ${fmtMoney(c.diff.abs())}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      decoration: c.status == CashCountStatus.voided ? TextDecoration.lineThrough : null)),
                              subtitle: Text([
                                'المتوقع ${fmtMoney(c.expected)} • المعدود ${fmtMoney(c.counted)}',
                                if (c.boxName != null) c.boxName!,
                                'عُدّ ${_dt(c.countedAt)}',
                                if (c.note != null) 'ملاحظة: ${c.note}',
                                if (c.reviewedBy != null) 'راجعه ${c.reviewedBy}${c.reviewNote == null ? '' : ': ${c.reviewNote}'}',
                              ].join(' • ')),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                StatusBadge(CashCountStatus.label(c.status), color: _color(c)),
                                if (_admin && c.status == CashCountStatus.pending)
                                  IconButton(
                                      tooltip: 'مراجعة', icon: const Icon(Icons.fact_check_rounded), onPressed: () => _review(c)),
                                if (_admin &&
                                    (c.status == CashCountStatus.posted || c.status == CashCountStatus.approved))
                                  IconButton(
                                      tooltip: 'إلغاء',
                                      icon: const Icon(Icons.block_rounded, color: ErpColors.red),
                                      onPressed: () => _voidReviewed(c)),
                              ]),
                            ),
                        ]),
                      ),
                    ]),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// فواتير أُنقصت بعد طباعتها
// ════════════════════════════════════════════════════════════════════

class ReducingEditsScreen extends StatefulWidget {
  const ReducingEditsScreen({super.key});
  @override
  State<ReducingEditsScreen> createState() => _ReducingEditsScreenState();
}

class _ReducingEditsScreenState extends State<ReducingEditsScreen> {
  DateTime? _from = _monthStart();
  DateTime _to = DateTime.now();
  bool _onlyAfterPrint = true;
  List<ReducingEdit> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ReducingEditsReport.load(from: _from ?? DateTime(2000), to: _to);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _onlyAfterPrint ? _rows.where((e) => e.afterPrint).toList() : _rows;
    final byUser = ReducingEditsReport.byUser(_rows);
    return ErpPage(
      title: 'فواتير أُنقصت بعد طباعتها',
      subtitle: 'تعديلات خفّضت مجموع الفاتورة أو نقدها — مع من عدّلها ومتى طُبعت',
      icon: Icons.print_disabled_rounded,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      body: Column(children: [
        PeriodBar(
            from: _from,
            to: _to,
            onChanged: (f, t) {
              _from = f;
              _to = t;
              _load();
            }),
        SwitchListTile(
          dense: true,
          title: const Text('بعد الطباعة فقط'),
          subtitle: const Text('أُطفئه لعرض كل التعديلات المُنقِصة، مطبوعة أو لا'),
          value: _onlyAfterPrint,
          onChanged: (v) => setState(() => _onlyAfterPrint = v),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(
                      'تتبّع الطباعة يبدأ من تاريخ تثبيت هذه الميزة: تعديلات الفواتير المطبوعة قبله تظهر «غير مطبوعة».',
                      style: TextStyle(fontSize: 12, color: ErpColors.muted),
                    ),
                  ),
                  if (byUser.isNotEmpty)
                    ErpSection(
                      title: 'حسب من عدّل',
                      icon: Icons.person_search_rounded,
                      child: SimpleTable(
                        headers: const ['المستخدم', 'تعديلات مُنقِصة', 'بعد الطباعة', 'مجموع النقص', 'النقص بعد الطباعة'],
                        numericColumns: const {1, 2, 3, 4},
                        rows: [
                          for (final s in byUser)
                            [s.user, '${s.edits}', '${s.afterPrint}', fmtMoney(s.drop), fmtMoney(s.dropAfterPrint)],
                        ],
                      ),
                    ),
                  if (shown.isEmpty)
                    const EmptyState('لا تعديلات مُنقِصة في الفترة', icon: Icons.verified_rounded)
                  else
                    ErpSection(
                      title: 'التعديلات (${shown.length})',
                      icon: Icons.list_alt_rounded,
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Column(children: [
                        for (final e in shown)
                          ListTile(
                            leading: Icon(e.afterPrint ? Icons.print_rounded : Icons.edit_note_rounded,
                                color: e.afterPrint ? ErpColors.red : ErpColors.orange),
                            title: Text(
                                'فاتورة ${e.invoiceNo ?? '#${e.invoiceId}'} — ${e.customer} — نقص ${fmtMoney(e.drop)}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([
                              'عدّلها ${e.editedBy} في ${_dt(e.editedAt)}',
                              'المجموع ${fmtMoney(e.totalBefore)} ← ${fmtMoney(e.totalAfter)}',
                              if ((e.cashBefore - e.cashAfter).abs() >= 0.5)
                                'النقد ${fmtMoney(e.cashBefore)} ← ${fmtMoney(e.cashAfter)}',
                              if (e.cashToCredit) 'حُوّلت من نقد إلى آجل',
                              if (e.afterPrint)
                                'طُبعت ${e.printsBefore} مرة قبله (أولها ${_dt(e.firstPrintAt!)}${e.firstPrintBy == null ? '' : ' — ${e.firstPrintBy}'})',
                              'تاريخ الفاتورة ${fmtDate(e.invoiceDate)}',
                            ].join(' • ')),
                          ),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// موافقات المدير: الإعدادات والسجل
// ════════════════════════════════════════════════════════════════════

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});
  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  DateTime? _from = _monthStart();
  DateTime _to = DateTime.now();
  ApprovalSettings? _s;
  final _pct = TextEditingController();
  List<Map<String, Object?>> _rows = const [];
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final a = await currentIsAdmin();
      final s = await ApprovalSettings.load();
      if (!mounted) return;
      setState(() {
        _admin = a;
        _s = s;
        _pct.text = s.discountPct == s.discountPct.roundToDouble() ? '${s.discountPct.round()}' : '${s.discountPct}';
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ApprovalGate.log(from: _from, to: _to);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    final s = _s;
    if (s == null) return;
    final pct = parseMoney(_pct.text) ?? 0;
    try {
      await ApprovalSettings.save(ApprovalSettings(pastDate: s.pastDate, belowCost: s.belowCost, discountPct: pct));
      if (mounted) showOk(context, 'حُفظت إعدادات الموافقات');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return ErpPage(
      title: 'موافقات المدير',
      subtitle: 'ما يحتاج كلمة سر المدير قبل الحفظ، وسجل كل طلب',
      icon: Icons.admin_panel_settings_rounded,
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (s != null)
          ErpSection(
            title: 'متى تُطلب الموافقة',
            icon: Icons.tune_rounded,
            trailing: _admin ? null : const StatusBadge('للمدير فقط', color: ErpColors.muted),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('المدير المسجّل دخوله لا يُسأل. الموظف يحتاج كلمة سر المدير على الجهاز نفسه.',
                  style: TextStyle(fontSize: 12.5, color: ErpColors.muted)),
              SwitchListTile(
                title: const Text('فاتورة بتاريخ سابق'),
                subtitle: const Text('تعديل فاتورة من يوم مضى، أو فاتورة جديدة بتاريخ رجعي'),
                value: s.pastDate,
                onChanged: !_admin
                    ? null
                    : (v) => setState(() => _s = ApprovalSettings(pastDate: v, belowCost: s.belowCost, discountPct: s.discountPct)),
              ),
              SwitchListTile(
                title: const Text('بيع تحت الكلفة'),
                subtitle: const Text('سطر سعره أقل من كلفته، ومنه الهدية المجانية'),
                value: s.belowCost,
                onChanged: !_admin
                    ? null
                    : (v) => setState(() => _s = ApprovalSettings(pastDate: s.pastDate, belowCost: v, discountPct: s.discountPct)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  const Expanded(child: Text('خصم الفاتورة أعلى من (٪) — 0 بلا قيد')),
                  SizedBox(width: 110, child: MoneyField(controller: _pct, label: '%', enabled: _admin)),
                ]),
              ),
              if (_admin)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: PrimaryButton(label: 'حفظ', icon: Icons.save_rounded, onPressed: _save),
                ),
            ]),
          ),
        PeriodBar(
            from: _from,
            to: _to,
            onChanged: (f, t) {
              _from = f;
              _to = t;
              _load();
            }),
        ErpSection(
          title: 'السجل (${_rows.length})',
          icon: Icons.history_rounded,
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: _rows.isEmpty
              ? const EmptyState('لا طلبات موافقة في الفترة', icon: Icons.verified_rounded)
              : Column(children: [
                  for (final r in _rows)
                    ListTile(
                      leading: Icon(
                        r['decision'] == 'approved' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: r['decision'] == 'approved' ? ErpColors.green : ErpColors.red,
                      ),
                      title: Text('${ApprovalRule.label('${r['rule']}')} — ${r['ref_label'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        '${r['details'] ?? ''}',
                        'طلبه ${r['requested_by'] ?? '—'}',
                        r['decision'] == 'approved' ? 'وافق ${r['decided_by'] ?? '—'}' : 'أُلغي الحفظ',
                        _dt(parseDate(r['created_at'])),
                      ].join(' • ')),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// سجل مصاريف الشحن
// ════════════════════════════════════════════════════════════════════

class LandedCostsScreen extends StatefulWidget {
  const LandedCostsScreen({super.key});
  @override
  State<LandedCostsScreen> createState() => _LandedCostsScreenState();
}

class _LandedCostsScreenState extends State<LandedCostsScreen> {
  List<Map<String, Object?>> _rows = const [];
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    currentIsAdmin().then((a) {
      if (mounted) setState(() => _admin = a);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await LandedCostService.list();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _extras(Object? json) {
    try {
      final l = jsonDecode('$json') as List;
      return l.map((e) => '${e['name']}: ${fmtMoney((e['amount'] as num).toDouble())}').join('، ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _void(Map<String, Object?> r) async {
    final ok = await confirmDialog(
        context,
        'إلغاء سجل الشحن',
        'يُحذف قيده (إن وُجد) في الترحيل التالي. كلفة المادة في بطاقتها لا تتغير — '
            'عدّلها من بطاقة المادة إن أردت.',
        ok: 'إلغاء السجل',
        color: ErpColors.red);
    if (!ok) return;
    try {
      await LandedCostService.voidRecord(r['id'] as int);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ErpPage(
      title: 'مصاريف الشحن على الكلفة',
      subtitle: 'تُضاف من «إدخال بضاعة» ← المزيد',
      icon: Icons.local_shipping_rounded,
      body: _rows.isEmpty
          ? const EmptyState('لا مصاريف شحن محمّلة بعد', icon: Icons.local_shipping_rounded)
          : ListView(padding: const EdgeInsets.all(8), children: [
              for (final r in _rows)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), side: const BorderSide(color: ErpColors.border)),
                  child: ListTile(
                    title: Text('${r['product_name'] ?? ''} — ${fmtMoney(d0(r['total_extra']))}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: r['status'] == 'void' ? TextDecoration.lineThrough : null)),
                    subtitle: Text([
                      fmtDate(parseDate(r['cost_date'])),
                      '${fmtQty(d0(r['base_qty']))} وحدة: +${fmtMoney(d0(r['per_unit']))} للوحدة '
                          '(${fmtMoney(d0(r['purchase_unit_cost']))} ← ${fmtMoney(d0(r['purchase_unit_cost']) + d0(r['per_unit']))})',
                      _extras(r['extras']),
                      LandedMode.label('${r['mode']}'),
                      if (r['status'] == 'void') 'ملغى',
                    ].where((x) => x.isNotEmpty).join(' • ')),
                    trailing: _admin && r['status'] != 'void'
                        ? IconButton(
                            tooltip: 'إلغاء',
                            icon: const Icon(Icons.block_rounded, color: ErpColors.red),
                            onPressed: () => _void(r))
                        : null,
                  ),
                ),
            ]),
    );
  }
}
