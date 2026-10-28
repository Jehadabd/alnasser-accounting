// نسخة الويب من DeviceFingerprint — نفس سلوك فرع kIsWeb في device_fingerprint_io.dart حرفياً.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class DeviceFingerprint {
  DeviceFingerprint._();

  static Map<String, String>? _cache;
  static String lastSource = '';

  @visibleForTesting
  static Map<String, String> parseSmbios(Uint8List raw) => const {};

  static Future<Map<String, String>> collect() async {
    if (_cache != null && _cache!.isNotEmpty) return _cache!;
    final out = <String, String>{};
    try {
      final id = await _persistentRandomId();
      final n = id.trim().toUpperCase();
      out['mg'] = sha256.convert(utf8.encode('alnaser-fp-v4||mg|$n')).toString();
      lastSource = 'web';
    } catch (e) {
      debugPrint('⚠️ [Fingerprint] $e');
    }
    if (out.isNotEmpty) _cache = out;
    return out;
  }

  static Future<String> _persistentRandomId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('alnaser_device_random_id');
    if (id == null || id.length < 16) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString('alnaser_device_random_id', id);
    }
    return id;
  }

  static String deviceName() => 'متصفح';
}
