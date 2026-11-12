// test/sync_harness/features_ops.dart
//
// 🧩 أفعال اختبار الميزات المتبقية (features_torture_test.dart) — تعمل داخل عزلة الجهاز
// وبكود التطبيق نفسه:
//   مطابقة البنك (BankRecService)، كلفة الشحن والتخليص (LandedCostService)، الدفعات
//   وتواريخ الصلاحية (BatchStore/Lots)، المحاسبة الإضافية (السند المركّب، إقفال السنة،
//   إعادة تقييم الدولار)، سند تعديل الفاتورة النقدية (InvoiceEditVoucher)، الفاتورة
//   المعلّقة (HeldInvoices)، وسند القبض المؤرشف (customer_receipt_vouchers).
// ignore_for_file: avoid_print

import 'package:alnaser/accounting/ledger.dart';
import 'package:alnaser/accounting/vouchers_service.dart';
import 'package:alnaser/erp/accounting_plus/accounting_plus_service.dart';
import 'package:alnaser/erp/batches/batch_models.dart';
import 'package:alnaser/erp/batches/batch_store.dart';
import 'package:alnaser/erp/control/bank_rec_service.dart';
import 'package:alnaser/erp/control/landed_cost_service.dart';
import 'package:alnaser/erp/erp_common.dart' show PeriodLock;
import 'package:alnaser/models/customer_receipt_voucher.dart';
import 'package:alnaser/models/invoice.dart';
import 'package:alnaser/models/transaction.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/held_invoices.dart';
import 'package:alnaser/services/invoice_edit_voucher.dart';
import 'package:alnaser/utils/money_calculator.dart';
import 'package:sqflite/sqflite.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

Future<Object?> featOp(String op, Map<String, Object?> a) async {
  try {
    return await _featOp(op, a);
  } catch (e) {
    return {'ok': false, 'err': '$e'.split('\n').first};
  }
}

/// بصمة الدفتر: عدد القيود والأسطر ومجموع المدين والدائن — لإثبات أن فعلاً «لا يغيّر قيداً».
Future<String> _ledgerPrint(Database db) async {
  final r = await db.rawQuery('''
    SELECT (SELECT COUNT(*) FROM journal_entries) AS e, COUNT(*) AS n,
           ROUND(COALESCE(SUM(debit), 0), 2) AS dr, ROUND(COALESCE(SUM(credit), 0), 2) AS cr
    FROM journal_lines''');
  return '${r.first['e']}|${r.first['n']}|${r.first['dr']}|${r.first['cr']}';
}

Future<Object?> _featOp(String op, Map<String, Object?> a) async {
  final db = await DatabaseService().database;
  switch (op) {
    case 'ledgerPrint':
      return {'ok': true, 'print': await _ledgerPrint(db)};

    case 'boxAccounts':
      return {
        'ok': true,
        for (final b in await VouchersService().cashBoxes()) '${b.id}': b.accountId,
      };

    case 'accountsInfo':
      // كل الحسابات الفرعية مع نوعها وكونها ذمماً — لبناء أسطر السند المركّب
      final rows = await db.rawQuery('SELECT * FROM accounts WHERE is_group = 0 AND is_active = 1 ORDER BY id');
      return {
        'ok': true,
        'rows': [
          for (final r in rows) {'id': r['id'], 'type': r['type'], 'control': r['is_control'], 'key': r['system_key']},
        ],
      };

    // ───────────────────────── مطابقة البنك ─────────────────────────
    case 'bankPlan':
      // ما سيُعرض في مطابقة جديدة اليوم (دون أن يبقى أثر): مسودة مؤقتة تُحمَّل ثم تُحذف
      final box = (a['box'] as num).toInt();
      final tmp = await BankRecService.create(boxId: box, statementDate: DateTime.now(), statementBalance: 0);
      try {
        final st = await BankRecService.load(tmp);
        return {
          'ok': true,
          'prior': st.priorCleared,
          'book': st.bookBalance,
          'lines': [for (final l in st.lines) {'key': l.key, 'amount': l.amount}],
        };
      } finally {
        await BankRecService.deleteDraft(tmp);
      }

    case 'bankCreate':
      final id = await BankRecService.create(
          boxId: (a['box'] as num).toInt(),
          statementDate: a['date'] == null ? DateTime.now() : DateTime.parse(a['date'] as String),
          statementBalance: _d(a['balance']));
      return {'ok': true, 'id': id};

    case 'bankLoad':
      final st = await BankRecService.load((a['id'] as num).toInt());
      return {
        'ok': true,
        'prior': st.priorCleared,
        'cleared': st.clearedBalance,
        'difference': st.difference,
        'balanced': st.balanced,
        'final': st.rec.isFinal,
        'statement': st.rec.statementBalance,
        'storedCleared': st.rec.clearedBalance,
        'marked': st.marked.toList(),
        'lines': [for (final l in st.lines) {'key': l.key, 'amount': l.amount}],
      };

    case 'bankToggle':
      final id = (a['id'] as num).toInt();
      final st = await BankRecService.load(id);
      final line = st.lines.where((l) => l.key == a['key']).firstOrNull;
      if (line == null) return {'ok': false, 'err': 'الحركة غير موجودة في المطابقة'};
      await BankRecService.toggle(id, line, a['mark'] == true);
      return {'ok': true};

    case 'bankFinalize':
      await BankRecService.finalize((a['id'] as num).toInt());
      return {'ok': true};

    case 'bankDelete':
      await BankRecService.deleteDraft((a['id'] as num).toInt());
      return {'ok': true};

    case 'bankReopen':
      await BankRecService.reopen((a['id'] as num).toInt());
      return {'ok': true};

    case 'boxLedgerLines':
      // حركات صندوق في الدفتر حتى اليوم بمفتاح المطابقة نفسه (نوع المصدر:معرّفه) — للمقارنة المستقلة
      final acc = (await db.query('cash_boxes', columns: ['account_id'], where: 'id = ?', whereArgs: [a['box']])).first['account_id'];
      final rows = await db.rawQuery('''
        SELECT e.id AS eid, e.source_type AS st, e.source_id AS sid, SUM(l.debit - l.credit) AS amt
        FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
        WHERE l.account_id = ? GROUP BY e.id HAVING ABS(SUM(l.debit - l.credit)) >= 0.005''', [acc]);
      return {
        'ok': true,
        'lines': {for (final r in rows) '${r['st']}:${r['sid'] ?? 'e${r['eid']}'}': ((_d(r['amt']) * 100).round()) / 100},
      };

    case 'bankRecs':
      await BankRecService.list(); // يضمن جدول المطابقات قبل أول مطابقة
      final rows = await db.rawQuery('''
        SELECT r.id, r.box_id, r.status, r.statement_balance, r.cleared_balance, r.statement_date,
               (SELECT COALESCE(SUM(m.amount), 0) FROM bank_rec_marks m WHERE m.rec_id = r.id) AS marks
        FROM bank_recs r ORDER BY r.id''');
      return {'ok': true, 'rows': rows};

    // ───────────────────────── كلفة الشحن والتخليص ─────────────────────────
    case 'landed':
      final plan = LandedPlan(
        purchaseUnitCost: _d(a['unitCost']),
        baseQty: _d(a['qty']),
        extras: [
          for (final e in (a['extras'] as List).cast<Map>()) LandedExtra('${e['name']}', _d(e['amount'])),
        ],
        mode: a['mode'] as String,
        boxId: (a['box'] as num?)?.toInt(),
        expenseAccountId: (a['acc'] as num?)?.toInt(),
      );
      final id = await LandedCostService.record(
          productId: (a['product'] as num).toInt(), productName: '${a['name']}', plan: plan);
      final r = (await db.query('landed_costs', where: 'id = ?', whereArgs: [id])).first;
      return {
        'ok': true,
        'id': id,
        'total': _d(r['total_extra']),
        'perUnit': _d(r['per_unit']),
        'planTotal': plan.totalExtra,
        'planPerUnit': plan.perUnit,
        'finalUnit': plan.finalUnitCost,
      };

    case 'landedVoid':
      await LandedCostService.voidRecord((a['id'] as num).toInt());
      return {'ok': true};

    case 'landedEntries':
      // قيود الشحن في الدفتر (بعد الترحيل): لكل سجل مبلغه وحسابه المقابل
      final rows = await db.rawQuery('''
        SELECT e.source_id AS id, SUM(l.debit) AS dr, SUM(l.credit) AS cr, COUNT(*) AS n
        FROM journal_entries e JOIN journal_lines l ON l.entry_id = e.id
        WHERE e.source_type = 'landed_cost' GROUP BY e.id''');
      return {'ok': true, 'rows': rows};

    // ───────────────────────── الدفعات وتواريخ الصلاحية ─────────────────────────
    case 'productId':
      final r = await db.query('products', columns: ['id', 'stock_quantity'], where: 'sync_uuid = ?', whereArgs: [a['uuid']], limit: 1);
      if (r.isEmpty) return {'ok': false, 'err': 'لا مادة'};
      return {'ok': true, 'id': r.first['id'], 'stock': _d(r.first['stock_quantity'])};

    case 'lotAdd':
      final id = await BatchStore().add(StockLot(
        productId: (a['product'] as num).toInt(),
        lotNo: '${a['lotNo'] ?? ''}',
        expiry: DateTime.parse(a['expiry'] as String),
        qty: _d(a['qty']),
        receivedAt: DateTime.now(),
      ));
      return {'ok': true, 'id': id};

    case 'lotRemove':
      await BatchStore().remove((a['id'] as num).toInt());
      return {'ok': true};

    case 'lots':
      final all = await BatchStore().all();
      final raw = await db.query('stock_lots');
      return {
        'ok': true,
        'rows': [for (final r in raw) {'id': r['id'], 'product': r['product_id'], 'qty': _d(r['qty'])}],
        'products': [
          for (final p in all)
            {
              'id': p.productId,
              'stock': p.stock,
              'lots': [
                for (final l in p.lots)
                  {'id': l.lot.id, 'qty': l.lot.qty, 'remaining': l.remaining, 'expiry': l.lot.expiry.toIso8601String()},
              ],
            },
        ],
      };

    // ───────────────────────── المحاسبة الإضافية ─────────────────────────
    case 'compound':
      final accRows = {
        for (final r in await db.query('accounts')) r['id'] as int: Account.fromMap(r),
      };
      final lines = <VLine>[];
      for (final l in (a['lines'] as List).cast<Map>()) {
        final acc = accRows[(l['acc'] as num).toInt()];
        if (acc == null) return {'ok': false, 'err': 'حساب غير موجود'};
        lines.add(VLine(
          account: acc,
          debit: _d(l['dr']),
          credit: _d(l['cr']),
          currency: (l['cur'] as String?) ?? 'IQD',
          fcAmount: (l['fc'] as num?)?.toDouble(),
          fxRate: (l['rate'] as num?)?.toDouble(),
        ));
      }
      final id = await CompoundVoucherService().create(
          date: a['date'] == null ? DateTime.now() : DateTime.parse(a['date'] as String),
          lines: lines,
          description: 'اختبار مركّب');
      return {'ok': true, 'id': id};

    case 'compoundDelete':
      await CompoundVoucherService().delete((a['id'] as num).toInt());
      return {'ok': true};

    case 'compoundCheck':
      // كل سند مركّب حي: قيده موجود ومتوازن ومجموعه = مبلغ السند؛ والمحذوف بلا قيد
      final problems = <String>[];
      final vs = await db.query('vouchers', where: "voucher_type = 'compound'");
      for (final v in vs) {
        final e = await db.rawQuery('''
          SELECT COALESCE(SUM(l.debit), 0) AS dr, COALESCE(SUM(l.credit), 0) AS cr, COUNT(*) AS n
          FROM journal_entries e JOIN journal_lines l ON l.entry_id = e.id
          WHERE e.source_type = 'voucher' AND e.source_id = ?''', [v['id']]);
        final dr = _d(e.first['dr']), cr = _d(e.first['cr']), n = (e.first['n'] as num).toInt();
        final deleted = (v['is_deleted'] as int? ?? 0) == 1;
        if (deleted && n > 0) problems.add('سند مركّب محذوف ${v['id']} ما زال له قيد');
        if (!deleted) {
          if (n == 0) problems.add('سند مركّب ${v['id']} بلا قيد');
          if ((dr - cr).abs() > 0.005) problems.add('قيد السند المركّب ${v['id']} غير متوازن ($dr/$cr)');
          if ((dr - _d(v['amount'])).abs() > 0.005) problems.add('قيد السند المركّب ${v['id']} = $dr والسند ${v['amount']}');
          final vl = await db.rawQuery(
              'SELECT COALESCE(SUM(debit), 0) AS dr, COUNT(*) AS n FROM voucher_lines WHERE voucher_id = ?', [v['id']]);
          if ((_d(vl.first['dr']) - dr).abs() > 0.005) problems.add('أسطر السند المركّب ${v['id']} ≠ قيده');
        }
      }
      return {'ok': true, 'problems': problems};

    case 'fiscalClose':
      final net = await FiscalCloseService().close((a['year'] as num).toInt(), lockAfter: a['lock'] != false);
      return {'ok': true, 'net': net};

    case 'fiscalPreviewNet':
      final lines = await FiscalCloseService().preview((a['year'] as num).toInt());
      return {'ok': true, 'net': FiscalCloseService.netProfit(lines), 'n': lines.length};

    case 'fiscalReopen':
      await FiscalCloseService().reopen((a['year'] as num).toInt());
      return {'ok': true};

    case 'fiscalDrift':
      return {'ok': true, 'drift': await FiscalCloseService().driftAfterClose((a['year'] as num).toInt())};

    case 'yearProfit':
      // صافي الإيرادات − المصاريف حتى نهاية السنة (كل القيود، ومنها قيد الإقفال)
      final end = DateTime((a['year'] as num).toInt() + 1, 1, 1).toIso8601String();
      final r = await db.rawQuery('''
        SELECT COALESCE(SUM(l.credit - l.debit), 0) AS n
        FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id
        WHERE e.entry_date < ? AND a.type IN ('revenue', 'expense')''', [end]);
      return {'ok': true, 'net': _d(r.first['n'])};

    case 'setLock':
      await PeriodLock.setLockDate(a['date'] == null ? null : DateTime.parse(a['date'] as String));
      return {'ok': true};

    case 'fxPreview':
      final rows = await FxRevaluationService().preview(DateTime.now(), rate: _d(a['rate']));
      return {
        'ok': true,
        'rows': [for (final r in rows) {'sup': r.supplierId, 'usd': r.usd, 'book': r.bookIqd, 'target': r.targetIqd}],
      };

    case 'fxPost':
      final total = await FxRevaluationService().post(DateTime.now(), rate: _d(a['rate']));
      return {'ok': true, 'total': total};

    case 'fxDelete':
      await FxRevaluationService().deleteEntry(FxRevaluationService.dayKey(DateTime.now()));
      return {'ok': true};

    case 'apUsd':
      // ذمم الموردين بالدولار في الدفتر لكل مورد: الدولار والدينار
      final ap = await Ledger.systemAccountId(db, 'ap_usd');
      final rows = await db.rawQuery('''
        SELECT l.party_id AS sid,
          SUM(CASE WHEN l.currency = 'USD' THEN (CASE WHEN l.credit > 0 THEN COALESCE(l.fc_amount, 0) ELSE -COALESCE(l.fc_amount, 0) END) ELSE 0 END) AS usd,
          SUM(l.credit - l.debit) AS iqd
        FROM journal_lines l WHERE l.account_id = ? AND l.party_type = 'supplier' GROUP BY l.party_id''', [ap]);
      final fx = await db.rawQuery("SELECT COUNT(*) AS n FROM journal_entries WHERE source_type = 'fx_reval'");
      return {'ok': true, 'rows': rows, 'fxEntries': (fx.first['n'] as num).toInt()};

    // ───────────────────────── سند تعديل الفاتورة النقدية ─────────────────────────
    case 'invSnapshot':
      final ir = await db.query('invoices', columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) return {'ok': false, 'err': 'لا فاتورة'};
      final s = await InvoiceEditVoucher.snapshot(ir.first['id'] as int);
      if (s == null) return {'ok': false, 'err': 'لا لقطة'};
      return {'ok': true, 'id': ir.first['id'], 'total': s.total, 'payment': s.payment};

    case 'editVoucher':
      // كما في invoice_actions بعد حفظ التعديل
      final id = (a['id'] as num).toInt();
      final after = await InvoiceEditVoucher.snapshot(id);
      if (after == null) return {'ok': false, 'err': 'لا لقطة'};
      final vid = await InvoiceEditVoucher.recordIfCash(
        invoiceId: id,
        before: (total: _d(a['beforeTotal']), payment: a['beforePayment'] as String),
        totalAfter: after.total,
        paymentAfter: after.payment,
        user: 'اختبار',
      );
      Map<String, Object?>? row;
      if (vid != null) row = (await db.query('invoice_edit_vouchers', where: 'id = ?', whereArgs: [vid])).first;
      return {
        'ok': true,
        'voucher': vid,
        'kind': row?['kind'],
        'amount': row == null ? null : _d(row['amount']),
        'after': after.total,
        'afterPayment': after.payment,
      };

    // ───────────────────────── الفاتورة المعلّقة: لا حذف إلا للمعلّقة ─────────────────────────
    case 'discardAny':
      // زر «حذف» يمرّ بـ HeldInvoices.discard: فاتورة غير معلّقة يجب ألا تُمسّ
      final ir = await db.query('invoices', where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) return {'ok': false, 'err': 'لا فاتورة'};
      await HeldInvoices.discard(Invoice.fromMap(ir.first));
      final after = await db.query('invoices',
          columns: ['is_deleted', 'status'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      return {'ok': true, 'deleted': after.isEmpty ? 1 : (after.first['is_deleted'] as int? ?? 0), 'status': after.firstOrNull?['status']};

    case 'invoiceState':
      final ir = await db.query('invoices',
          columns: ['id', 'is_deleted', 'status', 'total_amount', 'payment_type', 'customer_id'],
          where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) return {'ok': true, 'exists': false};
      return {'ok': true, 'exists': true, ...ir.first};

    // ───────────────────────── سند القبض المؤرشف ─────────────────────────
    case 'legacyReceipt':
      // كشاشة «إضافة معاملة» حين يختار المستخدم طباعة سند القبض: التسديد ثم أرشفة السند
      final cid = (await db.query('customers', columns: ['id', 'name', 'current_total_debt'],
              where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1))
          .firstOrNull;
      if (cid == null) return {'ok': false, 'err': 'لا عميل'};
      final before = _d(cid['current_total_debt']);
      final paid = _d(a['paid']);
      await AppProvider().addTransaction(DebtTransaction(
        customerId: cid['id'] as int,
        amountChanged: -paid,
        transactionType: 'manual_payment',
        transactionNote: 'سند قبض مؤرشف ${a['marker'] ?? ''}',
      ));
      final newBalance = MoneyCalculator.add(before, -paid);
      final ds = DatabaseService();
      final no = await ds.getNextCustomerReceiptNumber();
      final id = await ds.insertCustomerReceiptVoucher(CustomerReceiptVoucher(
        receiptNumber: no,
        customerId: cid['id'] as int,
        customerName: cid['name'] as String,
        beforePayment: before,
        paidAmount: paid,
        afterPayment: newBalance,
        createdAt: DateTime.now(),
      ));
      final actual = await db.query('customers', columns: ['current_total_debt'], where: 'id = ?', whereArgs: [cid['id']]);
      return {
        'ok': true,
        'id': id,
        'number': no,
        'before': before,
        'after': newBalance,
        'actual': _d(actual.first['current_total_debt']),
      };

    case 'custDebt':
      final r = await db.query('customers', columns: ['current_total_debt'], where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      return {'ok': true, 'debt': r.isEmpty ? 0.0 : _d(r.first['current_total_debt'])};

    case 'legacyReceipts':
      final rows = await db.query('customer_receipt_vouchers', columns: ['id', 'receipt_number'], orderBy: 'id');
      return {'ok': true, 'rows': rows};
  }
  throw StateError('unknown feat op $op');
}
