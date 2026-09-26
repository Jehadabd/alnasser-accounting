// lib/services/firebase_sync/armored_reconciliation_service.dart
// 🛡️ المطابقة المحصّنة المغلقة الحلقة بين الأجهزة (Armored Closed-Loop Reconciliation)
//
// الفلسفة: مطابقة كأنها حوار بين شخصين — بدون معاملات تصحيحية وهمية،
// وبدون "انتظار ثانيتين" القائم على الحظ. التأكيد يحدث فقط عندما يرِد
// الجهاز المستقبِل فعلياً بأنه طبّق المعاملات وأن رصيده تطابق.
//
// فولدر المطابقة:
//
//   reconciliation_data/{customerSyncUuid}          → رأس الكشف (الرصيد المرجعي + عدد الأجزاء)
//   reconciliation_data/{customerSyncUuid}__p{i}    → أجزاء الكشف (400 معاملة لكل جزء)
//
//   reconciliation_requests/{customerSyncUuid}_{requesterDeviceId}
//     → طلب المطابقة: mode = truth_push (بياناتي صحيحة) | truth_pull (الجهاز الآخر صحيح)
//       status = pending → (providing → data_ready) → completed | mismatch | timeout
//
//   reconciliation_results/{customerSyncUuid}_{applierDeviceId}
//     → رد الجهاز المستقبِل: طبقتُ المعاملات، رصيدي الآن = X
//
// الدورة (truth_push — بياناتي هي الصحيحة):
//   A: يسحب كل ما في السحابة → يرفع كشف العميل → يكتب طلباً → ينتظر.
//   B: يستمع للطلبات → يقرأ الكشف → يطبّق إدمبوتنت بالـ UUID → يكتب رداً.
//   A: يستلم الرد → يقارن (بهامش 0.01) → ✅ / ❌ يعلن التباين.
//
// الدورة (truth_pull — الجهاز الآخر هو الصحيح): نفس المجموعات مقلوبة الأدوار.
//
// ═══════════════════════════════════════════════════════════════════════════
// 🛡️ قواعد الأمان (المحاكاة: tools/sync_sim سيناريوهات 07، 22–27 + الفوضى)
// ═══════════════════════════════════════════════════════════════════════════
//   • الكشف إضافة في الأساس: يُضيف الناقص ولا يُعدّل الموجود.
//   • لا يُبطَل صف إلا إن غاب كل دليل على صحته: ليس من إنشاء هذا الجهاز، ليس
//     من حزمة فاتورة موجودة، لا مستند نشط له في السحابة، لا إقرار استلام له،
//     ولم يصل من مستند سحابي قط (remote_ver). كان الإبطال يطال معاملة حقيقية
//     لمجرد أن «جهاز الحقيقة» متأخر عنها، ثم تبثّ القرارات الإبطال لكل الأجهزة.
//   • لا قرارات إبطال عن بُعد (match_verdicts): كل جهاز يحكم ببياناته والسحابة.
//   • جهاز خرج للتو من استعادة نسخة احتياطية لا يعلن «بياناتي صحيحة».
//   • الكشف مجزّأ: عميل بآلاف المعاملات كان يتجاوز حد 1 MiB للوثيقة فيفشل الرفع.
//   • الطلب يحمل nonce: الأجزاء والرد مربوطة به، فلا يُخلط رد قديم أو جزء من
//     دفعة أخرى بالطلب الحالي.
//   • وثائق الكشف لا تُحذف عند أول رد: أجهزة أخرى قد لم تقرأه بعد. تُحذف بعد 24 ساعة.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'firebase_sync_config.dart';
import 'firebase_sync_service.dart';
import '../database_service.dart';
import '../database/business/customer_visibility.dart';
import '../database/core/database_helpers.dart';

class ArmoredReconciliationService {
  static final ArmoredReconciliationService _instance =
      ArmoredReconciliationService._internal();
  factory ArmoredReconciliationService() => _instance;
  ArmoredReconciliationService._internal();

  FirebaseFirestore? _fs;
  FirebaseFirestore get _firestore {
    _fs ??= FirebaseFirestore.instance;
    return _fs!;
  }

  final DatabaseService _db = DatabaseService();

  static const String _dataCol = 'reconciliation_data';
  static const String _requestsCol = 'reconciliation_requests';
  static const String _resultsCol = 'reconciliation_results';

  /// هامش قبول تطابق الرصيد (فروق التقريب العشري)
  static const double _balanceTolerance = 0.01;

  /// مهلة انتظار رد الجهاز الآخر قبل إعلان timeout
  static const Duration _responseTimeout = Duration(seconds: 90);

  /// أقصى عدد معاملات في جزء واحد من الكشف، وأقصى حجم تقريبي له.
  /// حد Firestore للوثيقة 1 MiB؛ نترك هامشاً واسعاً لترميز الحقول.
  static const int _chunkRows = 400;
  static const int _chunkBytes = 600 * 1024;

  /// طلب أقدم من هذا لا يُطبَّق: كشف قديم لا يصف الحاضر.
  static const Duration _requestMaxAge = Duration(hours: 2);

  /// وثائق المطابقة تبقى هذه المدة ثم تُحذف.
  static const Duration _staleAfter = Duration(hours: 24);

  /// أعمدة محلية لا تنتقل في الكشف (أرقام محلية أو حالة رفع هذا الجهاز).
  static const Set<String> _localOnlyColumns = {
    'id',
    'customer_id',
    'invoice_id',
    'is_uploaded',
    'is_read_by_others',
    'remote_ver',
    'last_uploaded_at',
    'remote_modified_at',
    'restored_mark',
    'synced_at',
  };

  /// 🔒 نتيجة آخر تطبيق كشف: معاملات هذا الجهاز التي صِينت لأن المصدر
  /// لم يكن يعلم بها. تُرسل مع الرد كي يرى الإنسان سبب التباين بدل أن
  /// يظهر اختلاف رصيد بلا تفسير.
  int _lastPreservedCount = 0;
  double _lastPreservedSum = 0.0;
  int _lastVoidedCount = 0;
  int _lastKeptCount = 0;

  StreamSubscription? _requestsSub;
  bool _listening = false;
  Timer? _cleanupTimer;

  /// الطلبات التي عالجها هذا الجهاز (مفتاح: معرّف الطلب|nonce).
  /// 🛡️ محفوظة في الإعدادات: كانت في الذاكرة فقط، فكل إعادة تشغيل (أو
  /// استعادة نسخة احتياطية) تعيد تطبيق كل كشف عمره أقل من ساعتين — كشفٌ
  /// بُني قبل تعديلات لاحقة يُدرج نسخها القديمة (اختبار الكود الحقيقي).
  final Set<String> _handledRequests = <String>{};
  static const _handledPrefsKey = 'armored_handled_requests';
  bool _handledLoaded = false;

  Future<bool> _markHandled(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_handledLoaded) {
        _handledRequests.addAll(prefs.getStringList(_handledPrefsKey) ?? const []);
        _handledLoaded = true;
      }
      if (!_handledRequests.add(key)) return false;
      final list = _handledRequests.toList();
      await prefs.setStringList(
          _handledPrefsKey, list.length > 300 ? list.sublist(list.length - 300) : list);
      return true;
    } catch (_) {
      return _handledRequests.add(key);
    }
  }

  Set<String>? _txColumns;

  /// إشعارات للواجهة (رسائل تقدم المطابقة)
  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;
  void _emit(String msg) {
    print('🛡️ مطابقة: $msg');
    _statusController.add(msg);
  }

  String? _myDeviceId;
  Future<String> _deviceId() async =>
      _myDeviceId ??= await FirebaseSyncConfig.getDeviceId();

  static String _newNonce() {
    final r = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${r.nextInt(1 << 30).toRadixString(36)}';
  }

  // ══════════════════════════════════════════════════════════════════════
  //  الاستماع التلقائي (يبدأ من FirebaseSyncService.initialize)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> startListening() async {
    if (_listening) return;
    if (!await FirebaseSyncConfig.isEnabled()) return;
    _listening = true;
    final myId = await _deviceId();

    _requestsSub = _firestore.collection(_requestsCol).snapshots().listen(
      (snap) async {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.removed) continue;
          final data = change.doc.data();
          if (data == null) continue;
          final requester = data['requesterDeviceId'] as String? ?? '';
          if (requester == myId) continue; // طلبي أنا — أتجاهله هنا
          final mode = data['mode'] as String? ?? '';
          final status = data['status'] as String?;
          // 🛡️ المستمع يدمج التغييرات: قد لا نرى pending أبداً بل completed
          // مباشرة (بعد رد جهاز آخر). طلب الدفع يُطبَّق في أي من هذه الحالات.
          final actionable = mode == 'truth_push'
              ? (status == 'pending' || status == 'completed' || status == 'mismatch')
              : status == 'pending';
          if (!actionable) continue;
          if (_isTooOld(data['createdAt'])) continue;
          // 🛡️ جهاز في وضع الاستعادة لا يطبّق كشفاً: معرفته قديمة، وما سيُحدَّث
          // إليه يأتيه من الأجهزة الأخرى. ولا يُسجَّل الطلب معالَجاً.
          if (mode == 'truth_push' && FirebaseSyncService().isRecovering) continue;
          final key = '${change.doc.id}|${data['nonce'] ?? ''}';
          if (!await _markHandled(key)) continue;
          try {
            await _handleRequestAsPeer(change.doc.id, data, myId);
          } catch (e) {
            print('❌ فشل معالجة طلب مطابقة وارد ${change.doc.id}: $e');
          }
        }
      },
      onError: (e) => print('❌ خطأ استماع طلبات المطابقة: $e'),
    );

    _cleanupTimer ??=
        Timer.periodic(const Duration(minutes: 30), (_) => _cleanupStaleDocs());

    print('🛡️ الاستماع لطلبات المطابقة المحصّنة فعّال');
  }

  Future<void> stopListening() async {
    await _requestsSub?.cancel();
    _requestsSub = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _listening = false;
  }

  bool _isTooOld(Object? createdAt) {
    if (createdAt is! Timestamp) return false; // لم يُحسم الطابع بعد = جديد
    return DateTime.now().difference(createdAt.toDate()) > _requestMaxAge;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  الدورة 1: "بياناتي هي الصحيحة" (truth_push)
  // ══════════════════════════════════════════════════════════════════════

  /// يرفع كشف العميل كاملاً (كل معاملاته + رصيده المرجعي) إلى فولدر المطابقة،
  /// ثم يستمع للردود.
  /// يُرجع true عند نجاح المطابقة المغلقة، false عند timeout/تباين.
  Future<bool> pushMyTruthForCustomer(String customerSyncUuid) async {
    final myId = await _deviceId();
    final sync = FirebaseSyncService();

    // 🛡️ جهاز استعاد نسخة احتياطية ولم يكمل التمهيد: بياناته قديمة بالتعريف
    if (sync.isRecovering) {
      _emit('⛔ هذا الجهاز استعاد نسخة احتياطية ولم يكمل استلام البيانات من '
          'السحابة بعد — لا يمكن اعتماد بياناته كمرجع الآن.');
      return false;
    }

    // 🛡️ لا تعلن «بياناتي صحيحة» وأنت متأخر: اسحب كل ما في السحابة أولاً
    // (السحب يعود بصمت إن لم تكن المزامنة مهيّأة — فلا نكمل بكشف قديم)
    if (!sync.isEnabled || !sync.isOnline) {
      _emit('⚠️ المزامنة غير متصلة — لا يمكن التأكد أن بيانات هذا الجهاز محدّثة.');
      return false;
    }
    _emit('جاري سحب آخر البيانات من السحابة قبل اعتماد الكشف...');
    try {
      await sync.performFullCatchUp();
    } catch (e) {
      _emit('⚠️ تعذّر سحب آخر البيانات — أُلغيت المطابقة: $e');
      return false;
    }

    _emit('جاري رفع كشف العميل كاملاً...');
    final ledger = await _buildCustomerLedger(customerSyncUuid);
    if (ledger == null) {
      _emit('⚠️ العميل غير موجود محلياً — لا يمكن اعتماد بياناته');
      return false;
    }

    final nonce = _newNonce();
    await _writeLedger(customerSyncUuid, ledger, nonce);

    final requestId = '${customerSyncUuid}_$myId';
    await _firestore.collection(_requestsCol).doc(requestId).set({
      'customerSyncUuid': customerSyncUuid,
      'customerName': ledger['customerName'],
      'requesterDeviceId': myId,
      'mode': 'truth_push',
      'status': 'pending',
      'nonce': nonce,
      'referenceBalance': ledger['referenceBalance'],
      'createdAt': FieldValue.serverTimestamp(),
    });
    _emit('تم رفع الكشف وإرسال الطلب — بانتظار تطبيق الأجهزة الأخرى...');

    return await _awaitVerification(customerSyncUuid, requestId, nonce,
        referenceBalance: (ledger['referenceBalance'] as num?)?.toDouble() ?? 0.0);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  الدورة 2: "الجهاز الآخر هو الصحيح" (truth_pull)
  // ══════════════════════════════════════════════════════════════════════

  /// يطلب من جهاز آخر رفع كشف العميل. عند وصول الكشف → تطبيقه محلياً
  /// إدمبوتنت → التحقق من تطابق رصيدي مع الرصيد المرجعي.
  Future<bool> pullPeerTruthForCustomer(String customerSyncUuid) async {
    final myId = await _deviceId();
    _emit('جاري إرسال طلب الكشف للجهاز الآخر...');

    final requestId = '${customerSyncUuid}_$myId';
    final nonce = _newNonce();
    await _firestore.collection(_requestsCol).doc(requestId).set({
      'customerSyncUuid': customerSyncUuid,
      'requesterDeviceId': myId,
      'mode': 'truth_pull',
      'status': 'pending',
      'nonce': nonce,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final completer = Completer<bool>();
    Timer? timeout;
    bool applying = false;

    late final StreamSubscription sub;
    sub = _firestore.collection(_requestsCol).doc(requestId).snapshots().listen(
      (docSnap) async {
        final data = docSnap.data();
        if (data == null || data['nonce'] != nonce) return;
        final status = data['status'] as String?;

        if (status == 'data_ready' && !applying) {
          applying = true;
          _emit('وصل الكشف من الجهاز الآخر — جاري التطبيق الإدمبوتنت...');
          final ledger = await _readLedger(customerSyncUuid, nonce);
          if (ledger == null) {
            _emit('⚠️ الكشف غير مكتمل في السحابة');
            await sub.cancel();
            timeout?.cancel();
            if (!completer.isCompleted) completer.complete(false);
            return;
          }
          final applied = await _applyCustomerLedger(ledger);
          final ref = (ledger['referenceBalance'] as num?)?.toDouble() ?? 0.0;
          final ok = await _verifyLocalBalance(customerSyncUuid, ref);
          await _firestore.collection(_requestsCol).doc(requestId)
              .set({'status': ok ? 'completed' : 'mismatch'}, SetOptions(merge: true));
          if (ok) {
            _emit('✅ تم التطبيق والتطابق');
          } else {
            _emit('⚠️ طُبّق الكشف ($applied معاملة) لكن الرصيد ما زال مختلفاً — '
                '${_explainLastApply()}');
          }
          await sub.cancel();
          timeout?.cancel();
          if (!completer.isCompleted) completer.complete(ok);
        } else if (status == 'mismatch' || status == 'timeout') {
          await sub.cancel();
          timeout?.cancel();
          if (!completer.isCompleted) completer.complete(false);
        }
      },
      onError: (e) {
        print('❌ خطأ استماع طلب truth_pull: $e');
      },
    );

    timeout = Timer(_responseTimeout, () async {
      if (applying) return;
      _emit('⏰ انتهت المهلة دون استلام الكشف من الجهاز الآخر');
      await _firestore.collection(_requestsCol).doc(requestId)
          .set({'status': 'timeout'}, SetOptions(merge: true));
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  دور النظير: معالجة طلب وارد (truth_push: طبّق وردّ / truth_pull: ارفع كشفك)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _handleRequestAsPeer(
      String requestId, Map<String, dynamic> data, String myId) async {
    final customerSyncUuid = data['customerSyncUuid'] as String? ?? '';
    if (customerSyncUuid.isEmpty) return;
    final mode = data['mode'] as String? ?? '';
    final nonce = data['nonce'] as String? ?? '';

    if (mode == 'truth_push') {
      _emit('استلمتُ طلباً لتطبيق كشف العميل «${data['customerName'] ?? ''}»');
      final ledger = await _readLedger(customerSyncUuid, nonce);
      if (ledger == null) {
        _emit('⚠️ وصل الطلب بدون كشف مكتمل — تجاهل');
        return;
      }
      final applied = await _applyCustomerLedger(ledger);
      final balance = await _localBalanceFor(customerSyncUuid);

      await _firestore
          .collection(_resultsCol)
          .doc('${customerSyncUuid}_$myId')
          .set({
        'customerSyncUuid': customerSyncUuid,
        'applierDeviceId': myId,
        'nonce': nonce,
        'balanceAfter': balance,
        'appliedCount': applied,
        // 🔒 تفسير أي تباين
        'preservedCount': _lastPreservedCount,
        'preservedSum': _lastPreservedSum,
        'keptCount': _lastKeptCount,
        'voidedCount': _lastVoidedCount,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      _emit('✅ طبّقتُ $applied معاملة — رصيدي الآن $balance. ${_explainLastApply()}');
    } else if (mode == 'truth_pull') {
      // 🛡️ مزوّد واحد فقط: أول جهاز يحجز الطلب يرفع كشفه، وإلا تداخلت
      // أجزاء كشوف أجهزة مختلفة في نفس الوثائق.
      final sync = FirebaseSyncService();
      if (sync.isRecovering) return; // بياناتي ليست مرجعاً الآن
      final reqRef = _firestore.collection(_requestsCol).doc(requestId);
      final claimed = await _firestore.runTransaction<bool>((txn) async {
        final snap = await txn.get(reqRef);
        final d = snap.data();
        if (d == null || d['status'] != 'pending' || d['nonce'] != nonce) {
          return false;
        }
        txn.update(reqRef, {'status': 'providing', 'providerDeviceId': myId});
        return true;
      });
      if (!claimed) return;

      _emit('طُلب منّي كشف العميل «${data['customerName'] ?? customerSyncUuid}» — جاري الرفع...');
      try {
        await sync.performFullCatchUp();
      } catch (_) {}
      final ledger = await _buildCustomerLedger(customerSyncUuid);
      if (ledger == null) {
        _emit('⚠️ العميل غير موجود لدي — تعذّر الرفع');
        await reqRef.set({'status': 'mismatch'}, SetOptions(merge: true));
        return;
      }
      await _writeLedger(customerSyncUuid, ledger, nonce);
      await reqRef.set({
        'status': 'data_ready',
        'referenceBalance': ledger['referenceBalance'],
        'providerDeviceId': myId,
      }, SetOptions(merge: true));
      _emit('✅ رفعتُ الكشف — الجهاز الطالب سيطبّقه ويتحقق');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  بناء الكشف (Ledger) ورفعه وقراءته
  // ══════════════════════════════════════════════════════════════════════

  /// يبني كشف العميل الكامل: كل معاملاته النشطة (بعد تعبئة UUID للناقص) + الرصيد المرجعي.
  Future<Map<String, dynamic>?> _buildCustomerLedger(String customerSyncUuid) async {
    final db = await _db.database;
    final myId = await _deviceId();
    final custRows = await db.query('customers',
        where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
    if (custRows.isEmpty) {
      print('🛡️🔍 [بناء الكشف] العميل $customerSyncUuid غير موجود محلياً!');
      return null;
    }
    final cust = custRows.first;
    final customerId = cust['id'] as int;

    final txs = await db.query('transactions',
        where: 'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [customerId],
        orderBy: 'transaction_date ASC, id ASC');

    // الرصيد المرجعي = مجموع المعاملات النشطة (مصدر الحقيقة الوحيد)
    double txSum = 0;
    for (final t in txs) {
      txSum += (t['amount_changed'] as num?)?.toDouble() ?? 0.0;
    }
    final storedBalance = (cust['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    if ((txSum - storedBalance).abs() > _balanceTolerance) {
      print('🛡️⚠️ [بناء الكشف] مجموع المعاملات ($txSum) ≠ الرصيد المخزّن '
          '($storedBalance) — المرجع هو المجموع');
    }

    final outTxs = <Map<String, dynamic>>[];
    int backfilled = 0;
    for (final tx in txs) {
      var txUuid = tx['transaction_uuid'] as String?;
      if (txUuid == null || txUuid.isEmpty) {
        txUuid = 'txb_${tx['id']}_${customerSyncUuid.hashCode.toRadixString(36)}';
        await db.update('transactions',
            {'transaction_uuid': txUuid, 'sync_uuid': txUuid},
            where: 'id = ?',
            whereArgs: [tx['id']]);
        backfilled++;
      }
      final m = <String, dynamic>{};
      tx.forEach((k, v) {
        if (!_localOnlyColumns.contains(k)) m[k] = v;
      });
      m['transaction_uuid'] = txUuid;
      m['sync_uuid'] = txUuid;
      // 🛡️ هوية الجهاز المالك تنتقل كما هي (لا يصير المستقبِل مالكاً)
      final mine = ((tx['is_created_by_me'] as int?) ?? 1) == 1;
      m['origin_device_id'] = mine ? myId : tx['origin_device_id'];
      outTxs.add(m);
    }
    if (backfilled > 0) {
      print('🛡️🔍 [بناء الكشف] عُبّئ UUID لـ $backfilled معاملة قديمة كانت بلا هوية');
    }

    return {
      'customerSyncUuid': customerSyncUuid,
      'customerName': cust['name'],
      'customerPhone': cust['phone'],
      'customerAddress': cust['address'],
      'referenceBalance': txSum,
      'referenceTxCount': outTxs.length,
      'transactions': outTxs,
    };
  }

  List<List<Map<String, dynamic>>> _chunk(List<Map<String, dynamic>> txs) {
    final chunks = <List<Map<String, dynamic>>>[];
    var cur = <Map<String, dynamic>>[];
    var bytes = 0;
    for (final t in txs) {
      final size = utf8.encode(jsonEncode(t)).length;
      if (cur.isNotEmpty && (cur.length >= _chunkRows || bytes + size > _chunkBytes)) {
        chunks.add(cur);
        cur = <Map<String, dynamic>>[];
        bytes = 0;
      }
      cur.add(t);
      bytes += size;
    }
    if (cur.isNotEmpty || chunks.isEmpty) chunks.add(cur);
    return chunks;
  }

  /// يكتب الأجزاء أولاً ثم الرأس: من يقرأ رأساً يجد كل أجزائه مكتوبة.
  Future<void> _writeLedger(
      String customerSyncUuid, Map<String, dynamic> ledger, String nonce) async {
    final txs = (ledger['transactions'] as List).cast<Map<String, dynamic>>();
    final chunks = _chunk(txs);
    for (var i = 0; i < chunks.length; i++) {
      await _firestore.collection(_dataCol).doc('${customerSyncUuid}__p$i').set({
        'customerSyncUuid': customerSyncUuid,
        'nonce': nonce,
        'index': i,
        'transactions': chunks[i],
        'builtAt': FieldValue.serverTimestamp(),
      });
    }
    final header = Map<String, dynamic>.from(ledger)..remove('transactions');
    header['nonce'] = nonce;
    header['chunks'] = chunks.length;
    header['builtAt'] = FieldValue.serverTimestamp();
    await _firestore.collection(_dataCol).doc(customerSyncUuid).set(header);
    print('🛡️📤 [الكشف] كُتب ${txs.length} معاملة في ${chunks.length} جزء');
  }

  /// يقرأ الكشف كاملاً ويتحقق أن كل أجزائه من نفس الطلب. null إن لم يكتمل.
  Future<Map<String, dynamic>?> _readLedger(String customerSyncUuid, String nonce) async {
    final headSnap = await _firestore.collection(_dataCol).doc(customerSyncUuid).get();
    final head = headSnap.data();
    if (head == null) return null;
    if (nonce.isNotEmpty && head['nonce'] != nonce) return null; // كشف طلب آخر
    final ledger = Map<String, dynamic>.from(head);
    final chunks = (head['chunks'] as num?)?.toInt();
    if (chunks == null) {
      // كشف بصيغة قديمة (وثيقة واحدة)
      return (head['transactions'] is List) ? ledger : null;
    }
    final txs = <dynamic>[];
    for (var i = 0; i < chunks; i++) {
      final p = (await _firestore
              .collection(_dataCol)
              .doc('${customerSyncUuid}__p$i')
              .get())
          .data();
      if (p == null || p['nonce'] != head['nonce']) return null;
      txs.addAll((p['transactions'] as List?) ?? const []);
    }
    ledger['transactions'] = txs;
    return ledger;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  التطبيق الإدمبوتنت
  // ══════════════════════════════════════════════════════════════════════

  Future<Set<String>> _transactionColumns(DatabaseExecutor db) async {
    if (_txColumns != null) return _txColumns!;
    final info = await db.rawQuery('PRAGMA table_info(transactions)');
    _txColumns = info.map((r) => r['name'] as String).toSet();
    return _txColumns!;
  }

  /// يطبّق الكشف الوارد: يضيف المعاملات الناقصة (بالـ UUID) ويهمل الموجودة،
  /// ويُبطل فقط ما لا دليل على صحته. يُرجع عدد ما أُضيف فعلاً.
  Future<int> _applyCustomerLedger(Map<String, dynamic> ledger) async {
    _lastPreservedCount = 0;
    _lastPreservedSum = 0.0;
    _lastVoidedCount = 0;
    _lastKeptCount = 0;
    final db = await _db.database;
    final txs = (ledger['transactions'] as List?) ?? const [];
    print('🛡️📥 [تطبيق كشف] العميل ${ledger['customerName']} | واردة=${txs.length}');

    final customerId = await _resolveCustomer(db, ledger);
    if (customerId == null) return 0;
    final columns = await _transactionColumns(db);
    final myId = await _deviceId();

    int applied = 0;
    final incomingUuids = <String>{};
    final candidates = <Map<String, dynamic>>[];
    final preservedLocal = <Map<String, dynamic>>[];

    // ── المرحلة 1: إضافة الناقص وتحديد المرشحين للإبطال (بلا أي I/O سحابي)
    await db.transaction((txn) async {
      for (final raw in txs) {
        if (raw is! Map) continue;
        final tx = Map<String, dynamic>.from(raw);
        final tu = ((tx['transaction_uuid'] as String?)?.isNotEmpty == true
            ? tx['transaction_uuid']
            : tx['sync_uuid']) as String?;
        if (tu == null || tu.isEmpty) continue; // لا هوية = لا نضيف
        incomingUuids.add(tu);
        // 🛡️ معاملة أملكها أنا: نسختي أو نسخة السحابة هي المرجع، لا كشف غيري.
        // كانت تُدرج «كمعاملة جهاز آخر» بمبلغ الكشف (قد يكون قديماً) بعد
        // استعادة نسخة احتياطية، فلا تقبل بعدها تعديلي الأحدث من السحابة.
        if (myId.isNotEmpty && tx['origin_device_id'] == myId) continue;

        // موجود (نشطاً أو محذوفاً) = نُهمله. الحذف نهائي: لا يُحييه كشف.
        final existing = await txn.query('transactions',
            columns: ['id'],
            where: 'transaction_uuid = ? OR sync_uuid = ?',
            whereArgs: [tu, tu],
            limit: 1);
        if (existing.isNotEmpty) continue;

        final row = <String, dynamic>{};
        tx.forEach((k, v) {
          if (columns.contains(k) && !_localOnlyColumns.contains(k)) row[k] = v;
        });
        row['transaction_uuid'] = tu;
        row['sync_uuid'] = tu;
        row['customer_id'] = customerId;
        row['is_created_by_me'] = 0;
        row['is_uploaded'] = 1;
        row['is_deleted'] = 0;
        // 🛡️ رقم الفاتورة المحلي عند المرسل لا يعني شيئاً هنا: نربط بالهوية
        final invUuid = tx['invoice_sync_uuid'] as String?;
        if (invUuid != null && invUuid.isNotEmpty && columns.contains('invoice_id')) {
          final inv = await txn.query('invoices',
              columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [invUuid], limit: 1);
          row['invoice_id'] = inv.isEmpty ? null : inv.first['id'];
        }
        row['transaction_date'] =
            row['transaction_date'] ?? DateTime.now().toIso8601String();
        row['amount_changed'] = (row['amount_changed'] as num?)?.toDouble() ?? 0.0;
        row['transaction_type'] = row['transaction_type'] ?? 'مطابقة';
        row['created_at'] = row['created_at'] ?? DateTime.now().toIso8601String();
        await txn.insert('transactions', row,
            conflictAlgorithm: ConflictAlgorithm.ignore);
        applied++;
      }

      final active = await txn.query('transactions',
          where: 'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [customerId]);
      for (final r in active) {
        final tu = (r['transaction_uuid'] as String?)?.isNotEmpty == true
            ? r['transaction_uuid'] as String
            : r['sync_uuid'] as String?;
        if (tu != null && tu.isNotEmpty && incomingUuids.contains(tu)) continue;
        final mine = ((r['is_created_by_me'] as int?) ?? 1) == 1;
        if (mine) {
          // 🔒 من إنشاء هذا الجهاز ولم يعرفه المصدر: يُصان ويُعاد للرفع
          preservedLocal.add(Map<String, dynamic>.from(r));
          final invUuid = r['invoice_sync_uuid'] as String?;
          if (invUuid != null && invUuid.isNotEmpty) {
            // 🛡️ صف فاتورة لا يُرفع وحده أبداً — يسافر داخل حزمة فاتورته.
            // تأشيره «غير مرفوع» كان يبقى عالقاً للأبد؛ نعيد الحزمة للطابور
            // (نفس الإصدار: من يملكها يتجاهلها، ومن ينقصه الصف يُدرجه).
            // فاتورة جهاز آخر لا نرفعها أبداً (المالك وحده يكتب حزمته).
            await txn.update('invoices', {'is_synced': 0},
                where: 'invoice_uuid = ? AND COALESCE(is_created_by_me, 1) = 1',
                whereArgs: [invUuid]);
          } else {
            await txn.update('transactions', {'is_uploaded': 0},
                where: 'id = ?', whereArgs: [r['id']]);
          }
          continue;
        }
        candidates.add(Map<String, dynamic>.from(r));
      }
    });

    if (preservedLocal.isNotEmpty) {
      double keptSum = 0;
      for (final r in preservedLocal) {
        keptSum += (r['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }
      _lastPreservedCount = preservedLocal.length;
      _lastPreservedSum = keptSum;
    }

    // ── المرحلة 2: فحص الأدلة لكل مرشح (قراءات سحابية خارج معاملة SQLite)
    final toVoid = <Map<String, dynamic>>[];
    for (final r in candidates) {
      if (await _hasEvidenceOfLife(db, r)) {
        _lastKeptCount++;
      } else {
        toVoid.add(r);
      }
    }

    // ── المرحلة 3: الإبطال (بعد التأكد أن الصف لم يتغير أثناء الفحص)
    final voided = <Map<String, dynamic>>[];
    await db.transaction((txn) async {
      for (final r in toVoid) {
        final n = await txn.update('transactions', {'is_deleted': 1},
            where: 'id = ? AND (is_deleted IS NULL OR is_deleted = 0) '
                'AND amount_changed = ? AND is_created_by_me = 0',
            whereArgs: [r['id'], r['amount_changed']]);
        if (n > 0) voided.add(r);
      }
      final sum = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount_changed),0) as s FROM transactions '
          'WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          [customerId]);
      await txn.update('customers',
          {'current_total_debt': (sum.first['s'] as num?)?.toDouble() ?? 0.0},
          where: 'id = ?', whereArgs: [customerId]);
      await CustomerVisibility.apply(txn, customerId);
    });
    _lastVoidedCount = voided.length;
    if (voided.isNotEmpty) {
      _archiveDeletedTransactions(voided, ledger['customerName']?.toString());
    }

    print('🛡️📥 [تطبيق كشف] أُضيف=$applied | أُبطل=${voided.length} | '
        'أُبقي بدليل=$_lastKeptCount | صِين من إنشائي=$_lastPreservedCount');
    return applied;
  }

  /// هل يوجد أي دليل على أن هذه المعاملة حقيقية؟ عند أي شك: نعم.
  Future<bool> _hasEvidenceOfLife(DatabaseExecutor db, Map<String, dynamic> r) async {
    // وصلت من مستند سحابي يوماً: غيابه الآن تنظيف لا حذف (الحذف يترك شاهداً)
    if (r['remote_ver'] != null) return true;
    // صف فاتورة: أثر الفاتورة يحكمه صاحبها (حزمتها) لا المطابقة — أبداً.
    // 🛡️ كان الشرط «والفاتورة موجودة هنا»: صف دين أدرجه كشفٌ قبل وصول حزمة
    // فاتورته، ثم جاء كشف ثانٍ لا يعرفه، فحُكم عليه «بلا أثر» وأُبطل — وبقي
    // مُبطلاً للأبد (الحزمة تحفظ الحذف) فضاع دين 3000 (اختبار الكود الحقيقي).
    final invUuid = r['invoice_sync_uuid'] as String?;
    if (invUuid != null && invUuid.isNotEmpty) return true;
    final tu = (r['transaction_uuid'] as String?)?.isNotEmpty == true
        ? r['transaction_uuid'] as String
        : r['sync_uuid'] as String?;
    if (tu == null || tu.isEmpty) return false;
    try {
      final doc = await _firestore
          .collection('transactions')
          .doc(tu)
          .get(const GetOptions(source: Source.server));
      final d = doc.data();
      if (d != null) return d['isDeleted'] != true; // مستند نشط = حقيقية
      // لا مستند: هل كان في السحابة ثم نظّفه SmartPipe؟ الإقرارات تشهد
      final acks = await _firestore
          .collection('transaction_acks')
          .where('transactionUuid', isEqualTo: tu)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return acks.docs.isNotEmpty;
    } catch (e) {
      // تعذّر التحقق = لا إبطال
      print('🛡️ [تطبيق كشف] تعذّر التحقق من $tu ($e) — أُبقيت');
      return true;
    }
  }

  /// يجد العميل بهويته. الربط بالاسم مسموح فقط لسجل قديم بلا هوية —
  /// كان يسرق هوية عميل آخر يحمل نفس الاسم فتختلط ديونهما.
  Future<int?> _resolveCustomer(Database db, Map<String, dynamic> ledger) async {
    final customerSyncUuid = ledger['customerSyncUuid'] as String;
    final rows = await db.query('customers',
        columns: ['id'], where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;

    final name = (ledger['customerName'] as String?) ?? 'عميل مطابقة';
    final normName = DatabaseHelpers.normalizeArabic(name);
    final legacy = await db.query('customers',
        columns: ['id', 'name'], where: "sync_uuid IS NULL OR sync_uuid = ''");
    for (final c in legacy) {
      if (DatabaseHelpers.normalizeArabic(c['name'] as String? ?? '') == normName) {
        final id = c['id'] as int;
        await db.update('customers', {'sync_uuid': customerSyncUuid},
            where: 'id = ?', whereArgs: [id]);
        return id;
      }
    }

    final now = DateTime.now().toIso8601String();
    final phone = ledger['customerPhone'] as String?;
    final row = <String, Object?>{
      'name': name,
      'phone': (phone == null || phone.isEmpty) ? null : phone,
      'address': ledger['customerAddress'],
      'current_total_debt': 0.0,
      'sync_uuid': customerSyncUuid,
      'is_created_by_me': 0,
      'is_deleted': 0,
      'created_at': now,
      'last_modified_at': now,
      'synced_at': now,
    };
    for (var k = 0; k <= 20; k++) {
      try {
        // UNIQUE(name, phone) مع عميل آخر: هاتف مميّز بمحرف غير مرئي كي يبقى منفصلاً
        if (k > 0) row['phone'] = '${phone ?? ''}${'​' * k}';
        return await db.insert('customers', row);
      } catch (_) {
        // سباق مع مسار استقبال آخر أدرج نفس الهوية (قيد فريد على sync_uuid)
        final same = await db.query('customers',
            columns: ['id'], where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
        if (same.isNotEmpty) return same.first['id'] as int;
      }
    }
    _emit('⚠️ تعذّر إنشاء العميل «$name» محلياً');
    return null;
  }

  String _explainLastApply() {
    final parts = <String>[];
    if (_lastPreservedCount > 0) {
      parts.add('صُينت $_lastPreservedCount معاملة من إنشاء هذا الجهاز لم يعرفها '
          'المصدر (مجموعها $_lastPreservedSum)');
    }
    if (_lastKeptCount > 0) {
      parts.add('أُبقيت $_lastKeptCount معاملة لأن لها أثراً في السحابة '
          '(المصدر متأخر عنها)');
    }
    if (_lastVoidedCount > 0) {
      parts.add('أُبطلت $_lastVoidedCount معاملة بلا أي أثر');
    }
    return parts.join('، ');
  }

  void _archiveDeletedTransactions(List<Map<String, dynamic>> rows, String? customerName) {
    if (_fs == null) return;

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(days: 730));

    final batch = _fs!.batch();
    for (var row in rows) {
      final docRef = _fs!.collection('deleted_transactions').doc();
      final data = Map<String, dynamic>.from(row);
      data['archived_at'] = now.toIso8601String();
      data['expires_at'] = Timestamp.fromDate(expiresAt);
      data['customer_name'] = customerName ?? 'غير معروف';
      data['reason'] = 'armored_reconciliation';
      batch.set(docRef, data);
    }

    batch.commit().then((_) {
      print('🛡️📤 [أرشفة] تمت أرشفة ${rows.length} معاملة مُبطلة في فايربيز');
    }).catchError((e) {
      print('🛡️⚠️ [أرشفة] خطأ أثناء أرشفة المعاملات المُبطلة: $e');
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  //  التحقق والتنظيف
  // ══════════════════════════════════════════════════════════════════════

  /// ينتظر أول رد على هذا الطلب بعينه (nonce) ويتحقق منه.
  Future<bool> _awaitVerification(
      String customerSyncUuid, String requestId, String nonce,
      {required double referenceBalance}) async {
    final completer = Completer<bool>();
    Timer? timeout;

    late final StreamSubscription sub;
    sub = _firestore
        .collection(_resultsCol)
        .where('customerSyncUuid', isEqualTo: customerSyncUuid)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        if (data == null || data['nonce'] != nonce) continue; // رد طلب سابق
        if (completer.isCompleted) return;
        final balanceAfter = (data['balanceAfter'] as num?)?.toDouble() ?? 0.0;
        final applier = data['applierDeviceId'] as String? ?? 'جهاز';
        final applied = (data['appliedCount'] as num?)?.toInt() ?? 0;
        final ok = (balanceAfter - referenceBalance).abs() <= _balanceTolerance;

        if (ok) {
          _emit('✅ $applier طبّق $applied معاملة وتطابق الرصيد — مطابقة ناجحة');
        } else {
          final preservedCount = (data['preservedCount'] as num?)?.toInt() ?? 0;
          final preservedSum = (data['preservedSum'] as num?)?.toDouble() ?? 0.0;
          final keptCount = (data['keptCount'] as num?)?.toInt() ?? 0;
          final why = <String>[];
          if (preservedCount > 0) {
            why.add('لديه $preservedCount معاملة من إنشائه (مجموعها $preservedSum) لم تصلك بعد');
          }
          if (keptCount > 0) {
            why.add('لديه $keptCount معاملة لها أثر في السحابة لم تصلك بعد');
          }
          _emit('⚠️ $applier طبّق الكشف لكن رصيده ($balanceAfter) يختلف عن المرجعي '
              '($referenceBalance)${why.isEmpty ? '' : ': ${why.join('، ')}'}. '
              'انتظر اكتمال المزامنة ثم أعد المطابقة.');
        }
        // لا نحذف الكشف هنا: أجهزة أخرى قد لم تقرأه بعد
        await _firestore.collection(_requestsCol).doc(requestId)
            .set({'status': ok ? 'completed' : 'mismatch'}, SetOptions(merge: true));
        await sub.cancel();
        timeout?.cancel();
        if (!completer.isCompleted) completer.complete(ok);
        return;
      }
    }, onError: (e) {
      print('🛡️❌ [انتظار] خطأ استماع نتائج المطابقة: $e');
    });

    timeout = Timer(_responseTimeout, () async {
      _emit('⏰ انتهت المهلة دون رد من الأجهزة الأخرى');
      await _firestore.collection(_requestsCol).doc(requestId)
          .set({'status': 'timeout'}, SetOptions(merge: true));
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  /// حذف وثائق المطابقة الأقدم من 24 ساعة.
  Future<void> _cleanupStaleDocs() async {
    final cutoff = Timestamp.fromDate(DateTime.now().subtract(_staleAfter));
    final targets = <String, String>{
      _requestsCol: 'createdAt',
      _resultsCol: 'respondedAt',
      _dataCol: 'builtAt',
    };
    for (final e in targets.entries) {
      try {
        final snap = await _firestore
            .collection(e.key)
            .where(e.value, isLessThan: cutoff)
            .get();
        for (final d in snap.docs) {
          await d.reference.delete();
        }
      } catch (_) {}
    }
  }

  Future<double> _localBalanceFor(String customerSyncUuid) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(t.amount_changed), 0) AS s
      FROM transactions t JOIN customers c ON c.id = t.customer_id
      WHERE c.sync_uuid = ? AND (t.is_deleted IS NULL OR t.is_deleted = 0)
    ''', [customerSyncUuid]);
    return (rows.first['s'] as num?)?.toDouble() ?? 0.0;
  }

  Future<bool> _verifyLocalBalance(String customerSyncUuid, double reference) async {
    final balance = await _localBalanceFor(customerSyncUuid);
    return (balance - reference).abs() <= _balanceTolerance;
  }
}
