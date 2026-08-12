/// نموذج بند فاتورة المشتريات (Odoo-Style)
class SupplierInvoiceItem {
  final int? id;
  int invoiceId;
  final int? productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? unit;
  final String? notes;
  final DateTime createdAt;

  SupplierInvoiceItem({
    this.id,
    required this.invoiceId,
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.unit,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': (productId != null && productId! > 0) ? productId : null,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'unit': unit,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SupplierInvoiceItem.fromMap(Map<String, dynamic> map) {
    return SupplierInvoiceItem(
      id: map['id'],
      invoiceId: map['invoice_id'],
      productId: map['product_id'],
      productName: map['product_name'],
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      unit: map['unit'],
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
