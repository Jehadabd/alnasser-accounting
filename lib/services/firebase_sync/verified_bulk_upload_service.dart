// lib/services/firebase_sync/verified_bulk_upload_service.dart
//
// 🅓 VerifiedBulkUploadService:
//   "الرفع الشامل" بالطريقة المطلوبة:
//     1) عميل واحد في كل مرة (مرتّبة أبجدياً).
//     2) جلب كل معلومات العميل + كل معاملاته.
//     3) رفع العميل → قراءة عكسية من Firebase → التحقق من الحفظ.
//     4) رفع كل معاملة واحدة تلو الأخرى → قراءة عكسية → التحقق.
//     5) الانتقال للعميل التالي فقط بعد اكتمال الحالي 100%.
//
// كل خطوة تبث SyncEvent إلى SyncEventBus فتظهر في الواجهة والسجل الحيّ.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../database_service.dart';
import 'firebase_sync_service.dart';
import 'sync_event_bus.dart';

/// نتيجة الرفع الشامل
class VerifiedBulkUploadResult {
  final int totalCustomers;
  final int successfulCustomers;
  final int failedCustomers;
  final int totalTransactions;
  final int successfulTransactions;
  final int failedTransactions;
  final Duration elapsed;
  final List<String> failedCustomerNames;
  final bool cancelled;

  const VerifiedBulkUploadResult({
    required this.totalCustomers,
    required this.successfulCustomers,
    required this.failedCustomers,
    required this.totalTransactions,
    required this.successfulTransactions,
    required this.failedTransactions,
    required this.elapsed,
    required this.failedCustomerNames,
    required this.cancelled,
  });

  Map<String, dynamic> toMap() => {
        'totalCustomers': totalCustomers,
        'successfulCustomers': successfulCustomers,
        'failedCustomers': failedCustomers,
        'totalTransactions': totalTransactions,
        'successfulTransactions': successfulTransactions,
        'failedTransactions': failedTransactions,
        'elapsedSeconds': elapsed.inSeconds,
        'failedCustomerNames': failedCustomerNames,
        'cancelled': cancelled,
      };
}

class VerifiedBulkUploadService {
  static final VerifiedBulkUploadService _instance =
      VerifiedBulkUploadService._internal();
  factory VerifiedBulkUploadService() => _instance;
  static VerifiedBulkUploadService get instance => _instance;
  VerifiedBulkUploadService._internal();

  final DatabaseService _db = DatabaseService();
  final FirebaseSyncService _sync = FirebaseSyncService();

  bool _isRunning = false;
  bool _cancelRequested = false;
  bool get isRunning => _isRunning;

  /// طلب الإيقاف — يوقف بعد انتهاء العميل الحالي (لا يقطع منتصف عميل)
  void requestCancel() {
    if (_isRunning) {
      _cancelRequested = true;
      syncBus.warning(SyncPhase.bulkUpload,
          'طُلب إيقاف الرفع الشامل — سيتوقف بعد انتهاء العميل الحالي');
    }
  }

  /// تشغيل الرفع الشامل
  Future<VerifiedBulkUploadResult> run() async {
    if (_isRunning) {
      syncBus.warning(
          SyncPhase.bulkUpload, 'الرفع الشامل يعمل بالفعل — تجاهل الطلب');
      return const VerifiedBulkUploadResult(
        totalCustomers: 0,
        successfulCustomers: 0,
        failedCustomers: 0,
        totalTransactions: 0,
        successfulTransactions: 0,
        failedTransactions: 0,
        elapsed: Duration.zero,
        failedCustomerNames: [],
        cancelled: false,
      );
    }

    _isRunning = true;
    _cancelRequested = false;
    final sw = Stopwatch()..start();
    final failedCustomers = <String>[];
    int okCustomers = 0;
    int failCustomers = 0;
    int okTx = 0;
    int failTx = 0;
    int totalTx = 0;

    try {
      // 1️⃣ التأكد من التهيئة
      if (_sync.status == FirebaseSyncStatus.notConfigured ||
          _sync.status == FirebaseSyncStatus.idle ||
          _sync.status == FirebaseSyncStatus.error) {
        syncBus.info(
            SyncPhase.bulkUpload, 'تهيئة المزامنة قبل الرفع الشامل...');
        final ok = await _sync.initialize();
        if (!ok) {
          syncBus.error(SyncPhase.bulkUpload,
              'فشل تهيئة المزامنة — إلغاء الرفع الشامل');
          return VerifiedBulkUploadResult(
            totalCustomers: 0,
            successfulCustomers: 0,
            failedCustomers: 0,
            totalTransactions: 0,
            successfulTransactions: 0,
            failedTransactions: 0,
            elapsed: sw.elapsed,
            failedCustomerNames: const [],
            cancelled: false,
          );
        }
      }

      // 2️⃣ جلب قائمة العملاء (مرتبة أبجدياً)
      final db = await _db.database;
      final customers = await db.query(
        'customers',
        where: '(is_deleted IS NULL OR is_deleted = 0) AND sync_uuid IS NOT NULL',
        orderBy: 'name COLLATE NOCASE ASC',
      );

      if (customers.isEmpty) {
        syncBus.info(SyncPhase.bulkUpload, 'لا يوجد عملاء للرفع');
        return VerifiedBulkUploadResult(
          totalCustomers: 0,
          successfulCustomers: 0,
          failedCustomers: 0,
          totalTransactions: 0,
          successfulTransactions: 0,
          failedTransactions: 0,
          elapsed: sw.elapsed,
          failedCustomerNames: const [],
          cancelled: false,
        );
      }

      // احسب مجموع المعاملات لكل العملاء لعرض تقدم دقيق
      final txCountResult = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM transactions WHERE is_deleted IS NULL OR is_deleted = 0');
      totalTx = (txCountResult.first['c'] as int?) ?? 0;

      final totalOps = customers.length + totalTx;
      syncBus.beginOverall(
        phase: SyncPhase.bulkUpload,
        total: totalOps,
        message:
            'الرفع الشامل: ${customers.length} عميل، $totalTx معاملة',
      );

      int processed = 0;

      // 3️⃣ لكل عميل: رفع + تحقق + رفع معاملاته + تحقق
      for (int i = 0; i < customers.length; i++) {
        if (_cancelRequested) {
          syncBus.warning(SyncPhase.bulkUpload,
              'تم إلغاء الرفع الشامل عند العميل ${i + 1}/${customers.length}');
          break;
        }

        final customer = Map<String, dynamic>.from(customers[i]);
        final customerId = customer['id'] as int;
        final syncUuid = customer['sync_uuid'] as String;
        final name = (customer['name'] as String?) ?? syncUuid;

        // 3a) بداية العميل
        processed++;
        syncBus.updateOverall(
          current: processed,
          message: '→ العميل $name (${i + 1}/${customers.length})',
        );
        syncBus.info(SyncPhase.bulkCustomer,
            'بدء معالجة العميل: $name',
            entityUuid: syncUuid, entityType: 'customer');

        // 3b) قراءة المعاملات
        final txs = await db.query(
          'transactions',
          where:
              'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [customerId],
          orderBy: 'transaction_date ASC, id ASC',
        );
        syncBus.debug(SyncPhase.bulkCustomer,
            'قرأت ${txs.length} معاملة للعميل $name');

        // 3c) رفع العميل مع محاولات متعددة + read-back verify
        final customerOk = await _uploadCustomerWithVerify(
          customer,
          totalCustomers: customers.length,
          index: i + 1,
        );

        if (!customerOk) {
          failCustomers++;
          failedCustomers.add(name);
          syncBus.warning(SyncPhase.bulkCustomer,
              'تخطي معاملات العميل $name بسبب فشل رفع بياناته');
          // نُقدم العدّاد بعدد المعاملات المتخطّاة كي يستمر شريط التقدّم
          processed += txs.length;
          syncBus.updateOverall(current: processed);
          failTx += txs.length;
          continue;
        }
        okCustomers++;

        // 3d) رفع المعاملات واحدة تلو الأخرى مع تحقق
        int txOkThisCustomer = 0;
        int txFailThisCustomer = 0;
        for (int j = 0; j < txs.length; j++) {
          if (_cancelRequested) {
            syncBus.warning(SyncPhase.bulkTransaction,
                'إلغاء أثناء معاملات العميل $name — يكتمل هذا العميل ثم يتوقف');
            // لا نقاطع منتصف عميل - نتابع لباقي معاملات هذا العميل ثم نتوقف
          }

          final tx = Map<String, dynamic>.from(txs[j]);
          final txSyncUuid = tx['sync_uuid'] as String? ?? '(بدون)';
          final amount = tx['amount_changed'];

          processed++;
          syncBus.updateOverall(
            current: processed,
            message:
                '→ معاملة العميل $name: $amount (${j + 1}/${txs.length})',
          );

          final txOk = await _uploadTransactionWithVerify(
            tx,
            customerSyncUuid: syncUuid,
            customerName: name,
            index: j + 1,
            total: txs.length,
          );

          if (txOk) {
            txOkThisCustomer++;
            okTx++;
          } else {
            txFailThisCustomer++;
            failTx++;
            syncBus.warning(SyncPhase.bulkTransaction,
                'فشلت معاملة $txSyncUuid — أُضيفت للطابور',
                entityUuid: txSyncUuid, entityType: 'transaction');
          }
        }

        // 3e) ملخص العميل
        if (txFailThisCustomer == 0) {
          syncBus.success(SyncPhase.bulkCustomer,
              '✅ اكتمل العميل $name: ${txs.length} معاملة',
              entityUuid: syncUuid, entityType: 'customer');
        } else {
          syncBus.warning(SyncPhase.bulkCustomer,
              '⚠️ العميل $name: نجح $txOkThisCustomer/${txs.length} معاملة',
              entityUuid: syncUuid, entityType: 'customer');
        }
      }

      // 4️⃣ الملخص النهائي
      final summary =
          'انتهى الرفع الشامل: $okCustomers/${customers.length} عميل، '
          '$okTx/$totalTx معاملة، ${sw.elapsed.inSeconds}s';
      syncBus.endOverall(
        message: summary,
        level: (failCustomers == 0 && failTx == 0)
            ? SyncEventLevel.success
            : SyncEventLevel.warning,
      );

      return VerifiedBulkUploadResult(
        totalCustomers: customers.length,
        successfulCustomers: okCustomers,
        failedCustomers: failCustomers,
        totalTransactions: totalTx,
        successfulTransactions: okTx,
        failedTransactions: failTx,
        elapsed: sw.elapsed,
        failedCustomerNames: failedCustomers,
        cancelled: _cancelRequested,
      );
    } catch (e, st) {
      syncBus.error(SyncPhase.bulkUpload, 'خطأ فادح في الرفع الشامل: $e');
      // ignore: avoid_print
      print(st);
      return VerifiedBulkUploadResult(
        totalCustomers: 0,
        successfulCustomers: okCustomers,
        failedCustomers: failCustomers,
        totalTransactions: totalTx,
        successfulTransactions: okTx,
        failedTransactions: failTx,
        elapsed: sw.elapsed,
        failedCustomerNames: failedCustomers,
        cancelled: _cancelRequested,
      );
    } finally {
      _isRunning = false;
      _cancelRequested = false;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// رفع + تحقق قراءة عكسية للعميل
  /// ═══════════════════════════════════════════════════════════════════════
  Future<bool> _uploadCustomerWithVerify(
    Map<String, dynamic> customer, {
    required int totalCustomers,
    required int index,
  }) async {
    final syncUuid = customer['sync_uuid'] as String;
    final name = (customer['name'] as String?) ?? syncUuid;

    const int maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        syncBus.info(SyncPhase.bulkCustomer,
            'رفع بيانات العميل $name (محاولة $attempt/$maxAttempts)',
            entityUuid: syncUuid,
            entityType: 'customer',
            currentIndex: index,
            totalItems: totalCustomers);

        final uploadOk = await _sync.uploadCustomer(customer);
        if (!uploadOk) {
          syncBus.warning(SyncPhase.bulkCustomer,
              'الرفع فشل للعميل $name (المحاولة $attempt)',
              entityUuid: syncUuid, entityType: 'customer');
        }

        // Read-back verify
        final verified = await _verifyCustomer(customer);
        if (verified) {
          syncBus.success(SyncPhase.verifyWrite,
              'تحقق ✅ من رفع العميل $name على Firebase',
              entityUuid: syncUuid, entityType: 'customer');

          // تحديث last_verified_at (إن وُجد العمود)
          await _markCustomerVerified(customer['id'] as int);
          return true;
        } else {
          syncBus.warning(SyncPhase.verifyWrite,
              'تحقق ❌ فشل للعميل $name — إعادة المحاولة',
              entityUuid: syncUuid, entityType: 'customer');
        }
      } catch (e) {
        syncBus.error(SyncPhase.bulkCustomer,
            'استثناء أثناء رفع العميل $name (محاولة $attempt): $e',
            entityUuid: syncUuid, entityType: 'customer');
      }

      // backoff تصاعدي
      final delay = Duration(seconds: 1 << (attempt - 1));
      await Future.delayed(delay);
    }

    syncBus.error(SyncPhase.bulkCustomer,
        'فشل رفع العميل $name بعد $maxAttempts محاولات',
        entityUuid: syncUuid, entityType: 'customer');
    return false;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// رفع + تحقق قراءة عكسية للمعاملة
  /// ═══════════════════════════════════════════════════════════════════════
  Future<bool> _uploadTransactionWithVerify(
    Map<String, dynamic> tx, {
    required String customerSyncUuid,
    required String customerName,
    required int index,
    required int total,
  }) async {
    final syncUuid = tx['sync_uuid'] as String?;
    if (syncUuid == null || syncUuid.isEmpty) {
      syncBus.warning(SyncPhase.bulkTransaction,
          'المعاملة بدون sync_uuid — تخطي', entityType: 'transaction');
      return false;
    }
    final amount = tx['amount_changed'];

    const int maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        syncBus.info(SyncPhase.bulkTransaction,
            'رفع معاملة $amount للعميل $customerName (محاولة $attempt/$maxAttempts)',
            entityUuid: syncUuid,
            entityType: 'transaction',
            currentIndex: index,
            totalItems: total);

        final uploadOk = await _sync.uploadTransaction(tx, customerSyncUuid);
        if (!uploadOk) {
          syncBus.warning(SyncPhase.bulkTransaction,
              'الرفع فشل للمعاملة (المحاولة $attempt)',
              entityUuid: syncUuid, entityType: 'transaction');
        }

        // Read-back verify
        final verified = await _verifyTransaction(tx);
        if (verified) {
          syncBus.success(SyncPhase.verifyWrite,
              'تحقق ✅ من رفع المعاملة $amount ($customerName)',
              entityUuid: syncUuid, entityType: 'transaction');

          await _markTransactionVerified(tx['id'] as int);
          return true;
        } else {
          syncBus.warning(SyncPhase.verifyWrite,
              'تحقق ❌ فشل للمعاملة — إعادة المحاولة',
              entityUuid: syncUuid, entityType: 'transaction');
        }
      } catch (e) {
        syncBus.error(SyncPhase.bulkTransaction,
            'استثناء أثناء رفع المعاملة: $e',
            entityUuid: syncUuid, entityType: 'transaction');
      }

      final delay = Duration(seconds: 1 << (attempt - 1));
      await Future.delayed(delay);
    }

    return false;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// التحقق (قراءة عكسية من Source.server)
  /// ═══════════════════════════════════════════════════════════════════════

  Future<bool> _verifyCustomer(Map<String, dynamic> customer) async {
    final firestore = FirebaseFirestore.instance;
    final syncUuid = customer['sync_uuid'] as String;

    try {
      final snap = await firestore
          .collection('customers')
          .doc(syncUuid)
          .get(const GetOptions(source: Source.server));

      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;

      // نتحقق من الحقول الجوهرية
      final remoteName = data['name']?.toString();
      final localName = customer['name']?.toString();
      if (remoteName != localName) return false;

      final remoteDebt =
          (data['currentTotalDebt'] as num?)?.toDouble() ?? 0.0;
      final localDebt =
          (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      // فرق صغير مسموح لتفادي مشاكل تقريب double
      if ((remoteDebt - localDebt).abs() > 0.001) {
        syncBus.debug(SyncPhase.verifyWrite,
            'التحقق: فرق في الرصيد $remoteDebt vs $localDebt');
        return false;
      }

      // uploadedAt يجب أن يكون موجود = دليل أن السيرفر حفظ فعلاً
      if (data['uploadedAt'] == null) return false;

      return true;
    } on FirebaseException catch (e) {
      syncBus.debug(SyncPhase.verifyWrite,
          'استثناء أثناء التحقق من العميل: ${e.code} - ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _verifyTransaction(Map<String, dynamic> tx) async {
    final firestore = FirebaseFirestore.instance;
    final syncUuid = tx['sync_uuid'] as String;

    try {
      final snap = await firestore
          .collection('transactions')
          .doc(syncUuid)
          .get(const GetOptions(source: Source.server));

      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;

      // نتحقق من الحقول الجوهرية
      final remoteAmount =
          (data['amountChanged'] as num?)?.toDouble() ??
              (data['amount_changed'] as num?)?.toDouble() ??
              0.0;
      final localAmount =
          (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      if ((remoteAmount - localAmount).abs() > 0.001) return false;

      if (data['uploadedAt'] == null) return false;

      return true;
    } on FirebaseException catch (e) {
      syncBus.debug(SyncPhase.verifyWrite,
          'استثناء أثناء التحقق من المعاملة: ${e.code} - ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// تحديث last_verified_at في SQLite (إن وُجد العمود)
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> _markCustomerVerified(int id) async {
    try {
      final db = await _db.database;
      final cols = await db.rawQuery('PRAGMA table_info(customers)');
      final hasCol = cols.any((c) => c['name'] == 'last_verified_at');
      if (!hasCol) return;
      await db.update(
        'customers',
        {'last_verified_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> _markTransactionVerified(int id) async {
    try {
      final db = await _db.database;
      final cols = await db.rawQuery('PRAGMA table_info(transactions)');
      final hasCol = cols.any((c) => c['name'] == 'verified_at');
      if (!hasCol) return;
      await db.update(
        'transactions',
        {'verified_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }
}
