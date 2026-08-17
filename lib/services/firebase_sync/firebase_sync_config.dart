// lib/services/firebase_sync/firebase_sync_config.dart
// إعدادات مجموعة المزامنة عبر Firebase

import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';



/// ═══════════════════════════════════════════════════════════════════════════
/// إعدادات أمان المزامنة عبر Firebase
/// ═══════════════════════════════════════════════════════════════════════════
class FirebaseSyncSecuritySettings {
  static const String _rejectOldTransactionsKey = 'firebase_sync_reject_old_transactions';
  static const String _maxTransactionAgeDaysKey = 'firebase_sync_max_transaction_age_days';
  static const String _enablePostSyncVerificationKey = 'firebase_sync_enable_post_sync_verification';
  
  /// هل تفعيل رفض المعاملات القديمة؟
  static Future<bool> isRejectOldTransactionsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rejectOldTransactionsKey) ?? false; // معطل افتراضياً
  }
  
  /// تفعيل/تعطيل رفض المعاملات القديمة
  static Future<void> setRejectOldTransactionsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rejectOldTransactionsKey, enabled);
  }
  
  /// الحصول على الحد الأقصى لعمر المعاملة بالأيام
  static Future<int> getMaxTransactionAgeDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxTransactionAgeDaysKey) ?? 30; // 30 يوم افتراضياً
  }
  
  /// تعيين الحد الأقصى لعمر المعاملة بالأيام
  static Future<void> setMaxTransactionAgeDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxTransactionAgeDaysKey, days);
  }
  
  /// هل تفعيل التحقق من الأرصدة بعد المزامنة؟
  static Future<bool> isPostSyncVerificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enablePostSyncVerificationKey) ?? true; // مفعل افتراضياً
  }
  
  /// تفعيل/تعطيل التحقق من الأرصدة بعد المزامنة
  static Future<void> setPostSyncVerificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enablePostSyncVerificationKey, enabled);
  }

  static const String _enableAutoCleanupKey = 'firebase_sync_enable_auto_cleanup';
  static const String _autoDeleteDaysKey = 'firebase_sync_auto_delete_days';
  static const String _enableDirectStockSyncKey = 'firebase_sync_enable_direct_stock_sync';

  /// هل تفعيل التنظيف التلقائي للبيانات القديمة؟
  static Future<bool> isAutoCleanupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableAutoCleanupKey) ?? false; // معطل افتراضياً
  }

  /// تفعيل/تعطيل التنظيف التلقائي
  static Future<void> setAutoCleanupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableAutoCleanupKey, enabled);
  }

  /// هل تفعيل المزامنة المباشرة للمخزون من صفحة المنتجات؟ (خطر للاستخدام المتعدد)
  static Future<bool> isDirectStockSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableDirectStockSyncKey) ?? false; // معطل افتراضياً
  }

  /// تفعيل/تعطيل المزامنة المباشرة للمخزون
  static Future<void> setDirectStockSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableDirectStockSyncKey, enabled);
  }

  /// الحصول على مدة الاحتفاظ بالبيانات في Firebase (بالأيام)
  static Future<int> getAutoDeleteDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoDeleteDaysKey) ?? 30; // 30 يوم افتراضياً
  }

  /// تعيين مدة الاحتفاظ بالبيانات في Firebase (بالأيام)
  static Future<void> setAutoDeleteDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_autoDeleteDaysKey, days);
  }
}

/// إعدادات المزامنة عبر Firebase
class FirebaseSyncConfig {
  static const String _enabledKey = 'firebase_sync_enabled';
  static const String _deviceIdKey = 'firebase_sync_device_id';
  static const String _lastSyncKey = 'firebase_sync_last_sync';
  
  static final _secureStorage = FlutterSecureStorage();
  
  /// في النظام الجديد (كل مستخدم لديه مشروع فايربيس خاص به)، لا نحتاج لمجموعات
  /// نستخدم معرف ثابت لجميع الأجهزة التي تتصل بنفس المشروع
  static Future<String?> getSyncGroupId() async {
    return 'default_sync_group';
  }

  
  /// هل المزامنة مفعلة؟
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }
  
  /// تفعيل/تعطيل المزامنة
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }
  
  /// الحصول على معرف الجهاز الفريد
  static Future<String> getDeviceId() async {
    String? deviceId = await _secureStorage.read(key: _deviceIdKey);
    if (deviceId == null) {
      deviceId = _generateDeviceId();
      await _secureStorage.write(key: _deviceIdKey, value: deviceId);
    }
    return deviceId;
  }
  
  /// توليد معرف جهاز فريد
  static String _generateDeviceId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  /// الحصول على آخر وقت مزامنة
  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_lastSyncKey);
    if (timestamp == null) return null;
    return DateTime.tryParse(timestamp);
  }
  
  /// تحديث آخر وقت مزامنة
  static Future<void> setLastSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, time.toIso8601String());
  }
  
  /// مسح جميع إعدادات المزامنة
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enabledKey);
    await prefs.remove(_lastSyncKey);
  }
  
  /// هل تم إعداد المزامنة؟
  static Future<bool> isConfigured() async {
    // نعتمد على الإعدادات المخصصة بدلاً من المجموعات
    return await isEnabled();
  }
}

/// تحدي رياضي للحماية
class MathChallenge {
  final double num1;
  final double num2;
  final String operator;
  final double answer;
  
  MathChallenge._({
    required this.num1,
    required this.num2,
    required this.operator,
    required this.answer,
  });
  
  /// توليد تحدي رياضي صعب
  static MathChallenge generate() {
    final random = Random();
    
    // أرقام عشوائية بكسور عشرية
    final num1 = (random.nextInt(900) + 100) + (random.nextInt(99) / 100);
    final num2 = (random.nextInt(90) + 10) + (random.nextInt(99) / 100);
    
    // اختيار عملية عشوائية (ضرب أو قسمة)
    final isMultiply = random.nextBool();
    final operator = isMultiply ? '×' : '÷';
    
    double answer;
    if (isMultiply) {
      answer = num1 * num2;
    } else {
      answer = num1 / num2;
    }
    
    return MathChallenge._(
      num1: double.parse(num1.toStringAsFixed(2)),
      num2: double.parse(num2.toStringAsFixed(2)),
      operator: operator,
      answer: double.parse(answer.toStringAsFixed(3)),
    );
  }
  
  /// التحقق من الإجابة (مع هامش خطأ صغير)
  bool verify(String userAnswer) {
    final parsed = double.tryParse(userAnswer);
    if (parsed == null) return false;
    
    // هامش خطأ 0.01
    return (parsed - answer).abs() < 0.01;
  }
  
  /// نص السؤال
  String get questionText => '${num1.toStringAsFixed(2)} $operator ${num2.toStringAsFixed(2)} = ؟';
}
