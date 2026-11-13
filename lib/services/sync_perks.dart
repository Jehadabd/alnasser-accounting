// lib/services/sync_perks.dart
//
// ⭐ ميزات اشتراك المزامنة: رسائل واتساب الآلية (القواعد، الإرسال الآن، الإرسال التلقائي
// عند الحفظ، إرسال المستندات عبر الخادم، خادم واتساب) والرفع إلى Google Drive.
//
// تُفتح فقط لـ:
//   • حساب المالك (own=1) — كل شيء مفتوح له دائماً.
//   • ترخيص صالح الآن بوضع المزامنة (mode = full_sync) لهذا البرنامج.
// القيمتان من الترخيص الموقَّع من السيرفر، فلا يفتحهما تعديل محلي.
// في غير ذلك تختفي الميزتان تماماً ويتوقف عملهما الآلي (لا يُحذف شيء من إعداداتهما أو سجلّهما).
//
// يبقى للجميع: رابط wa.me اليدوي من بطاقة العميل والرادار (المستخدم يضغط «إرسال» بنفسه).

import '../owner/owner_access.dart';
import 'license_service.dart';

class SyncPerks {
  SyncPerks._();

  static bool get enabled {
    if (OwnerAccess.enabled) return true;
    try {
      final s = LicenseService();
      final p = s.payload;
      return p != null && p.syncAllowed && !p.isForOtherApp && s.isLicenseActivated();
    } catch (_) {
      return false;
    }
  }
}
