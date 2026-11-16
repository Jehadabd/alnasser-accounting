// lib/services/simplex/simplex_backup_service.dart
//
// 🛡️ النسخ الاحتياطي عبر SimpleX — بديل تيليجرام المجاني.
//
// • المرسل: «بوت» على هذه الحاسبة (حساب SimpleX باسم «Alnaser Backup» ينشئه المحرك
//   في أول تشغيل). لا رقم هاتف ولا حساب ولا توكن ولا اشتراك.
// • المستقبل: هاتف صاحب المحل فقط، عبر محادثة مباشرة خاصة مشفّرة. الربط برابط دعوة
//   لمرة واحدة (رمز QR): يُستهلك عند أول استعمال فلا يصلح لغيره ولو تسرّب.
// • الملفات تمر عبر خوادم نقل SimpleX المجانية وتبقى عليها مدة محدودة (يومان تقريباً)
//   حتى ينزّلها الهاتف — لذلك الأرشيف الدائم يبقى في Google Drive / Dropbox.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../upload_progress.dart' show SentCallback;
import 'simplex_client.dart';
import 'simplex_engine.dart';

class SimplexSendResult {
  const SimplexSendResult._(this.success, this.error);
  const SimplexSendResult.ok() : this._(true, null);
  const SimplexSendResult.fail(String e) : this._(false, e);
  final bool success;
  final String? error;
}

class SimplexBackupService {
  SimplexBackupService._();
  static final SimplexBackupService instance = SimplexBackupService._();
  factory SimplexBackupService() => instance;

  static const _kContactId = 'simplex_contact_id';
  static const _kContactName = 'simplex_contact_name';
  static const _kPendingConn = 'simplex_pending_conn_id';

  SimplexClient get _c => SimplexClient.instance;

  // ───────────── الحالة ─────────────

  Future<int?> contactId() async => (await SharedPreferences.getInstance()).getInt(_kContactId);
  Future<String?> contactName() async => (await SharedPreferences.getInstance()).getString(_kContactName);

  /// مربوط بهاتف ومحرّكه مثبّت (بلا تشغيل ولا إنترنت).
  Future<bool> get isConfigured async {
    if (!SimplexEngine.supported) return false;
    if (await contactId() == null) return false;
    return SimplexEngine.isInstalled();
  }

  Future<int> _userId() async {
    final r = await _c.cmd('/user');
    final u = r['user'];
    if (u is Map && u['userId'] is num) return (u['userId'] as num).toInt();
    throw SimplexException('لا يوجد حساب بوت في محرك SimpleX');
  }

  // ───────────── الربط ─────────────

  /// رابط دعوة لمرة واحدة (يُعرض رمز QR). الرابط القصير إن توفّر (أسهل للمسح).
  Future<String> createInvite() async {
    final uid = await _userId();
    final r = await _c.cmd('/_connect $uid');
    final link = r['connLinkInvitation'];
    final conn = r['connection'];
    if (conn is Map && conn['pccConnId'] is num) {
      // دعوة سابقة لم تُستعمل تُلغى (لا نترك روابط صالحة معلّقة)
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getInt(_kPendingConn);
      if (old != null) {
        try {
          await _c.cmd('/_delete :$old full notify=off');
        } catch (_) {}
      }
      await prefs.setInt(_kPendingConn, (conn['pccConnId'] as num).toInt());
    }
    if (link is Map) {
      final s = link['connShortLink'];
      if (s is String && s.isNotEmpty) return s;
      final f = link['connFullLink'];
      if (f is String && f.isNotEmpty) return f;
    }
    throw SimplexException('لم يُنشئ المحرك رابط دعوة');
  }

  /// ينتظر أن يمسح الهاتف الرمز ويصبح الإرسال ممكناً. يحفظ جهة الاتصال ويعيد اسمها.
  Future<String> waitForPhone({Duration timeout = const Duration(minutes: 10)}) async {
    final done = Completer<Map>();
    final sub = _c.events.listen((e) {
      final t = e['type'];
      if ((t == 'contactSndReady' || t == 'contactConnected') && e['contact'] is Map && !done.isCompleted) {
        done.complete(e['contact'] as Map);
      }
    });
    try {
      final contact = await done.future.timeout(timeout,
          onTimeout: () => throw SimplexException('لم يُمسح الرمز خلال ${timeout.inMinutes} دقائق — أنشئ رمزاً جديداً'));
      final id = (contact['contactId'] as num).toInt();
      final name = '${(contact['profile'] as Map?)?['displayName'] ?? contact['localDisplayName'] ?? ''}';
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getInt(_kContactId);
      await prefs.setInt(_kContactId, id);
      await prefs.setString(_kContactName, name);
      await prefs.remove(_kPendingConn);
      // هاتف سابق مربوط ⇒ تُحذف محادثته (المستقبل واحد فقط)
      if (old != null && old != id) {
        try {
          await _c.cmd('/_delete @$old full notify=off');
        } catch (_) {}
      }
      await sendText('✅ تم ربط هذا الهاتف بالنسخ الاحتياطي لبرنامج الناصر.\n'
          'ستصلك هنا قاعدة البيانات والتقارير مع كل ضغطة على «رفع البيانات».\n'
          '⚠️ نزّل الملفات خلال يومين من وصولها — بعدها تُحذف من خوادم النقل.');
      return name;
    } finally {
      await sub.cancel();
    }
  }

  /// فصل الهاتف: تُحذف المحادثة عند البوت ويُنسى الربط.
  Future<void> unlink() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_kContactId);
    if (id != null) {
      try {
        await _c.cmd('/_delete @$id full notify=on');
      } catch (e) {
        debugPrint('SimpleX: حذف المحادثة: $e');
      }
    }
    await prefs.remove(_kContactId);
    await prefs.remove(_kContactName);
  }

  /// بعد «إعادة الضبط» في المحرك: الربط القديم لم يعد له وجود.
  Future<void> forgetLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kContactId);
    await prefs.remove(_kContactName);
    await prefs.remove(_kPendingConn);
  }

  // ───────────── الإرسال ─────────────

  /// رسالة نصية (HTML تيليجرام يُحوَّل إلى تنسيق SimpleX).
  Future<SimplexSendResult> sendText(String text) async {
    try {
      final id = await contactId();
      if (id == null) return const SimplexSendResult.fail('لم يُربط هاتف بعد (إعدادات SimpleX)');
      for (final part in splitText(htmlToSimplex(text))) {
        await _c.cmd(sendCommand(id, text: part));
      }
      return const SimplexSendResult.ok();
    } catch (e) {
      return SimplexSendResult.fail('$e');
    }
  }

  /// ملف مع تعليق. ينتظر حتى يكتمل رفعه إلى خوادم النقل (لا «جُدول» فقط).
  Future<SimplexSendResult> sendFile(File file, {String? caption, SentCallback? onSent}) async {
    try {
      final id = await contactId();
      if (id == null) return const SimplexSendResult.fail('لم يُربط هاتف بعد (إعدادات SimpleX)');
      if (!await file.exists()) return const SimplexSendResult.fail('الملف غير موجود');
      final size = await file.length();
      if (size > 1000 * 1024 * 1024) return const SimplexSendResult.fail('الملف أكبر من حد SimpleX (1 غيغابايت)');

      // نسخة باسم آمن داخل مجلد المحرك: الأصل قد يُحذف (حزمة الرفع) قبل اكتمال التشفير والرفع
      final dir = Directory(await SimplexEngine.filesDir());
      await dir.create(recursive: true);
      final copy = File('${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_${safeName(file.uri.pathSegments.last)}');
      await file.copy(copy.path);

      // نستمع قبل الإرسال: حدث الاكتمال قد يصل سريعاً
      final done = Completer<String?>();
      int? fileId;
      final early = <Map<String, dynamic>>[];
      void check(Map<String, dynamic> e) {
        final t = e['type'];
        final meta = e['fileTransferMeta'];
        final fid = meta is Map ? (meta['fileId'] as num?)?.toInt() : null;
        if (fid == null || done.isCompleted) return;
        if (fileId == null) {
          early.add(e);
          return;
        }
        if (fid != fileId) return;
        if (t == 'sndFileCompleteXFTP' || t == 'sndFileComplete') done.complete(null);
        if (t == 'sndFileError') done.complete('${e['errorMessage'] ?? 'خطأ في رفع الملف'}');
      }

      final sub = _c.events.listen(check);
      try {
        onSent?.call(0, size);
        final r = await _c.cmd(sendCommand(id, text: htmlToSimplex(caption ?? ''), filePath: copy.path),
            timeout: const Duration(minutes: 2));
        fileId = fileIdOf(r);
        if (fileId == null) return const SimplexSendResult.fail('لم يقبل المحرك الملف');
        for (final e in early) {
          check(e);
        }
        // مهلة تتناسب مع الحجم: 5 دقائق + دقيقة لكل 3 ميغا (إنترنت بطيء)
        final limit = Duration(minutes: 5 + size ~/ (3 * 1024 * 1024));
        final err = await done.future.timeout(limit,
            onTimeout: () => 'لم يكتمل رفع الملف خلال ${limit.inMinutes} دقيقة — تحقق من الإنترنت');
        if (err != null) return SimplexSendResult.fail(err);
        onSent?.call(size, size);
        return const SimplexSendResult.ok();
      } finally {
        await sub.cancel();
        // النسخة المشفّرة يصنعها المحرك بنفسه؛ نسختنا تُحذف بعد انتهاء الرفع
        Future<void>.delayed(const Duration(seconds: 30), () async {
          try {
            if (await copy.exists()) await copy.delete();
          } catch (_) {}
        });
      }
    } catch (e) {
      return SimplexSendResult.fail('$e');
    }
  }

  // ───────────── أدوات (مختبرة) ─────────────

  /// أمر الإرسال الرسمي: /_send @<id> json [ComposedMessage]
  @visibleForTesting
  static String sendCommand(int contactId, {required String text, String? filePath}) {
    final msg = <String, Object?>{
      if (filePath != null) 'fileSource': {'filePath': filePath},
      'msgContent': filePath != null ? {'type': 'file', 'text': text} : {'type': 'text', 'text': text},
      'mentions': <String, Object?>{},
    };
    return '/_send @$contactId json ${jsonEncode([msg])}';
  }

  /// رقم الملف من ردّ الإرسال (newChatItems → chatItems[0].chatItem.file.fileId).
  @visibleForTesting
  static int? fileIdOf(Map<String, dynamic> r) {
    final items = r['chatItems'];
    if (items is! List || items.isEmpty) return null;
    final ci = (items.first as Map?)?['chatItem'];
    final f = ci is Map ? ci['file'] : null;
    return f is Map ? (f['fileId'] as num?)?.toInt() : null;
  }

  /// HTML تيليجرام (<b> <i> <code>) → تنسيق SimpleX (*غامق* _مائل_ `رمز`).
  @visibleForTesting
  static String htmlToSimplex(String s) {
    var t = s
        .replaceAll(RegExp(r'</?(b|strong)>', caseSensitive: false), '*')
        .replaceAll(RegExp(r'</?(i|em)>', caseSensitive: false), '_')
        .replaceAll(RegExp(r'</?code>', caseSensitive: false), '`')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]{1,40}>'), '');
    t = t
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    return t;
  }

  /// رسالة طويلة جداً تُقسم على الأسطر (حد رسالة SimpleX أصغر من تيليجرام).
  @visibleForTesting
  static List<String> splitText(String s, {int max = 12000}) {
    if (s.length <= max) return [s];
    final out = <String>[];
    var cur = StringBuffer();
    for (final line in s.split('\n')) {
      if (cur.length + line.length + 1 > max && cur.isNotEmpty) {
        out.add(cur.toString());
        cur = StringBuffer();
      }
      if (line.length > max) {
        for (var i = 0; i < line.length; i += max) {
          out.add(line.substring(i, i + max > line.length ? line.length : i + max));
        }
        continue;
      }
      if (cur.isNotEmpty) cur.write('\n');
      cur.write(line);
    }
    if (cur.isNotEmpty) out.add(cur.toString());
    return out;
  }

  /// اسم ملف آمن على Windows (العربية مسموحة؛ الرموز الممنوعة لا).
  @visibleForTesting
  static String safeName(String n) {
    final s = n.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return s.isEmpty ? 'file' : (s.length > 100 ? s.substring(s.length - 100) : s);
  }
}
