// lib/services/diagnostics/error_journal.dart
//
// 🩺 سجل أخطاء البرنامج لأداة «تشخيص الأخطاء» (الإعدادات ← النظام والأدوات).
//
// يجمع كل ما يمكن التقاطه آلياً:
//   • أخطاء Flutter (الشاشات) والأخطاء غير المعالَجة — من ErrorLog.install.
//   • الأخطاء التي عالجها البرنامج وكتبها بـ debugPrint: السطر الذي يبدأ بـ ❌ أو 🔴،
//     أو ⚠️ ومعه اسم استثناء (SocketException…). التنبيهات العادية لا تُسجَّل.
//   • أعطال ويندوز الأصلية (native_errors.log من crash_guard.cpp): الخروج المفاجئ فقط.
//   • كل رسالة خطأ حمراء ظهرت للمستخدم (ErrorCaptureMessenger حول كل الشاشات).
//   • كل نافذة خطأ ظهرت للمستخدم: «لم يكتمل رفع البيانات»، «تعذّر حفظ النسخة»… (ErrorDialogObserver).
//   • تجمّد البرنامج 4 ثوانٍ فأكثر، وتوقف عمليات الخلفية (خيط تيليجرام).
//   • بلاغ المستخدم مع صورة الشاشة (Ctrl+Shift+E في أي شاشة): لما لا يرافقه خطأ، كزر لم يعمل.
// وكل خطأ يُرفق به آخر الشاشات التي فتحها المستخدم.
//
// لا يُلتقط: ما يُسكته الكود عمداً (catch (_) {})، والخروج المفاجئ على أندرويد (السجل الأصلي لويندوز).
//   • ما يسجّله الكود يدوياً: ErrorJournal.record(...).
//
// الأخطاء المتشابهة (تختلف بالأرقام فقط) مدخل واحد بعدد مرات حدوثها.
// 🔒 قبل الحفظ تُمحى الأسرار: رموز البوتات، رموز Dropbox وFirebase، كلمات المرور والرموز
//    في الروابط… (sanitize). لا يغيّر سلوك البرنامج ولا يلمس قاعدة البيانات:
//    ملف JSON صغير بجانب dart_errors.log (alnaser_logs\error_journal.json).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// مصدر الخطأ.
class ErrorSource {
  ErrorSource._();
  static const flutter = 'flutter'; // خطأ في رسم شاشة
  static const uncaught = 'uncaught'; // خطأ لم يعالجه البرنامج
  static const logged = 'logged'; // خطأ عالجه البرنامج وسجّله
  static const native = 'native'; // عطل أصلي في ويندوز (خروج مفاجئ)
  static const shown = 'shown'; // رسالة خطأ حمراء ظهرت للمستخدم
  static const dialog = 'dialog'; // نافذة خطأ ظهرت للمستخدم (لم يكتمل الرفع، تعذّر الحفظ…)
  static const freeze = 'freeze'; // البرنامج تجمّد ولم يستجب
  static const report = 'report'; // بلاغ كتبه المستخدم (الزر لم يعمل…)
  static const background = 'background'; // عملية في الخلفية توقفت
  static const manual = 'manual';

  static String label(String s) => switch (s) {
        flutter => 'خطأ في الشاشة',
        uncaught => 'خطأ غير معالَج',
        logged => 'خطأ عالجه البرنامج',
        native => 'خروج مفاجئ (ويندوز)',
        shown => 'رسالة ظهرت للمستخدم',
        dialog => 'نافذة خطأ ظهرت للمستخدم',
        freeze => 'تجمّد البرنامج',
        report => 'بلاغ من المستخدم',
        background => 'عملية في الخلفية',
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
    this.attachment,
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

  /// صورة الشاشة المرفقة ببلاغ المستخدم (مسار ملف PNG على هذا الجهاز).
  final String? attachment;

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
        if (attachment != null) 'attachment': attachment,
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
      attachment: j['attachment'] as String?,
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
          final ack = j is Map ? j['nativeAck'] : null;
          if (ack is Map) {
            for (final e in ack.entries) {
              final t = DateTime.tryParse('${e.value}');
              if (t != null) _nativeAck['${e.key}'] = t;
            }
          }
        }
      } catch (_) {
        // ملف تالف: نبدأ سجلاً جديداً (لا شيء يعتمد عليه)
      }
    }
    _hookDebugPrint();
    startFreezeWatch();
    await _markSession();
  }

  // ─────────────────────────── جلسة التطوير وتاريخ البناء ───────────────────────────

  /// البرنامج يعمل من «flutter run» (نسخة تطوير لا نسخة الزبائن).
  static bool get devSession => kDebugMode;

  /// وقت بناء البرنامج الحالي (تاريخ تعديل ملف البرنامج) — الخطأ الأقدم منه حدث في نسخة سابقة
  /// وقد يكون أُصلح. null إن تعذّر معرفته.
  static DateTime? buildTime;

  /// أرقام العمليات (pid) التي عملت كجلسة تطوير — خروجها المفاجئ غالباً إيقاف من الطرفية
  /// أو أثر Hot Restart، لا عطل عند الزبائن.
  static final Set<int> _devPids = {};

  static Future<void> _markSession() async {
    if (kIsWeb) return;
    try {
      final exe = File(Platform.resolvedExecutable);
      if (await exe.exists()) buildTime = await exe.lastModified();
    } catch (_) {}
    final dir = _dir;
    if (dir == null) return;
    final f = File('${dir.path}${Platform.pathSeparator}dev_sessions.txt');
    try {
      if (await f.exists()) {
        for (final l in await f.readAsLines()) {
          final n = int.tryParse(l.split(' ').first.trim());
          if (n != null) _devPids.add(n);
        }
      }
      if (devSession && !_devPids.contains(pid)) {
        _devPids.add(pid);
        // آخر 200 جلسة فقط
        final keep = (_devPids.toList()..sort()).reversed.take(200).toList();
        await f.writeAsString('${keep.map((x) => '$x').join('\n')}\n', flush: true);
      }
    } catch (_) {}
  }

  /// هل الخطأ حدث قبل بناء النسخة الحالية؟ (قد يكون أُصلح في التحديث)
  static bool beforeThisBuild(ErrorEntry e) {
    final b = buildTime;
    return b != null && e.last.isBefore(b.subtract(const Duration(seconds: 5)));
  }

  // ─────────────────────────── آخر ما فعله البرنامج ───────────────────────────

  /// آخر أسطر السجل (debugPrint) قبل الخطأ — تُرفق بالتجمّد والأخطاء غير المعالَجة وأخطاء
  /// الشاشة لتدلّ على ما كان البرنامج يفعله لحظتها.
  static final List<String> _recent = [];

  static void _remember(String line) {
    final t = line.trim();
    if (t.isEmpty) return;
    final now = DateTime.now().toIso8601String().substring(11, 19);
    _recent.add('$now  ${t.length > 220 ? '${t.substring(0, 220)}…' : t}');
    if (_recent.length > 12) _recent.removeAt(0);
  }

  static String? get _recentBlock => _recent.isEmpty ? null : 'آخر ما سجّله البرنامج قبلها:\n${_recent.join('\n')}';

  static void _hookDebugPrint() {
    if (_hooked) return;
    _hooked = true;
    final prev = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      prev(message, wrapWidth: wrapWidth);
      if (message != null && !_busy && looksLikeError(message)) {
        recordText(ErrorSource.logged, message);
      }
      if (message != null && !_busy) _remember(message.split('\n').first);
    };
  }

  // ─────────────────────────── التسجيل ───────────────────────────

  static final _exceptionName = RegExp(r'\b\w*(Exception|Error)\b');

  // كلمات الفشل (العربية بلا \b: حدود الكلمات في RegExp للأحرف اللاتينية فقط)
  static final _failure = RegExp(
      r'فشل|تعذّر|تعذر|خطأ|لم يكتمل|لم ينجح|توقف عن العمل|\b\w*(Exception|Error)\b|\bfailed\b|\bfailure\b|\berror\b',
      caseSensitive: false);
  static final _notError = RegExp(
      r'^(✅|ℹ️|📊|💡|🟢)|بلا (أخطاء|خطأ)|لا (أخطاء|خطأ)|دون (أخطاء|خطأ)|\b0 errors?\b|\bno errors?\b|errors?: 0\b',
      caseSensitive: false);

  /// هل هذا السطر من debugPrint خطأ يستحق التسجيل؟
  /// ❌ و🔴 دائماً؛ وأي سطر آخر فيه فشل أو استثناء (فشل، تعذّر، خطأ، Exception، failed…)
  /// إلا ما يقول صراحة إنه نجاح أو «بلا أخطاء».
  static bool looksLikeError(String line) {
    final t = line.trimLeft();
    if (t.isEmpty) return false;
    if (t.startsWith('❌') || t.startsWith('🔴')) return true;
    if (_notError.hasMatch(t)) return false;
    return _failure.hasMatch(t) || _exceptionName.hasMatch(t);
  }

  // ─────────────────────────── الشاشة الحالية (للسياق) ───────────────────────────

  static final List<String> _screens = [];

  /// الشاشة المفتوحة الآن (من ErrorDialogObserver).
  static String? get currentScreen => _screens.isEmpty ? null : _screens.last;

  /// يسجّل فتح شاشة (آخر 6 شاشات تُرفق بكل خطأ).
  static void screenOpened(String name) {
    if (_screens.isNotEmpty && _screens.last == name) return;
    _screens.add(name);
    if (_screens.length > 6) _screens.removeAt(0);
  }

  static String? get _trail => _screens.isEmpty ? null : 'الشاشات الأخيرة: ${_screens.join(' ← ')}';

  // ─────────────────────────── التجمّد ───────────────────────────

  static Timer? _watch;
  static DateTime? _tick;

  /// يراقب تجمّد البرنامج: مؤقت كل ثانية؛ إن تأخر 4 ثوانٍ فأكثر فالبرنامج كان متجمّداً
  /// (لا يستجيب للضغط ولا يرسم). فجوة أكثر من دقيقتين = نوم الحاسبة، لا تجمّد.
  static void startFreezeWatch() {
    if (_watch != null) return;
    _tick = DateTime.now();
    _watch = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final gap = now.difference(_tick ?? now);
      _tick = now;
      final sec = freezeSeconds(gap);
      if (sec != null) {
        recordText(
            ErrorSource.freeze,
            devSession
                ? 'تجمّد البرنامج $sec ثانية — لم يستجب للضغط ولا للرسم (جلسة تطوير: قد يكون توقفاً عند نقطة توقف أو Hot Reload)'
                : 'تجمّد البرنامج $sec ثانية — لم يستجب للضغط ولا للرسم');
      }
    });
  }

  /// كم ثانية تجمّد البرنامج إن كانت الفجوة بين نبضتين [gap] تدل على تجمّد، وإلا null.
  @visibleForTesting
  static int? freezeSeconds(Duration gap) {
    final s = gap.inMilliseconds / 1000.0 - 1;
    if (s < 4 || s > 120) return null;
    return s.round();
  }

  // ─────────────────────────── بلاغ المستخدم ───────────────────────────

  /// يحفظ صورة الشاشة للبلاغ (آخر 30 صورة فقط). null إن لا مجلد سجلات.
  static Future<String?> saveAttachment(Uint8List png) async {
    final dir = _dir;
    if (dir == null) return null;
    try {
      final d = Directory('${dir.path}${Platform.pathSeparator}reports');
      if (!await d.exists()) await d.create(recursive: true);
      final f = File('${d.path}${Platform.pathSeparator}report_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(png, flush: true);
      final all = (await d.list().toList()).whereType<File>().where((x) => x.path.endsWith('.png')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final old in all.take(all.length > 30 ? all.length - 30 : 0)) {
        try {
          await old.delete();
        } catch (_) {}
      }
      return f.path;
    } catch (_) {
      return null;
    }
  }

  static int _reportSeq = 0;

  /// بلاغ كتبه المستخدم («ضغطت حفظ ولم يحدث شيء»). كل بلاغ مدخل مستقل.
  static void recordReport(String text, {String? attachment, String? screen}) {
    final now = DateTime.now();
    final id = 'r${now.microsecondsSinceEpoch}_${_reportSeq++}'; // بلاغان في اللحظة نفسها لا يتداخلان
    final detail = [
      if (screen != null) 'الشاشة: $screen',
      if (_trail != null) _trail!,
    ].join('\n');
    _byId[id] = ErrorEntry(
      id: id,
      source: ErrorSource.report,
      message: _cut(sanitize(text.trim().isEmpty ? 'بلاغ بلا وصف' : text.trim()), _maxMessage),
      detail: detail.isEmpty ? null : detail,
      first: now,
      last: now,
      attachment: attachment,
    );
    if (_byId.length > maxEntries) _dropOldest();
    _changed();
    unawaited(save());
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
      final trail = _trail;
      final ctx = const {ErrorSource.freeze, ErrorSource.uncaught, ErrorSource.flutter, ErrorSource.background}.contains(source)
          ? _recentBlock
          : null;
      final raw = [
        if (detail != null && detail.trim().isNotEmpty) detail,
        if (trail != null) trail,
        if (ctx != null) ctx,
      ].join('\n');
      final d = raw.isEmpty ? null : _cut(sanitize(raw), _maxDetail);
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

  // الخروج المفاجئ يُقرأ من ملف ويندوز في كل مرة: «أُغلق» = حتى آخر حدوث رآه المستخدم
  static final Map<String, DateTime> _nativeAck = {};

  /// «عرفت الخطأ — أغلقه» لخطأ من أي مصدر: يختفي من القائمة ويعود إن تكرّر.
  static void dismiss(ErrorEntry e) {
    if (e.source == ErrorSource.native) {
      _nativeAck[e.id] = e.last;
      e.resolved = true;
      _changed();
    } else {
      setResolved(e.id, true);
    }
  }

  /// يعيد خطأً مغلقاً إلى القائمة.
  static void reopen(ErrorEntry e) {
    if (e.source == ErrorSource.native) {
      _nativeAck.remove(e.id);
      e.resolved = false;
      _changed();
    } else {
      setResolved(e.id, false);
    }
  }

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
        if (_nativeAck.isNotEmpty) 'nativeAck': {for (final e in _nativeAck.entries) e.key: e.value.toIso8601String()},
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
        final text = utf8.decode(bytes, allowMalformed: true);
        // جلسات قديمة قبل تسجيل dev_sessions.txt: إعادة تشغيل Dart داخل العملية نفسها
        // (Hot Restart) لا تحدث إلا في «flutter run» ⇒ جلسة تطوير.
        final hot = hotRestartPids(text, await _tailOf(File('${dir.path}${Platform.pathSeparator}dart_errors.log')));
        final list = parseNative(text, devPids: {..._devPids, ...hot});
        for (final e in list) {
          final ack = _nativeAck[e.id];
          if (ack != null && !e.last.isAfter(ack)) e.resolved = true; // أُغلق ولم يتكرر بعدها
        }
        return list;
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

  static Future<String> _tailOf(File f, [int max = 512 * 1024]) async {
    try {
      if (!await f.exists()) return '';
      final len = await f.length();
      final raf = await f.open();
      try {
        final start = len > max ? len - max : 0;
        await raf.setPosition(start);
        return utf8.decode(await raf.read(len - start), allowMalformed: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '';
    }
  }

  static final _dartStart = RegExp(r'^\[(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})[^\]]*\] ===== start');

  /// العمليات التي بدأ فيها Dart أكثر من مرة (Hot Restart) — من native_errors.log (بدء العملية)
  /// وdart_errors.log (بدء Dart). لا تحدث إعادة التشغيل هذه في نسخة الزبائن.
  @visibleForTesting
  static Set<int> hotRestartPids(String nativeText, String dartText) {
    final starts = <(DateTime, int)>[];
    for (final l in nativeText.split('\n')) {
      final m = _nativeStartAt.firstMatch(l.trimRight());
      if (m == null) continue;
      final t = DateTime.tryParse('${m.group(1)}T${m.group(2)}');
      final id = int.tryParse(m.group(3)!);
      if (t != null && id != null) starts.add((t, id));
    }
    if (starts.isEmpty) return const {};
    starts.sort((a, b) => a.$1.compareTo(b.$1));
    final dartStarts = <DateTime>[];
    for (final l in dartText.split('\n')) {
      final m = _dartStart.firstMatch(l);
      final t = m == null ? null : DateTime.tryParse('${m.group(1)}T${m.group(2)}');
      if (t != null) dartStarts.add(t);
    }
    final out = <int>{};
    for (var i = 0; i < starts.length; i++) {
      final from = starts[i].$1.subtract(const Duration(seconds: 5));
      final to = i + 1 < starts.length ? starts[i + 1].$1.subtract(const Duration(seconds: 5)) : DateTime(9999);
      final n = dartStarts.where((t) => !t.isBefore(from) && t.isBefore(to)).length;
      if (n >= 2) out.add(starts[i].$2);
    }
    return out;
  }

  static final _nativeStartAt = RegExp(r'^===== (\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) start \(pid (\d+)\) =====');

  static final _nativeStart = RegExp(r'^===== .* start \(pid (\d+)\) =====');

  /// بادئة الخروج المفاجئ في جلسة تطوير (يطابقها دليل الحلول «crash_dev»).
  static const msgPrefixDev = 'أثناء جلسة تطوير — ';

  /// يقرأ نص native_errors.log ويعيد الخروج المفاجئ فقط، مجمّعاً (النوع + الرمز + الوحدة).
  /// استثناءات C++ «first chance» العادية لا تُعرض: كثير منها يعالجه البرنامج.
  /// [devPids] للاختبار: عمليات التطوير (وإلا المسجّلة في dev_sessions.txt).
  @visibleForTesting
  static List<ErrorEntry> parseNative(String text, {Set<int>? devPids}) {
    final out = <String, ErrorEntry>{};
    final lines = text.split('\n');
    int? curPid; // العملية التي يخصّها ما يلي من أسطر («===== … start (pid N) =====»)
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      final st = _nativeStart.firstMatch(line);
      if (st != null) {
        curPid = int.tryParse(st.group(1)!);
        continue;
      }
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
      // 🧑‍💻 العملية كانت جلسة تطوير (flutter run): إيقافها من الطرفية أو بعد Hot Restart يظهر
      //    هنا كخروج مفاجئ — يُفصل عن أعطال نسخة الزبائن الحقيقية.
      if (curPid != null && (devPids ?? _devPids).contains(curPid)) msg = '$msgPrefixDev$msg';
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
    _devPids.clear();
    _recent.clear();
    buildTime = null;
    _byId.clear();
    _file = null;
    _dir = null;
    _saveTimer?.cancel();
    _saveTimer = null;
    _screens.clear();
    _nativeAck.clear();
  }
}
