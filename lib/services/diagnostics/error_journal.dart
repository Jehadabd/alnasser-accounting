// lib/services/diagnostics/error_journal.dart
//
// 🩺 سجل أخطاء البرنامج لأداة «تشخيص الأخطاء» (الإعدادات ← النظام والأدوات).
//
// يجمع خمسة مصادر:
//   • أخطاء Flutter (الشاشات) والأخطاء غير المعالَجة — من ErrorLog.install.
//   • الأخطاء التي عالجها البرنامج وكتبها بـ debugPrint: السطر الذي يبدأ بـ ❌ أو 🔴،
//     أو ⚠️ ومعه اسم استثناء (SocketException…). التنبيهات العادية لا تُسجَّل.
//   • أعطال ويندوز الأصلية (native_errors.log من crash_guard.cpp): الخروج المفاجئ فقط.
//   • كل رسالة خطأ حمراء ظهرت للمستخدم (ErrorCaptureMessenger حول كل الشاشات).
//   • ما يسجّله الكود يدوياً: ErrorJournal.record(...).
//
// الأخطاء المتشابهة (تختلف بالأرقام فقط) مدخل واحد بعدد مرات حدوثها.
// 🔒 قبل الحفظ تُمحى الأسرار: رموز البوتات، رموز Dropbox وFirebase، كلمات المرور والرموز
//    في الروابط… (sanitize). لا يغيّر سلوك البرنامج ولا يلمس قاعدة البيانات:
//    ملف JSON صغير بجانب dart_errors.log (alnaser_logs\error_journal.json).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// مصدر الخطأ.
class ErrorSource {
  ErrorSource._();
  static const flutter = 'flutter'; // خطأ في رسم شاشة
  static const uncaught = 'uncaught'; // خطأ لم يعالجه البرنامج
  static const logged = 'logged'; // خطأ عالجه البرنامج وسجّله
  static const native = 'native'; // عطل أصلي في ويندوز (خروج مفاجئ)
  static const shown = 'shown'; // رسالة خطأ حمراء ظهرت للمستخدم
  static const manual = 'manual';

  static String label(String s) => switch (s) {
        flutter => 'خطأ في الشاشة',
        uncaught => 'خطأ غير معالَج',
        logged => 'خطأ عالجه البرنامج',
        native => 'خروج مفاجئ (ويندوز)',
        shown => 'رسالة ظهرت للمستخدم',
        _ => 'مسجَّل يدوياً',
      };
}

/// خطأ واحد (أو مجموعة أخطاء متشابهة).
class ErrorEntry {
  ErrorEntry({
    required this.id,
    required this.source,
    required this.message,
    this.detail,
    required this.first,
    required this.last,
    this.count = 1,
    this.resolved = false,
  });

  final String id;
  final String source;
  String message;
  String? detail;
  final DateTime first;
  DateTime last;
  int count;

  /// علّمه المستخدم «تم الحل». يعود غير محلول إن تكرّر بعدها.
  bool resolved;

  /// كل النص الذي تُطابَق عليه الحلول.
  String get text => detail == null ? message : '$message\n$detail';

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'message': message,
        if (detail != null) 'detail': detail,
        'first': first.toIso8601String(),
        'last': last.toIso8601String(),
        'count': count,
        if (resolved) 'resolved': true,
      };

  static ErrorEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], msg = j['message'];
    final first = DateTime.tryParse('${j['first']}'), last = DateTime.tryParse('${j['last']}');
    if (id is! String || msg is! String || first == null || last == null) return null;
    return ErrorEntry(
      id: id,
      source: '${j['source'] ?? ErrorSource.manual}',
      message: msg,
      detail: j['detail'] as String?,
      first: first,
      last: last,
      count: (j['count'] as num?)?.toInt() ?? 1,
      resolved: j['resolved'] == true,
    );
  }
}

class ErrorJournal {
  ErrorJournal._();

  static const int maxEntries = 300;
  static const int _maxMessage = 600;
  static const int _maxDetail = 4000;

  static final Map<String, ErrorEntry> _byId = {};
  static File? _file;
  static Directory? _dir;
  static Timer? _saveTimer;
  static bool _busy = false; // يمنع تسجيل ما يكتبه السجل نفسه
  static bool _hooked = false;

  /// يتغيّر مع كل خطأ جديد أو تعديل (لتحديث الشاشة والعدّاد مباشرة).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// يُستدعى مرة من ErrorLog.install. [dir] مجلد alnaser_logs (null = في الذاكرة فقط).
  static Future<void> install(Directory? dir) async {
    _dir = dir;
    if (dir != null) {
      final f = File('${dir.path}${Platform.pathSeparator}error_journal.json');
      _file = f;
      try {
        if (await f.exists()) {
          final j = jsonDecode(await f.readAsString());
          for (final e in ((j is Map ? j['entries'] : null) as List? ?? const [])) {
            final x = ErrorEntry.fromJson(e);
            if (x != null) _byId[x.id] = x;
          }
        }
      } catch (_) {
        // ملف تالف: نبدأ سجلاً جديداً (لا شيء يعتمد عليه)
      }
    }
    _hookDebugPrint();
  }

  static void _hookDebugPrint() {
    if (_hooked) return;
    _hooked = true;
    final prev = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      prev(message, wrapWidth: wrapWidth);
      if (message != null && !_busy && looksLikeError(message)) {
        recordText(ErrorSource.logged, message);
      }
    };
  }

  // ─────────────────────────── التسجيل ───────────────────────────

  static final _exceptionName = RegExp(r'\b\w*(Exception|Error)\b');

  /// هل هذا السطر من debugPrint خطأ يستحق التسجيل؟
  static bool looksLikeError(String line) {
    final t = line.trimLeft();
    if (t.startsWith('❌') || t.startsWith('🔴')) return true;
    if (t.startsWith('⚠️')) return _exceptionName.hasMatch(t);
    return false;
  }

  /// يسجّل خطأ (استثناء + مكانه).
  static void record({required String source, required Object error, StackTrace? stack, String? context}) {
    final msg = '$error';
    final detail = [
      if (context != null && context.trim().isNotEmpty) 'المكان: ${context.trim()}',
      if (stack != null) _trimStack('$stack'),
    ].join('\n');
    _add(source, msg, detail.isEmpty ? null : detail);
  }

  /// يسجّل نصاً (سطر من السجل).
  static void recordText(String source, String text) {
    final lines = text.trim().split('\n');
    final msg = lines.first;
    final rest = lines.length > 1 ? lines.skip(1).join('\n') : null;
    _add(source, msg, rest);
  }

  static void _add(String source, String message, String? detail) {
    if (_busy) return;
    _busy = true;
    try {
      final m = _cut(sanitize(_stripMarkers(message)), _maxMessage);
      if (m.trim().isEmpty) return;
      final d = detail == null ? null : _cut(sanitize(detail), _maxDetail);
      final id = fingerprint(source, m);
      final now = DateTime.now();
      final e = _byId[id];
      if (e != null) {
        e.count++;
        e.last = now;
        e.message = m; // أحدث صيغة للرسالة
        if (d != null) e.detail = d;
        e.resolved = false; // تكرّر بعد «تم الحل»
      } else {
        _byId[id] = ErrorEntry(id: id, source: source, message: m, detail: d, first: now, last: now);
        if (_byId.length > maxEntries) _dropOldest();
      }
      _changed();
    } catch (_) {
      // التشخيص لا يُسقط البرنامج أبداً
    } finally {
      _busy = false;
    }
  }

  static void _dropOldest() {
    final list = _byId.values.toList()..sort((a, b) => a.last.compareTo(b.last));
    for (final e in list.take(_byId.length - maxEntries)) {
      _byId.remove(e.id);
    }
  }

  static String _stripMarkers(String s) => s.replaceFirst(RegExp(r'^\s*(❌|🔴|⚠️)\s*'), '');

  static String _cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

  /// أول 25 سطراً من المكدّس — ما يكفي لمعرفة المكان.
  static String _trimStack(String s) {
    final lines = s.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return lines.length <= 25 ? lines.join('\n') : '${lines.take(25).join('\n')}\n…';
  }

  // ─────────────────────────── القراءة والإدارة ───────────────────────────

  /// كل الأخطاء، الأحدث أولاً.
  static List<ErrorEntry> get entries => _byId.values.toList()..sort((a, b) => b.last.compareTo(a.last));

  static int get unresolvedCount => _byId.values.where((e) => !e.resolved).length;

  static void setResolved(String id, bool resolved) {
    final e = _byId[id];
    if (e == null || e.resolved == resolved) return;
    e.resolved = resolved;
    _changed();
  }

  /// يمسح السجل كله (لا يمسّ dart_errors.log ولا native_errors.log).
  static void clear() {
    _byId.clear();
    _changed();
  }

  static bool _notifyQueued = false;

  static void _changed() {
    // الإشعار مؤجّل ومجمّع: خطأ يُسجَّل أثناء رسم شاشة لا يطلب إعادة رسم وسط الرسم
    if (!_notifyQueued) {
      _notifyQueued = true;
      scheduleMicrotask(() {
        _notifyQueued = false;
        changes.value++;
      });
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  /// يحفظ الآن (الحفظ العادي مؤجّل ثانيتين ليجمع الأخطاء المتتالية).
  static Future<void> save() async {
    final f = _file;
    if (f == null) return;
    try {
      final body = jsonEncode({
        'v': 1,
        'entries': [for (final e in entries) e.toJson()],
      });
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  // ─────────────────────────── أعطال ويندوز الأصلية ───────────────────────────

  /// الخروج المفاجئ من native_errors.log (آخر 512 كيلوبايت). ويندوز فقط.
  static Future<List<ErrorEntry>> nativeCrashes() async {
    if (kIsWeb || !Platform.isWindows) return const [];
    final dir = _dir;
    if (dir == null) return const [];
    final f = File('${dir.path}${Platform.pathSeparator}native_errors.log');
    try {
      if (!await f.exists()) return const [];
      final len = await f.length();
      final raf = await f.open();
      try {
        final start = len > 512 * 1024 ? len - 512 * 1024 : 0;
        await raf.setPosition(start);
        final bytes = await raf.read(len - start);
        return parseNative(utf8.decode(bytes, allowMalformed: true));
      } finally {
        await raf.close();
      }
    } catch (_) {
      return const [];
    }
  }

  static final _nativeHead = RegExp(
      r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.\d{3}\] (UNHANDLED - the app is closing|FATAL-TYPE exception \(first chance\)) '
      r'code=0x([0-9A-Fa-f]{8}) at (\S+?)\+0x');

  /// يقرأ نص native_errors.log ويعيد الخروج المفاجئ فقط، مجمّعاً (النوع + الرمز + الوحدة).
  /// استثناءات C++ «first chance» العادية لا تُعرض: كثير منها يعالجه البرنامج.
  @visibleForTesting
  static List<ErrorEntry> parseNative(String text) {
    final out = <String, ErrorEntry>{};
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      String? msg;
      DateTime? at;
      final m = _nativeHead.firstMatch(line);
      if (m != null) {
        at = DateTime.tryParse(m.group(1)!);
        final fatal = m.group(2)!.startsWith('UNHANDLED') ? 'خروج البرنامج' : 'عطل خطير';
        msg = '$fatal — الرمز 0x${m.group(3)!.toUpperCase()} في ${m.group(4)}';
      } else if (line.contains('[abort]')) {
        msg = 'خروج البرنامج — abort() / std::terminate';
      }
      if (msg == null) continue;
      final detail = lines.skip(i + 1).take(14).takeWhile((l) => !l.startsWith('[') && !l.startsWith('=====')).join('\n');
      final id = fingerprint(ErrorSource.native, msg);
      final when = at ?? DateTime.now();
      final e = out[id];
      if (e == null) {
        out[id] = ErrorEntry(
            id: id, source: ErrorSource.native, message: msg, detail: detail.trim().isEmpty ? null : detail, first: when, last: when);
      } else {
        e.count++;
        if (when.isAfter(e.last)) {
          e.last = when;
          if (detail.trim().isNotEmpty) e.detail = detail;
        }
      }
    }
    return out.values.toList();
  }

  // ─────────────────────────── الأدوات ───────────────────────────

  /// بصمة المجموعة: المصدر + الرسالة بعد إزالة ما يتغيّر (الأرقام والمعرّفات).
  static String fingerprint(String source, String message) {
    var s = message.toLowerCase();
    s = s.replaceAll(RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'), '#');
    s = s.replaceAll(RegExp(r'0x[0-9a-f]+'), '#');
    s = s.replaceAll(RegExp(r'[0-9٠-٩]+'), '#');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 200) s = s.substring(0, 200);
    // FNV-1a 32 بت — بصمة قصيرة ثابتة بين التشغيلات
    var h = 0x811c9dc5;
    for (final c in utf8.encode('$source|$s')) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static final List<(RegExp, String)> _secrets = [
    // رمز بوت تيليجرام (وفي رابط api.telegram.org/bot<token>/)
    (RegExp(r'\d{6,12}:[A-Za-z0-9_-]{30,}'), '[رمز بوت مخفي]'),
    // رموز في الروابط والنماذج
    (
      RegExp(r'\b((?:access_token|refresh_token|id_token|token|apikey|api_key|key|password|passwd|pass|secret|client_secret|code|auth)=)[^&\s"' "'" r']+',
          caseSensitive: false),
      r'$1***'
    ),
    (RegExp(r'(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false), r'$1 ***'),
    // رموز Dropbox وGoogle/Firebase وJWT
    (RegExp(r'\bsl\.[A-Za-z0-9_-]{20,}'), '***'),
    (RegExp(r'AIza[0-9A-Za-z_-]{30,}'), '***'),
    (RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'), '***'),
    // أي سلسلة طويلة تشبه مفتاحاً (لا تشمل «/» حتى لا تُمسح مسارات الكود في المكدّس)
    (RegExp(r'\b[A-Za-z0-9+_-]{40,}={0,2}'), '***'),
  ];

  /// يمحو الأسرار من النص قبل حفظه أو عرضه أو نسخه.
  static String sanitize(String s) {
    var out = s;
    for (final (re, rep) in _secrets) {
      out = out.replaceAllMapped(re, (m) {
        if (!rep.contains(r'$1')) return rep;
        return rep.replaceAll(r'$1', m.group(1) ?? '');
      });
    }
    return out;
  }

  @visibleForTesting
  static void resetForTest() {
    _byId.clear();
    _file = null;
    _dir = null;
    _saveTimer?.cancel();
    _saveTimer = null;
  }
}
