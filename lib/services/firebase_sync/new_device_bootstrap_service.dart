// lib/services/firebase_sync/new_device_bootstrap_service.dart
// خدمة مزامنة الجهاز الجديد: طلب مطابقة من الأجهزة الأخرى
// يحل مشكلة: الجهاز الجديد لا يملك البيانات التاريخية التي حُذفت من Firebase

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_sync_config.dart';

// ─── حالة طلب المطابقة ──────────────────────────────────────────────────────
enum BootstrapStatus {
  idle,          // لا يوجد طلب نشط
  requesting,    // جاري إرسال الطلب
  waiting,       // بانتظار رد جهاز آخر
  uploading,     // جهاز آخر يرفع البيانات الناقصة
  downloading,   // هذا الجهاز ينزل البيانات
  completed,     // اكتملت المزامنة
  failed,        // فشل
}

// ─── نتيجة المطابقة ──────────────────────────────────────────────────────────
class BootstrapResult {
  final bool success;
  final String message;
  final int downloadedTransactions;
  final int downloadedCustomers;
  final int downloadedInvoices;

  BootstrapResult({
    required this.success,
    required this.message,
    this.downloadedTransactions = 0,
    this.downloadedCustomers = 0,
    this.downloadedInvoices = 0,
  });
}

/// خدمة مزامنة الجهاز الجديد عبر نظام "طلب المطابقة"
class NewDeviceBootstrapService {
  static final NewDeviceBootstrapService _instance =
      NewDeviceBootstrapService._internal();
  factory NewDeviceBootstrapService() => _instance;
  NewDeviceBootstrapService._internal();

  FirebaseFirestore? _firestore;

  BootstrapStatus _status = BootstrapStatus.idle;
  BootstrapStatus get status => _status;

  StreamSubscription? _requestListener;
  StreamSubscription? _responseListener;
  StreamController<BootstrapStatus>? _statusController;

  Stream<BootstrapStatus> get statusStream =>
      _statusController?.stream ?? const Stream.empty();

  // ═══════════════════════════════════════════════════════════════════════
  // 1. الجهاز الجديد: إرسال طلب مطابقة
  // ═══════════════════════════════════════════════════════════════════════

  /// يُستدعى عند اكتشاف أن هذا جهاز جديد أو ينقصه بيانات كثيرة
  Future<BootstrapResult> requestBootstrap({
    required int localTransactionCount,
    required int localCustomerCount,
    required int localInvoiceCount,
  }) async {
    _firestore ??= FirebaseFirestore.instance;
    _statusController ??= StreamController<BootstrapStatus>.broadcast();

    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    final deviceId = await FirebaseSyncConfig.getDeviceId();
    final groupSecret = await FirebaseSyncConfig.getGroupSecret();

    if (groupId == null || deviceId == null || groupSecret == null) {
      return BootstrapResult(success: false, message: 'الجهاز غير مُعد');
    }

    _updateStatus(BootstrapStatus.requesting);
    print('🆕 [Bootstrap] جهاز جديد يطلب مطابقة البيانات...');

    try {
      // 1. نشر طلب المطابقة في Firebase
      await _firestore!
          .collection('bootstrap_requests')
          .doc(deviceId)
          .set({
        'requestedBy': deviceId,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'localStats': {
          'transactions': localTransactionCount,
          'customers': localCustomerCount,
          'invoices': localInvoiceCount,
        },
        'groupSecret': groupSecret,
      });

      // 2. تحديث الجهاز كجهاز جديد
      await _firestore!
          .collection('devices')
          .doc(deviceId)
          .set({
        'isNewDevice': true,
        'bootstrapRequestedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _updateStatus(BootstrapStatus.waiting);
      print('⏳ [Bootstrap] بانتظار رد أجهزة المجموعة...');

      // 3. الاستماع لتغيير حالة الطلب (جهاز آخر يستجيب)
      final result = await _waitForBootstrapCompletion(
        groupId: groupId,
        deviceId: deviceId,
        groupSecret: groupSecret,
      );

      return result;
    } catch (e) {
      _updateStatus(BootstrapStatus.failed);
      print('❌ [Bootstrap] فشل طلب المطابقة: $e');
      return BootstrapResult(success: false, message: 'فشل: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. جهاز موجود: معالجة طلب المطابقة والرد عليه
  // ═══════════════════════════════════════════════════════════════════════

  /// يُشغَّل على الأجهزة الموجودة لمراقبة طلبات المطابقة
  Future<void> startListeningForBootstrapRequests({
    required Future<void> Function(String requestingDeviceId, Map<String, dynamic> stats)
        onRequestReceived,
  }) async {
    _firestore ??= FirebaseFirestore.instance;

    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    if (groupId == null) return;

    await _requestListener?.cancel();

    _requestListener = _firestore!
        .collection('bootstrap_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final requestingDeviceId = data['requestedBy'] as String?;
          final stats = (data['localStats'] as Map<dynamic, dynamic>?)
                  ?.cast<String, dynamic>() ??
              {};

          if (requestingDeviceId != null) {
            print('📩 [Bootstrap] طلب مطابقة من: $requestingDeviceId');
            await onRequestReceived(requestingDeviceId, stats);
          }
        }
      }
    }, onError: (e) {
      print('⚠️ [Bootstrap] خطأ في الاستماع للطلبات: $e');
    });
  }

  /// الجهاز الموجود يقوم برفع البيانات الناقصة للجهاز الجديد
  Future<bool> respondToBootstrapRequest({
    required String requestingDeviceId,
    required Future<List<Map<String, dynamic>>> Function() getTransactions,
    required Future<List<Map<String, dynamic>>> Function() getCustomers,
    required Future<List<Map<String, dynamic>>> Function() getInvoices,
    void Function(double progress, String message)? onProgress,
  }) async {
    _firestore ??= FirebaseFirestore.instance;

    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    final deviceId = await FirebaseSyncConfig.getDeviceId();
    final groupSecret = await FirebaseSyncConfig.getGroupSecret();

    if (groupId == null || deviceId == null || groupSecret == null) return false;

    try {
      // 1. تعليم الطلب كـ "جاري المعالجة"
      await _firestore!
          .collection('bootstrap_requests')
          .doc(requestingDeviceId)
          .update({
        'status': 'in_progress',
        'respondingDevice': deviceId,
        'respondingAt': FieldValue.serverTimestamp(),
      });

      onProgress?.call(0.05, 'جاري تحضير البيانات للجهاز الجديد...');

      // 2. رفع بيانات bootstrap في مجموعة مؤقتة خاصة بهذا الطلب
      final bootstrapRef = _firestore!
          .collection('bootstrap_data')
          .doc(requestingDeviceId);

      // رفع العملاء
      onProgress?.call(0.1, 'جاري رفع بيانات العملاء...');
      final customers = await getCustomers();
      int batchCount = 0;

      // رفع على شكل batch (500 مستند كحد أقصى لكل batch في Firestore)
      var batch = _firestore!.batch();

      for (int i = 0; i < customers.length; i++) {
        final cust = customers[i];
        final uuid = cust['sync_uuid'] as String? ?? 'cust_$i';
        final docRef = bootstrapRef.collection('customers').doc(uuid);
        cust['groupSecret'] = groupSecret;
        batch.set(docRef, cust);
        batchCount++;

        if (batchCount >= 400) {
          await batch.commit();
          batch = _firestore!.batch();
          batchCount = 0;
        }

        final pct = 0.1 + (i / customers.length) * 0.3;
        onProgress?.call(pct, 'رفع العملاء (${i + 1}/${customers.length})...');
      }

      if (batchCount > 0) {
        await batch.commit();
        batchCount = 0;
        batch = _firestore!.batch();
      }

      // رفع المعاملات
      onProgress?.call(0.4, 'جاري رفع بيانات المعاملات...');
      final transactions = await getTransactions();

      for (int i = 0; i < transactions.length; i++) {
        final tx = transactions[i];
        final uuid = tx['sync_uuid'] as String? ?? 'tx_$i';
        final docRef = bootstrapRef.collection('transactions').doc(uuid);
        tx['groupSecret'] = groupSecret;
        batch.set(docRef, tx);
        batchCount++;

        if (batchCount >= 400) {
          await batch.commit();
          batch = _firestore!.batch();
          batchCount = 0;
        }

        final pct = 0.4 + (i / transactions.length) * 0.4;
        onProgress?.call(pct, 'رفع المعاملات (${i + 1}/${transactions.length})...');
      }

      if (batchCount > 0) {
        await batch.commit();
        batchCount = 0;
        batch = _firestore!.batch();
      }

      // رفع الفواتير
      onProgress?.call(0.8, 'جاري رفع بيانات الفواتير...');
      final invoices = await getInvoices();

      for (int i = 0; i < invoices.length; i++) {
        final inv = invoices[i];
        final uuid = inv['invoice_uuid'] as String? ?? 'inv_$i';
        final docRef = bootstrapRef.collection('invoices').doc(uuid);
        inv['groupSecret'] = groupSecret;
        batch.set(docRef, inv);
        batchCount++;

        if (batchCount >= 400) {
          await batch.commit();
          batch = _firestore!.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) await batch.commit();

      // 3. تعليم الطلب كـ "جاهز للتنزيل"
      await _firestore!
          .collection('bootstrap_requests')
          .doc(requestingDeviceId)
          .update({
        'status': 'ready',
        'readyAt': FieldValue.serverTimestamp(),
        'stats': {
          'customers': customers.length,
          'transactions': transactions.length,
          'invoices': invoices.length,
        },
      });

      onProgress?.call(1.0, 'تم رفع البيانات! الجهاز الجديد يبدأ التنزيل...');
      print('✅ [Bootstrap] تم رفع البيانات للجهاز الجديد: $requestingDeviceId');
      return true;
    } catch (e) {
      print('❌ [Bootstrap] فشل الرد على طلب المطابقة: $e');
      await _firestore!
          .collection('bootstrap_requests')
          .doc(requestingDeviceId)
          .update({'status': 'failed', 'error': e.toString()});
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. الجهاز الجديد: انتظار والتنزيل
  // ═══════════════════════════════════════════════════════════════════════

  Future<BootstrapResult> _waitForBootstrapCompletion({
    required String groupId,
    required String deviceId,
    required String groupSecret,
  }) async {
    final completer = Completer<BootstrapResult>();

    // انتهاء المهلة بعد 10 دقائق
    final timeout = Timer(const Duration(minutes: 10), () {
      if (!completer.isCompleted) {
        _updateStatus(BootstrapStatus.failed);
        completer.complete(BootstrapResult(
          success: false,
          message: 'انتهت المهلة — لا يوجد جهاز آخر نشط للرد على طلب المطابقة',
        ));
      }
    });

    _responseListener?.cancel();
    _responseListener = _firestore!
        .collection('bootstrap_requests')
        .doc(deviceId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists || completer.isCompleted) return;

      final data = snapshot.data();
      final requestStatus = data?['status'] as String?;

      if (requestStatus == 'ready') {
        timeout.cancel();
        _updateStatus(BootstrapStatus.downloading);
        print('📥 [Bootstrap] البيانات جاهزة، جاري التنزيل...');

        final result = await _downloadBootstrapData(
          groupId: groupId,
          deviceId: deviceId,
          groupSecret: groupSecret,
        );

        completer.complete(result);
      } else if (requestStatus == 'failed') {
        timeout.cancel();
        _updateStatus(BootstrapStatus.failed);
        completer.complete(BootstrapResult(
          success: false,
          message: 'فشل الجهاز الآخر في رفع البيانات',
        ));
      } else if (requestStatus == 'in_progress') {
        _updateStatus(BootstrapStatus.uploading);
        print('⬆️ [Bootstrap] جهاز آخر يرفع البيانات...');
      }
    }, onError: (e) {
      if (!completer.isCompleted) {
        timeout.cancel();
        _updateStatus(BootstrapStatus.failed);
        completer.complete(BootstrapResult(
          success: false,
          message: 'خطأ في الاستماع: $e',
        ));
      }
    });

    return completer.future;
  }

  Future<BootstrapResult> _downloadBootstrapData({
    required String groupId,
    required String deviceId,
    required String groupSecret,
  }) async {
    int dlTx = 0;
    int dlCust = 0;
    int dlInv = 0;

    try {
      final bootstrapRef = _firestore!
          .collection('bootstrap_data')
          .doc(deviceId);

      // تنزيل عبر snapshot listener في firebase_sync_service يتم تلقائياً
      // هنا نتحقق فقط من الإحصاءات المُبلَّغة
      final requestDoc = await _firestore!
          .collection('bootstrap_requests')
          .doc(deviceId)
          .get();

      final stats =
          (requestDoc.data()?['stats'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? {};

      dlCust = (stats['customers'] as num?)?.toInt() ?? 0;
      dlTx = (stats['transactions'] as num?)?.toInt() ?? 0;
      dlInv = (stats['invoices'] as num?)?.toInt() ?? 0;

      // تعليم الجهاز كـ "اكتملت مزامنته" (إزالة isNewDevice)
      await _firestore!
          .collection('devices')
          .doc(deviceId)
          .update({
        'isNewDevice': false,
        'bootstrapCompletedAt': FieldValue.serverTimestamp(),
      });

      // تنظيف bootstrap_data بعد التنزيل (بعد 5 دقائق)
      Future.delayed(const Duration(minutes: 5), () async {
        try {
          await _cleanupBootstrapData(groupId, deviceId, bootstrapRef);
        } catch (_) {}
      });

      // حذف طلب المطابقة
      await _firestore!
          .collection('bootstrap_requests')
          .doc(deviceId)
          .delete();

      _updateStatus(BootstrapStatus.completed);
      print('✅ [Bootstrap] اكتملت المزامنة: عملاء=$dlCust، معاملات=$dlTx، فواتير=$dlInv');

      return BootstrapResult(
        success: true,
        message: 'اكتملت المزامنة بنجاح',
        downloadedTransactions: dlTx,
        downloadedCustomers: dlCust,
        downloadedInvoices: dlInv,
      );
    } catch (e) {
      _updateStatus(BootstrapStatus.failed);
      print('❌ [Bootstrap] فشل التنزيل: $e');
      return BootstrapResult(success: false, message: 'فشل التنزيل: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // تنظيف بيانات bootstrap بعد الانتهاء
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _cleanupBootstrapData(
    String groupId,
    String deviceId,
    DocumentReference bootstrapRef,
  ) async {
    for (final sub in ['customers', 'transactions', 'invoices']) {
      final snap = await bootstrapRef.collection(sub).limit(500).get();
      final batch = _firestore!.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      if (snap.docs.isNotEmpty) await batch.commit();
    }
    await bootstrapRef.delete();
    print('🧹 [Bootstrap] تم تنظيف بيانات bootstrap للجهاز: $deviceId');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // التحقق: هل هذا جهاز جديد؟
  // ═══════════════════════════════════════════════════════════════════════

  Future<bool> isNewDevice() async {
    _firestore ??= FirebaseFirestore.instance;

    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    final deviceId = await FirebaseSyncConfig.getDeviceId();
    if (groupId == null || deviceId == null) return false;

    try {
      final doc = await _firestore!
          .collection('devices')
          .doc(deviceId)
          .get();

      if (!doc.exists) return true; // لم يُسجَّل بعد → جهاز جديد
      return doc.data()?['isNewDevice'] == true;
    } catch (_) {
      return false;
    }
  }

  /// إحصاء عدد الأجهزة النشطة الأخرى (للتحقق هل هناك من يمكنه الرد)
  Future<int> countAvailableDevices() async {
    _firestore ??= FirebaseFirestore.instance;

    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    final deviceId = await FirebaseSyncConfig.getDeviceId();
    if (groupId == null) return 0;

    try {
      final snap = await _firestore!
          .collection('devices')
          .get();

      final now = DateTime.now();
      int count = 0;

      for (final doc in snap.docs) {
        if (doc.id == deviceId) continue; // لا نحسب نفسنا

        final data = doc.data();
        final lastSeen = data['lastSeen'];
        DateTime? lastSeenDate;

        if (lastSeen is Timestamp) {
          lastSeenDate = lastSeen.toDate();
        } else if (lastSeen is String) {
          lastSeenDate = DateTime.tryParse(lastSeen);
        }

        // جهاز نشط خلال آخر 90 يوم
        if (lastSeenDate != null && now.difference(lastSeenDate).inDays <= 90) {
          count++;
        }
      }

      return count;
    } catch (_) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // مساعدات
  // ═══════════════════════════════════════════════════════════════════════

  void _updateStatus(BootstrapStatus newStatus) {
    _status = newStatus;
    _statusController?.add(newStatus);
  }

  void dispose() {
    _requestListener?.cancel();
    _responseListener?.cancel();
    _statusController?.close();
  }
}
