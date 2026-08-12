/// نموذج دفعة المورد (Odoo-Style)
/// يمثل دفعة/سداد للمورد
class SupplierPayment {
  final int? id;
  final int supplierId;
  final int? delegateId; // معرف المندوب (اختياري)
  final double amount;
  final String currency; // 'IQD' or 'USD'
  final String paymentMethod; // 'cash', 'bank', 'transfer'
  final DateTime date;
  final int? receiptNumber; // رقم سند القبض
  final String? notes;
  final int? createdByUserId;

  SupplierPayment({
    this.id,
    required this.supplierId,
    this.delegateId,

    required this.amount,
    this.currency = 'IQD',
    this.paymentMethod = 'cash',
    required this.date,
    this.receiptNumber,
    this.notes,
    this.createdByUserId,
  });

  /// اسم طريقة الدفع بالعربي
  String get paymentMethodArabic {
    switch (paymentMethod) {
      case 'cash': return 'نقداً';
      case 'bank': return 'تحويل بنكي';
      case 'transfer': return 'حوالة';
      default: return paymentMethod;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'delegate_id': delegateId,

      'amount': amount,
      'currency': currency,
      'payment_method': paymentMethod,
      'date': date.toIso8601String(),
      'receipt_number': receiptNumber,
      'notes': notes,
      'created_by_user_id': createdByUserId,
    };
  }

  factory SupplierPayment.fromMap(Map<String, dynamic> map) {
    return SupplierPayment(
      id: map['id'],
      supplierId: map['supplier_id'],
      delegateId: map['delegate_id'],

      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] ?? 'IQD',
      paymentMethod: map['payment_method'] ?? 'cash',
      date: DateTime.parse(map['date']),
      receiptNumber: map['receipt_number'],
      notes: map['notes'],
      createdByUserId: map['created_by_user_id'],
    );
  }

  SupplierPayment copyWith({
    int? id,
    int? supplierId,
    int? delegateId,
    double? amount,
    String? currency,
    String? paymentMethod,
    DateTime? date,
    int? receiptNumber,
    String? notes,
    int? createdByUserId,
  }) {
    return SupplierPayment(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      delegateId: delegateId ?? this.delegateId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      date: date ?? this.date,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      notes: notes ?? this.notes,
      createdByUserId: createdByUserId ?? this.createdByUserId,
    );
  }
}
