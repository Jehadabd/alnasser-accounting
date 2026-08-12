// models/invoice_adjustment.dart

class InvoiceAdjustment {
  final int? id;
  final int invoiceId;
  // 'debit' = increase amount/debt, 'credit' = decrease (returns)
  final String type;
  // Signed effect on the invoice: positive for debit, negative for credit
  final double amountDelta;
  // Optional item-level details
  final int? productId;
  final String? productName;
  final double? quantity;
  final double? price;
  // Metadata to compute correct costs/profits using unit hierarchy
  final String? unit; // base unit label used by UI when saving (e.g., 'قطعة'/'متر')
  final String? saleType; // sale unit selected for this adjustment (e.g., 'باكيت', 'لفة', 'قطعة', 'متر')
  final double? unitsInLargeUnit; // number of base units within the saleType if it is a larger unit
  final String? settlementPaymentType; // 'نقد' أو 'دين' لتأثير التسوية على سجل الديون
  final String? note;
  final DateTime createdAt;

  InvoiceAdjustment({
    this.id,
    required this.invoiceId,
    required this.type,
    required this.amountDelta,
    this.productId,
    this.productName,
    this.quantity,
    this.price,
    this.note,
    this.unit,
    this.saleType,
    this.unitsInLargeUnit,
    this.settlementPaymentType,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'type': type,
      'amount_delta': amountDelta,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'price': price,
      'unit': unit,
      'sale_type': saleType,
      'units_in_large_unit': unitsInLargeUnit,
      'settlement_payment_type': settlementPaymentType,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InvoiceAdjustment.fromMap(Map<String, dynamic> map) {
    return InvoiceAdjustment(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] as int,
      type: map['type'] as String,
      amountDelta: (map['amount_delta'] as num).toDouble(),
      productId: map['product_id'] as int?,
      productName: map['product_name'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble(),
      price: (map['price'] as num?)?.toDouble(),
      unit: map['unit'] as String?,
      saleType: map['sale_type'] as String?,
      unitsInLargeUnit: (map['units_in_large_unit'] as num?)?.toDouble(),
      settlementPaymentType: map['settlement_payment_type'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}


