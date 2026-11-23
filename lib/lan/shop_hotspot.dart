// lib/lan/shop_hotspot.dart
//
// 📶 «شبكة المتجر» — بلا راوتر: جهاز السيرفر يبث شبكة Wi-Fi، والطرفيات تنضم إليها،
// فيصبحون على شبكة واحدة ويعمل الربط كما هو (لا تغيير في بروتوكول LAN).
//
//   • Windows: «نقطة الاتصال المحمولة» يشغّلها التطبيق بنفسه (WinRT عبر PowerShell،
//     بلا صلاحيات مدير) باسم وكلمة سر ثابتين يحفظهما. عنوان الحاسوب عليها 192.168.137.1.
//     يحتاج بطاقة Wi-Fi، وأن يكون الحاسوب متصلاً بأي شبكة يشاركها (قيد من Windows).
//   • Android: لا يسمح Android لتطبيق بتشغيل نقطة اتصال النظام، فهناك طريقتان:
//       - «شبكة التطبيق» (LocalOnlyHotspot): ضغطة واحدة، اسم وكلمة سر عشوائيان كل تشغيل،
//         وتبقى ما دام التطبيق يعمل.
//       - «نقطة اتصال النظام»: يفتح إعداداتها؛ تكتب اسمها وكلمة سرها مرة فيُحفظان هنا.
//   • الطرفية: تمسح رمز QR من شاشة السيرفر ⇒ عنوان السيرفر والمنفذ ورمز الربط تُكتب
//     وحدها، وتنضم لشبكة المتجر (Android 10+ بنافذة موافقة من النظام؛ Windows بـnetsh).
//
// لا مال ولا بيانات هنا: شبكة فقط.

import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShopNet {
  const ShopNet({required this.ssid, required this.password, this.host, this.port, this.secret});
  final String ssid;
  final String password;
  final String? host;
  final int? port;
  final String? secret;

  static const _prefix = 'ALNASER-NET:';

  /// نص رمز QR (يُلصق أيضاً كنص على جهاز بلا كاميرا).
  String toCode() => _prefix +
      base64Url.encode(utf8.encode(jsonEncode({
        's': ssid,
        'p': password,
        if (host != null) 'h': host,
        if (port != null) 'o': port,
        if ((secret ?? '').isNotEmpty) 'c': secret,
      })));

  static ShopNet? parse(String? raw) {
    final t = (raw ?? '').trim();
    if (!t.startsWith(_prefix)) return null;
    try {
      final m = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(t.substring(_prefix.length))))) as Map;
      final s = '${m['s'] ?? ''}';
      if (s.isEmpty) return null;
      return ShopNet(
        ssid: s,
        password: '${m['p'] ?? ''}',
        host: m['h'] as String?,
        port: (m['o'] as num?)?.toInt(),
        secret: m['c'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class ShopHotspotException implements Exception {
  ShopHotspotException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ShopHotspot {
  ShopHotspot._();

  static const _ch = MethodChannel('alnaser/hotspot');
  static const _kSsid = 'shop_net_ssid';
  static const _kPass = 'shop_net_pass';
  static const _kJoined = 'shop_net_joined_v1';

  static bool get supported => Platform.isWindows || Platform.isAndroid;

  // ─────────────────────────── الاسم وكلمة السر المحفوظان ───────────────────────────

  static Future<(String, String)> savedCredentials() async {
    final p = await SharedPreferences.getInstance();
    var s = p.getString(_kSsid) ?? '';
    var w = p.getString(_kPass) ?? '';
    if (s.isEmpty) s = 'AlNasser-POS';
    if (w.length < 8) {
      // كلمة سر عشوائية أول مرة (8 أحرف على الأقل — شرط WPA2)
      const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
      final r = Random.secure();
      w = List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
    }
    return (s, w);
  }

  static Future<void> saveCredentials(String ssid, String password) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSsid, ssid.trim());
    await p.setString(_kPass, password);
  }

  // ─────────────────────────── العنوان على شبكة المتجر ───────────────────────────

  /// عناوين IPv4 الخاصة على هذا الجهاز، والأرجح لشبكة المتجر أولاً.
  static Future<List<String>> addresses() async {
    final scored = <(int, String)>[];
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        final n = i.name.toLowerCase();
        for (final a in i.addresses) {
          final ip = a.address;
          if (!(ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip))) continue;
          var score = 0;
          if (ip == '192.168.137.1') score += 10; // نقطة اتصال Windows
          if (RegExp(r'^(ap|swlan|softap|wlan1|wlan2)').hasMatch(n) || n.contains('local area connection*')) score += 6;
          if (ip.startsWith('192.168.43.') || ip.startsWith('192.168.49.')) score += 4; // شبكات Android المعتادة
          if (ip.endsWith('.1')) score += 1;
          scored.add((score, ip));
        }
      }
    } catch (_) {}
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored) s.$2];
  }

  // ─────────────────────────── Windows ───────────────────────────

  static const _psPrelude = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function Await($op, $type) { $t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op)); $t.Wait(-1) | Out-Null; $t.Result }
function AwaitAction($op) { $t = $asTaskAction.Invoke($null, @($op)); $t.Wait(-1) | Out-Null }
$NI = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
$TM = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$cp = $NI::GetInternetConnectionProfile()
if ($cp -eq $null) { $cp = $NI::GetConnectionProfiles() | Where-Object { $_.GetNetworkConnectivityLevel() -ne 0 } | Select-Object -First 1 }
if ($cp -eq $null) { Write-Output 'ERR|NO_PROFILE'; exit 0 }
$tm = $TM::CreateFromConnectionProfile($cp)
''';

  static Future<String> _ps(String body, {Map<String, String> env = const {}}) async {
    final r = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', _psPrelude + body],
      environment: env,
      runInShell: false,
    ).timeout(const Duration(seconds: 40));
    final out = '${r.stdout}'.trim();
    final err = '${r.stderr}'.trim();
    final line = out.split(RegExp(r'[\r\n]+')).lastWhere((l) => l.startsWith('OK|') || l.startsWith('ERR|'), orElse: () => '');
    if (line.isEmpty) throw ShopHotspotException(_explainWin(err.isEmpty ? out : err));
    if (line.startsWith('ERR|')) throw ShopHotspotException(_explainWin(line.substring(4)));
    return line.substring(3);
  }

  static String _explainWin(String raw) {
    if (raw.contains('NO_PROFILE')) {
      return 'Windows لا يشغّل نقطة الاتصال إلا إذا كان الحاسوب متصلاً بشبكة ما (إنترنت أو كابل أو محوّل وهمي).\n'
          'اتصل بأي شبكة ولو بلا إنترنت، أو اطلب من الفني إضافة «Microsoft KM-TEST Loopback Adapter» مرة واحدة.';
    }
    if (raw.contains('WiFiDeviceOff') || raw.contains('RadioRestriction')) return 'الواي فاي مطفأ في الحاسوب — شغّله ثم أعد المحاولة.';
    if (raw.contains('MobileBroadbandDeviceOff') || raw.contains('NetworkLimitedConnectivity')) {
      return 'تعذّر التشغيل بسبب حالة الشبكة الحالية في Windows.';
    }
    if (raw.contains('BluetoothDeviceOff') || raw.contains('OperationInProgress')) return 'عملية أخرى جارية — أعد المحاولة بعد ثوانٍ.';
    return 'تعذّر تشغيل نقطة الاتصال: ${raw.length > 300 ? raw.substring(0, 300) : raw}\n'
        'تأكد أن في الحاسوب بطاقة Wi-Fi، وجرّب تشغيلها مرة من: الإعدادات ← الشبكة والإنترنت ← نقطة الاتصال المحمولة.';
  }

  static Future<ShopNet> startWindows({required String ssid, required String password}) async {
    final res = await _ps(r'''
$cfg = $tm.GetCurrentAccessPointConfiguration()
if ($cfg.Ssid -ne $env:HS_SSID -or $cfg.Passphrase -ne $env:HS_PASS) {
  $cfg.Ssid = $env:HS_SSID
  $cfg.Passphrase = $env:HS_PASS
  AwaitAction ($tm.ConfigureAccessPointAsync($cfg))
}
if ($tm.TetheringOperationalState -ne 'On') {
  $r = Await ($tm.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
  if ($r.Status -ne 'Success') { Write-Output ('ERR|' + $r.Status + ' ' + $r.AdditionalErrorMessage); exit 0 }
}
$cfg = $tm.GetCurrentAccessPointConfiguration()
Write-Output ('OK|' + $cfg.Ssid + '|' + $cfg.Passphrase)
''', env: {'HS_SSID': ssid, 'HS_PASS': password});
    final p = res.split('|');
    await saveCredentials(ssid, password);
    return ShopNet(ssid: p.isNotEmpty ? p[0] : ssid, password: p.length > 1 ? p.sublist(1).join('|') : password);
  }

  static Future<void> stopWindows() async {
    await _ps(r'''
if ($tm.TetheringOperationalState -eq 'On') {
  $r = Await ($tm.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
}
Write-Output 'OK|stopped'
''');
  }

  /// null = غير معروف (لا شبكة يشاركها Windows).
  static Future<bool?> windowsRunning() async {
    try {
      final r = await _ps(r"Write-Output ('OK|' + $tm.TetheringOperationalState)");
      return r.trim() == 'On';
    } catch (_) {
      return null;
    }
  }

  /// طرفية Windows تنضم لشبكة المتجر: ملف تعريف دائم (يتصل تلقائياً بعدها) ثم اتصال.
  static Future<void> joinWindows(ShopNet n) async {
    String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
    final hex = utf8.encode(n.ssid).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    final xml = '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>${esc(n.ssid)}</name>
  <SSIDConfig><SSID><hex>$hex</hex><name>${esc(n.ssid)}</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM><security>
    <authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>
    <sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>${esc(n.password)}</keyMaterial></sharedKey>
  </security></MSM>
</WLANProfile>''';
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}alnaser_shopnet_${DateTime.now().millisecondsSinceEpoch}.xml');
    try {
      await f.writeAsString(xml);
      final add = await Process.run('netsh', ['wlan', 'add', 'profile', 'filename=${f.path}', 'user=current']);
      if (add.exitCode != 0) throw ShopHotspotException('تعذّر حفظ الشبكة: ${add.stdout}${add.stderr}'.trim());
      final c = await Process.run('netsh', ['wlan', 'connect', 'name=${n.ssid}']);
      if (c.exitCode != 0) throw ShopHotspotException('تعذّر الاتصال بالشبكة: ${c.stdout}${c.stderr}'.trim());
    } finally {
      try {
        await f.delete(); // فيه كلمة السر — لا يبقى على القرص
      } catch (_) {}
    }
  }

  // ─────────────────────────── Android ───────────────────────────

  static Future<int> androidSdk() async => (await _ch.invokeMethod<int>('sdk')) ?? 0;

  static Future<void> _androidPermissions() async {
    final sdk = await androidSdk();
    if (sdk >= 33) {
      final s = await Permission.nearbyWifiDevices.request();
      if (!s.isGranted) throw ShopHotspotException('اسمح للتطبيق بـ«الأجهزة القريبة» ليشغّل شبكة المتجر.');
    } else {
      final s = await Permission.locationWhenInUse.request();
      if (!s.isGranted) throw ShopHotspotException('Android يشترط إذن «الموقع» لتشغيل شبكة التطبيق (لا نستعمل موقعك).');
      if (!await Permission.locationWhenInUse.serviceStatus.isEnabled) {
        throw ShopHotspotException('شغّل «الموقع» (GPS) من الإعدادات السريعة — Android يشترطه لتشغيل الشبكة.');
      }
    }
  }

  static Future<ShopNet> startAndroidLocal() async {
    await _androidPermissions();
    try {
      final m = await _ch.invokeMapMethod<String, Object?>('startLocal');
      final s = '${m?['ssid'] ?? ''}';
      if (s.isEmpty) throw ShopHotspotException('بدأت الشبكة لكن Android لم يُرجع اسمها.');
      return ShopNet(ssid: s, password: '${m?['password'] ?? ''}');
    } on PlatformException catch (e) {
      if (e.code == 'FAILED' && e.details == 1) {
        throw ShopHotspotException('نقطة اتصال النظام شغّالة — أطفئها أولاً أو استعمل «نقطة اتصال النظام» أدناه.');
      }
      if (e.code == 'UNSUPPORTED') throw ShopHotspotException('${e.message}');
      throw ShopHotspotException('تعذّر تشغيل شبكة التطبيق: ${e.message ?? e.code}');
    }
  }

  static Future<ShopNet?> androidLocalInfo() async {
    final m = await _ch.invokeMapMethod<String, Object?>('localInfo');
    if (m == null) return null;
    return ShopNet(ssid: '${m['ssid'] ?? ''}', password: '${m['password'] ?? ''}');
  }

  static Future<void> stopAndroidLocal() => _ch.invokeMethod('stopLocal');
  static Future<void> openSystemHotspotSettings() => _ch.invokeMethod('openSystemSettings');
  static Future<void> openWifiSettings() => _ch.invokeMethod('openWifiSettings');

  // ─────────────────────────── الطرفية ───────────────────────────

  /// ينضم لشبكة المتجر. true = اتصل؛ false = رفض المستخدم أو لم توجد الشبكة.
  static Future<bool> join(ShopNet n) async {
    if (Platform.isWindows) {
      await joinWindows(n);
      return true;
    }
    if (Platform.isAndroid) {
      try {
        final ok = await _ch.invokeMethod<bool>('join', {'ssid': n.ssid, 'password': n.password}) ?? false;
        if (ok) {
          final p = await SharedPreferences.getInstance();
          await p.setString(_kJoined, n.toCode());
        }
        return ok;
      } on PlatformException catch (e) {
        throw ShopHotspotException(e.message ?? e.code);
      }
    }
    throw ShopHotspotException('هذا الجهاز لا يدعم الانضمام التلقائي — اتصل بالشبكة من إعدادات الواي فاي.');
  }

  /// آخر شبكة متجر انضم إليها هذا الجهاز (لإعادة الانضمام بعد إعادة تشغيل التطبيق).
  static Future<ShopNet?> lastJoined() async {
    try {
      return ShopNet.parse((await SharedPreferences.getInstance()).getString(_kJoined));
    } catch (_) {
      return null;
    }
  }
}
