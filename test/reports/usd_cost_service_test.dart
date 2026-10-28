// test/reports/usd_cost_service_test.dart
//
// تثبيت كلفة المبيعات السابقة قبل تغيير كلفة المادة، وتحجيم كلفة الوحدات.
// التشغيل: flutter test test/reports/usd_cost_service_test.dart

import 'dart:convert';

import 'package:alnaser/erp/inventory/usd_cost_service.dart';
import 'package:alnaser/models/product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _db() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, unit TEXT, cost_price REAL,
      length_per_unit REAL, unit_costs TEXT, unit_hierarchy TEXT, is_deleted INTEGER DEFAULT 0)''');
  await db.execute('CREATE TABLE invoices (id INTEGER PRIMARY KEY, status TEXT)');
  await db.execute('''CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_name TEXT,
      product_id INTEGER, quantity_individual REAL, quantity_large_unit REAL, units_in_large_unit REAL,
      actual_cost_price REAL, applied_price REAL, sale_type TEXT)''');
  await db.execute('''CREATE TABLE invoice_adjustments (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_id INTEGER,
      quantity REAL, base_unit_cost REAL)''');
  await db.execute(
      "CREATE TABLE product_details (product_id INTEGER PRIMARY KEY, cost_currency TEXT NOT NULL DEFAULT 'IQD', cost_usd REAL, updated_at TEXT)");

  await db.insert('products', {
    'id': 1,
    'name': 'سلك',
    'unit': 'piece',
    'cost_price': 1300,
    'unit_costs': jsonEncode({'قطعة': 1300, 'كرتون': 13000}),
    'unit_hierarchy': jsonEncode([
      {'unit_name': 'كرتون', 'quantity': 10}
    ]),
  });
  await db.insert('products', {'id': 2, 'name': 'لمبة', 'unit': 'piece', 'cost_price': 500});
  await db.insert('invoices', {'id': 1, 'status': 'محفوظة'});
  await db.insert('invoices', {'id': 2, 'status': 'معلقة'});
  // بلا كلفة محفوظة: قطعتان + كرتونان
  await db.insert('invoice_items', {'id': 1, 'invoice_id': 1, 'product_name': 'سلك', 'product_id': 1,
      'quantity_individual': 2, 'quantity_large_unit': 0, 'actual_cost_price': 0, 'applied_price': 1500, 'sale_type': 'قطعة'});
  await db.insert('invoice_items', {'id': 2, 'invoice_id': 1, 'product_name': 'سلك', 'product_id': 1,
      'quantity_individual': 0, 'quantity_large_unit': 2, 'units_in_large_unit': 10, 'actual_cost_price': null,
      'applied_price': 15000, 'sale_type': 'كرتون'});
  // بكلفة محفوظة: لا يُلمس
  await db.insert('invoice_items', {'id': 3, 'invoice_id': 1, 'product_name': 'سلك', 'product_id': 1,
      'quantity_individual': 1, 'actual_cost_price': 900, 'applied_price': 1500, 'sale_type': 'قطعة'});
  // فاتورة معلّقة: لا يُثبَّت (البيع لم يكتمل)
  await db.insert('invoice_items', {'id': 4, 'invoice_id': 2, 'product_name': 'سلك', 'product_id': 1,
      'quantity_individual': 1, 'actual_cost_price': 0, 'applied_price': 1500, 'sale_type': 'قطعة'});
  // مادة أخرى: لا تُلمس
  await db.insert('invoice_items', {'id': 5, 'invoice_id': 1, 'product_name': 'لمبة', 'product_id': 2,
      'quantity_individual': 1, 'actual_cost_price': 0, 'applied_price': 800, 'sale_type': 'قطعة'});
  await db.insert('invoice_adjustments', {'id': 1, 'invoice_id': 1, 'product_id': 1, 'quantity': 1, 'base_unit_cost': null});
  await db.insert('invoice_adjustments', {'id': 2, 'invoice_id': 1, 'product_id': 1, 'quantity': 1, 'base_unit_cost': 1000});
  return db;
}

double _acp(List<Map<String, Object?>> rows, int id) =>
    ((rows.firstWhere((r) => r['id'] == id)['actual_cost_price']) as num?)?.toDouble() ?? 0;

void main() {
  sqfliteFfiInit();

  test('تثبيت كلفة البنود والتسويات التي بلا كلفة محفوظة', () async {
    final db = await _db();
    final r = await UsdCostService.freezePastCosts(db, {1});
    expect(r.items, 2);
    expect(r.adjustments, 1);
    final items = await db.query('invoice_items');
    expect(_acp(items, 1), 1300); // كلفة القطعة
    expect(_acp(items, 2), 13000); // كلفة الكرتون من unit_costs
    expect(_acp(items, 3), 900); // محفوظة سابقاً
    expect(_acp(items, 4), 0); // معلّقة
    expect(_acp(items, 5), 0); // مادة أخرى
    final adj = await db.query('invoice_adjustments', orderBy: 'id');
    expect(adj[0]['base_unit_cost'], 1300);
    expect(adj[1]['base_unit_cost'], 1000);
  });

  test('التثبيت مرة ثانية لا يغيّر شيئاً', () async {
    final db = await _db();
    await UsdCostService.freezePastCosts(db, {1});
    await db.update('products', {'cost_price': 1450}, where: 'id = 1');
    final r = await UsdCostService.freezePastCosts(db, {1});
    expect(r.items, 0);
    expect(r.adjustments, 0);
    expect(_acp(await db.query('invoice_items'), 1), 1300);
  });

  test('عملة الكلفة تُكتب في بطاقة المادة وتُقرأ', () async {
    final db = await _db();
    await UsdCostService.writeCurrency(db, 1, currency: 'USD', usd: 1);
    var c = await UsdCostService.read(db, 1);
    expect(c.currency, 'USD');
    expect(c.usd, 1);
    await UsdCostService.writeCurrency(db, 1, currency: 'IQD');
    c = await UsdCostService.read(db, 1);
    expect(c.currency, 'IQD');
    expect(c.usd, isNull);
  });

  test('كلفة الوحدات تتبع الوحدة الأساسية بالنسبة نفسها', () {
    final now = DateTime(2026);
    final p = Product(
      name: 'سلك',
      unit: 'piece',
      unitPrice: 1500,
      price1: 1500,
      costPrice: 1300,
      unitCosts: jsonEncode({'قطعة': 1300, 'كرتون': 13000}),
      createdAt: now,
      lastModifiedAt: now,
    );
    final m = jsonDecode(UsdCostService.scaledUnitCosts(p, 1450)!) as Map;
    expect(m['قطعة'], 1450);
    expect(m['كرتون'], 14500);
    // بلا كلفة وحدات محفوظة: تُبنى من التسلسل
    final q = Product(
      name: 'سلك',
      unit: 'piece',
      unitPrice: 1500,
      price1: 1500,
      costPrice: 0,
      unitHierarchy: jsonEncode([
        {'unit_name': 'كرتون', 'quantity': 10},
        {'unit_name': 'صندوق', 'quantity': 4}
      ]),
      createdAt: now,
      lastModifiedAt: now,
    );
    final n = jsonDecode(UsdCostService.scaledUnitCosts(q, 1450)!) as Map;
    expect(n['قطعة'], 1450);
    expect(n['كرتون'], 14500);
    expect(n['صندوق'], 58000);
  });
}
