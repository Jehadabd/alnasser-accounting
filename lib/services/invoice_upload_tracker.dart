// lib/services/invoice_upload_tracker.dart
//
// 📤 جدولان محليان (لا يُزامَنان، ولا يغيّران جدول الفواتير الذي تنسخه المزامنة
// صفاً كاملاً بين الأجهزة):
//   • invoice_tags: أي فاتورة جاءت من الكاشير (source = 'pos').
//     الإيصالات القديمة قبل هذا التحديث غير معلّمة فتُعدّ فواتير عادية.
//   • telegram_sent: متى رُفعت كل فاتورة إلى تيليغرام — لا تُرفع مرتين،
//     والمعدّلة بعد رفعها تُعرف (last_modified_at أحدث من sent_at).

import 'package:sqflite/sqflite.dart';

class InvoiceUploadTracker {
  InvoiceUploadTracker._();

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS invoice_tags (invoice_id INTEGER PRIMARY KEY, source TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS telegram_sent (invoice_id INTEGER PRIMARY KEY, sent_at TEXT NOT NULL)');
  }

  /// يعلّم فاتورة على أنها إيصال كاشير
  static Future<void> tagPos(DatabaseExecutor db, int invoiceId) async {
    await ensure(db);
    await db.rawInsert('INSERT OR REPLACE INTO invoice_tags (invoice_id, source) VALUES (?, ?)', [invoiceId, 'pos']);
  }

  /// شرط SQL: الفاتورة (بالاسم المستعار [alias]) إيصال كاشير
  static String isPosSql(String alias) =>
      "EXISTS (SELECT 1 FROM invoice_tags t WHERE t.invoice_id = $alias.id AND t.source = 'pos')";

  static Future<void> markSent(DatabaseExecutor db, Iterable<int> ids) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final id in ids) {
      batch.rawInsert('INSERT OR REPLACE INTO telegram_sent (invoice_id, sent_at) VALUES (?, ?)', [id, now]);
    }
    await batch.commit(noResult: true);
  }
}
