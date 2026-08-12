import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert'; // For utf8.encode

class PasswordService {
  static final PasswordService _instance = PasswordService._internal();
  final _storage = const FlutterSecureStorage();
  static const String _passwordsKey = 'app_passwords';
  static const String _isFirstLaunchKey = 'is_first_launch';
  static const String _jokerPassword = '2001'; // Joker password

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

  // Verify a given password
  Future<bool> verifyPassword(String password) async {
    // Check against joker password first
    if (password == _jokerPassword) {
      return true;
    }

    final storedJson = await _storage.read(key: _passwordsKey);
    if (storedJson == null) {
      return false; // No passwords set yet
    }
    final List<dynamic> hashedPasswords = jsonDecode(storedJson);
    final hashedPassword = _hashPassword(password);
    return hashedPasswords.contains(hashedPassword);
  }

  // Check if passwords are set (for app initialization logic)
  Future<bool> arePasswordsSet() async {
    final storedJson = await _storage.read(key: _passwordsKey);
    return storedJson != null;
  }
} 