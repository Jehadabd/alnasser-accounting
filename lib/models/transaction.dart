// models/transaction.dart
class DebtTransaction {
  final int? id;
  final int customerId;
  final DateTime transactionDate;
  final double amountChanged;
  final double? balanceBeforeTransaction;
  final double? newBalanceAfterTransaction;
  final String? transactionNote;
  final String transactionType;
  final String? description;
  final int? invoiceId;
  final DateTime createdAt;

  final bool isCreatedByMe;
  final bool isUploaded;
  final String? transactionUuid;
  final bool isReadByOthers;
  final String? syncUuid; // 🔄 معرف المزامنة الفريد
  final String? audioNotePath; // 🎙️ مسار ملاحظة صوتية مرفقة

  DebtTransaction({
    this.id,
    required this.customerId,
    DateTime? transactionDate,
    required this.amountChanged,
    this.balanceBeforeTransaction,
    this.newBalanceAfterTransaction,
    this.transactionNote,
    required this.transactionType,
    this.description,
    this.invoiceId,
    DateTime? createdAt,

    this.isCreatedByMe = true,
    this.isUploaded = false,
    this.transactionUuid,
    this.isReadByOthers = false,
    this.syncUuid,
    this.audioNotePath,
  })  : transactionDate = transactionDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'transaction_date': transactionDate.toIso8601String(),
      'amount_changed': amountChanged,
      'balance_before_transaction': balanceBeforeTransaction,
      'new_balance_after_transaction': newBalanceAfterTransaction,
      'transaction_note': transactionNote,
      'transaction_type': transactionType,
      'description': description,
      'invoice_id': invoiceId,
      'created_at': createdAt.toIso8601String(),

      'is_created_by_me': isCreatedByMe ? 1 : 0,
      'is_uploaded': isUploaded ? 1 : 0,
      'transaction_uuid': transactionUuid,
      'is_read_by_others': isReadByOthers ? 1 : 0,
      'sync_uuid': syncUuid,
      'audio_note_path': audioNotePath,
    };
  }

  factory DebtTransaction.fromMap(Map<String, dynamic> map) {
    return DebtTransaction(
      id: map['id'] as int,
      customerId: map['customer_id'] as int,
      transactionDate: DateTime.parse(map['transaction_date'] as String),
      amountChanged: (map['amount_changed'] as num).toDouble(),
      balanceBeforeTransaction: 
          (map['balance_before_transaction'] as num?)?.toDouble(),
      newBalanceAfterTransaction:
          (map['new_balance_after_transaction'] as num?)?.toDouble(),
      transactionNote: map['transaction_note'] as String?,
      transactionType: map['transaction_type'] as String,
      description: map['description'] as String?,
      invoiceId: map['invoice_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),

      isCreatedByMe: ((map['is_created_by_me'] as int?) ?? 1) == 1,
      isUploaded: ((map['is_uploaded'] as int?) ?? 0) == 1,
      transactionUuid: map['transaction_uuid'] as String?,
      isReadByOthers: ((map['is_read_by_others'] as int?) ?? 0) == 1,
      syncUuid: map['sync_uuid'] as String?,
      audioNotePath: map['audio_note_path'] as String?,
    );
  }

  DebtTransaction copyWith({
    int? id,
    int? customerId,
    DateTime? transactionDate,
    double? amountChanged,
    double? balanceBeforeTransaction,
    double? newBalanceAfterTransaction,
    String? transactionNote,
    String? transactionType,
    String? description,
    int? invoiceId,
    DateTime? createdAt,

    bool? isCreatedByMe,
    bool? isUploaded,
    String? transactionUuid,
    bool? isReadByOthers,
    String? syncUuid,
    String? audioNotePath,
  }) {
    return DebtTransaction(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      transactionDate: transactionDate ?? this.transactionDate,
      amountChanged: amountChanged ?? this.amountChanged,
      balanceBeforeTransaction: balanceBeforeTransaction ?? this.balanceBeforeTransaction,
      newBalanceAfterTransaction:
          newBalanceAfterTransaction ?? this.newBalanceAfterTransaction,
      transactionNote: transactionNote ?? this.transactionNote,
      transactionType: transactionType ?? this.transactionType,
      description: description ?? this.description,
      invoiceId: invoiceId ?? this.invoiceId,
      createdAt: createdAt ?? this.createdAt,

      isCreatedByMe: isCreatedByMe ?? this.isCreatedByMe,
      isUploaded: isUploaded ?? this.isUploaded,
      transactionUuid: transactionUuid ?? this.transactionUuid,
      isReadByOthers: isReadByOthers ?? this.isReadByOthers,
      syncUuid: syncUuid ?? this.syncUuid,
      audioNotePath: audioNotePath ?? this.audioNotePath,
    );
  }
}
