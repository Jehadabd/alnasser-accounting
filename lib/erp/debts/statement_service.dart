// lib/erp/debts/statement_service.dart
//
// 📄 كشف حساب العميل المتقدم (مثل الإداري): فترة برصيد أول المدة، رصيد تراكمي،
// مجموع كل شهر، بحث في الشرح/المبلغ/المادة، «منذ آخر مطابقة»، مع الاستحقاقات.
// و«مطابقة رصيد»: تسجيل الرصيد المتفق عليه مع العميل، وتسوية الفرق اختيارياً.

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../erp_common.dart';
import 'customer_money.dart';

class StatementLine {
  StatementLine({
    required this.id,
    required this.date,
    required this.label,
    required this.note,
    required this.debit,
    required this.credit,
    required this.balance,
    this.invoiceId,
    this.kind,
  });
  final int id;
  final DateTime date;
  final String label;
  final String note;
  final double debit;
  final double credit;
  final double balance;
  final int? invoiceId;
  final String? kind;
}

class MonthTotal {
  MonthTotal(this.year, this.month, this.debit, this.credit);
  final int year;
  final int month;
  double debit;
  double credit;
}

class CustomerStatement {
  CustomerStatement(this.opening, this.lines, this.months, this.from, this.to);
  final double opening;
  final List<StatementLine> lines;
  final List<MonthTotal> months;
  final DateTime? from;
  final DateTime to;
  double get totalDebit => lines.fold(0.0, (s, l) => s + l.debit);
  double get totalCredit => lines.fold(0.0, (s, l) => s + l.credit);
  double get closing => lines.isEmpty ? opening : lines.last.balance;
}

String customerTxLabel(String? type, String? kind, int? invoiceId, double amount) {
  if (invoiceId != null) return amount >= 0 ? 'فاتورة #$invoiceId' : 'تعديل فاتورة #$invoiceId';
  switch (kind) {
    case 'discount':
      return 'خصم مسموح';
    case 'cheque':
      return 'شيك/ورقة قبض';
    case 'cheque_bounce':
      return 'شيك مرتجع';
    case 'sales_return':
      return 'مرتجع مبيعات';
    case 'reconcile':
      return 'فرق مطابقة';
  }
  switch (type) {
    case 'opening_balance':
      return 'رصيد افتتاحي';
    case 'manual_debt':
      return 'دين';
    case 'manual_payment':
      return 'تسديد';
    case 'correction':
      return 'تصحيح';
  }
  return amount >= 0 ? 'دين' : 'تسديد';
}

class StatementService {
  Future<DateTime?> lastReconciliation(int customerId) async {
    final db = await erpDb();
    final r = await db.rawQuery(
        'SELECT MAX(recon_date) AS d FROM customer_reconciliations WHERE customer_id = ?', [customerId]);
    final v = r.first['d'] as String?;
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<CustomerStatement> statement(
    int customerId, {
    DateTime? from,
    required DateTime to,
    String? text,
    double? minAmount,
    double? maxAmount,
    String? productName,
  }) async {
    final db = await erpDb();
    var opening = 0.0;
    if (from != null) {
      final o = await db.rawQuery(
          'SELECT COALESCE(SUM(amount_changed), 0) AS b FROM transactions '
          'WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0 AND transaction_date < ?',
          [customerId, isoDay(from)]);
      opening = roundMoney(d0(o.first['b']));
    }
    final rows = await db.rawQuery('''
      SELECT t.id, t.transaction_date, t.amount_changed, t.transaction_type, t.transaction_note,
             t.description, t.invoice_id, x.kind
      FROM transactions t LEFT JOIN customer_tx_ext x ON x.transaction_uuid = t.transaction_uuid
      WHERE t.customer_id = ? AND COALESCE(t.is_deleted, 0) = 0 AND t.transaction_date < ?
        ${from == null ? '' : 'AND t.transaction_date >= ?'}
      ORDER BY t.transaction_date, t.id
    ''', [customerId, isoDayAfter(to), if (from != null) isoDay(from)]);

    Set<int>? invoiceFilter;
    if (productName != null && productName.trim().isNotEmpty) {
      final inv = await db.rawQuery(
          'SELECT DISTINCT invoice_id FROM invoice_items WHERE product_name LIKE ?', ['%${productName.trim()}%']);
      invoiceFilter = {for (final r in inv) r['invoice_id'] as int};
    }
    final hasFilter = (text != null && text.trim().isNotEmpty) ||
        minAmount != null ||
        maxAmount != null ||
        invoiceFilter != null;

    var bal = opening;
    final lines = <StatementLine>[];
    final months = <String, MonthTotal>{};
    for (final r in rows) {
      final amt = d0(r['amount_changed']);
      bal = roundMoney(bal + amt);
      final date = parseDate(r['transaction_date']);
      final note = [r['transaction_note'], r['description']]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' — ');
      final invoiceId = r['invoice_id'] as int?;
      if (hasFilter) {
        if (text != null && text.trim().isNotEmpty && !note.contains(text.trim())) continue;
        if (minAmount != null && amt.abs() < minAmount) continue;
        if (maxAmount != null && amt.abs() > maxAmount) continue;
        if (invoiceFilter != null && (invoiceId == null || !invoiceFilter.contains(invoiceId))) continue;
      }
      final line = StatementLine(
        id: r['id'] as int,
        date: date,
        label: customerTxLabel(r['transaction_type'] as String?, r['kind'] as String?, invoiceId, amt),
        note: note,
        debit: amt > 0 ? amt : 0,
        credit: amt < 0 ? -amt : 0,
        balance: bal,
        invoiceId: invoiceId,
        kind: r['kind'] as String?,
      );
      lines.add(line);
      final key = '${date.year}-${date.month}';
      final m = months.putIfAbsent(key, () => MonthTotal(date.year, date.month, 0, 0));
      m.debit += line.debit;
      m.credit += line.credit;
    }
    return CustomerStatement(opening, lines, months.values.toList(), from, to);
  }

  /// مواد فاتورة (للكشف «الموضّح»).
  Future<List<Map<String, Object?>>> invoiceItems(int invoiceId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT product_name, sale_type, quantity_individual, quantity_large_unit, applied_price, item_total
      FROM invoice_items WHERE invoice_id = ? ORDER BY id
    ''', [invoiceId]);
  }

  // ═══════════════════════════ مطابقة الرصيد ═══════════════════════════

  Future<double> balanceAt(int customerId, DateTime date) async {
    final db = await erpDb();
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS b FROM transactions '
        'WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0 AND transaction_date < ?',
        [customerId, isoDayAfter(date)]);
    return roundMoney(d0(r.first['b']));
  }

  /// يسجّل مطابقة. إن [adjust] والفرق ليس صفراً تُضاف معاملة «فرق مطابقة» تجعل
  /// الرصيد = المتفق عليه (عبر المسار الأصلي).
  Future<void> reconcile(
    BuildContext context, {
    required int customerId,
    required DateTime date,
    required double agreedBalance,
    required bool adjust,
    String? notes,
  }) async {
    final ours = await balanceAt(customerId, date);
    final diff = roundMoney(agreedBalance - ours);
    String? uuid;
    if (adjust && diff.abs() >= kMoneyEpsilon) {
      if (!context.mounted) throw ErpException('أُغلقت الشاشة');
      uuid = await CustomerMoney.post(
        context,
        customerId: customerId,
        amount: diff,
        kind: CustomerTxKind.reconcile,
        note: 'فرق مطابقة الرصيد بتاريخ ${date.year}/${date.month}/${date.day}'
            '${notes == null || notes.isEmpty ? '' : ' — $notes'}',
        date: date,
        refType: 'reconcile',
      );
    }
    final db = await erpDb();
    await db.insert('customer_reconciliations', {
      'customer_id': customerId,
      'recon_date': isoDay(date),
      'our_balance': ours,
      'agreed_balance': roundMoney(agreedBalance),
      'diff': diff,
      'adjust_tx_uuid': uuid,
      'notes': notes,
      'created_by': currentUserName(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> reconciliations(int customerId) async {
    final db = await erpDb();
    return db.query('customer_reconciliations',
        where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'recon_date DESC, id DESC');
  }

  // ═══════════════════════════ ربط عميل بمورد ═══════════════════════════

  Future<Map<String, Object?>?> linkedSupplier(int customerId) async {
    final db = await erpDb();
    final r = await db.rawQuery('''
      SELECT s.id, s.name, s.total_debt_iqd, s.total_debt_usd FROM party_links l
      JOIN suppliers s ON s.id = l.supplier_id WHERE l.customer_id = ? LIMIT 1
    ''', [customerId]);
    return r.isEmpty ? null : r.first;
  }

  Future<void> linkSupplier(int customerId, int? supplierId) async {
    final db = await erpDb();
    if (supplierId == null) {
      await db.delete('party_links', where: 'customer_id = ?', whereArgs: [customerId]);
      return;
    }
    await db.rawInsert(
        'INSERT OR REPLACE INTO party_links(customer_id, supplier_id, created_at) VALUES (?, ?, ?)',
        [customerId, supplierId, DateTime.now().toIso8601String()]);
  }
}
