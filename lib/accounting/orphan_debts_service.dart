// lib/accounting/orphan_debts_service.dart
//
// 👻 إعادة «عملاء ليسوا في سجل الديون» إلى السجل — بضغطة صاحب المحل فقط.
// العميل يُعاد برقمه الأصلي، فتعود إليه معاملاته كما هي: لا تُعدَّل ولا تُحذف أي معاملة،
// ولا يتغيّر أي قيد. دينه في السجل = مجموع معاملاته (وهو ما يحسبه الدفتر أصلاً)،
// فيختفي فرق «ذمم العملاء ≠ سجل الديون».
//   • صفّه مفقود  ← يُنشأ باسم واضح «عميل مستعاد #رقم — الاسم» (لا يتشابه مع عميل حالي).
//   • صفّه مخفي (محذوف منطقياً) ← يُظهَر.
// كل استعادة تُسجَّل في سجل النشاط. بعدها: راجع العميل من سجل الديون (تسديد، خصم، تسوية)
// بالطرق العادية التي تُنشئ قيودها الصحيحة.

import '../erp/activity/activity_log.dart';
import '../services/database/dao/customer_dao.dart';
import '../services/database_service.dart';
import 'accounting_reports.dart';

class OrphanDebtsService {
  OrphanDebtsService._();

  /// يعيد [items] إلى سجل الديون. يعيد عدد المُعادين.
  static Future<int> restore(List<OrphanCustomerDebt> items) async {
    final db = await DatabaseService().database;
    final now = DateTime.now().toIso8601String();
    final names = <String>[];
    var n = 0;
    await db.transaction((txn) async {
      for (final o in items) {
        final id = o.customerId;
        if (id == null) continue;
        final sum = await txn.rawQuery(
            'SELECT COALESCE(SUM(amount_changed), 0) AS s FROM transactions WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0',
            [id]);
        final total = ((sum.first['s'] as num?) ?? 0).toDouble();
        final cents = (total * 100).round();
        final existing = await txn.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
        final label = (o.name == null || o.name!.trim().isEmpty)
            ? 'عميل مستعاد #$id'
            : 'عميل مستعاد #$id — ${o.name!.trim()}';
        if (existing.isNotEmpty) {
          await txn.update(
            'customers',
            {
              'is_deleted': 0,
              'current_total_debt': total,
              'current_total_debt_cents': cents,
              'last_modified_at': now,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await txn.insert('customers', {
            'id': id,
            'name': label,
            'current_total_debt': total,
            'current_total_debt_cents': cents,
            'last_modified_at': now,
            'created_at': now,
            'sync_uuid': CustomerDao.newCustomerUuid(),
            'is_deleted': 0,
            'is_created_by_me': 1,
          });
        }
        names.add(label);
        n++;
      }
    });
    if (n > 0) {
      await ActivityLog.log('إضافة', 'سلامة الدفتر',
          'استعادة $n عميلاً إلى سجل الديون (بلا تغيير أي معاملة): ${names.take(10).join('، ')}${names.length > 10 ? '…' : ''}');
    }
    return n;
  }
}
