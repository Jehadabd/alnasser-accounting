// lib/inventory/purchase_return_screen.dart
//
// ↩️ مرتجع المشتريات: إرجاع بضاعة للمورد.
//
// ما يحدث عند الحفظ (في معاملة واحدة):
//   • حركة مخزون سالبة لكل مادة (kind = purchase_return) ⇒ تنقص الكمية.
//   • حركة على حساب المورد بقيمة المرتجع بالسالب (purchase_return) ⇒ ينقص دينه.
//   • إعادة حساب رصيد المورد من دفتره.
// محرك الترحيل يحوّل حركة المورد إلى قيد: مدين ذمم الموردين / دائن المخزون.

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../accounting/screens/acc_ui.dart';
import '../models/app_user.dart';
import '../services/database/business/stock_ledger.dart';
import '../services/database/business/supplier_debt_reconciler.dart';
import '../services/database_service.dart';
import '../services/firebase_sync/uuid_helper.dart';

class PurchaseReturnLine {
  PurchaseReturnLine({required this.productId, required this.name, required this.quantity, required this.unitPrice});
  final int productId;
  final String name;
  double quantity;
  double unitPrice;
  double get total => quantity * unitPrice;
}

class PurchaseReturnService {
  Future<Database> get _db => DatabaseService().database;

  Future<List<Map<String, Object?>>> suppliers() async {
    final db = await _db;
    return db.query('suppliers', columns: ['id', 'name', 'currency'], orderBy: 'name');
  }

  Future<List<Map<String, Object?>>> searchProducts(String q) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT id, name, unit, cost_price, stock_quantity FROM products
      WHERE COALESCE(is_deleted, 0) = 0 AND name LIKE ?
      ORDER BY name LIMIT 30
    ''', ['%${q.trim()}%']);
  }

  Future<void> save({
    required int supplierId,
    required String currency,
    required List<PurchaseReturnLine> lines,
    String? notes,
  }) async {
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw Exception('أضف مادة واحدة على الأقل');
    final total = valid.fold(0.0, (s, l) => s + l.total);
    if (total <= 0) throw Exception('قيمة المرتجع يجب أن تكون أكبر من صفر');
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final names = <String>[];
      for (final l in valid) {
        final uuid = await StockLedger.productSyncUuidForId(txn, l.productId);
        if (uuid == null) throw Exception('المادة ${l.name} غير موجودة');
        await StockLedger.addMovement(txn,
            productSyncUuid: uuid,
            delta: -l.quantity,
            kind: 'purchase_return',
            note: 'مرتجع مشتريات${notes == null || notes.isEmpty ? '' : ' — $notes'}');
        names.add('${l.name} × ${l.quantity}');
      }
      await txn.insert('supplier_transactions', {
        'supplier_id': supplierId,
        'transaction_date': now,
        'amount_changed': -total,
        'currency': currency,
        'balance_before': 0.0,
        'balance_after': 0.0,
        'transaction_type': 'purchase_return',
        'description': 'مرتجع مشتريات: ${names.join('، ')}',
        'transaction_uuid': UuidHelper.newTransactionUuid(),
        'is_deleted': 0,
        'created_at': now,
      });
      await SupplierDebtReconciler.rebuildSupplierBalances(txn, supplierId);
    });
  }
}

class PurchaseReturnScreen extends StatefulWidget {
  const PurchaseReturnScreen({super.key});

  @override
  State<PurchaseReturnScreen> createState() => _PurchaseReturnScreenState();
}

class _PurchaseReturnScreenState extends State<PurchaseReturnScreen> {
  final _svc = PurchaseReturnService();
  List<Map<String, Object?>> _suppliers = const [];
  Map<String, Object?>? _supplier;
  final List<PurchaseReturnLine> _lines = [];
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _svc.suppliers().then((s) {
      if (mounted) setState(() => _suppliers = s);
    });
  }

  Future<void> _addProduct() async {
    final picked = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const _ProductPicker(),
    );
    if (picked == null) return;
    setState(() => _lines.add(PurchaseReturnLine(
          productId: picked['id'] as int,
          name: '${picked['name']}',
          quantity: 1,
          unitPrice: ((picked['cost_price'] as num?) ?? 0).toDouble(),
        )));
  }

  Future<void> _save() async {
    if (!requirePermission(context, AppPermissions.suppliers)) return;
    final s = _supplier;
    if (s == null) {
      showError(context, 'اختر المورد');
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.save(
        supplierId: s['id'] as int,
        currency: (s['currency'] as String?) ?? 'IQD',
        lines: _lines,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      showOk(context, 'سُجّل المرتجع: نقص المخزون ودين المورد');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _lines.fold(0.0, (s, l) => s + l.total);
    final cur = (_supplier?['currency'] as String?) ?? 'IQD';
    return Scaffold(
      backgroundColor: AccColors.bg,
      appBar: accAppBar('مرتجع مشتريات'),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Text('المجموع: ${fmtMoney(total)} ${cur == 'USD' ? '\$' : 'د.ع'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AccColors.navy, padding: const EdgeInsets.all(16)),
            onPressed: _saving || _lines.isEmpty ? null : _save,
            icon: const Icon(Icons.assignment_return),
            label: const Text('حفظ المرتجع'),
          ),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        DropdownButtonFormField<Map<String, Object?>>(
          value: _supplier,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'المورد', filled: true, fillColor: Colors.white),
          items: [
            for (final s in _suppliers)
              DropdownMenuItem(value: s, child: Text('${s['name']}  (${s['currency'] ?? 'IQD'})')),
          ],
          onChanged: (s) => setState(() => _supplier = s),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'سبب الإرجاع / ملاحظات', filled: true, fillColor: Colors.white),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _lines.length; i++)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(flex: 3, child: Text(_lines[i].name, style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                  child: TextFormField(
                    initialValue: '${_lines[i].quantity}',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'الكمية', isDense: true),
                    onChanged: (v) => setState(() => _lines[i].quantity = double.tryParse(v) ?? 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _lines[i].unitPrice.toStringAsFixed(0),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'سعر الوحدة', isDense: true),
                    onChanged: (v) => setState(() => _lines[i].unitPrice = double.tryParse(v) ?? 0),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 110, child: MoneyText(_lines[i].total, bold: true)),
                IconButton(
                  onPressed: () => setState(() => _lines.removeAt(i)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
            ),
          ),
        TextButton.icon(onPressed: _addProduct, icon: const Icon(Icons.add), label: const Text('إضافة مادة')),
        const SizedBox(height: 8),
        const Text(
          'الكمية بالوحدة الأساسية للمادة (قطعة/متر). سعر الوحدة يُقترح من سعر الكلفة ويمكن تعديله.',
          style: TextStyle(color: AccColors.muted, fontSize: 12),
        ),
      ]),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker();

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  List<Map<String, Object?>> _rows = const [];

  Future<void> _search(String q) async {
    final r = await PurchaseReturnService().searchProducts(q);
    if (mounted) setState(() => _rows = r);
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر مادة'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
            onChanged: _search,
          ),
          Expanded(
            child: ListView(children: [
              for (final r in _rows)
                ListTile(
                  title: Text('${r['name']}'),
                  subtitle: Text('المخزون: ${r['stock_quantity'] ?? 0} ${r['unit'] ?? ''}'),
                  onTap: () => Navigator.pop(context, r),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
