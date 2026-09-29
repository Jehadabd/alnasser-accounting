// lib/lan/lan_client.dart
//
// جانب «الطرفية»: مصنع قاعدة بيانات (DatabaseFactory) يرسل كل عمليات sqflite
// إلى حاسبة السيرفر عبر الشبكة المحلية.
//
// الاستخدام في main.dart (وضع الطرفية):
//
//   final conn = LanClientConnection(host: '192.168.1.10', secret: '...');
//   await conn.connect();
//   databaseFactory = createLanDatabaseFactory(conn);
//
// بعد هذا السطر، كل الكود الحالي (DatabaseService والـ DAO والشاشات) يعمل كما
// هو دون أي تعديل — لكن القراءة والكتابة تتم في قاعدة السيرفر.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: implementation_imports
import 'package:sqflite_common/src/mixin/import_mixin.dart'
    show buildDatabaseFactory, SqfliteDatabaseException;
import 'package:sqflite_common/sqlite_api.dart' show DatabaseFactory;

import 'lan_codec.dart';

enum LanLinkState { disconnected, connecting, connected }

class LanClientConnection {
  LanClientConnection({
    required this.host,
    required this.secret,
    this.port = lanDefaultPort,
    this.clientName = 'طرفية',
    this.connectTimeout = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 90),
  });

  final String host;
  final int port;
  final String secret;
  final String clientName;
  final Duration connectTimeout;

  /// أطول من مهلة المعاملة المعلّقة في السيرفر (60 ث) عمداً.
  final Duration requestTimeout;

  WebSocket? _socket;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pending = {};

  /// آخر طلب openDatabase ونتيجته — يُعاد إرساله بعد إعادة الاتصال.
  Object? _lastOpenArgs;
  int? _lastOpenDbId;

  Future<void>? _connecting;

  final _stateController = StreamController<LanLinkState>.broadcast();
  LanLinkState _state = LanLinkState.disconnected;

  /// لشريط «متصل بالسيرفر / يعيد الاتصال» في الواجهة.
  Stream<LanLinkState> get stateStream => _stateController.stream;
  LanLinkState get state => _state;

  void _setState(LanLinkState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  Uri get _uri => Uri(scheme: 'ws', host: host, port: port, path: '/db');

  Future<void> connect() => _connecting ??= _doConnect().whenComplete(() {
        _connecting = null;
      });

  Future<void> _doConnect() async {
    _setState(LanLinkState.connecting);
    try {
      // رمز الربط يُرسل في ترويسة HTTP: أي حرف غير ASCII يعني رمزاً خاطئاً حتماً.
      if (secret.codeUnits.any((c) => c < 32 || c > 126)) {
        throw LanConnectionException('رمز الربط غير صحيح — يتكوّن من أحرف وأرقام إنجليزية فقط');
      }
      final socket = await WebSocket.connect(
        _uri.toString(),
        headers: {
          'x-alnaser-key': secret,
          'x-alnaser-proto': '$lanProtocolVersion',
          'x-alnaser-client': Uri.encodeComponent(clientName),
        },
      ).timeout(connectTimeout);
      socket.pingInterval = const Duration(seconds: 10);

      // ننتظر رسالة الترحيب من السيرفر، أو إغلاقاً برمز يشرح السبب.
      final hello = Completer<void>();
      socket.listen(
        (dynamic data) {
          if (!hello.isCompleted) {
            try {
              final m = jsonDecode(data as String) as Map<String, dynamic>;
              if (m.containsKey('hello')) {
                hello.complete();
                return;
              }
            } catch (_) {}
          }
          _onMessage(data);
        },
        onDone: () {
          if (!hello.isCompleted) {
            hello.completeError(_closeCodeError(socket.closeCode));
          }
          if (identical(_socket, socket)) _onDisconnected();
        },
        onError: (Object e) {
          if (!hello.isCompleted) {
            hello.completeError(LanConnectionException('خطأ اتصال: $e'));
          }
          if (identical(_socket, socket)) _onDisconnected();
        },
        cancelOnError: true,
      );
      try {
        await hello.future.timeout(connectTimeout);
      } catch (_) {
        try {
          await socket.close();
        } catch (_) {}
        rethrow;
      }
      _socket = socket;
      _setState(LanLinkState.connected);

      // بعد إعادة الاتصال: أعد تسجيل القاعدة المفتوحة في الجلسة الجديدة.
      if (_lastOpenArgs != null) {
        final result = await _send('openDatabase', _lastOpenArgs);
        final id = result is Map ? result['id'] as int? : null;
        if (id != _lastOpenDbId) {
          _socket = null;
          await socket.close();
          throw LanConnectionException(
              'أُعيد تشغيل برنامج السيرفر — أغلق البرنامج وافتحه من جديد على هذا الجهاز');
        }
      }
    } on LanConnectionException {
      _setState(LanLinkState.disconnected);
      rethrow;
    } on WebSocketException catch (e) {
      _setState(LanLinkState.disconnected);
      throw LanConnectionException('تعذّر الاتصال بالسيرفر $host:$port — ${e.message}');
    } on TimeoutException {
      _setState(LanLinkState.disconnected);
      throw LanConnectionException(
          'السيرفر $host:$port لا يستجيب — تأكد أن برنامج السيرفر مفتوح وأن الجهازين على نفس الشبكة');
    } on SocketException catch (e) {
      _setState(LanLinkState.disconnected);
      throw LanConnectionException('تعذّر الوصول إلى السيرفر $host:$port — ${e.message}');
    }
  }

  LanConnectionException _closeCodeError(int? code) {
    switch (code) {
      case lanCloseBadKey:
        return LanConnectionException('رمز الربط غير صحيح');
      case lanCloseBadProto:
        return LanConnectionException('إصدار البرنامج لا يطابق السيرفر — حدّث البرنامج على هذا الجهاز');
      default:
        return LanConnectionException('رفض السيرفر الاتصال (رمز $code)');
    }
  }

  void _onDisconnected() {
    _socket = null;
    _setState(LanLinkState.disconnected);
    final err = LanConnectionException('انقطع الاتصال بالسيرفر');
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(err);
    }
    _pending.clear();
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = msg['i'] as int?;
    final c = id == null ? null : _pending.remove(id);
    if (c == null || c.isCompleted) return;
    if (msg.containsKey('e')) {
      final err = LanRemoteError.fromMap(msg['e'] as Map);
      // نعيده كاستثناء sqflite عادي، فكل catch (DatabaseException) في الكود الحالي يعمل.
      c.completeError(SqfliteDatabaseException(
        err.message,
        err.details,
        resultCode: err.resultCode,
        transactionClosed: err.transactionClosed,
      ));
    } else {
      c.complete(lanDecodeValue(msg['r']));
    }
  }

  Future<Object?> _send(String method, Object? args) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(LanConnectionException('غير متصل بالسيرفر'));
    }
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    socket.add(lanEncodeRequest(id, method, args));
    return c.future.timeout(requestTimeout, onTimeout: () {
      _pending.remove(id);
      throw LanConnectionException('انتهت مهلة الطلب ($method) — السيرفر مشغول أو الشبكة بطيئة');
    });
  }

  /// نقطة الدخول التي يستدعيها sqflite لكل عملية.
  Future<Object?> invoke(String method, [Object? arguments]) async {
    if (_socket == null) {
      // إعادة اتصال تلقائية مرة واحدة (مثلاً بعد انقطاع قصير للواي فاي).
      await connect();
    }
    final result = await _send(method, arguments);
    if (method == 'openDatabase') {
      _lastOpenArgs = arguments;
      _lastOpenDbId = result is Map ? result['id'] as int? : null;
    }
    return result;
  }

  /// للاختبارات فقط: قطع الاتصال فجأة كأن الشبكة سقطت.
  Future<void> debugDropConnection() async {
    final s = _socket;
    _onDisconnected();
    await s?.close();
  }

  Future<void> close() async {
    await _socket?.close();
    _socket = null;
    await _stateController.close();
  }

  /// فحص سريع: هل يوجد سيرفر للبرنامج على هذا العنوان؟ (بدون رمز الربط)
  static Future<Map<String, Object?>?> probe(String host,
      {int port = lanDefaultPort}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(Uri(scheme: 'http', host: host, port: port, path: '/info'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      return map['app'] == 'alnaser' ? map : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// المصنع الذي يُسند إلى `databaseFactory` في وضع الطرفية.
DatabaseFactory createLanDatabaseFactory(LanClientConnection connection) =>
    buildDatabaseFactory(tag: 'lan', invokeMethod: connection.invoke);

/// اكتشاف السيرفرات على الشبكة المحلية (بث UDP).
/// يعيد قائمة: {name, host, port}.
Future<List<Map<String, Object?>>> discoverLanServers({
  Duration wait = const Duration(seconds: 2),
}) async {
  final found = <String, Map<String, Object?>>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket?.receive();
      if (dg == null) return;
      try {
        final map = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (map['app'] != 'alnaser') return;
        final host = dg.address.address;
        found[host] = {
          'name': map['name'],
          'host': host,
          'port': map['port'] ?? lanDefaultPort,
          'proto': map['proto'],
        };
      } catch (_) {}
    });
    final probe = utf8.encode('ALNASER_DISCOVER');
    socket.send(probe, InternetAddress('255.255.255.255'), lanDiscoveryPort);
    await Future<void>.delayed(wait);
  } catch (_) {
    // بعض الشبكات تمنع البث — يبقى الإدخال اليدوي للعنوان متاحاً.
  } finally {
    socket?.close();
  }
  return found.values.toList();
}
