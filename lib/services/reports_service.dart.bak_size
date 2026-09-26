// services/reports_service.dart
// خدمة التقارير المتقدمة - منفصلة عن database_service لتخفيف الحمل
import 'dart:convert';
import 'package:sqflite/sqflite.dart'; // ✅ Added for Sqflite.firstIntValue
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import '../utils/money_calculator.dart';
import '../models/invoice.dart';
import '../models/transaction.dart';
import '../models/person_data.dart';
import '../models/analytics_data.dart';

class ReportsService {
  ReportsService({DatabaseService? db}) : _db = db ?? DatabaseService();
  final DatabaseService _db;
  
  /// فلتر: عرض التقارير بناءً على مصدر البيانات
  /// 'all' = الكل, 'this_device' = هذا الجهاز فقط, 'sync' = المزامنة فقط
  String reportSourceFilter = 'all';
  
  /// فلتر: عرض التقارير بناءً على البيانات التي تم إنشاؤها في هذا الجهاز فقط (للتوافق مع الكود القديم)
  bool get filterOnlyThisDevice => reportSourceFilter == 'this_device';
  set filterOnlyThisDevice(bool value) => reportSourceFilter = value ? 'this_device' : 'all';
  
  String get _deviceFilter {
    if (reportSourceFilter == 'this_device') {
      return " AND is_created_by_me = 1 ";
    } else if (reportSourceFilter == 'sync') {
      return " AND is_created_by_me = 0 ";
    }
    return "";
  }
  
  String _deviceFilterFor(String alias) {
    if (reportSourceFilter == 'this_device') {
      return " AND ${alias}is_created_by_me = 1 ";
    } else if (reportSourceFilter == 'sync') {
      return " AND ${alias}is_created_by_me = 0 ";
    }
    return "";
  }
  
  /// 🔍 تشخيص مشكلة التكلفة - طباعة تفاصيل حساب التكلفة لكل بند
  /// يُستخدم لتحديد سبب التكلفة العالية
  double _calculateItemCostWithDebug(Map<String, dynamic> row, {bool enableDebug = false, String? productName, double? adHocProfitPercentage}) {
    final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
    final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
    final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
    final String saleType = (row['sale_type'] as String?) ?? '';
    final String productUnit = (row['product_unit'] as String?) ?? '';
    final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
    final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
    final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
    final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
    final double itemTotal = (row['item_total'] as num?)?.toDouble() ?? 0.0;
    final String? unitCostsJson = row['unit_costs'] as String?;
    final String? unitHierarchyJson = row['unit_hierarchy'] as String?;
    
    // تحليل unit_costs JSON
    Map<String, dynamic> unitCosts = const {};
    if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
      try { 
        unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; 
      } catch (e) { 
        // تجاهل خطأ التحليل
      }
    }

    final bool soldAsLargeUnit = ql > 0;
    final double soldUnitsCount = soldAsLargeUnit ? ql : qi;

    // حساب التكلفة لكل وحدة مباعة
    double costPerSoldUnit;
    String costSource = 'unknown';
    
    if (actualCostPerUnit != null && actualCostPerUnit > 0) {
      costPerSoldUnit = actualCostPerUnit;
      costSource = 'actualCostPerUnit';
    } else if (soldAsLargeUnit) {
      final dynamic stored = unitCosts[saleType];
      if (stored is num && stored > 0) {
        costPerSoldUnit = stored.toDouble();
        costSource = 'unitCosts[$saleType]';
      } else {
        final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
        if (isMeterRoll) {
          costPerSoldUnit = productCost * (lengthPerUnit ?? 1.0);
          costSource = 'meter_roll: $productCost * $lengthPerUnit';
        } else if (uilu > 0) {
          costPerSoldUnit = productCost * uilu;
          costSource = 'uilu: $productCost * $uilu';
        } else {
          costPerSoldUnit = _calculateCostFromHierarchy(
            productCost: productCost,
            saleType: saleType,
            unitHierarchyJson: unitHierarchyJson,
            productUnit: productUnit,
          );
          costSource = 'hierarchy: productCost=$productCost, saleType=$saleType';
        }
      }
    } else {
      costPerSoldUnit = productCost;
      costSource = 'productCost (base)';
    }

    // إذا كانت التكلفة صفر، افترض أن الربح 10% فقط (أو النسبة المحددة)
    if (costPerSoldUnit <= 0 && sellingPrice > 0) {
      costPerSoldUnit = MoneyCalculator.getEffectiveCost(
        0, 
        sellingPrice, 
        profitMargin: adHocProfitPercentage != null ? adHocProfitPercentage / 100.0 : MoneyCalculator.defaultProfitMargin
      );
      costSource = adHocProfitPercentage != null ? 'estimated_${adHocProfitPercentage.toStringAsFixed(0)}%' : 'estimated_10%';
    }

    final totalCost = costPerSoldUnit * soldUnitsCount;
    final profit = itemTotal - totalCost;
    
    // طباعة تشخيصية إذا كان الربح سالب أو التكلفة أعلى من المبيعات
    if (enableDebug || profit < 0 || totalCost > itemTotal * 2) {
      print('═══════════════════════════════════════════════════════════');
      print('🔍 تشخيص بند: ${productName ?? row['product_name'] ?? 'غير معروف'}');
      print('   نوع البيع: $saleType | وحدة المنتج: $productUnit');
      print('   الكمية: qi=$qi, ql=$ql, uilu=$uilu');
      print('   سعر البيع: $sellingPrice | إجمالي البند: $itemTotal');
      print('   تكلفة المنتج الأساسية: $productCost');
      print('   actualCostPerUnit: $actualCostPerUnit');
      print('   unitCosts: $unitCosts');
      print('   unitHierarchy: $unitHierarchyJson');
      print('   ─────────────────────────────────────────────────────────');
      print('   📊 النتيجة:');
      print('   مصدر التكلفة: $costSource');
      print('   تكلفة الوحدة المحسوبة: $costPerSoldUnit');
      print('   عدد الوحدات المباعة: $soldUnitsCount');
      print('   إجمالي التكلفة: $totalCost');
      print('   الربح: $profit ${profit < 0 ? "⚠️ سالب!" : "✅"}');
      print('═══════════════════════════════════════════════════════════');
    }

    return totalCost;
  }

  /// حساب تكلفة بند فاتورة بنفس منطق getMonthlySalesSummary
  /// يتعامل مع جميع أنواع الوحدات (قطعة، كرتون، متر، لفة)
  /// 🔧 إصلاح: عند عدم توفر actualCostPrice و uilu = 0، نحسب من unit_hierarchy
  double _calculateItemCost(Map<String, dynamic> row, {double? adHocProfitPercentage}) {
    final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
    final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
    final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
    final String saleType = (row['sale_type'] as String?) ?? '';
    final String productUnit = (row['product_unit'] as String?) ?? '';
    final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
    final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
    final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
    final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
    final String? unitCostsJson = row['unit_costs'] as String?;
    final String? unitHierarchyJson = row['unit_hierarchy'] as String?;
    
    // تحليل unit_costs JSON
    Map<String, dynamic> unitCosts = const {};
    if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
      try { 
        unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; 
      } catch (e) { 
        // تجاهل خطأ التحليل
      }
    }

    final bool soldAsLargeUnit = ql > 0;
    final double soldUnitsCount = soldAsLargeUnit ? ql : qi;

    // حساب التكلفة لكل وحدة مباعة - نفس منطق getDailyReport في ai_chat_service
    double costPerSoldUnit;
    if (actualCostPerUnit != null && actualCostPerUnit > 0) {
      // التكلفة الفعلية المخزنة في بند الفاتورة (الأولوية الأولى)
      costPerSoldUnit = actualCostPerUnit;
    } else if (soldAsLargeUnit) {
      // بيع بوحدة كبيرة (كرتون، لفة، إلخ)
      // أولاً: إن كانت تكلفة الوحدة الكبيرة مخزنة في unit_costs استخدمها
      final dynamic stored = unitCosts[saleType];
      if (stored is num && stored > 0) {
        costPerSoldUnit = stored.toDouble();
      } else {
        // حساب تكلفة الوحدة الكبيرة
        final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
        if (isMeterRoll) {
          costPerSoldUnit = productCost * (lengthPerUnit ?? 1.0);  // لفة = تكلفة المتر × طول اللفة
        } else if (uilu > 0) {
          costPerSoldUnit = productCost * uilu; // كرتون/باكية = تكلفة القطعة × عدد القطع
        } else {
          // 🔧 إصلاح: إذا كان uilu = 0، نحاول حساب المضاعف من unit_hierarchy
          costPerSoldUnit = _calculateCostFromHierarchy(
            productCost: productCost,
            saleType: saleType,
            unitHierarchyJson: unitHierarchyJson,
            productUnit: productUnit,
          );
        }
      }
    } else {
      // بيع بوحدة صغيرة (قطعة أو متر)
      costPerSoldUnit = productCost;
    }

    // إذا كانت التكلفة صفر، افترض أن الربح 10% فقط (أو النسبة المحددة)
    if (costPerSoldUnit <= 0 && sellingPrice > 0) {
      costPerSoldUnit = MoneyCalculator.getEffectiveCost(
        0, 
        sellingPrice,
        profitMargin: adHocProfitPercentage != null ? adHocProfitPercentage / 100.0 : MoneyCalculator.defaultProfitMargin
      );
    }

    return costPerSoldUnit * soldUnitsCount;
  }
  
  /// 🔧 حساب التكلفة من unit_hierarchy عندما لا تتوفر بيانات أخرى
  /// نفس منطق _calculateActualCostPrice في create_invoice_screen.dart
  double _calculateCostFromHierarchy({
    required double productCost,
    required String saleType,
    required String? unitHierarchyJson,
    required String productUnit,
  }) {
    // إذا لم يكن هناك تسلسل هرمي، نرجع التكلفة الأساسية
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty) {
      return productCost;
    }
    
    try {
      final List<dynamic> hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final double qty = (level['quantity'] as num?)?.toDouble() ?? 1.0;
        multiplier *= qty;
        
        // إذا وصلنا لوحدة البيع المطلوبة، نرجع التكلفة المحسوبة
        if (unitName == saleType) {
          return productCost * multiplier;
        }
      }
      
      // إذا لم نجد الوحدة في التسلسل، نرجع التكلفة الأساسية
      return productCost;
    } catch (e) {
      // في حالة خطأ التحليل، نرجع التكلفة الأساسية
      return productCost;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // أفضل المنتجات في فترة معينة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// أفضل المنتجات مبيعاً في فترة معينة
  Future<List<Map<String, dynamic>>> getTopProductsInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        ii.product_name,
        SUM(ii.item_total) as total_sales,
        SUM(COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)) as total_quantity,
        COUNT(DISTINCT ii.invoice_id) as invoice_count
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
        AND i.status = 'محفوظة' ${_deviceFilterFor('i.')}
      GROUP BY ii.product_name
      ORDER BY total_sales DESC
      LIMIT ?
    ''', [startStr, endStr, limit]);
    
    return results;
  }

  /// أفضل المنتجات ربحاً في فترة معينة
  /// يستخدم نفس منطق حساب الربح من database_service.getMonthlySalesSummary
  Future<List<Map<String, dynamic>>> getTopProductsByProfitInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    // جلب بنود الفواتير مع بيانات المنتج الكاملة (JOIN وليس LEFT JOIN لضمان وجود بيانات المنتج)
    final items = await db.rawQuery('''
      SELECT 
        ii.product_name,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
        AND i.status = 'محفوظة' ${_deviceFilterFor('i.')}
    ''', [startStr, endStr]);
    
    // حساب الربح لكل منتج بنفس منطق getMonthlySalesSummary
    Map<String, Map<String, dynamic>> productProfits = {};
    
    // جلب إعدادات التطبيق لنسبة الربح
    final settings = await SettingsManager.getAppSettings();
    final adHocProfit = settings.defaultAdHocProfitPercentage;
    
    for (final item in items) {
      final productName = item['product_name'] as String;
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;
      final ql = (item['ql'] as num?)?.toDouble() ?? 0;
      final qi = (item['qi'] as num?)?.toDouble() ?? 0;
      
      // حساب التكلفة باستخدام الدالة المشتركة
      final totalCost = _calculateItemCost(item, adHocProfitPercentage: adHocProfit);
      
      // حساب الربح
      final profit = MoneyCalculator.subtract(itemTotal, totalCost);
      final soldUnits = ql > 0 ? ql : qi;
      
      if (!productProfits.containsKey(productName)) {
        productProfits[productName] = {
          'product_name': productName,
          'total_sales': 0.0,
          'total_profit': 0.0,
          'total_quantity': 0.0,
        };
      }
      productProfits[productName]!['total_profit'] =
          (productProfits[productName]!['total_profit'] as num).toDouble() + profit;
        productProfits[productName]!['total_sales'] =
          (productProfits[productName]!['total_sales'] as num).toDouble() + itemTotal;
        productProfits[productName]!['total_quantity'] =
          (productProfits[productName]!['total_quantity'] as num).toDouble() + soldUnits;
    }
    
    // ترتيب حسب الربح
    final sortedProducts = productProfits.values.toList()
      ..sort((a, b) => ((b['total_profit'] as num).toDouble()).compareTo((a['total_profit'] as num).toDouble()));
    
    return sortedProducts.take(limit).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // أفضل العملاء في فترة معينة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// أفضل العملاء شراءً في فترة معينة
  Future<List<Map<String, dynamic>>> getTopCustomersInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        i.customer_name,
        c.phone as customer_phone,
        SUM(i.total_amount) as total_purchases,
        COUNT(i.id) as invoice_count
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
        AND i.status = 'محفوظة' ${_deviceFilterFor('i.')}
      GROUP BY i.customer_name
      ORDER BY total_purchases DESC
      LIMIT ?
    ''', [startStr, endStr, limit]);
    
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // مقارنة الفترات
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// الحصول على بيانات فترة معينة للمقارنة
  /// يستخدم نفس منطق getMonthlySalesSummary بالضبط
  Future<Map<String, dynamic>> getPeriodSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    // جلب إعدادات التطبيق لنسب الربح
    final settings = await SettingsManager.getAppSettings();
    final adHocProfit = settings.defaultAdHocProfitPercentage;
    final manualDebtProfitPercent = settings.manualDebtProfitPercentage / 100.0;
    
    // بيانات الفواتير الأساسية - فقط الفواتير المحفوظة (نفس منطق getMonthlySalesSummary)
    final invoiceData = await db.rawQuery('''
      SELECT 
        COUNT(*) as invoice_count,
        COALESCE(SUM(total_amount), 0) as total_sales,
        COALESCE(SUM(return_amount), 0) as total_returns,
        COALESCE(SUM(CASE WHEN payment_type = 'نقد' THEN total_amount ELSE 0 END), 0) as cash_sales,
        COALESCE(SUM(CASE WHEN payment_type = 'دين' THEN total_amount ELSE 0 END), 0) as credit_sales
      FROM invoices
      WHERE (substr(invoice_date, 1, 10) >= ? AND substr(invoice_date, 1, 10) <= ? OR (DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?))
        AND (status = 'محفوظة' OR status IS NULL OR status = '') 
        AND (is_deleted IS NULL OR is_deleted = 0) $_deviceFilter
    ''', [startStr, endStr, startStr, endStr]);
    
    // جلب الفواتير المحفوظة لحساب التكلفة والربح لكل فاتورة
    final invoices = await db.rawQuery('''
      SELECT id, total_amount, return_amount
      FROM invoices
      WHERE (substr(invoice_date, 1, 10) >= ? AND substr(invoice_date, 1, 10) <= ? OR (DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?))
        AND (status = 'محفوظة' OR status IS NULL OR status = '') 
        AND (is_deleted IS NULL OR is_deleted = 0) $_deviceFilter
    ''', [startStr, endStr, startStr, endStr]);
    
    // حساب التكلفة والربح لكل فاتورة بنفس منطق getMonthlySalesSummary
    double totalCostCalculated = 0.0;
    double totalProfitCalculated = 0.0;
    
    for (final invoice in invoices) {
      final invoiceId = invoice['id'] as int;
      final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
      final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0.0;
      
      // 🔧 إصلاح: استخدام LEFT JOIN لتشمل المنتجات غير الموجودة في قاعدة البيانات
      // المنتجات غير المسجلة ستستخدم 10% كنسبة ربح افتراضية
      final items = await db.rawQuery('''
        SELECT 
          ii.quantity_individual AS qi,
          ii.quantity_large_unit AS ql,
          ii.units_in_large_unit AS uilu,
          ii.actual_cost_price AS actual_cost_per_unit,
          ii.applied_price AS selling_price,
          ii.sale_type AS sale_type,
          ii.item_total,
          p.unit AS product_unit,
          p.cost_price AS product_cost_price,
          p.length_per_unit AS length_per_unit,
          p.unit_costs AS unit_costs,
          p.unit_hierarchy AS unit_hierarchy
        FROM invoice_items ii
        LEFT JOIN products p ON p.name = ii.product_name
        WHERE ii.invoice_id = ?
      ''', [invoiceId]);
      
      // حساب تكلفة الفاتورة
      double invoiceCost = 0.0;
      for (final item in items) {
        invoiceCost += _calculateItemCost(item, adHocProfitPercentage: adHocProfit);
      }
      
      totalCostCalculated += invoiceCost;
      
      // صافي المبيعات بعد الراجع مطروحاً منه التكلفة (نفس منطق getMonthlySalesSummary)
      final netSaleAmount = MoneyCalculator.subtract(totalAmount, returnAmount);
      final profit = MoneyCalculator.subtract(netSaleAmount, invoiceCost);
      totalProfitCalculated += profit;
    }
    
    // المعاملات اليدوية (جدول transactions)
    // 🔧 إصلاح: فقط المعاملات اليدوية من هذا الجهاز وغير المرتبطة بفاتورة
    final manualDebt = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(amount_changed), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type IN ('manual_debt', 'opening_balance')
        AND invoice_id IS NULL
        AND is_created_by_me = 1
    ''', [startStr, endStr]);
    
    final manualPayment = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(ABS(amount_changed)), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type = 'manual_payment'
        AND invoice_id IS NULL
        AND is_created_by_me = 1
    ''', [startStr, endStr]);
    
    final inv = invoiceData.first;
    final debt = manualDebt.first;
    final payment = manualPayment.first;
    
    final totalSales = (inv['total_sales'] as num?)?.toDouble() ?? 0.0;
    
    // 🆕 جلب الراجع من التعديلات (Box Match) ودمجه مع الراجع المباشر
    final snapshotReturnsList = await getCashReturnsInPeriod(startDate: startDate, endDate: endDate);
    double snapshotReturnsTotal = 0.0;
    for (final ret in snapshotReturnsList) {
      snapshotReturnsTotal += (ret['return_amount'] as num?)?.toDouble() ?? 0.0;
    }
    
    final totalReturns = ((inv['total_returns'] as num?)?.toDouble() ?? 0.0) + snapshotReturnsTotal;
    
    final totalManualDebt = (debt['total'] as num?)?.toDouble() ?? 0.0;
    // حساب ربح الديون اليدوية
    final manualDebtProfit = totalManualDebt * manualDebtProfitPercent;
    
    return {
      'invoiceCount': inv['invoice_count'] ?? 0,
      'totalSales': totalSales,
      'netProfit': totalProfitCalculated,
      'totalCost': totalCostCalculated,
      'cashSales': (inv['cash_sales'] as num?)?.toDouble() ?? 0.0,
      'creditSales': (inv['credit_sales'] as num?)?.toDouble() ?? 0.0,
      'totalReturns': totalReturns,
      'manualDebtCount': debt['count'] ?? 0,
      'totalManualDebt': totalManualDebt,
      'manualDebtProfit': manualDebtProfit,
      'manualPaymentCount': payment['count'] ?? 0,
      'totalManualPayment': (payment['total'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// مقارنة فترتين
  Future<Map<String, dynamic>> comparePeriods({
    required DateTime currentStart,
    required DateTime currentEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
  }) async {
    final current = await getPeriodSummary(startDate: currentStart, endDate: currentEnd);
    final previous = await getPeriodSummary(startDate: previousStart, endDate: previousEnd);
    
    // حساب نسب التغيير
    double calcChange(double curr, double prev) {
      if (prev == 0) return curr > 0 ? 100.0 : 0.0;
      return ((curr - prev) / prev) * 100;
    }
    
    return {
      'current': current,
      'previous': previous,
      'changes': {
        'salesChange': calcChange(current['totalSales'], previous['totalSales']),
        'profitChange': calcChange(current['netProfit'], previous['netProfit']),
        'invoiceCountChange': calcChange(
          (current['invoiceCount'] as num).toDouble(),
          (previous['invoiceCount'] as num).toDouble()
        ),
        'cashSalesChange': calcChange(current['cashSales'], previous['cashSales']),
        'creditSalesChange': calcChange(current['creditSales'], previous['creditSales']),
      },
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // العملاء الجدد
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// العملاء الجدد في فترة معينة
  Future<List<Map<String, dynamic>>> getNewCustomersInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        c.id,
        c.name,
        c.phone,
        c.created_at,
        COALESCE(SUM(i.total_amount), 0) as total_purchases,
        COUNT(i.id) as invoice_count
      FROM customers c
      LEFT JOIN invoices i ON c.id = i.customer_id AND i.status = 'محفوظة'
      WHERE DATE(c.created_at) >= ? AND DATE(c.created_at) <= ?
      GROUP BY c.id
      ORDER BY c.created_at DESC
    ''', [startStr, endStr]);
    
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الديون المتأخرة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// العملاء الذين لديهم ديون ولم يجروا أي معاملة (دفع أو شراء) منذ عدد من الأشهر
  Future<List<Map<String, dynamic>>> getOverdueDebtsInMonths({
    int monthsInactivity = 12,
    double minimumDebt = 0,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    // حساب تاريخ القطع: أي معاملة بعد هذا التاريخ تعني أن العميل نشط
    final cutoffDate = DateTime(now.year, now.month - monthsInactivity, now.day);
    
    // جلب العملاء الذين عليهم ديون، مع تاريخ آخر معاملة لهم ككل
    final results = await db.rawQuery('''
      SELECT 
        c.id,
        c.name,
        c.phone,
        c.current_total_debt,
        (
          SELECT MAX(transaction_date)
          FROM transactions t
          WHERE t.customer_id = c.id AND t.transaction_type = 'manual_payment' ${_deviceFilterFor('t.')}
        ) as last_payment_date,
        (
          SELECT MAX(transaction_date)
          FROM transactions t
          WHERE t.customer_id = c.id ${_deviceFilterFor('t.')}
        ) as last_transaction_date
      FROM customers c
      WHERE c.current_total_debt > ?
    ''', [minimumDebt]);
    
    // تصفية العملاء: نريد فقط من كانت آخر معاملة له قبل تاريخ القطع
    // هذا يشمل: من لم يسددوا، ومن لم يشتروا، لأكثر من الفترة المحددة
    final filtered = results.where((customer) {
      final lastTransStr = customer['last_transaction_date'] as String?;
      
      if (lastTransStr == null) {
        // العميل ليس لديه أي معاملات إطلاقاً (نظرياً لا ينبغي أن يكون عليه دين إلا إذا كان رصيد افتتاحي قديم جداً أو مرحل)
        // إذا كان عليه دين وليس لديه معاملات، فهو متأخر "منذ الأزل"، إذن نشمله
        return true; 
      }
      
      try {
        final lastTransDate = DateTime.parse(lastTransStr);
        // الشرط: آخر معاملة يجب أن تكون **قبل** تاريخ القطع
        // إذا كانت بعد القطع (أحدث)، إذن هو نشط حديثاً ولا يُعتبر متأخراً لهذه الفترة
        return lastTransDate.isBefore(cutoffDate);
      } catch (e) {
        return false;
      }
    }).toList();
    
    // الترتيب: الأقدم نشاطاً يظهر أولاً (الأكثر تأخراً)
    filtered.sort((a, b) {
      final dateA = a['last_transaction_date'] as String?;
      final dateB = b['last_transaction_date'] as String?;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return -1; // الذي بلا تاريخ (قديم جداً) يظهر أولاً
      if (dateB == null) return 1;
      return dateA.compareTo(dateB); // تصاعدي: التاريخ القديم أولاً
    });
    
    return filtered;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تحليل الاتجاه (Trend Analysis)
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// المبيعات اليومية خلال فترة (للرسم البياني)
  Future<List<Map<String, dynamic>>> getDailySalesInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        DATE(i.invoice_date) as date,
        COUNT(DISTINCT i.id) as invoice_count,
        COALESCE(SUM(ii.item_total), 0) as total_sales,
        COALESCE(SUM(
          COALESCE(
            NULLIF(ii.actual_cost_price, 0),
            NULLIF(p.cost_price, 0),
            ii.applied_price * 0.9
          ) * (COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0) * CASE WHEN COALESCE(ii.units_in_large_unit, 0) > 0 THEN ii.units_in_large_unit ELSE 1 END)
        ), 0) as total_cost,
        COALESCE(SUM(CASE WHEN i.payment_type = 'نقد' THEN ii.item_total ELSE 0 END), 0) as cash_sales,
        COALESCE(SUM(CASE WHEN i.payment_type = 'دين' THEN ii.item_total ELSE 0 END), 0) as credit_sales
      FROM invoices i
      LEFT JOIN invoice_items ii ON ii.invoice_id = i.id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
        AND i.status = 'محفوظة'
        ${_deviceFilterFor('i.')}
      GROUP BY DATE(i.invoice_date)
      ORDER BY date ASC
    ''', [startStr, endStr]);
    
    return results;
  }

  /// تحليل اتجاه المبيعات (صاعد/هابط/مستقر)
  Future<Map<String, dynamic>> analyzeSalesTrend({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dailySales = await getDailySalesInPeriod(startDate: startDate, endDate: endDate);
    
    if (dailySales.length < 2) {
      return {
        'trend': 'insufficient_data',
        'trendArabic': 'بيانات غير كافية',
        'averageDailySales': 0.0,
        'totalDays': dailySales.length,
      };
    }
    
    // حساب المتوسط
    double totalSales = 0;
    for (var day in dailySales) {
      totalSales += (day['total_sales'] as num?)?.toDouble() ?? 0;
    }
    final avgDailySales = totalSales / dailySales.length;
    
    // تقسيم الفترة إلى نصفين ومقارنتهما
    final midPoint = dailySales.length ~/ 2;
    double firstHalfTotal = 0;
    double secondHalfTotal = 0;
    
    for (int i = 0; i < dailySales.length; i++) {
      final sales = (dailySales[i]['total_sales'] as num?)?.toDouble() ?? 0;
      if (i < midPoint) {
        firstHalfTotal += sales;
      } else {
        secondHalfTotal += sales;
      }
    }
    
    final firstHalfAvg = firstHalfTotal / midPoint;
    final secondHalfAvg = secondHalfTotal / (dailySales.length - midPoint);
    
    String trend;
    String trendArabic;
    double changePercent = 0;
    
    if (firstHalfAvg > 0) {
      changePercent = ((secondHalfAvg - firstHalfAvg) / firstHalfAvg) * 100;
    }
    
    if (changePercent > 10) {
      trend = 'increasing';
      trendArabic = 'صاعد ↑';
    } else if (changePercent < -10) {
      trend = 'decreasing';
      trendArabic = 'هابط ↓';
    } else {
      trend = 'stable';
      trendArabic = 'مستقر →';
    }
    
    return {
      'trend': trend,
      'trendArabic': trendArabic,
      'changePercent': changePercent,
      'averageDailySales': avgDailySales,
      'totalDays': dailySales.length,
      'firstHalfAvg': firstHalfAvg,
      'secondHalfAvg': secondHalfAvg,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // نسبة الربح
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// حساب نسبة الربح لفترة معينة
  Future<double> getProfitPercentage({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final summary = await getPeriodSummary(startDate: startDate, endDate: endDate);
    final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0.0;
    final netProfit = (summary['netProfit'] as num?)?.toDouble() ?? 0.0;
    
    if (totalSales <= 0) return 0.0;
    return (netProfit / totalSales) * 100;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تقرير شهري مفصل
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تقرير شهري شامل
  Future<Map<String, dynamic>> getMonthlyDetailedReport({
    required int year,
    required int month,
  }) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0); // آخر يوم في الشهر
    
    // الشهر السابق للمقارنة
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear = month == 1 ? year - 1 : year;
    final prevStartDate = DateTime(prevYear, prevMonth, 1);
    final prevEndDate = DateTime(prevYear, prevMonth + 1, 0);
    
    final summary = await getPeriodSummary(startDate: startDate, endDate: endDate);
    final comparison = await comparePeriods(
      currentStart: startDate,
      currentEnd: endDate,
      previousStart: prevStartDate,
      previousEnd: prevEndDate,
    );
    final topProducts = await getTopProductsInPeriod(startDate: startDate, endDate: endDate, limit: 10);
    final topCustomers = await getTopCustomersInPeriod(startDate: startDate, endDate: endDate, limit: 10);
    final newCustomers = await getNewCustomersInPeriod(startDate: startDate, endDate: endDate);
    final trend = await analyzeSalesTrend(startDate: startDate, endDate: endDate);
    final rawDailySales = await getDailySalesInPeriod(startDate: startDate, endDate: endDate);
    final profitPercent = await getProfitPercentage(startDate: startDate, endDate: endDate);

    // تحويل البيانات اليومية المسترجعة إلى خريطة للبحث باليوم
    final Map<int, Map<String, dynamic>> salesByDay = {};
    for (final dayData in rawDailySales) {
      final dateStr = dayData['date'] as String?;
      if (dateStr != null) {
        final parsedDate = DateTime.tryParse(dateStr);
        if (parsedDate != null) {
          salesByDay[parsedDate.day] = dayData;
        }
      }
    }

    // بناء قائمة كاملة تحتوي على كافة أيام الشهر (من 1 إلى 28/29/30/31)
    final daysInMonth = endDate.day;
    final List<Map<String, dynamic>> fullMonthDailySales = [];

    for (int day = 1; day <= daysInMonth; day++) {
      final dayDate = DateTime(year, month, day);
      final formattedDate = '$day/$month/$year';

      if (salesByDay.containsKey(day)) {
        final item = Map<String, dynamic>.from(salesByDay[day]!);
        item['dateFormatted'] = formattedDate;
        item['dayNumber'] = day;
        final totalSales = (item['total_sales'] as num?)?.toDouble() ?? (item['totalSales'] as num?)?.toDouble() ?? 0.0;
        final totalCost = (item['total_cost'] as num?)?.toDouble() ?? (item['totalCost'] as num?)?.toDouble() ?? 0.0;
        item['totalSales'] = totalSales;
        item['totalCost'] = totalCost;
        item['netProfit'] = totalSales - totalCost;
        item['invoiceCount'] = (item['invoice_count'] as num?)?.toInt() ?? (item['invoiceCount'] as num?)?.toInt() ?? 0;
        fullMonthDailySales.add(item);
      } else {
        fullMonthDailySales.add({
          'date': dayDate.toIso8601String().split('T')[0],
          'dateFormatted': formattedDate,
          'dayNumber': day,
          'total_sales': 0.0,
          'total_cost': 0.0,
          'totalSales': 0.0,
          'totalCost': 0.0,
          'netProfit': 0.0,
          'invoice_count': 0,
          'invoiceCount': 0,
          'cash_sales': 0.0,
          'credit_sales': 0.0,
        });
      }
    }
    
    // 🆕 حساب المرتجعات الإضافية (من التعديلات) مع استثناء فواتير هذا الشهر
    final snapshotReturns = await _getSnapshotReturns(startDate, endDate, exclusionStartDate: startDate);
    
    return {
      'totalReturns': snapshotReturns, // إضافة المرتجعات للنتيجة
      'year': year,
      'month': month,
      'summary': summary,
      'comparison': comparison,
      'topProducts': topProducts,
      'topCustomers': topCustomers,
      'newCustomers': newCustomers,
      'newCustomersCount': newCustomers.length,
      'trend': trend,
      'dailySales': fullMonthDailySales,
      'profitPercent': profitPercent,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تقرير سنوي
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تقرير سنوي شامل
  Future<Map<String, dynamic>> getYearlyReport({required int year}) async {
    final startDate = DateTime(year, 1, 1);
    final endDate = DateTime(year, 12, 31);
    
    // السنة السابقة للمقارنة
    final prevStartDate = DateTime(year - 1, 1, 1);
    final prevEndDate = DateTime(year - 1, 12, 31);
    
    final summary = await getPeriodSummary(startDate: startDate, endDate: endDate);
    final comparison = await comparePeriods(
      currentStart: startDate,
      currentEnd: endDate,
      previousStart: prevStartDate,
      previousEnd: prevEndDate,
    );
    final topProducts = await getTopProductsInPeriod(startDate: startDate, endDate: endDate, limit: 20);
    final topCustomers = await getTopCustomersInPeriod(startDate: startDate, endDate: endDate, limit: 20);
    final newCustomers = await getNewCustomersInPeriod(startDate: startDate, endDate: endDate);
    final profitPercent = await getProfitPercentage(startDate: startDate, endDate: endDate);

    // 🆕 حساب المرتجعات الإضافية (من التعديلات) مع استثناء فواتير هذا العام
    final snapshotReturns = await _getSnapshotReturns(startDate, endDate, exclusionStartDate: startDate);
    
    // المبيعات الشهرية للسنة
    final monthlySales = <Map<String, dynamic>>[];
    for (int m = 1; m <= 12; m++) {
      final mStart = DateTime(year, m, 1);
      final mEnd = DateTime(year, m + 1, 0);
      final mSummary = await getPeriodSummary(startDate: mStart, endDate: mEnd);
      monthlySales.add({
        'month': m,
        'monthName': _getArabicMonthName(m),
        ...mSummary,
      });
    }

    // المبيعات الأسبوعية للسنة (52 أسبوع)
    final weeklySales = <Map<String, dynamic>>[];
    for (int w = 1; w <= 52; w++) {
      final wStart = DateTime(year, 1, 1).add(Duration(days: (w - 1) * 7));
      final wEnd = wStart.add(const Duration(days: 6));
      final wSummary = await getPeriodSummary(startDate: wStart, endDate: wEnd);
      weeklySales.add({
        'week': w,
        'weekName': 'أسبوع $w',
        ...wSummary,
      });
    }

    // المبيعات اليومية للسنة كاملة (365 يوم)
    final db = await _db.database;
    final yearStr = year.toString();
    final rawDailyData = await db.rawQuery('''
      SELECT 
        DATE(i.invoice_date) as day_date,
        COALESCE(SUM(ii.item_total), 0) as total_sales,
        COALESCE(SUM(
          COALESCE(
            NULLIF(ii.actual_cost_price, 0),
            NULLIF(p.cost_price, 0),
            ii.applied_price * 0.9
          ) * (COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0) * CASE WHEN COALESCE(ii.units_in_large_unit, 0) > 0 THEN ii.units_in_large_unit ELSE 1 END)
        ), 0) as total_cost,
        COUNT(DISTINCT i.id) as invoice_count
      FROM invoices i
      LEFT JOIN invoice_items ii ON ii.invoice_id = i.id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
        ${_deviceFilterFor('i.')}
      GROUP BY DATE(i.invoice_date)
    ''', [yearStr]);

    final Map<String, Map<String, dynamic>> dailyMap = {};
    for (var r in rawDailyData) {
      final dStr = r['day_date'] as String?;
      if (dStr != null) {
        final s = (r['total_sales'] as num?)?.toDouble() ?? 0.0;
        final c = (r['total_cost'] as num?)?.toDouble() ?? 0.0;
        final p = s - c;
        dailyMap[dStr] = {
          'totalSales': s,
          'totalCost': c,
          'netProfit': p,
          'invoiceCount': (r['invoice_count'] as num?)?.toInt() ?? 0,
        };
      }
    }

    final dailyFullYear = <Map<String, dynamic>>[];
    final isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    final totalDays = isLeapYear ? 366 : 365;

    DateTime curDate = DateTime(year, 1, 1);
    for (int d = 0; d < totalDays; d++) {
      final dateKey = '${curDate.year}-${curDate.month.toString().padLeft(2, '0')}-${curDate.day.toString().padLeft(2, '0')}';
      final existing = dailyMap[dateKey];

      dailyFullYear.add({
        'dayIndex': d,
        'dateStr': dateKey,
        'dayNum': curDate.day,
        'monthNum': curDate.month,
        'dateFormatted': '${curDate.day}/${curDate.month}/${curDate.year}',
        'monthName': _getArabicMonthName(curDate.month),
        'totalSales': existing?['totalSales'] ?? 0.0,
        'totalCost': existing?['totalCost'] ?? 0.0,
        'netProfit': existing?['netProfit'] ?? 0.0,
        'invoiceCount': existing?['invoiceCount'] ?? 0,
      });

      curDate = curDate.add(const Duration(days: 1));
    }

    final categoryBreakdown = await _getCategoryBreakdownInPeriod(startDate: startDate, endDate: endDate);
    final paymentBreakdown = await _getPaymentBreakdownInPeriod(startDate: startDate, endDate: endDate);

    return {
      'totalReturns': snapshotReturns,
      'year': year,
      'summary': summary,
      'comparison': comparison,
      'topProducts': topProducts,
      'topCustomers': topCustomers,
      'newCustomersCount': newCustomers.length,
      'profitPercent': profitPercent,
      'monthlySales': monthlySales,
      'weeklySales': weeklySales,
      'dailySales': dailyFullYear,
      'categoryBreakdown': categoryBreakdown,
      'paymentBreakdown': paymentBreakdown,
    };
  }

  /// المبيعات اليومية لشهر معين في السنة
  Future<List<Map<String, dynamic>>> getDailySalesForMonth({required int year, required int month}) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final dailySales = <Map<String, dynamic>>[];
    for (int d = 1; d <= daysInMonth; d++) {
      final dStart = DateTime(year, month, d, 0, 0, 0);
      final dEnd = DateTime(year, month, d, 23, 59, 59);
      final dSummary = await getPeriodSummary(startDate: dStart, endDate: dEnd);
      dailySales.add({
        'day': d,
        'dayName': 'يوم $d',
        'dateStr': '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}',
        ...dSummary,
      });
    }
    return dailySales;
  }

  Future<List<Map<String, dynamic>>> _getCategoryBreakdownInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final db = await _db.database;
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      final sql = '''
        SELECT 
          COALESCE(NULLIF(TRIM(cat.name), ''), 'عام / غير تصنيف') as category_name,
          COUNT(DISTINCT ii.invoice_id) as invoice_count,
          COALESCE(SUM(ii.item_total), 0) as total_sales,
          COALESCE(SUM(ii.quantity_large_unit + ii.quantity_individual), 0) as total_quantity
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        LEFT JOIN products p ON p.name = ii.product_name
        LEFT JOIN categories cat ON cat.id = p.category_id
        WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
          AND i.status = 'محفوظة'
          ${_deviceFilterFor('i.')}
        GROUP BY COALESCE(NULLIF(TRIM(cat.name), ''), 'عام / غير تصنيف')
        ORDER BY total_sales DESC
        LIMIT 10
      ''';
      return await db.rawQuery(sql, [startStr, endStr]);
    } catch (e) {
      print('Error getting category breakdown: $e');
      return [];
    }
  }

  Future<Map<String, double>> _getPaymentBreakdownInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final db = await _db.database;
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      final sql = '''
        SELECT 
          payment_type,
          COALESCE(SUM(final_total), 0) as total
        FROM invoices
        WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
          AND status = 'محفوظة'
          $_deviceFilter
        GROUP BY payment_type
      ''';
      final rows = await db.rawQuery(sql, [startStr, endStr]);
      final map = <String, double>{};
      for (var r in rows) {
        final pType = (r['payment_type'] as String?) ?? 'غير محدد';
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        map[pType] = total;
      }
      return map;
    } catch (e) {
      print('Error getting payment breakdown: $e');
      return {};
    }
  }

  String _getArabicMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return months[month - 1];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔍 تشخيص مشكلة التكلفة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تشخيص مشكلة التكلفة العالية - يطبع تفاصيل كل فاتورة وبنودها
  /// استخدم هذه الدالة لفهم سبب التكلفة العالية
  Future<Map<String, dynamic>> diagnoseCostProblem({
    required int year,
    required int month,
    int? limitInvoices,
  }) async {
    final db = await _db.database;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0);
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    print('');
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║  🔍 تشخيص مشكلة التكلفة - ${_getArabicMonthName(month)} $year');
    print('╚═══════════════════════════════════════════════════════════════════╝');
    print('');
    
    // جلب الفواتير المحفوظة
    final invoices = await db.rawQuery('''
      SELECT id, total_amount, return_amount, customer_name, invoice_date
      FROM invoices
      WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
        AND status = 'محفوظة'
      ORDER BY id DESC
      ${limitInvoices != null ? 'LIMIT $limitInvoices' : ''}
    ''', [startStr, endStr]);
    
    double grandTotalSales = 0.0;
    double grandTotalCost = 0.0;
    int problemItems = 0;
    int totalItems = 0;
    final problemProducts = <String, int>{};
    
    for (final invoice in invoices) {
      final invoiceId = invoice['id'] as int;
      final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
      final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0.0;
      final customerName = invoice['customer_name'] as String? ?? 'غير معروف';
      
      grandTotalSales += totalAmount;
      
      // جلب بنود الفاتورة - استخدام LEFT JOIN لتشمل المنتجات غير المسجلة
      final items = await db.rawQuery('''
        SELECT 
          ii.product_name,
          ii.quantity_individual AS qi,
          ii.quantity_large_unit AS ql,
          ii.units_in_large_unit AS uilu,
          ii.actual_cost_price AS actual_cost_per_unit,
          ii.applied_price AS selling_price,
          ii.sale_type AS sale_type,
          ii.item_total,
          p.unit AS product_unit,
          p.cost_price AS product_cost_price,
          p.length_per_unit AS length_per_unit,
          p.unit_costs AS unit_costs,
          p.unit_hierarchy AS unit_hierarchy
        FROM invoice_items ii
        LEFT JOIN products p ON p.name = ii.product_name
        WHERE ii.invoice_id = ?
      ''', [invoiceId]);
      
      double invoiceCost = 0.0;
      bool hasProblems = false;
      
      for (final item in items) {
        totalItems++;
        final productName = item['product_name'] as String? ?? 'غير معروف';
        final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
        
        // حساب التكلفة مع التشخيص
        final itemCost = _calculateItemCostWithDebug(item, enableDebug: false, productName: productName);
        invoiceCost += itemCost;
        
        // تحقق من وجود مشكلة
        if (itemCost > itemTotal * 1.5) { // التكلفة أعلى من 150% من المبيعات
          problemItems++;
          hasProblems = true;
          problemProducts[productName] = (problemProducts[productName] ?? 0) + 1;
          
          // طباعة تفاصيل البند المشكل
          _calculateItemCostWithDebug(item, enableDebug: true, productName: productName);
        }
      }
      
      grandTotalCost += invoiceCost;
      
      // طباعة ملخص الفاتورة إذا كانت بها مشاكل
      if (hasProblems) {
        final profit = (totalAmount - returnAmount) - invoiceCost;
        print('');
        print('📄 فاتورة #$invoiceId - $customerName');
        print('   المبيعات: $totalAmount | التكلفة: $invoiceCost | الربح: $profit');
        print('');
      }
    }
    
    // ملخص التشخيص
    final grandProfit = grandTotalSales - grandTotalCost;
    final profitPercent = grandTotalSales > 0 ? (grandProfit / grandTotalSales) * 100 : 0.0;
    
    print('');
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║  📊 ملخص التشخيص');
    print('╠═══════════════════════════════════════════════════════════════════╣');
    print('║  عدد الفواتير: ${invoices.length}');
    print('║  عدد البنود الإجمالي: $totalItems');
    print('║  عدد البنود المشكلة: $problemItems');
    print('║  ─────────────────────────────────────────────────────────────────');
    print('║  إجمالي المبيعات: $grandTotalSales');
    print('║  إجمالي التكلفة: $grandTotalCost');
    print('║  صافي الربح: $grandProfit');
    print('║  نسبة الربح: ${profitPercent.toStringAsFixed(1)}%');
    print('╠═══════════════════════════════════════════════════════════════════╣');
    
    if (problemProducts.isNotEmpty) {
      print('║  🚨 المنتجات الأكثر مشاكل:');
      final sorted = problemProducts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var i = 0; i < sorted.length && i < 10; i++) {
        print('║     ${i + 1}. ${sorted[i].key}: ${sorted[i].value} مرة');
      }
    }
    
    print('╚═══════════════════════════════════════════════════════════════════╝');
    print('');
    
    return {
      'invoiceCount': invoices.length,
      'totalItems': totalItems,
      'problemItems': problemItems,
      'grandTotalSales': grandTotalSales,
      'grandTotalCost': grandTotalCost,
      'grandProfit': grandProfit,
      'profitPercent': profitPercent,
      'problemProducts': problemProducts,
    };
  }

  /// تشخيص منتج محدد - يطبع كل الفواتير التي تحتوي على هذا المنتج
  Future<void> diagnoseProduct({
    required String productName,
    int? year,
    int? month,
  }) async {
    final db = await _db.database;
    
    print('');
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║  🔍 تشخيص منتج: $productName');
    print('╚═══════════════════════════════════════════════════════════════════╝');
    
    // جلب بيانات المنتج
    final products = await db.query('products', where: 'name = ?', whereArgs: [productName]);
    if (products.isEmpty) {
      print('❌ المنتج غير موجود في قاعدة البيانات!');
      return;
    }
    
    final product = products.first;
    print('');
    print('📦 بيانات المنتج:');
    print('   الوحدة: ${product['unit']}');
    print('   تكلفة الوحدة: ${product['cost_price']}');
    print('   unit_costs: ${product['unit_costs']}');
    print('   unit_hierarchy: ${product['unit_hierarchy']}');
    print('');
    
    // جلب بنود الفواتير لهذا المنتج
    String whereClause = 'ii.product_name = ?';
    List<dynamic> whereArgs = [productName];
    
    if (year != null && month != null) {
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0);
      whereClause += ' AND DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?';
      whereArgs.addAll([startDate.toIso8601String().split('T')[0], endDate.toIso8601String().split('T')[0]]);
    }
    
    final items = await db.rawQuery('''
      SELECT 
        i.id as invoice_id,
        i.invoice_date,
        i.customer_name,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE $whereClause AND i.status = 'محفوظة'
      ORDER BY i.invoice_date DESC
      LIMIT 20
    ''', whereArgs);
    
    print('📋 آخر ${items.length} فاتورة تحتوي على هذا المنتج:');
    print('');
    
    for (final item in items) {
      _calculateItemCostWithDebug(item, enableDebug: true, productName: productName);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تفصيل المنتجات المشتراة من عميل (المبيعات التراكمية)
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تفصيل المنتجات المشتراة من عميل معين في سنة أو شهر محدد
  /// يُرجع قائمة بالمنتجات مع المبلغ والربح والكمية بالوحدات الهرمية
  Future<List<CustomerProductBreakdown>> getCustomerProductsBreakdown({
    required int customerId,
    required int year,
    int? month,
  }) async {
    final db = await _db.database;
    
    // بناء شرط التاريخ
    String dateCondition;
    List<dynamic> dateArgs;
    if (month != null) {
      dateCondition = "strftime('%Y', i.invoice_date) = ? AND strftime('%m', i.invoice_date) = ?";
      dateArgs = [year.toString(), month.toString().padLeft(2, '0')];
    } else {
      dateCondition = "strftime('%Y', i.invoice_date) = ?";
      dateArgs = [year.toString()];
    }
    
    // جلب بنود الفواتير مع بيانات المنتج الكاملة
    final items = await db.rawQuery('''
      SELECT 
        ii.product_name,
        ii.product_id,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.id AS p_id,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE (i.customer_id = ? OR (i.customer_id IS NULL AND i.customer_name = (
        SELECT name FROM customers WHERE id = ?
      ))) AND i.status = 'محفوظة' AND $dateCondition
    ''', [customerId, customerId, ...dateArgs]);
    
    // تجميع البيانات حسب المنتج
    final Map<String, _ProductAggregation> productMap = {};
    
    for (final item in items) {
      final productName = item['product_name'] as String;
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;
      final qi = (item['qi'] as num?)?.toDouble() ?? 0;
      final ql = (item['ql'] as num?)?.toDouble() ?? 0;
      final uilu = (item['uilu'] as num?)?.toDouble() ?? 0;
      final saleType = (item['sale_type'] as String?) ?? '';
      final productUnit = (item['product_unit'] as String?) ?? 'piece';
      final lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble();
      final unitHierarchy = item['unit_hierarchy'] as String?;
      final unitCosts = item['unit_costs'] as String?;
      final productId = (item['p_id'] as int?) ?? (item['product_id'] as int?);
      
      // حساب التكلفة
      final totalCost = _calculateItemCost(item);
      final profit = itemTotal - totalCost;
      
      // حساب الكمية بالوحدة الأساسية
      // 🔧 إصلاح: التحقق من نوع البيع أولاً قبل افتراض أن ql > 0 يعني وحدة كبيرة
      double baseQuantity;
      if (saleType == 'قطعة' || saleType == 'متر') {
        // بيع بوحدة أساسية - استخدام الكمية مباشرة
        baseQuantity = qi > 0 ? qi : ql;
      } else if (ql > 0) {
        // بيع بوحدة كبيرة - تحويل للوحدة الأساسية
        if (productUnit == 'meter' && saleType == 'لفة') {
          baseQuantity = ql * (uilu > 0 ? uilu : (lengthPerUnit ?? 1));
        } else {
          baseQuantity = ql * (uilu > 0 ? uilu : _getMultiplierFromHierarchy(unitHierarchy, saleType));
        }
      } else {
        baseQuantity = qi;
      }
      
      if (!productMap.containsKey(productName)) {
        productMap[productName] = _ProductAggregation(
          productName: productName,
          productId: productId,
          productUnit: productUnit,
          lengthPerUnit: lengthPerUnit,
          unitHierarchy: unitHierarchy,
          unitCosts: unitCosts,
        );
      }
      
      productMap[productName]!.totalAmount += itemTotal;
      productMap[productName]!.totalProfit += profit;
      productMap[productName]!.totalBaseQuantity += baseQuantity;
    }
    
    // تحويل إلى قائمة النتائج
    final results = productMap.values.map((agg) {
      return CustomerProductBreakdown(
        productName: agg.productName,
        productId: agg.productId,
        totalAmount: agg.totalAmount,
        totalProfit: agg.totalProfit,
        baseQuantity: agg.totalBaseQuantity,
        baseUnit: agg.productUnit == 'meter' ? 'متر' : 'قطعة',
        quantityFormatted: _formatQuantityWithHierarchy(
          agg.totalBaseQuantity,
          agg.productUnit,
          agg.lengthPerUnit,
          agg.unitHierarchy,
        ),
      );
    }).toList();
    
    // ترتيب افتراضي حسب الربح
    results.sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
    
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تفصيل العملاء المشترين لمنتج معين
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تفصيل العملاء الذين اشتروا منتج معين في سنة أو شهر محدد
  /// يُرجع قائمة بالعملاء مع المبلغ والربح والكمية بالوحدات الهرمية
  Future<List<ProductCustomerBreakdown>> getProductCustomersBreakdown({
    required int productId,
    required int year,
    int? month,
  }) async {
    final db = await _db.database;
    
    // جلب بيانات المنتج أولاً
    final productData = await db.query('products', where: 'id = ?', whereArgs: [productId]);
    if (productData.isEmpty) return [];
    
    final product = productData.first;
    final productName = product['name'] as String;
    final productUnit = product['unit'] as String;
    final lengthPerUnit = (product['length_per_unit'] as num?)?.toDouble();
    final unitHierarchy = product['unit_hierarchy'] as String?;
    
    // بناء شرط التاريخ
    String dateCondition;
    List<dynamic> dateArgs;
    if (month != null) {
      dateCondition = "strftime('%Y', i.invoice_date) = ? AND strftime('%m', i.invoice_date) = ?";
      dateArgs = [year.toString(), month.toString().padLeft(2, '0')];
    } else {
      dateCondition = "strftime('%Y', i.invoice_date) = ?";
      dateArgs = [year.toString()];
    }
    
    // جلب بنود الفواتير لهذا المنتج
    final items = await db.rawQuery('''
      SELECT 
        i.customer_id,
        i.customer_name,
        c.id AS c_id,
        c.name AS c_name,
        c.phone AS c_phone,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      LEFT JOIN customers c ON i.customer_id = c.id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE ii.product_name = ? AND i.status = 'محفوظة' AND $dateCondition
    ''', [productName, ...dateArgs]);
    
    // تجميع البيانات حسب العميل
    final Map<String, _CustomerAggregation> customerMap = {};
    
    for (final item in items) {
      final customerId = (item['customer_id'] as int?) ?? (item['c_id'] as int?);
      final customerName = (item['c_name'] as String?) ?? (item['customer_name'] as String?) ?? 'غير معروف';
      final customerPhone = item['c_phone'] as String?;
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;
      final qi = (item['qi'] as num?)?.toDouble() ?? 0;
      final ql = (item['ql'] as num?)?.toDouble() ?? 0;
      final uilu = (item['uilu'] as num?)?.toDouble() ?? 0;
      final saleType = (item['sale_type'] as String?) ?? '';
      final pUnit = (item['product_unit'] as String?) ?? productUnit;
      final pLengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? lengthPerUnit;
      final pUnitHierarchy = (item['unit_hierarchy'] as String?) ?? unitHierarchy;
      
      // حساب التكلفة
      final totalCost = _calculateItemCost(item);
      final profit = itemTotal - totalCost;
      
      // حساب الكمية بالوحدة الأساسية
      // 🔧 إصلاح: التحقق من نوع البيع أولاً قبل افتراض أن ql > 0 يعني وحدة كبيرة
      double baseQuantity;
      if (saleType == 'قطعة' || saleType == 'متر') {
        // بيع بوحدة أساسية - استخدام الكمية مباشرة
        baseQuantity = qi > 0 ? qi : ql;
      } else if (ql > 0) {
        // بيع بوحدة كبيرة - تحويل للوحدة الأساسية
        if (pUnit == 'meter' && saleType == 'لفة') {
          baseQuantity = ql * (uilu > 0 ? uilu : (pLengthPerUnit ?? 1));
        } else {
          baseQuantity = ql * (uilu > 0 ? uilu : _getMultiplierFromHierarchy(pUnitHierarchy, saleType));
        }
      } else {
        baseQuantity = qi;
      }
      
      final key = customerId?.toString() ?? customerName;
      if (!customerMap.containsKey(key)) {
        customerMap[key] = _CustomerAggregation(
          customerId: customerId,
          customerName: customerName,
          customerPhone: customerPhone,
        );
      }
      
      customerMap[key]!.totalAmount += itemTotal;
      customerMap[key]!.totalProfit += profit;
      customerMap[key]!.totalBaseQuantity += baseQuantity;
    }
    
    // تحويل إلى قائمة النتائج
    final results = customerMap.values.map((agg) {
      return ProductCustomerBreakdown(
        customerId: agg.customerId,
        customerName: agg.customerName,
        customerPhone: agg.customerPhone,
        totalAmount: agg.totalAmount,
        totalProfit: agg.totalProfit,
        baseQuantity: agg.totalBaseQuantity,
        baseUnit: productUnit == 'meter' ? 'متر' : 'قطعة',
        quantityFormatted: _formatQuantityWithHierarchy(
          agg.totalBaseQuantity,
          productUnit,
          lengthPerUnit,
          unitHierarchy,
        ),
      );
    }).toList();
    
    // ترتيب افتراضي حسب الربح
    results.sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
    
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال مساعدة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تحويل الكمية للوحدات الهرمية
  /// مثال: 36 قطعة = 6 سيت = 1 كرتون
  String _formatQuantityWithHierarchy(
    double baseQuantity,
    String productUnit,
    double? lengthPerUnit,
    String? unitHierarchyJson,
  ) {
    if (baseQuantity == 0) return '0';
    
    final baseUnitName = productUnit == 'meter' ? 'متر' : 'قطعة';
    final parts = <String>[];
    
    // إضافة الكمية الأساسية
    parts.add('${_formatNumber(baseQuantity)} $baseUnitName');
    
    // للمنتجات المباعة بالمتر
    if (productUnit == 'meter' && lengthPerUnit != null && lengthPerUnit > 0) {
      final rolls = baseQuantity / lengthPerUnit;
      if (rolls >= 0.01) {
        parts.add('${_formatNumber(rolls)} لفة');
      }
      return parts.join(' = ');
    }
    
    // للمنتجات المباعة بالقطعة مع هرمية
    if (unitHierarchyJson != null && unitHierarchyJson.isNotEmpty) {
      try {
        final hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
        double remaining = baseQuantity;
        double multiplier = 1.0;
        
        for (final level in hierarchy) {
          final unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
          final qty = (level['quantity'] as num?)?.toDouble() ?? 1.0;
          
          if (unitName.isEmpty || qty <= 0) continue;
          
          multiplier *= qty;
          final unitsAtThisLevel = baseQuantity / multiplier;
          
          if (unitsAtThisLevel >= 0.01) {
            parts.add('${_formatNumber(unitsAtThisLevel)} $unitName');
          }
        }
      } catch (e) {
        // تجاهل خطأ التحليل
      }
    }
    
    return parts.join(' = ');
  }
  
  /// الحصول على المضاعف من التسلسل الهرمي
  double _getMultiplierFromHierarchy(String? unitHierarchyJson, String saleType) {
    if (unitHierarchyJson == null || unitHierarchyJson.isEmpty || saleType.isEmpty) {
      return 1.0;
    }
    
    try {
      final hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final qty = (level['quantity'] as num?)?.toDouble() ?? 1.0;
        
        multiplier *= qty;
        
        if (unitName == saleType) {
          return multiplier;
        }
      }
    } catch (e) {
      // تجاهل خطأ التحليل
    }
    
    return 1.0;
  }
  
  /// تنسيق الأرقام
  String _formatNumber(num value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 تقارير المنتجات (Product Reports)
  // ═══════════════════════════════════════════════════════════════════════════

  /// الملخص الشامل لمنتج (مبيعات، أرباح، كميات)
  Future<Map<String, dynamic>> getProductSalesData(int productId) async {
    final db = await _db.database;
    
    // جلب كل بنود الفواتير لهذا المنتج
    // نستخدم LEFT JOIN مع products للتأكد من وجود البيانات الأساسية
    final items = await db.rawQuery('''
      SELECT 
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON (ii.product_id = p.id OR ii.product_name = p.name)
      WHERE p.id = ? AND i.status = 'محفوظة' $_deviceFilter
    ''', [productId]);
    
    double totalSales = 0.0;
    double totalCost = 0.0;
    double totalQuantity = 0.0;
    double totalSellingPriceSum = 0.0; // لحساب المتوسط
    double totalItemsCount = 0.0; // عدد البنود لحساب المتوسط
    
    // جلب إعدادات الربح
    final settings = await SettingsManager.getAppSettings();
    final adHocProfit = settings.defaultAdHocProfitPercentage;

    for (final item in items) {
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
      final sellingPrice = (item['selling_price'] as num?)?.toDouble() ?? 0.0;
      final qi = (item['qi'] as num?)?.toDouble() ?? 0.0;
      final ql = (item['ql'] as num?)?.toDouble() ?? 0.0;
      
      final itemQuantity = ql > 0 ? ql : qi; 
      
      // Robust Cost Calculation Inline (Matching drill-down reports)
      double itemCost = 0.0;
      
      final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
      final String productUnit = (item['product_unit'] as String?) ?? 'piece';
      final String? unitCostsJson = item['unit_costs'] as String?;
      final double? actualCostPrice = (item['actual_cost_per_unit'] as num?)?.toDouble();
      final double productCostPrice = (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
      final String? hierarchyJson = item['unit_hierarchy'] as String?;
      final double unitsInLargeUnit = (item['uilu'] as num?)?.toDouble() ?? 1.0;
      final double lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? 1.0;

       Map<String, dynamic> unitCosts = const {};
       if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
         try { unitCosts = jsonDecode(unitCostsJson); } catch (_) {}
       }
      
      double costPerUnit = productCostPrice;
      if (actualCostPrice != null && actualCostPrice > 0) {
         costPerUnit = actualCostPrice;
      } else if (ql > 0) {
         if (unitCosts.containsKey(saleType) && (unitCosts[saleType] is num)) {
            costPerUnit = (unitCosts[saleType] as num).toDouble();
         } else {
             if (productUnit == 'meter' && saleType == 'لفة') {
                costPerUnit = productCostPrice * (unitsInLargeUnit > 0 ? unitsInLargeUnit : lengthPerUnit);
             } else if (unitsInLargeUnit > 0) {
                costPerUnit = productCostPrice * unitsInLargeUnit;
             } else {
                 costPerUnit = _calculateCostFromHierarchy(
                   productCost: productCostPrice,
                   saleType: saleType,
                   unitHierarchyJson: hierarchyJson,
                   productUnit: productUnit
                 );
             }
         }
      } else {
         // Individual unit
         // itemCostPrice (cost_price from invoice_items) is not in select list alias?
         // SELECT ... ii.actual_cost_price ...
         // The query (1450-1466) selects `ii.quantity_individual` etc.
         // It does NOT explicitly select `cost_price` from `invoice_items` aliased!
         // Wait, `ii.actual_cost_price` is selected.
         // `p.cost_price` is selected.
         // `ii.cost_price` is NOT explicitly selected in the query shown in Step 273!
         // It selects `ii.item_total`.
         // Is `ii.*` used? No, specific fields.
         // So `item` map might NOT have `cost_price` independent of `product_cost_price`.
         // But `_calculateItemCost` usually needs it.
         // Let's assume `productCostPrice` (base) is the best fallback if `actual` is missing.
      }
      
      if (costPerUnit <= 0 && sellingPrice > 0) {
         costPerUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
      }
      
      if (ql > 0) itemCost = costPerUnit * ql;
      else itemCost = costPerUnit * qi;
      
      // End Robust Calc
      
      totalSales += itemTotal;
      totalCost += itemCost;
      totalQuantity += itemQuantity;
      totalSellingPriceSum += sellingPrice * itemQuantity;
      if (itemQuantity > 0) totalItemsCount += itemQuantity;
    }
    
    final totalProfit = totalSales - totalCost;
    final averageSellingPrice = totalItemsCount > 0 ? totalSellingPriceSum / totalItemsCount : 0.0;
    final profitMargin = totalSales > 0 ? (totalProfit / totalSales) * 100 : 0.0;
    
    return {
      'totalSales': totalSales,
      'totalProfit': totalProfit,
      'totalQuantity': totalQuantity,
      'averageSellingPrice': averageSellingPrice,
      'totalCost': totalCost,
      'profitMargin': profitMargin,
    };
  }

  /// المبيعات السنوية لمنتج
  Future<Map<int, double>> getProductYearlySales(int productId) async {
    final db = await _db.database;
    final results = await db.rawQuery('''
      SELECT 
        strftime('%Y', i.invoice_date) as year,
        SUM(CASE 
              WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1.0)
              ELSE COALESCE(ii.quantity_individual, 0.0)
            END) as total_qty
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON (ii.product_id = p.id OR ii.product_name = p.name)
      WHERE p.id = ? AND i.status = 'محفوظة'
      GROUP BY year
    ''', [productId]);
    
    return Map.fromEntries(results.map((e) => MapEntry(
      int.parse(e['year'] as String), 
      (e['total_qty'] as num?)?.toDouble() ?? 0.0
    )));
  }

  /// الأرباح السنوية لمنتج
  Future<Map<int, double>> getProductYearlyProfit(int productId) async {
    final db = await _db.database;
    
    // نحتاج لجلب البنود وحساب التكلفة يدوياً لأنها غير مخزنة مباشرة كصافي ربح
    final items = await db.rawQuery('''
      SELECT 
        strftime('%Y', i.invoice_date) as year,
        ii.*, p.unit, p.cost_price as product_cost, p.length_per_unit, p.unit_costs, p.unit_hierarchy, p.name as product_name
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON (ii.product_id = p.id OR ii.product_name = p.name)
      WHERE (p.id = ? OR ii.product_id = ?) AND i.status = 'محفوظة'
    ''', [productId, productId]);
    
    final Map<int, double> yearlyProfit = {};
    final settings = await SettingsManager.getAppSettings();
    
    for (final item in items) {
      final year = int.parse(item['year'] as String);
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
      
      // Robust Cost Calculation Inline
      double cost = 0.0;
      
      final double quantityL = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
      final double quantityI = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
      final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
      final String productUnit = (item['unit'] as String?) ?? 'piece';
      final String? unitCostsJson = item['unit_costs'] as String?;
      final double? actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
      final double productCost = (item['product_cost'] as num?)?.toDouble() ?? 
                                 (item['cost_price'] as num?)?.toDouble() ?? 0.0;
      final String? hierarchyJson = item['unit_hierarchy'] as String?;
      final double unitsInLargeUnit = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
      final double lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? 1.0;

       Map<String, dynamic> unitCosts = const {};
       if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
         try { unitCosts = jsonDecode(unitCostsJson); } catch (_) {}
       }
      
      double costPerUnit = productCost;
      if (actualCostPrice != null && actualCostPrice > 0) {
         costPerUnit = actualCostPrice;
      } else if (quantityL > 0) {
         if (unitCosts.containsKey(saleType) && (unitCosts[saleType] is num)) {
            costPerUnit = (unitCosts[saleType] as num).toDouble();
         } else {
             // Fallback
             if (productUnit == 'meter' && saleType == 'لفة') {
                costPerUnit = productCost * (unitsInLargeUnit > 0 ? unitsInLargeUnit : lengthPerUnit);
             } else if (unitsInLargeUnit > 0) {
                costPerUnit = productCost * unitsInLargeUnit;
             } else {
                 costPerUnit = _calculateCostFromHierarchy(
                   productCost: productCost,
                   saleType: saleType,
                   unitHierarchyJson: hierarchyJson,
                   productUnit: productUnit
                 );
             }
         }
      }
      
      final double sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
      if (costPerUnit <= 0 && sellingPrice > 0) {
         costPerUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
      }
      
      if (quantityL > 0) cost = costPerUnit * quantityL;
      else cost = costPerUnit * quantityI;
      
      final profit = itemTotal - cost;
      
      yearlyProfit[year] = (yearlyProfit[year] ?? 0.0) + profit;
    }
    
    return yearlyProfit;
  }
  
  /// المبيعات الشهرية لمنتج في سنة محددة
  Future<Map<int, double>> getProductMonthlySales(int productId, int year) async {
    final db = await _db.database;
    final yearStr = year.toString();
    
    final results = await db.rawQuery('''
      SELECT 
        strftime('%m', i.invoice_date) as month,
        SUM(CASE 
              WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1.0)
              ELSE COALESCE(ii.quantity_individual, 0.0)
            END) as total_qty
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON (ii.product_id = p.id OR ii.product_name = p.name)
      WHERE p.id = ? AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
      GROUP BY month
    ''', [productId, yearStr]);
    
    return Map.fromEntries(results.map((e) => MapEntry(
      int.parse(e['month'] as String), 
      (e['total_qty'] as num?)?.toDouble() ?? 0.0
    )));
  }

  /// الأرباح الشهرية لمنتج في سنة محددة
  Future<Map<int, double>> getProductMonthlyProfit(int productId, int year) async {
    final db = await _db.database;
    final items = await db.rawQuery('''
      SELECT 
        strftime('%m', i.invoice_date) as month,
        ii.*, p.unit, p.cost_price as product_cost, p.length_per_unit, p.unit_costs, p.unit_hierarchy, p.name as product_name
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON (ii.product_id = p.id OR ii.product_name = p.name)
      WHERE (p.id = ? OR ii.product_id = ?) AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
    ''', [productId, productId, year.toString()]);
    
    final Map<int, double> monthlyProfit = {};
    final settings = await SettingsManager.getAppSettings();
    
    for (final item in items) {
      final month = int.parse(item['month'] as String);
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
      
      // Robust Cost Calculation Inline
      double cost = 0.0;
      
      final double quantityL = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
      final double quantityI = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
      final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
      final String productUnit = (item['unit'] as String?) ?? 'piece';
      final String? unitCostsJson = item['unit_costs'] as String?;
      final double? actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
      final double productCost = (item['product_cost'] as num?)?.toDouble() ?? 
                                 (item['cost_price'] as num?)?.toDouble() ?? 0.0;
      final String? hierarchyJson = item['unit_hierarchy'] as String?;
      final double unitsInLargeUnit = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
      final double lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? 1.0;

       Map<String, dynamic> unitCosts = const {};
       if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
         try { unitCosts = jsonDecode(unitCostsJson); } catch (_) {}
       }
      
      double costPerUnit = productCost;
      if (actualCostPrice != null && actualCostPrice > 0) {
         costPerUnit = actualCostPrice;
      } else if (quantityL > 0) {
         if (unitCosts.containsKey(saleType) && (unitCosts[saleType] is num)) {
            costPerUnit = (unitCosts[saleType] as num).toDouble();
         } else {
             // Fallback
             if (productUnit == 'meter' && saleType == 'لفة') {
                costPerUnit = productCost * (unitsInLargeUnit > 0 ? unitsInLargeUnit : lengthPerUnit);
             } else if (unitsInLargeUnit > 0) {
                costPerUnit = productCost * unitsInLargeUnit;
             } else {
                 costPerUnit = _calculateCostFromHierarchy(
                   productCost: productCost,
                   saleType: saleType,
                   unitHierarchyJson: hierarchyJson,
                   productUnit: productUnit
                 );
             }
         }
      }
      
      final double sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
      if (costPerUnit <= 0 && sellingPrice > 0) {
         costPerUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
      }
      
      if (quantityL > 0) cost = costPerUnit * quantityL;
      else cost = costPerUnit * quantityI;
      
      final profit = itemTotal - cost;
      
      monthlyProfit[month] = (monthlyProfit[month] ?? 0.0) + profit;
    }
    
    return monthlyProfit;
  }

  /// تفاصيل فواتير منتج في شهر معين
  Future<List<ProductInvoiceAnalytics>> getProductInvoicesForMonth(int productId, int year, int month) async {
    final db = await _db.database;
    final yearStr = year.toString();
    final monthStr = month.toString().padLeft(2, '0');
    
    final items = await db.rawQuery('''
      SELECT 
        i.*,
        ii.*, 
        i.id as id,
        p.unit, p.cost_price as product_cost, p.length_per_unit, p.unit_costs, p.unit_hierarchy, p.name as product_name
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON (ii.product_id = p.id OR ii.product_name = p.name)
      WHERE (p.id = ? OR ii.product_id = ?)
        AND strftime('%Y', i.invoice_date) = ? 
        AND strftime('%m', i.invoice_date) = ? 
        AND i.status = 'محفوظة'
      ORDER BY i.invoice_date DESC
    ''', [productId, productId, yearStr, monthStr]);
    
    final settings = await SettingsManager.getAppSettings();
    final List<ProductInvoiceAnalytics> analytics = [];
    
    for (final item in items) {
      // بناء كائن الفاتورة
      final invoice = Invoice.fromMap(item);
      
      final double sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
      final double itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0; // Total sales for this item line
      
      final double quantityIndividual = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
      final double quantityLargeUnit = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
      final double unitsInLargeUnit = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
      final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
      final String productUnit = (item['unit'] as String?) ?? 'piece';
      final double? actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
      final double itemCostPrice = (item['cost_price'] as num?)?.toDouble() ?? 0.0; // This might be item specific cost or fallback
      final double productCostPrice = (item['product_cost'] as num?)?.toDouble() ?? 0.0; // Rename from query if needed, assume mapped correctly
      // In query: p.cost_price as cost_price might conflict with ii.cost_price. 
      // Query used: ii.*, p.unit, p.cost_price, ...
      // If ii has cost_price, it takes precedence in map? No, map keys must be unique or overwritten.
      // SQLite query returns columns. If naming conflict, behavior depends on driver. 
      // Safest is to alias in query.
      // Refined Query in getProductInvoicesForMonth below aliases p.cost_price as product_cost_price
      
      final double quantitySold = quantityLargeUnit > 0 ? quantityLargeUnit : quantityIndividual; // Display unit count
      
      // Robust Cost Calculation (Inlined or Helper)
      // Since we are iterating, let's use the robust logic from Customer reports for consistency
       final String? unitCostsJson = item['unit_costs'] as String?;
       final String? unitHierarchyJson = item['unit_hierarchy'] as String?;
       final double lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? 1.0;
       
       Map<String, dynamic> unitCosts = const {};
        if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
          try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
        }

       double costPerSoldUnit = 0.0;
       // ...Logic...
       // Actually, we can just use _calculateItemCost provided we pass all fields.
       // But _calculateItemCost implementation in this file needs to be verified.
       // Instead, let's just implement the specific calculation for profit here to be safe
       
       final double baseCostPrice = (item['product_cost'] as num?)?.toDouble() ?? 
                                    (item['cost_price'] as num?)?.toDouble() ?? 0.0;
       
       if (actualCostPrice != null && actualCostPrice > 0) {
          costPerSoldUnit = actualCostPrice;
       } else if (quantityLargeUnit > 0) {
          final dynamic stored = unitCosts[saleType];
          if (stored is num && stored > 0) {
            costPerSoldUnit = stored.toDouble();
          } else {
             // Logic
             if (productUnit == 'meter' && saleType == 'لفة') {
                costPerSoldUnit = baseCostPrice * (unitsInLargeUnit > 0 ? unitsInLargeUnit : lengthPerUnit);
             } else if (unitsInLargeUnit > 0) {
                costPerSoldUnit = baseCostPrice * unitsInLargeUnit;
             } else {
                costPerSoldUnit = _calculateCostFromHierarchy(
                   productCost: baseCostPrice, 
                   saleType: saleType, 
                   unitHierarchyJson: unitHierarchyJson, 
                   productUnit: productUnit
                );
             }
          }
       } else {
          costPerSoldUnit = baseCostPrice;
       }
       
       if (costPerSoldUnit <= 0 && sellingPrice > 0) {
          costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
       }
       
       final double currentItemSellingTotal;
       final double currentItemCostTotal;
       
       if (quantityLargeUnit > 0) {
           currentItemSellingTotal = sellingPrice * quantityLargeUnit;
           currentItemCostTotal = costPerSoldUnit * quantityLargeUnit;
       } else {
           currentItemSellingTotal = sellingPrice * quantityIndividual;
           currentItemCostTotal = costPerSoldUnit * quantityIndividual;
       }
       
       final double totalProfit = currentItemSellingTotal - currentItemCostTotal;
       // Re-assign itemTotal from calc if needed, assuming DB item_total is correct selling total.
       // itemTotal from DB is usually reliable for Sales.
       
       final double totalCost = currentItemCostTotal;
      
      final unitCost = quantitySold > 0 ? (totalCost / quantitySold) : 0.0;
      
      analytics.add(ProductInvoiceAnalytics(
        invoice: invoice,
        quantitySold: quantitySold,
        saleUnitsCount: quantitySold,
        profit: totalProfit,
        sellingPrice: sellingPrice,
        unitCostAtSale: unitCost,
      ));
    }
    
    return analytics;
  }

  /// Helper: Get invoices for customer in a specific month (Standard)
  Future<List<Invoice>> getCustomerInvoicesForMonth(int customerId, int year, int month) async {
    final db = await _db.database;
    final results = await db.query(
      'invoices',
      where: 'customer_id = ? AND status = ?',
      whereArgs: [customerId, 'محفوظة'],
      orderBy: 'invoice_date DESC'
    );
    
    return results
      .map((map) => Invoice.fromMap(map))
      .where((inv) {
         try {
            final d = inv.invoiceDate;
           return d.year == year && d.month == month;
         } catch (_) { return false; }
      })
      .toList();
  }

  /// اختبار حساب الربح (لأغراض التطوير)
  Future<Map<String, dynamic>> testProfitCalculation(int productId) async {
    final data = await getProductSalesData(productId);
    
    // جلب بعض التفاصيل الإضافية للاختبار
    final db = await _db.database;
    final product = (await db.query('products', where: 'id = ?', whereArgs: [productId])).first;
    
    // جلب عينة من الفواتير (أول 5)
    final sampleInvoices = await getProductInvoicesForMonth(productId, DateTime.now().year, DateTime.now().month);
    
    List<Map<String, dynamic>> detailedResults = [];
    if (sampleInvoices.isNotEmpty) {
      detailedResults = sampleInvoices.take(5).map((e) => {
        'invoice_id': e.invoice.id,
        // 🔢 الرقم التجاري للعرض، نسقط للـ id احتياطاً
        'invoice_number': (e.invoice.invoiceNumber != null && e.invoice.invoiceNumber!.isNotEmpty)
            ? e.invoice.invoiceNumber
            : e.invoice.id.toString(),
        'date': e.invoice.invoiceDate.toString().split(' ')[0],
        'quantity': e.quantitySold,
        'cost_price': e.unitCostAtSale,
        'selling_price': e.sellingPrice,
        'profit': e.profit
      }).toList();
    }

    return {
      'product_name': product['name'],
      'product_cost_price': product['cost_price'],
      'total_quantity': data['totalQuantity'],
      'total_sales': data['totalSales'],
      'total_cost': data['totalCost'],
      'total_profit': data['totalProfit'],
      'calculation_formula': 'Profit = Sales - ComputedCost(Actual or Hierarchy)',
      'verification': 'Check detailed_results for logic check',
      'detailed_results': detailedResults,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 👥 تقارير الأشخاص (Customer Reports)
  // ═══════════════════════════════════════════════════════════════════════════

  /// الملخص المالي لعميل (أرباح، مبيعات، فواتير)
  Future<Map<String, dynamic>> getCustomerProfitData(int customerId) async {
    final db = await _db.database;
    try {
      final settings = await SettingsManager.getAppSettings();
      final double adHocProfit = settings.defaultAdHocProfitPercentage / 100.0;

      // جلب بيانات الفواتير (المحفوظة فقط) - تشمل الفواتير القديمة والجديدة
      final List<Map<String, dynamic>> invoiceMaps = await db.rawQuery('''
        SELECT 
          SUM(total_amount) as total_sales,
          COUNT(*) as total_invoices,
          (SELECT COUNT(*) FROM invoices WHERE (customer_id = ? OR ((customer_id IS NULL OR customer_id = 0) AND customer_name = (SELECT name FROM customers WHERE id = ?))) AND status = 'محفوظة') as total_invoices_global
        FROM invoices
        WHERE (customer_id = ? OR ((customer_id IS NULL OR customer_id = 0) AND customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND status = 'محفوظة' $_deviceFilter
      ''', [customerId, customerId, customerId, customerId]);
 
      // جلب بيانات المعاملات المالية
      final List<Map<String, dynamic>> transactionMaps = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_transactions
        FROM transactions
        WHERE customer_id = ? $_deviceFilter
      ''', [customerId]);
 
      // جلب جميع البنود مع بيانات المنتج (مع unit_costs و unit_hierarchy)
      final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
        SELECT 
          ii.quantity_individual,
          ii.quantity_large_unit,
          ii.units_in_large_unit,
          ii.applied_price,
          ii.sale_type,
          ii.cost_price as item_cost_price,
          ii.actual_cost_price,
          ii.item_total,
          p.cost_price as product_cost_price,
          p.unit as product_unit,
          p.length_per_unit,
          p.unit_costs,
          p.unit_hierarchy
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        LEFT JOIN products p ON ii.product_name = p.name
        WHERE (i.customer_id = ? OR ((i.customer_id IS NULL OR i.customer_id = 0) AND i.customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND i.status = 'محفوظة' $_deviceFilter
      ''', [customerId, customerId]);
      
      double totalProfit = 0.0;
      double totalSellingPrice = 0.0;
      double totalQuantity = 0.0;
      
      for (final item in itemMaps) {
        final double quantityIndividual = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
        final double quantityLargeUnit = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
        final double unitsInLargeUnit = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
        final double sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
        final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
        final double? actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
        final double itemCostPrice = (item['item_cost_price'] as num?)?.toDouble() ?? 
            (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
        final double baseCostPrice = (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
        final String productUnit = (item['product_unit'] as String?) ?? 'piece';
        final double lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? 1.0;
        final String? unitCostsJson = item['unit_costs'] as String?;
        final String? unitHierarchyJson = item['unit_hierarchy'] as String?;
        
        Map<String, dynamic> unitCosts = const {};
        if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
          try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
        }
        
        final bool soldAsLargeUnit = quantityLargeUnit > 0;
        final double soldUnitsCount = soldAsLargeUnit ? quantityLargeUnit : quantityIndividual;
        
        double costPerSoldUnit;
        if (actualCostPrice != null && actualCostPrice > 0) {
          costPerSoldUnit = actualCostPrice;
        } else if (soldAsLargeUnit) {
          final dynamic stored = unitCosts[saleType];
          if (stored is num && stored > 0) {
            costPerSoldUnit = stored.toDouble();
          } else {
            final bool isMeterRoll = productUnit == 'meter' && (saleType == 'لفة');
            if (isMeterRoll) {
              costPerSoldUnit = baseCostPrice * (unitsInLargeUnit > 0 ? unitsInLargeUnit : lengthPerUnit);
            } else if (unitsInLargeUnit > 0) {
              costPerSoldUnit = baseCostPrice * unitsInLargeUnit;
            } else {
              costPerSoldUnit = _calculateCostFromHierarchy(
                productCost: baseCostPrice,
                saleType: saleType,
                unitHierarchyJson: unitHierarchyJson,
                productUnit: productUnit,
              );
            }
          }
        } else {
          costPerSoldUnit = itemCostPrice > 0 ? itemCostPrice : baseCostPrice;
        }
        
        if (costPerSoldUnit <= 0 && sellingPrice > 0) {
          costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice, profitMargin: adHocProfit);
        }
        
        final double itemProfit = (sellingPrice - costPerSoldUnit) * soldUnitsCount;
        totalProfit += itemProfit;
        totalQuantity += soldUnitsCount;
        totalSellingPrice += sellingPrice * soldUnitsCount;
      }
 
      final totalSales = (invoiceMaps.first['total_sales'] as num?)?.toDouble() ?? 0.0;
      final totalInvoices = (invoiceMaps.first['total_invoices'] as num?)?.toInt() ?? 0;
      final totalTransactions = (transactionMaps.first['total_transactions'] as num?)?.toInt() ?? 0;
      
      double averageSellingPrice = 0.0;
      if (totalQuantity > 0) {
        averageSellingPrice = totalSellingPrice / totalQuantity;
      }

      double adjTotalSales = totalSales;
      double adjTotalProfit = totalProfit;
      double adjTotalQuantity = totalQuantity;
      double adjAverageSellingPrice = averageSellingPrice;
 
      try {
        final List<Map<String, dynamic>> invIds = await db.rawQuery('''
          SELECT id FROM invoices 
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND status = 'محفوظة'
        ''', [customerId, customerId]);
        if (invIds.isNotEmpty) {
          final ids = invIds.map((e) => (e['id'] as num).toInt()).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          final List<Map<String, Object?>> rows = await db.rawQuery('''
            SELECT ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
                   p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
            FROM invoice_adjustments ia
            JOIN invoices i ON i.id = ia.invoice_id
            LEFT JOIN products p ON p.id = ia.product_id
            WHERE ia.product_id IS NOT NULL AND ia.invoice_id IN ($placeholders)
          ''', ids);
          double addSales = 0.0;
          double addProfit = 0.0;
          double addBaseQty = 0.0;
          for (final r in rows) {
            final String type = (r['type'] as String?) ?? 'debit';
            final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
            final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
            final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
            final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
            final String productUnit = (r['product_unit'] as String?) ?? 'piece';
            final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
            final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
            if (qtySaleUnits == 0) continue;
            final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;
            double baseQty;
            if (productUnit == 'meter' && saleType == 'لفة') {
              final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
              baseQty = qtySaleUnits * factor;
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qtySaleUnits;
            } else {
              baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
            final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
            final double costContribution = baseCost * (signedBaseQty);
            addSales += salesContribution;
            addProfit += (salesContribution - costContribution);
            addBaseQty += signedBaseQty;
          }
          adjTotalSales += addSales;
          adjTotalProfit += addProfit;
          adjTotalQuantity += addBaseQty;
          if (adjTotalQuantity > 0) {
            adjAverageSellingPrice = adjTotalSales / adjTotalQuantity;
          }
        }
      } catch (_) {}

      return {
        'totalProfit': adjTotalProfit,
        'totalSales': adjTotalSales,
        'totalInvoices': totalInvoices,
        'totalTransactions': totalTransactions,
        'averageSellingPrice': adjAverageSellingPrice,
        'totalQuantity': adjTotalQuantity,
      };
    } catch (e) {
      throw Exception('Failed to fetch customer summary: $e');
    }
  }
  
  Future<Map<int, PersonYearData>> getCustomerYearlyData(int customerId) async {
    final db = await _db.database;
    try {
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔧 إصلاح: فصل استعلام الفواتير عن المعاملات لتجنب تكرار الصفوف
      // 🔧 إصلاح 2: تضمين الفواتير القديمة التي ليس لها customer_id (بالاسم)
      // 🔧 إصلاح 3: فصل استعلام المبيعات عن الأرباح لتجنب تكرار total_amount
      // ═══════════════════════════════════════════════════════════════════════════
      
      // 1. جلب بيانات المبيعات وعدد الفواتير (بدون JOIN مع الأصناف لتجنب التكرار)
      final List<Map<String, dynamic>> salesMaps = await db.rawQuery('''
        SELECT 
          strftime('%Y', invoice_date) as year,
          SUM(total_amount) as total_sales,
          COUNT(*) as total_invoices
        FROM invoices
        WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND status = 'محفوظة'
        GROUP BY strftime('%Y', invoice_date)
        ORDER BY year DESC
      ''', [customerId, customerId]);
      
      // 2. 🔧 إصلاح: نفس منطق getDailyReport
      final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
        SELECT 
          strftime('%Y', i.invoice_date) as year,
          ii.quantity_individual,
          ii.quantity_large_unit,
          ii.units_in_large_unit,
          ii.applied_price,
          ii.sale_type,
          ii.cost_price as item_cost_price,
          ii.actual_cost_price,
          p.cost_price as product_cost_price,
          p.unit as product_unit,
          p.length_per_unit,
          p.unit_costs,
          p.unit_hierarchy
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE (i.customer_id = ? OR (i.customer_id IS NULL AND i.customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND i.status = 'محفوظة'
      ''', [customerId, customerId]);
      
      // حساب الأرباح لكل سنة
      final Map<int, Map<String, dynamic>> profitByYear = {};
      for (final item in itemMaps) {
        final int year = int.tryParse(item['year']?.toString() ?? '') ?? 0;
        final double quantityIndividual = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
        final double quantityLargeUnit = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
        final double unitsInLargeUnit = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
        final double sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
        final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
        final double? actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
        final double itemCostPrice = (item['item_cost_price'] as num?)?.toDouble() ?? 
            (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
        final double baseCostPrice = (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
        final String productUnit = (item['product_unit'] as String?) ?? 'piece';
        final double lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? 1.0;
        final String? unitCostsJson = item['unit_costs'] as String?;
        final String? unitHierarchyJson = item['unit_hierarchy'] as String?;
        
        Map<String, dynamic> unitCosts = const {};
        if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
          try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
        }
        
        final bool soldAsLargeUnit = quantityLargeUnit > 0;
        final double soldUnitsCount = soldAsLargeUnit ? quantityLargeUnit : quantityIndividual;
        final double baseUnitsCount = soldAsLargeUnit ? (quantityLargeUnit * unitsInLargeUnit) : quantityIndividual;
        
        double costPerSoldUnit;
        if (actualCostPrice != null && actualCostPrice > 0) {
          costPerSoldUnit = actualCostPrice;
        } else if (soldAsLargeUnit) {
          final dynamic stored = unitCosts[saleType];
          if (stored is num && stored > 0) {
            costPerSoldUnit = stored.toDouble();
          } else {
            final bool isMeterRoll = productUnit == 'meter' && (saleType == 'لفة');
            if (isMeterRoll) {
              costPerSoldUnit = baseCostPrice * (unitsInLargeUnit > 0 ? unitsInLargeUnit : lengthPerUnit);
            } else if (unitsInLargeUnit > 0) {
              costPerSoldUnit = baseCostPrice * unitsInLargeUnit;
            } else {
              costPerSoldUnit = _calculateCostFromHierarchy(
                productCost: baseCostPrice,
                saleType: saleType,
                unitHierarchyJson: unitHierarchyJson,
                productUnit: productUnit,
              );
            }
          }
        } else {
          costPerSoldUnit = itemCostPrice > 0 ? itemCostPrice : baseCostPrice;
        }
        
        if (costPerSoldUnit <= 0 && sellingPrice > 0) {
          costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
        }
        
        final double itemProfit = (sellingPrice - costPerSoldUnit) * soldUnitsCount;
        final double itemSellingTotal = sellingPrice * soldUnitsCount;
        
        if (!profitByYear.containsKey(year)) {
          profitByYear[year] = {'total_profit': 0.0, 'total_selling_price': 0.0, 'total_quantity': 0.0};
        }
        profitByYear[year]!['total_profit'] = (profitByYear[year]!['total_profit'] as num).toDouble() + itemProfit;
        profitByYear[year]!['total_selling_price'] = (profitByYear[year]!['total_selling_price'] as num).toDouble() + itemSellingTotal;
        profitByYear[year]!['total_quantity'] = (profitByYear[year]!['total_quantity'] as num).toDouble() + baseUnitsCount;
      }
      
      // 2. جلب عدد المعاملات لكل سنة بشكل منفصل
      final List<Map<String, dynamic>> txMaps = await db.rawQuery('''
        SELECT 
          strftime('%Y', transaction_date) as year,
          COUNT(*) as total_transactions
        FROM transactions
        WHERE customer_id = ?
        GROUP BY strftime('%Y', transaction_date)
      ''', [customerId]);
 
      final Map<int, PersonYearData> yearlyData = {};
      final Map<int, int> txByYear = {};
      for (final tx in txMaps) {
        final year = int.tryParse(tx['year']?.toString() ?? '') ?? 0;
        txByYear[year] = (tx['total_transactions'] as num?)?.toInt() ?? 0;
      }
      
      for (final map in salesMaps) {
        final year = int.tryParse(map['year']?.toString() ?? '') ?? 0;
        final profitData = profitByYear[year];
        
        final totalSellingPrice = (profitData?['total_selling_price'] as num?)?.toDouble() ?? 0.0;
        final totalQuantity = (profitData?['total_quantity'] as num?)?.toDouble() ?? 0.0;
        final totalProfit = (profitData?['total_profit'] as num?)?.toDouble() ?? 0.0;
        
        double averageSellingPrice = 0.0;
        if (totalQuantity > 0) {
          averageSellingPrice = totalSellingPrice / totalQuantity;
        }
        
        yearlyData[year] = PersonYearData(
          totalProfit: totalProfit,
          totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0.0,
          totalInvoices: (map['total_invoices'] as num?)?.toInt() ?? 0,
          totalTransactions: txByYear[year] ?? 0,
          averageSellingPrice: averageSellingPrice,
          totalQuantity: totalQuantity,
          monthlyData: {},
        );
      }
 
      // دمج تسويات البنود سنوياً لهذا العميل
      try {
        final invIds = await db.rawQuery('''
          SELECT id, strftime('%Y', invoice_date) as y 
          FROM invoices 
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND status = 'محفوظة'
        ''', [customerId, customerId]);
        if (invIds.isNotEmpty) {
          final ids = invIds.map((e) => (e['id'] as num).toInt()).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          final rows = await db.rawQuery('''
            SELECT strftime('%Y', ia.created_at) as year, ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
                   p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
            FROM invoice_adjustments ia
            JOIN invoices i ON i.id = ia.invoice_id
            LEFT JOIN products p ON p.id = ia.product_id
            WHERE ia.product_id IS NOT NULL AND ia.invoice_id IN ($placeholders)
          ''', ids);
          for (final r in rows) {
            final int year = int.tryParse(r['year']?.toString() ?? '') ?? 0;
            final String type = (r['type'] as String?) ?? 'debit';
            final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
            final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
            final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
            final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
            final String productUnit = (r['product_unit'] as String?) ?? 'piece';
            final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
            final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
            if (qtySaleUnits == 0) continue;
            final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;
            double baseQty;
            if (productUnit == 'meter' && saleType == 'لفة') {
              final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
              baseQty = qtySaleUnits * factor;
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qtySaleUnits;
            } else {
              baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
            final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
            final double costContribution = baseCost * (signedBaseQty);
            final existing = yearlyData[year];
            if (existing != null) {
              final updated = PersonYearData(
                totalProfit: existing.totalProfit + (salesContribution - costContribution),
                totalSales: existing.totalSales + salesContribution,
                totalInvoices: existing.totalInvoices,
                totalTransactions: existing.totalTransactions,
                averageSellingPrice: 0.0, 
                totalQuantity: existing.totalQuantity + signedBaseQty,
                monthlyData: existing.monthlyData,
              );
              yearlyData[year] = updated;
            } else {
              yearlyData[year] = PersonYearData(
                totalProfit: (salesContribution - costContribution),
                totalSales: salesContribution,
                totalInvoices: 0,
                totalTransactions: 0,
                averageSellingPrice: 0.0,
                totalQuantity: signedBaseQty,
                monthlyData: {},
              );
            }
          }
          // إعادة حساب متوسط سعر البيع للسنة
          for (final entry in yearlyData.entries) {
            final q = entry.value.totalQuantity;
            final s = entry.value.totalSales;
            yearlyData[entry.key] = PersonYearData(
              totalProfit: entry.value.totalProfit,
              totalSales: s,
              totalInvoices: entry.value.totalInvoices,
              totalTransactions: entry.value.totalTransactions,
              averageSellingPrice: q > 0 ? (s / q) : 0.0,
              totalQuantity: q,
              monthlyData: entry.value.monthlyData,
            );
          }
        }
      } catch (_) {}

      return yearlyData;
    } catch (e) {
      throw Exception('Error fetching yearly data: $e');
    }
  }
  
  /// البيانات الشهرية للعميل في سنة
  Future<Map<int, PersonMonthData>> getCustomerMonthlyData(int customerId, int year) async {
    final db = await _db.database;
    try {
      // الخطوة 1: إحضار مجاميع المبيعات وعدد الفواتير والمعاملات شهرياً (بدون أرباح)
      // 🔧 إصلاح: تضمين الفواتير القديمة التي ليس لها customer_id (بالاسم)
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          m.month AS month,
          m.total_sales AS total_sales,
          m.total_invoices AS total_invoices,
          COALESCE(t.total_transactions, 0) AS total_transactions
        FROM (
          SELECT 
            strftime('%m', invoice_date) AS month,
            SUM(total_amount) AS total_sales,
            COUNT(DISTINCT id) AS total_invoices
          FROM invoices
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND strftime('%Y', invoice_date) = ? AND status = 'محفوظة'
          GROUP BY strftime('%m', invoice_date)
        ) m
        LEFT JOIN (
          SELECT strftime('%m', transaction_date) AS month, COUNT(DISTINCT id) AS total_transactions
          FROM transactions
          WHERE customer_id = ? AND strftime('%Y', transaction_date) = ?
          GROUP BY strftime('%m', transaction_date)
        ) t ON t.month = m.month
        ORDER BY m.month ASC
      ''', [customerId, customerId, year.toString(), customerId, year.toString()]);
 
      final Map<int, PersonMonthData> monthlyData = {};
      for (final map in maps) {
        final month = int.tryParse(map['month']?.toString() ?? '') ?? 0;
       monthlyData[month] = PersonMonthData(
          totalProfit: 0.0, // سنحسبها بدقة في الخطوة 2
          totalSales: (map['total_sales'] as num?)?.toDouble() ?? 0.0,
          totalInvoices: (map['total_invoices'] as num?)?.toInt() ?? 0,
          totalTransactions: (map['total_transactions'] as num?)?.toInt() ?? 0,
          invoices: const [],
        );
      }
 
      // الخطوة 2: 🔧 إصلاح: نفس منطق getDailyReport
      final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
        SELECT 
          strftime('%m', i.invoice_date) AS month,
          ii.quantity_individual,
          ii.quantity_large_unit,
          ii.units_in_large_unit,
          ii.applied_price,
          ii.sale_type,
          ii.cost_price as item_cost_price,
          ii.actual_cost_price,
          p.cost_price as product_cost_price,
          p.unit as product_unit,
          p.length_per_unit,
          p.unit_costs,
          p.unit_hierarchy
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE (i.customer_id = ? OR (i.customer_id IS NULL AND i.customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
      ''', [customerId, customerId, year.toString()]);

      // حساب الأرباح والكميات لكل شهر
      final Map<int, double> profitByMonth = {};
      final Map<int, double> quantityByMonth = {};
      for (final item in itemMaps) {
        final int month = int.tryParse(item['month']?.toString() ?? '') ?? 0;
      final double quantityIndividual = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
        final double quantityLargeUnit = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
        final double unitsInLargeUnit = (item['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
        final double sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
        final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
        final double? actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
        final double itemCostPrice = (item['item_cost_price'] as num?)?.toDouble() ?? 
            (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
        final double baseCostPrice = (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
        final String productUnit = (item['product_unit'] as String?) ?? 'piece';
        final double lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble() ?? 1.0;
        final String? unitCostsJson = item['unit_costs'] as String?;
        final String? unitHierarchyJson = item['unit_hierarchy'] as String?;
        
        // تحليل unit_costs JSON
        Map<String, dynamic> unitCosts = const {};
        if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
          try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
        }
        
        final bool soldAsLargeUnit = quantityLargeUnit > 0;
        final double soldUnitsCount = soldAsLargeUnit ? quantityLargeUnit : quantityIndividual;
        final double baseUnitsCount = soldAsLargeUnit ? (quantityLargeUnit * unitsInLargeUnit) : quantityIndividual;
        
        // حساب التكلفة لكل وحدة مباعة
        double costPerSoldUnit;
        if (actualCostPrice != null && actualCostPrice > 0) {
          costPerSoldUnit = actualCostPrice;
        } else if (soldAsLargeUnit) {
          final dynamic stored = unitCosts[saleType];
          if (stored is num && stored > 0) {
            costPerSoldUnit = stored.toDouble();
          } else {
            final bool isMeterRoll = productUnit == 'meter' && (saleType == 'لفة');
            if (isMeterRoll) {
              costPerSoldUnit = baseCostPrice * (unitsInLargeUnit > 0 ? unitsInLargeUnit : lengthPerUnit);
            } else if (unitsInLargeUnit > 0) {
              costPerSoldUnit = baseCostPrice * unitsInLargeUnit;
            } else {
              costPerSoldUnit = _calculateCostFromHierarchy(
                productCost: baseCostPrice,
                saleType: saleType,
                unitHierarchyJson: unitHierarchyJson,
                productUnit: productUnit,
              );
            }
          }
        } else {
          costPerSoldUnit = itemCostPrice > 0 ? itemCostPrice : baseCostPrice;
        }
        
        if (costPerSoldUnit <= 0 && sellingPrice > 0) {
          costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
        }
        
        final double itemProfit = (sellingPrice - costPerSoldUnit) * soldUnitsCount;
        profitByMonth[month] = (profitByMonth[month] ?? 0) + itemProfit;
        quantityByMonth[month] = (quantityByMonth[month] ?? 0) + baseUnitsCount;
      }

      // تحديث monthlyData بالأرباح المحسوبة
      for (final entry in profitByMonth.entries) {
        final int month = entry.key;
        final double totalProfit = entry.value;
        final double totalQuantity = quantityByMonth[month] ?? 0.0;
        
        final existing = monthlyData[month];
        if (existing != null) {
          monthlyData[month] = PersonMonthData(
            totalProfit: totalProfit,
            totalSales: existing.totalSales,
            totalInvoices: existing.totalInvoices,
            totalTransactions: existing.totalTransactions,
            totalQuantity: totalQuantity,
            invoices: existing.invoices,
          );
        } else {
          monthlyData[month] = PersonMonthData(
            totalProfit: totalProfit,
            totalSales: 0.0,
            totalInvoices: 0,
            totalTransactions: 0,
            totalQuantity: totalQuantity,
            invoices: const [],
          );
        }
      }

      // الخطوة 3: دمج تسويات البنود شهرياً
      try {
        final invIds = await db.rawQuery('''
          SELECT id 
          FROM invoices 
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND status = 'محفوظة' AND strftime('%Y', invoice_date) = ?
        ''', [customerId, customerId, year.toString()]);
        if (invIds.isNotEmpty) {
          final ids = invIds.map((e) => (e['id'] as num).toInt()).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          final rows = await db.rawQuery('''
            SELECT strftime('%m', ia.created_at) as month, ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
                   p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
            FROM invoice_adjustments ia
            JOIN invoices i ON i.id = ia.invoice_id
            LEFT JOIN products p ON p.id = ia.product_id
            WHERE ia.product_id IS NOT NULL AND ia.invoice_id IN ($placeholders)
          ''', ids);
          for (final r in rows) {
            final int month = int.tryParse(r['month']?.toString() ?? '') ?? 0;
            final String type = (r['type'] as String?) ?? 'debit';
            final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
            final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
            final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
            final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
            final String productUnit = (r['product_unit'] as String?) ?? 'piece';
            final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
            final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
            if (qtySaleUnits == 0) continue;
            final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;
            double baseQty;
            if (productUnit == 'meter' && saleType == 'لفة') {
              final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
              baseQty = qtySaleUnits * factor;
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qtySaleUnits;
            } else {
              baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
            final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
            final double costContribution = baseCost * (signedBaseQty);
            final existing = monthlyData[month];
            if (existing != null) {
              monthlyData[month] = PersonMonthData(
                totalProfit: existing.totalProfit + (salesContribution - costContribution),
                totalSales: existing.totalSales + salesContribution,
                totalInvoices: existing.totalInvoices,
                totalTransactions: existing.totalTransactions,
                invoices: existing.invoices,
              );
            }
          }
        }
      } catch (_) {}

      return monthlyData;
    } catch (e) {
      throw Exception('Failed to fetch monthly data: $e');
    }
  }
  
  /// جلب جميع فواتير العميل في شهر معيّن مع ربح كل فاتورة
  Future<List<InvoiceWithProductData>> getCustomerInvoicesWithProfitForMonth(int customerId, int year, int month) async {
    final db = await _db.database;
    final yearStr = year.toString();
    final monthStr = month.toString().padLeft(2, '0');

    // 1. Get all invoices for this customer in this month
    final List<Map<String, dynamic>> invoiceMaps = await db.rawQuery('''
      SELECT * FROM invoices
      WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
        SELECT name FROM customers WHERE id = ?
      )))
      AND strftime('%Y', invoice_date) = ?
      AND strftime('%m', invoice_date) = ?
      AND status = 'محفوظة'
      ORDER BY invoice_date DESC
    ''', [customerId, customerId, yearStr, monthStr]);

    if (invoiceMaps.isEmpty) return [];

    final invoiceIds = invoiceMaps.map((m) => m['id'] as int).toList();
    final placeholders = List.filled(invoiceIds.length, '?').join(',');
    
    // 2. Get all items for these invoices with product data
    final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
       SELECT 
         ii.*, p.unit, p.cost_price as product_cost, p.length_per_unit, p.unit_costs, p.unit_hierarchy, p.name as product_name
       FROM invoice_items ii
       LEFT JOIN products p ON (ii.product_id = p.id OR ii.product_name = p.name)
       WHERE ii.invoice_id IN ($placeholders)
    ''', invoiceIds);

    // Group items by invoice ID
    final Map<int, List<Map<String, dynamic>>> itemsByInvoice = {};
    for (final item in itemMaps) {
      final invId = item['invoice_id'] as int;
      itemsByInvoice.putIfAbsent(invId, () => []).add(item);
    }

    final List<InvoiceWithProductData> result = [];
    final settings = await SettingsManager.getAppSettings();

    // 3. Process each invoice and its items
    for (final invMap in invoiceMaps) {
      final invoice = Invoice.fromMap(invMap);
      final items = itemsByInvoice[invoice.id] ?? [];
      
      double totalProfitForInvoice = 0.0;
      final List<InvoiceItemData> itemDataList = [];

      for (final item in items) {
         final double itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
         final double sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
         final double quantityIndividual = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
         final double quantityLargeUnit = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
         final String saleType = (item['sale_type'] as String?) ?? 'قطعة';
         
         final costPerLine = _calculateItemCost(item, adHocProfitPercentage: settings.defaultAdHocProfitPercentage);
         final profitPerLine = itemTotal - costPerLine;

         totalProfitForInvoice += profitPerLine;
         
         itemDataList.add(InvoiceItemData(
           productName: item['product_name'] as String? ?? 'Unknown',
           quantity: quantityLargeUnit > 0 ? quantityLargeUnit : quantityIndividual,
           unit: saleType,
           unitPrice: sellingPrice,
           totalPrice: itemTotal,
           costPrice: costPerLine, 
           profit: profitPerLine,
         ));
      }
      
      result.add(InvoiceWithProductData(
        invoiceId: invoice.id!,
        invoiceDate: invoice.invoiceDate,
        customerName: invoice.customerName,
        totalAmount: invoice.totalAmount,
        discount: invoice.discount,
        profit: totalProfitForInvoice,
        items: itemDataList,
      ));
    }
    return result;
  }

  /// حركات الديون (دفوعات/سندات) لعميل في شهر معين
  Future<List<DebtTransaction>> getCustomerTransactionsForMonth(int customerId, int year, int month) async {
    final db = await _db.database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT *
        FROM transactions
        WHERE customer_id = ? 
          AND strftime('%Y', transaction_date) = ?
          AND strftime('%m', transaction_date) = ?
        ORDER BY transaction_date DESC
      ''', [customerId, year.toString(), month.toString().padLeft(2, '0')]);

      return List.generate(
          maps.length, (i) => DebtTransaction.fromMap(maps[i]));
    } catch (e) {
      throw Exception('Error fetching transactions: $e');
    }
  }

  /// 🚨 جلب عدد المنتجات التي ستنتهي صلاحيتها قريباً
  Future<int> getExpiringProductsCount(int monthsThreshold) async {
    final db = await _db.database;
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: monthsThreshold * 30)); // تقريب الشهر لـ 30 يوم
    
    // تنسيق التواريخ ISO8601 للمقارنة النصية في SQLite
    final nowStr = now.toIso8601String();
    final thresholdStr = thresholdDate.toIso8601String();
    
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM products 
      WHERE has_expiry = 1 
      AND expiry_date IS NOT NULL 
      AND expiry_date >= ? 
      AND expiry_date <= ?
    ''', [nowStr, thresholdStr]);
    
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تقارير المرتجعات (Returns)
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔄 حساب المرتجعات مع استثناء الفواتير المنشأة في نفس الفترة
  // ═══════════════════════════════════════════════════════════════════════════

  Future<double> _getSnapshotReturns(DateTime start, DateTime end, {DateTime? exclusionStartDate}) async {
    try {
      final db = await _db.database;
      final startStr = start.toIso8601String().split('T')[0];
      final endStr = end.toIso8601String().split('T')[0];
      
      // جلب السناب شوتس للفواتير النقدية التي حدث عليها تعديل في هذه الفترة
      // نقوم بجلب created_at للفاتورة الأصلية أيضاً للتحقق من شرط الاستثناء
      final snapshots = await db.rawQuery('''
        SELECT s.*, i.customer_name, i.created_at as invoice_created_at
        FROM invoice_snapshots s
        JOIN invoices i ON s.invoice_id = i.id
        WHERE DATE(s.created_at) >= ? AND DATE(s.created_at) <= ?
        AND i.payment_type = 'نقد'
        ORDER BY s.invoice_id, s.created_at ASC
      ''', [startStr, endStr]);
      
      if (snapshots.isEmpty) return 0.0;
      
      double total = 0.0;
      final Map<int, List<Map<String, dynamic>>> snapshotsByInvoice = {};
      for (var s in snapshots) {
        final invId = s['invoice_id'] as int;
        snapshotsByInvoice.putIfAbsent(invId, () => []).add(s);
      }
      
      snapshotsByInvoice.forEach((invoiceId, invoiceSnapshots) {
        // التحقق من شرط الاستثناء: إذا كانت الفاتورة أنشئت *في أو بعد* exclusionStartDate، نتجاهلها
        // أي أننا نحسب المرتجع فقط للفواتير "القديمة" التي عدلت في هذه الفترة
        if (exclusionStartDate != null && invoiceSnapshots.isNotEmpty) {
           final invCreatedAtStr = invoiceSnapshots.first['invoice_created_at'] as String?;
           if (invCreatedAtStr != null) {
              final invCreatedAt = DateTime.tryParse(invCreatedAtStr);
              if (invCreatedAt != null) {
                 // مقارنة التاريخ فقط (تجاهل الوقت) لضمان الدقة
                 final invDateOnly = DateTime(invCreatedAt.year, invCreatedAt.month, invCreatedAt.day);
                 final exclusionDateOnly = DateTime(exclusionStartDate.year, exclusionStartDate.month, exclusionStartDate.day);
                 
                 if (invDateOnly.isAfter(exclusionDateOnly) || invDateOnly.isAtSameMomentAs(exclusionDateOnly)) {
                   return; // ⏩ تخطي هذه الفاتورة لأنها أنشئت في نفس الفترة (أو بعدها)
                 }
              }
           }
        }

        for (int i = 0; i < invoiceSnapshots.length - 1; i++) {
          final current = invoiceSnapshots[i];
          final next = invoiceSnapshots[i+1];
          
          if (current['snapshot_type'] == 'before_edit' && next['snapshot_type'] == 'after_edit') {
            final oldTotal = (current['total_amount'] as num?)?.toDouble() ?? 0.0;
            final newTotal = (next['total_amount'] as num?)?.toDouble() ?? 0.0;
            
            if (newTotal < oldTotal) {
              total += (oldTotal - newTotal);
            }
          }
        }
      });
      
      return total;
    } catch (e) {
      print('Error calculating snapshot returns: $e');
      return 0.0;
    }
  }

  /// استخراج المرتجعات النقدية في فترة معينة من خلال سجل التعديلات
  /// المرتجع هو أي تعديل أدى إلى نقص في قيمة الفاتورة
  Future<List<Map<String, dynamic>>> getCashReturnsInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String();
    final endStr = endDate.toIso8601String();

    // جلب كل اللقطات في الفترة المحددة
    // نحتاج اللقطات من نوع before_edit و after_edit
    final snapshots = await db.rawQuery('''
      SELECT s.*
      FROM invoice_snapshots s
      JOIN invoices i ON s.invoice_id = i.id
      WHERE s.created_at >= ? AND s.created_at <= ?
        AND s.snapshot_type IN ('before_edit', 'after_edit')
        $_deviceFilter
      ORDER BY s.invoice_id ASC, s.created_at ASC
    ''', [startStr, endStr]);

    Map<int, List<Map<String, dynamic>>> snapshotsByInvoice = {};
    for (var s in snapshots) {
      final invoiceId = s['invoice_id'] as int;
      if (!snapshotsByInvoice.containsKey(invoiceId)) {
        snapshotsByInvoice[invoiceId] = [];
      }
      snapshotsByInvoice[invoiceId]!.add(s);
    }

    List<Map<String, dynamic>> returns = [];

    // تحليل اللقطات لكل فاتورة
    snapshotsByInvoice.forEach((invoiceId, invoiceSnapshots) {
      for (int i = 0; i < invoiceSnapshots.length - 1; i++) {
        final current = invoiceSnapshots[i];
        final next = invoiceSnapshots[i+1];

        // البحث عن زوج: قبل التعديل -> بعد التعديل (أو لقطتين متتاليتين)
        if (current['snapshot_type'] == 'before_edit' && next['snapshot_type'] == 'after_edit') {
           _processReturnPair(current, next, returns);
        }
      }
    });

    // 🔢 إثراء النتائج برقم الفاتورة التجاري من جدول invoices
    if (returns.isNotEmpty) {
      final invoiceIds = returns
          .map((r) => r['invoice_id'])
          .whereType<int>()
          .toSet()
          .toList();
      if (invoiceIds.isNotEmpty) {
        final placeholders = List.filled(invoiceIds.length, '?').join(',');
        final rows = await db.rawQuery(
          'SELECT id, invoice_number FROM invoices WHERE id IN ($placeholders)',
          invoiceIds,
        );
        final Map<int, String> numberById = {};
        for (final r in rows) {
          final numVal = r['invoice_number'] as String?;
          if (numVal != null && numVal.isNotEmpty) {
            numberById[r['id'] as int] = numVal;
          }
        }
        for (final ret in returns) {
          final invId = ret['invoice_id'] as int?;
          if (invId != null) {
            ret['invoice_number'] = numberById[invId] ?? invId.toString();
          }
        }
      }
    }

    return returns;
  }

  void _processReturnPair(Map<String, dynamic> before, Map<String, dynamic> after, List<Map<String, dynamic>> returns) {
    // 1. حساب الفرق في الإجمالي
    final totalBefore = (before['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalAfter = (after['total_amount'] as num?)?.toDouble() ?? 0.0;
    
    // إذا نقص الإجمالي، فهذا مرتجع
    if (totalBefore > totalAfter) {
      final diff = totalBefore - totalAfter;
      
      // 2. التحقق من نوع الدفع (نقد فقط أم الكل؟)
      final paymentType = (after['payment_type'] ?? before['payment_type'] ?? '').toString();
      
      returns.add({
        'invoice_id': before['invoice_id'],
        'date': after['created_at'], // تاريخ التعديل (المرتجع)
        'amount_returned': diff,
        'payment_type': paymentType,
        'customer_name': after['customer_name'] ?? before['customer_name'],
        'before_total': totalBefore,
        'after_total': totalAfter,
        'created_by': after['created_by'] ?? 'غير معروف', // المحاسب الذي قام بالتعديل
        'notes': after['notes'] ?? '',
      });
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// نماذج البيانات
// ═══════════════════════════════════════════════════════════════════════════

/// تفصيل منتج مشترى من عميل
class CustomerProductBreakdown {
  final String productName;
  final int? productId;
  final double totalAmount;
  final double totalProfit;
  final double baseQuantity;
  final String baseUnit;
  final String quantityFormatted;
  
  CustomerProductBreakdown({
    required this.productName,
    this.productId,
    required this.totalAmount,
    required this.totalProfit,
    required this.baseQuantity,
    required this.baseUnit,
    required this.quantityFormatted,
  });
}

/// تفصيل عميل اشترى منتج
class ProductCustomerBreakdown {
  final int? customerId;
  final String customerName;
  final String? customerPhone;
  final double totalAmount;
  final double totalProfit;
  final double baseQuantity;
  final String baseUnit;
  final String quantityFormatted;
  
  ProductCustomerBreakdown({
    this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.totalAmount,
    required this.totalProfit,
    required this.baseQuantity,
    required this.baseUnit,
    required this.quantityFormatted,
  });
}

// كلاسات مساعدة للتجميع
class _ProductAggregation {
  final String productName;
  final int? productId;
  final String productUnit;
  final double? lengthPerUnit;
  final String? unitHierarchy;
  final String? unitCosts;
  double totalAmount = 0;
  double totalProfit = 0;
  double totalBaseQuantity = 0;
  
  _ProductAggregation({
    required this.productName,
    this.productId,
    required this.productUnit,
    this.lengthPerUnit,
    this.unitHierarchy,
    this.unitCosts,
  });
}

class _CustomerAggregation {
  final int? customerId;
  final String customerName;
  final String? customerPhone;
  double totalAmount = 0;
  double totalProfit = 0;
  double totalBaseQuantity = 0;
  
  _CustomerAggregation({
    this.customerId,
    required this.customerName,
    this.customerPhone,
  });
}

// كلاس مساعد لتجميع بيانات السنة والشهور
class PersonYearDataBuilder {
  double totalSales = 0.0;
  double totalProfit = 0.0;
  int totalInvoices = 0;

  void addInvoice({required double sales, required double profit}) {
    totalSales += sales;
    totalProfit += profit;
    totalInvoices++;
  }
}
