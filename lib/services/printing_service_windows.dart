// services/printing_service_windows.dart
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
      print('No default printer set.');
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
                EndDocPrinter(hPrinter.value);
                print('Successfully printed to system printer: ${defaultPrinter.name}');
              } else {
                print('Error writing to printer: ${GetLastError()}');
              }
              free(pBytes);
              free(pBytesWritten);
            } else {
              print('Error starting document on printer: ${GetLastError()}');
            }
            ClosePrinter(hPrinter.value);
            free(docInfo.ref.pDocName);
            free(docInfo.ref.pDatatype);
            free(docInfo);
          } else {
            print('Error opening printer: ${GetLastError()}');
          }
          free(printerName);
          free(hPrinter);
        } catch (e) {
          print('Exception during system printing: $e');
        }
        break;
      default:
        print('Unsupported printer type for Windows.');
        break;
    }
  }

  @override
  Future<List<PrinterDevice>> findSystemPrinters() async {
    final List<PrinterDevice> printers = [];
    Pointer<DWORD> pcbNeeded = calloc<DWORD>();
    Pointer<DWORD> pcReturned = calloc<DWORD>();
    Pointer<PRINTER_INFO_4> pPrinterEnum = nullptr;

    try {
      // First call to get the size of the buffer needed
      EnumPrinters(
        PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
        nullptr,
        4, // Level 4 for PRINTER_INFO_4
        nullptr,
        0,
        pcbNeeded,
        pcReturned,
      );

      if (pcbNeeded.value > 0) {
        // Allocate buffer with the required size
        pPrinterEnum = calloc<PRINTER_INFO_4>(pcbNeeded.value ~/ sizeOf<PRINTER_INFO_4>());

        // Second call to get the actual printer data
        if (EnumPrinters(
          PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
          nullptr,
          4,
          pPrinterEnum.cast(),
          pcbNeeded.value,
          pcbNeeded,
          pcReturned,
        ) != 0) {
          for (int i = 0; i < pcReturned.value; i++) {
            final printerInfo = pPrinterEnum.elementAt(i).ref;
            final name = printerInfo.pPrinterName == nullptr ? 'Unknown Printer' : printerInfo.pPrinterName.toDartString();
            // For system printers, the address might not be directly available or meaningful
            // We can use the name as the identifier for now.
            printers.add(PrinterDevice(
              name: name,
              address: name, // Using name as address for system printers
              connectionType: PrinterConnectionType.system,
            ));
          }
        }
      }
    } catch (e) {
      print('Error enumerating system printers: $e');
    } finally {
      free(pcbNeeded);
      free(pcReturned);
      if (pPrinterEnum != nullptr) {
        free(pPrinterEnum);
      }
    }
    return printers;
  }

  @override
  Future<bool> _requestBluetoothPermissions() async {
    return false; // Not applicable for Windows
  }

  @override
  Future<List<PrinterDevice>> findBluetoothPrinters() async {
    return []; // Not applicable for Windows
  }

  @override
  Future<void> printWithBluetoothPrinter(String macAddress, List<int> commands) async {
    print('Bluetooth printing not supported on Windows.');
  }

  @override
  Future<void> printWithWifiPrinter(String ipAddress, List<int> commands, {int port = 9100}) async {
    print('Wi-Fi printing not supported on Windows for this implementation.');
  }
} 