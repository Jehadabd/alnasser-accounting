/// نموذج بند فاتورة المشتريات (Odoo-Style)
/// يمثل منتج واحد في فاتورة الشراء مع منطق تحويل الوحدات
class PurchaseInvoiceItem {
  final int? id;
  final int? invoiceId;
  final int productId;
  final String? productName; // للعرض فقط، لا يُحفظ في DB
  final String unitName; // الوحدة المختارة (كرتون، قطعة، إلخ)
  final double quantity; // الكمية بالوحدة المختارة
  final double unitPrice; // سعر الوحدة المختارة
  final double conversionFactor; // كم وحدة أساسية في الوحدة المختارة
  final double totalPrice;
  final double receivedQuantity; // الكمية المستلمة فعلياً (للاستلام الجزئي)

  PurchaseInvoiceItem({
    this.id,
    this.invoiceId,
    required this.productId,
    this.productName,
    required this.unitName,
    required this.quantity,
    required this.unitPrice,
    this.conversionFactor = 1.0,
    required this.totalPrice,
    this.receivedQuantity = 0.0,
  });

  /// الكمية بالوحدة الأساسية (القطع)
  double get baseQuantity => quantity * conversionFactor;

  /// سعر الوحدة الأساسية (القطعة)
  double get baseUnitCost => conversionFactor > 0 ? unitPrice / conversionFactor : unitPrice;

  /// هل تم الاستلام بالكامل؟
  bool get isFullyReceived => receivedQuantity >= quantity;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'unit_name': unitName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'conversion_factor': conversionFactor,
      'total_price': totalPrice,
      'received_quantity': receivedQuantity,
    };
  }

  factory PurchaseInvoiceItem.fromMap(Map<String, dynamic> map) {
    return PurchaseInvoiceItem(
      id: map['id'],
      invoiceId: map['invoice_id'],
      productId: map['product_id'],
      productName: map['product_name'],
      unitName: map['unit_name'],
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      conversionFactor: (map['conversion_factor'] as num?)?.toDouble() ?? 1.0,
      totalPrice: (map['total_price'] as num).toDouble(),
      receivedQuantity: (map['received_quantity'] as num?)?.toDouble() ?? 0.0,
    );
  }

  PurchaseInvoiceItem copyWith({
    int? id,
    int? invoiceId,
    int? productId,
    String? productName,
    String? unitName,
    double? quantity,
    double? unitPrice,
    double? conversionFactor,
    double? totalPrice,
    double? receivedQuantity,
  }) {
    return PurchaseInvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unitName: unitName ?? this.unitName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      conversionFactor: conversionFactor ?? this.conversionFactor,
      totalPrice: totalPrice ?? this.totalPrice,
      receivedQuantity: receivedQuantity ?? this.receivedQuantity,
    );
  }
}
