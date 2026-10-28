// lib/services/personal_pricing_service.dart
// 👤 محرك التسعير الشخصي — «المرجع الواحد الأحدث» (المواصفة المعتمدة 2026-09)
//
// المنطق:
//   المستوى 1: أحدث سطر في تاريخ العميل نفسه يطابق (المنتج + الوحدة + نوع الدفع)
//              خلال آخر سنة.
//   المستوى 2: إن لم يوجد → أقرب فاتورة سوقية (المنتج + الوحدة + نوع الدفع)
//              خلال آخر سنة — الأحدث زمنياً — لأي عميل.
//
// من السطر المرجعي نستخرج من بيانات السطر نفسه (لا من بيانات المنتج الحالية):
//   مبلغ الربح = السعر المطبق − التكلفة المسجلة في السطر
//   نسبة الربح = المبلغ ÷ التكلفة المسجلة في السطر
//
// ثم نطبق على التكلفة الحالية حسب النمط:
//   101 (تكلفة): التكلفة الحالية + مبلغ الربح القديم
//   102 (نسبة):  التكلفة الحالية × (1 + نسبة الربح القديمة)
//   103 (هايبرد): متوسط الطريقتين — كما هو
//
// قواعد صارمة:
//   • نوع الدفع: نقد → مراجع نقد فقط | دين أو مدمجة → مراجع دين + مدمجة
//   • الوحدة جزء من المفتاح: قطعة لا تختلط بباكيت/كرتون/متر إطلاقاً
//   • نافذة سنة واحدة للمستويين — الأقدم يُتجاهل كلياً
//   • الناتج خام من المعادلة: بلا تقريب 250، بلا أرضية تكلفة، بلا تعديل موظف
//   • الأداء: استعلامان فقط ORDER BY التاريخ DESC LIMIT 5 → O(log n) عبر الفهارس
//     idx_invoices_pricing(customer_id, status, payment_type, invoice_date)
//     idx_invoice_items_pricing(product_name, sale_type, invoice_id)

// (منقول من برنامج debt_book كما هو؛ الفرق الوحيد: كلفة الوحدة تُحسب هنا لأن
//  Product في الناصر لا يملك getProductCostForUnit)

import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';

import '../models/product.dart';
import 'database_service.dart';

/// كلفة المادة بوحدة البيع: unit_costs إن وُجدت، وإلا كلفة الأساسية × معامل الوحدة.
double? personalCostForUnit(Product p, String? saleType) {
  final base = p.costPrice;
  String norm(String u) => u == 'piece' ? 'قطعة' : (u == 'meter' ? 'متر' : u);
  final unit = norm((saleType ?? p.unit).trim());
  if (unit.isEmpty || unit == norm(p.unit)) return base;
  try {
    final raw = p.unitCosts;
    if (raw != null && raw.trim().isNotEmpty) {
      final m = jsonDecode(raw) as Map;
      final v = m[unit] ?? m[saleType];
      if (v is num && v > 0) return v.toDouble();
    }
  } catch (_) {}
  if (base == null || base <= 0) return null;
  var f = 1.0;
  for (final l in p.getUnitHierarchyList()) {
    final q = (l['quantity'] as num?)?.toDouble() ?? 1.0;
    f *= q;
    if ('${l['unit_name'] ?? l['name']}' == unit) return base * f;
  }
  return null;
}

class PersonalPricingService {
  static final PersonalPricingService _instance =
      PersonalPricingService._internal();
  factory PersonalPricingService() => _instance;
  PersonalPricingService._internal();

  final DatabaseService _dbService = DatabaseService();

  /// يحسب السعر الشخصي للمنتج للعميل حسب النمط (101/102/103).
  /// يُرجع null إذا لم يوجد مرجع صالح خلال السنة أو لم تتوفر تكلفة حالية —
  /// عندها تستخدم الشاشة السعر الافتراضي للمنتج.
  Future<double?> getPersonalizedPriceForProduct(
    String productName,
    String? saleType,
    int? customerId, {
    int mode = 101, // 101: تكلفة (مبلغ ربح ثابت), 102: نسبة, 103: هايبرد
    bool? usePercentage, // للتوافق العكسي
    String? paymentType, // نوع فاتورة التسعير الحالية: 'نقد' / 'دين' / 'مدمجة'
    Product? preloadedProduct, // ⚡ تحسين الأداء: المنتج المحمّل مسبقاً في الذاكرة
  }) async {
    final db = await _dbService.database;
    try {
      final effectiveMode = (mode == 101 || mode == 102 || mode == 103)
          ? mode
          : (usePercentage == true ? 102 : 101);

      // 💳 نوع الدفع الفعّال للبحث: نقد → مراجع نقد فقط؛ دين أو مدمجة → مراجع دين+مدمجة
      final isCash = (paymentType == 'نقد');
      final paymentTypes = isCash ? ['نقد'] : ['دين', 'مدمجة'];

      // 1. التكلفة الحالية للمنتج بالوحدة المطلوبة — أساس المعادلة
      Product? product =
          preloadedProduct ?? await _dbService.getProductByName(productName);
      double? currentCost;
      if (product != null) {
        currentCost = personalCostForUnit(product, saleType ?? product.unit) ??
            product.costPrice;
      }
      // بلا تكلفة حالية لا يمكن تطبيق المعادلة إطلاقاً
      if (currentCost == null || currentCost <= 0) return null;

      // 2. مطابقة الوحدة بدقة صارمة (مع المرادفات القطعة/piece والمتر/meter فقط)
      final matchingUnits = <String>[];
      if (saleType != null && saleType.isNotEmpty) {
        matchingUnits.add(saleType);
        if (saleType == 'قطعة') matchingUnits.add('piece');
        if (saleType == 'piece') matchingUnits.add('قطعة');
        if (saleType == 'متر') matchingUnits.add('meter');
        if (saleType == 'meter') matchingUnits.add('متر');
      }
      final unitClause = matchingUnits.isNotEmpty
          ? 'AND ii.sale_type IN (${matchingUnits.map((_) => '?').join(',')})'
          : '';
      final payClause =
          'AND i.payment_type IN (${paymentTypes.map((_) => '?').join(',')})';

      // 📅 نافذة سنة واحدة للمستويين: ما هو أقدم من سنة يُتجاهل تماماً
      final oneYearAgo =
          DateTime.now().subtract(const Duration(days: 365)).toIso8601String();

      // 3. المستوى الأول: أحدث سطر في تاريخ العميل نفسه يطابق
      //    (المنتج + الوحدة + نوع الدفع) خلال آخر سنة.
      //    LIMIT 5 احتياط: نأخذ أول سطر سليم البيانات من بينها.
      List<Map<String, dynamic>> refs = [];
      if (customerId != null && customerId > 0) {
        refs = await db.rawQuery(
          '''SELECT ii.applied_price, ii.actual_cost_price, ii.cost_price, i.invoice_date
             FROM invoice_items ii
             JOIN invoices i ON i.id = ii.invoice_id
             WHERE i.customer_id = ? AND ii.product_name = ? $unitClause $payClause
               AND i.status = 'محفوظة' AND i.invoice_date >= ?
             ORDER BY i.invoice_date DESC, ii.id DESC
             LIMIT 5''',
          [customerId, productName, ...matchingUnits, ...paymentTypes, oneYearAgo],
        );
      }

      // 4. المستوى الثاني: لا تاريخ مطابق للعميل (أو عميل مجهول) →
      //    أقرب فاتورة سوقية (المنتج + الوحدة + نوع الدفع) خلال آخر سنة — الأحدث زمنياً
      if (refs.isEmpty) {
        refs = await db.rawQuery(
          '''SELECT ii.applied_price, ii.actual_cost_price, ii.cost_price, i.invoice_date
             FROM invoice_items ii
             JOIN invoices i ON i.id = ii.invoice_id
             WHERE ii.product_name = ? $unitClause $payClause
               AND i.status = 'محفوظة' AND i.invoice_date >= ?
             ORDER BY i.invoice_date DESC, ii.id DESC
             LIMIT 5''',
          [productName, ...matchingUnits, ...paymentTypes, oneYearAgo],
        );
      }

      // 5. أول سطر مرجعي سليم البيانات (سعر وتكلفة تاريخية صالحان معاً).
      //    🔑 التكلفة تُؤخذ من سطر الفاتورة نفسه — لا يُعاد حساب الربح القديم
      //    بتكلفة المنتج الحالية أبداً.
      double? prevPrice;
      double? prevCost;
      for (final r in refs) {
        final p = (r['applied_price'] as num?)?.toDouble();
        final c = (r['actual_cost_price'] as num?)?.toDouble() ??
            (r['cost_price'] as num?)?.toDouble();
        if (p != null && p > 0 && c != null && c > 0) {
          prevPrice = p;
          prevCost = c;
          break;
        }
      }
      // لا مرجع صالح خلال السنة → لا تسعير شخصي (الشاشة تستخدم الافتراضي)
      if (prevPrice == null || prevCost == null) return null;

      // 6. 🧮 المعادلات — الناتج خام تماماً:
      //    بلا تقريب 250، بلا أرضية تكلفة، بلا تعديل تعلم الموظف
      final profitAmount = prevPrice - prevCost;
      final profitMargin = profitAmount / prevCost;

      if (effectiveMode == 101) {
        // 💵 نمط التكلفة: التكلفة الحالية + مبلغ الربح من الفاتورة المرجعية
        //    (مثال: تكلفة اليوم 10,000 + ربح 500 = 10,500)
        return currentCost + profitAmount;
      } else if (effectiveMode == 102) {
        // 📈 نمط النسبة: التكلفة الحالية × (1 + نسبة الربح من الفاتورة المرجعية)
        //    (مثال: 10,000 × (1 + 500/9,000) = 10,555.55)
        return currentCost * (1.0 + profitMargin);
      } else {
        // ⚡ 103 هايبرد — كما هو: متوسط الطريقتين من نفس المرجع
        final byAmount = currentCost + profitAmount;
        final byMargin = currentCost * (1.0 + profitMargin);
        return (byAmount + byMargin) / 2.0;
      }
    } catch (e) {
      debugPrint('Error calculating personalized price for $productName '
          '($saleType - $paymentType - mode=$mode): $e');
      return null;
    }
  }
}
