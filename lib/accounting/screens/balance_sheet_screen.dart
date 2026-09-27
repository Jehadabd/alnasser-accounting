// lib/accounting/screens/balance_sheet_screen.dart
//
// 🏦 الميزانية العمومية: الأصول = الخصوم + حقوق الملكية.

import 'package:flutter/material.dart';

import '../accounting_reports.dart';
import 'acc_ui.dart';

class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  DateTime _asOf = DateTime.now();
  BalanceSheet? _bs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final b = await AccountingReports().balanceSheet(asOf: _asOf);
      if (mounted) setState(() => _bs = b);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bs;
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('الميزانية العمومية'),
      body: Column(children: [
        PeriodBar(
          from: null,
          to: _asOf,
          showFrom: false,
          onChanged: (_, t) {
            setState(() => _asOf = t);
            _load();
          },
        ),
        if (_loading) const LinearProgressIndicator(),
        if (b != null)
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth > 900;
              final assets = SectionCard(
                title: 'الأصول',
                color: AccColors.blue,
                child: Column(children: [
                  for (final r in b.assets) AmountRow(r.account.name, r.natureBalance, indent: 1),
                  AmountRow('مجموع الأصول', b.totalAssets, bold: true),
                ]),
              );
              final right = Column(children: [
                SectionCard(
                  title: 'الخصوم',
                  color: AccColors.orange,
                  child: Column(children: [
                    for (final r in b.liabilities) AmountRow(r.account.name, r.natureBalance, indent: 1),
                    AmountRow('مجموع الخصوم', b.totalLiabilities, bold: true),
                  ]),
                ),
                SectionCard(
                  title: 'حقوق الملكية',
                  color: AccColors.purple,
                  child: Column(children: [
                    for (final r in b.equity) AmountRow(r.account.name, r.natureBalance, indent: 1),
                    AmountRow('أرباح الفترة (غير مقفلة)', b.currentProfit, indent: 1),
                    AmountRow('مجموع حقوق الملكية', b.totalEquity, bold: true),
                  ]),
                ),
              ]);
              final check = Card(
                margin: const EdgeInsets.all(8),
                color: b.difference.abs() < 1 ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    b.difference.abs() < 1
                        ? 'متوازنة ✓  الأصول ${fmtMoney(b.totalAssets)} = الخصوم + حقوق الملكية'
                        : 'غير متوازنة: الفرق ${fmtMoney(b.difference)} — شغّل الترحيل من شاشة المحاسبة',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
              return ListView(padding: const EdgeInsets.all(8), children: [
                check,
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: assets),
                    Expanded(child: right),
                  ])
                else ...[
                  assets,
                  right,
                ],
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'إذا ظهر رصيد المخزون سالباً فذلك لأن مشتريات قديمة لم تُسجَّل في البرنامج. '
                    'استعمل «مطابقة المخزون» من إعدادات المحاسبة ليساوي قيمة البضاعة الموجودة.',
                    style: TextStyle(color: AccColors.muted, fontSize: 12),
                  ),
                ),
              ]);
            }),
          ),
      ]),
    );
  }
}
