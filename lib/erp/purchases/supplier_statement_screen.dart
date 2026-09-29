// lib/erp/purchases/supplier_statement_screen.dart
//
// 📒 كشف حساب المورد: كل حركات دفتر المورد (supplier_transactions) بترتيب
// زمني، مع الرصيد بعد كل حركة لكل عملة. قراءة فقط — لا يغيّر أي رصيد.
// الرصيد = مجموع الحركات (نفس قاعدة SupplierDebtReconciler).

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../erp_ui.dart';

class SupplierStatementScreen extends StatefulWidget {
  const SupplierStatementScreen({super.key, required this.supplierId, required this.supplierName});
  final int supplierId;
  final String supplierName;

  @override
  State<SupplierStatementScreen> createState() => _SupplierStatementScreenState();
}

class _SupplierStatementScreenState extends State<SupplierStatementScreen> {
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await erpDb();
      final rows = await db.rawQuery('''
        SELECT transaction_date, amount_changed, COALESCE(currency, 'IQD') AS currency,
               transaction_type, description, invoice_id, payment_id
        FROM supplier_transactions
        WHERE supplier_id = ? AND COALESCE(is_deleted, 0) = 0
        ORDER BY transaction_date ASC, id ASC
      ''', [widget.supplierId]);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  static String _typeLabel(String? t, Object? invoiceId, Object? paymentId) {
    switch (t) {
      case 'supplier_payment':
        return 'دفعة للمورد';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      case 'purchase_return':
        return 'مرتجع مشتريات';
      case 'correction':
        return 'تصحيح';
      case 'purchase_invoice_sync':
      case 'invoice_debt':
        return 'فاتورة شراء';
    }
    if (paymentId != null) return 'دفعة للمورد';
    if (invoiceId != null) return 'فاتورة شراء';
    return t ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final balances = <String, double>{};
    final table = <List<String>>[];
    double debit = 0, credit = 0;
    for (final r in _rows) {
      final cur = '${r['currency']}';
      final amt = d0(r['amount_changed']);
      final bal = (balances[cur] ?? 0) + amt;
      balances[cur] = bal;
      if (amt >= 0) {
        debit += cur == 'IQD' ? amt : 0;
      } else {
        credit += cur == 'IQD' ? -amt : 0;
      }
      final date = DateTime.tryParse('${r['transaction_date']}');
      table.add([
        date == null ? '${r['transaction_date']}' : fmtDate(date),
        _typeLabel(r['transaction_type'] as String?, r['invoice_id'], r['payment_id']),
        '${r['description'] ?? ''}',
        amt >= 0 ? fmtMoney(amt) : '',
        amt < 0 ? fmtMoney(-amt) : '',
        '${fmtMoney(bal)} ${cur == 'IQD' ? '' : cur}'.trim(),
      ]);
    }
    final balanceText = balances.isEmpty
        ? '0'
        : balances.entries.map((e) => '${fmtMoney(e.value)} ${e.key == 'IQD' ? 'دينار' : e.key}').join(' + ');

    return ErpPage(
      title: 'كشف حساب المورد',
      subtitle: widget.supplierName,
      icon: Icons.list_alt,
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white))],
      headerExtra: Wrap(spacing: 10, runSpacing: 10, children: [
        StatCard(label: 'الرصيد الحالي (له علينا)', value: balanceText, icon: Icons.account_balance_wallet_outlined,
            color: ErpColors.orange),
        StatCard(label: 'عدد الحركات', value: '${_rows.length}', icon: Icons.format_list_numbered, color: ErpColors.blue),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('تعذّر تحميل الكشف: $_error'))
              : _rows.isEmpty
                  ? const Center(child: Text('لا توجد حركات لهذا المورد'))
                  : SimpleTable(
                      headers: const ['التاريخ', 'النوع', 'البيان', 'له (دين علينا)', 'دفعنا له', 'الرصيد'],
                      numericColumns: const {3, 4, 5},
                      rows: table.reversed.toList(),
                      footer: ['', 'المجموع (دينار)', '', fmtMoney(debit), fmtMoney(credit), balanceText],
                    ),
    );
  }
}
