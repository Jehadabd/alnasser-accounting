// test/inventory/product_lookup_test.dart
//
// البحث عن مادة: بالاسم (بلا فواصل وبأي ترتيب) أو رمز المادة أو الباركود — لا بالرقم الداخلي.

import 'package:alnaser/inventory/product_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, barcode TEXT, is_deleted INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE product_details (product_id INTEGER, item_code TEXT, second_name TEXT, min_role TEXT)');
    await db.execute('CREATE TABLE product_barcodes (product_id INTEGER, barcode TEXT)');
    await db.insert('products', {'id': 12, 'name': 'قاطع 32 أمبير ثنائي', 'barcode': '6281000000017'});
    await db.insert('products', {'id': 13, 'name': 'سلك 2.5 مم', 'barcode': null});
    await db.insert('products', {'id': 14, 'name': 'مصباح ليد', 'barcode': '999'});
    await db.insert('product_details', {'product_id': 13, 'item_code': 'W-25'});
    await db.insert('product_details', {'product_id': 14, 'item_code': 'L12'});
    await db.insert('product_barcodes', {'product_id': 13, 'barcode': '4400'});
  });
  tearDown(() => db.close());

  Future<List<int>> find(String q) async {
    final w = ProductLookup.where(q)!;
    final r = await db.rawQuery(
        'SELECT p.id FROM products p LEFT JOIN product_details d ON d.product_id = p.id '
        'WHERE ${w.sql} ORDER BY p.id',
        w.args);
    return [for (final x in r) x['id'] as int];
  }

  test('الاسم: كلمات بأي ترتيب وبلا فواصل وهمزات', () async {
    expect(await find('ثنائي قاطع'), [12]);
    expect(await find('امبير'), [12]); // أمبير
    expect(await find('سلك2.5'), [13]);
  });

  test('رمز المادة: جزء منه', () async {
    expect(await find('w-25'), [13]);
    expect(await find('L1'), [14]);
  });

  test('الباركود: الأساسي أو الإضافي، مطابقة تامة', () async {
    expect(await find('6281000000017'), [12]);
    expect(await find('4400'), [13]);
    expect(await find('628100'), isEmpty); // جزء من باركود لا يكفي
  });

  test('الرقم الداخلي (id) ليس وسيلة بحث', () async {
    expect(await find('13'), isEmpty); // id المادة 13 — لا رمز ولا باركود ولا اسم فيه 13
    expect(await find('12'), [14]); // فقط لأن رمز المادة 14 هو L12 — لا المادة 12
  });

  test('بحث فارغ = بلا شرط', () {
    expect(ProductLookup.where('  '), isNull);
  });
}
