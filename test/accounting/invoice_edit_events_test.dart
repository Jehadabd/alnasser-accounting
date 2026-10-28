// test/accounting/invoice_edit_events_test.dart
//
// ✏️ التعديل بالقلم = عملية بتاريخ يومه، في الدفتر والتقارير، بلا ازدواج.
// التشغيل: flutter test test/accounting/invoice_edit_events_test.dart

import 'package:alnaser/accounting/accounting_reports.dart';
import 'package:alnaser/accounting/accounting_schema.dart';
import 'package:alnaser/accounting/ledger.dart';
import 'package:alnaser/accounting/posting_engine.dart';
import 'package:alnaser/services/invoice_edit_events.dart';
import 'package:alnaser/services/reports/sales_facts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _db() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT,
      current_total_debt REAL DEFAULT 0, is_deleted INTEGER DEFAULT 0)''');
  await db.execute('''CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER)''');
  await db.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, unit TEXT, cost_price REAL,
      length_per_unit REAL, unit_costs TEXT, unit_hierarchy TEXT, category_id INTEGER, stock_quantity REAL DEFAULT 0)''');
  await db.execute('''CREATE TABLE invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, customer_id INTEGER,
      customer_name TEXT, invoice_date TEXT, payment_type TEXT, total_amount REAL, discount REAL DEFAULT 0,
      loading_fee REAL DEFAULT 0, return_amount REAL DEFAULT 0, amount_paid_on_invoice REAL DEFAULT 0, status TEXT,
      is_deleted INTEGER DEFAULT 0, is_created_by_me INTEGER DEFAULT 1)''');
  await db.execute('''CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_name TEXT,
      product_id INTEGER, quantity_individual REAL, quantity_large_unit REAL, units_in_large_unit REAL,
      actual_cost_price REAL, applied_price REAL, sale_type TEXT, item_total REAL)''');
  await db.execute('''CREATE TABLE transactions (id INTEGER PRIMARY KEY, customer_id INTEGER,
      transaction_date TEXT, amount_changed REAL, transaction_type TEXT, invoice_id INTEGER,
      description TEXT, is_deleted INTEGER DEFAULT 0)''');
  await AccountingSchema.ensure(db);

  await db.insert('customers', {'id': 1, 'name': 'أحمد'});
  await db.insert('products', {'id': 1, 'name': 'سلك', 'unit': 'piece', 'cost_price': 700, 'stock_quantity': 100});
  return db;
}

/// فاتورة نقدية: [qty] × 1,000 بكلفة 700.
Future<void> _setItems(Database db, int invoiceId, double qty, {String payment = 'نقد', double paid = 0}) async {
  await db.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
  await db.insert('invoice_items', {
    'invoice_id': invoiceId, 'product_name': 'سلك', 'product_id': 1, 'quantity_individual': qty,
    'quantity_large_unit': 0, 'units_in_large_unit': 1, 'applied_price': 1000, 'sale_type': 'قطعة',
    'item_total': qty * 1000,
  });
  await db.update('invoices', {'total_amount': qty * 1000, 'payment_type': payment, 'amount_paid_on_invoice': paid},
      where: 'id = ?', whereArgs: [invoiceId]);
}

Future<double> _cost(DatabaseExecutor d, int id) => PostingEngine.invoiceCostOf(d, id, 0.1);

/// تعديل كما يفعله حفظ الفاتورة: الحال قبل ← التغيير ← الحال بعد ← الحدث (بتاريخ [on]).
Future<int?> _edit(Database db, int invoiceId, double qty, DateTime on,
    {String payment = 'نقد', double paid = 0}) async {
  int? id;
  await db.transaction((txn) async {
    final before = await InvoiceEditEvents.capture(txn, invoiceId, costOf: _cost);
    await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    await txn.insert('invoice_items', {
      'invoice_id': invoiceId, 'product_name': 'سلك', 'product_id': 1, 'quantity_individual': qty,
      'quantity_large_unit': 0, 'units_in_large_unit': 1, 'applied_price': 1000, 'sale_type': 'قطعة',
      'item_total': qty * 1000,
    });
    await txn.update('invoices', {'total_amount': qty * 1000, 'payment_type': payment, 'amount_paid_on_invoice': paid},
        where: 'id = ?', whereArgs: [invoiceId]);
    final after = await InvoiceEditEvents.capture(txn, invoiceId, costOf: _cost);
    id = await InvoiceEditEvents.record(txn, invoiceId: invoiceId, before: before!, after: after!);
  });
  if (id != null) {
    await db.update(InvoiceEditEvents.table, {'event_date': on.toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }
  return id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late PostingEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await _db();
    engine = PostingEngine(getDatabase: () async => db);
    await db.insert('invoices', {
      'id': 1, 'customer_id': 1, 'customer_name': 'أحمد', 'invoice_date': '2026-09-01T09:00:00',
      'payment_type': 'نقد', 'total_amount': 0, 'status': 'محفوظة',
    });
    await _setItems(db, 1, 10); // 10,000 بكلفة 7,000
  });

  tearDown(() async => db.close());

  Future<double> bal(String key, {String? onDay}) async {
    final id = await Ledger.systemAccountId(db, key);
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit - l.credit), 0) AS b FROM journal_lines l
      JOIN journal_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? ${onDay == null ? '' : 'AND substr(e.entry_date, 1, 10) = ?'}''',
        [id, if (onDay != null) onDay]);
    return (r.first['b'] as num).toDouble();
  }

  test('الدفتر: الإضافة بتاريخ التعديل، والفاتورة بحالها الأصلية بتاريخها', () async {
    await _edit(db, 1, 12, DateTime(2026, 9, 10)); // +2 قطعة
    final s = await engine.syncAll();
    expect(s.errors, isEmpty);
    expect(await bal('cash_main', onDay: '2026-09-01'), 10000);
    expect(await bal('cash_main', onDay: '2026-09-10'), 2000);
    expect(await bal('cogs', onDay: '2026-09-01'), 7000);
    expect(await bal('cogs', onDay: '2026-09-10'), 1400);
    // المجموع = حال الفاتورة الآن بالضبط
    expect(await bal('cash_main'), 12000);
    expect(await bal('sales'), -12000);
    expect(await bal('cogs'), 8400);
    expect(await bal('inventory'), -8400);
    expect(await AccountingReports(getDatabase: () async => db).integrityCheck(), isEmpty);
  });

  test('الدفتر: مرتجع بعد إضافة، وتكرار الترحيل لا يغيّر شيئاً، والحذف يمسح الكل', () async {
    await _edit(db, 1, 12, DateTime(2026, 9, 10));
    await _edit(db, 1, 9, DateTime(2026, 9, 12)); // −3 قطع
    await engine.syncAll();
    expect(await bal('cash_main', onDay: '2026-09-12'), -3000);
    expect(await bal('cogs', onDay: '2026-09-12'), -2100);
    expect(await bal('cash_main'), 9000);
    expect(await bal('cogs'), 6300);

    final again = await engine.syncAll();
    expect(again.created + again.updated + again.deleted, 0);

    await db.update('invoices', {'is_deleted': 1}, where: 'id = 1');
    await engine.syncAll();
    expect(await bal('cash_main'), 0);
    expect(await bal('cogs'), 0);
  });

  test('تعديل بلا أثر مالي لا يُسجَّل حدثاً', () async {
    final id = await _edit(db, 1, 10, DateTime(2026, 9, 10));
    expect(id, isNull);
  });

  test('نقد ← دين بتاريخ التعديل: يخرج المقبوض من صندوق يوم التعديل لا يوم الفاتورة', () async {
    await _edit(db, 1, 10, DateTime(2026, 9, 10), payment: 'دين', paid: 0);
    await engine.syncAll();
    expect(await bal('cash_main', onDay: '2026-09-01'), 10000);
    expect(await bal('cash_main', onDay: '2026-09-10'), -10000);
    expect(await bal('cash_main'), 0);
  });

  test('التقارير: يوم الفاتورة بحاله الأصلية، ويوم التعديل بالفرق، والشهر = الآن', () async {
    await _edit(db, 1, 12, DateTime(2026, 9, 10));

    final d1 = (await SalesFacts.load(db, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 1))).totals();
    expect(d1.sales, 10000);
    expect(d1.cost, 7000);
    expect(d1.invoiceCount, 1);

    final d10 = (await SalesFacts.load(db, from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 10))).totals();
    expect(d10.sales, 2000);
    expect(d10.cost, 1400);
    expect(d10.invoiceCount, 0); // ليست فاتورة جديدة
    expect(d10.cashSales, 2000);

    final m = await SalesFacts.load(db, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    final t = m.totals();
    expect(t.sales, 12000);
    expect(t.cost, 8400);
    expect(t.invoiceCount, 1);
    final days = m.byDay();
    expect(days['2026-09-01']!.sales, 10000);
    expect(days['2026-09-10']!.sales, 2000);
    final p = m.byProduct().single;
    expect(p.baseQty, 12);
    expect(p.revenue, 12000);
  });

  test('التقارير: تعديل في يوم الفاتورة نفسه لا يضيف شيئاً', () async {
    await _edit(db, 1, 12, DateTime(2026, 9, 1, 15));
    final f = await SalesFacts.load(db, from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 1));
    expect(f.edits, isEmpty);
    expect(f.totals().sales, 12000);
  });
}
