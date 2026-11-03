// test/purchases/purchase_price_history_test.dart
//
// سجل أسعار الشراء: آخر 3 لكل مورد، المقارنة بالوحدة الأساسية والعملة نفسها،
// المؤكدة فقط، واستثناء الفاتورة المفتوحة للتعديل.

import 'package:alnaser/erp/purchases/purchase_price_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  Future<void> buy(int id, int supplier, String date, double price,
      {String unit = 'قطعة', double factor = 1, String currency = 'IQD', String status = 'confirmed'}) async {
    await db.insert('purchase_invoices',
        {'id': id, 'invoice_number': 'P$id', 'supplier_id': supplier, 'date': date, 'currency': currency, 'status': status});
    await db.insert('purchase_invoice_items',
        {'invoice_id': id, 'product_id': 7, 'unit_name': unit, 'unit_price': price, 'conversion_factor': factor});
  }

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE suppliers (id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE purchase_invoices (id INTEGER PRIMARY KEY, invoice_number TEXT, supplier_id INTEGER, '
        'date TEXT, currency TEXT, status TEXT)');
    await db.execute('CREATE TABLE purchase_invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_id INTEGER, '
        'unit_name TEXT, unit_price REAL, conversion_factor REAL)');
    await db.insert('suppliers', {'id': 1, 'name': 'الفرات'});
    await db.insert('suppliers', {'id': 2, 'name': 'النور'});
    await buy(1, 1, '2026-01-01', 1000);
    await buy(2, 1, '2026-02-01', 1100);
    await buy(3, 1, '2026-03-01', 1150);
    await buy(4, 1, '2026-04-01', 24000, unit: 'كرتون', factor: 24); // 1000 للقطعة
    await buy(5, 2, '2026-04-15', 950);
    await buy(6, 2, '2026-05-01', 900, status: 'draft'); // مسودة لا تُحسب
    await buy(7, 2, '2026-05-02', 3, currency: 'USD');
  });
  tearDown(() => db.close());

  test('آخر 3 لكل مورد، الأحدث أولاً، المؤكدة فقط', () async {
    final r = await PurchasePriceHistory.forProduct(db, 7);
    expect(r.where((x) => x.supplierId == 1).map((x) => x.invoiceNumber), ['P4', 'P3', 'P2']);
    expect(r.where((x) => x.supplierId == 2).map((x) => x.invoiceNumber), ['P7', 'P5']);
    expect(r.first.baseCost, 1000); // كرتون 24000 ÷ 24
  });

  test('آخر شراء من المورد نفسه وبالعملة نفسها، مع استثناء الفاتورة المفتوحة', () async {
    expect((await PurchasePriceHistory.last(db, productId: 7, supplierId: 1, currency: 'IQD'))!.invoiceNumber, 'P4');
    expect((await PurchasePriceHistory.last(db, productId: 7, supplierId: 1, currency: 'IQD', excludeInvoiceId: 4))!
        .invoiceNumber, 'P3');
    expect((await PurchasePriceHistory.last(db, productId: 7, supplierId: 2, currency: 'IQD'))!.invoiceNumber, 'P5');
    expect((await PurchasePriceHistory.last(db, productId: 7, supplierId: 2, currency: 'USD'))!.unitPrice, 3);
    expect(await PurchasePriceHistory.last(db, productId: 7, supplierId: 9, currency: 'IQD'), isNull);
  });

  test('نسبة الارتفاع', () {
    expect(PurchasePriceHistory.risePct(1100, 1000), closeTo(10, 1e-9));
    expect(PurchasePriceHistory.risePct(900, 1000), closeTo(-10, 1e-9));
    expect(PurchasePriceHistory.risePct(1000, null), isNull);
    expect(PurchasePriceHistory.risePct(1000, 0), isNull);
  });
}
