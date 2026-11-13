// lib/wa_messages/wa_access.dart
//
// 🔐 من يصل إلى رسائل واتساب: مدير البرنامج دائماً، والموظف بصلاحياته في «الموظفين»:
//   • إرسال الآن — يختار عملاء ويرسل مطالبة (مع كشف الحساب).
//   • الإرسال التلقائي للعملاء — يضيف عميلاً ويحدد ما يصله ويؤكد رقمه.
//   • القواعد التلقائية — ينشئ ويعدّل ويوقف القواعد (وتعمل جدولتها في جلسته).
//   • كل الصلاحيات — كل ما سبق مع طريقة الإرسال والخادم والسجل والأرقام المؤكدة.
// أزرار «إرسال عبر الخادم» على الفواتير والسندات لا تتبع هذه: تتبع صلاحية الشاشة نفسها.

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/sync_perks.dart';

class WaAccess {
  WaAccess._();

  static bool can(String key) {
    // ⭐ ميزة اشتراك المزامنة (أو حساب المالك) — بدونها لا يصل إليها أحد ولا المدير
    if (!SyncPerks.enabled) return false;
    try {
      final a = AuthService();
      if (a.isAdmin) return true;
      return a.hasPermission(AppPermissions.waAdmin) || a.hasPermission(key);
    } catch (_) {
      return false;
    }
  }

  static bool get full => can(AppPermissions.waAdmin);
  static bool get sendNow => can(AppPermissions.waSendNow);
  static bool get autoDocs => can(AppPermissions.waAutoDocs);
  static bool get rules => can(AppPermissions.waRules);

  /// له شيء من رسائل واتساب (تظهر له البطاقة في الإعدادات وسجل الديون).
  static bool get any => sendNow || autoDocs || rules;
}
