// lib/erp/inventory/usd_cost_service.dart
//
// 💱 كلفة المادة بالدولار — تتبع سعر الصرف دون أن تمسّ أرباح ما بيع سابقاً.
//
// النموذج:
//   • product_details.cost_currency = 'USD' و cost_usd = كلفة الوحدة الأساسية بالدولار.
//   • products.cost_price (بالدينار) = cost_usd × آخر سعر للدولار، ومعه unit_costs.
//
// لماذا «التثبيت» قبل أي تغيير للكلفة؟
//   الفاتورة تحفظ كلفة البند يوم البيع (invoice_items.actual_cost_price)، فلا يتأثر
//   ربحها بتغيّر الكلفة لاحقاً. لكن بنوداً بلا كلفة محفوظة (فواتير قديمة، أو مادة بلا
//   كلفة يومها) وتسويات الفواتير بعد الحفظ تأخذ «الكلفة الحالية» في التقارير؛ فلو
//   ارتفع الدولار لصارت مبيعات الأمس خاسرة. لذلك نكتب لها كلفتها الحالية أولاً
//   (وهي ما تعرضه التقارير الآن بالضبط)، ثم نغيّر كلفة المادة.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../accounting/ledger.dart' show Ledger, roundMoney;
import '../../models/product.dart';
import '../../services/database_service.dart';
import '../../services/reports/sales_facts.dart' show ItemCost;
import '../currency_service.dart';

/// مادة تغيّرت كلفتها بإعادة التسعير.
class RepricedProduct {
  RepricedProduct({
    required this.productId,
    required this.name,
    required this.usd,
    required this.oldCost,
    required this.newCost,
    required this.prices,
  });
  final int productId;
  final String name;
  final double usd;
  final double oldCost;
  final double newCost;

  /// أسعار البيع الستة الحالية (قبل أي رفع).
  final List<double> prices;

  double get ratio => oldCost > 0 ? newCost / oldCost : 1;
  double get changePct => (ratio - 1) * 100;
}

class RepriceResult {
  RepriceResult({required this.rate, required this.products, this.frozenItems = 0, this.frozenAdjustments = 0});
  final double rate;
  final List<RepricedProduct> products;
  final int frozenItems;
  final int frozenAdjustments;
  bool get isEmpty => products.isEmpty;
}

class UsdCostService {
  UsdCostService._();

  /// آخر سعر للدولار (دينار لكل 1$) — من سجل الأسعار، وإلا إعداد المحاسبة.
  static Future<double> currentRate(DatabaseExecutor db) async {
    try {
      final r = await CurrencyService.rateAt(db, 'USD', DateTime.now());
      if (r > 1) return r;
    } catch (_) {}
    try {
      return await Ledger.usdRate(db);
    } catch (_) {
      return 0;
    }
  }

  /// عملة كلفة المادة وكلفتها بالدولار (إن كانت دولارية).
  static Future<({String currency, double? usd})> read(DatabaseExecutor db, int productId) async {
    try {
      final r = await db.query('product_details',
          columns: ['cost_currency', 'cost_usd'], where: 'product_id = ?', whereArgs: [productId], limit: 1);
      if (r.isEmpty) return (currency: 'IQD', usd: null);
      final cur = (r.first['cost_currency'] as String?) ?? 'IQD';
      final usd = (r.first['cost_usd'] as num?)?.toDouble();
      return (currency: cur == 'USD' && (usd ?? 0) > 0 ? 'USD' : 'IQD', usd: usd);
    } catch (_) {
      return (currency: 'IQD', usd: null);
    }
  }

  /// يكتب عملة الكلفة في بطاقة المادة (دون لمس بقية الحقول).
  static Future<void> writeCurrency(DatabaseExecutor db, int productId, {required String currency, double? usd}) async {
    await db.rawInsert('INSERT OR IGNORE INTO product_details (product_id) VALUES (?)', [productId]);
    await db.update(
      'product_details',
      {
        'cost_currency': currency == 'USD' ? 'USD' : 'IQD',
        'cost_usd': currency == 'USD' ? usd : null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  /// يثبّت كلفة ما بيع سابقاً من هذه المواد بالكلفة الحالية، للبنود والتسويات التي
  /// لا تحمل كلفة محفوظة. يُستدعى قبل أي تغيير لكلفة المادة.
  static Future<({int items, int adjustments})> freezePastCosts(DatabaseExecutor db, Set<int> productIds) async {
    if (productIds.isEmpty) return (items: 0, adjustments: 0);
    final ids = productIds.toList();
    final ph = List.filled(ids.length, '?').join(',');
    var items = 0;
    var adjustments = 0;
    try {
      // نفس مطابقة المادة في التقارير: بالاسم أولاً ثم بالمعرّف
      final rows = await db.rawQuery('''
        SELECT ii.id AS item_id, ii.quantity_individual AS qi, ii.quantity_large_unit AS ql,
               ii.units_in_large_unit AS uilu, ii.applied_price AS selling_price, ii.sale_type AS sale_type,
               p.unit AS product_unit, p.cost_price AS product_cost_price, p.length_per_unit AS length_per_unit,
               p.unit_costs AS unit_costs, p.unit_hierarchy AS unit_hierarchy
        FROM invoice_items ii
        JOIN invoices i ON i.id = ii.invoice_id
        LEFT JOIN (SELECT name, MIN(id) AS id FROM products GROUP BY name) pn ON pn.name = ii.product_name
        JOIN products p ON p.id = COALESCE(pn.id, ii.product_id)
        WHERE COALESCE(ii.actual_cost_price, 0) <= 0
          AND COALESCE(p.cost_price, 0) > 0
          AND COALESCE(NULLIF(TRIM(i.status), ''), 'محفوظة') = 'محفوظة'
          AND p.id IN ($ph)''', ids);
      for (final r in rows) {
        final ql = (r['ql'] as num?)?.toDouble() ?? 0;
        final qi = (r['qi'] as num?)?.toDouble() ?? 0;
        final sold = ql > 0 ? ql : qi;
        if (sold <= 0) continue;
        final total = ItemCost.compute({...r, 'actual_cost_per_unit': null});
        final perUnit = total / sold;
        if (perUnit <= 0) continue;
        items += await db.rawUpdate('UPDATE invoice_items SET actual_cost_price = ? WHERE id = ?', [perUnit, r['item_id']]);
      }
    } catch (_) {}
    try {
      adjustments = await db.rawUpdate('''
        UPDATE invoice_adjustments
        SET base_unit_cost = (SELECT p.cost_price FROM products p WHERE p.id = invoice_adjustments.product_id)
        WHERE COALESCE(base_unit_cost, 0) <= 0
          AND product_id IN ($ph)
          AND (SELECT COALESCE(p.cost_price, 0) FROM products p WHERE p.id = invoice_adjustments.product_id) > 0''', ids);
    } catch (_) {
      // عمود base_unit_cost غير موجود بعد
    }
    return (items: items, adjustments: adjustments);
  }

  /// كلفة الوحدات بعد تغيّر كلفة الوحدة الأساسية: تُضرب القيم المحفوظة بالنسبة نفسها
  /// (الكرتون = 12 قطعة يبقى 12 ضعفاً)، وتُبنى من التسلسل إن لم تكن محفوظة.
  static String? scaledUnitCosts(Product p, double newCost) {
    final old = p.costPrice ?? 0;
    final raw = p.unitCosts;
    if (raw != null && raw.trim().isNotEmpty && old > 0) {
      try {
        final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final ratio = newCost / old;
        return jsonEncode({for (final e in m.entries) e.key: e.value is num ? roundMoney((e.value as num) * ratio) : e.value});
      } catch (_) {}
    }
    final baseKey = p.unit == 'meter' ? 'متر' : (p.unit == 'piece' ? 'قطعة' : p.unit);
    final out = <String, double>{baseKey: newCost};
    final h = p.unitHierarchy;
    if (h != null && h.trim().isNotEmpty) {
      try {
        var c = newCost;
        for (final level in jsonDecode(h.replaceAll("'", '"')) as List) {
          final name = ((level as Map)['unit_name'] ?? level['name'] ?? '').toString();
          final q = (level['quantity'] is num) ? (level['quantity'] as num).toDouble() : double.tryParse('${level['quantity']}') ?? 1;
          c = c * q;
          if (name.isNotEmpty) out[name] = roundMoney(c);
        }
      } catch (_) {}
    }
    return jsonEncode(out);
  }

  /// يكتب كلفة جديدة (بالدينار) للمادة بعد تثبيت كلفة مبيعاتها السابقة.
  static Future<Product?> applyCost(DatabaseExecutor db, int productId, double newCost) async {
    final dbs = DatabaseService();
    final p = await dbs.getProductById(productId);
    if (p == null) return null;
    if (((p.costPrice ?? 0) - newCost).abs() < 0.005) return p;
    await freezePastCosts(db, {productId});
    final updated = Product.fromMap({
      ...p.toMap(),
      'cost_price': newCost,
      'unit_costs': scaledUnitCosts(p, newCost),
      'last_modified_at': DateTime.now().toIso8601String(),
    });
    await dbs.updateProduct(updated);
    return updated;
  }

  /// يعيد حساب كلفة كل مادة دولارية بآخر سعر للدولار. يُستدعى بعد تغيير السعر.
  static Future<RepriceResult> repriceAll() async {
    final dbs = DatabaseService();
    final db = await dbs.database;
    final rate = await currentRate(db);
    if (rate <= 1) return RepriceResult(rate: rate, products: const []);
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery('''
        SELECT d.product_id, d.cost_usd
        FROM product_details d JOIN products p ON p.id = d.product_id
        WHERE d.cost_currency = 'USD' AND COALESCE(d.cost_usd, 0) > 0 AND COALESCE(p.is_deleted, 0) = 0''');
    } catch (_) {
      return RepriceResult(rate: rate, products: const []);
    }
    final targets = <int, double>{};
    for (final r in rows) {
      targets[(r['product_id'] as num).toInt()] = (r['cost_usd'] as num).toDouble();
    }
    // المواد التي تتغير كلفتها فعلاً
    final changing = <int, Product>{};
    for (final e in targets.entries) {
      final p = await dbs.getProductById(e.key);
      if (p == null) continue;
      final nc = roundMoney(e.value * rate);
      if (((p.costPrice ?? 0) - nc).abs() >= 0.005) changing[e.key] = p;
    }
    if (changing.isEmpty) return RepriceResult(rate: rate, products: const []);
    final frozen = await freezePastCosts(db, changing.keys.toSet());
    final out = <RepricedProduct>[];
    for (final e in changing.entries) {
      final p = e.value;
      final nc = roundMoney(targets[e.key]! * rate);
      await dbs.updateProduct(Product.fromMap({
        ...p.toMap(),
        'cost_price': nc,
        'unit_costs': scaledUnitCosts(p, nc),
        'last_modified_at': DateTime.now().toIso8601String(),
      }));
      out.add(RepricedProduct(
        productId: e.key,
        name: p.name,
        usd: targets[e.key]!,
        oldCost: p.costPrice ?? 0,
        newCost: nc,
        prices: [p.price1, p.price2 ?? 0, p.price3 ?? 0, p.price4 ?? 0, p.price5 ?? 0, p.price6 ?? 0],
      ));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return RepriceResult(rate: rate, products: out, frozenItems: frozen.items, frozenAdjustments: frozen.adjustments);
  }
}
