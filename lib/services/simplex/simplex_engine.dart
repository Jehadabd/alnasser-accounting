// lib/services/simplex/simplex_engine.dart
//
// 🛡️ محرك SimpleX على هذه الحاسبة (Windows فقط).
//
// البرنامج الرسمي لـ SimpleX Chat بنسخة سطر الأوامر (simplex-chat.exe) يعمل في
// الخلفية بلا نافذة، ويستمع على 127.0.0.1 فقط (لا يقبل اتصالاً من الشبكة — من كود
// SimpleX نفسه: runLocalTCPServer). البرنامج يكلّمه عبر WebSocket (simplex_client.dart).
//
// • التنزيل مرة واحدة من إصدارات SimpleX الرسمية على GitHub بنسخة مثبّتة [version]،
//   وتُطابق بصمة SHA-256 للملف مع بيانات الإصدار الرسمية قبل أي تشغيل. ملف لا تطابق
//   بصمته يُحذف ولا يُشغَّل.
// • قاعدة بيانات SimpleX (مفاتيح البوت وجهات الاتصال) مشفّرة بمفتاح عشوائي محفوظ في
//   مخزن Windows الآمن (FlutterSecureStorage) — لا في الإعدادات العادية.
// • تشغيل واحد: رقم العملية والمنفذ في run.json. إن بقي المحرك يعمل من جلسة سابقة
//   يُستعمل كما هو؛ وإن تعطّل يُغلق (بعد التأكد من أن العملية هي simplex-chat.exe نفسه).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'simplex_socks.dart';

class SimplexException implements Exception {
  SimplexException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SimplexEngine {
  SimplexEngine._();

  /// نسخة SimpleX المثبّتة (تُحدَّث هنا يدوياً بعد تجربتها).
  static const version = 'v6.5.6';
  static const _asset = 'simplex-chat-windows-x86-64';
  static const _exeName = 'simplex-chat.exe';
  static const _releaseApi = 'https://api.github.com/repos/simplex-chat/simplex-chat/releases/tags/$version';
  static const _downloadUrl = 'https://github.com/simplex-chat/simplex-chat/releases/download/$version/$_asset';

  /// اسم البوت الذي يظهر في هاتف صاحب المحل.
  static const botName = 'Alnaser Backup';

  static const _secure = FlutterSecureStorage();
  static const _kDbKey = 'simplex_db_key';

  static bool get supported => !kIsWeb && Platform.isWindows;

  // ───────────── سجل مختصر للتشخيص ─────────────

  static final ValueNotifier<List<String>> log = ValueNotifier(const []);
  static void _add(String s) {
    final l = [...log.value, '${DateTime.now().toIso8601String().substring(11, 19)}  $s'];
    log.value = l.length > 200 ? l.sublist(l.length - 200) : l;
    debugPrint('🛡️ SimpleX: $s');
  }

  // ───────────── المسارات ─────────────

  static Future<String> root() async => p.join((await getApplicationSupportDirectory()).path, 'simplex');
  static Future<String> _exe() async => p.join(await root(), 'bin', _exeName);
  static Future<String> _dbPrefix() async => p.join(await root(), 'data', 'alnaser');
  static Future<String> filesDir() async => p.join(await root(), 'files');
  static Future<File> _runFile() async => File(p.join(await root(), 'run.json'));
  static Future<File> _stamp() async => File(p.join(await root(), 'bin', 'installed.json'));
  static Future<String> logFile() async => p.join(await root(), 'engine.log');

  static Future<bool> isInstalled() async {
    if (!supported) return false;
    final exe = File(await _exe());
    if (!await exe.exists()) return false;
    // الملف المثبّت هو نفسه الذي طابقت بصمته عند التثبيت؟ (البصمة تُحسب مرة لكل نسخة من الملف)
    try {
      final stat = await exe.stat();
      final sig = '${stat.size}|${stat.modified.millisecondsSinceEpoch}';
      if (_checkedSig == sig) return true;
      final st = jsonDecode(await (await _stamp()).readAsString()) as Map;
      final ok = st['sha256'] == await _sha256(exe);
      if (ok) _checkedSig = sig;
      return ok;
    } catch (_) {
      return false;
    }
  }

  static String? _checkedSig;

  static Future<String?> installedVersion() async {
    try {
      final st = jsonDecode(await (await _stamp()).readAsString()) as Map;
      return '${st['version']}';
    } catch (_) {
      return null;
    }
  }

  // ───────────── التثبيت ─────────────

  static bool _installing = false;

  /// ينزّل simplex-chat.exe الرسمي ويطابق بصمته. [step]: نص الخطوة ونسبة التقدّم.
  static Future<void> install({void Function(String text, [double? progress])? step}) async {
    if (!supported) throw SimplexException('SimpleX متاح حالياً على Windows فقط');
    if (_installing) throw SimplexException('التثبيت جارٍ بالفعل');
    _installing = true;
    void s(String t, [double? f]) {
      _add(t);
      step?.call(t, f);
    }

    try {
      final bin = Directory(p.join(await root(), 'bin'));
      await bin.create(recursive: true);
      s('قراءة بصمة الملف من إصدار SimpleX الرسمي ($version)…');
      final want = await _officialHash();
      if (want == null) {
        throw SimplexException('تعذّر قراءة بصمة الملف من GitHub — لا يُنزَّل ملف لا يمكن التحقق منه. أعد المحاولة بعد قليل');
      }
      final tmp = File(p.join(bin.path, 'download.part.exe'));
      if (await tmp.exists()) await tmp.delete(); // بقايا محاولة سابقة
      s('تنزيل محرك SimpleX (مرة واحدة)…', 0);
      await _download(_downloadUrl, tmp, (f) => s('تنزيل محرك SimpleX…', f));
      final got = await _sha256(tmp);
      if (got != want) {
        try {
          await tmp.delete();
        } catch (_) {}
        throw SimplexException('بصمة الملف المنزَّل لا تطابق الإصدار الرسمي — حُذف ولم يُشغَّل. أعد المحاولة');
      }
      final exe = File(await _exe());
      if (await exe.exists() && await _sha256(exe) == got) {
        // الملف المثبّت هو نفسه ⇒ لا إيقاف ولا استبدال (كان يوقف المحرك ثم يفشل الحذف
        // لأن Windows لا يسمح بحذف ملف ما زال قيد التشغيل، فيبقى download.part.exe معلّقاً)
        await tmp.delete();
      } else {
        await stop(); // ملف قديم قد يكون قيد التشغيل
        await _deleteWhenFree(exe);
        await tmp.rename(exe.path);
      }
      _checkedSig = null;
      await (await _stamp()).writeAsString(jsonEncode({'version': version, 'sha256': got, 'at': DateTime.now().toIso8601String()}));
      s('تم تثبيت محرك SimpleX $version');
    } finally {
      _installing = false;
    }
  }

  /// Windows يُبقي الملف مقفلاً لحظات بعد إيقاف العملية: محاولات حذف لمدة 10 ثوانٍ.
  static Future<void> _deleteWhenFree(File f) async {
    for (var i = 0; i < 20; i++) {
      try {
        if (await f.exists()) await f.delete();
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw SimplexException('ملف المحرك القديم ما زال قيد الاستعمال — أغلق البرنامج وافتحه ثم أعد المحاولة');
  }

  /// البصمة من بيانات الإصدار: حقل digest للملف، وإلا سطر SHA2-256 في وصف الإصدار.
  static Future<String?> _officialHash() async {
    final j = jsonDecode(await _getText(_releaseApi, headers: {'accept': 'application/vnd.github+json'}));
    if (j is! Map) return null;
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map && a['name'] == _asset) {
        final d = a['digest'];
        if (d is String && RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(d)) return d.substring(7);
      }
    }
    return hashFromReleaseBody('${j['body'] ?? ''}', _asset);
  }

  /// سطر مثل «SHA2-256(simplex-chat-windows-x86-64)= ab12…» في وصف الإصدار.
  @visibleForTesting
  static String? hashFromReleaseBody(String body, String asset) {
    for (final line in const LineSplitter().convert(body)) {
      if (!line.contains('($asset)')) continue;
      final m = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(line);
      if (m != null) return m.group(0)!.toLowerCase();
    }
    return null;
  }

  static Future<String> _sha256(File f) async => (await sha256.bind(f.openRead()).first).toString();

  // ───────────── التشغيل ─────────────

  static Future<int>? _starting;
  static Process? _proc;
  static int? _port;

  /// يشغّل المحرك إن لم يكن يعمل ويعيد منفذه. آمن للاستدعاء المتكرر.
  static Future<int> ensureRunning() {
    return _starting ??= _ensure().whenComplete(() => _starting = null);
  }

  static Future<int> _ensure() async {
    if (!supported) throw SimplexException('SimpleX متاح حالياً على Windows فقط');
    if (!await isInstalled()) throw SimplexException('محرك SimpleX غير مثبّت — من إعدادات SimpleX اضغط «تثبيت المحرك»');

    // 1) يعمل من هذه الجلسة أو من جلسة سابقة؟ يُعاد استعماله فقط إن أمكن تشغيل الوسيط
    //    على المنفذ نفسه الذي بدأ المحرك به (وإلا لن يصل المحرك إلى أي خادم).
    final run = await _readRun();
    final known = _port ?? run?.$2;
    if (known != null && await _reachable(known)) {
      final want = run?.$3;
      if (want != null && await SimplexSocks.start(preferPort: want) == want) {
        _port = known;
        return known;
      }
      _add('المحرك الشغّال بدأ بلا الوسيط الحالي — إعادة تشغيله');
    }
    await _killStale();

    // 2) تشغيل جديد على منفذ محلي فارغ
    final port = await _freePort();
    final exe = await _exe();
    final prefix = await _dbPrefix();
    await Directory(p.dirname(prefix)).create(recursive: true);
    final files = await filesDir();
    await Directory(files).create(recursive: true);
    final key = await _dbKey();
    // 🧭 وسيط DNS: شبكات تحجب أسماء خوادم SimpleX في DNS (جواب 0.0.0.0) — انظر simplex_socks.dart
    final socks = await SimplexSocks.start();

    _add('تشغيل المحرك على 127.0.0.1:$port (الوسيط على $socks)');
    final proc = await Process.start(
      exe,
      [
        '-p', '$port',
        '-d', prefix,
        '-k', key,
        '-y', // ترقية قاعدة SimpleX تلقائياً عند تحديث نسخته
        '--create-bot-display-name', botName, // أول تشغيل فقط (يُتجاهل إن وُجد الحساب)
        '--create-bot-allow-files',
        '--files-folder', files,
        '--device-name', 'Alnaser',
        // مهلة الاتصال بخوادم SimpleX: الافتراضي 7 ثوانٍ قصير على إنترنت بطيء (TIMEOUT)
        '--tcp-timeout', '30',
        '--socks-proxy', '127.0.0.1:$socks',
        '--host-mode', 'public', // عناوين الخوادم العادية (لا عناوين .onion — الوسيط ليس Tor)
      ],
      workingDirectory: await root(),
      // detachedWithStdio: بلا نافذة سوداء، والمخرجات تُقرأ دائماً (لو لم تُقرأ لامتلأت فتوقف)
      mode: ProcessStartMode.detachedWithStdio,
    );
    _proc = proc;
    final lf = File(await logFile());
    try {
      if (await lf.exists() && await lf.length() > 1024 * 1024) await lf.rename('${lf.path}.old');
    } catch (_) {}
    final sink = lf.openWrite(mode: FileMode.append);
    final early = <String>[];
    var open = 2; // stdout + stderr: يُغلق الملف بعد انتهاء الاثنين
    void take(String chunk) {
      // لا يُكتب مفتاح القاعدة في السجل أبداً (للاحتياط إن طبعه البرنامج)
      final safe = chunk.replaceAll(key, '***');
      try {
        sink.write(safe);
      } catch (_) {}
      if (early.length < 40) early.addAll(const LineSplitter().convert(safe));
    }

    void closed() {
      if (--open == 0) sink.close().catchError((_) {});
    }

    proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(take, onError: (_) {}, onDone: closed);
    proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(take, onError: (_) {}, onDone: closed);
    await (await _runFile()).writeAsString(jsonEncode({'pid': proc.pid, 'port': port, 'socks': socks}));

    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await _reachable(port)) {
        _port = port;
        _add('المحرك يعمل');
        return port;
      }
    }
    try {
      Process.killPid(proc.pid);
    } catch (_) {}
    _proc = null;
    final tail = early.where((l) => l.trim().isNotEmpty).toList();
    final last = tail.length > 6 ? tail.sublist(tail.length - 6) : tail;
    final dbErr = last.any((l) => l.contains('Error opening database'));
    throw SimplexException(dbErr
        ? 'تعذّر فتح قاعدة SimpleX على هذه الحاسبة (مفتاحها تغيّر أو الملف تالف). من إعدادات SimpleX استعمل «إعادة الضبط» ثم اربط هاتفك من جديد.'
        : 'محرك SimpleX لم يبدأ خلال 30 ثانية.${last.isEmpty ? '' : '\n${last.join('\n')}'}');
  }

  /// منفذ المحرك إن كان يعمل الآن (بلا تشغيل).
  static Future<int?> runningPort() async {
    final known = _port ?? (await _readRun())?.$2;
    if (known != null && await _reachable(known)) return known;
    return null;
  }

  /// يوقف المحرك (العملية التي شغّلناها نحن فقط).
  static Future<void> stop() async {
    final run = await _readRun();
    final pid = _proc?.pid ?? run?.$1;
    _port = null;
    _proc = null;
    await SimplexSocks.stop();
    if (pid != null && await _isOurProcess(pid)) {
      try {
        Process.killPid(pid);
        _add('أُوقف المحرك');
      } catch (_) {}
    }
    try {
      final f = await _runFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// إعادة ضبط كاملة: يحذف حساب البوت وجهات الاتصال (يلزم ربط الهاتف من جديد).
  /// الملف التنفيذي يبقى (لا تنزيل جديد).
  static Future<void> reset() async {
    await stop();
    await Future.delayed(const Duration(milliseconds: 600));
    final data = Directory(p.dirname(await _dbPrefix()));
    if (await data.exists()) await data.delete(recursive: true);
    final files = Directory(await filesDir());
    if (await files.exists()) await files.delete(recursive: true);
    await _secure.delete(key: _kDbKey);
    _add('أُعيد ضبط SimpleX');
  }

  // ───────────── أدوات ─────────────

  /// (رقم العملية، منفذ المحرك، منفذ الوسيط)
  static Future<(int, int, int?)?> _readRun() async {
    try {
      final f = await _runFile();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map;
      return ((j['pid'] as num).toInt(), (j['port'] as num).toInt(), (j['socks'] as num?)?.toInt());
    } catch (_) {
      return null;
    }
  }

  static Future<void> _killStale() async {
    final run = await _readRun();
    if (run == null) return;
    if (await _isOurProcess(run.$1)) {
      _add('محرك سابق لا يستجيب — إغلاقه');
      try {
        Process.killPid(run.$1);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 800));
    }
    try {
      await (await _runFile()).delete();
    } catch (_) {}
  }

  /// العملية [pid] هي simplex-chat.exe فعلاً؟ (رقم عملية قديم قد يُعاد لبرنامج آخر)
  static Future<bool> _isOurProcess(int pid) async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
      return '${r.stdout}'.toLowerCase().contains(_exeName);
    } catch (_) {
      return false;
    }
  }

  /// اتصال TCP فقط (لا WebSocket): المحرك يوزّع أحداثه على كل عملائه، فعميل فحص
  /// مؤقت قد «يأخذ» حدث اكتمال رفع ملف من العميل الحقيقي.
  static Future<bool> _reachable(int port) async {
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 2));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  static Future<String> _dbKey() async {
    final k = await _secure.read(key: _kDbKey);
    if (k != null && k.length >= 32) return k;
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    final n = List.generate(40, (_) => chars[r.nextInt(chars.length)]).join();
    await _secure.write(key: _kDbKey, value: n);
    return n;
  }

  /// للاستعمال من محركات أخرى (محرك MTProto): نفس التنزيل الآمن.
  static Future<String> fetchText(String u, {Map<String, String>? headers}) => _getText(u, headers: headers);
  static Future<void> fetchFile(String u, File out, void Function(double) progress) => _download(u, out, progress);

  // ───────────── تنزيل يتحمّل شهادات Windows ─────────────
  // (الطريقة نفسها المستعملة لتنزيل Node.js لخادم واتساب: عند خطأ شهادة الجذر فقط
  //  يُعاد الطلب بأداة Windows — curl.exe ثم PowerShell — والتحقق من الشهادة لا يُطفأ أبداً.
  //  وفي كل الحالات تُطابق البصمة بعد التنزيل.)

  static bool _isCertError(Object e) =>
      e is TlsException || '$e'.contains('CERTIFICATE_VERIFY_FAILED') || '$e'.contains('HandshakeException');

  static Future<String> _getText(String u, {Map<String, String>? headers}) async {
    try {
      final r = await http.get(Uri.parse(u), headers: headers).timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) throw SimplexException('تعذّر القراءة (HTTP ${r.statusCode}): $u');
      return utf8.decode(r.bodyBytes);
    } on SocketException catch (e) {
      throw SimplexException('لا إنترنت أو الموقع محجوب: ${e.message}');
    } on TimeoutException {
      throw SimplexException('انتهت المهلة: $u');
    } catch (e) {
      if (!_isCertError(e) || !Platform.isWindows) rethrow;
      final tmp = File(p.join(await root(), 'fetch_${DateTime.now().microsecondsSinceEpoch}.txt'));
      try {
        await _winFetch(u, tmp, headers: headers);
        return utf8.decode(await tmp.readAsBytes());
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    }
  }

  static Future<void> _download(String u, File out, void Function(double) progress) async {
    try {
      await _downloadDart(u, out, progress);
    } catch (e) {
      if (!_isCertError(e) || !Platform.isWindows) rethrow;
      _add('شهادة الموقع لم تُقبل — إعادة التنزيل بأداة Windows');
      await _winFetch(u, out);
    }
  }

  static Future<void> _downloadDart(String u, File out, void Function(double) progress) async {
    final part = File('${out.path}.tmp');
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final res = await (await c.getUrl(Uri.parse(u))).close(); // يتبع التحويلات (GitHub)
      if (res.statusCode != 200) throw SimplexException('تعذّر التنزيل (HTTP ${res.statusCode})');
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
      if (total > 0 && got != total) throw SimplexException('انقطع التنزيل — أعد المحاولة');
      if (await out.exists()) await out.delete();
      await part.rename(out.path);
    } on SocketException catch (e) {
      throw SimplexException('لا إنترنت أو الموقع محجوب: ${e.message}');
    } on TimeoutException {
      throw SimplexException('توقف التنزيل (الإنترنت بطيء أو انقطع) — أعد المحاولة');
    } finally {
      c.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> _winFetch(String u, File out, {Map<String, String>? headers}) async {
    final part = File('${out.path}.tmp');
    if (await part.exists()) await part.delete();
    final sys = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final curl = p.join(sys, 'System32', 'curl.exe');
    final errors = <String>[];
    if (await File(curl).exists()) {
      final r = await Process.run(curl, [
        '-fsSL', '--retry', '2', '--connect-timeout', '30', '--max-time', '1800',
        for (final h in (headers ?? const <String, String>{}).entries) ...['-H', '${h.key}: ${h.value}'],
        '-o', part.path, u,
      ]);
      if (r.exitCode == 0 && await part.exists()) {
        if (await out.exists()) await out.delete();
        await part.rename(out.path);
        return;
      }
      errors.add('curl ${r.exitCode}: ${'${r.stderr}'.trim()}');
    }
    String q(String v) => "'${v.replaceAll("'", "''")}'";
    final hdr = (headers ?? const <String, String>{}).entries.map((h) => '${q(h.key)}=${q(h.value)}').join(';');
    final r = await Process.run('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command',
      "\$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; "
          'Invoke-WebRequest -UseBasicParsing -Uri ${q(u)} -OutFile ${q(part.path)} -Headers @{$hdr}',
    ]);
    if (r.exitCode == 0 && await part.exists()) {
      if (await out.exists()) await out.delete();
      await part.rename(out.path);
      return;
    }
    if (await part.exists()) await part.delete();
    errors.add('PowerShell ${r.exitCode}: ${'${r.stderr}'.trim()}');
    throw SimplexException('تعذّر الاتصال الآمن بـ ${Uri.parse(u).host}. افتحه في المتصفح مرة ثم أعد المحاولة، '
        'أو تأكد من تاريخ الحاسبة وساعتها. (${errors.join(' | ')})');
  }
}
