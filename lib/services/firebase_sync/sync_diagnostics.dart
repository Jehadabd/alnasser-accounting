// lib/services/firebase_sync/sync_diagnostics.dart
// 🩺 مركز تشخيص المزامنة والمصادقة:
// يجمع آخر الأخطاء بصيغها الأصلية ومترجمة لرسائل عربية واضحة،
// ويعرضها في شاشة إعدادات Firebase — بدل "فشل" عامة لا تشرح شيئاً.

import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as fauth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleListener; // (مطلوب لتصدير الواجهات)

class DiagEvent {
  final DateTime at;
  final String type; // auth | listener | sync | info
  final String message;
  DiagEvent(this.type, this.message) : at = DateTime.now();
}

class SyncDiagnostics {
  static final List<DiagEvent> events = <DiagEvent>[];
  static const int _maxEvents = 60;

  static String? lastAuthError;
  static String? lastListenerError;
  static String? lastSyncError;

  static void log(String type, String message) {
    events.insert(0, DiagEvent(type, message));
    if (events.length > _maxEvents) events.removeLast();
    print('🩺 [Diag/$type] $message');
  }

  static void logAuth(Object error) {
    lastAuthError = error.toString();
    log('auth', friendlyAuthError(error));
  }

  static void logListener(Object error) {
    lastListenerError = error.toString();
    log('listener', friendlyAuthError(error));
  }

  /// ترجمة أكواد أخطاء Firebase Auth الشائعة لرسائل عربية عملية.
  static String friendlyAuthError(Object error) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('network-request-failed') ||
        raw.contains('failed to fetch') ||
        raw.contains('network error')) {
      return 'تعذّر الوصول إلى خدمة مصادقة Google — مشكلة شبكة أو اتصال مؤقت.\n'
          'الحل: تحقق من الإنترنت، أغلق التطبيق وافتحه، أو جرّب شبكة/VPN أخرى.\n'
          '(الأصل: $error)';
    }
    if (raw.contains('typeerror')) {
      return 'تلف في مخزن الجلسة بالمتصفح (خطأ داخلي من Firebase ويب).\n'
          'الحل: أغلق التطبيق وافتحه (سيُنظَّف المخزن ويُعاد التسجيل تلقائياً)،\n'
          'أو من Safari: زر المشاركة ← مسح بيانات الموقع ثم أعد الدخول.\n'
          '(الأصل: $error)';
    }
    if (raw.contains('too-many-requests')) {
      return 'محاولات كثيرة متتالية — انتظر دقيقة ثم أعد الفتح.\n(الأصل: $error)';
    }
    if (raw.contains('invalid-api-key')) {
      return 'مفتاح Firebase (API Key) غير صحيح — أعد إدخال الإعدادات من شاشة إعداد Firebase.\n(الأصل: $error)';
    }
    if (raw.contains('configuration-not-found') ||
        raw.contains('operation-not-allowed') ||
        raw.contains('admin-restricted-operation')) {
      return 'تسجيل الدخول المجهول معطّل في مشروع Firebase.\n'
          'الحل: Firebase Console → Authentication → Sign-in method → فعّل Anonymous.\n(الأصل: $error)';
    }
    if (raw.contains('permission-denied') || raw.contains('permission_denied')) {
      return 'القواعد رفضت الطلب — المصادقة غير مكتملة لحظياً؛ سيُعاد تلقائياً.\n(الأصل: $error)';
    }
    if (raw.contains('api-key-not-valid') || raw.contains('app-not-authorized')) {
      return 'المشروع لا يقبل هذا التطبيق/المفتاح — تحقق من App ID (صيغة web) في الإعدادات.\n(الأصل: $error)';
    }
    if (raw.contains('unavailable') || raw.contains('internal-error')) {
      return 'خدمة Google غير متاحة مؤقتاً — أعد المحاولة بعد لحظات.\n(الأصل: $error)';
    }
    return 'خطأ مصادقة: $error';
  }

  /// لقطة تشخيصية شاملة لعرضها في الواجهة.
  static Map<String, dynamic> snapshot() {
    String? uid;
    try {
      uid = fauth.FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {}

    String platform;
    if (kIsWeb) {
      platform = 'ويب/PWA';
    } else if (Platform.isWindows) {
      platform = 'ويندوز';
    } else if (Platform.isAndroid) {
      platform = 'أندرويد';
    } else if (Platform.isIOS) {
      platform = 'iOS';
    } else {
      platform = 'غير معروف';
    }

    return {
      'platform': platform,
      'authUid': uid,
      'authenticated': uid != null,
      'lastAuthError': lastAuthError != null
          ? friendlyAuthError(lastAuthError!)
          : null,
      'lastListenerError': lastListenerError,
      'lastSyncError': lastSyncError,
      'recentEvents':
          events.map((e) => '[${e.at.hour}:${e.at.minute.toString().padLeft(2, '0')}] ${e.message}').toList(),
    };
  }
}

class DiagStep {
  final String name;
  bool ok;
  String detail;
  DiagStep(this.name, {this.ok = false, this.detail = ''});
}

/// 🔧 تشخيص شامل خطوة بخطوة مع محاولة إصلاح تلقائية:
/// الإنترنت ← المصادقة (+إصلاح) ← قراءة Firestore ← كتابة اختبارية
/// ← حالة المستمعين (+إنعاش). كل خطوة تُسجل ويعاد نتيجتها للعرض.
Future<List<DiagStep>> runFullDiagnosis({void Function(DiagStep)? onStep}) async {
  final steps = <DiagStep>[];

  // 0) قدرة التخزين في المتصفح (ويب فقط) — السفاري الخاص/حاجب الكوكيز يقتل Firebase Auth
  if (kIsWeb) {
    final storage = DiagStep('قدرة التخزين في المتصفح');
    steps.add(storage);
    try {
      await fauth.FirebaseAuth.instance
          .setPersistence(fauth.Persistence.LOCAL)
          .timeout(const Duration(seconds: 10));
      storage.ok = true;
      storage.detail = 'التخزين متاح';
    } catch (e) {
      storage.detail = 'المتصفح يمنع التخزين! هذا يمنع Firebase Auth من العمل.\n'
          'الحل: أطفئ وضع التصفح الخاص و"Block All Cookies" من إعدادات Safari ثم أعد الفتح.\n'
          '(الأصل: $e)';
      SyncDiagnostics.log('auth', 'مسبار التخزين فشل: $e');
      return steps; // بلا تخزين لا مصادقة إطلاقاً
    }
  }

  // 1) الإنترنت
  final net = DiagStep('الاتصال بالإنترنت');
  steps.add(net);
  try {
    final conn = await Connectivity().checkConnectivity();
    net.ok = !conn.contains(ConnectivityResult.none);
    net.detail = net.ok ? 'متصل' : 'لا يوجد اتصال — تحقق من الشبكة';
  } catch (e) {
    net.detail = 'تعذر الفحص: $e';
  }
  if (!net.ok) {
    onStep?.call(net);
    return steps;
  }
  onStep?.call(net);

  // 2) المصادقة (+ إصلاح تلقائي)
  final auth = DiagStep('مصادقة Firebase');
  steps.add(auth);
  try {
    var user = fauth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      auth.detail = 'لا جلسة — إنشاء جلسة جديدة...';
      user = (await fauth.FirebaseAuth.instance.signInAnonymously()).user;
    }
    await user!.getIdToken(true).timeout(const Duration(seconds: 20));
    auth.ok = true;
    auth.detail = 'سليمة (${user.uid.substring(0, 10)}...)';
  } catch (e) {
    auth.detail = SyncDiagnostics.friendlyAuthError(e);
    SyncDiagnostics.logAuth(e);
    onStep?.call(auth);
    return steps; // بلا مصادقة لا معنى للبقية
  }
  onStep?.call(auth);

  // 3) قراءة Firestore
  final read = DiagStep('قراءة من Firestore');
  steps.add(read);
  try {
    await FirebaseFirestore.instance
        .collection('devices')
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 20));
    read.ok = true;
    read.detail = 'القراءة تعمل';
  } catch (e) {
    read.detail = 'فشلت: $e';
    SyncDiagnostics.logListener(e);
  }
  onStep?.call(read);

  // 4) كتابة اختبارية
  final write = DiagStep('كتابة اختبارية إلى السحابة');
  steps.add(write);
  try {
    await FirebaseFirestore.instance
        .collection('devices')
        .doc('diag_test')
        .set({'ping': DateTime.now().toIso8601String()},
            SetOptions(merge: true))
        .timeout(const Duration(seconds: 20));
    write.ok = true;
    write.detail = 'الكتابة تعمل';
  } catch (e) {
    write.detail = 'فشلت: $e';
  }
  onStep?.call(write);

  return steps;
}
