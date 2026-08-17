// models/product.dart
import 'dart:convert';

class Product {
  final int? id;
  final String name;
  final String unit; 
  final double unitPrice;
  final double? costPrice;
  final int? piecesPerUnit;
  final double? lengthPerUnit;
  final double price1;
  final double? price2;
  final double? price3;
  final double? price4;
  final double? price5;
  final double? price6; // سعر اخرى
  final String? unitHierarchy; // JSON string representing the unit hierarchy
  final String? unitCosts; // JSON string representing costs for each unit level
  final DateTime createdAt;
  final DateTime lastModifiedAt;

  // --- Odoo Integration Fields ---
  final String? sku;
  final String productType; // 'storable', 'consumable', 'service'
  final String invoicePolicy; // 'ordered', 'delivered'

  // --- Joker System Fields ---
  final int? categoryId;
  final bool isWeighable; // هل يباع بالوزن؟
  final double? baseWeight; // وزن الوحدة الأساسية (للقطعة الواحدة)
  final String? weightUnit; // وحدة الوزن (kg, g, ton)
  final bool hasExpiry; // هل له تاريخ صلاحية؟
  final DateTime? expiryDate; // تاريخ الانتهاء ✅ Added
  final String? barcode; 
  final double stockQuantity; // الكمية الحالية في المخزن (للوحدة الأساسية)
  
  // 🔔 Alert Fields
  final double? alertQuantity; // الكمية التي يبدأ عندها التنبيه (للوحدة المختارة)
  final String? alertUnit; // الوحدة المستخدمة للتنبيه (مثلاً "كرتون")

  // 🔄 حقول مزامنة المنتجات (كتالوج موحد مركزياً عبر Firebase)
  final String? syncUuid; // معرّف المزامنة الفريد للمنتج
  final String? createdByDeviceId; // الجهاز الذي أنشأ المنتج
  final String? lastModifiedByDeviceId; // آخر جهاز عدّل المنتج
  final DateTime? lastSyncedAt; // آخر مزامنة ناجحة
  final bool isDeleted; // حذف ناعم (يُزامَن بدل الحذف الفعلي)

  String get translatedUnit => unit == 'piece' ? 'قطعة' : (unit == 'meter' ? 'متر' : unit);

  Product({
    this.id,
    required this.name,
    required this.unit,
    required this.unitPrice,
    this.costPrice,
    this.piecesPerUnit,
    this.lengthPerUnit,
    required this.price1,
    this.price2,
    this.price3,
    this.price4,
    this.price5,
    this.price6,
    this.unitHierarchy,
    this.unitCosts,
    required this.createdAt,
    required this.lastModifiedAt,
    this.categoryId,
    this.isWeighable = false,
    this.baseWeight,
    this.weightUnit,
    this.hasExpiry = false,
    this.expiryDate,
    this.barcode,
    this.stockQuantity = 0.0,
    this.alertQuantity,
    this.alertUnit,
    this.sku,
    this.productType = 'storable',
    this.invoicePolicy = 'ordered',
    this.syncUuid,
    this.createdByDeviceId,
    this.lastModifiedByDeviceId,
    this.lastSyncedAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'unit': unit,
      'unit_price': unitPrice,
      'cost_price': costPrice,
      'pieces_per_unit': piecesPerUnit,
      'length_per_unit': lengthPerUnit,
      'price1': price1,
      'price2': price2,
      'price3': price3,
      'price4': price4,
      'price5': price5,
      'price6': price6,
      'unit_hierarchy': unitHierarchy,
      'unit_costs': unitCosts,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'category_id': categoryId,
      'is_weighable': isWeighable ? 1 : 0,
      'base_weight': baseWeight,
      'weight_unit': weightUnit,
      'has_expiry': hasExpiry ? 1 : 0,
      'expiry_date': expiryDate?.toIso8601String(),
      'barcode': barcode,
      'stock_quantity': stockQuantity,
      'alert_quantity': alertQuantity,
      'alert_unit': alertUnit,
      'sku': sku,
      'product_type': productType,
      'invoice_policy': invoicePolicy,
      'sync_uuid': syncUuid,
      'created_by_device_id': createdByDeviceId,
      'last_modified_by_device_id': lastModifiedByDeviceId,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      name: map['name'],
      unit: map['unit'],
      unitPrice: (map['unit_price'] as num).toDouble(),
      costPrice: map['cost_price'] != null ? (map['cost_price'] as num).toDouble() : null,
      piecesPerUnit: map['pieces_per_unit'],
      lengthPerUnit: map['length_per_unit'] != null ? (map['length_per_unit'] as num).toDouble() : null,
      price1: (map['price1'] as num).toDouble(),
      price2: map['price2'] != null ? (map['price2'] as num).toDouble() : null,
      price3: map['price3'] != null ? (map['price3'] as num).toDouble() : null,
      price4: map['price4'] != null ? (map['price4'] as num).toDouble() : null,
      price5: map['price5'] != null ? (map['price5'] as num).toDouble() : null,
      price6: map['price6'] != null ? (map['price6'] as num).toDouble() : null,
      unitHierarchy: map['unit_hierarchy'],
      unitCosts: map['unit_costs'],
      createdAt: DateTime.parse(map['created_at']),
      lastModifiedAt: DateTime.parse(map['last_modified_at']),
      categoryId: map['category_id'],
      isWeighable: map['is_weighable'] == 1,
      baseWeight: map['base_weight'] != null ? (map['base_weight'] as num).toDouble() : null,
      weightUnit: map['weight_unit'],
      hasExpiry: map['has_expiry'] == 1,
      expiryDate: map['expiry_date'] != null ? DateTime.parse(map['expiry_date']) : null,
      barcode: map['barcode'],
      stockQuantity: map['stock_quantity'] != null ? (map['stock_quantity'] as num).toDouble() : 0.0,
      alertQuantity: map['alert_quantity'] != null ? (map['alert_quantity'] as num).toDouble() : null,
      alertUnit: map['alert_unit'],
      sku: map['sku'],
      productType: map['product_type'] ?? 'storable',
      invoicePolicy: map['invoice_policy'] ?? 'ordered',
      syncUuid: map['sync_uuid'] as String?,
      createdByDeviceId: map['created_by_device_id'] as String?,
      lastModifiedByDeviceId: map['last_modified_by_device_id'] as String?,
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.parse(map['last_synced_at'] as String)
          : null,
      isDeleted: ((map['is_deleted'] as int?) ?? 0) == 1,
    );
  }

  Product copyWith({
    int? id,
    String? name,
    String? unit,
    double? unitPrice,
    double? costPrice,
    int? piecesPerUnit,
    double? lengthPerUnit,
    double? price1,
    double? price2,
    double? price3,
    double? price4,
    double? price5,
    double? price6,
    String? unitHierarchy,
    String? unitCosts,
    int? categoryId,
    bool? isWeighable,
    double? baseWeight,
    String? weightUnit,
    bool? hasExpiry,
    DateTime? expiryDate,
    String? barcode,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    double? stockQuantity,
    double? alertQuantity,
    String? alertUnit,
    String? sku,
    String? productType,
    String? invoicePolicy,
    String? syncUuid,
    String? createdByDeviceId,
    String? lastModifiedByDeviceId,
    DateTime? lastSyncedAt,
    bool? isDeleted,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      piecesPerUnit: piecesPerUnit ?? this.piecesPerUnit,
      lengthPerUnit: lengthPerUnit ?? this.lengthPerUnit,
      price1: price1 ?? this.price1,
      price2: price2 ?? this.price2,
      price3: price3 ?? this.price3,
      price4: price4 ?? this.price4,
      price5: price5 ?? this.price5,
      price6: price6 ?? this.price6,
      unitHierarchy: unitHierarchy ?? this.unitHierarchy,
      unitCosts: unitCosts ?? this.unitCosts,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      categoryId: categoryId ?? this.categoryId,
      isWeighable: isWeighable ?? this.isWeighable,
      baseWeight: baseWeight ?? this.baseWeight,
      weightUnit: weightUnit ?? this.weightUnit,
      hasExpiry: hasExpiry ?? this.hasExpiry,
      expiryDate: expiryDate ?? this.expiryDate,
      barcode: barcode ?? this.barcode,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      alertQuantity: alertQuantity ?? this.alertQuantity,
      alertUnit: alertUnit ?? this.alertUnit,
      sku: sku ?? this.sku,
      productType: productType ?? this.productType,
      invoicePolicy: invoicePolicy ?? this.invoicePolicy,
      syncUuid: syncUuid ?? this.syncUuid,
      createdByDeviceId: createdByDeviceId ?? this.createdByDeviceId,
      lastModifiedByDeviceId: lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  // --- Helper Methods (Restored) ---
  
  /// Returns detailed unit hierarchy as List of Maps
  List<Map<String, dynamic>> getUnitHierarchyList() {
    if (unitHierarchy == null || unitHierarchy!.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(json.decode(unitHierarchy!));
    } catch (e) {
      return [];
    }
  }

  /// Returns unit costs as Map
  Map<String, double> getUnitCostsMap() {
    if (unitCosts == null || unitCosts!.isEmpty) return {};
    try {
      Map<String, dynamic> raw = json.decode(unitCosts!);
      return raw.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (e) {
      return {};
    }
  }

  /// Returns all available units for this product (base unit + hierarchy units)
  List<String> getAllUnitLevels() {
    List<String> levels = [];
    // The base unit logic might be complex depending on how 'unit' is stored ('piece' vs 'meter') 
    // and 'isWeighable'. But generally, the 'unit' field is the base.
    // If we want to be friendly, we can check logic. 
    // For now, let's trust 'unit' and 'unitHierarchy'.
    
    // BUT: In old logic 'unit' might be 'piece' or 'meter'.
    // In Joker, we might rely on unitHierarchy heavily.
    
    // Add base unit (Use localized name if possible, here simple string)
    levels.add(unit == 'piece' ? 'قطعة' : (unit == 'meter' ? 'متر' : unit));

    for (var item in getUnitHierarchyList()) {
      if (item['unit_name'] != null) {
        levels.add(item['unit_name']);
      }
    }
    return levels;
  }
}