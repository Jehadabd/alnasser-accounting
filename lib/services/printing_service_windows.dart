// services/printing_service_windows.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:async';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/services/printing_service.dart'; // Import the abstract base class

class PrintingServiceWindows implements PrintingService {
  @override
  Future<PrinterDevice?> getDefaultPrinter() async {
    return await SettingsManager.getDefaultPrinter();
  }

  @override
  Future<void> printData(Uint8List dataToPrint, {List<int>? escPosCommands, PrinterDevice? printerDevice}) async {
    final defaultPrinter = printerDevice ?? await SettingsManager.getDefaultPrinter();
    if (defaultPrinter == null) {
      debugPrint('No default printer set.');
      return;
    }

    switch (defaultPrinter.connectionType) {
      case PrinterConnectionType.system:
      case PrinterConnectionType.usb:
        try {
          final printerName = defaultPrinter.name.toNativeUtf16();
          final hPrinter = calloc<HANDLE>();

          if (OpenPrinter(printerName, hPrinter, nullptr) != 0) {
            final docInfo = calloc<DOC_INFO_1>()
              ..ref.pDocName = 'Invoice'.toNativeUtf16()
              ..ref.pOutputFile = nullptr
              ..ref.pDatatype = 'RAW'.toNativeUtf16();

            final dwJob = StartDocPrinter(hPrinter.value, 1, docInfo);
            if (dwJob > 0) {
              final pBytesWritten = calloc<DWORD>();
              final pBytes = calloc<BYTE>(dataToPrint.length);
              for (var i = 0; i < dataToPrint.length; i++) {
                pBytes[i] = dataToPrint[i];
              }

              if (WritePrinter(hPrinter.value, pBytes, dataToPrint.length, pBytesWritten) != 0) {
                debugPrint('Successfully printed to system printer: ${defaultPrinter.name}');
              } else {
                debugPrint('Error writing to printer: ${GetLastError()}');
              }
              // المستند يُغلق دائماً بعد فتحه (كان يبقى معلّقاً في طابور الطباعة عند الفشل)
              EndDocPrinter(hPrinter.value);
              free(pBytes);
              free(pBytesWritten);
            } else {
              debugPrint('Error starting document on printer: ${GetLastError()}');
            }
            ClosePrinter(hPrinter.value);
            free(docInfo.ref.pDocName);
            free(docInfo.ref.pDatatype);
            free(docInfo);
          } else {
            debugPrint('Error opening printer: ${GetLastError()}');
          }
          free(printerName);
          free(hPrinter);
        } catch (e) {
          debugPrint('Exception during system printing: $e');
        }
        break;
      default:
        debugPrint('Unsupported printer type for Windows.');
        break;
    }
  }

  /// قائمة طابعات ويندوز (EnumPrinters مستوى 4).
  ///
  /// 🛡️ إصلاح كراش: كان المخزن يُحجز بعدد «هياكل» = البايتات ÷ حجم الهيكل
  /// (قسمة صحيحة تُسقط الباقي)، بينما يُقال لويندوز إن حجمه كامل البايتات.
  /// ويندوز يكتب الهياكل ثم أسماء الطابعات بعدها، فيتجاوز نهاية المخزن بعدة
  /// بايتات ويُفسد ذاكرة البرنامج — فيُغلق فجأة عند فتح الإعدادات أو بعدها
  /// بلحظات، بلا أي رسالة ولا سجل. الآن: المخزن بالبايتات تماماً، مع إعادة
  /// المحاولة إن أُضيفت طابعة بين الاستدعاءين.
  @override
  Future<List<PrinterDevice>> findSystemPrinters() async {
    final List<PrinterDevice> printers = [];
    const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
    final pcbNeeded = calloc<DWORD>();
    final pcReturned = calloc<DWORD>();
    Pointer<Uint8> buffer = nullptr;

    try {
      // الاستدعاء الأول: كم بايتاً نحتاج
      EnumPrinters(flags, nullptr, 4, nullptr, 0, pcbNeeded, pcReturned);

      for (var attempt = 0; attempt < 3 && pcbNeeded.value > 0; attempt++) {
        final size = pcbNeeded.value;
        if (buffer != nullptr) free(buffer);
        buffer = calloc<Uint8>(size);
        if (EnumPrinters(flags, nullptr, 4, buffer, size, pcbNeeded, pcReturned) != 0) {
          final infos = buffer.cast<PRINTER_INFO_4>();
          for (var i = 0; i < pcReturned.value; i++) {
            final info = (infos + i).ref;
            final name = info.pPrinterName == nullptr ? 'Unknown Printer' : info.pPrinterName.toDartString();
            printers.add(PrinterDevice(
              name: name,
              address: name, // اسم الطابعة هو معرّفها في ويندوز
              connectionType: PrinterConnectionType.system,
            ));
          }
          break;
        }
        // ERROR_INSUFFICIENT_BUFFER: أُضيفت طابعة بين الاستدعاءين — pcbNeeded تحدّث، نعيد
        if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) break;
      }
    } catch (e) {
      debugPrint('Error enumerating system printers: $e');
    } finally {
      free(pcbNeeded);
      free(pcReturned);
      if (buffer != nullptr) free(buffer);
    }
    return printers;
  }


  @override
  Future<List<PrinterDevice>> findBluetoothPrinters() async {
    return []; // Not applicable for Windows
  }

  @override
  Future<void> printWithBluetoothPrinter(String macAddress, List<int> commands) async {
    debugPrint('Bluetooth printing not supported on Windows.');
  }

  @override
  Future<void> printWithWifiPrinter(String ipAddress, List<int> commands, {int port = 9100}) async {
    debugPrint('Wi-Fi printing not supported on Windows for this implementation.');
  }

  @override
  Future<List<PrinterDevice>> findUsbPrinters() async {
    // USB OTG not applicable on Windows desktop
    return [];
  }

  @override
  Future<bool> printWithUsbPrinter(int deviceId, Uint8List pdfBytes) async {
    debugPrint('USB OTG printing not supported on Windows.');
    return false;
  }
} 