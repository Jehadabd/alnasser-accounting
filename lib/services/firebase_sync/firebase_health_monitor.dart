// lib/services/firebase_sync/firebase_health_monitor.dart
//
// 🩺 FirebaseHealthMonitor:
//   خدمة تفحص باستمرار قدرة التطبيق على القراءة والكتابة من/إلى Firebase.
//   لا يكفي التحقق من "متصل بالإنترنت"، نحتاج تأكيد فعلي:
//     1) نكتب nonce عشوائي في مستند الجهاز على Firestore.
//     2) نقرأه من السيرفر (Source.server، ليس من الكاش).
//     3) نقارن nonce — لو تطابق فالكتابة والقراءة تعملان فعلاً.
//
// النتائج تُبثّ إلى SyncEventBus (للسجل الحيّ) وإلى healthStream (للواجهة).
//
// ملاحظة: نستخدم مستند devices/{deviceId} الموجود أصلاً بدل مجموعة منفصلة،
//         لأن firestore.rules الحالية لا تسمح إلا بمجموعات محددة.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'sync_event_bus.dart';

/// حالة صحة Firebase
enum FirebaseHealthState {
  unknown,          // لم يُفحص بعد
  checking,         // فحص جارٍ
  healthy,          // شبكة + مصادقة + قراءة + كتابة كلها ناجحة
  networkFailed,    // لا اتصال إنترنت
  authFailed,       // شبكة موجودة لكن المصادقة فشلت
  readFailed,       // كتبنا لكن لم نستطع القراءة
  writeFailed,      // فشلت الكتابة (أذونات/شبكة أثناء الطلب)
  verificationFailed, // كتبنا وقرأنا لكن nonce غير مطابق (بيانات لا تُحفَظ فعلاً)
}

/// نتيجة فحص واحد
class FirebaseHealthResult {
  final FirebaseHealthState state;
  final bool hasNetwork;
  final bool isAuthenticated;
  final bool canWrite;
  final bool canRead;
  final bool nonceMatched;
  final Duration? latency;
  final String? errorDetails;
  final DateTime checkedAt;

  const FirebaseHealthResult({
    required this.state,
    required this.hasNetwork,
    required this.isAuthenticated,
    required this.canWrite,
    required this.canRead,
    required this.nonceMatched,
    this.latency,
    this.errorDetails,
    required this.checkedAt,
  });

  bool get isHealthy => state == FirebaseHealthState.healthy;

  /// عنوان قصير للشاشة
  String get shortLabel {
    switch (state) {
      case FirebaseHealthState.unknown:
        return 'لم يُفحص';
      case FirebaseHealthState.checking:
        return 'جاري الفحص...';
      case FirebaseHealthState.healthy:
        return 'متصل بالكامل ✓';
      case FirebaseHealthState.networkFailed:
        return 'لا يوجد اتصال إنترنت';
      case FirebaseHealthState.authFailed:
        return 'فشل التحقق من الهوية';
      case FirebaseHealthState.writeFailed:
        return 'الكتابة على Firebase فاشلة';
      case FirebaseHealthState.readFailed:
        return 'القراءة من Firebase فاشلة';
      case FirebaseHealthState.verificationFailed:
        return 'البيانات لا تُحفظ على Firebase';
    }
  }

  Map<String, dynamic> toMap() => {
        'state': state.name,
        'hasNetwork': hasNetwork,
        'isAuthenticated': isAuthenticated,
        'canWrite': canWrite,
        'canRead': canRead,
        'nonceMatched': nonceMatched,
        if (latency != null) 'latencyMs': latency!.inMilliseconds,
        if (errorDetails != null) 'errorDetails': errorDetails,
        'checkedAt': checkedAt.toIso8601String(),
      };
}

/// ═══════════════════════════════════════════════════════════════════════════
/// FirebaseHealthMonitor — Singleton
/// ═══════════════════════════════════════════════════════════════════════════
class FirebaseHealthMonitor {
  static final FirebaseHealthMonitor _instance =
      FirebaseHealthMonitor._internal();
  factory FirebaseHealthMonitor() => _instance;
  static FirebaseHealthMonitor get instance => _instance;
  FirebaseHealthMonitor._internal();

  FirebaseFirestore? _firestore;
  String? _deviceId;

  Timer? _timer;
  bool _isChecking = false;
  bool _running = false;
  Duration _interval = const Duration(seconds: 30);

  final _controller = StreamController<FirebaseHealthResult>.broadcast();

  /// Stream لآخر نتيجة فحص (تبقى الواجهة تحيط بها لحظياً)
  Stream<FirebaseHealthResult> get healthStream => _controller.stream;

  /// آخر نتيجة (للقراءة الفورية عند فتح الشاشة)
  FirebaseHealthResult _lastResult = FirebaseHealthResult(
    state: FirebaseHealthState.unknown,
    hasNetwork: false,
    isAuthenticated: false,
    canWrite: false,
    canRead: false,
    nonceMatched: false,
    checkedAt: DateTime.now(),
  );
  FirebaseHealthResult get lastResult => _lastResult;

  final _random = Random.secure();

  /// ═══════════════════════════════════════════════════════════════════════
  /// التهيئة والتشغيل
  /// ═══════════════════════════════════════════════════════════════════════

  /// تهيئة الخدمة (تُستدعى بعد نجاح FirebaseSyncService.initialize)
  Future<void> initialize({
    required FirebaseFirestore firestore,
    required String deviceId,
    Duration? interval,
  }) async {
    _firestore = firestore;
    _deviceId = deviceId;
    _interval = interval ?? _interval;
    syncBus.debug(SyncPhase.health, 'تم تهيئة مراقب صحة Firebase');
  }

  /// بدء الفحص الدوري
  void start() {
    if (_running) return;
    if (_firestore == null || _deviceId == null) {
      syncBus.warning(SyncPhase.health,
          'محاولة بدء مراقب الصحة قبل التهيئة — تم التخطي');
      return;
    }
    _running = true;
    syncBus.info(SyncPhase.health,
        'بدء مراقبة صحة Firebase (كل ${_interval.inSeconds} ثانية)');
    // فحص فوري
    unawaited(_runCheck(source: 'startup'));
    _timer = Timer.periodic(_interval, (_) {
      unawaited(_runCheck(source: 'periodic'));
    });
  }

  /// إيقاف الفحص
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    syncBus.debug(SyncPhase.health, 'تم إيقاف مراقبة صحة Firebase');
  }

  /// فحص فوري عند الطلب (يستدعيه زر "مزامنة الآن" مثلاً)
  Future<FirebaseHealthResult> checkNow({String source = 'manual'}) async {
    return _runCheck(source: source);
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// الفحص الفعلي (كتابة → قراءة → مقارنة nonce)
  /// ═══════════════════════════════════════════════════════════════════════

  Future<FirebaseHealthResult> _runCheck({required String source}) async {
    if (_isChecking) {
      return _lastResult;
    }
    _isChecking = true;

    final sw = Stopwatch()..start();
    bool hasNetwork = false;
    bool isAuthenticated = false;
    bool canWrite = false;
    bool canRead = false;
    bool nonceMatched = false;
    String? errorDetails;

    syncBus.debug(SyncPhase.health, 'بدء فحص صحة Firebase [$source]');

    try {
      // 1️⃣ الشبكة
      final connectivity = await Connectivity().checkConnectivity();
      hasNetwork = connectivity.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) {
        return _publish(FirebaseHealthResult(
          state: FirebaseHealthState.networkFailed,
          hasNetwork: false,
          isAuthenticated: false,
          canWrite: false,
          canRead: false,
          nonceMatched: false,
          latency: sw.elapsed,
          errorDetails: 'لا يوجد اتصال إنترنت',
          checkedAt: DateTime.now(),
        ), reason: 'لا يوجد اتصال إنترنت');
      }

      // 2️⃣ المصادقة
      final user = FirebaseAuth.instance.currentUser;
      isAuthenticated = user != null;
      if (!isAuthenticated) {
        return _publish(FirebaseHealthResult(
          state: FirebaseHealthState.authFailed,
          hasNetwork: hasNetwork,
          isAuthenticated: false,
          canWrite: false,
          canRead: false,
          nonceMatched: false,
          latency: sw.elapsed,
          errorDetails: 'المستخدم غير مصادق عليه',
          checkedAt: DateTime.now(),
        ), reason: 'فشلت المصادقة');
      }

      // 3️⃣ الكتابة (نكتب nonce عشوائي في devices/{deviceId}._healthCheck)
      final nonce = _makeNonce();
      final serverTime = FieldValue.serverTimestamp();

      try {
        await _firestore!
            .collection('devices')
            .doc(_deviceId)
            .set({
          '_healthCheck': {
            'nonce': nonce,
            'writtenAt': serverTime,
            'source': source,
          },
        }, SetOptions(merge: true));
        canWrite = true;
      } on FirebaseException catch (e) {
        errorDetails = 'رمز الكتابة: ${e.code} — ${e.message}';
        return _publish(FirebaseHealthResult(
          state: FirebaseHealthState.writeFailed,
          hasNetwork: hasNetwork,
          isAuthenticated: isAuthenticated,
          canWrite: false,
          canRead: false,
          nonceMatched: false,
          latency: sw.elapsed,
          errorDetails: errorDetails,
          checkedAt: DateTime.now(),
        ), reason: 'فشلت الكتابة إلى Firebase (${e.code})');
      }

      // 4️⃣ القراءة من السيرفر (ليس من الكاش) للتحقق من الحفظ الفعلي
      DocumentSnapshot<Map<String, dynamic>>? snap;
      try {
        snap = await _firestore!
            .collection('devices')
            .doc(_deviceId)
            .get(const GetOptions(source: Source.server));
        canRead = true;
      } on FirebaseException catch (e) {
        errorDetails = 'رمز القراءة: ${e.code} — ${e.message}';
        return _publish(FirebaseHealthResult(
          state: FirebaseHealthState.readFailed,
          hasNetwork: hasNetwork,
          isAuthenticated: isAuthenticated,
          canWrite: true,
          canRead: false,
          nonceMatched: false,
          latency: sw.elapsed,
          errorDetails: errorDetails,
          checkedAt: DateTime.now(),
        ), reason: 'فشلت القراءة من Firebase (${e.code})');
      }

      // 5️⃣ مقارنة nonce (تحقق من أن الكتابة السابقة وصلت فعلاً)
      final readback = (snap.data() ?? const {})['_healthCheck'];
      final readNonce = (readback is Map) ? readback['nonce']?.toString() : null;
      nonceMatched = readNonce == nonce;

      if (!nonceMatched) {
        return _publish(FirebaseHealthResult(
          state: FirebaseHealthState.verificationFailed,
          hasNetwork: hasNetwork,
          isAuthenticated: isAuthenticated,
          canWrite: canWrite,
          canRead: canRead,
          nonceMatched: false,
          latency: sw.elapsed,
          errorDetails:
              'nonce غير مطابق (متوقّع: $nonce، مقروء: $readNonce) — البيانات لا تُحفظ فعلاً',
          checkedAt: DateTime.now(),
        ), reason: 'nonce غير مطابق (البيانات لا تُحفظ)');
      }

      // ✅ كل شيء تمام
      return _publish(FirebaseHealthResult(
        state: FirebaseHealthState.healthy,
        hasNetwork: true,
        isAuthenticated: true,
        canWrite: true,
        canRead: true,
        nonceMatched: true,
        latency: sw.elapsed,
        checkedAt: DateTime.now(),
      ), reason: 'صحة Firebase: كل شيء سليم (زمن الاستجابة ${sw.elapsedMilliseconds}ms)');
    } catch (e) {
      errorDetails = 'استثناء غير متوقع: $e';
      return _publish(FirebaseHealthResult(
        state: FirebaseHealthState.writeFailed,
        hasNetwork: hasNetwork,
        isAuthenticated: isAuthenticated,
        canWrite: canWrite,
        canRead: canRead,
        nonceMatched: nonceMatched,
        latency: sw.elapsed,
        errorDetails: errorDetails,
        checkedAt: DateTime.now(),
      ), reason: 'خطأ غير متوقع أثناء فحص Firebase');
    } finally {
      _isChecking = false;
    }
  }

  /// حفظ + بث النتيجة
  FirebaseHealthResult _publish(FirebaseHealthResult result,
      {required String reason}) {
    final previousState = _lastResult.state;
    _lastResult = result;
    if (!_controller.isClosed) {
      _controller.add(result);
    }

    // البث إلى Bus (لعرضه في السجل الحيّ)
    final level = result.isHealthy
        ? SyncEventLevel.success
        : (result.state == FirebaseHealthState.checking
            ? SyncEventLevel.info
            : SyncEventLevel.warning);
    syncBus.emit(SyncEvent(
      phase: SyncPhase.health,
      level: level,
      message: reason,
      metadata: result.toMap(),
    ));

    if (previousState != result.state) {
      syncBus.info(SyncPhase.health,
          'تحوّلت حالة Firebase من ${previousState.name} إلى ${result.state.name}');
    }
    return result;
  }

  String _makeNonce() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> dispose() async {
    stop();
    if (!_controller.isClosed) await _controller.close();
  }
}

/// اختصار سريع
final firebaseHealth = FirebaseHealthMonitor.instance;

/// helper للدوال المُطلقة (fire-and-forget)
void unawaited(Future<void> f) {
  f.catchError((_) {});
}
