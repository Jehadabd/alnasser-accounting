import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🌐 طبقة احتياطية
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐
import 'firebase_options_helper.dart'; // 🌐 خيارات الويب (authDomain)

class FirebaseCustomConfig {
  static const _storage = FlutterSecureStorage();

  static const String _keyApiKey = 'firebase_api_key';
  static const String _keyAppId = 'firebase_app_id';
  static const String _keyProjectId = 'firebase_project_id';
  static const String _keyMessagingSenderId = 'firebase_messaging_sender_id';
  static const String _keyAuthDomain = 'firebase_auth_domain'; // 🌐 للويب
  static const String _keyIsConfigured = 'firebase_is_custom_configured';

  // 🌐 شبكة أمان PWA: التخزين الآمن قد يترنح على iOS PWA — كل قيمة تُكتب
  // أيضاً في SharedPreferences (localStorage دائم) وتُقرأ منه عند فقدان الأولى.
  static Future<void> _writeDual(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  static Future<String?> _readDual(String key) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(key);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return null;
  }

  /// حفظ إعدادات Firebase الخاصة بالمستخدم
  static Future<void> saveCustomConfig({
    required String apiKey,
    required String appId,
    required String projectId,
    required String messagingSenderId,
    String? authDomain, // 🌐 اختياري للويب — يُشتق تلقائياً إن تُرك فارغاً
  }) async {
    await _writeDual(_keyApiKey, apiKey);
    await _writeDual(_keyAppId, appId);
    await _writeDual(_keyProjectId, projectId);
    await _writeDual(_keyMessagingSenderId, messagingSenderId);
    if (authDomain != null && authDomain.trim().isNotEmpty) {
      await _writeDual(
          _keyAuthDomain,
          authDomain.trim().isEmpty
              ? '$projectId.firebaseapp.com'
              : authDomain.trim());
    }
    await _writeDual(_keyIsConfigured, 'true');
  }

  /// هل تم إعداد Firebase الخاص بالمستخدم؟
  static Future<bool> isCustomConfigured() async {
    final value = await _readDual(_keyIsConfigured);
    return value == 'true';
  }

  /// استرجاع Project ID
  static Future<String?> getProjectId() async {
    return await _readDual(_keyProjectId);
  }

  /// مسح إعدادات الاتصال بالكامل
  static Future<void> clearCustomConfig() async {
    for (final key in [
      _keyApiKey, _keyAppId, _keyProjectId,
      _keyMessagingSenderId, _keyAuthDomain, _keyIsConfigured,
    ]) {
      try { await _storage.delete(key: key); } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {}
    }
  }

  /// استرجاع الإعدادات المحفوظة
  static Future<FirebaseOptions?> getCustomOptions() async {
    final isConfigured = await isCustomConfigured();
    if (!isConfigured) return null;

    final apiKey = await _readDual(_keyApiKey);
    final appId = await _readDual(_keyAppId);
    final projectId = await _readDual(_keyProjectId);
    final messagingSenderId = await _readDual(_keyMessagingSenderId);

    if (apiKey == null || appId == null || projectId == null || messagingSenderId == null) {
      return null;
    }

    // 🌐 الويب: خيارات بمعايير الويب — authDomain إلزامي للمصادقة
    // (غيابه أشهر سبب لفشل المصادقة المجانية بشكل متقطع على المتصفح)
    if (kIsWeb) {
      final savedAuthDomain = await _readDual(_keyAuthDomain);
      return buildWebFirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        projectId: projectId,
        messagingSenderId: messagingSenderId,
        authDomain: (savedAuthDomain != null && savedAuthDomain.trim().isNotEmpty)
            ? savedAuthDomain
            : '$projectId.firebaseapp.com', // الاشتقاق القياسي التلقائي
      );
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
    );
  }
}
