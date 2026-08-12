// lib/services/firebase_sync/sync_event_bus.dart
//
// 🚌 SyncEventBus: القناة المركزية اللحظية لكل ما يحدث في نظام المزامنة.
//
// المهمة:
// - كل مكون (Service, Watchdog, WAL, Retry, ACK, HealthMonitor, BulkUpload...)
//   يبثّ SyncEvent إلى Bus واحد.
// - الواجهة تشترك في هذا Bus لتعرض السجل الحي + شريط التقدّم الحقيقي.
// - النتيجة: الشاشة مرآة 100% لما يجري خلف الكواليس.
//
// المبدأ: طبقة نقل + عرض فقط. لا يمسّ منطق البيانات.

import 'dart:async';
import 'dart:collection';

/// مستوى الخطورة/اللون
enum SyncEventLevel {
  debug,    // رمادي (تشخيصي)
  info,     // أزرق (بداية عملية)
  success,  // أخضر (نجاح / تحقق)
  warning,  // أصفر (إعادة محاولة / تجاوز)
  error,    // أحمر (فشل)
}

/// أطوار (Phases) المزامنة — تُستخدم لتصنيف الأحداث في السجل والشريط.
class SyncPhase {
  // التهيئة
  static const auth = 'auth';
  static const config = 'config';
  static const serverTime = 'server_time';
  static const initialize = 'initialize';

  // صحة Firebase
  static const health = 'health';
  static const healthWrite = 'health_write';
  static const healthRead = 'health_read';

  // الرفع الفردي
  static const uploadCustomer = 'upload_customer';
  static const uploadTransaction = 'upload_transaction';
  static const verifyWrite = 'verify_write';

  // التنزيل والاستماع
  static const downloadCustomers = 'download_customers';
  static const downloadTransactions = 'download_transactions';
  static const listen = 'listen';
  static const applyRemote = 'apply_remote';

  // Watchdog / WAL / Retry / ACK
  static const watchdog = 'watchdog';
  static const wal = 'wal';
  static const retry = 'retry';
  static const ack = 'ack';

  // الرفع الشامل
  static const bulkUpload = 'bulk_upload';
  static const bulkCustomer = 'bulk_customer';
  static const bulkTransaction = 'bulk_transaction';

  // Migration / التنظيف
  static const migration = 'migration';
  static const cleanup = 'cleanup';

  // المطابقة / الأجهزة
  static const devices = 'devices';
  static const reconciliation = 'reconciliation';

  // عام
  static const general = 'general';
}

/// حدث مزامنة واحد
class SyncEvent {
  /// الطور (SyncPhase.*)
  final String phase;

  /// المستوى (info/success/warning/error/debug)
  final SyncEventLevel level;

  /// الرسالة النصية (تماماً كما تظهر في التيرمينال)
  final String message;

  /// (اختياري) رقم العنصر الحالي عند العدّ (لعمليات الدفعات)
  final int? currentIndex;

  /// (اختياري) إجمالي العناصر المتوقّعة (لعمليات الدفعات)
  final int? totalItems;

  /// (اختياري) معرّف الكيان (sync_uuid) — للربط والفلترة
  final String? entityUuid;

  /// (اختياري) نوع الكيان: 'customer' / 'transaction' / 'device' / 'wal_op'
  final String? entityType;

  /// (اختياري) بيانات إضافية للتشخيص
  final Map<String, dynamic>? metadata;

  /// الطابع الزمني
  final DateTime timestamp;

  SyncEvent({
    required this.phase,
    required this.level,
    required this.message,
    this.currentIndex,
    this.totalItems,
    this.entityUuid,
    this.entityType,
    this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// نسخة JSON للتسجيل/التصدير
  Map<String, dynamic> toMap() => {
        'phase': phase,
        'level': level.name,
        'message': message,
        if (currentIndex != null) 'currentIndex': currentIndex,
        if (totalItems != null) 'totalItems': totalItems,
        if (entityUuid != null) 'entityUuid': entityUuid,
        if (entityType != null) 'entityType': entityType,
        if (metadata != null) 'metadata': metadata,
        'timestamp': timestamp.toIso8601String(),
      };

  /// تمثيل نصّي مطابق للتيرمينال
  @override
  String toString() {
    final t = timestamp;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final indicator = _levelIndicator(level);
    if (currentIndex != null && totalItems != null) {
      return '$hh:$mm:$ss $indicator $message ($currentIndex/$totalItems)';
    }
    return '$hh:$mm:$ss $indicator $message';
  }

  static String _levelIndicator(SyncEventLevel level) {
    switch (level) {
      case SyncEventLevel.debug:
        return '·';
      case SyncEventLevel.info:
        return 'ℹ️';
      case SyncEventLevel.success:
        return '✅';
      case SyncEventLevel.warning:
        return '⚠️';
      case SyncEventLevel.error:
        return '❌';
    }
  }
}

/// ملخّص التقدّم الحالي (يُحسب من الأحداث)
class SyncProgressSnapshot {
  final String? currentPhase;
  final String? currentMessage;
  final int? currentIndex;
  final int? totalItems;
  final double? progress; // 0.0 - 1.0
  final int totalEvents;
  final int errorCount;
  final int warningCount;
  final DateTime updatedAt;

  const SyncProgressSnapshot({
    this.currentPhase,
    this.currentMessage,
    this.currentIndex,
    this.totalItems,
    this.progress,
    required this.totalEvents,
    required this.errorCount,
    required this.warningCount,
    required this.updatedAt,
  });

  static SyncProgressSnapshot get empty => SyncProgressSnapshot(
        totalEvents: 0,
        errorCount: 0,
        warningCount: 0,
        updatedAt: DateTime.now(),
      );
}

/// ═══════════════════════════════════════════════════════════════════════════
/// SyncEventBus — Singleton مركزي
/// ═══════════════════════════════════════════════════════════════════════════
class SyncEventBus {
  static final SyncEventBus _instance = SyncEventBus._internal();
  factory SyncEventBus() => _instance;
  static SyncEventBus get instance => _instance;
  SyncEventBus._internal();

  /// StreamController لبث الأحداث (broadcast — يدعم عدة مشتركين)
  final _controller = StreamController<SyncEvent>.broadcast();

  /// Stream للأحداث الحية — الواجهة تشترك بهذا
  Stream<SyncEvent> get stream => _controller.stream;

  /// آخر N حدث محفوظة في الذاكرة (للعرض عند فتح الشاشة متأخراً)
  final Queue<SyncEvent> _recentEvents = Queue<SyncEvent>();
  static const int _maxRecentEvents = 500;

  /// قائمة نسخة من آخر الأحداث (للقراءة)
  List<SyncEvent> get recentEvents => List.unmodifiable(_recentEvents);

  /// عدّاد الأحداث الإجمالي منذ بدء التطبيق
  int _totalEvents = 0;
  int _errorCount = 0;
  int _warningCount = 0;

  /// آخر حدث تقدّم فيه (currentIndex + totalItems) — لتحديث الشريط
  SyncEvent? _lastProgressEvent;

  /// طوران خاصان: تقدّم "الرفع الشامل" و"مزامنة معلقة"
  int? _overallCurrentIndex;
  int? _overallTotalItems;
  String? _overallPhase;
  String? _overallMessage;

  /// StreamController للقطات التقدّم (تُحدَّث مع كل حدث ذي مؤشر عددي)
  final _progressController =
      StreamController<SyncProgressSnapshot>.broadcast();
  Stream<SyncProgressSnapshot> get progressStream => _progressController.stream;
  SyncProgressSnapshot get currentProgress => _buildSnapshot();

  /// هل نطبع الأحداث في التيرمينال أيضاً (نعم افتراضياً لتبقى تجربة `flutter run` كما هي)
  bool mirrorToConsole = true;

  /// ═══════════════════════════════════════════════════════════════════════
  /// البث (Emit)
  /// ═══════════════════════════════════════════════════════════════════════

  /// بث حدث جديد
  void emit(SyncEvent event) {
    if (_controller.isClosed) return;

    _totalEvents++;
    if (event.level == SyncEventLevel.error) _errorCount++;
    if (event.level == SyncEventLevel.warning) _warningCount++;

    // حفظ في السجل الأخير
    _recentEvents.addLast(event);
    while (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeFirst();
    }

    // تتبع التقدّم من الحدث نفسه
    if (event.currentIndex != null && event.totalItems != null) {
      _lastProgressEvent = event;
    }

    // البث
    _controller.add(event);

    // بث لقطة التقدّم
    if (!_progressController.isClosed) {
      _progressController.add(_buildSnapshot());
    }

    // طباعة في التيرمينال (نحافظ على السلوك الحالي للمطور)
    if (mirrorToConsole) {
      // ignore: avoid_print
      print(event.toString());
    }
  }

  /// اختصار: بث حدث معلوماتي
  void info(String phase, String message,
      {int? currentIndex,
      int? totalItems,
      String? entityUuid,
      String? entityType,
      Map<String, dynamic>? metadata}) {
    emit(SyncEvent(
      phase: phase,
      level: SyncEventLevel.info,
      message: message,
      currentIndex: currentIndex,
      totalItems: totalItems,
      entityUuid: entityUuid,
      entityType: entityType,
      metadata: metadata,
    ));
  }

  /// اختصار: نجاح
  void success(String phase, String message,
      {int? currentIndex,
      int? totalItems,
      String? entityUuid,
      String? entityType,
      Map<String, dynamic>? metadata}) {
    emit(SyncEvent(
      phase: phase,
      level: SyncEventLevel.success,
      message: message,
      currentIndex: currentIndex,
      totalItems: totalItems,
      entityUuid: entityUuid,
      entityType: entityType,
      metadata: metadata,
    ));
  }

  /// اختصار: تحذير
  void warning(String phase, String message,
      {int? currentIndex,
      int? totalItems,
      String? entityUuid,
      String? entityType,
      Map<String, dynamic>? metadata}) {
    emit(SyncEvent(
      phase: phase,
      level: SyncEventLevel.warning,
      message: message,
      currentIndex: currentIndex,
      totalItems: totalItems,
      entityUuid: entityUuid,
      entityType: entityType,
      metadata: metadata,
    ));
  }

  /// اختصار: خطأ
  void error(String phase, String message,
      {int? currentIndex,
      int? totalItems,
      String? entityUuid,
      String? entityType,
      Map<String, dynamic>? metadata}) {
    emit(SyncEvent(
      phase: phase,
      level: SyncEventLevel.error,
      message: message,
      currentIndex: currentIndex,
      totalItems: totalItems,
      entityUuid: entityUuid,
      entityType: entityType,
      metadata: metadata,
    ));
  }

  /// اختصار: تشخيصي
  void debug(String phase, String message, {Map<String, dynamic>? metadata}) {
    emit(SyncEvent(
      phase: phase,
      level: SyncEventLevel.debug,
      message: message,
      metadata: metadata,
    ));
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// تقدّم عمليّ إجمالي (للـ Bulk Upload وما شابه)
  /// ═══════════════════════════════════════════════════════════════════════

  /// بدء عملية إجمالية بمؤشر تقدّم يعمّ الأحداث
  void beginOverall({
    required String phase,
    required int total,
    required String message,
  }) {
    _overallPhase = phase;
    _overallTotalItems = total;
    _overallCurrentIndex = 0;
    _overallMessage = message;
    info(phase, message, currentIndex: 0, totalItems: total);
  }

  /// تحديث عدد ما أُنجز في العملية الإجمالية
  void updateOverall({int? current, String? message, SyncEventLevel? level}) {
    if (current != null) _overallCurrentIndex = current;
    if (message != null) _overallMessage = message;
    emit(SyncEvent(
      phase: _overallPhase ?? SyncPhase.general,
      level: level ?? SyncEventLevel.info,
      message: _overallMessage ?? '',
      currentIndex: _overallCurrentIndex,
      totalItems: _overallTotalItems,
    ));
  }

  /// إنهاء العملية الإجمالية
  void endOverall({required String message, SyncEventLevel? level}) {
    emit(SyncEvent(
      phase: _overallPhase ?? SyncPhase.general,
      level: level ?? SyncEventLevel.success,
      message: message,
      currentIndex: _overallTotalItems,
      totalItems: _overallTotalItems,
    ));
    _overallPhase = null;
    _overallMessage = null;
    _overallCurrentIndex = null;
    _overallTotalItems = null;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// المساعدات الداخلية
  /// ═══════════════════════════════════════════════════════════════════════

  SyncProgressSnapshot _buildSnapshot() {
    // تفضيل التقدّم "الإجمالي" على تقدّم حدث واحد
    final index = _overallCurrentIndex ?? _lastProgressEvent?.currentIndex;
    final total = _overallTotalItems ?? _lastProgressEvent?.totalItems;
    double? progress;
    if (index != null && total != null && total > 0) {
      progress = (index / total).clamp(0.0, 1.0).toDouble();
    }
    return SyncProgressSnapshot(
      currentPhase: _overallPhase ?? _lastProgressEvent?.phase,
      currentMessage: _overallMessage ?? _lastProgressEvent?.message,
      currentIndex: index,
      totalItems: total,
      progress: progress,
      totalEvents: _totalEvents,
      errorCount: _errorCount,
      warningCount: _warningCount,
      updatedAt: DateTime.now(),
    );
  }

  /// تصفير السجل (لا يُغلق الـstream)
  void clearRecent() {
    _recentEvents.clear();
  }

  /// تصدير كل الأحداث الحديثة كنص (للاستخدام في زر "تصدير")
  String exportAsText({int? maxLines}) {
    final list = _recentEvents.toList();
    if (maxLines != null && list.length > maxLines) {
      return list
          .sublist(list.length - maxLines)
          .map((e) => e.toString())
          .join('\n');
    }
    return list.map((e) => e.toString()).join('\n');
  }

  /// إغلاق كامل (يُستدعى عادةً عند dispose)
  Future<void> dispose() async {
    await _controller.close();
    await _progressController.close();
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// اختصار عام للوصول السريع من أي مكان
/// ═══════════════════════════════════════════════════════════════════════════
final syncBus = SyncEventBus.instance;
