// lib/owner/wa_auto/wa_render_deployer.dart
//
// 🚀 إنشاء خادم واتساب على Render تلقائياً — بلا GitHub وبلا رفع ملفات:
//   صاحب المحل يلصق «مفتاح Render API» مرة واحدة، والبرنامج:
//   1) يقرأ حسابه (GET /v1/owners).
//   2) يبحث عن خدمة alnaser-wa سابقة؛ إن وُجدت حدّث مفتاح الخادم فيها وأعاد نشرها.
//   3) وإلا أنشأ خدمة مجانية (plan free) من صورة الخادم الجاهزة [image] —
//      تبنيها GitHub Actions من assets/wa_server (.github/workflows/wa-server-image.yml).
//   4) ينتظر حتى تصبح «live» ويرد الخادم، ثم يضع الرابط في البرنامج.
//
// مفتاح Render يتحكم في حساب Render كله: يُحفظ في التخزين الآمن، ولا يُرسل إلا إلى
// api.render.com، ويمكن حذفه من الشاشة في أي وقت. لا يغيّر أي دين أو معاملة.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'wa_server_client.dart';
import 'wa_usage_mark.dart';

class WaRenderDeployer {
  WaRenderDeployer._();

  /// صورة الخادم العامة (تبنيها GitHub Actions). يجب أن تكون حزمة GHCR «Public».
  static const image = 'ghcr.io/jehadabd/alnaser-wa:latest';
  static const serviceName = 'alnaser-wa';
  static const region = 'frankfurt'; // الأقرب إلى العراق والخليج بين مناطق Render

  static const registerPage = 'https://dashboard.render.com/register';
  static const keysPage = 'https://dashboard.render.com/u/settings#api-keys';

  static const _api = 'https://api.render.com/v1';
  static const _kApiKey = 'wa_render_api_key';
  static const _kService = 'wa_render_service_id';
  static const _kDashboard = 'wa_render_dashboard';
  static const _secure = FlutterSecureStorage();

  static const _failed = {'build_failed', 'update_failed', 'canceled', 'pre_deploy_failed', 'deactivated'};

  // ───────────── المفتاح والحالة ─────────────

  static Future<bool> hasApiKey() async => ((await _secure.read(key: _kApiKey)) ?? '').isNotEmpty;

  static Future<void> setApiKey(String k) async {
    final v = k.trim();
    if (v.length < 20 || v.contains(RegExp(r'\s'))) {
      throw WaServerException('هذا لا يبدو مفتاح Render API (يبدأ عادةً بـ rnd_) — انسخه كاملاً');
    }
    await _secure.write(key: _kApiKey, value: v);
  }

  static Future<void> forgetApiKey() => _secure.delete(key: _kApiKey);

  static Future<String?> serviceId() async => (await SharedPreferences.getInstance()).getString(_kService);
  static Future<String?> dashboardUrl() async => (await SharedPreferences.getInstance()).getString(_kDashboard);

  // ───────────── الطلبات ─────────────

  static Future<dynamic> _req(String method, String path, String key, {Object? body}) async {
    final uri = Uri.parse('$_api$path');
    final h = {
      'authorization': 'Bearer $key',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };
    http.Response r;
    try {
      final Future<http.Response> f = switch (method) {
        'GET' => http.get(uri, headers: h),
        'POST' => http.post(uri, headers: h, body: jsonEncode(body ?? const {})),
        'PUT' => http.put(uri, headers: h, body: jsonEncode(body ?? const {})),
        _ => throw ArgumentError(method),
      };
      r = await f.timeout(const Duration(seconds: 45));
    } on SocketException catch (e) {
      throw WaServerException('تعذّر الوصول إلى Render: ${e.message}');
    } on TimeoutException {
      throw WaServerException('Render لم يرد خلال 45 ثانية — أعد المحاولة');
    }
    dynamic j;
    try {
      j = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (r.statusCode >= 200 && r.statusCode < 300) return j;
    final msg = j is Map ? '${j['message'] ?? ''}' : '';
    throw WaServerException(errorText(r.statusCode, msg));
  }

  static String errorText(int code, String msg) {
    final m = msg.toLowerCase();
    final tail = msg.isEmpty ? '' : '\nرسالة Render: $msg';
    if (code == 401) return 'مفتاح Render غير صحيح أو أُلغي — أنشئ مفتاحاً جديداً والصقه$tail';
    if (code == 402 || m.contains('payment') || m.contains('credit card') || m.contains('billing')) {
      return 'Render يطلب إضافة بطاقة دفع للحساب قبل إنشاء أي خدمة (حتى المجانية). '
          'أضفها من Billing في Render، أو استعمل «هذه الحاسبة» — بلا بطاقة.$tail';
    }
    if (code == 429) return 'طلبات كثيرة إلى Render — انتظر دقيقة وأعد المحاولة$tail';
    if (m.contains('image') && (m.contains('not found') || m.contains('pull') || m.contains('unauthorized'))) {
      return 'Render لم يستطع جلب صورة الخادم ($image) — صاحب البرنامج يجب أن يجعلها Public في GitHub.$tail';
    }
    if (code == 403) return 'مفتاح Render لا يملك صلاحية لهذا الإجراء$tail';
    return 'Render: HTTP $code$tail';
  }

  static String statusText(String? s) => switch (s) {
        'created' || 'queued' => 'في الانتظار',
        'build_in_progress' => 'يجلب صورة الخادم',
        'update_in_progress' || 'pre_deploy_in_progress' => 'يشغّل الخادم',
        'live' => 'يعمل',
        null => '…',
        final String x => x,
      };

  static String? _urlOf(Map<String, dynamic> svc) {
    final d = svc['serviceDetails'];
    final u = d is Map ? d['url'] : null;
    return u is String && u.startsWith('http') ? u : null;
  }

  static Future<Map<String, dynamic>?> _findService(String key, String ownerId) async {
    final q = 'name=${Uri.encodeQueryComponent(serviceName)}&type=web_service&ownerId=$ownerId&limit=20';
    final list = await _req('GET', '/services?$q', key);
    if (list is! List) return null;
    for (final it in list) {
      final s = it is Map ? it['service'] : null;
      if (s is Map && s['name'] == serviceName) return s.cast<String, dynamic>();
    }
    return null;
  }

  static Future<String?> _deployStatus(String key, String id, String? deployId) async {
    if (deployId != null) {
      final d = await _req('GET', '/services/$id/deploys/$deployId', key);
      return d is Map ? d['status'] as String? : null;
    }
    final list = await _req('GET', '/services/$id/deploys?limit=1', key);
    if (list is List && list.isNotEmpty && list.first is Map) {
      final d = (list.first as Map)['deploy'];
      return d is Map ? d['status'] as String? : null;
    }
    return null;
  }

  static Future<void> _waitPing(String url, void Function(String) onStep) async {
    final until = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(until)) {
      try {
        final r = await http.get(Uri.parse('$url/ping')).timeout(const Duration(seconds: 70));
        final j = jsonDecode(r.body);
        if (j is Map && j['app'] == 'alnaser-wa') return;
      } catch (_) {}
      onStep('ينتظر أن يرد الخادم…');
      await Future.delayed(const Duration(seconds: 6));
    }
    throw WaServerException('النشر اكتمل لكن الخادم لا يرد على $url — افتح الخدمة في Render واقرأ «Logs»');
  }

  // ───────────── الإنشاء / التحديث ─────────────

  static bool _running = false;
  static bool get running => _running;

  /// ينشئ الخدمة (أو يحدّثها إن وُجدت) ويعيد رابطها بعد أن يرد. يضع الرابط في البرنامج.
  static Future<String> deploy({required void Function(String) onStep}) async {
    if (_running) throw WaServerException('الإنشاء جارٍ بالفعل');
    _running = true;
    try {
      final key = await _secure.read(key: _kApiKey);
      if (key == null || key.isEmpty) throw WaServerException('الصق مفتاح Render أولاً');
      await WaUsageMark.record('server'); // 🔖 علامة دائمة: الخدمة شُغّلت

      onStep('التحقق من مفتاح Render…');
      final owners = await _req('GET', '/owners?limit=20', key);
      final list = <Map<String, dynamic>>[
        if (owners is List)
          for (final o in owners)
            if (o is Map && o['owner'] is Map) (o['owner'] as Map).cast<String, dynamic>(),
      ];
      if (list.isEmpty) throw WaServerException('لم يُعثر على حساب في Render لهذا المفتاح');
      final owner = list.firstWhere((o) => o['type'] == 'user', orElse: () => list.first);
      final ownerId = '${owner['id']}';
      final srvKey = await WaServerClient.key();

      onStep('البحث عن خدمة $serviceName سابقة…');
      var svc = await _findService(key, ownerId);
      String? deployId;
      if (svc == null) {
        onStep('إنشاء خدمة مجانية في Render (فرانكفورت)…');
        final r = await _req('POST', '/services', key, body: {
          'type': 'web_service',
          'name': serviceName,
          'ownerId': ownerId,
          'image': {'ownerId': ownerId, 'imagePath': image},
          'envVars': [
            {'key': 'API_KEY', 'value': srvKey},
          ],
          'serviceDetails': {
            'runtime': 'image',
            'plan': 'free',
            'region': region,
            'healthCheckPath': '/ping',
            'numInstances': 1,
          },
        });
        if (r is! Map) throw WaServerException('رد غير متوقع من Render عند الإنشاء');
        final m = r.cast<String, dynamic>();
        svc = ((m['service'] as Map?) ?? m).cast<String, dynamic>();
        deployId = m['deployId'] as String?;
      } else {
        if (svc['suspended'] == 'suspended') {
          throw WaServerException('الخدمة $serviceName موقوفة في Render — افتحها واضغط «Resume» ثم أعد المحاولة');
        }
        onStep('الخدمة موجودة — تحديث «مفتاح الخادم» فيها…');
        await _req('PUT', '/services/${svc['id']}/env-vars/API_KEY', key, body: {'value': srvKey});
        onStep('إعادة نشر الخدمة…');
        final d = await _req('POST', '/services/${svc['id']}/deploys', key, body: const {});
        deployId = d is Map ? d['id'] as String? : null;
      }

      final id = '${svc['id']}';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kService, id);
      final dash = svc['dashboardUrl'];
      if (dash is String && dash.startsWith('https://')) await prefs.setString(_kDashboard, dash);

      onStep('Render يجلب الخادم ويشغّله (2 إلى 6 دقائق)…');
      final until = DateTime.now().add(const Duration(minutes: 15));
      while (true) {
        await Future.delayed(const Duration(seconds: 8));
        String? st;
        try {
          st = await _deployStatus(key, id, deployId);
        } on WaServerException catch (e) {
          onStep('تعذّرت قراءة الحالة مؤقتاً: ${e.message}');
        }
        if (st == 'live') break;
        if (st != null && _failed.contains(st)) {
          throw WaServerException('فشل النشر في Render ($st) — افتح الخدمة في Render واقرأ «Logs»');
        }
        if (DateTime.now().isAfter(until)) {
          throw WaServerException('النشر تجاوز 15 دقيقة — افتح الخدمة في Render وتحقق من حالتها');
        }
        onStep('حالة النشر: ${statusText(st)}…');
      }

      var url = _urlOf(svc);
      if (url == null) {
        final s = await _req('GET', '/services/$id', key);
        if (s is Map) url = _urlOf(s.cast<String, dynamic>());
      }
      if (url == null) throw WaServerException('النشر اكتمل لكن Render لم يعطِ رابطاً — انسخه من صفحة الخدمة');

      await _waitPing(url, onStep);
      await WaServerClient.setUrl(url);
      onStep('تم ✓ الخادم يعمل على $url');
      return url;
    } finally {
      _running = false;
    }
  }
}
