import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert'; // For utf8.encode
import 'database_service.dart';

class PasswordService {
  static final PasswordService _instance = PasswordService._internal();
  final _storage = const FlutterSecureStorage();
  static const String _passwordsKey = 'app_passwords';
  static const String _isFirstLaunchKey = 'is_first_launch';

  factory PasswordService() => _instance;

  PasswordService._internal();

  // Helper to hash passwords
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Check if it's the first launch
  Future<bool> isFirstLaunch() async {
    final storedValue = await _storage.read(key: _isFirstLaunchKey);
    return storedValue == null; // If null, it's the first launch
  }

  // Set first launch to false after setup
  Future<void> setFirstLaunchCompleted() async {
    await _storage.write(key: _isFirstLaunchKey, value: 'false');
  }

  // Save 3 passwords
  Future<void> savePasswords(List<String> passwords) async {
    if (passwords.length != 3) {
      throw ArgumentError('Exactly 3 passwords are required.');
    }
    final hashedPasswords = passwords.map((p) => _hashPassword(p)).toList();
    final jsonString = jsonEncode(hashedPasswords);
    await _storage.write(key: _passwordsKey, value: jsonString);
  }

  // 🔐 كلمة السر لهذه الأقفال = كلمة سر أحد المديرين داخل البرنامج.
  //    أُلغيت كلمة «الجوكر» الثابتة: كانت تفتح كل الأقفال لكل من يعرفها.
  Future<bool> verifyPassword(String password) async {
    if (password.isEmpty) return false;
    try {
      final db = await DatabaseService().database;
      final r = await db.query('users',
          columns: ['id'],
          where: "role = 'admin' AND password_hash = ?",
          whereArgs: [_hashPassword(password)],
          limit: 1);
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Check if passwords are set (for app initialization logic)
  Future<bool> arePasswordsSet() async {
    final storedJson = await _storage.read(key: _passwordsKey);
    return storedJson != null;
  }
} 