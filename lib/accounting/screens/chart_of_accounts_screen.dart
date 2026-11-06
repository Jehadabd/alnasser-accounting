// lib/accounting/screens/chart_of_accounts_screen.dart
//
// 🌳 شجرة الحسابات: عرض هرمي مع الأرصدة، إضافة حساب فرعي، تعديل الاسم، إيقاف.

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../accounting_reports.dart';
import '../ledger.dart';
import 'acc_ui.dart';
import 'account_statement_screen.dart';

class ChartOfAccountsScreen extends StatefulWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  State<ChartOfAccountsScreen> createState() => _ChartOfAccountsScreenState();
}

class _ChartOfAccountsScreenState extends State<ChartOfAccountsScreen> {
  final _ledger = Ledger();
  List<AccountBalanceRow> _rows = const [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await AccountingReports()
          .trialBalance(to: DateTime.now(), hideEmpty: false);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addChild(Account parent) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final code = TextEditingController(text: await _ledger.suggestChildCode(parent));
    final name = TextEditingController();
    var isGroup = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('حساب جديد تحت «${parent.name}»'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: code, decoration: const InputDecoration(labelText: 'الرمز')),
              const SizedBox(height: 10),
              TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم الحساب')),
              CheckboxListTile(
                value: isGroup,
                onChanged: (v) => setD(() => isGroup = v ?? false),
                title: const Text('حساب رئيسي (تتفرع منه حسابات)'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await _ledger.createAccount(
          code: code.text.trim(), name: name.text, parentId: parent.id, isGroup: isGroup);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rename(Account a) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final name = TextEditingController(text: a.name);
    final notes = TextEditingController(text: a.notes ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل ${a.code}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 10),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _ledger.renameAccount(a.id, name.text, notes: notes.text);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleActive(Account a) async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    try {
      await _ledger.setAccountActive(a.id, !a.isActive);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ─────────────────────────── العرض المبسّط ───────────────────────────
  // خمس مجموعات بلغة المحل، تحت كل منها حساباتها شجرةً تُفتح وتُطوى. الرموز والحسابات
  // الفارغة مخفية افتراضياً (زرّان لإظهارها). الضغط على حساب يفتح كشفه.

  String _type = 'asset';
  bool _showEmpty = false;
  bool _showCodes = false;
  final Set<int> _open = {};

  static const _types = <(String, String, String, IconData, Color)>[
    ('asset', 'ما تملكه', 'النقد والبنك، ديون العملاء لك، المخزون', Icons.account_balance_wallet_rounded, Color(0xFF0F766E)),
    ('liability', 'ما عليك', 'ديون الموردين وما تستحقه للغير', Icons.receipt_long_rounded, Color(0xFFB91C1C)),
    ('equity', 'رأس المال', 'ما وضعه المالك + الأرباح المتراكمة', Icons.savings_rounded, Color(0xFF6B21A8)),
    ('revenue', 'الإيرادات', 'المبيعات وكل دخل للمحل', Icons.trending_up_rounded, Color(0xFF047857)),
    ('expense', 'المصاريف', 'تكلفة البضاعة، رواتب، إيجار، كهرباء...', Icons.trending_down_rounded, Color(0xFFC2410C)),
  ];

  bool _hasValue(AccountBalanceRow r) => r.natureBalance.abs() > 0.004 || r.totalDebit.abs() > 0.004;

  Map<int?, List<AccountBalanceRow>> _childrenMap(List<AccountBalanceRow> rows) {
    final m = <int?, List<AccountBalanceRow>>{};
    for (final r in rows) {
      (m[r.account.parentId] ??= []).add(r);
    }
    return m;
  }

  /// الحساب يظهر إن كان فيه رصيد/حركة، أو فيه فرع ظاهر، أو «إظهار الفارغة» مفعّل.
  bool _visible(AccountBalanceRow r, Map<int?, List<AccountBalanceRow>> kids) {
    if (_showEmpty || _hasValue(r)) return true;
    for (final c in kids[r.account.id] ?? const <AccountBalanceRow>[]) {
      if (_visible(c, kids)) return true;
    }
    return false;
  }

  double _typeTotal(String type) {
    var t = 0.0;
    for (final r in _rows) {
      if (r.account.type == type && r.depth == 0) t += r.natureBalance;
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim();
    final kids = _childrenMap(_rows);
    final byId = {for (final r in _rows) r.account.id: r};
    final meta = _types.firstWhere((t) => t.$1 == _type);
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('شجرة الحسابات', actions: [
        IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        // 🔎 بحث + خيارات العرض
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'ابحث عن حساب بالاسم',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AccColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AccColors.border)),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(width: 8),
            _toggle('الفارغة', Icons.visibility_rounded, _showEmpty, () => setState(() => _showEmpty = !_showEmpty)),
            const SizedBox(width: 6),
            _toggle('الرموز', Icons.tag_rounded, _showCodes, () => setState(() => _showCodes = !_showCodes)),
          ]),
        ),
        if (q.isEmpty) _typeBar(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: q.isNotEmpty
              ? _searchList(q, byId)
              : _tree(kids, meta),
        ),
      ]),
    );
  }

  Widget _toggle(String label, IconData icon, bool on, VoidCallback onTap) => Tooltip(
        message: on ? 'إخفاء $label' : 'إظهار $label',
        child: Material(
          color: on ? AccColors.navy : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: BorderSide(color: on ? AccColors.navy : AccColors.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 17, color: on ? Colors.white : AccColors.muted),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : AccColors.text)),
              ]),
            ),
          ),
        ),
      );

  /// المجموعات الخمس بطاقاتٍ أفقية (الرقم = رصيد المجموعة الآن)
  Widget _typeBar() => SizedBox(
        height: 104,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          children: [
            for (final t in _types) ...[
              _typeCard(t),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _typeCard((String, String, String, IconData, Color) t) {
    final sel = _type == t.$1;
    return SizedBox(
      width: 176,
      child: Material(
        color: sel ? t.$5 : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: BorderSide(color: sel ? t.$5 : AccColors.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _type = t.$1),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(t.$4, size: 19, color: sel ? Colors.white : t.$5),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(t.$2,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: sel ? Colors.white : AccColors.text)),
                ),
              ]),
              const Spacer(),
              Text(fmtMoney(_typeTotal(t.$1)),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: sel ? Colors.white : t.$5)),
              Text(t.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: sel ? Colors.white70 : AccColors.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tree(Map<int?, List<AccountBalanceRow>> kids, (String, String, String, IconData, Color) meta) {
    final roots = [
      for (final r in _rows)
        if (r.account.type == _type && (r.account.parentId == null || !_rows.any((x) => x.account.id == r.account.parentId)))
          r,
    ];
    final items = <Widget>[];
    void add(AccountBalanceRow r, int level) {
      if (!_visible(r, kids)) return;
      final children = (kids[r.account.id] ?? const <AccountBalanceRow>[]).where((c) => _visible(c, kids)).toList();
      final isOpen = _open.contains(r.account.id) || level == 0;
      items.add(_accountRow(r, level, meta.$5, hasChildren: children.isNotEmpty, isOpen: isOpen));
      if (isOpen) {
        for (final c in children) {
          add(c, level + 1);
        }
      }
    }

    for (final r in roots) {
      add(r, 0);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: meta.$5.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.lightbulb_outline_rounded, size: 18, color: meta.$5),
            const SizedBox(width: 8),
            Expanded(
              child: Text('«${meta.$2}»: ${meta.$3}. اضغط مجموعة لفتحها، واضغط حساباً لرؤية كشفه.',
                  style: const TextStyle(fontSize: 12.5, height: 1.5, color: AccColors.text)),
            ),
          ]),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: Text('لا حسابات فيها أرصدة هنا — اضغط «الفارغة» لرؤية كل الحسابات',
                  textAlign: TextAlign.center, style: TextStyle(color: AccColors.muted)),
            ),
          ),
        ...items,
      ],
    );
  }

  Widget _accountRow(AccountBalanceRow r, int level, Color color,
      {required bool hasChildren, required bool isOpen, String? path}) {
    final a = r.account;
    final group = a.isGroup || hasChildren;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: level * 18.0, bottom: 6),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: level == 0 ? color.withValues(alpha: 0.35) : AccColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (group && level > 0) {
              setState(() => isOpen ? _open.remove(a.id) : _open.add(a.id));
            } else if (!group) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AccountStatementScreen(initialAccountId: a.id)));
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
            child: Row(children: [
              Icon(
                group
                    ? (level == 0 ? Icons.folder_special_rounded : (isOpen ? Icons.folder_open_rounded : Icons.folder_rounded))
                    : Icons.description_outlined,
                size: 20,
                color: a.isActive ? (group ? color : AccColors.blue) : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        _showCodes ? '${a.code}  ${a.name}' : a.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: group ? FontWeight.w800 : FontWeight.w600,
                          fontSize: level == 0 ? 14.5 : 13.5,
                          color: a.isActive ? AccColors.text : Colors.grey,
                          decoration: a.isActive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (a.systemKey != null || a.isControl) ...[
                      const SizedBox(width: 4),
                      const Tooltip(
                        message: 'يديره البرنامج تلقائياً من الفواتير والسندات',
                        child: Icon(Icons.lock_outline_rounded, size: 14, color: AccColors.muted),
                      ),
                    ],
                  ]),
                  if (path != null)
                    Text(path, style: const TextStyle(fontSize: 11, color: AccColors.muted), overflow: TextOverflow.ellipsis),
                ]),
              ),
              MoneyText(r.natureBalance, bold: group),
              if (group && level > 0)
                Icon(isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AccColors.muted),
              PopupMenuButton<String>(
                tooltip: 'خيارات',
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: AccColors.muted),
                onSelected: (v) {
                  switch (v) {
                    case 'add':
                      _addChild(a);
                    case 'edit':
                      _rename(a);
                    case 'toggle':
                      _toggleActive(a);
                    case 'ledger':
                      Navigator.push(
                          context, MaterialPageRoute(builder: (_) => AccountStatementScreen(initialAccountId: a.id)));
                  }
                },
                itemBuilder: (_) => [
                  if (a.isGroup) const PopupMenuItem(value: 'add', child: Text('إضافة حساب فرعي')),
                  if (!a.isGroup) const PopupMenuItem(value: 'ledger', child: Text('كشف الحساب')),
                  const PopupMenuItem(value: 'edit', child: Text('تعديل الاسم')),
                  PopupMenuItem(value: 'toggle', child: Text(a.isActive ? 'إيقاف الحساب' : 'تفعيل الحساب')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// نتائج البحث: قائمة مسطّحة، وتحت كل حساب مساره (أين يقع في الشجرة)
  Widget _searchList(String q, Map<int, AccountBalanceRow> byId) {
    final hits = _rows.where((r) => r.account.name.contains(q) || r.account.code.startsWith(q)).toList();
    String pathOf(Account a) {
      final parts = <String>[];
      var p = a.parentId;
      while (p != null && byId[p] != null) {
        parts.insert(0, byId[p]!.account.name);
        p = byId[p]!.account.parentId;
      }
      final t = _types.where((x) => x.$1 == a.type).map((x) => x.$2).firstOrNull;
      return [if (t != null) t, ...parts].join(' ← ');
    }

    if (hits.isEmpty) {
      return const Center(child: Text('لا حساب بهذا الاسم', style: TextStyle(color: AccColors.muted)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      children: [
        for (final r in hits)
          _accountRow(r, 0, _types.firstWhere((t) => t.$1 == r.account.type, orElse: () => _types.first).$5,
              hasChildren: false, isOpen: false, path: pathOf(r.account)),
      ],
    );
  }
}
