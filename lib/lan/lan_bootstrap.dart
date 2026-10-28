// lib/lan/lan_bootstrap.dart
//
// 🚀 تشغيل البرنامج حسب وضعه على الشبكة. يُستدعى من main():
//
//   1) beforeDatabase(): قبل أي فتح لقاعدة البيانات.
//        طرفية ⇒ اتصال بالسيرفر ثم databaseFactory = المصنع البعيد.
//   2) afterDatabase(): بعد أن تفتح القاعدة وتكتمل هجراتها.
//        سيرفر ⇒ تشغيل خادم الشبكة.
//        مستقل أو سيرفر ⇒ الترحيل المحاسبي التلقائي كل دقيقتين.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactory;

import '../accounting/posting_engine.dart';
import '../services/database/core/database_config.dart';
import '../services/database_service.dart';
import 'lan_client.dart';
import 'lan_codec.dart' show LanConnectionException, lanDefaultPort, lanCloseRevoked;
import 'lan_settings.dart';
import 'lan_server.dart';
import 'network_settings_screen.dart';
import 'windows_autostart.dart';
import '../services/license_service.dart';
import '../services/seat_service.dart';

class LanRuntime {
  LanRuntime._();

  static LanDatabaseServer? server;
  static LanClientConnection? client;
  static Timer? _postingTimer;

  /// نتيجة الإقلاع: null = نجح، وإلا رسالة خطأ الاتصال (للطرفية).
  static Future<String?> beforeDatabase() async {
    var settings = await LanSettings.load();
    AppNetworkMode.current = settings;
    if (!settings.isClient) return null;

    // 🖧 «طرفية» تشير إلى هذه الحاسبة نفسها (اسمها أو أحد عناوينها) خطأ مؤكد:
    // هذه الحاسبة هي السيرفر. تصير سيرفراً وتفتح مباشرة بلا رسالة «تعذّر الاتصال».
    if (Platform.isWindows && await pointsToThisPc(settings)) {
      settings = settings.copyWith(mode: LanMode.server);
      await settings.save();
      AppNetworkMode.current = settings;
      // ignore: avoid_print
      print('🖧 إعداد «طرفية» كان يشير إلى هذه الحاسبة نفسها — صارت سيرفراً');
      return null;
    }
    LanClientConnection.onLicenseRejected = (code) => unawaited(_onLicenseRejected(code));

    // ترخيص هذا الجهاز يكفي بدل رمز الربط (أجهزة الترخيص نفسه)
    await LicenseService.init();
    final token = LicenseService().currentToken ?? '';
    // 🖧 جهاز إضافي ينتظر حاسبة السيرفر (لم يجدها عند إضافته): يبحث عنها عند كل تشغيل
    if (settings.host.isEmpty && token.isNotEmpty) {
      final joined = await autoJoin();
      if (joined != null) {
        settings = joined;
        AppNetworkMode.current = joined;
      } else {
        return 'لم أجد حاسبة السيرفر على هذه الشبكة بعد.';
      }
    }
    if (settings.host.isEmpty || (settings.secret.isEmpty && token.isEmpty)) {
      return 'لم يُحدَّد عنوان السيرفر أو رمز الربط';
    }
    final name = settings.clientName.isEmpty ? Platform.localHostname : settings.clientName;
    LanClientConnection conn = LanClientConnection(
      host: settings.host,
      port: settings.port,
      secret: settings.secret,
      clientName: name,
      licenseToken: token,
    );
    try {
      await conn.connect();
    } catch (e) {
      // 🔎 ربما تغيّر عنوان حاسبة السيرفر (الراوتر يوزّع العناوين من جديد بعد إطفائه):
      // نبحث عنها في الشبكة ونجرّب برمز الربط نفسه، ونحفظ العنوان الجديد إن نجح.
      final moved = await _findMovedServer(settings, name);
      if (moved == null) {
        return e is LanConnectionException ? e.message : 'تعذّر الاتصال بالسيرفر: $e';
      }
      conn = moved;
    }
    client = conn;
    databaseFactory = createLanDatabaseFactory(conn);
    // حاسبة السيرفر تتحقق من ترخيص هذه الطرفية (قائمة الأجهزة النشطة)
    LicenseService.gatedByLanServer = true;
    return null;
  }

  /// السيرفر رفض ترخيص هذه الطرفية: نسأل سيرفر الترخيص بأنفسنا. إن أكّد فك
  /// الربط يُمسح الترخيص وتظهر شاشة التفعيل. لا نمسحه بكلمة حاسبة السيرفر وحدها.
  static bool _checkingRevoked = false;
  static Future<void> _onLicenseRejected(int code) async {
    if (code != lanCloseRevoked || _checkingRevoked) return;
    _checkingRevoked = true;
    try {
      final lic = LicenseService();
      await lic.refreshNow();
      if (!lic.isLicenseActivated()) LicenseService.onLocked?.call();
    } catch (_) {
    } finally {
      _checkingRevoked = false;
    }
  }

  /// هل يشير إعداد الطرفية إلى هذه الحاسبة نفسها؟
  static Future<bool> pointsToThisPc(LanSettings s) async {
    try {
      final me = Platform.localHostname.trim().toLowerCase();
      if (me.isNotEmpty && me != 'localhost' && s.serverName.trim().toLowerCase() == me) return true;
      final h = s.host.trim();
      if (h.isEmpty) return false;
      if (h == 'localhost' || h.startsWith('127.')) return true;
      for (final ni in await NetworkInterface.list(includeLoopback: true)) {
        for (final a in ni.addresses) {
          if (a.address == h) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// إعادة تشغيل البرنامج (ويندوز: يفتح نسخة جديدة ثم يغلق هذه؛ أندرويد: يغلق فقط)
  static Future<void> relaunch() async {
    await SeatService.release();
    try {
      if (Platform.isWindows) {
        await Process.start(Platform.resolvedExecutable, SeatService.relaunchArgs, mode: ProcessStartMode.detached);
      }
    } catch (_) {}
    exit(0);
  }

  static Future<LanClientConnection?> _findMovedServer(LanSettings s, String clientName) async {
    try {
      final found = await discoverLanServers(wait: const Duration(seconds: 3));
      // السيرفر الذي اخترناه سابقاً (بالاسم) أولاً، ثم البقية
      found.sort((a, b) => (b['name'] == s.serverName ? 1 : 0) - (a['name'] == s.serverName ? 1 : 0));
      for (final f in found) {
        final host = '${f['host']}';
        final port = (f['port'] as num?)?.toInt() ?? s.port;
        if (host == s.host && port == s.port) continue;
        final c = LanClientConnection(
            host: host, port: port, secret: s.secret, clientName: clientName,
            licenseToken: LicenseService().currentToken ?? '');
        try {
          await c.connect();
          await s.copyWith(host: host, port: port).save();
          AppNetworkMode.current = s.copyWith(host: host, port: port);
          // ignore: avoid_print
          print('🖧 السيرفر انتقل إلى $host:$port — حُفظ العنوان الجديد');
          return c;
        } catch (_) {
          try {
            await c.close();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  /// 🔁 فحص دوري من شاشة «تعذّر الاتصال»: هل صارت حاسبة السيرفر متاحة؟
  /// (العنوان المحفوظ، ثم البحث في الشبكة — ويُحفظ العنوان الجديد إن تغيّر)
  static Future<bool> probeServer() async {
    try {
      final s = await LanSettings.load();
      if (!s.isClient) return true;
      final token = LicenseService().currentToken ?? '';
      final name = s.clientName.isEmpty ? Platform.localHostname : s.clientName;
      if (s.host.isEmpty) return (await autoJoin()) != null;
      final c = LanClientConnection(host: s.host, port: s.port, secret: s.secret, clientName: name, licenseToken: token);
      try {
        await c.connect();
        try {
          await c.close();
        } catch (_) {}
        return true;
      } catch (_) {
        try {
          await c.close();
        } catch (_) {}
      }
      final moved = await _findMovedServer(s, name);
      if (moved != null) {
        try {
          await moved.close();
        } catch (_) {}
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// يبقى الجهاز «طرفية تنتظر السيرفر»: يبحث عنه عند كل تشغيل ويتصل وحده.
  static Future<void> markPendingJoin() async {
    final cur = await LanSettings.load();
    await cur
        .copyWith(mode: LanMode.client, host: '', secret: '', clientName: cur.clientName.isEmpty ? Platform.localHostname : cur.clientName)
        .save();
  }

  /// 🖧 بعد إضافة جهاز برمز: يبحث عن حاسبة السيرفر في الشبكة ويرتبط بها بترخيص
  /// هذا الجهاز (بلا رمز ربط). يُرجع الإعداد المحفوظ، أو null إن لم يجد سيرفراً.
  static Future<LanSettings?> autoJoin() async {
    final token = LicenseService().currentToken ?? '';
    if (token.isEmpty) return null;
    final name = Platform.localHostname;
    List<Map<String, Object?>> found = const [];
    for (var i = 0; i < 2 && found.isEmpty; i++) {
      found = await discoverLanServers(wait: const Duration(seconds: 3));
    }
    for (final f in found) {
      final host = '${f['host']}';
      final port = (f['port'] as num?)?.toInt() ?? lanDefaultPort;
      final c = LanClientConnection(host: host, port: port, secret: '', clientName: name, licenseToken: token);
      try {
        await c.connect();
        try {
          await c.close();
        } catch (_) {}
        final cur = await LanSettings.load();
        final next = cur.copyWith(
          mode: LanMode.client,
          host: host,
          port: port,
          secret: '',
          serverName: '${f['name'] ?? ''}',
          clientName: cur.clientName.isEmpty ? name : cur.clientName,
        );
        await next.save();
        return next;
      } catch (_) {
        try {
          await c.close();
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<void> afterDatabase() async {
    final s = AppNetworkMode.current;
    // ▶️ حاسبة السيرفر تفتح البرنامج وحدها عند تشغيل ويندوز (ما لم يُطفأ الخيار)
    WindowsAutostart.sync(s.isServer && s.autoStart);
    if (s.isServer) await _startServer(s);
    if (AppNetworkMode.ownsDatabase) {
      _postingTimer?.cancel();
      // أول ترحيل بعد دقيقة من الإقلاع (لا نزاحم الشاشة الأولى)، ثم كل دقيقتين
      Future<void>.delayed(const Duration(minutes: 1), _post);
      _postingTimer = Timer.periodic(const Duration(minutes: 2), (_) => _post());
    }
  }

  static Future<bool> _startServer(LanSettings s) async {
    if (server != null) return true;
    try {
      final path = await DatabaseConfig.getDatabasePath();
      // القاعدة يجب أن تكون مفتوحة قبل أن تتصل أي طرفية
      await DatabaseService().database;
      server = LanDatabaseServer(
        databasePath: path,
        secret: s.secret,
        serverName: s.serverName.isEmpty ? Platform.localHostname : s.serverName,
        port: s.port,
        checkLicense: LicenseService.checkPeerToken,
      );
      await server!.start();
      // 🔐 قائمة أجهزة الترخيص النشطة: كل 30 دقيقة وفوراً بعد فك ربط جهاز —
      // أي طرفية فُكّ ربطها تُقطع وتُرفض حتى لو عرفت رمز الربط
      LicenseService.onPeersChanged = () => unawaited(server?.recheckLicenses());
      LicenseService.startPeerWatch();
      return true;
    } catch (e) {
      server = null;
      // ignore: avoid_print
      print('⚠️ تعذّر تشغيل خادم الشبكة: $e');
      return false;
    }
  }

  /// 🖧 الجهاز الرئيسي يضيف جهازاً: يصير «حاسبة السيرفر» (إن كان مستقلاً) ويبدأ
  /// خدمة الطرفيات الآن — فالجهاز الجديد على نفس الشبكة يجده ويرتبط به وحده بعد
  /// إدخال الرمز، بلا اختيار «سيرفر/طرفية» يدوياً. يبقى سيرفراً بعد إعادة التشغيل.
  /// ويندوز فقط (حاسبة المحل)؛ الطرفية لا تُحوَّل.
  static Future<bool> ensureServerForPairing() async {
    try {
      if (!Platform.isWindows || !SeatService.isPrimary) return false;
      var s = await LanSettings.load();
      if (s.isClient) return false;
      if (!s.isServer) {
        s = s.copyWith(
          mode: LanMode.server,
          secret: s.secret.isEmpty ? LanSettings.generateSecret() : s.secret,
          serverName: s.serverName.isEmpty ? Platform.localHostname : s.serverName,
        );
        await s.save();
        AppNetworkMode.current = s;
        WindowsAutostart.sync(s.autoStart);
        // ignore: avoid_print
        print('🖧 الجهاز الرئيسي صار حاسبة السيرفر (لإضافة أجهزة على الشبكة)');
      }
      return await _startServer(s);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _post() async {
    try {
      await PostingEngine().syncAll();
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ الترحيل التلقائي: $e');
    }
  }
}

/// تطبيق صغير يظهر عندما تفشل الطرفية في الاتصال بالسيرفر عند الإقلاع.
/// 🔁 مثل الواي فاي: يبقى يحاول الاتصال بحاسبة السيرفر المحفوظة كل بضع ثوانٍ،
/// ويفتح البرنامج وحده حين تظهر (حتى تربطه بسيرفر آخر من «إعداد الشبكة»).
class LanConnectionErrorApp extends StatefulWidget {
  const LanConnectionErrorApp({super.key, required this.message});
  final String message;

  @override
  State<LanConnectionErrorApp> createState() => _LanConnectionErrorAppState();
}

class _LanConnectionErrorAppState extends State<LanConnectionErrorApp> {
  Timer? _timer;
  bool _probing = false;
  bool _found = false;
  int _tries = 0;

  String get message => widget.message;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _probe());
    Future<void>.delayed(const Duration(seconds: 2), _probe);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _probe() async {
    if (_probing || _found || !mounted) return;
    setState(() => _probing = true);
    final ok = await LanRuntime.probeServer();
    if (!mounted) return;
    setState(() {
      _probing = false;
      _tries++;
      _found = ok;
    });
    if (ok) {
      _timer?.cancel();
      // ويندوز: يفتح من جديد متصلاً. أندرويد لا يعيد تشغيل نفسه: يطلب من المستخدم فتحه
      if (Platform.isWindows) await LanRuntime.relaunch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF020F2B),
          body: Center(
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lan_outlined, size: 56, color: Color(0xFFB91C1C)),
                    const SizedBox(height: 12),
                    const Text('تعذّر الاتصال بحاسبة السيرفر',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    if (_found)
                      Text(
                        Platform.isWindows
                            ? '✅ وُجدت حاسبة السيرفر — يُفتح البرنامج الآن…'
                            : '✅ وُجدت حاسبة السيرفر — أغلق البرنامج وافتحه من جديد',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold),
                      )
                    else
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                        Text(_probing ? 'يبحث عن حاسبة السيرفر…' : 'يحاول تلقائياً كل 8 ثوانٍ (محاولة $_tries)',
                            style: const TextStyle(color: Colors.black54)),
                      ]),
                    const SizedBox(height: 8),
                    const Text(
                      'تأكد أن برنامج السيرفر مفتوح، وأن الجهازين على نفس الشبكة، ثم أعد تشغيل البرنامج.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      icon: const Icon(Icons.settings_ethernet),
                      label: const Text('إعداد الشبكة'),
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const NetworkSettingsScreen())),
                    ),
                    if (Platform.isWindows) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                        onPressed: LanRuntime.relaunch,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.dns_outlined),
                        label: const Text('هذه الحاسبة هي السيرفر — شغّلها سيرفراً'),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('تشغيل هذه الحاسبة سيرفراً؟'),
                              content: const Text(
                                  'اختر هذا فقط إن كانت قاعدة البيانات على هذه الحاسبة، وكانت الأجهزة الأخرى تتصل بها.\n'
                                  'سيُعاد تشغيل البرنامج، ومن الآن يعمل سيرفراً تلقائياً عند كل تشغيل.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، سيرفر')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          final cur = await LanSettings.load();
                          await cur.copyWith(mode: LanMode.server).save();
                          await LanRuntime.relaunch();
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => exit(0),
                      child: const Text('إغلاق البرنامج'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
