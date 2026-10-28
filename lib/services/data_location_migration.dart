// lib/services/data_location_migration.dart
//
// 📦 نقل بيانات «الناصر للحسابات» إلى مجلدها الخاص (مرة واحدة، ويندوز فقط).
//
// كان الناصر وشوب مانجر ودفتر الديون تحمل الهوية نفسها على ويندوز
// (com.example / debt_book)، فتشترك في مجلد واحد:
//   %APPDATA%\com.example\debt_book\debt_book.db
// صار للناصر مجلده (Runner.rc: Alnaser / AlnaserAccounting):
//   %APPDATA%\Alnaser\AlnaserAccounting\debt_book.db
//
// عند أول تشغيل بعد التحديث: إن لم توجد قاعدة في المجلد الجديد ووُجدت في
// القديم، يُنسخ المجلد القديم كله (القاعدة + الترخيص + الإعدادات). المجلد
// القديم يبقى كما هو نسخةً احتياطية — لا يُحذف شيء.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'error_log.dart';

class DataLocationMigration {
  DataLocationMigration._();

  static const _dbName = 'debt_book.db';
  static const _marker = 'migrated_from.txt';

  static Future<void> run() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) return;
      final oldDir = Directory(p.join(appData, 'com.example', 'debt_book'));
      final newDir = await getApplicationSupportDirectory();
      if (p.equals(p.normalize(oldDir.path), p.normalize(newDir.path))) return; // بناء قديم لم يتغيّر Runner.rc

      final newDb = File(p.join(newDir.path, _dbName));
      final oldDb = File(p.join(oldDir.path, _dbName));
      if (await newDb.exists() || !await oldDb.exists()) return;

      await newDir.create(recursive: true);
      var files = 0;
      await for (final e in oldDir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: oldDir.path);
        final target = File(p.join(newDir.path, rel));
        await target.parent.create(recursive: true);
        await e.copy(target.path);
        files++;
      }
      await File(p.join(newDir.path, _marker)).writeAsString(
          'نُسخت البيانات من:\n${oldDir.path}\nبتاريخ ${DateTime.now().toIso8601String()} ($files ملف)\n'
          'المجلد القديم بقي كما هو (نسخة احتياطية).\n');
      ErrorLog.note('نُقلت البيانات إلى ${newDir.path} من ${oldDir.path} ($files ملف)');
      debugPrint('📦 نُقلت بيانات الناصر إلى مجلدها الخاص: ${newDir.path}');
    } catch (e) {
      ErrorLog.note('تعذّر نقل البيانات إلى المجلد الجديد: $e');
      debugPrint('⚠️ نقل البيانات: $e');
    }
  }
}
