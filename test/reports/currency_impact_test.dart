// test/reports/currency_impact_test.dart
//
// أثر سعر الدولار: السعر قبل/بعد الفترة من سجل الأسعار، ديون العملاء الناتجة عن
// بضاعة الدولار فقط (الأحدث أولاً)، زيادة كلفة ديون الدولار، تغيّر قيمة مخزون الدولار،
// والمواد (تحت الكلفة، كلفة قديمة، كلفة مسجّلة بالرقم الدولاري خطأً، تتبّع تلقائي).
// التشغيل: flutter test test/reports/currency_impact_test.dart

import 'package:alnaser/services/reports/currency_impact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _db() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('CREATE TABLE accounting_settings (key TEXT PRIMARY KEY, value TEXT)');
  await db.execute('''CREATE TABLE currencies (code TEXT PRIMARY KEY, name TEXT, symbol TEXT, fraction_name TEXT,
      decimals INTEGER DEFAULT 0, rate REAL DEFAULT 1, is_base INTEGER DEFAULT 0, divide INTEGER DEFAULT 0,
      is_active INTEGER DEFAULT 1)''');
  await db.execute(
      'CREATE TABLE currency_rates (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT, rate REAL, rate_date TEXT, created_at TEXT)');
  await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, current_total_debt REAL, is_deleted INTEGER DEFAULT 0)');
  await db.execute('CREATE TABLE suppliers (id INTEGER PRIMARY KEY, name TEXT, total_debt_iqd REAL, total_debt_usd REAL)');
  await db.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, unit TEXT, cost_price REAL, price1 REAL,
      stock_quantity REAL, is_deleted INTEGER DEFAULT 0)''');
  await db.execute(
      "CREATE TABLE product_details (product_id INTEGER PRIMARY KEY, cost_currency TEXT NOT NULL DEFAULT 'IQD', cost_usd REAL)");
  await db.execute('''CREATE TABLE purchase_invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, supplier_id INTEGER,
      total_amount REAL, currency TEXT, status TEXT, date TEXT)''');
  await db.execute('''CREATE TABLE purchase_invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_id INTEGER,
      unit_name TEXT, quantity REAL, unit_price REAL, conversion_factor REAL, total_price REAL)''');
  await db.execute('''CREATE TABLE invoices (id INTEGER PRIMARY KEY, customer_id INTEGER, invoice_date TEXT, payment_type TEXT,
      total_amount REAL, amount_paid_on_invoice REAL, status TEXT, is_deleted INTEGER DEFAULT 0)''');
  await db.execute('CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_name TEXT, product_id INTEGER, item_total REAL)');
  await db.execute('''CREATE TABLE transactions (id INTEGER PRIMARY KEY, customer_id INTEGER, transaction_date TEXT,
      amount_changed REAL, transaction_type TEXT, invoice_id INTEGER, is_deleted INTEGER DEFAULT 0)''');

  await db.insert('currencies', {'code': 'USD', 'name': 'دولار', 'rate': 1450});
  await db.insert('currency_rates', {'code': 'USD', 'rate': 1300, 'rate_date': '2026-09-01', 'created_at': '2026-09-01'});
  await db.insert('currency_rates', {'code': 'USD', 'rate': 1450, 'rate_date': '2026-10-10', 'created_at': '2026-10-10'});

  await db.insert('customers', {'id': 1, 'name': 'أ', 'current_total_debt': 1000000});
  await db.insert('customers', {'id': 2, 'name': 'ب', 'current_total_debt': 300000});
  await db.insert('customers', {'id': 3, 'name': 'ج', 'current_total_debt': -50000}); // دائن: لا يُحسب
  await db.insert('suppliers', {'id': 1, 'name': 'مورد الدولار', 'total_debt_iqd': 0, 'total_debt_usd': 1000});
  await db.insert('suppliers', {'id': 2, 'name': 'مورد الدينار', 'total_debt_iqd': 500000, 'total_debt_usd': 0});

  // 1: آخر شراء بالدولار — كرتون 10$ فيه 10 قطع ← 1$ للقطعة، كلفتها 1300 (لا تتبع تلقائياً)
  await db.insert('products', {'id': 1, 'name': 'سلك', 'unit': 'piece', 'cost_price': 1300, 'price1': 1400, 'stock_quantity': 100});
  // 2: كلفة مسجلة 2 (الرقم الدولاري كأنه دينار) — خطأ قديم
  await db.insert('products', {'id': 2, 'name': 'قاطع', 'unit': 'piece', 'cost_price': 2, 'price1': 4000, 'stock_quantity': 10});
  // 3: آخر شراء بالدينار — بضاعة دينار
  await db.insert('products', {'id': 3, 'name': 'لمبة', 'unit': 'piece', 'cost_price': 500, 'price1': 800, 'stock_quantity': 5});
  // 4: كلفتها بالدولار في بطاقتها (2$) فتتبع السعر: 2 × 1450
  await db.insert('products', {'id': 4, 'name': 'مفتاح', 'unit': 'piece', 'cost_price': 2900, 'price1': 3000, 'stock_quantity': 50});
  await db.insert('product_details', {'product_id': 4, 'cost_currency': 'USD', 'cost_usd': 2});
  await db.insert('product_details', {'product_id': 3, 'cost_currency': 'IQD'});

  await db.insert('purchase_invoices',
      {'id': 1, 'supplier_id': 1, 'total_amount': 100, 'currency': 'USD', 'status': 'confirmed', 'date': '2026-09-05T10:00:00'});
  await db.insert('purchase_invoice_items',
      {'invoice_id': 1, 'product_id': 1, 'unit_name': 'كرتون', 'quantity': 10, 'unit_price': 10, 'conversion_factor': 10, 'total_price': 100});
  await db.insert('purchase_invoice_items',
      {'invoice_id': 1, 'product_id': 2, 'unit_name': 'قطعة', 'quantity': 10, 'unit_price': 2, 'conversion_factor': 1, 'total_price': 20});
  await db.insert('purchase_invoice_items',
      {'invoice_id': 1, 'product_id': 3, 'unit_name': 'قطعة', 'quantity': 5, 'unit_price': 0.3, 'conversion_factor': 1, 'total_price': 1.5});
  await db.insert('purchase_invoices',
      {'id': 2, 'supplier_id': 2, 'total_amount': 2500, 'currency': 'IQD', 'status': 'confirmed', 'date': '2026-10-12T10:00:00'});
  await db.insert('purchase_invoice_items',
      {'invoice_id': 2, 'product_id': 3, 'unit_name': 'قطعة', 'quantity': 5, 'unit_price': 500, 'conversion_factor': 1, 'total_price': 2500});
  await db.insert('purchase_invoices',
      {'id': 3, 'supplier_id': 1, 'total_amount': 999, 'currency': 'USD', 'status': 'draft', 'date': '2026-10-15T10:00:00'});
  await db.insert('purchase_invoices',
      {'id': 4, 'supplier_id': 1, 'total_amount': 50, 'currency': 'USD', 'status': 'confirmed', 'date': '2026-10-11T09:00:00'});

  // العميل 1 (دينه 1,000,000): الأحدث أولاً ← دين يدوي 200,000 ثم فاتورة 11 (400,000 منها 60% دولار) ثم فاتورة 10 (دينار)
  await db.insert('invoices', {'id': 10, 'customer_id': 1, 'invoice_date': '2026-08-01T10:00:00', 'payment_type': 'دين',
      'total_amount': 600000, 'amount_paid_on_invoice': 0, 'status': 'محفوظة'});
  await db.insert('invoice_items', {'invoice_id': 10, 'product_name': 'لمبة', 'product_id': 3, 'item_total': 600000});
  await db.insert('invoices', {'id': 11, 'customer_id': 1, 'invoice_date': '2026-09-20T10:00:00', 'payment_type': 'دين',
      'total_amount': 500000, 'amount_paid_on_invoice': 100000, 'status': 'محفوظة'});
  await db.insert('invoice_items', {'invoice_id': 11, 'product_name': 'سلك', 'product_id': 1, 'item_total': 300000});
  await db.insert('invoice_items', {'invoice_id': 11, 'product_name': 'لمبة', 'product_id': 3, 'item_total': 200000});
  await db.insert('invoices', {'id': 13, 'customer_id': 1, 'invoice_date': '2026-10-12T10:00:00', 'payment_type': 'نقد',
      'total_amount': 90000, 'amount_paid_on_invoice': 90000, 'status': 'محفوظة'}); // نقد: لا يُنشئ ديناً
  await db.insert('transactions', {'customer_id': 1, 'transaction_date': '2026-10-05T10:00:00', 'amount_changed': 200000,
      'transaction_type': 'manual_debt', 'invoice_id': null});
  // العميل 2 (دينه 300,000): فاتورة 12 كلها مادة تتبع الدولار
  await db.insert('invoices', {'id': 12, 'customer_id': 2, 'invoice_date': '2026-10-11T10:00:00', 'payment_type': 'دين',
      'total_amount': 500000, 'amount_paid_on_invoice': 100000, 'status': 'محفوظة'});
  await db.insert('invoice_items', {'invoice_id': 12, 'product_name': 'مفتاح', 'product_id': 4, 'item_total': 500000});
  return db;
}

void main() {
  sqfliteFfiInit();
  final oct1 = DateTime(2026, 10, 1), oct31 = DateTime(2026, 10, 31);

  test('السعر قبل الفترة وبعدها من سجل الأسعار', () async {
    final im = await CurrencyImpact.load(await _db(), from: oct1, to: oct31);
    expect(im.rateBefore, 1300);
    expect(im.rateAfter, 1450);
    expect(im.rateChanged, isTrue);
    expect(im.changePct, closeTo(11.538, 0.01));
    expect(im.hasRateHistory, isTrue);
    expect(im.rates.length, 1);
  });

  test('ديون بضاعة الدولار فقط (الأحدث أولاً)، وبضاعة الدينار واليدوي بلا خسارة', () async {
    final im = await CurrencyImpact.load(await _db(), from: oct1, to: oct31);
    expect(im.receivables, 1300000); // الدائن لا يُحسب
    expect(im.debtorCount, 2);
    // العميل 1: 0 (يدوي) + 400,000×60% + 0 = 240,000 — العميل 2: 300,000×100%
    expect(im.usdReceivables, closeTo(540000, 0.01));
    expect(im.usdDebtorCount, 2);
    expect(im.unknownReceivables, closeTo(0, 0.01));
    expect(im.iqdReceivables, closeTo(760000, 0.01));
    expect(im.receivablesUsdBefore, closeTo(415.385, 0.01));
    expect(im.receivablesUsdAfter, closeTo(372.414, 0.01));
    expect(im.receivablesLossPct, closeTo(10.345, 0.01));
    expect(im.receivablesLossIqd, closeTo(62307.69, 0.05));
  });

  test('ديون الدولار للموردين تزيد بالدينار', () async {
    final im = await CurrencyImpact.load(await _db(), from: oct1, to: oct31);
    expect(im.payablesUsd, 1000);
    expect(im.payablesIqd, 500000);
    expect(im.payablesIncrease, closeTo(150000, 0.001));
    expect(im.usdSuppliers.single.name, 'مورد الدولار');
    expect(im.coverage, closeTo(1300000 / 1450 / 1000, 0.001));
  });

  test('المخزون والمواد: تتبع تلقائي، تحت الكلفة، كلفة قديمة، كلفة مشكوك فيها', () async {
    final im = await CurrencyImpact.load(await _db(), from: oct1, to: oct31);
    expect(im.products.map((p) => p.productId).toSet(), {1, 2, 4}); // 3 بضاعة دينار
    final p4 = im.products.firstWhere((p) => p.productId == 4);
    expect(p4.autoTracked, isTrue);
    expect(p4.usdUnitCost, 2);
    expect(im.costOutdated.map((p) => p.productId).toList(), [1]); // المتتبَّعة لا تظهر «قديمة»
    expect(im.belowCost.single.productId, 1); // 1400 < 1450
    expect(im.lowMargin(10).single.productId, 4); // (3000−2900)/3000 = 3.3%
    expect(im.suspicious.single.productId, 2);
    // تغيّر قيمة المخزون: سلك 100×1×150 + مفتاح 50×2×150 (المشكوك فيها لا تدخل)
    expect(im.stockEffect, closeTo(30000, 0.001));
    expect(im.netEffect, closeTo(30000 - 62307.69 - 150000, 0.05));
  });

  test('مشتريات الفترة بالدولار (المؤكدة فقط) بسعر يومها', () async {
    final im = await CurrencyImpact.load(await _db(), from: oct1, to: oct31);
    expect(im.periodUsdPurchases, 50);
    expect(im.periodUsdPurchasesIqd, closeTo(72500, 0.001));
  });

  test('سعر ثابت: لا تغيّر ولا خسارة', () async {
    final im = await CurrencyImpact.load(await _db(), from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 30));
    expect(im.rateChanged, isFalse);
    expect(im.receivablesLossPct, closeTo(0, 1e-9));
    expect(im.receivablesLossIqd, closeTo(0, 1e-9));
    expect(im.payablesIncrease, closeTo(0, 1e-9));
    expect(im.stockEffect, closeTo(0, 1e-9));
  });

  test('ماذا لو: ارتفاع 10% إضافي', () async {
    final im = await CurrencyImpact.load(await _db(), from: oct1, to: oct31);
    final w = im.whatIf(10);
    expect(w.payablesIqd, closeTo(145000, 0.001)); // 1000 × 145
    expect(w.receivablesUsd, closeTo(540000 / 1450 - 540000 / 1595, 0.001));
    expect(w.stockIqd, closeTo((100 * 1 + 50 * 2) * 145, 0.001));
  });
}
