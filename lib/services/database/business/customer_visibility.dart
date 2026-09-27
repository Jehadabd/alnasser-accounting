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
//
// «نشطة» = معاملة يدوية أو تسديد (غير محذوفة)، أو فاتورة لها مساهمة غير صفرية
// (مجموع صفوف دينها — كما يحسبها الحارس المحاسبي). فاتورة صافي دينها صفر —
// نُقلت لعميل آخر، أو سُدّدت كاملة — لا تعيد عميلاً محذوفاً: كان صف التسوية
// الصفري للعميل القديم يبقيه ظاهراً على الجهاز المالك وحده، بينما الأجهزة
// الأخرى (تنسب صفوف الحزمة لعميلها الحالي) تخفيه (اختبار الكود الحقيقي:
// فوضى قاسية seed=1407).

import 'package:sqflite/sqflite.dart';

import 'invoice_debt_reconciler.dart';

class CustomerVisibility {
  static Future<void> apply(DatabaseExecutor db, int customerId) async {
    final r = await db.rawQuery('''
      SELECT c.tombstoned AS tomb, c.is_deleted AS del
      FROM customers c WHERE c.id = ?
    ''', [customerId]);
    if (r.isEmpty) return;
    final tomb = (r.first['tomb'] as num?)?.toInt() ?? 0;
    final tombstoned = tomb == 1 || tomb == 2;
    final hidden = (tombstoned && await _activeCount(db, customerId) == 0) ? 1 : 0;
    final del = (r.first['del'] as num?)?.toInt() ?? 0;
    if (del != hidden) {
      await db.update('customers', {'is_deleted': hidden},
          where: 'id = ?', whereArgs: [customerId]);
    }
  }

  /// معاملات العميل النشطة: اليدوية والتسديدات (كل صف غير محذوف)، والفواتير
  /// التي مجموع صفوف مساهمتها غير صفر (صف لكل فاتورة).
  static Future<int> _activeCount(DatabaseExecutor db, int customerId) async {
    const types = InvoiceDebtReconciler.nonContributionTypes;
    final ph = List.filled(types.length, '?').join(',');
    const linked = "(invoice_id IS NOT NULL OR COALESCE(invoice_sync_uuid, '') != '')";
    final manual = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM transactions
      WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
        AND (NOT $linked OR transaction_type IN ($ph))
    ''', <Object?>[customerId, ...types]);
    final invoices = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM (
        SELECT SUM(amount_changed) AS s FROM transactions
        WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
          AND $linked
          AND (transaction_type IS NULL OR transaction_type NOT IN ($ph))
        GROUP BY COALESCE(NULLIF(invoice_sync_uuid, ''), 'id:' || invoice_id)
      ) WHERE ABS(s) > 0.005
    ''', <Object?>[customerId, ...types]);
    return ((manual.first['n'] as num?)?.toInt() ?? 0) +
        ((invoices.first['n'] as num?)?.toInt() ?? 0);
  }
}
