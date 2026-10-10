// lib/services/license_v4/device_fingerprint.dart
//
// 🖐️ بصمة الجهاز: عدة قطع من العتاد، كل قطعة تُرسل مجزَّأة (SHA-256) لا
// بقيمتها الحقيقية. السيرفر يعتبر الجهاز نفسه إن تطابقت قطعتان على الأقل،
// فتغيير قطعة واحدة (قرص، تحديث BIOS) لا يُغلق البرنامج، لكن نقله إلى
// حاسوب آخر يغيّرها كلها فيُرفض.
//
// على ويندوز تُقرأ مباشرة من النظام (Win32 API) — بلا PowerShell ولا wmic:
//   mg   = MachineGuid (معرّف تثبيت ويندوز، من السجل)
//   uuid = SMBIOS UUID (اللوحة الأم/النظام)
//   bb   = الرقم التسلسلي للوحة الأم
//   cpu  = ProcessorId
//   bios = الرقم التسلسلي للنظام (SMBIOS)
//   disk = الرقم التسلسلي لقسم C:
// القراءة فورية وثابتة في كل تشغيل، ولا تُطلق أي عملية خارجية (برامج الحماية
// تشتبه بـ PowerShell المخفي). وهي نفس قيم CIM، فالأجهزة المفعّلة سابقاً تبقى معروفة.
//
// كل نسخ البرنامج على الحاسوب نفسه (المثبّتة، نسخة التطوير...) = جهاز واحد.
// للتجربة فقط: ملف alnaser_test_device.txt بجانب البرنامج يجعل تلك النسخة
// «جهازاً آخر» على الحاسوب نفسه (يغيّر البصمة ولا يجعلها تطابق جهازاً آخر).

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

class DeviceFingerprint {
  DeviceFingerprint._();

  static Map<String, String>? _cache;

  /// مصدر القراءة الأخيرة (للتشخيص فقط)
  static String lastSource = '';

  @visibleForTesting
  static Map<String, String> parseSmbios(Uint8List raw) => _WinIds.parseSmbios(raw);

  /// البصمة المجزَّأة {مفتاح: sha256}. فارغة إن تعذّرت القراءة كلياً.
  static Future<Map<String, String>> collect() async {
    if (_cache != null && _cache!.isNotEmpty) return _cache!;
    final v = await _collect();
    if (v.isNotEmpty) _cache = v;
    return v;
  }

  static Future<Map<String, String>> _collect() async {
    final raw = <String, String>{};
    try {
      if (kIsWeb) {
        raw['mg'] = await _persistentRandomId();
        lastSource = 'web';
      } else if (Platform.isWindows) {
        try {
          raw.addAll(_WinIds.read());
          lastSource = 'win32';
        } catch (e) {
          debugPrint('⚠️ [Fingerprint] win32: $e');
        }
        if ((raw['mg'] ?? '').isEmpty) {
          final mg = await _regQuery(r'HKLM\SOFTWARE\Microsoft\Cryptography', 'MachineGuid');
          if (mg != null) {
            raw['mg'] = mg;
            lastSource = '$lastSource+reg';
          }
        }
      } else if (Platform.isLinux) {
        final f = File('/etc/machine-id');
        if (await f.exists()) raw['mg'] = (await f.readAsString()).trim();
        lastSource = 'linux';
      } else {
        raw['mg'] = await _persistentRandomId();
        lastSource = 'random';
      }
    } catch (e) {
      debugPrint('⚠️ [Fingerprint] $e');
    }
    final salt = _testSalt();
    final out = <String, String>{};
    raw.forEach((k, v) {
      final n = _normalize(v);
      if (n != null) out[k] = sha256.convert(utf8.encode('alnaser-fp-v4|$salt|$k|$n')).toString();
    });
    debugPrint('🖐️ [Fingerprint] $lastSource: ${out.keys.join(',')}${salt.isEmpty ? '' : ' (test:$salt)'}');
    return out;
  }

  /// احتياط إن فشلت قراءة السجل مباشرة (reg.exe — أداة ويندوز عادية، لا PowerShell)
  static Future<String?> _regQuery(String key, String value) async {
    try {
      final r = await Process.run('reg', ['query', key, '/v', value]).timeout(const Duration(seconds: 8));
      for (final line in '${r.stdout}'.split('\n')) {
        final i = line.indexOf('REG_SZ');
        if (line.contains(value) && i > 0) return line.substring(i + 6).trim();
      }
    } catch (_) {}
    return null;
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

  /// للتجربة فقط: alnaser_test_device.txt بجانب ملف البرنامج.
  static String _testSalt() {
    if (kIsWeb) return '';
    try {
      final f = File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}alnaser_test_device.txt');
      if (!f.existsSync()) return '';
      final t = f.readAsStringSync().trim();
      if (t.isEmpty) return '';
      return t.length > 40 ? t.substring(0, 40) : t;
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

// ═══════════════════════════════════════════════════════════════════════════
//  قراءة معرّفات العتاد من ويندوز مباشرة
// ═══════════════════════════════════════════════════════════════════════════

typedef _RegGetValueC = Int32 Function(IntPtr hkey, Pointer<Utf16> subKey, Pointer<Utf16> value,
    Uint32 flags, Pointer<Uint32> type, Pointer<Void> data, Pointer<Uint32> cbData);
typedef _RegGetValueD = int Function(int hkey, Pointer<Utf16> subKey, Pointer<Utf16> value, int flags,
    Pointer<Uint32> type, Pointer<Void> data, Pointer<Uint32> cbData);

typedef _GetVolumeInformationC = Int32 Function(Pointer<Utf16> root, Pointer<Utf16> name, Uint32 nameSize,
    Pointer<Uint32> serial, Pointer<Uint32> maxLen, Pointer<Uint32> flags, Pointer<Utf16> fs, Uint32 fsSize);
typedef _GetVolumeInformationD = int Function(Pointer<Utf16> root, Pointer<Utf16> name, int nameSize,
    Pointer<Uint32> serial, Pointer<Uint32> maxLen, Pointer<Uint32> flags, Pointer<Utf16> fs, int fsSize);

typedef _GetSystemFirmwareTableC = Uint32 Function(Uint32 provider, Uint32 id, Pointer<Uint8> buf, Uint32 size);
typedef _GetSystemFirmwareTableD = int Function(int provider, int id, Pointer<Uint8> buf, int size);

class _WinIds {
  static const _hkeyLocalMachine = -2147483646; // 0x80000002 (HKEY، موسَّعة بالإشارة)
  static const _rrfRtRegSz = 0x00000002;
  static const _rrfSubkeyWow6464Key = 0x00010000;
  static const _rsmb = 0x52534D42; // 'RSMB'

  static Map<String, String> read() {
    final out = <String, String>{};
    final advapi = DynamicLibrary.open('advapi32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');

    try {
      final regGetValue = advapi.lookupFunction<_RegGetValueC, _RegGetValueD>('RegGetValueW');
      final mg = _regString(regGetValue, _hkeyLocalMachine, r'SOFTWARE\Microsoft\Cryptography', 'MachineGuid');
      if (mg != null) out['mg'] = mg;
    } catch (e) {
      debugPrint('⚠️ [Fingerprint] mg: $e');
    }

    try {
      final getVol = kernel.lookupFunction<_GetVolumeInformationC, _GetVolumeInformationD>('GetVolumeInformationW');
      final root = r'C:\'.toNativeUtf16();
      final serial = calloc<Uint32>();
      try {
        if (getVol(root, nullptr, 0, serial, nullptr, nullptr, nullptr, 0) != 0) {
          out['disk'] = serial.value.toRadixString(16).toUpperCase().padLeft(8, '0');
        }
      } finally {
        calloc.free(root);
        calloc.free(serial);
      }
    } catch (e) {
      debugPrint('⚠️ [Fingerprint] disk: $e');
    }

    try {
      final getFw = kernel.lookupFunction<_GetSystemFirmwareTableC, _GetSystemFirmwareTableD>('GetSystemFirmwareTable');
      final size = getFw(_rsmb, 0, nullptr, 0);
      if (size > 8) {
        final buf = calloc<Uint8>(size);
        try {
          final got = getFw(_rsmb, 0, buf, size);
          if (got > 8 && got <= size) {
            out.addAll(parseSmbios(Uint8List.fromList(buf.asTypedList(got))));
          }
        } finally {
          calloc.free(buf);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Fingerprint] smbios: $e');
    }
    return out;
  }

  static String? _regString(_RegGetValueD fn, int hkey, String sub, String name) {
    final pSub = sub.toNativeUtf16();
    final pName = name.toNativeUtf16();
    final pcb = calloc<Uint32>();
    try {
      final flags = _rrfRtRegSz | _rrfSubkeyWow6464Key;
      if (fn(hkey, pSub, pName, flags, nullptr, nullptr, pcb) != 0 || pcb.value == 0) return null;
      final buf = calloc<Uint8>(pcb.value + 4);
      try {
        if (fn(hkey, pSub, pName, flags, nullptr, buf.cast(), pcb) != 0) return null;
        final s = buf.cast<Utf16>().toDartString().trim();
        return s.isEmpty ? null : s;
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(pSub);
      calloc.free(pName);
      calloc.free(pcb);
    }
  }

  /// يقرأ جداول SMBIOS الخام (RawSMBIOSData) بنفس صيغة WMI/CIM.
  static Map<String, String> parseSmbios(Uint8List b) {
    final out = <String, String>{};
    final len = b[4] | (b[5] << 8) | (b[6] << 16) | (b[7] << 24);
    final end = min(8 + len, b.length);
    var i = 8;
    String h2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    String h8(int v) => v.toRadixString(16).padLeft(8, '0').toUpperCase();
    while (i + 4 <= end) {
      final type = b[i], slen = b[i + 1];
      if (slen < 4 || i + slen > end) break;
      final f = i;
      // مجموعة النصوص بعد الجزء المنسَّق، تنتهي بصفرين
      var j = i + slen;
      final strings = <String>[];
      if (j + 1 < end && b[j] == 0 && b[j + 1] == 0) {
        j += 2;
      } else {
        while (j < end) {
          final s = j;
          while (j < end && b[j] != 0) {
            j++;
          }
          strings.add(String.fromCharCodes(b.sublist(s, j)).trim());
          j++;
          if (j < end && b[j] == 0) {
            j++;
            break;
          }
        }
      }
      String? str(int off) {
        if (off >= slen) return null;
        final idx = b[f + off];
        if (idx == 0 || idx > strings.length) return null;
        final v = strings[idx - 1];
        return v.isEmpty ? null : v;
      }

      int dw(int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

      if (type == 1) {
        final serial = str(0x07);
        if (serial != null) out['bios'] ??= serial;
        if (slen >= 0x18) {
          final u = b.sublist(f + 8, f + 24);
          out['uuid'] ??= '${h2(u[3])}${h2(u[2])}${h2(u[1])}${h2(u[0])}-${h2(u[5])}${h2(u[4])}-'
              '${h2(u[7])}${h2(u[6])}-${h2(u[8])}${h2(u[9])}-${u.sublist(10).map(h2).join()}';
        }
      } else if (type == 2) {
        final serial = str(0x07);
        if (serial != null) out['bb'] ??= serial;
      } else if (type == 4) {
        if (slen >= 0x10 && !out.containsKey('cpu')) {
          final id = '${h8(dw(f + 12))}${h8(dw(f + 8))}';
          if (id != '0000000000000000') out['cpu'] = id;
        }
      } else if (type == 127) {
        break;
      }
      i = j;
    }
    return out;
  }
}
