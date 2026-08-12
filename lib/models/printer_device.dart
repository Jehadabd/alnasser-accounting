// models/printer_device.dart
class PrinterDevice {
  final String name;
  final String address;
  final PrinterConnectionType connectionType;
  final bool isDefault;
  final int? port;

  PrinterDevice({
    required this.name,
    required this.address,
    required this.connectionType,
    this.isDefault = false,
    this.port,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'connectionType': connectionType.toString(),
        'isDefault': isDefault,
        'port': port,
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
      );
}

enum PrinterConnectionType {
  bluetooth,
  usb,
  network,
  wifi,
  system,
}
