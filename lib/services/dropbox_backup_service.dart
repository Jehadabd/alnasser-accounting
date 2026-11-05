// lib/services/dropbox_backup_service.dart
// 🔥 خدمة النسخ الاحتياطي إلى Dropbox مع تدوير النسخ الذكي
//
// إصلاحات (مراجعة الجلسة):
//   • النسخة الناجحة كانت تُبلَّغ «فشلاً»: كان حجم الملف يُقرأ بعد حذف الملف المؤقت
//     فيرمي استثناءً يلتقطه catch العام → «خطأ غير متوقع» رغم أن الرفع تمّ.
//   • القاعدة تعمل بوضع WAL: نسخ ملف .db وحده قد يُسقط آخر العمليات (ما زالت في
//     ملف -wal). الآن نأخذ لقطة متّسقة بـ VACUUM INTO (وإن تعذّر: checkpoint ثم نسخ).
//   • رمز الدخول قصير العمر (~4 ساعات) ولم يكن يُجدَّد رغم حفظ refresh_token →
//     كان يُطلب تسجيل الدخول من جديد. الآن يُجدَّد تلقائياً، ويُعاد الطلب مرة عند 401.
//   • الاستعادة كانت تحذف ملف القاعدة وهي مفتوحة (يفشل على ويندوز أو يُطبَّق ملف
//     -wal القديم على النسخة المستعادة). الآن تمرّ عبر restoreDatabaseFromFile
//     (إغلاق → حذف -wal/-shm → فحص سلامة → تراجع تلقائي عند الفشل).
//   • مهلات زمنية لكل الطلبات، وتمييز «لا إنترنت» عن «انتهت المصادقة».
//   • عدد النسخ المحتفظ بها يُحفظ (كان يعود 20 دائماً، والرفع التلقائي يتجاهله).
//   • رفع الملفات > 140MB عبر جلسة رفع (حد files/upload هو 150MB).

import 'dart:io';
import 'dart:convert';
import 'dart:math' show Random;
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../lan/lan_settings.dart' show AppNetworkMode;
import 'database_service.dart';
import 'backup_space_planner.dart';
import 'backup_files.dart';
import 'backup_package.dart';

/// 📦 معلومات النسخة الاحتياطية
class BackupInfo {
  final String name;
  final String path;
  final DateTime modifiedTime;
  final int size;

  BackupInfo({
    required this.name,
    required this.path,
    required this.modifiedTime,
    required this.size,
  });

  factory BackupInfo.fromJson(Map<String, dynamic> json) {
    return BackupInfo(
      name: json['name'] ?? '',
      path: json['path_lower'] ?? '',
      modifiedTime: json['server_modified'] != null
          ? (DateTime.tryParse(json['server_modified'].toString())?.toLocal() ?? DateTime.now())
          : DateTime.now(),
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 📊 نتيجة عملية النسخ الاحتياطي
class BackupResult {
  final bool success;
  final String? error;
  final String? backupName;
  final int? backupSize;
  final int? deletedCount;

  /// حُذفت قبل الرفع لإفساح المكان.
  final int freedForSpace;

  BackupResult({
    required this.success,
    this.error,
    this.backupName,
    this.backupSize,
    this.deletedCount,
    this.freedForSpace = 0,
  });
}

/// 💾 مساحة حساب Dropbox (بايت). [allocated] null = غير معروفة.
class DropboxSpace {
  const DropboxSpace({required this.used, this.allocated});
  final int used;
  final int? allocated;
  int? get free => allocated == null ? null : (allocated! - used).clamp(0, allocated!).toInt();
}

/// 🔐 حالة الاتصال بـ Dropbox
enum DropboxAuthStatus {
  notConfigured,
  needsAuth,
  authenticated,
  error,
}

/// خطأ من Dropbox برسالة مفهومة.
/// حالة إذن واحد في فحص الأذونات.
enum DropboxScopeState { granted, missing, unknown }

/// خطوة واحدة من فحص الأذونات (طلب حقيقي صغير إلى Dropbox).
class DropboxProbe {
  const DropboxProbe(this.label, this.scope, this.ok, [this.detail]);
  final String label;
  final String scope;
  final bool ok;

  /// ردّ Dropbox كما وصل (عند الفشل).
  final String? detail;
}

/// 🩺 نتيجة فحص الأذونات: لكل إذن مطلوب حالته، ولكل خطوة نتيجتها.
class DropboxPermissionReport {
  const DropboxPermissionReport({required this.scopes, required this.probes, this.tokenScopes, this.fatal});

  /// الأذونات المطلوبة بالترتيب ← حالتها.
  final Map<String, DropboxScopeState> scopes;
  final List<DropboxProbe> probes;

  /// الأذونات التي منحها Dropbox لهذا الربط لحظة الاتصال (null = ربط قديم لم تُحفظ له).
  final List<String>? tokenScopes;

  /// خطأ منع الفحص نفسه (لا إنترنت، انتهى الاتصال...).
  final String? fatal;

  List<String> get missing => [
        for (final e in scopes.entries)
          if (e.value == DropboxScopeState.missing) e.key
      ];

  /// خطوة فشلت لسبب غير الأذونات.
  DropboxProbe? get otherFailure {
    for (final p in probes) {
      if (!p.ok && scopes[p.scope] != DropboxScopeState.missing) return p;
    }
    return null;
  }

  bool get allOk => fatal == null && probes.isNotEmpty && probes.every((p) => p.ok);
}

class DropboxException implements Exception {
  DropboxException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 🔥 خدمة النسخ الاحتياطي إلى Dropbox
class DropboxBackupService {
  static final DropboxBackupService _instance = DropboxBackupService._internal();
  factory DropboxBackupService() => _instance;
  DropboxBackupService._internal();

  // 🔑 تطبيق Dropbox (App Console). الربط بطريقة PKCE: يكفي «App key» العام — لا سرّ
  //    (App secret) داخل البرنامج. التطبيق القديم (StoreApp) كان بحساب آخر ولا تُضبط أذوناته.
  static const String defaultAppKey = '3qcpvyen8wn3cvp';
  static const String defaultAppName = 'asdfghertyu';
  static const String _appKeyPref = 'dropbox_app_key';
  static const String _appNamePref = 'dropbox_app_name';

  // 📁 مسار النسخ الاحتياطية في Dropbox
  static const String _backupFolder = '/Apps/StoreApp/backups';

  // 🔢 العدد الافتراضي للنسخ المحتفظ بها
  static const int _defaultMaxBackups = 20;
  static const String _maxBackupsKey = 'dropbox_max_backups';
  static const List<int> maxBackupsChoices = [10, 15, 20, 30, 50];

  // 🔐 تخزين آمن للتوكن
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _tokenKey = 'dropbox_access_token';
  static const String _refreshTokenKey = 'dropbox_refresh_token';
  static const String _grantedScopesKey = 'dropbox_granted_scopes';
  static const String _tokenAppKeyKey = 'dropbox_token_app_key'; // التطبيق الذي رُبط به الرمز
  static const String _pkceVerifierKey = 'dropbox_pkce_verifier';
  String? _pkceVerifier;

  /// مفتاح تطبيق Dropbox المستعمل (معرّف عام وليس سرّاً) — يطابقه المستخدم بعمود
  /// «App key» في App Console.
  Future<String> appKey() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_appKeyPref)?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return defaultAppKey;
  }

  /// اسم تطبيق Dropbox كما في App Console (للعرض فقط — Dropbox لا يعطيه عبر الـ API).
  Future<String> appName() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_appNamePref)?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return defaultAppName;
  }

  static final _appKeyPattern = RegExp(r'^[a-z0-9]{8,32}$');
  static bool isValidAppKey(String k) => _appKeyPattern.hasMatch(k.trim());

  /// تغيير تطبيق Dropbox. تغيير المفتاح يقطع الاتصال الحالي (الرمز مربوط بالتطبيق).
  Future<void> setApp({required String key, required String name}) async {
    final k = key.trim();
    if (!isValidAppKey(k)) throw DropboxException('App key غير صحيح — انسخه من عمود «App key» في App Console.');
    final changed = k != await appKey();
    if (changed) await logout();
    final prefs = await SharedPreferences.getInstance();
    if (k == defaultAppKey) {
      await prefs.remove(_appKeyPref);
    } else {
      await prefs.setString(_appKeyPref, k);
    }
    final n = name.trim();
    if (n.isEmpty || n == defaultAppName) {
      await prefs.remove(_appNamePref);
    } else {
      await prefs.setString(_appNamePref, n);
    }
  }

  /// هل يوجد ربط محفوظ لكن بتطبيق Dropbox آخر (قديم)؟ ⇒ يلزم الربط من جديد مرة.
  Future<bool> linkedToOtherApp() async {
    final t = await _secureStorage.read(key: _tokenKey);
    if (t == null || t.isEmpty) return false;
    return await _secureStorage.read(key: _tokenAppKeyKey) != await appKey();
  }

  /// آخر ردّ رفض به Dropbox الكود (للعرض).
  String? lastAuthError;

  // 🌐 API Endpoints
  static const String _apiContentUrl = 'https://content.dropboxapi.com/2';
  static const String _apiUrl = 'https://api.dropboxapi.com/2';
  static const String _tokenUrl = 'https://api.dropboxapi.com/oauth2/token';

  // ⏱️ مهلات
  static const Duration _shortTimeout = Duration(seconds: 30);
  static const Duration _transferTimeout = Duration(minutes: 10);

  // 📏 حد files/upload هو 150MB؛ فوق هذا نستعمل جلسة رفع مجزّأة.
  static const int _singleUploadLimit = 140 * 1024 * 1024;
  static const int _chunkSize = 8 * 1024 * 1024;

  /// 🔑 الحصول على Access Token (null إن كان مربوطاً بتطبيق Dropbox آخر)
  Future<String?> getAccessToken() async {
    final t = await _secureStorage.read(key: _tokenKey);
    if (t == null || t.isEmpty) return t;
    if (await _secureStorage.read(key: _tokenAppKeyKey) != await appKey()) return null;
    return t;
  }

  /// 🔑 حفظ Access Token
  Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  /// 🔑 حفظ Refresh Token
  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  /// 🔑 الحصول على Refresh Token
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _refreshTokenKey);
  }

  /// 🔢 عدد النسخ المحتفظ بها (محفوظ على الجهاز)
  Future<int> getMaxBackups() async {
    try {
      final v = (await SharedPreferences.getInstance()).getInt(_maxBackupsKey);
      if (v != null && v > 0) return v;
    } catch (_) {}
    return _defaultMaxBackups;
  }

  Future<void> setMaxBackups(int n) async {
    try {
      await (await SharedPreferences.getInstance()).setInt(_maxBackupsKey, n);
    } catch (_) {}
  }

  /// 🔄 تجديد رمز الدخول بالـ refresh_token. يعيد الرمز الجديد أو null.
  Future<String?> _refreshAccessToken() async {
    final rt = await getRefreshToken();
    if (rt == null || rt.isEmpty) return null;
    try {
      final r = await http.post(Uri.parse(_tokenUrl), body: {
        'grant_type': 'refresh_token',
        'refresh_token': rt,
        'client_id': await appKey(), // PKCE: بلا client_secret
      }).timeout(_shortTimeout);
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        final t = data['access_token'] as String?;
        if (t != null && t.isNotEmpty) {
          await saveAccessToken(t);
          final sc = data['scope'];
          if (sc is String && sc.trim().isNotEmpty) await _secureStorage.write(key: _grantedScopesKey, value: sc.trim());
          return t;
        }
      }
      debugPrint('⚠️ Dropbox: تعذّر تجديد الرمز (${r.statusCode}) ${r.body}');
    } catch (e) {
      debugPrint('⚠️ Dropbox: خطأ شبكة أثناء تجديد الرمز: $e');
      rethrow; // خطأ شبكة ≠ مصادقة منتهية
    }
    return null;
  }

  /// طلب POST بالرمز الحالي؛ عند 401 يجدّد الرمز ويعيد المحاولة مرة واحدة.
  Future<http.Response> _authorizedPost(
    String url, {
    Map<String, String> headers = const {},
    Object? body,
    Duration timeout = _shortTimeout,
  }) async {
    var token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw DropboxException('لم يتم الاتصال بـ Dropbox. يرجى تسجيل الدخول أولاً.');
    }
    Future<http.Response> send(String t) => http
        .post(Uri.parse(url), headers: {'Authorization': 'Bearer $t', ...headers}, body: body)
        .timeout(timeout);

    var r = await send(token);
    if (r.statusCode == 401) {
      final fresh = await _refreshAccessToken();
      if (fresh == null) throw DropboxException('انتهت صلاحية الاتصال بـ Dropbox — سجّل الدخول من جديد.');
      r = await send(fresh);
    }
    return r;
  }

  /// 🔌 التحقق من حالة الاتصال
  Future<DropboxAuthStatus> checkAuthStatus() async {
    try {
      if (await linkedToOtherApp()) return DropboxAuthStatus.needsAuth; // تغيّر التطبيق ⇒ اربط من جديد
      final token = await getAccessToken();
      if (token == null || token.isEmpty) {
        return DropboxAuthStatus.notConfigured;
      }
      final r = await _authorizedPost('$_apiUrl/users/get_current_account');
      if (r.statusCode == 200) return DropboxAuthStatus.authenticated;
      if (r.statusCode == 401 || r.statusCode == 400) return DropboxAuthStatus.needsAuth;
      return DropboxAuthStatus.error;
    } on DropboxException {
      return DropboxAuthStatus.needsAuth;
    } catch (e) {
      // لا إنترنت / مهلة: ليست «انتهاء مصادقة»
      debugPrint('⚠️ Dropbox: فحص الاتصال فشل: $e');
      return DropboxAuthStatus.error;
    }
  }

  /// 👤 اسم/بريد الحساب المتصل (للعرض فقط).
  Future<String?> getAccountLabel() async {
    try {
      final r = await _authorizedPost('$_apiUrl/users/get_current_account');
      if (r.statusCode != 200) return null;
      final data = json.decode(utf8.decode(r.bodyBytes));
      final name = data['name']?['display_name']?.toString();
      final email = data['email']?.toString();
      return [if (name != null && name.isNotEmpty) name, if (email != null && email.isNotEmpty) email].join(' • ');
    } catch (_) {
      return null;
    }
  }

  /// 🩺 فحص الأذونات بطلبات حقيقية صغيرة، كلٌّ منها يحتاج إذناً واحداً:
  /// الحساب ← قائمة النسخ ← رفع ملف اختبار صغير ← تنزيله ← حذفه.
  /// ما ينجح = الإذن موجود فعلاً؛ ما يرفضه Dropbox يذكر هو اسم الإذن الناقص.
  /// ملف الاختبار `.permission_check.txt` يُحذف فوراً ولا يُحسب نسخةً (القائمة تأخذ backup_* فقط).
  Future<DropboxPermissionReport> checkPermissionsDetailed() async {
    final token = await grantedScopes();
    final states = <String, DropboxScopeState>{
      for (final s in requiredScopes)
        s: token == null ? DropboxScopeState.unknown : (token.contains(s) ? DropboxScopeState.granted : DropboxScopeState.missing),
    };
    final probes = <DropboxProbe>[];
    const probePath = '$_backupFolder/.permission_check.txt';

    Future<bool> run(String label, String scope, Future<http.Response> Function() call,
        {bool Function(http.Response r)? alsoOk}) async {
      final r = await call();
      final ok = r.statusCode == 200 || (alsoOk?.call(r) ?? false);
      if (ok) {
        states[scope] = DropboxScopeState.granted; // نجح الطلب = الإذن موجود فعلاً
        probes.add(DropboxProbe(label, scope, true));
      } else {
        final need = requiredScopeOf(utf8.decode(r.bodyBytes, allowMalformed: true));
        if (need != null) states[need] = DropboxScopeState.missing;
        probes.add(DropboxProbe(label, need ?? scope, false, _describeRaw(r)));
      }
      return ok;
    }

    String? fatal;
    try {
      await run('قراءة معلومات الحساب', 'account_info.read', () => _authorizedPost('$_apiUrl/users/get_current_account'));
      await run(
        'عرض قائمة النسخ',
        'files.metadata.read',
        () => _authorizedPost(
          '$_apiUrl/files/list_folder',
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'path': _backupFolder, 'recursive': false}),
        ),
        alsoOk: (r) => r.statusCode == 409 && r.body.contains('not_found'), // لا مجلد بعد = القراءة مسموحة
      );
      final uploaded = await run(
        'رفع ملف اختبار صغير',
        'files.content.write',
        () => _authorizedPost(
          '$_apiContentUrl/files/upload',
          headers: {
            'Content-Type': 'application/octet-stream',
            'Dropbox-API-Arg': _apiArg({'path': probePath, 'mode': 'overwrite', 'mute': true}),
          },
          body: utf8.encode('permission check ${DateTime.now().toIso8601String()}'),
        ),
      );
      if (uploaded) {
        await run(
          'تنزيل ملف الاختبار',
          'files.content.read',
          () => _authorizedPost('$_apiContentUrl/files/download', headers: {'Dropbox-API-Arg': _apiArg({'path': probePath})}),
        );
        await run(
          'حذف ملف الاختبار',
          'files.content.write',
          () => _authorizedPost(
            '$_apiUrl/files/delete_v2',
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'path': probePath}),
          ),
        );
      }
    } on DropboxException catch (e) {
      fatal = e.message;
    } on SocketException catch (e) {
      fatal = 'تعذّر الوصول إلى Dropbox (الإنترنت؟): ${e.message}';
    } catch (e) {
      fatal = '$e';
    }
    return DropboxPermissionReport(scopes: states, probes: probes, tokenScopes: token, fatal: fatal);
  }

  /// ردّ Dropbox كما هو (مختصراً) مع رقم الحالة — للعرض في الفحص.
  static String _describeRaw(http.Response r) {
    var raw = '';
    try {
      raw = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
    } catch (_) {}
    if (raw.length > 400) raw = '${raw.substring(0, 400)}…';
    return 'HTTP ${r.statusCode}${raw.isEmpty ? '' : ' — $raw'}';
  }

  /// 💾 مساحة الحساب: المستعمل والكلي. null إن تعذّر السؤال (لا يمنع الرفع).
  Future<DropboxSpace?> getSpaceUsage() async {
    try {
      final r = await _authorizedPost('$_apiUrl/users/get_space_usage');
      if (r.statusCode != 200) return null;
      final data = json.decode(utf8.decode(r.bodyBytes));
      final used = (data['used'] as num?)?.toInt() ?? 0;
      final a = data['allocation'];
      int? allocated;
      if (a is Map) {
        final tag = a['.tag'];
        if (tag == 'individual') {
          allocated = (a['allocated'] as num?)?.toInt();
        } else if (tag == 'team') {
          // حساب فريق: المساحة المشتركة، أو حصة المستخدم إن حُدّدت له
          final teamAlloc = (a['allocated'] as num?)?.toInt();
          final teamUsed = (a['used'] as num?)?.toInt() ?? used;
          final userCap = (a['user_within_team_space_allocated'] as num?)?.toInt() ?? 0;
          if (teamAlloc != null) {
            final teamFree = teamAlloc - teamUsed;
            final userFree = userCap > 0 ? userCap - used : teamFree;
            return DropboxSpace(used: used, allocated: used + (teamFree < userFree ? teamFree : userFree));
          }
        }
      }
      return DropboxSpace(used: used, allocated: allocated);
    } catch (e) {
      debugPrint('⚠️ Dropbox: تعذّر جلب المساحة: $e');
      return null;
    }
  }

  /// 🔗 رابط الموافقة في Dropbox (PKCE، بلا إعادة توجيه: يعرض Dropbox الكود فينسخه المستخدم).
  /// يولّد «code_verifier» عشوائياً ويحفظه حتى لصق الكود (يبقى بعد إعادة فتح البرنامج).
  Future<String> getAuthorizationUrl() async {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    final verifier = List.generate(64, (_) => chars[rnd.nextInt(chars.length)]).join();
    _pkceVerifier = verifier;
    await _secureStorage.write(key: _pkceVerifierKey, value: verifier);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final key = await appKey();
    return 'https://www.dropbox.com/oauth2/authorize?'
        'client_id=$key&'
        'response_type=code&'
        'code_challenge=$challenge&'
        'code_challenge_method=S256&'
        // نطلب الأذونات صراحةً: إن نقص التطبيقَ إذنٌ في App Console يرفض Dropbox من البداية
        // في صفحة الموافقة نفسها بدل ربطٍ «ناجح» يفشل عند الرفع.
        'scope=${Uri.encodeComponent(requiredScopes.join(' '))}&'
        'token_access_type=offline';
  }

  /// يستخرج الكود سواء لُصق وحده أو لُصق رابط الإعادة كاملاً (http://localhost/?code=...).
  static String extractAuthCode(String input) {
    final s = input.trim();
    if (s.contains('code=')) {
      final uri = Uri.tryParse(s);
      final fromQuery = uri?.queryParameters['code'];
      if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
      final m = RegExp(r'code=([^&#\s]+)').firstMatch(s);
      if (m != null) return Uri.decodeComponent(m.group(1)!);
    }
    return s;
  }

  /// 🔐 تبديل Authorization Code بـ Access Token
  Future<bool> exchangeCodeForToken(String code) async {
    lastAuthError = null;
    final verifier = _pkceVerifier ?? await _secureStorage.read(key: _pkceVerifierKey);
    if (verifier == null || verifier.isEmpty) {
      lastAuthError = 'اضغط «فتح صفحة Dropbox» من البرنامج أولاً ثم الصق الكود الذي يظهر.';
      return false;
    }
    final key = await appKey();
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'code': extractAuthCode(code),
          'grant_type': 'authorization_code',
          'client_id': key,
          'code_verifier': verifier, // PKCE بدل client_secret
        },
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await saveAccessToken(data['access_token']);
        if (data['refresh_token'] != null) {
          await saveRefreshToken(data['refresh_token']);
        }
        await _secureStorage.write(key: _tokenAppKeyKey, value: key);
        _pkceVerifier = null;
        await _secureStorage.delete(key: _pkceVerifierKey);
        // Dropbox يذكر الأذونات الممنوحة فعلاً لهذا الربط — نحفظها لفحص الأذونات.
        final sc = data['scope'];
        if (sc is String && sc.trim().isNotEmpty) {
          await _secureStorage.write(key: _grantedScopesKey, value: sc.trim());
        } else {
          await _secureStorage.delete(key: _grantedScopesKey);
        }
        return true;
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
      lastAuthError = body.length > 300 ? '${body.substring(0, 300)}…' : body;
      debugPrint('❌ Dropbox: رُفض الكود (${response.statusCode}) $body');
      return false;
    } catch (e) {
      lastAuthError = '$e';
      debugPrint('❌ خطأ في تبديل الكود: $e');
      return false;
    }
  }

  /// 🚪 تسجيل الخروج (مع إبطال الرمز على خادم Dropbox إن أمكن)
  Future<void> logout() async {
    try {
      final t = await _secureStorage.read(key: _tokenKey); // حتى لو كان بتطبيق قديم
      if (t != null && t.isNotEmpty) {
        await http
            .post(Uri.parse('$_apiUrl/auth/token/revoke'), headers: {'Authorization': 'Bearer $t'})
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {}
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _grantedScopesKey);
    await _secureStorage.delete(key: _tokenAppKeyKey);
  }

  /// الأذونات الممنوحة لهذا الربط كما ذكرها Dropbox لحظة الاتصال (null = غير معروفة).
  Future<List<String>?> grantedScopes() async {
    final v = await _secureStorage.read(key: _grantedScopesKey);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim().split(RegExp(r'\s+'));
  }

  String _stampName(DateTime now, String extension) =>
      'backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
      '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}$extension';

  /// ☁️ رفع النسخة إلى Dropbox. يرمي DropboxException برسالة واضحة عند الفشل.
  Future<void> _uploadToDropbox(File file, String remotePath) async {
    final fileBytes = await file.readAsBytes();
    final commit = {'path': remotePath, 'mode': 'add', 'autorename': true, 'mute': false};

    if (fileBytes.length <= _singleUploadLimit) {
      final r = await _authorizedPost(
        '$_apiContentUrl/files/upload',
        headers: {'Content-Type': 'application/octet-stream', 'Dropbox-API-Arg': _apiArg(commit)},
        body: fileBytes,
        timeout: _transferTimeout,
      );
      if (r.statusCode != 200) throw DropboxException(_describe(r));
      return;
    }

    // جلسة رفع مجزّأة للملفات الكبيرة
    var offset = 0;
    final first = fileBytes.sublist(0, _chunkSize);
    var r = await _authorizedPost(
      '$_apiContentUrl/files/upload_session/start',
      headers: {'Content-Type': 'application/octet-stream', 'Dropbox-API-Arg': _apiArg({'close': false})},
      body: first,
      timeout: _transferTimeout,
    );
    if (r.statusCode != 200) throw DropboxException(_describe(r));
    final sessionId = json.decode(r.body)['session_id'] as String;
    offset = first.length;

    while (fileBytes.length - offset > _chunkSize) {
      final chunk = fileBytes.sublist(offset, offset + _chunkSize);
      r = await _authorizedPost(
        '$_apiContentUrl/files/upload_session/append_v2',
        headers: {
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': _apiArg({
            'cursor': {'session_id': sessionId, 'offset': offset},
            'close': false,
          }),
        },
        body: chunk,
        timeout: _transferTimeout,
      );
      if (r.statusCode != 200) throw DropboxException(_describe(r));
      offset += chunk.length;
    }

    final last = fileBytes.sublist(offset);
    r = await _authorizedPost(
      '$_apiContentUrl/files/upload_session/finish',
      headers: {
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': _apiArg({
          'cursor': {'session_id': sessionId, 'offset': offset},
          'commit': commit,
        }),
      },
      body: last,
      timeout: _transferTimeout,
    );
    if (r.statusCode != 200) throw DropboxException(_describe(r));
  }

  /// ترويسة Dropbox-API-Arg: يجب أن تكون ASCII — نهرّب أي حرف غير ASCII (\uXXXX).
  static String _apiArg(Map<String, dynamic> arg) {
    final raw = json.encode(arg);
    final sb = StringBuffer();
    for (final c in raw.codeUnits) {
      if (c < 0x7f) {
        sb.writeCharCode(c);
      } else {
        sb.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return sb.toString();
  }

  /// صفحة إعدادات تطبيقات Dropbox (لتفعيل الأذونات).
  static const appConsoleUrl = 'https://www.dropbox.com/developers/apps';

  /// الأذونات التي يستعملها البرنامج فعلاً (تبويب «Permissions» في App Console):
  ///   account_info.read  ← اسم الحساب والمساحة (users/get_current_account, get_space_usage)
  ///   files.metadata.read ← قائمة النسخ (files/list_folder)
  ///   files.content.write ← رفع النسخ وحذف الأقدم (files/upload, files/delete_v2)
  ///   files.content.read  ← تنزيل نسخة للاستعادة (files/download)
  static const requiredScopes = [
    'account_info.read',
    'files.metadata.read',
    'files.content.write',
    'files.content.read',
  ];

  /// شرح كل إذن بالعربية (للعرض).
  static const scopeMeaning = {
    'account_info.read': 'قراءة اسم الحساب والمساحة',
    'files.metadata.read': 'عرض قائمة النسخ',
    'files.content.write': 'رفع النسخ وحذف الأقدم',
    'files.content.read': 'تنزيل نسخة للاستعادة',
  };

  /// اسم الإذن الذي ذكره Dropbox في ردّه (JSON أو نص عادي)، أو null.
  static String? requiredScopeOf(String raw) {
    try {
      final j = json.decode(raw);
      final e = j is Map ? j['error'] : null;
      if (e is Map && e['required_scope'] is String) return e['required_scope'] as String;
    } catch (_) {}
    return RegExp(r"required scope '([a-z_.]+)'").firstMatch(raw)?.group(1);
  }

  /// رسالة «إذن ناقص» — يعرّف بها البرنامج هذا الخطأ تحديداً.
  static const missingScopeMarker = 'ينقص تطبيق Dropbox إذن';

  static String _describe(http.Response r) {
    String summary = '';
    String raw = '';
    try {
      raw = utf8.decode(r.bodyBytes, allowMalformed: true).trim();
    } catch (_) {}
    try {
      summary = (json.decode(raw)['error_summary'] ?? '').toString();
    } catch (_) {}
    // Dropbox يذكر الإذن الناقص: JSON {error: {required_scope}} أو نص عادي
    // «... does not have the required scope 'files.metadata.read' ...»
    final scope = requiredScopeOf(raw);
    if (scope != null || summary.contains('missing_scope')) {
      return '$missingScopeMarker «${scope ?? 'غير محدد'}». افتح شاشة Dropbox في البرنامج ← «فحص الأذونات» '
          'لترى الناقص بالضبط وطريقة إصلاحه.';
    }
    if (summary.contains('insufficient_space')) return 'لا توجد مساحة كافية في حساب Dropbox.';
    if (summary.contains('too_many_write_operations')) return 'Dropbox مشغول الآن — أعد المحاولة بعد قليل.';
    if (r.statusCode == 401) return 'انتهت صلاحية الاتصال بـ Dropbox — سجّل الدخول من جديد.';
    if (r.statusCode == 429) return 'طلبات كثيرة على Dropbox — أعد المحاولة بعد قليل.';
    final detail = summary.isNotEmpty ? summary : (raw.length > 200 ? '${raw.substring(0, 200)}…' : raw);
    return 'رفض Dropbox الطلب (${r.statusCode})${detail.isEmpty ? '' : ': $detail'}';
  }

  /// 📋 جلب قائمة النسخ من Dropbox. يرمي DropboxException عند الفشل
  /// (المجلد غير الموجود بعد = قائمة فارغة).
  Future<List<BackupInfo>> _fetchRemoteBackups() async {
    final out = <BackupInfo>[];
    var r = await _authorizedPost(
      '$_apiUrl/files/list_folder',
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': _backupFolder, 'recursive': false, 'include_deleted': false}),
    );
    while (true) {
      if (r.statusCode == 409 && r.body.contains('not_found')) return out; // لا مجلد بعد
      if (r.statusCode != 200) throw DropboxException(_describe(r));
      final data = json.decode(utf8.decode(r.bodyBytes));
      final entries = (data['entries'] as List?) ?? const [];
      out.addAll(entries
          .where((e) => e['.tag'] == 'file' && e['name'].toString().startsWith('backup_'))
          .map((e) => BackupInfo.fromJson(Map<String, dynamic>.from(e as Map))));
      if (data['has_more'] != true) return out;
      r = await _authorizedPost(
        '$_apiUrl/files/list_folder/continue',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'cursor': data['cursor']}),
      );
    }
  }

  /// 🗑️ حذف ملف من Dropbox
  Future<bool> _deleteFromDropbox(String path) async {
    try {
      final response = await _authorizedPost(
        '$_apiUrl/files/delete_v2',
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'path': path}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ خطأ في الحذف: $e');
      return false;
    }
  }

  /// 🚀 إنشاء ورفع نسخة احتياطية مع تدوير تلقائي.
  /// [maxBackups] اختياري: بدونه يُستعمل العدد المحفوظ في الإعدادات.
  Future<BackupResult> createAndUploadBackup({
    int? maxBackups,
    Function(int progress, String status)? onProgress,
  }) async {
    if (AppNetworkMode.isClient) {
      return BackupResult(
        success: false,
        error: 'هذا الجهاز طرفية متصلة بالخادم — النسخ الاحتياطي يُؤخذ من جهاز الخادم.',
      );
    }
    BackupPackage? ownedPkg;
    try {
      final max = maxBackups ?? await getMaxBackups();

      // 1. التحقق من الاتصال
      onProgress?.call(5, 'التحقق من الاتصال بـ Dropbox...');
      final authStatus = await checkAuthStatus();
      if (authStatus != DropboxAuthStatus.authenticated) {
        return BackupResult(
          success: false,
          error: authStatus == DropboxAuthStatus.error
              ? 'تعذّر الوصول إلى Dropbox — تحقّق من الإنترنت.'
              : 'لم يتم الاتصال بـ Dropbox. يرجى تسجيل الدخول أولاً.',
        );
      }

      // 2. الحزمة الموحّدة (الملف نفسه المرفوع لتيليجرام: لقطة + فحص سلامة + XZ متحقق منه)
      onProgress?.call(15, 'إنشاء النسخة الاحتياطية (ضغط وتحقق)...');
      final BackupPackage pkg;
      try {
        final got = await BackupPackage.obtain(onProgress: (v) => onProgress?.call(15 + (v * 6).round(), 'ضغط النسخة والتحقق منها...'));
        pkg = got.pkg;
        if (got.owned) ownedPkg = pkg;
      } catch (e) {
        return BackupResult(success: false, error: 'فشل إنشاء النسخة الاحتياطية: ${'$e'.replaceFirst('Exception: ', '')}');
      }
      final localBackup = pkg.file;
      final remoteName = _stampName(pkg.createdAt, pkg.extension);
      // ⚠️ الحجم يُقرأ قبل حذف الملف المؤقت (كان يُقرأ بعده فيفشل كل نسخ ناجح).
      final size = await localBackup.length();

      // 3. خطة الحذف: الأقدم فالأقدم للمساحة (قبل الرفع) وللعدد (بعده)، ولا تُمسّ أحدث نسختين
      onProgress?.call(22, 'فحص المساحة في Dropbox...');
      // تعذّرت القائمة ⇒ لا حذف إطلاقاً (لا نحذف على قائمة لا نعرفها)، ويُكمل الرفع كما كان
      List<BackupInfo> existing = const [];
      var listed = false;
      try {
        existing = await _fetchRemoteBackups();
        listed = true;
      } on DropboxException catch (e) {
        // إذن ناقص: الرفع سيُرفض أيضاً (ويقطع Dropbox الاتصال فيبدو «لا إنترنت») ⇒ نتوقف بالسبب الحقيقي
        if (e.message.startsWith(missingScopeMarker)) return BackupResult(success: false, error: e.message);
        debugPrint('⚠️ Dropbox: تعذّرت قائمة النسخ — رفع بلا حذف: ${e.message}');
      } catch (e) {
        debugPrint('⚠️ Dropbox: تعذّرت قائمة النسخ — رفع بلا حذف: $e');
      }
      final space = listed ? await getSpaceUsage() : null;
      final plan = BackupSpacePlanner.plan<BackupInfo>(
        existing: [for (final b in existing) BackupItem(b, b.modifiedTime, b.size)],
        newSize: size,
        free: space?.free,
        maxCount: max,
      );
      if (!plan.fits) {
        return BackupResult(
          success: false,
          error: 'المساحة في Dropbox لا تكفي حتى بعد حذف النسخ القديمة '
              '(الفارغ ${BackupSpacePlanner.human(plan.freeBefore ?? 0)}، المطلوب ${BackupSpacePlanner.human(plan.needed)}). '
              'المساحة تشغلها ملفات أخرى في حسابك — احذف بعضها من Dropbox. لم يُحذف شيء.',
        );
      }
      var freed = 0;
      for (final b in plan.beforeUpload) {
        onProgress?.call(26, 'إفساح المكان: حذف الأقدم ${b.ref.name}...');
        if (await _deleteFromDropbox(b.ref.path)) freed++;
      }
      if (plan.beforeUpload.isNotEmpty && freed < plan.beforeUpload.length) {
        return BackupResult(
          success: false,
          error: 'تعذّر حذف بعض النسخ القديمة لإفساح المكان — أعد المحاولة.',
          deletedCount: freed,
          freedForSpace: freed,
        );
      }

      // 4. رفع إلى Dropbox
      onProgress?.call(30, 'رفع النسخة إلى Dropbox...');
      await _uploadToDropbox(localBackup, '$_backupFolder/$remoteName');

      // 5. الزائد عن عدد النسخ المحدد (بعد نجاح الرفع فقط)
      onProgress?.call(85, 'تنظيف النسخ القديمة...');
      var deletedCount = freed;
      for (final b in plan.afterUpload) {
        if (await _deleteFromDropbox(b.ref.path)) deletedCount++;
      }

      onProgress?.call(100, 'تم بنجاح!');

      return BackupResult(
        success: true,
        backupName: remoteName,
        backupSize: size,
        deletedCount: deletedCount,
        freedForSpace: freed,
      );
    } on DropboxException catch (e) {
      return BackupResult(success: false, error: e.message);
    } on SocketException catch (e) {
      // ليس دائماً «لا إنترنت»: Dropbox يقطع الاتصال أثناء الرفع حين يرفض الطلب (مثل إذن ناقص)
      return BackupResult(
        success: false,
        error: 'انقطع الاتصال بـ Dropbox أثناء الرفع (${e.message}${e.osError == null ? '' : ' — ${e.osError!.message}'}). '
            'إن كان الإنترنت يعمل فالسبب غالباً إذن ناقص في تطبيق Dropbox: افتح إعدادات Dropbox في البرنامج واضغط «فحص الأذونات».',
      );
    } catch (e) {
      return BackupResult(
        success: false,
        error: 'خطأ غير متوقع: $e',
      );
    } finally {
      // 5. تنظيف الحزمة إن كانت لهذا الاستدعاء وحده (داخل «رفع البيانات» تحذفها الجلسة)
      await ownedPkg?.dispose();
    }
  }

  /// 📋 جلب قائمة النسخ الاحتياطية (الأحدث أولاً). يرمي DropboxException عند الفشل
  /// كي لا تظهر «لا توجد نسخ» بينما المشكلة في الاتصال.
  Future<List<BackupInfo>> listBackups() async {
    final list = await _fetchRemoteBackups();
    list.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return list;
  }

  /// ⬇️ تحميل نسخة احتياطية
  Future<File?> downloadBackup(BackupInfo backup) async {
    try {
      final response = await _authorizedPost(
        '$_apiContentUrl/files/download',
        headers: {'Dropbox-API-Arg': _apiArg({'path': backup.path})},
        timeout: _transferTimeout,
      );

      if (response.statusCode == 200) {
        final tempDir = await Directory.systemTemp.createTemp('download_');
        final file = File(p.join(tempDir.path, backup.name));
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      debugPrint('❌ Dropbox: تحميل مرفوض ${_describe(response)}');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في التحميل: $e');
      return null;
    }
  }

  /// 🔄 استعادة نسخة احتياطية — عبر مسار الاستعادة الموحّد للتطبيق
  /// (إغلاق القاعدة، حذف -wal/-shm، فحص السلامة، تراجع تلقائي عند الفشل،
  /// ووسم الصفوف المستعادة للمزامنة).
  Future<BackupResult> restoreBackup(BackupInfo backup) async {
    if (AppNetworkMode.isClient) {
      return BackupResult(success: false, error: 'هذا الجهاز طرفية — الاستعادة تتم على جهاز الخادم فقط.');
    }
    Directory? workDir;
    File? extracted;
    try {
      final downloadedFile = await downloadBackup(backup);
      if (downloadedFile == null) {
        return BackupResult(success: false, error: 'تعذّر تحميل النسخة من Dropbox.');
      }
      workDir = downloadedFile.parent;

      // القارئ الموحّد: نسخ XZ الجديدة ونسخ ZIP القديمة معاً (يُتعرّف على النوع من المحتوى)
      final File dbFile;
      try {
        dbFile = await BackupFiles.extractDatabase(downloadedFile);
      } catch (e) {
        return BackupResult(success: false, error: 'الملف لا يحتوي قاعدة بيانات صالحة: ${'$e'.replaceFirst('Exception: ', '')}');
      }
      if (dbFile.path != downloadedFile.path) extracted = dbFile;

      final ok = await DatabaseService().restoreDatabaseFromFile(dbFile);
      return ok
          ? BackupResult(success: true, backupName: backup.name)
          : BackupResult(success: false, error: 'فشلت الاستعادة.');
    } catch (e) {
      return BackupResult(success: false, error: 'فشلت الاستعادة: $e');
    } finally {
      try {
        await workDir?.delete(recursive: true);
      } catch (_) {}
      try {
        await extracted?.delete();
      } catch (_) {}
    }
  }

  /// 🗑️ حذف نسخة احتياطية
  Future<bool> deleteBackup(BackupInfo backup) async {
    return await _deleteFromDropbox(backup.path);
  }
}
