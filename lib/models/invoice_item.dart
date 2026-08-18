// models/invoice_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InvoiceItem {
  // دالة تنسيق الأرقام مع فواصل كل ثلاث خانات
  static String _formatNumber(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }
  int? id;
  int invoiceId; // Foreign key to Invoice
  int? productId; // Foreign key to Product
  String productName;
  String unit;
  // 💰 حقول الدقة المالية بالأعداد الصحيحة
  int unitPriceCents;
  int appliedPriceCents;
  int itemTotalCents;

  double get unitPrice => unitPriceCents / 100.0;
  set unitPrice(double value) => unitPriceCents = (value * 100).round();

  double get appliedPrice => appliedPriceCents / 100.0;
  set appliedPrice(double value) => appliedPriceCents = (value * 100).round();

  double get itemTotal => itemTotalCents / 100.0;
  set itemTotal(double value) => itemTotalCents = (value * 100).round();

  double? costPrice; // Added: The cost price of the item at the time of sale (made nullable)
  double? actualCostPrice; // التكلفة الفعلية للمنتج في وقت البيع - للحسابات الدقيقة
  // الكميات - حقل واحد فقط يُستخدم في كل مرة
  double? quantityIndividual; // Quantity in pieces or meters
  double? quantityLargeUnit; // Quantity in cartons/packets or full meters
  String? saleType; // نوع البيع بالحرف العربي: ق/ك/م/ل
  double? unitsInLargeUnit; // عدد القطع في الكرتون أو الأمتار في اللفة (للوحدة الكبيرة)

  // --- أضف هذا الحقل ---
  final String uniqueId;

  // 🔄 ربط ذري للمنتج عبر sync_uuid (لمزامنة المخزون بين الأجهزة)
  String? productSyncUuid;

  // Controllers for UI binding
  late TextEditingController productNameController;
  late TextEditingController quantityIndividualController;
  late TextEditingController quantityLargeUnitController;
  late TextEditingController appliedPriceController;
  late TextEditingController itemTotalController;
  late TextEditingController saleTypeController;

  InvoiceItem({
    this.id,
    required this.invoiceId,
    this.productId,
    required this.productName,
    required this.unit,
    double unitPrice = 0.0,
    int? unitPriceCents,
    this.quantityIndividual,
    this.quantityLargeUnit,
    double appliedPrice = 0.0,
    int? appliedPriceCents,
    double itemTotal = 0.0,
    int? itemTotalCents,
    this.costPrice, // Made optional
    this.actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
    this.saleType, // أضف هذا
    this.unitsInLargeUnit,
    String? uniqueId, // أضف هذا
    this.productSyncUuid, // 🔄 ربط ذري للمنتج عبر sync_uuid
  })  : unitPriceCents = unitPriceCents ?? (unitPrice * 100).round(),
        appliedPriceCents = appliedPriceCents ?? (appliedPrice * 100).round(),
        itemTotalCents = itemTotalCents ?? (itemTotal * 100).round(),
        uniqueId = uniqueId ?? 'item_${DateTime.now().microsecondsSinceEpoch}' {
    // Initialize controllers with initial values - مع تنسيق الأرقام بفواصل
    productNameController = TextEditingController(text: productName);
    quantityIndividualController =
        TextEditingController(text: quantityIndividual != null ? _formatNumber(quantityIndividual!) : '');
    quantityLargeUnitController =
        TextEditingController(text: quantityLargeUnit != null ? _formatNumber(quantityLargeUnit!) : '');
    appliedPriceController =
        TextEditingController(text: _formatNumber(appliedPrice));
    itemTotalController = TextEditingController(text: _formatNumber(itemTotal));
    saleTypeController = TextEditingController(text: saleType ?? '');
  }

  void initializeControllers() {
    productNameController.text = productName;
    quantityIndividualController.text = quantityIndividual != null ? _formatNumber(quantityIndividual!) : '';
    quantityLargeUnitController.text = quantityLargeUnit != null ? _formatNumber(quantityLargeUnit!) : '';
    appliedPriceController.text = _formatNumber(appliedPrice);
    itemTotalController.text = _formatNumber(itemTotal);
    saleTypeController.text = saleType ?? '';
  }

  void disposeControllers() {
    productNameController.dispose();
    quantityIndividualController.dispose();
    quantityLargeUnitController.dispose();
    appliedPriceController.dispose();
    itemTotalController.dispose();
    saleTypeController.dispose();
  }

  // Convert an InvoiceItem object into a Map object
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_name': productName,
      'unit': unit,
      'unit_price': unitPrice, // Selling unit price
      'unit_price_cents': unitPriceCents,
      'cost_price': costPrice ?? 0.0, // إرسال 0.0 بدلاً من null لتجنب خطأ NOT NULL
      'actual_cost_price': actualCostPrice ?? 0.0, // التكلفة الفعلية للمنتج في وقت البيع
      'quantity_individual': quantityIndividual ?? 0.0, // تجنب خطأ NOT NULL
      'quantity_large_unit': quantityLargeUnit ?? 0.0, // تجنب خطأ NOT NULL
      'applied_price': appliedPrice,
      'applied_price_cents': appliedPriceCents,
      'item_total': itemTotal,
      'item_total_cents': itemTotalCents,
      'sale_type': saleType, // أضف هذا
      'units_in_large_unit': unitsInLargeUnit,
      'unique_id': uniqueId, // أضف هذا
      'product_sync_uuid': productSyncUuid, // 🔄 ربط ذري للمنتج عبر sync_uuid
    };
  }

  // Extract an InvoiceItem object from a Map object
  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: تنظيف البيانات - استخدام الكمية الصحيحة بناءً على نوع البيع
    // ═══════════════════════════════════════════════════════════════════════════
    final String? saleType = map['sale_type'] as String?;
    double? quantityIndividual = (map['quantity_individual'] as num?)?.toDouble();
    double? quantityLargeUnit = (map['quantity_large_unit'] as num?)?.toDouble();
    
    // إذا كان نوع البيع قطعة أو متر، استخدم quantityIndividual فقط
    // وإلا استخدم quantityLargeUnit فقط
    if (saleType == 'قطعة' || saleType == 'متر') {
      // للوحدات الصغيرة: استخدم quantityIndividual، وإذا كانت null استخدم quantityLargeUnit
      if (quantityIndividual == null && quantityLargeUnit != null) {
        quantityIndividual = quantityLargeUnit;
      }
      quantityLargeUnit = null; // مسح القيمة الأخرى
    } else if (saleType != null && saleType.isNotEmpty) {
      // للوحدات الكبيرة (لفة، كرتون، إلخ): استخدم quantityLargeUnit
      if (quantityLargeUnit == null && quantityIndividual != null) {
        quantityLargeUnit = quantityIndividual;
      }
      quantityIndividual = null; // مسح القيمة الأخرى
    }

    final double parsedUnitPrice = (map['unit_price'] as num?)?.toDouble() ?? 0.0;
    final int? parsedUnitPriceCents = map['unit_price_cents'] as int?;
    final int calculatedUnitPriceCents = (parsedUnitPrice * 100).round();
    final int finalUnitPriceCents = (parsedUnitPriceCents != null && (parsedUnitPriceCents / 100.0 - parsedUnitPrice).abs() < 0.001)
        ? parsedUnitPriceCents
        : calculatedUnitPriceCents;

    final double parsedAppliedPrice = (map['applied_price'] as num?)?.toDouble() ?? 0.0;
    final int? parsedAppliedPriceCents = map['applied_price_cents'] as int?;
    final int calculatedAppliedPriceCents = (parsedAppliedPrice * 100).round();
    final int finalAppliedPriceCents = (parsedAppliedPriceCents != null && (parsedAppliedPriceCents / 100.0 - parsedAppliedPrice).abs() < 0.001)
        ? parsedAppliedPriceCents
        : calculatedAppliedPriceCents;

    final double parsedItemTotal = (map['item_total'] as num?)?.toDouble() ?? 0.0;
    final int? parsedItemTotalCents = map['item_total_cents'] as int?;
    final int calculatedItemTotalCents = (parsedItemTotal * 100).round();
    final int finalItemTotalCents = (parsedItemTotalCents != null && (parsedItemTotalCents / 100.0 - parsedItemTotal).abs() < 0.001)
        ? parsedItemTotalCents
        : calculatedItemTotalCents;
    
    return InvoiceItem(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] ?? 0,
      productId: map['product_id'] as int?,
      productName: map['product_name'] ?? '',
      unit: map['unit'] ?? '',
      unitPrice: parsedUnitPrice,
      unitPriceCents: finalUnitPriceCents,
      costPrice: (map['cost_price'] as num?)?.toDouble(),
      actualCostPrice: (map['actual_cost_price'] as num?)?.toDouble(),
      quantityIndividual: quantityIndividual,
      quantityLargeUnit: quantityLargeUnit,
      appliedPrice: parsedAppliedPrice,
      appliedPriceCents: finalAppliedPriceCents,
      itemTotal: parsedItemTotal,
      itemTotalCents: finalItemTotalCents,
      saleType: saleType,
      unitsInLargeUnit: (map['units_in_large_unit'] as num?)?.toDouble(),
      uniqueId: map['unique_id'] ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
      productSyncUuid: map['product_sync_uuid'] as String?,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 إصلاح: استخدام Object? sentinel pattern للسماح بتمرير null بشكل صريح
  // ═══════════════════════════════════════════════════════════════════════════
  static const _sentinel = Object();
  
  InvoiceItem copyWith({
    int? id,
    int? invoiceId,
    int? productId,
    String? productName,
    String? unit,
    double? unitPrice,
    double? costPrice,
    double? actualCostPrice,
    Object? quantityIndividual = _sentinel, // استخدام Object? للسماح بـ null
    Object? quantityLargeUnit = _sentinel,  // استخدام Object? للسماح بـ null
    double? appliedPrice,
    double? itemTotal,
    String? saleType,
    double? unitsInLargeUnit,
    String? uniqueId,
    String? productSyncUuid,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      actualCostPrice: actualCostPrice ?? this.actualCostPrice,
      // 🔧 إصلاح: السماح بتمرير null لمسح القيمة القديمة
      quantityIndividual: quantityIndividual == _sentinel 
          ? this.quantityIndividual 
          : quantityIndividual as double?,
      quantityLargeUnit: quantityLargeUnit == _sentinel 
          ? this.quantityLargeUnit 
          : quantityLargeUnit as double?,
      appliedPrice: appliedPrice ?? this.appliedPrice,
      itemTotal: itemTotal ?? this.itemTotal,
      saleType: saleType ?? this.saleType,
      unitsInLargeUnit: unitsInLargeUnit ?? this.unitsInLargeUnit,
      uniqueId: uniqueId ?? this.uniqueId,
      productSyncUuid: productSyncUuid ?? this.productSyncUuid,
    );
  }
}
