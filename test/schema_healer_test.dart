// test/schema_healer_test.dart
// مُصلِح المخطط: قاعدة قديمة ينقصها categories و units و products.barcode.
// التشغيل: flutter test test/schema_healer_test.dart

import 'package:alnaser/services/database/core/database_migrations.dart';
import 'package:alnaser/services/database/core/schema_healer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Set<String>> _cols(Database db, String t) async => {
      for (final c in await db.rawQuery('PRAGMA table_info("$t")')) c['name'] as String,
    };

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    SharedPreferences.setMockInitialValues({});
  });

  test('يكمّل الجداول والأعمدة الناقصة دون المساس بالبيانات', () async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    // قاعدة قديمة: منتجات بلا barcode/category_id، ولا جدول أقسام ولا وحدات
    await db.execute('''CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, unit TEXT NOT NULL, cost_price REAL NOT NULL,
        stock_quantity REAL DEFAULT 0)''');
    await db.insert('products',
        {'name': 'مادة قديمة', 'unit': 'قطعة', 'cost_price': 750, 'stock_quantity': 12});

    final n = await SchemaHealer.heal(db, DatabaseMigrations.createTables);
    expect(n, greaterThan(0));

    final tables = {
      for (final r in await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        r['name'] as String,
    };
    expect(tables, containsAll(['categories', 'units', 'customers', 'invoices']));

    final pc = await _cols(db, 'products');
    expect(pc, containsAll(['barcode', 'category_id', 'price1', 'unit_hierarchy', 'created_at']));

    // البيانات القديمة سليمة، والاستعلامات التي كانت تفشل تعمل الآن
    final p = (await db.query('products')).single;
    expect(p['name'], 'مادة قديمة');
    expect(p['stock_quantity'], 12);
    expect(p['price1'], 0); // الافتراضي الثابت طُبّق
    await db.rawQuery('''SELECT p.barcode, c.name FROM products p
        LEFT JOIN categories c ON c.id = p.category_id''');
    await db.rawQuery('SELECT * FROM units ORDER BY is_default DESC, name ASC');

    // التكرار آمن: لا شيء يُضاف مرة ثانية
    expect(await SchemaHealer.heal(db, DatabaseMigrations.createTables), 0);
    await db.close();
  });
}
