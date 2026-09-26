// lib/services/database/business/customer_visibility.dart
// 🛡️ قاعدة ظهور العميل الوحيدة بعد حذفه
//
// العميل مخفي ⇔ موسوم بالحذف (tombstoned = 1 أو 2) ولا معاملة نشطة له.
//
// لماذا دالة حتمية؟ حذف عميل على جهاز، مع بيع سُجّل عليه أوفلاين في جهاز آخر،
// كان يعطي نتائج مختلفة بين الأجهزة حسب ترتيب الوصول: الجهاز البائع يبقي
// العميل بكل ديونه القديمة، وبقية الأجهزة تحذفه أو تعيده بالبيع الجديد فقط
// (المحاكاة: tools/sync_sim سيناريو 41). حين يكون الظهور دالة على حالة
// متقاربة (شاهد الحذف + المعاملات النشطة)، تصل كل الأجهزة لنفس النتيجة.

import 'package:sqflite/sqflite.dart';

class CustomerVisibility {
  static Future<void> apply(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery('''
      SELECT c.tombstoned AS tomb, c.is_deleted AS del,
             (SELECT COUNT(*) FROM transactions t WHERE t.customer_id = c.id
                AND (t.is_deleted IS NULL OR t.is_deleted = 0)) AS active
      FROM customers c WHERE c.id = ?
    ''', [customerId]);
    if (r.isEmpty) return;
    final tomb = (r.first['tomb'] as num?)?.toInt() ?? 0;
    final active = (r.first['active'] as num?)?.toInt() ?? 0;
    final hidden = ((tomb == 1 || tomb == 2) && active == 0) ? 1 : 0;
    final del = (r.first['del'] as num?)?.toInt() ?? 0;
    if (del != hidden) {
      await db.update('customers', {'is_deleted': hidden},
          where: 'id = ?', whereArgs: [customerId]);
    }
  }
}
