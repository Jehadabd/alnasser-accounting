// services/usb_printer_service.dart
// خدمة الطباعة عبر USB OTG - تتواصل مع Native Android عبر Platform Channel
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:alnaser/models/printer_device.dart';

class UsbPrinterService {
  static const MethodChannel _channel = MethodChannel('usb_printer_channel');

  // ──────────────────────────────────────────────
  // اكتشاف جميع الطابعات المتصلة عبر USB OTG
  // ──────────────────────────────────────────────
  static Future<List<PrinterDevice>> findUsbPrinters() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('findUsbPrinters');
      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return PrinterDevice(
          name: map['deviceName'] as String? ?? 'USB Printer',
          address: (map['deviceId'] as int).toString(),
          connectionType: PrinterConnectionType.usb,
          vendorId: map['vendorId'] as int?,
          productId: map['productId'] as int?,
          usbDeviceId: map['deviceId'] as int?,
          manufacturerName: map['manufacturerName'] as String?,
        );
      }).toList();
    } on PlatformException catch (e) {
      print('UsbPrinterService.findUsbPrinters error: ${e.message}');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // طلب إذن الوصول للطابعة (مرة واحدة فقط)
  // ──────────────────────────────────────────────
  static Future<bool> requestPermission(int deviceId) async {
    try {
      final bool granted = await _channel.invokeMethod('requestUsbPermission', {
        'deviceId': deviceId,
      });
      return granted;
    } on PlatformException catch (e) {
      print('UsbPrinterService.requestPermission error: ${e.message}');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // إرسال بيانات الطباعة (PDF bytes) للطابعة
  // ──────────────────────────────────────────────
  static Future<bool> printBytes({
    required int deviceId,
    required Uint8List bytes,
  }) async {
    try {
      // طلب الإذن أولاً إذا لم يكن ممنوحاً
      final hasPermission = await requestPermission(deviceId);
      if (!hasPermission) {
        print('UsbPrinterService: Permission denied for device $deviceId');
        return false;
      }

      final bool success = await _channel.invokeMethod('printToUsb', {
        'deviceId': deviceId,
        'bytes': bytes,
      });
      return success;
    } on PlatformException catch (e) {
      print('UsbPrinterService.printBytes error: ${e.message}');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // فحص إذا كانت أي طابعة USB متصلة
  // ──────────────────────────────────────────────
  static Future<bool> isAnyPrinterConnected() async {
    try {
      final bool connected = await _channel.invokeMethod('isUsbPrinterConnected');
      return connected;
    } on PlatformException {
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // فحص إذا كانت طابعة محددة متصلة
  // ──────────────────────────────────────────────
  static Future<bool> isDeviceConnected(int deviceId) async {
    try {
      final bool connected = await _channel.invokeMethod('isUsbPrinterConnected', {
        'deviceId': deviceId,
      });
      return connected;
    } on PlatformException {
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // مساعد: نص وصفي للطابعة
  // ──────────────────────────────────────────────
  static String getPrinterDescription(PrinterDevice printer) {
    final manufacturer = printer.manufacturerName;
    final vid = printer.vendorId?.toRadixString(16).toUpperCase().padLeft(4, '0');
    final pid = printer.productId?.toRadixString(16).toUpperCase().padLeft(4, '0');
    if (manufacturer != null && manufacturer.isNotEmpty && manufacturer != 'Unknown') {
      return '$manufacturer (${vid ?? '?'}:${pid ?? '?'})';
    }
    return 'USB Printer (${vid ?? '?'}:${pid ?? '?'})';
  }
}
