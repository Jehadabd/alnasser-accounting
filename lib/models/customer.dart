// models/customer.dart
class Customer {
  final int? id;
  final String name;
  final String? phone;
  final double currentTotalDebt;
  final String? generalNote;
  final String? address;
  final DateTime createdAt;
  final DateTime lastModifiedAt;
  final String? audioNotePath;
  final String? syncUuid; // 🔄 معرف المزامنة الفريد

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.currentTotalDebt = 0.0,
    this.generalNote,
    this.address,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    this.audioNotePath,
    this.syncUuid,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'current_total_debt': currentTotalDebt,
      'general_note': generalNote,
      'address': address,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'audio_note_path': audioNotePath,
      'sync_uuid': syncUuid,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      currentTotalDebt: map['current_total_debt'] as double,
      generalNote: map['general_note'] as String?,
      address: map['address'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastModifiedAt: DateTime.parse(map['last_modified_at'] as String),
      audioNotePath: map['audio_note_path'] as String?,
      syncUuid: map['sync_uuid'] as String?,
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
    );
  }
}
