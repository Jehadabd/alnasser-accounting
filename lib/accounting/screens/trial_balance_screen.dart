// lib/accounting/screens/trial_balance_screen.dart
//
// ⚖️ ميزان المراجعة: رصيد أول المدة، حركة الفترة، الرصيد الختامي — هرمياً.

import 'package:flutter/material.dart';

import '../accounting_reports.dart';
import 'acc_ui.dart';
import 'account_statement_screen.dart';

class TrialBalanceScreen extends StatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  State<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends State<TrialBalanceScreen> {
  DateTime? _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to = DateTime.now();
  List<AccountBalanceRow> _rows = const [];
  bool _loading = true;
  int _maxDepth = 9;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await AccountingReports().trialBalance(from: _from, to: _to);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows.where((r) => r.depth <= _maxDepth).toList();
    final roots = _rows.where((r) => r.depth == 0);
    double sum(double Function(AccountBalanceRow) f) => roots.fold(0.0, (s, r) => s + f(r));
    const h = TextStyle(fontWeight: FontWeight.bold, color: Colors.white);

    DataCell m(double v, {bool bold = false}) => DataCell(MoneyText(v, bold: bold));

    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('ميزان المراجعة', actions: [
        PopupMenuButton<int>(
          tooltip: 'مستوى العرض',
          icon: const Icon(Icons.layers),
          onSelected: (d) => setState(() => _maxDepth = d),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('الحسابات الرئيسية فقط')),
            PopupMenuItem(value: 1, child: Text('مستويان')),
            PopupMenuItem(value: 9, child: Text('كل المستويات')),
          ],
        ),
      ]),
      body: Column(children: [
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
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AccColors.navy),
                columnSpacing: 22,
                columns: const [
                  DataColumn(label: Text('الحساب', style: h)),
                  DataColumn(label: Text('أول المدة مدين', style: h), numeric: true),
                  DataColumn(label: Text('أول المدة دائن', style: h), numeric: true),
                  DataColumn(label: Text('حركة مدين', style: h), numeric: true),
                  DataColumn(label: Text('حركة دائن', style: h), numeric: true),
                  DataColumn(label: Text('الرصيد مدين', style: h), numeric: true),
                  DataColumn(label: Text('الرصيد دائن', style: h), numeric: true),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      color: WidgetStateProperty.all(
                          r.account.isGroup ? AccColors.navy.withOpacity(0.05) : Colors.white),
                      onSelectChanged: r.account.isGroup
                          ? null
                          : (_) => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => AccountStatementScreen(
                                      initialAccountId: r.account.id, from: _from, to: _to))),
                      cells: [
                        DataCell(Padding(
                          padding: EdgeInsets.only(right: r.depth * 16.0),
                          child: Text('${r.account.code}  ${r.account.name}',
                              style: TextStyle(
                                  fontWeight: r.account.isGroup ? FontWeight.bold : FontWeight.normal)),
                        )),
                        m(r.openingDebit > r.openingCredit ? r.openingDebit - r.openingCredit : 0),
                        m(r.openingCredit > r.openingDebit ? r.openingCredit - r.openingDebit : 0),
                        m(r.periodDebit),
                        m(r.periodCredit),
                        m(r.closingDebit, bold: r.account.isGroup),
                        m(r.closingCredit, bold: r.account.isGroup),
                      ],
                    ),
                  DataRow(
                    color: WidgetStateProperty.all(AccColors.cyan.withOpacity(0.15)),
                    cells: [
                      const DataCell(Text('المجموع', style: TextStyle(fontWeight: FontWeight.bold))),
                      m(sum((r) => r.openingDebit > r.openingCredit ? r.openingDebit - r.openingCredit : 0), bold: true),
                      m(sum((r) => r.openingCredit > r.openingDebit ? r.openingCredit - r.openingDebit : 0), bold: true),
                      m(sum((r) => r.periodDebit), bold: true),
                      m(sum((r) => r.periodCredit), bold: true),
                      m(sum((r) => r.closingDebit), bold: true),
                      m(sum((r) => r.closingCredit), bold: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
