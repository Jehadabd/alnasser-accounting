// services/reports_service.dart
// خدمة التقارير المتقدمة - منفصلة عن database_service لتخفيف الحمل
import 'invoice_edit_log.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:sqflite/sqflite.dart'; // ✅ Added for Sqflite.firstIntValue
import 'database_service.dart';
import 'settings_manager.dart';
import '../utils/money_calculator.dart';
import '../models/invoice.dart';
import '../models/transaction.dart';
import '../models/person_data.dart';
import '../models/analytics_data.dart';
import '../models/monthly_overview.dart';
import 'reports/cash_flow.dart';
import 'reports/currency_impact.dart';
import 'reports/sales_facts.dart';
import 'debt_return_service.dart';
export 'reports/cash_flow.dart' show CashFlow, DebtGroup;
export 'reports/currency_impact.dart' show CurrencyImpact, UsdProductImpact, UsdSupplierDebt;
export 'reports/sales_facts.dart' show SalesFacts, SalesTotals, ProductAgg, CustomerAgg, CategoryAgg, SalesInvoiceFact, SalesReturnFact, SalesItemFact, SalesItemKind, ReportSource, ReportCategory;

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
          costPerSoldUnit = productCost * lengthPerUnit;
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
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('🔍 تشخيص بند: ${productName ?? row['product_name'] ?? 'غير معروف'}');
      debugPrint('   نوع البيع: $saleType | وحدة المنتج: $productUnit');
      debugPrint('   الكمية: qi=$qi, ql=$ql, uilu=$uilu');
      debugPrint('   سعر البيع: $sellingPrice | إجمالي البند: $itemTotal');
      debugPrint('   تكلفة المنتج الأساسية: $productCost');
      debugPrint('   actualCostPerUnit: $actualCostPerUnit');
      debugPrint('   unitCosts: $unitCosts');
      debugPrint('   unitHierarchy: $unitHierarchyJson');
      debugPrint('   ─────────────────────────────────────────────────────────');
      debugPrint('   📊 النتيجة:');
      debugPrint('   مصدر التكلفة: $costSource');
      debugPrint('   تكلفة الوحدة المحسوبة: $costPerSoldUnit');
      debugPrint('   عدد الوحدات المباعة: $soldUnitsCount');
      debugPrint('   إجمالي التكلفة: $totalCost');
      debugPrint('   الربح: $profit ${profit < 0 ? "⚠️ سالب!" : "✅"}');
      debugPrint('═══════════════════════════════════════════════════════════');
    }

    return totalCost;
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
  // 📊 المحرك الموحّد (SalesFacts) — كل الأرقام أدناه مشتقة منه
  // ═══════════════════════════════════════════════════════════════════════════

  /// يحمّل وقائع المبيعات للفترة بقاعدة واحدة (انظر services/reports/sales_facts.dart).
  Future<SalesFacts> loadFacts({
    DateTime? from,
    DateTime? to,
    int? customerId,
    String? customerName,
    int? productId,
    String? productName,
    int? invoiceId,
  }) async {
    final db = await _db.database;
    final settings = await SettingsManager.getAppSettings();
    return SalesFacts.load(
      db,
      from: from,
      to: to,
      source: reportSourceFilter,
      customerId: customerId,
      customerName: customerName,
      productId: productId,
      productName: productName,
      invoiceId: invoiceId,
      adHocProfitPercentage: settings.defaultAdHocProfitPercentage,
    );
  }

  /// 💵 المقبوض والمدفوع نقداً وحركة الديون للفترة نفسها ([facts] من [loadFacts] بنفس الفترة).
  Future<CashFlow> cashFlow(SalesFacts facts, {required DateTime from, required DateTime to}) async {
    final db = await _db.database;
    return CashFlow.load(db, facts, from: from, to: to, source: reportSourceFilter);
  }

  /// 💱 أثر سعر الدولار في فترة (الديون، ديون الموردين بالدولار، مواد الشراء بالدولار).
  Future<CurrencyImpact> currencyImpact({required DateTime from, required DateTime to}) async {
    final db = await _db.database;
    return CurrencyImpact.load(db, from: from, to: to);
  }

  /// الديون والتسديدات اليدوية (غير المرتبطة بفاتورة) لكل يوم في الفترة.
  /// تتبع فلتر المصدر نفسه الذي تتبعه الفواتير (كانت «هذا الجهاز فقط» دائماً،
  /// فتُحسب فواتير كل الأجهزة مع ديون جهاز واحد).
  Future<Map<String, Map<String, double>>> _manualByDay(DateTime start, DateTime end) async {
    final db = await _db.database;
    // ↩️ «تسديد دين راجع» (مرتبط بجدول returns كما في debt_book) يُفصل عن التسديد العادي
    await DebtReturnService.ensureSchema(db);
    // ↩️ مرتجع المبيعات على الحساب (وإلغاؤه) يُعدّ «دين راجع» لا تسديداً نقدياً ولا ديناً يدوياً
    final isRet = await DebtReturnService.isReturnSqlFull(db, 'transactions');
    final rows = await db.rawQuery('''
      SELECT substr(transaction_date, 1, 10) AS d,
             SUM(CASE WHEN transaction_type IN ('manual_debt', 'opening_balance') AND NOT $isRet THEN 1 ELSE 0 END) AS debt_n,
             COALESCE(SUM(CASE WHEN transaction_type IN ('manual_debt', 'opening_balance') AND NOT $isRet THEN amount_changed ELSE 0 END), 0) AS debt_t,
             SUM(CASE WHEN transaction_type = 'manual_payment' AND NOT $isRet THEN 1 ELSE 0 END) AS pay_n,
             COALESCE(SUM(CASE WHEN transaction_type = 'manual_payment' AND NOT $isRet THEN ABS(amount_changed) ELSE 0 END), 0) AS pay_t,
             SUM(CASE WHEN $isRet THEN 1 ELSE 0 END) AS ret_n,
             COALESCE(SUM(CASE WHEN $isRet THEN -amount_changed ELSE 0 END), 0) AS ret_t
      FROM transactions
      WHERE substr(transaction_date, 1, 10) >= ? AND substr(transaction_date, 1, 10) <= ?
        AND transaction_type IN ('manual_debt', 'opening_balance', 'manual_payment')
        AND invoice_id IS NULL
        AND COALESCE(is_deleted, 0) = 0
        $_deviceFilter
      GROUP BY substr(transaction_date, 1, 10)
    ''', [SalesFacts.day(start), SalesFacts.day(end)]);
    return {
      for (final r in rows)
        '${r['d']}': {
          'debtCount': (r['debt_n'] as num?)?.toDouble() ?? 0,
          'debtTotal': (r['debt_t'] as num?)?.toDouble() ?? 0,
          'payCount': (r['pay_n'] as num?)?.toDouble() ?? 0,
          'payTotal': (r['pay_t'] as num?)?.toDouble() ?? 0,
          'retCount': (r['ret_n'] as num?)?.toDouble() ?? 0,
          'retTotal': (r['ret_t'] as num?)?.toDouble() ?? 0,
        }
    };
  }

  /// يدمج مجاميع المبيعات مع الديون اليدوية بصيغة getPeriodSummary.
  Map<String, dynamic> _summaryMap(SalesTotals t, Iterable<Map<String, double>> manual, double manualProfitPct,
      {double invoiceEdits = 0, int invoiceEditsCount = 0}) {
    var debtN = 0.0, debtT = 0.0, payN = 0.0, payT = 0.0, retN = 0.0, retT = 0.0;
    for (final m in manual) {
      debtN += m['debtCount'] ?? 0;
      debtT += m['debtTotal'] ?? 0;
      payN += m['payCount'] ?? 0;
      payT += m['payTotal'] ?? 0;
      retN += m['retCount'] ?? 0;
      retT += m['retTotal'] ?? 0;
    }
    return {
      ...t.toSummaryMap(),
      'manualDebtCount': debtN.toInt(),
      'totalManualDebt': debtT,
      'manualDebtProfit': debtT * manualProfitPct / 100.0,
      'manualPaymentCount': payN.toInt(),
      'totalManualPayment': payT,
      // ↩️ تسديد دين راجع (بضاعة رجعت بدل النقد) — خارج «تسديد دين» كما في debt_book
      'manualPaymentReturnCount': retN.toInt(),
      'totalManualPaymentReturn': retT,
      // تخفيضات فواتير بعد حفظها (مطابقة الصندوق) — للعرض فقط: مبلغها منقوص من
      // total_amount أصلاً، فلا يُطرح مرة ثانية من المبيعات.
      'invoiceEditsReduction': invoiceEdits,
      'invoiceEditsCount': invoiceEditsCount,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // أفضل المنتجات والعملاء في فترة معينة
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _productRow(ProductAgg p) => {
        'product_name': p.name,
        'product_id': p.productId,
        'category_id': p.categoryId,
        'total_sales': p.netRevenue,
        'gross_sales': p.revenue,
        'total_cost': p.netCost,
        'total_profit': p.profit,
        'profit_margin': p.margin,
        'total_quantity': p.netQty,
        'base_unit': p.baseUnit,
        'invoice_count': p.invoiceCount,
        'customer_count': p.customerCount,
        'returned_quantity': p.returnedQty,
        'returned_sales': p.returnedRevenue,
      };

  /// أفضل المنتجات مبيعاً في فترة معينة (الكمية بالوحدة الأساسية: قطعة/متر).
  Future<List<Map<String, dynamic>>> getTopProductsInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final facts = await loadFacts(from: startDate, to: endDate);
    final list = facts.byProduct()..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
    return [for (final p in list.take(limit)) _productRow(p)];
  }

  /// أفضل المنتجات ربحاً في فترة معينة.
  Future<List<Map<String, dynamic>>> getTopProductsByProfitInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final facts = await loadFacts(from: startDate, to: endDate);
    final list = facts.byProduct()..sort((a, b) => b.profit.compareTo(a.profit));
    return [for (final p in list.take(limit)) _productRow(p)];
  }

  Future<List<Map<String, dynamic>>> _customerRows(SalesFacts facts, {int limit = 10, bool byProfit = false}) async {
    final list = facts.byCustomer()
      ..sort((a, b) => byProfit
          ? b.totals.profit.compareTo(a.totals.profit)
          : b.totals.netSales.compareTo(a.totals.netSales));
    final top = list.take(limit).toList();
    final ids = top.map((c) => c.customerId).whereType<int>().where((id) => id > 0).toList();
    final phones = <int, String?>{};
    if (ids.isNotEmpty) {
      final db = await _db.database;
      final rows = await db.rawQuery(
          'SELECT id, phone FROM customers WHERE id IN (${List.filled(ids.length, '?').join(',')})', ids);
      for (final r in rows) {
        phones[(r['id'] as num).toInt()] = r['phone'] as String?;
      }
    }
    return [
      for (final c in top)
        {
          'customer_id': c.customerId,
          'customer_name': c.name,
          'customer_phone': c.customerId == null ? null : phones[c.customerId],
          'total_purchases': c.totals.netSales,
          'gross_purchases': c.totals.sales,
          'total_profit': c.totals.profit,
          'invoice_count': c.totals.invoiceCount,
          'returns': c.totals.totalReturns,
        }
    ];
  }

  /// أفضل العملاء شراءً في فترة معينة (حسب المعرّف لا الاسم).
  Future<List<Map<String, dynamic>>> getTopCustomersInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final facts = await loadFacts(from: startDate, to: endDate);
    return _customerRows(facts, limit: limit);
  }

  /// أفضل العملاء ربحاً في فترة معينة.
  Future<List<Map<String, dynamic>>> getTopCustomersByProfitInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final facts = await loadFacts(from: startDate, to: endDate);
    return _customerRows(facts, limit: limit, byProfit: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ملخص فترة + المقارنة
  // ═══════════════════════════════════════════════════════════════════════════

  /// ملخص فترة — المرجع الوحيد لأرقام المبيعات والربح في كل التقارير.
  /// المفاتيح القديمة كما هي، والجديدة إضافة (grossSales، totalDiscount، salesReturns …).
  Future<Map<String, dynamic>> getPeriodSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final facts = await loadFacts(from: startDate, to: endDate);
    return _summaryForFacts(facts, startDate, endDate);
  }

  Future<Map<String, dynamic>> _summaryForFacts(SalesFacts facts, DateTime startDate, DateTime endDate,
      {SalesTotals? totals}) async {
    final settings = await SettingsManager.getAppSettings();
    final manual = await _manualByDay(startDate, endDate);
    final edits = await getCashReturnsInPeriod(startDate: startDate, endDate: endDate);
    final editsTotal = edits.fold<double>(0, (s, e) => s + ((e['amount_returned'] as num?)?.toDouble() ?? 0));
    final m = _summaryMap(totals ?? facts.totals(), manual.values, settings.manualDebtProfitPercentage,
        invoiceEdits: editsTotal, invoiceEditsCount: edits.length);
    // ↩️ مرتجعات بتعديل الفواتير (للعرض فقط: منقوصة من المبيعات أصلاً)
    final editReturns = await InvoiceEditLog.returnsInPeriod(await _db.database,
        from: startDate, to: endDate, invoiceFilter: _deviceFilter.replaceAll('is_created_by_me', 'i.is_created_by_me'));
    m['editReturns'] = editReturns.fold<double>(0, (s, r) => s + InvoiceEditLog.returnedAmount(r));
    m['editReturnsCount'] = editReturns.length;
    return m;
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
    return _comparison(current, previous);
  }

  Map<String, dynamic> _comparison(Map<String, dynamic> current, Map<String, dynamic> previous) {
    double calcChange(num? curr, num? prev) {
      final c = (curr ?? 0).toDouble();
      final p = (prev ?? 0).toDouble();
      if (p == 0) return c > 0 ? 100.0 : 0.0;
      return ((c - p) / p.abs()) * 100;
    }

    return {
      'current': current,
      'previous': previous,
      'changes': {
        'salesChange': calcChange(current['totalSales'], previous['totalSales']),
        'profitChange': calcChange(current['netProfit'], previous['netProfit']),
        'invoiceCountChange': calcChange(current['invoiceCount'] as num?, previous['invoiceCount'] as num?),
        'cashSalesChange': calcChange(current['cashSales'], previous['cashSales']),
        'creditSalesChange': calcChange(current['creditSales'], previous['creditSales']),
        'returnsChange': calcChange(current['totalReturns'], previous['totalReturns']),
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
        c.address,
        c.current_total_debt,
        (
          -- آخر تسديد بأي طريقة (يدوي، وصل قبض، مرتجع…): كل حركة تُنقص الدين
          SELECT MAX(transaction_date)
          FROM transactions t
          WHERE t.customer_id = c.id AND t.amount_changed < 0
            AND COALESCE(t.is_deleted, 0) = 0 ${_deviceFilterFor('t.')}
        ) as last_payment_date,
        (
          SELECT MAX(transaction_date)
          FROM transactions t
          WHERE t.customer_id = c.id AND t.amount_changed > 0
            AND COALESCE(t.is_deleted, 0) = 0 ${_deviceFilterFor('t.')}
        ) as last_debt_date,
        (
          SELECT MAX(transaction_date)
          FROM transactions t
          WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0 ${_deviceFilterFor('t.')}
        ) as last_transaction_date
      FROM customers c
      WHERE c.current_total_debt > ? AND COALESCE(c.is_deleted, 0) = 0
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
  // المبيعات اليومية والاتجاه
  // ═══════════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> _dailyRows(SalesFacts facts) {
    final days = facts.byDay();
    final keys = days.keys.toList()..sort();
    return [
      for (final k in keys)
        {
          'date': k,
          'invoice_count': days[k]!.invoiceCount,
          'total_sales': days[k]!.sales,
          'total_cost': days[k]!.cost,
          'net_profit': days[k]!.profit,
          'returns': days[k]!.totalReturns,
          'cash_sales': days[k]!.cashSales,
          'credit_sales': days[k]!.creditSales,
        }
    ];
  }

  /// المبيعات اليومية خلال فترة (للرسم البياني) — أيام فيها حركة فقط.
  /// total_sales = مجموع إجمالي الفواتير (نفس رقم الملخص)، net_profit = ربح اليوم الصافي.
  Future<List<Map<String, dynamic>>> getDailySalesInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final facts = await loadFacts(from: startDate, to: endDate);
    return _dailyRows(facts);
  }

  /// تحليل اتجاه المبيعات (صاعد/هابط/مستقر)
  Future<Map<String, dynamic>> analyzeSalesTrend({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dailySales = await getDailySalesInPeriod(startDate: startDate, endDate: endDate);
    return _trendFromDaily(dailySales);
  }

  Map<String, dynamic> _trendFromDaily(List<Map<String, dynamic>> dailySales) {
    if (dailySales.length < 2) {
      return {
        'trend': 'insufficient_data',
        'trendArabic': 'بيانات غير كافية',
        'averageDailySales': 0.0,
        'totalDays': dailySales.length,
        'changePercent': 0.0,
      };
    }
    double sales(Map<String, dynamic> d) => (d['total_sales'] as num?)?.toDouble() ?? 0;
    final total = dailySales.fold<double>(0, (s, d) => s + sales(d));
    final avg = total / dailySales.length;
    final mid = dailySales.length ~/ 2;
    var first = 0.0, second = 0.0;
    for (var i = 0; i < dailySales.length; i++) {
      if (i < mid) {
        first += sales(dailySales[i]);
      } else {
        second += sales(dailySales[i]);
      }
    }
    final firstAvg = first / mid;
    final secondAvg = second / (dailySales.length - mid);
    final change = firstAvg > 0 ? ((secondAvg - firstAvg) / firstAvg) * 100 : 0.0;
    final (trend, ar) = change > 10
        ? ('increasing', 'صاعد ↑')
        : (change < -10 ? ('decreasing', 'هابط ↓') : ('stable', 'مستقر →'));
    return {
      'trend': trend,
      'trendArabic': ar,
      'changePercent': change,
      'averageDailySales': avg,
      'totalDays': dailySales.length,
      'firstHalfAvg': firstAvg,
      'secondHalfAvg': secondAvg,
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
  
  /// تقرير شهري شامل — قراءة واحدة للشهر وواحدة للشهر السابق (كان يقرأ الشهر 5 مرات).
  Future<Map<String, dynamic>> getMonthlyDetailedReport({
    required int year,
    required int month,
  }) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0);
    final prevStartDate = DateTime(year, month - 1, 1);
    final prevEndDate = DateTime(year, month, 0);

    final facts = await loadFacts(from: startDate, to: endDate);
    final prevFacts = await loadFacts(from: prevStartDate, to: prevEndDate);
    final totals = facts.totals();
    final summary = await _summaryForFacts(facts, startDate, endDate, totals: totals);
    final prevSummary = await _summaryForFacts(prevFacts, prevStartDate, prevEndDate);

    final products = facts.byProduct();
    final topProducts = [
      for (final p in (List.of(products)..sort((a, b) => b.netRevenue.compareTo(a.netRevenue))).take(10)) _productRow(p)
    ];
    final topProductsByProfit = [
      for (final p in (List.of(products)..sort((a, b) => b.profit.compareTo(a.profit))).take(10)) _productRow(p)
    ];
    final topCustomers = await _customerRows(facts, limit: 10);
    final topCustomersByProfit = await _customerRows(facts, limit: 10, byProfit: true);
    final newCustomers = await getNewCustomersInPeriod(startDate: startDate, endDate: endDate);
    final rawDaily = _dailyRows(facts);
    final trend = _trendFromDaily(rawDaily);

    final byDay = {for (final d in rawDaily) d['date'] as String: d};
    final fullMonthDailySales = <Map<String, dynamic>>[];
    for (var day = 1; day <= endDate.day; day++) {
      final dayDate = DateTime(year, month, day);
      final key = SalesFacts.day(dayDate);
      final d = byDay[key];
      final sales = (d?['total_sales'] as num?)?.toDouble() ?? 0.0;
      final cost = (d?['total_cost'] as num?)?.toDouble() ?? 0.0;
      final profit = (d?['net_profit'] as num?)?.toDouble() ?? 0.0;
      final count = (d?['invoice_count'] as num?)?.toInt() ?? 0;
      fullMonthDailySales.add({
        'date': key,
        'dateFormatted': '$day/$month/$year',
        'dayNumber': day,
        'total_sales': sales,
        'total_cost': cost,
        'totalSales': sales,
        'totalCost': cost,
        'netProfit': profit,
        'returns': (d?['returns'] as num?)?.toDouble() ?? 0.0,
        'invoice_count': count,
        'invoiceCount': count,
        'cash_sales': (d?['cash_sales'] as num?)?.toDouble() ?? 0.0,
        'credit_sales': (d?['credit_sales'] as num?)?.toDouble() ?? 0.0,
      });
    }

    final snapshotReturns = await _getSnapshotReturns(startDate, endDate, exclusionStartDate: startDate);
    final totalSales = (summary['totalSales'] as num).toDouble();

    return {
      'totalReturns': snapshotReturns, // تخفيضات فواتير أشهر سابقة عُدّلت هذا الشهر (مطابقة الصندوق)
      'year': year,
      'month': month,
      'summary': summary,
      'comparison': _comparison(summary, prevSummary),
      'topProducts': topProducts,
      'topProductsByProfit': topProductsByProfit,
      'topCustomers': topCustomers,
      'topCustomersByProfit': topCustomersByProfit,
      'newCustomers': newCustomers,
      'newCustomersCount': newCustomers.length,
      'trend': trend,
      'dailySales': fullMonthDailySales,
      'profitPercent': totalSales > 0 ? totals.profit / totalSales * 100 : 0.0,
      'categoryBreakdown': await _categoryRows(facts, limit: 200),
      'paymentBreakdown': facts.byPayment(),
    };
  }

  /// تقرير سنوي شامل — قراءة واحدة للسنة وواحدة للسنة السابقة
  /// (كان يستدعي ملخص الفترة أكثر من 66 مرة).
  Future<Map<String, dynamic>> getYearlyReport({required int year}) async {
    final startDate = DateTime(year, 1, 1);
    final endDate = DateTime(year, 12, 31);
    final prevStartDate = DateTime(year - 1, 1, 1);
    final prevEndDate = DateTime(year - 1, 12, 31);

    final facts = await loadFacts(from: startDate, to: endDate);
    final prevFacts = await loadFacts(from: prevStartDate, to: prevEndDate);
    final totals = facts.totals();
    final summary = await _summaryForFacts(facts, startDate, endDate, totals: totals);
    final prevSummary = await _summaryForFacts(prevFacts, prevStartDate, prevEndDate);
    final settings = await SettingsManager.getAppSettings();
    final manual = await _manualByDay(startDate, endDate);

    final products = facts.byProduct()..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
    final topProducts = [for (final p in products.take(20)) _productRow(p)];
    final topCustomers = await _customerRows(facts, limit: 20);
    final newCustomers = await getNewCustomersInPeriod(startDate: startDate, endDate: endDate);
    final snapshotReturns = await _getSnapshotReturns(startDate, endDate, exclusionStartDate: startDate);

    // الأشهر
    final months = facts.byMonth();
    final monthlySales = <Map<String, dynamic>>[];
    for (var m = 1; m <= 12; m++) {
      final key = '$year-${m.toString().padLeft(2, '0')}';
      final t = months[key] ?? SalesTotals();
      final man = [
        for (final e in manual.entries)
          if (e.key.startsWith(key)) e.value
      ];
      monthlySales.add({'month': m, 'monthName': _getArabicMonthName(m), ..._summaryMap(t, man, settings.manualDebtProfitPercentage)});
    }

    // الأسابيع (52 أسبوعاً من 1 كانون الثاني؛ الأيام الأخيرة تدخل الأسبوع 52)
    final weekTotals = List.generate(52, (_) => SalesTotals());
    final weekManual = List.generate(52, (_) => <Map<String, double>>[]);
    int weekIndex(DateTime d) {
      final doy = DateTime(d.year, d.month, d.day).difference(startDate).inDays;
      return (doy ~/ 7).clamp(0, 51).toInt();
    }

    for (final i in facts.invoices) {
      weekTotals[weekIndex(i.date)].addInvoice(i);
    }
    for (final r in facts.returns) {
      weekTotals[weekIndex(r.date)].addReturn(r);
    }
    for (final e in facts.edits) {
      weekTotals[weekIndex(e.date)].addEdit(e);
    }
    for (final e in manual.entries) {
      final d = DateTime.tryParse(e.key);
      if (d != null) weekManual[weekIndex(d)].add(e.value);
    }
    final weeklySales = [
      for (var w = 0; w < 52; w++)
        {'week': w + 1, 'weekName': 'أسبوع ${w + 1}', ..._summaryMap(weekTotals[w], weekManual[w], settings.manualDebtProfitPercentage)}
    ];

    // الأيام (السنة كاملة)
    final days = facts.byDay();
    final dailyFullYear = <Map<String, dynamic>>[];
    final totalDays = DateTime(year + 1, 1, 1).difference(startDate).inDays;
    for (var d = 0; d < totalDays; d++) {
      final cur = startDate.add(Duration(days: d));
      final key = SalesFacts.day(cur);
      final t = days[key];
      dailyFullYear.add({
        'dayIndex': d,
        'dateStr': key,
        'dayNum': cur.day,
        'monthNum': cur.month,
        'dateFormatted': '${cur.day}/${cur.month}/${cur.year}',
        'monthName': _getArabicMonthName(cur.month),
        'totalSales': t?.sales ?? 0.0,
        'totalCost': t?.cost ?? 0.0,
        'netProfit': t?.profit ?? 0.0,
        'returns': t?.totalReturns ?? 0.0,
        'invoiceCount': t?.invoiceCount ?? 0,
      });
    }

    final totalSales = (summary['totalSales'] as num).toDouble();
    return {
      'totalReturns': snapshotReturns,
      'year': year,
      'summary': summary,
      'comparison': _comparison(summary, prevSummary),
      'topProducts': topProducts,
      'topCustomers': topCustomers,
      'newCustomersCount': newCustomers.length,
      'profitPercent': totalSales > 0 ? totals.profit / totalSales * 100 : 0.0,
      'monthlySales': monthlySales,
      'weeklySales': weeklySales,
      'dailySales': dailyFullYear,
      'categoryBreakdown': await _categoryRows(facts, limit: 200),
      // كان يُقرأ من final_total الذي لا يكتبه البرنامج فيخرج أصفاراً
      'paymentBreakdown': facts.byPayment(),
    };
  }

  /// المبيعات اليومية لشهر معين في السنة — قراءة واحدة بدل ملخص لكل يوم.
  Future<List<Map<String, dynamic>>> getDailySalesForMonth({required int year, required int month}) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0);
    final facts = await loadFacts(from: start, to: end);
    final settings = await SettingsManager.getAppSettings();
    final manual = await _manualByDay(start, end);
    final days = facts.byDay();
    final out = <Map<String, dynamic>>[];
    for (var d = 1; d <= end.day; d++) {
      final key = SalesFacts.day(DateTime(year, month, d));
      out.add({
        'day': d,
        'dayName': 'يوم $d',
        'dateStr': key,
        ..._summaryMap(days[key] ?? SalesTotals(), [if (manual[key] != null) manual[key]!],
            settings.manualDebtProfitPercentage),
      });
    }
    return out;
  }

  /// الأقسام الجذرية (الفرعي يُجمع تحت أبيه) — للتقارير الدورية.
  Future<List<Map<String, dynamic>>> _categoryRows(SalesFacts facts, {int limit = 10}) async {
    final cats = await getCategories();
    final names = {for (final c in cats) c.id: c.name};
    final parents = {for (final c in cats) c.id: c.parentId};
    final list = facts.byCategory(names, parents: parents, rollupToRoot: true)
      ..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
    return [
      for (final c in list.take(limit))
        {
          'category_id': c.categoryId,
          'category_name': c.categoryId == null ? 'عام / غير تصنيف' : c.name,
          'invoice_count': c.invoiceCount,
          'total_sales': c.netRevenue,
          'total_profit': c.profit,
          'total_quantity': c.baseQty,
          'product_count': c.productCount,
        }
    ];
  }

  /// كل الأقسام (للاختيار في تقارير البضاعة).
  Future<List<ReportCategory>> getCategories() async {
    try {
      final db = await _db.database;
      final rows = await db.rawQuery('''
        SELECT c.id, c.name, c.parent_id,
               (SELECT COUNT(*) FROM products p WHERE p.category_id = c.id) AS n
        FROM categories c ORDER BY c.name''');
      return [
        for (final r in rows)
          ReportCategory(
            id: (r['id'] as num).toInt(),
            name: (r['name'] as String?) ?? '',
            parentId: (r['parent_id'] as num?)?.toInt(),
            productCount: (r['n'] as num?)?.toInt() ?? 0,
          )
      ];
    } catch (_) {
      return const [];
    }
  }

  /// ملخص كل شهر لآخر [months] شهراً (للجرد الشهري) — قراءة واحدة بدل 24.
  Future<Map<String, MonthlyOverview>> getMonthlyOverviews({int months = 24}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - (months - 1), 1);
    final end = DateTime(now.year, now.month + 1, 0);
    final facts = await loadFacts(from: start, to: end);
    final settings = await SettingsManager.getAppSettings();
    final manual = await _manualByDay(start, end);
    final byMonth = facts.byMonth();
    final out = <String, MonthlyOverview>{};
    for (var i = 0; i < months; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      final key = SalesFacts.monthKey(d);
      final t = byMonth[key] ?? SalesTotals();
      final man = [
        for (final e in manual.entries)
          if (e.key.startsWith(key)) e.value
      ];
      final s = _summaryMap(t, man, settings.manualDebtProfitPercentage);
      if (t.invoiceCount == 0 &&
          (s['manualDebtCount'] as int) == 0 &&
          (s['manualPaymentCount'] as int) == 0 &&
          (s['manualPaymentReturnCount'] as int) == 0 &&
          t.salesReturnsCount == 0) {
        continue;
      }
      out[key] = MonthlyOverview(
        monthYear: key,
        totalSales: t.sales,
        netProfit: t.profit,
        totalCost: t.cost,
        cashSales: t.cashSales,
        creditSales: t.creditSales,
        totalReturns: t.totalReturns,
        totalDebtPayments: (s['totalManualPayment'] as num).toDouble(),
        totalManualDebt: (s['totalManualDebt'] as num).toDouble(),
        manualDebtProfit: (s['manualDebtProfit'] as num).toDouble(),
        settlementAdditions: 0,
        settlementReturns: 0,
        invoiceCount: t.invoiceCount,
        manualDebtCount: s['manualDebtCount'] as int,
        manualPaymentCount: s['manualPaymentCount'] as int,
        totalManualPaymentReturn: (s['totalManualPaymentReturn'] as num).toDouble(),
        manualPaymentReturnCount: s['manualPaymentReturnCount'] as int,
      );
    }
    return out;
  }

  /// اسم الشهر بالأرقام («شهر 10») كما في بقية البرنامج.
  String _getArabicMonthName(int month) => 'شهر $month';


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
    
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════════════════════════════════╗');
    debugPrint('║  🔍 تشخيص مشكلة التكلفة - ${_getArabicMonthName(month)} $year');
    debugPrint('╚═══════════════════════════════════════════════════════════════════╝');
    debugPrint('');
    
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
        debugPrint('');
        debugPrint('📄 فاتورة #$invoiceId - $customerName');
        debugPrint('   المبيعات: $totalAmount | التكلفة: $invoiceCost | الربح: $profit');
        debugPrint('');
      }
    }
    
    // ملخص التشخيص
    final grandProfit = grandTotalSales - grandTotalCost;
    final profitPercent = grandTotalSales > 0 ? (grandProfit / grandTotalSales) * 100 : 0.0;
    
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════════════════════════════════╗');
    debugPrint('║  📊 ملخص التشخيص');
    debugPrint('╠═══════════════════════════════════════════════════════════════════╣');
    debugPrint('║  عدد الفواتير: ${invoices.length}');
    debugPrint('║  عدد البنود الإجمالي: $totalItems');
    debugPrint('║  عدد البنود المشكلة: $problemItems');
    debugPrint('║  ─────────────────────────────────────────────────────────────────');
    debugPrint('║  إجمالي المبيعات: $grandTotalSales');
    debugPrint('║  إجمالي التكلفة: $grandTotalCost');
    debugPrint('║  صافي الربح: $grandProfit');
    debugPrint('║  نسبة الربح: ${profitPercent.toStringAsFixed(1)}%');
    debugPrint('╠═══════════════════════════════════════════════════════════════════╣');
    
    if (problemProducts.isNotEmpty) {
      debugPrint('║  🚨 المنتجات الأكثر مشاكل:');
      final sorted = problemProducts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var i = 0; i < sorted.length && i < 10; i++) {
        debugPrint('║     ${i + 1}. ${sorted[i].key}: ${sorted[i].value} مرة');
      }
    }
    
    debugPrint('╚═══════════════════════════════════════════════════════════════════╝');
    debugPrint('');
    
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
    
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════════════════════════════════╗');
    debugPrint('║  🔍 تشخيص منتج: $productName');
    debugPrint('╚═══════════════════════════════════════════════════════════════════╝');
    
    // جلب بيانات المنتج
    final products = await db.query('products', where: 'name = ?', whereArgs: [productName]);
    if (products.isEmpty) {
      debugPrint('❌ المنتج غير موجود في قاعدة البيانات!');
      return;
    }
    
    final product = products.first;
    debugPrint('');
    debugPrint('📦 بيانات المنتج:');
    debugPrint('   الوحدة: ${product['unit']}');
    debugPrint('   تكلفة الوحدة: ${product['cost_price']}');
    debugPrint('   unit_costs: ${product['unit_costs']}');
    debugPrint('   unit_hierarchy: ${product['unit_hierarchy']}');
    debugPrint('');
    
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
    
    debugPrint('📋 آخر ${items.length} فاتورة تحتوي على هذا المنتج:');
    debugPrint('');
    
    for (final item in items) {
      _calculateItemCostWithDebug(item, enableDebug: true, productName: productName);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تفصيل منتجات عميل / عملاء منتج (من المحرك الموحّد)
  // ═══════════════════════════════════════════════════════════════════════════

  (DateTime, DateTime) _yearMonthRange(int year, int? month) => month == null
      ? (DateTime(year, 1, 1), DateTime(year, 12, 31))
      : (DateTime(year, month, 1), DateTime(year, month + 1, 0));

  Future<Map<int, Map<String, Object?>>> _productsById(Iterable<int> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final db = await _db.database;
    final rows = await db.rawQuery(
        'SELECT id, name, unit, length_per_unit, unit_hierarchy FROM products WHERE id IN (${List.filled(list.length, '?').join(',')})',
        list);
    return {for (final r in rows) (r['id'] as num).toInt(): r};
  }

  /// تفصيل المنتجات المشتراة من عميل معين في سنة أو شهر محدد
  /// يُرجع قائمة بالمنتجات مع المبلغ والربح والكمية بالوحدات الهرمية
  Future<List<CustomerProductBreakdown>> getCustomerProductsBreakdown({
    required int customerId,
    required int year,
    int? month,
  }) async {
    final (from, to) = _yearMonthRange(year, month);
    final facts = await loadFacts(from: from, to: to, customerId: customerId);
    final aggs = facts.byProduct();
    final products = await _productsById(aggs.map((a) => a.productId).whereType<int>());
    final results = [
      for (final a in aggs)
        CustomerProductBreakdown(
          productName: a.name,
          productId: a.productId,
          totalAmount: a.netRevenue,
          totalProfit: a.profit,
          baseQuantity: a.netQty,
          baseUnit: a.baseUnit,
          quantityFormatted: _formatQuantityWithHierarchy(
            a.netQty,
            (products[a.productId]?['unit'] as String?) ?? (a.baseUnit == 'متر' ? 'meter' : 'piece'),
            (products[a.productId]?['length_per_unit'] as num?)?.toDouble(),
            products[a.productId]?['unit_hierarchy'] as String?,
          ),
        )
    ]..sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
    return results;
  }

  /// تفصيل العملاء الذين اشتروا منتج معين في سنة أو شهر محدد
  Future<List<ProductCustomerBreakdown>> getProductCustomersBreakdown({
    required int productId,
    required int year,
    int? month,
  }) async {
    final db = await _db.database;
    final productData = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (productData.isEmpty) return [];
    final product = productData.first;
    final productUnit = (product['unit'] as String?) ?? 'piece';
    final lengthPerUnit = (product['length_per_unit'] as num?)?.toDouble();
    final unitHierarchy = product['unit_hierarchy'] as String?;

    final (from, to) = _yearMonthRange(year, month);
    final facts = await loadFacts(from: from, to: to, productId: productId);
    final invById = {for (final i in facts.invoices) i.id: i};

    final map = <String, ({int? id, String name, double amount, double profit, double qty})>{};
    void add(int? id, String name, double amount, double profit, double qty) {
      final key = id != null && id > 0 ? 'id:$id' : 'n:$name';
      final cur = map[key];
      map[key] = (
        id: id,
        name: name,
        amount: (cur?.amount ?? 0) + amount,
        profit: (cur?.profit ?? 0) + profit,
        qty: (cur?.qty ?? 0) + qty,
      );
    }

    for (final it in facts.saleItems) {
      final inv = invById[it.invoiceId];
      if (inv == null) continue;
      add(inv.customerId, inv.customerName, it.revenue, it.profit, it.baseQty);
    }
    for (final r in facts.returns) {
      for (final it in r.items) {
        add(r.customerId, r.customerName, -it.revenue, -(it.revenue - it.cost), -it.baseQty);
      }
    }
    final ids = map.values.map((v) => v.id).whereType<int>().where((i) => i > 0).toList();
    final phones = <int, String?>{};
    if (ids.isNotEmpty) {
      final rows = await db.rawQuery(
          'SELECT id, phone FROM customers WHERE id IN (${List.filled(ids.length, '?').join(',')})', ids);
      for (final r in rows) {
        phones[(r['id'] as num).toInt()] = r['phone'] as String?;
      }
    }
    final results = [
      for (final v in map.values)
        ProductCustomerBreakdown(
          customerId: v.id,
          customerName: v.name,
          customerPhone: v.id == null ? null : phones[v.id],
          totalAmount: v.amount,
          totalProfit: v.profit,
          baseQuantity: v.qty,
          baseUnit: productUnit == 'meter' ? 'متر' : 'قطعة',
          quantityFormatted: _formatQuantityWithHierarchy(v.qty, productUnit, lengthPerUnit, unitHierarchy),
        )
    ]..sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
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
  
  /// تنسيق الأرقام
  String _formatNumber(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 تقارير المنتجات (Product Reports) — من المحرك الموحّد
  // ═══════════════════════════════════════════════════════════════════════════

  /// الملخص الشامل لمنتج (كل الفترات). الكمية بالوحدة الأساسية (قطعة/متر)
  /// — كانت تجمع الكراتين والقطع معاً.
  Future<Map<String, dynamic>> getProductSalesData(int productId) async {
    final facts = await loadFacts(productId: productId);
    final aggs = facts.byProduct();
    double sales = 0, cost = 0, qty = 0, gross = 0, returnedQty = 0, returned = 0;
    var invoices = 0;
    String unit = 'قطعة';
    for (final a in aggs) {
      sales += a.netRevenue;
      gross += a.revenue;
      cost += a.netCost;
      qty += a.netQty;
      returnedQty += a.returnedQty;
      returned += a.returnedRevenue;
      invoices += a.invoiceCount;
      unit = a.baseUnit;
    }
    final profit = sales - cost;
    return {
      'totalSales': sales,
      'totalProfit': profit,
      'totalQuantity': qty,
      'averageSellingPrice': qty > 0 ? gross / (qty + returnedQty) : 0.0,
      'totalCost': cost,
      'profitMargin': sales > 0 ? profit / sales * 100 : 0.0,
      'baseUnit': unit,
      'invoiceCount': invoices,
      'returnedQuantity': returnedQty,
      'returnedSales': returned,
    };
  }

  Future<Map<int, ({double qty, double sales, double profit})>> _productByYear(int productId, {int? year}) async {
    final facts = year == null
        ? await loadFacts(productId: productId)
        : await loadFacts(productId: productId, from: DateTime(year, 1, 1), to: DateTime(year, 12, 31));
    final out = <int, ({double qty, double sales, double profit})>{};
    void add(int k, double q, double s, double p) {
      final c = out[k];
      out[k] = (qty: (c?.qty ?? 0) + q, sales: (c?.sales ?? 0) + s, profit: (c?.profit ?? 0) + p);
    }

    for (final it in facts.saleItems) {
      add(year == null ? it.date.year : it.date.month, it.baseQty, it.revenue, it.profit);
    }
    for (final it in facts.returnItems) {
      add(year == null ? it.date.year : it.date.month, -it.baseQty, -it.revenue, -(it.revenue - it.cost));
    }
    return out;
  }

  /// الكمية المباعة سنوياً لمنتج (بالوحدة الأساسية).
  Future<Map<int, double>> getProductYearlySales(int productId) async {
    final m = await _productByYear(productId);
    return {for (final e in m.entries) e.key: e.value.qty};
  }

  /// الأرباح السنوية لمنتج.
  Future<Map<int, double>> getProductYearlyProfit(int productId) async {
    final m = await _productByYear(productId);
    return {for (final e in m.entries) e.key: e.value.profit};
  }

  /// الكمية المباعة شهرياً لمنتج في سنة (بالوحدة الأساسية).
  Future<Map<int, double>> getProductMonthlySales(int productId, int year) async {
    final m = await _productByYear(productId, year: year);
    return {for (final e in m.entries) e.key: e.value.qty};
  }

  /// الأرباح الشهرية لمنتج في سنة.
  Future<Map<int, double>> getProductMonthlyProfit(int productId, int year) async {
    final m = await _productByYear(productId, year: year);
    return {for (final e in m.entries) e.key: e.value.profit};
  }

  /// قيمة مبيعات المنتج شهرياً في سنة (جديد: كانت الشاشات تعرض الكمية فقط).
  Future<Map<int, double>> getProductMonthlyRevenue(int productId, int year) async {
    final m = await _productByYear(productId, year: year);
    return {for (final e in m.entries) e.key: e.value.sales};
  }

  /// تفاصيل فواتير منتج في شهر معين — سطر لكل فاتورة (بنود المادة فيها مجمّعة).
  Future<List<ProductInvoiceAnalytics>> getProductInvoicesForMonth(int productId, int year, int month) async {
    final facts = await loadFacts(productId: productId, from: DateTime(year, month, 1), to: DateTime(year, month + 1, 0));
    if (facts.invoices.isEmpty) return [];
    final db = await _db.database;
    final ids = facts.invoices.map((i) => i.id).toList();
    final rows = await db.rawQuery(
        'SELECT * FROM invoices WHERE id IN (${List.filled(ids.length, '?').join(',')})', ids);
    final invoiceById = {for (final r in rows) (r['id'] as num).toInt(): Invoice.fromMap(r)};
    final out = <ProductInvoiceAnalytics>[];
    for (final f in facts.invoices.reversed) {
      final inv = invoiceById[f.id];
      if (inv == null || f.items.isEmpty) continue;
      var base = 0.0, sold = 0.0, revenue = 0.0, cost = 0.0;
      for (final it in f.items) {
        base += it.baseQty;
        sold += it.soldQty;
        revenue += it.revenue;
        cost += it.cost;
      }
      out.add(ProductInvoiceAnalytics(
        invoice: inv,
        quantitySold: base,
        saleUnitsCount: sold,
        profit: revenue - cost,
        sellingPrice: f.items.first.unitPrice,
        unitCostAtSale: base > 0 ? cost / base : 0.0,
      ));
    }
    return out;
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
  // 👤 تقارير العملاء — من المحرك الموحّد (السنة = مجموع أشهرها = مجموع فواتيرها)
  // ═══════════════════════════════════════════════════════════════════════════

  /// الملخص المالي لعميل (أرباح، مبيعات، فواتير) — كل الفترات.
  Future<Map<String, dynamic>> getCustomerProfitData(int customerId) async {
    try {
      final facts = await loadFacts(customerId: customerId);
      final t = facts.totals();
      final db = await _db.database;
      final tx = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM transactions WHERE customer_id = ? $_deviceFilter', [customerId]);
      final qty = facts.saleItems.fold<double>(0, (s, i) => s + i.baseQty);
      final revenue = facts.saleItems.fold<double>(0, (s, i) => s + i.revenue);
      return {
        'totalProfit': t.profit,
        'totalSales': t.sales,
        'netSales': t.netSales,
        'totalCost': t.cost,
        'totalReturns': t.totalReturns,
        'profitMargin': t.margin,
        'totalInvoices': t.invoiceCount,
        'totalInvoicesGlobal': t.invoiceCount,
        'totalTransactions': (tx.first['n'] as num?)?.toInt() ?? 0,
        'averageSellingPrice': qty > 0 ? revenue / qty : 0.0,
        'totalQuantity': qty,
        'lastInvoiceDate': facts.invoices.isEmpty ? null : facts.invoices.last.date.toIso8601String(),
      };
    } catch (e) {
      throw Exception('Failed to fetch customer summary: $e');
    }
  }

  Future<Map<String, int>> _customerTxCount(int customerId, String fmt, {int? year}) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT strftime('$fmt', transaction_date) AS k, COUNT(*) AS n
      FROM transactions
      WHERE customer_id = ? ${year == null ? '' : "AND strftime('%Y', transaction_date) = ?"}
      GROUP BY k
    ''', [customerId, if (year != null) year.toString()]);
    return {for (final r in rows) '${r['k']}': (r['n'] as num?)?.toInt() ?? 0};
  }

  /// بيانات العميل لكل سنة.
  Future<Map<int, PersonYearData>> getCustomerYearlyData(int customerId) async {
    try {
      final facts = await loadFacts(customerId: customerId);
      final years = facts.byYear();
      final tx = await _customerTxCount(customerId, '%Y');
      final qtyByYear = <int, double>{};
      final revByYear = <int, double>{};
      for (final it in facts.saleItems) {
        qtyByYear[it.date.year] = (qtyByYear[it.date.year] ?? 0) + it.baseQty;
        revByYear[it.date.year] = (revByYear[it.date.year] ?? 0) + it.revenue;
      }
      final keys = years.keys.toList()..sort((a, b) => b.compareTo(a));
      return {
        for (final y in keys)
          y: PersonYearData(
            totalProfit: years[y]!.profit,
            totalSales: years[y]!.sales,
            totalInvoices: years[y]!.invoiceCount,
            totalTransactions: tx['$y'] ?? 0,
            averageSellingPrice: (qtyByYear[y] ?? 0) > 0 ? (revByYear[y] ?? 0) / qtyByYear[y]! : 0.0,
            totalQuantity: qtyByYear[y] ?? 0,
            monthlyData: {
              'returns': years[y]!.totalReturns,
              'netSales': years[y]!.netSales,
              'cost': years[y]!.cost,
            },
          )
      };
    } catch (e) {
      throw Exception('Error fetching yearly data: $e');
    }
  }

  /// البيانات الشهرية للعميل في سنة
  Future<Map<int, PersonMonthData>> getCustomerMonthlyData(int customerId, int year) async {
    try {
      final facts = await loadFacts(customerId: customerId, from: DateTime(year, 1, 1), to: DateTime(year, 12, 31));
      final months = facts.byMonth();
      final tx = await _customerTxCount(customerId, '%m', year: year);
      final qty = <int, double>{};
      for (final it in facts.saleItems) {
        qty[it.date.month] = (qty[it.date.month] ?? 0) + it.baseQty;
      }
      final out = <int, PersonMonthData>{};
      for (var m = 1; m <= 12; m++) {
        final t = months['$year-${m.toString().padLeft(2, '0')}'];
        final txN = tx[m.toString().padLeft(2, '0')] ?? 0;
        if (t == null && txN == 0) continue;
        out[m] = PersonMonthData(
          totalProfit: t?.profit ?? 0,
          totalSales: t?.sales ?? 0,
          totalInvoices: t?.invoiceCount ?? 0,
          totalTransactions: txN,
          totalQuantity: qty[m] ?? 0,
          invoices: const [],
        );
      }
      return out;
    } catch (e) {
      throw Exception('Failed to fetch monthly data: $e');
    }
  }

  InvoiceWithProductData _invoiceData(SalesInvoiceFact f) => InvoiceWithProductData(
        invoiceId: f.id,
        invoiceDate: f.date,
        customerName: f.customerName,
        totalAmount: f.total,
        discount: f.discount,
        profit: f.profit,
        invoiceNumber: f.displayNumber,
        paymentType: f.paymentType,
        returnAmount: f.returnAmount,
        loadingFee: f.loadingFee,
        cost: f.cost,
        paid: f.paid,
        items: [
          for (final it in f.items)
            InvoiceItemData(
              productName: it.productName,
              quantity: it.soldQty,
              unit: it.kind == SalesItemKind.adjustment ? '${it.saleType} (تسوية)' : it.saleType,
              unitPrice: it.unitPrice,
              totalPrice: it.revenue,
              costPrice: it.cost,
              profit: it.profit,
            )
        ],
      );

  /// جلب جميع فواتير العميل في شهر معيّن مع ربح كل فاتورة (الأحدث أولاً).
  /// (كانت الكلفة تُحسب بمفاتيح خاطئة فتخرج صفراً ويصير الربح = مبلغ الفاتورة.)
  Future<List<InvoiceWithProductData>> getCustomerInvoicesWithProfitForMonth(int customerId, int year, int month) async {
    final facts = await loadFacts(customerId: customerId, from: DateTime(year, month, 1), to: DateTime(year, month + 1, 0));
    return [for (final f in facts.invoices.reversed) _invoiceData(f)];
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
      // 🗜️ نجلب سلسلة لقطات الفاتورة كاملة لا اللقطات الواقعة في الفترة فقط:
      // بعد منع اللقطات المكررة قد تكون «الحالة قبل التعديل» لقطة أقدم من الفترة،
      // وبدونها يضيع المرتجع. نحتسب لاحقاً الانتقالات التي وقعت داخل الفترة فقط.
      final snapshots = await db.rawQuery('''
        SELECT s.*, i.customer_name, i.created_at as invoice_created_at
        FROM invoice_snapshots s
        JOIN invoices i ON s.invoice_id = i.id
        WHERE i.payment_type = 'نقد'
        AND s.invoice_id IN (
          SELECT invoice_id FROM invoice_snapshots
          WHERE DATE(created_at) >= ? AND DATE(created_at) <= ?
        )
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
          
          // 🗜️ لا نعتمد على أنواع اللقطات (before_edit / after_edit): اللقطة
          // المطابقة لسابقتها لم تعد تُكتب، فقد تأتي after_edit بلا before_edit.
          // كل انتقال بين لقطتين متتاليتين هو تعديل، ويُحتسب إن وقع داخل الفترة.
          final nextCreated = (next['created_at'] as String?) ?? '';
          final nextDay =
              nextCreated.length >= 10 ? nextCreated.substring(0, 10) : nextCreated;
          if (nextDay.compareTo(startStr) >= 0 && nextDay.compareTo(endStr) <= 0) {
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
      debugPrint('Error calculating snapshot returns: $e');
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
    // أيام كاملة: كان endDate منتصف ليل اليوم الأخير فتسقط تعديلات ذلك اليوم.
    final startStr = '${SalesFacts.day(startDate)}T00:00:00';
    final endStr = '${SalesFacts.day(endDate)}T23:59:59.999';

    // جلب كل اللقطات في الفترة المحددة
    // نحتاج اللقطات من نوع before_edit و after_edit
    // 🗜️ سلسلة اللقطات كاملة للفواتير التي عُدّلت في الفترة (انظر _getSnapshotReturns)
    final snapshots = await db.rawQuery('''
      SELECT s.*
      FROM invoice_snapshots s
      JOIN invoices i ON s.invoice_id = i.id
      WHERE s.invoice_id IN (
          SELECT invoice_id FROM invoice_snapshots
          WHERE created_at >= ? AND created_at <= ?
        )
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

        // 🗜️ كل انتقال بين لقطتين متتاليتين هو تعديل (أنواع اللقطات لم تعد
        // مضمونة بعد منع التكرار)، ويُحتسب إن وقعت اللقطة الناتجة داخل الفترة.
        final nextCreated = (next['created_at'] as String?) ?? '';
        if (nextCreated.compareTo(startStr) >= 0 &&
            nextCreated.compareTo(endStr) <= 0) {
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
