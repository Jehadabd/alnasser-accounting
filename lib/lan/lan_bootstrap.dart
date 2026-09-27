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
import 'lan_settings.dart';
import 'lan_server.dart';
import 'network_settings_screen.dart';

class LanRuntime {
  LanRuntime._();

  static LanDatabaseServer? server;
  static LanClientConnection? client;
  static Timer? _postingTimer;

  /// نتيجة الإقلاع: null = نجح، وإلا رسالة خطأ الاتصال (للطرفية).
  static Future<String?> beforeDatabase() async {
    final settings = await LanSettings.load();
    AppNetworkMode.current = settings;
    if (!settings.isClient) return null;

    if (settings.host.isEmpty || settings.secret.isEmpty) {
      return 'لم يُحدَّد عنوان السيرفر أو رمز الربط';
    }
    final conn = LanClientConnection(
      host: settings.host,
      port: settings.port,
      secret: settings.secret,
      clientName: settings.clientName.isEmpty ? Platform.localHostname : settings.clientName,
    );
    try {
      await conn.connect();
    } on LanConnectionException catch (e) {
      return e.message;
    } catch (e) {
      return 'تعذّر الاتصال بالسيرفر: $e';
    }
    client = conn;
    databaseFactory = createLanDatabaseFactory(conn);
    return null;
  }

  static Future<void> afterDatabase() async {
    final s = AppNetworkMode.current;
    if (s.isServer) {
      try {
        final path = await DatabaseConfig.getDatabasePath();
        // القاعدة يجب أن تكون مفتوحة قبل أن تتصل أي طرفية
        await DatabaseService().database;
        server = LanDatabaseServer(
          databasePath: path,
          secret: s.secret,
          serverName: s.serverName.isEmpty ? Platform.localHostname : s.serverName,
          port: s.port,
        );
        await server!.start();
      } catch (e) {
        // ignore: avoid_print
        print('⚠️ تعذّر تشغيل خادم الشبكة: $e');
      }
    }
    if (AppNetworkMode.ownsDatabase) {
      _postingTimer?.cancel();
      // أول ترحيل بعد دقيقة من الإقلاع (لا نزاحم الشاشة الأولى)، ثم كل دقيقتين
      Future<void>.delayed(const Duration(minutes: 1), _post);
      _postingTimer = Timer.periodic(const Duration(minutes: 2), (_) => _post());
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
class LanConnectionErrorApp extends StatelessWidget {
  const LanConnectionErrorApp({super.key, required this.message});
  final String message;

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
