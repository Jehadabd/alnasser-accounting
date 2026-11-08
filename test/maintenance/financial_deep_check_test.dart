// test/maintenance/financial_deep_check_test.dart
// الفحص العميق يقرأ فقط ويكشف ما لا يكشفه «الرصيد = مجموع المعاملات»،
// والصندوق الأسود يسجّل كل تغيّر دين أو معاملة من أي مسار دون أن يمنعه.

import 'package:alnaser/services/database/business/financial_black_box.dart';
import 'package:alnaser/services/database/business/financial_deep_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, current_total_debt REAL DEFAULT 0, '
        'is_deleted INTEGER DEFAULT 0, sync_uuid TEXT)');
    await db.execute('CREATE TABLE invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, customer_id INTEGER, '
        'customer_name TEXT, payment_type TEXT, total_amount REAL, amount_paid_on_invoice REAL DEFAULT 0, '
        'status TEXT, is_deleted INTEGER DEFAULT 0, is_created_by_me INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, item_total REAL)');
    await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, customer_id INTEGER, amount_changed REAL, '
        'transaction_date TEXT, invoice_id INTEGER, transaction_uuid TEXT, transaction_type TEXT, '
        'is_deleted INTEGER DEFAULT 0, is_created_by_me INTEGER DEFAULT 1)');
    await FinancialBlackBox.ensure(db);
    await FinancialBlackBox.ensure(db); // مرتين بلا خطأ
  });
  tearDown(() => db.close());

  Future<void> customer(int id, String name, double debt) =>
      db.insert('customers', {'id': id, 'name': name, 'current_total_debt': debt});
  Future<void> invoice(int id, int? cid, String pt, double total, {double paid = 0, int del = 0}) =>
      db.insert('invoices', {
        'id': id,
        'invoice_number': 'F$id',
        'customer_id': cid,
        'customer_name': 'c$cid',
        'payment_type': pt,
        'total_amount': total,
        'amount_paid_on_invoice': paid,
        'is_deleted': del,
      });
  Future<int> tx(int cid, double a, {int? inv, String type = 'invoice_debt_sync', int mine = 1}) =>
      db.insert('transactions', {
        'customer_id': cid,
        'amount_changed': a,
        'transaction_date': '2026-11-01',
        'invoice_id': inv,
        'transaction_uuid': 'u${DateTime.now().microsecondsSinceEpoch}$cid$a',
        'transaction_type': type,
        'is_created_by_me': mine,
      });

  Future<int> changes() async => ((await db.rawQuery('SELECT total_changes() AS n')).first['n'] as int);

  test('قاعدة سليمة: لا أخطاء، ولا كتابة إطلاقاً', () async {
    await customer(1, 'أحمد', 70);
    await invoice(10, 1, 'دين', 100, paid: 30);
    await tx(1, 70, inv: 10);
    await invoice(11, 1, 'نقد', 50);
    final before = await changes();
    final r = await FinancialDeepCheck(db).run();
    expect(await changes(), before, reason: 'الفحص لا يكتب');
    expect(r.errors, 0, reason: r.asText());
  });

  test('يكشف ما يخفيه «الرصيد = المجموع»: دين ناقص، فاتورة بلا دين، نقد بأثر، أثر على عميل آخر', () async {
    await customer(1, 'أحمد', 80 + 20 + 15);
    await customer(2, 'علي', 40);
    await invoice(10, 1, 'دين', 100); // سجل الديون 80 فقط
    await tx(1, 80, inv: 10);
    await invoice(11, 1, 'دين', 60); // لا شيء في سجل الديون
    await invoice(12, 1, 'نقد', 20); // نقد وله أثر
    await tx(1, 20, inv: 12);
    await invoice(13, 2, 'دين', 40, del: 1); // محذوفة وأثرها باقٍ على علي
    await tx(2, 40, inv: 13);
    await invoice(14, 1, 'دين', 15); // سليمة: لا تظهر
    await tx(1, 15, inv: 14);
    final r = await FinancialDeepCheck(db).run();
    final text = r.asText();
    // الأرصدة نفسها تطابق المجموع — الفحص القديم كان سيقول «سليم»
    expect(text, isNot(contains('رصيده لا يساوي مجموع معاملاته')));
    expect(text, contains('فاتورة F10'));
    expect(text, contains('لم تصل إلى سجل الديون'));
    expect(text, contains('فاتورة F11'));
    expect(text, contains('F12'));
    expect(text, contains('F13'));
    expect(text, isNot(contains('فاتورة F14')));
  });

  test('صف تسوية مكرر لفاتورة واحدة = خطأ', () async {
    await customer(1, 'أحمد', 200);
    await invoice(10, 1, 'دين', 100);
    await tx(1, 100, inv: 10);
    await tx(1, 100, inv: 10);
    final r = await FinancialDeepCheck(db).run();
    expect(r.asText(), contains('أكثر من صف دين واحد'));
  });

  test('الصندوق الأسود يسجّل الدين والمعاملة والحذف النهائي — ولا يمنع شيئاً', () async {
    await customer(1, 'أحمد', 0);
    final id = await tx(1, 50);
    await db.update('customers', {'current_total_debt': 50}, where: 'id = 1');
    await db.update('customers', {'current_total_debt': 50}, where: 'id = 1'); // بلا تغيّر ⇒ لا سطر
    await db.update('transactions', {'amount_changed': 60}, where: 'id = ?', whereArgs: [id]);
    await db.update('customers', {'current_total_debt': 999}, where: 'id = 1'); // مسار «قديم» يكتب رقماً خاطئاً
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    final other = await tx(1, 5, mine: 0);
    await db.delete('transactions', where: 'id = ?', whereArgs: [other]); // معاملة جهاز آخر ⇒ لا تُسجَّل

    final log = await db.query(FinancialBlackBox.table, orderBy: 'id');
    expect(log.map((e) => e['kind']).toList(), ['debt', 'tx_change', 'debt', 'tx_delete']);
    expect(log[2]['new_value'], 999);
    expect(log[2]['tx_sum'], 60);
    expect(log[3]['old_value'], 60);

    final r = await FinancialDeepCheck(db).run();
    final text = r.asText();
    expect(text, contains('رصيده لا يساوي مجموع معاملاته'));
    expect(text, contains('مجموع المعاملات لحظتها 60'));
    expect(text, contains('حُذفت نهائياً'));
  });
}
