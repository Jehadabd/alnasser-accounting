// lib/services/simplex/upload_route.dart
//
// 🔀 مسار الإرسال: محتوى تيليجرام نفسه (القاعدة، تقرير الديون، الكشوفات، الفواتير،
// الملخص الشهري) يُرسل إلى SimpleX بلا نسخ أي منطق. زر «رفع البيانات» يشغّل خطوات
// تيليجرام داخل [runSimplex]، فترى TelegramBackupService أن المسار SimpleX وتسلّم
// الرسائل والملفات لـ SimplexBackupService.
//
// المسار قيمة في Zone (لا متغيّر عام): تبقى مع كل await داخل الرفع فقط، فرسالة
// تيليجرام أخرى تعمل في الوقت نفسه (ملخص المالك اليومي مثلاً) تذهب لتيليجرام كالعادة.
//
// لكل مسار سجله الخاص: فاتورة أُرسلت لتيليجرام لا تُعدّ مرسلة إلى SimpleX، والعكس.

import 'dart:async';

class UploadRoute {
  UploadRoute._();

  static const _key = #alnaserUploadRoute;
  static const simplex = 'simplex';

  /// هل الكود الجاري الآن داخل رفع SimpleX؟
  static bool get isSimplex => Zone.current[_key] == simplex;

  /// يشغّل [body] على مسار SimpleX (وكل ما ينتظره من استدعاءات).
  static Future<T> runSimplex<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: simplex});

  /// جدول «ما أُرسل من الفواتير» لهذا المسار (محلي، لا يُزامَن).
  static String get sentTable => isSimplex ? 'simplex_sent' : 'telegram_sent';

  /// مفتاح نقطة بداية إرسال الفواتير لهذا المسار.
  static String get lastUploadKey => isSimplex ? 'simplex_last_upload_time' : 'telegram_last_upload_time';
}
