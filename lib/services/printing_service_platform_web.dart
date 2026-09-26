// services/printing_service_platform_web.dart
// 🌐 خدمة الطباعة للويب/PWA.
//
// قيود المتصفح الفيزيائية: لا طابعة حرارية بلوتوث، لا TCP مباشر (منفذ 9100)،
// لا USB. المسار المتاح: توليد الفاتورة PDF (نفس مسار pdf الموجود) وفتح
// حوار الطباعة/التنزيل في المتصفح عبر حزمة printing.
//
// 🎯 طبقة مستقلة تماماً — لا تمس أي كود طباعة أصلي (ويندوز/أندرويد).

import 'dart:typed_data';
import 'package:alnaser/services/printing_service.dart';
import 'package:alnaser/models/printer_device.dart';

class PrintingServiceWeb extends PrintingService {
  @override
  Future<List<PrinterDevice>> findBluetoothPrinters() async => [];

  @override
  Future<List<PrinterDevice>> findUsbPrinters() async => [];

  @override
  Future<List<PrinterDevice>> findSystemPrinters() async => [];

  @override
  Future<void> printData(Uint8List dataToPrint,
      {List<int>? escPosCommands, PrinterDevice? printerDevice}) async {
    throw UnsupportedError(
        'الطباعة المباشرة غير متاحة على الويب — استخدم مسار PDF في المتصفح');
  }

  @override
  Future<void> printWithBluetoothPrinter(
      String macAddress, List<int> commands) async {
    throw UnsupportedError('طابعة البلوتوث غير مدعومة على الويب');
  }

  @override
  Future<bool> printWithUsbPrinter(int deviceId, Uint8List pdfBytes) async {
    throw UnsupportedError('طابعة USB غير مدعومة على الويب');
  }

  @override
  Future<void> printWithWifiPrinter(String ipAddress, List<int> commands,
      {int port = 9100}) async {
    throw UnsupportedError('طابعة الشبكة غير مدعومة على الويب');
  }
}

PrintingService getPlatformPrintingService() {
  return PrintingServiceWeb();
}
