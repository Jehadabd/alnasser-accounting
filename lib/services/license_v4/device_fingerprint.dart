// lib/services/license_v4/device_fingerprint.dart
//
// 🖐️ بصمة الجهاز: عدة قطع من العتاد، كل قطعة تُرسل مجزَّأة (SHA-256) لا
// بقيمتها الحقيقية. السيرفر يعتبر الجهاز نفسه إن تطابقت قطعتان على الأقل،
// فتغيير قطعة واحدة (قرص، تحديث BIOS) لا يُغلق البرنامج، لكن نقله إلى
// حاسوب آخر يغيّرها كلها فيُرفض.
//
// على ويندوز (عبر PowerShell/CIM — wmic محذوف من ويندوز 11 الحديث):
//   mg   = MachineGuid (معرّف تثبيت ويندوز)
//   uuid = SMBIOS UUID (اللوحة الأم/النظام)
//   bb   = الرقم التسلسلي للوحة الأم
//   cpu  = ProcessorId
//   bios = الرقم التسلسلي لـ BIOS
//   disk = الرقم التسلسلي لقسم C:
// تُحسب البصمة في كل تشغيل (لا تُخزَّن): نسخ ملفات البرنامج لا ينقلها.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceFingerprint {
  DeviceFingerprint._();

  static Map<String, String>? _cache;
  static Future<Map<String, String>>? _inFlight;

  /// البصمة المجزَّأة {مفتاح: sha256}. فارغة إن تعذّرت القراءة كلياً.
  static Future<Map<String, String>> collect() {
    if (_cache != null) return Future.value(_cache);
    return _inFlight ??= _collect().then((v) {
      _cache = v;
      _inFlight = null;
      return v;
    });
  }

  static Future<Map<String, String>> _collect() async {
    final raw = <String, String>{};
    try {
      if (kIsWeb) {
        raw['mg'] = await _persistentRandomId();
      } else if (Platform.isWindows) {
        raw.addAll(await _windowsPowerShell());
        if ((raw['mg'] ?? '').isEmpty || (raw['uuid'] ?? '').isEmpty) {
          final reg = await _windowsRegistry();
          reg.forEach((k, v) {
            if ((raw[k] ?? '').isEmpty) raw[k] = v;
          });
        }
      } else if (Platform.isLinux) {
        final f = File('/etc/machine-id');
        if (await f.exists()) raw['mg'] = (await f.readAsString()).trim();
      } else {
        raw['mg'] = await _persistentRandomId();
      }
    } catch (e) {
      debugPrint('⚠️ [Fingerprint] $e');
    }
    final salt = await _testSalt();
    final out = <String, String>{};
    raw.forEach((k, v) {
      final n = _normalize(v);
      if (n != null) out[k] = sha256.convert(utf8.encode('alnaser-fp-v4|$salt|$k|$n')).toString();
    });
    return out;
  }

  static const _psScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
$o = [ordered]@{}
$o.mg   = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
$o.uuid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$o.bb   = (Get-CimInstance Win32_BaseBoard).SerialNumber
$o.cpu  = (Get-CimInstance Win32_Processor | Select-Object -First 1).ProcessorId
$o.bios = (Get-CimInstance Win32_BIOS).SerialNumber
$o.disk = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").VolumeSerialNumber
$o | ConvertTo-Json -Compress
''';

  static Future<Map<String, String>> _windowsPowerShell() async {
    // -EncodedCommand (UTF-16LE base64): بلا مشاكل علامات التنصيص
    final units = _psScript.codeUnits;
    final bytes = <int>[];
    for (final u in units) {
      bytes..add(u & 0xff)..add(u >> 8);
    }
    try {
      final r = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden', '-EncodedCommand', base64.encode(bytes),
      ]).timeout(const Duration(seconds: 20));
      final text = '${r.stdout}'.trim();
      final start = text.indexOf('{');
      if (start < 0) return {};
      final m = jsonDecode(text.substring(start));
      if (m is! Map) return {};
      return m.map((k, v) => MapEntry('$k', v == null ? '' : '$v'));
    } catch (e) {
      debugPrint('⚠️ [Fingerprint] PowerShell: $e');
      return {};
    }
  }

  static Future<Map<String, String>> _windowsRegistry() async {
    final out = <String, String>{};
    Future<String?> q(String key, String value) async {
      try {
        final r = await Process.run('reg', ['query', key, '/v', value]).timeout(const Duration(seconds: 8));
        for (final line in '${r.stdout}'.split('\n')) {
          final i = line.indexOf('REG_SZ');
          if (line.contains(value) && i > 0) return line.substring(i + 6).trim();
        }
      } catch (_) {}
      return null;
    }

    final mg = await q(r'HKLM\SOFTWARE\Microsoft\Cryptography', 'MachineGuid');
    if (mg != null) out['mg'] = mg;
    final uuid = await q(r'HKLM\SYSTEM\HardwareConfig', 'LastConfig');
    if (uuid != null) out['uuid'] = uuid.replaceAll(RegExp(r'[{}]'), '');
    return out;
  }

  static String? _normalize(String? v) {
    if (v == null) return null;
    final s = v.trim().toUpperCase();
    final compact = s.replaceAll(RegExp(r'[\s\-_.]'), '');
    if (compact.length < 4) return null;
    const junk = {
      'NONE', 'NULL', 'TOBEFILLEDBYOEM', 'DEFAULTSTRING', 'SYSTEMSERIALNUMBER',
      'NOTAPPLICABLE', 'NOTSPECIFIED', 'NA', 'OEM', 'INVALID', 'UNKNOWN', '0123456789',
      'BASEBOARDSERIALNUMBER', 'CHASSISSERIALNUMBER',
    };
    if (junk.contains(compact)) return null;
    if (RegExp(r'^0+$').hasMatch(compact) || RegExp(r'^F+$').hasMatch(compact)) return null;
    return s;
  }

  /// نسخ الاختبار (اسم منتج غير debt_book) تأخذ بصمة مختلفة عن النسخة الأصلية
  /// على الحاسوب نفسه. لا يفيد التزوير: يغيّر البصمة ولا يجعلها تطابق جهازاً آخر.
  static Future<String> _testSalt() async {
    if (kIsWeb) return '';
    try {
      final dir = await getApplicationSupportDirectory();
      final name = dir.path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;
      return name == 'debt_book' ? '' : name;
    } catch (_) {
      return '';
    }
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

  /// اسم الجهاز كما يظهر في قائمة الأجهزة
  static String deviceName() {
    if (kIsWeb) return 'متصفح';
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'جهاز';
    }
  }
}
