// lib/services/invoice_settings_service.dart
// إعدادات الفاتورة + معرّف الجهاز للترقيم المركّب (Composite Invoice ID).
// يطلبه database_service (stampInvoiceForSync) و invoice_actions.

import 'package:shared_preferences/shared_preferences.dart';

class InvoiceSettingsService {
  static const String _invoiceDeviceIdKey = 'invoice_device_id';
  static const String _invoiceHeaderKey = 'invoice_header';
  static const String _invoiceFooterKey = 'invoice_footer';

  /// 🔒 Cache متزامن لرقم الجهاز — يُملأ عند بدء التطبيق عبر initDeviceIdCache().
  /// يُستخدم في بناء رقم الفاتورة (formattedInvoiceNumber) الذي يجب أن يكون
  /// متزامناً ولا يستطيع استدعاء async. القيمة الافتراضية 1 حتى يُهيّأ.
  static int cachedDeviceId = 1;

  /// تهيئة cache رقم الجهاز من SharedPreferences — يُستدعى مرة عند بدء التطبيق.
  static Future<void> initDeviceIdCache() async {
    final prefs = await SharedPreferences.getInstance();
    cachedDeviceId = prefs.getInt(_invoiceDeviceIdKey) ?? 1;
  }

  /// الحصول على رقم هذا الجهاز للفواتير (افتراضياً 1 إذا لم يحدد)
  static Future<int> getInvoiceDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_invoiceDeviceIdKey) ?? 1;
    cachedDeviceId = id; // تحديث الـ cache
    return id;
  }

  /// تعيين رقم هذا الجهاز
  static Future<void> setInvoiceDeviceId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_invoiceDeviceIdKey, id);
    cachedDeviceId = id; // تحديث الـ cache فوراً
  }

  /// الحصول على ترويسة الفاتورة
  static Future<String> getInvoiceHeader() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_invoiceHeaderKey) ?? 'مؤسسة رائد الحمود التجارية';
  }

  /// تعيين ترويسة الفاتورة
  static Future<void> setInvoiceHeader(String header) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_invoiceHeaderKey, header);
  }

  /// الحصول على تذييل الفاتورة
  static Future<String> getInvoiceFooter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_invoiceFooterKey) ?? 'شكراً لتعاملكم معنا';
  }

  /// تعيين تذييل الفاتورة
  static Future<void> setInvoiceFooter(String footer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_invoiceFooterKey, footer);
  }
}
