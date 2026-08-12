// lib/services/smart_pricing_service.dart

import '../models/smart_pricing_models.dart';
import 'database_service.dart';
import 'settings_manager.dart';

class SmartPricingService {
  static const int RECENT_SALES_LIMIT = 20;
  static const int POINTS_LAST_PRICE = 50;
  static const int POINTS_IN_LAST_5 = 20; // 20 per appearance, max 100
  static const int POINTS_FREQUENCY_BONUS = 15;
  static const int POINTS_CUSTOMER_HISTORY = 75;
  static const int POINTS_DOMINANT_PRICE = 30;
  static const int POINTS_TREND_MATCH = 80;

  final DatabaseService _dbService = DatabaseService();

  /// 🎯 الحصول على السعر الذكي للمنتج
  Future<SmartPricingResult?> getSmartPriceEnhanced({
    required int productId,
    int? customerId,
    String? saleType,
    List<Map<String, dynamic>>? invoiceItemsContext,
  }) async {
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

    // جلب آخر 20 عملية
    final recentSales = await db.rawQuery('''
      SELECT price, invoice_date FROM recent_sales_buffer
      WHERE product_id = ?
      ORDER BY invoice_date DESC
      LIMIT ?
    ''', [productId, RECENT_SALES_LIMIT]);
    
    if (recentSales.isEmpty) return null;
    
    final recentPrices = recentSales.map((s) => (s['price'] as num).toDouble()).toList();
    
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
            POINTS_CUSTOMER_HISTORY,
            'سعر الزبون المعتاد (${customerStats['count']} عملية)',
          );
        } else {
          candidatePrices[customerPrice] = PriceCandidate(price: customerPrice);
          candidatePrices[customerPrice]!.addPoints(
            POINTS_CUSTOMER_HISTORY,
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
    final double maxPossibleScore = POINTS_LAST_PRICE + 100.0 + POINTS_FREQUENCY_BONUS + POINTS_DOMINANT_PRICE + POINTS_TREND_MATCH + POINTS_CUSTOMER_HISTORY;
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
      candidate.addPoints(POINTS_LAST_PRICE, 'آخر سعر');
    }
    
    // التواجد في آخر 5
    final last5 = recentPrices.take(5).toList();
    final countInLast5 = last5.where((p) => p == price).length;
    if (countInLast5 > 0) {
      candidate.addPoints(POINTS_IN_LAST_5 * countInLast5, 'في آخر 5 عمليات ($countInLast5 مرات)');
    }
    
    // التكرار الكلي
    final totalOccurrences = recentPrices.where((p) => p == price).length;
    final frequencyPercent = totalOccurrences / totalSales;
    candidate.addPoints((POINTS_FREQUENCY_BONUS * frequencyPercent).round(), 'تكرار ${(frequencyPercent * 100).toStringAsFixed(0)}%');
    
    // المهيمن
    if (frequencyPercent >= 0.60) {
      candidate.addPoints(POINTS_DOMINANT_PRICE, 'سعر مهيمن');
    }
    
    // اتجاه السعر
    if (recentPrices.length >= 5) {
      final last5Avg = last5.reduce((a, b) => a + b) / 5;
      if ((price - last5Avg).abs() < last5Avg * 0.05) {
        candidate.addPoints(POINTS_TREND_MATCH, 'يتوافق مع اتجاه السعر الحالي');
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
