// services/printing_service_android.dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:async';
import 'dart:typed_data';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';
import 'package:alnaser/services/printing_service.dart';
import 'package:alnaser/services/usb_printer_service.dart';

class PrintingServiceAndroid implements PrintingService {
  @override
  Future<PrinterDevice?> getDefaultPrinter() async {
    return await SettingsManager.getDefaultPrinter();
  }

  @override
  Future<void> printWithWifiPrinter(String ipAddress, List<int> commands, {int port = 9100}) async {
    final printer = PrinterNetworkManager(ipAddress, port: port);
    final PosPrintResult res = await printer.connect();

    if (res == PosPrintResult.success) {
      await printer.printTicket(commands);
      printer.disconnect();
    } else {
      debugPrint('Error connecting to Wi-Fi printer: $res');
      // TODO: Handle connection error
    }
  }

  @override
  Future<List<PrinterDevice>> findBluetoothPrinters() async {
    // Request Bluetooth permissions directly in this method as it's specific to Bluetooth operations
    var bluetoothPermission = await Permission.bluetooth.request();
    var bluetoothConnectPermission = await Permission.bluetoothConnect.request();
    var bluetoothScanPermission = await Permission.bluetoothScan.request();

    if (!(bluetoothPermission.isGranted && bluetoothConnectPermission.isGranted && bluetoothScanPermission.isGranted)) {
      return [];
    }

    if (await PrintBluetoothThermal.bluetoothEnabled == false) {
      debugPrint('Bluetooth is off. Please turn on Bluetooth.');
      return [];
    }

    try {
      final List<BluetoothInfo> listResult = await PrintBluetoothThermal.pairedBluetooths;
      return listResult.where((b) => b.macAdress.isNotEmpty).map((b) => PrinterDevice(
        name: b.name.isNotEmpty ? b.name : 'Unknown Device',
        address: b.macAdress,
        connectionType: PrinterConnectionType.bluetooth,
      )).toList();
    } catch (e) {
      debugPrint('Error finding Bluetooth printers: $e');
      // Optionally, you could throw a custom exception or log to a crash reporting service
      return [];
    }
  }

  @override
  Future<void> printWithBluetoothPrinter(String macAddress, List<int> commands) async {
    // Request Bluetooth permissions directly in this method
    var bluetoothPermission = await Permission.bluetooth.request();
    var bluetoothConnectPermission = await Permission.bluetoothConnect.request();
    var bluetoothScanPermission = await Permission.bluetoothScan.request();

    if (!(bluetoothPermission.isGranted && bluetoothConnectPermission.isGranted && bluetoothScanPermission.isGranted)) {
      debugPrint('Cannot print: Bluetooth permissions not granted.');
      return;
    }

    if (await PrintBluetoothThermal.bluetoothEnabled == false) {
      debugPrint('Cannot print: Bluetooth is off. Please turn on Bluetooth.');
      return;
    }

    final bool connectResult = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);

    if (connectResult) {
      await PrintBluetoothThermal.writeBytes(commands);
      await PrintBluetoothThermal.disconnect;
    } else {
      debugPrint('Error connecting to Bluetooth printer: $macAddress');
    }
  }

  @override
  Future<void> printData(Uint8List dataToPrint, {List<int>? escPosCommands, PrinterDevice? printerDevice}) async {
    final defaultPrinter = printerDevice ?? await SettingsManager.getDefaultPrinter();
    if (defaultPrinter == null) {
      debugPrint('No default printer set.');
      return;
    }

    switch (defaultPrinter.connectionType) {
      case PrinterConnectionType.wifi:
        if (escPosCommands != null) {
          await printWithWifiPrinter(defaultPrinter.address, escPosCommands, port: defaultPrinter.port ?? 9100);
        } else {
          debugPrint('ESC/POS commands are required for Wi-Fi printer.');
        }
        break;
      case PrinterConnectionType.bluetooth:
        if (escPosCommands != null) {
          await printWithBluetoothPrinter(defaultPrinter.address, escPosCommands);
        } else {
          debugPrint('ESC/POS commands are required for Bluetooth printer.');
        }
        break;
      case PrinterConnectionType.usb:
        // USB OTG printing — إرسال PDF bytes مباشرةً
        final deviceId = defaultPrinter.usbDeviceId ?? int.tryParse(defaultPrinter.address);
        if (deviceId != null) {
          await printWithUsbPrinter(deviceId, dataToPrint);
        } else {
          debugPrint('USB device ID not found for printer: ${defaultPrinter.name}');
        }
        break;
      default:
        debugPrint('Unsupported printer type for Android.');
        break;
    }
  }



  @override
  Future<List<PrinterDevice>> findUsbPrinters() async {
    return await UsbPrinterService.findUsbPrinters();
  }

  @override
  Future<bool> printWithUsbPrinter(int deviceId, Uint8List pdfBytes) async {
    return await UsbPrinterService.printBytes(
      deviceId: deviceId,
      bytes: pdfBytes,
    );
  }

  @override
  Future<List<PrinterDevice>> findSystemPrinters() {
    // Android does not have system printers in the same way Windows does.
    return Future.value([]);
  }
} 