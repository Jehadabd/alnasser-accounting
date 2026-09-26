import 'supplier_delegate.dart';

/// نموذج المورد (Odoo-Style)
/// يمثل مورد/بائع يمكنك شراء المنتجات منه
class Supplier {
  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final String currency; // العملة المفضلة: 'IQD' أو 'USD'
  final String paymentTerms; // شروط الدفع: 'cash' أو 'credit'
  final int creditDays; // أيام الآجل (إذا كانت credit)
  final double totalDebtIqd; // الدين بالدينار العراقي
  final double totalDebtUsd; // الدين بالدولار الأمريكي
  final double totalPurchases; // إجمالي المشتريات
  final double currentBalance; // الرصيد الحالي (الدين العام)
  final int totalInvoices; // عدد الفواتير
  final int totalPayments; // عدد الدفعات
  final String? notes;
  final List<SupplierDelegate>? delegates; // 👥 المندوبين (Optional for runtime)
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.currency = 'IQD',
    this.paymentTerms = 'cash',
    this.creditDays = 0,
    this.totalDebtIqd = 0.0,
    this.totalDebtUsd = 0.0,
    this.totalPurchases = 0.0,
    this.currentBalance = 0.0,
    this.totalInvoices = 0,
    this.totalPayments = 0,
    this.notes,
    this.delegates,
    required this.createdAt,
    required this.updatedAt,
  });

  /// الدين الكلي بالعملة المفضلة للمورد
  double get totalDebt => currency == 'USD' ? totalDebtUsd : totalDebtIqd;

  /// هل عليه دين؟ (بأي من العملتين)
  ///
  /// كانت تعتمد على currentBalance وحده، فمورد عليه دين بالدولار فقط
  /// كان يظهر وكأن لا دين عليه.
  bool get hasDebt => totalDebtIqd > 0.01 || totalDebtUsd > 0.01;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'currency': currency,
      'payment_terms': paymentTerms,
      'credit_days': creditDays,
      'total_debt_iqd': totalDebtIqd,
      'total_debt_usd': totalDebtUsd,
      'total_purchases': totalPurchases,
      'current_balance': currentBalance,
      'total_invoices': totalInvoices,
      'total_payments': totalPayments,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'],
      name: map['company_name'] ?? map['name'], // Handle both column names just in case
      phone: map['phone_number'] ?? map['phone'],
      address: map['address'],
      currency: map['currency'] ?? 'IQD',
      paymentTerms: map['payment_terms'] ?? 'cash',
      creditDays: map['credit_days'] ?? 0,
      totalDebtIqd: (map['total_debt_iqd'] as num?)?.toDouble() ?? (map['total_debt'] as num?)?.toDouble() ?? 0.0,
      totalDebtUsd: (map['total_debt_usd'] as num?)?.toDouble() ?? 0.0,
      totalPurchases: (map['total_purchases'] as num?)?.toDouble() ?? 0.0,
      currentBalance: (map['current_balance'] as num?)?.toDouble() ?? 0.0,
      totalInvoices: map['total_invoices'] ?? 0,
      totalPayments: map['total_payments'] ?? 0,
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at'] ?? map['created_at']),
    );
  }

  Supplier copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    String? currency,
    String? paymentTerms,
    int? creditDays,
    double? totalDebtIqd,
    double? totalDebtUsd,
    double? totalPurchases,
    double? currentBalance,
    int? totalInvoices,
    int? totalPayments,
    String? notes,
    List<SupplierDelegate>? delegates,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      currency: currency ?? this.currency,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      creditDays: creditDays ?? this.creditDays,
      totalDebtIqd: totalDebtIqd ?? this.totalDebtIqd,
      totalDebtUsd: totalDebtUsd ?? this.totalDebtUsd,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      currentBalance: currentBalance ?? this.currentBalance,
      totalInvoices: totalInvoices ?? this.totalInvoices,
      totalPayments: totalPayments ?? this.totalPayments,
      notes: notes ?? this.notes,
      delegates: delegates ?? this.delegates,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
