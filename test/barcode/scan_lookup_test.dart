// test/barcode/scan_lookup_test.dart
//
// مادة الرمز المقروء: الباركود (أساسي/إضافي) ثم رمز المادة ثم صيغ UPC/EAN — مطابقة تامة.

import 'package:alnaser/services/barcode/scan_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, barcode TEXT, is_deleted INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE product_details (product_id INTEGER, item_code TEXT, min_role TEXT)');
    await db.execute('CREATE TABLE product_barcodes (product_id INTEGER, barcode TEXT UNIQUE)');
    await db.insert('products', {'id': 1, 'name': 'قاطع', 'barcode': '6281000000017'});
    await db.insert('products', {'id': 2, 'name': 'سلك', 'barcode': ' ab-12 '});
    await db.insert('products', {'id': 3, 'name': 'مصباح', 'barcode': '036000291452'}); // UPC-A
    await db.insert('products', {'id': 4, 'name': 'محذوفة', 'barcode': '555', 'is_deleted': 1});
    await db.insert('products', {'id': 5, 'name': 'للمدير', 'barcode': '777'});
    await db.insert('products', {'id': 6, 'name': 'مكررة أ', 'barcode': '888'});
    await db.insert('products', {'id': 7, 'name': 'مكررة ب', 'barcode': '888'});
    await db.insert('products', {'id': 8, 'name': 'برمز فقط', 'barcode': null});
    await db.insert('product_details', {'product_id': 5, 'min_role': 'admin'});
    await db.insert('product_details', {'product_id': 8, 'item_code': 'W-25'});
    await db.insert('product_details', {'product_id': 2, 'item_code': '6281000000017'}); // رمز يطابق باركود مادة أخرى
    await db.insert('product_barcodes', {'product_id': 2, 'barcode': '4400'});
  });
  tearDown(() => db.close());

  Future<List<int>> ids(String c, {bool admin = false}) => ScanLookup.ids(db, c, isAdmin: admin);

  test('الباركود الأساسي والإضافي، بلا اعتبار للمسافات وحالة الأحرف', () async {
    expect(await ids('6281000000017'), [1]); // الباركود يسبق رمز المادة المطابق
    expect(await ids('4400'), [2]);
    expect(await ids('AB-12'), [2]);
  });

  test('رمز المادة إن لم يوجد باركود', () async {
    expect(await ids('w-25'), [8]);
  });

  test('جزء من الرمز لا يكفي (لا اقتراحات)', () async {
    expect(await ids('628100'), isEmpty);
    expect(await ids('W-2'), isEmpty);
  });

  test('UPC/EAN: صفر زائد أو ناقص في البداية', () async {
    expect(await ids('0036000291452'), [3]);
    expect(ScanLookup.variants('036000291452'), ['0036000291452']);
    expect(ScanLookup.variants('0036000291452'), ['036000291452']);
    expect(ScanLookup.variants('AB12'), isEmpty);
  });

  test('المحذوفة لا تُعاد، و«للمدير فقط» للمدير وحده', () async {
    expect(await ids('555'), isEmpty);
    expect(await ids('777'), isEmpty);
    expect(await ids('777', admin: true), [5]);
  });

  test('رمز لأكثر من مادة ⇒ كلها (يختار المستخدم)', () async {
    expect(await ids('888'), [6, 7]);
  });

  test('فارغ ⇒ لا شيء', () async {
    expect(await ids('  '), isEmpty);
  });
}
