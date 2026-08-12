// lib/services/sync/sync_validation.dart
// 🔐 التحقق من صحة البيانات الواردة من Firebase قبل تطبيقها محلياً.
// طبقة دفاعية: ترفض أي وثيقة لا تستوفي الحقول الإلزامية أو تحوي قيماً مشبوهة.

/// نتيجة التحقق من صحة وثيقة قادمة من السحابة.
class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  const ValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  factory ValidationResult.valid() => const ValidationResult(isValid: true);
  factory ValidationResult.invalid(List<String> errors) =>
      ValidationResult(isValid: false, errors: errors);
}

class SyncValidation {
  SyncValidation._();

  /// تعقيم نص واحد: إزالة المحارف الخطيرة على قاعدة البيانات/الـ UI.
  static String sanitizeString(String? input) {
    if (input == null) return '';
    // إزالة محارف التحكم/null بايت وقاطع أسطر مزدوجة مفرطة
    return input
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .trim();
  }

  /// تعقيم خريطة كاملة من الوثيقة: يطبّق sanitizeString على كل قيمة نصية.
  static Map<String, dynamic> sanitizeMap(Map<String, dynamic>? input) {
    if (input == null) return {};
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final v = entry.value;
      if (v is String) {
        out[entry.key] = sanitizeString(v);
      } else if (v is Map) {
        out[entry.key] = sanitizeMap(Map<String, dynamic>.from(v));
      } else if (v is List) {
        out[entry.key] = v
            .map((e) => e is String
                ? sanitizeString(e)
                : (e is Map ? sanitizeMap(Map<String, dynamic>.from(e)) : e))
            .toList();
      } else {
        out[entry.key] = v;
      }
    }
    return out;
  }

  /// التحقق من صحة وثيقة عميل قادمة من Firestore.
  static ValidationResult validateFirebaseCustomerData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return ValidationResult.invalid(['الوثيقة فارغة']);
    }
    final errors = <String>[];

    final name = data['name']?.toString();
    if (name == null || name.trim().isEmpty) {
      errors.add('اسم العميل مفقود');
    }

    // الرصيد إن وُجد يجب أن يكون رقماً
    final currentDebt = data['currentTotalDebt'] ?? data['current_total_debt'];
    if (currentDebt != null) {
      final debt = num.tryParse(currentDebt.toString());
      if (debt == null) {
        errors.add('رصيد العميل ليس رقماً صالحاً');
      }
    }

    // sync_uuid إلزامي لمطابقة الهوية عبر الأجهزة
    final syncUuid = (data['syncUuid'] ?? data['sync_uuid'] ?? data['transaction_uuid'])?.toString();
    if (syncUuid == null || syncUuid.trim().isEmpty) {
      errors.add('sync_uuid مفقود');
    }

    if (errors.isEmpty) return ValidationResult.valid();
    return ValidationResult.invalid(errors);
  }

  /// التحقق من صحة وثيقة معاملة قادمة من Firestore.
  static ValidationResult validateFirebaseTransactionData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return ValidationResult.invalid(['الوثيقة فارغة']);
    }
    final errors = <String>[];

    final amount = data['amountChanged'] ?? data['amount_changed'];
    if (amount == null || num.tryParse(amount.toString()) == null) {
      errors.add('amount_changed مفقود أو ليس رقماً');
    }

    final customerId = data['customerId'] ?? data['customer_id'];
    final customerSyncUuid = data['customerSyncUuid'] ?? data['customer_sync_uuid'];
    if (customerId == null && customerSyncUuid == null) {
      errors.add('معرّف العميل مفقود (customer_id أو customer_sync_uuid)');
    }
    final syncUuid = (data['syncUuid'] ?? data['sync_uuid'] ?? data['transaction_uuid'])?.toString();
    if (syncUuid == null || syncUuid.trim().isEmpty) {
      errors.add('sync_uuid مفقود');
    }

    if (errors.isEmpty) return ValidationResult.valid();
    return ValidationResult.invalid(errors);
  }
}
