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

  @override
  Widget build(BuildContext context) {
    final q = _search.trim();
    final rows = q.isEmpty
        ? _rows
        : _rows.where((r) => r.account.name.contains(q) || r.account.code.startsWith(q)).toList();
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('شجرة الحسابات', actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'بحث بالاسم أو الرمز',
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              final a = r.account;
              return Container(
                color: a.isGroup ? AccColors.navy.withOpacity(0.04) : Colors.white,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.only(right: 12.0 + r.depth * 22, left: 8),
                  leading: Icon(
                    a.isGroup ? Icons.folder : Icons.description_outlined,
                    color: a.isActive ? (a.isGroup ? AccColors.navy : AccColors.blue) : Colors.grey,
                  ),
                  title: Text(
                    '${a.code}  ${a.name}',
                    style: TextStyle(
                      fontWeight: a.isGroup ? FontWeight.bold : FontWeight.normal,
                      color: a.isActive ? AccColors.text : Colors.grey,
                      decoration: a.isActive ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  subtitle: Text([
                    a.typeLabel,
                    if (a.isControl) 'حساب مراقبة',
                    if (a.systemKey != null) 'حساب نظامي',
                  ].join(' • ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    MoneyText(r.natureBalance, bold: a.isGroup),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'add':
                            _addChild(a);
                            break;
                          case 'edit':
                            _rename(a);
                            break;
                          case 'toggle':
                            _toggleActive(a);
                            break;
                          case 'ledger':
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => AccountStatementScreen(initialAccountId: a.id)));
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        if (a.isGroup)
                          const PopupMenuItem(value: 'add', child: Text('إضافة حساب فرعي')),
                        if (!a.isGroup)
                          const PopupMenuItem(value: 'ledger', child: Text('كشف الحساب')),
                        const PopupMenuItem(value: 'edit', child: Text('تعديل الاسم')),
                        PopupMenuItem(
                            value: 'toggle', child: Text(a.isActive ? 'إيقاف الحساب' : 'تفعيل الحساب')),
                      ],
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
