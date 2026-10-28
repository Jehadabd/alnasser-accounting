// services/printing_service.dart
import 'dart:async'; // For Completer
import 'dart:typed_data';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/settings_manager.dart';

abstract class PrintingService {
  // Method to get the default printer from settings
  Future<PrinterDevice?> getDefaultPrinter() async {
    return await SettingsManager.getDefaultPrinter();
  }

  // --- Wi-Fi/LAN Printers ---
  Future<void> printWithWifiPrinter(String ipAddress, List<int> commands, {int port = 9100});

  // --- Bluetooth Printers ---
  Future<List<PrinterDevice>> findBluetoothPrinters();
  Future<void> printWithBluetoothPrinter(String macAddress, List<int> commands);

  // --- USB OTG Printers ---
  Future<List<PrinterDevice>> findUsbPrinters();
  Future<bool> printWithUsbPrinter(int deviceId, Uint8List pdfBytes);

  // Abstract method for general printing (platform-specific implementation)
  Future<void> printData(Uint8List dataToPrint, {List<int>? escPosCommands, PrinterDevice? printerDevice});

  // Abstract method for finding system printers (Windows-specific)
  Future<List<PrinterDevice>> findSystemPrinters();
} 