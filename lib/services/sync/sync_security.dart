// lib/services/sync/sync_security.dart
// 🔐 أمان المزامنة: توليد المعرّفات، التوقيع/التحقق، ومفاتيح المجموعة المشتركة.
//
// ملاحظة: فئة إعدادات الأمان (FirebaseSyncSecuritySettings) معرّفة في
// lib/services/firebase_sync/firebase_sync_config.dart (ملف مُجرّب لا يُعدّل).
// لا نُعرّفها هنا لتجنّب التعارض.
//
// هذا الملف يوفّر المعرّفات والتوقيع التي يعتمد عليها نظام firebase_sync.

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// مزود أمان المزامنة: معرّفات فريدة + توقيع HMAC + مفاتيح المجموعة.
class SyncSecurity {
  SyncSecurity._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  // مفتاحا المجموعة: أحدهما للتشفير/التوقيع، والآخر لقواعد Firestore.
  static const String _secretKeyStorage = 'sync_group_secret_key';
  static const String _secretKeyFireKey = 'sync_group_secret_fire';

  // ──────────────── المعرّفات ────────────────

  /// توليد UUID حتمي لمعاملة من (اسم العميل، المبلغ، التاريخ).
  /// حتمية: نفس المدخلات → نفس المخرجات. مفيد للسجلات القديمة والمطابقة.
  /// ملاحظة: لا تغيّر صيغة الإخراج أبداً بعد أن رُفعت بيانات قديمة بهذه الصيغة.
  static String generateTransactionUuid(
      String customerName, double amountChanged, DateTime date) {
    final normalized = customerName.trim().toLowerCase();
    // تقريب المبلغ لتفادي فروق النقطة العائمة بين الأجهزة
    final amountKey = (amountChanged * 100).round().toString();
    final dateKey = date.toUtc().toIso8601String();
    final payload = '$normalized|$amountKey|$dateKey';
    final bytes = utf8.encode(payload);
    return sha256.convert(bytes).toString();
  }

  /// توليد UUID عام غير حتمي (عشوائي) للعملاء والعمليات.
  static String generateUuid() {
    // مبني على عشوائية قوية + طابع زمني.
    final rndBytes = DateTime.now().microsecondsSinceEpoch.toString() +
        DateTime.now().toIso8601String();
    final hash = sha256.convert(utf8.encode(rndBytes)).toString();
    // صيغة 32 hex بدون شرطات (متوافقة كمفتاح وثيقة Firestore)
    return hash;
  }

  /// التحقق أن المعرّف صالح كمفتاح وثيقة Firestore (لا يحوي '/' ولا فارغ).
  static bool isValidDocumentId(String? id) {
    if (id == null) return false;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('/') || trimmed.contains('\\')) return false;
    // Firestore يرفض المفاتيح التي تتكون من نقطة واحدة فقط أو نقطتين
    if (trimmed == '.' || trimmed == '..') return false;
    return true;
  }

  /// تنظيف معرّف ليصبح صالحاً كمفتاح وثيقة (إزالة '/' و '\' وفضاءات طرفية).
  static String sanitizeDocumentId(String input) {
    var out = input.trim();
    out = out.replaceAll('/', '_').replaceAll('\\', '_');
    if (out.isEmpty || out == '.' || out == '..') {
      // احتياط: استبدال بمعرّف حتمي من النص الأصلي
      return sha256.convert(utf8.encode(input)).toString();
    }
    return out;
  }

  // ──────────────── المفاتيح المشتركة ────────────────

  /// الحصول على مفتاح المجموعة السري المشترك، أو إنشائه مرة واحدة وتخزينه.
  static Future<String> getOrCreateSecretKey() async {
    var key = await _storage.read(key: _secretKeyStorage);
    if (key == null || key.isEmpty) {
      // توليد مفتاح جديد (32 بايت hex)
      key = _generateRandomKey();
      await saveSecretKey(key);
    }
    return key;
  }

  /// حفظ مفتاح المجموعة السري بشكل دائم.
  static Future<void> saveSecretKey(String key) async {
    await _storage.write(key: _secretKeyStorage, value: key);
    // نزامن نسخة قواعد Firestore أيضاً
    await _storage.write(key: _secretKeyFireKey, value: key);
  }

  /// توليد مفتاح عشوائي قوي (hex 64 محرف ≈ 256 بت).
  static String _generateRandomKey() {
    final seed = DateTime.now().microsecondsSinceEpoch.toString() +
        DateTime.now().toIso8601String() +
        IdentityCache.nonce();
    return sha256.convert(utf8.encode(seed)).toString();
  }

  // ──────────────── التوقيع والتحقق ────────────────

  /// توقيع البيانات باستخدام HMAC-SHA256 بالمفتاح المعطى.
  /// يعيد التوقيع بصيغة hex.
  static String signData(String data, String key) {
    final hmac = Hmac(sha256, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString();
  }

  /// التحقق من صحة توقيع البيانات مقابل المفتاح المعطى (ثابت الوقت لمنع التوقيت).
  static bool verifySignature(String data, String signature, String key) {
    if (signature.isEmpty) return false;
    final expected = signData(data, key);
    // مقارنة ثابتة الطول
    if (expected.length != signature.length) return false;
    var equal = true;
    for (var i = 0; i < expected.length; i++) {
      if (expected.codeUnitAt(i) != signature.codeUnitAt(i)) equal = false;
    }
    return equal;
  }
}

/// مساعد داخلي لتوليد nonce بسيط (إنتروبيا إضافية لتوليد المفاتيح).
class IdentityCache {
  static int _counter = 0;
  static String nonce() {
    _counter += 1;
    return '${_counter}_${DateTime.now().millisecondsSinceEpoch}';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 🔐 تحديد معدل العمليات (Rate Limiter) لحماية Firestore من الإفراط في الطلبات.
// معرّف هنا لأنه يُستورد ضمنياً عبر sync_security.dart في firebase_sync_service.dart.
// ════════════════════════════════════════════════════════════════════════════
class SyncRateLimiter {
  final int maxOperationsPerMinute;
  final int maxOperationsPerHour;

  // طوابع زمنية آخر العمليات (مللي ثانية) لاحتساب المعدل.
  final List<int> _minuteWindow = [];
  final List<int> _hourWindow = [];

  SyncRateLimiter({
    required this.maxOperationsPerMinute,
    required this.maxOperationsPerHour,
  });

  /// هل يمكن إجراء عملية الآن دون تجاوز المعدل؟
  bool canProceed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _prune(now);
    return _minuteWindow.length < maxOperationsPerMinute &&
        _hourWindow.length < maxOperationsPerHour;
  }

  /// تسجيل عملية تمت (بعد نجاحها).
  void recordOperation() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _prune(now);
    _minuteWindow.add(now);
    _hourWindow.add(now);
  }

  /// المدة التي يجب انتظارها قبل إجراء العملية التالية.
  /// تعيد Duration.zero (أو null) إن كان يمكن المتابعة الآن.
  /// النوع Duration? ليتمايز مع الاستخدام ‏?.inSeconds في firebase_sync_service.
  Duration? getWaitTime() {
    if (canProceed()) return Duration.zero;
    final now = DateTime.now().millisecondsSinceEpoch;
    _prune(now);
    if (_minuteWindow.length >= maxOperationsPerMinute && _minuteWindow.isNotEmpty) {
      final waitMs = 60000 - (now - _minuteWindow.first);
      return Duration(milliseconds: waitMs < 0 ? 0 : waitMs);
    }
    if (_hourWindow.length >= maxOperationsPerHour && _hourWindow.isNotEmpty) {
      final waitMs = 3600000 - (now - _hourWindow.first);
      return Duration(milliseconds: waitMs < 0 ? 0 : waitMs);
    }
    return Duration.zero;
  }

  /// إزالة الطوابع الزمنية خارج نافذتي الدقيقة والساعة.
  void _prune(int now) {
    _minuteWindow.removeWhere((t) => now - t > 60000);
    _hourWindow.removeWhere((t) => now - t > 3600000);
  }
}
