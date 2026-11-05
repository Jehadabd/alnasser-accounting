// lib/services/backup_package.dart
//
// 📦 حزمة النسخ الاحتياطي الموحّدة — الملف نفسه لكل الوجهات (تيليجرام، Dropbox،
// Google Drive، ديسكورد):
//   1) لقطة متّسقة من القاعدة الحية (BackupFiles.snapshotForBackup: VACUUM INTO يشمل ما في
//      ملف WAL، ثم فكّ أصناف اللقطات المضغوطة نصاً لضغط أفضل — في النسخة وحدها).
//   2) فحص سلامة اللقطة (PRAGMA quick_check) — لقطة غير سليمة لا تُرفع أبداً.
//   3) TAR ثم XZ (LZMA2) في معالج منفصل، ثم فكّه بمسار الاستعادة نفسه ومقارنته بالأصل
//      بايتاً ببايت (XzBackup). إن تعذّر ذلك: ZIP — والاستعادة تقبل الاثنين.
// داخل عملية «رفع البيانات» (beginSession … endSession) تُصنع الحزمة مرة واحدة وتُرسل
// نفسها لكل وجهة: ضغط واحد بدل أربعة، ولقطة واحدة في لحظة واحدة.
// القاعدة الحية لا تتغير إطلاقاً (كل العمل على نسخة في مجلد مؤقت).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'backup_files.dart';
import 'settings_manager.dart';
import 'xz/xz_backup.dart';

class BackupPackage {
  BackupPackage._(this.file, this.format, this.rawSize, this.createdAt, this.branchName);

  /// الملف المضغوط الجاهز للرفع.
  final File file;

  /// 'XZ' أو 'ZIP'.
  final String format;

  /// حجم قاعدة البيانات قبل الضغط.
  final int rawSize;
  final DateTime createdAt;
  final String branchName;

  /// امتداد الملف بحسب الضغط.
  String get extension => format == 'XZ' ? '.tar.xz' : '.zip';
  String get mimeType => format == 'XZ' ? 'application/x-xz' : 'application/zip';

  Future<int> length() => file.length();

  /// يحذف المجلد المؤقت للحزمة.
  Future<void> dispose() async {
    try {
      await file.parent.delete(recursive: true);
    } catch (_) {}
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  // ─────────────────────────── جلسة «رفع البيانات» ───────────────────────────

  static bool _inSession = false;
  static Future<BackupPackage>? _session;

  /// تبدأ عملية رفع: كل الوجهات بعدها تستلم الحزمة نفسها.
  static void beginSession() {
    _inSession = true;
    _session = null;
  }

  /// تنتهي العملية: تُحذف الحزمة بعد مهلة (نسخة ديسكورد قد تُرسل في الخلفية من الملف نفسه).
  static void endSession() {
    final s = _session;
    _inSession = false;
    _session = null;
    if (s == null) return;
    Future<void>.delayed(const Duration(minutes: 15), () async {
      try {
        await (await s).dispose();
      } catch (_) {}
    });
  }

  /// الحزمة: داخل جلسة تُصنع مرة وتُشارك (owned = false، لا يحذفها المستدعي)؛
  /// خارجها حزمة جديدة يملكها المستدعي (owned = true، يحذفها بـ dispose).
  static Future<({BackupPackage pkg, bool owned})> obtain({void Function(double p)? onProgress}) async {
    if (!_inSession) return (pkg: await build(onProgress: onProgress), owned: true);
    final f = _session ??= build(onProgress: onProgress);
    try {
      return (pkg: await f, owned: false);
    } catch (_) {
      // فشل الصنع: لا نُبقي الفشل مخزّناً — الوجهة التالية تحاول من جديد
      if (identical(_session, f)) _session = null;
      rethrow;
    }
  }

  // ─────────────────────────── الصنع ───────────────────────────

  /// يصنع حزمة جديدة. يرمي Exception برسالة عربية عند أي فشل (لا يُرفع شيء ناقص).
  static Future<BackupPackage> build({void Function(double p)? onProgress}) async {
    final now = DateTime.now();
    final settings = await SettingsManager.getAppSettings();
    final branch = settings.branchName;
    final dir = await Directory.systemTemp.createTemp('alnaser_backup_');
    try {
      // 1) لقطة متّسقة
      onProgress?.call(0.02);
      final dbCopy = File(p.join(dir.path, 'debt_book.db'));
      await BackupFiles.snapshotForBackup(dbCopy.path);

      // 2) فحص سلامة اللقطة قبل أي رفع
      onProgress?.call(0.25);
      await _verifySnapshot(dbCopy.path);

      // 3) TAR ← XZ متحقق منه
      onProgress?.call(0.30);
      final folderName = '${branch}_${now.year}-${_two(now.month)}-${_two(now.day)}';
      final dbBytes = await dbCopy.readAsBytes();
      final archive = Archive()..addFile(ArchiveFile('$folderName/debt_book.db', dbBytes.length, dbBytes));
      final tarData = TarEncoder().encode(archive);
      final tarBytes = tarData is Uint8List ? tarData : Uint8List.fromList(tarData);
      final xz = await XzBackup.compressVerified(tarBytes, onProgress: (v) => onProgress?.call(0.32 + v * 0.66));

      final stamp = '${folderName}_${_two(now.hour)}-${_two(now.minute)}';
      final File out;
      final String format;
      if (xz != null) {
        out = File(p.join(dir.path, '$stamp.tar.xz'));
        await out.writeAsBytes(xz, flush: true);
        format = 'XZ';
      } else {
        // بديل نادر: ZIP — الاستعادة تقبله أيضاً
        debugPrint('⚠️ حزمة النسخ: تعذّر XZ المتحقق منه — ZIP بدلاً منه');
        final zip = ZipEncoder().encode(archive);
        if (zip == null) throw Exception('تعذّر ضغط قاعدة البيانات');
        out = File(p.join(dir.path, '$stamp.zip'));
        await out.writeAsBytes(zip, flush: true);
        format = 'ZIP';
      }
      try {
        await dbCopy.delete();
      } catch (_) {}
      onProgress?.call(1.0);
      debugPrint('📦 حزمة النسخ: $format ${dbBytes.length} ← ${await out.length()} بايت');
      return BackupPackage._(out, format, dbBytes.length, now, branch);
    } catch (e) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  /// يفتح اللقطة للقراءة ويتأكد أنها سليمة. أي نتيجة غير «ok» ⇒ لا رفع.
  static Future<void> _verifySnapshot(String path) async {
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final r = await db.rawQuery('PRAGMA quick_check');
      final first = r.isEmpty ? null : r.first.values.first?.toString();
      if (first != 'ok') {
        throw Exception('فحص سلامة نسخة القاعدة فشل ($first) — لم يُرفع شيء. '
            'أبلغ الدعم: قد تحتاج القاعدة نفسها إلى فحص.');
      }
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }
}
