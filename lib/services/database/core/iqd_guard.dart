// lib/services/database/core/iqd_guard.dart
//
// 💵 القاعدة نفسها ترفض مبلغاً بالدينار فيه كسور (lib/utils/iqd.dart).
//
// التطبيق يقرّب كل مبلغ قبل حفظه؛ هذه المشغّلات شبكة أمان تحته: إن فات مسارٌ
// التقريبَ رُفض الحفظ كله برسالة واضحة بدل أن يُخزَّن كسر بصمت.
//
// لماذا مشغّلات لا CHECK: قيد CHECK لا يُضاف إلى جدول موجود (يحتاج إعادة بناء
// الجدول)، وأي هجرة تعيد بناء جدول كانت ستسقطه. المشغّلات تُنشأ على القاعدة
// الجديدة والقديمة والمستعادة عند كل فتح، وآمنة التكرار.
//
// ما يُفحص — ما يكتبه هذا الجهاز فقط:
//   • الصف الوارد بالمزامنة أو المستعاد من السحابة (is_uploaded = 1 /
//     is_synced = 1) يُكتب كما جاء: مبلغه مسؤولية جهازه، وتقريبه هنا كان سيجعل
//     للمعاملة الواحدة مبلغين على جهازين.
//   • معاملة الفاتورة مشتقة من رأسها، والرأس نفسه مفحوص — فلا تُفحص مرتين
//     (وفاتورة قديمة بكسور تبقى قابلة للتعديل: فرقها يصفّي كسرها).
//   • التحديث يُفحص فقط إن تغيّر المبلغ: صف قديم بكسور لا يمنع تحديث حقل آخر فيه.
//   • معاملة يدوية بكسر تُقبل فقط إن جعلت رصيد العميل صحيحاً (تصفية كسر قديم).
//   • عند المورد: بالدينار فقط (currency = 'IQD')؛ الدولار يبقى بكسوره.
//   • سعر الوحدة والكلفة لا يُفحصان (قد يكونان مشتقين: 10,000 ÷ 3).

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

class IqdGuard {
  IqdGuard._();

  /// بادئة الأسماء: رقم الإصدار يتغير إن تغيّر نص مشغّل (فيُحذف القديم ويُنشأ الجديد)
  static const String prefix = 'iqd1_';

  /// نص الرفض — يبدأ بهذا الرمز ليُعرف في الأخطاء والاختبارات
  static const String code = 'IQD_FRACTION';

  static String _frac(String x) => 'ABS(($x) - ROUND($x)) > 0.0001';

  static String _raise(String where) =>
      "SELECT RAISE(ABORT, '$code: مبلغ بالدينار فيه كسور — رُفض الحفظ ($where)');";

  static Future<Set<String>> _cols(DatabaseExecutor db, String table) async {
    final r = await db.rawQuery('PRAGMA table_info($table)');
    return {for (final c in r) (c['name'] as String).toLowerCase()};
  }

  /// المشغّلات المطلوبة: (الاسم، الجدول، الأعمدة اللازمة، نص الإنشاء)
  static List<(String, String, List<String>, String)> _defs() {
    // —— سجل ديون العملاء: معاملة يكتبها المستخدم ——
    const txLocal = "COALESCE(NEW.is_uploaded, 0) = 0 AND NEW.invoice_id IS NULL "
        "AND COALESCE(NEW.invoice_sync_uuid, '') = '' AND COALESCE(NEW.is_deleted, 0) = 0";
    final txBalance = '(SELECT COALESCE(SUM(amount_changed), 0) FROM transactions '
        'WHERE customer_id = NEW.customer_id AND COALESCE(is_deleted, 0) = 0)';
    const txCols = ['amount_changed', 'is_uploaded', 'invoice_id', 'invoice_sync_uuid', 'is_deleted', 'customer_id'];

    // —— فاتورة البيع: رأسها (المحلية فقط: is_synced = 0) ——
    const invMoney = ['total_amount', 'discount', 'amount_paid_on_invoice', 'loading_fee', 'return_amount'];
    String invChanged(bool update) => invMoney
        .map((c) => update ? '(NEW.$c IS NOT OLD.$c AND ${_frac('NEW.$c')})' : _frac('NEW.$c'))
        .join(' OR ');

    // —— فاتورة البيع: أسطرها (محلية إن كان رأسها محلياً) ——
    const itemLocal = 'COALESCE((SELECT is_synced FROM invoices WHERE id = NEW.invoice_id), 0) = 0';

    String supplierHeader(String table, List<String> money, bool update, {String extra = ''}) {
      final changed = money
          .map((c) => update ? '(NEW.$c IS NOT OLD.$c AND ${_frac('NEW.$c')})' : _frac('NEW.$c'))
          .join(' OR ');
      return 'CREATE TRIGGER IF NOT EXISTS $prefix${table}_${update ? 'upd' : 'ins'} '
          '${update ? 'AFTER UPDATE' : 'AFTER INSERT'} ON $table '
          "WHEN COALESCE(NEW.currency, 'IQD') = 'IQD'$extra AND ($changed) "
          'BEGIN ${_raise(table)} END';
    }

    const purItemIqd =
        "COALESCE((SELECT currency FROM purchase_invoices WHERE id = NEW.invoice_id), 'IQD') = 'IQD'";
    const supTxManual = ' AND NEW.invoice_id IS NULL AND NEW.payment_id IS NULL AND COALESCE(NEW.is_deleted, 0) = 0';

    return [
      (
        '${prefix}tx_ins',
        'transactions',
        txCols,
        'CREATE TRIGGER IF NOT EXISTS ${prefix}tx_ins AFTER INSERT ON transactions '
            'WHEN $txLocal AND ${_frac('NEW.amount_changed')} AND ${_frac(txBalance)} '
            'BEGIN ${_raise('transactions')} END',
      ),
      (
        '${prefix}tx_upd',
        'transactions',
        txCols,
        'CREATE TRIGGER IF NOT EXISTS ${prefix}tx_upd AFTER UPDATE OF amount_changed ON transactions '
            'WHEN NEW.amount_changed IS NOT OLD.amount_changed AND $txLocal '
            'AND ${_frac('NEW.amount_changed')} AND ${_frac(txBalance)} '
            'BEGIN ${_raise('transactions')} END',
      ),
      (
        '${prefix}inv_ins',
        'invoices',
        [...invMoney, 'is_synced'],
        'CREATE TRIGGER IF NOT EXISTS ${prefix}inv_ins AFTER INSERT ON invoices '
            'WHEN COALESCE(NEW.is_synced, 0) = 0 AND (${invChanged(false)}) '
            'BEGIN ${_raise('invoices')} END',
      ),
      (
        '${prefix}inv_upd',
        'invoices',
        [...invMoney, 'is_synced'],
        'CREATE TRIGGER IF NOT EXISTS ${prefix}inv_upd AFTER UPDATE ON invoices '
            'WHEN COALESCE(NEW.is_synced, 0) = 0 AND (${invChanged(true)}) '
            'BEGIN ${_raise('invoices')} END',
      ),
      (
        '${prefix}item_ins',
        'invoice_items',
        ['item_total', 'invoice_id'],
        'CREATE TRIGGER IF NOT EXISTS ${prefix}item_ins AFTER INSERT ON invoice_items '
            'WHEN ${_frac('NEW.item_total')} AND $itemLocal '
            'BEGIN ${_raise('invoice_items')} END',
      ),
      (
        '${prefix}item_upd',
        'invoice_items',
        ['item_total', 'invoice_id'],
        'CREATE TRIGGER IF NOT EXISTS ${prefix}item_upd AFTER UPDATE OF item_total ON invoice_items '
            'WHEN NEW.item_total IS NOT OLD.item_total AND ${_frac('NEW.item_total')} AND $itemLocal '
            'BEGIN ${_raise('invoice_items')} END',
      ),
      (
        '${prefix}sret_ins',
        'sales_returns',
        ['total', 'cash_amount'],
        'CREATE TRIGGER IF NOT EXISTS ${prefix}sret_ins AFTER INSERT ON sales_returns '
            "WHEN ${_frac('NEW.total')} OR ${_frac('COALESCE(NEW.cash_amount, 0)')} "
            'BEGIN ${_raise('sales_returns')} END',
      ),
      (
        '${prefix}purchase_invoices_ins',
        'purchase_invoices',
        ['currency', 'total_amount', 'paid_amount'],
        supplierHeader('purchase_invoices', ['total_amount', 'paid_amount'], false),
      ),
      (
        '${prefix}purchase_invoices_upd',
        'purchase_invoices',
        ['currency', 'total_amount', 'paid_amount'],
        supplierHeader('purchase_invoices', ['total_amount', 'paid_amount'], true),
      ),
      (
        '${prefix}pitem_ins',
        'purchase_invoice_items',
        ['total_price', 'invoice_id'],
        'CREATE TRIGGER IF NOT EXISTS ${prefix}pitem_ins AFTER INSERT ON purchase_invoice_items '
            'WHEN ${_frac('NEW.total_price')} AND $purItemIqd '
            'BEGIN ${_raise('purchase_invoice_items')} END',
      ),
      (
        '${prefix}supplier_payments_ins',
        'supplier_payments',
        ['currency', 'amount'],
        supplierHeader('supplier_payments', ['amount'], false),
      ),
      (
        '${prefix}supplier_payments_upd',
        'supplier_payments',
        ['currency', 'amount'],
        supplierHeader('supplier_payments', ['amount'], true),
      ),
      (
        '${prefix}supplier_transactions_ins',
        'supplier_transactions',
        ['currency', 'amount_changed', 'invoice_id', 'payment_id', 'is_deleted'],
        supplierHeader('supplier_transactions', ['amount_changed'], false, extra: supTxManual),
      ),
      (
        '${prefix}supplier_transactions_upd',
        'supplier_transactions',
        ['currency', 'amount_changed', 'invoice_id', 'payment_id', 'is_deleted'],
        supplierHeader('supplier_transactions', ['amount_changed'], true, extra: supTxManual),
      ),
    ];
  }

  /// نصوص الإنشاء (للاختبار والمراجعة).
  static List<String> sqlForReview() => [for (final d in _defs()) d.$4];

  /// يُنشئ ما ينقص من المشغّلات. جدول أو عمود غائب ⇒ يُتخطّى مشغّله (لا يُكسر فتح القاعدة).
  static Future<void> ensure(Database db) async {
    // إصدار سابق من المشغّلات (بادئة أخرى) يُحذف: لا يبقى مشغّلان لقاعدة واحدة
    final old = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'iqd%' AND name NOT LIKE ?",
        ['$prefix%']);
    for (final r in old) {
      await db.execute('DROP TRIGGER IF EXISTS "${r['name']}"');
    }
    final colsCache = <String, Set<String>>{};
    for (final (name, table, needed, sql) in _defs()) {
      try {
        final cols = colsCache[table] ??= await _cols(db, table);
        if (cols.isEmpty) continue; // الجدول غير موجود في هذه القاعدة
        final missing = needed.where((c) => !cols.contains(c)).toList();
        if (missing.isNotEmpty) {
          debugPrint('💵 IqdGuard: $name تُخطّي — أعمدة غائبة في $table: $missing');
          continue;
        }
        await db.execute(sql);
      } catch (e) {
        debugPrint('💵 IqdGuard: تعذّر إنشاء $name: $e');
      }
    }
  }

  /// هل الخطأ رفضُ كسرٍ من هذه المشغّلات؟
  static bool isFractionError(Object e) => e.toString().contains(code);
}
