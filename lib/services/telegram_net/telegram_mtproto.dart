// lib/services/telegram_net/telegram_mtproto.dart
//
// ⭐ الطريقة المميزة لتيليجرام عند الحظر: MTProto عبر TDLib.
//
// • نفس البوت ونفس القناة ونفس المحتوى — يتغيّر طريق الاتصال فقط (لا Bot API).
// • تعمل عبر بروكسيات MTProto المنشورة في القنوات (tg://proxy?…&secret=…) وكذلك SOCKS5.
//   عدة روابط: يُجرَّب كل واحد (testProxy) ويُستعمل أول ما يعمل.
// • بيانات تطبيقك عند تيليجرام (api_id / api_hash) من my.telegram.org:
//     عند البناء: --dart-define-from-file=tg_api.json  (ملف خارج git) — هكذا تصل لكل الزبائن،
//     أو ملف .env بجانب البرنامج (TG_API_ID / TG_API_HASH) على أجهزتك أنت.
// • مطفأة ⇒ الإرسال المباشر كما كان (Bot API، أو عبر بروكسي SOCKS/HTTP إن فُعّل).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../upload_progress.dart' show SentCallback;
import 'tdlib_client.dart';
import 'tdlib_engine.dart';

class TelegramMtproto {
  TelegramMtproto._();

  static const _kEnabled = 'tg_mtproto_enabled';
  static const _kProxies = 'tg_mtproto_proxies';

  static TdlibClient get _c => TdlibClient.instance;

  // ───────────── بيانات التطبيق (api_id / api_hash) ─────────────

  static const _defId = String.fromEnvironment('TG_API_ID');
  static const _defHash = String.fromEnvironment('TG_API_HASH');

  static String _env(String k) {
    try {
      return dotenv.isInitialized ? (dotenv.env[k] ?? '').trim() : '';
    } catch (_) {
      return '';
    }
  }

  static int? get apiId => int.tryParse(_defId.trim()) ?? int.tryParse(_env('TG_API_ID'));
  static String get apiHash => _defHash.trim().isNotEmpty ? _defHash.trim() : _env('TG_API_HASH');
  static bool get hasCredentials => apiId != null && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(apiHash);

  static bool get supported => !kIsWeb && Platform.isWindows;

  // ───────────── الإعداد ─────────────

  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;
  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, v);

  static Future<List<String>> proxies() async => (await SharedPreferences.getInstance()).getStringList(_kProxies) ?? const [];
  static Future<void> setProxies(List<String> l) async => (await SharedPreferences.getInstance()).setStringList(_kProxies, l);

  /// مفعّلة وجاهزة للاستعمال (بلا شبكة).
  static Future<bool> isActive() async =>
      supported && hasCredentials && await isEnabled() && await TdlibEngine.isInstalled();

  /// رابط بروكسي من القنوات → كائن proxy في TDLib (MTProto أو SOCKS5). غير ذلك ⇒ null.
  @visibleForTesting
  static Map<String, dynamic>? proxyJson(String link) {
    Uri u;
    try {
      u = Uri.parse(link.trim());
    } catch (_) {
      return null;
    }
    final kind = u.scheme == 'tg'
        ? u.host
        : ((u.host == 't.me' || u.host == 'telegram.me') && u.pathSegments.isNotEmpty ? u.pathSegments.first : '');
    final q = u.queryParameters;
    final server = (q['server'] ?? '').trim();
    final port = int.tryParse(q['port'] ?? '');
    if (server.isEmpty || port == null || port <= 0 || port > 65535) return null;
    if (kind == 'proxy') {
      final secret = (q['secret'] ?? '').trim();
      if (secret.isEmpty) return null;
      return {
        '@type': 'proxy',
        'server': server,
        'port': port,
        'type': {'@type': 'proxyTypeMtproto', 'secret': secret},
      };
    }
    if (kind == 'socks') {
      return {
        '@type': 'proxy',
        'server': server,
        'port': port,
        'type': {'@type': 'proxyTypeSocks5', 'username': q['user'] ?? '', 'password': q['pass'] ?? ''},
      };
    }
    return null;
  }

  static String proxyLabel(String link) {
    final j = proxyJson(link);
    if (j == null) return link;
    final t = (j['type'] as Map)['@type'] == 'proxyTypeMtproto' ? 'MTProto' : 'SOCKS5';
    return '$t ${j['server']}:${j['port']}';
  }

  // ───────────── الجلسة ─────────────

  static String? lastProxyUsed;

  static Future<void> _ready(String token) async {
    if (!hasCredentials) throw TdError(0, 'بيانات التطبيق (api_id / api_hash) غير موجودة في هذه النسخة');
    _c.onWaitingForBot = _applyProxies;
    await _c.ensureReady(token: token, apiId: apiId!, apiHash: apiHash);
  }

  /// يجرّب الروابط بالترتيب ويفعّل أول رابط يعمل. بلا روابط ⇒ اتصال MTProto مباشر.
  static Future<void> _applyProxies() async {
    final links = await proxies();
    try {
      final existing = await _c.request({'@type': 'getProxies'});
      for (final p in (existing['proxies'] as List? ?? const [])) {
        await _c.request({'@type': 'removeProxy', 'proxy_id': (p as Map)['id']});
      }
    } catch (e) {
      debugPrint('⭐ TDLib proxies: $e');
    }
    if (links.isEmpty) {
      await _c.request({'@type': 'disableProxy'});
      lastProxyUsed = 'اتصال مباشر';
      return;
    }
    final errors = <String>[];
    for (final l in links) {
      final pj = proxyJson(l);
      if (pj == null) continue;
      try {
        await _c.request({'@type': 'testProxy', 'proxy': pj, 'dc_id': 2, 'timeout': 12.0}, timeout: const Duration(seconds: 25));
        await _c.request({'@type': 'addProxy', 'proxy': pj, 'enable': true, 'comment': 'alnaser'});
        lastProxyUsed = proxyLabel(l);
        return;
      } catch (e) {
        errors.add('${proxyLabel(l)}: ${e is TdError ? e.message : e}');
      }
    }
    lastProxyUsed = null;
    throw TdError(0, 'لا يعمل أي بروكسي من القائمة — أضف روابط جديدة من القنوات.\n${errors.join('\n')}');
  }

  /// بعد تغيير قائمة الروابط: يطبّقها على الجلسة المفتوحة (إن وُجدت).
  static Future<void> reapply() async {
    if (_c.ready) await _applyProxies();
  }

  static Future<int> _chat(String channelId) async {
    final id = channelId.trim();
    if (id.startsWith('@')) {
      final r = await _c.request({'@type': 'searchPublicChat', 'username': id.substring(1)});
      return (r['id'] as num).toInt();
    }
    final n = int.tryParse(id);
    if (n == null) throw TdError(0, 'معرّف القناة غير صالح: $id');
    final sg = TdlibClient.supergroupIdOf(n);
    if (sg != null) {
      await _c.request({'@type': 'createSupergroupChat', 'supergroup_id': sg, 'force': true});
    } else {
      await _c.request({'@type': 'getChat', 'chat_id': n});
    }
    return n;
  }

  // ───────────── الإرسال ─────────────

  /// يرسل ملفاً. يعيد null عند النجاح أو وصف الخطأ.
  static Future<String?> sendDocument({
    required String token,
    required String channelId,
    required File file,
    String? caption,
    SentCallback? onSent,
  }) =>
      _guard(token, () async {
        final size = await file.length();
        return _sendAndWait(
          channelId,
          {
            '@type': 'inputMessageDocument',
            'document': {
              '@type': 'inputDocument',
              'document': {'@type': 'inputFileLocal', 'path': file.absolute.path},
            },
            // التعليق نص عادي كما في Bot API (sendDocument بلا parse_mode)
            'caption': {'@type': 'formattedText', 'text': caption ?? '', 'entities': []},
          },
          size: size,
          onSent: onSent,
        );
      });

  /// يرسل رسالة HTML (كما sendMessage مع parse_mode=HTML).
  static Future<String?> sendHtml({required String token, required String channelId, required String html}) =>
      _guard(token, () => _sendAndWait(channelId, {'@type': 'inputMessageText', 'text': _html(html)}));

  /// يتصل ويعيد اسم البوت (للاختبار من الإعدادات).
  static Future<String> test(String token) async {
    await _ready(token);
    final me = await _c.request({'@type': 'getMe'});
    final names = (me['usernames'] as Map?)?['active_usernames'] as List?;
    return names != null && names.isNotEmpty ? '@${names.first}' : '${me['first_name'] ?? ''}';
  }

  /// محاولة، وعند فشل الشبكة: إعادة اختيار البروكسي ثم محاولة ثانية.
  static Future<String?> _guard(String token, Future<void> Function() body) async {
    try {
      await _ready(token);
      try {
        await body();
      } on TdError catch (e) {
        if (e.code != 0) rethrow; // خطأ من تيليجرام (صلاحيات، قناة…) لا يُحل بتغيير البروكسي
        await _applyProxies();
        await body();
      }
      return null;
    } on TdError catch (e) {
      return describe(e);
    } catch (e) {
      return '$e';
    }
  }

  static Future<void> _sendAndWait(String channelId, Map<String, dynamic> content, {int size = 0, SentCallback? onSent}) async {
    final chat = await _chat(channelId);
    final done = Completer<void>();
    int? msgId;
    int? fileId;
    final early = <Map<String, dynamic>>[];
    void onUpdate(Map<String, dynamic> u) {
      if (done.isCompleted) return;
      if (msgId == null) {
        early.add(u);
        return;
      }
      switch (u['@type']) {
        case 'updateMessageSendSucceeded':
          if ((u['old_message_id'] as num?)?.toInt() == msgId) done.complete();
        case 'updateMessageSendFailed':
          if ((u['old_message_id'] as num?)?.toInt() == msgId) {
            final err = (u['error'] as Map?) ?? const {};
            done.completeError(TdError((err['code'] as num?)?.toInt() ?? 1, '${err['message'] ?? 'فشل الإرسال'}'));
          }
        case 'updateFile':
          final f = u['file'] as Map?;
          if (onSent != null && f != null && (f['id'] as num?)?.toInt() == fileId) {
            final up = ((f['remote'] as Map?)?['uploaded_size'] as num?)?.toInt() ?? 0;
            onSent(up, size > 0 ? size : ((f['expected_size'] as num?)?.toInt() ?? 0));
          }
      }
    }

    final sub = _c.updates.listen(onUpdate);
    try {
      onSent?.call(0, size);
      final m = await _c.request({'@type': 'sendMessage', 'chat_id': chat, 'input_message_content': content});
      msgId = (m['id'] as num).toInt();
      fileId = (((m['content'] as Map?)?['document'] as Map?)?['document'] as Map?)?['id'] as int?;
      for (final u in early) {
        onUpdate(u);
      }
      // مهلة تتناسب مع الحجم: دقيقتان + دقيقة لكل 2 ميغا
      final limit = Duration(minutes: 2 + size ~/ (2 * 1024 * 1024));
      await done.future.timeout(limit, onTimeout: () => throw TdError(0, 'لم يكتمل الإرسال خلال ${limit.inMinutes} دقيقة'));
      if (size > 0) onSent?.call(size, size);
    } finally {
      await sub.cancel();
    }
  }

  static Map<String, dynamic> _html(String html) {
    try {
      final r = _c.execute({
        '@type': 'parseTextEntities',
        'text': html,
        'parse_mode': {'@type': 'textParseModeHTML'},
      });
      if (r != null && r['@type'] == 'formattedText') return r;
    } catch (_) {}
    return {'@type': 'formattedText', 'text': html, 'entities': []};
  }

  /// أخطاء تيليجرام الشائعة بالعربية.
  static String describe(TdError e) {
    final m = e.message;
    if (m.contains('ACCESS_TOKEN_INVALID') || m.contains('Unauthorized')) return 'توكن البوت غير صحيح';
    if (m.contains('API_ID_INVALID') || m.contains('api_id')) return 'بيانات التطبيق api_id / api_hash غير صحيحة';
    if (m.contains('CHAT_WRITE_FORBIDDEN') || m.contains('not enough rights') || m.contains('Have no write access')) {
      return 'البوت ليس مشرفاً في القناة أو لا يملك صلاحية النشر';
    }
    if (m.contains('Chat not found') || m.contains('CHANNEL_INVALID')) return 'القناة غير موجودة أو البوت ليس فيها';
    return e.code == 0 ? m : 'تيليجرام: $m';
  }
}
