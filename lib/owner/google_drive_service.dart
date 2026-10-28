// lib/owner/google_drive_service.dart
//
// ☁️ الرفع إلى Google Drive (ميزة حساب المالك):
//   • قاعدة البيانات مضغوطة (zip) — يُحتفظ بآخر [keepBackups] نسخ ويُحذف الأقدم.
//   • سجل الديون PDF — ملف واحد يُستبدل في كل رفع (أحدث نسخة دائماً).
//
// بلا أي حزمة إضافية: OAuth 2.0 (PKCE + loopback) ثم Drive REST v3 عبر http.
// الصلاحية drive.file فقط: البرنامج يرى ويعدّل الملفات التي رفعها هو، لا غيرها.
//
// المفاتيح: GOOGLE_CLIENT_ID و GOOGLE_CLIENT_SECRET في ملف .env
// (عميل OAuth من نوع «Desktop app» في Google Cloud Console، مع تفعيل Google Drive API).
// ويمكن كتابتها من شاشة الإعدادات إن لم تكن في .env.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/database_service.dart';
import '../services/debt_report_service.dart';

class DriveException implements Exception {
  DriveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DriveStatus {
  const DriveStatus({required this.configured, required this.signedIn, this.email, this.lastDb, this.lastDebts});
  final bool configured;
  final bool signedIn;
  final String? email;
  final DateTime? lastDb;
  final DateTime? lastDebts;
}

class GoogleDriveService {
  GoogleDriveService._();
  static final GoogleDriveService instance = GoogleDriveService._();

  static const keepBackups = 5;
  static const _rootFolderName = 'الناصر للحسابات — نسخ احتياطية';
  static const _debtsFileName = 'سجل الديون.pdf';
  static const _scopes = 'openid email https://www.googleapis.com/auth/drive.file';

  static const _kRefresh = 'gdrive_refresh_token';
  static const _kAccess = 'gdrive_access_token';
  static const _kExpiry = 'gdrive_access_expiry';
  static const _kEmail = 'gdrive_email';
  static const _kClientId = 'gdrive_client_id';
  static const _kClientSecret = 'gdrive_client_secret';
  static const _kFolder = 'gdrive_root_folder_id';
  static const _kLastDb = 'gdrive_last_db_upload';
  static const _kLastDebts = 'gdrive_last_debts_upload';

  final _store = const FlutterSecureStorage();
  final _http = http.Client();

  bool get isSupported => !kIsWeb;

  // ═════════════ المفاتيح ═════════════

  String _env(String k) {
    try {
      return dotenv.env[k]?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<(String, String)> _client() async {
    final id = (await _store.read(key: _kClientId))?.trim();
    final secret = (await _store.read(key: _kClientSecret))?.trim();
    return (
      (id != null && id.isNotEmpty) ? id : _env('GOOGLE_CLIENT_ID'),
      (secret != null && secret.isNotEmpty) ? secret : _env('GOOGLE_CLIENT_SECRET'),
    );
  }

  Future<bool> isConfigured() async {
    final (id, secret) = await _client();
    return id.isNotEmpty && secret.isNotEmpty;
  }

  /// المفتاحان المحفوظان (أو من .env) — لعرضهما في نافذة الإدخال
  Future<(String, String)> savedKeys() => _client();

  Future<void> saveClientKeys(String id, String secret) async {
    await _store.write(key: _kClientId, value: id.trim());
    await _store.write(key: _kClientSecret, value: secret.trim());
  }

  Future<DriveStatus> status() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime? t(String k) {
      final v = prefs.getString(k);
      return v == null ? null : DateTime.tryParse(v);
    }

    final refresh = await _store.read(key: _kRefresh);
    return DriveStatus(
      configured: await isConfigured(),
      signedIn: refresh != null && refresh.isNotEmpty,
      email: await _store.read(key: _kEmail),
      lastDb: t(_kLastDb),
      lastDebts: t(_kLastDebts),
    );
  }

  // ═════════════ تسجيل الدخول (PKCE + loopback) ═════════════

  String _random(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// يفتح المتصفح لتسجيل الدخول بحساب Google ثم يعود. يرمي DriveException برسالة واضحة.
  Future<String?> signIn() async {
    if (!isSupported) throw DriveException('الرفع إلى Google Drive غير متاح في نسخة المتصفح');
    final (clientId, secret) = await _client();
    if (clientId.isEmpty || secret.isEmpty) {
      throw DriveException('مفاتيح Google غير مضبوطة: أضف GOOGLE_CLIENT_ID و GOOGLE_CLIENT_SECRET');
    }
    final verifier = _random(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _random(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    try {
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': _scopes,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw DriveException('تعذّر فتح المتصفح لتسجيل الدخول');
      }

      String? code;
      String? error;
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final q = req.uri.queryParameters;
        if (!q.containsKey('code') && !q.containsKey('error')) {
          req.response.statusCode = 404;
          await req.response.close();
          continue;
        }
        if (q['state'] != state) {
          error = 'استجابة غير متوقعة';
        } else {
          code = q['code'];
          error = q['error'];
        }
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html dir="rtl"><body style="font-family:sans-serif;text-align:center;padding-top:80px">'
            '<h2>${code != null ? '✅ تم ربط Google Drive' : '❌ لم يكتمل الربط'}</h2>'
            '<p>يمكنك إغلاق هذه الصفحة والعودة إلى البرنامج.</p></body></html>');
        await req.response.close();
        break;
      }
      if (code == null) {
        throw DriveException(error == 'access_denied' ? 'أُلغي تسجيل الدخول' : 'لم يكتمل تسجيل الدخول${error != null ? ' ($error)' : ''}');
      }

      final res = await _http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
        'client_id': clientId,
        'client_secret': secret,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
      }).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw DriveException('رفضت Google الربط (${res.statusCode}): ${_short(res.body)}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final refresh = '${j['refresh_token'] ?? ''}';
      if (refresh.isEmpty) throw DriveException('لم تُرجع Google رمز التجديد — أعد المحاولة');
      await _store.write(key: _kRefresh, value: refresh);
      await _saveAccess(j);
      await _store.delete(key: _kFolder);

      String? email;
      try {
        final u = await _http.get(Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'),
            headers: {'Authorization': 'Bearer ${j['access_token']}'}).timeout(const Duration(seconds: 15));
        if (u.statusCode == 200) email = '${(jsonDecode(u.body) as Map)['email'] ?? ''}';
      } catch (_) {}
      if (email != null && email.isNotEmpty) await _store.write(key: _kEmail, value: email);
      return email;
    } on TimeoutException {
      throw DriveException('انتهت مهلة تسجيل الدخول (5 دقائق) — أعد المحاولة');
    } on SocketException {
      throw DriveException('لا يوجد اتصال بالإنترنت');
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> signOut() async {
    final refresh = await _store.read(key: _kRefresh);
    if (refresh != null) {
      try {
        await _http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': refresh}).timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    for (final k in [_kRefresh, _kAccess, _kExpiry, _kEmail, _kFolder]) {
      await _store.delete(key: k);
    }
  }

  Future<void> _saveAccess(Map<String, dynamic> j) async {
    await _store.write(key: _kAccess, value: '${j['access_token']}');
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    await _store.write(key: _kExpiry, value: DateTime.now().add(Duration(seconds: secs - 60)).toIso8601String());
  }

  Future<String> _token() async {
    final at = await _store.read(key: _kAccess);
    final exp = DateTime.tryParse(await _store.read(key: _kExpiry) ?? '');
    if (at != null && at.isNotEmpty && exp != null && DateTime.now().isBefore(exp)) return at;
    final refresh = await _store.read(key: _kRefresh);
    if (refresh == null || refresh.isEmpty) throw DriveException('اربط حساب Google Drive أولاً');
    final (clientId, secret) = await _client();
    final http.Response res;
    try {
      res = await _http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
        'client_id': clientId,
        'client_secret': secret,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
      }).timeout(const Duration(seconds: 30));
    } on SocketException {
      throw DriveException('لا يوجد اتصال بالإنترنت');
    } on TimeoutException {
      throw DriveException('انتهت مهلة الاتصال بـ Google');
    }
    if (res.statusCode == 400 || res.statusCode == 401) {
      await _store.delete(key: _kRefresh);
      throw DriveException('انتهى ربط Google Drive (أُلغيت الصلاحية أو تغيّرت كلمة السر) — اربط الحساب من جديد');
    }
    if (res.statusCode != 200) throw DriveException('خطأ من Google (${res.statusCode})');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    await _saveAccess(j);
    return '${j['access_token']}';
  }

  // ═════════════ Drive REST ═════════════

  Future<http.Response> _api(String method, Uri uri, {Map<String, String>? headers, Object? body}) async {
    final token = await _token();
    final req = http.Request(method, uri)..headers.addAll({'Authorization': 'Bearer $token', ...?headers});
    if (body is String) req.body = body;
    if (body is List<int>) req.bodyBytes = body;
    try {
      return await http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 5)));
    } on SocketException {
      throw DriveException('لا يوجد اتصال بالإنترنت');
    } on TimeoutException {
      throw DriveException('انتهت مهلة الرفع — تأكد من الإنترنت');
    }
  }

  static String _q(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<String> _findOrCreateFolder(String name, {String? parent}) async {
    final q = "name = '${_q(name)}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        "${parent != null ? " and '$parent' in parents" : ''}";
    final r = await _api('GET', Uri.https('www.googleapis.com', '/drive/v3/files', {'q': q, 'fields': 'files(id)', 'spaces': 'drive'}));
    if (r.statusCode != 200) throw DriveException('تعذّر الوصول إلى Drive (${r.statusCode}): ${_short(r.body)}');
    final files = (jsonDecode(r.body)['files'] as List?) ?? const [];
    if (files.isNotEmpty) return '${files.first['id']}';
    final c = await _api('POST', Uri.https('www.googleapis.com', '/drive/v3/files', {'fields': 'id'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'name': name,
          'mimeType': 'application/vnd.google-apps.folder',
          if (parent != null) 'parents': [parent],
        }));
    if (c.statusCode != 200) throw DriveException('تعذّر إنشاء مجلد في Drive (${c.statusCode})');
    return '${jsonDecode(c.body)['id']}';
  }

  Future<String> _rootFolder() async {
    final cached = await _store.read(key: _kFolder);
    if (cached != null && cached.isNotEmpty) {
      final r = await _api('GET', Uri.https('www.googleapis.com', '/drive/v3/files/$cached', {'fields': 'id,trashed'}));
      if (r.statusCode == 200 && jsonDecode(r.body)['trashed'] != true) return cached;
    }
    final id = await _findOrCreateFolder(_rootFolderName);
    await _store.write(key: _kFolder, value: id);
    return id;
  }

  /// رفع (أو استبدال [replaceId]) ملف بطريقة الرفع القابل للاستئناف (يناسب الملفات الكبيرة)
  Future<void> _upload(Uint8List bytes, String name, String mime, String folderId, {String? replaceId}) async {
    final init = await _api(
      replaceId == null ? 'POST' : 'PATCH',
      Uri.https('www.googleapis.com', '/upload/drive/v3/files${replaceId == null ? '' : '/$replaceId'}', {'uploadType': 'resumable'}),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'X-Upload-Content-Type': mime,
        'X-Upload-Content-Length': '${bytes.length}',
      },
      body: jsonEncode({'name': name, if (replaceId == null) 'parents': [folderId]}),
    );
    final location = init.headers['location'];
    if (init.statusCode != 200 || location == null) {
      throw DriveException('رفضت Drive بدء الرفع (${init.statusCode}): ${_short(init.body)}');
    }
    final put = await _api('PUT', Uri.parse(location), headers: {'Content-Type': mime}, body: bytes);
    if (put.statusCode != 200 && put.statusCode != 201) {
      throw DriveException('فشل الرفع (${put.statusCode}): ${_short(put.body)}');
    }
  }

  Future<List<Map<String, dynamic>>> _list(String folderId, String extraQ) async {
    final r = await _api('GET', Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': "'$folderId' in parents and trashed = false and $extraQ",
      'fields': 'files(id,name,createdTime)',
      'orderBy': 'createdTime desc',
      'pageSize': '100',
    }));
    if (r.statusCode != 200) return const [];
    return ((jsonDecode(r.body)['files'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  // ═════════════ العمليات ═════════════

  String _deviceFolder() {
    try {
      final n = Platform.localHostname.trim();
      return n.isEmpty ? 'هذا الجهاز' : n;
    } catch (_) {
      return 'هذا الجهاز';
    }
  }

  static String _stamp(DateTime d) =>
      '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}_${_pad2(d.hour)}-${_pad2(d.minute)}-${_pad2(d.second)}';
  static String _pad2(int v) => v.toString().padLeft(2, '0');

  /// للاستعمال خارج Drive (ديسكورد في زر رفع البيانات)
  Future<Uint8List> zippedDatabase() => _zippedDatabase();

  /// 📸 لقطة متّسقة من القاعدة المفتوحة (تشمل ما في -wal) ثم ضغطها zip
  Future<Uint8List> _zippedDatabase() async {
    final db = await DatabaseService().database;
    final tmp = await Directory.systemTemp.createTemp('gdrive_snap_');
    try {
      final snap = '${tmp.path}${Platform.pathSeparator}snapshot.db';
      Uint8List bytes;
      try {
        await db.execute("VACUUM INTO '${snap.replaceAll("'", "''")}'");
        bytes = await File(snap).readAsBytes();
      } catch (e) {
        debugPrint('☁️ Drive: VACUUM INTO تعذّر ($e) — checkpoint ثم نسخ الملف');
        try {
          await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
        } catch (_) {}
        bytes = await File(db.path).readAsBytes();
      }
      final archive = Archive()..addFile(ArchiveFile('database.db', bytes.length, bytes));
      final zip = ZipEncoder().encode(archive);
      if (zip == null) throw DriveException('تعذّر ضغط قاعدة البيانات');
      return Uint8List.fromList(zip);
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// يرفع قاعدة البيانات مضغوطة إلى «<المجلد الرئيسي>/<اسم الجهاز>»، ويبقي آخر [keepBackups] نسخ.
  Future<String> uploadDatabase({void Function(String step)? onStep}) async {
    onStep?.call('تجهيز نسخة من قاعدة البيانات...');
    final zip = await _zippedDatabase();
    onStep?.call('الاتصال بـ Google Drive...');
    final root = await _rootFolder();
    final folder = await _findOrCreateFolder(_deviceFolder(), parent: root);
    final name = 'قاعدة_البيانات_${_stamp(DateTime.now())}.zip';
    onStep?.call('رفع ${(zip.length / 1048576).toStringAsFixed(1)} ميجا...');
    await _upload(zip, name, 'application/zip', folder);

    onStep?.call('حذف النسخ الأقدم...');
    final files = await _list(folder, "name contains '.zip'");
    for (final f in files.skip(keepBackups)) {
      try {
        await _api('DELETE', Uri.https('www.googleapis.com', '/drive/v3/files/${f['id']}'));
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDb, DateTime.now().toIso8601String());
    return name;
  }

  /// يرفع سجل الديون PDF (نفس تقرير زر «تقرير الديون») ويستبدل النسخة السابقة.
  Future<void> uploadDebtsPdf({void Function(String step)? onStep}) async {
    onStep?.call('إنشاء سجل الديون PDF...');
    final pdf = await DebtReportService.generateReportPdf();
    onStep?.call('الاتصال بـ Google Drive...');
    final root = await _rootFolder();
    final existing = await _list(root, "name = '${_q(_debtsFileName)}'");
    onStep?.call('رفع سجل الديون...');
    await _upload(pdf, _debtsFileName, 'application/pdf', root, replaceId: existing.isEmpty ? null : '${existing.first['id']}');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastDebts, DateTime.now().toIso8601String());
  }

  static String _short(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;
}
