// test/inventory/label_reprint_test.dart
//
// ملصقات تحتاج إعادة طباعة: يُسجَّل السعر المطبوع لكل مستوى، وتظهر المادة فقط
// إن تغيّر سعرها بعده؛ وغير المطبوعة لا تظهر.

import 'package:alnaser/erp/inventory/label_reprint.dart';
import 'package:alnaser/erp/stock_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  ProductLite lite(int id, {double unitPrice = 0, double price1 = 0, double price2 = 0}) =>
      ProductLite.fromRow({'id': id, 'name': 'م$id', 'unit_price': unitPrice, 'price1': price1, 'price2': price2});

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, unit_price REAL, price1 REAL, '
        'price2 REAL, price3 REAL, price4 REAL, price5 REAL, price6 REAL, is_deleted INTEGER DEFAULT 0)');
    await db.insert('products', {'id': 1, 'name': 'م1', 'unit_price': 900, 'price1': 1000, 'price2': 950});
    await db.insert('products', {'id': 2, 'name': 'م2', 'unit_price': 500, 'price1': 0});
    await db.insert('products', {'id': 3, 'name': 'م3', 'price1': 300});
  });
  tearDown(() => db.close());

  test('يظهر فقط ما تغيّر سعره بعد طباعة ملصقه', () async {
    await LabelReprint.record(db, [lite(1, unitPrice: 900, price1: 1000, price2: 950), lite(2, unitPrice: 500)], 1);
    expect(await LabelReprint.stale(db), isEmpty); // طُبع بالسعر الحالي
    await db.update('products', {'price1': 1100}, where: 'id = 1');
    await db.update('products', {'price1': 999}, where: 'id = 3'); // لم يُطبع له ملصق — لا يظهر
    final s = await LabelReprint.stale(db);
    expect(s.single.productId, 1);
    expect(s.single.printedPrice, 1000);
    expect(s.single.currentPrice, 1100);
    // المادة 2: سعرها unit_price لأن price1 صفر — تغييره يظهرها
    await db.update('products', {'unit_price': 550}, where: 'id = 2');
    expect((await LabelReprint.stale(db)).map((x) => x.productId), [1, 2]);
    // إعادة الطباعة بالسعر الجديد تُخفيها
    await LabelReprint.record(db, [lite(1, unitPrice: 900, price1: 1100, price2: 950)], 1);
    expect((await LabelReprint.stale(db)).map((x) => x.productId), [2]);
  });

  test('كل مستوى سعر مستقل، والمحذوفة لا تظهر', () async {
    await LabelReprint.record(db, [lite(1, unitPrice: 900, price1: 1000, price2: 950)], 2);
    await db.update('products', {'price1': 1200}, where: 'id = 1'); // المستوى 1 لم يُطبع
    expect(await LabelReprint.stale(db), isEmpty);
    await db.update('products', {'price2': 990}, where: 'id = 1');
    expect((await LabelReprint.stale(db)).single.level, 2);
    await db.update('products', {'is_deleted': 1}, where: 'id = 1');
    expect(await LabelReprint.stale(db), isEmpty);
  });
}
