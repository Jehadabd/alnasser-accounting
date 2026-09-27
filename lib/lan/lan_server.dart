// lib/lan/lan_server.dart
//
// خادم قاعدة البيانات المدمج — يعمل داخل البرنامج نفسه على «حاسبة السيرفر».
//
// كيف يعمل:
//   • برنامج السيرفر يفتح قاعدة بياناته كالمعتاد (sqflite_common_ffi).
//   • هذا الخادم يستقبل من الطرفيات استدعاءات sqflite الخام (method, args)
//     وينفّذها على نفس الاتصال بالضبط (singleInstance)، فالكل يقرأ ويكتب
//     في ملف واحد.
//   • المعاملات (transactions) تُسلسَل تلقائياً: sqflite_common_ffi يؤجّل أي
//     عملية من خارج المعاملة الجارية حتى تنتهي — سواء جاءت من برنامج السيرفر
//     أو من أي طرفية.
//   • إذا انقطعت طرفية وسط معاملة، نتراجع عنها (ROLLBACK) فوراً حتى لا تُقفل
//     القاعدة على الجميع.
//
// الأمان: الشبكة المحلية فقط + «رمز الربط» يُعرض على شاشة السيرفر.
// صلاحيات الموظفين تُطبَّق داخل البرنامج بعد تسجيل الدخول (جدول users).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:sqflite_common/src/mixin/import_mixin.dart'
    show SqfliteInvokeHandler, SqfliteDatabaseException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

import 'lan_codec.dart';

/// معلومات طرفية متصلة — تُعرض في شاشة «الأجهزة المتصلة».
class LanClientInfo {
  LanClientInfo({
    required this.sessionId,
    required this.address,
    required this.clientName,
    required this.connectedAt,
  });

  final int sessionId;
  final String address;
  final String clientName;
  final DateTime connectedAt;
  DateTime lastActivity = DateTime.now();
  int requestCount = 0;
}

class LanDatabaseServer {
  LanDatabaseServer({
    required this.databasePath,
    required this.secret,
    this.serverName = 'السيرفر',
    this.port = lanDefaultPort,
    this.transactionIdleTimeout = const Duration(seconds: 60),
    this.enableDiscovery = true,
    SqfliteInvokeHandler? handler,
    this.log = _defaultLog,
  }) : _handler = handler ?? (databaseFactoryFfi as SqfliteInvokeHandler);

  /// مسار ملف قاعدة البيانات على حاسبة السيرفر. أي مسار ترسله الطرفية يُستبدل به.
  final String databasePath;

  /// رمز الربط: يجب أن ترسله الطرفية في ترويسة الاتصال.
  final String secret;

  final String serverName;
  final int port;

  /// معاملة مفتوحة بلا أي نشاط أطول من هذا ⇒ تراجع وقطع الطرفية.
  final Duration transactionIdleTimeout;

  final void Function(String message) log;

  /// الرد على بث الاكتشاف (يُعطَّل في الاختبارات).
  final bool enableDiscovery;

  final SqfliteInvokeHandler _handler;

  HttpServer? _http;
  RawDatagramSocket? _discovery;
  Timer? _watchdog;
  int _nextSessionId = 1;
  final Map<int, _LanSession> _sessions = {};

  final _clientsController = StreamController<List<LanClientInfo>>.broadcast();

  /// يتغيّر عند اتصال أو انقطاع أي طرفية.
  Stream<List<LanClientInfo>> get clientsStream => _clientsController.stream;

  List<LanClientInfo> get clients =>
      _sessions.values.map((s) => s.info).toList(growable: false);

  bool get isRunning => _http != null;

  /// المنفذ الفعلي (مفيد عند التشغيل على المنفذ 0 في الاختبارات).
  int get boundPort => _http?.port ?? port;

  Future<void> start() async {
    if (_http != null) return;
    _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http!.listen(_onRequest, onError: (Object e) => log('LAN server error: $e'));
    if (enableDiscovery) await _startDiscoveryResponder();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _checkIdle());
    log('🖧 خادم الشبكة يعمل على المنفذ $boundPort');
  }

  Future<void> stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    _discovery?.close();
    _discovery = null;
    for (final s in _sessions.values.toList()) {
      await s.close(reason: 'إيقاف السيرفر');
    }
    await _http?.close(force: true);
    _http = null;
    _emitClients();
    log('🖧 أُوقف خادم الشبكة');
  }

  // ───────────────────────── HTTP / WebSocket ─────────────────────────

  Future<void> _onRequest(HttpRequest req) async {
    try {
      if (req.uri.path == '/info' && req.method == 'GET') {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'app': 'alnaser',
            'name': serverName,
            'proto': lanProtocolVersion,
          }));
        await req.response.close();
        return;
      }

      if (req.uri.path == '/db' && WebSocketTransformer.isUpgradeRequest(req)) {
        final key = req.headers.value('x-alnaser-key') ?? '';
        final proto = int.tryParse(req.headers.value('x-alnaser-proto') ?? '');
        final remote = req.connectionInfo?.remoteAddress.address ?? '?';
        final clientName = Uri.decodeComponent(
            req.headers.value('x-alnaser-client') ?? 'طرفية');
        // نرقّي الاتصال أولاً ثم نرفض داخل WebSocket برمز إغلاق واضح،
        // لأن dart:io في الطرفية لا يكشف رمز HTTP عند فشل الترقية.
        final socket = await WebSocketTransformer.upgrade(req);
        if (!_constantTimeEquals(key, secret)) {
          log('⛔ محاولة اتصال برمز ربط خاطئ من $remote');
          await socket.close(lanCloseBadKey, 'bad key');
          return;
        }
        if (proto != lanProtocolVersion) {
          await socket.close(lanCloseBadProto, 'protocol $proto != $lanProtocolVersion');
          return;
        }
        socket.pingInterval = const Duration(seconds: 10);
        final id = _nextSessionId++;
        final session = _LanSession(
          server: this,
          socket: socket,
          info: LanClientInfo(
            sessionId: id,
            address: remote,
            clientName: clientName,
            connectedAt: DateTime.now(),
          ),
        );
        _sessions[id] = session;
        _emitClients();
        log('🔌 اتصلت طرفية: $clientName ($remote)');
        session.listen();
        socket.add(jsonEncode({
          'hello': {'name': serverName, 'proto': lanProtocolVersion}
        }));
        return;
      }

      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (e) {
      log('LAN request error: $e');
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  void _onSessionClosed(_LanSession s) {
    if (_sessions.remove(s.info.sessionId) != null) {
      _emitClients();
      log('🔌 انقطعت طرفية: ${s.info.clientName} (${s.info.address})');
    }
  }

  void _emitClients() {
    if (!_clientsController.isClosed) _clientsController.add(clients);
  }

  void _checkIdle() {
    final now = DateTime.now();
    for (final s in _sessions.values.toList()) {
      if (s.hasOpenTransaction &&
          now.difference(s.info.lastActivity) > transactionIdleTimeout) {
        log('⏱️ معاملة معلّقة من ${s.info.clientName} — تراجع وقطع الاتصال');
        unawaited(s.close(reason: 'معاملة معلّقة'));
      }
    }
  }

  // ───────────────────────── الاكتشاف التلقائي ─────────────────────────
  // الطرفية ترسل "ALNASER_DISCOVER" بثاً على المنفذ 47801،
  // والسيرفر يرد باسمه ومنفذه. لا يُرسل رمز الربط أبداً في هذا الرد.

  Future<void> _startDiscoveryResponder() async {
    try {
      _discovery = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, lanDiscoveryPort,
          reuseAddress: true);
      _discovery!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _discovery?.receive();
        if (dg == null) return;
        if (utf8.decode(dg.data, allowMalformed: true) != 'ALNASER_DISCOVER') {
          return;
        }
        final reply = utf8.encode(jsonEncode({
          'app': 'alnaser',
          'name': serverName,
          'port': port,
          'proto': lanProtocolVersion,
        }));
        _discovery?.send(reply, dg.address, dg.port);
      });
    } catch (e) {
      // ليس قاتلاً: يمكن إدخال عنوان السيرفر يدوياً.
      log('⚠️ تعذّر تشغيل الاكتشاف التلقائي: $e');
    }
  }

  // ───────────────────────── التنفيذ ─────────────────────────

  Future<Object?> _invoke(String method, Object? args) =>
      _handler.invokeMethod<Object?>(method, args);
}

/// جلسة طرفية واحدة.
class _LanSession {
  _LanSession({required this.server, required this.socket, required this.info});

  final LanDatabaseServer server;
  final WebSocket socket;
  final LanClientInfo info;

  /// معرّفات قواعد البيانات التي فتحتها هذه الطرفية (للتحقق من كل طلب).
  final Set<int> _dbIds = {};

  /// dbId → transactionId المفتوح حالياً من هذه الطرفية.
  final Map<int, int> _openTransactions = {};

  bool _closed = false;

  bool get hasOpenTransaction => _openTransactions.isNotEmpty;

  void listen() {
    socket.listen(
      (data) {
        if (data is String) {
          // لا ننتظر: كل طلب يُعالج مستقلاً، وsqflite يرتّب المعاملات بنفسه.
          unawaited(_handleMessage(data));
        }
      },
      onDone: () => unawaited(close(reason: 'انقطاع')),
      onError: (Object _) => unawaited(close(reason: 'خطأ اتصال')),
      cancelOnError: true,
    );
  }

  Future<void> _handleMessage(String raw) async {
    int id = -1;
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      id = msg['i'] as int;
      final method = msg['m'] as String;
      final args = lanDecodeValue(msg['a']);
      info.lastActivity = DateTime.now();
      info.requestCount++;
      final result = await _dispatch(method, args);
      info.lastActivity = DateTime.now();
      _send(lanEncodeResult(id, result));
    } catch (e) {
      _send(lanEncodeError(id, _toRemoteError(e)));
    }
  }

  Future<Object?> _dispatch(String method, Object? args) async {
    final map = args is Map ? Map<String, Object?>.from(args) : <String, Object?>{};

    switch (method) {
      case 'openDatabase': {
        // أي مسار ترسله الطرفية يُستبدل بملف السيرفر، ومشاركة الاتصال إجبارية.
        map['path'] = server.databasePath;
        map['singleInstance'] = true;
        final result = await server._invoke(method, map);
        final dbId = (result is Map) ? result['id'] as int? : null;
        if (dbId != null) _dbIds.add(dbId);
        return result;
      }

      case 'closeDatabase': {
        // لا نغلق القاعدة المشتركة أبداً — السيرفر وباقي الطرفيات يستخدمونها.
        final dbId = map['id'] as int?;
        if (dbId != null) {
          await _rollbackIfOpen(dbId);
          _dbIds.remove(dbId);
        }
        return null;
      }

      case 'databaseExists':
        return true;

      case 'getDatabasesPath':
        return p.dirname(server.databasePath);

      case 'getPlatformVersion':
        return 'alnaser-lan/$lanProtocolVersion';

      case 'options':
      case 'debugMode':
      case 'debug':
        // إعدادات عامة على السيرفر — لا تُغيَّر من طرفية.
        return null;

      case 'deleteDatabase':
      case 'writeDatabaseBytes':
      case 'readDatabaseBytes':
        throw LanRemoteError(
          code: 'lan_forbidden',
          message: 'هذه العملية ممنوعة من الطرفيات ($method) — تُنفّذ على حاسبة السيرفر فقط',
        );

      case 'execute':
      case 'query':
      case 'queryCursorNext':
      case 'insert':
      case 'update':
      case 'batch': {
        final dbId = map['id'] as int?;
        if (dbId == null || !_dbIds.contains(dbId)) {
          throw LanRemoteError(
              code: 'lan_bad_db', message: 'قاعدة بيانات غير مفتوحة في هذه الجلسة');
        }
        final inTxnChange = map['inTransaction'] as bool?;
        // عملية تحمل رقم معاملة ليست مفتوحة في هذه الجلسة = معاملة تراجعنا
        // عنها بعد انقطاع الاتصال. لو نفّذناها لنُفّذت خارج أي معاملة وحُفظ
        // نصف العملية. نرفضها ليفشل حفظ الطرفية كاملاً ويعيده المستخدم.
        final tid = map['transactionId'];
        if (tid is int && tid != -1 && _openTransactions[dbId] != tid) {
          throw LanRemoteError(
            code: 'lan_txn_lost',
            message: 'انقطع الاتصال بالسيرفر أثناء الحفظ فأُلغيت العملية كاملة — أعد المحاولة',
            transactionClosed: true,
          );
        }
        try {
          final result = await server._invoke(method, map);
          if (inTxnChange == true && result is Map && result['transactionId'] is int) {
            _openTransactions[dbId] = result['transactionId'] as int;
          } else if (inTxnChange == false) {
            _openTransactions.remove(dbId);
          }
          return result;
        } on SqfliteDatabaseException catch (e) {
          if (e.transactionClosed || inTxnChange == false) {
            _openTransactions.remove(dbId);
          }
          rethrow;
        }
      }

      default:
        throw LanRemoteError(code: 'lan_unknown_method', message: 'عملية غير معروفة: $method');
    }
  }

  Future<void> _rollbackIfOpen(int dbId) async {
    final txnId = _openTransactions.remove(dbId);
    if (txnId == null) return;
    try {
      await server._invoke('execute', {
        'id': dbId,
        'sql': 'ROLLBACK',
        'inTransaction': false,
        'transactionId': txnId,
      });
      server.log('↩️ تراجع عن معاملة غير مكتملة من ${info.clientName}');
    } catch (e) {
      server.log('⚠️ فشل التراجع عن معاملة ${info.clientName}: $e');
    }
  }

  void _send(String data) {
    if (_closed) return;
    try {
      socket.add(data);
    } catch (_) {}
  }

  Future<void> close({required String reason}) async {
    if (_closed) return;
    _closed = true;
    for (final dbId in _openTransactions.keys.toList()) {
      await _rollbackIfOpen(dbId);
    }
    try {
      await socket.close(WebSocketStatus.normalClosure, reason);
    } catch (_) {}
    server._onSessionClosed(this);
  }
}

LanRemoteError _toRemoteError(Object e) {
  if (e is LanRemoteError) return e;
  if (e is SqfliteDatabaseException) {
    String? code;
    try {
      code = (e as dynamic).code as String?; // SqfliteFfiException فقط
    } catch (_) {}
    return LanRemoteError(
      message: e.message ?? e.toString(),
      code: code,
      resultCode: e.getResultCode(),
      transactionClosed: e.transactionClosed,
      details: e.result,
    );
  }
  return LanRemoteError(message: e.toString(), code: 'lan_server_error');
}

bool _constantTimeEquals(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

void _defaultLog(String m) {
  // ignore: avoid_print
  print(m);
}
