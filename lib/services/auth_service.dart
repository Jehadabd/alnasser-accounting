// services/auth_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import 'database_service.dart';
import 'password_service.dart';
import '../erp/activity/activity_log.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final DatabaseService _db = DatabaseService();
  final PasswordService _passwordService = PasswordService();
  
  AppUser? _currentUser;
  static const String _sessionKey = 'current_user_session';

  /// المستخدم الحالي المسجل دخوله
  AppUser? get currentUser => _currentUser;
  
  /// هل المستخدم مسجل دخوله؟
  bool get isLoggedIn => _currentUser != null;

  /// هل المستخدم الحالي Admin؟
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  /// تشفير كلمة السر باستخدام SHA256
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// تهيئة الجلسة من SharedPreferences
  Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionJson = prefs.getString(_sessionKey);
    
    if (sessionJson != null) {
      try {
        final Map<String, dynamic> sessionData = jsonDecode(sessionJson);
        final userId = sessionData['user_id'];
        
        if (userId != null) {
          _currentUser = await _getUserById(userId);
        }
      } catch (e) {
        // Session corrupted, clear it
        await prefs.remove(_sessionKey);
      }
    }
  }

  /// حفظ الجلسة
  Future<void> _saveSession(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode({
      'user_id': user.id,
      'username': user.username,
    }));
  }

  /// مسح الجلسة
  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// هل يوجد أي مستخدمين في النظام؟
  Future<bool> hasAnyUsers() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    final count = result.first['count'] as int;
    return count > 0;
  }

  /// تسجيل الدخول
  Future<AppUser?> login(String username, String password) async {
    final db = await _db.database;
    final passwordHash = _hashPassword(password);
    
    final result = await db.query(
      'users',
      where: 'username = ? AND password_hash = ?',
      whereArgs: [username, passwordHash],
    );
    
    if (result.isEmpty) return null;
    
    final permissions = await _getUserPermissions(result.first['id'] as int);
    _currentUser = AppUser.fromMap(result.first, permissions: permissions);
    await _saveSession(_currentUser!);
    ActivityLog.log('دخول', 'تسجيل الدخول', 'دخول المستخدم ${_currentUser!.username}');
    
    return _currentUser;
  }

  /// تسجيل الخروج
  Future<void> logout() async {
    if (_currentUser != null) await ActivityLog.log('خروج', 'تسجيل الدخول', 'خروج المستخدم ${_currentUser!.username}');
    _currentUser = null;
    await _clearSession();
  }

  /// إنشاء مستخدم Admin
  Future<AppUser?> createAdmin(String username, String password) async {
    return await _createUser(username, password, 'admin', AppPermissions.allKeys);
  }

  /// إنشاء محاسب
  Future<AppUser?> createAccountant(String username, String password, List<String> permissions) async {
    return await _createUser(username, password, 'accountant', permissions);
  }

  /// إنشاء مستخدم
  Future<AppUser?> _createUser(String username, String password, String role, List<String> permissions) async {
    final db = await _db.database;
    final passwordHash = _hashPassword(password);
    
    try {
      final userId = await db.insert('users', {
        'username': username,
        'password_hash': passwordHash,
        'role': role,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      // إضافة الصلاحيات
      for (final perm in permissions) {
        await db.insert('user_permissions', {
          'user_id': userId,
          'permission_key': perm,
        });
      }
      
      return await _getUserById(userId);
    } catch (e) {
      return null; // Username already exists or other error
    }
  }

  /// التحقق من كلمة سر الاسترداد (كلمات السر الثلاثة أو الجوكر)
  Future<bool> verifyRecoveryPassword(String password) async {
    // التحقق من كلمة الجوكر أولاً
    if (await _passwordService.verifyPassword(password)) {
      return true;
    }
    // يمكن إضافة منطق إضافي للكلمات الثلاثة هنا
    return false;
  }

  /// إعادة تعيين كلمة السر
  Future<bool> resetPassword(String username, String newPassword) async {
    final db = await _db.database;
    final passwordHash = _hashPassword(newPassword);
    
    final count = await db.update(
      'users',
      {'password_hash': passwordHash},
      where: 'username = ?',
      whereArgs: [username],
    );
    
    return count > 0;
  }

  /// جلب مستخدم بالـ ID
  Future<AppUser?> _getUserById(int userId) async {
    final db = await _db.database;
    final result = await db.query('users', where: 'id = ?', whereArgs: [userId]);
    
    if (result.isEmpty) return null;
    
    final permissions = await _getUserPermissions(userId);
    return AppUser.fromMap(result.first, permissions: permissions);
  }

  /// جلب صلاحيات المستخدم
  Future<List<String>> _getUserPermissions(int userId) async {
    final db = await _db.database;
    final result = await db.query(
      'user_permissions',
      columns: ['permission_key'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    
    return result.map((row) => row['permission_key'] as String).toList();
  }

  /// جلب جميع المحاسبين
  Future<List<AppUser>> getAllAccountants() async {
    final db = await _db.database;
    final result = await db.query('users', where: 'role = ?', whereArgs: ['accountant']);
    
    List<AppUser> users = [];
    for (final row in result) {
      final permissions = await _getUserPermissions(row['id'] as int);
      users.add(AppUser.fromMap(row, permissions: permissions));
    }
    
    return users;
  }

  /// حذف مستخدم
  Future<bool> deleteUser(int userId) async {
    final db = await _db.database;
    final count = await db.delete('users', where: 'id = ?', whereArgs: [userId]);
    return count > 0;
  }

  /// تحديث صلاحيات المستخدم
  Future<void> updateUserPermissions(int userId, List<String> permissions) async {
    final db = await _db.database;
    
    // حذف الصلاحيات القديمة
    await db.delete('user_permissions', where: 'user_id = ?', whereArgs: [userId]);
    
    // إضافة الصلاحيات الجديدة
    for (final perm in permissions) {
      await db.insert('user_permissions', {
        'user_id': userId,
        'permission_key': perm,
      });
    }
  }

  /// فحص صلاحية معينة للمستخدم الحالي
  bool hasPermission(String permissionKey) {
    if (_currentUser == null) return true; // No users = full access
    return _currentUser!.hasPermission(permissionKey);
  }
}
