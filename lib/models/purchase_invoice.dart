/// نموذج فاتورة المشتريات (Odoo-Style)
/// يمثل فاتورة شراء من مورد
class PurchaseInvoice {
  final int? id;
  final String invoiceNumber; // رقم الفاتورة الورقي
  final int supplierId;
  final int? delegateId; // 👤 المندوب (Optional)
  final double totalAmount;
  final double paidAmount;
  final String currency; // 'IQD' or 'USD'
  final String status; // 'draft', 'confirmed', 'partial', 'paid'
  final DateTime date;
  final DateTime? dueDate;
  final int? createdByUserId;
  final String? notes;
  final DateTime? lastModifiedAt;
  final String? attachmentPath; // 📎 مسار الملف المرفق

  PurchaseInvoice({
    this.id,
    required this.invoiceNumber,
    required this.supplierId,
    this.delegateId,
    this.totalAmount = 0.0,
    this.paidAmount = 0.0,
    this.currency = 'IQD',
    this.status = 'draft',
    required this.date,
    this.dueDate,
    this.createdByUserId,
    this.notes,
    this.lastModifiedAt,
    this.attachmentPath,
  });

  /// المبلغ المتبقي
  double get remainingAmount => totalAmount - paidAmount;

  /// هل مدفوعة بالكامل؟
  bool get isPaid => remainingAmount <= 0;

  /// هل مدفوعة جزئياً؟
  bool get isPartial => paidAmount > 0 && paidAmount < totalAmount;

  /// اسم الحالة بالعربي
  String get statusArabic {
    switch (status) {
      case 'draft': return 'مسودة';
      case 'confirmed': return 'مؤكدة';
      case 'partial': return 'مدفوعة جزئياً';
      case 'paid': return 'مدفوعة';
      default: return status;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_number': invoiceNumber,
      'supplier_id': supplierId,
      'delegate_id': delegateId,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'currency': currency,
      'status': status,
      'date': date.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'created_by_user_id': createdByUserId,
      'created_by_user_id': createdByUserId,
      'notes': notes,
      'last_modified_at': lastModifiedAt?.toIso8601String(),
      'attachment_path': attachmentPath,
    };
  }

  factory PurchaseInvoice.fromMap(Map<String, dynamic> map) {
    return PurchaseInvoice(
      id: map['id'],
      invoiceNumber: map['invoice_number'],
      supplierId: map['supplier_id'],
      delegateId: map['delegate_id'],
      totalAmount: map['total_amount'] ?? 0.0,
      paidAmount: map['paid_amount'] ?? 0.0,
      currency: map['currency'] ?? 'IQD',
      status: map['status'] ?? 'draft',
      date: DateTime.parse(map['date']),
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : null,
      createdByUserId: map['created_by_user_id'],
      notes: map['notes'],
      lastModifiedAt: map['last_modified_at'] != null ? DateTime.parse(map['last_modified_at']) : null,
      attachmentPath: map['attachment_path'],
    );
  }

  PurchaseInvoice copyWith({
    int? id,
    String? invoiceNumber,
    int? supplierId,
    int? delegateId,
    double? totalAmount,
    double? paidAmount,
    String? currency,
    String? status,
    DateTime? date,
    DateTime? dueDate,
    int? createdByUserId,
    String? notes,
    DateTime? lastModifiedAt,
    String? attachmentPath,
  }) {
    return PurchaseInvoice(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      supplierId: supplierId ?? this.supplierId,
      delegateId: delegateId ?? this.delegateId,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      notes: notes ?? this.notes,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      attachmentPath: attachmentPath ?? this.attachmentPath,
    );
  }
}
