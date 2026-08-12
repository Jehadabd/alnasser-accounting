// lib/models/customer_receipt_voucher.dart

/// نموذج سند القبض للعميل
class CustomerReceiptVoucher {
  final int? id;
  final int receiptNumber;
  final int customerId;
  final String customerName;
  final double beforePayment;
  final double paidAmount;
  final double afterPayment;
  final int? transactionId;
  final String? notes;
  final DateTime createdAt;

  CustomerReceiptVoucher({
    this.id,
    required this.receiptNumber,
    required this.customerId,
    required this.customerName,
    required this.beforePayment,
    required this.paidAmount,
    required this.afterPayment,
    this.transactionId,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_number': receiptNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'before_payment': beforePayment,
      'paid_amount': paidAmount,
      'after_payment': afterPayment,
      'transaction_id': transactionId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CustomerReceiptVoucher.fromMap(Map<String, dynamic> map) {
    return CustomerReceiptVoucher(
      id: map['id'] as int?,
      receiptNumber: map['receipt_number'] as int,
      customerId: map['customer_id'] as int,
      customerName: map['customer_name'] as String,
      beforePayment: (map['before_payment'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      afterPayment: (map['after_payment'] as num).toDouble(),
      transactionId: map['transaction_id'] as int?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
