// lib/lan/lan_settings.dart
//
// وضع تشغيل البرنامج على الشبكة المحلية:
//   • standalone — جهاز واحد (كما هو الآن).
//   • server     — هذه الحاسبة تحمل قاعدة البيانات وتخدم الطرفيات.
//   • client     — طرفية: تقرأ وتكتب في قاعدة السيرفر عبر الشبكة.
//
// يُقرأ قبل فتح قاعدة البيانات، لذلك يُحفظ في SharedPreferences لا في القاعدة.

import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'lan_codec.dart';

enum LanMode { standalone, server, client }

class LanSettings {
  const LanSettings({
    this.mode = LanMode.standalone,
    this.host = '',
    this.port = lanDefaultPort,
    this.secret = '',
    this.serverName = '',
    this.clientName = '',
  });

  final LanMode mode;

  /// عنوان حاسبة السيرفر (للطرفية فقط).
  final String host;
  final int port;

  /// رمز الربط: يُولَّد على السيرفر ويُكتب في كل طرفية.
  final String secret;

  /// اسم السيرفر كما يظهر للطرفيات (مثلاً: «الفرع الرئيسي»).
  final String serverName;

  /// اسم هذه الطرفية كما يظهر في شاشة السيرفر (مثلاً: «كاشير 2»).
  final String clientName;

  bool get isServer => mode == LanMode.server;
  bool get isClient => mode == LanMode.client;

  static const _kMode = 'lan_mode';
  static const _kHost = 'lan_host';
  static const _kPort = 'lan_port';
  static const _kSecret = 'lan_secret';
  static const _kServerName = 'lan_server_name';
  static const _kClientName = 'lan_client_name';

  static Future<LanSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_kMode) ?? LanMode.standalone.name;
    return LanSettings(
      mode: LanMode.values.firstWhere((m) => m.name == modeName,
          orElse: () => LanMode.standalone),
      host: prefs.getString(_kHost) ?? '',
      port: prefs.getInt(_kPort) ?? lanDefaultPort,
      secret: prefs.getString(_kSecret) ?? '',
      serverName: prefs.getString(_kServerName) ?? '',
      clientName: prefs.getString(_kClientName) ?? Platform.localHostname,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, mode.name);
    await prefs.setString(_kHost, host);
    await prefs.setInt(_kPort, port);
    await prefs.setString(_kSecret, secret);
    await prefs.setString(_kServerName, serverName);
    await prefs.setString(_kClientName, clientName);
  }

  LanSettings copyWith({
    LanMode? mode,
    String? host,
    int? port,
    String? secret,
    String? serverName,
    String? clientName,
  }) =>
      LanSettings(
        mode: mode ?? this.mode,
        host: host ?? this.host,
        port: port ?? this.port,
        secret: secret ?? this.secret,
        serverName: serverName ?? this.serverName,
        clientName: clientName ?? this.clientName,
      );

  /// رمز ربط جديد: 12 حرفاً سهلة القراءة (بدون 0/O و1/I).
  static String generateSecret() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final s = List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
    return '${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8)}';
  }
}

/// الحالة الحالية للبرنامج — تُضبط مرة واحدة في main() قبل فتح القاعدة.
///
/// تُستخدم كحارس في الأماكن التي يجب ألا تعمل على الطرفية:
/// المزامنة مع Firebase، النسخ الاحتياطي، الهجرات، VACUUM، فحوص السلامة الثقيلة.
class AppNetworkMode {
  AppNetworkMode._();
  static LanSettings current = const LanSettings();

  static bool get isClient => current.isClient;
  static bool get isServer => current.isServer;

  /// هل تملك هذه الحاسبة ملف قاعدة البيانات؟ (مستقل أو سيرفر)
  static bool get ownsDatabase => !current.isClient;
}
