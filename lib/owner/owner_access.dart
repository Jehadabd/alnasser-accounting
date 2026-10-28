// lib/owner/owner_access.dart
//
// 👑 ميزات «حساب المالك»: المؤسسين ونقاطهم، والرفع إلى Google Drive.
//
// تُفتح فقط حين يصدر سيرفر الترخيص لهذا الجهاز ترخيصاً موقَّعاً فيه own=1
// (من أداة الأدمن: «حساب مالك»). في غير ذلك لا تظهر أزرارها ولا حقولها أبداً،
// وكأنها غير موجودة.
//
// للتجربة أثناء التطوير فقط (flutter run في وضع debug): OWNER_DEV=1 في ملف .env.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../services/license_service.dart';

class OwnerAccess {
  OwnerAccess._();

  static bool get enabled {
    if (kDebugMode && _devFlag) return true;
    try {
      final s = LicenseService();
      final p = s.payload;
      return p != null && p.isOwner && !p.isForOtherApp && s.isLicenseActivated();
    } catch (_) {
      return false;
    }
  }

  static bool get _devFlag {
    try {
      return dotenv.isInitialized && dotenv.env['OWNER_DEV'] == '1';
    } catch (_) {
      return false;
    }
  }
}
