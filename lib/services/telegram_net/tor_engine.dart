// lib/services/telegram_net/tor_engine.dart
//
// 🧅 الطريقة التلقائية لتيليجرام عند الحظر: Tor مع جسوره المدمجة (Snowflake و obfs4 و meek).
//
// • Tor Expert Bundle الرسمي لنظام Windows من torproject.org (آخر نسخة مستقرة)، وتُطابق
//   بصمة SHA-256 للحزمة مع ملف البصمات المنشور بجانبها قبل الاستخراج. حزمة لا تطابق تُحذف.
// • كل الجسور المدمجة معاً (Snowflake + obfs4 + meek) فيستعمل Tor أول ما يعمل منها — مقيس:
//   Snowflake وحده توقف عند 10% على شبكة المحل. الجسور وبرامجها تُقرأ من
//   pt_config.json الرسمي داخل الحزمة نفسها (لا أسطر مكتوبة يدوياً تقدم مع الوقت).
// • tor.exe يعمل في الخلفية بلا نافذة على 127.0.0.1 فقط، ويُغلق نفسه إن أُغلق البرنامج
//   (__OwningControllerProcess). رفع تيليجرام وحده يمر عبره (telegram_proxy.dart).
// • التشفير من البرنامج إلى api.telegram.org نفسه: محطات Tor لا تقرأ التوكن ولا الملفات.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/error_journal.dart'; // 🩺 خطأ Tor يُسجَّل مع ما سبقه من أسطره
import '../simplex/simplex_engine.dart' show SimplexEngine, SimplexException;

enum TorStartMode { onUpload, onAppStart }

class TorEngine {
  TorEngine._();

  static const _kEnabled = 'tg_tor_enabled';
  static const _kMode = 'tg_tor_start_mode';
  static const _versionsUrl = 'https://aus1.torproject.org/torbrowser/update_3/release/downloads.json';
  static const _hosts = ['https://dist.torproject.org/torbrowser', 'https://archive.torproject.org/tor-package-archive/torbrowser'];

  static bool get supported => !kIsWeb && Platform.isWindows;

  // ───────────── الإعداد ─────────────

  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;
  static Future<void> setEnabled(bool v) async {
    await (await SharedPreferences.getInstance()).setBool(_kEnabled, v);
    if (!v) await stop();
  }

  static Future<TorStartMode> startMode() async =>
      (await SharedPreferences.getInstance()).getString(_kMode) == 'app' ? TorStartMode.onAppStart : TorStartMode.onUpload;
  static Future<void> setStartMode(TorStartMode m) async =>
      (await SharedPreferences.getInstance()).setString(_kMode, m == TorStartMode.onAppStart ? 'app' : 'upload');

  /// مفعّل ومثبّت (بلا شبكة).
  static Future<bool> isActive() async => supported && await isEnabled() && await isInstalled();

  // ───────────── المسارات والتثبيت ─────────────

  static Future<String> root() async => p.join((await getApplicationSupportDirectory()).path, 'tor');
  static Future<String> _bin() async => p.join(await root(), 'bin');
  static Future<File> _stamp() async => File(p.join(await _bin(), 'installed.json'));
  static Future<String> _exe() async => p.join(await _bin(), 'tor', 'tor.exe');
  static Future<String> _ptDir() async => p.join(await _bin(), 'tor', 'pluggable_transports');

  static Future<bool> isInstalled() async {
    if (!supported) return false;
    try {
      final st = jsonDecode(await (await _stamp()).readAsString()) as Map;
      return st['version'] != null && await File(await _exe()).exists() && await File(p.join(await _ptDir(), 'pt_config.json')).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<String?> installedVersion() async {
    try {
      return '${(jsonDecode(await (await _stamp()).readAsString()) as Map)['version']}';
    } catch (_) {
      return null;
    }
  }

  static bool _installing = false;

  static Future<void> install({void Function(String text, [double? progress])? step}) async {
    if (!supported) throw SimplexException('Tor متاح حالياً على Windows فقط');
    if (_installing) throw SimplexException('التثبيت جارٍ بالفعل');
    _installing = true;
    void s(String t, [double? f]) {
      _add(t);
      step?.call(t, f);
    }

    try {
      s('معرفة آخر نسخة مستقرة من Tor…');
      final ver = versionFromDownloadsJson(await SimplexEngine.fetchText(_versionsUrl));
      if (ver == null) throw SimplexException('تعذّر معرفة نسخة Tor الحالية');
      final name = bundleName(ver);
      String? want;
      String? base;
      for (final h in _hosts) {
        try {
          final sums = await SimplexEngine.fetchText('$h/$ver/sha256sums-signed-build.txt');
          want = hashFor(sums, name);
          if (want != null) {
            base = '$h/$ver';
            break;
          }
        } catch (e) {
          _add('تعذّر $h: $e');
        }
      }
      if (want == null || base == null) throw SimplexException('تعذّر قراءة بصمة حزمة Tor — لا يُنزَّل ما لا يمكن التحقق منه');

      final bin = Directory(await _bin());
      await bin.create(recursive: true);
      final tmp = File(p.join(bin.path, 'download.tar.gz'));
      if (await tmp.exists()) await tmp.delete();
      s('تنزيل Tor $ver (مرة واحدة)…', 0);
      await SimplexEngine.fetchFile('$base/$name', tmp, (f) => s('تنزيل Tor…', f));
      final bytes = await tmp.readAsBytes();
      await tmp.delete();
      final got = sha256.convert(bytes).toString();
      if (got != want) throw SimplexException('بصمة حزمة Tor لا تطابق المنشورة — حُذفت ولم تُستعمل. أعد المحاولة');

      s('استخراج الملفات…');
      await stop();
      final tar = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      var n = 0;
      for (final f in tar.files) {
        if (!f.isFile) continue;
        final rel = safeRelative(f.name);
        if (rel == null) continue; // مسار يخرج من المجلد: يُتجاهل
        final out = File(p.join(bin.path, rel));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>, flush: true);
        n++;
      }
      if (!await File(await _exe()).exists()) throw SimplexException('الحزمة لا تحتوي tor.exe');
      if ((await builtinBridges()).isEmpty) throw SimplexException('الحزمة لا تحتوي إعداد الجسور المدمجة');
      await (await _stamp()).writeAsString(jsonEncode({'version': ver, 'sha256': got, 'files': n, 'at': DateTime.now().toIso8601String()}));
      s('تم تثبيت Tor $ver');
    } finally {
      _installing = false;
    }
  }

  /// أسطر جسور Snowflake من pt_config.json المرفق بالحزمة.
  static Future<List<String>?> snowflakeBridges() async {
    try {
      return bridgesFromPtConfig(await File(p.join(await _ptDir(), 'pt_config.json')).readAsString(), 'snowflake');
    } catch (_) {
      return null;
    }
  }

  /// كل الجسور المدمجة (Snowflake أولاً ثم obfs4 ثم meek) من pt_config.json.
  static Future<List<String>> builtinBridges() async {
    try {
      final json = await File(p.join(await _ptDir(), 'pt_config.json')).readAsString();
      return [
        for (final t in const ['snowflake', 'obfs4', 'meek', 'webtunnel']) ...?bridgesFromPtConfig(json, t),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// أسطر ClientTransportPlugin من pt_config.json (بأسماء ملفات نسبية لمجلد التشغيل).
  static Future<List<String>> _pluginLines() async {
    final dir = await _ptDir();
    try {
      final lines = pluginLinesFromPtConfig(await File(p.join(dir, 'pt_config.json')).readAsString());
      final ok = <String>[];
      for (final l in lines) {
        final exe = l.split(RegExp(r'\s+')).elementAt(3);
        if (await File(p.join(dir, exe)).exists()) ok.add(l);
      }
      if (ok.isNotEmpty) return ok;
    } catch (_) {}
    return ['ClientTransportPlugin snowflake exec ${await _snowflakeExe()}'];
  }

  /// برنامج Snowflake كما يسمّيه pt_config.json (lyrebird في النسخ الحديثة، snowflake-client قديماً).
  static Future<String> _snowflakeExe() async {
    final dir = await _ptDir();
    try {
      final name = snowflakeExecName(await File(p.join(dir, 'pt_config.json')).readAsString());
      if (name != null && await File(p.join(dir, name)).exists()) return name;
    } catch (_) {}
    if (await File(p.join(dir, 'lyrebird.exe')).exists()) return 'lyrebird.exe';
    if (await File(p.join(dir, 'snowflake-client.exe')).exists()) return 'snowflake-client.exe';
    throw SimplexException('برنامج Snowflake غير موجود في حزمة Tor — أعد التثبيت');
  }

  // ───────────── التشغيل ─────────────

  static final ValueNotifier<int> bootstrap = ValueNotifier(0); // نسبة الاتصال 0-100
  static final ValueNotifier<List<String>> log = ValueNotifier(const []);
  static void _add(String s) {
    final l = [...log.value, '${DateTime.now().toIso8601String().substring(11, 19)}  $s'];
    log.value = l.length > 200 ? l.sublist(l.length - 200) : l;
    debugPrint('🧅 Tor: $s');
  }

  static Process? _proc;
  static int? _socks;
  static Completer<int>? _ready;

  /// منفذ SOCKS إن كان Tor متصلاً الآن (بلا تشغيل).
  static int? get readyPort => (_ready?.isCompleted ?? false) && _proc != null ? _socks : null;

  /// آخر أسطر Tor كما خرجت (كل المستويات) — تُرفق بالخطأ في «تشخيص الأخطاء».
  static final List<String> _tail = [];
  static String? _lastErr;

  /// tor.exe خاصتنا ما زال يعمل بلا أن نملكه (بعد Hot Restart أثناء التطوير، أو تشغيل سابق
  /// لم يُغلق): يمسك مجلد البيانات فيفشل كل تشغيل جديد بـ «Reading config failed».
  /// يُغلق فقط ما مساره هو tor.exe الخاص بالبرنامج — لا يمسّ Tor Browser أو غيره.
  static Future<int> killStray() async {
    if (!supported) return 0;
    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'$p = Get-Process tor -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $env:ALNASER_TOR_EXE }; '
              r'$p | Stop-Process -Force -ErrorAction SilentlyContinue; ($p | Measure-Object).Count',
        ],
        environment: {'ALNASER_TOR_EXE': await _exe()},
      ).timeout(const Duration(seconds: 15));
      final n = int.tryParse('${r.stdout}'.trim()) ?? 0;
      if (n > 0) _add('أُغلقت $n نسخة Tor عالقة من تشغيل سابق');
      return n;
    } catch (e) {
      _add('تعذّر فحص نسخ Tor العالقة: $e');
      return 0;
    }
  }

  /// يشغّل Tor (إن لم يكن يعمل) وينتظر اكتمال الاتصال، ويعيد منفذ SOCKS.
  /// 🛠️ إصلاح ذاتي: إن رفض Tor الإعداد لأن نسخة عالقة تمسك مجلد البيانات، تُغلق ويُعاد مرة.
  static Future<int> ensureRunning({Duration timeout = const Duration(minutes: 4)}) async {
    try {
      return await _ensureRunningOnce(timeout: timeout);
    } on SimplexException {
      final err = _lastErr ?? '';
      if (!err.contains('Reading config failed') && !err.contains('still there')) rethrow;
      _add('Tor لم يقرأ إعداده — غالباً نسخة عالقة تمسك مجلد البيانات. إغلاقها وإعادة المحاولة…');
      await killStray();
      await Future<void>.delayed(const Duration(seconds: 1));
      return _ensureRunningOnce(timeout: timeout);
    }
  }

  static Future<int> _ensureRunningOnce({required Duration timeout}) async {
    final r = _ready;
    // تشغيل جارٍ (لم يكتمل بعد) أو يعمل ⇒ ننتظره؛ لا نشغّل نسخة ثانية على المجلد نفسه
    if (r != null && (_proc != null || !r.isCompleted)) {
      return r.future.timeout(timeout, onTimeout: () => throw _timeoutError());
    }
    if (!await isInstalled()) throw SimplexException('Tor غير مثبّت — من «عند حظر تيليجرام» اضغط «تثبيت Tor»');
    final bridges = await builtinBridges();
    if (bridges.isEmpty) throw SimplexException('إعداد الجسور المدمجة مفقود — أعد تثبيت Tor');
    final geoip = p.join(await _bin(), 'data', 'geoip');

    final ready = Completer<int>();
    _ready = ready;
    _lastErr = null;
    _tail.clear();
    try {
      final rootDir = await root();
      final data = Directory(p.join(rootDir, 'data'));
      await data.create(recursive: true);
      // ملف القفل موجود ولا Tor نملكه ⇒ نسخة عالقة على الأرجح (أو قفل قديم): أغلقها أولاً
      if (await File(p.join(data.path, 'lock')).exists()) await killStray();
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      final torrc = File(p.join(rootDir, 'torrc'));
      await torrc.writeAsString(buildTorrc(
        dataDir: data.path,
        socksPort: port,
        plugins: await _pluginLines(), // أسماء نسبية لمجلد التشغيل (المسار الكامل قد يحوي مسافات لا يفهمها سطر exec)
        geoipDir: await File(geoip).exists() ? p.dirname(geoip) : null,
        bridges: bridges,
        ownerPid: pid,
      ));
      bootstrap.value = 0;
      _add('تشغيل Tor (${bridges.length} جسراً مدمجاً) على 127.0.0.1:$port');
      final proc = await Process.start(await _exe(), ['-f', torrc.path],
          workingDirectory: await _ptDir(), mode: ProcessStartMode.detachedWithStdio);
      _proc = proc;
      _socks = port;
      final re = RegExp(r'Bootstrapped (\d+)%');
      void onLine(String line) {
        _tail.add(line.length > 240 ? line.substring(0, 240) : line);
        if (_tail.length > 30) _tail.removeAt(0);
        final m = re.firstMatch(line);
        if (m != null) {
          bootstrap.value = int.parse(m.group(1)!);
          _add(line.substring(line.indexOf('Bootstrapped')));
          if (bootstrap.value >= 100 && !ready.isCompleted) ready.complete(port);
        } else if (line.contains('[err]') || line.contains('[warn]')) {
          _add(line.length > 200 ? line.substring(0, 200) : line);
          if (line.contains('[err]')) {
            _lastErr = line;
            // 🩺 «see warnings above»: الأسطر التي سبقت الخطأ هي السبب الحقيقي — تُرفق به
            final before = _tail.where((l) => !l.contains('[err]')).toList();
            ErrorJournal.recordText(ErrorSource.logged,
                '🧅 Tor: $line\nما سبقه من Tor:\n${before.skip(before.length > 12 ? before.length - 12 : 0).join('\n')}');
          }
        }
      }

      proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(onLine, onError: (_) {});
      proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(onLine, onError: (_) {},
          onDone: () {
        if (!ready.isCompleted) ready.completeError(SimplexException('توقف Tor قبل أن يتصل — راجع «سجل Tor»'));
        if (identical(_proc, proc)) {
          _proc = null;
          _ready = null;
        }
      });
      return await ready.future.timeout(timeout, onTimeout: () => throw _timeoutError());
    } catch (e) {
      if (!ready.isCompleted) ready.completeError(e);
      await stop();
      rethrow;
    }
  }

  /// عند فتح البرنامج: يبدأ الاتصال مبكراً إن اختار المستخدم ذلك (بلا انتظار ولا أخطاء ظاهرة).
  static Future<void> autoStart() async {
    try {
      if (await isActive() && await startMode() == TorStartMode.onAppStart) await ensureRunning();
    } catch (e) {
      _add('التشغيل التلقائي: $e');
    }
  }

  static SimplexException _timeoutError() =>
      SimplexException('لم يكتمل اتصال Tor (وصل ${bootstrap.value}%) — جسور Tor المدمجة لم تعمل على هذه الشبكة');

  static Future<void> stop() async {
    final pr = _proc;
    _proc = null;
    _ready = null;
    _socks = null;
    bootstrap.value = 0;
    if (pr != null) {
      try {
        pr.kill();
      } catch (_) {}
      _add('أُوقف Tor');
    }
  }

  // ───────────── أدوات صافية (مختبرة) ─────────────

  @visibleForTesting
  static String bundleName(String ver) => 'tor-expert-bundle-windows-x86_64-$ver.tar.gz';

  /// النسخة من downloads.json الخاص بمحدّث متصفح Tor.
  @visibleForTesting
  static String? versionFromDownloadsJson(String body) {
    final j = jsonDecode(body);
    final v = j is Map ? j['version'] : null;
    return v is String && RegExp(r'^\d+(\.\d+){1,3}[a-z0-9]*$').hasMatch(v) ? v : null;
  }

  /// سطر «hash  name» من ملف البصمات.
  @visibleForTesting
  static String? hashFor(String sums, String name) {
    for (final line in const LineSplitter().convert(sums)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts.last.replaceFirst('*', '') == name && RegExp(r'^[0-9a-f]{64}$').hasMatch(parts.first)) {
        return parts.first;
      }
    }
    return null;
  }

  /// مسار نسبي آمن داخل المجلد (لا مطلق ولا ..)، أو null.
  @visibleForTesting
  static String? safeRelative(String name) {
    final n = name.replaceAll('\\', '/');
    if (n.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(n)) return null;
    final parts = n.split('/').where((s) => s.isNotEmpty && s != '.').toList();
    if (parts.isEmpty || parts.contains('..')) return null;
    return p.joinAll(parts);
  }

  @visibleForTesting
  static List<String>? bridgesFromPtConfig(String json, String transport) {
    final j = jsonDecode(json);
    final all = j is Map ? j['bridges'] : null;
    final b = all is Map ? all[transport] : null;
    if (b is! List) return null;
    final out = [for (final x in b) if (x is String && x.trim().startsWith(transport)) x.trim()];
    return out.isEmpty ? null : out;
  }

  /// «ClientTransportPlugin X exec ${pt_path}Y [args]» → «ClientTransportPlugin X exec Y.exe [args]».
  @visibleForTesting
  static List<String> pluginLinesFromPtConfig(String ptConfigJson) {
    final j = jsonDecode(ptConfigJson);
    final pts = j is Map ? j['pluggableTransports'] : null;
    if (pts is! Map) return const [];
    final out = <String>[];
    for (final v in pts.values) {
      if (v is! String) continue;
      final m = RegExp(r'^ClientTransportPlugin\s+([\w,]+)\s+exec\s+(\S+)(.*)$').firstMatch(v.trim());
      if (m == null) continue;
      var exe = m.group(2)!.replaceAll(r'${pt_path}', '').split(RegExp(r'[\\/]')).last;
      if (!RegExp(r'^[\w.\-]+$').hasMatch(exe)) continue;
      if (!exe.toLowerCase().endsWith('.exe')) exe = '$exe.exe';
      out.add('ClientTransportPlugin ${m.group(1)} exec $exe${m.group(3)}'.trimRight());
    }
    return out;
  }

  /// اسم الملف من «ClientTransportPlugin snowflake exec ${pt_path}lyrebird» → lyrebird.exe
  @visibleForTesting
  static String? snowflakeExecName(String ptConfigJson) {
    final j = jsonDecode(ptConfigJson);
    final pts = j is Map ? j['pluggableTransports'] : null;
    if (pts is! Map) return null;
    for (final v in pts.values) {
      if (v is! String) continue;
      final m = RegExp(r'ClientTransportPlugin\s+([\w,]+)\s+exec\s+(\S+)').firstMatch(v);
      if (m == null || !m.group(1)!.split(',').contains('snowflake')) continue;
      final name = m.group(2)!.replaceAll(r'${pt_path}', '').split(RegExp(r'[\\/]')).last;
      if (!RegExp(r'^[\w.\-]+$').hasMatch(name)) return null;
      return name.toLowerCase().endsWith('.exe') ? name : '$name.exe';
    }
    return null;
  }

  @visibleForTesting
  static String buildTorrc({
    required String dataDir,
    required int socksPort,
    required List<String> plugins,
    String? geoipDir,
    required List<String> bridges,
    required int ownerPid,
  }) {
    String q(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    return [
      'DataDirectory ${q(dataDir)}',
      'SocksPort 127.0.0.1:$socksPort',
      'ControlPort 0',
      'Log notice stdout',
      'AvoidDiskWrites 1',
      '__OwningControllerProcess $ownerPid',
      'UseBridges 1',
      ...plugins,
      if (geoipDir != null) ...['GeoIPFile ${q(p.join(geoipDir, 'geoip'))}', 'GeoIPv6File ${q(p.join(geoipDir, 'geoip6'))}'],
      for (final b in bridges) 'Bridge $b',
      '',
    ].join('\n');
  }
}
