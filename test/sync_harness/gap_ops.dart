// test/sync_harness/gap_ops.dart
//
// 🕳️ أفعال اختبار «مسارات المال التي لم يمر بها اختبار» (تقرير claude_money_coverage.bat).
// كل فعل سيناريو كامل عبر خدمات التطبيق الحقيقية، يعيد {'fails': [...], 'notes': [...]}:
// قائمة الإخفاقات فارغة = نجاح. البيانات «القديمة» (من إصدارات سابقة) تُصنع بـ SQL مباشر
// كما توجد فعلاً في قواعد المحلات، ثم يُشغَّل عليها كود التطبيق نفسه.
// ignore_for_file: avoid_print

import 'package:alnaser/accounting/accounting_reports.dart';
import 'package:alnaser/accounting/orphan_debts_service.dart';
import 'package:alnaser/accounting/posting_engine.dart';
import 'package:alnaser/accounting/vouchers_service.dart';
import 'package:alnaser/erp/control/fixed_assets_service.dart';
import 'package:alnaser/erp/debts/customer_money.dart';
import 'package:alnaser/erp/debts/receipts_service.dart';
import 'package:alnaser/erp/device_defaults.dart';
import 'package:alnaser/erp/erp_common.dart' show PeriodLock;
import 'package:alnaser/erp/inventory/usd_cost_service.dart';
import 'package:alnaser/erp/sales/invoice_extras.dart';
import 'package:alnaser/erp/stock_helpers.dart' show ErpStock;
import 'package:alnaser/models/customer.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/models/purchase_invoice.dart';
import 'package:alnaser/models/purchase_invoice_item.dart';
import 'package:alnaser/models/supplier.dart';
import 'package:alnaser/org/org_service.dart';
import 'package:alnaser/owner/founder_service.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/customer_merge_service.dart';
import 'package:alnaser/services/database/business/customer_name_rule.dart';
import 'package:alnaser/services/database/business/deep_check_repair.dart';
import 'package:alnaser/services/database/business/supplier_debt_reconciler.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/held_invoices.dart';
import 'package:alnaser/services/purchase_service.dart';
import 'package:sqflite/sqflite.dart';

import 'scenario_ops.dart' show scenOp;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

/// مدوّن نتائج سيناريو: إخفاقات وملاحظات.
class _R {
  final fails = <String>[];
  final notes = <String>[];

  void eq(String label, num actual, num expected) {
    if ((actual - expected).abs() > 0.005) fails.add('$label: المتوقع $expected والفعلي $actual');
  }

  void isTrue(String label, bool v) {
    if (!v) fails.add(label);
  }

  Future<void> throws(String label, Future<void> Function() f) async {
    try {
      await f();
      fails.add('$label: كان يجب أن يُرفض');
    } catch (_) {}
  }

  Map<String, Object?> get out => {'fails': fails, 'notes': notes};
}

Future<int> _id(Database db, String table, String col, String v) async {
  final r = await db.query(table, columns: ['id'], where: '$col = ?', whereArgs: [v], limit: 1);
  if (r.isEmpty) throw StateError('$table: لا صف بـ $col = $v');
  return r.first['id'] as int;
}

/// لا يرمي: الاستثناء غير المتوقع يعود إخفاقاً بنصّه وأول سطرين من مكانه.
Future<Object?> gapOp(String op, Map<String, Object?> a) async {
  try {
    return await _gapOp(op, a);
  } catch (e, st) {
    final where = '$st'.split('\n').take(2).join(' | ');
    return {'fails': ['هنا وقع خطأ: استثناء في $op: $e — $where'], 'notes': const []};
  }
}

Future<Object?> _gapOp(String op, Map<String, Object?> a) async {
  final db = await DatabaseService().database;
  switch (op) {
    case 'purResave':
      return (await _purResave(db, a['prod'] as String)).out;
    case 'supVoidLegacy':
      return (await _supVoidLegacy(db, a['prod'] as String)).out;
    case 'dupCustomer':
      return await _dupCustomer(db, a['name'] as String);
    case 'merge':
      return await _merge(db, a['survivor'] as String, (a['merged'] as List).cast<String>());
    case 'founderReturn':
      return (await _founderReturn(db, a['inv'] as String)).out;
    case 'founderImported':
      return (await _founderImported(db, a['inv'] as String)).out;
    case 'repairLedger':
      return (await _repairLedger(db, a['inv'] as String)).out;
    case 'repairRestored':
      return (await _repairRestored(db, a['inv'] as String)).out;
    case 'posStamp':
      return (await _posStamp(db, a['prod'] as String)).out;
    case 'moneyPostFail':
      return (await _moneyPostFail(db)).out;
    case 'freezeCosts':
      return (await _freezeCosts(db, a['inv'] as String)).out;
    case 'zeroEntry':
      return (await _zeroEntry(db, a['inv'] as String)).out;
    case 'extras':
      return (await _extras(db, a['inv'] as String)).out;
    case 'orphans':
      return (await _orphans(db, a['gone'] as String, a['hidden'] as String)).out;
    case 'linkOldCash':
      return (await _linkOldCash(db, a['inv'] as String, a['cust'] as String)).out;
    case 'assets':
      return (await _assets(db)).out;
    case 'regularStamp':
      return (await _regularStamp(db, a['prod'] as String)).out;
    case 'legacyInvoiceTx':
      // صف دين فاتورة وصل منفصلاً بمعرّفه (إصدارات قديمة رفعت معاملات الفواتير وحدها)
      final cid = await _id(db, 'customers', 'sync_uuid', a['cust'] as String);
      final now = DateTime.now().toIso8601String();
      await db.insert('transactions', {
        'customer_id': cid,
        'transaction_date': now,
        'amount_changed': (a['amount'] as num).toDouble(),
        'transaction_type': 'invoice_debt',
        'transaction_note': 'دين فاتورة (إصدار قديم)',
        'created_at': now,
        'is_created_by_me': 0,
        'is_uploaded': 1,
        'is_deleted': 0,
        'transaction_uuid': a['uuid'],
        'sync_uuid': a['uuid'],
        'origin_device_id': a['origin'],
      });
      await DatabaseService().recalculateAndApplyCustomerDebt(cid);
      return {'fails': const [], 'notes': const []};
    case 'recalc':
      await DatabaseService().recalculateAndApplyCustomerDebt(await _id(db, 'customers', 'sync_uuid', a['cust'] as String));
      return {'fails': const [], 'notes': const []};
    case 'clearRestore':
      // إقلاع التطبيق على جهاز بلا مزامنة بعد استعادة نسخة (main.dart)
      await DatabaseService.clearRestoreIfNoSync();
      return {'fails': const [], 'notes': const []};
  }
  throw StateError('unknown gap op $op');
}

// ═══════════════════════ 1) إعادة حفظ فاتورة شراء بمعرّفها ═══════════════════════
// PurchaseService.savePurchaseInvoice بفاتورة لها id: عكس أثر المؤكدة القديمة ثم تطبيق الجديد.

Future<double> _stock(Database db, int pid) async =>
    _d((await db.query('products', columns: ['stock_quantity'], where: 'id = ?', whereArgs: [pid])).first['stock_quantity']);

Future<double> _supDebt(Database db, int sid) async =>
    _d((await db.query('suppliers', columns: ['total_debt_iqd'], where: 'id = ?', whereArgs: [sid])).first['total_debt_iqd']);

Future<int> _newSupplier(PurchaseService ps, String name) {
  final now = DateTime.now();
  return ps.addSupplier(Supplier(name: '$name ${now.microsecondsSinceEpoch}', createdAt: now, updatedAt: now));
}

Future<_R> _purResave(Database db, String prod) async {
  final r = _R();
  final ps = PurchaseService();
  final pid = await _id(db, 'products', 'sync_uuid', prod);
  final sid = await _newSupplier(ps, 'مورد إعادة الحفظ');
  final now = DateTime.now();
  PurchaseInvoice head(double total, String status, {int? id}) =>
      PurchaseInvoice(id: id, invoiceNumber: 'G-RESAVE', supplierId: sid, totalAmount: total, status: status, date: now);
  List<PurchaseInvoiceItem> lines(double q) =>
      [PurchaseInvoiceItem(productId: pid, unitName: 'قطعة', quantity: q, unitPrice: 1000, totalPrice: q * 1000)];
  Future<int> lineCount(int id) async =>
      ((await db.rawQuery('SELECT COUNT(*) AS n FROM purchase_invoice_items WHERE invoice_id = ?', [id])).first['n'] as num)
          .toInt();

  final s0 = await _stock(db, pid);
  await ps.savePurchaseInvoice(head(5000, 'draft'), lines(5));
  final id = (await ps.getInvoicesForSupplier(sid)).first.id!;
  r.eq('المسودة: دين المورد', await _supDebt(db, sid), 0);
  r.eq('المسودة: المخزون', await _stock(db, pid), s0);

  // تأكيد المسودة بإعادة حفظها بمعرّفها
  await ps.savePurchaseInvoice(head(5000, 'draft', id: id), lines(5), confirm: true);
  r.eq('بعد التأكيد: دين المورد', await _supDebt(db, sid), 5000);
  r.eq('بعد التأكيد: المخزون', await _stock(db, pid), s0 + 5);
  r.eq('بعد التأكيد: أسطر الفاتورة', await lineCount(id), 1);

  // إعادة حفظ المؤكدة بكمية 7: يُعكس القديم ثم يُطبَّق الجديد (لا مضاعفة)
  await ps.savePurchaseInvoice(head(7000, 'confirmed', id: id), lines(7));
  r.eq('بعد التعديل إلى 7: دين المورد', await _supDebt(db, sid), 7000);
  r.eq('بعد التعديل إلى 7: المخزون', await _stock(db, pid), s0 + 7);
  r.eq('بعد التعديل إلى 7: أسطر الفاتورة', await lineCount(id), 1);

  // إعادة الحفظ نفسها مرة ثانية: لا يتغير شيء
  await ps.savePurchaseInvoice(head(7000, 'confirmed', id: id), lines(7));
  r.eq('إعادة الحفظ بلا تغيير: دين المورد', await _supDebt(db, sid), 7000);
  r.eq('إعادة الحفظ بلا تغيير: المخزون', await _stock(db, pid), s0 + 7);

  // إرجاعها مسودة: يُعكس أثرها كاملاً
  await ps.savePurchaseInvoice(head(7000, 'draft', id: id), lines(7));
  r.eq('بعد إرجاعها مسودة: دين المورد', await _supDebt(db, sid), 0);
  r.eq('بعد إرجاعها مسودة: المخزون', await _stock(db, pid), s0);
  r.notes.add('مسودة ← مؤكدة ← 7 ← 7 ← مسودة: الدين 0/5000/7000/7000/0 والمخزون كذلك');
  return r;
}

// ═══════════════════════ 2) إلغاء دفعة مورد من إصدار قديم ═══════════════════════
// PurchaseService.voidPayment: أثر الدفعة في دفتر المورد بلا معرّفها الثابت (spay_N) —
// يُعثر عليه برقم الدفعة. وإن لم يُعثر على أي أثر: يُرفض ولا يتغير الرصيد.

Future<_R> _supVoidLegacy(Database db, String prod) async {
  final r = _R();
  final ps = PurchaseService();
  final pid = await _id(db, 'products', 'sync_uuid', prod);
  final sid = await _newSupplier(ps, 'مورد دفعة قديمة');
  final now = DateTime.now();
  await ps.savePurchaseInvoice(
      PurchaseInvoice(invoiceNumber: 'G-LEGACY', supplierId: sid, totalAmount: 10000, status: 'confirmed', date: now),
      [PurchaseInvoiceItem(productId: pid, unitName: 'قطعة', quantity: 10, unitPrice: 1000, totalPrice: 10000)]);
  final box = await db.rawQuery('SELECT id FROM cash_boxes ORDER BY is_default DESC, id LIMIT 1');
  final boxId = box.isEmpty ? null : box.first['id'] as int;
  Future<int> pay(double amount) async {
    await ReceiptsService().supplierPayment(
        supplierId: sid, amount: amount, currency: 'IQD', method: 'cash', date: now, cashBoxId: boxId);
    final list = await ps.getPaymentsForSupplier(sid);
    list.sort((x, y) => (y.id ?? 0).compareTo(x.id ?? 0));
    return list.first.id!;
  }

  // أ) صف من إصدار قديم: بلا المعرّف الثابت، مربوط برقم الدفعة
  final p1 = await pay(4000);
  r.eq('بعد دفعة 4,000', await _supDebt(db, sid), 6000);
  final n1 = await db.rawUpdate('UPDATE supplier_transactions SET transaction_uuid = NULL WHERE transaction_uuid = ?',
      [SupplierDebtReconciler.paymentUuid(p1)]);
  r.eq('صف الدفعة الذي حُوِّل إلى صيغة قديمة', n1, 1);
  await ps.voidPayment(p1, reason: 'اختبار صف قديم');
  r.eq('بعد إلغاء الدفعة القديمة: الدين', await _supDebt(db, sid), 10000);
  final del = await db.rawQuery(
      'SELECT COALESCE(is_deleted, 0) AS d FROM supplier_transactions WHERE payment_id = ?', [p1]);
  r.isTrue('أثر الدفعة القديمة في الدفتر لم يُبطَل', del.isNotEmpty && _d(del.first['d']) == 1);
  await r.throws('إلغاء الدفعة القديمة مرتين', () => ps.voidPayment(p1));

  // ب) صف بلا أي ربط: الإلغاء يُرفض، والدفعة تبقى سارية، والرصيد لا يتغير
  final p2 = await pay(3000);
  r.eq('بعد دفعة 3,000', await _supDebt(db, sid), 7000);
  await db.rawUpdate('UPDATE supplier_transactions SET transaction_uuid = NULL, payment_id = NULL WHERE transaction_uuid = ?',
      [SupplierDebtReconciler.paymentUuid(p2)]);
  await r.throws('إلغاء دفعة بلا أثر معروف في الدفتر', () => ps.voidPayment(p2));
  r.eq('بعد رفض الإلغاء: الدين', await _supDebt(db, sid), 7000);
  final v = await db.query('supplier_payments', columns: ['is_void'], where: 'id = ?', whereArgs: [p2]);
  r.isTrue('الدفعة صارت «ملغاة» رغم رفض الإلغاء', _d(v.first['is_void']) == 0);
  r.notes.add('صف قديم: أُلغي بالرقم والدين عاد 10,000؛ صف بلا ربط: رُفض والدين 7,000');
  return r;
}

// ═══════════════════════ 3) دمج حسابين مكررين ═══════════════════════

/// حساب مكرر كما تتركه الإصدارات القديمة (قبل قيد «الاسم فريد»): يُسقط القيد ويُدرج صفاً.
Future<String> _dupCustomer(Database db, String name) async {
  await CustomerNameRule.dropUniqueIndex(db);
  final uuid = 'dup-${DateTime.now().microsecondsSinceEpoch}';
  final m = Customer(name: name).toMap()
    ..remove('id')
    ..['sync_uuid'] = uuid;
  await db.insert('customers', m);
  DatabaseService().invalidateCustomersCache();
  return uuid;
}

Future<Map<String, Object?>> _merge(Database db, String survivor, List<String> merged) async {
  try {
    final res = await CustomerMergeService.merge(
      await _id(db, 'customers', 'sync_uuid', survivor),
      [for (final u in merged) await _id(db, 'customers', 'sync_uuid', u)],
    );
    return {
      'ok': true,
      'before': res.result.balanceBefore,
      'after': res.result.balanceAfter,
      'index': res.result.uniqueIndexActive,
    };
  } catch (e) {
    return {'ok': false, 'err': '$e'};
  }
}

// ═══════════════════════ 4) نقاط المؤسسين ═══════════════════════

Future<FounderStats?> _founder(String name) async {
  for (final f in await FounderService.loadAll()) {
    if (f.name == name) return f;
  }
  return null;
}

/// «تسديد دين راجع» يخصم من نقاط مؤسس الفاتورة نسبةً، ولا يخصم أكثر مما أُعطي؛ وحذف حركة
/// الخصم يعيد نقاطها ويحرّر نصيبها من الراجع.
Future<_R> _founderReturn(Database db, String invUuid) async {
  final r = _R();
  final invId = await _id(db, 'invoices', 'invoice_uuid', invUuid);
  const name = 'فني الاختبار';
  var f = await _founder(name);
  if (f == null) {
    r.fails.add('المؤسس لا يظهر (فاتورة بمليون ومعدل 1)');
    return r;
  }
  r.eq('نقاط فاتورة بمليون بمعدل 1', f.balance, 10);

  final p1 = await FounderService.deductForReturnedPayment(invoiceId: invId, amount: 200000, customer: 'زبون المؤسس');
  r.eq('خصم راجع 200,000', p1, 2);
  final p2 = await FounderService.deductForReturnedPayment(invoiceId: invId, amount: 900000, customer: 'زبون المؤسس');
  r.eq('خصم راجع 900,000 (المتبقي 8 فقط)', p2, 8);
  final p3 = await FounderService.deductForReturnedPayment(invoiceId: invId, amount: 100000, customer: 'زبون المؤسس');
  r.eq('خصم راجع بعد استنفاد النقاط', p3, 0);
  f = (await _founder(name))!;
  r.eq('الرصيد بعد الخصومات', f.balance, 0);
  final links = await db.rawQuery('SELECT COUNT(*) AS n FROM founder_return_links WHERE invoice_id = ?', [invId]);
  r.eq('روابط الراجع المسجّلة', _d(links.first['n']), 3);

  await FounderService.addMove(f, 5, 'مكافأة اختبار');
  f = (await _founder(name))!;
  r.eq('بعد إضافة 5 يدوياً', f.balance, 5);

  final first = f.moves.where((m) => m.isReturnDeduction).toList()..sort((a, b) => a.id.compareTo(b.id));
  if (first.isEmpty) {
    r.fails.add('لا حركة «تسديد دين راجع» في سجل المؤسس');
    return r;
  }
  await FounderService.deleteMove(first.first.id);
  f = (await _founder(name))!;
  r.eq('بعد حذف حركة خصم النقطتين', f.balance, 7);
  final (amt, pts) = await FounderService.returnedOn(invId);
  r.eq('الراجع المسجّل على الفاتورة بعد الحذف (مبلغ)', amt, 1000000);
  r.eq('الراجع المسجّل على الفاتورة بعد الحذف (نقاط)', pts, 8);
  r.eq('معاينة خصم 200,000 بعد الحذف', await FounderService.previewReturnDeduction(invId, 200000), 2);
  r.notes.add('10 نقاط ← خصم 2 ثم 8 ثم 0 ← +5 ← حذف خصم 2 = 7');
  return r;
}

/// قاعدة مستوردة من البرنامج السابق: رصيد المؤسس يوم الاستيراد (installers.total_points) يُعتمد،
/// والفرق عمّا تحسبه الناصر يُحفظ مرة واحدة «فرق رصيد منقول».
Future<_R> _founderImported(Database db, String invUuid) async {
  final r = _R();
  final invId = await _id(db, 'invoices', 'invoice_uuid', invUuid);
  const name = 'مؤسس مستورد';
  await FounderService.loadAll(); // ينشئ جداول المؤسسين إن لم توجد
  await db.update('invoices', {'invoice_date': '2026-01-01T10:00:00.000'}, where: 'id = ?', whereArgs: [invId]);
  await db.rawInsert('INSERT OR IGNORE INTO installers (name, created_at) VALUES (?, ?)', [name, '2026-01-01T00:00:00.000']);
  await db.rawUpdate('UPDATE installers SET total_points = 30 WHERE name = ?', [name]);
  final insId = await _id(db, 'installers', 'name', name);
  await db.insert('installer_points', {
    'installer_id': insId,
    'invoice_id': invId,
    'points': 12,
    'reason': 'فاتورة قديمة',
    'created_at': '2026-01-02T00:00:00.000',
  });

  var f = await _founder(name);
  r.eq('رصيد المؤسس المستورد = رصيده في البرنامج السابق', f?.balance ?? -1, 30);
  final op = await db.rawQuery('SELECT name, points FROM founder_opening ORDER BY name');
  final diff = op.where((x) => x['name'] == name).toList();
  r.isTrue('فرق الرصيد المنقول لم يُحفظ', diff.length == 1);
  if (diff.isNotEmpty) r.eq('فرق الرصيد المنقول', _d(diff.first['points']), 18);

  f = await _founder(name);
  r.eq('فتح ثانٍ: الرصيد', f?.balance ?? -1, 30);
  final n = await db.rawQuery('SELECT COUNT(*) AS n FROM founder_opening');
  r.eq('فتح ثانٍ: لا يُحفظ الفرق مرة أخرى', _d(n.first['n']), op.length);
  r.eq('مؤسس الناصر لم يتأثر بالاستيراد', (await _founder('فني الاختبار'))?.balance ?? -1, 7);
  r.notes.add('مسجّل 12 + فرق 18 = 30، ولا يتكرر الفرق');
  return r;
}

// ═══════════════════════ 5) زر الإصلاح في الفحص العميق ═══════════════════════

Future<double> _custDebt(Database db, int cid) async =>
    _d((await db.query('customers', columns: ['current_total_debt'], where: 'id = ?', whereArgs: [cid])).first['current_total_debt']);

Future<Map<String, Object?>> _invRow(Database db, int id) async => (await db.query('invoices',
        columns: ['customer_id', 'amount_paid_on_invoice', 'payment_type', 'version', 'is_synced', 'restored_mark'],
        where: 'id = ?',
        whereArgs: [id]))
    .first;

/// مسدد الفاتورة كما تتركه بيانات قديمة/معطوبة (والسنتات إن وُجد عمودها).
Future<void> _setPaid(Database db, int id, double paid, [Map<String, Object?> extra = const {}]) async {
  final cols = (await db.rawQuery('PRAGMA table_info(invoices)')).map((c) => c['name']).toSet();
  await db.update(
      'invoices',
      {
        'amount_paid_on_invoice': paid,
        if (cols.contains('amount_paid_cents')) 'amount_paid_cents': (paid * 100).round(),
        ...extra,
      },
      where: 'id = ?',
      whereArgs: [id]);
}

/// «اعتمد سجل الديون»: الفاتورة تقول مسدد 4,000 والسجل يقول دينها 10,000 كاملاً ⇒ تُصحَّح
/// الفاتورة (المسدد 0) ولا يتغير أي دين.
Future<_R> _repairLedger(Database db, String invUuid) async {
  final r = _R();
  final id = await _id(db, 'invoices', 'invoice_uuid', invUuid);
  final cid = (await _invRow(db, id))['customer_id'] as int;
  final debt0 = await _custDebt(db, cid);
  await _setPaid(db, id, 4000);
  final info = await DeepCheckRepair.load(db, id);
  r.isTrue('الفحص لم يكشف اختلاف الفاتورة عن السجل', info != null && !info.consistent);
  r.isTrue('«اعتمد سجل الديون» محجوب: ${info?.ledgerTruthBlock}', info?.ledgerTruthBlock == null);
  final v0 = _d((await _invRow(db, id))['version'] ?? 1); // بلا رقم نسخة = 1 (COALESCE في التطبيق)
  final applied = await DeepCheckRepair.applyLedgerTruth(db, id, user: 'اختبار');
  r.eq('المسدد بعد التصحيح', applied.paid, 0);
  final row = await _invRow(db, id);
  r.eq('مسدد الفاتورة المخزّن', _d(row['amount_paid_on_invoice']), 0);
  r.isTrue('نوع الفاتورة بعد التصحيح ${row['payment_type']}', row['payment_type'] == 'دين');
  r.eq('نسخة الفاتورة زادت (لتصل الأجهزة الأخرى)', _d(row['version']), v0 + 1);
  r.eq('الفاتورة عادت للرفع', _d(row['is_synced']), 0);
  r.eq('دين العميل لم يتغير', await _custDebt(db, cid), debt0);
  r.isTrue('بعد التصحيح ما زالت غير متطابقة', (await DeepCheckRepair.load(db, id))?.consistent == true);
  r.notes.add('مسدد 4,000 ← 0، الدين $debt0 كما هو، النسخة ${v0.toInt()} ← ${(v0 + 1).toInt()}');
  return r;
}

/// «اعتمد الفاتورة» على فاتورة ما زالت من نسخة احتياطية مستعادة: يُضبط السجل عليها، وتُعاد
/// للرفع بلا زيادة نسختها (كي لا تبدو أحدث من نسخة السحابة الحقيقية).
Future<_R> _repairRestored(Database db, String invUuid) async {
  final r = _R();
  final id = await _id(db, 'invoices', 'invoice_uuid', invUuid);
  final cid = (await _invRow(db, id))['customer_id'] as int;
  final debt0 = await _custDebt(db, cid);
  await _setPaid(db, id, 4000, {'restored_mark': 1, 'is_synced': 1});
  final v0 = _d((await _invRow(db, id))['version'] ?? 1); // بلا رقم نسخة = 1 (COALESCE في التطبيق)
  try {
    final res = await DeepCheckRepair.applyInvoiceTruth(db, id, user: 'اختبار');
    r.isTrue('لم يُعَد رصيد العميل قبل/بعد', res.containsKey(cid));
    r.eq('دين العميل بعد اعتماد الفاتورة', await _custDebt(db, cid), debt0 - 4000);
    final row = await _invRow(db, id);
    r.eq('نسخة الفاتورة المستعادة لم تتغير', _d(row['version'] ?? 1), v0);
    r.eq('الفاتورة المستعادة عادت للرفع', _d(row['is_synced']), 0);
    r.isTrue('بعد الضبط ما زالت غير متطابقة', (await DeepCheckRepair.load(db, id))?.consistent == true);
    r.notes.add('مسدد 4,000 معتمد: الدين ${debt0.toInt()} ← ${(debt0 - 4000).toInt()}، النسخة ${v0.toInt()} كما هي');
  } finally {
    await db.update('invoices', {'restored_mark': 0}, where: 'id = ?', whereArgs: [id]);
  }
  return r;
}

// ═══════════════════════ 6) صندوق ومخزن الجهاز على فاتورة الكاشير ═══════════════════════

/// DeviceDefaults.stampInvoice: فاتورة الكاشير تُختم بصندوق الجهاز ومخزنه، فيُرحَّل المقبوض
/// إلى حساب صندوقه. لا يُغيَّر ختم موجود.
Future<_R> _posStamp(Database db, String prod) async {
  final r = _R();
  final pid = await _id(db, 'products', 'sync_uuid', prod);
  final p = (await db.query('products', where: 'id = ?', whereArgs: [pid], limit: 1)).first;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final box = await VouchersService().createCashBox('صندوق الطرفية $stamp');
  final wh = await OrgService().saveWarehouse(name: 'مخزن الطرفية $stamp');
  final boxAcc = (await db.query('cash_boxes', columns: ['account_id'], where: 'id = ?', whereArgs: [box])).first['account_id'];
  try {
    await DeviceDefaults.set(cashBoxId: box, warehouseId: wh);
    final id = await DatabaseService().createPosInvoice(
      items: [
        {
          'product_id': pid,
          'product_name': p['name'],
          'quantity': 2.0,
          'price': 2500.0,
          'unit': 'قطعة',
          'cost_price': _d(p['cost_price']),
          'sale_type': 'قطعة',
          'units_in_large_unit': 1.0,
        }
      ],
      totalAmount: 5000,
      paymentType: 'نقد',
      discount: 0,
      paidAmount: 5000,
    );
    var row = (await db.query('invoices', columns: ['cash_box_id', 'warehouse_id'], where: 'id = ?', whereArgs: [id])).first;
    r.eq('صندوق فاتورة الكاشير', _d(row['cash_box_id']), box);
    r.eq('مخزن فاتورة الكاشير', _d(row['warehouse_id']), wh);

    await PostingEngine().syncAll();
    final cash = await db.rawQuery(
        'SELECT COALESCE(SUM(l.debit), 0) AS d FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id '
        "WHERE e.source_type = 'invoice' AND e.source_id = ? AND l.account_id = ?",
        [id, boxAcc]);
    r.eq('المقبوض مرحَّل إلى حساب صندوق الطرفية', _d(cash.first['d']), 5000);

    // ختم موجود لا يُغيَّر
    final other = await VouchersService().createCashBox('صندوق آخر $stamp');
    await db.update('invoices', {'cash_box_id': other}, where: 'id = ?', whereArgs: [id]);
    await DeviceDefaults.stampInvoice(id);
    row = (await db.query('invoices', columns: ['cash_box_id'], where: 'id = ?', whereArgs: [id])).first;
    r.eq('ختم موجود بقي كما هو', _d(row['cash_box_id']), other);
    r.notes.add('فاتورة كاشير 5,000 خُتمت بصندوق ومخزن الطرفية ورُحّلت إلى صندوقها؛ الختم الموجود لا يتغير');
  } finally {
    await DeviceDefaults.set(); // إعادة الجهاز بلا صندوق ومخزن
  }
  return r;
}

// ═══════════════════════ 7) معاملة فشلت بعد كتابة وصفها ═══════════════════════

/// CustomerMoney.post: إن رُفضت المعاملة بعد كتابة وصفها (customer_tx_ext) يُمحى الوصف —
/// لا يبقى وصف يتيم. (العميل غير موجود: صف حُذف في بيانات قديمة)
Future<_R> _moneyPostFail(Database db) async {
  final r = _R();
  const uuid = 'gap-ext-fail';
  final missing = ((await db.rawQuery('SELECT COALESCE(MAX(id), 0) + 1000 AS n FROM customers')).first['n'] as num).toInt();
  await r.throws(
      'معاملة على عميل غير موجود',
      () => CustomerMoney.post(null,
          provider: AppProvider(),
          customerId: missing,
          amount: -1000,
          kind: CustomerTxKind.cash,
          note: 'اختبار وصف يتيم',
          presetUuid: uuid));
  final ext = await db.rawQuery('SELECT COUNT(*) AS n FROM customer_tx_ext WHERE transaction_uuid = ?', [uuid]);
  r.eq('وصف يتيم بقي بعد فشل المعاملة', _d(ext.first['n']), 0);
  final tx = await db.rawQuery('SELECT COUNT(*) AS n FROM transactions WHERE transaction_uuid = ?', [uuid]);
  r.eq('معاملة سُجّلت رغم الرفض', _d(tx.first['n']), 0);
  r.notes.add('رُفضت المعاملة ومُحي وصفها');
  return r;
}

// ═══════════════════════ 8) تثبيت كلفة ما بيع قبل تغيّر كلفة المادة ═══════════════════════

/// UsdCostService.freezePastCosts: بند فاتورة قديم بلا كلفة محفوظة يأخذ كلفة المادة الآن،
/// فلا يتغيّر ربح الفاتورة حين تتغيّر كلفة المادة بعدها.
Future<_R> _freezeCosts(Database db, String invUuid) async {
  final r = _R();
  final invId = await _id(db, 'invoices', 'invoice_uuid', invUuid);
  final item = (await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invId], limit: 1)).first;
  final pid = await _id(db, 'products', 'name', '${item['product_name']}');
  final qty = _d(item['quantity_individual']);
  await db.update('products', {'cost_price': 500.0}, where: 'id = ?', whereArgs: [pid]);
  await db.update('invoice_items', {'actual_cost_price': null}, where: 'invoice_id = ?', whereArgs: [invId]); // بند قديم
  final res = await UsdCostService.freezePastCosts(db, {pid});
  r.isTrue('لم يُثبَّت أي بند', res.items >= 1);
  final frozen = _d((await db.query('invoice_items', columns: ['actual_cost_price'], where: 'id = ?', whereArgs: [item['id']]))
      .first['actual_cost_price']);
  r.eq('كلفة البند المثبّتة للوحدة', frozen, 500);
  await db.update('products', {'cost_price': 900.0}, where: 'id = ?', whereArgs: [pid]); // ارتفعت الكلفة بعدها
  r.eq('كلفة الفاتورة بعد ارتفاع كلفة المادة', await PostingEngine.invoiceCostOf(db, invId, 0.1), 500 * qty);
  final again = await UsdCostService.freezePastCosts(db, {pid});
  r.eq('تثبيت ثانٍ لا يغيّر بنداً مثبّتاً', again.items, 0);
  r.notes.add('بند بلا كلفة ← 500، وبقي 500 بعد ارتفاع كلفة المادة إلى 900');
  return r;
}

// ═══════════════════════ 9) قيد فاتورة بلا كلفة ولا مقبوض ═══════════════════════

/// PostingEngine: فاتورة آجلة بقيمة صفر بلا بنود (يحفظها إصدار قديم أو استيراد — التطبيق
/// الحالي يرفض فاتورة إجماليها صفر) ⇒ لا كلفة ولا مقبوض ⇒ قيد صفري بلا أسطر يثبّت بصمتها:
/// لا يُعاد إنشاؤه كل مرة، ولا يغيّر الميزان.
Future<_R> _zeroEntry(Database db, String baseUuid) async {
  final r = _R();
  final base = (await db.query('invoices', where: 'invoice_uuid = ?', whereArgs: [baseUuid], limit: 1)).first;
  final cols = (await db.rawQuery('PRAGMA table_info(invoices)')).map((c) => '${c['name']}').toSet();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final legacy = <String, Object?>{
    ...base,
    'payment_type': 'دين',
    'total_amount': 0.0,
    'amount_paid_on_invoice': 0.0,
    'discount': 0.0,
    'loading_fee': 0.0,
    'return_amount': 0.0,
    'invoice_uuid': 'legacy-zero-$stamp',
    'invoice_number': 'Q-$stamp',
    'monthly_sequence_number': 900000 + stamp % 90000,
    if (cols.contains('total_amount_cents')) 'total_amount_cents': 0,
    if (cols.contains('amount_paid_cents')) 'amount_paid_cents': 0,
    if (cols.contains('discount_cents')) 'discount_cents': 0,
    if (cols.contains('final_total')) 'final_total': 0.0,
    if (cols.contains('cash_box_id')) 'cash_box_id': null,
  }
    ..remove('id')
    ..remove('serial_number');
  final id = await db.insert('invoices', legacy);
  Future<List<Map<String, Object?>>> entries() =>
      db.query('journal_entries', where: "source_type = 'invoice' AND source_id = ?", whereArgs: [id]);
  Future<double> lines() async => _d((await db.rawQuery(
          'SELECT COUNT(*) AS n FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id '
          "WHERE e.source_type = 'invoice' AND e.source_id = ?",
          [id]))
      .first['n']);
  Future<double> imbalance() async => _d((await db.rawQuery(
          'SELECT COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) AS x FROM journal_lines'))
      .first['x']);

  await PostingEngine().syncAll();
  var e = await entries();
  r.eq('قيود الفاتورة', e.length, 1);
  if (e.isNotEmpty) r.eq('رقم القيد الصفري', _d(e.first['entry_number']), 0);
  r.eq('أسطر قيد الفاتورة', await lines(), 0);
  r.eq('الميزان بعد الترحيل (مدين − دائن)', await imbalance(), 0);
  await PostingEngine().syncAll();
  e = await entries();
  r.eq('ترحيل ثانٍ: قيود الفاتورة', e.length, 1);
  r.notes.add('قيد صفري واحد بلا أسطر، والميزان متوازن، ولا يتكرر');
  return r;
}

// ═══════════════════════ 10) حقول الفاتورة الإضافية: البائع وعمولته ═══════════════════════

Future<_R> _extras(Database db, String invUuid) async {
  final r = _R();
  final id = await _id(db, 'invoices', 'invoice_uuid', invUuid);
  final total =
      _d((await db.query('invoices', columns: ['total_amount'], where: 'id = ?', whereArgs: [id])).first['total_amount']);
  final svc = InvoiceExtrasService();
  final name = 'بائع الاختبار ${DateTime.now().microsecondsSinceEpoch}';
  await svc.saveSeller(name: name, commission: 5);
  final seller = (await svc.sellers()).firstWhere((x) => x.name == name);
  await svc.save(id, seller: seller, deliveryMethod: 'توصيل');
  var row = await svc.get(id);
  r.eq('عمولة 5٪ من صافي الفاتورة', _d(row?['commission_amount']), (total * 5 / 100).roundToDouble());
  await svc.save(id, seller: seller, commissionAmount: 3000);
  row = await svc.get(id);
  r.eq('عمولة مكتوبة يدوياً', _d(row?['commission_amount']), 3000);
  r.eq('صف الحقول الإضافية واحد',
      _d((await db.rawQuery('SELECT COUNT(*) AS n FROM invoice_extras WHERE invoice_id = ?', [id])).first['n']), 1);
  await r.throws('عمولة سالبة', () => svc.save(id, seller: seller, commissionAmount: -1));
  try {
    await PeriodLock.setLockDate(DateTime.now().add(const Duration(days: 1)));
    await r.throws('تعديل حقول فاتورة داخل فترة مثبّتة', () => svc.save(id, seller: seller, commissionAmount: 100));
  } finally {
    await PeriodLock.setLockDate(null);
  }
  row = await svc.get(id);
  r.eq('العمولة بعد المحاولات المرفوضة', _d(row?['commission_amount']), 3000);
  r.notes.add('5٪ = ${(total * 0.05).round()} ← يدوياً 3,000؛ السالب والفترة المثبّتة مرفوضان');
  return r;
}

// ═══════════════════════ 11) عملاء ليسوا في سجل الديون ═══════════════════════

/// معاملات بقيت لعميل حُذف صفّه (إصدار قديم بلا قيود ربط) أو أُخفي ⇒ يكشفها الفحص، وتعيده
/// «الاستعادة» برقمه ورصيده = مجموع معاملاته، بلا تغيير أي معاملة.
Future<_R> _orphans(Database db, String goneUuid, String hiddenUuid) async {
  final r = _R();
  final gone = await _id(db, 'customers', 'sync_uuid', goneUuid);
  final hidden = await _id(db, 'customers', 'sync_uuid', hiddenUuid);
  Future<Map<String, Object?>> txStats() async => (await db.rawQuery(
          'SELECT COUNT(*) AS n, COALESCE(SUM(amount_changed), 0) AS s FROM transactions WHERE COALESCE(is_deleted, 0) = 0'))
      .first;
  final before = await txStats();
  await db.execute('PRAGMA foreign_keys = OFF');
  try {
    await db.delete('customers', where: 'id = ?', whereArgs: [gone]);
  } finally {
    await db.execute('PRAGMA foreign_keys = ON');
  }
  await db.update('customers', {'is_deleted': 1}, where: 'id = ?', whereArgs: [hidden]);

  final found = (await AccountingReports().orphanCustomerDebts())
      .where((o) => o.customerId == gone || o.customerId == hidden)
      .toList();
  r.eq('العملاء المكشوفون', found.length, 2);
  for (final o in found) {
    r.eq('دين ${o.customerId == gone ? 'المحذوف' : 'المخفي'} المكشوف', o.total, o.customerId == gone ? 2500 : 700);
  }
  r.eq('المستعادون', await OrphanDebtsService.restore(found), 2);

  final g = await db.query('customers', where: 'id = ?', whereArgs: [gone]);
  r.isTrue('المحذوف لم يُعَد برقمه', g.length == 1);
  if (g.isNotEmpty) {
    r.isTrue('اسم المستعاد «${g.first['name']}»', '${g.first['name']}'.startsWith('عميل مستعاد #$gone'));
    r.eq('دين المستعاد', _d(g.first['current_total_debt']), 2500);
  }
  final h = (await db.query('customers', where: 'id = ?', whereArgs: [hidden])).first;
  r.eq('المخفي ظهر', _d(h['is_deleted']), 0);
  r.eq('دين المخفي بعد ظهوره', _d(h['current_total_debt']), 700);
  final left =
      (await AccountingReports().orphanCustomerDebts()).where((o) => o.customerId == gone || o.customerId == hidden);
  r.isTrue('بقي في الفحص بعد الاستعادة', left.isEmpty);
  final after = await txStats();
  r.eq('عدد المعاملات لم يتغير', _d(after['n']), _d(before['n']));
  r.eq('مجموع المعاملات لم يتغير', _d(after['s']), _d(before['s']));
  r.notes.add('محذوف 2,500 ومخفي 700 عادا برقميهما، ولم تتغير أي معاملة');
  return r;
}

// ═══════════════════════ 12) ربط فواتير النقد القديمة بعملائها ═══════════════════════

/// DatabaseService.updateOldInvoicesWithCustomerIds (يعمل عند فتح شاشة العميل): فاتورة نقدية
/// قديمة بلا عميل تُربط بالعميل الذي يحمل اسمها (بتجاهل المسافات)، ولا يتغير أي دين.
Future<_R> _linkOldCash(Database db, String invUuid, String custUuid) async {
  final r = _R();
  final id = await _id(db, 'invoices', 'invoice_uuid', invUuid);
  final cid = await _id(db, 'customers', 'sync_uuid', custUuid);
  final name = '${(await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [cid])).first['name']}';
  final debt0 = await _custDebt(db, cid);
  // فاتورة من إصدار قديم: بلا عميل، واسمها بمسافة زائدة
  await db.update('invoices', {'customer_id': null, 'customer_name': name.replaceFirst(' ', '  ')},
      where: 'id = ?', whereArgs: [id]);
  await DatabaseService().updateOldInvoicesWithCustomerIds();
  final row = (await db.query('invoices', columns: ['customer_id'], where: 'id = ?', whereArgs: [id])).first;
  r.eq('الفاتورة رُبطت بعميلها', _d(row['customer_id']), cid);
  r.eq('دين العميل لم يتغير', await _custDebt(db, cid), debt0);
  r.notes.add('فاتورة نقدية بلا عميل رُبطت بـ «$name» ودينه كما هو');
  return r;
}

// ═══════════════════════ 14) الفاتورة العادية تُختم بصندوق الحاسبة ومخزنها ═══════════════════════

/// شاشة «إنشاء فاتورة» (InvoiceController) كفاتورة الكاشير: الفاتورة الجديدة، والمعلّقة حين
/// تُحفظ، تُختمان بصندوق الحاسبة ومخزنها داخل معاملة الحفظ ⇒ المقبوض في حساب صندوقها،
/// والكمية من مخزنها. تعديلها لاحقاً لا يغيّر ختمها ولو تغيّر صندوق الحاسبة.
Future<_R> _regularStamp(Database db, String prod) async {
  final r = _R();
  final pid = await _id(db, 'products', 'sync_uuid', prod);
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final box = await VouchersService().createCashBox('درج الحاسبة $stamp');
  final box2 = await VouchersService().createCashBox('درج آخر $stamp');
  final wh = await OrgService().saveWarehouse(name: 'مخزن الحاسبة $stamp');
  Future<Object?> acc(int b) async =>
      (await db.query('cash_boxes', columns: ['account_id'], where: 'id = ?', whereArgs: [b])).first['account_id'];
  Future<Map<String, Object?>> head(int id) async =>
      (await db.query('invoices', columns: ['cash_box_id', 'warehouse_id'], where: 'id = ?', whereArgs: [id])).first;
  // مقبوض الفاتورة في صندوق: قيدها + قيود تعديلاتها (تُرحَّل بتاريخها إلى صندوق الفاتورة)
  Future<double> cashIn(int id, int b) async => _d((await db.rawQuery(
          'SELECT COALESCE(SUM(l.debit), 0) - COALESCE(SUM(l.credit), 0) AS d FROM journal_lines l '
          'JOIN journal_entries e ON e.id = l.entry_id '
          "WHERE ((e.source_type = 'invoice' AND e.source_id = ?) OR (e.source_type = 'invoice_edit' AND "
          'e.source_id IN (SELECT ev.id FROM invoice_edit_events ev WHERE ev.invoice_id = ?))) AND l.account_id = ?',
          [id, id, await acc(b)]))
      .first['d']);
  Future<String> save(String name, double qty, double paid, {String? inv}) async {
    final res = (await scenOp('invSave', {
      'inv': inv,
      'name': name,
      'items': [
        {'prodId': pid, 'qty': qty, 'price': 3000}
      ],
      'discount': 0,
      'fee': 0,
      'paid': paid,
      'ptype': 'نقد',
    })) as Map;
    if (res['ok'] != true) throw StateError('حفظ الفاتورة رُفض: ${res['stage']} ${res['err']}');
    return res['uuid'] as String;
  }

  try {
    await DeviceDefaults.set(cashBoxId: box, warehouseId: wh);
    final whBefore = await ErpStock.available(db, pid, warehouseId: wh);

    // أ) فاتورة جديدة من الشاشة العادية
    final inv = await save('زبون الحاسبة', 2, 6000);
    final id = await _id(db, 'invoices', 'invoice_uuid', inv);
    var h = await head(id);
    r.eq('صندوق الفاتورة العادية', _d(h['cash_box_id']), box);
    r.eq('مخزن الفاتورة العادية', _d(h['warehouse_id']), wh);
    await PostingEngine().syncAll();
    r.eq('مقبوض الفاتورة في صندوق الحاسبة', await cashIn(id, box), 6000);
    r.eq('كمية مخزن الحاسبة بعد بيع 2', await ErpStock.available(db, pid, warehouseId: wh), whBefore - 2);

    // ب) تغيّر صندوق الحاسبة ثم عُدّلت الفاتورة: ختمها لا يتغير
    await DeviceDefaults.set(cashBoxId: box2, warehouseId: wh);
    await save('زبون الحاسبة', 3, 9000, inv: inv);
    h = await head(id);
    r.eq('صندوق الفاتورة بعد تعديلها', _d(h['cash_box_id']), box);
    await PostingEngine().syncAll();
    r.eq('مقبوض الفاتورة بعد تعديلها (في صندوقها الأول)', await cashIn(id, box), 9000);
    r.eq('لا شيء منها في الصندوق الجديد', await cashIn(id, box2), 0);

    // ج) فاتورة معلّقة تُختم حين تُحفظ
    final p = (await db.query('products', where: 'id = ?', whereArgs: [pid], limit: 1)).first;
    final held = await HeldInvoices.hold(
      existing: null,
      items: [
        InvoiceItem(
          invoiceId: 0,
          productId: pid,
          productName: p['name'] as String,
          unit: 'piece',
          unitPrice: 3000,
          costPrice: 0.5,
          quantityIndividual: 1,
          appliedPrice: 3000,
          itemTotal: 3000,
          saleType: 'قطعة',
        )
      ],
      customerName: 'زبون المعلّقة',
      invoiceDate: DateTime.now(),
      paymentType: 'نقد',
      discount: 0,
      loadingFee: 0,
      paid: 3000,
    );
    final heldId = held.id!;
    h = await head(heldId);
    r.isTrue('المعلّقة خُتمت قبل حفظها', h['cash_box_id'] == null);
    await save('زبون المعلّقة', 1, 3000, inv: held.invoiceUuid);
    h = await head(heldId);
    r.eq('صندوق المعلّقة بعد حفظها', _d(h['cash_box_id']), box2);
    r.notes.add('فاتورة عادية 6,000 في درج الحاسبة ومخزنها؛ تعديلها إلى 9,000 بقي في درجها الأول؛ '
        'المعلّقة خُتمت عند حفظها');
  } finally {
    await DeviceDefaults.set();
  }
  return r;
}

// ═══════════════════════ 15) إلغاء دورة إهلاك وحذف الأصل ═══════════════════════

/// الأصول الثابتة: أصل عليه إهلاك مرحّل لا يُحذف؛ إلغاء دورة الإهلاك يرفع المانع، ثم يُحذف.
/// (كان هذا يمر به اختبار التعذيب عشوائياً فقط — هنا بأرقام ثابتة كل مرة.)
Future<_R> _assets(Database db) async {
  final r = _R();
  final now = DateTime.now();
  final prev = DateTime(now.year, now.month - 1, 1);
  final period = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
  final id = await FixedAssetsService.create(
    name: 'أصل الاختبار ${now.microsecondsSinceEpoch}',
    acquiredOn: now.subtract(const Duration(days: 100)), // الشهر السابق داخل عمر الأصل
    cost: 1200000,
    salvage: 0,
    lifeMonths: 12,
    funding: AssetFunding.opening,
  );
  final run = await FixedAssetsService.runPeriod(period);
  r.isTrue('دورة الإهلاك لم تُرحِّل الأصل', await FixedAssetsService.hasDepreciation(db, id));
  await r.throws('حذف أصل عليه إهلاك مرحّل', () => FixedAssetsService.delete(id));
  r.eq('الأصل بعد رفض حذفه', (await db.query('fixed_assets', where: 'id = ?', whereArgs: [id])).length, 1);

  await FixedAssetsService.voidRun(run);
  final st = (await db.query('depreciation_runs', columns: ['status'], where: 'id = ?', whereArgs: [run])).first['status'];
  r.isTrue('حالة الدورة بعد الإلغاء «$st»', st == 'void');
  r.isTrue('الإهلاك ما زال محسوباً بعد إلغاء دورته', !await FixedAssetsService.hasDepreciation(db, id));
  await FixedAssetsService.voidRun(run); // إلغاء ثانٍ: لا شيء
  await FixedAssetsService.delete(id);
  r.eq('الأصل بعد حذفه', (await db.query('fixed_assets', where: 'id = ?', whereArgs: [id])).length, 0);
  r.notes.add('إهلاك $period: الحذف مرفوض ← إلغاء الدورة ← الحذف تم');
  return r;
}
