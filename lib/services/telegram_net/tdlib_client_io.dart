// lib/services/telegram_net/tdlib_client_io.dart  (يُصدَّر عبر tdlib_client.dart على Windows/Android — dart:ffi)
//
// ⭐ عميل TDLib (واجهة JSON الرسمية: td_create_client_id / td_send / td_receive / td_execute).
// يدخل كبوت بتوكن البوت نفسه (checkAuthenticationBotToken) ويتصل بخوادم تيليجرام بلغة MTProto،
// فيعمل عبر بروكسيات MTProto المنشورة في القنوات. التشفير من البرنامج إلى تيليجرام: البروكسي
// لا يقرأ شيئاً.
//
// td_receive يحجب حتى ثانية، فيعمل في Isolate منفصل لا يجمّد الواجهة؛ td_send آمن من أي خيط.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/error_journal.dart'; // 🩺 توقف الخيط يظهر في «تشخيص الأخطاء»
import 'tdlib_engine.dart';

class TdError implements Exception {
  TdError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'TDLib $code: $message';
}

typedef _CreateC = Int32 Function();
typedef _CreateD = int Function();
typedef _SendC = Void Function(Int32, Pointer<Utf8>);
typedef _SendD = void Function(int, Pointer<Utf8>);
typedef _RecvC = Pointer<Utf8> Function(Double);
typedef _RecvD = Pointer<Utf8> Function(double);
typedef _ExecC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ExecD = Pointer<Utf8> Function(Pointer<Utf8>);

DynamicLibrary _open(String binDir) {
  // المكتبات التابعة أولاً بمساراتها الكاملة: Windows يعيد استعمال الوحدة المحمّلة بالاسم نفسه
  DynamicLibrary? td;
  for (final d in TdlibEngine.dlls) {
    final lib = DynamicLibrary.open(p.join(binDir, d));
    if (d == 'tdjson.dll') td = lib;
  }
  return td!;
}

/// حلقة الاستقبال (Isolate): كل رد/حدث نصاً إلى البرنامج.
void _receiveLoop(List<Object> args) {
  final out = args[0] as SendPort;
  final lib = _open(args[1] as String);
  final recv = lib.lookupFunction<_RecvC, _RecvD>('td_receive');
  while (true) {
    final r = recv(1.0);
    if (r != nullptr) out.send(r.toDartString());
  }
}

class TdlibClient {
  TdlibClient._();
  static final TdlibClient instance = TdlibClient._();

  static const _secure = FlutterSecureStorage();
  static const _kDbKey = 'tdlib_db_key';

  DynamicLibrary? _lib;
  late _SendD _send;
  late _CreateD _create;
  late _ExecD _exec;
  Isolate? _isolate;
  ReceivePort? _port;
  ReceivePort? _errPort; // 🩺 أخطاء خيط الاستقبال (كانت تضيع بلا أثر)

  int? _clientId;
  String? _botId; // الجلسة الحالية لأي بوت
  String? _token;
  int _seq = 0;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Completer<void>? _ready;
  Completer<void>? _closed;
  String _authState = '';
  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get updates => _updates.stream;

  // بيانات الدخول (تُعطى عند البدء)
  late int _apiId;
  late String _apiHash;
  Future<void> Function()? onWaitingForBot; // لإعداد البروكسي قبل الدخول

  Future<void> _loadFrom() async {
    if (_lib != null) return;
    final bin = await TdlibEngine.binDir();
    // ❄️ التحميل الأول لمكتبة tdjson الكبيرة (عشرات الميغابايت) قد يطول جداً حين يفحصها
    //    برنامج الحماية — كان يحدث على خيط الواجهة فيتجمّد البرنامج (سُجّل تجمّد 84 ثانية في
    //    شاشة «عند حظر تيليجرام»). نحمّلها أولاً في Isolate جانبي؛ بعده التحميل هنا فوري
    //    (الوحدة محمّلة في العملية نفسها).
    await Isolate.run(() {
      _open(bin);
      return true;
    }, debugName: 'tdlib_preload');
    final lib = _open(bin);
    _send = lib.lookupFunction<_SendC, _SendD>('td_send');
    _create = lib.lookupFunction<_CreateC, _CreateD>('td_create_client_id');
    _exec = lib.lookupFunction<_ExecC, _ExecD>('td_execute');
    _lib = lib;
    execute({'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 1});
    final port = ReceivePort();
    _port = port;
    port.listen((m) => _onMessage(m as String));
    final errPort = ReceivePort();
    _errPort = errPort;
    errPort.listen((m) {
      final err = m is List && m.isNotEmpty ? m.first : m;
      final st = m is List && m.length > 1 ? '${m[1]}' : null;
      ErrorJournal.recordText(ErrorSource.background, 'توقف خيط تيليجرام (MTProto/tdjson): $err${st == null ? '' : '\n$st'}');
    });
    _isolate = await Isolate.spawn(_receiveLoop, [port.sendPort, bin], debugName: 'tdlib_receive', onError: errPort.sendPort);
  }

  /// طلب متزامن (td_execute) — لما تسمح به TDLib فقط (parseTextEntities، setLogVerbosityLevel…).
  Map<String, dynamic>? execute(Map<String, dynamic> q) {
    final ptr = jsonEncode(q).toNativeUtf8();
    try {
      final r = _exec(ptr);
      if (r == nullptr) return null;
      return (jsonDecode(r.toDartString()) as Map).cast<String, dynamic>();
    } finally {
      malloc.free(ptr);
    }
  }

  /// يدخل بالبوت [token] (ويغيّر الجلسة إن تغيّر البوت). يكتمل عند جاهزية الإرسال.
  Future<void> ensureReady({required String token, required int apiId, required String apiHash}) async {
    if (!await TdlibEngine.isInstalled()) throw TdError(0, 'محرك MTProto غير مثبّت');
    await _loadFrom();
    final botId = token.split(':').first;
    if (_clientId != null && (_botId != botId || _token != token)) await _closeSession();
    _apiId = apiId;
    _apiHash = apiHash;
    if (_clientId == null) {
      _botId = botId;
      _token = token;
      _ready = Completer<void>();
      _clientId = _create();
      // أول طلب يوقظ العميل فتبدأ أحداث حالة الدخول
      _raw({'@type': 'getOption', 'name': 'version'});
    }
    await _ready!.future.timeout(const Duration(seconds: 90),
        onTimeout: () => throw TdError(0, 'لم يتصل بتيليجرام خلال 90 ثانية — البروكسي لا يعمل أو الإنترنت مقطوع'));
  }

  /// طلب غير متزامن مع انتظار ردّه.
  Future<Map<String, dynamic>> request(Map<String, dynamic> q, {Duration timeout = const Duration(seconds: 60)}) async {
    final id = '${_seq++}';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _raw({...q, '@extra': id});
    try {
      final r = await c.future.timeout(timeout);
      if (r['@type'] == 'error') throw TdError((r['code'] as num?)?.toInt() ?? 0, '${r['message']}');
      return r;
    } on TimeoutException {
      throw TdError(0, 'انتهت المهلة (${timeout.inSeconds} ثانية)');
    } finally {
      _pending.remove(id);
    }
  }

  void _raw(Map<String, dynamic> q) {
    final cid = _clientId;
    if (cid == null) throw TdError(0, 'لا جلسة');
    final ptr = jsonEncode(q).toNativeUtf8();
    try {
      _send(cid, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  void _onMessage(String s) {
    final Map<String, dynamic> m;
    try {
      m = (jsonDecode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    if (m['@client_id'] != _clientId) return;
    final extra = m['@extra'];
    if (extra is String && _pending.containsKey(extra)) {
      _pending[extra]!.complete(m);
      return;
    }
    if (m['@type'] == 'updateAuthorizationState') {
      _onAuth((m['authorization_state'] as Map).cast<String, dynamic>());
    }
    _updates.add(m);
  }

  Future<void> _onAuth(Map<String, dynamic> st) async {
    _authState = '${st['@type']}';
    debugPrint('⭐ TDLib: $_authState');
    try {
      switch (_authState) {
        case 'authorizationStateWaitTdlibParameters':
          final dir = p.join(await TdlibEngine.root(), 'bot_$_botId');
          await request({
            '@type': 'setTdlibParameters',
            'use_test_dc': false,
            'database_directory': dir,
            'files_directory': p.join(dir, 'files'),
            'database_encryption_key': await _dbKey(),
            'use_file_database': false,
            'use_chat_info_database': false,
            'use_message_database': false,
            'use_secret_chats': false,
            'api_id': _apiId,
            'api_hash': _apiHash,
            'system_language_code': 'ar',
            'device_model': 'Alnaser Accounting',
            'system_version': 'Windows',
            'application_version': '1.0',
          });
        case 'authorizationStateWaitPhoneNumber':
          await onWaitingForBot?.call();
          await request({'@type': 'checkAuthenticationBotToken', 'token': _token});
        case 'authorizationStateReady':
          final r = _ready;
          if (r != null && !r.isCompleted) r.complete();
        case 'authorizationStateClosed':
          final c = _closed;
          if (c != null && !c.isCompleted) c.complete();
        default:
          if (_authState.startsWith('authorizationStateWait')) {
            _fail(TdError(0, 'تيليجرام يطلب خطوة غير متوقعة لبوت: $_authState'));
          }
      }
    } catch (e) {
      _fail(e is TdError ? e : TdError(0, '$e'));
    }
  }

  void _fail(TdError e) {
    final r = _ready;
    if (r != null && !r.isCompleted) r.completeError(e);
    // توكن خطأ أو بيانات API خطأ: الجلسة لا تصلح — تُغلق لتبدأ من جديد في المحاولة القادمة
    unawaited(_closeSession());
  }

  Future<void> _closeSession() async {
    final cid = _clientId;
    if (cid == null) return;
    _closed = Completer<void>();
    try {
      _raw({'@type': 'close'});
      await _closed!.future.timeout(const Duration(seconds: 15));
    } catch (_) {}
    _clientId = null;
    _botId = null;
    _token = null;
    _ready = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(TdError(0, 'أُغلقت الجلسة'));
    }
    _pending.clear();
  }

  /// يوقف كل شيء (عند إغلاق البرنامج).
  Future<void> shutdown() async {
    await _closeSession();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _errPort?.close();
    _errPort = null;
  }

  static Future<String> _dbKey() async {
    final k = await _secure.read(key: _kDbKey);
    if (k != null && k.isNotEmpty) return k;
    final r = Random.secure();
    final key = base64.encode(List<int>.generate(32, (_) => r.nextInt(256)));
    await _secure.write(key: _kDbKey, value: key);
    return key;
  }

  bool get ready => _ready?.isCompleted == true && _authState == 'authorizationStateReady';
  String get authState => _authState;

  // ───────────── أدوات صافية (مختبرة) ─────────────

  /// معرّف قناة Bot API (‎-100XXXXXXXX) → معرّف supergroup في TDLib.
  @visibleForTesting
  static int? supergroupIdOf(int chatId) {
    const base = -1000000000000;
    if (chatId > base) return null;
    return base - chatId;
  }
}
