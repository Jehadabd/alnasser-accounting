// test/reports/employee_sales_test.dart
//
// مبيعات الموظفين: كل رقم من محرك التقارير نفسه، ومجموع الموظفين = مجموع الفترة حرفياً.
// التشغيل: flutter test test/reports/employee_sales_test.dart

import 'package:alnaser/services/reports/employee_sales.dart';
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
      is_deleted INTEGER DEFAULT 0, is_created_by_me INTEGER DEFAULT 1, created_by_username TEXT)''');
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
  await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, display_name TEXT)');
  await db.insert('users', {'username': 'ali', 'display_name': 'علي'});
  await db.insert('users', {'username': 'sara', 'display_name': null});
  await db.insert('products', {'id': 1, 'name': 'قاطع', 'unit': 'piece', 'cost_price': 600});

  Future<void> inv(int id, String? user, String pay, double total, {double cost = 600, int qty = 1, String status = 'محفوظة'}) async {
    await db.insert('invoices', {
      'id': id, 'invoice_number': '$id', 'customer_name': 'زبون', 'invoice_date': '2026-10-1${id % 9}T10:00:00.000',
      'payment_type': pay, 'total_amount': total, 'discount': 0, 'loading_fee': 0, 'return_amount': 0,
      'amount_paid_on_invoice': 0, 'status': status, 'created_by_username': user,
    });
    await db.insert('invoice_items', {
      'invoice_id': id, 'product_name': 'قاطع', 'quantity_individual': qty, 'quantity_large_unit': 0,
      'units_in_large_unit': 1, 'actual_cost_price': cost, 'applied_price': total / qty, 'sale_type': 'قطعة',
      'item_total': total,
    });
  }

  await inv(1, 'ali', 'نقد', 1000);
  await inv(2, 'ali', 'دين', 3000, qty: 3);
  await inv(3, 'sara', 'نقد', 2000, qty: 2);
  await inv(4, null, 'نقد', 800); // قديمة بلا مستخدم
  await inv(5, 'sara', 'نقد', 99999, status: 'معلقة'); // معلّقة: لا تُحسب لأحد

  // مرتجع من فاتورة علي سجّلته سارة ⇒ يُنسب لعلي (صاحب البيع)
  await db.insert('sales_returns', {
    'id': 1, 'return_no': 1, 'return_date': '2026-10-20T10:00:00', 'customer_name': 'زبون', 'original_invoice_id': 2,
    'refund_mode': 'credit', 'cash_amount': 0, 'total': 1000, 'cost_total': 600, 'status': 'posted', 'created_by': 'sara',
  });
  // مرتجع بلا فاتورة أصلية ⇒ لمن سجّله
  await db.insert('sales_returns', {
    'id': 2, 'return_no': 2, 'return_date': '2026-10-21T10:00:00', 'customer_name': 'زبون', 'original_invoice_id': null,
    'refund_mode': 'cash', 'cash_amount': 500, 'total': 500, 'cost_total': 300, 'status': 'posted', 'created_by': 'sara',
  });
  return db;
}

void main() {
  sqfliteFfiInit();

  test('كل موظف بفواتيره، ومجموعهم = مجموع الفترة', () async {
    final db = await _db();
    final facts = await SalesFacts.load(db, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
    final creators = await EmployeeSalesReport.creators(db, facts);
    final names = await EmployeeSalesReport.displayNames(db);
    final r = EmployeeSalesReport.group(facts, creatorOf: creators, names: names);

    final ali = r.rows.firstWhere((e) => e.username == 'ali');
    final sara = r.rows.firstWhere((e) => e.username == 'sara');
    final none = r.rows.firstWhere((e) => e.username.isEmpty);

    expect(ali.name, 'علي');
    expect(sara.name, 'sara'); // بلا اسم معروض ⇒ اسم الدخول
    expect(none.name, 'غير مسجّل');
    expect(r.rows.last.username, isEmpty, reason: '«غير مسجّل» آخراً');

    expect(ali.totals.invoiceCount, 2);
    expect(ali.totals.sales, 4000);
    expect(ali.totals.cashSales, 1000);
    expect(ali.totals.creditSales, 3000);
    expect(ali.totals.salesReturns, 1000, reason: 'مرتجع فاتورته يُنسب له لا لمن سجّله');
    expect(ali.totals.netSales, 3000);

    expect(sara.totals.invoiceCount, 1, reason: 'المعلّقة لا تُحسب');
    expect(sara.totals.salesReturns, 500, reason: 'مرتجع بلا فاتورة أصلية لمن سجّله');
    expect(none.totals.sales, 800);

    // 🔒 المجموع: لا رقم يضيع ولا يتكرر
    double sum(double Function(SalesTotals t) f) => r.rows.fold(0.0, (s, e) => s + f(e.totals));
    expect(sum((t) => t.netSales), closeTo(r.total.netSales, 0.001));
    expect(sum((t) => t.profit), closeTo(r.total.profit, 0.001));
    expect(sum((t) => t.invoiceCount.toDouble()), r.total.invoiceCount.toDouble());
    expect(sum((t) => t.cashSales), closeTo(r.total.cashSales, 0.001));

    // التفصيل: فواتير علي فقط، الأحدث أولاً
    final list = EmployeeSalesReport.invoicesOf(facts, creators, 'ali');
    expect(list.map((i) => i.id), [2, 1]);
    await db.close();
  });

  test('فترة بلا مبيعات ⇒ قائمة فارغة', () async {
    final db = await _db();
    final facts = await SalesFacts.load(db, from: DateTime(2025, 1, 1), to: DateTime(2025, 1, 31));
    final r = EmployeeSalesReport.group(facts, creatorOf: await EmployeeSalesReport.creators(db, facts));
    expect(r.rows, isEmpty);
    await db.close();
  });
}
