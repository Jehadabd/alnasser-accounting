// lib/erp/stock_helpers.dart
//
// 📦 أدوات المخزون المشتركة لكل مستندات النسخة المحاسبية:
//   • وحدات المادة ومعاملات تحويلها إلى الوحدة الأساسية
//   • تسجيل حركة مخزون (عبر StockLedger فقط) مع ربطها بمخزن
//   • بيانات المادة المختصرة للبحث والاختيار

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../services/database/business/stock_ledger.dart';
import 'erp_common.dart';

class UnitOption {
  const UnitOption(this.name, this.factor);
  final String name;

  /// كم وحدة أساسية في هذه الوحدة.
  final double factor;

  @override
  String toString() => factor == 1 ? name : '$name (${fmtQty(factor)})';
}

class ProductLite {
  ProductLite({
    required this.id,
    required this.name,
    required this.unit,
    required this.cost,
    required this.prices,
    required this.stock,
    this.hierarchy,
    this.lengthPerUnit,
    this.barcode,
    this.syncUuid,
    this.categoryId,
    this.itemCode,
    this.itemType = 'trade',
    this.unitCosts,
  });

  final int id;
  final String name;
  final String unit;
  final double cost;

  /// [مفرد، مفرد 2، منزل، جملة، جملة 2، أخرى]
  final List<double> prices;
  final double stock;
  final String? hierarchy;
  final double? lengthPerUnit;
  final String? barcode;
  final String? syncUuid;
  final int? categoryId;
  final String? itemCode;
  final String itemType;
  final String? unitCosts;

  String get baseUnitName => unit == 'piece' ? 'قطعة' : (unit == 'meter' ? 'متر' : unit);

  bool get isService => itemType == 'service';

  /// كل وحدات المادة: الأساسية ثم الوحدات الكبرى بمعاملاتها التراكمية.
  List<UnitOption> get units {
    final out = <UnitOption>[UnitOption(baseUnitName, 1)];
    final seen = <String>{baseUnitName};
    if (hierarchy != null && hierarchy!.trim().isNotEmpty) {
      try {
        List<dynamic> list;
        try {
          list = jsonDecode(hierarchy!) as List<dynamic>;
        } catch (_) {
          list = jsonDecode(hierarchy!.replaceAll("'", '"')) as List<dynamic>;
        }
        var mult = 1.0;
        for (final level in list) {
          if (level is! Map) continue;
          final name = (level['unit_name'] ?? level['name'] ?? '').toString();
          final q = level['quantity'];
          final qty = q is num ? q.toDouble() : (double.tryParse('$q') ?? 1.0);
          mult *= qty <= 0 ? 1 : qty;
          if (name.isEmpty || seen.contains(name)) continue;
          seen.add(name);
          out.add(UnitOption(name, mult));
        }
      } catch (_) {}
    }
    if (unit == 'meter' && (lengthPerUnit ?? 0) > 1 && !seen.contains('لفة')) {
      out.add(UnitOption('لفة', lengthPerUnit!));
    }
    return out;
  }

  UnitOption unitNamed(String? name) {
    for (final u in units) {
      if (u.name == name) return u;
    }
    return units.first;
  }

  /// سعر مستوى (1..6) للوحدة الأساسية.
  double priceLevel(int level) {
    final i = level < 1 ? 0 : (level > 6 ? 5 : level - 1);
    final p = prices[i];
    return p > 0 ? p : prices[0];
  }

  /// كلفة الوحدة المختارة (من unit_costs إن وُجدت، وإلا الكلفة × المعامل).
  double costFor(UnitOption u) {
    if (u.factor == 1) return cost;
    if (unitCosts != null && unitCosts!.trim().isNotEmpty) {
      try {
        final m = jsonDecode(unitCosts!) as Map<String, dynamic>;
        final v = m[u.name];
        if (v is num && v > 0) return v.toDouble();
      } catch (_) {}
    }
    return cost * u.factor;
  }

  factory ProductLite.fromRow(Map<String, Object?> r) {
    double p(String k) => d0(r[k]);
    final unitPrice = p('unit_price');
    final p1 = p('price1') > 0 ? p('price1') : unitPrice;
    return ProductLite(
      id: r['id'] as int,
      name: (r['name'] as String?) ?? '',
      unit: (r['unit'] as String?) ?? 'piece',
      cost: p('cost_price'),
      prices: [p1, p('price2'), p('price3'), p('price4'), p('price5'), p('price6')],
      stock: p('stock_quantity'),
      hierarchy: r['unit_hierarchy'] as String?,
      lengthPerUnit: (r['length_per_unit'] as num?)?.toDouble(),
      barcode: r['barcode'] as String?,
      syncUuid: r['sync_uuid'] as String?,
      categoryId: r['category_id'] as int?,
      itemCode: r['item_code'] as String?,
      itemType: (r['item_type'] as String?) ?? 'trade',
      unitCosts: r['unit_costs'] as String?,
    );
  }
}

/// مستويات الأسعار كما في شاشة الفاتورة.
const List<String> priceLevelNames = ['مفرد', 'مفرد 2', 'منزل', 'جملة', 'جملة 2', 'أخرى'];

int priceLevelIndex(String? name) {
  final i = priceLevelNames.indexOf(name ?? '');
  return i < 0 ? 1 : i + 1;
}

class ErpStock {
  ErpStock._();

  static const String productSelect = '''
    SELECT p.id, p.name, p.unit, p.unit_price, p.cost_price, p.price1, p.price2, p.price3,
           p.price4, p.price5, p.price6, p.stock_quantity, p.unit_hierarchy, p.length_per_unit,
           p.barcode, p.sync_uuid, p.category_id, p.unit_costs,
           d.item_code, d.item_type
    FROM products p LEFT JOIN product_details d ON d.product_id = p.id
  ''';

  static Future<List<ProductLite>> search(String q, {int limit = 60}) async {
    final db = await erpDb();
    final t = q.trim();
    final like = '%$t%';
    final rows = await db.rawQuery('''
      $productSelect
      WHERE COALESCE(p.is_deleted, 0) = 0
        ${t.isEmpty ? '' : '''AND (p.name LIKE ? OR d.item_code = ? OR p.barcode = ? OR CAST(p.id AS TEXT) = ?
              OR p.id IN (SELECT product_id FROM product_barcodes WHERE barcode = ?))'''}
      ORDER BY p.name LIMIT $limit
    ''', t.isEmpty ? null : [like, t, t, t, t]);
    return rows.map(ProductLite.fromRow).toList();
  }

  static Future<ProductLite?> byId(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery('$productSelect WHERE p.id = ? LIMIT 1', [id]);
    return rows.isEmpty ? null : ProductLite.fromRow(rows.first);
  }

  static Future<List<ProductLite>> all(DatabaseExecutor db, {String? where, List<Object?>? args}) async {
    final rows = await db.rawQuery(
        '$productSelect WHERE COALESCE(p.is_deleted, 0) = 0 ${where == null ? '' : 'AND ($where)'} ORDER BY p.name',
        args);
    return rows.map(ProductLite.fromRow).toList();
  }

  /// يسجّل حركة مخزون (بالوحدة الأساسية) عبر دفتر المخزون، ويربطها بمخزن إن حُدِّد.
  /// يعيد معرّف الحركة. يرمي إن لم توجد المادة.
  static Future<String?> move(
    DatabaseExecutor txn, {
    required int productId,
    required double baseDelta,
    required String kind,
    String? note,
    int? warehouseId,
  }) async {
    final uuid = await StockLedger.productSyncUuidForId(txn, productId);
    if (uuid == null) throw ErpException('المادة #$productId غير موجودة');
    final mv = await StockLedger.addMovement(txn,
        productSyncUuid: uuid, delta: baseDelta, kind: kind, note: note);
    if (mv != null && warehouseId != null) {
      final main = await txn.query('warehouses',
          columns: ['id'], where: 'is_default = 1', orderBy: 'id', limit: 1);
      final mainId = main.isEmpty ? 1 : main.first['id'] as int;
      // المخزن الرئيسي = الكلي − غيره، فلا نختم حركاته
      if (warehouseId != mainId) {
        await txn.update('stock_movements', {'warehouse_id': warehouseId},
            where: 'movement_uuid = ?', whereArgs: [mv]);
      }
    }
    return mv;
  }

  /// كمية المادة المتاحة في مخزن (أو الكلية إن لم يُحدَّد).
  static Future<double> available(DatabaseExecutor db, int productId, {int? warehouseId}) async {
    if (warehouseId == null) {
      final r = await db.query('products', columns: ['stock_quantity'], where: 'id = ?', whereArgs: [productId], limit: 1);
      return r.isEmpty ? 0 : d0(r.first['stock_quantity']);
    }
    final main = await db.query('warehouses', columns: ['id'], where: 'is_default = 1', orderBy: 'id', limit: 1);
    final mainId = main.isEmpty ? 1 : main.first['id'] as int;
    const inW = '''
      COALESCE((SELECT SUM(m.delta) FROM stock_movements m
                WHERE m.product_sync_uuid = p.sync_uuid AND m.warehouse_id = w.id AND m.kind != 'opening'), 0)
      - COALESCE((SELECT SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                                  THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                                  ELSE COALESCE(ii.quantity_individual, 0) END)
                  FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
                  WHERE ii.product_sync_uuid = p.sync_uuid AND i.warehouse_id = w.id
                    AND COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة'), 0)''';
    if (warehouseId == mainId) {
      final r = await db.rawQuery('''
        SELECT COALESCE(p.stock_quantity, 0) - COALESCE((SELECT SUM($inW) FROM warehouses w WHERE w.id != ?), 0) AS q
        FROM products p WHERE p.id = ?''', [mainId, productId]);
      return r.isEmpty ? 0 : d0(r.first['q']);
    }
    final r = await db.rawQuery(
        'SELECT ($inW) AS q FROM products p, warehouses w WHERE p.id = ? AND w.id = ?', [productId, warehouseId]);
    return r.isEmpty ? 0 : d0(r.first['q']);
  }

  /// الكميات المحجوزة في طلبات المبيعات المفتوحة (بالوحدة الأساسية) لكل مادة.
  static Future<Map<int, double>> reserved(DatabaseExecutor db) async {
    final r = await db.rawQuery('''
      SELECT oi.product_id AS pid, SUM(MAX(oi.base_qty - oi.delivered_base_qty, 0)) AS q
      FROM order_items oi JOIN orders o ON o.id = oi.order_id
      WHERE o.order_type = 'sales' AND o.status IN ('open', 'partial')
        AND (o.reserve = 1 OR oi.reserve = 1) AND oi.product_id IS NOT NULL
      GROUP BY oi.product_id
    ''');
    return {for (final x in r) x['pid'] as int: d0(x['q'])};
  }
}
