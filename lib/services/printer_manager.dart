import 'package:flutter/services.dart';
import 'dart:io' show Platform; // Use show Platform to avoid conflict with `Platform` in flutter/widgets.dart

class PrinterManager {
  static const MethodChannel _channel = MethodChannel('printer_settings');

  Future<void> openPrinterSettings() async {
    try {
      if (Platform.isWindows) {
        await _channel.invokeMethod('openWindowsPrinterSettings');
      } else if (Platform.isAndroid) {
        // You might want to implement a platform channel for Android settings here as well
        // or simply show a message that Android printer settings are handled internally by the app.
        print("Opening Android printer settings via platform channel is not yet implemented.");
        // Example: await _channel.invokeMethod('openAndroidPrinterSettings');
      }
    } on PlatformException catch (e) {
      print("فشل فتح إعدادات الطابعة: ${e.message}");
      // عرض رسالة خطأ للمستخدم
    }
  }
} 