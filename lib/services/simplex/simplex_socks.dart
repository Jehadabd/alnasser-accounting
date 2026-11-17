// lib/services/simplex/simplex_socks.dart
//
// 🧭 وسيط محلي لمحرك SimpleX يتجاوز حجب DNS.
//
// المشكلة (مقيسة على شبكة المحل): DNS المزوّد يُرجع 0.0.0.0 لخوادم SimpleX، وطلبات DNS
// العادية إلى 1.1.1.1/8.8.8.8 لا ترجع أصلاً — لكن DNS المشفّر عبر HTTPS (DoH) يعطي
// العنوان الحقيقي، والاتصال بذلك العنوان ينجح.
//
// الحل: المحرك يتصل عبر وسيط SOCKS5 داخل البرنامج (127.0.0.1 فقط). الوسيط يحل اسم
// الخادم عبر DoH (Cloudflare ثم Google ثم DNS النظام إن لم يكن مزيّفاً) ويوصل الاتصال
// كما هو. لا يُطفأ أي تشفير: اتصال المحرك بالخادم مشفّر من طرف إلى طرف وهويّة الخادم
// يتحقق منها المحرك ببصمته — الوسيط لا يرى إلا بايتات مشفّرة.
//
// يقبل المنفذين 443 و5223 فقط (منافذ خوادم SimpleX) — لا يصلح وسيطاً عاماً لبرامج أخرى.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;

class SimplexSocks {
  SimplexSocks._();

  static ServerSocket? _server;
  static int? get port => _server?.port;
  static bool get running => _server != null;

  /// يشغّل الوسيط (على [preferPort] إن أمكن — ليبقى المحرك الشغّال من جلسة سابقة صالحاً).
  static Future<int> start({int? preferPort}) async {
    final s0 = _server;
    if (s0 != null) return s0.port;
    ServerSocket s;
    try {
      s = await ServerSocket.bind(InternetAddress.loopbackIPv4, preferPort ?? 0);
    } on SocketException {
      if (preferPort == null) rethrow;
      s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    }
    _server = s;
    s.listen((c) => _Session(c).run(), onError: (_) {});
    return s.port;
  }

  static Future<void> stop() async {
    final s = _server;
    _server = null;
    try {
      await s?.close();
    } catch (_) {}
  }

  static const allowedPorts = {443, 5223};
}

/// حل أسماء خوادم SimpleX بلا DNS المزوّد.
class SimplexDns {
  SimplexDns._();

  static final _cache = <String, (String, DateTime)>{};

  static Future<String> resolve(String host) async {
    if (InternetAddress.tryParse(host) != null) return host;
    if (!validHost(host)) throw SocketException('اسم خادم غير صالح: $host');
    final c = _cache[host];
    if (c != null && DateTime.now().isBefore(c.$2)) return c.$1;

    for (final u in [
      'https://cloudflare-dns.com/dns-query?name=${Uri.encodeQueryComponent(host)}&type=A',
      'https://dns.google/resolve?name=${Uri.encodeQueryComponent(host)}&type=A',
      'https://1.1.1.1/dns-query?name=${Uri.encodeQueryComponent(host)}&type=A',
    ]) {
      try {
        final r = await http.get(Uri.parse(u), headers: {'accept': 'application/dns-json'}).timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) continue;
        final ip = ipFromDohJson(utf8.decode(r.bodyBytes));
        if (ip != null) {
          _cache[host] = (ip, DateTime.now().add(const Duration(minutes: 10)));
          return ip;
        }
      } catch (e) {
        debugPrint('SimpleX DoH: $u → $e');
      }
    }
    // آخر حل: DNS النظام — إن لم يكن الجواب مزيّفاً (0.0.0.0 / 127.x)
    try {
      for (final a in await InternetAddress.lookup(host, type: InternetAddressType.IPv4)) {
        if (!isSinkhole(a.address)) return a.address;
      }
    } catch (_) {}
    throw SocketException('تعذّر معرفة عنوان $host (DNS محجوب ولم يرد DNS المشفّر)');
  }

  /// أول عنوان IPv4 حقيقي من جواب DoH بصيغة JSON (type 1 = A).
  @visibleForTesting
  static String? ipFromDohJson(String body) {
    final j = jsonDecode(body);
    if (j is! Map) return null;
    for (final a in (j['Answer'] as List? ?? const [])) {
      if (a is Map && a['type'] == 1 && a['data'] is String) {
        final ip = a['data'] as String;
        if (InternetAddress.tryParse(ip)?.type == InternetAddressType.IPv4 && !isSinkhole(ip)) return ip;
      }
    }
    return null;
  }

  /// جواب «ممنوع» المزيّف الذي تعيده شبكات الحجب.
  @visibleForTesting
  static bool isSinkhole(String ip) => ip == '0.0.0.0' || ip.startsWith('127.') || ip.startsWith('0.');

  @visibleForTesting
  static bool validHost(String h) => h.length <= 253 && RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(h);
}

/// جلسة SOCKS5 واحدة (CONNECT فقط، بلا مصادقة أو باسم/كلمة سر يُقبلان كما هما:
/// المحرك يرسل اسماً وكلمة سر عشوائيين لعزل الاتصالات عن بعضها).
class _Session {
  _Session(this.c);
  final Socket c;
  final _buf = <int>[];
  Completer<void>? _wait;
  StreamSubscription<Uint8List>? _sub;
  Socket? _remote;
  bool _closed = false;
  bool _requested = false;

  Future<void> run() async {
    _sub = c.listen((d) {
      final r = _remote;
      if (r != null) {
        try {
          r.add(d);
        } catch (_) {
          _close();
        }
        return;
      }
      _buf.addAll(d);
      final w = _wait;
      _wait = null;
      w?.complete();
    }, onDone: _close, onError: (_) => _close(), cancelOnError: true);

    try {
      final g = await _read(2);
      if (g[0] != 5) {
        _close();
        return;
      }
      final methods = await _read(g[1]);
      if (methods.contains(0)) {
        c.add([5, 0]);
      } else if (methods.contains(2)) {
        c.add([5, 2]);
        final v = await _read(2); // VER ULEN
        await _read(v[1]);
        final pl = await _read(1);
        await _read(pl[0]);
        c.add([1, 0]);
      } else {
        c.add([5, 0xFF]);
        _close();
        return;
      }

      final h = await _read(4); // VER CMD RSV ATYP
      _requested = true;
      if (h[0] != 5 || h[1] != 1) {
        _fail(7);
        return;
      } // CONNECT فقط
      final String host;
      switch (h[3]) {
        case 1:
          host = (await _read(4)).join('.');
        case 3:
          final l = await _read(1);
          host = ascii.decode(await _read(l[0]), allowInvalid: true);
        case 4:
          host = InternetAddress.fromRawAddress(Uint8List.fromList(await _read(16))).address;
        default:
          _fail(8);
          return;
      }
      final pb = await _read(2);
      final port = (pb[0] << 8) | pb[1];
      if (!SimplexSocks.allowedPorts.contains(port)) {
        _fail(2);
        return;
      } // ممنوع بالقاعدة

      final ip = await SimplexDns.resolve(host);
      final r = await Socket.connect(ip, port, timeout: const Duration(seconds: 25));
      if (_closed) {
        r.destroy();
        return;
      }
      c.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      final pending = List<int>.of(_buf);
      _buf.clear();
      if (pending.isNotEmpty) r.add(pending);
      _remote = r;
      r.listen((d) {
        if (_closed) return;
        try {
          c.add(d);
        } catch (_) {
          _close();
        }
      }, onDone: _close, onError: (_) => _close(), cancelOnError: true);
    } catch (e) {
      debugPrint('SimpleX SOCKS: $e');
      _fail(4);
    }
  }

  Future<List<int>> _read(int n) async {
    while (_buf.length < n) {
      if (_closed) throw const SocketException('أُغلق الاتصال');
      final w = Completer<void>();
      _wait = w;
      await w.future;
    }
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  void _fail(int code) {
    if (_requested && !_closed) {
      try {
        c.add([5, code, 0, 1, 0, 0, 0, 0, 0, 0]);
      } catch (_) {}
    }
    _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.completeError(const SocketException('أُغلق الاتصال'));
    _sub?.cancel();
    try {
      c.destroy();
    } catch (_) {}
    try {
      _remote?.destroy();
    } catch (_) {}
  }
}

// ═══════════════ وسيط تنزيل يتجاوز حجب DNS (HTTP CONNECT) ═══════════════
//
// لتنزيل المحركات (Tor / TDLib / SimpleX) حين يحجب DNS المزوّد المواقع الرسمية (مقيس: 
// torproject.org يفشل في DNS المزوّد، وعناوينه الحقيقية من DoH تتصل). HttpClient يطلب
// CONNECT من هذا الوسيط، فيحل الاسم عبر DoH ويتصل مباشرة. TLS والتحقق من الشهادة بين
// البرنامج والموقع نفسه كما هما. يقبل مواقع التنزيل الرسمية على المنفذ 443 فقط.

class DohConnectProxy {
  DohConnectProxy._();

  static ServerSocket? _server;

  static const allowedSuffixes = [
    'torproject.org',
    'api.nuget.org',
    'github.com',
    'githubusercontent.com',
    'simplex.chat',
  ];

  @visibleForTesting
  static bool allowed(String host, int port) {
    final h = host.toLowerCase();
    return port == 443 && allowedSuffixes.any((s) => h == s || h.endsWith('.$s'));
  }

  static Future<int> start() async {
    final s0 = _server;
    if (s0 != null) return s0.port;
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen((c) => _HttpConnectSession(c).run(), onError: (_) {});
    return s.port;
  }
}

class _HttpConnectSession {
  _HttpConnectSession(this.c);
  final Socket c;
  final _buf = <int>[];
  Completer<void>? _wait;
  StreamSubscription<Uint8List>? _sub;
  Socket? _remote;
  bool _closed = false;

  Future<void> run() async {
    _sub = c.listen((d) {
      final r = _remote;
      if (r != null) {
        try {
          r.add(d);
        } catch (_) {
          _close();
        }
        return;
      }
      _buf.addAll(d);
      final w = _wait;
      _wait = null;
      w?.complete();
    }, onDone: _close, onError: (_) => _close(), cancelOnError: true);
    try {
      int end;
      while ((end = _headEnd()) < 0) {
        if (_buf.length > 8192 || _closed) {
          _close();
          return;
        }
        final w = Completer<void>();
        _wait = w;
        await w.future;
      }
      final first = latin1.decode(_buf.sublist(0, end)).split('\r\n').first.split(' ');
      _buf.removeRange(0, end + 4);
      final target = first.length >= 2 && first[0].toUpperCase() == 'CONNECT' ? first[1] : '';
      final colon = target.lastIndexOf(':');
      final host = colon > 0 ? target.substring(0, colon) : '';
      final port = colon > 0 ? int.tryParse(target.substring(colon + 1)) ?? 0 : 0;
      if (!DohConnectProxy.allowed(host, port)) {
        _reply('403 Forbidden');
        return;
      }
      final ip = await SimplexDns.resolve(host);
      final r = await Socket.connect(ip, port, timeout: const Duration(seconds: 25));
      if (_closed) {
        r.destroy();
        return;
      }
      c.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
      final pending = List<int>.of(_buf);
      _buf.clear();
      if (pending.isNotEmpty) r.add(pending);
      _remote = r;
      r.listen((d) {
        if (_closed) return;
        try {
          c.add(d);
        } catch (_) {
          _close();
        }
      }, onDone: _close, onError: (_) => _close(), cancelOnError: true);
    } catch (e) {
      debugPrint('DoH proxy: $e');
      _reply('502 Bad Gateway');
    }
  }

  int _headEnd() {
    for (var i = 0; i + 3 < _buf.length; i++) {
      if (_buf[i] == 13 && _buf[i + 1] == 10 && _buf[i + 2] == 13 && _buf[i + 3] == 10) return i;
    }
    return -1;
  }

  void _reply(String status) {
    try {
      c.add(latin1.encode('HTTP/1.1 $status\r\nContent-Length: 0\r\n\r\n'));
    } catch (_) {}
    Future<void>.delayed(const Duration(milliseconds: 200), _close);
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.complete();
    _sub?.cancel();
    try {
      c.destroy();
    } catch (_) {}
    try {
      _remote?.destroy();
    } catch (_) {}
  }
}
