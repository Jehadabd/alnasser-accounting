// test/sync_harness/rest_ops.dart
//
// أفعال «اختبار البقية القاسي» على الجهاز الوهمي — كلها عبر الكود الحقيقي:
// الكاشير (createPosInvoice)، وصل القبض المركّب (ReceiptsService)، الموردون وفواتير
// الشراء والدفعات والمرتجعات والرصيد الافتتاحي (PurchaseService)، الاستيراد من Excel
// (DataImport)، مرتجع المبيعات، والتشغيل في الخلفية ثم «القتل» (انقطاع مفاجئ).
// كل فعل يعيد نتيجته أو {'ok': false, 'err': ...} ولا يرمي.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:alnaser/erp/debts/receipts_service.dart';
import 'package:alnaser/erp/purchases/purchase_return_service.dart';
import 'package:alnaser/erp/sales/sales_return_service.dart';
import 'package:alnaser/erp/stock_helpers.dart';
import 'package:alnaser/models/purchase_invoice.dart';
import 'package:alnaser/models/purchase_invoice_item.dart';
import 'package:alnaser/models/supplier.dart';
import 'package:alnaser/models/transaction.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/import/data_import.dart';
import 'package:alnaser/services/import/sheet_reader.dart';
import 'package:alnaser/services/purchase_service.dart';
import 'package:sqflite/sqflite.dart';

Future<Database> _db() => DatabaseService().database;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

Future<int> _custId(Database db, String uuid) async {
  final r = await db.query('customers', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [uuid], limit: 1);
  if (r.isEmpty) throw StateError('customer not on device');
  return r.first['id'] as int;
}

Future<int> _prodId(Database db, String uuid) async {
  var r = await db.query('products', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [uuid], limit: 1);
  if (r.isEmpty) {
    final al = await db.query('product_uuid_alias',
        columns: ['new_uuid'], where: 'old_uuid = ?', whereArgs: [uuid], limit: 1);
    if (al.isNotEmpty) {
      r = await db.query('products', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [al.first['new_uuid']], limit: 1);
    }
  }
  if (r.isEmpty) throw StateError('product not on device');
  return r.first['id'] as int;
}

Future<int?> _box(Database db) async {
  final b = await db.rawQuery('SELECT id FROM cash_boxes ORDER BY is_default DESC, id LIMIT 1');
  return b.isEmpty ? null : b.first['id'] as int;
}

/// معاملات هذا الجهاز اليدوية الجديدة بعد [txMax] (لا معاملات الفواتير ولا الواردة).
Future<List<List<Object?>>> _newTxs(Database db, int txMax) async {
  final r = await db.rawQuery('''
    SELECT t.transaction_uuid AS u, c.sync_uuid AS c, t.amount_changed AS a, t.transaction_type AS ty,
           COALESCE(t.is_deleted, 0) AS del, t.transaction_note AS note
    FROM transactions t JOIN customers c ON c.id = t.customer_id
    WHERE t.id > ? AND COALESCE(t.is_created_by_me, 1) = 1
      AND t.invoice_id IS NULL AND COALESCE(t.invoice_sync_uuid, '') = ''
    ORDER BY t.id''', [txMax]);
  return [for (final x in r) [x['u'], x['c'], _d(x['a']), x['ty'], x['del'], x['note']]];
}

Future<int> _txMax(Database db) async =>
    ((await db.rawQuery('SELECT COALESCE(MAX(id), 0) AS m FROM transactions')).first['m'] as num).toInt();

Future<Object?> restOp(String op, Map<String, Object?> a) async {
  try {
    return await _restOp(op, a);
  } catch (e) {
    return {'ok': false, 'err': '$e'.split('\n').first};
  }
}

Future<Object?> _restOp(String op, Map<String, Object?> a) async {
  final db = await _db();
  switch (op) {
    // ─────────────────────── أدوات ───────────────────────
    case 'txMax':
      return await _txMax(db);

    case 'newTxs':
      return await _newTxs(db, (a['after'] as num).toInt());

    case 'spawn':
      // 🔌 فعل يبدأ في الخلفية ثم يُقتل الجهاز بعد [delayMs] (Harness.restart):
      // ما حُفظ على القرص لحظتها هو ما يبقى — كانقطاع الكهرباء تماماً.
      unawaited(restOp(a['op'] as String, (a['args'] as Map).cast<String, Object?>()));
      await Future<void>.delayed(Duration(milliseconds: (a['delayMs'] as num).toInt()));
      return true;

    // ─────────────────────── سجل الديون ───────────────────────
    case 'tx':
      // معاملة يدوية (شاشة العميل) بعلامة في الملاحظة
      final cid = await _custId(db, a['cust'] as String);
      final amount = _d(a['amount']);
      await AppProvider().addTransaction(DebtTransaction(
        customerId: cid,
        amountChanged: amount,
        transactionType: amount >= 0 ? 'manual_debt' : 'manual_payment',
        transactionNote: a['marker'] as String,
      ));
      return {'ok': true};

    case 'byNote':
      // معاملات هذا الجهاز التي تحمل العلامة (بعد انقطاع: هل حُفظت؟)
      final r = await db.rawQuery('''
        SELECT t.transaction_uuid AS u, c.sync_uuid AS c, t.amount_changed AS a, COALESCE(t.is_deleted, 0) AS del
        FROM transactions t JOIN customers c ON c.id = t.customer_id
        WHERE t.transaction_note LIKE ?''', ['%${a['marker']}%']);
      return [for (final x in r) [x['u'], x['c'], _d(x['a']), x['del']]];

    case 'pos':
      // 🧾 بيع الكاشير: DatabaseService.createPosInvoice (كما يستدعيه PosProvider)
      String? name;
      if (a['cust'] != null) {
        final c = await db.query('customers', columns: ['name'], where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
        if (c.isEmpty) throw StateError('customer not on device');
        name = c.first['name'] as String;
      }
      final items = <Map<String, dynamic>>[];
      var raw = 0.0;
      for (final it in (a['items'] as List).cast<Map>()) {
        final pid = await _prodId(db, it['prod'] as String);
        final p = (await db.query('products', where: 'id = ?', whereArgs: [pid], limit: 1)).first;
        final qty = _d(it['qty']), price = _d(it['price']);
        raw += qty * price;
        items.add({
          'product_id': pid,
          'product_name': p['name'],
          'quantity': qty,
          'price': price,
          'unit': 'قطعة',
          'cost_price': _d(p['cost_price']),
          'sale_type': 'قطعة',
          'units_in_large_unit': 1.0,
        });
      }
      final discount = _d(a['discount']);
      final total = (raw - discount).clamp(0, double.infinity).toDouble();
      final credit = a['ptype'] == 'دين';
      final id = await DatabaseService().createPosInvoice(
        items: items,
        totalAmount: total,
        paymentType: credit ? 'دين' : 'نقد',
        customerName: name,
        discount: discount,
        paidAmount: credit ? _d(a['paid']) : total,
      );
      final inv = (await db.rawQuery('''
        SELECT i.invoice_uuid AS u, i.total_amount AS t, i.amount_paid_on_invoice AS p, i.discount AS d,
               i.payment_type AS pt, c.sync_uuid AS c
        FROM invoices i LEFT JOIN customers c ON c.id = i.customer_id WHERE i.id = ?''', [id])).first;
      return {'ok': true, 'uuid': inv['u'], 'cust': inv['c'], 'total': _d(inv['t']), 'paid': _d(inv['p']), 'discount': _d(inv['d']), 'ptype': inv['pt']};

    case 'creceipt':
      // 🧾 وصل قبض مركّب: عدة عملاء، تسديد وخصم، بالدينار أو بالدولار بسعر تعادل
      final box = await _box(db);
      if (box == null) throw StateError('no cash box');
      final lines = <ReceiptLineInput>[];
      for (final l in (a['lines'] as List).cast<Map>()) {
        final cid = await _custId(db, l['cust'] as String);
        lines.add(ReceiptLineInput(
            customerId: cid, customerName: '${l['cust']}', amountFc: _d(l['amount']), discount: _d(l['discount'])));
      }
      final res = await ReceiptsService().createCustomerReceipt(null,
          provider: AppProvider(),
          date: DateTime.now(),
          cashBoxId: box,
          currency: a['currency'] as String,
          fxRate: _d(a['fx']),
          lines: lines,
          notes: a['marker'] as String?);
      return {'ok': true, 'errors': res.errors, ...await _receiptState(db, res.receiptId)};

    case 'receiptByNote':
      final r = await db.query('customer_receipts', columns: ['id'], where: 'notes = ?', whereArgs: [a['marker']], limit: 1);
      if (r.isEmpty) return null;
      return await _receiptState(db, r.first['id'] as int);

    case 'sret':
      // ↩️ مرتجع مبيعات على الحساب من فاتورة (SalesReturnService)
      final cid = await _custId(db, a['cust'] as String);
      final ir = await db.query('invoices', columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) throw StateError('invoice not on device');
      final cname = (await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [cid])).first['name'] as String;
      final pid = await _prodId(db, a['prod'] as String);
      final p = await ErpStock.byId(db, pid);
      final rid = await SalesReturnService().create(null,
          provider: AppProvider(),
          customerId: cid,
          customerName: cname,
          originalInvoiceId: ir.first['id'] as int,
          refundMode: 'credit',
          date: DateTime.now(),
          notes: a['marker'] as String,
          lines: [ReturnLine(product: p!, unit: p.units.first, quantity: _d(a['qty']), price: _d(a['price']))]);
      final h = (await db.query('sales_returns', where: 'id = ?', whereArgs: [rid])).first;
      return {'ok': true, 'id': rid, 'total': _d(h['total']), 'tx': h['tx_uuid']};

    // ─────────────────────── الموردون ───────────────────────
    case 'supAdd':
      final now = DateTime.now();
      final id = await PurchaseService().addSupplier(
          Supplier(name: a['name'] as String, currency: a['currency'] as String, createdAt: now, updatedAt: now));
      return {'ok': true, 'id': id};

    case 'supBuy':
    case 'supEdit':
      final ps = PurchaseService();
      final items = <PurchaseInvoiceItem>[];
      for (final it in (a['items'] as List).cast<Map>()) {
        final q = _d(it['qty']), pr = _d(it['price']);
        items.add(PurchaseInvoiceItem(
            productId: await _prodId(db, it['prod'] as String), unitName: 'قطعة', quantity: q, unitPrice: pr, totalPrice: q * pr));
      }
      final raw = items.fold<double>(0, (s, i) => s + i.totalPrice);
      final status = a['status'] as String;
      final paid = _d(a['paid']);
      final int id;
      if (op == 'supBuy') {
        await ps.savePurchaseInvoice(
            PurchaseInvoice(
                invoiceNumber: a['number'] as String,
                supplierId: (a['sup'] as num).toInt(),
                currency: a['currency'] as String,
                totalAmount: raw,
                paidAmount: paid,
                status: status,
                date: DateTime.now()),
            items);
        final r = await db.query('purchase_invoices', columns: ['id'], where: 'invoice_number = ?', whereArgs: [a['number']], limit: 1);
        if (r.isEmpty) return {'ok': false, 'err': 'لم تُحفظ'};
        id = r.first['id'] as int;
      } else {
        id = (a['id'] as num).toInt();
        final old = await ps.getInvoiceById(id);
        if (old == null) throw StateError('purchase invoice missing');
        final oldItems = await ps.getInvoiceItems(id);
        await ps.updatePurchaseInvoiceWithReversal(
            old, old.copyWith(totalAmount: raw, paidAmount: paid, status: status), oldItems, items);
      }
      return {'ok': true, ...await _purchaseState(db, id)};

    case 'supCancel':
      await PurchaseService().cancelPurchaseInvoice((a['id'] as num).toInt(), reason: 'اختبار');
      return {'ok': true};

    case 'supPay':
      final box = await _box(db);
      final cur = a['currency'] as String;
      await ReceiptsService().supplierPayment(
          supplierId: (a['sup'] as num).toInt(),
          amount: _d(a['amount']),
          currency: cur,
          method: 'cash',
          date: DateTime.now(),
          cashBoxId: box,
          fxRate: cur == 'IQD' ? null : 1310.0,
          notes: a['marker'] as String);
      return {'ok': true, ...?await _paymentByNote(db, a['marker'] as String)};

    case 'payByNote':
      return await _paymentByNote(db, a['marker'] as String);

    case 'supVoidPay':
      await PurchaseService().voidPayment((a['id'] as num).toInt(), reason: 'اختبار');
      return {'ok': true};

    case 'supOpen':
      await PurchaseService().setOpeningBalance((a['sup'] as num).toInt(),
          amount: _d(a['amount']), currency: a['currency'] as String, date: DateTime.now().subtract(const Duration(days: 40)));
      return {'ok': true};

    case 'supRet':
      final box = await _box(db);
      final cur = a['currency'] as String;
      final lines = <PurchaseReturnLine>[];
      for (final it in (a['items'] as List).cast<Map>()) {
        final p = await ErpStock.byId(db, await _prodId(db, it['prod'] as String));
        lines.add(PurchaseReturnLine(product: p!, unit: p.units.first, quantity: _d(it['qty']), price: _d(it['price'])));
      }
      final id = await PurchaseReturnService().create(
        supplierId: (a['sup'] as num).toInt(),
        supplierName: 'مورد',
        originalInvoiceId: (a['inv'] as num?)?.toInt(),
        currency: cur,
        fxRate: cur == 'IQD' ? 1.0 : 1310.0,
        refundMode: a['mode'] as String,
        cashAmount: _d(a['cash']),
        cashBoxId: box,
        date: DateTime.now(),
        lines: lines,
      );
      final h = (await db.query('purchase_returns', where: 'id = ?', whereArgs: [id])).first;
      return {'ok': true, 'id': id, 'total': _d(h['total']), 'cash': _d(h['cash_amount'])};

    case 'supVoidRet':
      await PurchaseReturnService().voidReturn((a['id'] as num).toInt(), reason: 'اختبار');
      return {'ok': true};

    case 'supState':
      // رصيد كل مورد كما في بطاقته، ومجموع حركات دفتره لكل عملة
      final out = <Map<String, Object?>>[];
      for (final s in await db.query('suppliers', columns: ['id', 'total_debt_iqd', 'total_debt_usd'])) {
        final sums = await db.rawQuery('''
          SELECT currency AS cur, COALESCE(SUM(amount_changed), 0) AS s FROM supplier_transactions
          WHERE supplier_id = ? AND COALESCE(is_deleted, 0) = 0 GROUP BY currency''', [s['id']]);
        final m = {for (final x in sums) x['cur']: _d(x['s'])};
        out.add({'id': s['id'], 'iqd': _d(s['total_debt_iqd']), 'usd': _d(s['total_debt_usd']), 'sumIqd': m['IQD'] ?? 0.0, 'sumUsd': m['USD'] ?? 0.0});
      }
      return out;

    case 'purchaseState':
      return await _purchaseState(db, (a['id'] as num).toInt());

    // ─────────────────────── الاستيراد من Excel ───────────────────────
    case 'import':
      final kind = ImportKind.values.byName(a['kind'] as String);
      final rows = [for (final r in (a['rows'] as List)) [for (final c in (r as List)) '$c']];
      final map = <String, int?>{'name': 0, if (kind == ImportKind.products) 'price': 1 else 'balance': 1};
      if (kind == ImportKind.products) map['qty'] = 2;
      if (kind == ImportKind.suppliers) map['currency'] = 2;
      final o = ImportOptions(openingDate: DateTime.now().subtract(const Duration(days: 1)), sourceId: a['source'] as String);
      final plan = await DataImport.plan(db, SheetTable('ورقة', rows), kind, map, o);
      final actions = (a['actions'] as Map?)?.cast<String, String>() ?? const {};
      for (final r in plan.existingRows) {
        r.action = ExistingAction.values.byName(actions[r.name] ?? 'keep');
      }
      final before = await _txMax(db);
      final res = await DataImport.execute(plan, o, fileName: 'اختبار.xlsx', sheet: 'ورقة');
      return {
        'ok': true,
        'added': res.added,
        'verified': res.verified,
        'problems': res.problems,
        'errors': [for (final e in plan.errors) '${e.line}'],
        'txs': await _newTxs(db, before),
        'custs': [
          for (final r in plan.newRows)
            if (kind == ImportKind.customers)
              (await db.query('customers', columns: ['sync_uuid'], where: 'name = ?', whereArgs: [r.name], limit: 1))
                  .map((x) => [x['sync_uuid'], r.name])
                  .firstOrNull,
        ],
        'sups': [
          if (kind == ImportKind.suppliers)
            for (final r in plan.newRows)
              (await db.query('suppliers', columns: ['id'], where: 'name = ?', whereArgs: [r.name], limit: 1))
                  .map((x) => [x['id'], r.name, r.currency])
                  .firstOrNull,
        ],
        'prods': [
          if (kind == ImportKind.products)
            for (final r in plan.newRows)
              (await db.query('products',
                      columns: ['sync_uuid', 'price1', 'stock_quantity'], where: 'name = ?', whereArgs: [r.name], limit: 1))
                  .map((x) => [x['sync_uuid'], r.name, _d(x['price1']), _d(x['stock_quantity'])])
                  .firstOrNull,
        ],
      };

    // ─────────────────────── الثوابت بعد كل شيء (وبعد الانقطاع) ───────────────────────
    case 'invariants':
      return await _invariants(db);
  }
  throw StateError('unknown rest op $op');
}

Future<Map<String, Object?>> _receiptState(Database db, int id) async {
  final h = (await db.query('customer_receipts', where: 'id = ?', whereArgs: [id])).first;
  final ls = await db.rawQuery('''
    SELECT c.sync_uuid AS c, l.amount AS a, l.discount AS d, l.pay_tx_uuid AS pu, l.disc_tx_uuid AS du,
           l.balance_before AS b0, l.balance_after AS b1
    FROM customer_receipt_lines l JOIN customers c ON c.id = l.customer_id WHERE l.receipt_id = ? ORDER BY l.id''', [id]);
  return {
    'id': id,
    'total': _d(h['total_amount']),
    'disc': _d(h['total_discount']),
    'lines': [
      for (final l in ls)
        {'cust': l['c'], 'amount': _d(l['a']), 'discount': _d(l['d']), 'pay': l['pu'], 'disc': l['du'], 'before': _d(l['b0']), 'after': _d(l['b1'])}
    ],
  };
}

Future<Map<String, Object?>> _purchaseState(Database db, int id) async {
  final h = (await db.query('purchase_invoices', where: 'id = ?', whereArgs: [id])).first;
  final it = await db.query('purchase_invoice_items', columns: ['total_price'], where: 'invoice_id = ?', whereArgs: [id], orderBy: 'id');
  return {'id': id, 'total': _d(h['total_amount']), 'paid': _d(h['paid_amount']), 'status': h['status'], 'lines': [for (final x in it) _d(x['total_price'])]};
}

Future<Map<String, Object?>?> _paymentByNote(Database db, String marker) async {
  final r = await db.query('supplier_payments', columns: ['id', 'amount'], where: 'notes LIKE ?', whereArgs: ['%$marker%'], limit: 1);
  return r.isEmpty ? null : {'id': r.first['id'], 'amount': _d(r.first['amount'])};
}

Future<List<String>> _invariants(Database db) async {
  final out = <String>[];
  // 1) دين كل عميل = مجموع معاملاته
  for (final r in await db.rawQuery('''
      SELECT c.id, c.name, c.current_total_debt AS d,
             (SELECT COALESCE(SUM(amount_changed), 0) FROM transactions t
              WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0) AS s
      FROM customers c WHERE COALESCE(c.is_deleted, 0) = 0''')) {
    if ((_d(r['d']) - _d(r['s'])).abs() > 0.005) out.add('دين «${r['name']}» ${r['d']} ≠ مجموع معاملاته ${r['s']}');
  }
  // 2) فاتورة البيع المحفوظة: الإجمالي = الأسطر + الأجور − الخصم، ودينها في السجل = الإجمالي − المسدد
  for (final r in await db.rawQuery('''
      SELECT i.id, i.invoice_number AS n, i.total_amount AS t, i.loading_fee AS f, i.discount AS d,
             i.amount_paid_on_invoice AS p, i.payment_type AS pt, i.customer_id AS cid,
             (SELECT COALESCE(SUM(item_total), 0) FROM invoice_items x WHERE x.invoice_id = i.id) AS items,
             (SELECT COALESCE(SUM(amount_changed), 0) FROM transactions t
              WHERE t.invoice_id = i.id AND COALESCE(t.is_deleted, 0) = 0) AS debt
      FROM invoices i
      WHERE COALESCE(i.is_created_by_me, 1) = 1 AND i.status = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0''')) {
    final want = _d(r['items']) + _d(r['f']) - _d(r['d']);
    if ((want - _d(r['t'])).abs() > 0.005) out.add('فاتورة ${r['n']}: الإجمالي ${r['t']} ≠ الأسطر والأجور والخصم $want');
    final c = r['pt'] == 'دين' && r['cid'] != null ? (_d(r['t']) - _d(r['p'])).clamp(0, double.infinity) : 0.0;
    if ((c - _d(r['debt'])).abs() > 0.005) out.add('فاتورة ${r['n']}: دينها في السجل ${r['debt']} والصحيح $c');
  }
  // 3) وصل القبض: الرأس = مجموع أسطره، وكل سطر له معاملته بمبلغه
  for (final r in await db.rawQuery('''
      SELECT h.id, h.receipt_no AS n, h.total_amount AS t, h.total_discount AS td,
             (SELECT COALESCE(SUM(amount), 0) FROM customer_receipt_lines l WHERE l.receipt_id = h.id) AS la,
             (SELECT COALESCE(SUM(discount), 0) FROM customer_receipt_lines l WHERE l.receipt_id = h.id) AS ld
      FROM customer_receipts h''')) {
    if ((_d(r['t']) - _d(r['la'])).abs() > 0.005 || (_d(r['td']) - _d(r['ld'])).abs() > 0.005) {
      out.add('وصل قبض ${r['n']}: الرأس ${r['t']}+${r['td']} ≠ أسطره ${r['la']}+${r['ld']} (وصل ناقص)');
    }
  }
  for (final r in await db.rawQuery('''
      SELECT l.receipt_id AS id, l.amount AS a, l.pay_tx_uuid AS u, t.amount_changed AS ta, COALESCE(t.is_deleted, 0) AS del
      FROM customer_receipt_lines l LEFT JOIN transactions t ON t.transaction_uuid = l.pay_tx_uuid
      WHERE l.amount > 0''')) {
    if (r['ta'] == null || r['del'] == 1 || (_d(r['ta']) + _d(r['a'])).abs() > 0.005) {
      out.add('وصل ${r['id']}: سطر بـ${r['a']} معاملته ${r['ta'] ?? 'غائبة'}');
    }
  }
  // 4) مرتجع مبيعات: معاملته موجودة، وكل معاملة مرتجع لها مستندها
  for (final r in await db.rawQuery('''
      SELECT s.return_no AS n, s.total AS tot, s.cash_amount AS cash, s.tx_uuid AS u, t.amount_changed AS ta
      FROM sales_returns s LEFT JOIN transactions t ON t.transaction_uuid = s.tx_uuid AND COALESCE(t.is_deleted, 0) = 0
      WHERE s.status = 'posted' ''')) {
    final credit = _d(r['tot']) - _d(r['cash']);
    if (credit > 0.005 && (r['ta'] == null || (_d(r['ta']) + credit).abs() > 0.005)) {
      out.add('مرتجع مبيعات ${r['n']}: أثره على الدين ${r['ta'] ?? 'غائب'} والصحيح ${-credit}');
    }
  }
  // معاملة «مرتجع مبيعات رقم N» بلا مستند، ولا تعويض «إلغاء مرتجع مبيعات رقم N (فشل الحفظ)»
  final ext = await db.rawQuery('''
      SELECT e.transaction_uuid AS u, e.note AS note, t.amount_changed AS a FROM customer_tx_ext e
      JOIN transactions t ON t.transaction_uuid = e.transaction_uuid AND COALESCE(t.is_deleted, 0) = 0
      WHERE e.ref_type = 'sales_return' ''');
  final notes = [for (final x in ext) '${x['note']}'];
  for (final r in ext) {
    final note = '${r['note']}';
    if (note.startsWith('إلغاء')) continue;
    final docs = await db.query('sales_returns', columns: ['id'], where: 'tx_uuid = ?', whereArgs: [r['u']], limit: 1);
    if (docs.isNotEmpty) continue;
    final m = RegExp(r'رقم (\d+)').firstMatch(note);
    final undone = m != null && notes.any((n) => n.startsWith('إلغاء مرتجع مبيعات رقم ${m.group(1)} '));
    if (!undone) out.add('معاملة مرتجع مبيعات بلا مستند: $note (${r['a']})');
  }
  // 5) المورد: رصيده = مجموع حركات دفتره لكل عملة
  for (final s in await db.query('suppliers', columns: ['id', 'name', 'total_debt_iqd', 'total_debt_usd'])) {
    for (final cur in const ['IQD', 'USD']) {
      final sum = _d((await db.rawQuery(
              'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM supplier_transactions '
              'WHERE supplier_id = ? AND currency = ? AND COALESCE(is_deleted, 0) = 0', [s['id'], cur]))
          .first['s']);
      final card = _d(s[cur == 'IQD' ? 'total_debt_iqd' : 'total_debt_usd']);
      if ((sum - card).abs() > 0.005) out.add('المورد «${s['name']}» $cur: البطاقة $card ≠ الدفتر $sum');
    }
  }
  // 6) الدينار بلا كسور فيما كتبه هذا الجهاز
  for (final r in await db.rawQuery('''
      SELECT transaction_uuid AS u, amount_changed AS a FROM transactions
      WHERE COALESCE(is_uploaded, 0) = 0 AND invoice_id IS NULL AND COALESCE(invoice_sync_uuid, '') = ''
        AND ABS(amount_changed - ROUND(amount_changed)) > 0.0001''')) {
    out.add('معاملة بكسور: ${r['a']} (${r['u']})');
  }
  for (final r in await db.rawQuery('''
      SELECT invoice_number AS n, total_amount AS t, amount_paid_on_invoice AS p, discount AS d FROM invoices
      WHERE COALESCE(is_created_by_me, 1) = 1 AND (ABS(total_amount - ROUND(total_amount)) > 0.0001
         OR ABS(amount_paid_on_invoice - ROUND(amount_paid_on_invoice)) > 0.0001 OR ABS(discount - ROUND(discount)) > 0.0001)''')) {
    out.add('فاتورة بكسور ${r['n']}: ${r['t']} / ${r['p']} / ${r['d']}');
  }
  for (final r in await db.rawQuery('''
      SELECT invoice_number AS n, total_amount AS t, paid_amount AS p FROM purchase_invoices
      WHERE currency = 'IQD' AND (ABS(total_amount - ROUND(total_amount)) > 0.0001 OR ABS(paid_amount - ROUND(paid_amount)) > 0.0001)''')) {
    out.add('فاتورة شراء بالدينار بكسور ${r['n']}: ${r['t']} / ${r['p']}');
  }
  // 7) معاملة يدوية قيمتها صفر لا معنى لها (تقريب أنتج صفراً بلا رفض)
  for (final r in await db.rawQuery('''
      SELECT transaction_uuid AS u, transaction_note AS n FROM transactions
      WHERE COALESCE(is_created_by_me, 1) = 1 AND invoice_id IS NULL AND COALESCE(invoice_sync_uuid, '') = ''
        AND COALESCE(is_deleted, 0) = 0 AND ABS(amount_changed) < 0.0001
        AND transaction_type IN ('manual_debt', 'manual_payment')''')) {
    out.add('معاملة يدوية بمبلغ صفر: ${r['n'] ?? r['u']}');
  }
  return out;
}
