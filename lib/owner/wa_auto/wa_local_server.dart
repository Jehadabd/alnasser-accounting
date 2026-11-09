// lib/owner/wa_auto/wa_local_server.dart
//
// 🖥️ خادم واتساب على هذه الحاسبة بضغطة واحدة (Windows):
//   1) ينزّل Node.js المحمول من nodejs.org ويطابق بصمته (SHA-256) مع ملف nodejs.org الرسمي.
//   2) إن لم يكن Git مثبّتاً: ينزّل MinGit من إصدارات git-for-windows الرسمية ويطابق بصمته
//      (مكتبة واتساب تحتاج Git مرة واحدة عند التثبيت).
//   3) ينسخ ملفات الخادم من البرنامج ويثبّت مكتباته (npm install).
//   4) يشغّل الخادم بلا نافذة، على 127.0.0.1 فقط: لا يصل إليه أحد من الشبكة، ولا يسأل
//      جدار الحماية.
//
// كل شيء داخل مجلد بيانات البرنامج (wa_local): لا يُثبَّت شيء في النظام ولا يحتاج صلاحيات
// المدير. الخادم يتوقف وحده عند إغلاق البرنامج (PARENT_PID)، ويعود عند أول تذكير أو فحص.
// ملف لا تطابق بصمته يُحذف ولا يُشغَّل أبداً. لا يغيّر أي دين أو معاملة.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wa_server_client.dart';
import 'wa_usage_mark.dart';

/// خطوة تثبيت: [frac] نسبة التنزيل (0..1) أو null لخطوة بلا نسبة.
typedef WaLocalStep = void Function(String message, double? frac);

class WaLocalServer {
  WaLocalServer._();

  static const port = 8765;
  static const url = 'http://127.0.0.1:$port';

  static const _node = 'v20.18.1';
  static const _nodeDirName = 'node-$_node-win-x64';
  static const _nodeZipUrl = 'https://nodejs.org/dist/$_node/$_nodeDirName.zip';
  static const _nodeSumsUrl = 'https://nodejs.org/dist/$_node/SHASUMS256.txt';

  static const _gitTag = 'v2.47.1.windows.1';
  static const _gitZipName = 'MinGit-2.47.1-64-bit.zip';
  static const _gitZipUrl = 'https://github.com/git-for-windows/git/releases/download/$_gitTag/$_gitZipName';
  static const _gitReleaseApi = 'https://api.github.com/repos/git-for-windows/git/releases/tags/$_gitTag';

  static const _kEnabled = 'wa_local_enabled';
  static const _serverFiles = ['server.js', 'package.json'];

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// يتغيّر عند كل سطر جديد في [log] (للواجهة).
  static final changes = ValueNotifier<int>(0);
  static final _log = <String>[];
  static List<String> get log => List.unmodifiable(_log);

  static void _add(String m) {
    _log.add(m);
    if (_log.length > 200) _log.removeAt(0);
    changes.value++;
  }

  // ───────────── المسارات ─────────────

  static Future<String> _root() async => p.join((await getApplicationSupportDirectory()).path, 'wa_local');
  static Future<String> _nodeDir() async => p.join(await _root(), 'node', _nodeDirName);
  static Future<String> _nodeExe() async => p.join(await _nodeDir(), 'node.exe');
  static Future<String> _appDir() async => p.join(await _root(), 'app');
  static Future<String> _dataDir() async => p.join(await _root(), 'data');
  static Future<String> logFile() async => p.join(await _root(), 'server.log');
  static Future<File> _stamp() async => File(p.join(await _root(), 'installed.json'));

  static bool isLocalUrl(String u) => u == url || u == 'http://localhost:$port';

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;
  static Future<void> _setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, v);

  // ───────────── الحالة ─────────────

  static Future<String> _assetText(String f) async => rootBundle.loadString('assets/wa_server/$f');

  static String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

  /// المكتبات مثبّتة ومطابقة لـ package.json الحالي في البرنامج.
  static Future<bool> isInstalled() async {
    if (!supported) return false;
    try {
      if (!await File(await _nodeExe()).exists()) return false;
      if (!await File(p.join(await _appDir(), 'node_modules', 'baileys', 'package.json')).exists()) return false;
      final st = await _stamp();
      if (!await st.exists()) return false;
      final j = jsonDecode(await st.readAsString()) as Map;
      return j['node'] == _node && j['pkg'] == _sha(await _assetText('package.json'));
    } catch (_) {
      return false;
    }
  }

  /// يرد خادم الناصر على هذه الحاسبة؟ يعيد {v, pid} أو null.
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
          .get(Uri.parse('$url/status'), headers: {'x-key': await WaServerClient.key()})
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _assetVersion() async {
    final m = RegExp(r"const VERSION = '([^']+)'").firstMatch(await _assetText('server.js'));
    return m?.group(1);
  }

  // ───────────── التثبيت ─────────────

  static bool _installing = false;
  static bool get installing => _installing;

  /// كل شيء بضغطة: تثبيت (إن لزم) ← تشغيل ← ضبط رابط الخادم في البرنامج.
  static Future<void> setup({WaLocalStep? onStep}) async {
    if (!await isInstalled()) await install(onStep: onStep);
    await _setEnabled(true);
    onStep?.call('تشغيل الخادم…', null);
    await start(force: true);
    await WaServerClient.setUrl(url);
    onStep?.call('الخادم يعمل على هذه الحاسبة ✓', null);
  }

  static Future<void> install({WaLocalStep? onStep}) async {
    if (!supported) throw WaServerException('التشغيل الآلي على هذه الحاسبة متاح في Windows فقط');
    if (_installing) throw WaServerException('التثبيت جارٍ بالفعل');
    _installing = true;
    void step(String m, [double? f]) {
      onStep?.call(m, f);
      if (f == null) _add(m);
    }

    try {
      await WaUsageMark.record('server'); // 🔖 علامة دائمة: الخدمة شُغّلت
      final root = await _root();
      await Directory(root).create(recursive: true);

      // 1) Node.js المحمول
      final nodeExe = File(await _nodeExe());
      if (!await nodeExe.exists()) {
        step('قراءة بصمة Node.js من nodejs.org…');
        final want = hashFor(await _getText(_nodeSumsUrl), '$_nodeDirName.zip');
        if (want == null) throw WaServerException('تعذّر قراءة بصمة Node.js من nodejs.org — أعد المحاولة');
        final zip = File(p.join(root, 'node.zip'));
        step('تنزيل Node.js $_node (≈30 ميغابايت)…');
        await _download(_nodeZipUrl, zip, (f) => step('تنزيل Node.js…', f));
        await _verify(zip, want, 'Node.js');
        step('فك ضغط Node.js…');
        await _extract(zip, p.join(root, 'node'));
        if (!await nodeExe.exists()) throw WaServerException('ملف node.exe غير موجود بعد فك الضغط');
      }

      // 2) Git: من النظام إن وُجد، وإلا MinGit محمول
      var gitCmd = _systemGitDir();
      if (gitCmd == null) {
        final mg = p.join(root, 'git');
        final gitExe = File(p.join(mg, 'cmd', 'git.exe'));
        if (!await gitExe.exists()) {
          step('قراءة بصمة MinGit من GitHub…');
          final want = await _minGitHash();
          if (want == null) throw WaServerException('تعذّر قراءة بصمة MinGit من GitHub — أعد المحاولة بعد قليل');
          final zip = File(p.join(root, 'git.zip'));
          step('تنزيل MinGit (≈40 ميغابايت، مرة واحدة)…');
          await _download(_gitZipUrl, zip, (f) => step('تنزيل MinGit…', f));
          await _verify(zip, want, 'MinGit');
          step('فك ضغط MinGit…');
          await _extract(zip, mg);
          if (!await gitExe.exists()) throw WaServerException('ملف git.exe غير موجود بعد فك الضغط');
        }
        gitCmd = p.join(mg, 'cmd');
      } else {
        step('Git موجود في هذه الحاسبة — لا تنزيل');
      }

      // 3) ملفات الخادم
      step('نسخ ملفات الخادم…');
      final app = await _appDir();
      await _writeServerFiles(app);

      // 4) المكتبات
      step('تثبيت مكتبات الخادم من الإنترنت (1 إلى 5 دقائق)…');
      await _npmInstall(nodeExe.path, app, gitCmd, step);

      final st = await _stamp();
      await st.writeAsString(jsonEncode({'node': _node, 'pkg': _sha(await _assetText('package.json'))}), flush: true);
      step('اكتمل التثبيت ✓');
    } on WaServerException catch (e) {
      _add('❌ ${e.message}');
      rethrow;
    } catch (e) {
      _add('❌ $e');
      throw WaServerException('تعذّر التثبيت: $e');
    } finally {
      _installing = false;
    }
  }

  @visibleForTesting
  static String? hashFor(String sums, String file) {
    for (final line in const LineSplitter().convert(sums)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && parts[1] == file && RegExp(r'^[0-9a-f]{64}$').hasMatch(parts[0])) return parts[0];
    }
    return null;
  }

  /// بصمة MinGit من بيانات الإصدار الرسمي (حقل digest، أو جدول SHA-256 في وصف الإصدار).
  static Future<String?> _minGitHash() async {
    final j = jsonDecode(await _getText(_gitReleaseApi, headers: {'accept': 'application/vnd.github+json'}));
    if (j is! Map) return null;
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map && a['name'] == _gitZipName) {
        final d = a['digest'];
        if (d is String && RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(d)) return d.substring(7);
      }
    }
    for (final line in const LineSplitter().convert('${j['body'] ?? ''}')) {
      if (!line.contains(_gitZipName)) continue;
      final m = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(line);
      if (m != null) return m.group(0)!.toLowerCase();
    }
    return null;
  }

  static String? _systemGitDir() {
    final env = Platform.environment;
    final key = env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    for (final d in (env[key] ?? '').split(';')) {
      final dir = d.trim().replaceAll('"', '');
      if (dir.isEmpty) continue;
      try {
        if (File(p.join(dir, 'git.exe')).existsSync()) return dir;
      } catch (_) {}
    }
    return null;
  }

  static Future<String> _getText(String u, {Map<String, String>? headers}) async {
    try {
      final r = await http.get(Uri.parse(u), headers: headers).timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) throw WaServerException('تعذّر القراءة (HTTP ${r.statusCode}): $u');
      return utf8.decode(r.bodyBytes);
    } on SocketException catch (e) {
      throw WaServerException('لا إنترنت أو الموقع محجوب: ${e.message}');
    } on TimeoutException {
      throw WaServerException('انتهت المهلة: $u');
    }
  }

  static Future<void> _download(String u, File out, void Function(double) progress) async {
    final part = File('${out.path}.part');
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final res = await (await c.getUrl(Uri.parse(u))).close(); // يتبع التحويلات (GitHub)
      if (res.statusCode != 200) throw WaServerException('تعذّر التنزيل (HTTP ${res.statusCode}): $u');
      final total = res.contentLength;
      var got = 0, last = -1;
      final sink = part.openWrite();
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            final pct = got * 100 ~/ total;
            if (pct != last) {
              last = pct;
              progress(got / total);
            }
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) throw WaServerException('انقطع التنزيل — أعد المحاولة');
      if (await out.exists()) await out.delete();
      await part.rename(out.path);
    } on SocketException catch (e) {
      throw WaServerException('لا إنترنت أو الموقع محجوب: ${e.message}');
    } on TimeoutException {
      throw WaServerException('توقف التنزيل (الإنترنت بطيء أو انقطع) — أعد المحاولة');
    } finally {
      c.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  /// ملف لا تطابق بصمته يُحذف فوراً ولا يُفك ولا يُشغَّل.
  static Future<void> _verify(File f, String want, String name) async {
    final got = (await sha256.bind(f.openRead()).first).toString();
    if (got != want.toLowerCase()) {
      await f.delete();
      throw WaServerException('بصمة $name لا تطابق الملف الرسمي — حُذف الملف ولن يُشغَّل. أعد المحاولة.');
    }
    _add('✓ بصمة $name مطابقة');
  }

  static Future<void> _extract(File zip, String dest) async {
    final tmp = '$dest.tmp';
    if (await Directory(tmp).exists()) await Directory(tmp).delete(recursive: true);
    final zp = zip.path;
    await Isolate.run(() => extractFileToDisk(zp, tmp)); // لا يجمّد الواجهة
    if (await Directory(dest).exists()) await Directory(dest).delete(recursive: true);
    for (var i = 0;; i++) {
      try {
        await Directory(tmp).rename(dest);
        break;
      } on FileSystemException {
        if (i >= 4) rethrow; // برنامج الحماية يفحص الملفات — ننتظر قليلاً
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    await zip.delete();
  }

  static Future<void> _writeServerFiles(String app) async {
    await Directory(app).create(recursive: true);
    for (final f in _serverFiles) {
      final want = await _assetText(f);
      final file = File(p.join(app, f));
      if (await file.exists() && await file.readAsString() == want) continue;
      await file.writeAsString(want, flush: true);
    }
  }

  static Map<String, String> _env(String nodeDir, String? gitCmd) {
    final env = Map<String, String>.from(Platform.environment);
    final key = env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    env[key] = [nodeDir, if (gitCmd != null) gitCmd, env[key] ?? ''].join(';');
    env['npm_config_update_notifier'] = 'false';
    env['npm_config_fund'] = 'false';
    env['npm_config_audit'] = 'false';
    return env;
  }

  static Future<void> _npmInstall(String nodeExe, String app, String? gitCmd, void Function(String, [double?]) step) async {
    final nodeDir = p.dirname(nodeExe);
    final cli = p.join(nodeDir, 'node_modules', 'npm', 'bin', 'npm-cli.js');
    // detachedWithStdio: بلا نافذة سوداء، مع قراءة المخرجات
    final proc = await Process.start(
      nodeExe,
      [cli, 'install', '--omit=dev', '--no-audit', '--no-fund', '--loglevel=error'],
      workingDirectory: app,
      environment: _env(nodeDir, gitCmd),
      includeParentEnvironment: false,
      mode: ProcessStartMode.detachedWithStdio,
    );
    final tail = <String>[];
    void take(String s) {
      for (final l in const LineSplitter().convert(s)) {
        if (l.trim().isEmpty) continue;
        tail.add(l);
        if (tail.length > 30) tail.removeAt(0);
        _add('npm: $l');
      }
    }

    final done = Future.wait([
      proc.stdout.transform(utf8.decoder).forEach(take),
      proc.stderr.transform(utf8.decoder).forEach(take),
    ]);
    try {
      await done.timeout(const Duration(minutes: 12));
    } on TimeoutException {
      Process.killPid(proc.pid);
      throw WaServerException('تثبيت المكتبات تجاوز 12 دقيقة — تحقق من الإنترنت وأعد المحاولة');
    }
    final ok = await File(p.join(app, 'node_modules', 'baileys', 'package.json')).exists();
    if (!ok) {
      final last = tail.length > 8 ? tail.sublist(tail.length - 8) : tail;
      throw WaServerException('فشل تثبيت مكتبات الخادم:\n${last.join('\n')}');
    }
  }

  // ───────────── التشغيل والإيقاف ─────────────

  static Future<void>? _starting;

  /// يشغّل الخادم إن لم يكن يعمل بمفتاح البرنامج ونسخته الحالية. آمن للاستدعاء المتكرر.
  static Future<void> start({bool force = false}) {
    return _starting ??= _start(force).whenComplete(() => _starting = null);
  }

  static Future<void> _start(bool force) async {
    if (!supported) throw WaServerException('التشغيل الآلي على هذه الحاسبة متاح في Windows فقط');
    if (!await isInstalled()) {
      throw WaServerException('الخادم غير مثبّت على هذه الحاسبة — اضغط «تشغيل على هذه الحاسبة بضغطة»');
    }
    final ping = await _ping();
    if (ping != null) {
      final sameVersion = ping['v'] == await _assetVersion();
      if (sameVersion && await _keyAccepted()) return; // يعمل كما يجب
      _add(sameVersion ? 'الخادم يعمل بمفتاح قديم — إعادة تشغيل' : 'نسخة خادم أحدث في البرنامج — إعادة تشغيل');
      await stop();
    } else if (!force && !await enabled()) {
      return;
    }

    final app = await _appDir();
    await _writeServerFiles(app);
    final data = await _dataDir();
    await Directory(data).create(recursive: true);
    final logPath = await logFile();
    try {
      final lf = File(logPath);
      if (await lf.exists() && await lf.length() > 1024 * 1024) await lf.rename('$logPath.old');
    } catch (_) {}

    final nodeExe = await _nodeExe();
    // detached: بلا نافذة. يقرأ المفتاح من البيئة (لا ملف .env على القرص).
    await Process.start(
      nodeExe,
      ['server.js'],
      workingDirectory: app,
      environment: {
        'API_KEY': await WaServerClient.key(),
        'PORT': '$port',
        'HOST': '127.0.0.1',
        'STATE_DIR': data,
        'LOG_FILE': logPath,
        'PARENT_PID': '$pid',
        'NODE_ENV': 'production',
      },
      includeParentEnvironment: true,
      mode: ProcessStartMode.detached,
    );

    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await _ping() != null) {
        _add('الخادم يعمل على $url');
        return;
      }
    }
    final tail = await logTail(6);
    throw WaServerException('الخادم لم يبدأ خلال 20 ثانية.${tail.isEmpty ? '' : '\n$tail'}');
  }

  /// يوقف الخادم المحلي (pid من ردّه نفسه — لا نقتل عملية لا نعرفها).
  static Future<void> stop() async {
    final ping = await _ping();
    final id = (ping?['pid'] as num?)?.toInt();
    if (id == null) return;
    Process.killPid(id);
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (await _ping() == null) break;
    }
    _add('أُوقف الخادم');
  }

  /// للتذكير والفحص: إن كان التشغيل الآلي مفعّلاً والخادم متوقفاً ⇒ يشغّله.
  static Future<bool> ensureRunning() async {
    if (!supported || !await enabled()) return false;
    try {
      // تحديث البرنامج غيّر مكتبات الخادم ⇒ يعيد تثبيتها وحده (Node وGit موجودان)
      if (!await isInstalled() && !_installing) await install();
      await start();
      return true;
    } catch (e) {
      _add('❌ $e');
      return false;
    }
  }

  /// إيقاف وإزالة الملفات المنزّلة (Node وGit والمكتبات). تبقى جلسة الربط المشفّرة (data).
  static Future<void> remove() async {
    await stop();
    await _setEnabled(false);
    final root = await _root();
    for (final d in ['node', 'git', 'app']) {
      final dir = Directory(p.join(root, d));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    final st = await _stamp();
    if (await st.exists()) await st.delete();
    _add('أُزيل التثبيت المحلي');
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
