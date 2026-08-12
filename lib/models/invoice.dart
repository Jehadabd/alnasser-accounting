// models/invoice.dart
import 'package:intl/intl.dart';

class Invoice {
  int? id;
  String customerName;
  String? customerPhone;
  String? customerAddress;
  String? installerName;
  DateTime invoiceDate;
  String paymentType;
  // Relationship with Invoice Items will be handled separately
  double totalAmount;
  double discount;
  double amountPaidOnInvoice;
  double loadingFee;
  DateTime createdAt;
  DateTime lastModifiedAt;
  int? customerId;
  String status;
  double returnAmount;
  bool isLocked;
  double pointsRate; // معدل النقاط لكل 100,000
  int? createdByUserId; // 👤 معرف المستخدم الذي أنشأ الفاتورة
  String? createdByUsername; // 👤 اسم المستخدم الذي أنشأ الفاتورة
  String? notes; // 📝 ملاحظات الفاتورة
  // 🔥 حقول مزامنة Firebase
  String? invoiceUuid; // المعرّف الفريد للفاتورة عبر الأجهزة (مفتاح وثيقة Firestore)
  String? creatorDeviceId; // معرّف الجهاز الذي أنشأ الفاتورة (لتحديد المالك)
  int version; // رقم نسخة الفاتورة لحل التعارضات (يزداد عند كل تعديل)
  // 🔢 رقم الفاتورة المرئي للمستخدم (Natural Key): [جهاز][سنة][شهر][تسلسل]
  // مثال: 120260815 - مستقل عن id التسلسلي
  String? invoiceNumber;
  int? monthlySequenceNumber; // التسلسل الشهري للترقيم
  // أعمدة مساعدة للقيد الفريد المركّب وسرعة الاستعلام (تُشتقّ من invoiceDate)
  int? invoiceYear;
  int? invoiceMonth;
  bool isCreatedByMe; // 🔥 هل هذه الفاتورة أنشئت بواسطتي؟

  Invoice({
    this.id,
    required this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.installerName,
    required this.invoiceDate,
    required this.paymentType,
    required this.totalAmount,
    this.discount = 0.0,
    this.amountPaidOnInvoice = 0.0,
    this.loadingFee = 0.0,
    required this.createdAt,
    required this.lastModifiedAt,
    this.customerId,
    this.status = 'محفوظة',
    this.returnAmount = 0.0,
    this.isLocked = false,
    this.pointsRate = 1.0,
    this.createdByUserId,
    this.createdByUsername,
    this.notes,
    this.invoiceUuid,
    this.creatorDeviceId,
    this.version = 1,
    this.monthlySequenceNumber,
    this.invoiceNumber,
    this.invoiceYear,
    this.invoiceMonth,
    this.isCreatedByMe = true,
  });

  // Helper getters
  String get formattedInvoiceDate {
    return DateFormat('yyyy-MM-dd').format(invoiceDate);
  }
  
  String get formattedInvoiceNumber {
    // ✅ أولاً: استخدام رقم الفاتورة المخزّن (Natural Key)
    if (invoiceNumber != null && invoiceNumber!.isNotEmpty) {
      return invoiceNumber!;
    }
    // ⬇️ احتياط: للفواتير القديمة قبل التحديث
    return '#${id?.toString().padLeft(5, '0') ?? 'جديد'}';
  }

  /// 🔥 هل هذه الفاتورة من إنشاء جهاز آخر (أجنبية عن جهازي)؟
  /// تُستخدم لإخفاء أزرار التعديل وحماية سجلات الغير.
  bool isForeignTo(String myDeviceId) =>
      creatorDeviceId != null &&
      creatorDeviceId!.isNotEmpty &&
      creatorDeviceId != myDeviceId;

  // Convert an Invoice object into a Map object
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
      'installer_name': installerName,
      'invoice_date': invoiceDate.toIso8601String(),
      'payment_type': paymentType,
      'total_amount': totalAmount,
      'discount': discount,
      'amount_paid_on_invoice': amountPaidOnInvoice,
      'loading_fee': loadingFee,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'customer_id': customerId,
      'status': status,
      'return_amount': returnAmount,
      'is_locked': isLocked ? 1 : 0,
      'points_rate': pointsRate,
      'created_by_user_id': createdByUserId,
      'created_by_username': createdByUsername,
      'notes': notes,
      'invoice_uuid': invoiceUuid,
      'creator_device_id': creatorDeviceId,
      'version': version,
      'monthly_sequence_number': monthlySequenceNumber,
      'invoice_number': invoiceNumber,
      'invoice_year': invoiceYear,
      'invoice_month': invoiceMonth,
      'is_created_by_me': isCreatedByMe ? 1 : 0,
    };
  }

  // Extract an Invoice object from a Map object
  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'] as int?,
      customerName: map['customer_name'] ?? '',
      customerPhone: map['customer_phone'] as String?,
      customerAddress: map['customer_address'] as String?,
      installerName: map['installer_name'] as String?,
      invoiceDate: DateTime.parse(map['invoice_date']),
      paymentType: map['payment_type'] ?? 'نقد',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      amountPaidOnInvoice: (map['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0,
      loadingFee: (map['loading_fee'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['created_at']),
      lastModifiedAt: DateTime.parse(map['last_modified_at']),
      customerId: map['customer_id'] as int?,
      status: map['status'] as String? ?? 'محفوظة',
      returnAmount: (map['return_amount'] as num?)?.toDouble() ?? 0.0,
      isLocked: (map['is_locked'] ?? 0) == 1,
      pointsRate: (map['points_rate'] as num?)?.toDouble() ?? 1.0,
      createdByUserId: map['created_by_user_id'] as int?,
      createdByUsername: map['created_by_username'] as String?,
      notes: map['notes'] as String?,
      invoiceUuid: map['invoice_uuid'] as String?,
      creatorDeviceId: map['creator_device_id'] as String?,
      version: (map['version'] as int?) ?? 1,
      monthlySequenceNumber: map['monthly_sequence_number'] as int?,
      invoiceNumber: map['invoice_number'] as String?,
      invoiceYear: map['invoice_year'] as int?,
      invoiceMonth: map['invoice_month'] as int?,
      isCreatedByMe: ((map['is_created_by_me'] as int?) ?? 1) == 1,
    );
  }

  // Optional: Implement copyWith
  Invoice copyWith({
    int? id,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? installerName,
    DateTime? invoiceDate,
    String? paymentType,
    double? totalAmount,
    double? discount,
    double? amountPaidOnInvoice,
    double? loadingFee,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    int? customerId,
    String? status,
    double? returnAmount,
    bool? isLocked,
    double? pointsRate,
    int? createdByUserId,
    String? createdByUsername,
    String? notes,
    String? invoiceUuid,
    String? creatorDeviceId,
    int? version,
    int? monthlySequenceNumber,
    String? invoiceNumber,
    int? invoiceYear,
    int? invoiceMonth,
    bool? isCreatedByMe,
  }) {
    return Invoice(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      installerName: installerName ?? this.installerName,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      paymentType: paymentType ?? this.paymentType,
      totalAmount: totalAmount ?? this.totalAmount,
      discount: discount ?? this.discount,
      amountPaidOnInvoice: amountPaidOnInvoice ?? this.amountPaidOnInvoice,
      loadingFee: loadingFee ?? this.loadingFee,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
      returnAmount: returnAmount ?? this.returnAmount,
      isLocked: isLocked ?? this.isLocked,
      pointsRate: pointsRate ?? this.pointsRate,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByUsername: createdByUsername ?? this.createdByUsername,
      notes: notes ?? this.notes,
      invoiceUuid: invoiceUuid ?? this.invoiceUuid,
      creatorDeviceId: creatorDeviceId ?? this.creatorDeviceId,
      version: version ?? this.version,
      monthlySequenceNumber: monthlySequenceNumber ?? this.monthlySequenceNumber,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceYear: invoiceYear ?? this.invoiceYear,
      invoiceMonth: invoiceMonth ?? this.invoiceMonth,
      isCreatedByMe: isCreatedByMe ?? this.isCreatedByMe,
    );
  }
}
