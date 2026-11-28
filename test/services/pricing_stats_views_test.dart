// test/services/pricing_stats_views_test.dart
//
// 📊 قاعدة قادمة من debt_book: product_price_stats و recent_sales_buffer «جداول» قديمة.
// كان زر «إصلاح إحصائيات التسعير» ينفّذ DROP VIEW عليها ⇒ خطأ، والأنماط تقرأ أرقاماً قديمة.
// هنا بكود البرنامج نفسه (PricingStatsViews):
//   • الجدول القديم يُحفظ باسم _legacy_… ببياناته (لا يُحذف شيء)، والاسم يصير View حية.
//   • الإصلاح يعمل مراراً بلا خطأ، والـ View تقرأ الفواتير الحالية.

import 'package:alnaser/services/database/core/pricing_stats_views.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _open() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('CREATE TABLE invoices (id INTEGER PRIMARY KEY, invoice_date TEXT)');
  await db.execute('CREATE TABLE invoice_items (id INTEGER PRIMARY KEY, invoice_id INTEGER, product_id INTEGER, applied_price REAL)');
  await db.insert('invoices', {'id': 1, 'invoice_date': '2026-11-01'});
  await db.insert('invoices', {'id': 2, 'invoice_date': '2026-11-20'});
  await db.insert('invoice_items', {'invoice_id': 1, 'product_id': 5, 'applied_price': 1000});
  await db.insert('invoice_items', {'invoice_id': 2, 'product_id': 5, 'applied_price': 2000});
  return db;
}

Future<String?> _type(Database db, String name) async {
  final r = await db.rawQuery('SELECT type FROM sqlite_master WHERE name = ?', [name]);
  return r.isEmpty ? null : r.first['type'] as String?;
}

void main() {
  sqfliteFfiInit();

  test('جداول debt_book القديمة ⇒ تُحفظ باسم _legacy_ والاسم يصير View حية', () async {
    final db = await _open();
    await db.execute('CREATE TABLE product_price_stats (product_id INTEGER PRIMARY KEY, median_price REAL, sale_count INTEGER)');
    await db.execute('CREATE TABLE recent_sales_buffer (id INTEGER PRIMARY KEY, product_id INTEGER, price REAL, invoice_date TEXT)');
    await db.insert('product_price_stats', {'product_id': 5, 'median_price': 99, 'sale_count': 1});
    await db.insert('recent_sales_buffer', {'product_id': 5, 'price': 77, 'invoice_date': '2025-01-01'});

    await PricingStatsViews.ensure(db);

    expect(await _type(db, 'product_price_stats'), 'view');
    expect(await _type(db, 'recent_sales_buffer'), 'view');
    // القديم محفوظ ببياناته
    expect((await db.query('_legacy_product_price_stats')).single['median_price'], 99);
    expect((await db.query('_legacy_recent_sales_buffer')).single['price'], 77);
    // الـ View تقرأ الفواتير الحالية لا الأرقام القديمة
    final s = (await db.query('product_price_stats', where: 'product_id = 5')).single;
    expect(s['median_price'], 1500);
    expect(s['sales_count'], 2);
    final last = await db.rawQuery(
        'SELECT price FROM recent_sales_buffer WHERE product_id = 5 ORDER BY invoice_date DESC LIMIT 1');
    expect(last.single['price'], 2000);
    await db.close();
  });

  test('زر الإصلاح يعمل مراراً بلا خطأ (هنا كان يقع خطأ DROP VIEW على جدول)', () async {
    final db = await _open();
    await db.execute('CREATE TABLE product_price_stats (product_id INTEGER PRIMARY KEY, median_price REAL)');
    await PricingStatsViews.repair(db);
    await PricingStatsViews.repair(db);
    await PricingStatsViews.ensure(db);
    expect(await _type(db, 'product_price_stats'), 'view');
    expect(await _type(db, 'recent_sales_buffer'), 'view');
    await db.close();
  });

  test('قاعدة جديدة بلا شيء ⇒ تُنشأ الـ Views', () async {
    final db = await _open();
    await PricingStatsViews.ensure(db);
    expect(await _type(db, 'product_price_stats'), 'view');
    expect(await _type(db, 'recent_sales_buffer'), 'view');
    expect(await _type(db, '_legacy_product_price_stats'), isNull);
    await db.close();
  });
}
