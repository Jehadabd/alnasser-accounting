// services/printing_service.dart
import 'dart:async'; // For Completer
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart'; // Changed to esc_pos_utils_plus
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart'; // Keep for Bluetooth
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart'; // New import for Wi-Fi/LAN printing

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

  // Abstract method for general printing (platform-specific implementation)
  Future<void> printData(Uint8List dataToPrint, {List<int>? escPosCommands, PrinterDevice? printerDevice});

  // Abstract method for finding system printers (Windows-specific)
  Future<List<PrinterDevice>> findSystemPrinters();
} 