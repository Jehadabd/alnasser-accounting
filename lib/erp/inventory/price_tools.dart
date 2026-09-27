// lib/erp/inventory/price_tools.dart
//
// 💲 أدوات الأسعار (مثل «تعديل قائمة المواد» في الإداري):
//   • أسعار كنسبة ربح على الكلفة لكل مستوى، مع تقريب.
//   • تعديل جماعي: من «سعر منطلق» (الكلفة أو أي مستوى) إلى «سعر هدف»، بنسبة أو
//     مبلغ، زيادة أو نقصان، مع تقريب، واختيار «الأسعار الصفرية فقط».
//   • توحيد سعر أو مسحه لمجموعة مواد.
// كل تغيير يمر عبر DatabaseService.updateProduct (المسار الأصلي الذي يزامن المادة
// ولا يلمس كميتها)، ويُسجَّل في price_change_log مع رقم دفعة للمراجعة.

import '../../accounting/ledger.dart';
import '../../models/product.dart';
import '../../services/database_service.dart';
import '../erp_common.dart';

const List<String> priceFieldNames = ['مفرد', 'مفرد 2', 'منزل', 'جملة', 'جملة 2', 'أخرى'];

/// نسخة من المادة بقسم جديد — يقبل null (بلا قسم)، بخلاف copyWith.
Product productWithCategory(Product p, int? categoryId) =>
    Product.fromMap({...p.toMap(), 'category_id': categoryId, 'last_modified_at': DateTime.now().toIso8601String()});

double roundToStep(double v, double step) {
  if (step <= 0) return roundMoney(v);
  return roundMoney((v / step).roundToDouble() * step);
}

class PriceChange {
  PriceChange(this.productId, this.name, this.level, this.oldValue, this.newValue);
  final int productId;
  final String name;

  /// 1..6 (مستوى السعر)
  final int level;
  final double oldValue;
  final double newValue;
}

class PriceTools {
  static double priceOf(Product p, int level) {
    switch (level) {
      case 1:
        return p.price1;
      case 2:
        return p.price2 ?? 0;
      case 3:
        return p.price3 ?? 0;
      case 4:
        return p.price4 ?? 0;
      case 5:
        return p.price5 ?? 0;
      default:
        return p.price6 ?? 0;
    }
  }

  static Product withPrice(Product p, int level, double v) {
    switch (level) {
      case 1:
        return p.copyWith(price1: v, unitPrice: v);
      case 2:
        return p.copyWith(price2: v);
      case 3:
        return p.copyWith(price3: v);
      case 4:
        return p.copyWith(price4: v);
      case 5:
        return p.copyWith(price5: v);
      default:
        return p.copyWith(price6: v);
    }
  }

  /// الأسعار المحسوبة من الكلفة ونسب الربح (null = لا يتغير ذلك المستوى).
  static List<double?> fromMarkups(double cost, List<double?> markups, double rounding) => [
        for (final m in markups) (m == null || cost <= 0) ? null : roundToStep(cost * (1 + m / 100), rounding),
      ];

  /// يطبّق أسعاراً جديدة لمادة (مستوى ⇒ سعر). يعيد عدد المستويات المتغيّرة.
  Future<int> applyPrices(int productId, Map<int, double> prices, {int? batchNo}) async {
    final dbs = DatabaseService();
    final p = await dbs.getProductById(productId);
    if (p == null) throw ErpException('المادة غير موجودة');
    var updated = p;
    final changes = <PriceChange>[];
    prices.forEach((level, v) {
      if (v < 0) throw ErpException('سعر سالب');
      if (level == 1 && v <= 0) return; // سعر المفرد الأساسي لا يُصفَّر
      final old = priceOf(updated, level);
      if ((old - v).abs() < kMoneyEpsilon) return;
      changes.add(PriceChange(productId, p.name, level, old, v));
      updated = withPrice(updated, level, v);
    });
    if (changes.isEmpty) return 0;
    await dbs.updateProduct(updated.copyWith(lastModifiedAt: DateTime.now()));
    await _log(changes, batchNo ?? await _nextBatch());
    return changes.length;
  }

  Future<int> _nextBatch() async {
    final db = await erpDb();
    return nextDocNumber(db, 'price_change_log', 'batch_no');
  }

  Future<void> _log(List<PriceChange> changes, int batch) async {
    final db = await erpDb();
    final now = DateTime.now().toIso8601String();
    final user = currentUserName();
    for (final c in changes) {
      await db.insert('price_change_log', {
        'batch_no': batch,
        'product_id': c.productId,
        'field': 'price${c.level}',
        'old_value': c.oldValue,
        'new_value': c.newValue,
        'created_by': user,
        'created_at': now,
      });
    }
  }

  /// معاينة التعديل الجماعي.
  /// [source]: 0 = الكلفة، 1..6 = مستوى سعر. [targets]: المستويات الهدف.
  /// [method]: percent | amount | set | clear. [increase]: زيادة أم نقصان.
  Future<List<PriceChange>> preview({
    required List<int> productIds,
    required int source,
    required List<int> targets,
    required String method,
    bool increase = true,
    double value = 0,
    double rounding = 0,
    bool onlyZero = false,
  }) async {
    final dbs = DatabaseService();
    final out = <PriceChange>[];
    for (final id in productIds) {
      final p = await dbs.getProductById(id);
      if (p == null) continue;
      final base = source == 0 ? (p.costPrice ?? 0) : priceOf(p, source);
      for (final t in targets) {
        final old = priceOf(p, t);
        if (onlyZero && old.abs() > kMoneyEpsilon) continue;
        double nv;
        switch (method) {
          case 'percent':
            if (base <= 0) continue;
            nv = base * (1 + (increase ? value : -value) / 100);
            break;
          case 'amount':
            if (base <= 0 && !increase) continue;
            nv = base + (increase ? value : -value);
            break;
          case 'set':
            nv = value;
            break;
          case 'clear':
            nv = 0;
            break;
          default:
            continue;
        }
        if (method != 'clear') nv = roundToStep(nv, rounding);
        if (nv < 0) nv = 0;
        if (t == 1 && nv <= 0) continue; // سعر المفرد الأساسي لا يُصفَّر أبداً (يكسر البيع)
        if ((nv - old).abs() < kMoneyEpsilon) continue;
        out.add(PriceChange(id, p.name, t, old, nv));
      }
    }
    return out;
  }

  /// تنفيذ معاينة. يعيد رقم الدفعة.
  Future<int> apply(List<PriceChange> changes) async {
    if (changes.isEmpty) return 0;
    final batch = await _nextBatch();
    final byProduct = <int, Map<int, double>>{};
    for (final c in changes) {
      byProduct.putIfAbsent(c.productId, () => {})[c.level] = c.newValue;
    }
    for (final e in byProduct.entries) {
      await applyPrices(e.key, e.value, batchNo: batch);
    }
    return batch;
  }

  /// التراجع عن دفعة: يعيد كل سعر إلى قيمته قبل الدفعة (إن لم يتغير بعدها).
  Future<int> undoBatch(int batch) async {
    final db = await erpDb();
    final rows = await db.query('price_change_log', where: 'batch_no = ?', whereArgs: [batch]);
    final byProduct = <int, Map<int, double>>{};
    for (final r in rows) {
      final level = int.tryParse(((r['field'] as String?) ?? 'price1').replaceAll('price', '')) ?? 1;
      byProduct.putIfAbsent(r['product_id'] as int, () => {})[level] = d0(r['old_value']);
    }
    final newBatch = await _nextBatch();
    var n = 0;
    for (final e in byProduct.entries) {
      n += await applyPrices(e.key, e.value, batchNo: newBatch);
    }
    return n;
  }

  Future<List<Map<String, Object?>>> batches() async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT batch_no, MIN(created_at) AS at, COUNT(*) AS n, MIN(created_by) AS by
      FROM price_change_log GROUP BY batch_no ORDER BY batch_no DESC LIMIT 100
    ''');
  }

  /// تحديث أسعار مادة من نسب ربحها المحفوظة في بطاقتها (إن كانت طريقة التسعير «نسبة»).
  Future<int> refreshFromMarkups(int productId) async {
    final db = await erpDb();
    final d = await db.query('product_details', where: 'product_id = ?', whereArgs: [productId], limit: 1);
    if (d.isEmpty || d.first['pricing_mode'] != 'markup') return 0;
    final p = await DatabaseService().getProductById(productId);
    if (p == null) return 0;
    final m = [for (var i = 1; i <= 6; i++) (d.first['markup$i'] as num?)?.toDouble()];
    final computed = fromMarkups(p.costPrice ?? 0, m, d0(d.first['price_rounding']));
    final prices = <int, double>{};
    for (var i = 0; i < 6; i++) {
      if (computed[i] != null && computed[i]! > 0) prices[i + 1] = computed[i]!;
    }
    return applyPrices(productId, prices);
  }

  /// تحديث كل المواد المسعّرة بالنسبة (بعد تغيّر الكلفة من المشتريات).
  Future<int> refreshAllMarkups() async {
    final db = await erpDb();
    final r = await db.query('product_details', columns: ['product_id'], where: "pricing_mode = 'markup'");
    var n = 0;
    for (final x in r) {
      n += await refreshFromMarkups(x['product_id'] as int);
    }
    return n;
  }
}
