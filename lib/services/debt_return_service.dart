// lib/services/debt_return_service.dart
//
// ↩️ «تسديد دين راجع» (من سجل الديون debt_book): العميل يرجّع بضاعة فيُنقص دينه
// بلا نقد في الصندوق.
//
//   • المعاملة نفسها تسديد عادي (manual_payment) عبر CustomerMoney بوصف
//     «مرتجع مبيعات على الحساب» ⇒ قيدها على حساب مرتجع المبيعات، لا الصندوق.
//   • سطر في جدول returns (نفس جدول debt_book، فالقواعد المستوردة تظهر كما كانت)
//     يربطها بمعاملتها ⇒ التقارير تفصلها عن «تسديد دين» تحت «تسديد دين راجع».
//   • لكل فاتورة مختارة يُخصم من مؤسسها نقاط بنسبة المبلغ الراجع (FounderService).
//
// ⚠️ لا يُرجِع المواد إلى المخزن (المبلغ فقط، كما في debt_book). مرتجع المواد
//    الفعلي من «مرتجع الفاتورة»، وهو يُنقص نقاط المؤسس تلقائياً.

import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'database_service.dart';

/// فاتورة للعميل يمكن أن يُسجَّل عليها راجع
class ReturnableInvoice {
  ReturnableInvoice({
    required this.id,
    required this.number,
    required this.date,
    required this.net,
    required this.founder,
    required this.paymentType,
  });
  final int id;
  final String number;
  final DateTime date;

  /// الصافي بعد التسويات ومستندات المرتجع المرحّلة
  final double net;
  final String founder;
  final String paymentType;

  /// ما سُجّل راجعاً عليها سابقاً (مبلغ، نقاط)
  double returnedBefore = 0;

  /// نقاط الفاتورة للمؤسس (null = لم تُحمَّل بعد)
  double? points;
  double pointsDeductedBefore = 0;

  double get room => math.max(0, net - returnedBefore);
  bool get hasFounder => founder.trim().isNotEmpty;
}

class DebtReturnService {
  DebtReturnService._();

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER,
        customer_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        return_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
      )''');
  }

  /// شرط SQL: المعاملة [alias] تسديد دين راجع
  static String isReturnSql(String alias) =>
      "EXISTS (SELECT 1 FROM returns rr WHERE rr.transaction_id = $alias.id)";

  /// مثل [isReturnSql] ويشمل «مرتجع مبيعات» على الحساب وإلغاءه (customer_tx_ext.kind =
  /// 'sales_return'): كان المرتجع يُعدّ «تسديد دين» نقدياً، وإلغاؤه «إضافة دين» يدوياً.
  static Future<String> isReturnSqlFull(DatabaseExecutor db, String alias) async {
    final base = isReturnSql(alias);
    if (!await _has(db, 'customer_tx_ext')) return base;
    final cols = await db.rawQuery('PRAGMA table_info(transactions)');
    if (!cols.any((r) => r['name'] == 'transaction_uuid')) return base;
    return "($base OR EXISTS (SELECT 1 FROM customer_tx_ext xr "
        "WHERE xr.transaction_uuid = $alias.transaction_uuid AND xr.kind = 'sales_return'))";
  }

  static Future<bool> _has(DatabaseExecutor db, String t) async =>
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [t])).isNotEmpty;

  /// فواتير العميل المحفوظة (الأحدث أولاً) مع ما سُجّل راجعاً عليها
  static Future<List<ReturnableInvoice>> customerInvoices(int customerId, String customerName) async {
    final db = await DatabaseService().database;
    await ensureSchema(db);
    final hasAdj = await _has(db, 'invoice_adjustments');
    final hasRet = await _has(db, 'sales_returns');
    final hasLinks = await _has(db, 'founder_return_links');
    final cols = (await db.rawQuery('PRAGMA table_info(invoices)')).map((r) => '${r['name']}').toSet();
    final del = cols.contains('is_deleted') ? 'AND COALESCE(i.is_deleted, 0) = 0' : '';
    final noCol = cols.contains('invoice_number') ? 'i.invoice_number' : 'i.id';
    final rows = await db.rawQuery('''
      SELECT i.id, $noCol AS no, i.invoice_date, i.payment_type, TRIM(COALESCE(i.installer_name, '')) AS founder,
             COALESCE(i.total_amount, 0)
               ${hasAdj ? '+ COALESCE((SELECT SUM(a.amount_delta) FROM invoice_adjustments a WHERE a.invoice_id = i.id), 0)' : ''}
               ${hasRet ? "- COALESCE((SELECT SUM(r.total) FROM sales_returns r WHERE r.original_invoice_id = i.id AND r.status = 'posted'), 0)" : ''}
               AS net,
             ${hasLinks ? 'COALESCE((SELECT SUM(l.amount) FROM founder_return_links l WHERE l.invoice_id = i.id), 0)' : '0'} AS ret
        FROM invoices i
       WHERE (i.customer_id = ? OR (i.customer_id IS NULL AND TRIM(i.customer_name) = ?))
         AND COALESCE(i.status, 'محفوظة') = 'محفوظة' $del
       ORDER BY i.invoice_date DESC, i.id DESC
       LIMIT 300''', [customerId, customerName.trim()]);
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return [
      for (final r in rows)
        ReturnableInvoice(
          id: r['id'] as int,
          number: '${r['no'] ?? r['id']}',
          date: DateTime.tryParse('${r['invoice_date']}') ?? DateTime(2000),
          net: math.max(0, d(r['net'])),
          founder: '${r['founder'] ?? ''}',
          paymentType: '${r['payment_type'] ?? ''}',
        )..returnedBefore = d(r['ret']),
    ];
  }

  /// يربط معاملة التسديد بجدول returns. يعيد id المعاملة (null إن لم تُوجد).
  static Future<int?> recordReturn({
    required String transactionUuid,
    required int customerId,
    required double amount,
    String? note,
  }) async {
    final db = await DatabaseService().database;
    await ensureSchema(db);
    final t = await db.query('transactions',
        columns: ['id', 'transaction_date'], where: 'transaction_uuid = ?', whereArgs: [transactionUuid], limit: 1);
    final txId = t.isEmpty ? null : t.first['id'] as int?;
    final now = DateTime.now().toIso8601String();
    await db.insert('returns', {
      'transaction_id': txId,
      'customer_id': customerId,
      'amount': amount,
      'note': note,
      'return_date': t.isEmpty ? now : '${t.first['transaction_date'] ?? now}',
      'created_at': now,
    });
    return txId;
  }
}
