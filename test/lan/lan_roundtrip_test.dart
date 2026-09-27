// test/lan/lan_roundtrip_test.dart
//
// اختبارات طبقة الشبكة المحلية: سيرفر حقيقي على 127.0.0.1 + طرفيات حقيقية.
// التشغيل:  flutter test test/lan/lan_roundtrip_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:alnaser/lan/lan_client.dart';
import 'package:alnaser/lan/lan_codec.dart';
import 'package:alnaser/lan/lan_server.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late String dbPath;
  late Database serverDb; // ما يفتحه برنامج السيرفر نفسه
  late LanDatabaseServer server;
  const secret = 'test-secret-1234';

  Future<(LanClientConnection, Database)> newClient(String name) async {
    final conn = LanClientConnection(
      host: '127.0.0.1',
      port: server.boundPort,
      secret: secret,
      clientName: name,
      requestTimeout: const Duration(seconds: 20),
    );
    await conn.connect();
    final factory = createLanDatabaseFactory(conn);
    // المسار الذي ترسله الطرفية يُتجاهل — السيرفر يستبدله بملفه.
    final db = await factory.openDatabase('ignored_on_client.db');
    return (conn, db);
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lan_test_');
    dbPath = p.join(tmp.path, 'server.db');
    serverDb = await databaseFactoryFfi.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
                'CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT UNIQUE, qty INTEGER, img BLOB)');
            await db.execute('CREATE TABLE counter (id INTEGER PRIMARY KEY, n INTEGER)');
            await db.insert('counter', {'id': 1, 'n': 0});
          },
        ));
    server = LanDatabaseServer(
      databasePath: dbPath,
      secret: secret,
      port: 0,
      enableDiscovery: false,
      transactionIdleTimeout: const Duration(seconds: 3),
      log: (_) {},
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await serverDb.close();
    await tmp.delete(recursive: true);
  });

  test('الطرفية تكتب والسيرفر يقرأ، والعكس', () async {
    final (conn, db) = await newClient('كاشير 1');
    await db.insert('items', {'name': 'سكر', 'qty': 5});
    final seenByServer = await serverDb.query('items');
    expect(seenByServer.single['name'], 'سكر');

    await serverDb.insert('items', {'name': 'رز', 'qty': 7});
    final seenByClient = await db.rawQuery('SELECT name FROM items ORDER BY id');
    expect(seenByClient.map((r) => r['name']), ['سكر', 'رز']);
    await conn.close();
  });

  test('البيانات الثنائية (BLOB) تصل كما هي', () async {
    final (conn, db) = await newClient('c');
    final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));
    await db.insert('items', {'name': 'صورة', 'img': bytes});
    final row = (await db.query('items', where: 'name = ?', whereArgs: ['صورة'])).single;
    expect(row['img'], isA<Uint8List>());
    expect(row['img'], bytes);
    await conn.close();
  });

  test('معاملات متزامنة من طرفيتين + السيرفر لا تفقد أي زيادة', () async {
    final (c1, db1) = await newClient('c1');
    final (c2, db2) = await newClient('c2');

    Future<void> bump(Database db, int times) async {
      for (var i = 0; i < times; i++) {
        await db.transaction((txn) async {
          final n = (await txn.rawQuery('SELECT n FROM counter WHERE id = 1'))
              .single['n'] as int;
          await txn.rawUpdate('UPDATE counter SET n = ? WHERE id = 1', [n + 1]);
        });
      }
    }

    await Future.wait([bump(db1, 40), bump(db2, 40), bump(serverDb, 40)]);
    final n = (await serverDb.rawQuery('SELECT n FROM counter')).single['n'];
    expect(n, 120);
    await c1.close();
    await c2.close();
  });

  test('خطأ داخل معاملة الطرفية ⇒ تراجع كامل', () async {
    final (conn, db) = await newClient('c');
    await expectLater(
      db.transaction((txn) async {
        await txn.insert('items', {'name': 'مؤقت', 'qty': 1});
        throw StateError('فشل مقصود');
      }),
      throwsStateError,
    );
    expect(await serverDb.query('items'), isEmpty);
    await conn.close();
  });

  test('أخطاء القيود تصل كـ DatabaseException عادي', () async {
    final (conn, db) = await newClient('c');
    await db.insert('items', {'name': 'مكرر'});
    try {
      await db.insert('items', {'name': 'مكرر'});
      fail('كان يجب أن يفشل');
    } on DatabaseException catch (e) {
      expect(e.isUniqueConstraintError(), isTrue);
    }
    await conn.close();
  });

  test('انقطاع الطرفية وسط معاملة ⇒ السيرفر يتراجع ولا يتجمّد', () async {
    final (conn, db) = await newClient('c');
    final txn = db.transaction((txn) async {
      await txn.insert('items', {'name': 'لن يُحفظ'});
      await conn.debugDropConnection(); // الشبكة سقطت هنا
      await txn.insert('items', {'name': 'ولا هذا'});
    });
    await expectLater(txn, throwsA(anything));

    // السيرفر يجب أن يكتب فوراً (لا ينتظر المعاملة الميتة)
    await serverDb
        .insert('items', {'name': 'بعد الانقطاع'})
        .timeout(const Duration(seconds: 5));
    final names = (await serverDb.query('items')).map((r) => r['name']).toList();
    expect(names, ['بعد الانقطاع']);
  });

  test('رمز ربط خاطئ ⇒ رسالة واضحة', () async {
    final conn = LanClientConnection(
        host: '127.0.0.1', port: server.boundPort, secret: 'خطأ');
    await expectLater(
      conn.connect(),
      throwsA(isA<LanConnectionException>()
          .having((e) => e.message, 'message', contains('رمز الربط'))),
    );
  });

  test('الطرفية لا تستطيع حذف قاعدة السيرفر', () async {
    final (conn, _) = await newClient('c');
    final factory = createLanDatabaseFactory(conn);
    await expectLater(factory.deleteDatabase('x.db'), throwsA(anything));
    expect(File(dbPath).existsSync(), isTrue);
    await conn.close();
  });

  test('إغلاق الطرفية لقاعدتها لا يغلق قاعدة السيرفر', () async {
    final (conn, db) = await newClient('c');
    await db.close();
    await serverDb.insert('items', {'name': 'ما زال يعمل'});
    expect((await serverDb.query('items')).length, 1);
    await conn.close();
  });

  test('إعادة الاتصال التلقائية بعد انقطاع قصير', () async {
    final (conn, db) = await newClient('c');
    await db.insert('items', {'name': 'قبل'});
    await conn.debugDropConnection();
    await db.insert('items', {'name': 'بعد'}); // يعيد الاتصال تلقائياً
    expect((await serverDb.query('items')).length, 2);
    await conn.close();
  });

  test('ترميز القيم ذهاباً وإياباً', () {
    final v = {
      'a': 1,
      'b': 2.5,
      'c': 'نص',
      'd': null,
      'e': Uint8List.fromList([1, 2, 3]),
      'f': [1, 'x', Uint8List.fromList([9])],
    };
    final back = lanDecodeValue(lanEncodeValue(v)) as Map;
    expect(back['a'], 1);
    expect(back['b'], 2.5);
    expect(back['e'], Uint8List.fromList([1, 2, 3]));
    expect((back['f'] as List)[2], Uint8List.fromList([9]));
  });
}
