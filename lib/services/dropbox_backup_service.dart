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
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lan/lan_settings.dart' show AppNetworkMode;
import 'database_service.dart';
import 'database/core/database_config.dart';

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

  BackupResult({
    required this.success,
    this.error,
    this.backupName,
    this.backupSize,
    this.deletedCount,
  });
}

/// 🔐 حالة الاتصال بـ Dropbox
enum DropboxAuthStatus {
  notConfigured,
  needsAuth,
  authenticated,
  error,
}

/// خطأ من Dropbox برسالة مفهومة.
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

  // 🔑 بيانات التطبيق
  static const String _appKey = 'yklmvnhmfsz65yh';
  static const String _appSecret = 'zxukh96m5s2jd6h';

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

  /// 🔑 الحصول على Access Token
  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _tokenKey);
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
        'client_id': _appKey,
        'client_secret': _appSecret,
      }).timeout(_shortTimeout);
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        final t = data['access_token'] as String?;
        if (t != null && t.isNotEmpty) {
          await saveAccessToken(t);
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

  /// 🔗 إنشاء رابط OAuth للمصادقة
  String getAuthorizationUrl(String redirectUri) {
    return 'https://www.dropbox.com/oauth2/authorize?'
        'client_id=$_appKey&'
        'response_type=code&'
        'redirect_uri=${Uri.encodeComponent(redirectUri)}&'
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
  Future<bool> exchangeCodeForToken(String code, String redirectUri) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'code': extractAuthCode(code),
          'grant_type': 'authorization_code',
          'client_id': _appKey,
          'client_secret': _appSecret,
          'redirect_uri': redirectUri,
        },
      ).timeout(_shortTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await saveAccessToken(data['access_token']);
        if (data['refresh_token'] != null) {
          await saveRefreshToken(data['refresh_token']);
        }
        return true;
      }
      debugPrint('❌ Dropbox: رُفض الكود (${response.statusCode}) ${response.body}');
      return false;
    } catch (e) {
      debugPrint('❌ خطأ في تبديل الكود: $e');
      return false;
    }
  }

  /// 🚪 تسجيل الخروج (مع إبطال الرمز على خادم Dropbox إن أمكن)
  Future<void> logout() async {
    try {
      final t = await getAccessToken();
      if (t != null && t.isNotEmpty) {
        await http
            .post(Uri.parse('$_apiUrl/auth/token/revoke'), headers: {'Authorization': 'Bearer $t'})
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {}
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
  }

  /// 📸 لقطة متّسقة من القاعدة المفتوحة (تشمل ما في ملف -wal).
  Future<Uint8List> _snapshotDatabase(String dbPath) async {
    Directory? tmp;
    try {
      tmp = await Directory.systemTemp.createTemp('dbx_snap_');
      final snapPath = p.join(tmp.path, 'snapshot.db');
      final db = await DatabaseService().database;
      await db.execute("VACUUM INTO '${snapPath.replaceAll("'", "''")}'");
      return await File(snapPath).readAsBytes();
    } catch (e) {
      debugPrint('⚠️ Dropbox: VACUUM INTO تعذّر ($e) — checkpoint ثم نسخ الملف');
      try {
        final db = await DatabaseService().database;
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      return await File(dbPath).readAsBytes();
    } finally {
      try {
        await tmp?.delete(recursive: true);
      } catch (_) {}
    }
  }

  String _stampName(DateTime now) =>
      'backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
      '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.db.zip';

  /// 📦 إنشاء نسخة احتياطية محلية (ملف zip مؤقت)
  Future<File?> _createLocalBackup(String backupName) async {
    try {
      final dbPath = await DatabaseConfig.getDatabasePath();
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        debugPrint('❌ ملف قاعدة البيانات غير موجود');
        return null;
      }

      final dbBytes = await _snapshotDatabase(dbPath);
      final archive = Archive();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));

      final zipBytes = ZipEncoder().encode(archive);
      // ignore: unnecessary_null_comparison
      if (zipBytes == null) return null;

      final tempDir = await Directory.systemTemp.createTemp('backup_');
      final zipFile = File(p.join(tempDir.path, backupName));
      await zipFile.writeAsBytes(zipBytes);

      return zipFile;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النسخة المحلية: $e');
      return null;
    }
  }

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

  static String _describe(http.Response r) {
    String summary = '';
    try {
      summary = (json.decode(utf8.decode(r.bodyBytes))['error_summary'] ?? '').toString();
    } catch (_) {}
    if (summary.contains('insufficient_space')) return 'لا توجد مساحة كافية في حساب Dropbox.';
    if (summary.contains('too_many_write_operations')) return 'Dropbox مشغول الآن — أعد المحاولة بعد قليل.';
    if (r.statusCode == 401) return 'انتهت صلاحية الاتصال بـ Dropbox — سجّل الدخول من جديد.';
    if (r.statusCode == 429) return 'طلبات كثيرة على Dropbox — أعد المحاولة بعد قليل.';
    return 'رفض Dropbox الطلب (${r.statusCode})${summary.isEmpty ? '' : ': $summary'}';
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

  /// نسخة آمنة للتدوير: عند أي خطأ قائمة فارغة (فلا يُحذف شيء).
  Future<List<BackupInfo>> _listRemoteBackups() async {
    try {
      return await _fetchRemoteBackups();
    } catch (e) {
      debugPrint('❌ خطأ في جلب القائمة: $e');
      return [];
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

  /// 🔄 تنفيذ تدوير النسخ (حذف القديمة)
  Future<int> _rotateBackups(int maxBackups) async {
    try {
      final backups = await _listRemoteBackups();

      if (backups.length <= maxBackups) {
        return 0; // لا حاجة للحذف
      }

      // ترتيب من الأقدم للأحدث
      backups.sort((a, b) => a.modifiedTime.compareTo(b.modifiedTime));

      int deletedCount = 0;
      final toDelete = backups.length - maxBackups;

      for (int i = 0; i < toDelete; i++) {
        final success = await _deleteFromDropbox(backups[i].path);
        if (success) {
          deletedCount++;
          debugPrint('🗑️ تم حذف النسخة القديمة: ${backups[i].name}');
        }
      }

      return deletedCount;
    } catch (e) {
      debugPrint('❌ خطأ في تدوير النسخ: $e');
      return 0;
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
    Directory? tempDir;
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

      // 2. إنشاء النسخة المحلية
      onProgress?.call(15, 'إنشاء النسخة الاحتياطية...');
      final remoteName = _stampName(DateTime.now());
      final localBackup = await _createLocalBackup(remoteName);
      if (localBackup == null) {
        return BackupResult(
          success: false,
          error: 'فشل في إنشاء النسخة الاحتياطية المحلية.',
        );
      }
      tempDir = localBackup.parent;
      // ⚠️ الحجم يُقرأ قبل حذف الملف المؤقت (كان يُقرأ بعده فيفشل كل نسخ ناجح).
      final size = await localBackup.length();

      // 3. رفع إلى Dropbox
      onProgress?.call(30, 'رفع النسخة إلى Dropbox...');
      await _uploadToDropbox(localBackup, '$_backupFolder/$remoteName');

      // 4. تدوير النسخ القديمة
      onProgress?.call(80, 'تنظيف النسخ القديمة...');
      final deletedCount = await _rotateBackups(max);

      onProgress?.call(100, 'تم بنجاح!');

      return BackupResult(
        success: true,
        backupName: remoteName,
        backupSize: size,
        deletedCount: deletedCount,
      );
    } on DropboxException catch (e) {
      return BackupResult(success: false, error: e.message);
    } on SocketException {
      return BackupResult(success: false, error: 'لا يوجد اتصال بالإنترنت.');
    } catch (e) {
      return BackupResult(
        success: false,
        error: 'خطأ غير متوقع: $e',
      );
    } finally {
      // 5. تنظيف الملف المؤقت دائماً (نجاحاً أو فشلاً)
      try {
        await tempDir?.delete(recursive: true);
      } catch (_) {}
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
    try {
      final downloadedFile = await downloadBackup(backup);
      if (downloadedFile == null) {
        return BackupResult(success: false, error: 'تعذّر تحميل النسخة من Dropbox.');
      }
      workDir = downloadedFile.parent;

      final archive = ZipDecoder().decodeBytes(await downloadedFile.readAsBytes());
      File? dbFile;
      for (final f in archive) {
        if (f.isFile && f.name.endsWith('.db')) {
          dbFile = File(p.join(workDir.path, 'restored.db'));
          await dbFile.writeAsBytes(f.content as List<int>);
          break;
        }
      }
      if (dbFile == null) {
        return BackupResult(success: false, error: 'الملف لا يحتوي قاعدة بيانات صالحة.');
      }

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
    }
  }

  /// 🗑️ حذف نسخة احتياطية
  Future<bool> deleteBackup(BackupInfo backup) async {
    return await _deleteFromDropbox(backup.path);
  }
}
