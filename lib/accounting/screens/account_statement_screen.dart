// lib/accounting/screens/account_statement_screen.dart
//
// 📄 كشف حساب (دفتر الأستاذ): أي حساب، أو عميل/مورد من حساب المراقبة.

import 'package:flutter/material.dart';

import '../accounting_reports.dart';
import '../ledger.dart';
import 'acc_ui.dart';
import 'journal_screen.dart' show sourceTypeLabels;

class AccountStatementScreen extends StatefulWidget {
  const AccountStatementScreen({super.key, this.initialAccountId, this.from, this.to});
  final int? initialAccountId;
  final DateTime? from;
  final DateTime? to;

  @override
  State<AccountStatementScreen> createState() => _AccountStatementScreenState();
}

class _AccountStatementScreenState extends State<AccountStatementScreen> {
  final _ledger = Ledger();
  List<Account> _accounts = const [];
  Account? _account;
  late DateTime? _from = widget.from ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _to = widget.to ?? DateTime.now();
  AccountStatement? _st;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ledger.postableAccounts().then((a) {
      if (!mounted) return;
      setState(() {
        _accounts = a;
        if (widget.initialAccountId != null) {
          for (final x in a) {
            if (x.id == widget.initialAccountId) _account = x;
          }
        }
      });
      if (_account != null) _load();
    });
  }

  Future<void> _load() async {
    final a = _account;
    if (a == null) return;
    setState(() => _loading = true);
    try {
      final s = await AccountingReports().accountStatement(accountId: a.id, from: _from, to: _to);
      if (mounted) setState(() => _st = s);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _st;
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('كشف حساب'),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Autocomplete<Account>(
            displayStringForOption: (a) => '${a.code} ${a.name}',
            optionsBuilder: (v) {
              final q = v.text.trim();
              if (q.isEmpty) return _accounts.take(40);
              return _accounts.where((a) => a.name.contains(q) || a.code.startsWith(q)).take(40);
            },
            onSelected: (a) {
              setState(() => _account = a);
              _load();
            },
            fieldViewBuilder: (ctx, ctrl, focus, _) {
              if (_account != null && ctrl.text.isEmpty) {
                ctrl.text = '${_account!.code} ${_account!.name}';
              }
              return TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'الحساب'),
              );
            },
          ),
        ),
        PeriodBar(
          from: _from,
          to: _to,
          onChanged: (f, t) {
            setState(() {
              _from = f;
              _to = t;
            });
            _load();
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        if (s != null) ...[
          Container(
            color: AccColors.navy.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const Text('رصيد أول المدة: '),
              MoneyText(s.openingBalance, bold: true),
              const Spacer(),
              const Text('الرصيد الختامي: '),
              MoneyText(s.closingBalance, bold: true, size: 18),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: s.lines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final l = s.lines[i];
                return ListTile(
                  tileColor: Colors.white,
                  dense: true,
                  title: Text(l.description),
                  subtitle: Text('${fmtDate(l.date)} • قيد ${l.entryNumber}'
                      ' • ${sourceTypeLabels[l.sourceType] ?? l.sourceType ?? ''}'
                      '${l.memo == null ? '' : ' • ${l.memo}'}'),
                  trailing: SizedBox(
                    width: 330,
                    child: Row(children: [
                      Expanded(
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: l.debit > 0 ? MoneyText(l.debit) : const Text(''))),
                      Expanded(
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: l.credit > 0 ? MoneyText(-l.credit) : const Text(''))),
                      Expanded(
                          child: Align(
                              alignment: Alignment.centerLeft, child: MoneyText(l.balance, bold: true))),
                    ]),
                  ),
                );
              },
            ),
          ),
        ] else if (!_loading)
          const Expanded(child: Center(child: Text('اختر حساباً لعرض كشفه'))),
      ]),
    );
  }
}
