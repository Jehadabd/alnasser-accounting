// lib/services/sync/sync_encryption.dart
// 🔐 وحدة التشفير المشتركة للمزامنة.
//
// تُصدَّر من lib/services/firebase_sync/firebase_sync.dart (الـ barrel).
// التشفير الفعلي للتوقيع يعيش في sync_security.dart (HMAC-SHA256).
// هذه الوحدة توفّر أدوات تشفير مساعدة اختيارية لو احتاجها أي مكوّن لاحقاً.

import 'dart:convert';
import 'package:crypto/crypto.dart';

class SyncEncryption {
  SyncEncryption._();

  /// تجزئة SHA-256 لنص (سلسلة hex بطول 64).
  static String hashString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// تجزئة خريطة بيانات بشكل مستقر (لإنشاء checksum).
  static String hashMap(Map<String, dynamic> data) {
    // ترتيب المفاتيح لضمان حتمية التجزئة عبر الأجهزة
    final sortedKeys = data.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final k in sortedKeys) {
      buffer.write('$k=${data[k]};');
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }
}
