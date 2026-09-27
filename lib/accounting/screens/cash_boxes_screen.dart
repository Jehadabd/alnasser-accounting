// lib/accounting/screens/cash_boxes_screen.dart
//
// 💰 الصناديق والبنوك: الأرصدة، إضافة صندوق، تعيين الافتراضي، كشف الحركة.

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../vouchers_service.dart';
import 'acc_ui.dart';
import 'account_statement_screen.dart';

class CashBoxesScreen extends StatefulWidget {
  const CashBoxesScreen({super.key});

  @override
  State<CashBoxesScreen> createState() => _CashBoxesScreenState();
}

class _CashBoxesScreenState extends State<CashBoxesScreen> {
  final _svc = VouchersService();
  List<CashBox> _boxes = const [];
  Map<int, double> _bal = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await _svc.cashBoxes(activeOnly: false);
      final bal = await _svc.cashBoxBalances();
      if (mounted) {
        setState(() {
          _boxes = b;
          _bal = bal;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _add() async {
    if (!requirePermission(context, AppPermissions.accountingPost)) return;
    final name = TextEditingController();
    var kind = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('صندوق جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'الاسم (مثلاً: صندوق كاشير 2)')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('صندوق نقدي'), icon: Icon(Icons.payments)),
                ButtonSegment(value: 'bank', label: Text('حساب بنكي'), icon: Icon(Icons.account_balance)),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setD(() => kind = s.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await _svc.createCashBox(name.text, kind: kind);
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _bal.values.fold(0.0, (s, v) => s + v);
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('الصناديق والبنوك'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AccColors.navy,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('صندوق جديد'),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: AccColors.navy,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet, color: Colors.white, size: 36),
              const SizedBox(width: 16),
              const Expanded(
                  child: Text('مجموع النقدية', style: TextStyle(color: Colors.white, fontSize: 18))),
              Text(fmtMoney(total),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        for (final b in _boxes)
          Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(b.kind == 'bank' ? Icons.account_balance : Icons.payments,
                  color: b.isActive ? AccColors.green : Colors.grey),
              title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(b.isDefault ? 'الصندوق الافتراضي — تدخله مبيعات الكاشير النقدية' : ''),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                MoneyText(_bal[b.id] ?? 0, bold: true, size: 18),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'default') {
                      if (!requirePermission(context, AppPermissions.accountingPost)) return;
                      await _svc.setDefaultCashBox(b.id);
                      _load();
                    } else if (v == 'ledger') {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => AccountStatementScreen(initialAccountId: b.accountId)));
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'ledger', child: Text('حركة الصندوق')),
                    if (!b.isDefault)
                      const PopupMenuItem(value: 'default', child: Text('اجعله الافتراضي')),
                  ],
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
