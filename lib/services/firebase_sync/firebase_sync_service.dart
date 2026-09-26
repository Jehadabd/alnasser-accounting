// lib/services/firebase_sync/firebase_sync_service.dart
// خدمة المزامنة الفورية عبر Firebase - Offline-First
// مع قيود صارمة لحل التعارضات ومنع التكرار

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as fauth; // 🔐 Firebase Auth

import '../database_service.dart';
import '../database/core/database_helpers.dart';
import '../database/business/customer_visibility.dart';
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
import 'stock_movement_sync_service.dart'; // 📦 دفتر المخزون المشترك
import 'reconciliation_service.dart'; // 🧮 المطابقة بين الأجهزة
import 'armored_reconciliation_service.dart'; // 🛡️ المطابقة المحصّنة مغلقة الحلقة
import 'live_match_service.dart'; // 📡 مطابقة حية جهاز↔جهاز
import 'smart_pipe_cleanup_service.dart'; // 🧹 الحذف الذكي بشرط قراءة الجميع
import 'match_verdict_service.dart'; // ⚖️ بثّ قرارات المطابقة للمجموعة
import 'sync_diagnostics.dart'; // 🩺 تشخيص المصادقة/المزامنة
import 'web_auth_clear.dart'; // 🧹 تنظيف مخزن جلسة الويب التالف
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleListener; // 🌅 خطاف العودة للحياة
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
  // 🛡️ الحد القديم (120/دقيقة، 1000/ساعة) كان يجعل رفع يوم عمل أوفلاين
  // (1500 معاملة) يستغرق أكثر من ساعة، ويُشلّ الرفع كله ساعةً عند أي عاصفة.
  // والعملية المحجوبة كانت تُعاد كـ«نجاح» فتُحذف من طابور الإعادة.
  final SyncRateLimiter _rateLimiter = SyncRateLimiter(
    maxOperationsPerMinute: 600,
    maxOperationsPerHour: 20000,
  );

  // 🛡️ وضع الاستعادة: قاعدة البيانات استُعيدت من نسخة احتياطية. لا نرفع
  // شيئاً منها حتى نطلب ما فاتها من الأجهزة الأخرى ونقارن نسخنا بالسحابة.
  bool _recoveryMode = false;
  bool _bootstrapping = false;

  /// تمهيد جهاز جديد بدأ ولم يكتمل (لا مستجيب/انقطاع): تعيده الدورة الخلفية.
  /// كان يُعاد عند التشغيل التالي للتطبيق فقط، وحتى ذلك الحين ينقص الجهازَ
  /// كلُّ ما نظّفه SmartPipe من السحابة.
  bool _bootstrapIncomplete = false;
  bool get isRecovering => _recoveryMode;
  
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
    // نفس توجيه المستمع: مستندي أنا يُعالَج كمستندي (لا يُدرَج كمعاملة جهاز آخر)
    if (data['deviceId'] == _deviceId) {
      await _handleOwnTxDoc(syncUuid, data);
      return;
    }
    await _applyTransactionChange(syncUuid, data);
  }

  /// تطبيق وثيقة عميل وردت من السحابة — نفس مسار الاستقبال المعتاد.
  Future<void> applyRemoteCustomer(
      String syncUuid, Map<String, dynamic> data) async {
    if (data['deviceId'] == _deviceId) {
      await _handleOwnCustomerDoc(syncUuid, data);
      return;
    }
    await _applyCustomerChange(syncUuid, data);
  }
  /// ═══════════════════════════════════════════════════════════════════════
  /// التهيئة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تهيئة خدمة المزامنة
  /// تهيئة جارية: استدعاء ثانٍ أثناءها يعيد نفس العملية.
  Future<bool>? _initInFlight;

  /// 🛡️ لا تهيئتان متوازيتان. التهيئة قد تطول (رفع معلّق أثناء انقطاع
  /// الشبكة)، وعودة الاتصال أو مؤقت إعادة المحاولة كانا يبدآن تهيئة ثانية
  /// فوقها: مستمعون وخدمات مزدوجة تعالج نفس المستند مرتين في آن واحد
  /// (اختبار الكود الحقيقي: test/sync_harness).
  Future<bool> initialize({
    void Function(double progress, String message)? onProgress,
  }) {
    if (_isInitialized) {
      onProgress?.call(1.0, 'تم التهيئة مسبقاً');
      return Future.value(true);
    }
    final inFlight = _initInFlight;
    if (inFlight != null) return inFlight;
    final f = _initializeImpl(onProgress: onProgress);
    _initInFlight = f;
    return f.whenComplete(() => _initInFlight = null);
  }

  Future<bool> _initializeImpl({
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
      // 🌅 خطاف العودة للتطبيق (iOS/PWA: إنعاش فوري بعد القفل/الخلفية)
      _startLifecycleHook();
    
    try {
      // 🚪 Auth-Gate الصارم: لا مستمعي Firestore ولا أي اتصال قبل توكن ناجح.
      // (الفحص اللحظي السابق isAuthenticated كان السباق المسبب لفشل PWA:
      // currentUser=null لبرهة في iOS رغم جلسة قائمة في IndexedDB).
      onProgress?.call(0.05, 'بوابة المصادقة: انتظار جلسة صالحة...');
      final gateOk = await _waitForValidAuthToken();
      if (!gateOk) {
        print('❌ [AuthGate] تعذّر تأمين جلسة مصادقة - لا مزامنة الآن');
        SyncDiagnostics.log('auth', 'بوابة المصادقة رفضت المرور — إعادة محاولة مجدولة');
        _updateStatus(FirebaseSyncStatus.offline);
        _errorController.add('فشل المصادقة: تعذر تأمين جلسة صالحة (ستتم إعادة المحاولة)');
        _initFailureRetryable = true;
        _scheduleInitRetry();
        return false;
      }
      print('✅ [AuthGate] المصادقة مؤمّنة بتوكن حي: ${fauth.FirebaseAuth.instance.currentUser?.uid}');
      
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

      // 🛡️ هل استُعيدت قاعدة البيانات من نسخة احتياطية منذ آخر تشغيل؟
      await _loadRecoveryState();
      
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
          // TimeoutException.
          //
          // 🌐 وعلى الويب نعطّلها أيضاً: تفتح قاعدة IndexedDB ثانية (إلى جانب
          // مخزن جلسة المصادقة) وتأخذ «عقد ملكية» عليها. وiOS يقتل الـ PWA بلا
          // إغلاق نظيف، فيبقى سجل المالك من الجلسة السابقة ويتعذّر انتزاع
          // العقد عند التشغيل التالي — وهو أحد سببَي فشل المزامنة من المرة
          // الثانية فصاعداً على الآيفون.
          //
          // ولا نخسر شيئاً بتعطيلها: التخزين المحلي هنا SQLite (WASM) وليس
          // ذاكرة Firestore المؤقتة. فـ Firestore على الويب يعمل من الشبكة
          // مباشرةً، وهو المطلوب تماماً من المزامنة.
          final usePersistence = !isDesktop && !kIsWeb;

          _firestore!.settings = Settings(
            persistenceEnabled: usePersistence,
            cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          );
          _firestoreSettingsApplied = true;
          print('⚙️ إعدادات Firestore: persistenceEnabled=$usePersistence '
              '(${kIsWeb ? "Web — معطّلة لتفادي تعليق IndexedDB على iOS/PWA" : isDesktop ? "Desktop — معطّلة لحل تعليق الكتابة" : "Mobile — مفعّلة لدعم offline"})');
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

      // 📦 حركات المخزون (شراء، تعديل يدوي، رصيد افتتاحي) — بعد الكتالوج
      try {
        await StockMovementSyncService().start();
      } catch (e) {
        print('⚠️ تعذّر بدء مزامنة حركات المخزون: $e');
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

      // 🆕 الاستماع لطلبات الأجهزة الجديدة (هذا الجهاز قد يكون هو المُجيب)
      try {
        await startBootstrapResponder();
      } catch (e) {
        print('⚠️ تعذّر بدء الاستماع لطلبات التمهيد: $e');
      }

      // 🆕 وإن كنتُ أنا الجهاز الجديد، أطلب دفتر المجموعة.
      // يعمل في الخلفية حتى لا يحجز إقلاع التطبيق عشر دقائق.
      unawaited(ensureNewDeviceBootstrap());
      
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

      // 🛡️ رفع المعلّق والسحب الكامل فعلياً: الاستدعاءان أعلاه (قبل
      // _isInitialized = true) كانا يعودان فوراً دون عمل، فتعديلات أوفلاين لا
      // تُرفع عند الإقلاع، وشواهد الحذف التي فاتت المستمع لا تُسحب.
      unawaited(() async {
        try {
          await _syncPendingChanges();
        } catch (e) {
          print('⚠️ رفع المعلّق بعد التهيئة: $e');
        }
        try {
          await performFullCatchUp();
        } catch (e) {
          print('⚠️ السحب الكامل بعد التهيئة: $e');
        }
      }());

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
    await _bootstrapRequestListener?.cancel(); // 🆕 إيقاف الاستماع لطلبات التمهيد
    _bootstrapRequestListener = null;
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
        // 🩺 فحص صحة المصادقة كل نبضة: جلسة ساقطة تُستعاد فوراً
        // (يغطي انتهاء التوكن أثناء الجلسة على PWA)
        if (fauth.FirebaseAuth.instance.currentUser == null) {
          SyncDiagnostics.log('auth', 'سقوط الجلسة أثناء التشغيل — استعادة فورية');
          unawaited(_recoverFromAuthFailure());
        }
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
  /// للاختبار فقط (test/sync_harness): يشغّل دورة المزامنة الخلفية فوراً
  /// بدل انتظار مؤقت العشر دقائق. نفس الدالة التي يستدعيها المؤقت.
  @visibleForTesting
  Future<void> debugRunBackgroundCycle() => _performBackgroundSync();

  /// للاختبار: تمهيد جهاز جديد/مستعيد جارٍ الآن (ينتظر إعادة بثّ الأجهزة).
  @visibleForTesting
  bool get debugBootstrapping => _bootstrapping;

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

      // 3️⃣.أ 🛡️ وضع الاستعادة أو تمهيد جهاز جديد لم يكتمل؟ أعد المحاولة
      if (_recoveryMode || _bootstrapIncomplete) {
        await ensureNewDeviceBootstrap();
      }

      // 3️⃣.ب 🛡️ كل ما يملكه هذا الجهاز ولم يُرفع — أياً كان منشئ العميل.
      //      كانت هذه المسارات تقتصر على «عملاء أنشأتُهم» أو على المنسق،
      //      فتعديل معاملة على عميل جهاز آخر لم يُرفع أبداً.
      await _uploadAllOwnedPending();
      await _syncPendingChanges();
      await StockMovementSyncService().uploadPending();

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
      
      // 🛡️ لا تنظيف تلقائي للإقرارات: هي دليل المطابقة المحصّنة على أن
      // المعاملة كانت في السحابة (الزر اليدوي في الإعدادات باقٍ).
      
      // تنظيف سجلات العمليات
      await _operationTracker?.cleanupOldLogs();
      
      print('✅ اكتمل التنظيف الدوري');
    } catch (e) {
      print('⚠️ خطأ في التنظيف الدوري: $e');
    }
  }
  /// 🩺 الشفاء الذاتي من فشل المصادقة على الويب/PWA:
  /// مستمعو Firestore يموتون بصمت عند رفض التوكن (جلسة مجهولة منتهية).
  /// هنا: إعادة مصادقة مجهولة ثم إعادة تشغيل المستمعين — فتُقام القيامة.
  Future<void> _recoverFromAuthFailure() async {
    if (_isRecoveringFromAuth) return;
    _isRecoveringFromAuth = true;
    try {
      print('🩺 [AuthRecovery] خطأ مصادقة — محاولة الشفاء الذاتي...');
      SyncDiagnostics.log('auth', 'خطأ في مستمعي المزامنة — شفاء ذاتي جارٍ...');
      try {
        await fauth.FirebaseAuth.instance.signOut();
      } catch (_) {}
      final fresh = await fauth.FirebaseAuth.instance.signInAnonymously();
      SyncDiagnostics.log('auth', '✅ جلسة مجهولة جديدة بعد الشفاء: ${fresh.user?.uid}');
      print('🩺 [AuthRecovery] جلسة مجهولة جديدة: ${fresh.user?.uid}');
      await _stopListening();
      await _startListening().timeout(const Duration(seconds: 30));
      SyncDiagnostics.log('listener', '✅ المستمعون عادوا للعمل بعد الشفاء');
      print('🩺 [AuthRecovery] المستمعون عادوا للعمل ✅');
    } catch (e) {
      SyncDiagnostics.logAuth(e);
      print('🩺 [AuthRecovery] فشل الشفاء: $e — ستُعاد المحاولة مع دورة المراقبة');
    } finally {
      _isRecoveringFromAuth = false;
    }
  }

  bool _isRecoveringFromAuth = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚪 Auth-Gate: انتظار جلسة حقيقية + توكن مُتحقق منه — لا اتصال قبله.
  // ═══════════════════════════════════════════════════════════════════════════
  Future<bool> _waitForValidAuthToken() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        // 1) انتظار استرجاع الجلسة (غير متزامن على الويب/PWA)
        fauth.User? user;
        try {
          user = await fauth.FirebaseAuth.instance.authStateChanges()
              .first
              .timeout(const Duration(seconds: 8));
        } catch (e) {
          final raw = e.toString();
          SyncDiagnostics.log('auth', '[بوابة/استرجاع الجلسة] $raw');

          // 🔀 مسار بديل عند فشل interop للبث (TypeError في السفاري):
          // استعلام دوري مباشر عن currentUser — يتجاوز القناة المتعثرة.
          if (raw.toLowerCase().contains('typeerror')) {
            SyncDiagnostics.log('auth', 'تبديل إلى المسار البديل لاسترجاع الجلسة...');
            for (var i = 0; i < 8; i++) {
              await Future.delayed(const Duration(seconds: 1));
              try {
                user = fauth.FirebaseAuth.instance.currentUser;
              } catch (_) {}
              if (user != null) break;
            }
          }
          user ??= fauth.FirebaseAuth.instance.currentUser;
        }

        // 🌐 لا جلسة بعد انقضاء المهلة على الويب ⇒ الاسترجاع متعلّق لا غائب
        // (عطل WebKit: indexedDB.open لا يُطلق أي حدث بعد إقلاع بارد لـ PWA).
        // ندع المخزن جانباً ونكمل بذاكرة فقط، وإلا فشل التسجيل المجهول أيضاً
        // لأنه يحتاج الكتابة في نفس المخزن المتعلّق.
        if (kIsWeb && user == null) {
          SyncDiagnostics.log('auth',
              'البوابة: تعليق في استرجاع الجلسة — المتابعة بذاكرة فقط');
          try {
            await clearWebAuthStorage();
          } catch (_) {}
          try {
            await fauth.FirebaseAuth.instance
                .setPersistence(fauth.Persistence.NONE);
          } catch (_) {}
        }

        // 2) لا جلسة → تسجيل مجهول
        if (user == null) {
          user = (await fauth.FirebaseAuth.instance.signInAnonymously()).user;
        }

        // 3) التحقيق الحقيقي: توكن قابل للتجديد
        await user!.getIdToken(true).timeout(const Duration(seconds: 20));
        return true;
      } catch (e) {
        final raw = e.toString();
        print('🚪 [AuthGate] محاولة $attempt فشلت: $raw');
        SyncDiagnostics.log('auth', 'بوابة المصادقة — محاولة $attempt/3: $raw');

        // 🧹 شفاء TypeError على الويب: جلسة تالفة في IndexedDB —
        // نظّف المخزن وسيُعاد التسجيل المجهول على قاعدة نظيفة.
        if (kIsWeb && raw.toLowerCase().contains('typeerror')) {
          SyncDiagnostics.log('auth',
              'اكتشاف تلف مخزن الجلسة في المتصفح — تنظيف وإعادة تسجيل...');
          try {
            await fauth.FirebaseAuth.instance.signOut();
          } catch (_) {}
          await clearWebAuthStorage();
          try {
            final fresh = await fauth.FirebaseAuth.instance.signInAnonymously();
            await fresh.user!.getIdToken(true)
                .timeout(const Duration(seconds: 20));
            SyncDiagnostics.log('auth', '✅ شُفيت الجلسة بعد تنظيف المخزن');
            return true;
          } catch (e2) {
            SyncDiagnostics.log('auth', 'بعد التنظيف ما زال الفشل: $e2');
          }
        }

        if (attempt < 3) {
          // تفريغ جلسة ميتة والبدء من جديد
          try {
            await fauth.FirebaseAuth.instance.signOut();
          } catch (_) {}
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    SyncDiagnostics.log('auth', 'بوابة المصادقة: فشلت كل المحاولات');
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🌅 خطاف العودة للحياة: iOS/PWA يجمّد المؤقتات بالخلفية ويقطع الاتصالات
  // عند القفل — هذا الفحص الفوري عند العودة يمسك اللحظة قبل أي مستخدم.
  // ═══════════════════════════════════════════════════════════════════════════
  AppLifecycleListener? _lifecycleListener;

  void _startLifecycleHook() {
    if (_lifecycleListener != null) return;
    // 🛡️ خارج الخيط الرئيسي (مهام workmanager الخلفية، واختبار الأجهزة
    // الوهمية في test/sync_harness) لا توجد بيئة واجهة، فيرمي المنشئ استثناءً
    // كان يُسقط التهيئة كلها. الخطاف تحسين للعودة من الخلفية، لا شرط للمزامنة.
    try {
      _lifecycleListener = AppLifecycleListener(onResume: () {
        _onAppResumed();
      });
    } catch (e) {
      print('⚠️ لا بيئة واجهة لخطاف العودة للتطبيق (خيط خلفي؟): $e');
    }
  }

  Future<void> _onAppResumed() async {
    if (!_isInitialized) return;
    try {
      // جلسة ساقطة أو توكن ميت → إنعاش فوري
      final user = fauth.FirebaseAuth.instance.currentUser;
      bool tokenOk = false;
      if (user != null) {
        try {
          await user.getIdToken().timeout(const Duration(seconds: 10));
          tokenOk = true;
        } catch (_) {}
      }
      if (!tokenOk) {
        SyncDiagnostics.log('auth', '🔄 عودة للتطبيق والجلسة ميتة — إنعاش فوري');
        await _recoverFromAuthFailure();
        return;
      }
      // جلسة سليمة لكن المستمعين ماتوا بالخلفية → إعادة تشغيلهم
      if (!_isListening) {
        SyncDiagnostics.log('listener', '🔄 عودة للتطبيق والمستمعون متوقفون — إعادة تشغيل');
        await _startListening().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      SyncDiagnostics.log('auth', 'خطأ في فحص العودة: $e');
    }
  }

  /// واجهة عامة للتشخيص اليدوي: هل المستمعون أحياء؟
  bool get isListeningNow => _isListening;

  /// واجهة عامة: إنعاش فوري (يستدعيه زر التشخيص والإصلاح).
  Future<void> recoverNow() async {
    await _recoverFromAuthFailure();
    await performFullCatchUp();
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
          onError: (e) {
            print('❌ خطأ في استماع العملاء: $e');
            SyncDiagnostics.logListener(e);
            unawaited(_recoverFromAuthFailure());
          },
        );

    // الاستماع لتغييرات المعاملات
    _transactionsListener = transactionsQuery
        .snapshots()
        .listen(
          _onTransactionsChanged,
          onError: (e) {
            print('❌ خطأ في استماع المعاملات: $e');
            SyncDiagnostics.logListener(e);
            unawaited(_recoverFromAuthFailure());
          },
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

      // 🛡️ اختفاء المستند من السحابة (تنظيف/«حذف قاعدة البيانات السحابية»)
      // ليس أمر حذف. كان هذا الفرع يحذف العميل ومعاملاته محلياً على كل جهاز
      // عند مسح السحابة (المحاكاة: سيناريو 17). الحذف الحقيقي = isDeleted.
      if (change.type == DocumentChangeType.removed) continue;

      // مستند آخر كاتب له هو أنا: قد يحمل شاهد حذف كتبه غيري ودُمج فيه،
      // أو عميلاً فقدتُه باستعادة نسخة احتياطية قديمة.
      if (sourceDeviceId == _deviceId) {
        try {
          await _handleOwnCustomerDoc(syncUuid, data);
        } catch (e) {
          print('⚠️ مستند عميل ذاتي $syncUuid: $e');
        }
        continue;
      }

      print('📥 استلام تغيير عميل من جهاز آخر: $syncUuid (نوع: ${change.type})');
      print('   - الجهاز المصدر: $sourceDeviceId');

      try {
        await _applyCustomerChange(syncUuid, data);
      } catch (e) {
        print('❌ خطأ في تطبيق تغيير العميل $syncUuid: $e');
      }
    }
    
    // تحديث وقت آخر مزامنة بعد معالجة أي تغييرات (للاستماع الذكي)
    if (snapshot.docChanges.isNotEmpty) {
      await mergeDuplicateCustomersByName();
      final db = await _db.database;
      final nowStr = DateTime.now().toIso8601String();
      // 🛡️ إدراج ذرّي: مستمعا العملاء والمعاملات يصلان هنا معاً، و«اقرأ ثم
      // أدرج» كان يرمي UNIQUE constraint failed: sync_state.id (اختبار الكود الحقيقي)
      await db.rawInsert(
          'INSERT OR IGNORE INTO sync_state (id, last_sync_at) VALUES (1, ?)', [nowStr]);
      await db.update('sync_state', {'last_sync_at': nowStr}, where: 'id = 1');
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

      // مستندي أنا: قد يحمل شاهد حذف دُمج فيه، أو معاملة فقدتُها باستعادة نسخة
      if (sourceDeviceId == _deviceId) {
        if (change.type != DocumentChangeType.removed) {
          try {
            await _handleOwnTxDoc(syncUuid, data);
          } catch (e) {
            print('⚠️ مستند معاملة ذاتي $syncUuid: $e');
          }
        }
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
      // 🛡️ إدراج ذرّي: مستمعا العملاء والمعاملات يصلان هنا معاً، و«اقرأ ثم
      // أدرج» كان يرمي UNIQUE constraint failed: sync_state.id (اختبار الكود الحقيقي)
      await db.rawInsert(
          'INSERT OR IGNORE INTO sync_state (id, last_sync_at) VALUES (1, ?)', [nowStr]);
      await db.update('sync_state', {'last_sync_at': nowStr}, where: 'id = 1');
    }
  }

  /// تطبيق تغيير عميل من Firebase على قاعدة البيانات المحلية.
  /// 🔒 مهم: لا نحدث current_total_debt من البيانات البعيدة!
  /// الرصيد يُحسب دائماً من مجموع المعاملات المحلية
  Future<void> _applyCustomerChange(String syncUuid, Map<String, dynamic> data) async {
    final isTombstone = data['isDeleted'] == true || data['is_deleted'] == 1;

    // 🔐 التحقق من صحة البيانات الواردة (شاهد الحذف القديم قد يخلو من الاسم)
    final validation = SyncValidation.validateFirebaseCustomerData(data);
    if (!validation.isValid && !isTombstone) {
      print('❌ رفض بيانات عميل غير صالحة: ${validation.errors.join(', ')}');
      return;
    }

    // 🔐 التوقيع (يُفرض فقط في الوضع الصارم بسرّ مشترك)
    if (!await _verifyIncomingSignature(syncUuid, data, isCustomer: true)) return;

    // 🔐 تنظيف البيانات من المحتوى الخطر
    final sanitizedData = SyncValidation.sanitizeMap(data);

    // 🗑️ شاهد حذف: لا نحذف المعاملات هنا ولا نعيد الرفع (كان ذلك يرتد بين
    // الأجهزة بلا نهاية: ~1000 كتابة/دقيقة حتى يُستنفد حد المعدل — سيناريو 15).
    // المعاملات تُبطَل بشواهدها الخاصة التي يرفعها الجهاز الحاذف.
    if (isTombstone) {
      await _applyCustomerTombstone(syncUuid, sanitizedData);
      return;
    }

    final db = await _db.database;

    // التحقق من وجود العميل محلياً بـ sync_uuid
    final existing = await db.query(
      'customers',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
      limit: 1,
    );
    if (existing.isEmpty) {
      final incomingName = SyncValidation.sanitizeString(sanitizedData['name']?.toString() ?? '').trim();
      final normIncomingName = DatabaseHelpers.normalizeArabic(incomingName);

      // 🛡️ الربط بالاسم مسموح فقط مع سجل محلي قديم لم يُعطَ هوية مزامنة قط.
      //
      // كان الكود يربط أي عميل محلي بنفس الاسم ويستبدل sync_uuid الخاص به.
      // فـ«محمد علي» الذي أنشأه D1 و«محمد علي» آخر أنشأه D2 كانا يُدمجان،
      // وتُكتب هوية أحدهما فوق الآخر، فتتيتّم معاملاته إلى الأبد (سيناريو 12).
      // الاسم ليس هوية؛ sync_uuid هو الهوية الوحيدة.
      final legacyCandidates = await db.query(
        'customers',
        where: "(is_deleted IS NULL OR is_deleted = 0) AND (sync_uuid IS NULL OR sync_uuid = '')",
      );

      Map<String, dynamic>? matchedCustomer;
      for (final c in legacyCandidates) {
        final cName = (c['name'] as String? ?? '').trim();
        final cNorm = DatabaseHelpers.normalizeArabic(cName);
        if (cName == incomingName || (normIncomingName.isNotEmpty && cNorm == normIncomingName)) {
          matchedCustomer = c;
          break;
        }
      }

      if (matchedCustomer != null) {
        final matchedId = matchedCustomer['id'] as int;
        print('🔗 [FirebaseSyncService] ربط سجل قديم بلا هوية: $incomingName (ID: $matchedId) -> $syncUuid');

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

        await _processOrphans(matchedId, syncUuid);
        await _verifyAndRepairCustomerBalance(matchedId);
        await _applyCustomerVisibility(matchedId);

        _syncEventController.add('ربط عميل: $incomingName');
        return;
      }

      // عميل جديد — برصيد 0، والرصيد يُشتق من المعاملات
      final newCustomerId = await _insertReceivedCustomer(db, syncUuid, sanitizedData, incomingName);

      await _coordinator!.registerOperation(
        entityType: 'customer',
        syncUuid: syncUuid,
        source: SyncSource.firebase,
      );
      await _coordinator!.markFirebaseSynced('customer', syncUuid);

      print('✅ تم إضافة عميل جديد بنجاح من Firebase: ${data['name']}');
      print('   - Sync UUID: $syncUuid');

      // 🧮 خزّن البصمة الحسابية الواردة ليُحاكَم عليها بعد اكتمال المزامنة
      await _rememberExpectation(syncUuid, data);

      // 👻 معالجة المعاملات اليتيمة أولاً (قبل الإشعار!)
      await _processOrphans(newCustomerId, syncUuid);
      await _applyCustomerVisibility(newCustomerId);
      _syncEventController.add('عميل جديد: ${data['name']}');
    } else {
      // 🔒 عميل موجود - تحديث البيانات الوصفية فقط (بدون الرصيد!)
      final localData = existing.first;
      final customerId = localData['id'] as int;
      final localBalance = (localData['current_total_debt'] as num?)?.toDouble() ?? 0.0;

      final values = <String, Object?>{
        'name': data['name'] ?? localData['name'],
        'phone': data['phone'] ?? localData['phone'],
        // 🔒 لا نحدث current_total_debt - يبقى كما هو
        'general_note': data['generalNote'] ?? localData['general_note'],
        'address': data['address'] ?? localData['address'],
        'last_modified_at': data['lastModifiedAt'] ?? DateTime.now().toIso8601String(),
        'audio_note_path': data['audioNotePath'] ?? localData['audio_note_path'],
        'synced_at': DateTime.now().toIso8601String(),
        // 🛡️ لا نمسّ is_created_by_me: كان يُصفَّر هنا فيفقد الجهاز المنشئ
        // ملكية عميله كلما رفع جهاز آخر وثيقته (فاتورة من D2 لعميل D1 مثلاً)،
        // فتتوقف مسارات رفعه الفوري لذلك العميل (سيناريو 37).
      };
      // إعادة تنشيط صريحة من جهاز آخر (isDeleted=false تُكتب فقط عند التنشيط)
      final localTomb = (localData['tombstoned'] as int?) ?? 0;
      if (data['isDeleted'] == false && localTomb == 1) {
        values['tombstoned'] = 0;
      }

      try {
        await db.update('customers', values, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
      } on DatabaseException catch (e) {
        // UNIQUE(name, phone) مع عميل آخر مستقل: نميّز الهاتف بمحرف غير مرئي
        if (e.isUniqueConstraintError()) {
          values['phone'] = await _uniquePhoneFor(
              db, values['name']?.toString() ?? '', values['phone']?.toString(), excludeId: customerId);
          await db.update('customers', values, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
        } else {
          rethrow;
        }
      }
      await _applyCustomerVisibility(customerId);

      // 🧮 خزّن البصمة الحسابية الواردة ليُحاكَم عليها بعد اكتمال المزامنة
      await _rememberExpectation(syncUuid, data);

      print('✅ تم تحديث بيانات العميل (بدون الرصيد): ${data['name']}');
      print('   📊 الرصيد المحلي محفوظ: $localBalance');
      _syncEventController.add('تحديث عميل: ${data['name']}');
    }
  }

  /// يُدرج عميلاً وارداً. قيد UNIQUE(name, phone) قديم في المخطط كان يُفشل
  /// إدراج عميل مستقل يحمل نفس الاسم والهاتف (أُنشئ على جهازين، أو اسم عميل
  /// محذوف)، فتتيتّم معاملاته للأبد (سيناريوهات 38، 39). الهوية هي sync_uuid،
  /// فنُبقي العميلين منفصلين ونميّز الهاتف بمحرف عرض صفري (لا يُرى).
  Future<int> _insertReceivedCustomer(
    Database db,
    String syncUuid,
    Map<String, dynamic> data,
    String name,
  ) async {
    final row = <String, Object?>{
      'name': name,
      'phone': data['phone'],
      'current_total_debt': 0.0, // 🔒 نبدأ بصفر، المعاملات ستحدد الرصيد
      'general_note': data['generalNote'],
      'address': data['address'],
      'created_at': data['createdAt'],
      'last_modified_at': data['lastModifiedAt'],
      'audio_note_path': data['audioNotePath'],
      'sync_uuid': syncUuid,
      'is_deleted': 0,
      'synced_at': DateTime.now().toIso8601String(),
      'is_created_by_me': 0,
    };
    try {
      return await db.insert('customers', row);
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
      // 🛡️ سباق: مسار آخر (حزمة فاتورة، مطابقة…) أدرج نفس العميل للتو —
      // القيد الفريد على sync_uuid يمنع النسخة الثانية، فنعتمد الموجودة.
      final same = await db.query('customers',
          columns: ['id'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
      if (same.isNotEmpty) return same.first['id'] as int;
      row['phone'] = await _uniquePhoneFor(db, name, data['phone']?.toString());
      print('🛡️ عميل مستقل بنفس الاسم والهاتف ($name) — أُبقي منفصلاً بهويته $syncUuid');
      return await db.insert('customers', row);
    }
  }

  Future<String> _uniquePhoneFor(Database db, String name, String? phone, {int? excludeId}) async {
    var candidate = phone ?? '';
    for (var k = 1; k <= 20; k++) {
      candidate = '${phone ?? ''}${'​' * k}';
      final clash = await db.query(
        'customers',
        columns: ['id'],
        where: excludeId == null ? 'name = ? AND phone = ?' : 'name = ? AND phone = ? AND id != ?',
        whereArgs: excludeId == null ? [name, candidate] : [name, candidate, excludeId],
        limit: 1,
      );
      if (clash.isEmpty) break;
    }
    return candidate;
  }

  /// 🗑️ شاهد حذف عميل وارد.
  ///
  /// القاعدة: العميل مخفي إذا وُسم محذوفاً ولم تبقَ له معاملة نشطة. لا نحذف
  /// معاملاته هنا — يبطلها الجهاز الحاذف بشاهد لكل معاملة كان يعرفها، فيصل كل
  /// جهاز إلى نفس المجموعة المُبطَلة بالضبط. ما سُجّل أوفلاين على جهاز لم يعلم
  /// بالحذف يبقى نشطاً ويُعيد العميل للظهور (إعادة تنشيط ذكي متسقة — سيناريو 41).
  Future<void> _applyCustomerTombstone(String syncUuid, Map<String, dynamic> data) async {
    final db = await _db.database;
    final rows = await db.query('customers',
        columns: ['id', 'tombstoned'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
    int customerId;
    if (rows.isEmpty) {
      final name = (data['name']?.toString() ?? '').trim();
      customerId = await _insertReceivedCustomer(db, syncUuid, data, name.isEmpty ? 'عميل محذوف' : name);
      await _coordinator!.registerOperation(
        entityType: 'customer',
        syncUuid: syncUuid,
        source: SyncSource.firebase,
      );
      await _coordinator!.markFirebaseSynced('customer', syncUuid);
    } else {
      customerId = rows.first['id'] as int;
      final tomb = (rows.first['tombstoned'] as int?) ?? 0;
      if (tomb == 3) {
        // تنشيطي المحلي لم يُرفع بعد — نسختي أحدث من هذا الشاهد
        return;
      }
    }

    await db.update(
      'customers',
      {'tombstoned': 1, 'synced_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND (tombstoned IS NULL OR tombstoned != 2)',
      whereArgs: [customerId],
    );

    // سياسة الحذف الصارم: المالك يُبطل كل معاملاته هو على العميل ويرفع شواهدها
    try {
      final policy = await FirebaseSyncSecuritySettings.getCustomerConflictPolicy();
      if (policy == CustomerConflictPolicy.strictDelete) {
        await db.update(
          'transactions',
          {'is_deleted': 1, 'is_uploaded': 0, 'restored_mark': 0},
          where: 'customer_id = ? AND (is_created_by_me = 1 OR is_created_by_me IS NULL) '
              'AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [customerId],
        );
      }
    } catch (e) {
      print('⚠️ سياسة الحذف الصارم: $e');
    }

    await _rebuildCustomerBalances(customerId);
    await _applyCustomerVisibility(customerId);
    _customerUpdatedController.add(syncUuid);
    _syncEventController.add('حذف عميل من جهاز آخر');
  }

  /// مستند عميل آخر كاتب له هو هذا الجهاز.
  Future<void> _handleOwnCustomerDoc(String syncUuid, Map<String, dynamic> data) async {
    final db = await _db.database;
    final rows = await db.query('customers',
        columns: ['id', 'tombstoned'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
    final isTomb = data['isDeleted'] == true || data['is_deleted'] == 1;
    if (rows.isNotEmpty) {
      // شاهد حذف كتبه جهاز آخر ثم دُمج رفعي أنا فوقه (merge يُبقي isDeleted)
      if (isTomb && ((rows.first['tombstoned'] as int?) ?? 0) == 0) {
        await _applyCustomerTombstone(syncUuid, SyncValidation.sanitizeMap(data));
      }
      return;
    }
    // عميلي أنا مفقود محلياً: قاعدة استُعيدت من نسخة قديمة
    final name = SyncValidation.sanitizeString(data['name']?.toString() ?? '').trim();
    if (name.isEmpty || isTomb) return;
    final id = await _insertReceivedCustomer(db, syncUuid, SyncValidation.sanitizeMap(data), name);
    await db.update('customers', {'is_created_by_me': 1}, where: 'id = ?', whereArgs: [id]);
    await _coordinator!.registerOperation(
      entityType: 'customer',
      syncUuid: syncUuid,
      source: SyncSource.firebase,
    );
    await _coordinator!.markFirebaseSynced('customer', syncUuid);
    await _processOrphans(id, syncUuid);
    print('♻️ استُعيد عميلي المفقود محلياً من السحابة: $name');
  }

  /// 🛡️ قاعدة الظهور الوحيدة: العميل مخفي ⇔ موسوم بالحذف ولا معاملة نشطة له.
  /// دالة حتمية على حالة متقاربة، فتصل كل الأجهزة لنفس النتيجة مهما كان الترتيب.
  Future<void> _applyCustomerVisibility(int customerId) async {
    try {
      final db = await _db.database;
      await CustomerVisibility.apply(db, customerId);
    } catch (e) {
      print('⚠️ _applyCustomerVisibility: $e');
    }
  }

  /// إعادة بناء السلسلة التراكمية + الرصيد من مجموع المعاملات.
  Future<void> _rebuildCustomerBalances(int customerId) async {
    try {
      final dbService = DatabaseService();
      await dbService.recalculateCustomerTransactionBalances(customerId);
      await dbService.recalculateAndApplyCustomerDebt(customerId);
    } catch (e) {
      print('⚠️ _rebuildCustomerBalances($customerId): $e');
      await _verifyAndRepairCustomerBalance(customerId);
    }
  }

  /// وقت الخادم (uploadedAt) بالملّي ثانية — إصدار المستند.
  int? _serverMillis(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch;
    return null;
  }

  Future<void> _sendAckFor(String syncUuid, Map<String, dynamic> data) async {
    final senderDeviceId = data['originDeviceId'] as String? ?? data['deviceId'] as String?;
    if (senderDeviceId != null && senderDeviceId != _deviceId) {
      await _ackService?.sendAck(
        transactionUuid: syncUuid,
        senderDeviceId: senderDeviceId,
      );
    }
  }

  /// مستند معاملة آخر كاتب له هو هذا الجهاز.
  Future<void> _handleOwnTxDoc(String syncUuid, Map<String, dynamic> data) async {
    final db = await _db.database;
    final isDel = data['isDeleted'] == true || data['is_deleted'] == 1;
    final rows = await db.query('transactions',
        where: 'transaction_uuid = ?', whereArgs: [syncUuid], limit: 1);
    if (rows.isNotEmpty) {
      final loc = rows.first;
      final cid = loc['customer_id'] as int;
      final locDeleted = ((loc['is_deleted'] as int?) ?? 0) == 1;
      // شاهد حذف (حذف عميل على جهاز آخر) دُمج في مستندي — الحذف نهائي
      if (isDel && !locDeleted) {
        await db.update('transactions', {'is_deleted': 1, 'is_uploaded': 1},
            where: 'id = ?', whereArgs: [loc['id']]);
        await _rebuildCustomerBalances(cid);
        await _applyCustomerVisibility(cid);
        return;
      }
      // 🛡️ معاملتي محفوظة هنا «كمعاملة جهاز آخر» (وصلت من كشف مطابقة أو
      // إعادة بثّ بعد استعادة نسخة احتياطية): لا يطبّق عليها أي مسار نسخةَ
      // السحابة الأحدث. نسترد ملكيتها ونأخذ نسخة السحابة إن لم تكن أقدم.
      if (!locDeleted && !isDel && ((loc['is_created_by_me'] as int?) ?? 1) == 0) {
        final inVer = _serverMillis(data['uploadedAt']);
        final locVer = (loc['remote_ver'] as num?)?.toInt();
        if (inVer == null || locVer == null || inVer >= locVer) {
          await db.update(
            'transactions',
            {
              'amount_changed': (data['amountChanged'] as num?)?.toDouble() ??
                  loc['amount_changed'],
              'transaction_type': data['transactionType'] ?? loc['transaction_type'],
              'transaction_note': data['transactionNote'] ?? loc['transaction_note'],
              'is_created_by_me': 1,
              'origin_device_id': _deviceId,
              'is_uploaded': 1,
              'restored_mark': 0,
              'remote_ver': inVer,
              'last_uploaded_at': data['lastModifiedAt']?.toString(),
            },
            where: 'id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
            whereArgs: [loc['id']],
          );
          await _rebuildCustomerBalances(cid);
          await _applyCustomerVisibility(cid);
          print('♻️ استُردّت ملكية معاملتي $syncUuid بنسخة السحابة');
        }
        return;
      }
      // 🛡️ وضع الاستعادة: ما رفعتُه بعد أخذ النسخة الاحتياطية يلغي ما فيها
      // (حتى تعديلاً «بانتظار الرفع» داخلها)، ما لم يُعدَّل الصف بعد الاستعادة.
      // وخارج وضع الاستعادة: صفّي بلا تعديل معلّق، ومستندي أحدث من آخر رفع
      // أعرفه (كلا الوقتين من ساعتي أنا) = تعديل رفعتُه قبل أن تُستعاد نسخة
      // أقدم. يُؤخذ بدل أن يبقى الصف القديم ثم يُفرض على الكل كـ «نسختي»
      // (استعادة انتهت قبل أن يصل كل شيء — اختبار الكود الحقيقي).
      final restoredRow =
          _recoveryMode && ((loc['restored_mark'] as int?) ?? 0) == 1;
      final locPending = ((loc['is_uploaded'] as int?) ?? 0) == 0;
      // صف فاتورة: حزمة الفاتورة مرجعه لا مستند المعاملة (نسخة قديمة منه قد
      // تبقى في مجموعة transactions من إصدارات سابقة — سيناريو 18).
      final locInv = (loc['invoice_sync_uuid'] as String?) ?? '';
      final locUpKnown = (loc['last_uploaded_at']?.toString() ?? '').isNotEmpty;
      if (!locDeleted &&
          !isDel &&
          (restoredRow || (!locPending && locInv.isEmpty && locUpKnown))) {
        final docMod = data['lastModifiedAt']?.toString() ?? '';
        final locUp = loc['last_uploaded_at']?.toString() ?? '';
        if (docMod.compareTo(locUp) > 0) {
          await db.update(
            'transactions',
            {
              'amount_changed': (data['amountChanged'] as num?)?.toDouble() ?? 0.0,
              'transaction_type': data['transactionType'] ?? loc['transaction_type'],
              'transaction_note': data['transactionNote'] ?? loc['transaction_note'],
              'last_uploaded_at': docMod,
              'is_uploaded': 1,
            },
            // مشروط: لا كتابة فوق حذف أو تعديل تمّ هنا بعد القراءة
            where: restoredRow
                ? 'id = ? AND (is_deleted IS NULL OR is_deleted = 0) AND restored_mark = 1'
                : 'id = ? AND (is_deleted IS NULL OR is_deleted = 0) AND is_uploaded = 1',
            whereArgs: [loc['id']],
          );
          await _rebuildCustomerBalances(cid);
          await _applyCustomerVisibility(cid);
        } else if (!restoredRow &&
            docMod.compareTo(locUp) < 0 &&
            (((data['amountChanged'] as num?)?.toDouble() ?? 0.0) -
                        ((loc['amount_changed'] as num?)?.toDouble() ?? 0.0))
                    .abs() >
                0.01) {
          // 🛡️ في السحابة نسخة من معاملتي أقدم من آخر ما رفعتُ (إعادة بثّ من
          // جهاز متأخر): أعيد رفع نسختي لتصحّحها عند الجميع.
          await db.update('transactions', {'is_uploaded': 0},
              where: 'id = ?', whereArgs: [loc['id']]);
        }
      }
      return;
    }

    // معاملتي مفقودة محلياً: استُعيدت قاعدة قديمة — تُستعاد كمعاملة أملكها
    final cs = data['customerSyncUuid'] as String?;
    if (cs == null || cs.isEmpty) return;
    final cust = await db.query('customers',
        columns: ['id'], where: 'sync_uuid = ?', whereArgs: [cs], limit: 1);
    if (cust.isEmpty) {
      await _addToOrphans(syncUuid, data);
      return;
    }
    final inv = (data['invoiceSyncUuid'] ?? data['invoice_sync_uuid'])?.toString();
    if (inv != null && inv.isNotEmpty) {
      final hasInv = await db.query('invoices',
          columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [inv], limit: 1);
      if (hasInv.isNotEmpty) return; // حزمة الفاتورة هي المرجع
    }
    final cid = cust.first['id'] as int;
    final amount = (data['amountChanged'] as num?)?.toDouble() ?? 0.0;
    await db.insert('transactions', {
      'customer_id': cid,
      'transaction_date': data['transactionDate'] ?? DateTime.now().toIso8601String(),
      'amount_changed': amount,
      'transaction_note': data['transactionNote'],
      'transaction_type': data['transactionType'] ?? (amount >= 0 ? 'manual_debt' : 'manual_payment'),
      'description': data['description'],
      'created_at': data['createdAt'] ?? DateTime.now().toIso8601String(),
      'is_created_by_me': 1,
      'is_uploaded': 1,
      'sync_uuid': syncUuid,
      'transaction_uuid': syncUuid,
      'invoice_sync_uuid': inv,
      'is_deleted': isDel ? 1 : 0,
      'origin_device_id': _deviceId,
      'last_uploaded_at': data['lastModifiedAt']?.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _coordinator?.registerOperation(
      entityType: 'transaction',
      syncUuid: syncUuid,
      source: SyncSource.local,
    );
    await _coordinator?.markFirebaseSynced('transaction', syncUuid);
    await _rebuildCustomerBalances(cid);
    await _applyCustomerVisibility(cid);
    print('♻️ استُعيدت معاملتي المفقودة محلياً من السحابة: $syncUuid');
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

    // 🔐 التوقيع (يُفرض فقط في الوضع الصارم بسرّ مشترك)
    if (!await _verifyIncomingSignature(syncUuid, data)) return;

    // 🛡️ «رفض المعاملات القديمة» صار تنبيهاً فقط.
    //
    // الرفض بالعمر لا يمكن أن يكون آمناً: جهاز غاب 40 يوماً يجد معاملات
    // رُفعت قبل 40 يوماً فيرفضها — فيبقى رصيده ناقصاً إلى الأبد (سيناريو 10).
    // والتكرار أصلاً مستحيل بفضل المعرّف الفريد، فالرفض لا يحمي من شيء.
    try {
      if (await FirebaseSyncSecuritySettings.isRejectOldTransactionsEnabled()) {
        final measured = _serverMillis(data['uploadedAt'] ?? data['uploaded_at']);
        if (measured != null) {
          final maxAgeDays = await FirebaseSyncSecuritySettings.getMaxTransactionAgeDays();
          final age = DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(measured))
              .inDays;
          if (age > maxAgeDays) {
            SyncDiagnostics.log('sync',
                'معاملة $syncUuid رُفعت قبل $age يوم (الحد $maxAgeDays) — قُبلت '
                'لأن رفضها يُسقط معاملة حقيقية لجهاز عائد من غياب');
          }
        }
      }
    } catch (_) {}

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
      limit: 1,
    );

    if (customerResult.isEmpty) {
      // 👻 العميل غير موجود - إضافة للطابور
      print('⏳ معاملة مؤقتة (بانتظار بيانات العميل): $syncUuid');
      await _addToOrphans(syncUuid, data);
      return;
    }

    final localCustomerId = customerResult.first['id'] as int;
    final customerName = customerResult.first['name'] as String? ?? 'غير معروف';
    final currentBalance = (customerResult.first['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    final isTxDeleted = (data['isDeleted'] == true || data['is_deleted'] == 1);

    // 🛡️ معاملة فاتورة نشطة: حزمة الفاتورة هي المرجع الوحيد.
    // نسخة قديمة منها في مجموعة transactions (رُفعت قبل تحويل الفاتورة لنقد)
    // كانت تُعيد الدين الوهمي عند كل سحب كامل/إعادة تشغيل (سيناريو 18).
    // شاهد الحذف (حذف العميل) يُطبَّق دائماً.
    final incomingInvUuid = (data['invoiceSyncUuid'] ?? data['invoice_sync_uuid'])?.toString();
    if (!isTxDeleted && incomingInvUuid != null && incomingInvUuid.isNotEmpty) {
      final inv = await db.query('invoices',
          columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [incomingInvUuid], limit: 1);
      if (inv.isNotEmpty) return;
    }

    // 🛡️ إصدار المستند = وقت الخادم عند آخر كتابة. لقطة سحب كامل أو تدقيق
    // قُرئت قبل ثوانٍ ثم طُبّقت بعد وصول نسخة أحدث عبر المستمع كانت تكتب
    // الرقم القديم فوق الجديد.
    final int? incomingVer = _serverMillis(data['uploadedAt']);
    final String? incomingModified = data['lastModifiedAt']?.toString();

    // 1️⃣ التحقق من وجود المعاملة بـ transaction_uuid
    final existingByUuid = await db.query(
      'transactions',
      where: 'transaction_uuid = ?',
      whereArgs: [syncUuid],
      limit: 1,
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
      final existingTx = existingByUuid.first;
      final txId = existingTx['id'] as int;
      final existingCustomerId = existingTx['customer_id'] as int;

      final localVer = (existingTx['remote_ver'] as num?)?.toInt();
      if (incomingVer != null && localVer != null && incomingVer < localVer) {
        return; // نسخة أقدم مما طُبّق
      }
      if (incomingVer != null && (localVer == null || incomingVer > localVer)) {
        // نسجّل أحدث إصدار رأيناه حتى لو تطابق المحتوى، وإلا تسللت نسخة أقدم بعده
        await db.update('transactions',
            {'remote_ver': incomingVer, 'remote_modified_at': incomingModified},
            where: 'id = ?', whereArgs: [txId]);
      }

      final isMine = (existingTx['is_created_by_me'] as int?) != 0;
      final localDeleted = ((existingTx['is_deleted'] as int?) ?? 0) == 1;
      final currentAmount = (existingTx['amount_changed'] as num?)?.toDouble() ?? 0.0;

      if (isMine) {
        // 🛡️ صاحب المعاملة: لا يقبل من غيره إلا شاهد الحذف (حذف العميل).
        // أي نسخة أخرى مختلفة (إعادة بث قديمة، كتابة جهاز آخر) لا تُطبَّق،
        // بل تُعاد نسختي للرفع لتصحح السحابة.
        if (isTxDeleted && !localDeleted) {
          await db.update('transactions', {'is_deleted': 1, 'is_uploaded': 1},
              where: 'id = ?', whereArgs: [txId]);
          await _rebuildCustomerBalances(existingCustomerId);
          await _applyCustomerVisibility(existingCustomerId);
          await _sendAckFor(syncUuid, data);
          _customerUpdatedController.add(customerSyncUuid);
        } else if (!isTxDeleted && !localDeleted && (currentAmount - amountChanged).abs() > 0.01) {
          // 🛡️ لكن إن لم يكن عندي تعديل معلّق والمستند يحمل وقت تعديل (بساعتي،
          // تحفظه إعادة البث) أحدث من آخر رفع أعرفه: هو تعديلي أنا قبل استعادة
          // نسخة احتياطية — نأخذه. رفع صفي القديم فوقه كان يمحوه من كل الأجهزة.
          final locPending = ((existingTx['is_uploaded'] as int?) ?? 0) == 0;
          final docMod = incomingModified ?? '';
          final locUp = existingTx['last_uploaded_at']?.toString() ?? '';
          final locInv = (existingTx['invoice_sync_uuid'] as String?) ?? '';
          if (!locPending &&
              locInv.isEmpty &&
              locUp.isNotEmpty &&
              docMod.compareTo(locUp) > 0) {
            await db.update(
              'transactions',
              {
                'amount_changed': amountChanged,
                'transaction_type': transactionType,
                'transaction_note': transactionNote,
                'last_uploaded_at': docMod,
                'is_uploaded': 1,
              },
              // مشروط: لا كتابة فوق حذف تمّ هنا بعد القراءة (شاهده بانتظار الرفع)
              where: 'id = ? AND (is_deleted IS NULL OR is_deleted = 0) AND is_uploaded = 1',
              whereArgs: [txId],
            );
            await _rebuildCustomerBalances(existingCustomerId);
            await _applyCustomerVisibility(existingCustomerId);
            _customerUpdatedController.add(customerSyncUuid);
          } else {
            await db.update('transactions', {'is_uploaded': 0},
                where: 'id = ?', whereArgs: [txId]);
          }
        }
        return;
      }

      // 🛡️ الحذف نهائي: لا نُحيي معاملة محذوفة بمستند نشط
      if (localDeleted) return;


      final currentType = existingTx['transaction_type'] as String?;
      final currentNote = existingTx['transaction_note'] as String? ?? '';
      final needsUpdate = (currentAmount - amountChanged).abs() > 0.01 ||
          currentType != transactionType ||
          currentNote != transactionNote ||
          isTxDeleted;
      if (!needsUpdate) return;

      // 🔒 التحقق من مطابقة العميل
      final txCustomerCheck = await db.query(
        'customers',
        columns: ['sync_uuid'],
        where: 'id = ?',
        whereArgs: [existingCustomerId],
        limit: 1,
      );
      if (txCustomerCheck.isEmpty ||
          txCustomerCheck.first['sync_uuid'] != customerSyncUuid) {
        print('❌ رُفض تحديث معاملة $syncUuid: عدم تطابق العميل');
        return;
      }

      // 🛡️ مشروط: الصف قُرئ نشطاً أعلاه، لكن حذف العميل على هذا الجهاز قد
      // يكتمل بين القراءة وهذه الكتابة. كانت تكتب is_deleted = 0 و is_uploaded = 1
      // فوق الحذف: تُحيي المعاملة، ويضيع شاهد حذفها قبل رفعه — فيبقى دينها
      // على كل الأجهزة (اختبار الكود الحقيقي). الحذف نهائي: لا كتابة فوقه.
      final updated = await db.update(
        'transactions',
        {
          'amount_changed': amountChanged,
          'transaction_note': transactionNote,
          'transaction_type': transactionType,
          'description': data['description'],
          'transaction_date': transactionDate ?? existingTx['transaction_date'],
          if (isTxDeleted) 'is_deleted': 1,
          'is_uploaded': 1,
        },
        where: 'id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [txId],
      );
      if (updated == 0) return; // حُذفت هنا أثناء المعالجة
      await _rebuildCustomerBalances(existingCustomerId);
      await _applyCustomerVisibility(existingCustomerId);
      await _sendAckFor(syncUuid, data);

      print('📥 طُبّق تحديث معاملة $syncUuid للعميل $customerName: '
          '$currentAmount → ${isTxDeleted ? "محذوفة" : amountChanged}');
      _syncEventController.add('تحديث معاملة: $customerName');
      _customerUpdatedController.add(customerSyncUuid);
      return;
    }

    // 2️⃣ تبنّي السجلات التاريخية اليتيمة فقط (بلا معرّف).
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
      print('❌ رُفضت معاملة $syncUuid: مبلغ غير منطقي ($amountChanged)');
      return;
    }

    // 5️⃣ إعداد ملاحظة المعاملة مع علامة "من المزامنة"
    String finalNote = transactionNote;
    if (!finalNote.contains('من المزامنة') && !finalNote.contains('من جهاز آخر')) {
      finalNote = finalNote.isEmpty
          ? '🔄 من المزامنة (Firebase)'
          : '$finalNote\n🔄 من المزامنة (Firebase)';
    }

    // 7️⃣ إدراج المعاملة الجديدة وتحديث الرصيد — ذرياً.
    final applied = await db.transaction<double?>((txn) async {
      final alreadyThere = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'transaction_uuid = ? OR sync_uuid = ?',
        whereArgs: [syncUuid, syncUuid],
        limit: 1,
      );
      if (alreadyThere.isNotEmpty) return null; // موجودة مسبقاً بنفس المعرّف

      final balanceBefore = await _sumTransactions(txn, localCustomerId);

      await txn.insert(
        'transactions',
        {
          'customer_id': localCustomerId,
          'transaction_date': transactionDate ?? DateTime.now().toIso8601String(),
          'amount_changed': amountChanged,
          'balance_before_transaction': balanceBefore,
          'new_balance_after_transaction': balanceBefore + (isTxDeleted ? 0.0 : amountChanged),
          'transaction_note': finalNote,
          'transaction_type': transactionType,
          'description': data['description'],
          'created_at': data['createdAt'] ?? DateTime.now().toIso8601String(),
          'audio_note_path': data['audioNotePath'],
          'is_created_by_me': 0, // 🔒 ليست من هذا الجهاز - لا يمكن حذفها أو تعديلها
          'is_uploaded': 1, // 🔒 تعليمها كمرفوعة لتجنب إعادة رفعها
          'sync_uuid': syncUuid,
          'transaction_uuid': syncUuid,
          'invoice_sync_uuid': incomingInvUuid,
          // 🛡️ شاهد حذف لمعاملة لم تصلنا نسختها النشطة: تُسجَّل محذوفة
          'is_deleted': isTxDeleted ? 1 : 0,
          'origin_device_id': data['originDeviceId'] ?? data['deviceId'],
          'remote_ver': incomingVer,
          'remote_modified_at': incomingModified,
        },
      );

      // 8️⃣ الرصيد = مجموع المعاملات، لا رصيد سابق + مبلغ.
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
      return authoritativeBalance;
    });

    if (applied == null) {
      print('🚫 رُفضت معاملة واردة بمعرّف موجود مسبقاً: $syncUuid');
      return;
    }

    final authoritativeBalance = applied;
    await _applyCustomerVisibility(localCustomerId);

    // 9️⃣ تسجيل في المنسق
    await _coordinator!.registerOperation(
      entityType: 'transaction',
      syncUuid: syncUuid,
      source: SyncSource.firebase,
    );
    await _coordinator!.markFirebaseSynced('transaction', syncUuid);

    // 📬 إرسال تأكيد استلام (ACK) للجهاز المرسل
    await _sendAckFor(syncUuid, data);

    // ⚖️ لم تعد قرارات الإبطال عن بُعد تُطبَّق (انظر MatchVerdictService).

    final typeLabel = amountChanged >= 0 ? 'إضافة دين' : 'تسديد';
    print('📥 معاملة واردة: $typeLabel ${amountChanged.abs()} — $customerName '
        '(الرصيد $currentBalance → $authoritativeBalance)${isTxDeleted ? " [محذوفة]" : ""}');

    _syncEventController.add('معاملة جديدة: $typeLabel ${amountChanged.abs()} - $customerName');

    // 🔄 إرسال إشعار لتحديث الواجهة فوراً.
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

    // 🛡️ شباك الأمان الحسابي
    await _verifyAndRepairCustomerBalance(localCustomerId);
  }

  /// 🛡️ شباك الأمان الحسابي: يضمن أن رصيد العميل = مجموع معاملاته بالضبط.
  ///
  /// يُستدعى بعد كل معاملة واردة. لو وُجد فرق > 0.01 يُصحّح الرصيد المخزّن
  /// ويُسجّل الإنذار للتدقيق. هذه الطبقة الأخيرة هي ما يرفع الموثوقية المحاسبية
  /// إلى مستوى "لا يمكن أن يختل الرصيد أبدًا" — حتى لو فشل منطق أعلى منها.
  // ═══════════════════════════════════════════════════════════════════════
  // 🧮 كاشف الانحراف الحسابي بين الأجهزة
  //
  // المبدأ: لا يُكتب رصيد عميل أبداً من الشبكة. الرصيد يُشتقّ محلياً من
  // مجموع المعاملات وحده. لكن كل جهاز يرفع مع العميل «بصمة حسابية»:
  // مجموع المعاملات وعددها كما يراها هو. فإذا اكتملت دورة مزامنة وبقي
  // ما لديّ مخالفاً لما لدى غيري، لم يعد الانحراف قابلاً للمرور صامتاً —
  // يُسجَّل، ويُبلَّغ به المستخدم، ويُعاد بناء الرصيد من المعاملات.
  //
  // لماذا جدول منفصل يُنشأ عند الطلب؟ لأن الاعتماد على ترقية مخطط
  // قاعدة البيانات يجعل الكاشف نفسه عرضة للسقوط في الأجهزة القديمة،
  // والكاشف الذي قد يغيب لا قيمة له.
  // ═══════════════════════════════════════════════════════════════════════

  bool _expectationTableReady = false;

  Future<void> _ensureExpectationTable(DatabaseExecutor db) async {
    if (_expectationTableReady) return;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_balance_expectations (
          sync_uuid TEXT PRIMARY KEY,
          expected_balance REAL,
          expected_tx_count INTEGER,
          expected_fingerprint TEXT,
          expected_by_device TEXT,
          recorded_at TEXT,
          diff_value REAL,
          diff_since TEXT,
          diff_strikes INTEGER DEFAULT 0
        )
      ''');
      // أعمدة الضربات قد تغيب في جهاز أنشأ الجدول بنسخة أقدم
      for (final col in const [
        'diff_value REAL',
        'diff_since TEXT',
        'diff_strikes INTEGER DEFAULT 0',
      ]) {
        try {
          await db.execute('ALTER TABLE sync_balance_expectations ADD COLUMN $col');
        } catch (_) {/* موجود سلفاً */}
      }
      _expectationTableReady = true;
    } catch (e) {
      print('⚠️ _ensureExpectationTable: $e');
    }
  }

  /// يحسب البصمة الحسابية لعميل من المعاملات المحلية (مصدر الحقيقة الوحيد).
  Future<Map<String, dynamic>> _computeCustomerExpectation(String syncUuid) async {
    try {
      final db = await _db.database;
      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(t.amount_changed), 0) AS total,
          COUNT(t.id) AS cnt
        FROM customers c
        LEFT JOIN transactions t
          ON t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0)
        WHERE c.sync_uuid = ?
      ''', [syncUuid]);
      if (rows.isEmpty) {
        return {'balance': null, 'count': null, 'fingerprint': null};
      }
      final total = (rows.first['total'] as num?)?.toDouble() ?? 0.0;
      final cnt = (rows.first['cnt'] as num?)?.toInt() ?? 0;
      return {
        'balance': double.parse(total.toStringAsFixed(2)),
        'count': cnt,
        'fingerprint': '${total.toStringAsFixed(2)}|$cnt',
      };
    } catch (e) {
      print('⚠️ _computeCustomerExpectation: $e');
      return {'balance': null, 'count': null, 'fingerprint': null};
    }
  }

  /// يخزّن البصمة الواردة من جهاز آخر — دون أن يمسّ أي رصيد.
  Future<void> _rememberExpectation(String syncUuid, Map<String, dynamic> data) async {
    final raw = data['expectedBalance'];
    if (raw is! num) return; // جهاز بنسخة أقدم لا يرسل بصمة — لا شيء لنقارنه
    try {
      final db = await _db.database;
      await _ensureExpectationTable(db);
      if (!_expectationTableReady) return;
      await db.insert(
        'sync_balance_expectations',
        {
          'sync_uuid': syncUuid,
          'expected_balance': raw.toDouble(),
          'expected_tx_count': (data['expectedTxCount'] as num?)?.toInt(),
          'expected_fingerprint': data['expectedFingerprint']?.toString(),
          'expected_by_device': data['expectedByDevice']?.toString() ??
              data['originDeviceId']?.toString(),
          'recorded_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('⚠️ _rememberExpectation: $e');
    }
  }

  /// 🔍 يُستدعى بعد اكتمال دورة المزامنة (تنزيل ثم رفع).
  /// يقارن كل بصمة واردة بما لدى هذا الجهاز فعلياً، ويُبلّغ عن كل فرق.
  /// لا يكتب أي رصيد من الشبكة؛ غاية إصلاحه أن يعيد اشتقاق الرصيد من
  /// المعاملات المحلية — وهو حساب، لا استيراد.
  Future<Map<String, dynamic>> verifyExpectedBalances({bool repair = true}) async {
    final List<Map<String, dynamic>> divergences = [];
    int checked = 0;
    try {
      final db = await _db.database;
      await _ensureExpectationTable(db);
      if (!_expectationTableReady) {
        return {'checked': 0, 'divergences': divergences};
      }

      final rows = await db.rawQuery('''
        SELECT
          e.sync_uuid              AS uuid,
          e.expected_balance       AS expected,
          e.expected_tx_count      AS expected_count,
          e.expected_by_device     AS by_device,
          e.recorded_at            AS recorded_at,
          e.diff_value             AS prev_diff,
          e.diff_since             AS diff_since,
          e.diff_strikes           AS strikes,
          c.id                     AS cid,
          c.name                   AS name,
          c.current_total_debt     AS stored,
          COALESCE((SELECT SUM(t.amount_changed) FROM transactions t
                    WHERE t.customer_id = c.id
                      AND (t.is_deleted IS NULL OR t.is_deleted = 0)), 0) AS computed,
          COALESCE((SELECT COUNT(t.id) FROM transactions t
                    WHERE t.customer_id = c.id
                      AND (t.is_deleted IS NULL OR t.is_deleted = 0)), 0) AS cnt,
          COALESCE((SELECT COUNT(t.id) FROM transactions t
                    WHERE t.customer_id = c.id
                      AND (t.is_deleted IS NULL OR t.is_deleted = 0)
                      AND (t.is_uploaded IS NULL OR t.is_uploaded = 0)), 0) AS pending,
          (SELECT MAX(COALESCE(t.created_at, t.transaction_date)) FROM transactions t
                    WHERE t.customer_id = c.id
                      AND (t.is_deleted IS NULL OR t.is_deleted = 0)) AS newest_tx
        FROM sync_balance_expectations e
        JOIN customers c ON c.sync_uuid = e.sync_uuid
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
      ''');

      final String nowIso = DateTime.now().toIso8601String();

      for (final r in rows) {
        checked++;
        final expected = (r['expected'] as num?)?.toDouble();
        if (expected == null) continue;
        final computed = (r['computed'] as num?)?.toDouble() ?? 0.0;
        final stored = (r['stored'] as num?)?.toDouble() ?? 0.0;
        final cid = r['cid'] as int;
        final uuid = r['uuid'] as String;

        // ① انحراف داخلي: المخزَّن ≠ مجموع معاملاتي. خطأ محلي صِرف،
        //    وإصلاحه اشتقاقٌ من معاملاتي لا استيرادٌ من الشبكة — فيُصلَح فوراً.
        if (repair && (stored - computed).abs() > 0.01) {
          await db.update(
            'customers',
            {
              'current_total_debt': computed,
              'last_modified_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: [cid],
          );
          SyncDiagnostics.log('sync',
              'تصحيح داخلي: العميل ${r['name']} كان $stored والصحيح $computed');
        }

        final diff = computed - expected;

        // ② تطابق: امسح أي ضربات سابقة.
        if (diff.abs() <= 0.01) {
          if (((r['strikes'] as num?)?.toInt() ?? 0) > 0) {
            await db.update('sync_balance_expectations',
                {'diff_value': null, 'diff_since': null, 'diff_strikes': 0},
                where: 'sync_uuid = ?', whereArgs: [uuid]);
          }
          continue;
        }

        // ③ حارسان يمنعان الإنذار الكاذب — الفرق هنا متوقَّع لا مَرَضيّ:
        //    (أ) عندي معاملات لم تُرفع بعد، فمن الطبيعي ألّا يراها الآخر.
        //    (ب) بصمة الآخر أقدم من أحدث معاملة عندي، أي أنها قديمة أصلاً.
        final pending = (r['pending'] as num?)?.toInt() ?? 0;
        if (pending > 0) continue;

        final recordedAt = DateTime.tryParse((r['recorded_at'] ?? '').toString());
        final newestTx = DateTime.tryParse((r['newest_tx'] ?? '').toString());
        if (recordedAt != null && newestTx != null && newestTx.isAfter(recordedAt)) {
          continue; // بصمة متجاوَزة زمنياً — لا معنى لمقارنتها
        }

        // ④ ضربتان قبل الصراخ: فرقٌ عابر يزول في الدورة التالية،
        //    والباقي بعد دورتين انحرافٌ حقيقي يستحق أن يُقال.
        final prevDiff = (r['prev_diff'] as num?)?.toDouble();
        final sameAsBefore = prevDiff != null && (prevDiff - diff).abs() <= 0.01;
        final strikes = sameAsBefore
            ? (((r['strikes'] as num?)?.toInt() ?? 0) + 1)
            : 1;

        await db.update(
            'sync_balance_expectations',
            {
              'diff_value': diff,
              'diff_since': sameAsBefore
                  ? ((r['diff_since'] ?? nowIso).toString())
                  : nowIso,
              'diff_strikes': strikes,
            },
            where: 'sync_uuid = ?',
            whereArgs: [uuid]);

        if (strikes < 2) {
          print('🔎 فرق مبدئي للعميل ${r['name']}: $diff — '
              'بانتظار دورة أخرى قبل الحكم');
          continue;
        }

        // ⑤ انحراف مؤكَّد. لا يُصلَح هنا: إصلاحه يعني تصديق رقمٍ لم أرَ
        //    معاملاته. يُسجَّل ويُبلَّغ ليُحسم بزر المطابقة أو بقرار بشري.
        final entry = <String, dynamic>{
          'syncUuid': uuid,
          'customerId': cid,
          'name': r['name'],
          'localSum': computed,
          'remoteExpected': expected,
          'difference': diff,
          'localTxCount': (r['cnt'] as num?)?.toInt() ?? 0,
          'remoteTxCount': (r['expected_count'] as num?)?.toInt(),
          'reportedBy': r['by_device'],
          'since': r['diff_since'],
          'strikes': strikes,
        };
        divergences.add(entry);
        print('🚨🧮 انحراف مؤكَّد بين الأجهزة — ${r['name']}: '
            'عندي $computed، وعند ${r['by_device']} $expected '
            '(الفرق $diff، مستمر منذ ${r['diff_since']})');
        SyncDiagnostics.log('sync',
            'انحراف مؤكَّد للعميل ${r['name']} ($uuid): '
            'محلي=$computed (${entry['localTxCount']} معاملة) '
            'بعيد=$expected (${entry['remoteTxCount']} معاملة) '
            'الفرق=$diff — لم يُكتب أي رصيد من الشبكة؛ استخدم زر المطابقة.');
      }

      if (divergences.isNotEmpty) {
        _syncEventController.add(
            '🚨 ${divergences.length} عميل بأرصدة مختلفة بين الأجهزة — راجع سجل المزامنة');
      } else if (checked > 0) {
        print('✅ 🧮 تطابق حسابي: $checked عميل فُحِصوا، صفر انحراف مؤكَّد');
      }
    } catch (e) {
      print('⚠️ verifyExpectedBalances: $e');
    }
    return {'checked': checked, 'divergences': divergences};
  }

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
        // 🛡️ لا ندمج هويتين مزامنتين مختلفتين أبداً. الدمج المحلي ينقل معاملات
        // هوية إلى أخرى على هذا الجهاز وحده، فتختلف أرصدة كل عميل بين الأجهزة
        // (المحاكاة: سيناريو 13). ندمج فقط السجلات المحلية القديمة التي لم
        // تُعطَ هوية مزامنة قط، في سجل واحد (ذي هوية إن وُجد).
        final withId = entry.value
            .where((c) => (c['sync_uuid'] as String? ?? '').isNotEmpty)
            .toList();
        final legacy = entry.value
            .where((c) => (c['sync_uuid'] as String? ?? '').isEmpty)
            .toList();
        if (legacy.isEmpty) continue;
        final list = <Map<String, dynamic>>[
          ...legacy,
          if (withId.isNotEmpty) withId.first,
        ];
        if (list.length <= 1) continue; // لا يوجد تكرار

        print('🧹 [FirebaseSyncService] اكتشاف ${list.length} عميل مكرر باسم: "${list.first['name']}" -> جاري الدمج والتنظيف...');

        // اختيار العميل الرئيسي: نفضل الذي أُنكئ محلياً أولاً أو أقدم ID
        list.sort((a, b) {
          // السجل ذو الهوية (إن وُجد) هو الأساس دائماً، فلا تضيع هويته
          final aHasId = (a['sync_uuid'] as String? ?? '').isNotEmpty ? 1 : 0;
          final bHasId = (b['sync_uuid'] as String? ?? '').isNotEmpty ? 1 : 0;
          if (aHasId != bHasId) return bHasId.compareTo(aHasId);
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

        // ═══════════════════════════════════════════════════════════════
        // 🛡️ لا نجمع دفترين ماليين لمجرد تطابق الاسم
        // ═══════════════════════════════════════════════════════════════
        //
        // «اسمان متطابقان = شخص واحد» معيار لا يصح في سوق يتكرر فيه الاسم.
        // وكان الدمج تلقائياً عند كل بدء مزامنة، وبحذف نهائي (db.delete)
        // لا رجعة فيه.
        //
        // القاعدة الآمنة: نُدمج فقط حين يكون واحد على الأكثر يملك حركة
        // مالية — وهذه حالة التكرار الحقيقية (أُدخل العميل مرتين). أما
        // سجلّان لكل منهما معاملاته فقد يكونان شخصين، والدمج يخلط ديونهما
        // بلا رجعة. تلك تُترك لقرار إنسان.
        int ledgersWithHistory = 0;
        final Map<int, int> txCounts = {};
        for (final c in list) {
          final cid = c['id'] as int;
          final r = await db.rawQuery(
            'SELECT COUNT(*) AS n FROM transactions '
            'WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
            [cid],
          );
          final n = (r.first['n'] as num?)?.toInt() ?? 0;
          txCounts[cid] = n;
          if (n > 0) ledgersWithHistory++;
        }

        if (ledgersWithHistory > 1) {
          print('🛑 [FirebaseSyncService] تخطّي دمج «${list.first['name']}»: '
              '$ledgersWithHistory سجلات تحمل معاملات — قد يكونون أشخاصاً '
              'مختلفين بنفس الاسم. يحتاج قرار المستخدم.');
          _syncEventController.add(
              'تنبيه: عميلان بالاسم «${list.first['name']}» ولكلٍّ معاملاته — '
              'لم يُدمجا تلقائياً');
          continue; // لا دمج
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

          // 3) 🛡️ حذف منطقي لا نهائي: الصف يبقى للتدقيق ويمكن استرجاعه
          await db.update(
            'customers',
            {
              'is_deleted': 1,
              'current_total_debt': 0.0,
              'last_modified_at': DateTime.now().toIso8601String(),
            },
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
  ///
  /// 🛡️ يقرأ الصف الحالي من القاعدة دائماً — ما يُمرَّر (من طابور الإعادة أو
  /// WAL أو الشاشات) قد يكون لقطة قديمة.
  Future<bool> uploadCustomer(Map<String, dynamic> customerData) async {
    if (!_isInitialized || _groupId == null) return true;
    // 🛡️ أوفلاين: لا ننتظر مهلة 60 ثانية تحبس القفل — المعلّق يُلتقط عند العودة
    if (_status == FirebaseSyncStatus.offline) return false;
    // 🛡️ وضع الاستعادة: لا رفع من نسخة احتياطية قبل مقارنتها بالسحابة
    if (_recoveryMode) return false;

    final syncUuid = customerData['sync_uuid'] as String?;
    if (syncUuid == null || syncUuid.isEmpty) return true;

    // 🛡️ نفس الحماية المطبّقة على المعاملات: معرّف غير صالح يُسقط التطبيق أصلياً
    if (!SyncSecurity.isValidDocumentId(syncUuid)) {
      print('❌ تخطي رفع عميل بمعرّف غير صالح لـ Firestore: $syncUuid');
      return true;
    }

    // 🔒 القفل يُؤخذ قبل أي await (الفحص ثم الانتظار ثم الأخذ كان يسمح برفعين متوازيين)
    final lockKey = 'customer_$syncUuid';
    if (_uploadLocks[lockKey] == true) return true;
    _uploadLocks[lockKey] = true;

    String? walOperationId;
    Map<String, dynamic> row = customerData;
    try {
      final db = await _db.database;
      final fresh = await db.query('customers',
          where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
      if (fresh.isEmpty) return true;
      row = Map<String, dynamic>.from(fresh.first);

      if (!_validateCustomerData(row)) {
        print('❌ بيانات العميل غير صالحة - تم تخطي الرفع');
        return true;
      }

      final tomb = (row['tombstoned'] as int?) ?? 0;
      final pendingTomb = tomb == 2 || tomb == 3;
      final isMine = (row['is_created_by_me'] as int?) != 0;
      // 🛡️ وثيقة العميل يرفعها منشئه وحده. غيره كان يرفعها (فاتورة لعميل جهاز
      // آخر مثلاً) فيسرق منها deviceId ويُفقد المنشئ ملكيته. الاستثناء: شاهد
      // حذف أو إعادة تنشيط قام بهما هذا الجهاز.
      if (!isMine && !pendingTomb) return true;

      if (!pendingTomb && await _coordinator!.isFirebaseSynced('customer', syncUuid)) {
        final lastModified = row['last_modified_at'] as String?;
        final syncedAt = row['synced_at'] as String?;
        bool needsReupload = false;
        if (lastModified != null && syncedAt != null) {
          final lm = DateTime.tryParse(lastModified);
          final sa = DateTime.tryParse(syncedAt);
          needsReupload = lm == null || sa == null || lm.isAfter(sa);
        } else if (syncedAt == null) {
          needsReupload = true;
        }
        if (!needsReupload) return true;
      }

      // 🔧 Rate limiting: المحجوب «فشل» يُعاد لاحقاً، لا «نجاح» يُسقط العملية
      if (!_rateLimiter.canProceed()) return false;
      _rateLimiter.recordOperation();

      // 🛡️ تسجيل في WAL قبل الرفع
      if (_crashRecovery != null) {
        walOperationId = await _crashRecovery!.beginOperation(
          type: 'customer',
          action: 'create',
          syncUuid: syncUuid,
          data: row,
        );
        await _crashRecovery!.markUploading(walOperationId);
      }

      final checksum = _calculateChecksum(row);
      final bool isDeleted = tomb == 2 || ((row['is_deleted'] as int?) ?? 0) == 1;
      final now = DateTime.now();
      final Map<String, dynamic> expectation =
          await _computeCustomerExpectation(syncUuid);

      final doc = <String, dynamic>{
        'syncUuid': syncUuid,
        'name': row['name'],
        'phone': row['phone'],
        'currentTotalDebt': isDeleted ? 0.0 : row['current_total_debt'],
        'expectedBalance': isDeleted ? 0.0 : expectation['balance'],
        'expectedTxCount': expectation['count'],
        'expectedFingerprint': expectation['fingerprint'],
        'expectedByDevice': _deviceId,
        'generalNote': row['general_note'],
        'address': row['address'],
        'createdAt': row['created_at'],
        'lastModifiedAt': row['last_modified_at'] ?? now.toIso8601String(),
        'audioNotePath': row['audio_note_path'],
        'deviceId': _deviceId,
        'originDeviceId': _deviceId, // 🔍 للتتبع والتدقيق
        'checksum': checksum,
        'uploadedAt': FieldValue.serverTimestamp(),
      };
      // 🛡️ isDeleted يُكتب فقط عند حذف أو إعادة تنشيط صريحين: رفعٌ عادي بـ
      // merge لا يمحو شاهد حذف كتبه جهاز آخر في الوقت نفسه.
      if (tomb == 2) {
        doc['isDeleted'] = true;
        doc['is_deleted'] = 1;
        doc['deletedAt'] = now.toIso8601String();
      } else if (tomb == 3) {
        doc['isDeleted'] = false;
        doc['is_deleted'] = 0;
      }
      doc['signature'] = _signDoc(syncUuid, doc, isCustomer: true);

      await _firestore!
          .collection('customers')
          .doc(syncUuid)
          .set(doc, SetOptions(merge: true))
          .timeout(const Duration(seconds: 60));

      await _coordinator!.registerOperation(
        entityType: 'customer',
        syncUuid: syncUuid,
        source: SyncSource.local,
        checksum: checksum,
      );
      await _coordinator!.markFirebaseSynced('customer', syncUuid);

      await db.update('customers', {'synced_at': now.toIso8601String()},
          where: 'sync_uuid = ?', whereArgs: [syncUuid]);
      if (tomb == 2) {
        await db.update('customers', {'tombstoned': 1},
            where: 'sync_uuid = ? AND tombstoned = 2', whereArgs: [syncUuid]);
      } else if (tomb == 3) {
        await db.update('customers', {'tombstoned': 0},
            where: 'sync_uuid = ? AND tombstoned = 3', whereArgs: [syncUuid]);
      }

      await _operationTracker?.trackCreate(
        syncUuid: syncUuid,
        entityType: 'customer',
        data: row,
      );

      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markSynced(walOperationId);
      }

      print('☁️ رُفع العميل: ${row['name']} ($syncUuid)${tomb == 2 ? " [شاهد حذف]" : ""}');
      return true;
    } catch (e) {
      print('❌ فشل رفع العميل $syncUuid: $e');
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markFailed(walOperationId, e.toString());
      }
      await _addToRetryQueue(_RetryOperation(
        type: 'customer',
        syncUuid: syncUuid,
        data: row,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
      return false;
    } finally {
      _uploadLocks.remove(lockKey);
    }
  }

  /// بصمة الحقول المالية لمعاملة — للمقارنة قبل الرفع وبعده (CAS).
  String _txFingerprint(Map<String, dynamic> t) =>
      '${(t['amount_changed'] as num?)?.toDouble()}|${t['transaction_type']}|'
      '${t['is_deleted'] ?? 0}|${t['customer_id']}|${t['transaction_note']}|${t['invoice_sync_uuid']}';

  /// رفع معاملة جديدة أو محدثة
  /// يرجع true عند النجاح (أو عند تخطي مقصود)، و false عند فشل الرفع
  ///
  /// [force] يعيد الرفع حتى لو كانت معلّمة محلياً كمرفوعة — للمطابقة فقط.
  ///
  /// 🛡️ ضمانات:
  ///   • تُقرأ المعاملة من القاعدة لحظة الرفع (طابور الإعادة وWAL يحملان لقطات
  ///     قديمة كانت تُرفع فوق نسخة أحدث — سيناريو 09).
  ///   • CAS: لا تُعلَّم «مرفوعة» إلا إن لم تتغير منذ قراءتها؛ وإلا تبقى معلّقة.
  ///   • لا تُرفع معاملة جهاز آخر أبداً — إلا شاهد حذف ناتج عن حذف عميل هنا.
  ///   • معاملة فاتورة نشطة لا تُرفع هنا: تسافر داخل حزمة الفاتورة وحدها.
  Future<bool> uploadTransaction(
    Map<String, dynamic> txData,
    String customerSyncUuid, {
    bool force = false,
  }) async {
    if (!_isInitialized || _groupId == null) return true;
    if (_status == FirebaseSyncStatus.offline) return false;
    if (_recoveryMode) return false;

    final syncUuid = (txData['transaction_uuid'] as String?) ?? '';
    if (syncUuid.isEmpty) return true;

    // 🛡️ معرّف غير صالح (يحتوي فاصل مسار مثلاً) يُنهي التطبيق داخل مكتبة Firestore
    if (!SyncSecurity.isValidDocumentId(syncUuid)) {
      print('❌ تخطي رفع معاملة بمعرّف غير صالح لـ Firestore: $syncUuid');
      return true;
    }

    // 🔒 القفل قبل أي await
    final lockKey = 'transaction_$syncUuid';
    if (_uploadLocks[lockKey] == true) return true;
    _uploadLocks[lockKey] = true;

    String? walOperationId;
    Map<String, dynamic> tx = Map<String, dynamic>.from(txData);
    String custUuid = customerSyncUuid;
    try {
      final db = await _db.database;
      final rows = await db.rawQuery(
        'SELECT t.*, c.sync_uuid AS _customer_sync_uuid FROM transactions t '
        'LEFT JOIN customers c ON c.id = t.customer_id '
        'WHERE t.transaction_uuid = ? LIMIT 1',
        [syncUuid],
      );
      if (rows.isEmpty) return true;
      tx = Map<String, dynamic>.from(rows.first);
      final cs = tx.remove('_customer_sync_uuid') as String?;
      if (cs != null && cs.isNotEmpty) custUuid = cs;

      final isMine = (tx['is_created_by_me'] as int?) != 0; // NULL = قديم = من هذا الجهاز
      final isTxDeleted = ((tx['is_deleted'] as int?) ?? 0) == 1;
      if (!isMine && !isTxDeleted) {
        return true; // تخطٍ مقصود — ليس فشلاً يُعاد
      }
      if (!force && (tx['is_uploaded'] as int?) == 1) return true;

      final invUuid = tx['invoice_sync_uuid'] as String?;
      if (!isTxDeleted && invUuid != null && invUuid.isNotEmpty) {
        return true; // حزمة الفاتورة هي القناة الوحيدة لمعاملات الفواتير
      }

      if (!_validateTransactionData(tx)) {
        print('❌ بيانات المعاملة غير صالحة - تم تخطي الرفع');
        return true;
      }

      if (!_rateLimiter.canProceed()) return false;
      _rateLimiter.recordOperation();

      // 🛡️ تسجيل في WAL قبل الرفع
      if (_crashRecovery != null) {
        final walData = Map<String, dynamic>.from(tx);
        walData['customer_sync_uuid'] = custUuid;
        walOperationId = await _crashRecovery!.beginOperation(
          type: 'transaction',
          action: 'create',
          syncUuid: syncUuid,
          data: walData,
        );
        await _crashRecovery!.markUploading(walOperationId);
      }

      final sentFingerprint = _txFingerprint(tx);
      final checksum = _calculateChecksum(tx);
      final nowIso = DateTime.now().toIso8601String();
      final doc = <String, dynamic>{
        'syncUuid': syncUuid,
        'customerSyncUuid': custUuid,
        'invoiceSyncUuid': tx['invoice_sync_uuid'],
        'transactionDate': tx['transaction_date'],
        'amountChanged': tx['amount_changed'],
        'balanceBeforeTransaction': tx['balance_before_transaction'],
        'newBalanceAfterTransaction': tx['new_balance_after_transaction'],
        'transactionNote': tx['transaction_note'],
        'transactionType': tx['transaction_type'],
        'description': tx['description'],
        'createdAt': tx['created_at'],
        'lastModifiedAt': nowIso,
        'audioNotePath': tx['audio_note_path'],
        'deviceId': _deviceId,
        'originDeviceId': isMine ? _deviceId : (tx['origin_device_id'] ?? _deviceId),
        'checksum': checksum,
        'uploadedAt': FieldValue.serverTimestamp(),
      };
      // 🛡️ لا نكتب isDeleted=false أبداً: تعديل يُرفع (merge) بعد شاهد حذف
      // كتبه جهاز حذف العميل لا يجوز أن «يُحيي» المعاملة. الحذف نهائي.
      if (isTxDeleted) {
        doc['isDeleted'] = true;
        doc['is_deleted'] = 1;
      }
      doc['signature'] = _signDoc(syncUuid, doc);

      await _firestore!
          .collection('transactions')
          .doc(syncUuid)
          .set(doc, SetOptions(merge: true))
          .timeout(const Duration(seconds: 60));

      await _coordinator!.registerOperation(
        entityType: 'transaction',
        syncUuid: syncUuid,
        source: SyncSource.local,
        checksum: checksum,
      );
      await _coordinator!.markFirebaseSynced('transaction', syncUuid);

      // 🛡️ CAS: «مرفوعة» فقط إن لم تتغير المعاملة أثناء الرفع
      final cur = await db.query('transactions',
          where: 'transaction_uuid = ?', whereArgs: [syncUuid], limit: 1);
      if (cur.isNotEmpty) {
        if (_txFingerprint(cur.first) == sentFingerprint) {
          await db.update('transactions', {'is_uploaded': 1, 'last_uploaded_at': nowIso},
              where: 'transaction_uuid = ?', whereArgs: [syncUuid]);
        } else {
          await db.update('transactions', {'is_uploaded': 0},
              where: 'transaction_uuid = ?', whereArgs: [syncUuid]);
        }
      }

      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markSynced(walOperationId);
      }
      return true;
    } catch (e) {
      print('❌ فشل رفع المعاملة $syncUuid: $e');
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markFailed(walOperationId, e.toString());
      }
      final retryData = Map<String, dynamic>.from(tx);
      retryData['customer_sync_uuid'] = custUuid;
      await _addToRetryQueue(_RetryOperation(
        type: 'transaction',
        syncUuid: syncUuid,
        data: retryData,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
      return false;
    } finally {
      _uploadLocks.remove(lockKey);
    }
  }

  /// شرط SQL لـ«معاملة يجب أن يرفعها هذا الجهاز»: أملكها ولم تُرفع (بما فيها
  /// المحذوفة = شاهد حذف)، أو معاملة غيري أبطلها حذفي أنا للعميل.
  /// معاملات الفواتير النشطة مستثناة: تسافر داخل حزمة الفاتورة.
  static const String _ownedPendingWhere =
      "t.transaction_uuid IS NOT NULL AND t.transaction_uuid != '' "
      "AND (t.is_uploaded = 0 OR t.is_uploaded IS NULL) "
      "AND ((t.is_created_by_me = 1 OR t.is_created_by_me IS NULL) "
      "     OR (t.is_created_by_me = 0 AND t.is_deleted = 1)) "
      "AND (t.invoice_sync_uuid IS NULL OR t.invoice_sync_uuid = '' OR t.is_deleted = 1)";

  /// 🛡️ يرفع كل ما يجب أن يرفعه هذا الجهاز — مهما كان منشئ العميل ومهما قال
  /// المنسق. (Watchdog كان يتخطى أي معاملة سبق رفعها مرة، فالتعديلات اللاحقة
  /// عليها لا تُرفع أبداً إلا لعملاء أنشأهم هذا الجهاز.)
  Future<int> uploadAllOwnedPending({int? limit}) => _uploadAllOwnedPending(limit: limit);

  Future<int> _uploadAllOwnedPending({int? limit}) async {
    if (!_isInitialized || _groupId == null || _recoveryMode) return 0;
    if (_status == FirebaseSyncStatus.offline) return 0;
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT t.*, c.sync_uuid AS customer_sync_uuid
      FROM transactions t
      JOIN customers c ON c.id = t.customer_id
      WHERE c.sync_uuid IS NOT NULL AND c.sync_uuid != '' AND $_ownedPendingWhere
      ORDER BY t.transaction_date ASC, t.id ASC
      ${limit != null ? 'LIMIT $limit' : ''}
    ''');
    int ok = 0;
    for (final r in rows) {
      final cs = r['customer_sync_uuid'] as String;
      try {
        if (await uploadTransaction(Map<String, dynamic>.from(r), cs)) ok++;
      } catch (e) {
        print('⚠️ رفع معلّق ${r['transaction_uuid']}: $e');
      }
    }
    return ok;
  }

  /// 🗑️ رفع حذف عميل فوراً: شاهد العميل + شاهد لكل معاملة كانت معروفة هنا
  /// (حتى معاملات الأجهزة الأخرى، ومعاملات الفواتير). كل جهاز يُبطل بالضبط ما
  /// أبطله هذا الجهاز، وما سُجّل أوفلاين بعد الحذف يبقى ويعيد تنشيط العميل.
  Future<void> syncCustomerDeletionNow(int customerId) async {
    if (!_isInitialized || _groupId == null) return;
    try {
      final db = await _db.database;
      final rows = await db.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (rows.isEmpty) return;
      final c = rows.first;
      final cs = c['sync_uuid'] as String?;
      if (cs == null || cs.isEmpty) return;
      await uploadCustomer(c);
      final pend = await db.rawQuery(
        'SELECT t.* FROM transactions t WHERE t.customer_id = ? AND $_ownedPendingWhere',
        [customerId],
      );
      for (final t in pend) {
        await uploadTransaction(Map<String, dynamic>.from(t), cs);
      }
    } catch (e) {
      print('⚠️ رفع حذف العميل $customerId: $e (ستتكفل به المزامنة الخلفية)');
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
        try {
          if (data['deviceId'] == _deviceId) {
            // مستندي: قد يحمل شاهد حذف مدموجاً، أو عميلاً فقدتُه باستعادة نسخة
            await _handleOwnCustomerDoc(doc.id, data);
            continue;
          }
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

    // 2️⃣ المعاملات (كل مستند يحمل إصداره uploadedAt، فلا تُطبَّق نسخة أقدم
    // مما وصل عبر المستمع أثناء هذه الدورة الطويلة)
    try {
      final txSnap = await _firestore!.collection('transactions').get().timeout(
            const Duration(seconds: 120),
          );
      int appliedTx = 0;
      for (final doc in txSnap.docs) {
        final data = doc.data();
        try {
          if (data['deviceId'] == _deviceId) {
            await _handleOwnTxDoc(doc.id, data);
            continue;
          }
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

    // 3️⃣ حركات المخزون (المستمع يلتقط الجديد؛ هذا لما فاته)
    try {
      final n = await StockMovementSyncService().downloadAll();
      if (n > 0) print('✅ [Catch-Up] حركات مخزون: طُبّق $n');
    } catch (e) {
      print('❌ [Catch-Up] فشل سحب حركات المخزون: $e');
    }

    print('✅ [Catch-Up] اكتمل السحب الكامل');
    // ⚖️ قرارات الإبطال عن بُعد لم تعد تُطبَّق (انظر MatchVerdictService).
  }

  /// 🚀 رفع فوري لعميل محدد ومعاملاته المعلقة (يُستدعى لحظة إنشاء/تعديل العميل).
  ///
  /// 🛡️ لعميل أنشأه جهاز آخر: لا نرفع وثيقته (يرفعها منشئه)، لكن نرفع
  /// معاملاتي المعلّقة عليه. كانت هذه الدالة تعود فوراً لعملاء الأجهزة الأخرى،
  /// فتعديلات معاملاتي عليهم لا تُرفع أبداً (سيناريو 33).
  Future<void> syncCustomerNow(int customerId) async {
    if (!_isInitialized || _groupId == null) return;

    try {
      final db = await _db.database;
      final rows = await db.query('customers',
          where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (rows.isEmpty) return;
      final customer = rows.first;
      final customerSyncUuid = customer['sync_uuid'] as String?;
      if (customerSyncUuid == null || customerSyncUuid.isEmpty) return;

      final isMine = (customer['is_created_by_me'] as int?) != 0;
      final tomb = (customer['tombstoned'] as int?) ?? 0;
      final isDeleted = ((customer['is_deleted'] as int?) ?? 0) == 1;
      if ((isMine && !isDeleted) || tomb == 2 || tomb == 3) {
        final customerOk = await uploadCustomer(customer);
        if (!customerOk) return;
      }

      final pendingTx = await db.rawQuery(
        'SELECT t.* FROM transactions t WHERE t.customer_id = ? AND $_ownedPendingWhere '
        'ORDER BY t.transaction_date ASC, t.id ASC',
        [customerId],
      );

      for (final tx in pendingTx) {
        try {
          await uploadTransaction(Map<String, dynamic>.from(tx), customerSyncUuid);
        } catch (e) {
          print('⚠️ [رفع فوري] فشل رفع معاملة ${tx['transaction_uuid']}: $e '
              '(ستُعاد تلقائياً)');
        }
      }

      if (pendingTx.isNotEmpty) {
        print('🚀 [رفع فوري] العميل "${customer['name']}": ${pendingTx.length} معاملة');
      }
    } catch (e) {
      print('⚠️ [رفع فوري] فشل رفع العميل $customerId: $e (ستتكفل به المزامنة الخلفية)');
    }
  }

  Future<void> _syncPendingChanges({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (!_isInitialized || _groupId == null) return;
    if (_recoveryMode) return; // وضع الاستعادة: الرفع بعد اكتمال المقارنة

    print('🔄 جاري مزامنة التغييرات المعلقة...');

    final db = await _db.database;

    // 🎯 وثائق العملاء: ما أنشأه هذا الجهاز وتغيّر، + كل شاهد حذف/تنشيط محلي
    // بانتظار الرفع (حتى لعملاء أجهزة أخرى).
    final customers = await db.query(
      'customers',
      where:
          "sync_uuid IS NOT NULL AND sync_uuid != '' AND ("
          "  ((is_deleted IS NULL OR is_deleted = 0) "
          "   AND (synced_at IS NULL OR last_modified_at > synced_at) "
          "   AND (is_created_by_me = 1 OR is_created_by_me IS NULL)) "
          "  OR tombstoned IN (2, 3))",
      orderBy: 'id ASC',
    );

    final totalCustomers = customers.length;
    var processedCustomers = 0;

    for (final customer in customers) {
      final customerName = customer['name'] as String? ?? '';
      try {
        await uploadCustomer(customer);
      } catch (e) {
        print('⚠️ فشل رفع العميل $customerName: $e');
      }
      processedCustomers++;
      if (totalCustomers > 0 && onProgress != null) {
        final p = (processedCustomers / totalCustomers) * 0.5;
        onProgress(p, 'رفع العملاء ($processedCustomers/$totalCustomers)...');
      }
    }

    // 🛡️ كل معاملة يجب أن يرفعها هذا الجهاز — بغض النظر عن منشئ العميل.
    // (معاملة وصلت قبل عميلها لا تضيع: الجهاز المستقبل يحفظها يتيمة.)
    onProgress?.call(0.5, 'رفع المعاملات المعلّقة...');
    final uploaded = await _uploadAllOwnedPending();
    if (uploaded > 0) print('✅ رُفعت $uploaded معاملة معلّقة');

    // 3️⃣ رفع الفواتير والمنتجات غير المرفوعة (85-100%).
    onProgress?.call(0.85, 'جاري رفع الفواتير والمنتجات...');
    try {
      await InvoiceSyncService().syncPendingInvoices();
      await ProductSyncService().syncPendingProducts();
      await StockMovementSyncService().uploadPending();
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

      // 🧮 محاكمة البصمات الحسابية الواردة بعد أن استقرّ التنزيل والرفع معاً.
      // قبل هذه النقطة الفروق طبيعية (وصل العميل ولمّا تصل معاملاته)؛ بعدها
      // كل فرق باقٍ هو انحراف حقيقي يستحق أن يُقال.
      final expectationReport = await verifyExpectedBalances();
      final divergentList =
          expectationReport['divergences'] as List<Map<String, dynamic>>;
      if (divergentList.isNotEmpty) {
        print('🚨 [performFullSync] ${divergentList.length} انحراف حسابي بين الأجهزة');
      }

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
      // 🛡️ من الخادم لا من ذاكرة Firestore المحلية: على الجوال (persistence
      // مفعّلة) كان get() بلا إنترنت يعيد نسخة الذاكرة «بنجاح»، فتكتمل
      // الاستعادة على بيانات قديمة.
      customersSnapshot = await _firestore!
          .collection('customers')
          .get(const GetOptions(source: Source.server));
      
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
      } else {
        await _handleOwnCustomerDoc(doc.id, data);
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
        .get(const GetOptions(source: Source.server));

    final totalTransactions = transactionsSnapshot.docs.length;
    var processedTransactions = 0;

    for (final doc in transactionsSnapshot.docs) {
      final data = doc.data();
      if (data['deviceId'] != _deviceId) {
        await _applyTransactionChange(doc.id, data);
      } else {
        await _handleOwnTxDoc(doc.id, data);
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
    // 🛡️ فشل قراءة الفواتير يُفشل السحب الكامل (كان يُبتلع فتبدو المزامنة
    // مكتملة وحزم الفواتير لم تُقرأ — وعليه كانت تنتهي الاستعادة).
    await InvoiceSyncService().downloadAllInvoices(
      rethrowErrors: true,
      onProgress: (p, m) {
        onProgress?.call(0.85 + (p * 0.10), m);
      },
    );
    try {
      await ProductSyncService().downloadAllProducts();
    } catch (e) {
      print('⚠️ فشل تنزيل المنتجات أثناء المزامنة الشاملة: $e');
    }
    // 📦 حركات المخزون: فشلها يُفشل السحب الكامل (كالفواتير) — الجهاز المستعيد
    // أو الجديد بلا حركات يحسب كمية خاطئة.
    await StockMovementSyncService().downloadAll(rethrowErrors: true);

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
      
      // عدد العملاء في Firebase = الكل − شواهد الحذف.
      // 🛡️ isNotEqualTo يستبعد الوثائق التي لا تحمل الحقل أصلاً، والوثائق
      // الحية لم تعد تكتب isDeleted:false — فكان العدّ يُسقطها كلها.
      final remoteCustomersAll =
          await _firestore!.collection('customers').count().get();
      final remoteCustomersDel = await _firestore!
          .collection('customers')
          .where('isDeleted', isEqualTo: true)
          .count()
          .get();
      
      // عدد المعاملات محلياً
      final localTransactions = await db.query(
        'transactions',
        where: 'transaction_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      // عدد المعاملات في Firebase = الكل − شواهد الحذف
      final remoteTxAll =
          await _firestore!.collection('transactions').count().get();
      final remoteTxDel = await _firestore!
          .collection('transactions')
          .where('isDeleted', isEqualTo: true)
          .count()
          .get();
      
      // التحقق من التطابق
      final localCustomerCount = localCustomers.length;
      final remoteCustomerCount =
          (remoteCustomersAll.count ?? 0) - (remoteCustomersDel.count ?? 0);
      final localTxCount = localTransactions.length;
      final remoteTxCount = (remoteTxAll.count ?? 0) - (remoteTxDel.count ?? 0);
      
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
  // ═══════════════════════════════════════════════════════════════════════
  // 🆕 تمهيد الجهاز الجديد (Bootstrap)
  //
  // المشكلة التي يحلّها: التنظيف الذكي يحذف المستند من السحابة متى أقرّ
  // بقراءته كل جهاز مؤهَّل. فجهاز ينضم بعد ذلك لا يجد شيئاً — ينزّل
  // العملاء بأرصدة صفرية بلا معاملات. لم يكن لهذا مسار حيّ في الكود:
  // خدمة التمهيد موجودة كاملة لكن لا أحد يستدعيها، ودالة التنزيل فيها
  // لا تنزّل شيئاً أصلاً (تقرأ الإحصاءات ثم تُعلن النجاح).
  //
  // الحل هنا لا يبني بروتوكولاً جديداً: الجهاز الجديد يعلن حاجته، وجهاز
  // واحد من المجموعة يعيد بثّ كل دفتره إلى المجموعات المعتادة، فينزّله
  // الجديد بنفس المسار الإدمبوتنت المُجرَّب. لا مسار استيراد موازٍ،
  // ولا رصيد يُكتب من الشبكة.
  // ═══════════════════════════════════════════════════════════════════════

  StreamSubscription? _bootstrapRequestListener;
  bool _bootstrapResponding = false;

  /// يقرأ علَم الاستعادة (يضبطه DatabaseService بعد استعادة نسخة احتياطية).
  Future<void> _loadRecoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _recoveryMode = prefs.getBool(DatabaseService.restoredFlagKey) ?? false;
      if (_recoveryMode && !(prefs.getBool(DatabaseService.restoredRowsMarkedKey) ?? false)) {
        // استُبدل ملف القاعدة وهي مغلقة (Dropbox): نوسم الصفوف الآن
        final db = await _db.database;
        await db.rawUpdate('UPDATE transactions SET restored_mark = 1');
        await db.rawUpdate('UPDATE invoices SET restored_mark = 1 WHERE is_created_by_me = 1 OR is_created_by_me IS NULL');
        await prefs.setBool(DatabaseService.restoredRowsMarkedKey, true);
      }
      if (_recoveryMode) {
        print('🛡️ وضع الاستعادة: القاعدة من نسخة احتياطية — الرفع موقوف حتى المقارنة');
        _syncEventController.add('استعادة نسخة احتياطية: جاري طلب ما فاتها من الأجهزة الأخرى...');
      }
    } catch (e) {
      print('⚠️ _loadRecoveryState: $e');
    }
  }

  Future<void> _finishRecovery() async {
    if (!_recoveryMode) return;
    try {
      final db = await _db.database;
      await db.rawUpdate('UPDATE transactions SET restored_mark = 0 WHERE restored_mark = 1');
      // فاتورة من النسخة لم تحلّ محلها نسخة سحابية وفيها تغيير معلّق:
      // نسخة جديدة فوق كل ما سبق رفعه، ثم يُمحى الوسم.
      await db.rawUpdate('UPDATE invoices SET version = COALESCE(version, 1) + 1 '
          'WHERE restored_mark = 1 AND is_synced = 0');
      await db.rawUpdate('UPDATE invoices SET restored_mark = 0 WHERE restored_mark = 1');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(DatabaseService.restoredFlagKey);
      await prefs.remove(DatabaseService.restoredRowsMarkedKey);
    } catch (e) {
      print('⚠️ _finishRecovery: $e');
    }
    _recoveryMode = false;
    print('✅ اكتمل وضع الاستعادة — استُؤنف الرفع');
    _syncEventController.add('اكتملت استعادة البيانات من الأجهزة الأخرى');
    unawaited(_syncPendingChanges().catchError((_) {}));
    unawaited(StockMovementSyncService().uploadPending().catchError((_) => 0));
}

  /// 🛡️ تنزيل كامل يُبنى عليه إنهاء التمهيد/الاستعادة.
  ///
  /// كانت النتيجة تُهمل: performFullSync تعيد false بلا إنترنت، أو إن كانت
  /// مزامنة أخرى جارية، أو إن فشل سحب المعاملات — وتنزيل الفواتير يبتلع
  /// أخطاءه أصلاً. فتنتهي الاستعادة على بيانات النسخة الاحتياطية القديمة، ثم
  /// يعتبرها هذا الجهاز «نسختي المرجعية» فيرفعها فوق التعديلات الأحدث عند
  /// كل الأجهزة (اختبار الكود الحقيقي: test/sync_harness). الآن: نجاح حقيقي
  /// أو لا إنهاء، وتعيد الدورة الخلفية المحاولة.
  Future<bool> _downloadForBootstrap() async {
    final ok = await performFullSync();
    if (!ok) {
      print('⚠️ [Bootstrap] التنزيل الكامل لم يكتمل — لا إنهاء للتمهيد الآن');
    }
    return ok;
  }

  Future<void> _markBootstrapComplete(DocumentReference selfRef) async {
    await selfRef.set({'bootstrapCompletedAt': DateTime.now().toIso8601String()},
        SetOptions(merge: true));
    _bootstrapIncomplete = false;
    await _finishRecovery();
  }

  /// يُستدعى بعد تسجيل الجهاز. يطلب إعادة البث إن كان الجهاز جديداً (لم يكمل
  /// التمهيد قط) أو استُعيدت قاعدته من نسخة احتياطية.
  ///
  /// 🛡️ كان الشرط «دفتر غير فارغ ⇒ لست جديداً» فجهاز جديد عليه معاملة محلية
  /// واحدة (استُخدم أوفلاين قبل تفعيل المزامنة) لا يطلب شيئاً، ولا يحصل أبداً
  /// على تاريخ نظّفه SmartPipe من السحابة (سيناريو 27). وجهاز استعاد نسخة
  /// قديمة لم يكن يُكتشف أصلاً (سيناريو 26).
  Future<void> ensureNewDeviceBootstrap() async {
    if (_firestore == null || _deviceId == null || _groupId == null) return;
    if (_bootstrapping) return;
    _bootstrapping = true;
    try {
      // تُستدعى أثناء التهيئة: ننتظر اكتمالها (performFullSync يشترطه)
      for (var i = 0; i < 180 && !_isInitialized; i++) {
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!_isInitialized) return;
      // يُمحى عند التأكد من اكتمال التمهيد. قبل القراءة لا بعدها: قراءة فاشلة
      // (بلا إنترنت عند الإقلاع) كانت تُسقط التمهيد حتى التشغيل التالي.
      _bootstrapIncomplete = true;
      final selfRef = _firestore!.collection('devices').doc(_deviceId);
      final selfDoc = await selfRef.get().timeout(const Duration(seconds: 20));
      if (selfDoc.data()?['bootstrapCompletedAt'] != null && !_recoveryMode) {
        _bootstrapIncomplete = false;
        return;
      }

      // لا يوجد من يردّ ⇒ هذا أول جهاز في المجموعة، لا شيء ليُستقبل
      final devices =
          await _firestore!.collection('devices').get().timeout(const Duration(seconds: 20));
      final others = devices.docs.where((d) => d.id != _deviceId).length;
      if (others == 0) {
        // 🛡️ لا ننهي الاستعادة على تنزيل فاشل (انظر _downloadForBootstrap)
        if (_recoveryMode && !await _downloadForBootstrap()) return;
        await _markBootstrapComplete(selfRef);
        print('🆕 [Bootstrap] أول جهاز في المجموعة — لا حاجة للتمهيد');
        return;
      }

      print('🆕 [Bootstrap] طلب إعادة بثّ من $others جهاز '
          '(${_recoveryMode ? "استعادة نسخة احتياطية" : "جهاز جديد"})');
      _syncEventController.add('جاري استلام بيانات المجموعة من جهاز آخر...');

      final reqRef = _firestore!.collection('bootstrap_requests').doc(_deviceId);
      await reqRef.set({
        'requestedBy': _deviceId,
        'requestedAt': FieldValue.serverTimestamp(),
        'requestedAtIso': DateTime.now().toIso8601String(),
        'status': 'pending',
      });

      // الانتظار حتى يعلن أحدهم الجاهزية (10 دقائق كحد أقصى)
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      String status = 'pending';
      var lastNudge = DateTime.now();
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 10));
        Map<String, dynamic>? req;
        try {
          final snap = await reqRef.get();
          req = snap.data();
          status = (req?['status'] as String?) ?? 'pending';
        } catch (_) {}
        if (status == 'ready' || status == 'failed') break;

        // 🛡️ طلب لم يلبّه أحد (كل المستجيبين كانوا مشغولين فتخطّوه، ولا حدث
        // جديد يعيدهم إليه)، أو مستجيب أُغلق تطبيقه أثناء البثّ فبقي الطلب
        // «قيد التنفيذ» إلى الأبد (اختبار الكود الحقيقي): ننبّه الأجهزة من
        // جديد. إعادة البثّ إدمبوتنت، فمستجيبان معاً لا يضرّان.
        final now = DateTime.now();
        if (now.difference(lastNudge) >= const Duration(seconds: 60)) {
          final beat = req?['respondingAt'];
          final responderDead = status == 'in_progress' &&
              beat is Timestamp &&
              now.difference(beat.toDate()) > const Duration(minutes: 2);
          if (status == 'pending' || responderDead) {
            try {
              await reqRef.update({
                'status': 'pending',
                'nudgedAt': FieldValue.serverTimestamp(),
              });
            } catch (_) {}
            lastNudge = now;
          }
        }
      }

      if (status != 'ready') {
        print('⚠️ [Bootstrap] لم يستجب أي جهاز خلال المهلة');
        if (_recoveryMode) {
          // نكمل الاستعادة من السحابة وحدها ثم نفك حظر الرفع
          if (!await _downloadForBootstrap()) return;
          await _markBootstrapComplete(selfRef);
          return;
        }
        SyncDiagnostics.log('sync',
            'تمهيد الجهاز الجديد لم يكتمل: لا جهاز مستجيب. سيُعاد لاحقاً.');
        _syncEventController.add(
            '⚠️ لم يستجب أي جهاز — افتح تطبيقاً على جهاز قديم');
        return; // يبقى الطلب معلَّقاً ليلتقطه جهاز يستيقظ لاحقاً
      }

      // نزّل ما أُعيد بثّه بالمسار المعتاد (إدمبوتنت، ولا يكتب رصيداً)
      if (!await _downloadForBootstrap()) {
        print('⚠️ [Bootstrap] تعذّر تنزيل ما أُعيد بثّه — يُعاد لاحقاً');
        return;
      }
      await _markBootstrapComplete(selfRef);
      try {
        await reqRef.delete();
      } catch (_) {}

      final db = await _db.database;
      final after = Sqflite.firstIntValue(await db.rawQuery(
              'SELECT COUNT(*) FROM transactions '
              'WHERE (is_deleted IS NULL OR is_deleted = 0)')) ??
          0;
      print('✅ [Bootstrap] اكتمل التمهيد: $after معاملة');
      SyncDiagnostics.log('sync', 'اكتمل تمهيد الجهاز: $after معاملة');
      _syncEventController.add('تم استلام بيانات المجموعة ($after معاملة)');
    } catch (e) {
      print('⚠️ [Bootstrap] فشل التمهيد: $e (يُعاد في الدورة الخلفية)');
    } finally {
      _bootstrapping = false;
    }
  }

  /// كل جهاز يستمع لطلبات التمهيد ويردّ عليها إن لم يسبقه أحد.
  Future<void> startBootstrapResponder() async {
    if (_firestore == null || _deviceId == null) return;
    await _bootstrapRequestListener?.cancel();
    _bootstrapRequestListener = _firestore!
        .collection('bootstrap_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) async {
      for (final doc in snap.docs) {
        final requester = doc.data()['requestedBy'] as String?;
        if (requester == null || requester == _deviceId) continue;
        if (_bootstrapResponding) return;
        await _serveBootstrapRequest(doc.reference, requester);
      }
    }, onError: (e) {
      print('⚠️ [Bootstrap] خطأ في الاستماع للطلبات: $e');
    });
  }

  Future<void> _serveBootstrapRequest(
      DocumentReference reqRef, String requester) async {
    // 🛡️ بياناتي من نسخة احتياطية لم تكتمل مقارنتها: إعادة بثّها تكتب نسخاً
    // قديمة في السحابة بوقت خادم جديد، فتقبلها الأجهزة كأنها الأحدث.
    if (_recoveryMode) return;
    // حجز الطلب ذرّياً حتى لا يعيد عشرة أجهزة البثّ معاً
    try {
      final claimed = await _firestore!.runTransaction<bool>((txn) async {
        final snap = await txn.get(reqRef);
        if (!snap.exists) return false;
        final data = snap.data() as Map<String, dynamic>?;
        if ((data?['status'] as String?) != 'pending') return false;
        txn.update(reqRef, {
          'status': 'in_progress',
          'respondingDevice': _deviceId,
          'respondingAt': FieldValue.serverTimestamp(),
        });
        return true;
      }).timeout(const Duration(seconds: 30));
      if (!claimed) return;
    } catch (e) {
      print('⚠️ [Bootstrap] تعذّر حجز الطلب: $e');
      return;
    }

    _bootstrapResponding = true;
    try {
      print('📩 [Bootstrap] إعادة بثّ الدفتر كاملاً للجهاز الجديد: $requester');
      _syncEventController.add('جهاز جديد انضم — جاري إرسال البيانات إليه...');
      // نبضة كل 30 ثانية: الطالب يعرف أن المستجيب ما زال حياً (دفتر كبير
      // قد يستغرق دقائق)، ولا يعيد الطلب لغيره إلا إن انقطعت النبضات.
      var lastBeat = DateTime.now();
      final stats = await rebroadcastEverything(onProgress: (_, __) {
        final now = DateTime.now();
        if (now.difference(lastBeat) < const Duration(seconds: 30)) return;
        lastBeat = now;
        unawaited(reqRef
            .update({'respondingAt': FieldValue.serverTimestamp()})
            .catchError((_) {}));
      });
      await reqRef.update({
        'status': 'ready',
        'readyAt': FieldValue.serverTimestamp(),
        'stats': stats,
      });
      print('✅ [Bootstrap] تمّ البثّ: $stats');
      SyncDiagnostics.log('sync', 'أُعيد بثّ الدفتر لجهاز جديد ($requester): $stats');
    } catch (e) {
      print('❌ [Bootstrap] فشل البثّ: $e');
      // نُعيده معلَّقاً ليحاول جهاز آخر — لا نُسقط الطلب
      await reqRef.update({'status': 'pending', 'lastError': e.toString()})
          .catchError((_) {});
    } finally {
      _bootstrapResponding = false;
    }
  }

  /// إعادة بثّ دفتر المجموعة كما يعرفه هذا الجهاز — للجهاز الجديد أو المستعيد.
  ///
  /// 🛡️ قواعد آمنة (المحاكاة: سيناريوهات 26، 27 + الفوضى القاسية):
  ///   • لا نكتب إلا المستندات **الغائبة** من السحابة (داخل معاملة Firestore):
  ///     الكتابة فوق مستند موجود قد تُرجع نسخة أحدث إلى أقدم.
  ///   • كل المعاملات النشطة — لا معاملات هذا الجهاز وحده. كان
  ///     _forceUploadTransaction يرفض معاملات الأجهزة الأخرى، فلا يستلم الجهاز
  ///     الجديد بعد التنظيف إلا جزءاً من الدفتر.
  ///   • المستند يحمل مالكه الأصلي (origin_device_id) وlastModifiedAt الأصلي،
  ///     فلا يسرق المُجيب ملكية شيء، ويتعرّف المالك (بعد استعادة) على معاملاته.
  ///   • الفواتير تُعاد عبر قناتها (حزم)، الغائبة فقط.
  Future<Map<String, dynamic>> rebroadcastEverything(
      {void Function(double progress, String message)? onProgress}) async {
    final db = await _db.database;
    int custOk = 0, txOk = 0, invOk = 0, failed = 0;

    Future<bool> createIfAbsent(String coll, String id, Map<String, dynamic> data) async {
      final ref = _firestore!.collection(coll).doc(id);
      return await _firestore!.runTransaction<bool>((txn) async {
        final snap = await txn.get(ref);
        if (snap.exists) return false;
        txn.set(ref, data);
        return true;
      }).timeout(const Duration(seconds: 30));
    }

    final customers = await db.query('customers',
        where: "sync_uuid IS NOT NULL AND sync_uuid != '' AND (is_deleted IS NULL OR is_deleted = 0)");
    for (var i = 0; i < customers.length; i++) {
      final c = customers[i];
      final uuid = c['sync_uuid'] as String;
      if (!SyncSecurity.isValidDocumentId(uuid)) continue;
      try {
        final mine = (c['is_created_by_me'] as int?) != 0;
        final doc = <String, dynamic>{
          'syncUuid': uuid,
          'name': c['name'],
          'phone': c['phone'],
          'generalNote': c['general_note'],
          'address': c['address'],
          'createdAt': c['created_at'],
          'lastModifiedAt': c['last_modified_at'],
          'deviceId': mine ? _deviceId : 'rebroadcast',
          'originDeviceId': mine ? _deviceId : 'rebroadcast',
          'uploadedAt': FieldValue.serverTimestamp(),
        };
        doc['signature'] = _signDoc(uuid, doc, isCustomer: true);
        if (await createIfAbsent('customers', uuid, doc)) custOk++;
      } catch (_) {
        failed++;
      }
      onProgress?.call(i / (customers.length + 1) * 0.3, 'إرسال العملاء...');
    }

    final txs = await db.rawQuery('''
      SELECT t.*, c.sync_uuid AS customer_sync_uuid
      FROM transactions t JOIN customers c ON c.id = t.customer_id
      WHERE t.transaction_uuid IS NOT NULL AND t.transaction_uuid != ''
        AND (t.is_deleted IS NULL OR t.is_deleted = 0)
        AND (t.invoice_sync_uuid IS NULL OR t.invoice_sync_uuid = '')
        AND c.sync_uuid IS NOT NULL AND c.sync_uuid != ''
    ''');
    for (var i = 0; i < txs.length; i++) {
      final t = txs[i];
      final uuid = t['transaction_uuid'] as String;
      if (!SyncSecurity.isValidDocumentId(uuid)) continue;
      try {
        final mine = (t['is_created_by_me'] as int?) != 0;
        final owner = mine ? _deviceId : ((t['origin_device_id'] as String?) ?? 'rebroadcast');
        final doc = <String, dynamic>{
          'syncUuid': uuid,
          'customerSyncUuid': t['customer_sync_uuid'],
          'transactionDate': t['transaction_date'],
          'amountChanged': t['amount_changed'],
          'transactionNote': t['transaction_note'],
          'transactionType': t['transaction_type'],
          'description': t['description'],
          'createdAt': t['created_at'],
          'lastModifiedAt': (mine ? t['last_uploaded_at'] : t['remote_modified_at']) ?? t['created_at'],
          'deviceId': owner,
          'originDeviceId': owner,
          'uploadedAt': FieldValue.serverTimestamp(),
        };
        doc['signature'] = _signDoc(uuid, doc);
        if (await createIfAbsent('transactions', uuid, doc)) txOk++;
      } catch (_) {
        failed++;
      }
      onProgress?.call(0.3 + i / (txs.length + 1) * 0.5, 'إرسال المعاملات...');
    }

    // الفواتير: حزم الفواتير الغائبة من السحابة (كل الفواتير، لا فواتيري وحدي)
    try {
      invOk = await InvoiceSyncService().rebroadcastMissingInvoices();
    } catch (e) {
      print('⚠️ [Bootstrap] تعذّر إعادة بثّ الفواتير: $e');
    }

    onProgress?.call(1.0, 'اكتمل الإرسال');
    return {
      'customers': custOk,
      'transactions': txOk,
      'invoices': invOk,
      'failed': failed,
    };
  }

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
            // 🔐 لم يعد السرّ يُكتب نصاً في أي مستند (كان يكشفه لكل من يقرأ)،
            // بل بصمته فقط لتعرف الأجهزة من يشاركها نفس السرّ.
            'secretFingerprint': _secretFingerprint(),
            // 🛡️ جهاز مسجَّل = جهاز مطالَب بالقراءة. لا يُحذف من السحابة
            // مستند قبل أن يقرأه. البقاء على isNewDevice=true كان يعني
            // إسقاطه من الحساب وحذف مستندات لم يرها قط.
            'isNewDevice': false,
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

        // 🛡️ وصلت المعاملة (بنسخة أحدث) عبر المستمع بعد تخزين اليتيمة —
        // تطبيق اللقطة المخزّنة الآن كان يكتب رقماً قديماً فوق الجديد.
        final already = await db.query('transactions',
            columns: ['id'], where: 'transaction_uuid = ?', whereArgs: [syncUuid], limit: 1);
        if (already.isNotEmpty) {
          await db.delete('sync_orphans', where: 'sync_uuid = ?', whereArgs: [syncUuid]);
          continue;
        }

        // محاولة تطبيق المعاملة الآن (معاملتي المفقودة بعد استعادة → مسار المالك)
        if (data['deviceId'] == _deviceId) {
          await _handleOwnTxDoc(syncUuid, data);
        } else {
          await _applyTransactionChange(syncUuid, data);
        }
        
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

  /// رفع عميل بالقوة (زر «الرفع الشامل»).
  /// 🛡️ لا يكتب isDeleted إطلاقاً: الرفع الشامل لعملاء نشطين، وكتابة
  /// isDeleted=false بـ merge كانت «تُحيي» عميلاً حذفه جهاز آخر للتو.
  Future<void> _forceUploadCustomer(Map<String, dynamic> customerData) async {
    if (_groupId == null) return;
    if (_recoveryMode) {
      throw Exception('وضع الاستعادة: الرفع موقوف حتى تكتمل مقارنة النسخة المستعادة');
    }

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
    final Map<String, dynamic> custExpectation =
        await _computeCustomerExpectation(syncUuid);

    try {
      final doc = <String, dynamic>{
        'syncUuid': syncUuid,
        'name': customerData['name'],
        'phone': customerData['phone'],
        'currentTotalDebt': customerData['current_total_debt'],
        'expectedBalance': custExpectation['balance'],
        'expectedTxCount': custExpectation['count'],
        'expectedFingerprint': custExpectation['fingerprint'],
        'expectedByDevice': _deviceId,
        'generalNote': customerData['general_note'],
        'address': customerData['address'],
        'createdAt': customerData['created_at'],
        'lastModifiedAt':
            customerData['last_modified_at'] ?? DateTime.now().toIso8601String(),
        'audioNotePath': customerData['audio_note_path'],
        'deviceId': _deviceId,
        'originDeviceId': _deviceId,
        'checksum': checksum,
        'uploadedAt': FieldValue.serverTimestamp(),
      };
      doc['signature'] = _signDoc(syncUuid, doc, isCustomer: true);
      await _firestore!
          .collection('customers')
          .doc(syncUuid)
          .set(doc, SetOptions(merge: true))
          .timeout(const Duration(seconds: 60));

      final db = await _db.database;
      await db.rawUpdate(
        'UPDATE customers SET synced_at = ? WHERE sync_uuid = ?',
        [DateTime.now().toIso8601String(), syncUuid],
      );
    } catch (e) {
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
  /// 🛡️ نفس ضمانات uploadTransaction: قراءة حديثة، CAS، لا isDeleted=false،
  /// ومعاملات الفواتير النشطة تسافر في حزمها.
  Future<void> _forceUploadTransaction(
    Map<String, dynamic> txData,
    String customerSyncUuid,
  ) async {
    if (_groupId == null) return;
    if (_recoveryMode) {
      throw Exception('وضع الاستعادة: الرفع موقوف حتى تكتمل مقارنة النسخة المستعادة');
    }

    final syncUuid = txData['transaction_uuid'] as String?;
    if (syncUuid == null || syncUuid.isEmpty) return;
    if (!SyncSecurity.isValidDocumentId(syncUuid)) {
      print('❌ تخطي رفع معاملة بمعرّف غير صالح: $syncUuid');
      return;
    }

    final db = await _db.database;
    final rows = await db.query('transactions',
        where: 'transaction_uuid = ?', whereArgs: [syncUuid], limit: 1);
    if (rows.isEmpty) return;
    final tx = Map<String, dynamic>.from(rows.first);

    final owned = tx['is_created_by_me'];
    if (owned != null && owned == 0) {
      print('🚫 رُفض رفع معاملة من المزامنة: $syncUuid');
      return;
    }
    final isTxDeleted = ((tx['is_deleted'] as int?) ?? 0) == 1;
    final invUuid = tx['invoice_sync_uuid'] as String?;
    if (!isTxDeleted && invUuid != null && invUuid.isNotEmpty) return;

    if (!_rateLimiter.canProceed()) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _rateLimiter.recordOperation();

    final checksum = _calculateChecksum(tx);
    final sentFingerprint = _txFingerprint(tx);
    final nowIso = DateTime.now().toIso8601String();

    try {
      final doc = <String, dynamic>{
        'syncUuid': syncUuid,
        'customerSyncUuid': customerSyncUuid,
        'invoiceSyncUuid': tx['invoice_sync_uuid'],
        'transactionDate': tx['transaction_date'],
        'amountChanged': tx['amount_changed'],
        'balanceBeforeTransaction': tx['balance_before_transaction'],
        'newBalanceAfterTransaction': tx['new_balance_after_transaction'],
        'transactionNote': tx['transaction_note'],
        'transactionType': tx['transaction_type'],
        'description': tx['description'],
        'createdAt': tx['created_at'],
        'lastModifiedAt': nowIso,
        'audioNotePath': tx['audio_note_path'],
        'deviceId': _deviceId,
        'originDeviceId': _deviceId,
        'checksum': checksum,
        'uploadedAt': FieldValue.serverTimestamp(),
      };
      if (isTxDeleted) {
        doc['isDeleted'] = true;
        doc['is_deleted'] = 1;
      }
      doc['signature'] = _signDoc(syncUuid, doc);
      await _firestore!
          .collection('transactions')
          .doc(syncUuid)
          .set(doc, SetOptions(merge: true))
          .timeout(const Duration(seconds: 60));

      final cur = await db.query('transactions',
          where: 'transaction_uuid = ?', whereArgs: [syncUuid], limit: 1);
      if (cur.isNotEmpty && _txFingerprint(cur.first) == sentFingerprint) {
        await db.update('transactions', {'is_uploaded': 1, 'last_uploaded_at': nowIso},
            where: 'transaction_uuid = ?', whereArgs: [syncUuid]);
      } else {
        await db.update('transactions', {'is_uploaded': 0},
            where: 'transaction_uuid = ?', whereArgs: [syncUuid]);
      }
    } catch (e) {
      final retryData = Map<String, dynamic>.from(tx);
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

  // ═══════════════════════════════════════════════════════════════════════
  // 🔐 التوقيع: يغطي الحقول المالية (المبلغ، العميل، الحذف، الكاتب).
  //
  // كان التوقيع يغطي (المعرّف|الجهاز|checksum) فقط، والـ checksum لا يمكن
  // للمستقبِل إعادة حسابه من المستند، فيمكن تغيير المبلغ مع إبقاء التوقيع. وكان
  // السرّ نفسه يُكتب نصاً في كل مستند (groupSecret)، فمن يقرأ أي مستند يستطيع
  // التوقيع. الآن: لا سرّ في المستندات، والتحقق الصارم يُفعَّل من الإعدادات بعد
  // إدخال نفس السرّ على كل الأجهزة (المحاكاة: سيناريو 28).
  // ═══════════════════════════════════════════════════════════════════════

  String _canonAmount(dynamic v) =>
      v is num ? v.toDouble().toStringAsFixed(2) : (v?.toString() ?? '');

  String _canonicalFor(String uuid, Map<String, dynamic> d, {bool isCustomer = false}) {
    final del = d['isDeleted'] == true ? '1' : (d['isDeleted'] == false ? '0' : '');
    if (isCustomer) {
      return 'c|$uuid|$del|${d['deviceId'] ?? ''}';
    }
    return 't|$uuid|${d['customerSyncUuid'] ?? ''}|${_canonAmount(d['amountChanged'])}|$del|${d['deviceId'] ?? ''}';
  }

  String? _signDoc(String uuid, Map<String, dynamic> doc, {bool isCustomer = false}) {
    final key = _groupSecretKey;
    if (key == null || key.isEmpty) return null;
    return SyncSecurity.signData(_canonicalFor(uuid, doc, isCustomer: isCustomer), key);
  }

  String _secretFingerprint() {
    final key = _groupSecretKey;
    if (key == null || key.isEmpty) return '';
    return sha256.convert(utf8.encode('fp|$key')).toString().substring(0, 16);
  }

  /// أسماء الأجهزة (غير الخارجة عن الخدمة) التي لا تطابق بصمة سرّها سرّ هذا
  /// الجهاز، أو لم تُحدَّث بعد فلا تنشر بصمة. الوضع الصارم آمن فقط إن كانت فارغة.
  Future<List<String>> devicesWithMismatchedSecret() async {
    if (_firestore == null) {
      throw StateError('المزامنة غير مُهيّأة');
    }
    final mine = _secretFingerprint();
    final snap = await _firestore!
        .collection('devices')
        .get(const GetOptions(source: Source.server));
    final out = <String>[];
    for (final d in snap.docs) {
      if (d.id == _deviceId) continue;
      final data = d.data();
      if (data['isRetired'] == true) continue;
      if (mine.isEmpty || data['secretFingerprint'] != mine) {
        out.add((data['deviceName'] as String?) ?? d.id);
      }
    }
    return out;
  }

  /// يُرجع false لمستند يجب رفضه. لا رفض إلا في الوضع الصارم (سرّ مشترك مُدخل
  /// على كل الأجهزة + تفعيل صريح)، وإلا نكتفي بالتسجيل.
  Future<bool> _verifyIncomingSignature(String uuid, Map<String, dynamic> data,
      {bool isCustomer = false}) async {
    bool strict = false;
    try {
      strict = await FirebaseSyncSecuritySettings.isStrictSignatureEnabled();
    } catch (_) {}
    final key = _groupSecretKey;
    if (!strict || key == null || key.isEmpty) return true;
    final sig = data['signature'] as String?;
    final ok = sig != null &&
        SyncSecurity.verifySignature(_canonicalFor(uuid, data, isCustomer: isCustomer), sig, key);
    if (!ok) {
      print('🛑 رُفض مستند غير موقّع بسرّ المجموعة: $uuid (من ${data['deviceId']})');
      SyncDiagnostics.log('security',
          'رُفض مستند غير موقّع: $uuid من ${data['deviceId']} — تحقق من تطابق سرّ المجموعة على كل الأجهزة');
    }
    return ok;
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
