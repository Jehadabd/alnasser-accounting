// test/reports/sales_facts_test.dart
//
// اختبارات محرك أرقام التقارير الموحّد على قاعدة SQLite في الذاكرة.
// التشغيل: flutter test test/reports/sales_facts_test.dart

import 'package:alnaser/services/reports/sales_facts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _db() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)');
  await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER)');
  await db.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, unit TEXT, cost_price REAL,
      length_per_unit REAL, unit_costs TEXT, unit_hierarchy TEXT, category_id INTEGER)''');
  await db.execute('''CREATE TABLE invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, customer_id INTEGER,
      customer_name TEXT, invoice_date TEXT, payment_type TEXT, total_amount REAL, discount REAL,
      loading_fee REAL, return_amount REAL, amount_paid_on_invoice REAL, status TEXT,
      is_deleted INTEGER DEFAULT 0, is_created_by_me INTEGER DEFAULT 1)''');
  await db.execute('''CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_name TEXT,
      product_id INTEGER, quantity_individual REAL, quantity_large_unit REAL, units_in_large_unit REAL,
      actual_cost_price REAL, applied_price REAL, sale_type TEXT, item_total REAL)''');
  await db.execute('''CREATE TABLE invoice_adjustments (id INTEGER PRIMARY KEY, invoice_id INTEGER, type TEXT,
      amount_delta REAL, product_id INTEGER, product_name TEXT, quantity REAL, price REAL, sale_type TEXT,
      units_in_large_unit REAL, created_at TEXT)''');
  await db.execute('''CREATE TABLE sales_returns (id INTEGER PRIMARY KEY, return_no INTEGER, return_date TEXT,
      customer_id INTEGER, customer_name TEXT, original_invoice_id INTEGER, refund_mode TEXT, cash_amount REAL,
      total REAL, cost_total REAL, notes TEXT, status TEXT, created_by TEXT)''');
  await db.execute('''CREATE TABLE sales_return_items (id INTEGER PRIMARY KEY, return_id INTEGER, product_id INTEGER,
      product_name TEXT, sale_type TEXT, quantity REAL, base_qty REAL, price REAL, total REAL, unit_cost REAL)''');

  await db.insert('customers', {'id': 1, 'name': 'أحمد'});
  await db.insert('categories', {'id': 10, 'name': 'كهربائيات', 'parent_id': null});
  await db.insert('categories', {'id': 11, 'name': 'قواطع', 'parent_id': 10});
  await db.insert('products', {'id': 1, 'name': 'قاطع', 'unit': 'piece', 'cost_price': 500, 'category_id': 11});
  await db.insert('products', {'id': 2, 'name': 'لمبة', 'unit': 'piece', 'cost_price': 100, 'category_id': 10});

  // فاتورة 1 (نقد): قطعتان + كرتون (12 قطعة)، خصم 500 وأجور تحميل 1000
  await db.insert('invoices', {
    'id': 1, 'invoice_number': '120261001', 'customer_name': 'زبون نقدي', 'invoice_date': '2026-10-14T10:00:00.000',
    'payment_type': 'نقد', 'total_amount': 11500, 'discount': 500, 'loading_fee': 1000, 'return_amount': 0,
    'status': 'محفوظة',
  });
  await db.insert('invoice_items', {
    'invoice_id': 1, 'product_name': 'قاطع', 'quantity_individual': 2, 'quantity_large_unit': 0,
    'units_in_large_unit': 1, 'actual_cost_price': 600, 'applied_price': 1000, 'sale_type': 'قطعة', 'item_total': 2000,
  });
  await db.insert('invoice_items', {
    'invoice_id': 1, 'product_name': 'قاطع', 'quantity_individual': 0, 'quantity_large_unit': 1,
    'units_in_large_unit': 12, 'actual_cost_price': 6000, 'applied_price': 9000, 'sale_type': 'كرتون', 'item_total': 9000,
  });

  // فاتورة 2 (دين) لأحمد: 10 لمبات بكلفة المادة (100) + تسوية لاحقة لمبتان (total صار 1800)
  await db.insert('invoices', {
    'id': 2, 'customer_id': 1, 'customer_name': 'أحمد', 'invoice_date': '2026-10-15T09:00:00.000',
    'payment_type': 'دين', 'total_amount': 1800, 'discount': 0, 'loading_fee': 0, 'return_amount': 0,
    'amount_paid_on_invoice': 500, 'status': 'محفوظة',
  });
  await db.insert('invoice_items', {
    'invoice_id': 2, 'product_name': 'لمبة', 'product_id': 2, 'quantity_individual': 10, 'quantity_large_unit': 0,
    'units_in_large_unit': 1, 'actual_cost_price': null, 'applied_price': 150, 'sale_type': 'قطعة', 'item_total': 1500,
  });
  await db.insert('invoice_adjustments', {
    'invoice_id': 2, 'type': 'debit', 'amount_delta': 300, 'product_id': 2, 'product_name': 'لمبة',
    'quantity': 2, 'price': 150, 'sale_type': 'قطعة', 'units_in_large_unit': 1, 'created_at': '2026-10-20T09:00:00',
  });

  // فاتورة قديمة بلا حالة وبلا معرّف عميل لكن باسم أحمد (تُحتسب له)
  await db.insert('invoices', {
    'id': 3, 'customer_id': null, 'customer_name': 'أحمد', 'invoice_date': '2026-09-01T09:00:00.000',
    'payment_type': 'دين', 'total_amount': 300, 'status': null,
  });
  await db.insert('invoice_items', {
    'invoice_id': 3, 'product_name': 'لمبة', 'quantity_individual': 2, 'quantity_large_unit': 0,
    'applied_price': 150, 'sale_type': 'قطعة', 'item_total': 300,
  });

  // تُستبعد: محذوفة، معلّقة
  await db.insert('invoices', {
    'id': 4, 'customer_name': 'x', 'invoice_date': '2026-10-14T11:00:00', 'payment_type': 'نقد',
    'total_amount': 999999, 'status': 'محفوظة', 'is_deleted': 1,
  });
  await db.insert('invoices', {
    'id': 5, 'customer_name': 'y', 'invoice_date': '2026-10-14T11:00:00', 'payment_type': 'نقد',
    'total_amount': 888888, 'status': 'معلقة',
  });

  // فاتورة من جهاز آخر (مزامنة)
  await db.insert('invoices', {
    'id': 6, 'customer_name': 'بعيد', 'invoice_date': '2026-10-16T09:00:00', 'payment_type': 'نقد',
    'total_amount': 1000, 'status': 'محفوظة', 'is_created_by_me': 0,
  });
  await db.insert('invoice_items', {
    'invoice_id': 6, 'product_name': 'لمبة', 'quantity_individual': 5, 'quantity_large_unit': 0,
    'actual_cost_price': 120, 'applied_price': 200, 'sale_type': 'قطعة', 'item_total': 1000,
  });

  // مرتجع مبيعات: لمبتان من فاتورة 2 — 300 بكلفة 200
  await db.insert('sales_returns', {
    'id': 1, 'return_no': 7, 'return_date': '2026-10-17T12:00:00', 'customer_id': 1, 'customer_name': 'أحمد',
    'original_invoice_id': 2, 'refund_mode': 'credit', 'total': 300, 'cost_total': 200, 'status': 'posted',
  });
  await db.insert('sales_return_items', {
    'return_id': 1, 'product_id': 2, 'product_name': 'لمبة', 'sale_type': 'قطعة', 'quantity': 2, 'base_qty': 2,
    'price': 150, 'total': 300, 'unit_cost': 100,
  });
  // مرتجع ملغى لا يُحتسب
  await db.insert('sales_returns', {
    'id': 2, 'return_no': 8, 'return_date': '2026-10-17T12:00:00', 'customer_name': 'x', 'refund_mode': 'cash',
    'total': 5000, 'cost_total': 1000, 'status': 'void',
  });
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  setUp(() async => db = await _db());
  tearDown(() async => db.close());

  test('ملخص أكتوبر: المبيعات والكلفة والربح والمرتجع بقاعدة واحدة', () async {
    final f = await SalesFacts.load(db, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
    final t = f.totals();
    expect(t.invoiceCount, 3); // 1 + 2 + 6 (المحذوفة والمعلّقة مستبعدتان)
    expect(t.sales, 11500 + 1800 + 1000);
    // الكلفة: ف1 = 2×600 + 1×6000 = 7200 ؛ ف2 = 10×100 + تسوية 2×100 = 1200 ؛ ف6 = 5×120 = 600
    expect(t.invoiceCost, 7200 + 1200 + 600);
    expect(t.salesReturns, 300);
    expect(t.salesReturnsCost, 200);
    expect(t.cost, 9000 - 200);
    // الربح = (11500−7200) + (1800−1200) + (1000−600) − (300−200)
    expect(t.profit, 4300 + 600 + 400 - 100);
    expect(t.cashSales, 12500);
    expect(t.creditSales, 1800);
    expect(t.netSales, 14300 - 300);
    expect(t.discount, 500);
    expect(t.loadingFees, 1000);
  });

  test('مصدر البيانات: هذا الجهاز / المزامنة', () async {
    final mine = (await SalesFacts.load(db, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31),
            source: ReportSource.thisDevice))
        .totals();
    expect(mine.invoiceCount, 2);
    final sync = (await SalesFacts.load(db, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31),
            source: ReportSource.sync))
        .totals();
    expect(sync.invoiceCount, 1);
    expect(sync.salesReturns, 0); // المرتجعات محلية
  });

  test('مجموع الأيام = مجموع الفترة', () async {
    final f = await SalesFacts.load(db, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
    final days = f.byDay();
    final sumProfit = days.values.fold<double>(0, (s, t) => s + t.profit);
    final sumSales = days.values.fold<double>(0, (s, t) => s + t.sales);
    expect(sumProfit, closeTo(f.totals().profit, 0.001));
    expect(sumSales, closeTo(f.totals().sales, 0.001));
    expect(days['2026-10-17']!.salesReturns, 300);
  });

  test('المادة: الكرتون يتحول إلى 12 قطعة ولا يُجمع ككرتون واحد', () async {
    final f = await SalesFacts.load(db, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
    final p = f.byProduct().firstWhere((e) => e.name == 'قاطع');
    expect(p.baseQty, 14);
    expect(p.revenue, 11000);
    expect(p.cost, 7200);
    expect(p.profit, 3800);
    final lamp = f.byProduct().firstWhere((e) => e.name == 'لمبة');
    // 10 + تسوية 2 + 5 (مزامنة) − مرتجع 2
    expect(lamp.netQty, 15);
    expect(lamp.categoryId, 10);
  });

  test('العميل: بالمعرّف وبالاسم للفواتير القديمة، والسنوات', () async {
    final f = await SalesFacts.load(db, customerId: 1);
    final t = f.totals();
    expect(t.invoiceCount, 2); // ف2 + ف3 القديمة باسمه
    expect(t.sales, 1800 + 300);
    final years = f.byYear();
    expect(years.keys, [2026]);
    final months = f.byMonth();
    expect(months['2026-09']!.sales, 300);
    expect(months['2026-10']!.salesReturns, 300);
  });

  test('الأقسام: تجميع الفرعي تحت الأب', () async {
    final f = await SalesFacts.load(db, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
    final cats = f.byCategory({10: 'كهربائيات', 11: 'قواطع'}, parents: {10: null, 11: 10}, rollupToRoot: true);
    expect(cats.length, 1);
    expect(cats.first.name, 'كهربائيات');
    expect(cats.first.revenue, 11000 + 1500 + 300 + 1000);
  });

  test('مادة واحدة: بنودها فقط', () async {
    final f = await SalesFacts.load(db, productId: 1);
    expect(f.saleItems.every((i) => i.productName == 'قاطع'), isTrue);
    expect(f.byProduct().single.revenue, 11000);
  });

  test('بداية الأسبوع السبت', () {
    expect(SalesFacts.weekStart(DateTime(2026, 10, 14)), DateTime(2026, 10, 10));
    expect(SalesFacts.weekStart(DateTime(2026, 10, 10)), DateTime(2026, 10, 10));
    expect(SalesFacts.weekStart(DateTime(2026, 10, 16)), DateTime(2026, 10, 10));
    expect(SalesFacts.weekStart(DateTime(2026, 10, 17)), DateTime(2026, 10, 17));
  });

  test('كلفة الكرتون من التسلسل الهرمي عند غياب الكلفة الفعلية', () {
    final cost = ItemCost.compute({
      'qi': 0,
      'ql': 2,
      'uilu': 0,
      'sale_type': 'كرتون',
      'product_unit': 'piece',
      'product_cost_price': 100,
      'unit_hierarchy': '[{"unit_name":"باكيت","quantity":6},{"unit_name":"كرتون","quantity":4}]',
      'selling_price': 3000,
    });
    expect(cost, 2 * 100 * 24);
  });
}
