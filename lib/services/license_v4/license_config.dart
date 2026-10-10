// lib/services/license_v4/license_config.dart
//
// ⚙️ إعدادات نظام الترخيص (الإصدار 4).
//
// • serverUrl: رابط «Web app» لسكربت Google (admintool/server/Code.gs).
// • publicKeyHex: المفتاح العام للتوقيع (ورقة info، الخلية B2). ليس سراً:
//   يتحقق به البرنامج من التوقيع، ولا يصلح لصنع تراخيص.
//   المفتاح الخاص لا يغادر Google (Script Properties).

class LicenseConfig {
  LicenseConfig._();

  /// روابط السيرفر بالترتيب: الأول هو المعتمد، والبقية احتياط إن تعطّل
  /// (نشر محذوف أو مؤرشف). كلها لنفس السكربت ونفس الجدول ونفس مفتاح التوقيع.
  static const List<String> serverUrls = [
    'https://script.google.com/macros/s/AKfycbwjQyu6uySoh48hnhnpaR_7TNhCmkXdGR4SuAfVsVlLBrT7foeiDOKf68KYS84ELVEMQQ/exec',
    'https://script.google.com/macros/s/AKfycbzluC_BLnVyqUyFO0NjJzUQDImcX0qgrmLQcOaycBT_jexqvs-RvwbDg3HNndQvYiNJJg/exec',
  ];
  static String get serverUrl => serverUrls.first;
  static const String publicKeyHex = '31dc0ccf8b49bb730d25a48a807c29ce54e01a1dbb3bc88614f693a6d37eddb6';

  /// يظهر للعميل في رسائل التجديد والتفعيل
  static const String supportPhone = '07705252905';
  static const String whatsappUrl = 'https://wa.me/9647705252905';

  static bool get isConfigured =>
      serverUrl.startsWith('https://') && publicKeyHex.length == 64;
}
