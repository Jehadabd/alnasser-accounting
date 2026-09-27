// lib/services/firebase_sync/stock_movement_sync_service.dart
//
// 📦 مزامنة حركات المخزون (دفتر المخزون المشترك — StockLedger).
//
// • مجموعة Firestore: stock_movements/{movement_uuid}. الحركة لا تُعدَّل أبداً
//   (التصحيح حركة جديدة)، فالاستقبال «أدرج إن لم يوجد» والتكرار آمن.
// • الرصيد الافتتاحي opening_<منتج> معرّفه ثابت للمجموعة كلها: يُرفع داخل
//   معاملة Firestore «أنشئ إن غاب»، وأول جهاز يثبّته. من يجد غيره سبقه يتبنّى
//   قيمته — فلا يتكرر الرصيد الافتتاحي ولا تختلف الأجهزة عليه.
// • التنظيف الذكي (SmartPipe) لا يلمس هذه المجموعة: الجهاز الجديد أو المستعيد
//   يحتاج كل الحركات ليحسب الكمية نفسها.
// • المستقبِل يعيد حساب كمية المنتج في نفس معاملة SQLite (مشغّلات الدفتر).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';

import '../database_service.dart';
import '../database/business/stock_ledger.dart';
import 'firebase_sync_config.dart';
import 'firebase_sync_service.dart';
import 'sync_health.dart';

class StockMovementSyncService {
  static final StockMovementSyncService _instance = StockMovementSyncService._internal();
  factory StockMovementSyncService() => _instance;
  StockMovementSyncService._internal() {
    StockLedger.onMovementAdded = uploadPendingSoon;
  }

  static const String collectionName = 'stock_movements';

  FirebaseFirestore? _fs;
  FirebaseFirestore get _firestore => _fs ??= FirebaseFirestore.instance;
  final DatabaseService _db = DatabaseService();

  StreamSubscription? _sub;
  Timer? _debounce;
  bool _uploading = false;
  bool _uploadAgain = false;
  bool _started = false;

  /// 🛡️ المستمع يلتقط ما يُرفع من الآن فقط (بعد أحدث حركة في السحابة، بهامش
  /// ساعة)، وما قبله يكمله [downloadMissing]. كان المستمع يقرأ المجموعة كلها
  /// عند كل تشغيل، وهي تكبر بلا حدّ (SmartPipe لا ينظّفها عمداً): كلفة قراءة
  /// تزيد مع عمر المحل. تعذّر أيٌّ من الخطوتين = المستمع الكامل كما كان.
  Future<void> start() async {
    if (_started) return;
    if (!await FirebaseSyncConfig.isEnabled()) return;
    _started = true;
    await _sub?.cancel();
    _sub = null;
    final col = _firestore.collection(collectionName);
    final since = await _listenSince();
    if (since != null) {
      try {
        _listen(col.where('uploadedAt', isGreaterThanOrEqualTo: since));
        await downloadMissing(rethrowErrors: true);
      } catch (e) {
        print('⚠️ [حركات المخزون] الاستماع الجزئي تعذّر ($e) — مستمع كامل');
        await _sub?.cancel();
        _sub = null;
      }
    }
    if (_sub == null) _listen(col);
    unawaited(uploadPending().catchError((_) => 0));
  }

  void _listen(Query<Map<String, dynamic>> q) {
    _sub = q.snapshots().listen((snap) async {
      for (final c in snap.docChanges) {
        if (c.type == DocumentChangeType.removed) continue;
        final d = c.doc.data();
        if (d == null) continue;
        try {
          await applyRemote(c.doc.id, d);
        } catch (e) {
          print('⚠️ [حركات المخزون] تعذّر تطبيق ${c.doc.id}: $e');
        }
      }
    }, onError: (Object e) {
      SyncHealth.reportUploadError(collectionName, e);
      print('⚠️ [حركات المخزون] خطأ الاستماع: $e');
    });
  }

  /// مستند الحركة في السحابة من صفها المحلي.
  static Map<String, dynamic> _movementDoc(Map<String, Object?> r, String me) => {
        'movementUuid': r['movement_uuid'],
        'productSyncUuid': r['product_sync_uuid'],
        'delta': (r['delta'] as num).toDouble(),
        'kind': r['kind'],
        'note': r['note'],
        'createdAt': r['created_at'],
        'originDeviceId': (r['origin_device_id'] as String?) ?? me,
        'uploadedAt': FieldValue.serverTimestamp(),
      };

  /// بداية نافذة المستمع: وقت رفع أحدث حركة في السحابة (بساعة السيرفر لا
  /// بساعة الجهاز) ناقص ساعة. null = السحابة فارغة أو تعذّر السؤال.
  Future<Timestamp?> _listenSince() async {
    try {
      final q = await _firestore
          .collection(collectionName)
          .orderBy('uploadedAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (q.docs.isEmpty) return null;
      final t = q.docs.first.data()['uploadedAt'];
      if (t is! Timestamp) return null;
      return Timestamp.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch - 3600 * 1000);
    } catch (e) {
      print('⚠️ [حركات المخزون] تعذّر معرفة أحدث حركة: $e');
      return null;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _debounce?.cancel();
    _started = false;
  }

  /// رفع مؤجَّل قليلاً: الحركة تُسجَّل غالباً داخل معاملة SQLite لم تكتمل بعد.
  void uploadPendingSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(uploadPending().catchError((_) => 0));
    });
  }

  /// يرفع الحركات المحلية غير المرفوعة. تُرجع عدد ما رُفع.
  Future<int> uploadPending() async {
    if (!await FirebaseSyncConfig.isEnabled()) return 0;
    // وضع الاستعادة: حركات النسخة الاحتياطية رُفعت قبلها غالباً؛ رفعها ثانيةً
    // آمن (نفس المعرّف والمحتوى)، لكن الرصيد الافتتاحي قد يكون أقدم — نؤجّل
    // حتى تكتمل المقارنة كبقية الرفع.
    if (_isRecovering()) return 0;
    if (_uploading) {
      _uploadAgain = true;
      return 0;
    }
    _uploading = true;
    var n = 0;
    try {
      do {
        _uploadAgain = false;
        final db = await _db.database;
        final me = await FirebaseSyncConfig.getDeviceId();
        final rows = await db.query('stock_movements', where: 'is_uploaded = 0', limit: 400);
        for (final r in rows) {
          final uuid = r['movement_uuid'] as String;
          try {
            final doc = _movementDoc(r, me);
            final ref = _firestore.collection(collectionName).doc(uuid);
            if (r['kind'] == StockLedger.openingKind) {
              // أول من يثبّت الرصيد الافتتاحي يربح؛ غيره يتبنّى قيمته
              final winner = await _firestore.runTransaction<Map<String, dynamic>?>((txn) async {
                final snap = await txn.get(ref);
                if (snap.exists) return snap.data();
                txn.set(ref, doc);
                return null;
              }).timeout(const Duration(seconds: 30));
              if (winner != null) {
                await _adoptOpening(db, uuid, winner);
                n++;
                continue;
              }
            } else {
              await ref.set(doc).timeout(const Duration(seconds: 30));
            }
            SyncHealth.reportUploadOk(collectionName);
            await db.update('stock_movements', {'is_uploaded': 1},
                where: 'movement_uuid = ?', whereArgs: [uuid]);
            n++;
          } catch (e) {
            SyncHealth.reportUploadError(collectionName, e);
            print('⚠️ [حركات المخزون] تعذّر رفع $uuid: $e (يُعاد لاحقاً)');
          }
        }
        if (rows.length == 400) _uploadAgain = true;
      } while (_uploadAgain);
    } finally {
      _uploading = false;
    }
    return n;
  }

  /// سحب ما ينقص هذا الجهاز فقط. كل حركة مؤشَّرة «مرفوعة» هنا (is_uploaded = 1)
  /// موجودة في السحابة (لا شيء يحذف الحركات)، فتساوي العددين يعني أن لا شيء
  /// ينقص — وعدّ السحابة قراءة واحدة لكل ألف حركة بدل قراءة كل حركة.
  /// عند الاختلاف أو التعذّر: سحب كامل كما كان.
  Future<int> downloadMissing({bool rethrowErrors = false}) async {
    try {
      final agg = await _firestore
          .collection(collectionName)
          .count()
          .get(source: AggregateSource.server)
          .timeout(const Duration(seconds: 30));
      final db = await _db.database;
      final local = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM stock_movements WHERE is_uploaded = 1')) ??
          0;
      if ((agg.count ?? -1) == local) return 0;
    } catch (e) {
      print('⚠️ [حركات المخزون] تعذّر العدّ ($e) — سحب كامل');
    }
    return downloadAll(rethrowErrors: rethrowErrors);
  }

  /// تنزيل كل الحركات (سحب كامل / تمهيد جهاز جديد أو مستعيد).
  Future<int> downloadAll({bool rethrowErrors = false}) async {
    try {
      final snap = await _firestore
          .collection(collectionName)
          .get(const GetOptions(source: Source.server));
      var n = 0;
      for (final d in snap.docs) {
        try {
          if (await applyRemote(d.id, d.data())) n++;
        } catch (e) {
          print('⚠️ [حركات المخزون] تعذّر تطبيق ${d.id}: $e');
        }
      }
      // القائمة كاملة من السيرفر: ما رُفع من هنا وغاب منها يُعاد
      unawaited(_recreateMissing(snap.docs.map((d) => d.id).toSet()).catchError((_) => 0));
      return n;
    } catch (e) {
      print('❌ [حركات المخزون] فشل التنزيل: $e');
      if (rethrowErrors) rethrow;
      return 0;
    }
  }

  /// لجهاز جديد/مستعيد (FirebaseSyncService.rebroadcastEverything): يعيد إنشاء
  /// ما غاب من السحابة قبل أن ينزّله. العدّ أولاً، فلا كلفة في الحالة العادية.
  Future<int> rebroadcastMissing() async {
    final db = await _db.database;
    final local = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM stock_movements WHERE is_uploaded = 1')) ??
        0;
    if (local == 0) return 0;
    final agg = await _firestore
        .collection(collectionName)
        .count()
        .get(source: AggregateSource.server)
        .timeout(const Duration(seconds: 30));
    if ((agg.count ?? 0) >= local) return 0;
    final snap = await _firestore
        .collection(collectionName)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 60));
    return _recreateMissing(snap.docs.map((d) => d.id).toSet());
  }

  /// 🛡️ يعيد إنشاء حركات «مرفوعة» هنا غابت من السحابة — «أنشئ إن غاب»، لا
  /// يكتب فوق مستند قائم. لا شيء في التطبيق يحذف الحركات، فغيابها = بيانات
  /// السحابة حُذفت من خارج التطبيق (لوحة Firebase) أو نُقلت المجموعة لمشروع
  /// جديد؛ وبدونها يحسب الجهاز الجديد كمية خاطئة. الرصيد الافتتاحي يُعاد بقيمته
  /// المعتمدة (التي تبنّاها هذا الجهاز).
  Future<int> _recreateMissing(Set<String> cloudIds) async {
    final db = await _db.database;
    final rows = (await db.query('stock_movements', where: 'is_uploaded = 1'))
        .where((r) => !cloudIds.contains(r['movement_uuid']))
        .toList();
    if (rows.isEmpty) return 0;
    final me = await FirebaseSyncConfig.getDeviceId();
    var n = 0;
    for (final r in rows) {
      final uuid = r['movement_uuid'] as String;
      try {
        final ref = _firestore.collection(collectionName).doc(uuid);
        final doc = _movementDoc(r, me);
        final created = await _firestore.runTransaction<bool>((txn) async {
          final snap = await txn.get(ref);
          if (snap.exists) return false;
          txn.set(ref, doc);
          return true;
        }).timeout(const Duration(seconds: 30));
        if (created) n++;
      } catch (e) {
        print('⚠️ [حركات المخزون] إعادة إنشاء $uuid: $e');
      }
    }
    if (n > 0) print('📦 [حركات المخزون] أُعيد إنشاء $n حركة غابت من السحابة');
    return n;
  }

  /// يطبّق حركة واردة. تُرجع true إن غيّرت شيئاً.
  Future<bool> applyRemote(String id, Map<String, dynamic> data) async {
    final product = data['productSyncUuid'] as String?;
    final delta = (data['delta'] as num?)?.toDouble();
    final kind = data['kind'] as String?;
    if (product == null || product.isEmpty || delta == null || kind == null) return false;
    if (!delta.isFinite || delta.abs() > 1e9) return false;
    final db = await _db.database;
    if (kind == StockLedger.openingKind) {
      if (id != StockLedger.openingUuid(product)) return false; // رصيد افتتاحي لمعرّف آخر
      return _adoptOpening(db, id, data);
    }
    final n = await db.insert(
      'stock_movements',
      {
        'movement_uuid': id,
        'product_sync_uuid': product,
        'delta': delta,
        'kind': kind,
        'note': data['note'],
        'created_at': data['createdAt'] ?? DateTime.now().toIso8601String(),
        'origin_device_id': data['originDeviceId'],
        'is_uploaded': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return n > 0;
  }

  /// الرصيد الافتتاحي في السحابة هو المعتمد متى وُجد.
  Future<bool> _adoptOpening(Database db, String id, Map<String, dynamic> data) async {
    final product = data['productSyncUuid'] as String?;
    final delta = (data['delta'] as num?)?.toDouble();
    if (product == null || delta == null) return false;
    final cur = await db.query('stock_movements',
        columns: ['delta', 'is_uploaded'], where: 'movement_uuid = ?', whereArgs: [id], limit: 1);
    if (cur.isEmpty) {
      await db.insert('stock_movements', {
        'movement_uuid': id,
        'product_sync_uuid': product,
        'delta': delta,
        'kind': StockLedger.openingKind,
        'note': data['note'],
        'created_at': data['createdAt'] ?? DateTime.now().toIso8601String(),
        'origin_device_id': data['originDeviceId'],
        'is_uploaded': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return true;
    }
    final same = (((cur.first['delta'] as num?)?.toDouble() ?? 0.0) - delta).abs() < 1e-9;
    if (same && cur.first['is_uploaded'] == 1) return false;
    await db.update('stock_movements', {'delta': delta, 'is_uploaded': 1},
        where: 'movement_uuid = ?', whereArgs: [id]);
    return !same;
  }

  bool _isRecovering() => FirebaseSyncService().isRecovering;
}
