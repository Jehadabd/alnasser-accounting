// models/printer_device.dart
class PrinterDevice {
  final String name;
  final String address; // IP for WiFi, MAC for BT, deviceId string for USB
  final PrinterConnectionType connectionType;
  final bool isDefault;
  final int? port;
  // USB-specific fields
  final int? vendorId;
  final int? productId;
  final int? usbDeviceId;
  final String? manufacturerName;

  PrinterDevice({
    required this.name,
    required this.address,
    required this.connectionType,
    this.isDefault = false,
    this.port,
    this.vendorId,
    this.productId,
    this.usbDeviceId,
    this.manufacturerName,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'connectionType': connectionType.toString(),
        'isDefault': isDefault,
        'port': port,
        'vendorId': vendorId,
        'productId': productId,
        'usbDeviceId': usbDeviceId,
        'manufacturerName': manufacturerName,
      };

  factory PrinterDevice.fromJson(Map<String, dynamic> json) => PrinterDevice(
        name: json['name'] ?? '',
        address: json['address'] ?? '',
        connectionType: PrinterConnectionType.values.firstWhere(
          (e) => e.toString() == json['connectionType'],
          orElse: () => PrinterConnectionType.bluetooth,
        ),
        isDefault: json['isDefault'] ?? false,
        port: json['port'],
        vendorId: json['vendorId'],
        productId: json['productId'],
        usbDeviceId: json['usbDeviceId'],
        manufacturerName: json['manufacturerName'],
      );
}

enum PrinterConnectionType {
  bluetooth,
  usb,
  network,
  wifi,
  system,
}
