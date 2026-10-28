// lib/services/seat_service.dart
//
// 🖥️ تعدد الشاشات على الحاسبة الواحدة (مثل ASTER وأمثاله): شاشة ثانية بكيبورد
// وماوس خاصين بها على نفس الحاسبة، يعمل عليها محاسب ثانٍ وكأنهما حاسبتان على
// الشبكة نفسها — على قاعدة البيانات نفسها.
//
// • عدد الشاشات يحدده الترخيص (seats، موقَّع من سيرفرنا) — لا يزيد بالحيلة:
//   كل نسخة مفتوحة تحجز «مقعداً» في جدول app_seats داخل القاعدة، والزائد يُرفض.
// • برنامج ويندوز (main.cpp) يعطي كل نسخة رقم شاشتها (--seat=2) من أقفال النظام.
// • كل شاشة «طرف» مستقل: أقفال الفواتير والعملاء، الدخول، المسودات — منفصلة.
// • الأعمال الخلفية (المزامنة، الترحيل المحاسبي، النسخ، خدمة الشبكة) في الشاشة
//   الأولى وحدها، فلا تعمل مرتين.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'license_service.dart';

class SeatService {
  SeatService._();

  /// رقم الشاشة من برنامج ويندوز (قفل النظام) — يُستعمل عند إعادة التشغيل
  static int nativeSlot = 1;

  /// رقم الشاشة المحجوز فعلاً لهذه النسخة (1 = الأولى)
  static int seat = 1;

  /// عدد الشاشات المسموح في الترخيص
  static int allowed = 1;

  static bool get isPrimary => seat == 1;
  static bool get multiSeat => allowed > 1;

  /// يظهر في رسائل الأقفال: «أحمد — PC-01 (شاشة 2)»
  static String get label => seat <= 1 ? '' : 'شاشة $seat';

  static final String instanceId =
      List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static String _deviceId = '';
  static Timer? _beat;
  static Timer? _watch;
  static int? _dataVersion;

  /// يُستدعى أول main(): يقرأ --seat=N من برنامج ويندوز
  static void parseArgs(List<String> args) {
    for (final a in args) {
      if (a.startsWith('--seat=')) {
        final n = int.tryParse(a.substring(7));
        if (n != null && n >= 1 && n <= 8) nativeSlot = n;
      }
    }
    seat = nativeSlot;
  }

  /// وسائط إعادة التشغيل: النسخة الجديدة تنتظر قفل الشاشة نفسها
  static List<String> get relaunchArgs => ['--relaunch', if (nativeSlot > 1) '--seat=$nativeSlot'];

  /// مفتاح تخزين خاص بهذه الشاشة (المسودات والدخول): الأولى بلا تغيير (توافق قديم)
  static String key(String base) => seat <= 1 ? base : '${base}__seat$seat';

  /// برنامج ويندوز يقرأ العدد المسموح من هذا الملف قبل أن تبدأ Dart
  static Future<void> _writeAllowedForRunner() async {
    try {
      final base = Platform.environment['LOCALAPPDATA'];
      if (base == null || base.isEmpty) return;
      final dir = Directory('$base\\alnaser_logs');
      if (!await dir.exists()) await dir.create(recursive: true);
      await File('${dir.path}\\seats.txt').writeAsString('$allowed', flush: true);
    } catch (_) {}
  }

  static String get _exe {
    try {
      return Platform.resolvedExecutable.toLowerCase();
    } catch (_) {
      return '';
    }
  }

  static Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_seats (
        device_id TEXT NOT NULL,
        seat_no INTEGER NOT NULL,
        instance_id TEXT NOT NULL,
        exe_path TEXT,
        user_name TEXT,
        heartbeat_at INTEGER NOT NULL,
        PRIMARY KEY (device_id, seat_no)
      )''');
  }

  static const _staleMs = 75 * 1000;

  /// يحجز شاشة لهذه النسخة. null = نجح (أو لا حاجة)، وإلا رسالة المنع.
  static Future<String?> claim() async {
    if (kIsWeb || !Platform.isWindows) return null;
    final p = LicenseService().payload;
    if (p == null) return null; // غير مفعّل: شاشة التفعيل وحدها
    allowed = p.seats;
    await _writeAllowedForRunner();
    _deviceId = p.deviceId.isEmpty ? 'unknown' : p.deviceId;
    try {
      final db = await DatabaseService().database;
      await _ensureTable(db);
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.delete('app_seats', where: 'device_id = ? AND heartbeat_at < ?', whereArgs: [_deviceId, now - _staleMs]);
      final order = <int>{nativeSlot, for (var k = 1; k <= allowed; k++) k}.where((k) => k <= allowed);
      for (final k in order) {
        if (await _tryTake(db, k, now)) {
          seat = k;
          _startBeat();
          _startWatch();
          debugPrint('🖥️ [Seat] هذه الشاشة رقم $seat من $allowed');
          return null;
        }
      }
      return 'كل الشاشات المسموحة على هذه الحاسبة مستعملة الآن ($allowed).\n'
          'أغلق البرنامج على شاشة أخرى، أو اطلب زيادة عدد الشاشات في ترخيصك.';
    } catch (e) {
      // عطل في الجدول نفسه لا يمنع العمل (القفل وسيلة تنسيق لا بوّابة)
      debugPrint('⚠️ [Seat] تخطي حجز الشاشة: $e');
      return null;
    }
  }

  static Future<bool> _tryTake(Database db, int k, int now) async {
    final rows = await db.query('app_seats', where: 'device_id = ? AND seat_no = ?', whereArgs: [_deviceId, k], limit: 1);
    if (rows.isNotEmpty) {
      final r = rows.first;
      final mine = r['instance_id'] == instanceId;
      // نفس البرنامج ونفس رقم قفل ويندوز ⇒ صاحب الصف السابق خرج (القفل لا يُمسك
      // مرتين)، فنأخذه فوراً بلا انتظار (إعادة التشغيل لا تُرفض)
      final sameSlot = k == nativeSlot && '${r['exe_path'] ?? ''}' == _exe && _exe.isNotEmpty;
      if (!mine && !sameSlot) return false;
      await db.update('app_seats', _row(k, now), where: 'device_id = ? AND seat_no = ?', whereArgs: [_deviceId, k]);
      return true;
    }
    try {
      await db.insert('app_seats', _row(k, now));
      return true;
    } catch (_) {
      return false; // نسخة أخرى أخذته في اللحظة نفسها
    }
  }

  static Map<String, Object?> _row(int k, int now) => {
        'device_id': _deviceId,
        'seat_no': k,
        'instance_id': instanceId,
        'exe_path': _exe,
        'user_name': Platform.environment['USERNAME'] ?? '',
        'heartbeat_at': now,
      };

  static void _startBeat() {
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 25), (_) async {
      try {
        final db = await DatabaseService().database;
        final now = DateTime.now().millisecondsSinceEpoch;
        final n = await db.update('app_seats', {'heartbeat_at': now},
            where: 'device_id = ? AND seat_no = ? AND instance_id = ?', whereArgs: [_deviceId, seat, instanceId]);
        if (n == 0) await _tryTake(db, seat, now); // نوم الحاسبة طويلاً: نعيد الحجز
      } catch (_) {}
    });
  }

  /// 🔄 شاشة أخرى غيّرت القاعدة (سعر، مادة، عميل) ⇒ نُسقط الذاكرة المؤقتة هنا
  /// فلا يبيع هذا المحاسب بسعر قديم. PRAGMA data_version يتغيّر فقط بتعديل
  /// من اتصال آخر — لا يتغيّر بتعديلاتنا نحن.
  static void _startWatch() {
    if (allowed <= 1) return;
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final db = await DatabaseService().database;
        final r = await db.rawQuery('PRAGMA data_version');
        final v = r.isEmpty ? null : (r.first.values.first as num?)?.toInt();
        if (v == null) return;
        if (_dataVersion != null && v != _dataVersion) {
          final s = DatabaseService();
          s.invalidateProductsCache();
          s.invalidateCustomersCache();
        }
        _dataVersion = v;
      } catch (_) {}
    });
  }

  /// قبل الخروج (أفضل جهد؛ وإلا ينتهي الحجز وحده بعد 75 ثانية)
  static Future<void> release() async {
    _beat?.cancel();
    _watch?.cancel();
    if (_deviceId.isEmpty) return;
    try {
      final db = await DatabaseService().database;
      await db.delete('app_seats',
          where: 'device_id = ? AND seat_no = ? AND instance_id = ?', whereArgs: [_deviceId, seat, instanceId]);
    } catch (_) {}
  }
}
