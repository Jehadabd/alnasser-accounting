// lib/owner/wa_auto/wa_phone_server.dart
//
// 📱 خادم واتساب على هذا الهاتف (أندرويد) — مثل «الخادم على هذه الحاسبة» في Windows:
//   • Node.js ومكتبات الخادم مضمّنة داخل التطبيق (لا تنزيل): Node من nodejs-mobile، والمكتبات
//     أرشيف يُفك مرة لكل نسخة من التطبيق (WaNode.kt).
//   • يعمل في خدمة أمامية بإشعار ثابت «خادم واتساب يعمل» على 127.0.0.1 فقط، ومفتاحه في بيئة
//     العملية (لا ملف على القرص).
//   • اختيار طريقة الهاتف: «خادم على هذا الهاتف» أو «خادم حاسبة المحل» (wa_remote_server.dart).
// لا يغيّر أي دين أو معاملة.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wa_pair_code.dart';
import 'wa_server_client.dart';

/// على الهاتف: أين الخادم؟
enum WaPhoneMode { none, phone, pc }

class WaPhoneServer {
  WaPhoneServer._();

  static const port = 8765;
  static const url = 'http://127.0.0.1:$port';
  static const _ch = MethodChannel('alnaser/wa_node');

  static const _kEnabled = 'wa_phone_enabled';
  static const _kAutoStart = 'wa_phone_autostart';
  static const _kMode = 'wa_phone_mode';
  static const _serverFiles = ['server.js', 'package.json', 'boot_android.mjs'];

  static bool get supported => !kIsWeb && Platform.isAndroid;

  // ───────────── الطريقة والإعدادات ─────────────

  static Future<WaPhoneMode> mode() async {
    final v = (await SharedPreferences.getInstance()).getString(_kMode);
    return WaPhoneMode.values.firstWhere((m) => m.name == v, orElse: () => WaPhoneMode.none);
  }

  static Future<void> setMode(WaPhoneMode m) async =>
      (await SharedPreferences.getInstance()).setString(_kMode, m.name);

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;
  static Future<void> _setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, v);

  /// true (الافتراضي) = يبدأ مع فتح البرنامج. false = عند أول إرسال فقط.
  static Future<bool> autoStart() async => (await SharedPreferences.getInstance()).getBool(_kAutoStart) ?? true;
  static Future<void> setAutoStart(bool v) async => (await SharedPreferences.getInstance()).setBool(_kAutoStart, v);

  /// هل بُنيت هذه النسخة بخادم الهاتف؟ (Node في التطبيق + أرشيف المكتبات)
  static Future<({bool native, bool modules, String abi})> availability() async {
    if (!supported) return (native: false, modules: false, abi: '');
    try {
      final m = (await _ch.invokeMapMethod<String, dynamic>('available')) ?? const {};
      return (native: m['native'] == true, modules: m['modules'] == true, abi: '${m['abi'] ?? ''}');
    } catch (_) {
      return (native: false, modules: false, abi: '');
    }
  }

  static Future<bool> available() async {
    final a = await availability();
    return a.native && a.modules;
  }

  // ───────────── المسارات ─────────────

  static Future<String> _root() async => p.join((await getApplicationSupportDirectory()).path, 'wa_phone');
  static Future<String> _appDir() async => p.join(await _root(), 'app');
  static Future<String> _dataDir() async => p.join(await _root(), 'data');
  static Future<String> logFile() async => p.join(await _root(), 'server.log');

  static Future<String> _assetText(String f) async => rootBundle.loadString('assets/wa_server/$f');

  static Future<String?> _assetVersion() async =>
      RegExp(r"const VERSION = '([^']+)'").firstMatch(await _assetText('server.js'))?.group(1);

  // ───────────── الحالة ─────────────

  static Future<Map<String, dynamic>?> _ping() async {
    try {
      final r = await http.get(Uri.parse('$url/ping')).timeout(const Duration(seconds: 3));
      final j = jsonDecode(r.body);
      if (j is Map && j['app'] == 'alnaser-wa') return j.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  static Future<bool> isRunning() async => await _ping() != null;

  static Future<bool> _keyAccepted() async {
    try {
      final r = await http
          .get(Uri.parse('$url/status'), headers: {'x-key': await WaServerClient.localKey()})
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ───────────── التشغيل ─────────────

  /// كل شيء بضغطة: إذن الإشعار ← فك المكتبات ← تشغيل ← ضبط رابط الخادم في البرنامج.
  static Future<void> setup({void Function(String message)? onStep}) async {
    if (!supported) throw WaServerException('خادم الهاتف لأجهزة أندرويد فقط');
    final a = await availability();
    if (!a.native || !a.modules) {
      throw WaServerException('هذه النسخة من التطبيق بُنيت بلا «خادم على الهاتف». '
          'استعمل «خادم حاسبة المحل»، أو ثبّت النسخة الكاملة.');
    }
    if (!a.abi.contains('64') && a.abi != 'armeabi-v7a') {
      throw WaServerException('معالج هذا الهاتف (${a.abi}) غير مدعوم لخادم الهاتف');
    }
    onStep?.call('إذن الإشعار (الخادم يعمل بإشعار ثابت)…');
    try {
      await Permission.notification.request();
    } catch (_) {}
    await setMode(WaPhoneMode.phone);
    await _setEnabled(true);
    await start(force: true, onStep: onStep);
    await WaServerClient.setUrl(url);
    onStep?.call('الخادم يعمل على هذا الهاتف ✓');
  }

  static Future<void>? _starting;

  static Future<void> start({bool force = false, void Function(String message)? onStep}) {
    return _starting ??= _start(force, onStep).whenComplete(() => _starting = null);
  }

  static Future<void> _start(bool force, void Function(String message)? onStep) async {
    if (!supported) throw WaServerException('خادم الهاتف لأجهزة أندرويد فقط');
    final ping = await _ping();
    if (ping != null) {
      if (ping['v'] == await _assetVersion() && await _keyAccepted()) return; // يعمل كما يجب
      await stop();
    } else if (!force && !await enabled()) {
      return;
    }

    final app = await _appDir();
    await Directory(app).create(recursive: true);
    onStep?.call('تجهيز مكتبات الخادم (أول مرة بعد كل تحديث: قد يأخذ دقيقة)…');
    try {
      await _ch.invokeMethod('prepare', {'dir': app});
    } on PlatformException catch (e) {
      throw WaServerException('تعذّر تجهيز مكتبات الخادم: ${e.message}');
    }
    for (final f in _serverFiles) {
      await File(p.join(app, f)).writeAsString(await _assetText(f), flush: true);
    }
    final data = await _dataDir();
    await Directory(data).create(recursive: true);
    final logPath = await logFile();
    try {
      final lf = File(logPath);
      if (await lf.exists() && await lf.length() > 512 * 1024) await lf.rename('$logPath.old');
    } catch (_) {}

    final env = <String, String>{
      'API_KEY': await WaServerClient.localKey(),
      'PORT': '$port',
      'HOST': '127.0.0.1',
      'STATE_DIR': data,
      'LOG_FILE': logPath,
      'NODE_ENV': 'production',
    };
    onStep?.call('تشغيل الخادم…');
    try {
      await _ch.invokeMethod('start', {
        'script': p.join(app, 'boot_android.mjs'),
        'log': logPath,
        'envNames': env.keys.toList(),
        'envValues': env.values.toList(),
      });
    } on PlatformException catch (e) {
      throw WaServerException('تعذّر تشغيل خدمة الخادم: ${e.message}');
    }
    // الهاتف أبطأ من الحاسبة: أول تشغيل يحمّل المكتبات
    for (var i = 0; i < 90; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await _ping() != null) return;
    }
    final tail = await logTail(8);
    throw WaServerException('الخادم لم يبدأ خلال 45 ثانية.${tail.isEmpty ? '' : '\n$tail'}');
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (await _ping() == null) break;
    }
  }

  /// للإرسال والفحص: إن كان خادم الهاتف مختاراً ومتوقفاً ⇒ يشغّله.
  static Future<bool> ensureRunning() async {
    if (!supported || !await enabled() || await mode() != WaPhoneMode.phone) return false;
    try {
      await start();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// عند فتح البرنامج: يشغّل الخادم إن كان مختاراً و«يبدأ مع البرنامج». خادم الحاسبة ⇒ true
  /// (لا شيء يُشغَّل هنا، والفحص يتصل بالحاسبة).
  static Future<bool> startAtLaunch() async {
    if (!supported) return false;
    final m = await mode();
    if (m == WaPhoneMode.pc) return true;
    if (m != WaPhoneMode.phone || !await enabled() || !await autoStart()) return false;
    return ensureRunning();
  }

  /// «خادم حاسبة المحل»: يحفظ رابطها ومفتاحها من رمز الربط، ويوقف خادم الهاتف إن كان يعمل
  /// (لا يعمل خادمان برقم واحد)، ثم يتصل ويعيد الحالة.
  static Future<WaServerStatus> usePc(WaPairCode code) async {
    await WaServerClient.setRemote(code.url, code.key);
    await setMode(WaPhoneMode.pc);
    if (await enabled() || await isRunning()) await disable();
    return WaServerClient.ensureReady();
  }

  /// إيقاف خادم الهاتف وإلغاء اختياره (الجلسة المشفّرة تبقى في data).
  static Future<void> disable() async {
    await _setEnabled(false);
    await stop();
  }

  // ───────────── البطارية ─────────────

  /// أندرويد لا يقيّد البرنامج في الخلفية؟
  static Future<bool> batteryExempt() async {
    if (!supported) return true;
    try {
      return await _ch.invokeMethod<bool>('batteryExempt') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestBatteryExempt() async {
    try {
      await _ch.invokeMethod('requestBatteryExempt');
    } catch (_) {}
  }

  static Future<String> logTail([int lines = 60]) async {
    try {
      final f = File(await logFile());
      if (!await f.exists()) return '';
      final all = const LineSplitter().convert(await f.readAsString());
      return all.sublist(all.length > lines ? all.length - lines : 0).join('\n');
    } catch (_) {
      return '';
    }
  }
}
