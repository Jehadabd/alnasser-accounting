// lib/services/simplex/simplex_client.dart
//
// 🔌 عميل WebSocket لمحرك SimpleX المحلي (واجهة البوتات الرسمية في SimpleX:
// كل أمر {corrId, cmd} وردّه بالـ corrId نفسه، والأحداث بلا corrId).
// عميل واحد فقط في البرنامج: المحرك يوزّع أحداثه على كل العملاء المتصلين.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'simplex_engine.dart';

class SimplexClient {
  SimplexClient._();
  static final SimplexClient instance = SimplexClient._();

  WebSocket? _ws;
  int? _wsPort;
  Future<void>? _connecting;
  int _seq = 0;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// أحداث المحرك (اتصال جهة، اكتمال رفع ملف، ...) — كل حدث هو حقل resp.
  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> _ensure() async {
    final port = await SimplexEngine.ensureRunning();
    if (_ws != null && _wsPort == port && _ws!.readyState == WebSocket.open) return;
    await (_connecting ??= _connect(port).whenComplete(() => _connecting = null));
  }

  Future<void> _connect(int port) async {
    try {
      await _ws?.close();
    } catch (_) {}
    final ws = await WebSocket.connect('ws://127.0.0.1:$port').timeout(const Duration(seconds: 10));
    _ws = ws;
    _wsPort = port;
    ws.listen(
      (data) {
        try {
          final j = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
          if (j is! Map) return;
          final resp = j['resp'];
          if (resp is! Map) return;
          final r = Map<String, dynamic>.from(resp);
          final id = j['corrId'];
          if (id is String && _pending.containsKey(id)) {
            _pending.remove(id)!.complete(r);
          } else {
            _events.add(r);
          }
        } catch (e) {
          debugPrint('SimpleX: رسالة غير مفهومة: $e');
        }
      },
      onDone: () => _drop('انقطع الاتصال بمحرك SimpleX'),
      onError: (e) => _drop('خطأ في الاتصال بمحرك SimpleX: $e'),
      cancelOnError: true,
    );
  }

  void _drop(String why) {
    _ws = null;
    _wsPort = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(SimplexException(why));
    }
    _pending.clear();
  }

  /// يرسل أمراً وينتظر ردّه. خطأ المحرك (chatCmdError) يُرمى SimplexException بوصف مختصر.
  Future<Map<String, dynamic>> cmd(String command, {Duration timeout = const Duration(seconds: 60)}) async {
    await _ensure();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws!.add(jsonEncode({'corrId': id, 'cmd': command}));
    final Map<String, dynamic> r;
    try {
      r = await c.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw SimplexException('محرك SimpleX لم يردّ خلال ${timeout.inSeconds} ثانية');
    }
    if (r['type'] == 'chatCmdError' || r['type'] == 'chatError') {
      throw SimplexException('SimpleX: ${describeError(r['chatError'])}');
    }
    return r;
  }

  /// وصف مختصر لخطأ المحرك (الأنواع من وثائق SimpleX: error / errorAgent / errorStore).
  static String describeError(Object? e) {
    if (e is! Map) return '$e';
    final inner = e['errorType'] ?? e['agentError'] ?? e['storeError'];
    if (inner is Map) {
      final t = inner['type'];
      final more = inner['message'] ?? inner['errorMessage'];
      return more != null ? '$t: $more' : '$t';
    }
    return '${e['type'] ?? e}';
  }

  /// يغلق الاتصال (المحرك نفسه يبقى إلى أن يُوقف).
  Future<void> close() async {
    try {
      await _ws?.close();
    } catch (_) {}
    _drop('أُغلق الاتصال');
  }
}
