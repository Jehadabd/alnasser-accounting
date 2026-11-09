// lib/owner/wa_auto/wa_server_client.dart
//
// 👑💬 الاتصال بخادم واتساب الخاص بالمالك (assets/wa_server/server.js).
//
//   • الرابط في الإعدادات، و«مفتاح الخادم» في التخزين الآمن (لا في الإعدادات العادية).
//   • البرنامج يحتفظ بنسخة من جلسة الربط (مشفّرة بمفتاح الخادم، لا يقرؤها البرنامج):
//     إن أُعيد تشغيل الخادم على منصة تمسح الملفات أعادها البرنامج — فلا ربط جديد.
//   • لا يغيّر أي دين أو معاملة.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wa_usage_mark.dart';

class WaServerStatus {
  const WaServerStatus({
    this.reachable = false,
    this.linked = false,
    this.connected = false,
    this.me,
    this.rev = 0,
    this.error,
    this.sentLastHour = 0,
    this.maxPerHour = 0,
  });

  final bool reachable, linked, connected;
  final String? me, error;
  final int rev, sentLastHour, maxPerHour;

  factory WaServerStatus.fromJson(Map<String, dynamic> j) => WaServerStatus(
        reachable: true,
        linked: j['linked'] == true,
        connected: j['connected'] == true,
        me: j['me'] as String?,
        rev: (j['rev'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
        sentLastHour: (j['sentLastHour'] as num?)?.toInt() ?? 0,
        maxPerHour: (j['maxPerHour'] as num?)?.toInt() ?? 0,
      );
}

class WaServerException implements Exception {
  WaServerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WaServerClient {
  WaServerClient._();

  static const _kUrl = 'wa_srv_url';
  static const _kKey = 'wa_srv_key';
  static const _kBlob = 'wa_srv_blob';
  static const _kRev = 'wa_srv_rev';
  static const _secure = FlutterSecureStorage();

  /// ملفات الحزمة (assets/wa_server/…).
  static const files = [
    'server.js',
    'package.json',
    'README.md',
    'Dockerfile',
    'render.yaml',
    'install-oracle.sh',
    'deploy-oracle.bat',
    'start-windows.bat',
  ];

  // ───────────── الإعدادات ─────────────

  static Future<String> url() async => (await SharedPreferences.getInstance()).getString(_kUrl) ?? '';

  static Future<void> setUrl(String v) async {
    var u = v.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    await (await SharedPreferences.getInstance()).setString(_kUrl, u);
  }

  /// مفتاح الخادم — يُولَّد مرة واحدة (32 حرفاً عشوائياً آمناً).
  static Future<String> key() async {
    final k = await _secure.read(key: _kKey);
    if (k != null && k.length >= 24) return k;
    return newKey();
  }

  /// مفتاح جديد: الخادم القديم يرفض البرنامج حتى يُحدَّث مفتاحه هناك، والجلسة
  /// المحفوظة بالمفتاح القديم لا تُفتح — يلزم ربط جديد.
  static Future<String> newKey() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    final k = List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
    await _secure.write(key: _kKey, value: k);
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBlob);
    await p.remove(_kRev);
    return k;
  }

  static Future<bool> hasSavedSession() async =>
      ((await SharedPreferences.getInstance()).getString(_kBlob) ?? '').isNotEmpty;

  // ───────────── الطلبات ─────────────

  static Future<Map<String, dynamic>> _call(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 90)}) async {
    final base = await url();
    if (base.isEmpty) throw WaServerException('لم يُضبط رابط الخادم');
    final uri = Uri.parse('$base$path');
    final headers = {'x-key': await key(), 'content-type': 'application/json'};
    http.Response r;
    try {
      r = await (method == 'GET'
              ? http.get(uri, headers: headers)
              : http.post(uri, headers: headers, body: jsonEncode(body ?? const {})))
          .timeout(timeout);
    } on SocketException catch (e) {
      throw WaServerException('تعذّر الوصول إلى الخادم: ${e.message}');
    } on HttpException catch (e) {
      throw WaServerException('تعذّر الوصول إلى الخادم: ${e.message}');
    } on FormatException {
      throw WaServerException('رابط الخادم غير صالح');
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        throw WaServerException('الخادم لم يرد خلال ${timeout.inSeconds} ثانية');
      }
      rethrow;
    }
    Map<String, dynamic> j;
    try {
      j = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw WaServerException('الرد ليس من خادم الناصر (HTTP ${r.statusCode})');
    }
    if (r.statusCode == 401) throw WaServerException('مفتاح الخادم غير مطابق — انسخ المفتاح من هنا إلى الخادم');
    j['_code'] = r.statusCode;
    return j;
  }

  /// يوقظ الخادم ويقرأ حالته (Render المجاني يحتاج حتى دقيقة ليستيقظ).
  static Future<WaServerStatus> status() async => WaServerStatus.fromJson(await _call('GET', '/status'));

  /// جاهز للإرسال: إن كان الخادم بلا جلسة (أُعيد تشغيله على منصة تمسح الملفات)
  /// والبرنامج يحمل نسخة ⇒ يعيدها. ثم يأخذ النسخة الأحدث.
  static Future<WaServerStatus> ensureReady() async {
    var s = await status();
    if (!s.linked && await hasSavedSession()) {
      final p = await SharedPreferences.getInstance();
      final j = await _call('POST', '/state', body: {'blob': p.getString(_kBlob)});
      if (j['_code'] == 200) s = WaServerStatus.fromJson(j);
    }
    if (s.linked) await pullState(s.rev);
    return s;
  }

  /// يحفظ نسخة الجلسة إن تغيّرت على الخادم.
  static Future<void> pullState([int? serverRev]) async {
    final p = await SharedPreferences.getInstance();
    final mine = p.getInt(_kRev) ?? -1;
    if (serverRev != null && serverRev == mine) return;
    final j = await _call('GET', '/state');
    final blob = j['blob'] as String?;
    if (blob == null || blob.isEmpty) return;
    await p.setString(_kBlob, blob);
    await p.setInt(_kRev, (j['rev'] as num?)?.toInt() ?? 0);
  }

  /// يطلب رمز ربط من 8 خانات للرقم [phone] (دولي بلا +).
  static Future<String> pair(String phone) async {
    await WaUsageMark.record('server'); // 🔖 علامة دائمة: الخدمة شُغّلت
    final j = await _call('POST', '/pair', body: {'phone': phone});
    if (j['ok'] != true) throw WaServerException(errorText(j['error'] as String?));
    final code = '${j['code']}';
    return code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
  }

  /// يفك الربط من الخادم ومن واتساب، ويحذف نسخة الجلسة من البرنامج.
  static Future<void> logout() async {
    try {
      await _call('POST', '/logout');
    } finally {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kBlob);
      await p.remove(_kRev);
    }
  }

  /// null = أُرسلت. وإلا سبب الفشل بالعربية. [notOnWhatsApp] = الرقم ليس على واتساب.
  static Future<({String? error, bool notOnWhatsApp})> send(String phone, String text) async {
    try {
      final j = await _call('POST', '/send', body: {'to': phone, 'text': text});
      if (j['ok'] == true) return (error: null, notOnWhatsApp: false);
      final e = j['error'] as String?;
      return (error: errorText(e), notOnWhatsApp: e == 'not_on_whatsapp');
    } on WaServerException catch (e) {
      return (error: e.message, notOnWhatsApp: false);
    }
  }

  static String errorText(String? code) => switch (code) {
        'not_linked' => 'الخادم غير مربوط برقم واتساب',
        'not_connected' => 'الخادم لم يتصل بواتساب (تحقق من الهاتف والإنترنت)',
        'not_on_whatsapp' => 'الرقم ليس على واتساب',
        'hour_limit' => 'بلغ الخادم حد الرسائل في الساعة',
        'bad_number' || 'bad_phone' => 'رقم غير صالح',
        'bad_text' => 'نص الرسالة فارغ أو طويل جداً',
        'logged_out' => 'فُكّ الربط من الهاتف — اربط من جديد',
        'pair_timeout' => 'انتهت مهلة الربط — اطلب رمزاً جديداً',
        null => 'خطأ غير معروف',
        final String c => c,
      };

  // ───────────── حزمة ملفات الخادم ─────────────

  /// يكتب alnaser-wa-server.zip في مجلد التنزيلات ويعيد مساره. بلا مفتاح بداخله.
  static Future<String> savePackage() async {
    final archive = Archive();
    for (final f in files) {
      final data = await rootBundle.load('assets/wa_server/$f');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      archive.addFile(ArchiveFile('alnaser-wa-server/$f', bytes.length, bytes));
    }
    const ignore = 'node_modules/\ndata/\n.env\n';
    archive.addFile(ArchiveFile('alnaser-wa-server/.gitignore', ignore.length, utf8.encode(ignore)));
    final zip = ZipEncoder().encode(archive)!;

    Directory? dir;
    final home = Platform.environment['USERPROFILE'];
    if (Platform.isWindows && home != null && Directory('$home\\Downloads').existsSync()) {
      dir = Directory('$home\\Downloads');
    }
    try {
      dir ??= await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    final out = File('${dir.path}${Platform.pathSeparator}alnaser-wa-server.zip');
    await out.writeAsBytes(zip, flush: true);
    return out.path;
  }
}
