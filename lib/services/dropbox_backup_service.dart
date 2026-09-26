// lib/services/dropbox_backup_service.dart
// 🔥 خدمة النسخ الاحتياطي إلى Dropbox مع تدوير النسخ الذكي

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
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
          ? DateTime.parse(json['server_modified'])
          : DateTime.now(),
      size: json['size'] ?? 0,
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
  
  // 🔐 تخزين آمن للتوكن
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _tokenKey = 'dropbox_access_token';
  static const String _refreshTokenKey = 'dropbox_refresh_token';
  
  // 🌐 API Endpoints
  static const String _apiContentUrl = 'https://content.dropboxapi.com/2';
  static const String _apiUrl = 'https://api.dropboxapi.com/2';

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

  /// 🔌 التحقق من حالة الاتصال
  Future<DropboxAuthStatus> checkAuthStatus() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) {
        return DropboxAuthStatus.notConfigured;
      }
      
      // التحقق من صلاحية التوكن
      final isValid = await _validateToken(token);
      if (isValid) {
        return DropboxAuthStatus.authenticated;
      } else {
        return DropboxAuthStatus.needsAuth;
      }
    } catch (e) {
      return DropboxAuthStatus.error;
    }
  }

  /// ✅ التحقق من صلاحية التوكن
  Future<bool> _validateToken(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiUrl/users/get_current_account'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
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

  /// 🔐 تبويل Authorization Code بـ Access Token
  Future<bool> exchangeCodeForToken(String code, String redirectUri) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.dropboxapi.com/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'code': code,
          'grant_type': 'authorization_code',
          'client_id': _appKey,
          'client_secret': _appSecret,
          'redirect_uri': redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await saveAccessToken(data['access_token']);
        if (data['refresh_token'] != null) {
          await saveRefreshToken(data['refresh_token']);
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ خطأ في تبديل الكود: $e');
      return false;
    }
  }

  /// 🚪 تسجيل الخروج
  Future<void> logout() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
  }

  /// 📦 إنشاء نسخة احتياطية محلية
  Future<File?> _createLocalBackup() async {
    try {
      final dbPath = await DatabaseConfig.getDatabasePath();
      final dbFile = File(dbPath);
      
      if (!await dbFile.exists()) {
        debugPrint('❌ ملف قاعدة البيانات غير موجود');
        return null;
      }

      // إنشاء اسم الملف مع التاريخ
      final now = DateTime.now();
      final backupName = 'backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.db.zip';
      
      // ضغط الملف
      final dbBytes = await dbFile.readAsBytes();
      final archive = Archive();
      archive.addFile(ArchiveFile('database.db', dbBytes.length, dbBytes));
      
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) return null;

      // حفظ مؤقتاً
      final tempDir = await Directory.systemTemp.createTemp('backup_');
      final zipFile = File(p.join(tempDir.path, backupName));
      await zipFile.writeAsBytes(zipBytes);
      
      return zipFile;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النسخة المحلية: $e');
      return null;
    }
  }

  /// ☁️ رفع النسخة إلى Dropbox
  Future<bool> _uploadToDropbox(File file, String remotePath) async {
    try {
      final token = await getAccessToken();
      if (token == null) return false;

      final fileBytes = await file.readAsBytes();
      
      final response = await http.post(
        Uri.parse('$_apiContentUrl/files/upload'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': json.encode({
            'path': remotePath,
            'mode': 'add',
            'autorename': true,
            'mute': false,
          }),
        },
        body: fileBytes,
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ خطأ في الرفع: $e');
      return false;
    }
  }

  /// 📋 جلب قائمة النسخ من Dropbox
  Future<List<BackupInfo>> _listRemoteBackups() async {
    try {
      final token = await getAccessToken();
      if (token == null) return [];

      final response = await http.post(
        Uri.parse('$_apiUrl/files/list_folder'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'path': _backupFolder,
          'recursive': false,
          'include_deleted': false,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final entries = data['entries'] as List;
        
        return entries
            .where((e) => e['.tag'] == 'file' && e['name'].toString().startsWith('backup_'))
            .map((e) => BackupInfo.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب القائمة: $e');
      return [];
    }
  }

  /// 🗑️ حذف ملف من Dropbox
  Future<bool> _deleteFromDropbox(String path) async {
    try {
      final token = await getAccessToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('$_apiUrl/files/delete_v2'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
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

  /// 🚀 إنشاء ورفع نسخة احتياطية مع تدوير تلقائي
  Future<BackupResult> createAndUploadBackup({
    int? maxBackups,
    Function(int progress, String status)? onProgress,
  }) async {
    try {
      final max = maxBackups ?? _defaultMaxBackups;
      
      // 1. التحقق من الاتصال
      onProgress?.call(5, 'التحقق من الاتصال بـ Dropbox...');
      final authStatus = await checkAuthStatus();
      if (authStatus != DropboxAuthStatus.authenticated) {
        return BackupResult(
          success: false,
          error: 'لم يتم الاتصال بـ Dropbox. يرجى تسجيل الدخول أولاً.',
        );
      }

      // 2. إنشاء النسخة المحلية
      onProgress?.call(15, 'إنشاء النسخة الاحتياطية...');
      final localBackup = await _createLocalBackup();
      if (localBackup == null) {
        return BackupResult(
          success: false,
          error: 'فشل في إنشاء النسخة الاحتياطية المحلية.',
        );
      }

      // 3. رفع إلى Dropbox
      onProgress?.call(30, 'رفع النسخة إلى Dropbox...');
      final now = DateTime.now();
      final remoteName = 'backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}.db.zip';
      final remotePath = '$_backupFolder/$remoteName';
      
      final uploaded = await _uploadToDropbox(localBackup, remotePath);
      if (!uploaded) {
        await localBackup.parent.delete(recursive: true);
        return BackupResult(
          success: false,
          error: 'فشل في رفع النسخة إلى Dropbox.',
        );
      }

      // 4. تنظيف الملف المحلي المؤقت
      await localBackup.parent.delete(recursive: true);

      // 5. تدوير النسخ القديمة
      onProgress?.call(80, 'تنظيف النسخ القديمة...');
      final deletedCount = await _rotateBackups(max);

      onProgress?.call(100, 'تم بنجاح!');

      return BackupResult(
        success: true,
        backupName: remoteName,
        backupSize: await localBackup.length(),
        deletedCount: deletedCount,
      );
    } catch (e) {
      return BackupResult(
        success: false,
        error: 'خطأ غير متوقع: $e',
      );
    }
  }

  /// 📋 جلب قائمة النسخ الاحتياطية
  Future<List<BackupInfo>> listBackups() async {
    return await _listRemoteBackups();
  }

  /// ⬇️ تحميل نسخة احتياطية
  Future<File?> downloadBackup(BackupInfo backup) async {
    try {
      final token = await getAccessToken();
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('$_apiContentUrl/files/download'),
        headers: {
          'Authorization': 'Bearer $token',
          'Dropbox-API-Arg': json.encode({'path': backup.path}),
        },
      );

      if (response.statusCode == 200) {
        final tempDir = await Directory.systemTemp.createTemp('download_');
        final file = File(p.join(tempDir.path, backup.name));
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في التحميل: $e');
      return null;
    }
  }

  /// 🔄 استعادة نسخة احتياطية
  Future<bool> restoreBackup(BackupInfo backup) async {
    try {
      // تحميل النسخة
      final downloadedFile = await downloadBackup(backup);
      if (downloadedFile == null) return false;

      // فك الضغط
      final zipBytes = await downloadedFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      
      File? dbFile;
      for (final file in archive) {
        if (file.name.endsWith('.db')) {
          dbFile = File('${downloadedFile.parent.path}/restored.db');
          await dbFile.writeAsBytes(file.content as List<int>);
          break;
        }
      }

      if (dbFile == null) return false;

      // استبدال قاعدة البيانات الحالية
      final currentDbPath = await DatabaseConfig.getDatabasePath();
      final currentDb = File(currentDbPath);
      
      // نسخ احتياطي للقاعدة الحالية
      final backupPath = '$currentDbPath.before_restore';
      await currentDb.copy(backupPath);
      
      // استبدال
      await currentDb.delete();
      await dbFile.copy(currentDbPath);

      // 🛡️ وضع الاستعادة للمزامنة: لا رفع من نسخة قديمة قبل مقارنتها بالسحابة
      await DatabaseService.flagDatabaseRestored();

      return true;
    } catch (e) {
      debugPrint('❌ خطأ في الاستعادة: $e');
      return false;
    }
  }

  /// 🗑️ حذف نسخة احتياطية
  Future<bool> deleteBackup(BackupInfo backup) async {
    return await _deleteFromDropbox(backup.path);
  }
}
