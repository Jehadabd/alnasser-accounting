// lib/services/firebase_sync/armored_reconciliation_service.dart
// 🛡️ المطابقة المحصّنة المغلقة الحلقة بين الأجهزة (Armored Closed-Loop Reconciliation)
//
// الفلسفة: مطابقة كأنها حوار بين شخصين — بدون معاملات تصحيحية وهمية،
// وبدون "انتظار ثانيتين" القائم على الحظ. التأكيد يحدث فقط عندما يرِد
// الجهاز المستقبِل فعلياً بأنه طبّق المعاملات وأن رصيده تطابق.
//
// فولدر المطابقة (3 مجموعات تُحذف فوراً بعد النجاح ليبقى الفولدر نظيفاً):
//
//   reconciliation_data/{customerSyncUuid}
//     → وثيقة "الكشف الكامل": كل معاملات العميل + الرصيد المرجعي (من مصدر الحقيقة)
//
//   reconciliation_requests/{customerSyncUuid}_{requesterDeviceId}
//     → طلب المطابقة: mode = truth_push (بياناتي صحيحة) | truth_pull (الجهاز الآخر صحيح)
//       status = pending → data_ready → completed | mismatch | timeout
//
//   reconciliation_results/{customerSyncUuid}_{applierDeviceId}
//     → رد الجهاز المستقبِل: طبقتُ المعاملات، رصيدي الآن = X
//
// الدورة (truth_push — بياناتي هي الصحيحة):
//   A: يرفع كشف العميل كاملاً → يكتب طلباً → ينتظر.
//   B: يستمع للطلبات → يقرأ الكشف → يطبّق إدمبوتنت بالـ UUID
//      (يضيف الناقص ويهمل الموجود) → يعيد حساب رصيده من SUM → يكتب رداً.
//   A: يستلم الرد → يقارن (بهامش 0.01) → ✅ يحذف الـ 3 وثائق فوراً / ❌ يعلن التباين.
//
// الدورة (truth_pull — الجهاز الآخر هو الصحيح): نفس المجموعات مقلوبة الأدوار.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'firebase_sync_config.dart';
import 'match_verdict_service.dart'; // ⚖️ بثّ قرارات الإبطال لبقية الأجهزة
import '../database_service.dart';
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

  /// 🔒 نتيجة آخر تطبيق كشف: معاملات هذا الجهاز التي صِينت لأن المصدر
  /// لم يكن يعلم بها. تُرسل مع الرد كي يرى الإنسان سبب التباين بدل أن
  /// يظهر اختلاف رصيد بلا تفسير.
  int _lastPreservedCount = 0;
  double _lastPreservedSum = 0.0;

  StreamSubscription? _requestsSub;
  StreamSubscription? _resultsSub;
  bool _listening = false;

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

  // ══════════════════════════════════════════════════════════════════════
  //  الاستماع التلقائي (يبدأ من FirebaseSyncService.initialize)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> startListening() async {
    if (_listening) return;
    if (!await FirebaseSyncConfig.isEnabled()) return;
    _listening = true;
    final myId = await _deviceId();

    // الاستماع لطلبات المطابقة الموجهة لي (أو للجميع)
    _requestsSub = _firestore.collection(_requestsCol).snapshots().listen(
      (snap) async {
        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.removed) continue;
          final data = change.doc.data();
          if (data == null) continue;
          final requester = data['requesterDeviceId'] as String? ?? '';
          if (requester == myId) continue; // طلبي أنا — أتجاهله هنا
          if ((data['status'] as String?) != 'pending') continue;
          try {
            await _handleRequestAsPeer(change.doc.id, data, myId);
          } catch (e) {
            print('❌ فشل معالجة طلب مطابقة وارد ${change.doc.id}: $e');
          }
        }
      },
      onError: (e) => print('❌ خطأ استماع طلبات المطابقة: $e'),
    );

    // تنظيف فرصي للوثائق الموقوتة (أقدم من ساعة) ليبقى الفولدر نظيفاً
    Timer.periodic(const Duration(minutes: 10), (_) => _cleanupStaleDocs());

    print('🛡️ الاستماع لطلبات المطابقة المحصّنة فعّال');
  }

  Future<void> stopListening() async {
    await _requestsSub?.cancel();
    await _resultsSub?.cancel();
    _requestsSub = null;
    _resultsSub = null;
    _listening = false;
  }

  // ══════════════════════════════════════════════════════════════════════
  //  الدورة 1: "بياناتي هي الصحيحة" (truth_push)
  // ══════════════════════════════════════════════════════════════════════

  /// يرفع كشف العميل كاملاً (كل معاملاته + رصيده المرجعي) إلى فولدر المطابقة،
  /// ثم يستمع للردود. عند تأكيد التطابق من الجهاز الآخر → حذف فوري للوثائق.
  /// يُرجع true عند نجاح المطابقة المغلقة، false عند timeout/تباين.
  Future<bool> pushMyTruthForCustomer(String customerSyncUuid) async {
    final myId = await _deviceId();
    print('🛡️📤 [truth_push] ═══ بدء دورة «بياناتي صحيحة» لـ $customerSyncUuid (جهازي=$myId)');
    _emit('جاري رفع كشف العميل كاملاً...');

    // 1) تجهيز كشف العميل (مع تعبئة UUID للمعاملات القديمة الناقصة)
    final data = await _buildCustomerLedger(customerSyncUuid);
    if (data == null) {
      _emit('⚠️ العميل غير موجود محلياً — لا يمكن اعتماد بياناته');
      return false;
    }

    // 2) رفع الكشف إلى فولدر المطابقة
    print('🛡️📤 [truth_push] جاري كتابة وثيقة الكشف في $_dataCol/$customerSyncUuid '
        '(${data['referenceTxCount']} معاملة)...');
    await _firestore.collection(_dataCol).doc(customerSyncUuid).set(data);
    print('🛡️📤 [truth_push] ✅ كُتبت وثيقة الكشف في السحابة بنجاح');

    // 3) كتابة الطلب (كل الأجهزة الأخرى ستستلمه وتطبّقه)
    final requestId = '${customerSyncUuid}_$myId';
    print('🛡️📤 [truth_push] جاري كتابة الطلب في $_requestsCol/$requestId...');
    await _firestore.collection(_requestsCol).doc(requestId).set({
      'customerSyncUuid': customerSyncUuid,
      'customerName': data['customerName'],
      'requesterDeviceId': myId,
      'mode': 'truth_push',
      'status': 'pending',
      'referenceBalance': data['referenceBalance'],
      'createdAt': FieldValue.serverTimestamp(),
    });
    print('🛡️📤 [truth_push] ✅ كُتب الطلب في السحابة — الأجهزة الأخرى ستستلمه الآن');
    _emit('تم رفع الكشف وإرسال الطلب — بانتظار تطبيق الأجهزة الأخرى...');

    // 4) الاستماع للردود + مهلة صريحة
    return await _awaitVerification(customerSyncUuid, requestId,
        referenceBalance: (data['referenceBalance'] as num?)?.toDouble() ?? 0.0);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  الدورة 2: "الجهاز الآخر هو الصحيح" (truth_pull)
  // ══════════════════════════════════════════════════════════════════════

  /// يطلب من الأجهزة الأخرى رفع كشوف العميل. عند وصول الكشف → تطبيقه محلياً
  /// إدمبوتنت → التحقق من تطابق رصيدي مع الرصيد المرجعي → حذف فوري.
  Future<bool> pullPeerTruthForCustomer(String customerSyncUuid) async {
    final myId = await _deviceId();
    _emit('جاري إرسال طلب الكشف للجهاز الآخر...');

    final requestId = '${customerSyncUuid}_$myId';
    await _firestore.collection(_requestsCol).doc(requestId).set({
      'customerSyncUuid': customerSyncUuid,
      'requesterDeviceId': myId,
      'mode': 'truth_pull',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // الانتظار: إما أن يرفع النظير الكشف (data_ready) ثم نطبّقه نحن، أو timeout.
    final completer = Completer<bool>();
    Timer? timeout;

    late final StreamSubscription sub;
    sub = _firestore.collection(_requestsCol).doc(requestId).snapshots().listen(
      (docSnap) async {
        final data = docSnap.data();
        if (data == null) return;
        final status = data['status'] as String?;

        if (status == 'data_ready') {
          _emit('وصل الكشف من الجهاز الآخر — جاري التطبيق الإدمبوتنت...');
          // قراءة الكشف وتطبيقه محلياً
          final ledgerSnap = await _firestore
              .collection(_dataCol)
              .doc(customerSyncUuid)
              .get();
          final ledger = ledgerSnap.data();
          if (ledger == null) {
            if (!completer.isCompleted) completer.complete(false);
            return;
          }
          final applied = await _applyCustomerLedger(ledger);
          // التحقق من رصيدنا مقابل الرصيد المرجعي
          final ref = (ledger['referenceBalance'] as num?)?.toDouble() ?? 0.0;
          final ok = await _verifyLocalBalance(customerSyncUuid, ref);
          if (ok) {
            _emit('✅ تم التطبيق والتطابق — جاري تنظيف فولدر المطابقة');
            await _firestore.collection(_requestsCol).doc(requestId)
                .set({'status': 'completed'}, SetOptions(merge: true));
            await _cleanupCustomerDocs(customerSyncUuid, keepRequestId: requestId);
            await sub.cancel();
            timeout?.cancel();
            if (!completer.isCompleted) completer.complete(true);
          } else {
            _emit('⚠️ طُبّق الكشف ($applied معاملة) لكن الرصيد ما زال مختلفاً');
            await _firestore.collection(_requestsCol).doc(requestId)
                .set({'status': 'mismatch'}, SetOptions(merge: true));
            await sub.cancel();
            timeout?.cancel();
            if (!completer.isCompleted) completer.complete(false);
          }
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

    if (mode == 'truth_push') {
      // النظير المطبِّق: اقرأ الكشف → طبّق → اكتب الرد
      _emit('استلمتُ طلباً لتطبيق كشف العميل «${data['customerName'] ?? ''}»');
      final ledgerSnap =
          await _firestore.collection(_dataCol).doc(customerSyncUuid).get();
      final ledger = ledgerSnap.data();
      if (ledger == null) {
        _emit('⚠️ وصل الطلب بدون كشف — تجاهل');
        return;
      }
      // ⚖️ جهاز الحقيقة يوثَّق في الكشف — يستخدمه بثّ قرارات المطابقة
      ledger['truthDeviceId'] = data['requesterDeviceId'] ?? 'unknown';
      final applied = await _applyCustomerLedger(ledger);
      final balance = await _localBalanceFor(customerSyncUuid);

      // كتابة الرد (الوثيقة تُحذف من المُبادِر بعد التحقق)
      await _firestore
          .collection(_resultsCol)
          .doc('${customerSyncUuid}_$myId')
          .set({
        'customerSyncUuid': customerSyncUuid,
        'applierDeviceId': myId,
        'balanceAfter': balance,
        'appliedCount': applied,
        // 🔒 تفسير أي تباين: معاملات محلية لم يكن المصدر يعلم بها فصِينت
        'preservedCount': _lastPreservedCount,
        'preservedSum': _lastPreservedSum,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      if (_lastPreservedCount > 0) {
        _emit('✅ طبّقتُ $applied معاملة — وصُينت $_lastPreservedCount معاملة '
            'من إنشائي لم يعرفها المصدر (مجموعها $_lastPreservedSum). '
            'رصيدي الآن $balance');
      } else {
        _emit('✅ طبّقتُ $applied معاملة — رصيدي الآن $balance (تم الرد للمُبادِر)');
      }
    } else if (mode == 'truth_pull') {
      // النظير المُزوِّد: هذا الجهاز هو مصدر الحقيقة — ارفع كشفك وعلّم الطلب
      _emit('طُلب منّي كشف العميل «${data['customerName'] ?? customerSyncUuid}» — جاري الرفع...');
      final ledger = await _buildCustomerLedger(customerSyncUuid);
      if (ledger == null) {
        _emit('⚠️ العميل غير موجود لدي — تعذّر الرفع');
        return;
      }
      await _firestore.collection(_dataCol).doc(customerSyncUuid).set(ledger);
      await _firestore.collection(_requestsCol).doc(requestId).set({
        'status': 'data_ready',
        'referenceBalance': ledger['referenceBalance'],
        'providerDeviceId': myId,
      }, SetOptions(merge: true));
      _emit('✅ رفعتُ الكشف — الجهاز الطالب سيطبّقه ويتحقق');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  بناء الكشف (Ledger) والتطبيق الإدمبوتنت
  // ══════════════════════════════════════════════════════════════════════

  /// يبني كشف العميل الكامل: كل معاملاته (بعد تعبئة UUID للناقص) + الرصيد المرجعي.
  Future<Map<String, dynamic>?> _buildCustomerLedger(String customerSyncUuid) async {
    final db = await _db.database;
    final custRows = await db.query('customers',
        where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
    if (custRows.isEmpty) {
      print('🛡️🔍 [بناء الكشف] العميل $customerSyncUuid غير موجود محلياً!');
      return null;
    }
    final cust = custRows.first;
    final customerId = cust['id'] as int;
    final storedBalance = (cust['current_total_debt'] as num?)?.toDouble() ?? 0.0;

    final txs = await db.query('transactions',
        where: 'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [customerId],
        orderBy: 'transaction_date ASC, id ASC');

    // 🔍 تشخيص محاسبي حرج: هل مجموع المعاملات يطابق الرصيد المخزّن؟
    double txSum = 0;
    for (final t in txs) {
      txSum += (t['amount_changed'] as num?)?.toDouble() ?? 0.0;
    }
    print('🛡️🔍 [بناء الكشف] العميل «${cust['name']}» (id=$customerId)');
    print('🛡️🔍 [بناء الكشف] عدد المعاملات=${txs.length} | مجموعها=$txSum | الرصيد المخزّن=$storedBalance');
    if ((txSum - storedBalance).abs() > _balanceTolerance) {
      print('🛡️⚠️ [بناء الكشف] ⚠️⚠️ تحذير: مجموع المعاملات ($txSum) ≠ الرصيد المخزّن ($storedBalance)!');
      print('🛡️⚠️ [بناء الكشف] هذا يعني وجود معاملات مكررة/زائدة في السجل المحلي.');
      // كشف التكرار: نفس (التاريخ+المبلغ+النوع) أكثر من مرة
      final dupKey = <String, int>{};
      for (final t in txs) {
        final k = '${t['transaction_date']}|${t['amount_changed']}|${t['transaction_type']}';
        dupKey[k] = (dupKey[k] ?? 0) + 1;
      }
      final dups = dupKey.entries.where((e) => e.value > 1).length;
      print('🛡️⚠️ [بناء الكشف] عدد المجموعات المكررة (تاريخ+مبلغ+نوع): $dups');
    }

    // تعبئة UUID للمعاملات القديمة الناقصة (تحديث محلي دائم)
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
      final m = Map<String, dynamic>.from(tx);
      m.remove('id');
      m.remove('customer_id');
      m.remove('is_uploaded');
      m.remove('is_read_by_others');
      outTxs.add(m);
    }
    if (backfilled > 0) {
      print('🛡️🔍 [بناء الكشف] عُبّئ UUID لـ $backfilled معاملة قديمة كانت بلا هوية');
    }

    print('🛡️📤 [بناء الكشف] الكشف جاهز: ${outTxs.length} معاملة | الرصيد المرجعي=$storedBalance');

    return {
      'customerSyncUuid': customerSyncUuid,
      'customerName': cust['name'],
      'customerPhone': cust['phone'],
      'customerAddress': cust['address'],
      'referenceBalance': storedBalance,
      'referenceTxCount': outTxs.length,
      'transactions': outTxs,
      'builtAt': FieldValue.serverTimestamp(),
    };
  }

  /// يطبّق الكشف الوارد إدمبوتنت: يضيف المعاملات الناقصة (بالـ UUID) ويهمل الموجودة.
  /// لا يحذف شيئاً ولا يخترع معاملات تصحيحية. يُرجع عدد ما أُضيف فعلاً.
  Future<int> _applyCustomerLedger(Map<String, dynamic> ledger) async {
    _lastPreservedCount = 0;
    _lastPreservedSum = 0.0;
    final db = await _db.database;
    final customerSyncUuid = ledger['customerSyncUuid'] as String;
    final refBalance = (ledger['referenceBalance'] as num?)?.toDouble() ?? 0.0;
    final incoming = (ledger['transactions'] as List?)?.length ?? 0;
    print('🛡️📥 [تطبيق كشف] بدء التطبيق: العميل ${ledger['customerName']} | '
        'واردة=$incoming معاملة | الرصيد المرجعي=$refBalance');

    // العميل موجود محلياً؟ وإلا ننشئه من بيانات الكشف
    var custRows = await db.query('customers',
        columns: ['id'], where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
    int customerId;
    if (custRows.isEmpty) {
      // محاولة البحث بالاسم المطبّع كخط أمان ثانوي لمنع إنشاء عميل مكرر
      final normName = DatabaseHelpers.normalizeArabic(ledger['customerName'] ?? '');
      final allCusts = await db.query('customers', columns: ['id', 'name', 'sync_uuid']);
      Map<String, dynamic>? matchByName;
      for (final c in allCusts) {
        if (DatabaseHelpers.normalizeArabic(c['name'] as String? ?? '') == normName) {
          matchByName = c;
          break;
        }
      }
      
      if (matchByName != null) {
        customerId = matchByName['id'] as int;
        await db.update('customers', {'sync_uuid': customerSyncUuid}, where: 'id = ?', whereArgs: [customerId]);
        print('🛡️📥 [تطبيق كشف] رُبط العميل محلياً بالاسم «${ledger['customerName']}» (id=$customerId)');
      } else {
        final now = DateTime.now().toIso8601String();
        customerId = await db.insert('customers', {
          'name': ledger['customerName'] ?? 'عميل مطابقة',
          'phone': ledger['customerPhone'],
          'address': ledger['customerAddress'],
          'current_total_debt': 0.0,
          'sync_uuid': customerSyncUuid,
          'is_created_by_me': 0,
          'created_at': now,
          'last_modified_at': now,
        });
        print('🛡️📥 [تطبيق كشف] أُنشئ العميل محلياً (id=$customerId) — لم يكن موجوداً');
      }
    } else {
      customerId = custRows.first['id'] as int;
      final beforeRows = await db.query('transactions',
          where: 'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [customerId]);
      double beforeSum = 0;
      for (final t in beforeRows) {
        beforeSum += (t['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }
      print('🛡️📥 [تطبيق كشف] العميل موجود (id=$customerId) | لديه ${beforeRows.length} '
          'معاملة محلية بمجموع $beforeSum');
    }

    final txs = (ledger['transactions'] as List?) ?? const [];
    int applied = 0;
    int ignored = 0;
    int skippedNoUuid = 0;
    int deletedLocal = 0;

    // ⚖️ تُرفع خارج معاملة SQLite (لا I/O سحابي داخلها) ثم تُبثّ
    // كقرارات مطابقة لبقية الأجهزة بعد اكتمال الإبطال المحلي.
    final List<Map<String, dynamic>> rowsToVoidBroadcast = [];

    // 🔒 معاملات من إنشاء هذا الجهاز غائبة عن الكشف الوارد: تُصان ولا تُحذف
    final List<Map<String, dynamic>> preservedLocal = [];

    await db.transaction((txn) async {
      final incomingUuids = <String>{};
      
      for (final raw in txs) {
        final tx = Map<String, dynamic>.from(raw as Map);
        final txUuid = ((tx['transaction_uuid'] as String?)?.isNotEmpty == true
            ? tx['transaction_uuid']
            : tx['sync_uuid']) as String?;
        if (txUuid == null || txUuid.isEmpty) {
          skippedNoUuid++;
          continue; // لا هوية = لا نضيف
        }
        
        incomingUuids.add(txUuid);

        final existing = await txn.query('transactions',
            columns: ['id'],
            where: 'transaction_uuid = ? OR sync_uuid = ?',
            whereArgs: [txUuid, txUuid],
            limit: 1);
        if (existing.isNotEmpty) {
          ignored++;
          continue; // موجود = نُهمله (إدمبوتنت)
        }

        tx.remove('id');
        tx.remove('is_uploaded');
        tx.remove('is_read_by_others');
        tx['customer_id'] = customerId;
        tx['is_created_by_me'] = 0;
        tx['is_uploaded'] = 1;
        // تأمين الحقول الإلزامية
        tx['transaction_date'] =
            tx['transaction_date'] ?? DateTime.now().toIso8601String();
        tx['amount_changed'] = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
        tx['transaction_type'] = tx['transaction_type'] ?? 'مطابقة';
        tx['created_at'] = tx['created_at'] ?? DateTime.now().toIso8601String();
        await txn.insert('transactions', tx);
        applied++;
      }

      // ═══════════════════════════════════════════════════════════════════
      // 🛡️ حذف الزائد — مع صون ما أنشأه هذا الجهاز ولم يره المصدر بعد
      // ═══════════════════════════════════════════════════════════════════
      //
      // كان هذا الموضع يحذف **كل** معاملة محلية غير موجودة في الكشف الوارد،
      // «لضمان التطابق التام». لكن الجهاز المستقبِل يطبّق تلقائياً عبر مستمع
      // Firestore بلا أي موافقة منه — فكان تسديد سجّله صاحب الجهاز الآخر قبل
      // دقائق، ولم يُرفع بعد، يُمحى لمجرد أن أحداً ضغط «بياناتي صحيحة».
      //
      // القاعدة الآمنة: لا نحذف إلا ما وصلنا أصلاً من المزامنة
      // (is_created_by_me = 0). أما ما أنشأه هذا الجهاز بنفسه فلا يملك المصدر
      // علماً به، وغيابه من الكشف لا يعني بطلانه — بل يعني أنه لم يصل بعد.
      // نُبقيه، ونُعلّمه للرفع، ونُبلّغ المُبادِر بالتباين ليقرر إنسان.
      final List<Map<String, dynamic>> rowsToDelete = [];
      List<Map<String, dynamic>> excessRows = const [];

      if (incomingUuids.isNotEmpty) {
        final placeholders = List.filled(incomingUuids.length, '?').join(',');
        excessRows = await txn.rawQuery('''
          SELECT * FROM transactions
          WHERE customer_id = ?
            AND (
              COALESCE(NULLIF(transaction_uuid, ''), NULLIF(sync_uuid, '')) IS NULL
              OR COALESCE(NULLIF(transaction_uuid, ''), NULLIF(sync_uuid, '')) NOT IN ($placeholders)
            )
            AND (is_deleted IS NULL OR is_deleted = 0)
        ''', [customerId, ...incomingUuids]);
      } else if (txs.isEmpty) {
        // كشف فارغ: المصدر يقول «لا معاملات لهذا العميل»
        excessRows = await txn.rawQuery('''
          SELECT * FROM transactions
          WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
        ''', [customerId]);
      }

      for (final row in excessRows) {
        final mine = ((row['is_created_by_me'] as int?) ?? 1) == 1;
        if (mine) {
          // 🔒 من إنشاء هذا الجهاز: يُصان ويُعاد إلى طابور الرفع
          preservedLocal.add(Map<String, dynamic>.from(row));
          await txn.update('transactions', {'is_uploaded': 0},
              where: 'id = ?', whereArgs: [row['id']]);
          continue;
        }
        rowsToDelete.add(Map<String, dynamic>.from(row));
        rowsToVoidBroadcast.add(Map<String, dynamic>.from(row));
        await txn.update('transactions', {'is_deleted': 1},
            where: 'id = ?', whereArgs: [row['id']]);
        deletedLocal++;
      }

      if (preservedLocal.isNotEmpty) {
        double keptSum = 0;
        for (final r in preservedLocal) {
          keptSum += (r['amount_changed'] as num?)?.toDouble() ?? 0.0;
        }
        _lastPreservedCount = preservedLocal.length;
        _lastPreservedSum = keptSum;
        print('🛡️🔒 [تطبيق كشف] صُينت ${preservedLocal.length} معاملة من إنشاء '
            'هذا الجهاز لم يرسلها المصدر (مجموعها $keptSum) — أُعيدت للرفع '
            'ولم تُحذف. سيُبلَّغ المُبادِر بالتباين.');
      }

      if (rowsToDelete.isNotEmpty) {
        _archiveDeletedTransactions(rowsToDelete, ledger['customerName']?.toString());
      }

      // إعادة حساب الرصيد من المجموع (شباك الأمان المحاسبي)
      final sum = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount_changed),0) as s, COUNT(*) as c FROM transactions '
          'WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          [customerId]);
      final newBalance = (sum.first['s'] as num?)?.toDouble() ?? 0.0;
      final totalCount = sum.first['c'] as int? ?? 0;
      await txn.update('customers',
          {'current_total_debt': newBalance},
          where: 'id = ?',
          whereArgs: [customerId]);
      print('🛡️📥 [تطبيق كشف] النتيجة: أُضيف=$applied | حُذف الزائد=$deletedLocal | أُهمل (موجود)=$ignored | '
          'بلا هوية=$skippedNoUuid');
      print('🛡️📥 [تطبيق كشف] الرصيد الجديد من المجموع=$newBalance عبر $totalCount معاملة '
          '(المرجعي=$refBalance)');
      if ((newBalance - refBalance).abs() > _balanceTolerance) {
        print('🛡️⚠️ [تطبيق كشف] الرصيد الناتج ($newBalance) ≠ المرجعي ($refBalance) — '
            'سيُبلَّغ المُبادِر بالتباين');
      }
    });

    // ⚖️ بثّ قرارات الإبطال لبقية الأجهزة (خارج معاملة SQLite):
    // الجهاز الخامس/السادس الذي لم يكن في الجلسة يستقبلها ويبطل ما عنده
    // أيضاً — فينتشر الإصلاح على الشبكة كلها بضغطة واحدة.
    if (rowsToVoidBroadcast.isNotEmpty) {
      try {
        await MatchVerdictService().publishVerdicts(
          customerSyncUuid: customerSyncUuid,
          voidedRows: rowsToVoidBroadcast,
          truthDeviceId: ledger['truthDeviceId'] as String? ?? 'unknown',
          referenceBalance: refBalance,
        );
      } catch (e) {
        print('🛡️⚠️ [تطبيق كشف] فشل بثّ قرارات الإبطال (غير حرج محلياً): $e');
      }
    }

    return applied;
  }

  void _archiveDeletedTransactions(List<Map<String, dynamic>> rows, String? customerName) {
    if (_fs == null) return;
    
    final now = DateTime.now();
    // مدة البقاء: سنتان من الآن
    final expiresAt = now.add(const Duration(days: 730)); 
    
    final batch = _fs!.batch();
    for (var row in rows) {
      final docRef = _fs!.collection('deleted_transactions').doc();
      final data = Map<String, dynamic>.from(row);
      data['archived_at'] = now.toIso8601String();
      data['expires_at'] = Timestamp.fromDate(expiresAt); // ليتمكن الفايربيز من حذفها تلقائيا عبر TTL
      data['customer_name'] = customerName ?? 'غير معروف';
      
      batch.set(docRef, data);
    }
    
    batch.commit().then((_) {
      print('🛡️📤 [أرشفة] تمت أرشفة ${rows.length} معاملة محذوفة في فايربيز');
    }).catchError((e) {
      print('🛡️⚠️ [أرشفة] خطأ أثناء أرشفة المعاملات المحذوفة: $e');
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  //  التحقق والتنظيف
  // ══════════════════════════════════════════════════════════════════════

  /// ينتظر ردود الأجهزة على طلب truth_push ويتحقق منها (حلقة مغلقة حقيقية).
  Future<bool> _awaitVerification(String customerSyncUuid, String requestId,
      {required double referenceBalance}) async {
    final completer = Completer<bool>();
    Timer? timeout;
    print('🛡️⏳ [انتظار] بدء الاستماع لردود $_resultsCol للعميل $customerSyncUuid '
        '(المرجعي=$referenceBalance، المهلة=${_responseTimeout.inSeconds}ث)');

    late final StreamSubscription sub;
    sub = _firestore
        .collection(_resultsCol)
        .where('customerSyncUuid', isEqualTo: customerSyncUuid)
        .snapshots()
        .listen((snap) async {
      print('🛡️⏳ [انتظار] وصل إشعار من مجموعة النتائج: ${snap.docChanges.length} تغيير');
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final data = change.doc.data();
        if (data == null) continue;
        final balanceAfter = (data['balanceAfter'] as num?)?.toDouble() ?? 0.0;
        final applier = data['applierDeviceId'] as String? ?? 'جهاز';
        final applied = data['appliedCount'] as int? ?? 0;
        print('🛡️⏳ [انتظار] 📩 رد وصل من الجهاز $applier: طبّق=$applied معاملة | '
            'رصيده بعد التطبيق=$balanceAfter');

        if ((balanceAfter - referenceBalance).abs() <= _balanceTolerance) {
          print('🛡️✅ [انتظار] تطابق مؤكد من $applier (الفرق ضمن $_balanceTolerance)');
          _emit('✅ $applier طبّق $applied معاملة وتطابق الرصيد — مطابقة ناجحة');
          await _firestore.collection(_requestsCol).doc(requestId)
              .set({'status': 'completed'}, SetOptions(merge: true));
          await _cleanupCustomerDocs(customerSyncUuid);
          await sub.cancel();
          timeout?.cancel();
          if (!completer.isCompleted) completer.complete(true);
        } else {
          final diff = balanceAfter - referenceBalance;
          print('🛡️❌ [انتظار] تباين من $applier: رصيده=$balanceAfter ≠ المرجعي='
              '$referenceBalance (الفرق=$diff — '
              '${(balanceBalanceRatioHint(balanceAfter, referenceBalance))})');
          // 🔒 تفسير التباين إن كان سببه صون معاملات محلية لم يعرفها المصدر
          final preservedCount = (data['preservedCount'] as num?)?.toInt() ?? 0;
          final preservedSum =
              (data['preservedSum'] as num?)?.toDouble() ?? 0.0;
          if (preservedCount > 0) {
            _emit('⚠️ $applier لديه $preservedCount معاملة من إنشائه '
                '(مجموعها $preservedSum) لم تصلك بعد، فلم تُحذف. '
                'رصيده $balanceAfter مقابل المرجعي $referenceBalance. '
                'انتظر اكتمال المزامنة ثم أعد المطابقة، أو راجعها معه.');
          } else {
            _emit('⚠️ $applier طبّق الكشف لكن رصيده ($balanceAfter) ما زال مختلفاً '
                'عن المرجعي ($referenceBalance)');
          }
          await _firestore.collection(_requestsCol).doc(requestId)
              .set({'status': 'mismatch'}, SetOptions(merge: true));
          await sub.cancel();
          timeout?.cancel();
          if (!completer.isCompleted) completer.complete(false);
        }
        return; // أول رد يكفي للتحقق
      }
    }, onError: (e) {
      print('🛡️❌ [انتظار] خطأ استماع نتائج المطابقة: $e');
    });

    timeout = Timer(_responseTimeout, () async {
      print('🛡️⏰ [انتظار] انتهت المهلة (${_responseTimeout.inSeconds}ث) دون أي رد — '
          'لا جهاز استلم/استجاب للطلب');
      _emit('⏰ انتهت المهلة دون رد من الأجهزة الأخرى');
      await _firestore.collection(_requestsCol).doc(requestId)
          .set({'status': 'timeout'}, SetOptions(merge: true));
      await sub.cancel();
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  /// تلميح تشخيصي: هل الفرق مضاعف exactly؟ (يشرح سبب التباين غالباً)
  String balanceBalanceRatioHint(double balance, double reference) {
    if (reference != 0 && (balance / reference - 2).abs() < 0.001) {
      return 'الرصيد ضعف المرجعي بالضبط — يشير لمعاملات مكررة عند المُبادِر';
    }
    if (reference != 0 && (balance / reference - 0.5).abs() < 0.001) {
      return 'الرصيد نصف المرجعي — يشكر لنقص معاملات عند المستقبِل';
    }
    return 'فرق غير مضاعف';
  }

  /// حذف فوري لكل وثائق العميل من فولدر المطابقة (يبقى الفولدر نظيفاً).
  Future<void> _cleanupCustomerDocs(String customerSyncUuid,
      {String? keepRequestId}) async {
    try {
      await _firestore.collection(_dataCol).doc(customerSyncUuid).delete();
    } catch (_) {}
    try {
      await _firestore
          .collection(_requestsCol)
          .where('customerSyncUuid', isEqualTo: customerSyncUuid)
          .get()
          .then((s) async {
        for (final d in s.docs) {
          if (keepRequestId != null && d.id == keepRequestId) continue;
          await d.reference.delete();
        }
      });
    } catch (_) {}
    try {
      await _firestore
          .collection(_resultsCol)
          .where('customerSyncUuid', isEqualTo: customerSyncUuid)
          .get()
          .then((s) async {
        for (final d in s.docs) {
          await d.reference.delete();
        }
      });
    } catch (_) {}
    if (keepRequestId != null) {
      try {
        await _firestore.collection(_requestsCol).doc(keepRequestId).delete();
      } catch (_) {}
    }
  }

  /// حذف الوثائق المتروكة الأقدم من ساعة (طلبات ميتة/منتهية).
  Future<void> _cleanupStaleDocs() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    for (final col in [_requestsCol, _resultsCol, _dataCol]) {
      try {
        final snap = await _firestore
            .collection(col)
            .where('createdAt', isLessThan: cutoff)
            .get();
        for (final d in snap.docs) {
          await d.reference.delete();
        }
        // وثائق data لا تحمل createdAt بل builtAt
        if (col == _dataCol) {
          final snap2 = await _firestore
              .collection(col)
              .where('builtAt', isLessThan: cutoff)
              .get();
          for (final d in snap2.docs) {
            await d.reference.delete();
          }
        }
      } catch (_) {}
    }
  }

  Future<double> _localBalanceFor(String customerSyncUuid) async {
    final db = await _db.database;
    final rows = await db.query('customers',
        columns: ['current_total_debt'],
        where: 'sync_uuid = ?',
        whereArgs: [customerSyncUuid],
        limit: 1);
    if (rows.isEmpty) return 0.0;
    return (rows.first['current_total_debt'] as num?)?.toDouble() ?? 0.0;
  }

  Future<bool> _verifyLocalBalance(String customerSyncUuid, double reference) async {
    final balance = await _localBalanceFor(customerSyncUuid);
    return (balance - reference).abs() <= _balanceTolerance;
  }
}
