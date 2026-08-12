// lib/services/firebase_sync/sync_watchdog.dart
// 🔒 نظام مراقبة المزامنة الاحتياطي (Safety Net)
// يعمل بالتوازي مع النظام الرئيسي لضمان عدم فقدان أي عملية

import 'dart:async';
import '../database_service.dart';
import 'firebase_sync_helper.dart';
import 'firebase_sync_coordinator.dart';
import 'firebase_sync_service.dart'; // 🛡️ للتحقق من حالة الإصلاح

/// 🛡️ SyncWatchdog - نظام المراقبة الاحتياطي
/// 
/// المهمة: مراقبة قاعدة البيانات والتأكد من رفع جميع العملاء والمعاملات
/// الضمانات:
/// - ✅ لا يُعدّل جدول customers
/// - ✅ لا يُعدّل جدول transactions  
/// - ✅ لا يُضيف/يحذف أي عميل أو معاملة
/// - ✅ للقراءة فقط من الجداول الرئيسية
/// - ✅ الكتابة فقط في sync_coordination
class SyncWatchdog {
  static SyncWatchdog? _instance;
  static SyncWatchdog get instance => _instance ??= SyncWatchdog._();
  
  SyncWatchdog._();
  
  final DatabaseService _db = DatabaseService();
  FirebaseSyncHelper? _syncHelper;
  FirebaseSyncCoordinator? _coordinator;
  
  Timer? _watchdogTimer;
  bool _isRunning = false;
  bool _isProcessing = false;
  bool _isPaused = false; // 🔒 إيقاف مؤقت أثناء الرفع الشامل
  
  // إحصائيات
  int _customersSynced = 0;
  int _transactionsSynced = 0;
  int _lastRunErrors = 0;
  DateTime? _lastRunTime;
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// التهيئة والتشغيل
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تهيئة نظام المراقبة
  Future<void> initialize({
    required FirebaseSyncHelper syncHelper,
    required FirebaseSyncCoordinator coordinator,
  }) async {
    _syncHelper = syncHelper;
    _coordinator = coordinator;
    print('🛡️ SyncWatchdog: تم التهيئة');
  }
  
  /// 🛡️ التحقق مما إذا كانت عملية الإصلاح جارية
  bool _isRepairingInProgress() {
    final syncService = FirebaseSyncService();
    return syncService.isRepairing;
  }
  
  /// بدء المراقبة الدورية
  void start({Duration interval = const Duration(seconds: 30)}) {
    if (_isRunning) {
      print('🛡️ SyncWatchdog: المراقبة تعمل بالفعل');
      return;
    }
    
    _isRunning = true;
    print('🛡️ SyncWatchdog: بدء المراقبة (كل ${interval.inSeconds} ثانية)');
    
    // تشغيل فوري عند البدء
    _runWatchdogCycle();
    
    // تشغيل دوري
    _watchdogTimer = Timer.periodic(interval, (_) {
      _runWatchdogCycle();
    });
  }
  
  /// إيقاف المراقبة
  void stop() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _isRunning = false;
    print('🛡️ SyncWatchdog: تم إيقاف المراقبة');
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// دورة المراقبة الرئيسية
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// 🔒 إيقاف مؤقت (يُستخدم أثناء الرفع الشامل)
  void pause() {
    _isPaused = true;
    print('🛡️ SyncWatchdog: ⏸️ تم الإيقاف المؤقت');
  }
  
  /// 🔒 استئناف بعد الإيقاف المؤقت
  void resume() {
    _isPaused = false;
    print('🛡️ SyncWatchdog: ▶️ تم الاستئناف');
  }
  
  Future<void> _runWatchdogCycle() async {
    if (_isPaused) {
      return; // لا نطبع شيء لتجنب السبام أثناء الرفع الشامل
    }

    // 🛡️ توقف تام أثناء الرفع الشامل/الطوارئ لمنع «عاصفة الرفع»:
    // نفس المعاملة تُرفع من _syncPendingChanges والـ Watchdog والـ Tracker
    // دفعة واحدة. القفل يضمن أن Watchdog لا يلمس البيانات أثناء المزامنة الكبيرة.
    if (FirebaseSyncService().isBulkUploading) {
      return;
    }

    if (_isProcessing) {
      return; // دورة سابقة قيد التنفيذ
    }

    if (_syncHelper == null || _coordinator == null) {
      return;
    }

    _isProcessing = true;
    _lastRunErrors = 0;
    
    try {
      print('🛡️ SyncWatchdog: بدء دورة المراقبة...');
      
      // 1. مزامنة العملاء غير المرفوعين
      await _syncPendingCustomers();
      
      // 2. مزامنة المعاملات غير المرفوعة
      await _syncPendingTransactions();
      
      _lastRunTime = DateTime.now();
      
      if (_customersSynced > 0 || _transactionsSynced > 0) {
        print('🛡️ SyncWatchdog: ✅ تم رفع $_customersSynced عميل و $_transactionsSynced معاملة');
      }
      
    } catch (e) {
      print('🛡️ SyncWatchdog: ❌ خطأ في دورة المراقبة: $e');
      _lastRunErrors++;
    } finally {
      _isProcessing = false;
      _customersSynced = 0;
      _transactionsSynced = 0;
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// مزامنة العملاء
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// 🔍 البحث عن العملاء الذين لم يُرفعوا ورفعهم
  Future<void> _syncPendingCustomers() async {
    final db = await _db.database;
    
    try {
      // 🔒 قراءة فقط: جلب العملاء الذين لهم sync_uuid ولكن ليسوا في sync_coordination
      final pendingCustomers = await db.rawQuery('''
        SELECT c.* FROM customers c
        LEFT JOIN sync_coordination sc 
          ON sc.entity_type = 'customer' AND sc.sync_uuid = c.sync_uuid
        WHERE c.sync_uuid IS NOT NULL 
          AND c.sync_uuid != ''
          AND (sc.id IS NULL OR sc.firebase_synced = 0 OR sc.firebase_synced IS NULL)
          AND (c.is_deleted IS NULL OR c.is_deleted = 0)
        LIMIT 5
      ''');
      
      if (pendingCustomers.isEmpty) return;
      
      print('🛡️ SyncWatchdog: وجد ${pendingCustomers.length} عميل غير مرفوع');
      
      for (final customerData in pendingCustomers) {
        // 🛡️ فحص إذا كانت عملية إصلاح أو رفع شامل جارية
        if (_isRepairingInProgress() || FirebaseSyncService().isBulkUploading) {
          return;
        }

        try {
          // 🔥 رفع إلى Firebase. uploadCustomer يتكفل بالتسجيل في المنسق داخليًا.
          await _syncHelper!.syncCustomer(customerData);
          _customersSynced++;
        } catch (e) {
          _lastRunErrors++;
        }
      }
    } catch (e) {
      print('🛡️ SyncWatchdog: خطأ في جلب العملاء: $e');
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// مزامنة المعاملات
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// 🔍 البحث عن المعاملات التي لم تُرفع ورفعها
  Future<void> _syncPendingTransactions() async {
    final db = await _db.database;
    
    try {
      // 🔒 قراءة فقط: جلب المعاملات التي لها sync_uuid ولكن ليست في sync_coordination.
      // 🔒 إضافة is_uploaded = 0 (لم تُرفع فعليًا) و is_created_by_me = 1 (من هذا الجهاز).
      // بدون is_uploaded كان Watchdog يعيد رفع معاملات رُفعت بالفعل لأن المنسق قد
      // يكون متأخرًا. وبدون is_created_by_me كان يحاول رفع معاملات جاءت من أجهزة
      // أخرى، فيرفضها uploadTransaction داخليًا ويعيدها كنجاح كاذب.
      final pendingTransactions = await db.rawQuery('''
        SELECT t.*, c.sync_uuid as customer_sync_uuid
        FROM transactions t
        INNER JOIN customers c ON t.customer_id = c.id
        LEFT JOIN sync_coordination sc
          ON sc.entity_type = 'transaction' AND sc.sync_uuid = t.transaction_uuid
        WHERE t.transaction_uuid IS NOT NULL
          AND t.transaction_uuid != ''
          AND c.sync_uuid IS NOT NULL
          AND (t.is_uploaded = 0 OR t.is_uploaded IS NULL)
          AND (t.is_created_by_me = 1 OR t.is_created_by_me IS NULL)
          AND (sc.id IS NULL OR sc.firebase_synced = 0 OR sc.firebase_synced IS NULL)
        LIMIT 10
      ''');
      
      if (pendingTransactions.isEmpty) return;
      
      print('🛡️ SyncWatchdog: وجد ${pendingTransactions.length} معاملة غير مرفوعة');
      
      for (final txData in pendingTransactions) {
        try {
          final syncUuid = txData['transaction_uuid'] as String;
          final customerSyncUuid = txData['customer_sync_uuid'] as String?;

          if (customerSyncUuid == null || customerSyncUuid.isEmpty) {
            continue;
          }

          // 🔥 رفع إلى Firebase. uploadTransaction يتكفل داخليًا بكل شيء:
          // التسجيل في المنسق، تحديث is_uploaded=1، الـ WAL. لذلك لا نكررها هنا
          // (التكرار كان يسبب تضاربًا وتسجيلات مزدوجة في sync_coordination).
          await _syncHelper!.syncTransaction(
            Map<String, dynamic>.from(txData),
            customerSyncUuid,
          );

          _transactionsSynced++;
        } catch (e) {
          _lastRunErrors++;
        }
      }
    } catch (e) {
      print('🛡️ SyncWatchdog: خطأ في جلب المعاملات: $e');
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// تشغيل يدوي (للاختبار أو عند الطلب)
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تشغيل دورة مراقبة يدوية
  Future<Map<String, dynamic>> runManualSync() async {
    final startTime = DateTime.now();
    _customersSynced = 0;
    _transactionsSynced = 0;
    
    await _runWatchdogCycle();
    
    return {
      'success': _lastRunErrors == 0,
      'customers_synced': _customersSynced,
      'transactions_synced': _transactionsSynced,
      'errors': _lastRunErrors,
      'duration_ms': DateTime.now().difference(startTime).inMilliseconds,
    };
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// إحصائيات
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// الحصول على إحصائيات نظام المراقبة
  Map<String, dynamic> getStats() {
    return {
      'is_running': _isRunning,
      'is_processing': _isProcessing,
      'last_run_time': _lastRunTime?.toIso8601String(),
      'total_customers_synced': _customersSynced,
      'total_transactions_synced': _transactionsSynced,
      'last_run_errors': _lastRunErrors,
    };
  }
  
  /// الحصول على عدد العناصر المعلقة
  Future<Map<String, int>> getPendingCounts() async {
    final db = await _db.database;
    
    try {
      final customerCount = await db.rawQuery('''
        SELECT COUNT(*) as count FROM customers c
        LEFT JOIN sync_coordination sc 
          ON sc.entity_type = 'customer' AND sc.sync_uuid = c.sync_uuid
        WHERE c.sync_uuid IS NOT NULL 
          AND c.sync_uuid != ''
          AND (sc.id IS NULL OR sc.firebase_synced = 0 OR sc.firebase_synced IS NULL)
          AND (c.is_deleted IS NULL OR c.is_deleted = 0)
      ''');
      
      final transactionCount = await db.rawQuery('''
        SELECT COUNT(*) as count FROM transactions t
        INNER JOIN customers c ON t.customer_id = c.id
        LEFT JOIN sync_coordination sc 
          ON sc.entity_type = 'transaction' AND sc.sync_uuid = t.transaction_uuid
        WHERE t.transaction_uuid IS NOT NULL 
          AND t.transaction_uuid != ''
          AND c.sync_uuid IS NOT NULL
          AND (sc.id IS NULL OR sc.firebase_synced = 0 OR sc.firebase_synced IS NULL)
      ''');
      
      return {
        'pending_customers': (customerCount.first['count'] as int?) ?? 0,
        'pending_transactions': (transactionCount.first['count'] as int?) ?? 0,
      };
    } catch (e) {
      print('🛡️ SyncWatchdog: خطأ في جلب العدد: $e');
      return {'pending_customers': -1, 'pending_transactions': -1};
    }
  }
}
