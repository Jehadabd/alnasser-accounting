// test/accounting/accounting_test.dart
//
// اختبارات النواة المحاسبية على قاعدة SQLite في الذاكرة.
// التشغيل: flutter test test/accounting/accounting_test.dart

import 'package:alnaser/accounting/accounting_reports.dart';
import 'package:alnaser/accounting/accounting_schema.dart';
import 'package:alnaser/accounting/ledger.dart';
import 'package:alnaser/accounting/posting_engine.dart';
import 'package:alnaser/accounting/vouchers_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _legacyDb() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  // الحد الأدنى من جداول البرنامج القديمة التي يقرأها محرك الترحيل
  await db.execute('''CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT,
      current_total_debt REAL DEFAULT 0, is_deleted INTEGER DEFAULT 0)''');
  await db.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, unit TEXT,
      cost_price REAL, length_per_unit REAL, unit_costs TEXT, stock_quantity REAL DEFAULT 0)''');
  await db.execute('''CREATE TABLE invoices (id INTEGER PRIMARY KEY, customer_id INTEGER,
      customer_name TEXT, invoice_date TEXT, payment_type TEXT, total_amount REAL,
      amount_paid_on_invoice REAL, status TEXT, is_deleted INTEGER DEFAULT 0)''');
  await db.execute('''CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER,
      product_name TEXT, quantity_individual REAL, quantity_large_unit REAL,
      units_in_large_unit REAL, actual_cost_price REAL, applied_price REAL,
      sale_type TEXT, item_total REAL)''');
  await db.execute('''CREATE TABLE transactions (id INTEGER PRIMARY KEY, customer_id INTEGER,
      transaction_date TEXT, amount_changed REAL, transaction_type TEXT, invoice_id INTEGER,
      description TEXT, is_deleted INTEGER DEFAULT 0)''');
  await AccountingSchema.ensure(db);
  return db;
}

Future<void> _customerTx(Database db, int id, int customer, double amount, String type,
    {int? invoiceId}) async {
  await db.insert('transactions', {
    'id': id,
    'customer_id': customer,
    'transaction_date': '2026-09-01T10:00:00',
    'amount_changed': amount,
    'transaction_type': type,
    'invoice_id': invoiceId,
  });
  await db.rawUpdate(
      'UPDATE customers SET current_total_debt = current_total_debt + ? WHERE id = ?', [amount, customer]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late PostingEngine engine;
  late AccountingReports reports;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await _legacyDb();
    engine = PostingEngine(getDatabase: () async => db);
    reports = AccountingReports(getDatabase: () async => db);

    await db.insert('customers', {'id': 1, 'name': 'أحمد', 'current_total_debt': 0});
    await db.insert('products', {'id': 1, 'name': 'سلك', 'unit': 'piece', 'cost_price': 700, 'stock_quantity': 10});
    // فاتورة نقدية 10,000 (كلفة 7,000)
    await db.insert('invoices', {
      'id': 1, 'customer_id': 1, 'customer_name': 'أحمد', 'invoice_date': '2026-09-01T09:00:00',
      'payment_type': 'نقد', 'total_amount': 10000, 'amount_paid_on_invoice': 10000, 'status': 'محفوظة',
    });
    await db.insert('invoice_items', {
      'invoice_id': 1, 'product_name': 'سلك', 'quantity_individual': 10, 'quantity_large_unit': 0,
      'units_in_large_unit': 1, 'applied_price': 1000, 'item_total': 10000,
    });
    // فاتورة آجلة 5,000 دُفع منها 1,000 (كلفة 3,500)
    await db.insert('invoices', {
      'id': 2, 'customer_id': 1, 'customer_name': 'أحمد', 'invoice_date': '2026-09-02T09:00:00',
      'payment_type': 'دين', 'total_amount': 5000, 'amount_paid_on_invoice': 1000, 'status': 'محفوظة',
    });
    await db.insert('invoice_items', {
      'invoice_id': 2, 'product_name': 'سلك', 'quantity_individual': 5, 'quantity_large_unit': 0,
      'units_in_large_unit': 1, 'applied_price': 1000, 'item_total': 5000,
    });
    await _customerTx(db, 1, 1, 4000, 'invoice_debt', invoiceId: 2);
    await _customerTx(db, 2, 1, 2500, 'opening_balance');
    await _customerTx(db, 3, 1, -1500, 'manual_payment');
  });

  tearDown(() async => db.close());

  Future<double> bal(String key) async {
    final id = await Ledger.systemAccountId(db, key);
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines WHERE account_id = ?', [id]);
    return (r.first['b'] as num).toDouble();
  }

  test('المخطط آمن التكرار ولا يكرر الشجرة', () async {
    final before = (await db.rawQuery('SELECT COUNT(*) AS n FROM accounts')).first['n'];
    await AccountingSchema.ensure(db);
    final after = (await db.rawQuery('SELECT COUNT(*) AS n FROM accounts')).first['n'];
    expect(after, before);
    expect(after, AccountingSchema.defaultChart.length);
  });

  test('الترحيل: الصندوق والمبيعات والذمم والكلفة صحيحة ومتوازنة', () async {
    final s = await engine.syncAll();
    expect(s.errors, isEmpty);
    // صندوق: 10,000 نقدي + 1,000 مقدّم + 1,500 تسديد = 12,500
    expect(await bal('cash_main'), 12500);
    // ذمم: 4,000 + 2,500 − 1,500 = 5,000 = رصيد العميل
    expect(await bal('ar_customers'), 5000);
    // مبيعات: 10,000 + 1,000 + 4,000 = 15,000 (دائنة)
    expect(await bal('sales'), -15000);
    expect(await bal('cogs'), 10500);
    expect(await bal('inventory'), -10500);
    expect(await bal('opening_equity'), -2500);
    expect(await reports.integrityCheck(), isEmpty);
  });

  test('الترحيل الثاني لا يغيّر شيئاً، والتعديل والحذف ينعكسان', () async {
    await engine.syncAll();
    final s2 = await engine.syncAll();
    expect(s2.created + s2.updated + s2.deleted, 0);

    await db.update('invoices', {'total_amount': 12000, 'amount_paid_on_invoice': 12000},
        where: 'id = 1');
    await db.update('transactions', {'is_deleted': 1}, where: 'id = 3');
    await db.rawUpdate('UPDATE customers SET current_total_debt = current_total_debt + 1500 WHERE id = 1');
    final s3 = await engine.syncAll();
    expect(s3.updated, 1);
    expect(s3.deleted, 1);
    expect(await bal('cash_main'), 13000); // 12,000 + 1,000
    expect(await bal('ar_customers'), 6500);
    expect(await reports.integrityCheck(), isEmpty);
  });

  test('سند مصروف يخفض الصندوق ويظهر في قائمة الدخل', () async {
    await engine.syncAll();
    final v = VouchersService(getDatabase: () async => db);
    final rent = (await db.query('accounts', where: "code = '5201'")).first['id'] as int;
    final box = (await v.cashBoxes()).firstWhere((b) => b.isDefault);
    await v.create(
        type: VoucherType.expense, amount: 2000, date: DateTime(2026, 9, 5), cashBoxId: box.id, accountId: rent);
    expect(await bal('cash_main'), 10500);
    final inc = await reports.incomeStatement(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));
    expect(inc.totalRevenue, 15000);
    expect(inc.totalCogs, 10500);
    expect(inc.totalExpenses, 2000);
    expect(inc.netProfit, 2500);
    final bs = await reports.balanceSheet(asOf: DateTime(2026, 9, 30));
    expect(bs.difference.abs() < 0.01, isTrue);
  });

  test('لا يُسمح بمصروف على حساب ذمم العملاء', () async {
    final v = VouchersService(getDatabase: () async => db);
    final ar = await Ledger.systemAccountId(db, 'ar_customers');
    final box = (await v.cashBoxes()).first;
    expect(
      () => v.create(type: VoucherType.payment, amount: 100, date: DateTime.now(), cashBoxId: box.id, accountId: ar),
      throwsA(isA<LedgerException>()),
    );
  });

  test('القيد اليدوي غير المتوازن مرفوض', () async {
    final ledger = Ledger(getDatabase: () async => db);
    final cash = await Ledger.systemAccountId(db, 'cash_main');
    final cap = await Ledger.systemAccountId(db, 'capital');
    expect(
      () => ledger.postManualEntry(date: DateTime.now(), description: 'x', lines: [
        JournalLineInput(accountId: cash, debit: 100),
        JournalLineInput(accountId: cap, credit: 90),
      ]),
      throwsA(isA<UnbalancedEntryException>()),
    );
    await ledger.postManualEntry(date: DateTime.now(), description: 'رأس مال', lines: [
      JournalLineInput(accountId: cash, debit: 100),
      JournalLineInput(accountId: cap, credit: 100),
    ]);
    expect(await bal('capital'), -100);
  });

  test('مطابقة المخزون تجعل رصيده = الكمية × الكلفة', () async {
    await engine.syncAll();
    await engine.alignInventoryToStockValue();
    expect(await bal('inventory'), 7000); // 10 × 700
    // تكرارها لا يضيف شيئاً
    await engine.alignInventoryToStockValue();
    expect(await bal('inventory'), 7000);
  });

  test('ميزان المراجعة الهرمي: المجموعات تجمع أبناءها', () async {
    await engine.syncAll();
    final tb = await reports.trialBalance(to: DateTime(2026, 12, 31));
    final assets = tb.firstWhere((r) => r.account.code == '1');
    // الأصول = صندوق 12,500 + ذمم 5,000 − مخزون 10,500
    expect(assets.natureBalance, 7000);
    final roots = tb.where((r) => r.depth == 0);
    final d = roots.fold(0.0, (s, r) => s + r.closingDebit);
    final c = roots.fold(0.0, (s, r) => s + r.closingCredit);
    expect((d - c).abs() < 0.01, isTrue);
  });
}
