// lib/accounting/screens/income_statement_screen.dart
//
// 📈 قائمة الدخل (الأرباح والخسائر).

import 'package:flutter/material.dart';

import '../accounting_reports.dart';
import 'acc_ui.dart';

class IncomeStatementScreen extends StatefulWidget {
  const IncomeStatementScreen({super.key});

  @override
  State<IncomeStatementScreen> createState() => _IncomeStatementScreenState();
}

class _IncomeStatementScreenState extends State<IncomeStatementScreen> {
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  IncomeStatement? _st;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await AccountingReports()
          .incomeStatement(from: _from ?? DateTime(2000), to: _to);
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
      appBar: accAppBar('قائمة الدخل'),
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
        if (s != null)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.all(8), children: [
                  SectionCard(
                    title: 'الإيرادات',
                    color: AccColors.green,
                    child: Column(children: [
                      for (final r in s.revenues)
                        AmountRow(r.account.name, r.periodCredit - r.periodDebit, indent: 1),
                      AmountRow('مجموع الإيرادات', s.totalRevenue, bold: true),
                    ]),
                  ),
                  SectionCard(
                    title: 'كلفة البضاعة المباعة',
                    color: AccColors.orange,
                    child: Column(children: [
                      AmountRow('كلفة المبيعات', s.totalCogs, bold: true),
                    ]),
                  ),
                  _bigLine('مجمل الربح', s.grossProfit,
                      s.totalRevenue == 0 ? null : s.grossProfit / s.totalRevenue * 100),
                  SectionCard(
                    title: 'المصاريف',
                    color: AccColors.red,
                    child: Column(children: [
                      if (s.expenses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('لا مصاريف مسجّلة — سجّلها من «سند مصروف» ليظهر صافي الربح الحقيقي',
                              style: TextStyle(color: AccColors.muted)),
                        ),
                      for (final r in s.expenses)
                        AmountRow(r.account.name, r.periodDebit - r.periodCredit, indent: 1),
                      AmountRow('مجموع المصاريف', s.totalExpenses, bold: true),
                    ]),
                  ),
                  _bigLine('صافي الربح', s.netProfit,
                      s.totalRevenue == 0 ? null : s.netProfit / s.totalRevenue * 100),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _bigLine(String label, double v, double? pct) => Card(
        color: v >= 0 ? AccColors.navy : AccColors.red,
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
            if (pct != null)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            Text(fmtMoney(v),
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}
