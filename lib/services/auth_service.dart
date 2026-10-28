// services/auth_service.dart
import 'dart:convert';
import 'dart:math' show Random;
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import 'database_service.dart';
import 'firebase_sync/users_sync_service.dart';
import '../erp/activity/activity_log.dart';
import 'seat_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final DatabaseService _db = DatabaseService();
  
  AppUser? _currentUser;
  // 🖥️ لكل شاشة جلستها (شاشة ثانية على نفس الحاسبة = محاسب آخر)
  static String get _sessionKey => SeatService.key('current_user_session');

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

  /// (تبقى الدالة للتوافق؛ الدخول التلقائي في restoreSavedLogin)
  Future<void> initSession() async {}

  // ───────────── البقاء مسجلاً للدخول (حتى يخرج المستخدم بنفسه) ─────────────
  // إعداد لكل جهاز (مفعّل افتراضياً). يُحفظ «دخول» المستخدم في المخزن الآمن
  // لهذا الجهاز (مشفّر بحساب ويندوز / Keystore في أندرويد)، موقَّعاً بسرّ
  // عشوائي خاص بالجهاز وببصمة كلمة سر المستخدم: إن غُيّرت كلمة سره، أو حُذف،
  // أو ضُغط «تبديل المستخدم» ⇒ تُطلب كلمة السر من جديد.
  static const String _kStay = 'stay_logged_in';
  static String get _kSaved => SeatService.key('alnaser_saved_login');
  static const String _kDevSecret = 'alnaser_login_device_secret';
  static const _secure = FlutterSecureStorage();

  /// هل يبقى هذا الجهاز مسجلاً للدخول؟ (افتراضياً نعم)
  Future<bool> stayLoggedIn() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_kStay) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setStayLoggedIn(bool v) async {
    await (await SharedPreferences.getInstance()).setBool(_kStay, v);
    if (!v) {
      await _forgetSavedLogin();
    } else if (_currentUser != null) {
      await _rememberLogin(_currentUser!);
    }
  }

  Future<String> _deviceSecret() async {
    var s = await _secure.read(key: _kDevSecret);
    if (s == null || s.length < 32) {
      final r = Random.secure();
      s = List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _secure.write(key: _kDevSecret, value: s);
    }
    return s;
  }

  static String _loginSig(int id, String username, String passwordHash, String secret) =>
      sha256.convert(utf8.encode('$id|$username|$passwordHash|$secret')).toString();

  Future<void> _rememberLogin(AppUser u) async {
    if (u.id == null) return;
    try {
      final secret = await _deviceSecret();
      await _secure.write(
          key: _kSaved,
          value: jsonEncode({'id': u.id, 'u': u.username, 's': _loginSig(u.id!, u.username, u.passwordHash, secret)}));
    } catch (_) {}
  }

  Future<void> _forgetSavedLogin() async {
    try {
      await _secure.delete(key: _kSaved);
    } catch (_) {}
  }

  /// 🔓 يُدخل آخر مستخدم تلقائياً (إن كان الإعداد مفعّلاً ولم يخرج بنفسه).
  Future<AppUser?> restoreSavedLogin() async {
    if (_currentUser != null) return _currentUser;
    if (!await stayLoggedIn()) return null;
    try {
      final raw = await _secure.read(key: _kSaved);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final id = (m['id'] as num?)?.toInt();
      if (id == null) return null;
      final db = await _db.database;
      final r = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) {
        await _forgetSavedLogin();
        return null;
      }
      final row = r.first;
      final username = '${row['username']}';
      final hash = '${row['password_hash']}';
      final secret = await _deviceSecret();
      if (m['u'] != username || m['s'] != _loginSig(id, username, hash, secret)) {
        await _forgetSavedLogin(); // غُيّرت كلمة السر أو الاسم ⇒ دخول من جديد
        return null;
      }
      _currentUser = AppUser.fromMap(row, permissions: await _getUserPermissions(id));
      await _touchLastLogin(id);
      ActivityLog.log('دخول', 'تسجيل الدخول', 'دخول تلقائي (البقاء مسجلاً): ${_currentUser!.username}');
      return _currentUser;
    } catch (_) {
      return null;
    }
  }

  /// آخر اسم مستخدم دخل من هذا الجهاز (لملء حقل الدخول فقط — ليس جلسة).
  Future<String?> lastUsername() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionJson = prefs.getString(_sessionKey);
      if (sessionJson == null) return null;
      final data = jsonDecode(sessionJson);
      return data is Map ? data['username'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// 🧪 الوضع التجريبي: قاعدته منفصلة وبلا مستخدمين ⇒ دخول مؤقت بصلاحيات المدير
  /// في الذاكرة فقط (لا يُكتب شيء في جدول المستخدمين).
  void loginDemo() {
    _currentUser = AppUser(
      id: null,
      username: 'تجريبي',
      passwordHash: '',
      role: 'admin',
      createdAt: DateTime.now(),
      permissions: AppPermissions.allKeys,
    );
  }

  /// حساب المدير (أول مستخدم بدور admin) إن وُجد — منفصل عن حساب الترخيص.
  Future<AppUser?> adminUser() async {
    final db = await _db.database;
    final r = await db.query('users', where: "role = 'admin'", orderBy: 'id', limit: 1);
    if (r.isEmpty) return null;
    return AppUser.fromMap(r.first, permissions: AppPermissions.allKeys);
  }

  /// كل المستخدمين: المدير أولاً ثم الموظفون.
  Future<List<AppUser>> getAllUsers() async {
    final db = await _db.database;
    final rows = await db.query('users', orderBy: "CASE WHEN role = 'admin' THEN 0 ELSE 1 END, username");
    final out = <AppUser>[];
    for (final row in rows) {
      out.add(AppUser.fromMap(row, permissions: await _getUserPermissions(row['id'] as int)));
    }
    return out;
  }

  /// تغيير كلمة سر مستخدم (المدير للموظفين، أو المستخدم لنفسه).
  Future<bool> setPassword(int userId, String newPassword) async {
    final db = await _db.database;
    final n = await db.update('users', {'password_hash': _hashPassword(newPassword)},
        where: 'id = ?', whereArgs: [userId]);
    if (n > 0) await UsersSyncService.instance.markChanged(userId);
    return n > 0;
  }

  /// هل كلمة السر هذه صحيحة لهذا المستخدم؟ (لتأكيد العمليات الحساسة)
  Future<bool> checkPassword(int userId, String password) async {
    final db = await _db.database;
    final r = await db.query('users',
        columns: ['id'], where: 'id = ? AND password_hash = ?', whereArgs: [userId, _hashPassword(password)]);
    return r.isNotEmpty;
  }

  /// حفظ الجلسة
  Future<void> _saveSession(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode({
      'user_id': user.id,
      'username': user.username,
    }));
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
    await _touchLastLogin(_currentUser!.id);
    await _saveSession(_currentUser!);
    if (await stayLoggedIn()) await _rememberLogin(_currentUser!);
    ActivityLog.log('دخول', 'تسجيل الدخول', 'دخول المستخدم ${_currentUser!.username}');
    
    return _currentUser;
  }

  Future<void> _touchLastLogin(int? userId) async {
    if (userId == null) return;
    try {
      final db = await _db.database;
      await db.update('users', {'last_login_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [userId]);
    } catch (_) {} // عمود اختياري (يضيفه SchemaHealer/ErpSchema)
  }

  /// تسجيل الخروج (يبقى اسم آخر مستخدم لملء حقل الدخول)
  Future<void> logout() async {
    if (_currentUser != null && _currentUser!.id != null) {
      await ActivityLog.log('خروج', 'تسجيل الدخول', 'خروج المستخدم ${_currentUser!.username}');
    }
    _currentUser = null;
    await _forgetSavedLogin(); // خرج بنفسه ⇒ كلمة السر في الفتح القادم
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
      
      await UsersSyncService.instance.markChanged(userId); // 👥 يظهر في بقية الأجهزة
      return await _getUserById(userId);
    } catch (e) {
      return null; // Username already exists or other error
    }
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
    if (count > 0) {
      final r = await db.query('users', columns: ['id'], where: 'username = ?', whereArgs: [username], limit: 1);
      if (r.isNotEmpty) await UsersSyncService.instance.markChanged(r.first['id'] as int);
    }
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
    final target = await db.query('users', columns: ['role'], where: 'id = ?', whereArgs: [userId], limit: 1);
    if (target.isNotEmpty && target.first['role'] != 'admin') {
      await UsersSyncService.instance.markDeleted(userId); // 👥 يُحذف من بقية الأجهزة
    }
    // حساب المدير لا يُحذف
    final count = await db.delete('users', where: "id = ? AND role != 'admin'", whereArgs: [userId]);
    if (count > 0) await db.delete('user_permissions', where: 'user_id = ?', whereArgs: [userId]);
    return count > 0;
  }

  /// تغيير اسم الدخول. يفيد خاصةً مديراً أُنشئ قديماً باسم حساب الترخيص.
  /// العمليات السابقة تبقى مسجّلة بالاسم القديم. يعيد false إن كان الاسم مستعملاً.
  Future<bool> renameUser(int userId, String newUsername) async {
    final name = newUsername.trim();
    if (name.isEmpty) return false;
    final db = await _db.database;
    final taken = await db.query('users',
        columns: ['id'], where: 'username = ? AND id != ?', whereArgs: [name, userId], limit: 1);
    if (taken.isNotEmpty) return false;
    try {
      final n = await db.update('users', {'username': name}, where: 'id = ?', whereArgs: [userId]);
      if (n == 0) return false;
      await UsersSyncService.instance.markChanged(userId);
      if (_currentUser?.id == userId) {
        _currentUser = await _getUserById(userId);
        if (_currentUser != null) await _saveSession(_currentUser!);
      }
      ActivityLog.log('تعديل', 'المستخدمون', 'تغيير اسم دخول المستخدم #$userId إلى $name');
      return true;
    } catch (_) {
      return false;
    }
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
    await UsersSyncService.instance.markChanged(userId);
  }

  /// فحص صلاحية معينة للمستخدم الحالي.
  /// 🔐 بلا مستخدم مسجّل = لا صلاحيات (الدخول إلزامي قبل أي شاشة).
  bool hasPermission(String permissionKey) {
    if (_currentUser == null) return false;
    return _currentUser!.hasPermission(permissionKey);
  }
}
