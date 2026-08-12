import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseCustomConfig {
  static const _storage = FlutterSecureStorage();

  static const String _keyApiKey = 'firebase_api_key';
  static const String _keyAppId = 'firebase_app_id';
  static const String _keyProjectId = 'firebase_project_id';
  static const String _keyMessagingSenderId = 'firebase_messaging_sender_id';
  static const String _keyIsConfigured = 'firebase_is_custom_configured';

  /// حفظ إعدادات Firebase الخاصة بالمستخدم
  static Future<void> saveCustomConfig({
    required String apiKey,
    required String appId,
    required String projectId,
    required String messagingSenderId,
  }) async {
    await _storage.write(key: _keyApiKey, value: apiKey);
    await _storage.write(key: _keyAppId, value: appId);
    await _storage.write(key: _keyProjectId, value: projectId);
    await _storage.write(key: _keyMessagingSenderId, value: messagingSenderId);
    await _storage.write(key: _keyIsConfigured, value: 'true');
  }

  /// هل تم إعداد Firebase الخاص بالمستخدم؟
  static Future<bool> isCustomConfigured() async {
    final value = await _storage.read(key: _keyIsConfigured);
    return value == 'true';
  }

  /// استرجاع Project ID
  static Future<String?> getProjectId() async {
    return await _storage.read(key: _keyProjectId);
  }

  /// مسح إعدادات الاتصال بالكامل
  static Future<void> clearCustomConfig() async {
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyAppId);
    await _storage.delete(key: _keyProjectId);
    await _storage.delete(key: _keyMessagingSenderId);
    await _storage.delete(key: _keyIsConfigured);
  }

  /// استرجاع الإعدادات المحفوظة
  static Future<FirebaseOptions?> getCustomOptions() async {
    final isConfigured = await isCustomConfigured();
    if (!isConfigured) return null;

    final apiKey = await _storage.read(key: _keyApiKey);
    final appId = await _storage.read(key: _keyAppId);
    final projectId = await _storage.read(key: _keyProjectId);
    final messagingSenderId = await _storage.read(key: _keyMessagingSenderId);

    if (apiKey == null || appId == null || projectId == null || messagingSenderId == null) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
    );
  }
}
