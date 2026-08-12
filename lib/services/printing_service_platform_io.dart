// services/printing_service_platform_io.dart
import 'dart:io';
import 'package:alnaser/services/printing_service.dart';

import 'package:alnaser/services/printing_service_android.dart';
import 'package:alnaser/services/printing_service_windows.dart';

PrintingService getPlatformPrintingService() {
  if (Platform.isAndroid) {
    return PrintingServiceAndroid();
  } else if (Platform.isWindows) {
    return PrintingServiceWindows();
  } else {
    throw UnsupportedError('Unsupported platform for PrintingService');
  }
} 