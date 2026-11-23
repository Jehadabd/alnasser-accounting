// test/erp/invoice_returns_test.dart
//
// ↩️ حارس الفاتورة التي عليها مرتجع (كما في ERP): الفاتورة تبقى كما بيعت، والمرتجع مستند مستقل.
// لا حذف، ولا تغيير عميل، ولا إنقاص مادة تحت ما أُرجع — إلا بعد إلغاء المرتجع.

import 'package:alnaser/erp/sales/invoice_returns.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, sync_uuid TEXT)');
    await db.execute('CREATE TABLE sales_returns (id INTEGER PRIMARY KEY, return_no INTEGER, return_date TEXT, '
        'original_invoice_id INTEGER, refund_mode TEXT, total REAL, cash_amount REAL, notes TEXT, status TEXT)');
    await db.execute('CREATE TABLE sales_return_items (id INTEGER PRIMARY KEY, return_id INTEGER, product_id INTEGER, '
        'product_name TEXT, sale_type TEXT, quantity REAL, base_qty REAL, total REAL)');
    await db.insert('products', {'id': 7, 'name': 'شاحن سامسونج', 'sync_uuid': 'u7'});
    await db.insert('products', {'id': 8, 'name': 'كابل', 'sync_uuid': null});
    // فاتورة 100: بيعت قطعة شاحن، ثم استرجاع ضمان لقطعة واحدة
    await db.insert('sales_returns', {
      'id': 1, 'return_no': 3, 'return_date': '2026-11-23', 'original_invoice_id': 100, 'refund_mode': 'credit',
      'total': 25000, 'cash_amount': 0, 'notes': 'ضمان — عطل', 'status': 'posted',
    });
    await db.insert('sales_return_items', {
      'return_id': 1, 'product_id': 7, 'product_name': 'شاحن سامسونج', 'sale_type': 'قطعة', 'quantity': 1,
      'base_qty': 1, 'total': 25000,
    });
    // مرتجع ملغى على فاتورة 200 — لا يحسب
    await db.insert('sales_returns', {
      'id': 2, 'return_no': 4, 'return_date': '2026-11-23', 'original_invoice_id': 200, 'refund_mode': 'cash',
      'total': 5000, 'cash_amount': 5000, 'notes': '', 'status': 'void',
    });
    await db.insert('sales_return_items', {
      'return_id': 2, 'product_id': 8, 'product_name': 'كابل', 'sale_type': 'قطعة', 'quantity': 1, 'base_qty': 1, 'total': 5000,
    });
  });
  tearDown(() => db.close());

  test('المرتجع المُرحَّل يظهر على فاتورته، والملغى لا', () async {
    final docs = await InvoiceReturns.forInvoice(db, 100);
    expect(docs.length, 1);
    expect(docs.first.no, '3');
    expect(docs.first.warranty, isTrue);
    expect(docs.first.credit, 25000);
    expect(await InvoiceReturns.forInvoice(db, 200), isEmpty);
    expect(await InvoiceReturns.returnedBase(db, 100), {7: 1.0});
  });

  test('لا تُحذف فاتورة عليها مرتجع مُرحَّل', () async {
    expect(await InvoiceReturns.deleteBlockReason(db, 100), isNotNull);
    expect(await InvoiceReturns.deleteBlockReason(db, 200), isNull); // مرتجعها ملغى
    expect(await InvoiceReturns.deleteBlockReason(db, 999), isNull);
  });

  test('لا تُنقص المادة المرتجعة تحت ما أُرجع، ولا يتغيّر العميل', () async {
    expect(await InvoiceReturns.editBlockReason(db, 100, newBase: {7: 0}, customerChanged: false), isNotNull);
    expect(await InvoiceReturns.editBlockReason(db, 100, newBase: {}, customerChanged: false), isNotNull); // حُذف السطر
    expect(await InvoiceReturns.editBlockReason(db, 100, newBase: {7: 1}, customerChanged: false), isNull);
    expect(await InvoiceReturns.editBlockReason(db, 100, newBase: {7: 3, 8: 1}, customerChanged: false), isNull);
    expect(await InvoiceReturns.editBlockReason(db, 100, newBase: {7: 1}, customerChanged: true), isNotNull);
    expect(await InvoiceReturns.editBlockReason(db, 200, newBase: {}, customerChanged: true), isNull);
  });

  test('كمية السطر بالأساسية: بـ sync_uuid أو بالاسم، والكرتون × عدد قطعه', () async {
    final r = await InvoiceReturns.baseOfLines(db, [
      (syncUuid: 'u7', name: 'شاحن سامسونج', large: null, single: 2.0, per: null),
      (syncUuid: null, name: 'كابل', large: 2.0, single: null, per: 12.0),
    ]);
    expect(r.base, {7: 2.0, 8: 24.0});
  });
}
