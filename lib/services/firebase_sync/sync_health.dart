// lib/services/firebase_sync/sync_health.dart
//
// 🩺 تنبيهات صحة المزامنة للمستخدم: ما لا يستطيع الكود إصلاحه وحده ويحتاج
// تصرفاً من صاحب المحل — يُكتشف آلياً ويظهر في الشاشة الرئيسية
// (SyncHealthBanner) بدل أن يمرّ صامتاً:
//
//   • استعادة نسخة احتياطية جارية: السجلات القديمة مقفلة للتعديل حتى يلحق
//     الجهاز بالأجهزة الأخرى (DatabaseService.assertNotRestoredLocked).
//   • جهاز في المجموعة بإصدار أقدم (بروتوكول مزامنة أقدم): يحسب المخزون
//     والأرصدة بطريقة أخرى فتختلف الأرقام — يجب تحديث كل الأجهزة معاً.
//   • ساعة هذا الجهاز بعيدة عن ساعة السيرفر: «آخر تعديل يغلب» يعتمد عليها.
//   • قواعد Firestore ترفض مجموعة (permission-denied): لا تتزامن أبداً.
//   • صنفان بالاسم نفسه دُمجا: الرصيد الافتتاحي لإحدى النسختين أُهمل.
//   • صنفان بالاسم نفسه على هذا الجهاز (من إصدار سابق): جهاز ينضم لاحقاً
//     يدمجهما — أعد تسمية أحدهما (الإضافة/إعادة التسمية بالاسم نفسه صارت ممنوعة).

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncHealthLevel { info, warning, error }

class SyncHealthWarning {
  final String id;
  final SyncHealthLevel level;
  final String title;
  final String details;

  /// يخفيه المستخدم بعد أن يتصرف (تنبيه الدمج). الباقي يزول وحده متى زال سببه.
  final bool dismissible;

  const SyncHealthWarning({
    required this.id,
    required this.level,
    required this.title,
    required this.details,
    this.dismissible = false,
  });
}

class SyncHealth {
  SyncHealth._();

  /// رقم بروتوكول المزامنة — يُرفع متى وجب تحديث كل الأجهزة معاً (تغيّرت
  /// طريقة حساب أو نقل رقم). 3 = دفتر المخزون المشترك وإصلاحات المزامنة.
  /// كل جهاز يكتبه في مستنده (devices)، والإصدارات السابقة لا تكتبه (= 0).
  static const int syncProtocol = 3;

  /// أقصى فرق مقبول بين ساعة الجهاز وساعة السيرفر.
  static const Duration maxClockSkew = Duration(minutes: 5);

  /// جهاز لم يظهر منذ هذه المدة لا يُحسب (لم يعد مستعملاً).
  static const Duration activeDeviceWindow = Duration(days: 14);

  static final ValueNotifier<List<SyncHealthWarning>> warnings =
      ValueNotifier<List<SyncHealthWarning>>(const []);

  /// للاختبار فقط: إزاحة ساعة «الجهاز» عند فحص الساعة.
  @visibleForTesting
  static Duration debugClockOffset = Duration.zero;

  /// وقت الجهاز الآن كما يُقارَن بوقت السيرفر في فحص الساعة.
  static DateTime deviceNow() => DateTime.now().add(debugClockOffset);

  static bool _recovering = false;
  static List<String> _olderDevices = const [];
  static List<String> _newerDevices = const [];
  static Duration? _clockSkew;
  static List<String> _localDuplicates = const [];
  static final Set<String> _deniedCollections = <String>{};
  static List<Map<String, dynamic>> _merges = [];
  static bool _mergesLoaded = false;

  static const String _mergesKey = 'sync_health_merge_notices';

  // ─────────────────────────── المدخلات ───────────────────────────

  static void setRecovering(bool value) {
    if (_recovering == value) return;
    _recovering = value;
    _publish();
  }

  static void setDeviceVersions({required List<String> older, required List<String> newer}) {
    if (listEquals(_olderDevices, older) && listEquals(_newerDevices, newer)) return;
    _olderDevices = List.unmodifiable(older);
    _newerDevices = List.unmodifiable(newer);
    _publish();
  }

  static void setClockSkew(Duration? skew) {
    _clockSkew = skew;
    _publish();
  }

  /// أصناف متكررة الاسم على هذا الجهاز (ProductSyncService.checkLocalDuplicateNames).
  static void setLocalDuplicates(List<String> names) {
    if (listEquals(_localDuplicates, names)) return;
    _localDuplicates = List.unmodifiable(names);
    _publish();
  }

  static bool isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  /// فشل رفع إلى [collection]: يُسجَّل تنبيهاً إن كان رفض قواعد Firestore.
  static void reportUploadError(String collection, Object error) {
    if (!isPermissionDenied(error)) return;
    if (_deniedCollections.add(collection)) _publish();
  }

  /// رفع ناجح إلى [collection]: القواعد تسمح (يزول التنبيه إن كان).
  static void reportUploadOk(String collection) {
    if (_deniedCollections.remove(collection)) _publish();
  }

  /// دمج نسختين من صنف بالاسم نفسه (ProductSyncService). [id] ثابت لكل دمج
  /// (معرّف النسخة الخاسرة) فلا يتكرر التنبيه عند إعادة معالجة المستندات.
  static Future<void> addMergeNotice({required String id, required String productName}) async {
    await load();
    if (_merges.any((m) => m['id'] == id)) return;
    _merges.add({'id': id, 'name': productName, 'at': DateTime.now().toIso8601String()});
    await _saveMerges();
    _publish();
  }

  /// المستخدم راجع التنبيه (تنبيهات الدمج فقط تُخفى يدوياً).
  static Future<void> dismiss(String id) async {
    await load();
    final before = _merges.length;
    _merges.removeWhere((m) => 'merge:${m['id']}' == id);
    if (_merges.length != before) {
      await _saveMerges();
      _publish();
    }
  }

  /// يحمّل تنبيهات الدمج المحفوظة (مرة واحدة).
  static Future<void> load() async {
    if (_mergesLoaded) return;
    _mergesLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_mergesKey);
      if (raw != null && raw.isNotEmpty) {
        _merges = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {
      _merges = [];
    }
    _publish();
  }

  static Future<void> _saveMerges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_mergesKey, jsonEncode(_merges));
    } catch (_) {}
  }

  // ─────────────────────────── التنبيهات ───────────────────────────

  static void _publish() {
    final out = <SyncHealthWarning>[];
    if (_deniedCollections.isNotEmpty) {
      out.add(SyncHealthWarning(
        id: 'rules',
        level: SyncHealthLevel.error,
        title: 'قواعد Firebase تمنع مزامنة: ${_deniedCollections.map(_collectionLabel).join('، ')}',
        details: 'انسخ «قواعد الأمان» من شاشة إعداد Firebase والصقها في مشروعك '
            '(Firestore ← Rules). حتى ذلك لا تصل هذه البيانات للأجهزة الأخرى.',
      ));
    }
    if (_olderDevices.isNotEmpty) {
      out.add(SyncHealthWarning(
        id: 'older_devices',
        level: SyncHealthLevel.error,
        title: 'أجهزة بإصدار قديم من التطبيق: ${_olderDevices.join('، ')}',
        details: 'حدّثها اليوم: الإصدار القديم يحسب المخزون والأرصدة بطريقة أخرى، '
            'فتختلف الأرقام بين الأجهزة.',
      ));
    }
    if (_newerDevices.isNotEmpty) {
      out.add(SyncHealthWarning(
        id: 'this_device_older',
        level: SyncHealthLevel.error,
        title: 'هذا الجهاز بإصدار أقدم من: ${_newerDevices.join('، ')}',
        details: 'حدّث التطبيق على هذا الجهاز: الإصداران يحسبان بعض الأرقام بطريقتين مختلفتين.',
      ));
    }
    if (_recovering) {
      out.add(const SyncHealthWarning(
        id: 'recovering',
        level: SyncHealthLevel.info,
        title: 'جاري استرجاع آخر البيانات بعد استعادة نسخة احتياطية',
        details: 'السجلات القديمة (من النسخة) مقفلة للتعديل حتى يلحق هذا الجهاز بالأجهزة '
            'الأخرى — قد تكون قيمها المعروضة قديمة. البيع والتسديد الجديد مسموحان. '
            'اتصل بالإنترنت وانتظر دقائق.',
      ));
    }
    final skew = _clockSkew;
    if (skew != null && skew.abs() > maxClockSkew) {
      final minutes = skew.abs().inMinutes;
      out.add(SyncHealthWarning(
        id: 'clock',
        level: SyncHealthLevel.warning,
        title: 'ساعة هذا الجهاز غير مضبوطة (فرق $minutes دقيقة '
            '${skew.isNegative ? 'متقدمة' : 'متأخرة'})',
        details: 'فعّل «ضبط التاريخ والوقت تلقائياً» في إعدادات الجهاز: المزامنة تعتمد '
            'على الوقت لتعرف أيّ تعديل على الصنف أحدث.',
      ));
    }
    if (_localDuplicates.isNotEmpty) {
      out.add(SyncHealthWarning(
        id: 'local_duplicates',
        level: SyncHealthLevel.warning,
        title: 'أصناف مكررة الاسم على هذا الجهاز: ${_localDuplicates.take(5).join('، ')}'
            '${_localDuplicates.length > 5 ? ' و${_localDuplicates.length - 5} غيرها' : ''}',
        details: 'المزامنة تعدّ الاسم نفسه صنفاً واحداً، فجهاز ينضم لاحقاً يدمج الصنفين '
            'فتختلف كميته عن هذا الجهاز. أعد تسمية أحدهما (مثلاً بإضافة رقم أو وصف).',
      ));
    }
    for (final m in _merges) {
      out.add(SyncHealthWarning(
        id: 'merge:${m['id']}',
        level: SyncHealthLevel.warning,
        title: 'دُمج صنفان بالاسم نفسه: «${m['name']}»',
        details: 'أُنشئ الصنف على جهازين قبل أن يتزامنا فصار صنفاً واحداً. الكمية = الرصيد '
            'الأول لإحدى النسختين + كل الشراء والبيع للنسختين — راجعها بالجرد وصحّحها '
            'بـ«تعديل المخزون» إن لزم.',
        dismissible: true,
      ));
    }
    warnings.value = List.unmodifiable(out);
  }

  static String _collectionLabel(String c) {
    switch (c) {
      case 'stock_movements':
        return 'حركات المخزون';
      case 'products':
        return 'الأصناف';
      default:
        return c;
    }
  }
}
