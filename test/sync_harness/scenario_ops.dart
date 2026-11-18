// test/sync_harness/scenario_ops.dart
//
// 🧾 أفعال اختبار سيناريوهات الفاتورة (invoice_scenarios_test.dart) داخل عزلة الجهاز.
// 'invSave' يمر بمسار زر «حفظ» في الشاشة (invoice_actions) بالترتيب نفسه:
//   التحقق من البيانات ← مبلغ كل سطر = الكمية × السعر ← فحص الدين السالب ← لقطة ما قبل
//   التعديل ← InvoiceController.saveInvoice ← سند تعديل الفاتورة النقدية.
// (حوارات الشاشة — تأكيد التحويل إلى نقد، سقف الدين، موافقة المدير — تُعتبر موافَقاً عليها.)
// ignore_for_file: avoid_print

import 'package:alnaser/controllers/invoice_controller.dart';
import 'package:alnaser/erp/inventory/inventory_reports.dart';
import 'package:alnaser/models/invoice.dart';
import 'package:alnaser/models/invoice_input_data.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/invoice_edit_events.dart';
import 'package:alnaser/services/invoice_edit_voucher.dart';
import 'package:alnaser/services/invoice_safety/line_math_check.dart';
import 'package:alnaser/models/transaction.dart';
import 'package:alnaser/services/database/business/snapshot_chain.dart';
import 'package:alnaser/services/database/dao/audit_dao.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

/// حجم الكرتون من وحدات المنتج (كما في شاشة المنتج: [{"unit_name":"كرتون","quantity":24}]).
int? _cartonOf(String? hierarchy) {
  if (hierarchy == null) return null;
  final m = RegExp(r'"quantity"\s*:\s*(\d+)').firstMatch(hierarchy);
  return m == null ? null : int.parse(m.group(1)!);
}

Future<Map<String, Object?>?> _txByUuid(String uuid) async {
  final db = await DatabaseService().database;
  final r = await db.query('transactions', where: 'transaction_uuid = ?', whereArgs: [uuid], limit: 1);
  return r.isEmpty ? null : r.first;
}

Map<String, Object?> _txView(Map<String, Object?> r) => {
      'id': r['id'],
      'customerId': r['customer_id'],
      'amount': _d(r['amount_changed']),
      'note': r['transaction_note'],
      'date': r['transaction_date'],
      'type': r['transaction_type'],
      'deleted': r['is_deleted'],
      'invoiceId': r['invoice_id'],
    };

Future<Object?> scenOp(String op, Map<String, Object?> a) async {
  try {
    return await _scenOp(op, a);
  } catch (e) {
    return {'ok': false, 'stage': 'exception', 'err': '$e'.split('\n').first};
  }
}

Future<Map<String, Object?>> _invoiceInfo(String uuid) async {
  final db = await DatabaseService().database;
  final ir = await db.query('invoices', where: 'invoice_uuid = ?', whereArgs: [uuid], limit: 1);
  if (ir.isEmpty) return {'exists': false};
  final inv = ir.first;
  final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [inv['id']]);
  final cid = inv['customer_id'] as int?;
  Map<String, Object?>? cust;
  if (cid != null) {
    final c = await db.rawQuery('''
      SELECT c.sync_uuid AS uuid, c.name, c.current_total_debt AS debt,
        (SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t
          WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0) AS txsum
      FROM customers c WHERE c.id = ?''', [cid]);
    if (c.isNotEmpty) cust = c.first;
  }
  final linked = await db.rawQuery('''
    SELECT COALESCE(SUM(amount_changed), 0) AS s, COUNT(*) AS n FROM transactions
    WHERE invoice_id = ? AND COALESCE(is_deleted, 0) = 0''', [inv['id']]);
  return {
    'exists': true,
    'id': inv['id'],
    'deleted': inv['is_deleted'],
    'status': inv['status'],
    'total': _d(inv['total_amount']),
    'paid': _d(inv['amount_paid_on_invoice']),
    'discount': _d(inv['discount']),
    'fee': _d(inv['loading_fee']),
    'ptype': inv['payment_type'],
    'name': inv['customer_name'],
    'cust': cust,
    'linked': _d(linked.first['s']),
    'linkedN': (linked.first['n'] as num).toInt(),
    'items': [
      for (final it in items)
        {
          'prodId': it['product_id'],
          'qty': _d(it['quantity_individual']),
          'price': _d(it['applied_price']),
          'total': _d(it['item_total']),
          // 📦 البيع بالكرتون: الكمية بالكرتون ومعامله، والكمية بالوحدة الأساسية
          'qtyL': _d(it['quantity_large_unit']),
          'units': _d(it['units_in_large_unit']),
          'saleType': it['sale_type'],
          'base': _d(it['quantity_large_unit']) > 0
              ? _d(it['quantity_large_unit']) * (_d(it['units_in_large_unit']) > 0 ? _d(it['units_in_large_unit']) : 1)
              : _d(it['quantity_individual']),
        },
    ],
  };
}

/// سند حدث التعديل كما يُطبع: نوعه ورقمه ومبلغه.
Future<Map<String, Object?>?> _editEvent(int id) async {
  final db = await DatabaseService().database;
  final e = await InvoiceEditEvents.byId(db, id);
  if (e == null) return null;
  return {'kind': e['doc_kind'], 'no': e['doc_no'], 'amount': InvoiceEditEvents.voucherAmount(e)};
}

Future<Object?> _scenOp(String op, Map<String, Object?> a) async {
  final db = await DatabaseService().database;
  switch (op) {
    case 'prodIds':
      final rows = await db.query('products', columns: ['id', 'sync_uuid', 'name', 'stock_quantity']);
      return {
        'ok': true,
        'rows': [for (final r in rows) {'id': r['id'], 'uuid': r['sync_uuid'], 'name': r['name'], 'stock': _d(r['stock_quantity'])}],
      };

    case 'custByUuid':
      final r = await db.rawQuery('''
        SELECT c.id, c.name, c.current_total_debt AS debt, c.is_deleted AS del,
          (SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t
            WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0) AS txsum
        FROM customers c WHERE c.sync_uuid = ? LIMIT 1''', [a['cust']]);
      if (r.isEmpty) return {'ok': true, 'exists': false};
      return {'ok': true, 'exists': true, ...r.first};

    case 'custByName':
      // كل العملاء الحيّين بهذا الاسم بعد إزالة المسافات (لرصد عميل وُلد بالخطأ)
      final key = '${a['name']}'.replaceAll(' ', '');
      final rows = await db.rawQuery('''
        SELECT sync_uuid AS uuid, name, current_total_debt AS debt FROM customers
        WHERE COALESCE(is_deleted, 0) = 0 AND REPLACE(name, ' ', '') = ?''', [key]);
      return {'ok': true, 'rows': rows};

    case 'invInfo':
      return {'ok': true, ...await _invoiceInfo(a['inv'] as String)};

    case 'productCard':
      // بطاقة حركة المادة كما تعرضها الشاشة (InventoryReports.productCard)
      final card = await InventoryReports().productCard((a['prodId'] as num).toInt());
      return {
        'ok': true,
        'rows': [for (final r in card.rows) {'d': r['d'], 'q': _d(r['q']), 'kind': r['kind'], 'note': r['note'], 'balance': _d(r['balance'])}],
        'stored': card.storedQty,
        'ledger': card.ledgerQty,
        'matches': card.matches,
      };

    // ───────────── 🧾 الفاتورة الواحدة (one_invoice_history_test.dart) ─────────────

    case 'txRow':
      final r = await _txByUuid(a['tx'] as String);
      return r == null ? {'ok': true, 'exists': false} : {'ok': true, 'exists': true, ..._txView(r)};

    case 'txEdit':
      // ✏️ حوار «تعديل المعاملة» في بطاقة العميل (edit_transaction_dialog ← customer_details_screen):
      //   transaction.copyWith(amountChanged: r.amount, transactionNote: r.note, transactionDate: r.date)
      //   ثم DatabaseService().updateTransaction(updated) — بالترتيب نفسه.
      final row = await _txByUuid(a['tx'] as String);
      if (row == null) return {'ok': false, 'stage': 'load', 'err': 'المعاملة غير موجودة'};
      final t = DebtTransaction.fromMap(row);
      final note = (a['note'] as String?)?.trim();
      final updated = t.copyWith(
        amountChanged: (a['amount'] as num).toDouble(),
        transactionNote: (note == null || note.isEmpty) ? null : note,
        transactionDate: DateTime.parse(a['date'] as String),
      );
      try {
        await DatabaseService().updateTransaction(updated);
      } catch (e) {
        return {'ok': false, 'stage': 'refused', 'err': '$e'.split('\n').first, ..._txView((await _txByUuid(a['tx'] as String))!)};
      }
      return {'ok': true, ..._txView((await _txByUuid(a['tx'] as String))!)};

    case 'txConvert':
      // 🔁 زر «تحويل النوع» في بطاقة العميل: DatabaseService().convertTransactionType(id)
      final row = await _txByUuid(a['tx'] as String);
      if (row == null) return {'ok': false, 'stage': 'load', 'err': 'المعاملة غير موجودة'};
      try {
        await DatabaseService().convertTransactionType(row['id'] as int);
      } catch (e) {
        return {'ok': false, 'stage': 'refused', 'err': '$e'.split('\n').first, ..._txView((await _txByUuid(a['tx'] as String))!)};
      }
      return {'ok': true, ..._txView((await _txByUuid(a['tx'] as String))!)};

    case 'chainCheck':
      // 🔗 سلسلة الأرصدة في كشف العميل: كل معاملة «قبلها» = «بعد» سابقتها، و«بعدها» = قبلها + مبلغها
      final problems = <String>[];
      for (final cu in (a['custs'] as List).cast<String>()) {
        final c = await db.query('customers', columns: ['id', 'name', 'current_total_debt'], where: 'sync_uuid = ?', whereArgs: [cu], limit: 1);
        if (c.isEmpty) {
          problems.add('العميل $cu غير موجود');
          continue;
        }
        final rows = await db.query('transactions',
            where: 'customer_id = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [c.first['id']], orderBy: 'transaction_date ASC, id ASC');
        var run = 0.0;
        for (final r in rows) {
          final b = _d(r['balance_before_transaction']), af = _d(r['new_balance_after_transaction']), am = _d(r['amount_changed']);
          if ((b - run).abs() > 0.011 || (af - (run + am)).abs() > 0.011) {
            problems.add('«${c.first['name']}» المعاملة ${r['id']} (${r['transaction_note'] ?? r['transaction_type']}): '
                'قبلها $b والمفروض ${run.toStringAsFixed(2)}، بعدها $af والمفروض ${(run + am).toStringAsFixed(2)}');
            if (problems.length > 20) break;
          }
          run += am;
        }
        if ((run - _d(c.first['current_total_debt'])).abs() > 0.011) {
          problems.add('«${c.first['name']}» دينه المخزّن ${c.first['current_total_debt']} ومجموع كشفه $run');
        }
      }
      return {'ok': true, 'problems': problems};

    case 'invHistory':
      // 📜 سجل تعديلات الفاتورة كما تبنيه شاشته (invoice_history_screen): النسخ تُعاد بناؤها
      // بـ SnapshotChain.materialize، والنسخة التي لا تُبنى بدقة تظهر «غير معروفة».
      final ir = await db.query('invoices', columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) return {'ok': false, 'err': 'الفاتورة غير موجودة'};
      final id = ir.first['id'];
      final raw = await db.query('invoice_snapshots', where: 'invoice_id = ?', whereArgs: [id], orderBy: 'version_number ASC, id ASC');
      final snaps = SnapshotChain.materialize(raw.map((r) => Map<String, dynamic>.from(r)).toList(), AuditDao.decodeSnapshotItems);
      Future<int> n(String sql) async {
        try {
          return ((await db.rawQuery(sql, [id])).first['n'] as num).toInt();
        } catch (_) {
          return -1; // الجدول غير موجود
        }
      }
      return {
        'ok': true,
        'id': id,
        'snapshots': snaps.length,
        'unknown': snaps.where((s) => s['items_unknown'] == 1).length,
        'events': await n('SELECT COUNT(*) AS n FROM invoice_edit_events WHERE invoice_id = ?'),
        'vouchers': await n('SELECT COUNT(*) AS n FROM invoice_edit_vouchers WHERE invoice_id = ?'),
        'adjustments': await n('SELECT COUNT(*) AS n FROM invoice_adjustments WHERE invoice_id = ?'),
      };

    case 'invSave':
      // ── بيانات الشاشة كما تبنيها invoice_actions ──
      Invoice? existing;
      final invUuid = a['inv'] as String?;
      if (invUuid != null) {
        final ir = await db.query('invoices', where: 'invoice_uuid = ?', whereArgs: [invUuid], limit: 1);
        if (ir.isEmpty) return {'ok': false, 'stage': 'load', 'err': 'الفاتورة غير موجودة'};
        existing = Invoice.fromMap(ir.first);
      }
      final items = <InvoiceItem>[];
      for (final raw in (a['items'] as List).cast<Map>()) {
        final pid = (raw['prodId'] as num).toInt();
        final p = (await db.query('products', where: 'id = ?', whereArgs: [pid], limit: 1)).first;
        final qty = _d(raw['qty']), price = _d(raw['price']);
        // 📦 نوع البيع «كرتون» (اختياري): كما تبنيه الشاشة للوحدة الكبيرة
        final carton = raw['large'] == true ? _cartonOf(p['unit_hierarchy'] as String?) : null;
        if (carton != null) {
          items.add(InvoiceItem(
            invoiceId: existing?.id ?? 0,
            productId: pid,
            productName: p['name'] as String,
            unit: 'piece',
            unitPrice: price,
            costPrice: 0.5 * qty * carton,
            quantityLargeUnit: qty,
            unitsInLargeUnit: carton.toDouble(),
            appliedPrice: price,
            itemTotal: qty * price,
            saleType: 'كرتون',
          ));
          continue;
        }
        items.add(InvoiceItem(
          invoiceId: existing?.id ?? 0,
          productId: pid,
          productName: p['name'] as String,
          unit: 'piece',
          unitPrice: price,
          costPrice: 0.5 * qty,
          quantityIndividual: qty,
          appliedPrice: price,
          itemTotal: qty * price,
          saleType: 'قطعة',
        ));
      }
      final data = InvoiceInputData(
        invoiceToManage: existing,
        customerName: a['name'] as String,
        customerPhone: '',
        customerAddress: '',
        paidAmount: _d(a['paid']),
        loadingFee: _d(a['fee']),
        discount: _d(a['discount']),
        paymentType: a['ptype'] as String,
        selectedDate: existing?.invoiceDate ?? DateTime.now(),
        invoiceItems: items,
        installerName: a['installer'] as String?, // 👷 مؤسس الفاتورة (اختياري)
        pointsRate: _d(a['rate']),
      );
      final controller = InvoiceController(db: DatabaseService());
      final v = controller.validateInvoiceData(data);
      if (!v.isValid) return {'ok': false, 'stage': 'validate', 'err': v.errorMessage};
      final mismatch = LineMathCheck.firstMismatch(data.invoiceItems);
      if (mismatch != null) return {'ok': false, 'stage': 'lineMath', 'err': mismatch};
      final dv = await controller.validateDebtChangeWontCauseNegativeBalance(data);
      if (!dv.isValid) return {'ok': false, 'stage': 'debt', 'err': dv.errorMessage};
      final editId = existing?.id;
      final before = editId == null ? null : await InvoiceEditVoucher.snapshot(editId);
      final res = await controller.saveInvoice(data);
      if (!res.success || res.invoice == null) return {'ok': false, 'stage': 'save', 'err': res.errorMessage};
      final saved = res.invoice!;
      int? vid;
      if (before != null && saved.id != null) {
        vid = await InvoiceEditVoucher.recordIfCash(
          invoiceId: saved.id!,
          before: before,
          totalAfter: saved.totalAmount,
          paymentAfter: saved.paymentType,
          user: 'اختبار',
        );
      }
      Map<String, Object?>? voucher;
      if (vid != null) {
        final r = (await db.query('invoice_edit_vouchers', where: 'id = ?', whereArgs: [vid])).first;
        voucher = {'kind': r['kind'], 'amount': _d(r['amount'])};
      }
      return {
        'ok': true,
        'uuid': saved.invoiceUuid,
        'before': before == null ? null : {'total': before.total, 'payment': before.payment},
        'voucher': voucher,
        'editEvent': res.editEventId == null ? null : await _editEvent(res.editEventId!),
        ...await _invoiceInfo(saved.invoiceUuid!),
      };
  }
  throw StateError('unknown scen op $op');
}
