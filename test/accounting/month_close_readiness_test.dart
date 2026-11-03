// test/accounting/month_close_readiness_test.dart
//
// فحوص جاهزية إقفال الشهر: قراءة فقط، والخطأ الحسابي يظهر «خطأ» لا «سليم».

import 'package:alnaser/erp/accounting_plus/month_close_readiness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, current_total_debt REAL, is_deleted INTEGER)');
    await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, customer_id INTEGER, amount_changed REAL, is_deleted INTEGER)');
    await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, stock_quantity REAL, is_deleted INTEGER)');
    await db.execute('CREATE TABLE invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, customer_name TEXT, '
        'invoice_date TEXT, status TEXT, payment_type TEXT, is_deleted INTEGER)');
    await db.execute('CREATE TABLE journal_entries (id INTEGER PRIMARY KEY, entry_number INTEGER, entry_date TEXT, description TEXT)');
    await db.execute('CREATE TABLE journal_lines (id INTEGER PRIMARY KEY, entry_id INTEGER, debit REAL, credit REAL)');
    // علي سليم، زينب بطاقتها 500 ومعاملاتها 450
    await db.insert('customers', {'id': 1, 'name': 'علي', 'current_total_debt': 100, 'is_deleted': 0});
    await db.insert('transactions', {'customer_id': 1, 'amount_changed': 100, 'is_deleted': 0});
    await db.insert('customers', {'id': 2, 'name': 'زينب', 'current_total_debt': 500, 'is_deleted': 0});
    await db.insert('transactions', {'customer_id': 2, 'amount_changed': 450, 'is_deleted': 0});
    await db.insert('transactions', {'customer_id': 2, 'amount_changed': 999, 'is_deleted': 1}); // محذوفة لا تُحسب
    await db.insert('products', {'name': 'سلك', 'stock_quantity': -3, 'is_deleted': 0});
    await db.insert('products', {'name': 'قاطع', 'stock_quantity': 4, 'is_deleted': 0});
    // معلّقة في تشرين الأول (بصيغتي وقت مختلفتين) وأخرى في تشرين الثاني لا تُحسب
    await db.insert('invoices', {'invoice_number': 'A1', 'invoice_date': '2026-10-05T10:00:00', 'status': 'معلقة', 'is_deleted': 0});
    await db.insert('invoices', {'invoice_number': 'A2', 'invoice_date': '2026-10-31 23:00:00', 'status': 'معلقة', 'is_deleted': 0});
    await db.insert('invoices', {'invoice_number': 'A3', 'invoice_date': '2026-11-01 08:00:00', 'status': 'معلقة', 'is_deleted': 0});
    // قيد متوازن وآخر غير متوازن في الشهر
    await db.insert('journal_entries', {'id': 1, 'entry_number': 1, 'entry_date': '2026-10-02T00:00:00.000'});
    await db.insert('journal_lines', {'entry_id': 1, 'debit': 100, 'credit': 0});
    await db.insert('journal_lines', {'entry_id': 1, 'debit': 0, 'credit': 100});
    await db.insert('journal_entries', {'id': 2, 'entry_number': 2, 'entry_date': '2026-10-20T00:00:00.000'});
    await db.insert('journal_lines', {'entry_id': 2, 'debit': 50, 'credit': 0});
  });
  tearDown(() => db.close());

  test('الفحوص', () async {
    final r = await MonthCloseReadiness.checks(db, DateTime(2026, 10, 15));
    ReadinessCheck c(String t) => r.firstWhere((x) => x.title == t);
    expect(c('توازن القيود').level, CheckLevel.fail);
    expect(c('توازن القيود').items.single, contains('قيد 2'));
    expect(c('أرصدة العملاء').level, CheckLevel.fail);
    expect(c('أرصدة العملاء').items.single, 'زينب: البطاقة 500.0 • المعاملات 450.0');
    expect(c('أرصدة الموردين').level, CheckLevel.na);
    expect(c('فواتير معلّقة').level, CheckLevel.warn);
    expect(c('فواتير معلّقة').items.length, 2); // A1 وA2 فقط
    expect(c('مواد برصيد سالب').items.single, startsWith('سلك'));
    expect(c('عدّ الدرج').level, CheckLevel.na);
    expect(c('مطابقة البنك').level, CheckLevel.na);
  });

  test('لا يكتب شيئاً', () async {
    final before = (await db.rawQuery('SELECT COUNT(*) AS n FROM sqlite_master')).first['n'];
    final tx = (await db.rawQuery('SELECT COUNT(*) AS n FROM transactions')).first['n'];
    await MonthCloseReadiness.checks(db, DateTime(2026, 10, 15));
    expect((await db.rawQuery('SELECT COUNT(*) AS n FROM sqlite_master')).first['n'], before);
    expect((await db.rawQuery('SELECT COUNT(*) AS n FROM transactions')).first['n'], tx);
  });
}
