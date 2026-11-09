// lib/erp/variants/variant_store.dart
//
// 🗄️ عائلات المتغيّرات: product_families (المادة الأساس) و product_family_members (كل متغيّر
// مادة حقيقية + خصائصه). إنشاء المتغيّر يمر بالحفظ المعتمد للمواد (DatabaseService.insertProduct)
// فيأخذ معرّف مزامنة ورصيداً افتتاحياً صفراً كأي مادة جديدة — لا كتابة مباشرة في جدول المواد.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/product.dart';
import '../../services/database_service.dart';
import '../erp_common.dart';
import 'variant_models.dart';

class VariantMember {
  VariantMember(this.productId, this.name, this.attrs, this.stock);
  final int productId;
  final String name;
  final VariantCombo attrs;
  final double stock;
}

class VariantFamily {
  VariantFamily(this.id, this.baseProductId, this.name, this.members);
  final int id, baseProductId;
  final String name;
  final List<VariantMember> members;
  double get stock => members.fold(0.0, (s, m) => s + m.stock);
}

class VariantStore {
  VariantStore({DatabaseService? db}) : _svc = db ?? DatabaseService();
  final DatabaseService _svc;
  static int _readyGen = -1;

  Future<Database> _db() async {
    final db = await _svc.database;
    if (_readyGen != DatabaseService.openGeneration) {
      await ensureSchema(db);
      _readyGen = DatabaseService.openGeneration;
    }
    return db;
  }

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_families (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base_product_id INTEGER NOT NULL UNIQUE,
        name TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_family_members (
        family_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL UNIQUE,
        attrs TEXT NOT NULL
      )''');
  }

  Future<List<VariantFamily>> families() async {
    final db = await _db();
    final fams = await db.query('product_families', orderBy: 'name');
    final out = <VariantFamily>[];
    for (final f in fams) {
      final rows = await db.rawQuery('''
        SELECT m.product_id, m.attrs, p.name, COALESCE(p.stock_quantity, 0) AS q
        FROM product_family_members m JOIN products p ON p.id = m.product_id
        WHERE m.family_id = ? AND COALESCE(p.is_deleted, 0) = 0 ORDER BY p.name''', [f['id']]);
      out.add(VariantFamily(f['id'] as int, f['base_product_id'] as int, '${f['name']}', [
        for (final r in rows)
          VariantMember(r['product_id'] as int, '${r['name']}', _attrs(r['attrs']), (r['q'] as num).toDouble()),
      ]));
    }
    return out;
  }

  static VariantCombo _attrs(Object? raw) {
    try {
      return (jsonDecode('$raw') as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  /// ينشئ المتغيّرات الناقصة من المادة [baseId] (بأسعارها وكلفتها ووحداتها، وكمية صفر).
  /// يعيد (أُنشئ، تُخطّي لأن الاسم موجود).
  Future<({int created, List<String> skipped})> create(int baseId, List<VariantCombo> combos) async {
    if (combos.isEmpty) throw ErpException('أدخل قيم خاصية واحدة على الأقل');
    final base = await _svc.getProductById(baseId);
    if (base == null) throw ErpException('المادة الأساس غير موجودة');
    final db = await _db();
    final famRows = await db.query('product_families', where: 'base_product_id = ?', whereArgs: [baseId]);
    final famId = famRows.isEmpty
        ? await db.insert('product_families', {'base_product_id': baseId, 'name': base.name})
        : famRows.first['id'] as int;
    var created = 0;
    final skipped = <String>[];
    for (final c in combos) {
      final name = Variants.name(base.name, c);
      final exists = await db.query('products', columns: ['id'], where: 'name = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [name], limit: 1);
      if (exists.isNotEmpty) {
        skipped.add(name);
        continue;
      }
      final now = DateTime.now();
      final id = await _svc.insertProduct(Product(
        name: name,
        unit: base.unit,
        unitPrice: base.unitPrice,
        costPrice: base.costPrice,
        piecesPerUnit: base.piecesPerUnit,
        lengthPerUnit: base.lengthPerUnit,
        price1: base.price1,
        price2: base.price2,
        price3: base.price3,
        price4: base.price4,
        price5: base.price5,
        price6: base.price6,
        unitHierarchy: base.unitHierarchy,
        unitCosts: base.unitCosts,
        createdAt: now,
        lastModifiedAt: now,
        categoryId: base.categoryId,
        isWeighable: base.isWeighable,
        baseWeight: base.baseWeight,
        weightUnit: base.weightUnit,
        hasExpiry: base.hasExpiry,
        productType: base.productType,
        invoicePolicy: base.invoicePolicy,
        alertQuantity: base.alertQuantity,
        alertUnit: base.alertUnit,
        stockQuantity: 0,
      ));
      await db.insert('product_family_members', {'family_id': famId, 'product_id': id, 'attrs': jsonEncode(c)},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      created++;
    }
    return (created: created, skipped: skipped);
  }
}
