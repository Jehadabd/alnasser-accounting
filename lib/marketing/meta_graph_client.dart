// lib/marketing/meta_graph_client.dart
//
// 🌐 واجهة Meta الرسمية (Graph API) لصفحة المحل على فيسبوك وحسابها على إنستغرام — فقط ما
// تسمح به Meta لصاحب الصفحة نفسه: نشر منشور، ونشر صورة، وقراءة التفاعل.
//   • الرمز (Page Access Token) يُنشئه صاحب الصفحة من تطبيقه في Meta for Developers.
//   • إنستغرام عبر الواجهة يقبل صورة من رابط عام (image_url) فقط — شرط من Meta نفسها.
// لا تجاوز لأي قيد: لا نشر في مجموعات، ولا حسابات شخصية، ولا تفاعل آلي.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class MetaException implements Exception {
  MetaException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MetaPage {
  MetaPage(this.id, this.name, this.instagramId);
  final String id, name;
  final String? instagramId;
}

class MetaGraphClient {
  MetaGraphClient(this.token, {http.Client? client}) : _http = client ?? http.Client();
  final String token;
  final http.Client _http;

  static const base = 'https://graph.facebook.com/v21.0';

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    Map<String, dynamic> j;
    try {
      j = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw MetaException('رد غير مفهوم من Meta (HTTP ${r.statusCode})');
    }
    final e = j['error'];
    if (e is Map) {
      final code = e['code'];
      final msg = '${e['message'] ?? ''}';
      throw MetaException(switch (code) {
        190 => 'رمز الوصول منتهٍ أو غير صالح — أنشئ رمزاً جديداً للصفحة',
        10 || 200 => 'الرمز لا يملك صلاحية النشر (pages_manage_posts / instagram_content_publish): $msg',
        4 || 17 || 32 || 613 => 'بلغت حد Meta للطلبات — انتظر ثم أعد المحاولة',
        368 => 'Meta أوقفت النشر مؤقتاً لهذه الصفحة: $msg',
        _ => 'Meta: $msg',
      });
    }
    if (r.statusCode >= 400) throw MetaException('Meta: HTTP ${r.statusCode}');
    return j;
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> q) async {
    try {
      final uri = Uri.parse('$base/$path').replace(queryParameters: {...q, 'access_token': token});
      return _decode(await _http.get(uri).timeout(const Duration(seconds: 40)));
    } on SocketException catch (e) {
      throw MetaException('لا اتصال بـ Meta: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, String> body) async {
    try {
      return _decode(await _http
          .post(Uri.parse('$base/$path'), body: {...body, 'access_token': token})
          .timeout(const Duration(seconds: 60)));
    } on SocketException catch (e) {
      throw MetaException('لا اتصال بـ Meta: ${e.message}');
    }
  }

  /// يتحقق من الرمز ويعيد الصفحة وحساب إنستغرام المرتبط بها (إن وُجد).
  Future<MetaPage> page(String pageId) async {
    final j = await _get(pageId, {'fields': 'id,name,instagram_business_account'});
    final ig = j['instagram_business_account'];
    return MetaPage('${j['id']}', '${j['name'] ?? ''}', ig is Map ? '${ig['id']}' : null);
  }

  /// منشور نصي على الصفحة. يعيد رقم المنشور.
  Future<String> postText(String pageId, String message) async =>
      '${(await _post('$pageId/feed', {'message': message}))['id']}';

  /// صورة من الجهاز مع نص على الصفحة. يعيد رقم المنشور.
  Future<String> postPhoto(String pageId, File image, String caption) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$base/$pageId/photos'))
        ..fields['caption'] = caption
        ..fields['access_token'] = token
        ..files.add(await http.MultipartFile.fromPath('source', image.path));
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 120)));
      final j = await _decode(res);
      return '${j['post_id'] ?? j['id']}';
    } on SocketException catch (e) {
      throw MetaException('لا اتصال بـ Meta: ${e.message}');
    }
  }

  /// إنستغرام: حاوية ثم نشر (الصورة من رابط عام فقط — شرط Meta).
  Future<String> postInstagram(String igUserId, String imageUrl, String caption) async {
    final c = await _post('$igUserId/media', {'image_url': imageUrl, 'caption': caption});
    final p = await _post('$igUserId/media_publish', {'creation_id': '${c['id']}'});
    return '${p['id']}';
  }

  /// التفاعل على منشور فيسبوك: (إعجابات وتفاعلات، تعليقات، مشاركات).
  Future<({int reactions, int comments, int shares})> facebookStats(String postId) async {
    final j = await _get(postId, {'fields': 'reactions.summary(total_count),comments.summary(total_count),shares'});
    int sum(String k) => ((j[k] as Map?)?['summary'] as Map?)?['total_count'] as int? ?? 0;
    return (reactions: sum('reactions'), comments: sum('comments'), shares: (j['shares'] as Map?)?['count'] as int? ?? 0);
  }

  /// التفاعل على منشور إنستغرام: (إعجابات، تعليقات).
  Future<({int likes, int comments})> instagramStats(String mediaId) async {
    final j = await _get(mediaId, {'fields': 'like_count,comments_count'});
    return (likes: (j['like_count'] as num?)?.toInt() ?? 0, comments: (j['comments_count'] as num?)?.toInt() ?? 0);
  }
}
