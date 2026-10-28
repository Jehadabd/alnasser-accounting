// lib/services/backup_files.dart
//
// 📦 ملفات النسخ الاحتياطي:
//   • snapshotForBackup — نسخة متّسقة من القاعدة الحية لرفعها (تيليجرام):
//       VACUUM INTO يأخذ كل ما في ملف WAL أيضاً (نسخ الملف مباشرة كان يفوّت آخر
//       العمليات التي لم تُكتب بعد في الملف الرئيسي)، وبلا صفحات فارغة.
//       ثم تُفكّ أصناف اللقطات المضغوطة (gzip) نصاً في النسخة وحدها: ضغط XZ
//       للأرشيف لا يستطيع ضغط بيانات مضغوطة سلفاً، فالنص يعطي أرشيفاً أصغر
//       (قيس على قاعدة حقيقية: 8.5 ← 4.6 ميغابايت). القاعدة الحية لا تتغير.
//   • extractDatabase — الاستعادة من أي شكل: ملف .db مباشرة، أو أرشيف تيليجرام
//       (.tar.xz)، أو zip / gz / tar. يُتعرّف على النوع من محتواه لا من اسمه.

import 'dart:convert' show utf8;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database/dao/audit_dao.dart';
import 'database_service.dart';

class BackupFiles {
  BackupFiles._();

  static const _sqliteHeader = 'SQLite format 3';

  static bool _isSqlite(List<int> b) =>
      b.length >= 16 && utf8.decode(b.sublist(0, 15), allowMalformed: true) == _sqliteHeader;

  // ─────────────────────────── للرفع ───────────────────────────

  /// يكتب في [path] نسخة متّسقة من القاعدة الحية مهيّأة لأفضل ضغط.
  static Future<void> snapshotForBackup(String path) async {
    final out = File(path);
    if (await out.exists()) await out.delete();
    final live = await DatabaseService().database;
    try {
      await live.execute("VACUUM INTO '${path.replaceAll("'", "''")}'");
    } catch (e) {
      // قاعدة لا تدعم VACUUM INTO (أو طرفية شبكة): كتابة WAL في الملف ثم نسخه
      debugPrint('⚠️ نسخة الرفع: VACUUM INTO تعذّر ($e) — checkpoint ثم نسخ الملف');
      try {
        await live.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      final src = await DatabaseService().getDatabaseFile();
      await src.copy(path);
      return;
    }
    await _inflateSnapshots(path);
  }

  /// أصناف اللقطات المضغوطة ← نص، في النسخة فقط. أي لقطة لا تُفكّ تبقى كما هي.
  static Future<void> _inflateSnapshots(String path) async {
    Database? db;
    try {
      db = await openDatabase(path, singleInstance: false);
      final has = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'invoice_snapshots'");
      if (has.isEmpty) return;
      var lastId = -1;
      var inflated = 0;
      while (true) {
        final rows = await db.rawQuery('''
          SELECT id, items_json FROM invoice_snapshots
          WHERE typeof(items_json) = 'blob' AND id > ?
          ORDER BY id LIMIT 500''', [lastId]);
        if (rows.isEmpty) break;
        final batch = db.batch();
        for (final r in rows) {
          lastId = (r['id'] as num).toInt();
          final raw = r['items_json'];
          if (raw is! List<int> || raw.isEmpty) continue;
          final text = AuditDao.decodeSnapshotItems(raw);
          // فكّ فاشل يعيد '[]' — لا نستبدل لقطة فيها أصناف بقائمة فارغة
          if (text == '[]' && raw.length > 40) continue;
          batch.update('invoice_snapshots', {'items_json': text}, where: 'id = ?', whereArgs: [lastId]);
          inflated++;
        }
        await batch.commit(noResult: true);
      }
      debugPrint('📦 نسخة الرفع: فُكّت $inflated لقطة نصاً لضغط أفضل');
    } catch (e) {
      // النسخة صالحة كما هي (اللقطات المضغوطة يقرأها البرنامج) — فقط أكبر قليلاً
      debugPrint('⚠️ نسخة الرفع: تعذّر فكّ اللقطات ($e) — تُرفع كما هي');
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  // ─────────────────────────── للاستعادة ───────────────────────────

  /// يعيد ملف قاعدة بيانات جاهزاً للاستعادة من [picked] مهما كان شكله:
  /// قاعدة مباشرة، أو أرشيف (.tar.xz من تيليجرام، .zip، .gz، .tar).
  static Future<File> extractDatabase(File picked) async {
    final head = await _head(picked, 300);
    if (_isSqlite(head)) return picked;

    List<int> bytes = await picked.readAsBytes();
    // طبقة الضغط
    if (_starts(bytes, const [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) {
      bytes = XZDecoder().decodeBytes(bytes);
    } else if (_starts(bytes, const [0x1F, 0x8B])) {
      bytes = GZipDecoder().decodeBytes(bytes);
    } else if (_starts(bytes, const [0x42, 0x5A, 0x68])) {
      bytes = BZip2Decoder().decodeBytes(bytes);
    }

    List<int>? db;
    if (_isSqlite(bytes)) {
      db = bytes;
    } else {
      Archive? archive;
      if (_starts(bytes, const [0x50, 0x4B, 0x03, 0x04])) {
        archive = ZipDecoder().decodeBytes(bytes);
      } else if (bytes.length > 262 && utf8.decode(bytes.sublist(257, 262), allowMalformed: true) == 'ustar') {
        archive = TarDecoder().decodeBytes(bytes);
      }
      if (archive != null) {
        // الأفضل debt_book.db، وإلا أول ملف هو قاعدة SQLite فعلاً
        final files = archive.files.where((f) => f.isFile).toList()
          ..sort((a, b) => (b.name.toLowerCase().endsWith('debt_book.db') ? 1 : 0)
              .compareTo(a.name.toLowerCase().endsWith('debt_book.db') ? 1 : 0));
        for (final f in files) {
          final c = f.content as List<int>;
          if (_isSqlite(c)) {
            db = c;
            break;
          }
        }
      }
    }
    if (db == null) {
      throw Exception('الملف ليس قاعدة بيانات ولا نسخة احتياطية فيها قاعدة بيانات '
          '(المقبول: ‎.db أو أرشيف تيليجرام ‎.tar.xz أو ‎.zip أو ‎.gz)');
    }
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/restore_${DateTime.now().millisecondsSinceEpoch}.db');
    await out.writeAsBytes(db, flush: true);
    return out;
  }

  static bool _starts(List<int> b, List<int> magic) {
    if (b.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[i] != magic[i]) return false;
    }
    return true;
  }

  static Future<List<int>> _head(File f, int n) async {
    final raf = await f.open();
    try {
      return await raf.read(n);
    } finally {
      await raf.close();
    }
  }
}
