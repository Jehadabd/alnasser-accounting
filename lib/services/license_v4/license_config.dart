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

  /// معرّف هذا البرنامج عند السيرفر الموحّد (يرسَل مع كل طلب، ويُكتب داخل الترخيص الموقَّع).
  /// السيرفر يرفض تفعيل حساب «شوب مانجر» على «الناصر» والعكس.
  static const String appId = 'alnasser';
  static const String appLabel = 'الناصر للحسابات';

  /// روابط السيرفر بالترتيب: الأول هو المعتمد، والبقية احتياط إن تعطّل
  /// (نشر محذوف أو مؤرشف). كلها لنفس السكربت ونفس الجدول ونفس مفتاح التوقيع.
  static const List<String> serverUrls = [
    'https://script.google.com/macros/s/AKfycbz2vW4B1pJkilCKelw1-oYIXFtPRPTHGWF4-zP31Z6GgAoRlOU7PfZmvUi6PUWz_APa/exec',
  ];
  static String get serverUrl => serverUrls.first;
  static const String publicKeyHex = 'e35d89ce1ed6066e285ceab0624a19b8f42acac8eabbf29958e34ad2f8e48ec1';

  /// يظهر للعميل في رسائل التجديد والتفعيل
  static const String supportPhone = '07705252905';
  static const String whatsappUrl = 'https://wa.me/9647705252905';

  static bool get isConfigured =>
      serverUrl.startsWith('https://') && publicKeyHex.length == 64;
}
