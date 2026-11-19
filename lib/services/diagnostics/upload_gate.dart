// lib/services/diagnostics/upload_gate.dart
//
// 🔐 بوابة الإصلاح: لا يُنفَّذ أي إصلاح من «تشخيص الأخطاء» قبل رفع قاعدة البيانات رفعاً
// جديداً ناجحاً إلى وجهة واحدة على الأقل (تيليجرام، Dropbox، …).
//
// الرفع نفسه هو زر «رفع البيانات» في الشاشة الرئيسية بكل خطواته (MainScreen._uploadData):
// الشاشة الرئيسية تسجّله هنا عند فتحها. بعد رفع ناجح يبقى الإصلاح مفتوحاً [window]
// ليُنفَّذ أكثر من إصلاح على النسخة نفسها، ثم يُطلب رفع جديد.

import 'package:flutter/foundation.dart';

class UploadGate {
  UploadGate._();

  /// مدة صلاحية الرفع الناجح للإصلاحات المتتالية.
  static const Duration window = Duration(minutes: 15);

  static Future<bool> Function()? _runner;
  static DateTime? _lastOk;

  /// الشاشة الرئيسية تسجّل الرفع: يعيد true إن نجح إلى وجهة واحدة على الأقل.
  static void register(Future<bool> Function() runner) => _runner = runner;

  static void unregister(Future<bool> Function() runner) {
    // == لا identical: اقتطاع دالة الكائن نفسه مرتين متساويان لا متطابقان
    if (_runner == runner) _runner = null;
  }

  /// هل يمكن الرفع من هنا الآن؟
  static bool get available => _runner != null;

  /// آخر رفع ناجح بدأ من هذه البوابة.
  static DateTime? get lastOk => _lastOk;

  /// الإصلاح مفتوح (رفع ناجح خلال [window]).
  static bool get isOpen => _lastOk != null && DateTime.now().difference(_lastOk!) < window;

  /// ينتهي فتح الإصلاح في…
  static DateTime? get openUntil => isOpen ? _lastOk!.add(window) : null;

  /// يرفع الآن. لا يفتح الإصلاح إلا رفع ناجح.
  static Future<bool> uploadNow() async {
    final r = _runner;
    if (r == null) return false;
    bool ok;
    try {
      ok = await r();
    } catch (_) {
      ok = false;
    }
    if (ok) _lastOk = DateTime.now();
    return ok;
  }

  @visibleForTesting
  static void setLastOkForTest(DateTime? t) => _lastOk = t;
}
