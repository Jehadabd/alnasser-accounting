// models/customer.dart
class Customer {
  final int? id;
  final String name;
  final String? phone;
  final int currentTotalDebtCents;
  final String? generalNote;
  final String? address;
  final DateTime createdAt;
  final DateTime lastModifiedAt;
  final String? audioNotePath;
  final String? syncUuid; // 🔄 معرف المزامنة الفريد
  final bool isDeleted; // 🗑️ علامة الحذف المنطقي

  double get currentTotalDebt => currentTotalDebtCents / 100.0;

  Customer({
    this.id,
    required this.name,
    this.phone,
    double currentTotalDebt = 0.0,
    int? currentTotalDebtCents,
    this.generalNote,
    this.address,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    this.audioNotePath,
    this.syncUuid,
    this.isDeleted = false,
  })  : currentTotalDebtCents = currentTotalDebtCents ?? (currentTotalDebt * 100).round(),
        createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'current_total_debt': currentTotalDebt,
      'current_total_debt_cents': currentTotalDebtCents,
      'general_note': generalNote,
      'address': address,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'audio_note_path': audioNotePath,
      'sync_uuid': syncUuid,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    final double parsedDebt = (map['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    final int? parsedDebtCents = map['current_total_debt_cents'] as int?;

    // 🛡️ حساب السنتات من قيمة الدين المحدثة parsedDebt في حال وجود تفاوت مع القيم القديمة
    final int calculatedCents = (parsedDebt * 100).round();
    final int finalCents = (parsedDebtCents != null && (parsedDebtCents / 100.0 - parsedDebt).abs() < 0.001)
        ? parsedDebtCents
        : calculatedCents;

    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String?,
      currentTotalDebt: parsedDebt,
      currentTotalDebtCents: finalCents,
      generalNote: map['general_note'] as String?,
      address: map['address'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastModifiedAt: DateTime.parse(map['last_modified_at'] as String),
      audioNotePath: map['audio_note_path'] as String?,
      syncUuid: map['sync_uuid'] as String?,
      isDeleted: ((map['is_deleted'] as int?) ?? 0) == 1,
    );
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    double? currentTotalDebt,
    String? generalNote,
    String? address,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    String? audioNotePath,
    String? syncUuid,
    bool? isDeleted,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      currentTotalDebt: currentTotalDebt ?? this.currentTotalDebt,
      generalNote: generalNote ?? this.generalNote,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      audioNotePath: audioNotePath ?? this.audioNotePath,
      syncUuid: syncUuid ?? this.syncUuid,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
