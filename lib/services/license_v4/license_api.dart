// lib/services/license_v4/license_api.dart
//
// 🌐 الاتصال بسيرفر التراخيص (Google Apps Script).
// POST بنص JSON (text/plain: طلب «بسيط» يعمل من المتصفح أيضاً بلا CORS)،
// ثم اتباع تحويل 302 الذي يعيده Apps Script إلى رابط النتيجة.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

import 'license_config.dart';

class LicenseApi {
  LicenseApi._();

  static const _timeout = Duration(seconds: 30);

  static Map<String, dynamic> networkError([Object? e]) => {
        'ok': false,
        'error': 'NETWORK_ERROR',
        'message': 'تعذّر الاتصال بسيرفر التراخيص — تأكد من الإنترنت ثم أعد المحاولة',
        if (e != null) 'detail': '$e',
      };

  static Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    if (!LicenseConfig.isConfigured) {
      return {'ok': false, 'error': 'NOT_CONFIGURED', 'message': 'سيرفر التراخيص غير مضبوط في هذه النسخة'};
    }
    // الرابط المعتمد أولاً؛ إن لم يُجب (نشر معطّل) أو لم يعرف العملية، فالرابط الاحتياطي
    Map<String, dynamic>? first;
    for (final url in LicenseConfig.serverUrls) {
      final r = await _callUrl(url, body);
      first ??= r;
      final err = r['error'];
      if (err != 'NETWORK_ERROR' && err != 'UNKNOWN_ACTION') return r;
    }
    return first ?? networkError();
  }

  static Future<Map<String, dynamic>> _callUrl(String url, Map<String, dynamic> body) async {
    final action = body['action'];
    try {
      final payload = jsonEncode(body);
      http.Response res;
      if (kIsWeb) {
        res = await http
            .post(Uri.parse(url),
                headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: payload)
            .timeout(_timeout);
      } else {
        final client = http.Client();
        try {
          final req = http.Request('POST', Uri.parse(url))
            ..followRedirects = false
            ..headers['Content-Type'] = 'text/plain;charset=utf-8'
            ..body = payload;
          res = await http.Response.fromStream(await client.send(req).timeout(_timeout));
          var hops = 0;
          while ((res.statusCode == 301 || res.statusCode == 302 || res.statusCode == 303) &&
              res.headers['location'] != null &&
              hops++ < 3) {
            res = await client.get(Uri.parse(res.headers['location']!)).timeout(_timeout);
          }
        } finally {
          client.close();
        }
      }
      if (res.statusCode != 200) {
        debugPrint('🔐 [License] $action → HTTP ${res.statusCode}');
        return networkError('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        debugPrint('🔐 [License] $action → ${decoded['ok'] == true ? 'OK' : decoded['error']}');
        return decoded;
      }
      return networkError('INVALID_RESPONSE');
    } catch (e) {
      debugPrint('🔐 [License] $action → $e');
      return networkError(e);
    }
  }
}
