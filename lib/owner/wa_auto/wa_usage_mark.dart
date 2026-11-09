// lib/owner/wa_auto/wa_usage_mark.dart
//
// 🔖 علامة دائمة: «خدمة الإرسال الآلي عبر واتساب شُغّلت على هذا الجهاز».
//
// تُكتب عند أول تفعيل أو تجربة أو ربط أو إرسال — بأي طريقة (WhatsApp Desktop أو
// الخادم) — ولا يوجد في البرنامج ما يمحوها: إطفاء الخدمة لا يزيلها. الغرض أن يرى
// صاحب البرنامج (أو الدعم) أن الخدمة استُعملت على هذا الجهاز إن قيل لاحقاً
// «حُظر رقمي ولم أشغّلها».
//
// تُحفظ في أربعة أماكن مستقلة، وعند كل قراءة تُدمج وتُعاد إلى كلها:
//   الإعدادات، التخزين الآمن، جدول في قاعدة البيانات، وملف في مجلد البرنامج.
// فلا يمحوها إطفاء الخدمة ولا استعادة نسخة قديمة ولا «بدء جديد». يمحوها فقط من
// يحذف بيانات البرنامج كلها يدوياً من الأماكن الأربعة — هي دليل، لا قفل.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/database_service.dart';

class WaUsage {
  WaUsage({
    required this.first,
    required this.last,
    required this.firstMode,
    required this.firstUser,
    required this.modes,
    required this.events,
    required this.sends,
  });

  final DateTime first, last;
  final String firstMode, firstUser;
  final Set<String> modes;
  final int events, sends;

  static String modeName(String m) => switch (m) {
        'server' => 'الخادم',
        'desktop' => 'WhatsApp Desktop',
        _ => m,
      };

  String get modesText => modes.map(modeName).join(' و');

  String summary() {
    final f = DateFormat('yyyy/MM/dd HH:mm', 'en');
    return 'شُغّلت خدمة الإرسال الآلي عبر واتساب على هذا الجهاز أول مرة في ${f.format(first)} '
        '(${modeName(firstMode)}${firstUser.isEmpty ? '' : ' — المستخدم $firstUser'}). '
        'آخر استعمال ${f.format(last)}، الطرق: $modesText، رسائل أُرسلت: $sends.';
  }

  Map<String, dynamic> toJson() => {
        'first': first.toIso8601String(),
        'last': last.toIso8601String(),
        'firstMode': firstMode,
        'firstUser': firstUser,
        'modes': modes.toList()..sort(),
        'events': events,
        'sends': sends,
      };

  static WaUsage? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return WaUsage(
        first: DateTime.parse(j['first'] as String),
        last: DateTime.parse(j['last'] as String),
        firstMode: '${j['firstMode'] ?? ''}',
        firstUser: '${j['firstUser'] ?? ''}',
        modes: {for (final m in (j['modes'] as List? ?? const [])) '$m'},
        events: (j['events'] as num?)?.toInt() ?? 0,
        sends: (j['sends'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// الأقدم أولاً، الأحدث آخراً، والأكبر من العدّادات — فلا يُنقص الدمج شيئاً.
  static WaUsage? merge(Iterable<WaUsage?> all) {
    WaUsage? out;
    for (final u in all) {
      if (u == null) continue;
      if (out == null) {
        out = u;
        continue;
      }
      final older = u.first.isBefore(out.first) ? u : out;
      out = WaUsage(
        first: older.first,
        last: u.last.isAfter(out.last) ? u.last : out.last,
        firstMode: older.firstMode,
        firstUser: older.firstUser,
        modes: {...out.modes, ...u.modes},
        events: u.events > out.events ? u.events : out.events,
        sends: u.sends > out.sends ? u.sends : out.sends,
      );
    }
    return out;
  }
}

class WaUsageMark {
  WaUsageMark._();

  static const _key = 'wa_usage_mark_v1';
  static const _secure = FlutterSecureStorage();

  static Future<File?> _file() async {
    try {
      final d = await getApplicationSupportDirectory();
      return File('${d.path}${Platform.pathSeparator}.wa_usage_mark');
    } catch (_) {
      return null;
    }
  }

  static Future<List<String?>> _readAll() async {
    final out = <String?>[];
    try {
      out.add((await SharedPreferences.getInstance()).getString(_key));
    } catch (_) {}
    try {
      out.add(await _secure.read(key: _key));
    } catch (_) {}
    try {
      final db = await DatabaseService().database;
      await _ensureTable();
      final r = await db.query('wa_usage_mark', columns: ['data'], where: 'id = 1');
      if (r.isNotEmpty) out.add(r.first['data'] as String?);
    } catch (_) {}
    try {
      final f = await _file();
      if (f != null && await f.exists()) out.add(await f.readAsString());
    } catch (_) {}
    return out;
  }

  static Future<void> _ensureTable() async {
    final db = await DatabaseService().database;
    await db.execute('CREATE TABLE IF NOT EXISTS wa_usage_mark (id INTEGER PRIMARY KEY, data TEXT NOT NULL)');
  }

  static Future<void> _writeAll(WaUsage u) async {
    final raw = jsonEncode(u.toJson());
    try {
      await (await SharedPreferences.getInstance()).setString(_key, raw);
    } catch (_) {}
    try {
      await _secure.write(key: _key, value: raw);
    } catch (_) {}
    try {
      await _ensureTable();
      final db = await DatabaseService().database;
      await db.execute('INSERT OR REPLACE INTO wa_usage_mark (id, data) VALUES (1, ?)', [raw]);
    } catch (_) {}
    try {
      final f = await _file();
      if (f != null) await f.writeAsString(raw, flush: true);
    } catch (_) {}
  }

  /// العلامة إن وُجدت في أي مكان — وتُعاد إلى الأماكن التي فُقدت منها.
  static Future<WaUsage?> read() async {
    final all = await _readAll();
    final merged = WaUsage.merge(all.map(WaUsage.fromJson));
    if (merged != null) {
      final raw = jsonEncode(merged.toJson());
      if (all.length < 4 || all.any((x) => x != raw)) await _writeAll(merged);
    }
    return merged;
  }

  /// يسجّل استعمالاً (تفعيل، تجربة، ربط، إرسال). [mode] = 'desktop' أو 'server'.
  static Future<void> record(String mode, {int sends = 0}) async {
    try {
      final now = DateTime.now();
      final old = await read();
      String user = '';
      try {
        user = AuthService().currentUser?.username ?? '';
      } catch (_) {}
      final next = old == null
          ? WaUsage(
              first: now, last: now, firstMode: mode, firstUser: user, modes: {mode}, events: 1, sends: sends)
          : WaUsage(
              first: old.first,
              last: now,
              firstMode: old.firstMode,
              firstUser: old.firstUser,
              modes: {...old.modes, mode},
              events: old.events + 1,
              sends: old.sends + sends,
            );
      await _writeAll(next);
    } catch (_) {
      // علامة إضافية — لا تُفشل الإرسال نفسه
    }
  }
}
