// lib/services/telegram_net/telegram_proxy.dart
//
// 🧦 رفع تيليجرام عبر بروكسي (عند حظر تيليجرام) — إضافة، الطريقة المباشرة باقية كما هي.
//
// • مطفأ ⇒ HttpClient عادي (السلوك السابق تماماً).
// • SOCKS5 (من قنوات تيليجرام أو برنامج VPN مثل v2rayN على 127.0.0.1:10808):
//   Dart لا يتكلم SOCKS، فجسر صغير داخل البرنامج (127.0.0.1 فقط) يستقبل طلب HTTP CONNECT
//   من HttpClient ويفتح الاتصال عبر بروكسي SOCKS5. اسم الخادم يُرسل للبروكسي (لا يُحل محلياً)،
//   فحجب DNS لا يؤثر.
// • HTTP (برنامج VPN على 127.0.0.1:10809): يُعطى لـ HttpClient مباشرة.
//
// 🔒 في كل الحالات التشفير (TLS) من البرنامج إلى api.telegram.org نفسه، والتحقق من شهادته
// كامل: البروكسي يرى أنك تتصل بتيليجرام فقط، ولا يقرأ توكن البوت ولا الملفات.
// الجسر يقبل نطاقات telegram.org على المنفذ 443 فقط — لا يصلح وسيطاً عاماً.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tor_engine.dart';

enum TgProxyType { socks5, http }

class TgProxyConfig {
  const TgProxyConfig({required this.type, required this.host, required this.port, this.user, this.pass});
  final TgProxyType type;
  final String host;
  final int port;
  final String? user;
  final String? pass;

  bool get hasAuth => (user ?? '').isNotEmpty;
  String get label => '${type == TgProxyType.socks5 ? 'SOCKS5' : 'HTTP'} $host:$port';

  @override
  bool operator ==(Object o) =>
      o is TgProxyConfig && o.type == type && o.host == host && o.port == port && o.user == user && o.pass == pass;
  @override
  int get hashCode => Object.hash(type, host, port, user, pass);
}

class TelegramProxy {
  TelegramProxy._();

  static const _kEnabled = 'tg_proxy_enabled';
  static const _kType = 'tg_proxy_type';
  static const _kHost = 'tg_proxy_host';
  static const _kPort = 'tg_proxy_port';
  static const _kUser = 'tg_proxy_user';
  static const _kPass = 'tg_proxy_pass'; // في المخزن الآمن
  static const _secure = FlutterSecureStorage();

  // ───────────── الإعداد ─────────────

  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  static Future<TgProxyConfig?> saved() async {
    final p = await SharedPreferences.getInstance();
    final host = p.getString(_kHost);
    final port = p.getInt(_kPort);
    if (host == null || port == null) return null;
    String? pass;
    try {
      pass = await _secure.read(key: _kPass);
    } catch (_) {}
    return TgProxyConfig(
      type: p.getString(_kType) == 'http' ? TgProxyType.http : TgProxyType.socks5,
      host: host,
      port: port,
      user: p.getString(_kUser),
      pass: pass,
    );
  }

  /// البروكسي الفعّال الآن (مفعّل ومحفوظ)، أو null للاتصال المباشر.
  static Future<TgProxyConfig?> active() async => await isEnabled() ? saved() : null;

  static Future<void> save(TgProxyConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kType, c.type == TgProxyType.http ? 'http' : 'socks5');
    await p.setString(_kHost, c.host);
    await p.setInt(_kPort, c.port);
    if (c.hasAuth) {
      await p.setString(_kUser, c.user!);
      await _secure.write(key: _kPass, value: c.pass ?? '');
    } else {
      await p.remove(_kUser);
      await _secure.delete(key: _kPass);
    }
  }

  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, v);

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [_kEnabled, _kType, _kHost, _kPort, _kUser]) {
      await p.remove(k);
    }
    await _secure.delete(key: _kPass);
    await _Bridge.stop();
  }

  /// يفهم ما يُلصق من القنوات وبرامج VPN:
  ///   tg://socks?server=…&port=…&user=…&pass=…   https://t.me/socks?server=…
  ///   socks5://user:pass@host:port   socks5h://…   http://host:port   host:port
  @visibleForTesting
  static TgProxyConfig? parse(String input, {TgProxyType fallback = TgProxyType.socks5}) {
    final s = input.trim();
    if (s.isEmpty) return null;
    Uri? u;
    try {
      u = Uri.parse(s);
    } catch (_) {}
    if (u != null && (u.scheme == 'tg' || (u.host == 't.me' || u.host == 'telegram.me'))) {
      final kind = u.scheme == 'tg' ? u.host : (u.pathSegments.isEmpty ? '' : u.pathSegments.first);
      if (kind != 'socks') return null; // proxy?secret= هو MTProto — ليس SOCKS
      final q = u.queryParameters;
      final port = int.tryParse(q['port'] ?? '');
      final host = q['server'] ?? '';
      if (host.isEmpty || port == null || !_validPort(port)) return null;
      return TgProxyConfig(type: TgProxyType.socks5, host: host, port: port, user: _nz(q['user']), pass: _nz(q['pass']));
    }
    if (u != null && u.hasScheme && u.host.isNotEmpty) {
      final type = switch (u.scheme) {
        'socks5' || 'socks5h' || 'socks' => TgProxyType.socks5,
        'http' || 'https' => TgProxyType.http,
        _ => null,
      };
      if (type == null || !u.hasPort || !_validPort(u.port)) return null;
      final info = u.userInfo.split(':');
      return TgProxyConfig(
        type: type,
        host: u.host,
        port: u.port,
        user: _nz(info.isNotEmpty ? Uri.decodeComponent(info[0]) : null),
        pass: _nz(info.length > 1 ? Uri.decodeComponent(info.sublist(1).join(':')) : null),
      );
    }
    final m = RegExp(r'^\[?([A-Za-z0-9.\-:]+?)\]?:(\d{1,5})$').firstMatch(s);
    if (m != null) {
      final port = int.parse(m.group(2)!);
      if (!_validPort(port)) return null;
      return TgProxyConfig(type: fallback, host: m.group(1)!, port: port);
    }
    return null;
  }

  /// رابط MTProto (tg://proxy?server=…&secret=…)؟ — يحتاج طريقة الإرسال الثانية لا هذه.
  static bool isMtprotoLink(String s) {
    final t = s.trim();
    return RegExp(r'^(tg://proxy\?|https?://(t|telegram)\.me/proxy\?)', caseSensitive: false).hasMatch(t) && t.contains('secret=');
  }

  static bool _validPort(int p) => p > 0 && p < 65536;
  static String? _nz(String? s) => (s == null || s.isEmpty) ? null : s;

  // ───────────── الاتصال ─────────────

  /// HttpClient لطلبات تيليجرام: مباشر إن كان البروكسي مطفأ (كما كان دائماً).
  static Future<HttpClient> client() async {
    final c = HttpClient();
    // 🧅 Tor التلقائي (إن فُعّل) يسبق البروكسي اليدوي: يُشغَّل هنا إن لم يكن يعمل (مع زر الرفع)
    if (await TorEngine.isActive()) {
      final port = await TorEngine.ensureRunning();
      await configure(c, TgProxyConfig(type: TgProxyType.socks5, host: '127.0.0.1', port: port));
      return c;
    }
    final cfg = await active();
    if (cfg == null) return c;
    await configure(c, cfg);
    return c;
  }

  /// يربط [c] بالبروكسي [cfg] (يُستعمل أيضاً لزر «اختبار» قبل الحفظ).
  static Future<void> configure(HttpClient c, TgProxyConfig cfg) async {
    if (cfg.type == TgProxyType.http) {
      c.findProxy = (_) => 'PROXY ${_hostPort(cfg.host, cfg.port)}';
      if (cfg.hasAuth) {
        c.addProxyCredentials(cfg.host, cfg.port, '', HttpClientBasicCredentials(cfg.user!, cfg.pass ?? ''));
      }
    } else {
      final port = await _Bridge.start(cfg);
      c.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    }
    c.connectionTimeout = const Duration(seconds: 25);
  }

  static String _hostPort(String h, int p) => h.contains(':') ? '[$h]:$p' : '$h:$p';

  /// اختبار: getMe عبر البروكسي [cfg] بالتوكن [token]. يعيد null عند النجاح أو وصف الخطأ.
  static Future<String?> test(TgProxyConfig cfg, String token) async {
    final c = HttpClient();
    try {
      await configure(c, cfg);
      final req = await c.getUrl(Uri.parse('https://api.telegram.org/bot$token/getMe')).timeout(const Duration(seconds: 30));
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200 && body.contains('"ok":true')) return null;
      if (res.statusCode == 401) return 'وصل الطلب إلى تيليجرام لكن توكن البوت غير صحيح';
      return 'رد تيليجرام بالرمز ${res.statusCode}';
    } on TimeoutException {
      return 'انتهت المهلة — البروكسي لا يستجيب أو بطيء جداً';
    } catch (e) {
      return describe(e);
    } finally {
      c.close(force: true);
    }
  }

  static String describe(Object e) {
    final s = '$e';
    if (s.contains('SOCKS')) return s.replaceFirst('SocketException: ', '');
    if (s.contains('Connection refused') || s.contains('errno = 1225')) {
      return 'البروكسي يرفض الاتصال — تأكد من العنوان والمنفذ وأن برنامج الـVPN يعمل';
    }
    if (s.contains('HandshakeException') || s.contains('CERTIFICATE')) {
      return 'فشل التحقق من شهادة تيليجرام — البروكسي يحاول قراءة الاتصال، لا تستعمله';
    }
    return s;
  }
}

// ───────────── جسر HTTP CONNECT → SOCKS5 ─────────────

class _Bridge {
  static ServerSocket? _server;
  static TgProxyConfig? _cfg;

  static Future<int> start(TgProxyConfig cfg) async {
    _cfg = cfg; // الجلسات الجديدة تأخذ آخر إعداد
    final s = _server;
    if (s != null) return s.port;
    final n = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = n;
    n.listen((c) => _BridgeSession(c).run(), onError: (_) {});
    return n.port;
  }

  static Future<void> stop() async {
    final s = _server;
    _server = null;
    try {
      await s?.close();
    } catch (_) {}
  }
}

/// القواعد: نطاقات تيليجرام فقط على 443.
@visibleForTesting
bool telegramTargetAllowed(String host, int port) {
  final h = host.toLowerCase();
  return port == 443 && (h == 'telegram.org' || h.endsWith('.telegram.org'));
}

/// اتصال يُقرأ بأطوال محددة ثم يتحول إلى تمرير خام.
class _Pipe {
  _Pipe(this.s) {
    _sub = s.listen((d) {
      final o = _other;
      if (o != null) {
        try {
          o.add(d);
        } catch (_) {
          onClose?.call();
        }
        return;
      }
      _buf.addAll(d);
      final w = _wait;
      _wait = null;
      w?.complete();
    }, onDone: () => onClose?.call(), onError: (_) => onClose?.call(), cancelOnError: true);
  }

  final Socket s;
  late final StreamSubscription<List<int>> _sub;
  final _buf = <int>[];
  Completer<void>? _wait;
  Socket? _other;
  bool closed = false;
  void Function()? onClose;

  Future<void> _more() async {
    if (closed) throw const SocketException('أُغلق الاتصال');
    final w = Completer<void>();
    _wait = w;
    await w.future;
  }

  Future<List<int>> read(int n) async {
    while (_buf.length < n) {
      await _more();
    }
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  /// يقرأ حتى نهاية رأس HTTP (حد 8 كيلو).
  Future<String> readHead() async {
    while (true) {
      final i = _indexOf(_buf, const [13, 10, 13, 10]);
      if (i >= 0) {
        final head = latin1.decode(_buf.sublist(0, i));
        _buf.removeRange(0, i + 4);
        return head;
      }
      if (_buf.length > 8192) throw const SocketException('رأس طلب طويل');
      await _more();
    }
  }

  /// تحويل إلى تمرير: ما تبقى في المخزن يُرسل أولاً.
  void pipeTo(Socket other) {
    final pending = List<int>.of(_buf);
    _buf.clear();
    if (pending.isNotEmpty) other.add(pending);
    _other = other;
  }

  void close() {
    if (closed) return;
    closed = true;
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.completeError(const SocketException('أُغلق الاتصال'));
    _sub.cancel();
    try {
      s.destroy();
    } catch (_) {}
  }

  static int _indexOf(List<int> a, List<int> p) {
    outer:
    for (var i = 0; i + p.length <= a.length; i++) {
      for (var j = 0; j < p.length; j++) {
        if (a[i + j] != p[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

class _BridgeSession {
  _BridgeSession(Socket c) : client = _Pipe(c);
  final _Pipe client;
  _Pipe? upstream;

  void _closeAll() {
    client.close();
    upstream?.close();
  }

  Future<void> run() async {
    client.onClose = _closeAll;
    try {
      final head = await client.readHead();
      final first = head.split('\r\n').first.split(' ');
      if (first.length < 2 || first[0].toUpperCase() != 'CONNECT') {
        _reply(405, 'Method Not Allowed');
        return;
      }
      final target = first[1];
      final colon = target.lastIndexOf(':');
      final host = colon > 0 ? target.substring(0, colon) : target;
      final port = colon > 0 ? int.tryParse(target.substring(colon + 1)) ?? 0 : 0;
      if (!telegramTargetAllowed(host, port)) {
        _reply(403, 'Forbidden');
        return;
      }

      final cfg = _Bridge._cfg;
      if (cfg == null) {
        _reply(502, 'Bad Gateway');
        return;
      }
      final raw = await Socket.connect(cfg.host, cfg.port, timeout: const Duration(seconds: 20));
      final up = _Pipe(raw);
      upstream = up;
      up.onClose = _closeAll;
      await socks5Connect(up.read, raw.add, host, port, user: cfg.user, pass: cfg.pass);

      client.s.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
      client.pipeTo(raw);
      up.pipeTo(client.s);
    } catch (e) {
      debugPrint('Telegram proxy bridge: $e');
      final msg = TelegramProxy.describe(e).replaceAll(RegExp(r'[\r\n]'), ' ');
      _reply(502, 'Bad Gateway', detail: msg);
    }
  }

  void _reply(int code, String text, {String? detail}) {
    try {
      client.s.add(latin1.encode('HTTP/1.1 $code $text\r\nContent-Length: 0\r\n'
          '${detail != null ? 'X-Alnaser-Proxy-Error: ${Uri.encodeComponent(detail)}\r\n' : ''}\r\n'));
    } catch (_) {}
    Future<void>.delayed(const Duration(milliseconds: 200), _closeAll);
  }
}

/// مصافحة SOCKS5 (RFC 1928/1929): CONNECT باسم الخادم (البروكسي يحل الاسم بنفسه).
@visibleForTesting
Future<void> socks5Connect(
  Future<List<int>> Function(int n) read,
  void Function(List<int>) write,
  String host,
  int port, {
  String? user,
  String? pass,
}) async {
  final auth = (user ?? '').isNotEmpty;
  write(auth ? [5, 2, 0, 2] : [5, 1, 0]);
  final g = await read(2);
  if (g[0] != 5) throw const SocketException('SOCKS: هذا ليس بروكسي SOCKS5');
  if (g[1] == 2) {
    if (!auth) throw const SocketException('SOCKS: البروكسي يطلب اسم مستخدم وكلمة سر');
    final u = utf8.encode(user!), p = utf8.encode(pass ?? '');
    if (u.length > 255 || p.length > 255) throw const SocketException('SOCKS: اسم أو كلمة سر طويلة');
    write([1, u.length, ...u, p.length, ...p]);
    final a = await read(2);
    if (a[1] != 0) throw const SocketException('SOCKS: اسم المستخدم أو كلمة السر خطأ');
  } else if (g[1] != 0) {
    throw const SocketException('SOCKS: البروكسي رفض طريقة الدخول');
  }
  final h = utf8.encode(host);
  write([5, 1, 0, 3, h.length, ...h, (port >> 8) & 0xFF, port & 0xFF]);
  final r = await read(4);
  if (r[1] != 0) {
    const reasons = {
      1: 'خطأ عام في البروكسي',
      2: 'البروكسي يمنع هذا الاتصال',
      3: 'الشبكة غير متاحة من البروكسي',
      4: 'تيليجرام غير متاح من البروكسي',
      5: 'رُفض الاتصال',
      6: 'انتهت المهلة',
    };
    throw SocketException('SOCKS: ${reasons[r[1]] ?? 'رفض (${r[1]})'}');
  }
  // عنوان الربط في الرد: نقرؤه ونتجاهله
  final atyp = r[3];
  final n = atyp == 1 ? 4 : atyp == 4 ? 16 : (await read(1))[0];
  await read(n + 2);
}
