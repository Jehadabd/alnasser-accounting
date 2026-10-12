// test/invoice_numbering_test.dart
// ترقيم الفواتير الجديدة لا يصطدم بأي من القيدين الفريدين (رقم الفاتورة،
// والجهاز+السنة+الشهر+التسلسل) — حالة «UNIQUE constraint failed: invoices.invoice_number».

import 'package:alnaser/services/database/business/invoice_numbering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'invoice_number TEXT, creator_device_id TEXT, invoice_year INTEGER, '
        'invoice_month INTEGER, monthly_sequence_number INTEGER)');
    await db.execute('CREATE UNIQUE INDEX idx_invoices_invoice_number ON invoices(invoice_number)');
    await db.execute('CREATE UNIQUE INDEX idx_invoices_unique_composite ON invoices('
        'creator_device_id, invoice_year, invoice_month, monthly_sequence_number)');
  });
  tearDown(() => db.close());

  Future<void> add(String? number, String? dev, int y, int m, int? seq) => db.insert('invoices', {
        'invoice_number': number,
        'creator_device_id': dev,
        'invoice_year': y,
        'invoice_month': m,
        'monthly_sequence_number': seq,
      });

  test('حالة الصورة: فواتير جهاز آخر على «رقم الجهاز 1» نفسه ⇒ يكمل بعدها', () async {
    for (var i = 1; i <= 49; i++) {
      await add('1202610$i', '3f2aeedacd1388cccf1df61b8651d5a4', 2026, 10, i);
    }
    final n = await InvoiceNumbering.next(db, deviceNum: 1, year: 2026, month: 10);
    expect(n.seq, 50);
    expect(n.number, '120261050');
    final map = <String, dynamic>{
      'invoice_number': n.number,
      'creator_device_id': '1',
      'invoice_year': 2026,
      'invoice_month': 10,
      'monthly_sequence_number': n.seq,
    };
    expect(await InvoiceNumbering.insertNew(db, map), greaterThan(0));
    final again = await InvoiceNumbering.next(db, deviceNum: 1, year: 2026, month: 10);
    expect(again.number, '120261051');
  });

  test('الصيغة بلا فواصل: نوفمبر/5 = يناير/15 ⇒ يتخطى الرقم المستعمل', () async {
    for (var i = 1; i <= 15; i++) {
      await add('120261$i', '1', 2026, 1, i);
    }
    final n = await InvoiceNumbering.next(db, deviceNum: 1, year: 2026, month: 11);
    expect(n.number, '12026116');
    expect(n.seq, 6);
  });

  test('جهاز آخر سبقنا بالرقم نفسه لحظة الحفظ ⇒ إعادة ترقيم تلقائية', () async {
    final n = await InvoiceNumbering.next(db, deviceNum: 2, year: 2026, month: 10);
    expect(n.number, '2202610' '1');
    await add(n.number, 'x', 2026, 10, 1); // طرفية أخرى حفظت الرقم نفسه قبلنا
    final map = <String, dynamic>{
      'invoice_number': n.number,
      'creator_device_id': '2',
      'invoice_year': 2026,
      'invoice_month': 10,
      'monthly_sequence_number': n.seq,
    };
    await InvoiceNumbering.insertNew(db, map);
    expect(map['invoice_number'], '22026102');
    final rows = await db.query('invoices', where: 'creator_device_id = ?', whereArgs: ['2']);
    expect(rows.single['invoice_number'], '22026102');
  });

  test('تسلسل هذا الجهاز يستمر من آخر رقم له، والأرقام الفارغة لا تُحسب', () async {
    await add(null, null, 2026, 10, null);
    await add('12026107', '1', 2026, 10, 7);
    final n = await InvoiceNumbering.next(db, deviceNum: 1, year: 2026, month: 10);
    expect(n.seq, 8);
    expect(n.number, '12026108');
  });

  test('خطأ غير التكرار لا يُعاد', () async {
    final map = <String, dynamic>{'no_such_column': 1, 'creator_device_id': '1', 'invoice_year': 2026, 'invoice_month': 10};
    expect(() => InvoiceNumbering.insertNew(db, map), throwsA(isA<DatabaseException>()));
  });
}
