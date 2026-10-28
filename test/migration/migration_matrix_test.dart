// test/migration/migration_matrix_test.dart
//
// 🧪 مصفوفة الهجرة: كل قاعدة قديمة/غريبة تُستعاد بالمسار الحقيقي للبرنامج
// (DatabaseService.restoreDatabaseFromFile ← فتح ← ensureSchema ← SchemaHealer ←
// المخططات ← ضغط اللقطات ← حارس الهجرة)، ثم يُتحقق من:
//   1) فُتحت بلا خطأ (ولا رفض من حارس الهجرة).
//   2) المخطط مكتمل: كل جدول وعمود في قاعدة جديدة موجود فيها.
//   3) المال لم يتغير: عدد ومجموع المعاملات، الفواتير، الأصناف، التسديدات الراجعة.
//   4) لا لقطة نصية باقية، ولا عميلان بنفس الهوية.
//   5) التقارير تعمل عليها (الملخص، المقبوض والديون).
//   6) الاستعادة مرة ثانية للقاعدة نفسها بعد الهجرة لا تغيّر شيئاً.
//   7) ملف تالف يُرفض وتبقى القاعدة السابقة كما هي.
//
// المصادر: test/migration/fixtures/*.db (مخططات قديمة مولّدة ببيانات وهمية)
// + أي مجلد في المتغير MIGRATION_FIXTURES (نسخك الحقيقية، تُقرأ ولا تُعدّل):
//   flutter test test/migration/migration_matrix_test.dart
//   $env:MIGRATION_FIXTURES="C:\Users\jihad\Desktop\AlnaserAccounting"; flutter test test/migration/migration_matrix_test.dart
//
// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';

import 'package:alnaser/services/backup_files.dart';
import 'package:alnaser/services/database/core/migration_guard.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/reports_service.dart';
import 'package:archive/archive_io.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sync_harness/fake_platforms.dart';

/// أرقام المال وما يجب ألّا يضيع.
class _Money {
  _Money(this.v);
  final Map<String, num> v;

  static Future<bool> _has(Database db, String t, [String? col]) async {
    final r = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [t]);
    if (r.isEmpty) return false;
    if (col == null) return true;
    return (await db.rawQuery('PRAGMA table_info("$t")')).any((c) => c['name'] == col);
  }

  static Future<num> _one(Database db, String sql) async {
    final r = await db.rawQuery(sql);
    return (r.first.values.first as num?) ?? 0;
  }

  static Future<_Money> take(Database db) async {
    final m = <String, num>{};
    final txDel = await _has(db, 'transactions', 'is_deleted') ? 'WHERE COALESCE(is_deleted,0)=0' : '';
    m['transactions.count'] = await _one(db, 'SELECT COUNT(*) FROM transactions $txDel');
    m['transactions.sum'] = await _one(db, 'SELECT COALESCE(SUM(amount_changed),0) FROM transactions $txDel');
    if (await _has(db, 'invoices')) {
      final d = await _has(db, 'invoices', 'is_deleted') ? 'WHERE COALESCE(is_deleted,0)=0' : '';
      m['invoices.count'] = await _one(db, 'SELECT COUNT(*) FROM invoices $d');
      m['invoices.sum'] = await _one(db, 'SELECT COALESCE(SUM(total_amount),0) FROM invoices $d');
    }
    if (await _has(db, 'invoice_items')) {
      m['invoice_items.count'] = await _one(db, 'SELECT COUNT(*) FROM invoice_items');
      m['invoice_items.sum'] = await _one(db, 'SELECT COALESCE(SUM(item_total),0) FROM invoice_items');
    }
    if (await _has(db, 'returns')) {
      m['returns.count'] = await _one(db, 'SELECT COUNT(*) FROM returns');
      m['returns.sum'] = await _one(db, 'SELECT COALESCE(SUM(amount),0) FROM returns');
    }
    if (await _has(db, 'invoice_snapshots')) {
      m['snapshots.invoices'] = await _one(db, 'SELECT COUNT(DISTINCT invoice_id) FROM invoice_snapshots');
    }
    return _Money(m);
  }

  List<String> diff(_Money after) {
    final out = <String>[];
    for (final e in v.entries) {
      final a = after.v[e.key];
      if (a == null) {
        out.add('${e.key}: اختفى بعد الهجرة');
      } else if ((a - e.value).abs() > 0.5) {
        out.add('${e.key}: قبل ${e.value} — بعد $a');
      }
    }
    return out;
  }
}

Future<Map<String, Set<String>>> _schema(Database db) async {
  final out = <String, Set<String>>{};
  for (final r in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL%'")) {
    final t = '${r['name']}';
    if (t.contains('_fts')) continue;
    out[t] = {for (final c in await db.rawQuery('PRAGMA table_info("$t")')) '${c['name']}'};
  }
  return out;
}

Future<Database> _raw(String path) =>
    databaseFactoryFfiNoIsolate.openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));

void main() {
  late Directory home;
  late Map<String, Set<String>> fresh;

  final fixtures = <File>[];
  final builtIn = Directory('test/migration/fixtures');
  if (builtIn.existsSync()) {
    fixtures.addAll(builtIn.listSync().whereType<File>().where((f) => f.path.endsWith('.db')));
  }
  final extra = Platform.environment['MIGRATION_FIXTURES'];
  if (extra != null && Directory(extra).existsSync()) {
    fixtures.addAll(Directory(extra)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.db')));
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    home = Directory.systemTemp.createTempSync('mig_matrix_');
    Directory('${home.path}/tmp').createSync(recursive: true);
    PathProviderPlatform.instance = FakePathProvider(home.path);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    FirebasePlatform.instance = FakeFirebaseCore();
    // قاعدة جديدة = المخطط المرجعي
    fresh = await _schema(await DatabaseService().database);
    print('📐 المخطط المرجعي: ${fresh.length} جدولاً — ${fixtures.length} قاعدة للاختبار');
  });

  Future<void> restoreAndCheck(File source, {required String label}) async {
    // نسخة من الملف (والأصل لا يُلمس) مع WAL إن وُجد
    final work = File('${home.path}/in_${DateTime.now().microsecondsSinceEpoch}.db');
    await source.copy(work.path);
    for (final s in ['-wal', '-shm']) {
      final f = File('${source.path}$s');
      if (f.existsSync()) await f.copy('${work.path}$s');
    }
    final rawBefore = await _raw(work.path);
    final before = await _Money.take(rawBefore);
    await rawBefore.close();

    final sw = Stopwatch()..start();
    try {
      final ok = await DatabaseService().restoreDatabaseFromFile(work);
      expect(ok, isTrue);
    } on MigrationGuardException catch (e) {
      fail('$label: رفض حارس الهجرة:\n${e.problems.take(20).join('\n')}');
    }
    final db = await DatabaseService().database;
    print('⏱️ $label: ${sw.elapsedMilliseconds}ms');
    expect(DatabaseService.lastRestoreReport, isNotNull, reason: '$label: لا تقرير استعادة');
    print(DatabaseService.lastRestoreReport);

    // 2) المخطط مكتمل
    final have = await _schema(db);
    final missing = <String>[];
    for (final e in fresh.entries) {
      final cols = have[e.key];
      if (cols == null) {
        missing.add('جدول ${e.key}');
        continue;
      }
      for (final c in e.value) {
        if (!cols.contains(c)) missing.add('${e.key}.$c');
      }
    }
    expect(missing, isEmpty, reason: '$label: ناقص بعد الهجرة: ${missing.take(40).join('، ')}');

    // 3) المال
    final after = await _Money.take(db);
    final d = before.diff(after);
    expect(d, isEmpty, reason: '$label: ${d.join(' | ')}');

    // 4) اللقطات والهوية
    final text = await db.rawQuery("SELECT COUNT(*) AS n FROM invoice_snapshots WHERE typeof(items_json) = 'text'");
    expect((text.first['n'] as num).toInt(), 0, reason: '$label: لقطات نصية لم تُضغط');
    final dup = await db.rawQuery('''SELECT COUNT(*) AS n FROM (SELECT sync_uuid FROM customers
        WHERE sync_uuid IS NOT NULL AND sync_uuid != '' GROUP BY sync_uuid HAVING COUNT(*) > 1)''');
    expect((dup.first['n'] as num).toInt(), 0, reason: '$label: عملاء مكررون بنفس الهوية');

    // 5) التقارير
    final rs = ReportsService();
    final from = DateTime(2000), to = DateTime.now();
    final s = await rs.getPeriodSummary(startDate: from, endDate: to);
    expect(s['totalSales'], isNotNull);
    final facts = await rs.loadFacts(from: from, to: to);
    final cash = await rs.cashFlow(facts, from: from, to: to);
    // دفتر الديون: البداية + التغيّر = مجموع الأرصدة (عملاء غير محذوفين)
    final bal = await db.rawQuery(
        'SELECT COALESCE(SUM(current_total_debt),0) AS s FROM customers WHERE COALESCE(is_deleted,0)=0');
    print('   💵 $label: مبيعات ${s['totalSales']} • مقبوض ${cash.netCollected.round()} • '
        'ديون الدفتر ${cash.debtEnd?.round()} • أرصدة العملاء ${(bal.first['s'] as num).round()}');
  }

  for (final f in fixtures) {
    final label = f.path.split(Platform.pathSeparator).last;
    test('استعادة وهجرة: $label', () async {
      await restoreAndCheck(f, label: label);

      // 6) مرة ثانية على الناتج: لا تغيير
      final db = await DatabaseService().database;
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final again = File('${home.path}/again_${DateTime.now().microsecondsSinceEpoch}.db');
      await db.execute("VACUUM INTO '${again.path.replaceAll("'", "''")}'");
      await restoreAndCheck(again, label: '$label (مرة ثانية)');
    }, timeout: const Timeout(Duration(minutes: 30)));
  }

  test('قاعدة من إصدار أحدث (user_version أعلى) تُفتح وتُكمَّل', () async {
    final db = await DatabaseService().database;
    final f = File('${home.path}/future.db');
    if (f.existsSync()) f.deleteSync();
    await db.execute("VACUUM INTO '${f.path.replaceAll("'", "''")}'");
    final raw = await databaseFactoryFfiNoIsolate.openDatabase(f.path, options: OpenDatabaseOptions(singleInstance: false));
    await raw.execute('PRAGMA user_version = 999');
    await raw.execute('CREATE TABLE future_feature (id INTEGER PRIMARY KEY, x TEXT)'); // جدول لا نعرفه
    await raw.close();
    await restoreAndCheck(f, label: 'إصدار أحدث');
    final t = await (await DatabaseService().database)
        .rawQuery("SELECT 1 FROM sqlite_master WHERE name = 'future_feature'");
    expect(t, isNotEmpty, reason: 'جدول من إصدار أحدث يُترك كما هو');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('ملف تالف أو ليس قاعدة يُرفض وتبقى القاعدة السابقة', () async {
    final db = await DatabaseService().database;
    final before = await _Money.take(db);
    final junk = File('${home.path}/junk.db')..writeAsBytesSync(List<int>.generate(4096, (i) => i % 251));
    await expectLater(DatabaseService().restoreDatabaseFromFile(junk), throwsA(anything));
    final after = await _Money.take(await DatabaseService().database);
    expect(before.diff(after), isEmpty);
  });

  test('أرشيف تيليجرام (.tar.xz) تُستخرج منه القاعدة', () async {
    if (fixtures.isEmpty) return;
    final src = fixtures.first;
    final bytes = src.readAsBytesSync();
    final archive = Archive()..addFile(ArchiveFile('فرع_2026-10-27/debt_book.db', bytes.length, bytes));
    final xz = XZEncoder().encode(TarEncoder().encode(archive));
    final f = File('${home.path}/backup.tar.xz')..writeAsBytesSync(xz);
    final out = await BackupFiles.extractDatabase(f);
    expect(out.readAsBytesSync().length, bytes.length);
    expect(String.fromCharCodes(out.readAsBytesSync().sublist(0, 15)), 'SQLite format 3');
  });
}
