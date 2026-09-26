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

  Future<void> start() async {
    if (_started) return;
    if (!await FirebaseSyncConfig.isEnabled()) return;
    _started = true;
    await _sub?.cancel();
    _sub = _firestore.collection(collectionName).snapshots().listen((snap) async {
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
    }, onError: (e) => print('⚠️ [حركات المخزون] خطأ الاستماع: $e'));
    unawaited(uploadPending().catchError((_) => 0));
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
            final doc = <String, dynamic>{
              'movementUuid': uuid,
              'productSyncUuid': r['product_sync_uuid'],
              'delta': (r['delta'] as num).toDouble(),
              'kind': r['kind'],
              'note': r['note'],
              'createdAt': r['created_at'],
              'originDeviceId': (r['origin_device_id'] as String?) ?? me,
              'uploadedAt': FieldValue.serverTimestamp(),
            };
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
            await db.update('stock_movements', {'is_uploaded': 1},
                where: 'movement_uuid = ?', whereArgs: [uuid]);
            n++;
          } catch (e) {
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
      return n;
    } catch (e) {
      print('❌ [حركات المخزون] فشل التنزيل: $e');
      if (rethrowErrors) rethrow;
      return 0;
    }
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
