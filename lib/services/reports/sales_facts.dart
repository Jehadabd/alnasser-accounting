// lib/services/reports/sales_facts.dart
//
// 📊 محرك أرقام المبيعات الموحّد لكل التقارير.
//
// قبل هذا الملف كانت كل شاشة تقارير تحسب «المبيعات» و«الربح» بطريقتها:
//   • الملخصات (اليوم/الأسبوع/لوحة المؤشرات): إجمالي الفاتورة − الراجع − الكلفة.
//   • رسوم الأيام: مجموع البنود − كلفة تقريبية (تضرب كلفة الكرتون بعدد قطعه مرة ثانية).
//   • تقارير الأشخاص: (سعر − كلفة) × كمية لكل بند، بلا خصم الفاتورة، مع احتساب
//     التسويات مرتين.
//   • تقرير البضاعة: يجمع الكراتين مع القطع ككمية واحدة.
// فلا يتطابق رقمان بين شاشتين. هنا تُقرأ البيانات مرة واحدة وتُشتق منها كل
// المجاميع (يوم، شهر، سنة، مادة، عميل، قسم، طريقة دفع) بقاعدة واحدة:
//
//   مبيعات الفاتورة = total_amount (البنود + أجور التحميل − الخصم + التسويات)
//   كلفة الفاتورة   = كلفة البنود (بنفس منطق محرك الترحيل) + كلفة بنود التسويات
//   ربح الفاتورة    = total_amount − return_amount − الكلفة
//   مرتجع المبيعات (المستند المستقل) يُطرح: مبلغه من المبيعات، وكلفته من الكلفة.
//
// الفاتورة الصالحة: محفوظة (أو بلا حالة في البيانات القديمة) وغير محذوفة.
// يعتمد على DatabaseExecutor فقط ليُختبر على قاعدة في الذاكرة.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../utils/money_calculator.dart';

/// مصدر البيانات: الكل، أو ما أُنشئ على هذا الجهاز، أو ما وصل بالمزامنة.
class ReportSource {
  static const all = 'all';
  static const thisDevice = 'this_device';
  static const sync = 'sync';
}

// ═══════════════════════════ كلفة البند (المنطق المعتمد) ═══════════════════════════

/// كلفة بند فاتورة — نفس منطق ReportsService._calculateItemCost حرفياً
/// (وهو نفس منطق محرك الترحيل مع زيادة الحساب من التسلسل الهرمي).
/// المفاتيح المتوقعة: qi, ql, uilu, sale_type, product_unit, product_cost_price,
/// length_per_unit, actual_cost_per_unit, selling_price, unit_costs, unit_hierarchy.
class ItemCost {
  ItemCost._();

  static double compute(Map<String, Object?> row, {double? adHocProfitPercentage}) {
    final qi = _d(row['qi']);
    final ql = _d(row['ql']);
    final uilu = _d(row['uilu']);
    final saleType = (row['sale_type'] as String?) ?? '';
    final productUnit = (row['product_unit'] as String?) ?? '';
    final productCost = _d(row['product_cost_price']);
    final lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
    final actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
    final sellingPrice = _d(row['selling_price']);
    final unitCosts = _jsonMap(row['unit_costs'] as String?);
    final unitHierarchyJson = row['unit_hierarchy'] as String?;

    final soldAsLargeUnit = ql > 0;
    final soldUnitsCount = soldAsLargeUnit ? ql : qi;

    double costPerSoldUnit;
    if (actualCostPerUnit != null && actualCostPerUnit > 0) {
      costPerSoldUnit = actualCostPerUnit;
    } else if (soldAsLargeUnit) {
      final stored = unitCosts[saleType];
      if (stored is num && stored > 0) {
        costPerSoldUnit = stored.toDouble();
      } else {
        final isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && saleType == 'لفة';
        if (isMeterRoll) {
          costPerSoldUnit = productCost * lengthPerUnit;
        } else if (uilu > 0) {
          costPerSoldUnit = productCost * uilu;
        } else {
          costPerSoldUnit = productCost * hierarchyMultiplier(unitHierarchyJson, saleType, fallback: 1.0);
        }
      }
    } else {
      costPerSoldUnit = productCost;
    }

    if (costPerSoldUnit <= 0 && sellingPrice > 0) {
      costPerSoldUnit = MoneyCalculator.getEffectiveCost(
        0,
        sellingPrice,
        profitMargin: adHocProfitPercentage != null
            ? adHocProfitPercentage / 100.0
            : MoneyCalculator.defaultProfitMargin,
      );
    }
    return costPerSoldUnit * soldUnitsCount;
  }

  /// مضاعف وحدة البيع من التسلسل الهرمي للمادة (كرتون = 12 قطعة …).
  static double hierarchyMultiplier(String? unitHierarchyJson, String saleType, {double fallback = 1.0}) {
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty || saleType.isEmpty) return fallback;
    try {
      final hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
      var multiplier = 1.0;
      for (final level in hierarchy) {
        final unitName = ((level as Map)['unit_name'] ?? level['name'] ?? '').toString();
        final qty = (level['quantity'] as num?)?.toDouble() ?? 1.0;
        multiplier *= qty;
        if (unitName == saleType) return multiplier;
      }
    } catch (_) {}
    return fallback;
  }

  /// الكمية بالوحدة الأساسية (قطعة/متر) لبند — نفس منطق تفصيل منتجات العميل.
  static double baseQuantity(Map<String, Object?> row) {
    final qi = _d(row['qi']);
    final ql = _d(row['ql']);
    final uilu = _d(row['uilu']);
    final saleType = (row['sale_type'] as String?) ?? '';
    final productUnit = (row['product_unit'] as String?) ?? '';
    final lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
    if (saleType == 'قطعة' || saleType == 'متر') return qi > 0 ? qi : ql;
    if (ql > 0) {
      if (productUnit == 'meter' && saleType == 'لفة') {
        return ql * (uilu > 0 ? uilu : (lengthPerUnit ?? 1));
      }
      return ql * (uilu > 0 ? uilu : hierarchyMultiplier(row['unit_hierarchy'] as String?, saleType));
    }
    return qi;
  }

  static String baseUnitName(String? productUnit) => productUnit == 'meter' ? 'متر' : 'قطعة';
}

// ═══════════════════════════ الوقائع ═══════════════════════════

/// بند مبيع (أو بند تسوية/مرتجع) بعد حساب كمّيته الأساسية وكلفته.
class SalesItemFact {
  SalesItemFact({
    required this.invoiceId,
    required this.date,
    required this.productName,
    required this.productId,
    required this.categoryId,
    required this.saleType,
    required this.soldQty,
    required this.baseQty,
    required this.baseUnit,
    required this.unitPrice,
    required this.revenue,
    required this.cost,
    this.kind = SalesItemKind.sale,
  });

  final int invoiceId;
  final DateTime date;
  final String productName;
  final int? productId;
  final int? categoryId;
  final String saleType;
  final double soldQty;
  final double baseQty;
  final String baseUnit;
  final double unitPrice;
  final double revenue;
  final double cost;
  final SalesItemKind kind;

  double get profit => revenue - cost;

  /// مفتاح المادة: المعرّف إن عُرف، وإلا الاسم.
  String get productKey => productId != null ? 'id:$productId' : 'name:$productName';
}

enum SalesItemKind { sale, adjustment, salesReturn }

class SalesInvoiceFact {
  SalesInvoiceFact({
    required this.id,
    required this.number,
    required this.date,
    required this.customerId,
    required this.customerName,
    required this.paymentType,
    required this.total,
    required this.discount,
    required this.loadingFee,
    required this.returnAmount,
    required this.paidOnInvoice,
    required this.createdByMe,
  });

  final int id;
  final String? number;
  final DateTime date;
  final int? customerId;
  final String customerName;
  final String paymentType;
  final double total;
  final double discount;
  final double loadingFee;
  final double returnAmount;
  final double paidOnInvoice;
  final bool createdByMe;

  double gross = 0; // مجموع البنود قبل خصم الفاتورة
  double itemsCost = 0;
  double adjustmentsCost = 0;
  final List<SalesItemFact> items = [];

  double get cost => itemsCost + adjustmentsCost;
  double get netSales => total - returnAmount;
  double get profit => MoneyCalculator.subtract(netSales, cost);
  bool get isCash => paymentType == 'نقد';
  String get displayNumber => (number != null && number!.isNotEmpty) ? number! : '#$id';

  /// المدفوع من الفاتورة (النقدية كلها مدفوعة).
  double get paid => isCash ? total : (paidOnInvoice > total ? total : paidOnInvoice);
}

/// مستند «مرتجع مبيعات» المستقل (جدول sales_returns).
class SalesReturnFact {
  SalesReturnFact({
    required this.id,
    required this.number,
    required this.date,
    required this.customerId,
    required this.customerName,
    required this.originalInvoiceId,
    required this.refundMode,
    required this.total,
    required this.cost,
    required this.cashPart,
    required this.notes,
    required this.createdBy,
  });

  final int id;
  final String number;
  final DateTime date;
  final int? customerId;
  final String customerName;
  final int? originalInvoiceId;
  final String refundMode; // cash | credit | mixed
  final double total;
  final double cost;
  final double cashPart;
  final String? notes;
  final String? createdBy;
  final List<SalesItemFact> items = [];

  /// ما يُنقصه المرتجع من الربح (سعر البيع − كلفة البضاعة العائدة).
  double get profitImpact => total - cost;

  String get refundModeArabic => switch (refundMode) {
        'cash' => 'نقداً',
        'credit' => 'من الدين',
        'mixed' => 'مختلط',
        _ => refundMode,
      };
}

/// ✏️ تعديل بالقلم على فاتورة محفوظة (حدث من invoice_edit_events) في التقارير.
///
/// الفاتورة نفسها تبقى في قائمة الفواتير بحالها الآن؛ ولكل حدث واقعتان:
///   • [sign] = −1 بتاريخ الفاتورة: يُعيد يومها إلى ما كان قبل التعديل.
///   • [sign] = +1 بتاريخ التعديل: الإضافة/المرتجع تظهر في يومها.
/// في يوم واحد تتلاشيان (لا تُحمَّلان أصلاً). المجموع على كل الأيام = الفاتورة الآن.
class SalesEditFact {
  SalesEditFact({
    required this.eventId,
    required this.invoiceId,
    required this.date,
    required this.sign,
    required this.customerId,
    required this.customerName,
    required this.paymentBefore,
    required this.paymentAfter,
    required this.totalBefore,
    required this.totalAfter,
    required this.paidBefore,
    required this.paidAfter,
    required this.discountBefore,
    required this.discountAfter,
    required this.loadingBefore,
    required this.loadingAfter,
  });

  final int eventId;
  final int invoiceId;
  final DateTime date;
  final double sign;
  final int? customerId;
  final String customerName;
  final String paymentBefore;
  final String paymentAfter;
  final double totalBefore;
  final double totalAfter;
  final double paidBefore;
  final double paidAfter;
  final double discountBefore;
  final double discountAfter;
  final double loadingBefore;
  final double loadingAfter;

  /// فروق المواد (بإشارتها) — kind = adjustment.
  final List<SalesItemFact> items = [];

  double get dTotal => sign * (totalAfter - totalBefore);
  double get dPaid => sign * (paidAfter - paidBefore);
  double get dDiscount => sign * (discountAfter - discountBefore);
  double get dLoading => sign * (loadingAfter - loadingBefore);
  double get dGross => items.fold(0.0, (s, i) => s + i.revenue);
  double get dCost => items.fold(0.0, (s, i) => s + i.cost);
  double get dProfit => dTotal - dCost;

  bool get _cashBefore => paymentBefore == 'نقد';
  bool get _cashAfter => paymentAfter == 'نقد';
  double get dCashSales => sign * ((_cashAfter ? totalAfter : 0) - (_cashBefore ? totalBefore : 0));
  double get dCreditSales => sign * ((_cashAfter ? 0 : totalAfter) - (_cashBefore ? 0 : totalBefore));

  /// إضافة (موجب) أم مرتجع (سالب) — بحسب فرق المجموع في يوم التعديل.
  bool get isAddition => (totalAfter - totalBefore) >= 0;
}

/// مجموع فرق مادة واحدة (اسم + وحدة بيع) في حدث تعديل.
class _EditGroup {
  _EditGroup(this.name, this.saleType, this.productId, this.categoryId, this.unit);
  final String name;
  final String saleType;
  final int? productId;
  final int? categoryId;
  final String unit;
  double revenue = 0;
  double cost = 0;
  double soldQty = 0;
  double baseQty = 0;
  double unitPrice = 0;

  bool get isZero => revenue.abs() < 0.005 && cost.abs() < 0.005 && soldQty.abs() < 0.0005 && baseQty.abs() < 0.0005;
}

// ═══════════════════════════ المجاميع ═══════════════════════════

class SalesTotals {
  int invoiceCount = 0;
  double sales = 0; // Σ total_amount
  double gross = 0;
  double discount = 0;
  double loadingFees = 0;
  double invoiceReturns = 0; // Σ return_amount (الراجع المسجل على الفاتورة)
  double salesReturns = 0; // مستندات مرتجع المبيعات
  double salesReturnsCost = 0;
  int salesReturnsCount = 0;
  double invoiceCost = 0;
  double invoiceProfit = 0;
  double cashSales = 0;
  double creditSales = 0;
  double paid = 0;
  final Set<String> _customers = {};

  int get customerCount => _customers.length;
  double get totalReturns => invoiceReturns + salesReturns;
  double get netSales => sales - totalReturns;
  double get cost => invoiceCost - salesReturnsCost;
  double get profit => invoiceProfit - (salesReturns - salesReturnsCost);
  double get margin => netSales.abs() > 0.0001 ? profit / netSales * 100 : 0;
  double get averageInvoice => invoiceCount > 0 ? sales / invoiceCount : 0;
  bool get isEmpty => invoiceCount == 0 && salesReturnsCount == 0;

  void addInvoice(SalesInvoiceFact inv) {
    invoiceCount++;
    sales += inv.total;
    gross += inv.gross;
    discount += inv.discount;
    loadingFees += inv.loadingFee;
    invoiceReturns += inv.returnAmount;
    invoiceCost += inv.cost;
    invoiceProfit += inv.profit;
    if (inv.isCash) {
      cashSales += inv.total;
    } else {
      creditSales += inv.total;
    }
    paid += inv.paid;
    _customers.add(inv.customerId != null && inv.customerId! > 0 ? 'id:${inv.customerId}' : 'n:${inv.customerName}');
  }

  void addReturn(SalesReturnFact r) {
    salesReturnsCount++;
    salesReturns += r.total;
    salesReturnsCost += r.cost;
  }

  /// ✏️ تعديل بالقلم (لا يزيد عدد الفواتير ولا العملاء — فرق أرقام فقط).
  void addEdit(SalesEditFact e) {
    sales += e.dTotal;
    gross += e.dGross;
    discount += e.dDiscount;
    loadingFees += e.dLoading;
    invoiceCost += e.dCost;
    invoiceProfit += e.dProfit;
    cashSales += e.dCashSales;
    creditSales += e.dCreditSales;
    paid += e.dPaid;
  }

  /// بصيغة getPeriodSummary القديمة + مفاتيح جديدة (إضافة فقط، لا حذف).
  Map<String, dynamic> toSummaryMap() => {
        'invoiceCount': invoiceCount,
        'totalSales': sales,
        'netProfit': profit,
        'totalCost': cost,
        'cashSales': cashSales,
        'creditSales': creditSales,
        'totalReturns': totalReturns,
        // جديد
        'grossSales': gross,
        'totalDiscount': discount,
        'totalLoadingFees': loadingFees,
        'invoiceReturns': invoiceReturns,
        'salesReturns': salesReturns,
        'salesReturnsCost': salesReturnsCost,
        'salesReturnsCount': salesReturnsCount,
        'netSales': netSales,
        'profitMargin': margin,
        'paidAmount': paid,
        'customerCount': customerCount,
        'averageInvoice': averageInvoice,
      };
}

class ProductAgg {
  ProductAgg({required this.key, required this.name, this.productId, this.categoryId, required this.baseUnit});
  final String key;
  final String name;
  final int? productId;
  int? categoryId;
  final String baseUnit;
  double baseQty = 0;
  double revenue = 0;
  double cost = 0;
  double returnedQty = 0;
  double returnedRevenue = 0;
  double returnedCost = 0;
  final Set<int> _invoices = {};
  final Set<String> _customers = {};
  DateTime? lastSale;

  int get invoiceCount => _invoices.length;
  int get customerCount => _customers.length;
  double get netQty => baseQty - returnedQty;
  double get netRevenue => revenue - returnedRevenue;
  double get netCost => cost - returnedCost;
  double get profit => netRevenue - netCost;
  double get margin => netRevenue.abs() > 0.0001 ? profit / netRevenue * 100 : 0;
  double get averagePrice => baseQty > 0 ? revenue / baseQty : 0;
}

class CustomerAgg {
  CustomerAgg({required this.key, required this.customerId, required this.name});
  final String key;
  final int? customerId;
  final String name;
  final SalesTotals totals = SalesTotals();
  DateTime? lastInvoice;
}

class CategoryAgg {
  CategoryAgg({required this.categoryId, required this.name});
  final int? categoryId;
  final String name;
  double revenue = 0;
  double cost = 0;
  double baseQty = 0;
  double returnedRevenue = 0;
  double returnedCost = 0;
  final Set<int> _invoices = {};
  final Set<String> _products = {};
  int get invoiceCount => _invoices.length;
  int get productCount => _products.length;
  double get netRevenue => revenue - returnedRevenue;
  double get profit => netRevenue - (cost - returnedCost);
  double get margin => netRevenue.abs() > 0.0001 ? profit / netRevenue * 100 : 0;
}

// ═══════════════════════════ التحميل والتجميع ═══════════════════════════

class SalesFacts {
  SalesFacts._(this.invoices, this.returns, this.from, this.to, [this.edits = const []]);

  final List<SalesInvoiceFact> invoices;
  final List<SalesReturnFact> returns;

  /// ✏️ تعديلات بالقلم التي تمسّ الفترة (انظر [SalesEditFact]).
  final List<SalesEditFact> edits;
  final DateTime? from;
  final DateTime? to;

  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// يحمّل وقائع الفترة [from, to] (أيام كاملة، شاملة الطرفين؛ null = بلا حد).
  ///
  /// [customerId]: فواتير عميل واحد (ومعها القديمة المحفوظة باسمه بلا معرّف).
  /// [productId]/[productName]: بنود مادة واحدة فقط (مجاميع الفواتير عندها بلا معنى).
  static Future<SalesFacts> load(
    DatabaseExecutor db, {
    DateTime? from,
    DateTime? to,
    String source = ReportSource.all,
    int? customerId,
    String? customerName,
    int? productId,
    String? productName,
    int? invoiceId,
    double adHocProfitPercentage = 10,
    bool includeAdjustments = true,
    bool includeSalesReturns = true,
    bool includeEdits = true,
  }) async {
    final where = <String>[
      "COALESCE(NULLIF(TRIM(i.status), ''), 'محفوظة') = 'محفوظة'",
      'COALESCE(i.is_deleted, 0) = 0',
    ];
    final args = <Object?>[];
    if (from != null) {
      where.add('substr(i.invoice_date, 1, 10) >= ?');
      args.add(day(from));
    }
    if (to != null) {
      where.add('substr(i.invoice_date, 1, 10) <= ?');
      args.add(day(to));
    }
    if (source == ReportSource.thisDevice) {
      where.add('COALESCE(i.is_created_by_me, 1) = 1');
    } else if (source == ReportSource.sync) {
      where.add('COALESCE(i.is_created_by_me, 1) = 0');
    }
    if (invoiceId != null) {
      where.add('i.id = ?');
      args.add(invoiceId);
    }
    String? custName = customerName;
    if (customerId != null) {
      if (custName == null) {
        final c = await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [customerId], limit: 1);
        custName = c.isEmpty ? null : c.first['name'] as String?;
      }
      where.add('(i.customer_id = ? OR ((i.customer_id IS NULL OR i.customer_id = 0) AND i.customer_name = ?))');
      args
        ..add(customerId)
        ..add(custName ?? '\u0000');
    } else if (customerName != null) {
      // زبون بلا بطاقة (نقدي باسم فقط)
      where.add('((i.customer_id IS NULL OR i.customer_id = 0) AND i.customer_name = ?)');
      args.add(customerName);
    }

    // مادة واحدة: نطابق بالاسم أو بالمعرّف (البنود القديمة بلا product_id)
    String productItemFilter = '';
    final productArgs = <Object?>[];
    if (productId != null || productName != null) {
      String? pName = productName;
      if (pName == null && productId != null) {
        final p = await db.query('products', columns: ['name'], where: 'id = ?', whereArgs: [productId], limit: 1);
        pName = p.isEmpty ? null : p.first['name'] as String?;
      }
      productItemFilter = ' AND (ii.product_name = ? OR (? IS NOT NULL AND ii.product_id = ?))';
      productArgs.addAll([pName ?? '\u0000', productId, productId]);
    }

    final whereSql = where.join(' AND ');

    // شروط الفواتير بلا شرط تاريخها — لأحداث التعديل (تاريخها قد يكون خارج الفترة)
    final evWhere = <String>[];
    final evArgs = <Object?>[];
    {
      var ai = 0;
      for (final w in where) {
        final n = '?'.allMatches(w).length;
        if (!w.contains('i.invoice_date')) {
          evWhere.add(w);
          evArgs.addAll(args.sublist(ai, ai + n));
        }
        ai += n;
      }
    }

    // 1) رؤوس الفواتير
    final invRows = await db.rawQuery('''
      SELECT i.id, i.invoice_number, i.invoice_date, i.customer_id, i.customer_name, i.payment_type,
             COALESCE(i.total_amount, 0) AS total_amount, COALESCE(i.discount, 0) AS discount,
             COALESCE(i.loading_fee, 0) AS loading_fee, COALESCE(i.return_amount, 0) AS return_amount,
             COALESCE(i.amount_paid_on_invoice, 0) AS paid, COALESCE(i.is_created_by_me, 1) AS mine
      FROM invoices i
      WHERE $whereSql
        ${productItemFilter.isEmpty ? '' : 'AND i.id IN (SELECT ii.invoice_id FROM invoice_items ii WHERE 1 = 1$productItemFilter)'}
      ORDER BY i.invoice_date, i.id
    ''', [...args, ...productArgs]);

    final byId = <int, SalesInvoiceFact>{};
    final invoices = <SalesInvoiceFact>[];
    for (final r in invRows) {
      final f = SalesInvoiceFact(
        id: (r['id'] as num).toInt(),
        number: r['invoice_number']?.toString(),
        date: _parseDate(r['invoice_date']),
        customerId: (r['customer_id'] as num?)?.toInt(),
        customerName: (r['customer_name'] as String?)?.trim().isNotEmpty == true ? (r['customer_name'] as String).trim() : 'بدون اسم',
        paymentType: (r['payment_type'] as String?) ?? '',
        total: _d(r['total_amount']),
        discount: _d(r['discount']),
        loadingFee: _d(r['loading_fee']),
        returnAmount: _d(r['return_amount']),
        paidOnInvoice: _d(r['paid']),
        createdByMe: _d(r['mine']) != 0,
      );
      byId[f.id] = f;
      invoices.add(f);
    }

    // 2) البنود — المادة تُطابق بالاسم أولاً (كمحرك الترحيل) ثم بالمعرّف، بلا تكرار صفوف.
    if (invoices.isNotEmpty) {
      final itemRows = await db.rawQuery('''
        SELECT ii.invoice_id, ii.product_name AS item_name, ii.product_id AS item_product_id,
               ii.quantity_individual AS qi, ii.quantity_large_unit AS ql,
               ii.units_in_large_unit AS uilu, ii.actual_cost_price AS actual_cost_per_unit,
               ii.applied_price AS selling_price, ii.sale_type AS sale_type, ii.item_total AS item_total,
               p.id AS pid, p.unit AS product_unit, p.cost_price AS product_cost_price,
               p.length_per_unit AS length_per_unit, p.unit_costs AS unit_costs,
               p.unit_hierarchy AS unit_hierarchy, p.category_id AS category_id
        FROM invoice_items ii
        JOIN invoices i ON i.id = ii.invoice_id
        LEFT JOIN (SELECT name, MIN(id) AS id FROM products GROUP BY name) pn ON pn.name = ii.product_name
        LEFT JOIN products p ON p.id = COALESCE(pn.id, ii.product_id)
        WHERE $whereSql$productItemFilter
      ''', [...args, ...productArgs]);

      for (final r in itemRows) {
        final inv = byId[(r['invoice_id'] as num).toInt()];
        if (inv == null) continue;
        final revenue = _d(r['item_total']);
        final cost = ItemCost.compute(r, adHocProfitPercentage: adHocProfitPercentage);
        final ql = _d(r['ql']);
        final qi = _d(r['qi']);
        final pid = (r['pid'] as num?)?.toInt() ?? (r['item_product_id'] as num?)?.toInt();
        final unit = (r['product_unit'] as String?) ?? '';
        final item = SalesItemFact(
          invoiceId: inv.id,
          date: inv.date,
          productName: (r['item_name'] as String?) ?? '',
          productId: pid,
          categoryId: (r['category_id'] as num?)?.toInt(),
          saleType: (r['sale_type'] as String?) ?? ItemCost.baseUnitName(unit),
          soldQty: ql > 0 ? ql : qi,
          baseQty: ItemCost.baseQuantity(r),
          baseUnit: ItemCost.baseUnitName(unit),
          unitPrice: _d(r['selling_price']),
          revenue: revenue,
          cost: cost,
        );
        inv.items.add(item);
        inv.gross += revenue;
        inv.itemsCost += cost;
      }

      // 3) بنود التسويات بعد الحفظ: مبلغها داخل total_amount أصلاً (insertInvoiceAdjustment
      //    يحدّثه)، فنضيف كلفتها وكميتها فقط — وكانت الملخصات تتجاهل كلفتها.
      if (includeAdjustments) {
        try {
          final adjRows = await db.rawQuery('''
            SELECT ia.*, p.id AS pid, p.unit AS product_unit, p.cost_price AS product_cost_price,
                   p.length_per_unit AS length_per_unit, p.unit_hierarchy AS unit_hierarchy,
                   p.category_id AS category_id, p.name AS p_name
            FROM invoice_adjustments ia
            JOIN invoices i ON i.id = ia.invoice_id
            LEFT JOIN products p ON p.id = ia.product_id
            WHERE ia.product_id IS NOT NULL AND $whereSql
              ${productItemFilter.isEmpty ? '' : 'AND (ia.product_id = ? OR ia.product_name = ?)'}
          ''', [
            ...args,
            if (productItemFilter.isNotEmpty) ...[productId ?? -1, productArgs.first],
          ]);
          for (final r in adjRows) {
            final inv = byId[(r['invoice_id'] as num).toInt()];
            if (inv == null) continue;
            final qty = _d(r['quantity']);
            if (qty == 0) continue;
            final type = ((r['type'] ?? r['adjustment_type']) as String?) ?? 'debit';
            final sign = type == 'credit' ? -1.0 : 1.0;
            final unit = (r['product_unit'] as String?) ?? 'piece';
            final saleType = (r['sale_type'] as String?) ?? (unit == 'meter' ? 'متر' : 'قطعة');
            final uilu = (r['units_in_large_unit'] as num?)?.toDouble() ?? 1.0;
            final lpu = (r['length_per_unit'] as num?)?.toDouble();
            double baseQty;
            if (unit == 'meter' && saleType == 'لفة') {
              baseQty = qty * (uilu > 0 ? uilu : (lpu ?? 1.0));
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qty;
            } else {
              baseQty = qty * (uilu > 0 ? uilu : 1.0);
            }
            final price = _d(r['price']);
            final revenue = sign * qty * price;
            // كلفة يوم التسوية إن حُفظت، وإلا كلفة المادة الحالية
            final snap = _d(r['base_unit_cost']);
            final baseCost = snap > 0 ? snap : _d(r['product_cost_price']);
            double cost;
            if (baseCost > 0) {
              cost = sign * baseCost * baseQty;
            } else {
              cost = revenue * (1 - adHocProfitPercentage / 100.0);
            }
            inv.adjustmentsCost += cost;
            inv.items.add(SalesItemFact(
              invoiceId: inv.id,
              date: inv.date,
              productName: ((r['product_name'] ?? r['p_name']) as String?) ?? '',
              productId: (r['pid'] as num?)?.toInt() ?? (r['product_id'] as num?)?.toInt(),
              categoryId: (r['category_id'] as num?)?.toInt(),
              saleType: saleType,
              soldQty: sign * qty,
              baseQty: sign * baseQty,
              baseUnit: ItemCost.baseUnitName(unit),
              unitPrice: price,
              revenue: revenue,
              cost: cost,
              kind: SalesItemKind.adjustment,
            ));
          }
        } catch (_) {
          // جدول التسويات غير موجود في قاعدة قديمة جداً
        }
      }
    }

    // 3.5) ✏️ تعديلات بالقلم: «−الفرق» بتاريخ الفاتورة و«+الفرق» بتاريخ التعديل
    final edits = <SalesEditFact>[];
    if (includeEdits) {
      try {
        edits.addAll(await _loadEdits(
          db,
          evWhere,
          evArgs,
          from: from,
          to: to,
          productId: productItemFilter.isEmpty ? null : productId,
          productName: productItemFilter.isEmpty ? null : productArgs.first as String?,
          adHoc: adHocProfitPercentage,
        ));
      } catch (_) {
        // لا جدول أحداث بعد، أو قاعدة قديمة: التقارير كما كانت
      }
    }

    // 4) مستندات مرتجع المبيعات (لا تحمل علَم الجهاز؛ تُستبعد عند «المزامنة فقط»)
    final returns = <SalesReturnFact>[];
    if (includeSalesReturns && source != ReportSource.sync && invoiceId == null) {
      try {
        final rw = <String>["r.status = 'posted'"];
        final ra = <Object?>[];
        if (from != null) {
          rw.add('substr(r.return_date, 1, 10) >= ?');
          ra.add(day(from));
        }
        if (to != null) {
          rw.add('substr(r.return_date, 1, 10) <= ?');
          ra.add(day(to));
        }
        if (customerId != null) {
          rw.add('(r.customer_id = ? OR (r.customer_id IS NULL AND r.customer_name = ?))');
          ra
            ..add(customerId)
            ..add(custName ?? '\u0000');
        } else if (customerName != null) {
          rw.add('(r.customer_id IS NULL AND r.customer_name = ?)');
          ra.add(customerName);
        }
        if (productItemFilter.isNotEmpty) {
          rw.add('r.id IN (SELECT ri.return_id FROM sales_return_items ri WHERE ri.product_id = ? OR ri.product_name = ?)');
          ra
            ..add(productId ?? -1)
            ..add(productArgs.first);
        }
        final rRows = await db.rawQuery(
            'SELECT r.* FROM sales_returns r WHERE ${rw.join(' AND ')} ORDER BY r.return_date, r.id', ra);
        final rById = <int, SalesReturnFact>{};
        for (final r in rRows) {
          final total = _d(r['total']);
          final mode = (r['refund_mode'] as String?) ?? 'cash';
          final f = SalesReturnFact(
            id: (r['id'] as num).toInt(),
            number: '${r['return_no'] ?? r['id']}',
            date: _parseDate(r['return_date']),
            customerId: (r['customer_id'] as num?)?.toInt(),
            customerName: (r['customer_name'] as String?) ?? '',
            originalInvoiceId: (r['original_invoice_id'] as num?)?.toInt(),
            refundMode: mode,
            total: total,
            cost: _d(r['cost_total']),
            cashPart: mode == 'cash' ? total : (mode == 'mixed' ? _d(r['cash_amount']) : 0),
            notes: r['notes'] as String?,
            createdBy: r['created_by'] as String?,
          );
          rById[f.id] = f;
          returns.add(f);
        }
        if (rById.isNotEmpty) {
          final ids = rById.keys.toList();
          final ph = List.filled(ids.length, '?').join(',');
          final itRows = await db.rawQuery('''
            SELECT ri.*, p.unit AS product_unit, p.category_id AS category_id
            FROM sales_return_items ri LEFT JOIN products p ON p.id = ri.product_id
            WHERE ri.return_id IN ($ph)
          ''', ids);
          for (final r in itRows) {
            final ret = rById[(r['return_id'] as num).toInt()];
            if (ret == null) continue;
            final name = (r['product_name'] as String?) ?? '';
            if (productItemFilter.isNotEmpty &&
                !((productId != null && (r['product_id'] as num?)?.toInt() == productId) || name == productArgs.first)) {
              continue;
            }
            final baseQty = _d(r['base_qty']);
            ret.items.add(SalesItemFact(
              invoiceId: ret.originalInvoiceId ?? 0,
              date: ret.date,
              productName: name,
              productId: (r['product_id'] as num?)?.toInt(),
              categoryId: (r['category_id'] as num?)?.toInt(),
              saleType: (r['sale_type'] as String?) ?? '',
              soldQty: _d(r['quantity']),
              baseQty: baseQty,
              baseUnit: ItemCost.baseUnitName(r['product_unit'] as String?),
              unitPrice: _d(r['price']),
              revenue: _d(r['total']),
              cost: _d(r['unit_cost']) * baseQty,
              kind: SalesItemKind.salesReturn,
            ));
          }
        }
      } catch (_) {
        // جداول المرتجع غير موجودة بعد (قاعدة قبل تحديث ERP)
      }
    }

    return SalesFacts._(invoices, returns, from, to, edits);
  }

  static bool _inRange(DateTime d, DateTime? from, DateTime? to) {
    final k = day(d);
    if (from != null && k.compareTo(day(from)) < 0) return false;
    if (to != null && k.compareTo(day(to)) > 0) return false;
    return true;
  }

  static List<Map<String, Object?>> _decodeItems(Object? json) {
    if (json == null) return const [];
    try {
      final v = jsonDecode('$json');
      if (v is! List) return const [];
      return [for (final e in v) if (e is Map) Map<String, Object?>.from(e)];
    } catch (_) {
      return const [];
    }
  }

  /// ✏️ أحداث التعديل بالقلم التي تمسّ الفترة (بتاريخ فاتورتها أو بتاريخها).
  /// [evWhere]/[evArgs]: شروط الفواتير نفسها بلا شرط التاريخ (العميل، المصدر، الفاتورة).
  static Future<List<SalesEditFact>> _loadEdits(
    DatabaseExecutor db,
    List<String> evWhere,
    List<Object?> evArgs, {
    DateTime? from,
    DateTime? to,
    int? productId,
    String? productName,
    required double adHoc,
  }) async {
    final t = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='invoice_edit_events'");
    if (t.isEmpty) return const [];
    final rows = await db.rawQuery('''
      SELECT e.*, i.invoice_date AS cur_invoice_date, i.customer_id AS inv_customer_id,
             i.customer_name AS inv_customer_name
      FROM invoice_edit_events e
      JOIN invoices i ON i.id = e.invoice_id
      WHERE ${evWhere.isEmpty ? '1 = 1' : evWhere.join(' AND ')}
      ORDER BY e.event_date, e.id
    ''', evArgs);
    if (rows.isEmpty) return const [];

    // الأحداث التي تمسّ الفترة فقط (في يوم واحد مع فاتورتها تتلاشى فلا تُحمَّل)
    final todo = <(Map<String, Object?>, DateTime, DateTime, bool, bool)>[];
    final names = <String>{};
    final ids = <int>{};
    for (final r in rows) {
      final invDate = _parseDate(r['cur_invoice_date']);
      final evDate = _parseDate(r['event_date']);
      if (day(invDate) == day(evDate)) continue;
      final inInv = _inRange(invDate, from, to);
      final inEv = _inRange(evDate, from, to);
      if (!inInv && !inEv) continue;
      todo.add((r, invDate, evDate, inInv, inEv));
      for (final it in [..._decodeItems(r['items_before']), ..._decodeItems(r['items_after'])]) {
        final n = '${it['product_name'] ?? ''}';
        if (n.isNotEmpty) names.add(n);
        final pid = (it['product_id'] as num?)?.toInt();
        if (pid != null) ids.add(pid);
      }
    }
    if (todo.isEmpty) return const [];

    // بيانات المواد الحالية — كبنود الفواتير: بالاسم أولاً (أصغر معرّف) ثم بالمعرّف
    final byName = <String, Map<String, Object?>>{};
    final byPid = <int, Map<String, Object?>>{};
    const cols = 'id, name, unit, cost_price, length_per_unit, unit_costs, unit_hierarchy, category_id';
    final nl = names.toList();
    for (var i = 0; i < nl.length; i += 400) {
      final chunk = nl.sublist(i, i + 400 > nl.length ? nl.length : i + 400);
      final pr = await db.rawQuery(
          'SELECT $cols FROM products WHERE name IN (${List.filled(chunk.length, '?').join(',')}) ORDER BY id', chunk);
      for (final p in pr) {
        byName.putIfAbsent('${p['name']}', () => p);
      }
    }
    final il = ids.toList();
    for (var i = 0; i < il.length; i += 400) {
      final chunk = il.sublist(i, i + 400 > il.length ? il.length : i + 400);
      final pr = await db.rawQuery(
          'SELECT $cols FROM products WHERE id IN (${List.filled(chunk.length, '?').join(',')})', chunk);
      for (final p in pr) {
        byPid[(p['id'] as num).toInt()] = p;
      }
    }

    final out = <SalesEditFact>[];
    for (final (r, invDate, evDate, inInv, inEv) in todo) {
      final groups = <String, _EditGroup>{};
      void addRows(List<Map<String, Object?>> items, double s) {
        for (final it in items) {
          final name = '${it['product_name'] ?? ''}';
          final st = '${it['sale_type'] ?? ''}';
          final p = byName[name] ?? byPid[(it['product_id'] as num?)?.toInt()];
          final row = <String, Object?>{
            'qi': it['qi'],
            'ql': it['ql'],
            'uilu': it['uilu'],
            'sale_type': it['sale_type'],
            'actual_cost_per_unit': it['actual_cost_per_unit'],
            'selling_price': it['selling_price'],
            'product_unit': p?['unit'],
            'product_cost_price': p?['cost_price'],
            'length_per_unit': p?['length_per_unit'],
            'unit_costs': p?['unit_costs'],
            'unit_hierarchy': p?['unit_hierarchy'],
          };
          final unit = (p?['unit'] as String?) ?? '';
          final g = groups.putIfAbsent(
              '$name\u0001$st',
              () => _EditGroup(name, st.isEmpty ? ItemCost.baseUnitName(unit) : st,
                  (p?['id'] as num?)?.toInt() ?? (it['product_id'] as num?)?.toInt(),
                  (p?['category_id'] as num?)?.toInt(), unit));
          g.revenue += s * _d(it['item_total']);
          g.cost += s * ItemCost.compute(row, adHocProfitPercentage: adHoc);
          final ql = _d(it['ql']);
          final qi = _d(it['qi']);
          g.soldQty += s * (ql > 0 ? ql : qi);
          g.baseQty += s * ItemCost.baseQuantity(row);
          final price = _d(it['selling_price']);
          if (price > 0) g.unitPrice = price;
        }
      }

      addRows(_decodeItems(r['items_before']), -1);
      addRows(_decodeItems(r['items_after']), 1);
      var kept = groups.values.where((g) => !g.isZero).toList();
      if (productId != null || productName != null) {
        kept = kept.where((g) => (productId != null && g.productId == productId) || g.name == productName).toList();
        if (kept.isEmpty) continue; // الحدث لا يمسّ هذه المادة
      }

      for (final sign in [if (inInv) -1.0, if (inEv) 1.0]) {
        final date = sign < 0 ? invDate : evDate;
        final cn = (r['inv_customer_name'] as String?)?.trim();
        final f = SalesEditFact(
          eventId: (r['id'] as num).toInt(),
          invoiceId: (r['invoice_id'] as num).toInt(),
          date: date,
          sign: sign,
          customerId: (r['inv_customer_id'] as num?)?.toInt(),
          customerName: (cn != null && cn.isNotEmpty) ? cn : 'بدون اسم',
          paymentBefore: '${r['payment_before'] ?? ''}',
          paymentAfter: '${r['payment_after'] ?? ''}',
          totalBefore: _d(r['total_before']),
          totalAfter: _d(r['total_after']),
          paidBefore: _d(r['paid_before']),
          paidAfter: _d(r['paid_after']),
          discountBefore: _d(r['discount_before']),
          discountAfter: _d(r['discount_after']),
          loadingBefore: _d(r['loading_before']),
          loadingAfter: _d(r['loading_after']),
        );
        for (final g in kept) {
          f.items.add(SalesItemFact(
            invoiceId: f.invoiceId,
            date: date,
            productName: g.name,
            productId: g.productId,
            categoryId: g.categoryId,
            saleType: g.saleType,
            soldQty: sign * g.soldQty,
            baseQty: sign * g.baseQty,
            baseUnit: ItemCost.baseUnitName(g.unit),
            unitPrice: g.unitPrice,
            revenue: sign * g.revenue,
            cost: sign * g.cost,
            kind: SalesItemKind.adjustment,
          ));
        }
        out.add(f);
      }
    }
    return out;
  }

  // ─────────────────────────── تجميعات ───────────────────────────

  SalesTotals totals() {
    final t = SalesTotals();
    for (final i in invoices) {
      t.addInvoice(i);
    }
    for (final r in returns) {
      t.addReturn(r);
    }
    for (final e in edits) {
      t.addEdit(e);
    }
    return t;
  }

  Map<K, SalesTotals> _group<K>(K Function(DateTime d) keyOf) {
    final out = <K, SalesTotals>{};
    for (final i in invoices) {
      out.putIfAbsent(keyOf(i.date), SalesTotals.new).addInvoice(i);
    }
    for (final r in returns) {
      out.putIfAbsent(keyOf(r.date), SalesTotals.new).addReturn(r);
    }
    for (final e in edits) {
      out.putIfAbsent(keyOf(e.date), SalesTotals.new).addEdit(e);
    }
    return out;
  }

  /// yyyy-MM-dd → مجاميع اليوم.
  Map<String, SalesTotals> byDay() => _group(day);

  /// yyyy-MM → مجاميع الشهر.
  Map<String, SalesTotals> byMonth() => _group(monthKey);

  Map<int, SalesTotals> byYear() => _group((d) => d.year);

  /// مجاميع حسب أسبوع يبدأ بالسبت؛ المفتاح تاريخ السبت.
  Map<String, SalesTotals> byWeek() => _group((d) => day(weekStart(d)));

  /// بداية الأسبوع (السبت) — الأسبوع في العراق يبدأ بالسبت.
  static DateTime weekStart(DateTime d) {
    final dayOnly = DateTime(d.year, d.month, d.day);
    final back = (dayOnly.weekday + 1) % 7; // السبت = 6 → 0
    return dayOnly.subtract(Duration(days: back));
  }

  /// كل البنود (مبيع + تسويات) ثم بنود المرتجعات.
  Iterable<SalesItemFact> get saleItems sync* {
    for (final i in invoices) {
      yield* i.items;
    }
    for (final e in edits) {
      yield* e.items;
    }
  }

  Iterable<SalesItemFact> get returnItems sync* {
    for (final r in returns) {
      yield* r.items;
    }
  }

  List<ProductAgg> byProduct() {
    final map = <String, ProductAgg>{};
    ProductAgg agg(SalesItemFact it) => map.putIfAbsent(
          it.productKey,
          () => ProductAgg(
            key: it.productKey,
            name: it.productName,
            productId: it.productId,
            categoryId: it.categoryId,
            baseUnit: it.baseUnit,
          ),
        );
    final invById = {for (final i in invoices) i.id: i};
    for (final it in saleItems) {
      final a = agg(it);
      a.categoryId ??= it.categoryId;
      a.baseQty += it.baseQty;
      a.revenue += it.revenue;
      a.cost += it.cost;
      a._invoices.add(it.invoiceId);
      final inv = invById[it.invoiceId];
      if (inv != null) {
        a._customers.add(inv.customerId != null && inv.customerId! > 0 ? 'id:${inv.customerId}' : 'n:${inv.customerName}');
      }
      if (a.lastSale == null || it.date.isAfter(a.lastSale!)) a.lastSale = it.date;
    }
    for (final it in returnItems) {
      final a = agg(it);
      a.returnedQty += it.baseQty;
      a.returnedRevenue += it.revenue;
      a.returnedCost += it.cost;
    }
    return map.values.toList();
  }

  List<CustomerAgg> byCustomer() {
    final map = <String, CustomerAgg>{};
    String keyOf(int? id, String name) => id != null && id > 0 ? 'id:$id' : 'n:$name';
    for (final i in invoices) {
      final a = map.putIfAbsent(keyOf(i.customerId, i.customerName),
          () => CustomerAgg(key: keyOf(i.customerId, i.customerName), customerId: i.customerId, name: i.customerName));
      a.totals.addInvoice(i);
      if (a.lastInvoice == null || i.date.isAfter(a.lastInvoice!)) a.lastInvoice = i.date;
    }
    for (final r in returns) {
      final a = map.putIfAbsent(keyOf(r.customerId, r.customerName),
          () => CustomerAgg(key: keyOf(r.customerId, r.customerName), customerId: r.customerId, name: r.customerName));
      a.totals.addReturn(r);
    }
    for (final e in edits) {
      final a = map.putIfAbsent(keyOf(e.customerId, e.customerName),
          () => CustomerAgg(key: keyOf(e.customerId, e.customerName), customerId: e.customerId, name: e.customerName));
      a.totals.addEdit(e);
    }
    return map.values.toList();
  }

  /// [names]: اسم كل قسم؛ [parents]: الأب لكل قسم — إن أُعطي [rollupTo] تُجمع
  /// الأقسام الفرعية تحت جذرها (أو تحت القسم المطلوب).
  List<CategoryAgg> byCategory(Map<int, String> names, {Map<int, int?> parents = const {}, bool rollupToRoot = false}) {
    int? root(int? id) {
      if (!rollupToRoot || id == null) return id;
      var cur = id;
      final seen = <int>{};
      while (parents[cur] != null && seen.add(cur)) {
        cur = parents[cur]!;
      }
      return cur;
    }

    final map = <int?, CategoryAgg>{};
    CategoryAgg agg(int? id) => map.putIfAbsent(
        id, () => CategoryAgg(categoryId: id, name: id == null ? 'بلا قسم' : (names[id] ?? 'قسم #$id')));
    for (final it in saleItems) {
      final a = agg(root(it.categoryId));
      a.revenue += it.revenue;
      a.cost += it.cost;
      a.baseQty += it.baseQty;
      a._invoices.add(it.invoiceId);
      a._products.add(it.productKey);
    }
    for (final it in returnItems) {
      final a = agg(root(it.categoryId));
      a.returnedRevenue += it.revenue;
      a.returnedCost += it.cost;
    }
    return map.values.toList();
  }

  /// نقد / دين … → مجموع total_amount.
  Map<String, double> byPayment() {
    final out = <String, double>{};
    for (final i in invoices) {
      final k = i.paymentType.isEmpty ? 'غير محدد' : i.paymentType;
      out[k] = (out[k] ?? 0) + i.total;
    }
    for (final e in edits) {
      final kb = e.paymentBefore.isEmpty ? 'غير محدد' : e.paymentBefore;
      final ka = e.paymentAfter.isEmpty ? 'غير محدد' : e.paymentAfter;
      out[kb] = (out[kb] ?? 0) - e.sign * e.totalBefore;
      out[ka] = (out[ka] ?? 0) + e.sign * e.totalAfter;
    }
    return out;
  }
}

// ═══════════════════════════ أدوات ═══════════════════════════

double _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);

Map<String, dynamic> _jsonMap(String? s) {
  if (s == null || s.trim().isEmpty) return const {};
  try {
    final v = jsonDecode(s);
    return v is Map<String, dynamic> ? v : const {};
  } catch (_) {
    return const {};
  }
}

DateTime _parseDate(Object? v) {
  final s = v?.toString() ?? '';
  final d = DateTime.tryParse(s);
  if (d != null) return d;
  // صيغ قديمة غير مبطّنة: 2024-1-5
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
  return DateTime(1970);
}

/// قسم مواد (للاختيار في تقارير البضاعة).
class ReportCategory {
  const ReportCategory({required this.id, required this.name, this.parentId, this.productCount = 0});
  final int id;
  final String name;
  final int? parentId;
  final int productCount;
}
