// lib/services/firebase_sync/reconciliation_service.dart
//
// 🧮 نظام المطابقة بين الأجهزة.
//
// الفكرة الأساسية: لا نطابق الأجهزة ببعضها، بل نطابق كل جهاز مع السحابة.
// إن تأكد كل جهاز أن كل ما في السحابة عنده، وأن كل ما عنده في السحابة، فتساوي
// الأجهزة نتيجة حتمية لا تحتاج إثباتاً — ولا تحتاج أن يكون الجهازان متصلين في
// اللحظة نفسها، ولا تتقادم لقطة، ولا يعطّل جهاز مطفأ تدقيق غيره.
//
// الجلسة الجماعية فوق ذلك ليست شرطاً للصحة، بل وسيلة لجمع تقارير كل الأجهزة في
// مكان واحد ولحظة واحدة، لترى بعينك أن الجميع متطابق.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../database_service.dart';
import 'firebase_sync_service.dart';

/// حالة الجلسة كما تُكتب في السحابة.
class ReconciliationStatus {
  static const requesting = 'requesting';
  static const running = 'running';
  static const completed = 'completed';
  static const cancelled = 'cancelled';
  static const expired = 'expired';
}

/// فرق مكتشف لعميل واحد بين هذا الجهاز والسحابة.
class CustomerDiff {
  final String customerName;
  final String customerSyncUuid;
  final int localCount;
  final int cloudCount;
  final double localSum;
  final double cloudSum;

  /// معرّفات موجودة في السحابة وغير موجودة هنا (نقص في التنزيل).
  final List<String> missingLocally;

  /// معرّفات موجودة هنا وغير موجودة في السحابة (نقص في الرفع).
  final List<String> missingInCloud;

  /// كم من `missingInCloud` ما زال في طابور الرفع أصلاً — أي عمل معلّق لا خلل.
  final int pendingUpload;

  CustomerDiff({
    required this.customerName,
    required this.customerSyncUuid,
    required this.localCount,
    required this.cloudCount,
    required this.localSum,
    required this.cloudSum,
    this.missingLocally = const [],
    this.missingInCloud = const [],
    this.pendingUpload = 0,
  });

  /// فرق سببه كله معاملات لم تُرفع بعد ليس خللاً، بل مزامنة لم تكتمل.
  /// يشترط وجود نواقص في السحابة فعلاً؛ وإلا فاختلاف مبلغ بمعرّفات متطابقة
  /// خلل حقيقي لا يُصنَّف كمعلّق.
  bool get isOnlyPending =>
      missingLocally.isEmpty &&
      missingInCloud.isNotEmpty &&
      missingInCloud.length == pendingUpload;

  Map<String, dynamic> toMap() => {
        'customerName': customerName,
        'customerSyncUuid': customerSyncUuid,
        'localCount': localCount,
        'cloudCount': cloudCount,
        'localSum': localSum,
        'cloudSum': cloudSum,
        'missingLocally': missingLocally,
        'missingInCloud': missingInCloud,
        'pendingUpload': pendingUpload,
      };

  static CustomerDiff fromMap(Map<String, dynamic> m) => CustomerDiff(
        customerName: m['customerName'] as String? ?? '',
        customerSyncUuid: m['customerSyncUuid'] as String? ?? '',
        localCount: (m['localCount'] as num?)?.toInt() ?? 0,
        cloudCount: (m['cloudCount'] as num?)?.toInt() ?? 0,
        localSum: (m['localSum'] as num?)?.toDouble() ?? 0.0,
        cloudSum: (m['cloudSum'] as num?)?.toDouble() ?? 0.0,
        missingLocally: List<String>.from(m['missingLocally'] as List? ?? []),
        missingInCloud: List<String>.from(m['missingInCloud'] as List? ?? []),
        pendingUpload: (m['pendingUpload'] as num?)?.toInt() ?? 0,
      );
}

/// نتيجة تدقيق جهاز واحد مقابل السحابة.
class AuditResult {
  final String deviceId;
  final String deviceName;
  final DateTime completedAt;
  final int customersChecked;

  /// عملاء موجودون في السحابة ولم يصلوا هذا الجهاز إطلاقاً.
  final int customersMissingLocally;
  final double totalLocalDebt;
  final int totalLocalTransactions;
  final List<CustomerDiff> diffs;

  /// كم معاملة جُلبت وكم رُفعت أثناء العلاج.
  final int fetched;
  final int reuploaded;

  /// كم عميل جُلب من السحابة لأنه لم يكن موجوداً محلياً.
  final int customersFetched;
  final String? error;

  AuditResult({
    required this.deviceId,
    required this.deviceName,
    required this.completedAt,
    required this.customersChecked,
    required this.customersMissingLocally,
    required this.totalLocalDebt,
    required this.totalLocalTransactions,
    required this.diffs,
    this.fetched = 0,
    this.reuploaded = 0,
    this.customersFetched = 0,
    this.error,
  });

  /// الفروق التي تستحق قلقاً، بعد استبعاد ما هو مجرد رفع معلّق.
  List<CustomerDiff> get realProblems =>
      diffs.where((d) => !d.isOnlyPending).toList();

  bool get isClean =>
      error == null && realProblems.isEmpty && customersMissingLocally == 0;

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'completedAt': completedAt.toIso8601String(),
        'customersChecked': customersChecked,
        'customersMissingLocally': customersMissingLocally,
        'totalLocalDebt': totalLocalDebt,
        'totalLocalTransactions': totalLocalTransactions,
        'fetched': fetched,
        'reuploaded': reuploaded,
        'customersFetched': customersFetched,
        'error': error,
        // نحفظ عيّنة فقط: وثيقة Firestore محدودة بميغابايت واحد، وقائمة فروق
        // ضخمة قد تتجاوزه فتفشل كتابة النتيجة كلها ونخسر التقرير.
        'diffs': diffs.take(100).map((d) => d.toMap()).toList(),
        'diffsTotal': diffs.length,
      };

  static AuditResult fromMap(Map<String, dynamic> m) => AuditResult(
        deviceId: m['deviceId'] as String? ?? '',
        deviceName: m['deviceName'] as String? ?? '',
        completedAt:
            DateTime.tryParse(m['completedAt'] as String? ?? '') ?? DateTime.now(),
        customersChecked: (m['customersChecked'] as num?)?.toInt() ?? 0,
        customersMissingLocally:
            (m['customersMissingLocally'] as num?)?.toInt() ?? 0,
        totalLocalDebt: (m['totalLocalDebt'] as num?)?.toDouble() ?? 0.0,
        totalLocalTransactions:
            (m['totalLocalTransactions'] as num?)?.toInt() ?? 0,
        fetched: (m['fetched'] as num?)?.toInt() ?? 0,
        reuploaded: (m['reuploaded'] as num?)?.toInt() ?? 0,
        customersFetched: (m['customersFetched'] as num?)?.toInt() ?? 0,
        error: m['error'] as String?,
        diffs: ((m['diffs'] as List?) ?? [])
            .map((e) => CustomerDiff.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// طلب مطابقة وارد من جهاز آخر، يُعرض على المستخدم للموافقة أو الرفض.
class ReconciliationRequest {
  final String sessionId;
  final String initiatorId;
  final String initiatorName;
  final DateTime expiresAt;
  final int invitedCount;

  ReconciliationRequest({
    required this.sessionId,
    required this.initiatorId,
    required this.initiatorName,
    required this.expiresAt,
    required this.invitedCount,
  });

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

class ReconciliationService {
  static final ReconciliationService _instance =
      ReconciliationService._internal();
  factory ReconciliationService() => _instance;
  ReconciliationService._internal();

  static const String _collection = 'reconciliation_sessions';

  /// مهلة جمع الموافقات. بعدها تنتهي الجلسة ولا تعمل بموافقات ناقصة.
  static const Duration invitationWindow = Duration(minutes: 2);

  /// جهاز يُعدّ متصلاً إن وصلت نبضته خلال هذه المدة. النبضة كل 30 ثانية،
  /// فتسعون ثانية تحتمل ضياع نبضة واحدة دون أن نستبعد جهازاً حاضراً.
  static const Duration onlineWindow = Duration(seconds: 90);

  final DatabaseService _db = DatabaseService();
  final FirebaseSyncService _sync = FirebaseSyncService();

  StreamSubscription<QuerySnapshot>? _sessionsListener;
  String? _activeSessionId;
  final Set<String> _handledSessions = {};

  final _requestController = StreamController<ReconciliationRequest>.broadcast();
  final _progressController = StreamController<String>.broadcast();

  /// طلب وارد يحتاج قرار المستخدم.
  Stream<ReconciliationRequest> get onRequest => _requestController.stream;

  /// رسائل تقدّم لعرضها أثناء التدقيق.
  Stream<String> get onProgress => _progressController.stream;

  FirebaseFirestore? get _fs => _sync.firestore;
  String? get _myId => _sync.deviceId;

  /// ═════════════════════════════════════════════════════════════════════
  /// سجل الأجهزة
  /// ═════════════════════════════════════════════════════════════════════

  /// الأجهزة الحاضرة فعلاً الآن، لا كل ما سُجّل يوماً.
  ///
  /// نعتمد على نبضة القلب لا على معرّف عتادي: النبضة تخبرنا أن الجهاز يعمل
  /// ومتصل بالإنترنت الآن، وهو ما تحتاجه الجلسة فعلاً. أما الجهاز الذي أُعيد
  /// تنصيب التطبيق عليه فيبقى تسجيله القديم بلا نبضة فيسقط من العدّ تلقائياً.
  Future<List<Map<String, dynamic>>> getOnlineDevices() async {
    final fs = _fs;
    if (fs == null) return [];

    final snapshot = await fs.collection('devices').get();
    // lastSeen من السيرفر؛ نقارنه بالتوقيت المصحّح لا بساعة الجهاز المحلية،
    // وإلا ساعة متقدمة تستبعد الجميع وساعة متأخرة تعدّ أجهزة مطفأة حاضرة.
    final now = _sync.now;
    final devices = <Map<String, dynamic>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lastSeen = data['lastSeen'];
      DateTime? seenAt;
      if (lastSeen is Timestamp) {
        seenAt = lastSeen.toDate();
      } else if (lastSeen is String) {
        seenAt = DateTime.tryParse(lastSeen);
      }
      if (seenAt == null) continue;
      if (now.difference(seenAt) > onlineWindow) continue;

      devices.add({
        'deviceId': data['deviceId'] ?? doc.id,
        'deviceName': data['deviceName'] ?? 'جهاز غير معروف',
        'isCurrentDevice': (data['deviceId'] ?? doc.id) == _myId,
      });
    }
    return devices;
  }

  /// ═════════════════════════════════════════════════════════════════════
  /// الاستماع لطلبات المطابقة الواردة
  /// ═════════════════════════════════════════════════════════════════════

  void startListening() {
    final fs = _fs;
    if (fs == null || _sessionsListener != null) return;

    _sessionsListener = fs
        .collection(_collection)
        .where('status', whereIn: [
          ReconciliationStatus.requesting,
          ReconciliationStatus.running,
        ])
        .snapshots()
        .listen(_onSessionsChanged,
            onError: (e) => print('❌ خطأ في استماع جلسات المطابقة: $e'));
    print('🧮 بدأ الاستماع لطلبات المطابقة');
  }

  Future<void> stopListening() async {
    await _sessionsListener?.cancel();
    _sessionsListener = null;
  }

  void _onSessionsChanged(QuerySnapshot snapshot) {
    final myId = _myId;
    if (myId == null) return;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final sessionId = doc.id;
      final status = data['status'] as String?;
      final invited = List<String>.from(data['invited'] as List? ?? []);
      if (!invited.contains(myId)) continue;

      final initiatorId = data['initiatorId'] as String?;
      if (initiatorId == myId) continue; // الطالب يدير جلسته بنفسه

      final expiresAt =
          DateTime.tryParse(data['expiresAt'] as String? ?? '') ?? DateTime.now();

      if (status == ReconciliationStatus.requesting) {
        final responses =
            Map<String, dynamic>.from(data['responses'] as Map? ?? {});
        if (responses.containsKey(myId)) continue; // أجبنا سابقاً
        if (DateTime.now().isAfter(expiresAt)) continue; // فات الأوان
        if (!_handledSessions.add('req_$sessionId')) continue;

        _requestController.add(ReconciliationRequest(
          sessionId: sessionId,
          initiatorId: initiatorId ?? '',
          initiatorName: data['initiatorName'] as String? ?? 'جهاز آخر',
          expiresAt: expiresAt,
          invitedCount: invited.length,
        ));
      } else if (status == ReconciliationStatus.running) {
        final results = Map<String, dynamic>.from(data['results'] as Map? ?? {});
        if (results.containsKey(myId)) continue; // نشرنا نتيجتنا
        if (!_handledSessions.add('run_$sessionId')) continue;

        // وافقنا، والجلسة انطلقت: ندقّق أنفسنا وننشر النتيجة.
        unawaited(_runAndPublish(sessionId));
      }
    }
  }

  /// ═════════════════════════════════════════════════════════════════════
  /// إدارة الجلسة
  /// ═════════════════════════════════════════════════════════════════════

  /// بدء طلب مطابقة ودعوة كل الأجهزة الحاضرة.
  /// يُعيد معرّف الجلسة، أو يرمي استثناءً إن تعذّر البدء.
  Future<String> requestSession() async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null) {
      throw Exception('المزامنة غير مفعّلة على هذا الجهاز');
    }

    final devices = await getOnlineDevices();
    final invited = devices.map((d) => d['deviceId'] as String).toList();
    if (!invited.contains(myId)) invited.add(myId);

    final now = DateTime.now();
    final sessionId =
        'rec_${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    String myName = 'هذا الجهاز';
    for (final d in devices) {
      if (d['deviceId'] == myId) myName = d['deviceName'] as String;
    }

    await fs.collection(_collection).doc(sessionId).set({
      'sessionId': sessionId,
      'initiatorId': myId,
      'initiatorName': myName,
      'createdAt': now.toIso8601String(),
      'expiresAt': now.add(invitationWindow).toIso8601String(),
      'status': ReconciliationStatus.requesting,
      'invited': invited,
      // الطالب موافق ضمناً؛ لا معنى لأن يستأذن نفسه.
      'responses': {myId: 'accepted'},
      'results': <String, dynamic>{},
    });

    _activeSessionId = sessionId;
    _handledSessions.add('req_$sessionId');
    print('🧮 طُلبت جلسة مطابقة $sessionId ودُعي ${invited.length} جهاز');
    return sessionId;
  }

  /// ردّ هذا الجهاز على دعوة.
  Future<void> respond(String sessionId, {required bool accept}) async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null) return;

    final ref = fs.collection(_collection).doc(sessionId);
    await ref.update({
      'responses.$myId': accept ? 'accepted' : 'rejected',
      if (!accept) 'status': ReconciliationStatus.cancelled,
      if (!accept) 'cancelledBy': myId,
    });

    if (accept) {
      // نمهّد الطريق: نرفع ما لدينا من معلّق قبل التدقيق، وإلا اشتكى التدقيق
      // من نقص هو في حقيقته عمل لم يُرسل بعد.
      _handledSessions.add('req_$sessionId');
    }
  }

  /// متابعة جلسة حيّة (يستخدمها الطالب لعرض التقدّم والنتائج).
  Stream<DocumentSnapshot> watchSession(String sessionId) {
    final fs = _fs;
    if (fs == null) return const Stream.empty();
    return fs.collection(_collection).doc(sessionId).snapshots();
  }

  /// يستدعيها الطالب دورياً: يبدأ التنفيذ عند اكتمال الموافقات، أو ينهي
  /// الجلسة إن انقضت المهلة أو رفض أحدهم.
  Future<String> evaluateSession(String sessionId) async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null) return ReconciliationStatus.expired;

    final ref = fs.collection(_collection).doc(sessionId);
    final snap = await ref.get();
    if (!snap.exists) return ReconciliationStatus.expired;

    final data = snap.data() as Map<String, dynamic>;
    final status = data['status'] as String? ?? '';
    if (status != ReconciliationStatus.requesting) return status;

    final invited = List<String>.from(data['invited'] as List? ?? []);
    final responses = Map<String, dynamic>.from(data['responses'] as Map? ?? {});
    final expiresAt =
        DateTime.tryParse(data['expiresAt'] as String? ?? '') ?? DateTime.now();

    if (responses.values.contains('rejected')) {
      await ref.update({'status': ReconciliationStatus.cancelled});
      return ReconciliationStatus.cancelled;
    }

    final allAccepted =
        invited.every((id) => responses[id] == 'accepted');

    if (allAccepted) {
      await ref.update({'status': ReconciliationStatus.running});
      unawaited(_runAndPublish(sessionId));
      return ReconciliationStatus.running;
    }

    if (DateTime.now().isAfter(expiresAt)) {
      // 🔒 لا نشغّل مطابقة بموافقات ناقصة: تقرير عن بعض الأجهزة يوهم بشمول
      // لا وجود له، وهو أسوأ من غياب التقرير.
      await ref.update({'status': ReconciliationStatus.expired});
      return ReconciliationStatus.expired;
    }

    return ReconciliationStatus.requesting;
  }

  /// هل وصلت نتائج كل المدعوّين؟ عندها نغلق الجلسة.
  Future<bool> finalizeIfComplete(String sessionId) async {
    final fs = _fs;
    if (fs == null) return false;

    final ref = fs.collection(_collection).doc(sessionId);
    final snap = await ref.get();
    if (!snap.exists) return false;

    final data = snap.data() as Map<String, dynamic>;
    if (data['status'] != ReconciliationStatus.running) {
      return data['status'] == ReconciliationStatus.completed;
    }

    final invited = List<String>.from(data['invited'] as List? ?? []);
    final results = Map<String, dynamic>.from(data['results'] as Map? ?? {});
    if (invited.every(results.containsKey)) {
      await ref.update({'status': ReconciliationStatus.completed});
      return true;
    }
    return false;
  }

  Future<void> _runAndPublish(String sessionId) async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null) return;

    AuditResult result;
    try {
      result = await runSelfAudit(repair: true);
    } catch (e) {
      result = AuditResult(
        deviceId: myId,
        deviceName: 'جهاز',
        completedAt: DateTime.now(),
        customersChecked: 0,
        customersMissingLocally: 0,
        totalLocalDebt: 0,
        totalLocalTransactions: 0,
        diffs: const [],
        error: e.toString(),
      );
    }

    try {
      await fs
          .collection(_collection)
          .doc(sessionId)
          .update({'results.$myId': result.toMap()});
    } catch (e) {
      print('⚠️ تعذّر نشر نتيجة المطابقة: $e');
    }
  }

  /// ═════════════════════════════════════════════════════════════════════
  /// محرّك التدقيق: هذا الجهاز مقابل السحابة
  /// ═════════════════════════════════════════════════════════════════════

  /// تدقيق شامل لهذا الجهاز وحده. يعمل بلا حاجة لأي جهاز آخر.
  ///
  /// الطبقة الأولى رخيصة: نسأل السحابة عن عدد معاملات كل عميل ومجموعها عبر
  /// استعلام تجميعي يُحسب على الخادم، فيكلّف قراءة واحدة عن كل ألف وثيقة بدل
  /// تنزيلها جميعاً. الطبقة الثانية لا تعمل إلا على العملاء الذين اختلف فيهم
  /// العدد أو المجموع، فتنزّل معرّفاتهم وتحدد المعاملة الناقصة بعينها.
  Future<AuditResult> runSelfAudit({bool repair = false}) async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null) {
      throw Exception('المزامنة غير مفعّلة');
    }

    final db = await _db.database;
    final startedAt = DateTime.now();

    // ──٠── جلب العملاء الناقصين أولاً. بدونهم لا معنى لتدقيق معاملاتهم،
    // لأن حلقة التدقيق تمرّ على العملاء المحليين فقط.
    int customersFetched = 0;
    if (repair) {
      _progressController.add('جاري جلب العملاء الناقصين...');
      customersFetched = await _fetchMissingCustomers();
    }

    _progressController.add('جاري قراءة البيانات المحلية...');

    final customers = await db.query(
      'customers',
      columns: ['id', 'name', 'sync_uuid'],
      where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
    );

    // خريطة العميل المحلي: العدد والمجموع من مصدر واحد.
    final localAgg = await db.rawQuery('''
      SELECT c.sync_uuid AS uuid,
             COUNT(t.id) AS cnt,
             COALESCE(SUM(t.amount_changed), 0) AS total
      FROM customers c
      LEFT JOIN transactions t
             ON t.customer_id = c.id
            AND (t.is_deleted IS NULL OR t.is_deleted = 0)
      WHERE c.sync_uuid IS NOT NULL
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
      GROUP BY c.sync_uuid
    ''');

    final localCounts = <String, int>{};
    final localSums = <String, double>{};
    for (final row in localAgg) {
      final uuid = row['uuid'] as String;
      localCounts[uuid] = (row['cnt'] as num?)?.toInt() ?? 0;
      localSums[uuid] = (row['total'] as num?)?.toDouble() ?? 0.0;
    }

    final diffs = <CustomerDiff>[];
    int fetched = 0;
    int reuploaded = 0;
    int checked = 0;

    for (final customer in customers) {
      final uuid = customer['sync_uuid'] as String;
      final name = customer['name'] as String? ?? 'غير معروف';
      checked++;

      if (checked % 10 == 0) {
        _progressController
            .add('جاري التدقيق ($checked/${customers.length})...');
      }

      // الطبقة الأولى رخيصة على الخادم. نستبعد المحذوف صراحةً حتى لا يختلط
      // برصيدٍ لا يجب أن يُحسب.
      final query = fs
          .collection('transactions')
          .where('customerSyncUuid', isEqualTo: uuid)
          .where('isDeleted', isEqualTo: false);

      int cloudCount;
      double cloudSum;
      try {
        final agg = await query
            .aggregate(count(), sum('amountChanged'))
            .get(source: AggregateSource.server);
        cloudCount = agg.count ?? 0;
        cloudSum = agg.getSum('amountChanged')?.toDouble() ?? 0.0;
      } catch (e) {
        // وثائق قديمة بلا حقل isDeleted قد تفشل التجميع المصفّى؛ نعيد
        // المحاولة بلا فلتر ونصفّي المحذوف يدوياً في الطبقة الثانية.
        print('⚠️ تجميع مصفّى فشل لـ $name، إعادة بلا فلتر: $e');
        try {
          final fallback = fs
              .collection('transactions')
              .where('customerSyncUuid', isEqualTo: uuid);
          final agg = await fallback
              .aggregate(count(), sum('amountChanged'))
              .get(source: AggregateSource.server);
          cloudCount = agg.count ?? 0;
          cloudSum = agg.getSum('amountChanged')?.toDouble() ?? 0.0;
        } catch (e2) {
          print('⚠️ تعذّر تجميع بيانات العميل $name: $e2');
          continue;
        }
      }

      final localCount = localCounts[uuid] ?? 0;
      final localSum = localSums[uuid] ?? 0.0;

      if (localCount == cloudCount && (localSum - cloudSum).abs() <= 0.01) {
        continue; // متطابق
      }

      // ── الطبقة الثانية: تحديد المعاملة الناقصة بعينها ──
      final cloudDocs = await fs
          .collection('transactions')
          .where('customerSyncUuid', isEqualTo: uuid)
          .get(const GetOptions(source: Source.server));
      final cloudUuids = <String, Map<String, dynamic>>{};
      for (final doc in cloudDocs.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true) continue;
        cloudUuids[doc.id] = data;
      }

      // إن فشل الفلتر في الطبقة الأولى، نصحّح العدد والمجموع من الوثائق نفسها.
      cloudCount = cloudUuids.length;
      cloudSum = cloudUuids.values.fold<double>(
          0.0, (s, d) => s + ((d['amountChanged'] as num?)?.toDouble() ?? 0.0));

      if (localCount == cloudCount && (localSum - cloudSum).abs() <= 0.01) {
        continue;
      }

      final localRows = await db.rawQuery('''
        SELECT t.transaction_uuid AS uuid, t.is_uploaded AS uploaded
        FROM transactions t
        INNER JOIN customers c ON c.id = t.customer_id
        WHERE c.sync_uuid = ?
          AND t.transaction_uuid IS NOT NULL
          AND (t.is_deleted IS NULL OR t.is_deleted = 0)
      ''', [uuid]);

      final localUuids = <String, bool>{}; // uuid -> uploaded
      for (final row in localRows) {
        localUuids[row['uuid'] as String] =
            ((row['uploaded'] as num?)?.toInt() ?? 0) == 1;
      }

      final missingLocally =
          cloudUuids.keys.where((u) => !localUuids.containsKey(u)).toList();
      final missingInCloud =
          localUuids.keys.where((u) => !cloudUuids.containsKey(u)).toList();
      final pending =
          missingInCloud.where((u) => localUuids[u] == false).length;

      // ── العلاج: نجلب الناقص ونرفع غير المرفوع، ولا نخترع مبلغاً أبداً ──
      if (repair) {
        for (final missing in missingLocally) {
          try {
            await _sync.applyRemoteTransaction(missing, cloudUuids[missing]!);
            fetched++;
          } catch (e) {
            print('⚠️ تعذّر جلب المعاملة $missing: $e');
          }
        }

        for (final notUp in missingInCloud) {
          try {
            final rows = await db.query('transactions',
                where: 'transaction_uuid = ?', whereArgs: [notUp], limit: 1);
            if (rows.isEmpty) continue;
            if (await _sync.uploadTransaction(
                Map<String, dynamic>.from(rows.first), uuid)) {
              reuploaded++;
            }
          } catch (e) {
            print('⚠️ تعذّر رفع المعاملة $notUp: $e');
          }
        }

        // معرّف مشترك ومبلغ مختلف: السحابة هي المرجع لأن صاحب السجل هو من
        // يكتب إليها. نمرّر التحديث عبر مسار الاستقبال الذي يعيد حساب الرصيد.
        if (missingLocally.isEmpty && missingInCloud.isEmpty) {
          for (final entry in cloudUuids.entries) {
            final localRow = await db.query(
              'transactions',
              columns: ['amount_changed', 'is_created_by_me'],
              where: 'transaction_uuid = ?',
              whereArgs: [entry.key],
              limit: 1,
            );
            if (localRow.isEmpty) continue;
            // لا نكتب فوق معاملة أنشأها هذا الجهاز — هو مصدر الحقيقة لها.
            if (((localRow.first['is_created_by_me'] as num?)?.toInt() ?? 1) ==
                1) {
              continue;
            }
            final localAmt =
                (localRow.first['amount_changed'] as num?)?.toDouble() ?? 0.0;
            final cloudAmt =
                (entry.value['amountChanged'] as num?)?.toDouble() ?? 0.0;
            if ((localAmt - cloudAmt).abs() <= 0.01) continue;
            try {
              await _sync.applyRemoteTransaction(entry.key, entry.value);
              fetched++;
            } catch (e) {
              print('⚠️ تعذّر تحديث المعاملة ${entry.key}: $e');
            }
          }
        }
      }

      diffs.add(CustomerDiff(
        customerName: name,
        customerSyncUuid: uuid,
        localCount: localCount,
        cloudCount: cloudCount,
        localSum: localSum,
        cloudSum: cloudSum,
        missingLocally: missingLocally,
        missingInCloud: missingInCloud,
        pendingUpload: pending,
      ));
    }

    // عملاء ما زالوا في السحابة ولم يصلوا بعد العلاج (فشل جلب أو تعطيل repair).
    int customersMissingLocally = 0;
    try {
      final localSet = customers
          .map((c) => c['sync_uuid'] as String)
          .toSet();
      final cloudSnap = await fs
          .collection('customers')
          .get(const GetOptions(source: Source.server));
      for (final doc in cloudSnap.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true) continue;
        if (!localSet.contains(doc.id)) customersMissingLocally++;
      }
    } catch (e) {
      print('⚠️ تعذّر عدّ عملاء السحابة: $e');
    }

    final totalsRow = await db.rawQuery('''
      SELECT COUNT(*) AS cnt, COALESCE(SUM(amount_changed), 0) AS total
      FROM transactions
      WHERE (is_deleted IS NULL OR is_deleted = 0)
    ''');

    final result = AuditResult(
      deviceId: myId,
      deviceName: await _myDeviceName(),
      completedAt: DateTime.now(),
      customersChecked: checked,
      customersMissingLocally: customersMissingLocally,
      totalLocalDebt: (totalsRow.first['total'] as num?)?.toDouble() ?? 0.0,
      totalLocalTransactions: (totalsRow.first['cnt'] as num?)?.toInt() ?? 0,
      diffs: diffs,
      fetched: fetched,
      reuploaded: reuploaded,
      customersFetched: customersFetched,
    );

    final elapsed = DateTime.now().difference(startedAt);
    print('🧮 اكتمل التدقيق في ${elapsed.inSeconds} ثانية: '
        '${diffs.length} فرق، جُلبت $fetched وسُحِب $customersFetched عميل '
        'ورُفعت $reuploaded');

    return result;
  }

  /// ينزّل كل عميل موجود في السحابة وغير موجود محلياً.
  Future<int> _fetchMissingCustomers() async {
    final fs = _fs;
    if (fs == null) return 0;

    final db = await _db.database;
    final local = await db.query(
      'customers',
      columns: ['sync_uuid'],
      where: 'sync_uuid IS NOT NULL',
    );
    final localSet =
        local.map((r) => r['sync_uuid'] as String).toSet();

    final cloudSnap = await fs
        .collection('customers')
        .get(const GetOptions(source: Source.server));

    int fetched = 0;
    for (final doc in cloudSnap.docs) {
      final data = doc.data();
      if (data['isDeleted'] == true) continue;
      if (localSet.contains(doc.id)) continue;
      try {
        await _sync.applyRemoteCustomer(doc.id, data);
        fetched++;
      } catch (e) {
        print('⚠️ تعذّر جلب العميل ${doc.id}: $e');
      }
    }
    if (fetched > 0) {
      print('🧮 جُلب $fetched عميل ناقص من السحابة');
    }
    return fetched;
  }

  Future<String> _myDeviceName() async {
    final devices = await getOnlineDevices();
    for (final d in devices) {
      if (d['deviceId'] == _myId) return d['deviceName'] as String;
    }
    return 'هذا الجهاز';
  }

  /// ═════════════════════════════════════════════════════════════════════
  /// التشغيل التلقائي عند سكون النظام
  /// ═════════════════════════════════════════════════════════════════════

  Timer? _idleTimer;
  DateTime? _lastAuditAt;
  DateTime _lastActivityAt = DateTime.now();

  /// تُستدعى عند كل نشاط مزامنة، لتأجيل التدقيق حتى يهدأ التدفق.
  void noteActivity() => _lastActivityAt = DateTime.now();

  /// مهلة السكون: التدقيق أثناء تدفق البيانات يكذب، لأن معاملة في طريقها
  /// إلينا الآن تُحسب نقصاً وهي ليست كذلك.
  static const Duration idleRequired = Duration(minutes: 2);
  static const Duration auditCooldown = Duration(hours: 1);

  void startAutoAudit() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (!_sync.isOnline) return;
      if (DateTime.now().difference(_lastActivityAt) < idleRequired) return;
      if (_lastAuditAt != null &&
          DateTime.now().difference(_lastAuditAt!) < auditCooldown) {
        return;
      }

      final db = await _db.database;
      final pending = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM transactions '
        'WHERE (is_uploaded IS NULL OR is_uploaded = 0) '
        'AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      if (((pending.first['c'] as num?)?.toInt() ?? 0) > 0) return;

      _lastAuditAt = DateTime.now();
      try {
        final result = await runSelfAudit(repair: true);
        if (!result.isClean) {
          print('🧮 التدقيق التلقائي وجد ${result.realProblems.length} فرقاً');
        }
      } catch (e) {
        print('⚠️ فشل التدقيق التلقائي: $e');
      }
    });
  }

  void stopAutoAudit() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  String? get activeSessionId => _activeSessionId;

  void dispose() {
    stopAutoAudit();
    stopListening();
  }
}
