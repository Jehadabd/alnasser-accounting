/// نموذج المندوب (Delegate)
/// يمثل الشخص الذي يمثل الشركة (المورد) والذي يتم التعامل معه مباشرة
class SupplierDelegate {
  final int? id;
  final int supplierId;
  final String name;
  final String? phone;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  SupplierDelegate({
    this.id,
    required this.supplierId,
    required this.name,
    this.phone,
    this.notes,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'name': name,
      'phone': phone,
      'notes': notes,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SupplierDelegate.fromMap(Map<String, dynamic> map) {
    return SupplierDelegate(
      id: map['id'],
      supplierId: map['supplier_id'],
      name: map['name'],
      phone: map['phone'],
      notes: map['notes'],
      isActive: (map['is_active'] ?? 1) == 1,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
    );
  }

  SupplierDelegate copyWith({
    int? id,
    int? supplierId,
    String? name,
    String? phone,
    String? notes,
    bool? isActive,
  }) {
    return SupplierDelegate(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt, // Usually copyWith doesn't change creation date
    );
  }
}
