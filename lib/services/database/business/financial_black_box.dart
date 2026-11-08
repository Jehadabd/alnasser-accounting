// lib/services/database/business/financial_black_box.dart
//
// 📼 الصندوق الأسود المالي — مشغّلات (TRIGGER) في القاعدة تسجّل، ولا تمنع.
//
// دين العميل يُكتب من أماكن كثيرة غير الموفِّق المركزي (المزامنة، الاستعادة،
// الدمج، الاستيراد، أدوات الإصلاح…). بدل لمس كل مسار منها: مشغّل يلتقط كل
// تغيّر فعلي — من أي مسار، بلا استثناء — ويكتب سطراً في fin_black_box:
//
//   • debt        : تغيّر current_total_debt لعميل (القديم، الجديد، ومجموع
//                   معاملاته الحيّة لحظتها).
//   • tx_change   : تغيّر مبلغ معاملة أو عميلها أو فاتورتها أو حالة حذفها.
//   • tx_delete   : حذف نهائي لمعاملة من معاملات هذا الجهاز (لا تُفقد: يبقى
//                   مبلغها وعميلها وفاتورتها وتاريخها ونوعها هنا).
//
// لماذا تسجيل لا منع؟ بعض المسارات تكتب الدين قبل المعاملة وبعضها بعدها داخل
// المعاملة نفسها؛ مشغّل يرفض «الدين ≠ المجموع» لحظياً كان سيوقف حفظاً سليماً
// ويقطع المزامنة في منتصفها. السجل لا يغيّر أي رقم ولا يرفض أي عملية؛
// الفحص العميق يقرؤه ليقول متى قفز الدين ومن أي قيمة إلى أي قيمة.
//
// المعاملات المستلمة من أجهزة أخرى (is_created_by_me = 0) تُستبدل حذفاً
// وإعادة إدراج في كل حزمة مزامنة — حذفها لا يُسجَّل (أصلها على جهازها).

import 'package:sqflite/sqflite.dart';

class FinancialBlackBox {
  FinancialBlackBox._();

  static const table = 'fin_black_box';

  static const _now = "strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')";

  static Future<void> ensure(DatabaseExecutor db) async {
    final tx = await db.rawQuery('PRAGMA table_info(transactions)');
    final cu = await db.rawQuery('PRAGMA table_info(customers)');
    if (tx.isEmpty || cu.isEmpty) return;
    final txCols = {for (final c in tx) '${c['name']}'};
    final cuCols = {for (final c in cu) '${c['name']}'};
    // المشغّل يُقرأ عند كل تحديث: عمود ناقص يُفشل التحديث نفسه، فلا نُنشئه
    // إلا والأعمدة كلها موجودة.
    const needTx = {'customer_id', 'amount_changed', 'is_deleted', 'invoice_id', 'transaction_uuid',
        'transaction_type', 'transaction_date', 'is_created_by_me'};
    if (!txCols.containsAll(needTx) || !cuCols.contains('current_total_debt')) return;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at TEXT NOT NULL,
        kind TEXT NOT NULL,
        customer_id INTEGER,
        invoice_id INTEGER,
        tx_uuid TEXT,
        tx_type TEXT,
        tx_date TEXT,
        old_value REAL,
        new_value REAL,
        tx_sum REAL,
        note TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fbb_customer ON $table(customer_id, id)');

    const liveSum = '(SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t '
        'WHERE t.customer_id = NEW.id AND COALESCE(t.is_deleted, 0) = 0)';

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_fbb_debt_upd_v1
      AFTER UPDATE OF current_total_debt ON customers
      WHEN COALESCE(OLD.current_total_debt, 0) <> COALESCE(NEW.current_total_debt, 0)
      BEGIN
        INSERT INTO $table (at, kind, customer_id, old_value, new_value, tx_sum)
        VALUES ($_now, 'debt', NEW.id, OLD.current_total_debt, NEW.current_total_debt, $liveSum);
      END''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_fbb_debt_ins_v1
      AFTER INSERT ON customers
      WHEN COALESCE(NEW.current_total_debt, 0) <> 0
      BEGIN
        INSERT INTO $table (at, kind, customer_id, old_value, new_value, tx_sum, note)
        VALUES ($_now, 'debt', NEW.id, NULL, NEW.current_total_debt, $liveSum, 'insert');
      END''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_fbb_tx_upd_v1
      AFTER UPDATE OF amount_changed, customer_id, invoice_id, is_deleted ON transactions
      WHEN OLD.amount_changed IS NOT NEW.amount_changed
        OR OLD.customer_id IS NOT NEW.customer_id
        OR OLD.invoice_id IS NOT NEW.invoice_id
        OR COALESCE(OLD.is_deleted, 0) <> COALESCE(NEW.is_deleted, 0)
      BEGIN
        INSERT INTO $table (at, kind, customer_id, invoice_id, tx_uuid, tx_type, tx_date, old_value, new_value, note)
        VALUES ($_now, 'tx_change', NEW.customer_id, NEW.invoice_id, NEW.transaction_uuid, NEW.transaction_type,
                NEW.transaction_date, OLD.amount_changed, NEW.amount_changed,
                'customer ' || COALESCE(OLD.customer_id, '-') || '>' || COALESCE(NEW.customer_id, '-')
                || ' invoice ' || COALESCE(OLD.invoice_id, '-') || '>' || COALESCE(NEW.invoice_id, '-')
                || ' deleted ' || COALESCE(OLD.is_deleted, 0) || '>' || COALESCE(NEW.is_deleted, 0));
      END''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_fbb_tx_del_v1
      AFTER DELETE ON transactions
      WHEN COALESCE(OLD.is_created_by_me, 1) = 1 AND COALESCE(OLD.is_deleted, 0) = 0
      BEGIN
        INSERT INTO $table (at, kind, customer_id, invoice_id, tx_uuid, tx_type, tx_date, old_value, new_value)
        VALUES ($_now, 'tx_delete', OLD.customer_id, OLD.invoice_id, OLD.transaction_uuid, OLD.transaction_type,
                OLD.transaction_date, OLD.amount_changed, NULL);
      END''');
  }

  /// آخر [limit] سطراً لعميل (الأحدث أولاً). قراءة فقط.
  static Future<List<Map<String, Object?>>> forCustomer(DatabaseExecutor db, int customerId,
      {int limit = 20}) async {
    try {
      return await db.query(table,
          where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'id DESC', limit: limit);
    } catch (_) {
      return const [];
    }
  }
}
