// lib/services/firebase_sync/smart_pipe_cleanup_service.dart
// Firebase كأنبوب مؤقت: الحذف الذكي بعد قراءة جميع الأجهزة النشطة
// المنطق: مستند محفوظ محلياً في SQLite → لا داعي لبقائه في Firebase

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

  // حذف بعد أسبوع (7 أيام) من الرفع إذا قرأها الجميع
  static const int _gracePeriodDays = 7;

  // جهاز خامل أكثر من 90 يوم → يُستبعد من حساب القراءة
  static const int _deviceInactiveDays = 90;

  // جهاز جديد لم يكمل مزامنته بعد → يُستبعد أيضاً
  static const String _newDeviceFlag = 'isNewDevice';

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

      final cutoff =
          DateTime.now().subtract(Duration(days: _gracePeriodDays));

      // 2. حذف المعاملات
      final txResult = await _cleanupCollection(
        groupId: groupId,
        collection: 'transactions',
        senderField: 'deviceId',
        timestampField: 'uploadedAt',
        cutoff: cutoff,
        eligibleDevices: eligibleDevices,
        ackCollection: 'transaction_acks',
        ackSyncField: 'transactionSyncUuid',
        ackDeviceField: 'receiverDeviceId',
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

      // 4. حذف العملاء القديمة المُحذوفة (soft delete)
      deletedCust = await _cleanupDeletedCustomers(groupId, cutoff);

      // 5. حذف ACKs القديمة التابعة لمستندات محذوفة
      deletedAcks = await _cleanupOrphanedAcks(groupId);

      // 6. الحذف النهائي (Hard TTL) بناءً على إعدادات المستخدم الديناميكية
      await _runHardTTLCleanup(groupId);

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

    final now = DateTime.now();
    final eligible = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // جهاز جديد لم يكمل مزامنته → مستبعد من الحساب
      if (data[_newDeviceFlag] == true) continue;

      final lastSeen = data['lastSeen'];
      DateTime? lastSeenDate;

      if (lastSeen is Timestamp) {
        lastSeenDate = lastSeen.toDate();
      } else if (lastSeen is String) {
        lastSeenDate = DateTime.tryParse(lastSeen);
      }

      // جهاز خامل أكثر من 90 يوم → يُستبعد
      if (lastSeenDate == null ||
          now.difference(lastSeenDate).inDays > _deviceInactiveDays) {
        continue;
      }

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
  }) async {
    int deleted = 0;
    int skipped = 0;

    // جلب batch من 100 مستند
    final snapshot = await _firestore!
        .collection(collection)
        .limit(100)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      // 1. التحقق من تجاوز grace period
      final ts = data[timestampField];
      DateTime? uploadedAt;

      if (ts is Timestamp) {
        uploadedAt = ts.toDate();
      } else if (ts is String) {
        uploadedAt = DateTime.tryParse(ts);
      }

      if (uploadedAt == null || uploadedAt.isAfter(cutoff)) {
        // لم تمر grace period بعد
        continue;
      }

      // 2. جهاز المُرسل
      final senderId = data[senderField] as String?;

      // 3. جلب ACKs لهذا المستند
      final acksSnapshot = await _firestore!
          .collection(ackCollection)
          .where(ackSyncField, isEqualTo: doc.id)
          .get();

      final ackedDevices =
          acksSnapshot.docs.map((a) => a.data()[ackDeviceField] as String? ?? '').toSet();

      // 4. التحقق: هل كل جهاز مؤهل (غير المرسل) قرأ المستند؟
      bool allRead = true;
      for (final device in eligibleDevices) {
        if (device == senderId) continue; // المرسل لا يحتاج ACK
        if (!ackedDevices.contains(device)) {
          allRead = false;
          break;
        }
      }

      if (allRead) {
        await doc.reference.delete();
        deleted++;
        print('🗑️ [SmartPipe] حُذف من $collection: ${doc.id}');
      } else {
        skipped++;
      }
    }

    return {'deleted': deleted, 'skipped': skipped};
  }

  // ═══════════════════════════════════════════════════════════════════════
  // حذف العملاء المُعلَّمين كمحذوفين بعد تأكيد وصولهم
  // ═══════════════════════════════════════════════════════════════════════

  Future<int> _cleanupDeletedCustomers(String groupId, DateTime cutoff) async {
    int deleted = 0;

    final snapshot = await _firestore!
        .collection('customers')
        .where('isDeleted', isEqualTo: true)
        .limit(100)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final deletedAtStr = data['deletedAt'] as String?;
      if (deletedAtStr == null) continue;

      try {
        final deletedAt = DateTime.parse(deletedAtStr);
        // احذف إذا مر على الحذف أكثر من grace period
        if (deletedAt.isBefore(cutoff)) {
          await doc.reference.delete();
          deleted++;
        }
      } catch (_) {}
    }

    return deleted;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // حذف ACKs اليتيمة (تابعة لمستندات محذوفة بالفعل)
  // ═══════════════════════════════════════════════════════════════════════

  Future<int> _cleanupOrphanedAcks(String groupId) async {
    int deleted = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 60));

    for (final ackColl in ['transaction_acks', 'invoice_read_acks']) {
      final snapshot = await _firestore!
          .collection(ackColl)
          .limit(200)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final readAtRaw = data['readAt'];
        DateTime? readAt;

        if (readAtRaw is Timestamp) {
          readAt = readAtRaw.toDate();
        } else if (readAtRaw is String) {
          readAt = DateTime.tryParse(readAtRaw);
        }

        // احذف ACKs القديمة (أقدم من 60 يوم) — المستند الأصل محذوف بالتأكيد
        if (readAt != null && readAt.isBefore(cutoff)) {
          await doc.reference.delete();
          deleted++;
        }
      }
    }

    return deleted;
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
        'transactionSyncUuid': syncUuid,
        'deviceId': deviceId,
        'readAt': FieldValue.serverTimestamp(),
        'groupSecret': groupSecret,
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
        'groupSecret': groupSecret,
      }, SetOptions(merge: true));
    } catch (e) {
      print('⚠️ [SmartPipe] فشل إرسال invoice ACK: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الحذف التلقائي الديناميكي (Hard TTL) كبديل لفايربيس
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _runHardTTLCleanup(String groupId) async {
    try {
      final days = await FirebaseSyncSecuritySettings.getAutoDeleteDays();
      final cutoff = DateTime.now().subtract(Duration(days: days));
      
      print('🗑️ [Hard TTL] فحص التواريخ الأقدم من $days يوم (قبل ${cutoff.toString().split(' ')[0]})...');

      int ttlDeleted = 0;
      final collections = {
        'transactions': 'uploadedAt',
        'customers': 'uploadedAt',
        'invoices': 'uploadedAt'
      };

      for (var entry in collections.entries) {
        final collName = entry.key;
        final dateField = entry.value;

        // جلب عينة لفحصها محلياً لدعم التاريخين (String و Timestamp)
        final snapshot = await _firestore!
            .collection(collName)
            .limit(300)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          final rawDate = data[dateField] ?? data['uploadedAt'];
          DateTime? date;

          if (rawDate is Timestamp) {
            date = rawDate.toDate();
          } else if (rawDate is String) {
            date = DateTime.tryParse(rawDate);
          }

          if (date != null && date.isBefore(cutoff)) {
            await doc.reference.delete();
            ttlDeleted++;
          }
        }
      }

      if (ttlDeleted > 0) {
        print('✅ [Hard TTL] تم تدمير $ttlDeleted سجل منتهي الصلاحية نهائياً بنجاح.');
      } else {
        print('ℹ️ [Hard TTL] لا توجد سجلات منتهية الصلاحية.');
      }
    } catch (e) {
      print('❌ [Hard TTL] فشل الحذف التلقائي: $e');
    }
  }
}
