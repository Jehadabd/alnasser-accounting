// lib/services/firebase_sync/smart_pipe_cleanup_service.dart
// Firebase كأنبوب مؤقت: الحذف الذكي بعد قراءة جميع الأجهزة النشطة
// المنطق: مستند محفوظ محلياً في SQLite → لا داعي لبقائه في Firebase
//
// 🛡️ قواعد الأمان (المحاكاة: tools/sync_sim سيناريوهات 29، 30 + الفوضى)
//   • الإقرار يُحسب فقط إن كان أحدث من نسخة المستند الحالية (readAt ≥ uploadedAt).
//     كان إقرار قراءة النسخة الأولى يكفي لحذف نسخة معدّلة أو شاهد حذف كُتب
//     بعدها، فيفوت الجهاز الذي لم يقرأها التعديل أو الحذف إلى الأبد.
//   • الحذف مشروط داخل معاملة Firestore: إن تغيّرت النسخة بين الفحص والحذف
//     (شاهد حذف كُتب للتو) لا نحذف.
//   • لا تُحذف شواهد حذف العملاء ولا الإقرارات: شاهد العميل هو الطريق الوحيد
//     لجهاز غائب ليعرف بالحذف، والإقرار دليل تعتمده المطابقة المحصّنة.
//   • ولا تُحذف شواهد حذف المعاملات (isDeleted = true): «كل من يعرفها قرأها»
//     لا يشمل جهازاً ينضم لاحقاً ولا جهازاً يستعيد نسخة احتياطية أقدم من
//     الحذف. كلاهما يستلم الدين حياً (من حزمة الفاتورة أو من نسخته) ولا
//     يصله الحذف من أي طريق آخر: إعادة البثّ للجهاز الجديد لا تحمل إلا
//     النشط (اختبار الكود الحقيقي: test/sync_harness).

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_sync_config.dart';

/// نتيجة عملية الحذف الذكي
class PipeCleanupResult {
  final int deletedTransactions;
  final int deletedCustomers;
  final int deletedInvoices;
  final int deletedAcks;
  final int skippedPendingRead; // مستندات لم تُقرأ من بعض الأجهزة
  final DateTime ranAt;

  PipeCleanupResult({
    required this.deletedTransactions,
    required this.deletedCustomers,
    required this.deletedInvoices,
    required this.deletedAcks,
    required this.skippedPendingRead,
    required this.ranAt,
  });

  Map<String, dynamic> toMap() => {
        'deletedTransactions': deletedTransactions,
        'deletedCustomers': deletedCustomers,
        'deletedInvoices': deletedInvoices,
        'deletedAcks': deletedAcks,
        'skippedPendingRead': skippedPendingRead,
        'ranAt': ranAt.toIso8601String(),
      };
}

/// خدمة الحذف الذكي: Firebase كأنبوب مؤقت
class SmartPipeCleanupService {
  static final SmartPipeCleanupService _instance =
      SmartPipeCleanupService._internal();
  factory SmartPipeCleanupService() => _instance;
  SmartPipeCleanupService._internal();

  FirebaseFirestore? _firestore;
  Timer? _cleanupTimer;
  bool _isRunning = false;

  // حذف بعد المدة التي يضبطها المستخدم (getAutoDeleteDays) من الرفع
  // وشرط إضافي إلزامي: قراءة المستند من كل الأجهزة المؤهلة (ACKs)

  // جهاز جديد لم يكمل مزامنته بعد → يُستبعد أيضاً
  static const String _newDeviceFlag = 'isNewDevice';

  // جهاز اعتُبر خارج الخدمة بقرار يدوي من صاحب المحل → يُستبعد
  static const String _retiredDeviceFlag = 'isRetired';

  // ═══════════════════════════════════════════════════════════════════════
  // تشغيل وإيقاف
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> start() async {
    if (!await FirebaseSyncConfig.isEnabled()) return;

    _firestore ??= FirebaseFirestore.instance;

    // تنفيذ فوري عند البدء
    await _runCleanup();

    // ثم كل 6 ساعات
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 6), (_) => _runCleanup());
  }

  void stop() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الإرسال اليدوي (من الإعدادات)
  // ═══════════════════════════════════════════════════════════════════════

  Future<PipeCleanupResult> runManualCleanup() async {
    _firestore ??= FirebaseFirestore.instance;
    return await _runCleanup();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // منطق الحذف الرئيسي
  // ═══════════════════════════════════════════════════════════════════════

  Future<PipeCleanupResult> _runCleanup() async {
    if (_isRunning) {
      return PipeCleanupResult(
        deletedTransactions: 0,
        deletedCustomers: 0,
        deletedInvoices: 0,
        deletedAcks: 0,
        skippedPendingRead: 0,
        ranAt: DateTime.now(),
      );
    }

    _isRunning = true;

    int deletedTx = 0;
    int deletedCust = 0;
    int deletedInv = 0;
    int deletedAcks = 0;
    int skipped = 0;

    try {
      final groupId = await FirebaseSyncConfig.getSyncGroupId();
      if (groupId == null || _firestore == null) {
        _isRunning = false;
        return PipeCleanupResult(
          deletedTransactions: 0,
          deletedCustomers: 0,
          deletedInvoices: 0,
          deletedAcks: 0,
          skippedPendingRead: 0,
          ranAt: DateTime.now(),
        );
      }

      print('🧹 [SmartPipe] بدء الحذف الذكي...');

      // 1. جلب قائمة الأجهزة المؤهلة (نشطة ولم تُعلَّم كجهاز جديد)
      final eligibleDevices = await _getEligibleDevices(groupId);
      print('📱 [SmartPipe] أجهزة مؤهلة للحساب: ${eligibleDevices.length}');

      if (eligibleDevices.isEmpty) {
        // لا أجهزة مسجلة → لا حذف آمن
        print('⚠️ [SmartPipe] لا توجد أجهزة مسجلة، تخطي الحذف');
        _isRunning = false;
        return PipeCleanupResult(
          deletedTransactions: 0,
          deletedCustomers: 0,
          deletedInvoices: 0,
          deletedAcks: 0,
          skippedPendingRead: 0,
          ranAt: DateTime.now(),
        );
      }

      // 🔒 الحذف يتبع المدة التي ضبطها المستخدم في الإعدادات
      final userDays = await FirebaseSyncSecuritySettings.getAutoDeleteDays();
      final cutoff = DateTime.now().subtract(Duration(days: userDays));
      print('🧹 [SmartPipe] عمر الحذف الأدنى: $userDays يوم (قبل ${cutoff.toString().split(' ')[0]})');

      // 2. حذف المعاملات (بعد قراءة الجميع فقط)
      //    الحقول متوافقة مع TransactionAckService.sendAck:
      //    transactionUuid / receiverDeviceId
      final txResult = await _cleanupCollection(
        groupId: groupId,
        collection: 'transactions',
        senderField: 'deviceId',
        timestampField: 'uploadedAt',
        cutoff: cutoff,
        eligibleDevices: eligibleDevices,
        ackCollection: 'transaction_acks',
        ackSyncField: 'transactionUuid',
        ackDeviceField: 'receiverDeviceId',
        keepTombstones: true,
      );
      deletedTx = txResult['deleted'] as int;
      skipped += txResult['skipped'] as int;

      // 3. حذف الفواتير
      final invResult = await _cleanupCollection(
        groupId: groupId,
        collection: 'invoices',
        senderField: 'creator_device_id',
        timestampField: 'uploadedAt',
        cutoff: cutoff,
        eligibleDevices: eligibleDevices,
        ackCollection: 'invoice_read_acks',
        ackSyncField: 'invoiceUuid',
        ackDeviceField: 'deviceId',
      );
      deletedInv = invResult['deleted'] as int;
      skipped += invResult['skipped'] as int;

      // 4. 🛡️ شواهد حذف العملاء تبقى (انظر رأس الملف) — كانت تُحذف بعد المدة
      //    دون أي تأكيد قراءة، فيبقى العميل حياً على جهاز غاب أطول منها.
      // 5. 🛡️ الإقرارات تبقى (انظر رأس الملف).

      // 🔒 تم إلغاء الحذف النهائي الأعمى (_runHardTTLCleanup):
      // لا يُمحى أي مستند مهما تقادم إلا إذا قرأته كل الأجهزة المؤهلة أعلاه.

      print(
          '✅ [SmartPipe] اكتمل: معاملات=$deletedTx، فواتير=$deletedInv، عملاء=$deletedCust، ACKs=$deletedAcks، تخطي=$skipped');
    } catch (e) {
      print('❌ [SmartPipe] خطأ في الحذف الذكي: $e');
    } finally {
      _isRunning = false;
    }

    return PipeCleanupResult(
      deletedTransactions: deletedTx,
      deletedCustomers: deletedCust,
      deletedInvoices: deletedInv,
      deletedAcks: deletedAcks,
      skippedPendingRead: skipped,
      ranAt: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // جلب الأجهزة المؤهلة (نشطة وليست جديدة)
  // ═══════════════════════════════════════════════════════════════════════

  Future<Set<String>> _getEligibleDevices(String groupId) async {
    final snapshot = await _firestore!
        .collection('devices')
        .get();

    // ملاحظة: كل مستخدم يملك مشروع Firebase خاصاً، فكل الأجهزة في
    // هذا المشروع تنتمي لنفس المجموعة عملياً — لا حاجة لتصفية إضافية.

    final eligible = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // جهاز جديد لم يكمل مزامنته → مستبعد من الحساب
      if (data[_newDeviceFlag] == true) continue;

      // 🚫 جهاز اعتُبر خارج الخدمة بقرار يدوي موثّق → مستبعد
      if (data[_retiredDeviceFlag] == true) continue;

      // ⚠️ لا يوجد استبعاد تلقائي للأجهزة الخاملة بعد الآن:
      // الجهاز الغائب يبقى مطالباً بالقراءة (ACK) حتى يعود أو يُعتبر
      // خارج الخدمة بقرار يدوي — هذا يمنع فقد بيانات جهاز غائب طويلاً.

      eligible.add(doc.id);
    }

    return eligible;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // حذف مجموعة (معاملات أو فواتير) بعد تأكيد قراءة الجميع
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, int>> _cleanupCollection({
    required String groupId,
    required String collection,
    required String senderField,
    required String timestampField,
    required DateTime cutoff,
    required Set<String> eligibleDevices,
    required String ackCollection,
    required String ackSyncField,
    required String ackDeviceField,
    bool keepTombstones = false,
  }) async {
    int deleted = 0;
    int skipped = 0;

    // 🔁 تصفّح دائري كامل للمجموعة (بدل عينة 100 محدودة سابقاً)
    const batchSize = 500;
    DocumentSnapshot<Object?>? lastDoc;

    while (true) {
      var query = _firestore!
          .collection(collection)
          .orderBy(FieldPath.documentId)
          .limit(batchSize);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;
      lastDoc = snapshot.docs.last;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // 🛡️ شاهد الحذف دائم (انظر رأس الملف)
        if (keepTombstones && (data['isDeleted'] == true || data['is_deleted'] == 1)) {
          continue;
        }

        // 1. التحقق من تجاوز المدة التي ضبطها المستخدم
        final ts = data[timestampField];
        DateTime? uploadedAt;

        if (ts is Timestamp) {
          uploadedAt = ts.toDate();
        } else if (ts is String) {
          uploadedAt = DateTime.tryParse(ts);
        }

        if (uploadedAt == null || uploadedAt.isAfter(cutoff)) {
          // لم تمر المدة بعد
          continue;
        }

        // 2. جهاز المُرسل
        final senderId = data[senderField] as String?;

        // 3. جلب ACKs لهذا المستند: أحدث قراءة لكل جهاز
        final acksSnapshot = await _firestore!
            .collection(ackCollection)
            .where(ackSyncField, isEqualTo: doc.id)
            .get();

        final readBy = <String, DateTime>{};
        for (final a in acksSnapshot.docs) {
          final ad = a.data();
          final dev = ad[ackDeviceField] as String? ?? '';
          final at = _ackTime(ad);
          if (dev.isEmpty || at == null) continue;
          final prev = readBy[dev];
          if (prev == null || at.isAfter(prev)) readBy[dev] = at;
        }

        // 4. التحقق: هل كل جهاز مؤهل (غير المرسل) قرأ *هذه النسخة*؟
        bool allRead = true;
        for (final device in eligibleDevices) {
          if (device == senderId) continue; // المرسل لا يحتاج ACK
          final at = readBy[device];
          if (at == null || at.isBefore(uploadedAt)) {
            allRead = false;
            break;
          }
        }

        if (allRead) {
          // 5. حذف مشروط: فقط إن بقيت النسخة التي فحصناها كما هي
          final expected = data[timestampField];
          final removed = await _firestore!.runTransaction<bool>((txn) async {
            final cur = await txn.get(doc.reference);
            final cd = cur.data();
            if (cd == null || cd[timestampField] != expected) return false;
            txn.delete(doc.reference);
            return true;
          });
          if (removed) {
            deleted++;
            print('🗑️ [SmartPipe] حُذف من $collection: ${doc.id}');
          } else {
            skipped++;
          }
        } else {
          skipped++;
        }
      }

      // آخر دفعة أصغر من الحجم → انتهينا
      if (snapshot.docs.length < batchSize) break;
    }

    return {'deleted': deleted, 'skipped': skipped};
  }

  /// وقت قراءة الإقرار: readAt (توقيت الخادم). الإقرارات القديمة تحمل
  /// receivedAt بساعة الجهاز فقط؛ نطرح منها هامشاً كي لا تجعلها ساعة متقدمة
  /// تبدو أحدث من نسخة لم تُقرأ.
  static DateTime? _ackTime(Map<String, dynamic> ack) {
    final r = ack['readAt'];
    if (r is Timestamp) return r.toDate();
    if (r is String) {
      final d = DateTime.tryParse(r);
      if (d != null) return d;
    }
    final rec = ack['receivedAt'];
    if (rec is String) {
      final d = DateTime.tryParse(rec);
      if (d != null) return d.subtract(const Duration(minutes: 10));
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // اعتبار جهاز خارج الخدمة / إعادته للخدمة (قرار يدوي من صاحب المحل)
  // ═══════════════════════════════════════════════════════════════════════
  // الجهاز المُعتَرف خارج الخدمة لا يُطالَب بـ ACK، فيتاح حذف مستنداته
  // القديمة بعد قراءة بقية الأجهزة. القرار يدوي وموثّق بالتاريخ لضمان
  // عدم فقد بيانات جهاز غائب مؤقتاً.

  Future<void> setDeviceRetired(String deviceId, bool retired) async {
    _firestore ??= FirebaseFirestore.instance;
    await _firestore!.collection('devices').doc(deviceId).set({
      _retiredDeviceFlag: retired,
      if (retired) 'retiredAt': DateTime.now().toIso8601String(),
      if (!retired) 'reactivatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    print(retired
        ? '🚫 [SmartPipe] الجهاز $deviceId اعتُبر خارج الخدمة (قرار يدوي)'
        : '✅ [SmartPipe] الجهاز $deviceId أعيد للخدمة');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // إرسال Read ACK عند قراءة مستند
  // ═══════════════════════════════════════════════════════════════════════

  /// يُستدعى من firebase_sync_service بعد _applyTransactionChange
  Future<void> markTransactionRead({
    required String groupId,
    required String syncUuid,
    required String deviceId,
    required String groupSecret,
  }) async {
    _firestore ??= FirebaseFirestore.instance;

    try {
      await _firestore!
          .collection('transaction_acks')
          .doc('${syncUuid}_$deviceId')
          .set({
        // 🔒 نفس أسماء حقول TransactionAckService.sendAck ليعمل فحص الحذف
        'transactionUuid': syncUuid,
        'receiverDeviceId': deviceId,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ACK غير حرج — تجاهل الخطأ
      print('⚠️ [SmartPipe] فشل إرسال transaction ACK: $e');
    }
  }

  /// يُستدعى من invoice_sync_service بعد _processIncomingInvoice
  Future<void> markInvoiceRead({
    required String groupId,
    required String invoiceUuid,
    required String deviceId,
    required String groupSecret,
  }) async {
    _firestore ??= FirebaseFirestore.instance;

    try {
      await _firestore!
          .collection('invoice_read_acks')
          .doc('${invoiceUuid}_$deviceId')
          .set({
        'invoiceUuid': invoiceUuid,
        'deviceId': deviceId,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('⚠️ [SmartPipe] فشل إرسال invoice ACK: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🚫 تم إلغاء الحذف النهائي الأعمى (Hard TTL)
  // ═══════════════════════════════════════════════════════════════════════
  // كان هذا المسار يحذف المستندات القديمة دون أي فحص لقراءة الأجهزة (ACKs)،
  // مما قد يفقد بيانات جهاز غائب. الحذف الآن يمر حصرياً عبر _cleanupCollection
  // بشرطين معاً: تجاوز المدة التي ضبطها المستخدم + قراءة جميع الأجهزة المؤهلة.
}
