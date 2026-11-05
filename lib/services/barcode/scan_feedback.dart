// lib/services/barcode/scan_feedback.dart
//
// 🔔 تنبيه المسح: اهتزاز ونقرة عند النجاح، وصوت تنبيه عند الفشل (حتى يعرف الكاشير دون
// النظر للشاشة). يُطفأ من إعدادات الباركود.

import 'package:flutter/services.dart';

import 'scan_settings.dart';

class ScanFeedback {
  ScanFeedback._();

  static void ok() {
    if (!ScanSettings.current.sound) return;
    try {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  static void fail() {
    if (!ScanSettings.current.sound) return;
    try {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }
}
