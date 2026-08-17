import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnaser/models/app_settings.dart'; // Import AppSettings model
import 'package:alnaser/models/printer_device.dart'; // Import PrinterDevice model

class SettingsManager {
  static const _keyAppSettings = 'app_settings';
  static const _keyDefaultPrinter = 'default_printer';
  static const _keyPosThermalPrinter = 'pos_thermal_printer';
  static const _keyInvoicePrinter = 'invoice_printer';

  static Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = jsonEncode(settings.toJson());
    await prefs.setString(_keyAppSettings, settingsJson);
  }

  static Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_keyAppSettings);
    if (settingsJson != null) {
      return AppSettings.fromJson(jsonDecode(settingsJson));
    }
    return AppSettings(); // Return default settings if none are saved
  }

  static Future<void> saveAppSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = jsonEncode(settings.toJson());
    await prefs.setString(_keyAppSettings, settingsJson);
  }

  static Future<AppSettings> getAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_keyAppSettings);
    if (settingsJson != null) {
      return AppSettings.fromJson(jsonDecode(settingsJson));
    }
    return AppSettings(); // Return default settings if none are saved
  }

  static Future<void> saveDefaultPrinter(PrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = jsonEncode(printer.toJson());
    await prefs.setString(_keyDefaultPrinter, printerJson);
  }

  static Future<PrinterDevice?> getDefaultPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = prefs.getString(_keyDefaultPrinter);
    if (printerJson != null) {
      return PrinterDevice.fromJson(jsonDecode(printerJson));
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🖨️ إعدادات الطابعات اليدوية (Wi-Fi / Bluetooth)
  // ═══════════════════════════════════════════════════════════════
  static const _keyManualPrinters = 'manual_printers';

  static Future<List<PrinterDevice>> getManualPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyManualPrinters) ?? [];
    return jsonList.map((str) => PrinterDevice.fromJson(jsonDecode(str))).toList();
  }

  static Future<void> addManualPrinter(PrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getManualPrinters();
    
    // تجنب التكرار
    if (current.any((p) => p.address == printer.address && p.connectionType == printer.connectionType)) {
      return;
    }
    
    current.add(printer);
    final jsonList = current.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_keyManualPrinters, jsonList);
  }

  static Future<void> removeManualPrinter(String address) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getManualPrinters();
    
    current.removeWhere((p) => p.address == address);
    
    final jsonList = current.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_keyManualPrinters, jsonList);
  }

  // ═══════════════════════════════════════════════════════════════
  // 🖨️ إعدادات الطابعات المتعددة
  // ═══════════════════════════════════════════════════════════════

  /// حفظ طابعة الكاشير الحرارية (POS Thermal Printer)
  static Future<void> savePosThermalPrinter(PrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = jsonEncode(printer.toJson());
    await prefs.setString(_keyPosThermalPrinter, printerJson);
  }

  /// جلب طابعة الكاشير الحرارية
  static Future<PrinterDevice?> getPosThermalPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = prefs.getString(_keyPosThermalPrinter);
    if (printerJson != null) {
      return PrinterDevice.fromJson(jsonDecode(printerJson));
    }
    return null;
  }

  /// حفظ طابعة الفواتير الكبيرة (A4 Invoice Printer)
  static Future<void> saveInvoicePrinter(PrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = jsonEncode(printer.toJson());
    await prefs.setString(_keyInvoicePrinter, printerJson);
  }

  /// جلب طابعة الفواتير الكبيرة
  static Future<PrinterDevice?> getInvoicePrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = prefs.getString(_keyInvoicePrinter);
    if (printerJson != null) {
      return PrinterDevice.fromJson(jsonDecode(printerJson));
    }
    return null;
  }

  // 📤 حفظ إعدادات تيليجرام (Bot Token و Channel ID)
  static Future<void> setTelegramSettings({
    required String botToken,
    required String channelId,
  }) async {
    final currentSettings = await getAppSettings();
    final updated = currentSettings.copyWith(
      telegramBotToken: botToken,
      telegramChannelId: channelId,
    );
    await saveAppSettings(updated);
  }

  // ═══════════════════════════════════════════════════════════════
  // 📤 خيارات التقارير المتقدمة (تيليجرام / ديسكورد)
  // ═══════════════════════════════════════════════════════════════
  static const _keyReportOnlyLocalInvoices = 'report_only_local_invoices';
  static const _keyReportDetailedDivided = 'report_detailed_divided';

  /// هل يجب فلترة الإحصائيات لتشمل فقط فواتير "هذا الكمبيوتر"؟
  static Future<bool> isReportOnlyLocalInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReportOnlyLocalInvoices) ?? false; // الافتراضي: إرسال جميع الفواتير
  }

  static Future<void> setReportOnlyLocalInvoices(bool onlyLocal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReportOnlyLocalInvoices, onlyLocal);
  }

  /// هل يجب إرسال التقرير مفصلاً (مقسم) أم إجمالي مدمج؟
  static Future<bool> isReportDetailedDivided() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReportDetailedDivided) ?? false; // الافتراضي: إجمالي
  }

  static Future<void> setReportDetailedDivided(bool detailed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReportDetailedDivided, detailed);
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎮 إعدادات Discord
  // ═══════════════════════════════════════════════════════════════
  static const _keyDiscordWebhookUrl = 'discord_webhook_url';

  static Future<String?> getDiscordWebhookUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDiscordWebhookUrl);
  }

  static Future<void> setDiscordWebhookUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDiscordWebhookUrl, url);
  }

  static List<dynamic> parseHierarchy(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      return [];
    }
  }
} 