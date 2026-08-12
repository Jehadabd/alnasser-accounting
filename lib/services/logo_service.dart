// services/logo_service.dart
// خدمة مساعدة لتحميل اللوجو المخصص
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/services/settings_manager.dart';

class LogoService {
  /// تحميل اللوجو - يستخدم اللوجو المخصص إذا كان موجودًا، وإلا يُرجع null
  /// عندما لا يوجد لوجو مخصص، لن يظهر أي شعار في الفاتورة
  static Future<pw.MemoryImage?> getLogoImage({AppSettings? appSettings}) async {
    appSettings ??= await SettingsManager.getAppSettings();
    
    // تحقق من وجود لوجو مخصص
    final customLogoPath = appSettings.invoiceDesign.logoPath;
    if (customLogoPath != null && customLogoPath.isNotEmpty) {
      final logoFile = File(customLogoPath);
      if (await logoFile.exists()) {
        try {
          final bytes = await logoFile.readAsBytes();
          return pw.MemoryImage(bytes);
        } catch (e) {
          print('خطأ في تحميل اللوجو المخصص: $e');
        }
      }
    }
    
    // لا يوجد لوجو مخصص - إرجاع null
    return null;
  }

  /// تحميل بيانات اللوجو كـ Uint8List (null إذا لم يوجد)
  static Future<Uint8List?> getLogoBytes({AppSettings? appSettings}) async {
    appSettings ??= await SettingsManager.getAppSettings();
    
    final customLogoPath = appSettings.invoiceDesign.logoPath;
    if (customLogoPath != null && customLogoPath.isNotEmpty) {
      final logoFile = File(customLogoPath);
      if (await logoFile.exists()) {
        try {
          return await logoFile.readAsBytes();
        } catch (e) {
          print('خطأ في تحميل اللوجو المخصص: $e');
        }
      }
    }
    
    return null;
  }

  /// التحقق مما إذا كان هناك لوجو مخصص
  static Future<bool> hasCustomLogo({AppSettings? appSettings}) async {
    appSettings ??= await SettingsManager.getAppSettings();
    final customLogoPath = appSettings.invoiceDesign.logoPath;
    if (customLogoPath != null && customLogoPath.isNotEmpty) {
      final logoFile = File(customLogoPath);
      return await logoFile.exists();
    }
    return false;
  }
}

