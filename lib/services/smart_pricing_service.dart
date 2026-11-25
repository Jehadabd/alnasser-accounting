// lib/services/smart_pricing_service.dart

import '../models/smart_pricing_models.dart';
import 'database_service.dart';
import 'smart_price_engine.dart';
import 'settings_manager.dart';
import 'smart_search/smart_search_db.dart';

class SmartPricingService {
  static const int recentSalesLimit = 20;

  final DatabaseService _dbService = DatabaseService();

  /// 🎯 الحصول على السعر الذكي للمنتج
  ///
  /// • 0 «مطفأ»: لا اقتراح — السعر من مستوى السعر المختار في الفاتورة.
  /// • 1 / 3 / 21: استراتيجيات الإعدادات (آخر سعر، متوسط آخر 3، الأكثر تكراراً) كما هي.
  /// • غير ذلك (99 الافتراضي): المحرك الذكي في smart_price_engine.dart — وحدة البيع
  ///   جزء من المفتاح، آخر سعر للزبون، سعر السوق × معامل الزبون، هامش نطاق الكلفة.
  ///   [invoiceItemsContext] لم يعد يُستعمل (تحليل الفواتير: مستوى بقية المواد لا يحدد السعر).
  Future<SmartPricingResult?> getSmartPriceEnhanced({
    required int productId,
    int? customerId,
    String? saleType,
    List<Map<String, dynamic>>? invoiceItemsContext,
  }) async {
    int mode = 99;
    try {
      mode = (await SettingsManager.getAppSettings()).pricingMode;
    } catch (_) {}
    if (mode == 0) return null;
    final db = await _dbService.database;

    if (mode == 1 || mode == 3 || mode == 21) {
      final recentSales = await db.rawQuery('''
        SELECT price, invoice_date FROM recent_sales_buffer
        WHERE product_id = ?
        ORDER BY invoice_date DESC
        LIMIT ?
      ''', [productId, recentSalesLimit]);
      if (recentSales.isEmpty) return null;
      final recentPrices = recentSales.map((s) => (s['price'] as num).toDouble()).toList();
      final picked = await _priceByMode(db, mode, productId, recentPrices);
      if (picked == null || picked.$1 <= 0) return null;
      if (await _isBelowCost(productId, saleType, picked.$1)) return null; // نفس صمام الخسارة
      return SmartPricingResult(
        price: picked.$1,
        confidence: 100,
        source: 'استراتيجية الإعدادات',
        reason: picked.$2,
        candidateScores: {picked.$1: 100},
      );
    }

    try {
      final product = await _dbService.getProductById(productId);
      if (product == null) return null;
      final unit = (saleType == null || saleType.trim().isEmpty) ? product.translatedUnit : saleType;
      return await SmartPriceEngine.instance.suggest(
        product: product,
        saleType: unit,
        customerId: customerId,
      );
    } catch (_) {
      return null; // بلا اقتراح ⇒ الشاشة تستعمل سعر المادة
    }
  }

  /// السعر حسب الاستراتيجية: 1 = آخر سعر، 3 = متوسط آخر 3، 21 = الأكثر تكراراً خلال 30 يوماً.
  /// مستوى سعر بيع: أقل من الوسيط بـ 5% = جملة، أعلى بـ 5% = مفرد، وإلا متوسط
  Future<String> _levelOf(dynamic db, int productId, double price) async {
    try {
      final s = await db.query('product_price_stats', where: 'product_id = ?', whereArgs: [productId]);
      if (s.isNotEmpty) {
        final median = (s.first['median_price'] as num?)?.toDouble() ?? 0;
        if (median > 0) {
          if (price <= median * 0.95) return 'wholesale';
          if (price >= median * 1.05) return 'retail';
        }
      }
    } catch (_) {}
    return 'average';
  }

  /// 🧠 بعد حفظ فاتورة: يتعلّم أي مستويات أسعار تأتي معاً (جملة مع جملة…)
  /// فيقترح للمادة التالية المستوى نفسه. يعمل في الخلفية ولا يوقف الحفظ.
  Future<void> recordInvoicePriceLevels(int invoiceId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT p.id AS pid, ii.applied_price AS price
      FROM invoice_items ii JOIN products p ON p.name = ii.product_name
      WHERE ii.invoice_id = ? AND ii.applied_price > 0
    ''', [invoiceId]);
    final levels = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final r in rows) {
      final pid = (r['pid'] as num?)?.toInt();
      final price = (r['price'] as num?)?.toDouble() ?? 0;
      if (pid == null || !seen.add(pid)) continue;
      levels.add({'id': pid, 'level': await _levelOf(db, pid, price)});
    }
    if (levels.length > 40) return; // فاتورة ضخمة: لا نولّد مئات العلاقات
    for (var i = 0; i < levels.length; i++) {
      for (var j = i + 1; j < levels.length; j++) {
        await SmartSearchDatabase.instance.upsertPriceLevelAssociation(
          productIdA: levels[i]['id'] as int,
          productIdB: levels[j]['id'] as int,
          priceLevelA: levels[i]['level'] as String,
          priceLevelB: levels[j]['level'] as String,
        );
      }
    }
  }

  Future<(double, String)?> _priceByMode(dynamic db, int mode, int productId, List<double> recentPrices) async {
    if (recentPrices.isEmpty) return null;
    switch (mode) {
      case 1:
        return (recentPrices.first, 'آخر سعر بيع');
      case 3:
        final last = recentPrices.take(3).toList();
        final avg = last.reduce((a, b) => a + b) / last.length;
        return (double.parse(avg.toStringAsFixed(2)), 'متوسط آخر ${last.length} عمليات بيع');
      case 21:
        final rows = await db.rawQuery('''
          SELECT price, invoice_date FROM recent_sales_buffer
          WHERE product_id = ?
          ORDER BY invoice_date DESC
          LIMIT 500
        ''', [productId]) as List<Map<String, Object?>>;
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        final counts = <double, int>{};
        for (final r in rows) {
          final d = DateTime.tryParse('${r['invoice_date']}');
          if (d == null || d.isBefore(cutoff)) continue;
          final p = (r['price'] as num?)?.toDouble();
          if (p == null || p <= 0) continue;
          counts[p] = (counts[p] ?? 0) + 1;
        }
        if (counts.isEmpty) return (recentPrices.first, 'آخر سعر (لا مبيعات خلال 30 يوماً)');
        final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
        return (best.key, 'الأكثر تكراراً خلال 30 يوماً (${best.value} مرة)');
    }
    return null;
  }

  /// صمام الخسارة: سعر مقترح أقل من الكلفة يُرفض.
  Future<bool> _isBelowCost(int productId, String? saleType, double price) async {
    try {
      final product = await _dbService.getProductById(productId);
      if (product != null) {
        final cost = _dbService.calculateUnitCost(product, saleType ?? product.unit);
        return cost > 0 && price < cost;
      }
    } catch (_) {}
    return false;
  }
}
