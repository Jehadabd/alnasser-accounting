// test/lan/lan_license_test.dart
//
// حاسبة السيرفر ترفض الطرفية التي فُكّ ربطها من الترخيص (حتى برمز ربط صحيح)،
// وتقطع المتصلة فوراً حين تتغير قائمة الأجهزة.
// التشغيل:  flutter test test/lan/lan_license_test.dart

import 'dart:async';
import 'dart:io';

import 'package:alnaser/lan/lan_client.dart';
import 'package:alnaser/lan/lan_codec.dart';
import 'package:alnaser/lan/lan_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  const secret = 'TEST-SECRET-77';
  late Directory tmp;
  late Database serverDb;
  late LanDatabaseServer server;
  // الحكم على كل ترخيص (يتغير أثناء الاختبار كما لو فُكّ ربط جهاز)
  final verdicts = <String, String?>{};

  setUp(() async {
    verdicts
      ..clear()
      ..addAll({'good': null, 'revoked': 'revoked', 'stale': 'stale', 'foreign': 'foreign'});
    tmp = await Directory.systemTemp.createTemp('lan_lic_');
    final dbPath = p.join(tmp.path, 'server.db');
    serverDb = await databaseFactoryFfi.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)'),
        ));
    server = LanDatabaseServer(
      databasePath: dbPath,
      secret: secret,
      port: 0,
      enableDiscovery: false,
      checkLicense: (t) async => verdicts.containsKey(t) ? verdicts[t] : 'invalid',
      log: (_) {},
    );
    await server.start();
  });

  tearDown(() async {
    LanClientConnection.onLicenseRejected = null;
    await server.stop();
    await serverDb.close();
    await tmp.delete(recursive: true);
  });

  LanClientConnection conn(String token, {String key = ''}) => LanClientConnection(
        host: '127.0.0.1',
        port: server.boundPort,
        secret: key,
        licenseToken: token,
        clientName: 'طرفية $token',
      );

  test('ترخيص نشط من الحساب نفسه يكفي بلا رمز ربط', () async {
    final c = conn('good');
    await c.connect();
    expect(c.state, LanLinkState.connected);
    await c.close();
  });

  test('جهاز مفكوك يُرفض حتى برمز ربط صحيح، برسالة واضحة', () async {
    final codes = <int>[];
    LanClientConnection.onLicenseRejected = codes.add;
    final c = conn('revoked', key: secret);
    await expectLater(
        c.connect(),
        throwsA(isA<LanConnectionException>()
            .having((e) => e.message, 'message', contains('فُكّ ربط هذا الجهاز'))));
    expect(codes, [lanCloseRevoked]);
  });

  test('جهاز لم يتحقق منذ مدة طويلة يُرفض', () async {
    await expectLater(conn('stale', key: secret).connect(), throwsA(isA<LanConnectionException>()));
  });

  test('ترخيص حساب آخر: يلزمه رمز الربط', () async {
    await expectLater(conn('foreign').connect(), throwsA(isA<LanConnectionException>()));
    final c = conn('foreign', key: secret);
    await c.connect();
    expect(c.state, LanLinkState.connected);
    await c.close();
  });

  test('فك ربط طرفية متصلة ⇒ تُقطع فوراً', () async {
    final codes = <int>[];
    LanClientConnection.onLicenseRejected = codes.add;
    verdicts['flip'] = null;
    final c = conn('flip');
    await c.connect();
    expect(server.clients.length, 1);
    final dropped = c.stateStream.firstWhere((s) => s == LanLinkState.disconnected);
    verdicts['flip'] = 'revoked';
    await server.recheckLicenses();
    await dropped.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.clients, isEmpty);
    expect(codes, [lanCloseRevoked]);
  });
}
