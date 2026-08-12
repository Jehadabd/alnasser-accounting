// lib/services/database/core/database_config.dart
// إعداد قاعدة البيانات والاتصال

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// إعدادات قاعدة البيانات
class DatabaseConfig {
  static const int databaseVersion = 49;
  static const String databaseName = 'debt_book.db';
  static const bool verboseLogs = false;

  /// الحصول على مسار قاعدة البيانات
  static Future<String> getDatabasePath() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, databaseName);
  }

  /// ترحيل قاعدة البيانات من المسار القديم إذا لزم الأمر
  static Future<void> migrateFromOldPath() async {
    final dir = await getApplicationSupportDirectory();
    final newPath = join(dir.path, databaseName);
    final oldPath = join(await getDatabasesPath(), databaseName);

    final oldFile = File(oldPath);
    final newFile = File(newPath);
    
    if (await oldFile.exists() && !(await newFile.exists())) {
      await oldFile.copy(newPath);
      await oldFile.delete();
    }
  }

  /// تطبيق إعدادات PRAGMA للأداء والتزامن
  static Future<void> applyPragmas(Database db) async {
    // تفعيل FOREIGN KEYS لضمان عمل CASCADE
    // استخدام rawQuery بدلاً من execute لتوافق أفضل مع Android
    await db.rawQuery('PRAGMA foreign_keys = ON');
    
    // ═══════════════════════════════════════════════════════════════════
    // 🔥 Multi-Session POS Optimization (20+ concurrent users)
    // ═══════════════════════════════════════════════════════════════════
    
    // WAL Mode: يسمح بقراءات غير محدودة أثناء الكتابة
    await db.rawQuery('PRAGMA journal_mode = WAL');
    
    // Busy Timeout: مهلة 30 ثانية للانتظار في الطابور قبل الفشل
    // استخدام rawQuery بدلاً من execute لتوافق أفضل مع Android
    await db.rawQuery('PRAGMA busy_timeout = 30000');
    
    // Synchronous NORMAL: توازن بين السرعة والأمان (WAL يحمي البيانات)
    await db.rawQuery('PRAGMA synchronous = NORMAL');
    
    // Temp Store in Memory: تسريع العمليات المؤقتة
    await db.rawQuery('PRAGMA temp_store = MEMORY');
    
    // Memory-mapped I/O: تسريع القراءة (30GB max)
    await db.rawQuery('PRAGMA mmap_size = 30000000000');
    
    // Cache Size: 200MB RAM cache للبيانات المتكررة
    await db.rawQuery('PRAGMA cache_size = -200000');
  }

  /// التحقق من سلامة قاعدة البيانات
  static Future<bool> checkIntegrity(Database db) async {
    try {
      final integrityCheck = await db.rawQuery('PRAGMA integrity_check;');
      return integrityCheck.first.values.first == 'ok';
    } catch (e) {
      return false;
    }
  }

  /// إصلاح قاعدة البيانات
  static Future<void> repair(Database db) async {
    try {
      await db.execute('VACUUM;');
      await db.rawQuery('REINDEX;');
    } catch (e) {
      // تجاهل الخطأ
    }
  }

  /// استعادة من النسخة الاحتياطية
  static Future<void> restoreFromBackup() async {
    // Stub implementation
    print('Restore from backup called');
  }
}
