// lib/lan/lan_codec.dart
//
// ترميز رسائل الشبكة المحلية (LAN) بين حاسبة السيرفر وحاسبات الطرفيات.
//
// الفكرة: مكتبة sqflite تحوّل كل عملية قاعدة بيانات إلى استدعاء
// (method, arguments) — نفس ما تفعله مع Android أو مع الـ isolate في ffi.
// نحن ننقل هذا الاستدعاء كما هو عبر WebSocket إلى السيرفر، فيُنفَّذ هناك على
// نفس اتصال SQLite الذي يستخدمه برنامج السيرفر نفسه.
//
// JSON لا يعرف Uint8List، فنلفّها في {"__b64": "..."}.

import 'dart:convert';
import 'dart:typed_data';

/// رقم إصدار البروتوكول — يُرفع عند أي تغيير غير متوافق.
const int lanProtocolVersion = 1;

/// المنفذ الافتراضي لخادم قاعدة البيانات.
const int lanDefaultPort = 47800;

/// منفذ الاكتشاف التلقائي (UDP broadcast).
const int lanDiscoveryPort = 47801;

const String _b64Key = '__b64';

/// يحوّل أي قيمة قادمة من/ذاهبة إلى sqflite إلى شكل قابل لـ JSON.
Object? lanEncodeValue(Object? v) {
  if (v == null || v is String || v is bool || v is int) return v;
  if (v is double) {
    // JSON لا يدعم NaN/Infinity — SQLite نفسه لا يخزّنها كقيم عادية.
    if (v.isNaN || v.isInfinite) return null;
    return v;
  }
  if (v is Uint8List) return {_b64Key: base64Encode(v)};
  if (v is List) return v.map(lanEncodeValue).toList();
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), lanEncodeValue(val)));
  }
  // أي نوع آخر يُرسل كنص (لا ينبغي أن يحدث مع sqflite).
  return v.toString();
}

/// العكس: يعيد Uint8List حيث وُجد {"__b64": ...}.
Object? lanDecodeValue(Object? v) {
  if (v is List) return v.map(lanDecodeValue).toList();
  if (v is Map) {
    if (v.length == 1 && v.containsKey(_b64Key)) {
      return base64Decode(v[_b64Key] as String);
    }
    return v.map((k, val) => MapEntry(k as String, lanDecodeValue(val)));
  }
  return v;
}

/// رسالة طلب: {"i": id, "m": method, "a": arguments}
String lanEncodeRequest(int id, String method, Object? arguments) =>
    jsonEncode({'i': id, 'm': method, 'a': lanEncodeValue(arguments)});

/// رسالة نجاح: {"i": id, "r": result}
String lanEncodeResult(int id, Object? result) =>
    jsonEncode({'i': id, 'r': lanEncodeValue(result)});

/// رسالة خطأ: {"i": id, "e": {...}}
String lanEncodeError(int id, LanRemoteError error) =>
    jsonEncode({'i': id, 'e': error.toMap()});

/// خطأ قادم من السيرفر، يحمل ما يلزم لإعادة بناء استثناء sqflite في الطرفية.
class LanRemoteError implements Exception {
  LanRemoteError({
    required this.message,
    this.code,
    this.resultCode,
    this.transactionClosed,
    this.details,
  });

  final String message;
  final String? code;
  final int? resultCode;
  final bool? transactionClosed;
  final Object? details;

  Map<String, Object?> toMap() => {
        'message': message,
        if (code != null) 'code': code,
        if (resultCode != null) 'resultCode': resultCode,
        if (transactionClosed != null) 'transactionClosed': transactionClosed,
        if (details != null) 'details': lanEncodeValue(details),
      };

  static LanRemoteError fromMap(Map map) => LanRemoteError(
        message: (map['message'] ?? 'خطأ غير معروف من السيرفر').toString(),
        code: map['code'] as String?,
        resultCode: map['resultCode'] as int?,
        transactionClosed: map['transactionClosed'] as bool?,
        details: lanDecodeValue(map['details']),
      );

  @override
  String toString() => 'LanRemoteError($code, $resultCode): $message';
}

/// أخطاء الاتصال نفسه (السيرفر غير متاح، انقطاع الشبكة، رمز ربط خاطئ).
class LanConnectionException implements Exception {
  LanConnectionException(this.message);
  final String message;
  @override
  String toString() => 'LanConnectionException: $message';
}

/// رموز إغلاق WebSocket الخاصة بالبرنامج (4000–4999 مسموحة للتطبيقات).
const int lanCloseBadKey = 4401;
const int lanCloseBadProto = 4426;
