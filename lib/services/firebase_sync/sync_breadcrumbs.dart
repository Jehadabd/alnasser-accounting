// lib/services/firebase_sync/sync_breadcrumbs.dart
//
// 🧭 آثار تشخيصية للمزامنة: سطر في ملف لكل خطوة، يُكتب ويُفرَّغ فوراً حتى لو
// انهار البرنامج بعده مباشرة. يعمل فقط إن وُجد الملف:
//   سطح المكتب\alnaser_stress_reports\sync_debug.flag
// فلا أثر له عند المستخدم العادي.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

class SyncCrumb {
  SyncCrumb._();

  static bool? _enabled;
  static RandomAccessFile? _out;

  static String? _dir() {
    if (kIsWeb) return null;
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return null;
    return '$home${Platform.pathSeparator}Desktop${Platform.pathSeparator}alnaser_stress_reports';
  }

  static void mark(String s) {
    try {
      if (_enabled == false) return;
      if (_enabled == null) {
        final d = _dir();
        _enabled = d != null && File('$d${Platform.pathSeparator}sync_debug.flag').existsSync();
        if (_enabled != true) return;
        _out = File('$d${Platform.pathSeparator}sync_breadcrumbs.txt').openSync(mode: FileMode.append);
        _out!.writeStringSync('\n===== ${DateTime.now().toIso8601String()} بدء =====\n');
      }
      _out!.writeStringSync('${DateTime.now().toIso8601String().substring(11, 23)} $s\n');
      _out!.flushSync();
    } catch (_) {}
  }
}
