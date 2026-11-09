// lib/erp/delivery/delivery_models.dart
//
// 🚚 نماذج شركات التوصيل وطلباتها، والحساب الصافي (دوال صافية مختبَرة).
// المبالغ بالفلس (عدد صحيح × 100) فلا يتراكم خطأ الكسور في المجاميع.
//
// الحساب مع الشركة لكل طلب غير مُسوّى:
//   • سُلّم  ⇒ الشركة قبضت مبلغ التحصيل لنا، ولها أجرة التوصيل.
//   • راجع   ⇒ لا تحصيل، ولها أجرة التوصيل (إن سُجّلت للطلب).
//   • ملغى/جديد/مع المندوب ⇒ لا شيء بعد.
//   الصافي المستحق لنا = Σ التحصيل − Σ الأجور.

enum DeliveryStatus { pending, out, delivered, returned, cancelled }

extension DeliveryStatusX on DeliveryStatus {
  String get label => switch (this) {
        DeliveryStatus.pending => 'جديد',
        DeliveryStatus.out => 'مع المندوب',
        DeliveryStatus.delivered => 'سُلّم',
        DeliveryStatus.returned => 'راجع',
        DeliveryStatus.cancelled => 'ملغى',
      };

  /// الحالات التي يمكن الانتقال إليها من هذه الحالة. المُسوّى لا يتغير.
  List<DeliveryStatus> get next => switch (this) {
        DeliveryStatus.pending => [DeliveryStatus.out, DeliveryStatus.cancelled],
        DeliveryStatus.out => [DeliveryStatus.delivered, DeliveryStatus.returned, DeliveryStatus.pending],
        DeliveryStatus.delivered => [DeliveryStatus.returned],
        DeliveryStatus.returned => [DeliveryStatus.out],
        DeliveryStatus.cancelled => [DeliveryStatus.pending],
      };

  bool get isFinal => this == DeliveryStatus.delivered || this == DeliveryStatus.returned;

  static DeliveryStatus parse(String? s) =>
      DeliveryStatus.values.firstWhere((x) => x.name == s, orElse: () => DeliveryStatus.pending);
}

int toFils(double v) => (v * 100).round();
double fromFils(int v) => v / 100.0;

class DeliveryCompany {
  DeliveryCompany({
    this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    this.customerId,
    this.defaultFeeFils = 0,
    this.active = true,
  });
  final int? id;
  final String name, phone, notes;

  /// حساب الشركة في سجل الديون (اختياري) — للتسوية بوصل قبض.
  final int? customerId;
  final int defaultFeeFils;
  final bool active;

  Map<String, Object?> toMap() => {
        'name': name.trim(),
        'phone': phone.trim(),
        'notes': notes.trim(),
        'customer_id': customerId,
        'default_fee_fils': defaultFeeFils,
        'active': active ? 1 : 0,
      };

  factory DeliveryCompany.fromMap(Map<String, Object?> m) => DeliveryCompany(
        id: m['id'] as int?,
        name: '${m['name'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        notes: '${m['notes'] ?? ''}',
        customerId: m['customer_id'] as int?,
        defaultFeeFils: (m['default_fee_fils'] as num?)?.toInt() ?? 0,
        active: (m['active'] as int? ?? 1) == 1,
      );
}

class DeliveryOrder {
  DeliveryOrder({
    this.id,
    required this.companyId,
    this.invoiceId,
    this.invoiceNumber = '',
    required this.customerName,
    this.phone = '',
    this.area = '',
    this.address = '',
    required this.codFils,
    required this.feeFils,
    this.status = DeliveryStatus.pending,
    this.note = '',
    required this.createdAt,
    this.updatedAt,
    this.settlementId,
  });
  final int? id;
  final int companyId;
  final int? invoiceId;
  final String invoiceNumber, customerName, phone, area, address, note;

  /// مبلغ التحصيل من الزبون عند التسليم.
  final int codFils;

  /// أجرة التوصيل للشركة.
  final int feeFils;
  final DeliveryStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? settlementId;

  bool get settled => settlementId != null;

  Map<String, Object?> toMap() => {
        'company_id': companyId,
        'invoice_id': invoiceId,
        'invoice_number': invoiceNumber.trim(),
        'customer_name': customerName.trim(),
        'phone': phone.trim(),
        'area': area.trim(),
        'address': address.trim(),
        'cod_fils': codFils,
        'fee_fils': feeFils,
        'status': status.name,
        'note': note.trim(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': (updatedAt ?? createdAt).toIso8601String(),
        'settlement_id': settlementId,
      };

  factory DeliveryOrder.fromMap(Map<String, Object?> m) => DeliveryOrder(
        id: m['id'] as int?,
        companyId: m['company_id'] as int,
        invoiceId: m['invoice_id'] as int?,
        invoiceNumber: '${m['invoice_number'] ?? ''}',
        customerName: '${m['customer_name'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        area: '${m['area'] ?? ''}',
        address: '${m['address'] ?? ''}',
        codFils: (m['cod_fils'] as num?)?.toInt() ?? 0,
        feeFils: (m['fee_fils'] as num?)?.toInt() ?? 0,
        status: DeliveryStatusX.parse(m['status'] as String?),
        note: '${m['note'] ?? ''}',
        createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime(2000),
        updatedAt: DateTime.tryParse('${m['updated_at'] ?? ''}'),
        settlementId: m['settlement_id'] as int?,
      );
}

/// حساب طلبات غير مُسوّاة مع شركة. دالة صافية.
class DeliveryBalance {
  DeliveryBalance._(this.codFils, this.feeFils, this.delivered, this.returned, this.open, this.orders);

  final int codFils, feeFils, delivered, returned, open;

  /// الطلبات الداخلة في التسوية (سُلّم أو راجع، غير مُسوّاة).
  final List<DeliveryOrder> orders;

  int get netFils => codFils - feeFils;

  static DeliveryBalance of(Iterable<DeliveryOrder> all) {
    var cod = 0, fee = 0, delivered = 0, returned = 0, open = 0;
    final settle = <DeliveryOrder>[];
    for (final o in all) {
      if (o.settled) continue;
      switch (o.status) {
        case DeliveryStatus.delivered:
          cod += o.codFils;
          fee += o.feeFils;
          delivered++;
          settle.add(o);
        case DeliveryStatus.returned:
          fee += o.feeFils;
          returned++;
          settle.add(o);
        case DeliveryStatus.pending || DeliveryStatus.out:
          open++;
        case DeliveryStatus.cancelled:
          break;
      }
    }
    return DeliveryBalance._(cod, fee, delivered, returned, open, settle);
  }
}
