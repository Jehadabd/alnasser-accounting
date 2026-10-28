// lib/services/smart_pricing_service.dart

import '../models/smart_pricing_models.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import 'smart_search/smart_search_db.dart';

class SmartPricingService {
  static const int recentSalesLimit = 20;
  static const int pointsLastPrice = 50;
  static const int pointsInLast5 = 20; // 20 per appearance, max 100
  static const int pointsFrequencyBonus = 15;
  static const int pointsCustomerHistory = 75;
  static const int pointsDominantPrice = 30;
  static const int pointsTrendMatch = 80;

  final DatabaseService _dbService = DatabaseService();

  /// 🎯 الحصول على السعر الذكي للمنتج
  Future<SmartPricingResult?> getSmartPriceEnhanced({
    required int productId,
    int? customerId,
    String? saleType,
    List<Map<String, dynamic>>? invoiceItemsContext,
  }) async {
    // 🎛️ «مطفأ» في الإعدادات: لا اقتراح إطلاقاً — السعر من مستوى السعر المختار
    // في الفاتورة (مفرد، جملة…) كما أُدخل في بطاقة المادة. (كان هذا الخيار يُحفظ
    // ويتجاهله هذا المحرك، فيبقى الاقتراح يعمل عند اختيار المادة وتغيير وحدتها.)
    try {
      if ((await SettingsManager.getAppSettings()).pricingMode == 0) return null;
    } catch (_) {}
    final db = await _dbService.database;
    String? expectedLevel;
    double? productMedianPrice;

    // جلب متوسط سعر المنتج الحالي
    try {
      final statsMap = await db.query('product_price_stats', where: 'product_id = ?', whereArgs: [productId]);
      if (statsMap.isNotEmpty) {
        productMedianPrice = (statsMap.first['median_price'] as num?)?.toDouble();
      }
    } catch (e) {
      // Ignore if view doesn't exist yet
    }

    // تصنيف العميل التلقائي
    try {
      final appSettings = await SettingsManager.getAppSettings();
      final double wholesaleLimit = appSettings.wholesaleCustomerLimit;
      if (customerId != null && customerId > 0 && wholesaleLimit > 0) {
        final totalPurchasesResult = await db.rawQuery('''
          SELECT SUM(total_amount) as total
          FROM invoices
          WHERE customer_id = ? AND status = 'محفوظة'
        ''', [customerId]);
        
        final totalPurchases = (totalPurchasesResult.first['total'] as num?)?.toDouble() ?? 0.0;
        if (totalPurchases >= wholesaleLimit) {
          expectedLevel = 'wholesale';
        }
      }
    } catch (e) {
      // ignore
    }

    // 📋 سياق الفاتورة (من البحث الذكي): بقية مواد الفاتورة بسعر جملة؟ مفرد؟
    // إن لم يحدد العميل المستوى، نسأل علاقات المستويات المتعلَّمة من الفواتير
    // السابقة، وإلا نأخذ أغلبية مستويات مواد الفاتورة الحالية.
    if (expectedLevel == null && invoiceItemsContext != null && invoiceItemsContext.isNotEmpty) {
      try {
        final contextProducts = <Map<String, dynamic>>[];
        for (final item in invoiceItemsContext) {
          final pid = item['product_id'];
          final price = (item['applied_price'] as num?)?.toDouble() ?? 0;
          if (pid is! int || pid == productId || price <= 0) continue;
          contextProducts.add({'id': pid, 'level': await _levelOf(db, pid, price)});
        }
        if (contextProducts.isNotEmpty) {
          expectedLevel = await SmartSearchDatabase.instance.getExpectedPriceLevel(
            queryProductId: productId,
            contextProducts: contextProducts,
          );
          if (expectedLevel == null) {
            final w = contextProducts.where((p) => p['level'] == 'wholesale').length;
            final r = contextProducts.where((p) => p['level'] == 'retail').length;
            if (w > r) {
              expectedLevel = 'wholesale';
            } else if (r > w) {
              expectedLevel = 'retail';
            }
          }
        }
      } catch (_) {}
    }

    // جلب آخر 20 عملية
    final recentSales = await db.rawQuery('''
      SELECT price, invoice_date FROM recent_sales_buffer
      WHERE product_id = ?
      ORDER BY invoice_date DESC
      LIMIT ?
    ''', [productId, recentSalesLimit]);
    
    if (recentSales.isEmpty) return null;
    
    final recentPrices = recentSales.map((s) => (s['price'] as num).toDouble()).toList();

    // 🎛️ استراتيجية التسعير المختارة في الإعدادات (الأسعار والأرباح ← محرك التسعير).
    // كانت تُحفظ ولا يقرأها أي كود — كل الخيارات كانت تعطي «ذكي». الآن تُطبَّق؛
    // الافتراضي 99 (ذكي) يبقى كما كان تماماً.
    int mode = 99;
    try {
      mode = (await SettingsManager.getAppSettings()).pricingMode;
    } catch (_) {}
    if (mode == 1 || mode == 3 || mode == 21) {
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
    
    final candidatePrices = <double, PriceCandidate>{};
    for (var price in recentPrices) {
      candidatePrices.putIfAbsent(price, () => PriceCandidate(price: price));
    }

    // حساب نقاط كل سعر
    for (var candidate in candidatePrices.values) {
      _calculatePriceScore(
        candidate: candidate,
        recentPrices: recentPrices,
        customerId: customerId,
        expectedLevel: expectedLevel,
        productMedianPrice: productMedianPrice,
      );
    }

    // إضافة نقاط تاريخ العميل
    if (customerId != null && customerId > 0) {
      final customerStats = await _getCustomerProductStats(customerId, productId);
      if (customerStats != null && customerStats['count'] >= 2) {
        final customerPrice = customerStats['price'] as double;
        if (candidatePrices.containsKey(customerPrice)) {
          candidatePrices[customerPrice]!.addPoints(
            pointsCustomerHistory,
            'سعر الزبون المعتاد (${customerStats['count']} عملية)',
          );
        } else {
          candidatePrices[customerPrice] = PriceCandidate(price: customerPrice);
          candidatePrices[customerPrice]!.addPoints(
            pointsCustomerHistory,
            'سعر الزبون المعتاد (${customerStats['count']} عملية)',
          );
        }
      }
    }

    // اختيار السعر الأعلى نقاطاً
    final sortedCandidates = candidatePrices.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final winner = sortedCandidates.first;

    // صمام الأمان (Cost Check)
    try {
      final product = await _dbService.getProductById(productId);
      if (product != null) {
        final cost = _dbService.calculateUnitCost(product, saleType ?? product.unit);
        if (cost > 0 && winner.price < cost) {
          return null; // رفض المقترح لمنع الخسارة
        }
      }
    } catch (e) {
      // ignore
    }

    // نسبة الثقة
    const double maxPossibleScore = pointsLastPrice + 100.0 + pointsFrequencyBonus + pointsDominantPrice + pointsTrendMatch + pointsCustomerHistory;
    double confidence = (winner.score / maxPossibleScore) * 100;
    if (confidence > 100) confidence = 100;

    final scoresMap = <double, int>{ for (var e in candidatePrices.values) e.price : e.score.toInt() };

    return SmartPricingResult(
      price: winner.price,
      confidence: confidence,
      source: 'المحرك الذكي',
      reason: winner.reasons.join(' | '),
      candidateScores: scoresMap,
    );
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

  void _calculatePriceScore({
    required PriceCandidate candidate,
    required List<double> recentPrices,
    int? customerId,
    String? expectedLevel,
    double? productMedianPrice,
  }) {
    final price = candidate.price;
    final totalSales = recentPrices.length;
    
    // آخر سعر
    if (recentPrices.first == price) {
      candidate.addPoints(pointsLastPrice, 'آخر سعر');
    }
    
    // التواجد في آخر 5
    final last5 = recentPrices.take(5).toList();
    final countInLast5 = last5.where((p) => p == price).length;
    if (countInLast5 > 0) {
      candidate.addPoints(pointsInLast5 * countInLast5, 'في آخر 5 عمليات ($countInLast5 مرات)');
    }
    
    // التكرار الكلي
    final totalOccurrences = recentPrices.where((p) => p == price).length;
    final frequencyPercent = totalOccurrences / totalSales;
    candidate.addPoints((pointsFrequencyBonus * frequencyPercent).round(), 'تكرار ${(frequencyPercent * 100).toStringAsFixed(0)}%');
    
    // المهيمن
    if (frequencyPercent >= 0.60) {
      candidate.addPoints(pointsDominantPrice, 'سعر مهيمن');
    }
    
    // اتجاه السعر
    if (recentPrices.length >= 5) {
      final last5Avg = last5.reduce((a, b) => a + b) / 5;
      if ((price - last5Avg).abs() < last5Avg * 0.05) {
        candidate.addPoints(pointsTrendMatch, 'يتوافق مع اتجاه السعر الحالي');
      }
    }
  }

  Future<Map<String, dynamic>?> _getCustomerProductStats(int customerId, int productId) async {
    final db = await _dbService.database;
    final result = await db.rawQuery('''
      SELECT ii.applied_price as price, COUNT(*) as count
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      WHERE i.customer_id = ? AND ii.product_id = ?
      GROUP BY ii.applied_price
      ORDER BY count DESC
      LIMIT 1
    ''', [customerId, productId]);
    
    if (result.isNotEmpty) {
      return {
        'price': (result.first['price'] as num).toDouble(),
        'count': result.first['count'] as int,
      };
    }
    return null;
  }
}
