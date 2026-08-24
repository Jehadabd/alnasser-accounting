// lib/services/firebase_sync/firebase_sync_service.dart
// خدمة المزامنة الفورية عبر Firebase - Offline-First
// مع قيود صارمة لحل التعارضات ومنع التكرار

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:firebase_auth/firebase_auth.dart' as fauth; // 🔐 Firebase Auth

import '../database_service.dart';
import '../database/core/database_helpers.dart';
import 'firebase_sync_config.dart';
import 'firebase_sync_coordinator.dart';
import 'firebase_auth_service.dart';
import 'sync_operation_tracker.dart';
import 'transaction_ack_service.dart';
import 'sync_crash_recovery_service.dart'; // 🛡️ WAL للحماية من الانقطاع
import 'sync_watchdog.dart'; // 🛡️ نظام المراقبة الاحتياطي
import 'firebase_sync_helper.dart'; // Helper for Watchdog initialization
import 'invoice_sync_service.dart'; // 🧾 مزامنة الفواتير
import 'product_sync_service.dart'; // 📦 مزامنة المنتجات
import 'reconciliation_service.dart'; // 🧮 المطابقة بين الأجهزة
import 'armored_reconciliation_service.dart'; // 🛡️ المطابقة المحصّنة مغلقة الحلقة
import 'live_match_service.dart'; // 📡 مطابقة حية جهاز↔جهاز
import 'smart_pipe_cleanup_service.dart'; // 🧹 الحذف الذكي بشرط قراءة الجميع
import 'match_verdict_service.dart'; // ⚖️ بثّ قرارات المطابقة للمجموعة
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import '../sync/sync_validation.dart';
import '../sync/sync_security.dart';
import '../../models/transaction.dart'; // Import DebtTransaction model
import '../../utils/uuid_helper.dart'; // للـ UUID الحتمي
import '../license_service.dart'; // 🔐 نظام التراخيص

/// حالة المزامنة
enum FirebaseSyncStatus {
  idle,           // في انتظار
  syncing,        // جاري المزامنة
  online,         // متصل ويستمع للتغييرات
  offline,        // غير متصل
  error,          // خطأ
  disabled,       // معطل
  notConfigured,  // غير مُعد
}

/// معلومات عملية مزامنة
class SyncOperation {
  final String type; // 'customer' أو 'transaction'
  final String action; // 'create', 'update', 'delete'
  final String syncUuid;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  SyncOperation({
    required this.type,
    required this.action,
    required this.syncUuid,
    required this.data,
    required this.timestamp,
  });
  
  Map<String, dynamic> toMap() => {
    'type': type,
    'action': action,
    'syncUuid': syncUuid,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نتيجة التحقق من التعارض
/// ═══════════════════════════════════════════════════════════════════════════
enum ConflictResolution {
  useRemote,    // استخدام البيانات البعيدة (الأحدث)
  useLocal,     // استخدام البيانات المحلية
  merge,        // دمج البيانات
  skip,         // تخطي (البيانات متطابقة)
}

class ConflictResult {
  final ConflictResolution resolution;
  final String reason;
  final Map<String, dynamic>? mergedData;
  
  ConflictResult({
    required this.resolution,
    required this.reason,
    this.mergedData,
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة المزامنة الفورية عبر Firebase
/// ═══════════════════════════════════════════════════════════════════════════
class FirebaseSyncService {
  static final FirebaseSyncService _instance = FirebaseSyncService._internal();
  factory FirebaseSyncService() => _instance;
  FirebaseSyncService._internal();
  
  final DatabaseService _db = DatabaseService();
  FirebaseFirestore? _firestore;
  FirebaseSyncCoordinator? _coordinator;
  SyncOperationTracker? _operationTracker;
  TransactionAckService? _ackService;
  final MatchVerdictService _verdictService = MatchVerdictService(); // ⚖️
  SyncCrashRecoveryService? _crashRecovery; // 🛡️ WAL للحماية من الانقطاع
  SyncWatchdog? _watchdog; // 🛡️ نظام المراقبة الاحتياطي
  
  // حالة الخدمة
  FirebaseSyncStatus _status = FirebaseSyncStatus.idle;
  String? _groupId;
  String? _deviceId;
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSyncing = false; // 🔒 قفل لمنع المزامنة المتزامنة
  bool _firestoreSettingsApplied = false; // 🔒 منع تكرار ضبط إعدادات Firestore
  
  // 🔒 تتبع العمليات الجارية (للحماية من race conditions)
  // استخدام Map بدلاً من Set لضمان atomic check-and-set
  final Map<String, bool> _uploadLocks = {};
  DateTime? _syncStartTime;
  
  // 🕰️ فرق التوقيت مع السيرفر (لتصحيح clock skew)
  Duration _serverTimeOffset = Duration.zero;
  
  /// الوقت الحالي مصححاً بتوقيت السيرفر
  DateTime get now => DateTime.now().add(_serverTimeOffset);
  
  // 🔄 Retry Queue مع Exponential Backoff
  Timer? _retryTimer;
  static const int _maxRetries = 999999; // 🔄 إعادة محاولات لا نهائي حتى نجاح الرفع
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  
  // 🧹 إعدادات التنظيف التلقائي
  // (أُلغي _keepFirebaseDataDays=7: التنظيف يتبع مدة المستخدم + فحص ACKs)
  static const int _maxFirebaseOperations = 10000; // 10,000 عملية كحد أقصى
  
  // 🔐 إعدادات الأمان
  String? _groupSecretKey; // مفتاح المجموعة للتوقيع
  String? _groupSecret; // 🔐 المفتاح السري للمجموعة (للتحقق في Firestore Rules)
  final SyncRateLimiter _rateLimiter = SyncRateLimiter(
    maxOperationsPerMinute: 120, // 🔧 تقليل الحد لتقليل الحمل على النظام
    maxOperationsPerHour: 1000,  // 🔧 تقليل الحد الساعي
  );
  
  // Listeners
  StreamSubscription<QuerySnapshot>? _customersListener;
  StreamSubscription<QuerySnapshot>? _transactionsListener;
  StreamSubscription<List<ConnectivityResult>>? _connectivityListener;
  
  //  Live Stats Cache - إحصائيات لحظية من Streams
  int _liveCustomersCount = 0;
  int _liveTransactionsCount = 0;
  int _liveInvoicesCount = 0;
  List<Map<String, dynamic>> _liveDevices = [];
  
  // 📊 Stats Listeners - مستمعات للإحصائيات اللحظية
  StreamSubscription<QuerySnapshot>? _devicesListener;
  
  // 📊 Stats Stream Controllers - لبث التحديثات للواجهة
  final _syncStatsController = StreamController<Map<String, dynamic>>.broadcast();
  final _devicesController = StreamController<List<Map<String, dynamic>>>.broadcast();
  
  /// 🔄 Stream للإحصائيات اللحظية
  Stream<Map<String, dynamic>> get liveStatsStream => _syncStatsController.stream;
  
  /// 🔄 Stream للأجهزة اللحظية
  Stream<List<Map<String, dynamic>>> get liveDevicesStream => _devicesController.stream;
  
  /// 📊 هل المستمعات اللحظية للإحصائيات والأجهزة فعالة؟
  bool get statsListenersActive =>
      _isListening && _customersListener != null && _transactionsListener != null;
  
  /// 📊 قائمة الأجهزة اللحظية المتوفرة حالياً (آخر تحديث من الـ Stream)
  List<Map<String, dynamic>> get liveDevices => _liveDevices;
  
  // 📱 مؤقت نبضة القلب للأجهزة (كل 30 ثانية للدقة)
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  
  // 🔄 مؤقت المزامنة الخلفية (كل 10 دقائق - تقليل الحمل)
  Timer? _backgroundSyncTimer;
  static const Duration _backgroundSyncInterval = Duration(minutes: 10);

  // 🛡️ مؤقت استقرار الاتصال (للتحقق المتبادل - 15 دقيقة)
  Timer? _stabilityTimer;
  bool _isVerificationScheduled = false;

  // 🔄 مؤقت إعادة محاولة التهيئة: إذا فشلت المصادقة أو اختبار الاتصال لحظة
  // فتح التطبيق (والجهاز متصل أصلاً)، لا يُطلق connectivity_plus أي حدث جديد،
  // فتبقى المزامنة ميتة بصمت حتى إعادة تشغيل التطبيق. هذا المؤقت يعيد
  // المحاولة كل 30 ثانية حتى تنجح التهيئة (مثلاً هاتف فُتح بعد يومين أوفلاين
  // ثم التقط الشبكة، لكن signInAnonymously فشل أول مرة).
  Timer? _initRetryTimer;
  static const Duration _initRetryInterval = Duration(seconds: 30);
  // هل آخر فشل تهيئة قابل للإعادة؟ (فشل مصادقة/اتصال = نعم، عدم ضبط/ترخيص = لا)
  bool _initFailureRetryable = false;
  
  // Callbacks
  final _statusController = StreamController<FirebaseSyncStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _syncEventController = StreamController<String>.broadcast();
  Stream<String> get syncEvents => _syncEventController.stream;
  
  // 🔄 إشعارات تحديث الواجهة الفوري
  final _transactionReceivedController = StreamController<Map<String, dynamic>>.broadcast();
  final _customerUpdatedController = StreamController<String>.broadcast(); // sync_uuid للعميل
  
  Stream<FirebaseSyncStatus> get statusStream => _statusController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<String> get syncEventStream => _syncEventController.stream;
  
  /// 🔄 Stream للإشعار عند استقبال معاملة جديدة من جهاز آخر
  Stream<Map<String, dynamic>> get onTransactionReceived => _transactionReceivedController.stream;
  
  /// 🔄 Stream للإشعار عند تحديث بيانات عميل
  Stream<String> get onCustomerUpdated => _customerUpdatedController.stream;
  
  FirebaseSyncStatus get status => _status;
  String? get groupId => _groupId;
  bool get isOnline => _status == FirebaseSyncStatus.online;
  bool get isEnabled => _isInitialized && _groupId != null;

  /// 🛡️ التحقق مما إذا كانت عملية الإصلاح جارية
  bool get isRepairing => _isRepairing;

  /// 🛡️ هل الرفع الشامل/الطوارئ جارٍ الآن؟ Watchdog وTracker يجب أن يتوقفا
  /// تمامًا أثناءه لمنع "عاصفة الرفع" (نفس المعاملة تُرفع من 3 مصادر دفعة واحدة).
  bool _isBulkUploading = false;
  bool get isBulkUploading => _isBulkUploading;

  /// اتصال Firestore الجاهز، لتستخدمه خدمة المطابقة بدل فتح اتصال ثانٍ.
  FirebaseFirestore? get firestore => _firestore;

  /// تطبيق وثيقة معاملة وردت من السحابة عبر نفس مسار الاستقبال المعتاد.
  /// خدمة المطابقة تستدعيها لجلب معاملة اكتُشف نقصها، فتمرّ بكل فحوص
  /// الاستقبال الإدمبوتنت بدل أن تُدرج بطريق جانبي.
  Future<void> applyRemoteTransaction(
      String syncUuid, Map<String, dynamic> data) async {
    await _applyTransactionChange(syncUuid, data);
  }

  /// تطبيق وثيقة عميل وردت من السحابة — نفس مسار الاستقبال المعتاد.
  Future<void> applyRemoteCustomer(
      String syncUuid, Map<String, dynamic> data) async {
    await _applyCustomerChange(syncUuid, data);
  }
  /// ═══════════════════════════════════════════════════════════════════════
  /// التهيئة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تهيئة خدمة المزامنة
  Future<bool> initialize({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (_isInitialized) {
      onProgress?.call(1.0, 'تم التهيئة مسبقاً');
      return true;
    }
    
    // 🔐 فحص حماية الترخيص: المزامنة غير مسموحة للـ debts_only و full_offline
    final license = LicenseService().getStoredLicense();
    if (license != null && !license.isSyncAllowed) {
      print('🔒 [FirebaseSyncService] المزامنة غير مشمولة في هذا الترخيص (${license.appMode}) - تم حظر محرك المزامنة.');
      _initFailureRetryable = false; // إعادة المحاولة بلا فائدة هنا
      _updateStatus(FirebaseSyncStatus.disabled);
      return false;
    }

    // 🌐 بدء مراقبة الاتصال مبكراً (حتى لو فشلت التهيئة)
    _startConnectivityMonitoring();
    
    try {
      // 🔐 التحقق من المصادقة أولاً
      onProgress?.call(0.05, 'جاري التحقق من المصادقة...');
      final authService = FirebaseAuthService();
      if (!authService.isAuthenticated) {
        print('⚠️ المستخدم غير مصادق عليه - جاري تسجيل الدخول...');
        try {
          final uid = await authService.signInAnonymously();
          if (uid == null) {
            print('❌ فشل تسجيل الدخول - لا يمكن المزامنة (ستتم إعادة المحاولة)');
            _updateStatus(FirebaseSyncStatus.offline);
            _errorController.add('فشل المصادقة المجهولة');
            _initFailureRetryable = true; // 🔄 فشل مؤقت غالباً - أعد المحاولة دورياً
            _scheduleInitRetry();
            return false;
          }
        } catch (authErr) {
          _updateStatus(FirebaseSyncStatus.error);
          _errorController.add('خطأ مصادقة: $authErr');
          _initFailureRetryable = true; // 🔄 فشل مؤقت غالباً - أعد المحاولة دورياً
          _scheduleInitRetry();
          return false;
        }
      }
      print('✅ المصادقة ناجحة: ${authService.uid}');
      
      // التحقق من الإعدادات
      onProgress?.call(0.1, 'جاري التحقق من الإعدادات...');
      final isConfigured = await FirebaseSyncConfig.isConfigured();
      final isEnabled = await FirebaseSyncConfig.isEnabled();
      
      if (!isConfigured || !isEnabled) {
        _initFailureRetryable = false; // الإعدادات لن تتغير وحدها - لا إعادة محاولة
        _updateStatus(FirebaseSyncStatus.notConfigured);
        return false;
      }
      
      // الحصول على الإعدادات
      _groupId = await FirebaseSyncConfig.getSyncGroupId();
      _deviceId = await FirebaseSyncConfig.getDeviceId();

      // بادئة الجهاز داخل المعرّفات الجديدة: تجعل التصادم بين جهازين مستحيلاً
      // حتى قبل الاعتماد على العشوائية.
      if (_deviceId != null) UuidHelper.configureDevice(_deviceId!);
      
      // تهيئة Firestore
      _firestore = FirebaseFirestore.instance;

      // ضبط إعدادات Firestore — مرة واحدة فقط.
      // 🔒 persistenceEnabled معطّلة على Windows/desktop: على هذه المنصات كانت
      // تسبب TimeoutException دائم في كل كتابة (.set/.update) لأن Firestore
      // يكتفي بالكتابة المحلية وينتظر تأكيد السيرفر الذي لا يصل. على mobile
      // فقط نفعّلها (هي مفيدة هناك لعمل offline فعلي). هذا كان السبب الجذري
      // لفشل كل عمليات الرفع بـ TimeoutException.
      if (!_firestoreSettingsApplied) {
        try {
          final isDesktop = !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.windows ||
               defaultTargetPlatform == TargetPlatform.linux ||
               defaultTargetPlatform == TargetPlatform.macOS);

          // 🔒 على Desktop نعطّل persistence لأنها كانت تقتل كل كتابة بـ
          // TimeoutException. على Mobile/Web نفعّلها لدعم الـ offline.
          _firestore!.settings = Settings(
            persistenceEnabled: !isDesktop,
            cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          );
          _firestoreSettingsApplied = true;
          print('⚙️ إعدادات Firestore: persistenceEnabled=${!isDesktop} '
              '(${isDesktop ? "Desktop — معطّلة لحل تعليق الكتابة" : "Mobile/Web — مفعّلة لدعم offline"})');
        } catch (e) {
          print('⚠️ تعذّر ضبط إعدادات Firestore (قد تكون مُطبّقة): $e');
        }
      }
      
      // 🚀 اختبار الاتصال الفعلي وإنشاء المجلدات الأساسية قبل إكمال التهيئة
      final testPassed = await _testFirebaseConnectivity();
      if (!testPassed) {
        _updateStatus(FirebaseSyncStatus.error);
        _errorController.add('فشل الاتصال بـ Firebase أو تعذر إنشاء المجلدات.');
        _initFailureRetryable = true; // 🔄 قد يكون انقطاعاً مؤقتاً - أعد المحاولة دورياً
        _scheduleInitRetry();
        return false;
      }
      
      // 🔒 تهيئة منسق المزامنة (إذا لم يكن مُهيأ)
      if (_coordinator == null) {
        _coordinator = FirebaseSyncCoordinator();
        await _coordinator!.initialize();
      }
      
      // 🔄 تهيئة نظام تتبع العمليات (إذا لم يكن مُهيأ)
      if (_operationTracker == null) {
        _operationTracker = SyncOperationTracker();
        await _operationTracker!.initialize(
          firestore: _firestore!,
          groupId: _groupId!,
          deviceId: _deviceId!,
          groupSecret: _groupSecret,
        );
      }
      
      // 📬 تهيئة خدمة تأكيد الاستلام (إذا لم تكن مُهيأة)
      if (_ackService == null) {
        _ackService = TransactionAckService.instance;
        await _ackService!.initialize(
          firestore: _firestore!,
          deviceId: _deviceId!,
          groupId: _groupId!,
          deviceName: await _getDeviceName(),
        );
      }

      // ⚖️ تشغيل مستمع قرارات المطابقة (انتشار إصلاح المطابقة لكل الأجهزة)
      try {
        await _verdictService.start();
      } catch (e) {
        print('⚠️ تعذّر تشغيل مستمع قرارات المطابقة: $e');
      }
      
      // 🛡️ تهيئة خدمة الحماية من الانقطاع (WAL)
      if (_crashRecovery == null) {
        _crashRecovery = SyncCrashRecoveryService.instance;
        await _crashRecovery!.initialize();
        print('✅ تم تهيئة نظام الحماية من الانقطاع (WAL)');
        print('✅ تم تهيئة نظام الحماية من الانقطاع (WAL)');
      }
      
      // 🛡️ تهيئة وتشغيل نظام المراقبة الاحتياطي (Safety Net)
      if (_watchdog == null) {
        _watchdog = SyncWatchdog.instance;
        await _watchdog!.initialize(
          syncHelper: FirebaseSyncHelper(),
          coordinator: _coordinator!,
        );
        _watchdog!.start(); // بدء المراقبة
        print('🛡️ تم تشغيل نظام المراقبة الاحتياطي');
      }
      
      // 🔐 تهيئة مفتاح المجموعة للتشفير والتوقيع
      _groupSecretKey = await SyncSecurity.getOrCreateSecretKey();
      print('🔐 تم تحميل المفتاح للتشفير');
      
      // 🔐 تهيئة المفتاح السري للمجموعة (للتحقق في Firestore Rules)
      _groupSecret = await SyncSecurity.getOrCreateSecretKey();
      print('🔐 تم تحميل المفتاح السري للمشروع');
      
      // 🔒 تهيئة جدول الأيتام (Orphan Transactions)
      try {
        await _createOrphanTable().timeout(const Duration(seconds: 60));
      } catch (e) {
        print('⚠️ خطأ/تأخير في تهيئة جدول الأيتام: $e');
      }

      // 🕰️ حساب فرق التوقيت مع السيرفر
      try {
        await _calculateServerTimeOffset().timeout(const Duration(seconds: 60));
      } catch (e) {
        print('⚠️ خطأ/تأخير في حساب وقت السيرفر (تخطي): $e');
      }

      // بدء الاستماع للتغييرات
      onProgress?.call(0.6, 'جاري بدء الاستماع للتغييرات...');
      try {
        await _startListening().timeout(const Duration(seconds: 60));
      } catch (e) {
        print('⚠️ خطأ/تأخير في بدء الاستماع (تخطي): $e');
      }
      
      // ═══ ترتيب الإقلاع (كما هو مطلوب): ═══
      // 1) المصادقة + فحص الاتصال (تم أعلاه)
      // 2) رفع كل المعلق محلياً أولاً: معاملات، ثم فواتير، ثم منتجات
      // 3) ثم السحب الكامل من Firebase لالتقاط آخر التغييرات

      // مزامنة البيانات المعلقة عند الإقلاع.
      // 🔒 ننتظرها بمهلة 90 ثانية بدل fire-and-forget تماماً: لو فُتح التطبيق
      // قصيراً ثم أُغلق (سيناريو الهاتف بعد يومين أوفلاين)، كان الرفع الخلفي
      // يُقتل مع إغلاق التطبيق ولا يُرفع شيء حتى فتحٍ لاحق. بانتظارها حتى 90
      // ثانية تُرفع معظم الحِمل (10 معاملات أو أكثر) قبل اكتمال التهيئة.
      // إن انتهت المهلة يستمر الرفع في الخلفية (المؤقت لا يلغي المستقبل)،
      // ويلتقط الـ Watchdog أي متبقٍّ لاحقاً.
      onProgress?.call(0.7, 'جاري رفع المعاملات المعلقة...');
      try {
        await _syncPendingChanges().timeout(
          const Duration(seconds: 90),
          onTimeout: () => print('⏳ استمرار التهيئة - رفع المعلق ما زال جارياً في الخلفية'),
        );
      } catch (e) {
        print('⚠️ خطأ في المزامنة الخلفية الأولية: $e');
      }

      // 🧾 محرك الفواتير: يجب أن يبدأ قبل السحب الكامل حتى تُرفع الفواتير
      // المعلقة محلياً أولاً (رفع + استماع للوارد + مؤقتات إعادة المحاولة).
      try {
        await InvoiceSyncService().startSync();
      } catch (e) {
        print('⚠️ تعذّر بدء مزامنة الفواتير: $e');
      }

      // 📦 محرك المنتجات: رفع المعلق + تنزيل الكتالوج + الاستماع الحي —
      // قبل السحب الكامل بنفس المنطق.
      try {
        await ProductSyncService().startSync();
        print('📦 تم تشغيل محرك مزامنة المنتجات بنجاح');
      } catch (e) {
        print('⚠️ تعذّر بدء مزامنة المنتجات: $e');
      }

      // 🔄 سحب كامل إدمبوتنت بعد رفع كل المعلق (معاملات + فواتير + منتجات):
      // يضمن وصول كل ما فات هذا الجهاز أثناء إيقافه مهما كان سبب فواته من
      // المستمعين اللحظيين.
      try {
        await performFullCatchUp().timeout(
          const Duration(seconds: 120),
          onTimeout: () => print('⏳ استمرار التهيئة - السحب الكامل ما زال جارياً في الخلفية'),
        );
      } catch (e) {
        print('⚠️ خطأ في السحب الكامل عند التشغيل: $e');
      }
      
      // 🔐 تحميل Retry Queue من قاعدة البيانات
      try {
        await _loadRetryQueue().timeout(const Duration(seconds: 60));
      } catch (e) {
        print('⚠️ خطأ/تأخير في تحميل طابور إعادة المحاولة: $e');
      }

      // 📱 تسجيل هذا الجهاز في المجموعة
      try {
        await registerDevice().timeout(const Duration(seconds: 60));
      } catch (e) {
        print('⚠️ خطأ/تأخير في تسجيل الجهاز بالسحابة: $e');
      }
      
      // 📱 بدء مؤقت نبضة القلب
      _startHeartbeat();
      
      // 🔄 بدء المزامنة الخلفية الدورية
      _startBackgroundSync();

      onProgress?.call(0.95, 'اكتملت التهيئة');
      _isInitialized = true;
      _initFailureRetryable = false;
      _initRetryTimer?.cancel(); // ✅ نجحت التهيئة - لا حاجة لإعادة المحاولة
      _initRetryTimer = null;
      _updateStatus(FirebaseSyncStatus.online);

      // 🧮 الاستماع لطلبات المطابقة + التدقيق التلقائي عند سكون النظام.
      try {
        ReconciliationService().startListening();
        ReconciliationService().startAutoAudit();
        // مطابقة حية بين الأجهزة: نستمع للدعوات حتى لو لم تُفتح الشاشة.
        LiveMatchService().start();
        // 🛡️ المطابقة المحصّنة: نستمع لطلبات فولدر المطابقة (data/requests/results)
        //    حتى يستجيب هذا الجهاز تلقائياً لطلبات المطابقة من الأجهزة الأخرى.
        ArmoredReconciliationService().startListening();
      } catch (e) {
        print('⚠️ تعذّر بدء خدمة المطابقة: $e');
      }
      
      
      print('✅ Firebase Sync initialized for group: $_groupId');
      onProgress?.call(1.0, 'تمت تهيئة المزامنة بنجاح');
      return true;
      
    } catch (e) {
      print('❌ Firebase Sync initialization failed: $e');
      _updateStatus(FirebaseSyncStatus.error);
      _errorController.add('فشل تهيئة المزامنة: $e');
      _initFailureRetryable = true; // 🔄 قد يكون فشلاً مؤقتاً (شبكة/اتصال)
      _scheduleInitRetry();
      return false;
    }
  }

  /// 🔄 جدولة إعادة محاولة التهيئة بعد فشل قابل للإعادة.
  /// يعيد المحاولة فقط عند توفر اتصال فعلي بالإنترنت، ويتوقف فور نجاح التهيئة.
  void _scheduleInitRetry() {
    if (_isInitialized || !_initFailureRetryable) return;
    _initRetryTimer?.cancel();
    _initRetryTimer = Timer(_initRetryInterval, () async {
      if (_isInitialized || !_initFailureRetryable) return;

      // لا تُهدر محاولات مصادقة/اتصال بلا إنترنت
      try {
        final results = await Connectivity().checkConnectivity();
        if (results.contains(ConnectivityResult.none)) {
          print('⏳ [InitRetry] لا يوجد اتصال - إعادة الجدولة...');
          _scheduleInitRetry();
          return;
        }
      } catch (e) {
        print('⚠️ [InitRetry] تعذر فحص الاتصال: $e');
      }

      print('🔄 [InitRetry] إعادة محاولة تهيئة المزامنة...');
      try {
        final ok = await initialize();
        if (!ok) {
          _scheduleInitRetry(); // فشلت مجدداً - أعد الجدولة
        }
      } catch (e) {
        print('❌ [InitRetry] استثناء أثناء إعادة المحاولة: $e');
        _scheduleInitRetry();
      }
    });
    print('⏱️ [InitRetry] ستتم إعادة محاولة التهيئة خلال ${_initRetryInterval.inSeconds} ثانية');
  }
  
  /// إيقاف الخدمة
  Future<void> dispose() async {
    await markDeviceOffline(); // تعليم الجهاز كغير متصل
    _stopHeartbeat();
    _stopBackgroundSync(); // 🔄 إيقاف المزامنة الخلفية
    _watchdog?.stop(); // 🛡️ إيقاف المراقبة
    await InvoiceSyncService().stopSync(); // 🧾 إيقاف مزامنة الفواتير
    ReconciliationService().dispose(); // 🧮 إيقاف خدمة المطابقة
    LiveMatchService().dispose(); // 📡 إيقاف المطابقة الحية
    await _stopListening();
    _connectivityListener?.cancel();
    _operationTracker?.dispose(); // 🔄 إيقاف تتبع العمليات
    _ackService?.dispose(); // 📬 إيقاف خدمة التأكيد
    _retryTimer?.cancel(); // 🔄 إيقاف مؤقت Retry
    _initRetryTimer?.cancel(); // 🔄 إيقاف مؤقت إعادة محاولة التهيئة
    _initRetryTimer = null;
    _statusController.close();
    _errorController.close();
    _syncEventController.close();
    _transactionReceivedController.close();
    _customerUpdatedController.close();
    _syncStatsController.close(); // 📊
    _devicesController.close(); // 📊
    _isInitialized = false;
  }
  /// ═══════════════════════════════════════════════════════════════════════
  /// مراقبة الاتصال
  /// ═══════════════════════════════════════════════════════════════════════
  
  void _startConnectivityMonitoring() {
    // تجنب تشغيل المراقبة مرتين
    if (_connectivityListener != null) return;
    
    _connectivityListener = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      
      if (hasConnection && (_status == FirebaseSyncStatus.offline || _status == FirebaseSyncStatus.error || !_isInitialized)) {
        print('🌐 الاتصال عاد - جاري المزامنة...');
        _onConnectionRestored();
      } else if (!hasConnection && _status != FirebaseSyncStatus.offline) {
        print('📴 انقطع الاتصال - العمل محلياً');
        _updateStatus(FirebaseSyncStatus.offline);
        markDeviceOffline(); // تعليم الجهاز كغير متصل
      }
    });
  }
  
  /// بدء مؤقت نبضة القلب
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_status == FirebaseSyncStatus.online) {
        updateDeviceHeartbeat();
      }
    });
  }
  
  /// إيقاف مؤقت نبضة القلب
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  /// 🔄 بدء المزامنة الخلفية الدورية
  void _startBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(_backgroundSyncInterval, (_) async {
      if (_status == FirebaseSyncStatus.online && !_isSyncing) {
        print('🔄 المزامنة الخلفية الدورية...');
        await _performBackgroundSync();
      }
    });
    print('✅ تم تفعيل المزامنة الخلفية (كل ${_backgroundSyncInterval.inMinutes} دقائق)');
  }
  
  /// إيقاف المزامنة الخلفية
  void _stopBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }
  
  /// تنفيذ المزامنة الخلفية (خفيفة - لا تؤثر على الأداء)
  Future<void> _performBackgroundSync() async {
    if (!_isInitialized || _groupId == null || _isSyncing) return;
    
    try {
      // 1️⃣ معالجة العمليات المعلقة في WAL
      if (_crashRecovery != null) {
        final pendingUploads = await _crashRecovery!.getPendingUploads();
        if (pendingUploads.isNotEmpty) {
          print('🔄 معالجة ${pendingUploads.length} عملية معلقة من WAL...');
          for (final op in pendingUploads) {
            try {
              bool uploadSucceeded = false;
              if (op.type == 'customer') {
                uploadSucceeded = await uploadCustomer(op.data);
              } else if (op.type == 'transaction') {
                final customerSyncUuid = op.data['customer_sync_uuid'] as String?;
                if (customerSyncUuid != null) {
                  uploadSucceeded = await uploadTransaction(op.data, customerSyncUuid);
                }
              }
              if (uploadSucceeded) {
                await _crashRecovery!.markSynced(op.id);
              } else {
                // ⚠️ الرفع فشل - نعلّم العملية كفاشلة وليس كمكتملة
                // (البيانات ستُعاد محاولتها عبر Retry Queue)
                await _crashRecovery!.markFailed(op.id, 'فشل رفع العملية أثناء المزامنة الخلفية');
              }
            } catch (e) {
              print('⚠️ فشل معالجة عملية WAL: ${op.id}');
              await _crashRecovery!.markFailed(op.id, e.toString());
            }
          }
        }
      }
        
      // 2️⃣ معالجة Retry Queue
      await _processRetryQueue();
      
      // 3️⃣ معالجة المعاملات اليتيمة القديمة (أكثر من 5 دقائق)
      await _retryOldOrphans();
      
      // 4️⃣ تنظيف البيانات القديمة (مرة واحدة يومياً)
      await _periodicCleanup();
      
    } catch (e) {
      print('⚠️ خطأ في المزامنة الخلفية: $e');
    }
  }
  
  /// إعادة محاولة المعاملات اليتيمة القديمة
  Future<void> _retryOldOrphans() async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
    
    // جلب الأيتام القديمة
    final oldOrphans = await db.query(
      'sync_orphans',
      where: 'received_at < ?',
      whereArgs: [cutoff],
      limit: 10,
    );
    
    if (oldOrphans.isEmpty) return;
    
    print('🔄 إعادة محاولة ${oldOrphans.length} معاملة يتيمة قديمة...');
    
    for (final orphan in oldOrphans) {
      final customerSyncUuid = orphan['customer_sync_uuid'] as String;
      
      // البحث عن العميل مرة أخرى
      final customerResult = await db.query(
        'customers',
        columns: ['id'],
        where: 'sync_uuid = ?',
        whereArgs: [customerSyncUuid],
      );
      
      if (customerResult.isNotEmpty) {
        // العميل موجود الآن - معالجة الأيتام
        final customerId = customerResult.first['id'] as int;
        await _processOrphans(customerId, customerSyncUuid);
      } else {
        // 🔒 لا نحذف اليتيمة مهما طال انتظارها. حذفها يعني ضياع مبلغ بصمت
        // واختلال رصيد العميل إلى الأبد، وهو بالضبط ما نبني هذا النظام لمنعه.
        // العميل قد يصل بعد ساعات (جهاز مطفأ، أو رفع عميل فشل ويُعاد لاحقاً)،
        // وحينها تُطبَّق المعاملة. نبقيها ونُبلّغ عنها بصوت عالٍ.
        final receivedAt = DateTime.parse(orphan['received_at'] as String);
        final waiting = DateTime.now().difference(receivedAt);
        if (waiting.inHours > 1) {
          print('⚠️ معاملة تنتظر عميلها منذ ${waiting.inHours} ساعة: '
              '${orphan['sync_uuid']} (العميل: $customerSyncUuid)');
        }
      }
    }
  }
  
  /// تنظيف دوري (مرة واحدة يومياً)
  DateTime? _lastCleanupDate;
  Future<void> _periodicCleanup() async {
    final today = DateTime.now();
    if (_lastCleanupDate != null && 
        _lastCleanupDate!.day == today.day && 
        _lastCleanupDate!.month == today.month) {
      return; // تم التنظيف اليوم
    }
    
    print('🧹 التنظيف الدوري اليومي...');
    _lastCleanupDate = today;
    
    try {
      // تنظيف WAL
      if (_crashRecovery != null) {
        await _crashRecovery!.cleanupCompletedOperations(keepDays: 7);
      }
      
      // تنظيف ACKs القديمة
      await _ackService?.cleanupOldAcks();
      
      // تنظيف سجلات العمليات
      await _operationTracker?.cleanupOldLogs();
      
      print('✅ اكتمل التنظيف الدوري');
    } catch (e) {
      print('⚠️ خطأ في التنظيف الدوري: $e');
    }
  }
  Future<void> _onConnectionRestored() async {
    _updateStatus(FirebaseSyncStatus.syncing);
    
    try {
      // 🔄 إذا لم تكتمل التهيئة الأولى، نعيد التهيئة الكاملة
      if (!_isInitialized) {
        print('🔄 إعادة التهيئة الكاملة بعد عودة الاتصال...');
        final success = await initialize();
        if (success) {
          print('✅ تمت إعادة التهيئة بنجاح');
          _syncEventController.add('تمت إعادة التهيئة بعد عودة الاتصال');
        } else {
          print('❌ فشلت إعادة التهيئة');
          _updateStatus(FirebaseSyncStatus.error);
        }
        return;
      }
      
      // مزامنة التغييرات المعلقة
      await _syncPendingChanges();

      // 🔄 سحب كامل إدمبوتنت: كل ما فات أثناء الانقطاع
      try {
        await performFullCatchUp();
      } catch (e) {
        print('⚠️ خطأ في السحب الكامل بعد عودة الاتصال: $e');
      }

      // إعادة تشغيل الـ listeners
      if (!_isListening) {
        await _startListening();
      }
      
      // 📱 تسجيل الجهاز مرة أخرى
      await registerDevice();
      
      _updateStatus(FirebaseSyncStatus.online);
      _syncEventController.add('تمت المزامنة بعد عودة الاتصال');
      
      
    } catch (e) {
      print('❌ خطأ في المزامنة بعد عودة الاتصال: $e');
      _updateStatus(FirebaseSyncStatus.error);
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// الاستماع للتغييرات من Firebase (Real-time)
  /// ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _startListening() async {
    if (_isListening || _groupId == null) return;
    
    // 🧹 دمج وتنظيف أي عملاء مكررين بنفس الاسم قبل بدء الاستماع
    await mergeDuplicateCustomersByName();

    print('👂 بدء الاستماع للتغييرات من Firebase...');
    print('   📍 المجموعة: $_groupId');
    print('   📱 معرف الجهاز: $_deviceId');

    // 🔒 استماع شامل بلا فلتر زمني (نفس نهج الفواتير المجرّب).
    // الفلتر السابق (lastModifiedAt > lastSyncAt) كان يتجاوز أي عميل أو
    // معاملة رُفعت أثناء إيقاف هذا الجهاز إذا سقطت خارج النافذة (فرق
    // ساعات الأجهزة / مقارنة نصية ISO)، فلا تصل أبداً حتى بمزامنة يدوية.
    // التطبيق الاستقبالي إدمبوتنت بالكالة (sync_uuid + مطابقة الاسم)،
    // لذا الاستماع الشامل آمن ولا يكرر شيئاً.
    final db = await _db.database;
    final syncState = await db.query('sync_state', limit: 1);
    final lastSyncAt = syncState.isNotEmpty ? syncState.first['last_sync_at'] as String? : null;
    print('🧠 استماع شامل إدمبوتنت (آخر مزامنة مرجعية: ${lastSyncAt ?? "لا يوجد"} — للاطلاع فقط)');

    final Query<Map<String, dynamic>> customersQuery = _firestore!.collection('customers');
    final Query<Map<String, dynamic>> transactionsQuery = _firestore!.collection('transactions');
    
    // الاستماع لتغييرات العملاء
    _customersListener = customersQuery
        .snapshots()
        .listen(
          _onCustomersChanged,
          onError: (e) => print('❌ خطأ في استماع العملاء: $e'),
        );
    
    // الاستماع لتغييرات المعاملات
    _transactionsListener = transactionsQuery
        .snapshots()
        .listen(
          _onTransactionsChanged, 
          onError: (e) => print('❌ خطأ في استماع المعاملات: $e'),
        );
    
    _isListening = true;
    _startDevicesListener(); // 📊 بدء مستمع الأجهزة والإحصائيات
    print('✅ تم بدء الاستماع للتغييرات');
  }
  
  Future<void> _stopListening() async {
    await _customersListener?.cancel();
    await _transactionsListener?.cancel();
    await _devicesListener?.cancel(); // 📊
    _customersListener = null;
    _transactionsListener = null;
    _devicesListener = null; // 📊
    _isListening = false;
  }

  /// 📊 بدء مستمع الأجهزة اللحظي
  void _startDevicesListener() {
    if (_devicesListener != null || _firestore == null) return;
    
    _devicesListener = _firestore!
        .collection('devices')
        .snapshots()
        .listen(
          _onDevicesChanged,
          onError: (e) => print('❌ خطأ في استماع الأجهزة: $e'),
        );
  }
  
  /// 📊 معالجة تغييرات الأجهزة اللحظية
  void _onDevicesChanged(QuerySnapshot snapshot) {
    final correctedNow = this.now;
    final devices = <Map<String, dynamic>>[];
    
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      final lastSeen = data['lastSeen'];
      DateTime? lastSeenDate;
      
      if (lastSeen is Timestamp) {
        lastSeenDate = lastSeen.toDate();
      } else if (lastSeen is String) {
        lastSeenDate = DateTime.tryParse(lastSeen);
      }
      
      final secondsSinceLastSeen = lastSeenDate != null 
          ? correctedNow.difference(lastSeenDate).inSeconds 
          : 9999;
      final isRecentlyActive = secondsSinceLastSeen < 60;
      
      final isOnline = data['isOnline'] == true && isRecentlyActive;
      final isListening = data['isListening'] == true && isRecentlyActive;
      final syncStatus = data['syncStatus'] as String? ?? 'unknown';
      
      String realtimeSyncStatus;
      if (!isOnline) {
        realtimeSyncStatus = 'غير متصل';
      } else if (isListening && syncStatus == 'online') {
        realtimeSyncStatus = 'متصل ويستمع ✓';
      } else if (isOnline && !isListening) {
        realtimeSyncStatus = 'متصل (لا يستمع)';
      } else {
        realtimeSyncStatus = syncStatus;
      }
      
      devices.add({
        'deviceId': data['deviceId'] ?? doc.id,
        'deviceName': data['deviceName'] ?? 'جهاز غير معروف',
        'platform': data['platform'] ?? 'غير محدد',
        'lastSeen': lastSeenDate?.toIso8601String(),
        'lastSeenFormatted': _formatLastSeen(lastSeenDate),
        'secondsSinceLastSeen': secondsSinceLastSeen,
        'isOnline': isOnline,
        'isListening': isListening,
        'syncStatus': syncStatus,
        'realtimeSyncStatus': realtimeSyncStatus,
        'isRealtimeSyncActive': isOnline && isListening && syncStatus == 'online',
        'isCurrentDevice': doc.id == _deviceId,
        'registeredAt': data['registeredAt'],
        'appVersion': data['appVersion'],
      });
    }
    
    _liveDevices = devices;
    if (!_devicesController.isClosed) {
      _devicesController.add(devices);
    }
  }
  
  /// 📊 بث تحديث الإحصائيات اللحظية
  void _emitLiveStats() {
    if (_syncStatsController.isClosed) return;
    _syncStatsController.add({
      'groupId': _groupId,
      'deviceId': _deviceId,
      'customersInCloud': _liveCustomersCount,
      'transactionsInCloud': _liveTransactionsCount,
      'status': _status.name,
    });
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// معالجة التغييرات الواردة من Firebase
  /// ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _onCustomersChanged(QuerySnapshot snapshot) async {
    // 📊 تحديث عدد العملاء اللحظي
    _liveCustomersCount = snapshot.docs.length;
    _emitLiveStats();
    
    for (final change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      final syncUuid = change.doc.id;
      final sourceDeviceId = data['deviceId'] as String?;
      
      // تجاهل التغييرات من نفس الجهاز
      if (sourceDeviceId == _deviceId) {
         // print('⏭️ تجاهل عميل من نفس الجهاز: $syncUuid'); 
         continue;
      }
      
      print('📥 استلام تغيير عميل من جهاز آخر: $syncUuid (نوع: ${change.type})');
      print('   - الجهاز المصدر: $sourceDeviceId');
      
      try {
        switch (change.type) {
          case DocumentChangeType.added:
            print('   ✨ جاري إضافة عميل جديد...');
            await _applyCustomerChange(syncUuid, data);
            break;
          case DocumentChangeType.modified:
             print('   📝 جاري تحديث عميل...');
            await _applyCustomerChange(syncUuid, data);
            break;
          case DocumentChangeType.removed:
            print('   🗑️ جاري حذف عميل...');
            await _deleteLocalCustomer(syncUuid);
            break;
        }
      } catch (e) {
        print('❌ خطأ في تطبيق تغيير العميل $syncUuid: $e');
      }
    }
    
    // تحديث وقت آخر مزامنة بعد معالجة أي تغييرات (للاستماع الذكي)
    if (snapshot.docChanges.isNotEmpty) {
      await mergeDuplicateCustomersByName();
      final db = await _db.database;
      final nowStr = DateTime.now().toIso8601String();
      final syncState = await db.query('sync_state', limit: 1);
      if (syncState.isNotEmpty) {
        await db.update('sync_state', {'last_sync_at': nowStr}, where: 'id = 1');
      } else {
        await db.insert('sync_state', {'id': 1, 'last_sync_at': nowStr});
      }
    }
  }
  
  Future<void> _onTransactionsChanged(QuerySnapshot snapshot) async {
    // 📊 تحديث عدد المعاملات اللحظي
    _liveTransactionsCount = snapshot.docs.length;
    _emitLiveStats();

    // 🧮 وصول بيانات = النظام غير ساكن، فيؤجَّل التدقيق التلقائي. التدقيق أثناء
    // التدفق يعدّ معاملة في طريقها إلينا نقصاً، فيطلق إنذاراً كاذباً.
    if (snapshot.docChanges.isNotEmpty) {
      ReconciliationService().noteActivity();
    }

    // 🔇 تنقية: نعالج بصمت تغييرات نفس الجهاز (رد فعل Firebase لكتاباتنا).
    // فقط المعاملات من أجهزة أخرى تطبع وتُحصى — هذا ما يهم المستخدم رؤيته.
    int fromOthers = 0;

    for (final change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final syncUuid = change.doc.id;
      final sourceDeviceId = data['deviceId'] as String?;

      // تجاهل التغييرات من نفس الجهاز (بصمت)
      if (sourceDeviceId == _deviceId) {
        continue;
      }
      fromOthers++;

      try {
        switch (change.type) {
          case DocumentChangeType.added:
          case DocumentChangeType.modified:
            await _applyTransactionChange(syncUuid, data);
            break;
          case DocumentChangeType.removed:
            await _deleteLocalTransaction(syncUuid);
            break;
        }
      } catch (e) {
        print('❌ خطأ في تطبيق تغيير المعاملة $syncUuid: $e');
      }
    }

    // ملخص واحد بدل طباعة كل تغيير على حدة (كان يملأ السجل بالضجيج).
    if (fromOthers > 0) {
      print('📥 استُلمت $fromOthers معاملة/تحديث من أجهزة أخرى');
    }
    
    // تحديث وقت آخر مزامنة بعد معالجة أي تغييرات (للاستماع الذكي)
    if (snapshot.docChanges.isNotEmpty) {
      final db = await _db.database;
      final nowStr = DateTime.now().toIso8601String();
      final syncState = await db.query('sync_state', limit: 1);
      if (syncState.isNotEmpty) {
        await db.update('sync_state', {'last_sync_at': nowStr}, where: 'id = 1');
      } else {
        await db.insert('sync_state', {'id': 1, 'last_sync_at': nowStr});
      }
    }
  }

  /// تطبيق تغيير عميل من Firebase على قاعدة البيانات المحلية.
  /// 🔒 مهم: لا نحدث current_total_debt من البيانات البعيدة!
  /// الرصيد يُحسب دائماً من مجموع المعاملات المحلية
  Future<void> _applyCustomerChange(String syncUuid, Map<String, dynamic> data) async {
    // 🔐 التحقق من صحة البيانات الواردة
    final validation = SyncValidation.validateFirebaseCustomerData(data);
    if (!validation.isValid) {
      print('❌ رفض بيانات عميل غير صالحة: ${validation.errors.join(', ')}');
      return;
    }
    if (validation.warnings.isNotEmpty) {
      print('⚠️ تحذيرات في بيانات العميل: ${validation.warnings.join(', ')}');
    }
    
    // 🔐 التحقق من التوقيع إذا كان موجوداً (تحذير فقط - لا رفض)
    final signature = data['signature'] as String?;
    final originDeviceId = data['originDeviceId'] as String?;
    if (signature != null && _groupSecretKey != null && originDeviceId != null) {
      final dataToVerify = '$syncUuid|$originDeviceId|${data['checksum'] ?? ''}';
      if (!SyncSecurity.verifySignature(dataToVerify, signature, _groupSecretKey!)) {
        // تحذير فقط - لا نرفض البيانات لأن المفتاح قد يكون مختلفاً بين الأجهزة
        print('⚠️ تحذير: توقيع العميل غير متطابق (قد يكون من جهاز آخر): $syncUuid');
      }
    }
    
    // 🔐 تنظيف البيانات من المحتوى الخطر
    final sanitizedData = SyncValidation.sanitizeMap(data);
    
    // 🗑️ إذا كان العميل محدداً كـ محذوف في البيانات الواردة
    if (sanitizedData['isDeleted'] == true || data['is_deleted'] == 1) {
      final conflictPolicy = await FirebaseSyncSecuritySettings.getCustomerConflictPolicy();
      if (conflictPolicy == CustomerConflictPolicy.smartReactivate) {
        final db = await _db.database;
        final newOfflineTx = await db.rawQuery('''
          SELECT t.id FROM transactions t
          JOIN customers c ON c.id = t.customer_id
          WHERE c.sync_uuid = ? AND (t.is_deleted IS NULL OR t.is_deleted = 0) AND t.is_created_by_me = 1
        ''', [syncUuid]);
        if (newOfflineTx.isNotEmpty) {
          print('🌟 [FirebaseSyncService] الإبقاء على العميل $syncUuid نشطاً لوجود ${newOfflineTx.length} معاملات محلية جديدة');
          return;
        }
      }
      await _deleteLocalCustomer(syncUuid);
      return;
    }
    
    final db = await _db.database;
    
    // التحقق من وجود العميل محلياً بـ sync_uuid
    final existing = await db.query(
      'customers',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
    );
    if (existing.isEmpty) {
      // 🎯 لم يُعثر عليه بـ sync_uuid: ابحث أولاً عن عميل موجود بنفس الاسم محلياً لتفادي تكرار العملاء!
      final incomingName = SyncValidation.sanitizeString(sanitizedData['name']?.toString() ?? '').trim();
      final normIncomingName = DatabaseHelpers.normalizeArabic(incomingName);

      final activeCustomers = await db.query(
        'customers',
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );

      Map<String, dynamic>? matchedCustomer;
      for (final c in activeCustomers) {
        final cName = (c['name'] as String? ?? '').trim();
        final cNorm = DatabaseHelpers.normalizeArabic(cName);
        if (cName == incomingName || (normIncomingName.isNotEmpty && cNorm == normIncomingName)) {
          matchedCustomer = c;
          break;
        }
      }

      if (matchedCustomer != null) {
        // 🔗 تم العثور على عميل محلي موجود بنفس الاسم! ربطه بدلاً من إنشاء عميل مكرر!
        final matchedId = matchedCustomer['id'] as int;
        print('🔗 [FirebaseSyncService] مطابقة عميل بالاسم: $incomingName (ID: $matchedId) -> ربط بـ sync_uuid: $syncUuid');

        await db.update(
          'customers',
          {
            'sync_uuid': syncUuid,
            'phone': (matchedCustomer['phone'] == null || matchedCustomer['phone'].toString().isEmpty) ? sanitizedData['phone'] : matchedCustomer['phone'],
            'general_note': matchedCustomer['general_note'] ?? sanitizedData['generalNote'],
            'address': matchedCustomer['address'] ?? sanitizedData['address'],
            'last_modified_at': DateTime.now().toIso8601String(),
            'synced_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [matchedId],
        );

        await _coordinator!.registerOperation(
          entityType: 'customer',
          syncUuid: syncUuid,
          source: SyncSource.firebase,
        );
        await _coordinator!.markFirebaseSynced('customer', syncUuid);

        // 👻 معالجة المعاملات اليتيمة بـ syncUuid
        await _processOrphans(matchedId, syncUuid);
        await _verifyAndRepairCustomerBalance(matchedId);

        _syncEventController.add('ربط عميل: $incomingName');
        return;
      }

      // عميل جديد - إضافته
      // 🔒 مهم: نضيف العميل برصيد 0، والرصيد سيُحسب من المعاملات لاحقاً
      await db.insert('customers', {
        'name': incomingName,
        'phone': sanitizedData['phone'],
        'current_total_debt': 0.0, // 🔒 نبدأ بصفر، المعاملات ستحدد الرصيد
        'general_note': sanitizedData['generalNote'],
        'address': sanitizedData['address'],
        'created_at': sanitizedData['createdAt'],
        'last_modified_at': sanitizedData['lastModifiedAt'],
        'audio_note_path': sanitizedData['audioNotePath'],
        'sync_uuid': syncUuid,
        'is_deleted': sanitizedData['isDeleted'] == true ? 1 : 0,
        'synced_at': DateTime.now().toIso8601String(),
        'is_created_by_me': 0,
      });
      
      // 🔒 تسجيل في المنسق (مستلم من Firebase)
      await _coordinator!.registerOperation(
        entityType: 'customer',
        syncUuid: syncUuid,
        source: SyncSource.firebase,
      );
      await _coordinator!.markFirebaseSynced('customer', syncUuid);
      
      print('✅ تم إضافة عميل جديد بنجاح من Firebase: ${data['name']}');
      print('   - Sync UUID: $syncUuid');
      
      // 👻 معالجة المعاملات اليتيمة أولاً (قبل الإشعار!)
      final newCustomerId = await db.query('customers', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [syncUuid]);
      if (newCustomerId.isNotEmpty) {
          await _processOrphans(newCustomerId.first['id'] as int, syncUuid);
      }
      // 🔔 الإشعار بعد اكتمال كل شيء (العميل + معاملاته)
      _syncEventController.add('عميل جديد: ${data['name']}');
      
    } else {
      // 🔒 عميل موجود - تحديث البيانات الوصفية فقط (بدون الرصيد!)
      final localData = existing.first;
      final customerId = localData['id'] as int;
      final localBalance = (localData['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      
      // 🔒 تحديث البيانات الوصفية فقط (الاسم، الهاتف، العنوان، الملاحظات)
      // لا نحدث current_total_debt أبداً من البيانات البعيدة!
      await db.update(
        'customers',
        {
          'name': data['name'] ?? localData['name'],
          'phone': data['phone'] ?? localData['phone'],
          // 🔒 لا نحدث current_total_debt - يبقى كما هو
          'general_note': data['generalNote'] ?? localData['general_note'],
          'address': data['address'] ?? localData['address'],
          'last_modified_at': data['lastModifiedAt'] ?? DateTime.now().toIso8601String(),
          'audio_note_path': data['audioNotePath'] ?? localData['audio_note_path'],
          'synced_at': DateTime.now().toIso8601String(),
          'is_created_by_me': 0,
          // 🔒 لا نحذف العميل من البيانات البعيدة
        },
        where: 'sync_uuid = ?',
        whereArgs: [syncUuid],
      );
      
      print('✅ تم تحديث بيانات العميل (بدون الرصيد): ${data['name']}');
      print('   📊 الرصيد المحلي محفوظ: $localBalance');
      _syncEventController.add('تحديث عميل: ${data['name']}');
    }
  }
  
  /// تطبيق تغيير معاملة من Firebase على قاعدة البيانات المحلية
  /// 🔄 تعمل بنفس طريقة Google Drive Sync:
  /// - تضيف المعاملة كمعاملة منفصلة
  /// - تعلّمها بـ is_created_by_me = 0
  /// - تضيف ملاحظة "من المزامنة (Firebase)"
  /// - لا تحذف أو تعدل المعاملات الموجودة
  Future<void> _applyTransactionChange(String syncUuid, Map<String, dynamic> data) async {
    // 🔐 التحقق من صحة البيانات الواردة
    final validation = SyncValidation.validateFirebaseTransactionData(data);
    if (!validation.isValid) {
      print('❌ رفض بيانات معاملة غير صالحة: ${validation.errors.join(', ')}');
      return;
    }
    
    // 🔒 التحقق من رفض المعاملات القديمة (إذا كان مفعلاً)
    final rejectOldTransactions = await FirebaseSyncSecuritySettings.isRejectOldTransactionsEnabled();
    if (rejectOldTransactions) {
      final transactionDateStr = data['transactionDate'] as String?;
      if (transactionDateStr != null) {
        try {
          final transactionDate = DateTime.parse(transactionDateStr);
          final maxAgeDays = await FirebaseSyncSecuritySettings.getMaxTransactionAgeDays();
          final cutoffDate = DateTime.now().subtract(Duration(days: maxAgeDays));
          
          if (transactionDate.isBefore(cutoffDate)) {
            final age = DateTime.now().difference(transactionDate).inDays;
            print('🚫 رفض معاملة قديمة ($age يوم): $syncUuid');
            print('   📅 تاريخ المعاملة: $transactionDateStr');
            print('   ⏰ الحد الأقصى: $maxAgeDays يوم');
            return;
          }
        } catch (e) {
          print('⚠️ خطأ في تحليل تاريخ المعاملة: $e');
        }
      }
    }
    
    final db = await _db.database;
    
    // الحصول على customer_id المحلي من sync_uuid
    final customerSyncUuid = data['customerSyncUuid'] as String?;
    if (customerSyncUuid == null) {
      print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
      print('   - السبب: معاملة بدون ربط عميل (customerSyncUuid)');
      print('   - ID: $syncUuid');
      return;
    }
    
    // البحث عن العميل
    final customerResult = await db.query(
      'customers',
      columns: ['id', 'name', 'current_total_debt', 'is_deleted'],
      where: 'sync_uuid = ?',
      whereArgs: [customerSyncUuid],
    );
    
    if (customerResult.isEmpty) {
      // 👻 العميل غير موجود - إضافة للطابور
      print('⏳ معاملة مؤقتة (بانتظار بيانات العميل)');
      print('   - العميل غير موجود بعد في القاعدة المحلية');
      print('   - ID: $syncUuid');
      print('   👉 تم حفظها في قائمة الانتظار لحين وصول بيانات العميل');
      await _addToOrphans(syncUuid, data);
      return;
    }
    
    final localCustomerId = customerResult.first['id'] as int;
    final customerName = customerResult.first['name'] as String? ?? 'غير معروف';
    final currentBalance = (customerResult.first['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    final isCustomerDeleted = ((customerResult.first['is_deleted'] as int?) ?? 0) == 1;
    final isTxDeleted = (data['isDeleted'] == true || data['is_deleted'] == 1);

    // 🛡️ معالجة سياسة تعارض حذف العملاء
    if (isCustomerDeleted && !isTxDeleted) {
      final conflictPolicy = await FirebaseSyncSecuritySettings.getCustomerConflictPolicy();
      if (conflictPolicy == CustomerConflictPolicy.smartReactivate) {
        print('🌟 [FirebaseSyncService] إعادة تنشيط ذكي للعميل: $customerName (ID: $localCustomerId) لوجود معاملة جديدة واردة أثناء انقطاع الاتصال!');
        await db.update(
          'customers',
          {
            'is_deleted': 0,
            'last_modified_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [localCustomerId],
        );
        _syncEventController.add('إعادة تنشيط العميل: $customerName لوجود معاملة جديدة');
      } else if (conflictPolicy == CustomerConflictPolicy.strictDelete) {
        print('🔒 [FirebaseSyncService] تم رفض معاملة لعميل محذوف حسب سياسة الحذف الصارم: $syncUuid');
        return;
      }
    }
    
    // 1️⃣ التحقق من وجود المعاملة بـ transaction_uuid
    final existingByUuid = await db.query(
      'transactions',
      where: 'transaction_uuid = ?',
      whereArgs: [syncUuid],
    );
    
    // البيانات الواردة
    final amountChanged = (data['amountChanged'] as num?)?.toDouble() ?? 0.0;
    final transactionDate = data['transactionDate'] as String?;
    final transactionNote = data['transactionNote'] as String? ?? '';
    String transactionType = data['transactionType'] as String? ?? '';
    if (transactionType.isEmpty) {
      transactionType = amountChanged >= 0 ? 'manual_debt' : 'manual_payment';
    }

    if (existingByUuid.isNotEmpty) {
      // ✅ المعاملة موجودة - نتحقق هل تحتاج تحديث؟
      final existingTx = existingByUuid.first;
      final currentAmount = (existingTx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      final currentType = existingTx['transaction_type'] as String?;
      final currentNote = existingTx['transaction_note'] as String? ?? '';
      
      // هل هناك اختلاف جوهري؟
      bool needsUpdate = (currentAmount - amountChanged).abs() > 0.01 || 
                         currentType != transactionType ||
                         currentNote != transactionNote;

      if (needsUpdate) {
        print('🔄 تحديث معاملة واردة من المزامنة: $syncUuid');
        print('   💰 المبلغ: $currentAmount -> $amountChanged');
        print('   🏷️ النوع: $currentType -> $transactionType');
        
        // 🔒 إصلاح أمني حرج: التحقق من مطابقة العميل
        final txCustomerId = existingTx['customer_id'] as int;
        final txCustomerCheck = await db.query(
          'customers',
          columns: ['sync_uuid', 'name'],
          where: 'id = ?',
          whereArgs: [txCustomerId],
        );
        
        if (txCustomerCheck.isEmpty) {
          print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
          print('   - السبب: العميل المرتبط غير موجود');
          print('   - معرف العميل المحلي: $txCustomerId');
          return;
        }
        
        final txCustomerSyncUuid = txCustomerCheck.first['sync_uuid'] as String?;
        if (txCustomerSyncUuid != customerSyncUuid) {
          print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
          print('   - السبب: عدم تطابق العميل (خطأ حرج!)');
          print('   - المتوقع (من Firebase): $customerSyncUuid');
          print('   - الموجود (محلياً): $txCustomerSyncUuid');
          print('   - المعاملة: $syncUuid');
          return;
        }
        
        // ⚠️ مهم جداً: استخدام DatabaseService لإعادة حساب كل شيء بشكل صحيح
        final dbService = DatabaseService();
        
        // تحديث المعاملة باستخدام DatabaseService (لإعادة حساب الأرصدة)
        final txId = existingTx['id'] as int;
        final existingTransaction = await dbService.getTransactionById(txId);
        
        if (existingTransaction != null) {
          // إنشاء نسخة محدثة من المعاملة
          final updatedTransaction = DebtTransaction(
            id: existingTransaction.id,
            customerId: existingTransaction.customerId,
            transactionDate: transactionDate != null ? DateTime.parse(transactionDate) : existingTransaction.transactionDate,
            amountChanged: amountChanged,
            balanceBeforeTransaction: existingTransaction.balanceBeforeTransaction, // سيتم إعادة حسابه
            newBalanceAfterTransaction: existingTransaction.newBalanceAfterTransaction, // سيتم إعادة حسابه
            
            transactionNote: transactionNote,
            transactionType: transactionType,
            description: data['description'] as String?,
            createdAt: existingTransaction.createdAt,
            audioNotePath: data['audioNotePath'] as String?,
            isCreatedByMe: existingTransaction.isCreatedByMe,
            isUploaded: existingTransaction.isUploaded,
            transactionUuid: existingTransaction.transactionUuid,
            invoiceId: existingTransaction.invoiceId,
          );
          
          // استخدام updateManualTransaction لإعادة حساب كل شيء بشكل صحيح.
          // fromSync يتجاوز حارس الملكية: هذا تحديث وصل من صاحب السجل نفسه.
          await dbService.updateManualTransaction(updatedTransaction,
              fromSync: true);
          
          // 🛡️ إصلاح جذري لمشكلة عدم تناسق الأرصدة:
          // إجبار النظام على إعادة حساب تسلسل الأرصدة بالكامل + الرصيد النهائي
          // هذا يضمن أنه حتى لو تغير التاريخ أو الترتيب، الأرصدة ستكون صحيحة 100%
          print('🔄 جاري إعادة حساب تسلسل الأرصدة للعميل ${existingTransaction.customerId}...');
          await dbService.recalculateCustomerTransactionBalances(existingTransaction.customerId);
          await dbService.recalculateAndApplyCustomerDebt(existingTransaction.customerId);
          
          // 🔒 التحقق من سلامة الرصيد بعد التحديث
          final updatedCustomer = await dbService.getCustomerById(existingTransaction.customerId);
          if (updatedCustomer != null) {
            final newBalance = updatedCustomer.currentTotalDebt;           
            // فحص الأرصدة غير المنطقية
            if (newBalance.abs() > 10000000) {
              print('⚠️ تحذير: رصيد غير منطقي بعد التحديث!');
              print('   - العميل: ${updatedCustomer.name}');
              print('   - الرصيد الجديد: $newBalance');
            }
            
            // فحص التغير المفاجئ
            final balanceChange = (newBalance - currentBalance).abs();
            if (balanceChange > 100000) {
              print('⚠️ تحذير: تغير كبير في الرصيد!');
              print('   - العميل: ${updatedCustomer.name}');
              print('   - التغير: $balanceChange');
            }
          }
        }
        
        print('═══════════════════════════════════════════════════════════════════');
        print('📥 تم استلام وتطبيق **تحديث** لمعاملة موجودة! 🔄✅');
        print('   - العميل: $customerName');
        print('   - المبلغ: $currentAmount ⬅️ تغير إلى: $amountChanged');
        print('   - الملاحظة: $transactionNote');
        print('   - ID: $syncUuid');
        print('═══════════════════════════════════════════════════════════════════');
        
        _syncEventController.add('تحديث معاملة: $customerName');
      } else {
        print('⏭️ المعاملة موجودة ومطابقة تماماً (تم تجاهل التحديث)');
        print('   - ID: $syncUuid');
      }
      return;
    }
    
    // 2️⃣ تبنّي السجلات التاريخية اليتيمة فقط.
    //
    // الهوية الآن هي sync_uuid وحده: كل معاملة تُولّد معرّفها لحظة إنشائها،
    // فالمعاملة الواردة إمّا معروفة بمعرّفها (عولجت أعلاه) أو جديدة تماماً.
    // الاستثناء الوحيد سجلات قديمة أُنشئت قبل هذا النظام على الجهازين معاً
    // وبقيت بلا معرّف؛ نربطها بدل أن نضاعفها. الشرط `sync_uuid IS NULL` أساسي:
    // بدونه يمكن أن نسرق هوية معاملة أخرى لها معرّفها الخاص بالفعل.
    if (transactionDate != null) {
      final orphanMatch = await db.query(
        'transactions',
        where: '''customer_id = ?
                  AND transaction_date = ?
                  AND ABS(amount_changed - ?) < 0.01
                  AND (transaction_uuid IS NULL OR transaction_uuid = '')
                  AND (is_deleted IS NULL OR is_deleted = 0)''',
        whereArgs: [localCustomerId, transactionDate, amountChanged],
        limit: 1,
      );

      if (orphanMatch.isNotEmpty) {
        await db.update(
          'transactions',
          {'sync_uuid': syncUuid, 'transaction_uuid': syncUuid, 'is_uploaded': 1},
          where: 'id = ?',
          whereArgs: [orphanMatch.first['id']],
        );
        print('🔗 رُبط سجل تاريخي يتيم بالمعرّف الوارد: $syncUuid');
        return;
      }
    }
    
    // 3️⃣ التحقق من صحة المبلغ
    if (amountChanged.abs() > 1000000000) {
      print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
      print('   - السبب: مبلغ غير منطقي (أكبر من مليار)');
      print('   - المبلغ: $amountChanged');
      print('   - ID: $syncUuid');
      return;
    }
    
    // 4️⃣ حساب الرصيد الجديد (مثل Google Drive Sync)
    final newBalance = currentBalance + amountChanged;
    
    // 5️⃣ إعداد ملاحظة المعاملة مع علامة "من المزامنة"
    String finalNote = transactionNote;
    if (!finalNote.contains('من المزامنة') && !finalNote.contains('من جهاز آخر')) {
      finalNote = finalNote.isEmpty 
          ? '🔄 من المزامنة (Firebase)' 
          : '$finalNote\n🔄 من المزامنة (Firebase)';
    }
    
    // 6️⃣ تحديد نوع المعاملة
    // المتغير transactionType تم تحديده في الأعلى
    if (transactionType.isEmpty) {
      // تحديد النوع من المبلغ
      transactionType = amountChanged >= 0 ? 'manual_debt' : 'manual_payment';
    }
    
    // 7️⃣ إدراج المعاملة الجديدة وتحديث الرصيد — ذرياً.
    //
    // 🔒 هنا يتحقق الاستقبال الإدمبوتنت: نُعيد فحص المعرّف داخل المعاملة نفسها
    // قبل الإدراج، فلو وصلت نفس المعاملة مرتين (إعادة بث، أو خطأ برمجي أنشأ
    // نسختين بنفس المعرّف) تُقبل الأولى وتُرفض الثانية دون أن يتحرك الرصيد.
    // ضمّ الإدراج وتحديث الرصيد في معاملة واحدة يمنع أيضاً بقاء رصيد مُحدَّث
    // لمعاملة لم تُدرج، أو العكس.
    final applied = await db.transaction<double?>((txn) async {
      final incomingInvUuid = data['invoiceSyncUuid'] ?? data['invoice_sync_uuid'];
      final alreadyThere = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'transaction_uuid = ? OR (invoice_sync_uuid = ? AND invoice_sync_uuid IS NOT NULL AND invoice_sync_uuid != "")',
        whereArgs: [syncUuid, incomingInvUuid ?? '___NONE___'],
        limit: 1,
      );
      if (alreadyThere.isNotEmpty) return null; // مرفوضة تكراراً (موجودة مسبقاً أو مرتبطة بالفاتورة)

      // 🔒 الرصيد يُقرأ داخل المعاملة، لا من اللقطة التي أُخذت قبلها.
      // القراءة الخارجية تفتح نافذة "التحديث الضائع": لو حُفظت معاملة محلية
      // بين القراءة والكتابة، لكتبنا فوق رصيدها بقيمة قديمة واختلّ الرصيد.
      final balanceBefore = await _sumTransactions(txn, localCustomerId);

      await txn.insert(
        'transactions',
        {
          'customer_id': localCustomerId,
          'transaction_date': transactionDate ?? DateTime.now().toIso8601String(),
          'amount_changed': amountChanged,
          'balance_before_transaction': balanceBefore,
          'new_balance_after_transaction': balanceBefore + amountChanged,
          'transaction_note': finalNote,
          'transaction_type': transactionType,
          'description': data['description'],
          'created_at': data['createdAt'] ?? DateTime.now().toIso8601String(),
          'audio_note_path': data['audioNotePath'],
          'is_created_by_me': 0, // 🔒 ليست من هذا الجهاز - لا يمكن حذفها أو تعديلها
          'is_uploaded': 1, // 🔒 تعليمها كمرفوعة لتجنب إعادة رفعها
          'sync_uuid': syncUuid,
          'transaction_uuid': syncUuid,
          'invoice_sync_uuid': data['invoiceSyncUuid'] ?? data['invoice_sync_uuid'],
          'is_deleted': 0, // 🔒 لا نحذف المعاملات القادمة من المزامنة
        },
      );

      // 8️⃣ الرصيد = مجموع المعاملات، لا رصيد سابق + مبلغ.
      // الاشتقاق من المجموع يجعل النتيجة مستقلة عن ترتيب الوصول، فجهاز استقبل
      // المعاملات بترتيب مختلف يصل إلى نفس الرصيد بالضبط.
      final authoritativeBalance = await _sumTransactions(txn, localCustomerId);
      await txn.update(
        'customers',
        {
          'current_total_debt': authoritativeBalance,
          'last_modified_at': DateTime.now().toIso8601String(),
          'synced_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [localCustomerId],
      );
      return authoritativeBalance; // الرصيد الفعلي بعد الإدراج
    });

    if (applied == null) {
      print('🚫 رُفضت معاملة واردة بمعرّف موجود مسبقاً: $syncUuid');
      print('   - لم يُمسّ رصيد العميل $customerName');
      return;
    }

    // 🧮 الرصيد الفعلي المُعتمد = ما خُزّن فعلًا في قاعدة البيانات.
    // نتجنّب استخدام `currentBalance + amountChanged` لأنه قد يكذب في حال سباق
    // (معاملتان وصلتا معًا قبل تحديث القراءة الخارجية). المعروض للمستخدم =
    // المخزن في القاعدة، بأخذ المعاملة الأخيرة كمرجع للحساب والتحقق.
    final authoritativeBalance = applied;
    
    // 9️⃣ تسجيل في المنسق
    await _coordinator!.registerOperation(
      entityType: 'transaction',
      syncUuid: syncUuid,
      source: SyncSource.firebase,
    );
    await _coordinator!.markFirebaseSynced('transaction', syncUuid);
    
    //  طإرسال تأكيد استلام (ACK) للجهاز المرسل
    final senderDeviceId = data['originDeviceId'] as String? ?? data['deviceId'] as String?;
    if (senderDeviceId != null && senderDeviceId != _deviceId) {
      await _ackService!.sendAck(
        transactionUuid: syncUuid,
        senderDeviceId: senderDeviceId,
      );
    }

    // ⚖️ هل على هذه المعاملة قرار إبطال معلّق (وصل القرار قبل معاملته)؟
    // نفّذه فوراً — يضمن التقارب مهما كان ترتيب الوصول.
    try {
      await _verdictService.applyPendingVerdictsFor(syncUuid);
    } catch (_) {}
    
    // 🔟 طباعة تفاصيل المعاملة للتدقيق
    final typeLabel = amountChanged >= 0 ? 'إضافة دين' : 'تسديد';
    print('═══════════════════════════════════════════════════════════════════');
    print('📥 تم استلام وقراءة معاملة جديدة بنجاح! ✅');
    print('   - العميل: $customerName (ID: $localCustomerId)');
    print('   - النوع: $typeLabel');
    print('   - المبلغ: ${amountChanged.abs()}');
    print('   - الرصيد قبل: $currentBalance');
    print('   - الرصيد بعد: $authoritativeBalance');
    print('   - من جهاز: $senderDeviceId');
    print('═══════════════════════════════════════════════════════════════════');

    _syncEventController.add('معاملة جديدة: $typeLabel ${amountChanged.abs()} - $customerName');

    // 🔄 إرسال إشعار لتحديث الواجهة فوراً.
    // 🔒 newBalance هنا = الرصيد الفعلي المخزّن، لا قيمة محسوبة بمعزل عن القاعدة.
    _transactionReceivedController.add({
      'customerId': localCustomerId,
      'customerSyncUuid': customerSyncUuid,
      'customerName': customerName,
      'syncUuid': syncUuid,
      'amountChanged': amountChanged,
      'newBalance': authoritativeBalance,
      'transactionType': transactionType,
      'transactionDate': transactionDate,
    });
    
    // إشعار بتحديث العميل
    _customerUpdatedController.add(customerSyncUuid);

    // 🛡️ شباك الأمان الحسابي (بليون بالمئة): بعد كل معاملة واردة نتأكد أن
    // الرصيد المخزّن = مجموع المعاملات تمامًا. لو انحرف لأي سبب (خطأ برمجي
    // نادر، إعادة بث مزدوجة، انقطاع في منتصف معاملة...) نُصحّحه فورًا هنا
    // قبل أن يراه المستخدم. هذا مستقل عن منطق الإدراج، فيتحقق حتى لو كان
    // الإدراج صحيحًا — فائض أمان لا يضر.
    await _verifyAndRepairCustomerBalance(localCustomerId);
  }

  /// 🛡️ شباك الأمان الحسابي: يضمن أن رصيد العميل = مجموع معاملاته بالضبط.
  ///
  /// يُستدعى بعد كل معاملة واردة. لو وُجد فرق > 0.01 يُصحّح الرصيد المخزّن
  /// ويُسجّل الإنذار للتدقيق. هذه الطبقة الأخيرة هي ما يرفع الموثوقية المحاسبية
  /// إلى مستوى "لا يمكن أن يختل الرصيد أبدًا" — حتى لو فشل منطق أعلى منها.
  Future<void> _verifyAndRepairCustomerBalance(int customerId) async {
    try {
      final db = await _db.database;
      final row = await db.rawQuery(
        'SELECT c.current_total_debt AS stored, '
        'COALESCE((SELECT SUM(amount_changed) FROM transactions '
        '          WHERE customer_id = c.id AND (is_deleted IS NULL OR is_deleted = 0)), 0) AS computed '
        'FROM customers c WHERE c.id = ?',
        [customerId],
      );
      if (row.isEmpty) return;
      final stored = (row.first['stored'] as num?)?.toDouble() ?? 0.0;
      final computed = (row.first['computed'] as num?)?.toDouble() ?? 0.0;
      if ((stored - computed).abs() > 0.01) {
        await db.update(
          'customers',
          {
            'current_total_debt': computed,
            'last_modified_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [customerId],
        );
        print('🚨🛡️ انحراف محاسبي اكتُشف وصُحّح للعميل $customerId: '
            'المخزن=$stored → الصحيح=$computed');
      }
    } catch (e) {
      print('⚠️ _verifyAndRepairCustomerBalance: $e');
    }
  }

  /// 🧹 دمج العملاء المكررين أوتوماتيكياً بنفس الاسم محلياً
  Future<void> mergeDuplicateCustomersByName() async {
    try {
      final db = await _db.database;
      final customers = await db.query(
        'customers',
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final c in customers) {
        final rawName = (c['name'] as String? ?? '').trim();
        if (rawName.isEmpty) continue;
        final normName = DatabaseHelpers.normalizeArabic(rawName);
        final key = normName.isEmpty ? rawName.toLowerCase() : normName;
        grouped.putIfAbsent(key, () => []).add(c);
      }

      for (final entry in grouped.entries) {
        final list = entry.value;
        if (list.length <= 1) continue; // لا يوجد تكرار

        print('🧹 [FirebaseSyncService] اكتشاف ${list.length} عميل مكرر باسم: "${list.first['name']}" -> جاري الدمج والتنظيف...');

        // اختيار العميل الرئيسي: نفضل الذي أُنكئ محلياً أولاً أو أقدم ID
        list.sort((a, b) {
          final aCreatedByMe = (a['is_created_by_me'] as int?) ?? 0;
          final bCreatedByMe = (b['is_created_by_me'] as int?) ?? 0;
          if (aCreatedByMe != bCreatedByMe) return bCreatedByMe.compareTo(aCreatedByMe);
          return (a['id'] as int).compareTo(b['id'] as int);
        });

        final primaryCustomer = list.first;
        final primaryId = primaryCustomer['id'] as int;

        final duplicateIds = <int>[];
        for (int i = 1; i < list.length; i++) {
          duplicateIds.add(list[i]['id'] as int);
        }

        for (final dupId in duplicateIds) {
          // 1) نقل كافة المعاملات للعميل الرئيسي
          await db.update(
            'transactions',
            {'customer_id': primaryId},
            where: 'customer_id = ?',
            whereArgs: [dupId],
          );

          // 2) نقل كافة الفواتير للعميل الرئيسي
          await db.update(
            'invoices',
            {'customer_id': primaryId},
            where: 'customer_id = ?',
            whereArgs: [dupId],
          );

          // 3) حذف الصف المكرر
          await db.delete(
            'customers',
            where: 'id = ?',
            whereArgs: [dupId],
          );
        }

        // 4) تصحيح وإصلاح الرصيد الكلي للعميل الرئيسي
        await _verifyAndRepairCustomerBalance(primaryId);
        print('✅ [FirebaseSyncService] تم دمج العملاء المكررين بنجاح في العميل ID: $primaryId');
      }
    } catch (e) {
      print('⚠️ [FirebaseSyncService] خطأ أثناء دمج العملاء المكررين: $e');
    }
  }

  /// 🗑️ حذف عميل من Firebase عند حذفه محلياً ليتزامن مع جميع الأجهزة (Soft Delete Tombstone)
  Future<void> deleteCustomerFromFirebase(String syncUuid) async {
    if (_groupId == null || _firestore == null) return;
    try {
      final now = DateTime.now().toIso8601String();
      await _firestore!.collection('customers').doc(syncUuid).set({
        'isDeleted': true,
        'is_deleted': 1,
        'lastModifiedAt': now,
        'deviceId': _deviceId,
      }, SetOptions(merge: true));
      print('🗑️ [FirebaseSyncService] تم تسجيل حذف العميل في Firebase بنجاح (Tombstone): $syncUuid');
    } catch (e) {
      print('❌ [FirebaseSyncService] خطأ أثناء تسجيل حذف العميل في Firebase: $e');
    }
  }

  /// 🗑️ حذف عميل محلياً تنفيذاً لأمر حذف قادم من جهاز آخر عبر Firebase
  Future<void> _deleteLocalCustomer(String syncUuid) async {
    try {
      final db = await _db.database;
      final existing = await db.query('customers', columns: ['id', 'name'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
      if (existing.isNotEmpty) {
        final customerId = existing.first['id'] as int;
        final customerName = existing.first['name'] as String? ?? '';
        
        await _db.deleteCustomer(customerId);
        
        print('🗑️ [FirebaseSyncService] تم حذف العميل محلياً بنجاح تنفيذاً لأمر الحذف من جهاز آخر: $customerName (ID: $customerId)');
        _syncEventController.add('تم حذف العميل: $customerName من جهاز آخر');
      }
    } catch (e) {
      print('❌ [FirebaseSyncService] خطأ أثناء تنفيذ الحذف المحلي للعميل $syncUuid: $e');
    }
  }
  
  /// حذف معاملة محلياً (Soft Delete)
  /// 🔒 لا نحذف المعاملات من Firebase - فقط نسجل تحذير
  Future<void> _deleteLocalTransaction(String syncUuid) async {
    // 🔒 حديد: لا حذف محلي أبداً — والرفع الشامل يقفل أي مسار حذف إضافي.
    if (_isRepairing || DatabaseService.blockTransactionDeletes) {
      print('🔒 رُفض حذف معاملة أثناء الرفع الشامل: $syncUuid');
      return;
    }
    // 🔒 لا نحذف المعاملات من البيانات البعيدة
    // هذا يمنع فقدان البيانات عند المزامنة
    print('⚠️ تجاهل طلب حذف معاملة من Firebase: $syncUuid');
    print('   🔒 المعاملات لا تُحذف عبر المزامنة للحفاظ على البيانات');
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// رفع التغييرات المحلية إلى Firebase
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// رفع عميل جديد أو محدث
  /// يرجع true عند النجاح (أو عند تخطي مقصود)، و false عند فشل الرفع
  Future<bool> uploadCustomer(Map<String, dynamic> customerData) async {
    if (!_isInitialized || _groupId == null) return true;
    
    //  التحقق  من Rate Limiting
    if (!_rateLimiter.canProceed()) {
      final waitTime = _rateLimiter.getWaitTime();
      print('⏳ تجاوز حد العمليات، انتظر ${waitTime?.inSeconds ?? 0} ثانية');
      return true;
    }
    
    // 🔒 التحقق من صحة البيانات
    if (!_validateCustomerData(customerData)) {
      print('❌ بيانات العميل غير صالحة - تم تخطي الرفع');
      return true;
    }
    
    final syncUuid = customerData['sync_uuid'] as String;

    // 🛡️ نفس الحماية المطبّقة على المعاملات: معرّف غير صالح يُسقط التطبيق أصلياً
    if (!SyncSecurity.isValidDocumentId(syncUuid)) {
      print('❌ تخطي رفع عميل بمعرّف غير صالح لـ Firestore: $syncUuid');
      return true;
    }

    // 🔒 التحقق من أن العملية ليست قيد الرفع حالياً
    if (_uploadLocks['customer_$syncUuid'] == true) {
      print('⏳ العميل قيد الرفع حالياً: $syncUuid');
      return true;
    }
    
    // 🔒 التحقق من أنها لم تُرفع مسبقاً
    final alreadySynced = await _coordinator!.isFirebaseSynced('customer', syncUuid);
    
    // 🔍 تشخيص دقيق: لماذا قد يتم تخطي الرفع؟
    if (alreadySynced) {
      // 🔄 الإصلاح: التحقق من تاريخ المزامنة الأخيرة
      // إذا كان last_modified_at أحدث من synced_at، يجب إعادة رفع العميل
      final lastModified = customerData['last_modified_at'] as String?;
      final syncedAt = customerData['synced_at'] as String?;
      
      bool needsReupload = false;
      if (lastModified != null && syncedAt != null) {
        try {
          final lastModDate = DateTime.parse(lastModified);
          final syncedDate = DateTime.parse(syncedAt);
          if (lastModDate.isAfter(syncedDate)) {
            needsReupload = true;
            print('⚠️ العميل تم تعديله بعد آخر مزامنة - جاري إعادة الرفع: $syncUuid');
          }
        } catch (e) {
          // في حالة خطأ في التحليل، نعيد الرفع للتأكد
          needsReupload = true;
        }
      } else if (syncedAt == null) {
        // لم تتم مزامنته من قبل
        needsReupload = true;
      }
      
      if (!needsReupload) {
        print('⏭️ العميل مرفوع ومحدث: $syncUuid');
        return true;
      }
      // نستمر في الرفع إذا needsReupload = true
    }
    
    print('🚀 بدء رفع العميل إلى Firebase: ${customerData['name']} ($syncUuid)');
    
    _uploadLocks['customer_$syncUuid'] = true;
    _rateLimiter.recordOperation();
    
    // 🛡️ تسجيل في WAL قبل الرفع
    String? walOperationId;
    if (_crashRecovery != null) {
      walOperationId = await _crashRecovery!.beginOperation(
        type: 'customer',
        action: 'create',
        syncUuid: syncUuid,
        data: customerData,
      );
      await _crashRecovery!.markUploading(walOperationId);
    }
    
    try {
      // حساب checksum للتحقق من التغييرات
      final checksum = _calculateChecksum(customerData);
      
      // 🔐 حساب التوقيع
      String? signature;
      if (_groupSecretKey != null) {
        final dataToSign = '$syncUuid|$_deviceId|$checksum';
        signature = SyncSecurity.signData(dataToSign, _groupSecretKey!);
      }
      
      final bool isDeleted = ((customerData['is_deleted'] as int?) ?? 0) == 1;
      final now = DateTime.now();
      await _firestore!
          .collection('customers')
          .doc(syncUuid)
          .set({
            'syncUuid': syncUuid,
            'name': customerData['name'],
            'phone': customerData['phone'],
            'currentTotalDebt': isDeleted ? 0.0 : customerData['current_total_debt'],
            'generalNote': customerData['general_note'],
            'address': customerData['address'],
            'createdAt': customerData['created_at'],
            'lastModifiedAt': customerData['last_modified_at'] ?? now.toIso8601String(),
            'audioNotePath': customerData['audio_note_path'],
            'isDeleted': isDeleted,
            'is_deleted': isDeleted ? 1 : 0,
            'deviceId': _deviceId,
            'originDeviceId': _deviceId, // 🔍 للتتبع والتدقيق
            'checksum': checksum,
            'signature': signature, // 🔐 التوقيع
            'groupSecret': _groupSecret, // 🔐 المفتاح السري للتحقق
            'uploadedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 60));
      
      // 🔒 تسجيل في المنسق
      await _coordinator!.registerOperation(
        entityType: 'customer',
        syncUuid: syncUuid,
        source: SyncSource.local,
        checksum: checksum,
      );
      await _coordinator!.markFirebaseSynced('customer', syncUuid);
      
      // 📝 تحديث قاعدة البيانات لتسجيل الرفع
      final db = await _db.database;
      await db.execute('UPDATE customers SET synced_at = ? WHERE sync_uuid = ?', [now.toIso8601String(), syncUuid]);
        
      // 🔄 تتبع العملية (للتحديثات)
      await _operationTracker!.trackCreate(
        syncUuid: syncUuid,
        entityType: 'customer',
        data: customerData,
      );
      
      // 🛡️ تعليم العملية كمكتملة في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markSynced(walOperationId);
      }
      
      print('☁️ تم رفع العميل بنجاح إلى الفاير بيس! 🚀');
      print('   - الاسم: ${customerData['name']}');
      print('   - ID: $syncUuid');
      
      return true;
      
    } catch (e) {
      print('❌ فشل رفع العميل للفاير بيس! حاول مرة أخرى.');
      print('   - الخطأ: $e');
      
      // 🛡️ تسجيل الفشل في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markFailed(walOperationId, e.toString());
      }
      // 🔄 إضافة للـ Retry Queue
      await _addToRetryQueue(_RetryOperation(
        type: 'customer',
        syncUuid: syncUuid,
        data: customerData,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
      return false;
    } finally {
      _uploadLocks.remove('customer_$syncUuid');
    }
  }
  
  /// رفع معاملة جديدة أو محدثة
  /// يرجع true عند النجاح (أو عند تخطي مقصود)، و false عند فشل الرفع
  ///
  /// [force] يعيد الرفع حتى لو كانت معلّمة محلياً كمرفوعة — للمطابقة فقط.
  /// لا يتجاوز أبداً قيد الملكية: معاملات المزامنة (`is_created_by_me = 0`)
  /// تُرفض في كل المسارات بما فيها الرفع الشامل والرفع القسري.
  Future<bool> uploadTransaction(
    Map<String, dynamic> txData,
    String customerSyncUuid, {
    bool force = false,
  }) async {
    if (!_isInitialized || _groupId == null) return true;
    
    // 🔒 حديد: لا تُرفع معاملة أتت من المزامنة بأي طريق كان.
    // NULL يُعامل كـ «من هذا الجهاز» للتوافق مع السجلات القديمة فقط.
    final isCreatedByMe = txData['is_created_by_me'];
    if (isCreatedByMe != null && isCreatedByMe == 0) {
      print('🚫 رُفض رفع معاملة ليست من إنشاء هذا الجهاز: ${txData['transaction_uuid']}');
      return true; // تخطٍ مقصود — ليس فشلاً يُعاد
    }
    
    // 🔧 التحقق من Rate Limiting
    if (!_rateLimiter.canProceed()) {
      final waitTime = _rateLimiter.getWaitTime();
      print('⏳ تجاوز حد العمليات، انتظر ${waitTime?.inSeconds ?? 0} ثانية');
      return true;
    }
    
    // 🔒 التحقق من صحة البيانات
    if (!_validateTransactionData(txData)) {
      print('❌ بيانات المعاملة غير صالحة - تم تخطي الرفع');
      return true;
    }
    
    final syncUuid = txData['transaction_uuid'] as String;

    // 🛡️ معرّف غير صالح (يحتوي فاصل مسار مثلاً) يُنهي التطبيق داخل مكتبة Firestore
    // الأصلية قبل أن يصل الخطأ إلى Dart، لذا نوقفه هنا. الإصلاح الفعلي يتم في
    // DatabaseService.sanitizeLegacyTransactionUuids عند بدء التشغيل.
    if (!SyncSecurity.isValidDocumentId(syncUuid)) {
      print('❌ تخطي رفع معاملة بمعرّف غير صالح لـ Firestore: $syncUuid');
      return true;
    }

    // 🔒 التحقق من أن العملية ليست قيد الرفع حالياً
    if (_uploadLocks['transaction_$syncUuid'] == true) {
      print('⏳ المعاملة قيد الرفع حالياً: $syncUuid');
      return true;
    }    // 🔒 التحقق من أنها لم تُرفع مسبقاً
    final lastSyncTime = await _coordinator!.getLastSyncTime('transaction', syncUuid);  // ⚠️ المعاملات في قاعدة البيانات المحلية لا تحتوي على حقل updated_at (في النسخة الحالية)
    // لذلك إذا كانت مسجلة في المنسق أنها مرفوعة، نتحقق من الحالة المحلية الفعلية
    if (!force && lastSyncTime != null) {
      // 🔄 الإصلاح: إذا كانت is_uploaded = 0 محلياً، يجب إعادة رفعها!
      // لأن تسجيل المنسق قد يكون خاطئاً (سجل قبل فشل الرفع الفعلي)
      if (txData['is_uploaded'] != 1) {
        print('⚠️ المعاملة مسجلة في المنسق كمرفوعة لكن is_uploaded=0 - جاري إعادة الرفع: $syncUuid');
        // لا نرجع هنا، نستمر في الرفع
      } else {
        print('⏭️ المعاملة مرفوعة فعلاً (المنسق + المحلي متطابقان): $syncUuid');
        return true;
      }
    }
    
      
    // 🔒 التحقق من عدم وجود معاملة مكررة
    final isDuplicate = await _coordinator!.isDuplicateTransaction(
      customerId: txData['customer_id'] as int,
      transactionDate: txData['transaction_date'] as String,
      amount: (txData['amount_changed'] as num).toDouble(),
      transactionType: txData['transaction_type'] as String? ?? 'debt',
    );
    
    // لا نتخطى إذا كانت مكررة، لكن نسجل تحذير
    if (isDuplicate) {
      print('⚠️ تحذير: معاملة قد تكون مكررة: $syncUuid');
    }
    
    _uploadLocks['transaction_$syncUuid'] = true;
    _rateLimiter.recordOperation();
    
    // 🛡️ تسجيل في WAL قبل الرفع
    String? walOperationId;
    if (_crashRecovery != null) {
      final walData = Map<String, dynamic>.from(txData);
      walData['customer_sync_uuid'] = customerSyncUuid;
      walOperationId = await _crashRecovery!.beginOperation(
        type: 'transaction',
        action: 'create',
        syncUuid: syncUuid,
        data: walData,
      );
      await _crashRecovery!.markUploading(walOperationId);
    }
    
    try {
      // حساب checksum للتحقق من التغييرات
      final checksum = _calculateChecksum(txData);
      
      // 🔐 حساب التوقيع
      String? signature;
      if (_groupSecretKey != null) {
        final dataToSign = '$syncUuid|$_deviceId|$checksum';
        signature = SyncSecurity.signData(dataToSign, _groupSecretKey!);
      }
      
      final bool isTxDeleted = ((txData['is_deleted'] as int?) ?? 0) == 1;
      await _firestore!
          .collection('transactions')
          .doc(syncUuid)
          .set({
            'syncUuid': syncUuid,
            'customerSyncUuid': customerSyncUuid,
            'invoiceSyncUuid': txData['invoice_sync_uuid'],
            'transactionDate': txData['transaction_date'],
            'amountChanged': txData['amount_changed'],
            'balanceBeforeTransaction': txData['balance_before_transaction'],
            'newBalanceAfterTransaction': txData['new_balance_after_transaction'],
            'transactionNote': txData['transaction_note'],
            'transactionType': txData['transaction_type'],
            'description': txData['description'],
            'createdAt': txData['created_at'],
            'lastModifiedAt': DateTime.now().toIso8601String(),
            'audioNotePath': txData['audio_note_path'],
            'isDeleted': isTxDeleted,
            'is_deleted': isTxDeleted ? 1 : 0,
            'deviceId': _deviceId,
            'originDeviceId': _deviceId, // 🔍 للتتبع والتدقيق
            'checksum': checksum,
            'signature': signature, // 🔐 التوقيع
            'groupSecret': _groupSecret, // 🔐 المفتاح السري للتحقق
            'uploadedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 60));
      
      // 🔒 تسجيل في المنسق وتحديث قاعدة البيانات
      await _coordinator!.registerOperation(
        entityType: 'transaction',
        syncUuid: syncUuid,
        source: SyncSource.local,
        checksum: checksum,
      );
      await _coordinator!.markFirebaseSynced('transaction', syncUuid);
      
      // 📝 تحديث قاعدة البيانات لتسجيل الرفع
      final db = await _db.database;
      await db.execute('UPDATE transactions SET is_uploaded = 1 WHERE transaction_uuid = ?', [syncUuid]);
      
      print('☁️ تم رفع المعاملة بنجاح إلى الفاير بيس! 🚀');
      print('   - ID: $syncUuid');
      print('   - المبلغ: ${txData['amountChanged'] ?? txData['amount_changed']}');
      
      // 🛡️ تعليم العملية كمكتملة في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markSynced(walOperationId);
      }
      
      return true;
    } catch (e) {
      print('❌ فشل رفع المعاملة: $e');
      
      // 🛡️ تسجيل الفشل في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markFailed(walOperationId, e.toString());
      }
      
      // 🔄 إضافة للـ Retry Queue
      final retryData = Map<String, dynamic>.from(txData);
      retryData['customer_sync_uuid'] = customerSyncUuid;
      await _addToRetryQueue(_RetryOperation(
        type: 'transaction',
        syncUuid: syncUuid,
        data: retryData,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
      return false;
    } finally {
      _uploadLocks.remove('transaction_$syncUuid');
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// مزامنة البيانات المعلقة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// مزامنة جميع التغييرات المعلقة مع دعم مؤشر التقدم
  /// مزامنة جميع التغييرات المعلقة — بطريقة **العميل-بعميل الصارمة**.
  ///
  /// المبدأ: لكل عميل نرفعه هو + كل معاملاته كـ «كتلة واحدة متماسكة». لا ننتقل
  /// للعميل التالي إلا بعد التأكد أن العميل الحالي رُفع هو ومعاملاته كلها.
  /// هذا يمنع «عاصفة الرفع» (نفس المعاملة تُرفع من 3 مصادر) ويضمن ترتيبًا
  /// منطقيًا: العميل دائمًا يصل قبل معاملاته إلى الجهاز الآخر.
  /// 🔄 سحب كامل عند التشغيل (Catch-Up) — ضمان تقارب لا يعتمد على المستمعين.
  ///
  /// المستمعون اللحظيون يعالجون docChanges فقط؛ أي مستند فاتتهم (تطبيق قديم
  /// على جهاز آخر، جدولة الشبكة، إعادة تشغيل) لا يعالج لاحقاً أبداً.
  /// هذه الدالة تسحب كل عملاء ومعاملات السحابة عند الإقلاع وتطبقها
  /// إدمبوتنت — فأي جهاز يعود للعمل يصل للحقيقة كاملة مهما غاب.
  /// التطبيق آمن: موجود بالـ UUID يُهمل، والرصيد يُشتق من المجموع.
  Future<void> performFullCatchUp() async {
    if (!_isInitialized || _groupId == null || _firestore == null) return;

    print('🔄 [Catch-Up] بدء السحب الكامل عند التشغيل...');

    // 1️⃣ العملاء أولاً (المعاملات تتيمة بدون عملائها)
    try {
      final custSnap = await _firestore!.collection('customers').get().timeout(
            const Duration(seconds: 60),
          );
      int appliedCust = 0;
      for (final doc in custSnap.docs) {
        final data = doc.data();
        if (data['deviceId'] == _deviceId) continue; // من صنعي — عندي نسخة أصلية
        try {
          await _applyCustomerChange(doc.id, data);
          appliedCust++;
        } catch (e) {
          print('⚠️ [Catch-Up] فشل تطبيق عميل ${doc.id}: $e');
        }
      }
      print('✅ [Catch-Up] العملاء: فُحص ${custSnap.docs.length}، طُبّق/تُحقّق $appliedCust');
    } catch (e) {
      print('❌ [Catch-Up] فشل سحب العملاء: $e');
    }

    // 2️⃣ المعاملات
    try {
      final txSnap = await _firestore!.collection('transactions').get().timeout(
            const Duration(seconds: 120),
          );
      int appliedTx = 0;
      for (final doc in txSnap.docs) {
        final data = doc.data();
        if (data['deviceId'] == _deviceId) continue;
        try {
          await _applyTransactionChange(doc.id, data);
          appliedTx++;
        } catch (e) {
          print('⚠️ [Catch-Up] فشل تطبيق معاملة ${doc.id}: $e');
        }
      }
      print('✅ [Catch-Up] المعاملات: فُحص ${txSnap.docs.length}، طُبّق/تُحقّق $appliedTx');
    } catch (e) {
      print('❌ [Catch-Up] فشل سحب المعاملات: $e');
    }

    print('✅ [Catch-Up] اكتمل السحب الكامل');

    // ⚖️ بعد السحب الكامل: نفّذ أي قرارات إبطال معلّقة وصلت معاملاتها
    try {
      await _verdictService.processPendingVerdicts();
    } catch (_) {}
  }

  /// 🚀 رفع فوري لعميل محدد ومعاملاته المعلقة (يُستدعى لحظة إنشاء/تعديل العميل).
  ///
  /// قبل هذه الدالة كان الإنشاء يُخزَّن محلياً فقط، والرفع ينتظر الدورة
  /// الخلفية (10 دقائق) أو الـ watchdog (30 ثانية) — فإذا أُغلق التطبيق
  /// بسرعة بعد الإضافة بقي العميل محلياً ولم يصل لبقية الأجهزة.
  /// المنطق نفسه كتلة _syncPendingChanges: العميل أولاً ثم معاملاته.
  Future<void> syncCustomerNow(int customerId) async {
    if (!_isInitialized || _groupId == null) return;

    try {
      final db = await _db.database;
      final rows = await db.query(
        'customers',
        where: 'id = ? AND sync_uuid IS NOT NULL AND sync_uuid != \'\' '
            'AND (is_deleted IS NULL OR is_deleted = 0) '
            'AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
        whereArgs: [customerId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final customer = rows.first;
      final customerSyncUuid = customer['sync_uuid'] as String;

      final customerOk = await uploadCustomer(customer);
      if (!customerOk) return;

      final pendingTx = await db.query(
        'transactions',
        where: 'customer_id = ? AND transaction_uuid IS NOT NULL AND transaction_uuid != \'\' '
            'AND (is_deleted IS NULL OR is_deleted = 0) '
            'AND (is_uploaded = 0 OR is_uploaded IS NULL) '
            'AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
        whereArgs: [customerId],
        orderBy: 'transaction_date ASC, id ASC',
      );

      for (final tx in pendingTx) {
        try {
          await uploadTransaction(tx, customerSyncUuid);
        } catch (e) {
          print('⚠️ [رفع فوري] فشل رفع معاملة ${tx['transaction_uuid']}: $e '
              '(ستُعاد تلقائياً)');
        }
      }

      print('🚀 [رفع فوري] اكتمل رفع العميل "${customer['name']}" '
          'و${pendingTx.length} معاملة');
    } catch (e) {
      print('⚠️ [رفع فوري] فشل رفع العميل $customerId: $e (ستتكفل به المزامنة الخلفية)');
    }
  }

  Future<void> _syncPendingChanges({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (!_isInitialized || _groupId == null) return;

    print('🔄 جاري مزامنة التغييرات المعلقة (عميل-بعميل)...');

    final db = await _db.database;

    // 🎯 جلب العملاء الذين أنشأهم هذا الجهاز ويحتاجون رفعًا أو إعادة رفع.
    final customers = await db.query(
      'customers',
      where:
          "sync_uuid IS NOT NULL AND sync_uuid != '' AND (is_deleted IS NULL OR is_deleted = 0) "
          "AND (synced_at IS NULL OR last_modified_at > synced_at) "
          "AND (is_created_by_me = 1 OR is_created_by_me IS NULL)",
      orderBy: 'id ASC',
    );

    final totalCustomers = customers.length;
    var processedCustomers = 0;

    for (final customer in customers) {
      final customerSyncUuid = customer['sync_uuid'] as String?;
      final customerId = customer['id'] as int;
      final customerName = customer['name'] as String? ?? '';

      // 1️⃣ رفع العميل أولًا والتحقق من نجاحه. لا نرفع معاملاته إن فشل رفع العميل،
      // لأن معاملة بدون عميلها تُخزَّن يتيمة على الجهاز الآخر.
      bool customerOk = false;
      try {
        customerOk = await uploadCustomer(customer);
      } catch (e) {
        print('⚠️ فشل رفع العميل $customerName: $e');
      }
      if (!customerOk) {
        processedCustomers++;
        continue; // نحاول مع العميل التالي؛ المعاملات تبقى معلّقة (is_uploaded=0).
      }

      // 2️⃣ رفع جميع معاملات هذا العميل (من إنشاء هذا الجهاز) التي لم تُرفع.
      final pendingTx = await db.query(
        'transactions',
        where:
            "customer_id = ? AND transaction_uuid IS NOT NULL AND transaction_uuid != '' "
            "AND (is_deleted IS NULL OR is_deleted = 0) "
            "AND (is_uploaded = 0 OR is_uploaded IS NULL) "
            "AND (is_created_by_me = 1 OR is_created_by_me IS NULL)",
        whereArgs: [customerId],
        orderBy: 'transaction_date ASC, id ASC',
      );

      int txFailed = 0;
      for (final tx in pendingTx) {
        try {
          final ok = await uploadTransaction(tx, customerSyncUuid!);
          if (!ok) txFailed++;
        } catch (e) {
          txFailed++;
          print('⚠️ فشل رفع معاملة ${tx['transaction_uuid']}: $e');
        }
      }

      if (txFailed == 0 && pendingTx.isNotEmpty) {
        print('✅ اكتمل رفع كتلة العميل "$customerName": '
            '${pendingTx.length} معاملة');
      } else if (txFailed > 0) {
        print('⚠️ العميل "$customerName": فشل رفع $txFailed معاملة '
            '(ستُعاد محاولتها تلقائيًا)');
      }

      processedCustomers++;
      if (totalCustomers > 0 && onProgress != null) {
        final p = (processedCustomers / totalCustomers) * 0.85;
        onProgress(p, 'رفع $customerName ومعاملاته '
            '($processedCustomers/$totalCustomers)...');
      }
    }

    // 3️⃣ رفع الفواتير والمنتجات غير المرفوعة (85-100%).
    onProgress?.call(0.85, 'جاري رفع الفواتير والمنتجات...');
    try {
      await InvoiceSyncService().syncPendingInvoices();
      await ProductSyncService().syncPendingProducts();
    } catch (e) {
      print('⚠️ فشل رفع الفواتير/المنتجات المعلقة: $e');
    }

    onProgress?.call(1.0, 'تم رفع البيانات!');
    await FirebaseSyncConfig.setLastSyncTime(DateTime.now());
    print('✅ تمت مزامنة التغييرات المعلقة');
  }
  /// مزامنة كاملة (تنزيل + رفع) مع دعم مؤشر التقدم
  /// مزامنة كاملة (تنزيل + رفع) مع دعم مؤشر التقدم
  /// يرجع true عند اكتمال المزامنة بنجاح، و false عند الفشل أو عدم الاتصال
  Future<bool> performFullSync({
    void Function(double progress, String message)? onProgress,
  }) async {
    print('🔄 [performFullSync] ════════════════════════════════════════');
    
    if (!_isInitialized || _groupId == null) {
      print('❌ [performFullSync] المزامنة غير مُعدة');
      print('❌ [performFullSync] _isInitialized: $_isInitialized');
      print('❌ [performFullSync] _groupId: $_groupId');
      return false;
    }
    
    // ✅ تشخيص حالة Firebase قبل المزامنة
    print('✅ [performFullSync] GroupId: $_groupId');
    print('✅ [performFullSync] DeviceId: $_deviceId');
    print('✅ [performFullSync] Firestore instance: ${_firestore != null ? "موجود" : "NULL!"}');
    
    // ✅ فحص حالة المصادقة
    try {
      final currentUser = FirebaseAuthService().currentUser;
      if (currentUser == null) {
        print('❌ [performFullSync] المستخدم غير مسجل دخول!');
        print('❌ [performFullSync] FirebaseAuth.currentUser = null');
        print('❌ [performFullSync] المزامنة ستفشل - يجب تسجيل الدخول أولاً');
        return false;
      } else {
        print('✅ [performFullSync] المستخدم مسجل الدخول');
        print('✅ [performFullSync] UID: ${currentUser.uid}');
        print('✅ [performFullSync] isAnonymous: ${currentUser.isAnonymous}');
        
        // ✅ فحص صلاحية Token
        try {
          final token = await currentUser.getIdToken();
          print('✅ [performFullSync] Token موجود وصالح');
          print('✅ [performFullSync] Token length: ${token?.length ?? 0}');
        } catch (e) {
          print('❌ [performFullSync] فشل الحصول على Token: $e');
        }
      }
    } catch (e) {
      print('❌ [performFullSync] خطأ في فحص المصادقة: $e');
    }
    
    // 🔒 منع المزامنة المتزامنة
    if (_isSyncing) {
      print('⚠️ [performFullSync] المزامنة قيد التنفيذ بالفعل');
      return false;
    }
    
    _isSyncing = true;
    _isBulkUploading = true; // 🛡️ أوقف Watchdog وTracker لمنع عاصفة الرفع
    DatabaseService.blockTransactionDeletes = true;
    _syncStartTime = DateTime.now();
    _updateStatus(FirebaseSyncStatus.syncing);
    try {
      // 🔒 التحقق من الاتصال قبل البدء (5%)
      print('🔍 [performFullSync] فحص الاتصال بالإنترنت...');
      onProgress?.call(0.05, 'جاري التحقق من الاتصال...');
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult.any((r) => r != ConnectivityResult.none);
      
      if (!hasConnection) {
        print('❌ [performFullSync] لا يوجد اتصال بالإنترنت');
        print('📴 لا يوجد اتصال - تأجيل المزامنة');
        _updateStatus(FirebaseSyncStatus.offline);
        return false;
      }
      print('✅ [performFullSync] الاتصال بالإنترنت موجود: $connectivityResult');
      
      // 1. تنزيل البيانات من Firebase (10-50%)
      print('⬇️ [performFullSync] بدء تنزيل البيانات من Firebase...');
      onProgress?.call(0.10, 'جاري تنزيل العملاء...');
      await _downloadAllData(onProgress: (p, m) {
        // التقدم من 10% إلى 50%
        onProgress?.call(0.10 + (p * 0.40), m);
      });
      print('✅ [performFullSync] انتهى التنزيل من Firebase');
      
      // 🔒 التحقق من الاتصال مرة أخرى قبل الرفع (55%)
      onProgress?.call(0.55, 'جاري التحقق من الاتصال...');
      final stillConnected = await Connectivity().checkConnectivity();
      if (!stillConnected.any((r) => r != ConnectivityResult.none)) {
        print('❌ [performFullSync] انقطع الاتصال أثناء التنزيل');
        print('📴 انقطع الاتصال أثناء التنزيل - إيقاف المزامنة');
        _updateStatus(FirebaseSyncStatus.offline);
        return false;
      }
      
      // 2. رفع البيانات المحلية (60-85%)
      print('⬆️ [performFullSync] بدء رفع البيانات المحلية...');
      onProgress?.call(0.60, 'جاري رفع البيانات المحلية...');
      await _syncPendingChanges(onProgress: (p, m) {
        // التقدم من 60% إلى 85%
        onProgress?.call(0.60 + (p * 0.25), m);
      });
      print('✅ [performFullSync] انتهى رفع البيانات');
      
      // 3. التحقق من سلامة البيانات (90%)
      onProgress?.call(0.90, 'جاري التحقق من سلامة البيانات...');
      final integrity = await verifyDataIntegrity();
      if (integrity['valid'] != true) {
        print('⚠️ [performFullSync] تحذير: بعض البيانات قد لا تكون متزامنة');
        print('⚠️ [performFullSync] Issues: ${integrity['issues']}');
        _syncEventController.add('تحذير: ${integrity['issues']}');
      }
      
      // 4. الانتهاء (100%)
      onProgress?.call(1.0, 'تمت المزامنة بنجاح!');
      
      _updateStatus(FirebaseSyncStatus.online);
      _syncEventController.add('تمت المزامنة الكاملة');
      
      final duration = DateTime.now().difference(_syncStartTime!);
      print('✅ [performFullSync] اكتملت المزامنة في ${duration.inSeconds} ثانية');
      print('🎉 [performFullSync] ════════════════════════════════════════');
      
      return true;
      
    } catch (e, stackTrace) {
      print('❌ [performFullSync] فشلت المزامنة الكاملة!');
      print('❌ [performFullSync] Error Type: ${e.runtimeType}');
      print('❌ [performFullSync] Error: $e');
      print('❌ [performFullSync] StackTrace: $stackTrace');
      
      if (e.toString().contains('permission-denied')) {
        print('❌ [performFullSync] السبب: Firestore Rules ترفض الوصول');
        print('❌ [performFullSync] تحقق من: هل المستخدم مصادق بشكل صحيح؟');
        print('❌ [performFullSync] تحقق من: هل Firestore Rules منشورة بشكل صحيح؟');
      }
      
      _updateStatus(FirebaseSyncStatus.error);
      _errorController.add('فشلت المزامنة: $e');
      return false;
    } finally {
      _isSyncing = false;
      _isBulkUploading = false; // 🔓 اسمح لـ Watchdog وTracker بالعمل مجددًا
      DatabaseService.blockTransactionDeletes = false;
      _syncStartTime = null;
    }
  }
  
  /// تنزيل جميع البيانات من Firebase مع دعم مؤشر التقدم
  Future<void> _downloadAllData({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (_groupId == null) return;
    
    print('⬇️ [_downloadAllData] ════════════════════════════════════════');
    print('⬇️ جاري تنزيل البيانات من Firebase...');
    
    // تنزيل العملاء (0-50%)
    QuerySnapshot<Map<String, dynamic>>? customersSnapshot;
    int totalCustomers = 0;
    
    try {
      print('🔍 [_downloadAllData] محاولة قراءة customers...');
      onProgress?.call(0.0, 'جاري تنزيل العملاء...');
      customersSnapshot = await _firestore!
          .collection('customers')
          .get();
      
      totalCustomers = customersSnapshot.docs.length;
      print('✅ [_downloadAllData] تم تنزيل ${totalCustomers} عميل');
    } catch (e) {
      print('❌ [_downloadAllData] فشل تنزيل العملاء!');
      print('❌ [_downloadAllData] Error Type: ${e.runtimeType}');
      print('❌ [_downloadAllData] Error: $e');
      rethrow; // إعادة رمي الخطأ لإيقاف المزامنة
    }
    
    var processedCustomers = 0;
    
    for (final doc in customersSnapshot!.docs) {
      final data = doc.data();
      if (data['deviceId'] != _deviceId) {
        await _applyCustomerChange(doc.id, data);
      }
      processedCustomers++;
      if (totalCustomers > 0) {
        final progress = (processedCustomers / totalCustomers) * 0.5;
        onProgress?.call(progress, 'تنزيل العملاء ($processedCustomers/$totalCustomers)...');
      }
    }
    // تنزيل المعاملات (50-85%)
    onProgress?.call(0.5, 'جاري تنزيل المعاملات...');
    final transactionsSnapshot = await _firestore!
        .collection('transactions')
        .get();

    final totalTransactions = transactionsSnapshot.docs.length;
    var processedTransactions = 0;

    for (final doc in transactionsSnapshot.docs) {
      final data = doc.data();
      if (data['deviceId'] != _deviceId) {
        await _applyTransactionChange(doc.id, data);
      }
      processedTransactions++;
      if (totalTransactions > 0) {
        final progress = 0.5 + ((processedTransactions / totalTransactions) * 0.35);
        onProgress?.call(progress, 'تنزيل المعاملات ($processedTransactions/$totalTransactions)...');
      }
    }

    // تنزيل الفواتير (85-100%).
    // تفويض كامل لمح محرك الفواتير: كل وثيقة تمرّ عبر مسار الاستقبال الإدمبوتنت
    // الذي يحترم version و creator_device_id، فلا تُكرَّر ولا تُستبدل نسخة أحدث.
    onProgress?.call(0.85, 'جاري تنزيل الفواتير والمنتجات...');
    try {
      await InvoiceSyncService().downloadAllInvoices(onProgress: (p, m) {
        onProgress?.call(0.85 + (p * 0.10), m);
      });
      await ProductSyncService().downloadAllProducts();
    } catch (e) {
      print('⚠️ فشل تنزيل الفواتير/المنتجات أثناء المزامنة الشاملة: $e');
    }

    onProgress?.call(1.0, 'تم تنزيل البيانات!');
    print('✅ تم تنزيل البيانات من Firebase');
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// أدوات مساعدة
  /// ═══════════════════════════════════════════════════════════════════════
  
  void _updateStatus(FirebaseSyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
    
    // 🛡️ إدارة مؤقت الاستقرار للتحقق المتبادل
    if (newStatus == FirebaseSyncStatus.online) {
      _startStabilityTimer();
    } else {
      _stopStabilityTimer();
    }
  }

  /// التدقيق التلقائي انتقل إلى ReconciliationService.startAutoAudit():
  /// يعمل عند سكون النظام لا بعد مدة اتصال ثابتة — التدقيق أثناء تدفق
  /// البيانات يكذب لأن معاملة في الطريق تُحسب نقصاً وهي ليست كذلك.
  void _startStabilityTimer() {}
  void _stopStabilityTimer() {
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    _isVerificationScheduled = false;
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔒 قيود صارمة للتحقق من البيانات ومنع التكرار
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// حساب checksum للبيانات
  String _calculateChecksum(Map<String, dynamic> data) {
    // إزالة الحقول المتغيرة (timestamps, deviceId)
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('uploadedAt');
    cleanData.remove('deviceId');
    cleanData.remove('lastModifiedAt');
    
    final jsonString = jsonEncode(cleanData);
    final bytes = utf8.encode(jsonString);
    return sha256.convert(bytes).toString().substring(0, 16);
  }
  
  /// التحقق من صحة البيانات قبل الرفع
  bool _validateCustomerData(Map<String, dynamic> data) {
    // التحقق من الحقول المطلوبة
    if (data['sync_uuid'] == null || (data['sync_uuid'] as String).isEmpty) {
      print('❌ العميل بدون sync_uuid');
      return false;
    }
    if (data['name'] == null || (data['name'] as String).isEmpty) {
      print('❌ العميل بدون اسم');
      return false;
    }
    return true;
  }
  bool _validateTransactionData(Map<String, dynamic> data) {
    if (data['sync_uuid'] == null || (data['sync_uuid'] as String).isEmpty) {
      print('❌ المعاملة بدون sync_uuid');
      return false;
    }
    if (data['customer_id'] == null) {
      print('❌ المعاملة بدون customer_id');
      return false;
    }
    if (data['amount_changed'] == null) {
      print('❌ المعاملة بدون مبلغ');
      return false;
    }
    return true;
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔍 التحقق من سلامة البيانات بعد المزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// التحقق من تطابق عدد السجلات
  Future<Map<String, dynamic>> verifyDataIntegrity() async {
    if (_groupId == null) {
      return {'error': 'غير مُعد', 'valid': false};
    }
    
    final db = await _db.database;
    final issues = <String>[];
    
    try {
      // عدد العملاء محلياً
      final localCustomers = await db.query(
        'customers',
        where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      // عدد العملاء في Firebase
      final remoteCustomersCount = await _firestore!
          .collection('customers')
          .where('isDeleted', isNotEqualTo: true)
          .count()
          .get();
      
      // عدد المعاملات محلياً
      final localTransactions = await db.query(
        'transactions',
        where: 'transaction_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      // عدد المعاملات في Firebase
      final remoteTransactionsCount = await _firestore!
          .collection('transactions')
          .where('isDeleted', isNotEqualTo: true)
          .count()
          .get();
      
      // التحقق من التطابق
      final localCustomerCount = localCustomers.length;
      final remoteCustomerCount = remoteCustomersCount.count ?? 0;
      final localTxCount = localTransactions.length;
      final remoteTxCount = remoteTransactionsCount.count ?? 0;
      
      if (localCustomerCount != remoteCustomerCount) {
        issues.add('عدد العملاء غير متطابق: محلي=$localCustomerCount، سحابي=$remoteCustomerCount');
      }
      
      
      if (localTxCount != remoteTxCount) {
        issues.add('عدد المعاملات غير متطابق: محلي=$localTxCount، سحابي=$remoteTxCount');
      }
      
      return {
        'valid': issues.isEmpty,
        'localCustomers': localCustomerCount,
        'remoteCustomers': remoteCustomerCount,
        'localTransactions': localTxCount,
        'remoteTransactions': remoteTxCount,
        'issues': issues,
        'checkedAt': DateTime.now().toIso8601String(),
      };
      
    } catch (e) {
      return {
        'valid': false,
        'error': e.toString(),
        'issues': ['فشل التحقق: $e'],
      };
    }
  }
  
  /// 🔍 التحقق من صحة الأرصدة بعد المزامنة
  /// يقارن الرصيد المسجل مع مجموع المعاملات لكل عميل
  Future<Map<String, dynamic>> verifyBalancesAfterSync() async {
    final db = await _db.database;
    final issues = <Map<String, dynamic>>[];
    
    try {
      // جلب جميع العملاء
      final customers = await db.query(
        'customers',
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );
      
      for (final customer in customers) {
        final customerId = customer['id'] as int;
        final customerName = customer['name'] as String? ?? 'غير معروف';
        final recordedBalance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
        
        // حساب الرصيد من المعاملات
        final sumResult = await db.rawQuery('''
          SELECT COALESCE(SUM(amount_changed), 0) as total
          FROM transactions
          WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
        ''', [customerId]);
        
        final calculatedBalance = (sumResult.first['total'] as num?)?.toDouble() ?? 0.0;
        
        // مقارنة الأرصدة (مع هامش خطأ صغير)
        final difference = (recordedBalance - calculatedBalance).abs();
        if (difference > 0.01) {
          issues.add({
            'customerId': customerId,
            'customerName': customerName,
            'recordedBalance': recordedBalance,
            'calculatedBalance': calculatedBalance,
            'difference': difference,
          });
          
          print('⚠️ فرق في رصيد العميل "$customerName": مسجل=$recordedBalance، محسوب=$calculatedBalance');
        }
      }
      
      if (issues.isEmpty) {
        print('✅ جميع الأرصدة صحيحة');
      } else {
        print('⚠️ وُجدت ${issues.length} فروقات في الأرصدة');
      }
      
      return {
        'hasIssues': issues.isNotEmpty,
        'issuesCount': issues.length,
        'issues': issues,
        'checkedAt': DateTime.now().toIso8601String(),
      };
      
    } catch (e) {
      print('❌ فشل التحقق من الأرصدة: $e');
      return {
        'hasIssues': false,
        'error': e.toString(),
        'issues': [],
      };
    }
  }
  
  /// إعادة تهيئة الخدمة (بعد تغيير المجموعة)
  Future<void> reinitialize() async {
    await _stopListening();
    _stopBackgroundSync(); // 🔄 إيقاف المزامنة الخلفية
    _isInitialized = false;
    _groupId = null;
    // 🔧 إعادة تعيين المنسق والخدمات لتجنب خطأ التهيئة المكررة
    _coordinator = null;
    _operationTracker = null;
    _ackService = null;
    _crashRecovery = null; // 🛡️ إعادة تعيين WAL
    await initialize();
  }
  
  /// الحصول على إحصائيات المزامنة مع دعم مؤشر التقدم
  Future<Map<String, dynamic>> getSyncStats({
    void Function(double progress, String message)? onProgress,
  }) async {
    print('📊 [getSyncStats] ════════════════════════════════════════');
    
    if (_groupId == null) {
      print('❌ [getSyncStats] _groupId is null - Firebase غير مهيأ!');
      return {'error': 'غير مُعد', 'valid': false};
    }
    
    // ✅ تشخيص حالة Firebase قبل البدء
    print('✅ [getSyncStats] GroupId: $_groupId');
    print('✅ [getSyncStats] DeviceId: $_deviceId');
    print('✅ [getSyncStats] Firestore instance: ${_firestore != null ? "موجود" : "NULL!"}');
    
    // ✅ فحص حالة المصادقة
    try {
      final currentUser = fauth.FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('❌ [getSyncStats] المستخدم غير مسجل دخول! FirebaseAuth.currentUser = null');
        print('❌ [getSyncStats] يجب تسجيل الدخول المجهول أولاً');
      } else {
        print('✅ [getSyncStats] المستخدم مسجل الدخول');
        print('✅ [getSyncStats] UID: ${currentUser.uid}');
        print('✅ [getSyncStats] isAnonymous: ${currentUser.isAnonymous}');
        print('✅ [getSyncStats] Token موجود: ${await currentUser.getIdToken() != null}');
      }
    } catch (e) {
      print('❌ [getSyncStats] خطأ في فحص حالة المصادقة: $e');
    }
    
    try {
      // 🚀 Always fetch fresh stats from Cloud to avoid trusting local cache

      int customersCountVal = 0;
      int transactionsCountVal = 0;
      int invoicesCountVal = 0;
      int productsCountVal = 0;

      try {
        print('🔍 [getSyncStats] محاولة قراءة customers.count()...');
        onProgress?.call(0.0, 'جاري تحميل بيانات العملاء...');
        final customersCount = await _firestore!.collection('customers').count().get();
        customersCountVal = customersCount.count ?? 0;
        print('✅ [getSyncStats] نجح قراءة العملاء: $customersCountVal');
        onProgress?.call(0.2, 'تم تحميل بيانات العملاء ✓');
      } catch (e) {
        print('❌ [getSyncStats] فشل قراءة العملاء!');
        print('❌ [getSyncStats] Error Type: ${e.runtimeType}');
        print('❌ [getSyncStats] Error: $e');
      }

      try {
        print('🔍 [getSyncStats] محاولة قراءة products.count()...');
        onProgress?.call(0.25, 'جاري تحميل بيانات المنتجات...');
        final productsCount = await _firestore!.collection('products').count().get();
        productsCountVal = productsCount.count ?? 0;
        print('✅ [getSyncStats] نجح قراءة المنتجات: $productsCountVal');
      } catch (e) {
        print('❌ [getSyncStats] فشل قراءة المنتجات: $e');
      }

      try {
        print('🔍 [getSyncStats] محاولة قراءة transactions.count()...');
        onProgress?.call(0.4, 'جاري تحميل بيانات المعاملات...');
        final transactionsCount = await _firestore!.collection('transactions').count().get();
        transactionsCountVal = transactionsCount.count ?? 0;
        print('✅ [getSyncStats] نجح قراءة المعاملات: $transactionsCountVal');
        
        print('🔍 [getSyncStats] محاولة قراءة invoices.count()...');
        onProgress?.call(0.55, 'جاري تحميل بيانات الفواتير...');
        final invoicesCount = await _firestore!.collection('invoices').count().get();
        invoicesCountVal = invoicesCount.count ?? 0;
        print('✅ [getSyncStats] نجح قراءة الفواتير: $invoicesCountVal');
        onProgress?.call(0.65, 'تم تحميل بيانات المعاملات والفواتير والمنتجات ✓');
      } catch (e) {
        print('❌ [getSyncStats] فشل قراءة المعاملات/الفواتير!');
        print('❌ [getSyncStats] Error Type: ${e.runtimeType}');
        print('❌ [getSyncStats] Error: $e');
      }
      
      // المرحلة 3: تحميل وقت آخر مزامنة (65% -> 80%)
      onProgress?.call(0.7, 'جاري تحميل معلومات المزامنة...');
      final lastSync = await FirebaseSyncConfig.getLastSyncTime();
      onProgress?.call(0.8, 'تم تحميل معلومات المزامنة ✓');
      
      // المرحلة 4: إحصائيات المنسق (80% -> 100%)
      onProgress?.call(0.85, 'جاري تحميل إحصائيات المنسق...');
      final coordStats = _coordinator != null ? await _coordinator!.getStats() : {};
      onProgress?.call(1.0, 'اكتمل التحميل!');
      
      return {
        'groupId': _groupId,
        'deviceId': _deviceId,
        'customersInCloud': customersCountVal,
        'productsInCloud': productsCountVal,
        'transactionsInCloud': transactionsCountVal,
        'invoicesInCloud': invoicesCountVal,
        'lastSync': lastSync?.toIso8601String(),
        'status': _status.name,
        'coordinatorStats': coordStats,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 📱 إدارة الأجهزة المتصلة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تسجيل هذا الجهاز في المجموعة
  Future<void> registerDevice({String? deviceName}) async {
    if (_groupId == null || _deviceId == null || _firestore == null) return;
    
    try {
      final now = DateTime.now();
      final name = deviceName ?? await _getDeviceName();
      
      _firestore!
          .collection('devices')
          .doc(_deviceId)
          .set({
            'deviceId': _deviceId,
            'deviceName': name,
            'platform': _platformLabel(),
            'lastSeen': DateTime.now().toIso8601String(),
            'registeredAt': now.toIso8601String(),
            'isOnline': true,
            'isListening': _isListening,
            'syncStatus': _status.name,
            'appVersion': '1.0.0',
            'groupSecret': _groupSecret,
          }, SetOptions(merge: true)).catchError((e) {
            print('⚠️ خطأ في تسجيل الجهاز بالسحابة: $e');
          });
      
      print('📱 تم تسجيل الجهاز: $name ($_deviceId)');
    } catch (e) {
      print('❌ فشل تسجيل الجهاز: $e');
    }
  }
  
  /// تحديث حالة الجهاز (نبضة قلب) مع معلومات تفصيلية
  Future<void> updateDeviceHeartbeat() async {
    if (_groupId == null || _deviceId == null || _firestore == null) return;
    
    try {
      _firestore!
          .collection('devices')
          .doc(_deviceId)
          .update({
            'lastSeen': DateTime.now().toIso8601String(),
            'isOnline': true,
            'isListening': _isListening, // هل يستمع للتغييرات الفورية
            'syncStatus': _status.name, // حالة المزامنة الحالية
          }).catchError((e) {
            // تجاهل الخطأ - قد يكون الجهاز غير مسجل بعد
          });
    } catch (e) {
      // تجاهل الخطأ - قد يكون الجهاز غير مسجل بعد
    }
  }
  
  /// تعليم الجهاز كغير متصل
  Future<void> markDeviceOffline() async {
    if (_groupId == null || _deviceId == null || _firestore == null) return;
    
    try {
      await _firestore!
          .collection('devices')
          .doc(_deviceId)
          .update({
            'isOnline': false,
            'isListening': false,
            'syncStatus': 'offline',
            'lastSeen': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      // تجاهل الخطأ
    }
  }
  
  /// جلب قائمة الأجهزة المتصلة في المجموعة
  Future<List<Map<String, dynamic>>> getConnectedDevices() async {
    if (_groupId == null || _firestore == null) {
      return [];
    }
    
    try {
      // 🚀 استخدام الكاش اللحظي إذا كان الاستماع فعالاً
      if (_isListening && _liveDevices.isNotEmpty) {
        return List<Map<String, dynamic>>.from(_liveDevices);
      }
      
      final snapshot = await _firestore!
          .collection('devices')
          .orderBy('lastSeen', descending: true)
          .get();
      
      final devices = <Map<String, dynamic>>[];
      // 🕰️ استخدام التوقيت المصحح بالسيرفر لتجنب مشاكل الساعة المحلية الخاطئة
      final correctedNow = this.now;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final lastSeen = data['lastSeen'];
        DateTime? lastSeenDate;
        
        if (lastSeen is Timestamp) {
          lastSeenDate = lastSeen.toDate();
        } else if (lastSeen is String) {
          lastSeenDate = DateTime.tryParse(lastSeen);
        }
        
        // اعتبار الجهاز متصلاً إذا كان آخر ظهور له خلال دقيقة واحدة (30 ثانية نبضة + هامش)
        final secondsSinceLastSeen = lastSeenDate != null 
            ? correctedNow.difference(lastSeenDate).inSeconds 
            : 9999;
        final isRecentlyActive = secondsSinceLastSeen < 60;
        
        // تحديد حالة الاتصال الفعلية
        final isOnline = data['isOnline'] == true && isRecentlyActive;
        final isListening = data['isListening'] == true && isRecentlyActive;
        final syncStatus = data['syncStatus'] as String? ?? 'unknown';
        
        // تحديد حالة المزامنة الفورية
        String realtimeSyncStatus;
        if (!isOnline) {
          realtimeSyncStatus = 'غير متصل';
        } else if (isListening && syncStatus == 'online') {
          realtimeSyncStatus = 'متصل ويستمع ✓';
        } else if (isOnline && !isListening) {
          realtimeSyncStatus = 'متصل (لا يستمع)';
        } else {
          realtimeSyncStatus = syncStatus;
        }
        
        devices.add({
          'deviceId': data['deviceId'] ?? doc.id,
          'deviceName': data['deviceName'] ?? 'جهاز غير معروف',
          'platform': data['platform'] ?? 'غير محدد',
          'lastSeen': lastSeenDate?.toIso8601String(),
          'lastSeenFormatted': _formatLastSeen(lastSeenDate),
          'secondsSinceLastSeen': secondsSinceLastSeen,
          'isOnline': isOnline,
          'isListening': isListening,
          'syncStatus': syncStatus,
          'realtimeSyncStatus': realtimeSyncStatus,
          'isRealtimeSyncActive': isOnline && isListening && syncStatus == 'online',
          'isCurrentDevice': doc.id == _deviceId,
          'registeredAt': data['registeredAt'],
          'appVersion': data['appVersion'],
        });
      }
      
      return devices;
    } catch (e) {
      print('❌ فشل جلب قائمة الأجهزة: $e');
      return [];
    }
  }
  
  /// حذف جهاز من المجموعة
  Future<bool> removeDevice(String deviceId) async {
    if (_groupId == null || _firestore == null) return false;
    
    // لا يمكن حذف الجهاز الحالي
    if (deviceId == _deviceId) {
      print('⚠️ لا يمكن حذف الجهاز الحالي');
      return false;
    }
    
    try {
      await _firestore!
          .collection('devices')
          .doc(deviceId)
          .delete();
      
      print('🗑️ تم حذف الجهاز: $deviceId');
      return true;
    } catch (e) {
      print('❌ فشل حذف الجهاز: $e');
      return false;
    }
  }
  /// الحصول على اسم الجهاز
  Future<String> _getDeviceName() async {
    try {
      // محاولة الحصول على اسم الكمبيوتر من متغيرات البيئة
      final computerName = const String.fromEnvironment('COMPUTERNAME', defaultValue: '');
      if (computerName.isNotEmpty) return computerName;
      
      // استخدام معرف الجهاز المختصر كاسم افتراضي
      return 'جهاز ${_deviceId?.substring(0, 8) ?? 'غير معروف'}';
    } catch (e) {
      return 'جهاز غير معروف';
    }
  }

  String _platformLabel() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return 'Unknown';
    }
  }
  
  /// تنسيق وقت آخر ظهور
  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'غير معروف';
    
    // 🕰️ استخدام التوقيت المصحح بالسيرفر
    final correctedNow = this.now;
    final diff = correctedNow.difference(lastSeen);
    
    if (diff.inSeconds < 60) {
      return 'الآن';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else if (diff.inDays < 7) {
      return 'منذ ${diff.inDays} يوم';
    } else {
      return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }
  
  /// معرف الجهاز الحالي
  String? get deviceId => _deviceId;
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔗 واجهة للتنسيق مع نظام Google Drive Sync
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// التحقق مما إذا كانت العملية مرفوعة على Firebase
  /// (يستخدمها نظام Google Drive لتجنب الرفع المكرر)
  Future<bool> isOperationSyncedToFirebase(String entityType, String syncUuid) async {
    return await _coordinator!.isFirebaseSynced(entityType, syncUuid);
  }
  
  /// الحصول على قائمة العمليات المرفوعة على Firebase
  /// (يستخدمها نظام Google Drive لتخطيها)
  Future<List<String>> getFirebaseSyncedUuids(String entityType) async {
    return await _coordinator!.getFirebaseSyncedUuids(entityType);
  }
  
  /// تسجيل عملية تم استلامها من Firebase
  /// (لإخبار نظام Google Drive أن لا يرفعها)
  Future<void> registerReceivedFromFirebase(String entityType, String syncUuid) async {
    await _coordinator!.registerOperation(
      entityType: entityType,
      syncUuid: syncUuid,
      source: SyncSource.firebase,
    );
    await _coordinator!.markFirebaseSynced(entityType, syncUuid);
  }
  
  /// هل المزامنة قيد التنفيذ؟
  bool get isSyncing => _isSyncing;
  
  /// هل هناك عمليات معلقة؟
  bool get hasPendingUploads => _uploadLocks.isNotEmpty;
  
  /// عدد العمليات المعلقة
  int get pendingUploadsCount => _uploadLocks.length;
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔄 واجهة نظام تتبع العمليات والإقرار
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// الحصول على إحصائيات تتبع العمليات
  Future<Map<String, dynamic>> getOperationTrackerStats() async {
    return await _operationTracker!.getStats();
  }
  
  /// الحصول على ملخص تأكيدات الاستلام
  Future<Map<String, dynamic>> getAckSummary() async {
    return await _ackService!.getAckSummary();
  }
  
  /// الحصول على المعاملات التي لم يتم تأكيد استلامها
  Future<List<String>> getPendingAckTransactions() async {
    return await _ackService!.getPendingAckTransactions();
  }
  
  /// تنظيف التأكيدات القديمة
  Future<int> cleanupOldAcks() async {
    return await _ackService!.cleanupOldAcks();
  }
  
  /// تنظيف سجلات العمليات القديمة
  Future<int> cleanupOldOperationLogs() async {
    return await _operationTracker!.cleanupOldLogs();
  }
  
  /// 🛡️ الحصول على إحصائيات WAL (الحماية من الانقطاع)
  Future<Map<String, dynamic>> getWalRecoveryStats() async {
    if (_crashRecovery == null) {
      return {'error': 'WAL غير مُهيأ'};
    }
    return await _crashRecovery!.getRecoveryStats();
  }
  
  /// 🛡️ الحصول على العمليات المعلقة في WAL
  Future<int> getPendingWalOperationsCount() async {
    if (_crashRecovery == null) return 0;
    final pending = await _crashRecovery!.getPendingUploads();
    return pending.length;
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔄 Retry Queue مع Exponential Backoff (محفوظ في قاعدة البيانات)
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// إضافة عملية للـ Retry Queue (في قاعدة البيانات)
  Future<void> _addToRetryQueue(_RetryOperation operation) async {
    final db = await _db.database;
    
    // التحقق من عدم وجودها مسبقاً
    final existing = await db.query(
      'sync_retry_queue',
      where: 'sync_uuid = ?',
      whereArgs: [operation.syncUuid],
    );
    
    
    if (existing.isNotEmpty) return;
    
    await db.insert(
      'sync_retry_queue',
      {
        'type': operation.type,
        'sync_uuid': operation.syncUuid,
        'data': jsonEncode(operation.data),
        'retry_count': operation.retryCount,
        'next_retry_time': operation.nextRetryTime.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    
    _scheduleRetry();
  }
  
  /// جدولة المحاولة التالية
  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    
    // جدولة فحص كل 30 ثانية
    _retryTimer = Timer(const Duration(seconds: 30), _processRetryQueue);
  }
  
  /// معالجة الـ Retry Queue (من قاعدة البيانات)
  Future<void> _processRetryQueue() async {
    if (!_isInitialized || _groupId == null) return;
    
    final db = await _db.database;
    final now = DateTime.now();// جلب العمليات الجاهزة للمحاولة
    final readyOps = await db.query(
      'sync_retry_queue',
      where: 'next_retry_time <= ?',
      whereArgs: [now.toIso8601String()],
      orderBy: 'next_retry_time ASC',
      limit: 10, // معالجة 10 عمليات كحد أقصى في كل مرة
    );
    
    for (final opRow in readyOps) {
      final syncUuid = opRow['sync_uuid'] as String;
      final type = opRow['type'] as String;
      final data = jsonDecode(opRow['data'] as String) as Map<String, dynamic>;
      var retryCount = opRow['retry_count'] as int;

      bool success = false;
      Object? error;

      try {
        if (type == 'customer') {
          success = await uploadCustomer(data);
        } else if (type == 'transaction') {
          final customerSyncUuid = data['customer_sync_uuid'] as String?;
          if (customerSyncUuid != null) {
            success = await uploadTransaction(data, customerSyncUuid);
          } else {
            // لا يمكن رفع معاملة بدون عميل — تبقى في الطابور حتى يصل العميل.
            success = false;
          }
        }
      } catch (e) {
        error = e;
        success = false;
      }

      // ✅ النجاح الحقيقي أو التخطي المقصود (مثل "مرفوعة مسبقًا"):
      // في الحالتين وصلت البيانات إلى السحابة أو سبق أن وصلت، فلا حاجة
      // لإبقائها في الطابور. نحذفها بأمان.
      if (success) {
        await db.delete(
          'sync_retry_queue',
          where: 'sync_uuid = ?',
          whereArgs: [syncUuid],
        );
        if (retryCount > 0) {
          print('✅ نجحت المحاولة رقم ${retryCount + 1} للعملية $syncUuid');
        }
        continue;
      }

      // ❌ الفشل الحقيقي: نُعيد المحاولة لا نهائيًا مع backoff آمن.
      // 🔒 أمان الحساب: لا نحذف العملية أبدًا — البيانات أغلى من الطابور.
      retryCount++;
      // Exponential Backoff محسوب بأمان من فيض int: min(2^retry, 300) ثانية.
      // بعد 8 محاولات نصل إلى الحد الأقصى (5 دقائق) ونثبّته هناك للأبد.
      final exponent = retryCount < 30 ? (1 << retryCount) : (1 << 30);
      final cappedMultiplier =
          exponent > 300 ? 300 : exponent; // الحد الأقصى 5 دقائق
      final backoffDelay = _baseRetryDelay * cappedMultiplier;
      final nextRetryTime = DateTime.now().add(backoffDelay);

      await db.update(
        'sync_retry_queue',
        {
          'retry_count': retryCount,
          'next_retry_time': nextRetryTime.toIso8601String(),
          'last_error': error?.toString() ?? 'فشل رفع بدون استثناء',
        },
        where: 'sync_uuid = ?',
        whereArgs: [syncUuid],
      );

      if (retryCount <= 5 || retryCount % 50 == 0) {
        print('🔄 سيتم إعادة المحاولة ${retryCount + 1} بعد '
            '${backoffDelay.inSeconds}ث للعملية $syncUuid');
      }
    }
    
    // جدولة المحاولة التالية إذا كان هناك عمليات متبقية
    final remaining = await db.rawQuery('SELECT COUNT(*) as count FROM sync_retry_queue');
    if ((remaining.first['count'] as int) > 0) {
      _scheduleRetry();
    }
  }
  
  /// تحميل Retry Queue عند بدء التشغيل
  Future<void> _loadRetryQueue() async {
    final db = await _db.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_retry_queue')
    ) ?? 0;

    if (count > 0) {
      print('📋 تم تحميل $count عملية من Retry Queue');
      _scheduleRetry();
    }
  }

  /// 📋 قراءة العمليات الفاشلة (العملاء والمعاملات) من Retry Queue.
  ///
  /// تُرجع قائمة بكل عملية معلّقة مع تفاصيلها: النوع (عميل/معاملة)، الاسم،
  /// المبلغ، عدد المحاولات، آخر خطأ، ووقت المحاولة التالية. تُستخدم لعرضها
  /// في زر "المعاملات الفاشلة".
  Future<List<Map<String, dynamic>>> getFailedSyncOperations() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_retry_queue',
      orderBy: 'next_retry_time ASC',
    );

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final type = row['type'] as String? ?? 'unknown';
      final syncUuid = row['sync_uuid'] as String? ?? '';
      final data = <String, dynamic>{};
      try {
        data.addAll(jsonDecode(row['data'] as String? ?? '{}')
            as Map<String, dynamic>);
      } catch (_) {}

      // استخراج وصف مفهوم للعملية من البيانات المخزّنة.
      String name = data['name'] as String? ?? '';
      double? amount;
      if (type == 'transaction') {
        amount = (data['amount_changed'] as num?)?.toDouble();
        if (name.isEmpty) {
          // محاولة جلب اسم العميل من customer_sync_uuid.
          final cSync = data['customer_sync_uuid'] as String?;
          if (cSync != null) {
            final cRows = await db.query('customers',
                columns: ['name'], where: 'sync_uuid = ?', whereArgs: [cSync], limit: 1);
            if (cRows.isNotEmpty) name = cRows.first['name'] as String? ?? '';
          }
        }
      }

      result.add({
        'type': type,
        'syncUuid': syncUuid,
        'name': name,
        'amount': amount,
        'retryCount': row['retry_count'] as int? ?? 0,
        'lastError': row['last_error'] as String?,
        'nextRetryTime': row['next_retry_time'] as String?,
        'createdAt': row['created_at'] as String?,
        'data': data,
      });
    }
    return result;
  }

  /// 🔢 عدد العمليات الفاشلة (للعرض السريع في الواجهة دون تحميل التفاصيل).
  Future<int> getFailedSyncOperationsCount() async {
    final db = await _db.database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sync_retry_queue'),
        ) ??
        0;
  }

  /// 🔁 محاولة إعادة رفع كل العمليات الفاشلة يدويًا (عند الضغط على زر "إعادة المحاولة").
  Future<Map<String, dynamic>> retryAllFailedOperations() async {
    final db = await _db.database;
    // تصفير next_retry_time لتُصبح جاهزة فورًا.
    await db.update(
      'sync_retry_queue',
      {'next_retry_time': DateTime.now().toIso8601String()},
    );
    // تشغيل معالجة الطابور.
    await _processRetryQueue();
    final remaining = await getFailedSyncOperationsCount();
    return {
      'success': remaining == 0,
      'remaining': remaining,
    };
  }

  /// 🗑️ حذف عملية فاشلة من الطابور (عند التخلي عنها يدويًا).
  Future<void> removeFailedOperation(String syncUuid) async {
    final db = await _db.database;
    await db.delete(
      'sync_retry_queue',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
    );
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🧹 تنظيف Firebase التلقائي
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تنظيف البيانات القديمة من Firebase
  Future<Map<String, dynamic>> cleanupOldFirebaseData() async {
    if (_isRepairing) {
      return {'error': 'ممنوع تنظيف السحابة أثناء الرفع الشامل'};
    }
    if (_groupId == null || _firestore == null) {
      return {'error': 'غير مُعد'};
    }

    // 🔒 تحويل آمن: هذا المسار كان يحذف المعاملات الأقدم من 7 أيام ثابتة
    // (متتجاهلاً إعدادات المستخدم وفحص قراءة الأجهزة). الحذف الآن يمر حصرياً
    // عبر SmartPipeCleanupService بشرطين: مدة المستخدم + قراءة الجميع (ACKs).
    print('🧹 cleanupOldFirebaseData: تحويل إلى الحذف الذكي الآمن (SmartPipe)...');
    final result = await SmartPipeCleanupService().runManualCleanup();
    return {
      'success': true,
      'deletedCustomers': result.deletedCustomers,
      'deletedTransactions': result.deletedTransactions,
      'skippedPendingRead': result.skippedPendingRead,
      'mode': 'smart_pipe_ack_gated',
    };
  }

  /// حذف قاعدة البيانات السحابية بالكامل
  Future<Map<String, dynamic>> clearCloudDatabase() async {
    if (_isRepairing) {
      return {
        'success': false,
        'error': 'ممنوع مسح السحابة أثناء الرفع الشامل',
      };
    }
    if (_firestore == null) {
      return {'error': 'غير مُعد'};
    }
    
    print('🧹 جاري حذف قاعدة البيانات السحابية بالكامل...');
    
    int totalDeleted = 0;
    
    try {
      final collections = [
        'transactions',
        'customers',
        'transaction_acks',
        'sync_operations',
        'devices',
        '_time_check'
      ];

      for (final collectionPath in collections) {
        bool hasMore = true;
        while (hasMore) {
          final query = await _firestore!
              .collection(collectionPath)
              .limit(500)
              .get();
              
          if (query.docs.isEmpty) {
            hasMore = false;
            break;
          }
          
          final batch = _firestore!.batch();
          for (final doc in query.docs) {
            batch.delete(doc.reference);
            totalDeleted++;
          }
          await batch.commit();
        }
      }
      print('✅ تم حذف $totalDeleted مستند بنجاح من جميع المجموعات');
      return {
        'success': true,
        'deletedCount': totalDeleted,
      };
    } catch (e) {
      print('❌ خطأ في حذف قاعدة البيانات: $e');
      return {'error': e.toString()};
    }
  }
  
  /// التحقق من حجم البيانات في Firebase
  Future<Map<String, dynamic>> checkFirebaseSize() async {
    if (_groupId == null) return {'error': 'غير مُعد'};
    
    try {
      final customersCount = await _firestore!
          .collection('customers')
          .count()
          .get();
      
      final transactionsCount = await _firestore!
          .collection('transactions')
          .count()
          .get();
      
      final totalCount = (customersCount.count ?? 0) + (transactionsCount.count ?? 0);
      final needsCleanup = totalCount > _maxFirebaseOperations;
      
      return {
        'customersCount': customersCount.count,
        'transactionsCount': transactionsCount.count,
        'totalCount': totalCount,
        'maxAllowed': _maxFirebaseOperations,
        'needsCleanup': needsCleanup,
        'usagePercent': (totalCount / _maxFirebaseOperations * 100).toStringAsFixed(1),
      };
      
    } catch (e) {
      return {'error': e.toString()};
    }
  }
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🕰️ تصحيح التوقيت (Server Time Offset)
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> _calculateServerTimeOffset() async {
    // 🔒 عُطّلت كتابة وثيقة القياس (_time_check) لأنها كانت السبب الرئيسي
    // لـ TimeoutException على Windows: الكتابة بـ FieldValue.serverTimestamp
    // تنتظر تأكيدًا من السيرفر لا يصل. تصحيح التوقيت تحسيني فقط (لعرض
    // "آخر ظهور" دقيق للأجهزة) وليس ضروريًا للمزامنة؛ التوقيت المحلي كافٍ.
    // إن احتجناه مستقبلًا، نقرأ lastSeen من وثيقة devices (بها serverTimestamp
    // من registerDevice) بدل كتابة وثيقة منفصلة.
    _serverTimeOffset = Duration.zero;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🚀 اختبار الاتصال الفعلي بـ Firestore
  /// ═══════════════════════════════════════════════════════════════════════
  ///
  /// نتأكد هنا أن الاتصال بـ Firestore يعمل وأن قواعد الأمان تسمح بالقراءة،
  /// قبل أن نكمل التهيئة ونفتح الـ Listeners.
  ///
  /// نعتمد على **القراءة** فقط (لا كتابة) لتجنّب TimeoutException على Windows
  /// التي كانت تنتظر تأكيد السيرفر على الكتابة فلا يصل. القراءة تكتفي
  /// بالبيانات المحلية/المخزّنة مؤقتًا وترجع سريعًا.
  ///
  /// ملاحظة: حتى لو فشل الاختبار (شبكة ضعيفة، قواعد أمان)، لا نوقف التهيئة
  /// تمامًا — الـ Listeners قد تنجح لاحقًا والمزامنة الخلفية ستعيد المحاولة.
  /// نكتفي بتسجيل التحذير حتى لا يظل التطبيق معطّلاً بسبب خطأ مؤقت.
  Future<bool> _testFirebaseConnectivity() async {
    if (_firestore == null) {
      print('❌ اختبار الاتصال: Firestore غير مهيأ');
      return false;
    }

    try {
      // محاولة قراءة وثيقة واحدة من مجموعة devices — موجودة دائمًا بعد
      // أول تسجيل جهاز. مهلة 20 ثانية كافية لأول اتصال.
      await _firestore!
          .collection('devices')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 20));

      print('✅ اختبار الاتصال بـ Firestore ناجح');
      return true;
    } catch (e) {
      print('❌ اختبار الاتصال بـ Firestore فشل: $e');
      // لا نوقف التهيئة: قد يكون فشلًا مؤقتًا، والمزامنة ستعيد المحاولة.
      return true;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 👻 معالجة المعاملات اليتيمة (Orphan Queue)
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> _createOrphanTable() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_orphans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_uuid TEXT NOT NULL,
        customer_sync_uuid TEXT NOT NULL,
        data TEXT NOT NULL,
        received_at TEXT NOT NULL,
        UNIQUE(sync_uuid)
      )
    ''');
    
    // فهرس للبحث السريع
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_orphans_customer 
      ON sync_orphans(customer_sync_uuid)
    ''');
    
    // 🔐 جدول Retry Queue (للحفظ الدائم)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_retry_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        sync_uuid TEXT NOT NULL,
        data TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        next_retry_time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_error TEXT,
        UNIQUE(sync_uuid)
      )
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_retry_next_time 
      ON sync_retry_queue(next_retry_time)
    ''');
  }

  Future<void> _addToOrphans(String syncUuid, Map<String, dynamic> data) async {
    final db = await _db.database;
    final customerSyncUuid = data['customerSyncUuid'] as String;
    
    // 🔒 لا سقف يحذف الأيتام. عند تهيئة جهاز جديد تصل آلاف المعاملات قبل
    // عملائها لأن المستمعَين يعملان بالتوازي، فحذف "الأقدم" هنا يعني إسقاط
    // معاملات حقيقية أثناء أول مزامنة بالذات. الطابور يُستنزف تلقائياً فور
    // وصول العملاء، فتراكمه مؤقت بطبيعته.
    final orphanCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_orphans')
    ) ?? 0;

    if (orphanCount > 0 && orphanCount % 500 == 0) {
      print('👻 $orphanCount معاملة تنتظر وصول عملائها');
    }
    
    // 🔧 إصلاح: تحويل Timestamp إلى String قبل jsonEncode
    final cleanData = _convertTimestampsToStrings(data);
    
    await db.insert(
      'sync_orphans',
      {
        'sync_uuid': syncUuid,
        'customer_sync_uuid': customerSyncUuid,
        'data': jsonEncode(cleanData),
        'received_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    print('👻 تم إضافة معاملة يتيمة للطابور: $syncUuid (العميل: $customerSyncUuid)');
  }
  
  /// 🔧 تحويل Timestamp من Firebase إلى String
  Map<String, dynamic> _convertTimestampsToStrings(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is Timestamp) {
        result[entry.key] = value.toDate().toIso8601String();
      } else if (value is Map<String, dynamic>) {
        result[entry.key] = _convertTimestampsToStrings(value);
      } else if (value is List) {
        result[entry.key] = value.map((item) {
          if (item is Timestamp) {
            return item.toDate().toIso8601String();
          } else if (item is Map<String, dynamic>) {
            return _convertTimestampsToStrings(item);
          }
          return item;
        }).toList();
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  /// مجموع معاملات العميل — المصدر الوحيد للحقيقة بشأن رصيده.
  Future<double> _sumTransactions(DatabaseExecutor txn, int customerId) async {
    final row = await txn.rawQuery(
      'SELECT COALESCE(SUM(amount_changed), 0) AS total FROM transactions '
      'WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      [customerId],
    );
    return (row.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> _processOrphans(int customerId, String customerSyncUuid) async {
    final db = await _db.database;
    
    // البحث عن معاملات لهذا العميل
    final orphans = await db.query(
      'sync_orphans',
      where: 'customer_sync_uuid = ?',
      whereArgs: [customerSyncUuid],
    );
    
    if (orphans.isEmpty) return;
    
    print('👻 تم العثور على ${orphans.length} معاملة يتيمة للعميل $customerSyncUuid');
    
    for (final orphan in orphans) {
      try {
        final data = jsonDecode(orphan['data'] as String) as Map<String, dynamic>;
        final syncUuid = orphan['sync_uuid'] as String;
        
        // محاولة تطبيق المعاملة الآن
        await _applyTransactionChange(syncUuid, data);
        
        // حذف من الطابور بعد النجاح
        await db.delete(
          'sync_orphans',
          where: 'sync_uuid = ?',
          whereArgs: [syncUuid],
        );
        
      } catch (e) {
        print('❌ فشل معالجة المعاملة اليتيمة: $e');
      }
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔧 إصلاح وتعيين sync_uuid للمعاملات القديمة + الرفع الشامل
  /// النسخة البسيطة الموثوقة: إصلاح المعرّفات ثم رفع فقط (بدون حذف).
  /// ═══════════════════════════════════════════════════════════════════════

  bool _isRepairing = false;

  /// زر الرفع الشامل — منطق بسيط كما في النسخة المستقرة:
  /// 1) إصلاح sync_uuid الناقص
  /// 2) رفع كل العملاء
  /// 3) رفع كل معاملات هذا الجهاز (حتى المرفوعة مسبقاً)
  /// لا يحذف أي معاملة محلياً ولا من السحابة.
  Future<Map<String, dynamic>> repairAndSyncAllTransactions({
    Function(int current, int total, String message)? onProgress,
  }) async {
    if (_isRepairing) {
      print('⚠️ عملية الإصلاح قيد التنفيذ بالفعل، يرجى الانتظار');
      return {'success': false, 'error': 'عملية إصلاح أخرى قيد التنفيذ'};
    }

    if (!_isInitialized || _groupId == null) {
      return {'success': false, 'error': 'المزامنة غير مُعدة'};
    }

    _isRepairing = true;
    DatabaseService.blockTransactionDeletes = true;
    _watchdog?.pause();
    await _stopListening();

    try {
      return await _repairAndSyncAllTransactionsInternal(onProgress: onProgress);
    } finally {
      _isRepairing = false;
      DatabaseService.blockTransactionDeletes = false;
      _watchdog?.resume();
      if (!_isListening) await _startListening();
    }
  }

  Future<Map<String, dynamic>> _repairAndSyncAllTransactionsInternal({
    Function(int current, int total, String message)? onProgress,
  }) async {
    final db = await _db.database;
    int fixedCount = 0;
    int uploadedCustomers = 0;
    int uploadedTransactions = 0;
    int errorCount = 0;

    print('🔧 بدء إصلاح ومزامنة جميع البيانات (الرفع الشامل البسيط)...');
    print('🔒 الرفع الشامل ممنوع من حذف أي معاملة');
    onProgress?.call(0, 100, 'جاري البدء...');
    
    if (_watchdog != null) {
      _watchdog!.pause();
      // ⏳ انتظار قليل حتى تكتمل أي عمليات رفع معلقة للـ Watchdog قبل بدء الهجوم الشامل لتجنب الاختناق
      await Future.delayed(const Duration(seconds: 3));
    }

    final txCountBefore = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM transactions')) ??
        0;

    try {
      // 1️⃣ إصلاح المعاملات التي ليس لها sync_uuid
      final transactionsWithoutUuid = await db.query(
        'transactions',
        where:
            "(transaction_uuid IS NULL OR transaction_uuid = '') AND (is_deleted IS NULL OR is_deleted = 0)",
      );

      for (var i = 0; i < transactionsWithoutUuid.length; i++) {
        final tx = transactionsWithoutUuid[i];
        if (i % 50 == 0) {
          onProgress?.call(
            i,
            transactionsWithoutUuid.length,
            'جاري إصلاح المعاملات (${i + 1}/${transactionsWithoutUuid.length})...',
          );
        }

        final existingUuid = tx['transaction_uuid'] as String?;
        String uuid;
        if (existingUuid != null &&
            existingUuid.isNotEmpty &&
            SyncSecurity.isValidDocumentId(existingUuid)) {
          uuid = existingUuid;
        } else {
          final customerRows = await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [tx['customer_id']], limit: 1);
          final customerName = customerRows.isNotEmpty ? customerRows.first['name'] as String : 'unknown';
          final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
          final dateStr = tx['transaction_date'] as String?;
          final date = dateStr != null ? DateTime.tryParse(dateStr) ?? DateTime.now() : DateTime.now();
          uuid = SyncSecurity.generateTransactionUuid(customerName, amount, date);
        }

        int suffix = 1;
        final base = uuid;
        while (true) {
          final clash = await db.query(
            'transactions',
            columns: ['id'],
            where: 'transaction_uuid = ? AND id != ?',
            whereArgs: [uuid, tx['id']],
            limit: 1,
          );
          if (clash.isEmpty) break;
          uuid = '${base}_$suffix';
          suffix++;
        }

        await db.update(
          'transactions',
          {
            'sync_uuid': uuid,
            'transaction_uuid': uuid,
          },
          where: 'id = ?',
          whereArgs: [tx['id']],
        );
        fixedCount++;
      }

      if (fixedCount > 0) {
        print('✅ تم إصلاح $fixedCount معاملة بدون sync_uuid');
      }

      // 2️⃣ إصلاح العملاء الذين ليس لهم sync_uuid
      final customersWithoutUuid = await db.query(
        'customers',
        where: 'sync_uuid IS NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );

      for (final customer in customersWithoutUuid) {
        String uuid = UuidHelper.sanitizeId(
            'cust_${SyncSecurity.generateUuid()}');
        int suffix = 1;
        final base = uuid;
        while (true) {
          final clash = await db.query(
            'customers',
            columns: ['id'],
            where: 'sync_uuid = ? AND id != ?',
            whereArgs: [uuid, customer['id']],
            limit: 1,
          );
          if (clash.isEmpty) break;
          uuid = '${base}_$suffix';
          suffix++;
        }
        await db.update(
          'customers',
          {'sync_uuid': uuid},
          where: 'id = ?',
          whereArgs: [customer['id']],
        );
      }

      if (customersWithoutUuid.isNotEmpty) {
        print('✅ تم إصلاح ${customersWithoutUuid.length} عميل بدون sync_uuid');
      }

      // 3️⃣ رفع جميع العملاء
      final allCustomers = await db.query(
        'customers',
        where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0) AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
      );
      final totalCustomers = allCustomers.length;
      print('📤 جاري رفع $totalCustomers عميل...');
      onProgress?.call(0, totalCustomers, 'جاري رفع العملاء...');

      const chunkSize = 1;
      
      for (var i = 0; i < allCustomers.length; i += chunkSize) {
        final chunk = allCustomers.skip(i).take(chunkSize).toList();

        // 🔒 timeout لكل عملية رفع حتى لا تتعلق الدفعة بأكملها إلى الأبد لو
        // الشبكة بطيئة. كل عميل له 15 ثانية كحد أقصى؛ من لم يُرفع يُحسب كخطأ
        // ونكمل الباقي (لا نتوقف عند أول فشل).
        final results = await Future.wait(
          chunk.map((customer) async {
            final name = customer['name'] as String? ?? 'غير معروف';
            try {
              if (!isOnline) {
                print('❌ فشل رفع عميل $name: لا يوجد اتصال بالإنترنت');
                return 0; // Failure
              }
              await _forceUploadCustomer(customer)
                  .timeout(const Duration(seconds: 60));
              return 1; // Success
            } catch (e) {
              print('❌ فشل رفع عميل $name: $e');
              return 0; // Failure
            }
          }),
          eagerError: false, // لا تتوقف عند أول خطأ — ارفع الباقي.
        );

        uploadedCustomers += results.fold<int>(0, (sum, val) => sum + val);
        final failedInChunk = chunk.length - results.fold<int>(0, (sum, val) => sum + val);
        errorCount += failedInChunk;

        final currentProgress = (i + chunkSize > totalCustomers) ? totalCustomers : i + chunkSize;
        onProgress?.call(currentProgress, totalCustomers, 'رفع العملاء ($currentProgress/$totalCustomers)...');
      }

      // 4️⃣ رفع معاملات هذا الجهاز فقط (حتى لو is_uploaded = 1)
      final allTransactions = await db.query(
        'transactions',
        where: 'transaction_uuid IS NOT NULL '
            'AND (is_deleted IS NULL OR is_deleted = 0) '
            'AND (is_created_by_me IS NULL OR is_created_by_me = 1)',
      );
      final totalTx = allTransactions.length;
      print('📤 جاري رفع $totalTx معاملة مملوكة لهذا الجهاز...');
      onProgress?.call(0, totalTx, 'جاري رفع المعاملات...');

      for (var i = 0; i < allTransactions.length; i += chunkSize) {
        final chunk = allTransactions.skip(i).take(chunkSize).toList();

        final results = await Future.wait(
          chunk.map((tx) async {
            try {
              if (!isOnline) {
                print('❌ فشل رفع معاملة: لا يوجد اتصال بالإنترنت');
                return 0; // Failure
              }
              final customerId = tx['customer_id'] as int;
              final customerResult = await db.query(
                'customers',
                columns: ['sync_uuid'],
                where: 'id = ?',
                whereArgs: [customerId],
                limit: 1,
              );
              if (customerResult.isEmpty) {
                return 0; // Failure
              }
              final customerSyncUuid = customerResult.first['sync_uuid'] as String?;
              if (customerSyncUuid == null || customerSyncUuid.isEmpty) {
                return 0; // Failure
              }

              // 🔒 timeout لكل معاملة حتى لا تتعلق الدفعة.
              await _forceUploadTransaction(tx, customerSyncUuid)
                  .timeout(const Duration(seconds: 60));
              return 1; // Success
            } catch (e) {
              print('❌ فشل رفع معاملة: $e');
              return 0; // Failure
            }
          }),
          eagerError: false,
        );

        uploadedTransactions += results.fold<int>(0, (sum, val) => sum + val);
        final failedInChunk = chunk.length - results.fold<int>(0, (sum, val) => sum + val);
        errorCount += failedInChunk;

        final currentProgress = (i + chunkSize > totalTx) ? totalTx : i + chunkSize;
        onProgress?.call(currentProgress, totalTx, 'رفع معاملات ($currentProgress/$totalTx)...');
      }

      final txCountAfter = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM transactions')) ??
          0;
      if (txCountAfter < txCountBefore) {
        return {
          'success': false,
          'error':
              'توقف: نقص عدد المعاملات من $txCountBefore إلى $txCountAfter. الرفع الشامل ممنوع من الحذف.',
          'fixed': fixedCount,
          'uploadedCustomers': uploadedCustomers,
          'uploadedTransactions': uploadedTransactions,
          'errors': errorCount,
        };
      }

      print('═══════════════════════════════════════════════════════════════════');
      print('✅ اكتمل الإصلاح والمزامنة (الرفع الشامل البسيط)');
      print('   - معاملات تم إصلاح معرّفها: $fixedCount');
      print('   - عملاء تم رفعهم: $uploadedCustomers / $totalCustomers');
      print('   - معاملات تم رفعها: $uploadedTransactions / $totalTx');
      print('   - أخطاء: $errorCount');
      print('   - عدد المعاملات قبل/بعد: $txCountBefore → $txCountAfter');
      print('═══════════════════════════════════════════════════════════════════');

      // 🕒 تحديث وقت آخر مزامنة
      await FirebaseSyncConfig.setLastSyncTime(DateTime.now());

      onProgress?.call(100, 100, 'اكتمل الرفع الشامل');

      return {
        'success': errorCount == 0,
        'fixed': fixedCount,
        'uploadedCustomers': uploadedCustomers,
        'totalCustomers': totalCustomers,
        'uploadedTransactions': uploadedTransactions,
        'expectedTransactions': totalTx,
        'errors': errorCount,
        'txCountBefore': txCountBefore,
        'txCountAfter': txCountAfter,
      };
    } catch (e) {
      print('❌ فشل الإصلاح والمزامنة: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// رفع عميل بالقوة (النسخة البسيطة — بدون تحقق سيرفر ثقيل).
  /// 🔒 أي فشل (timeout أو خطأ شبكة) يُسجَّل في Retry Queue حتى يظهر في
  /// زر "المعاملات الفاشلة" ويُعاد رفعه تلقائيًا لاحقًا.
  Future<void> _forceUploadCustomer(Map<String, dynamic> customerData) async {
    if (_groupId == null) return;

    final syncUuid = customerData['sync_uuid'] as String?;
    if (syncUuid == null || syncUuid.isEmpty) return;
    if (!SyncSecurity.isValidDocumentId(syncUuid)) {
      print('❌ تخطي رفع عميل بمعرّف غير صالح: $syncUuid');
      return;
    }

    if (!_rateLimiter.canProceed()) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _rateLimiter.recordOperation();

    final checksum = _calculateChecksum(customerData);
    final bool isCustDeleted = ((customerData['is_deleted'] as int?) ?? 0) == 1;

    try {
      await _firestore!
          .collection('customers')
          .doc(syncUuid)
          .set({
        'syncUuid': syncUuid,
        'name': customerData['name'],
        'phone': customerData['phone'],
        'currentTotalDebt': isCustDeleted ? 0.0 : customerData['current_total_debt'],
        'generalNote': customerData['general_note'],
        'address': customerData['address'],
        'createdAt': customerData['created_at'],
        'lastModifiedAt':
            customerData['last_modified_at'] ?? DateTime.now().toIso8601String(),
        'audioNotePath': customerData['audio_note_path'],
        'isDeleted': isCustDeleted,
        'is_deleted': isCustDeleted ? 1 : 0,
        'deviceId': _deviceId,
        'originDeviceId': _deviceId,
        'checksum': checksum,
        'groupSecret': _groupSecret,
        'uploadedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 60));

      final db = await _db.database;
      await db.rawUpdate(
        'UPDATE customers SET synced_at = ? WHERE sync_uuid = ?',
        [DateTime.now().toIso8601String(), syncUuid],
      );
    } catch (e) {
      // 🔌 سجّل الفشل في Retry Queue حتى يظهر في "المعاملات الفاشلة" ويُعاد
      // رفعه تلقائيًا، بدل أن يضيع العميل بصمت.
      await _addToRetryQueue(_RetryOperation(
        type: 'customer',
        syncUuid: syncUuid,
        data: customerData,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
      rethrow; // أعد رمي الاستثناء ليُسجّله الـ caller كخطأ.
    }
  }

  /// رفع معاملة بالقوة — معاملات هذا الجهاز فقط، بلا حذف محلي.
  /// 🔒 أي فشل يُسجَّل في Retry Queue أيضًا.
  Future<void> _forceUploadTransaction(
    Map<String, dynamic> txData,
    String customerSyncUuid,
  ) async {
    if (_groupId == null) return;

    final syncUuid = txData['transaction_uuid'] as String?;
    if (syncUuid == null || syncUuid.isEmpty) return;
    if (!SyncSecurity.isValidDocumentId(syncUuid)) {
      print('❌ تخطي رفع معاملة بمعرّف غير صالح: $syncUuid');
      return;
    }

    final owned = txData['is_created_by_me'];
    if (owned != null && owned == 0) {
      print('🚫 رُفض رفع معاملة من المزامنة: $syncUuid');
      return;
    }

    if (!_rateLimiter.canProceed()) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _rateLimiter.recordOperation();

    final checksum = _calculateChecksum(txData);
    final bool isTxDeleted = ((txData['is_deleted'] as int?) ?? 0) == 1;

    try {
      await _firestore!
          .collection('transactions')
          .doc(syncUuid)
          .set({
        'syncUuid': syncUuid,
        'customerSyncUuid': customerSyncUuid,
        'transactionDate': txData['transaction_date'],
        'amountChanged': txData['amount_changed'],
        'balanceBeforeTransaction': txData['balance_before_transaction'],
        'newBalanceAfterTransaction': txData['new_balance_after_transaction'],
        'transactionNote': txData['transaction_note'],
        'transactionType': txData['transaction_type'],
        'description': txData['description'],
        'createdAt': txData['created_at'],
        'lastModifiedAt': DateTime.now().toIso8601String(),
        'audioNotePath': txData['audio_note_path'],
        'isDeleted': isTxDeleted,
        'is_deleted': isTxDeleted ? 1 : 0,
        'deviceId': _deviceId,
        'originDeviceId': _deviceId,
        'checksum': checksum,
        'groupSecret': _groupSecret,
        'uploadedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 60));

      // تعليم محلي فقط — لا حذف ولا تعديل مبلغ.
      final db = await _db.database;
      final localId = txData['id'];
      if (localId is int) {
        await db.rawUpdate(
          'UPDATE transactions SET is_uploaded = 1 WHERE id = ?',
          [localId],
        );
      } else {
        await db.rawUpdate(
          'UPDATE transactions SET is_uploaded = 1 WHERE transaction_uuid = ?',
          [syncUuid],
        );
      }
    } catch (e) {
      // 🔌 سجّل الفشل في Retry Queue حتى يظهر في "المعاملات الفاشلة" ويُعاد
      // رفعه تلقائيًا، بدل أن تضيع المعاملة بصمت.
      final retryData = Map<String, dynamic>.from(txData);
      retryData['customer_sync_uuid'] = customerSyncUuid;
      await _addToRetryQueue(_RetryOperation(
        type: 'transaction',
        syncUuid: syncUuid,
        data: retryData,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
      rethrow;
    }
  }

  /// توافق مع الشاشات التي تنتظر bool.
  Future<bool> _forceUploadCustomerWithResult(
      Map<String, dynamic> customerData) async {
    try {
      await _forceUploadCustomer(customerData);
      return true;
    } catch (e) {
      print('❌ فشل رفع العميل: $e');
      return false;
    }
  }

  Future<bool> _forceUploadTransactionWithResult(
    Map<String, dynamic> txData,
    String customerSyncUuid,
  ) async {
    try {
      await _forceUploadTransaction(txData, customerSyncUuid);
      return true;
    } catch (e) {
      print('❌ فشل رفع المعاملة: $e');
      return false;
    }
  }

  /// إعادة رفع قسرية لمعاملة يملكها هذا الجهاز فقط — لشاشة المطابقة.
  Future<bool> forceReuploadOwnedTransaction(String syncUuid) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT t.*, c.sync_uuid AS customer_sync_uuid
      FROM transactions t
      JOIN customers c ON c.id = t.customer_id
      WHERE t.sync_uuid = ?
      LIMIT 1
    ''', [syncUuid]);
    if (rows.isEmpty) return false;

    final tx = Map<String, dynamic>.from(rows.first);
    final owned = tx['is_created_by_me'];
    if (owned != null && owned == 0) {
      print('🚫 رُفضت إعادة الرفع: المعاملة $syncUuid ليست من إنشاء هذا الجهاز');
      return false;
    }

    final customerUuid = tx['customer_sync_uuid'] as String?;
    if (customerUuid == null || customerUuid.isEmpty) return false;

    try {
      await _forceUploadTransaction(tx, customerUuid);
      return true;
    } catch (e) {
      print('❌ فشل إعادة رفع المعاملة: $e');
      return false;
    }
  }

}

/// ═══════════════════════════════════════════════════════════════════════════
/// عملية في انتظار إعادة المحاولة
/// ═══════════════════════════════════════════════════════════════════════════
class _RetryOperation {
  final String type; // 'customer' أو 'transaction'
  final String syncUuid;
  final Map<String, dynamic> data;
  int retryCount;
  DateTime nextRetryTime;
  
  _RetryOperation({
    required this.type,
    required this.syncUuid,
    required this.data,
    this.retryCount = 0,
    DateTime? nextRetryTime,
  }) : nextRetryTime = nextRetryTime ?? DateTime.now();
}
