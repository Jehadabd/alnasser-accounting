// lib/services/firebase_sync/windowed_listener.dart
//
// 👂 مستمع Firestore «بنافذة زمنية» بساعة السيرفر (uploadedAt).
//
// المشكلة التي يحلّها (وجدها اختبار التحمّل على 5000 فاتورة):
//   المستمع على مجموعة كاملة يُرسل في كل حدث **كل وثائق المجموعة** إلى Dart
//   (هكذا تعمل مكتبة cloud_firestore)، لا التغيير وحده. فمع آلاف الفواتير صار
//   رفع فاتورة واحدة يكلّف نقل آلاف الوثائق، وانهارت سرعة الرفع من 54 فاتورة
//   في الدقيقة إلى 4. وكل فتح للبرنامج كان يقرأ المجموعة كلها من جديد
//   (آلاف القراءات من الحصة اليومية).
//
// الحل:
//   • نستمع فقط للوثائق التي رُفعت منذ «آخر ما عالجناه» (يُحفظ محلياً) ناقص هامش.
//     uploadedAt = FieldValue.serverTimestamp() — ساعة السيرفر، فلا يؤثر اختلاف
//     ساعات الأجهزة (سبب إلغاء الفلتر الزمني القديم المبني على ساعة الجهاز).
//   • حين تكبر النافذة (رفع كثيف) نعيد تثبيتها على آخر ما عولج: نفتح المستمع
//     الجديد أولاً ثم نغلق القديم، فلا فجوة (التكرار آمن: المعالجة إدمبوتنت).
//   • جهاز بلا «آخر ما عولج» (جديد أو أول تشغيل بهذا الإصدار): مستمع كامل
//     كالسابق مرة واحدة، ثم يُعاد تثبيته على نافذة صغيرة.
//   • انقطاع الإنترنت: مستمع Firestore يستأنف وحده ويُسلّم كل ما رُفع أثناء
//     الانقطاع (النافذة تبدأ قبله). إعادة التشغيل: تبدأ النافذة من المحفوظ.
//   • شبكة أمان: سحب كامل مرة كل 24 ساعة (performFullCatchUp) لأي وثيقة
//     كُتبت بمسار لا يضع uploadedAt.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../database_service.dart';

import 'sync_breadcrumbs.dart';

typedef WindowedSnapshotHandler = Future<void> Function(QuerySnapshot<Map<String, dynamic>> snapshot);

class WindowedListener {
  WindowedListener({
    required this.firestore,
    required this.collection,
    required this.onSnapshot,
    required this.onError,
    this.field = 'uploadedAt',
    // الهامش: الطابع الزمني يضعه السيرفر لحظة الحفظ عنده (حتى لجهاز كان
    // مقطوعاً)، فدقائق قليلة تكفي. وكل إعادة تثبيت تعيد قراءة وثائق الهامش،
    // فهامش كبير + تثبيت متكرر كان يستهلك حصة القراءة (اختبار التحمّل).
    this.margin = const Duration(minutes: 3),
    this.reanchorAbove = 500,
    this.checkEvery = const Duration(minutes: 5),
  });

  final FirebaseFirestore firestore;
  final String collection;
  final WindowedSnapshotHandler onSnapshot;
  final void Function(Object error) onError;
  final String field;
  final Duration margin;
  final int reanchorAbove;
  final Duration checkEvery;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Timer? _timer;
  Timer? _saveTimer;
  Timestamp? _since;
  int? _processedMax; // أحدث uploadedAt (بالملّي) عولجت وثيقته بالكامل
  int _lastSize = 0;
  int _gen = 0;
  Future<void> _chain = Future.value();

  bool get active => _sub != null;
  int get windowSize => _lastSize;

  // «آخر ما عولج» يُحفظ داخل قاعدة البيانات نفسها لا في الإعدادات: حذف القاعدة
  // أو استبدالها يُنسيه تلقائياً، فتُنزَّل البيانات كاملة من جديد.
  static bool _tableReady = false;

  static Future<void> _ensureTable() async {
    if (_tableReady) return;
    final db = await DatabaseService().database;
    await db.execute('CREATE TABLE IF NOT EXISTS sync_listener_hwm ('
        'collection TEXT PRIMARY KEY, ms INTEGER NOT NULL)');
    _tableReady = true;
  }

  static Future<int?> loadHwm(String collection) async {
    try {
      await _ensureTable();
      final db = await DatabaseService().database;
      final r = await db.query('sync_listener_hwm',
          columns: ['ms'], where: 'collection = ?', whereArgs: [collection], limit: 1);
      return r.isEmpty ? null : (r.first['ms'] as num).toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveHwm(String collection, int ms) async {
    try {
      await _ensureTable();
      final db = await DatabaseService().database;
      await db.rawInsert(
          'INSERT INTO sync_listener_hwm(collection, ms) VALUES(?, ?) '
          'ON CONFLICT(collection) DO UPDATE SET ms = MAX(ms, excluded.ms)',
          [collection, ms]);
    } catch (_) {}
  }

  /// يُنسى «آخر ما عولج» لكل المجموعات (استعادة نسخة احتياطية…)
  static Future<void> resetAll() async {
    try {
      await _ensureTable();
      final db = await DatabaseService().database;
      await db.delete('sync_listener_hwm');
    } catch (_) {}
  }

  Future<void> start() async {
    await stop();
    final hwm = await loadHwm(collection);
    _processedMax = hwm;
    _since = hwm == null ? null : Timestamp.fromMillisecondsSinceEpoch(hwm - margin.inMilliseconds);
    _listen();
    _timer = Timer.periodic(checkEvery, (_) => _maybeReanchor());
    SyncCrumb.mark('window:$collection start since=${_since?.toDate().toIso8601String() ?? 'FULL'}');
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _gen++;
    final s = _sub;
    _sub = null;
    await s?.cancel();
    await _persist();
  }

  void _listen() {
    final gen = ++_gen;
    Query<Map<String, dynamic>> q = firestore.collection(collection);
    final since = _since;
    if (since != null) q = q.where(field, isGreaterThanOrEqualTo: since);
    final old = _sub;
    _sub = q.snapshots().listen((snap) {
      _lastSize = snap.size;
      // معالجة متسلسلة: حدث بعد حدث، و«آخر ما عولج» لا يتقدم إلا بعد اكتمال المعالجة
      _chain = _chain.then((_) async {
        await onSnapshot(snap);
        var mx = _processedMax;
        for (final c in snap.docChanges) {
          if (c.doc.metadata.hasPendingWrites) continue;
          final t = c.doc.data()?[field];
          if (t is Timestamp) {
            final ms = t.millisecondsSinceEpoch;
            if (mx == null || ms > mx) mx = ms;
          }
        }
        if (mx != _processedMax) {
          _processedMax = mx;
          _schedulePersist();
        }
      }).catchError((Object e) {
        print('⚠️ [نافذة $collection] خطأ معالجة: $e');
      });
    }, onError: (Object e) {
      if (gen != _gen) return; // مستمع قديم أُغلق بإعادة التثبيت
      onError(e);
    });
    // إعادة تثبيت: المستمع الجديد يعمل قبل إغلاق القديم — لا فجوة
    if (old != null) unawaited(old.cancel());
  }

  void _schedulePersist() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 3), () => unawaited(_persist()));
  }

  Future<void> _persist() async {
    final v = _processedMax;
    if (v == null) return;
    await saveHwm(collection, v);
  }

  Future<void> _maybeReanchor() async {
    final mx = _processedMax;
    if (_sub == null || mx == null || _lastSize <= reanchorAbove) return;
    final newSince = Timestamp.fromMillisecondsSinceEpoch(mx - margin.inMilliseconds);
    final since = _since;
    if (since != null && newSince.compareTo(since) <= 0) return;
    await _persist();
    _since = newSince;
    SyncCrumb.mark('window:$collection reanchor size=$_lastSize since=${newSince.toDate().toIso8601String()}');
    print('👂 [نافذة $collection] إعادة تثبيت المستمع (كان $_lastSize وثيقة)');
    _listen();
  }
}
