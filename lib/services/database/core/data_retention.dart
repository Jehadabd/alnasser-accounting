// lib/services/database/core/data_retention.dart
//
// 🧹 سياسة الاحتفاظ بالسجلات غير المالية — حتى لا تكبر القاعدة بالضجيج.
//
// ما يُحذف (فقط):
//   • سجل «تصفح» الشاشات (activity_logs.action = 'تصفح') الأقدم من 7 أيام.
//
// ما لا يُمسّ أبداً: الفواتير، المعاملات، القيود، السندات، سجل العمليات المالية
// (إضافة/تعديل/حذف/اعتماد/موافقة)، إقرارات المزامنة (transaction_acks: دليل المطابقة
// المحصّنة)، وسجل رفع تيليجرام (telegram_sent: حذفه يعيد رفع الفواتير القديمة).
// المزامنة تنظّف سجلاتها بنفسها (sync_operation_log بعد 30 يوماً، WAL بعد 7 أيام).
//
// يعمل مرة في اليوم على حاسبة القاعدة (لا الطرفيات). فشله لا يوقف شيئاً.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

import 'database_doctor.dart' show MaintenanceLog;

class DataRetention {
  DataRetention._();

  static const int browseDays = 7;
  static const String _lastRunKey = 'retention_last_run';

  /// يحذف «تصفح» الشاشات الأقدم من [browseDays]. يعيد عدد الصفوف المحذوفة.
  static Future<int> runIfDue(Database db, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final today = '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    try {
      final has = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='accounting_settings'");
      if (has.isNotEmpty) {
        final r = await db.rawQuery('SELECT value FROM accounting_settings WHERE key = ?', [_lastRunKey]);
        if (r.isNotEmpty && r.first['value'] == today) return 0;
      }
      var deleted = 0;
      final logs = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='activity_logs'");
      if (logs.isNotEmpty) {
        final cutoff = t.subtract(const Duration(days: browseDays)).toIso8601String();
        deleted += await db.delete('activity_logs', where: "action = 'تصفح' AND at < ?", whereArgs: [cutoff]);
      }
      if (has.isNotEmpty) {
        await db.rawInsert(
            'INSERT INTO accounting_settings(key, value) VALUES (?, ?) '
            'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
            [_lastRunKey, today]);
      }
      if (deleted > 0) {
        MaintenanceLog.add('حُذف $deleted سطراً من سجل تصفح الشاشات الأقدم من $browseDays أيام '
            '(سجل العمليات المالية لا يُمسّ)');
      }
      return deleted;
    } catch (e) {
      debugPrint('⚠️ سياسة الاحتفاظ بالسجلات: $e');
      return 0;
    }
  }
}
