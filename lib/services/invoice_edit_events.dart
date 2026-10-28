// lib/services/invoice_edit_events.dart
//
// ✏️ تعديل فاتورة محفوظة بالقلم = عملية محاسبية مستقلة بتاريخ يوم التعديل
// (قرار المالك 2026-10-28).
//
// كل حفظ تعديل يغيّر شيئاً له أثر مالي يُسجَّل «حدثاً» فيه حال الفاتورة قبله
// وبعده: المجموع، المقبوض نقداً، الكلفة، الخصم، أجور التحميل، نوع الدفع، والمواد.
//
// كيف يُستعمل الحدث (ولماذا لا يُحسب شيء مرتين):
//   • الدفتر (PostingEngine): قيد الفاتورة بتاريخها = حالها الآن − مجموع فروق
//     أحداثها (أي حالها الأصلية)، وكل حدث قيد منفصل بتاريخه بفرقه وحده.
//     المجموع = حال الفاتورة الآن بالضبط — دائماً، مهما تعددت التعديلات.
//   • التقارير (SalesFacts): الفاتورة تبقى في قائمتها بحالها الآن، ويُضاف لكل
//     حدث سطران: «−الفرق» بتاريخ الفاتورة و«+الفرق» بتاريخ التعديل. في يوم واحد
//     يتلاشيان.
//   • دين العميل لا يمسّه هذا الملف: InvoiceDebtReconciler يسجّل فرق الدين بحركة
//     بتاريخ التعديل أصلاً.
//
// قواعد الأمان:
//   • يُكتب داخل معاملة حفظ الفاتورة نفسها: إما يُحفظ التعديل وحدثه معاً، أو لا شيء.
//   • لا يغيّر رصيداً ولا مخزوناً ولا قيداً — يصف فقط.
//   • تعديلات ما قبل هذه الميزة بلا أحداث: تبقى بتاريخ فاتورتها كما كانت (لا أثر رجعي).
//   • فشل تسجيل الحدث لا يُفشل الحفظ: تعود الفاتورة للسلوك القديم (كل شيء بتاريخها)،
//     وهذا لا يضاعف شيئاً.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';

/// حال فاتورة محاسبياً في لحظة (تُقرأ داخل معاملة الحفظ).
class InvoiceMoneyState {
  InvoiceMoneyState({
    required this.total,
    required this.paid,
    required this.cash,
    required this.cost,
    required this.discount,
    required this.loadingFee,
    required this.paymentType,
    required this.invoiceDate,
    required this.items,
  });

  final double total;

  /// المدفوع على الفاتورة (النقدية = مجموعها) — كما في تقارير المبيعات.
  final double paid;

  /// الجزء النقدي كما يحسبه محرك الترحيل (بلا التسويات).
  final double cash;

  /// الكلفة كما يحسبها محرك الترحيل.
  final double cost;
  final double discount;
  final double loadingFee;
  final String paymentType;
  final String invoiceDate;

  /// بنود الفاتورة (للتقارير: فرق كل مادة).
  final List<Map<String, Object?>> items;
}

class InvoiceEditEvents {
  InvoiceEditEvents._();

  static const String table = 'invoice_edit_events';

  /// أنواع المستند المطبوع للحدث.
  static const kindCashReceipt = 'cash_receipt'; // سند قبض — إضافة على فاتورة نقدية
  static const kindCashRefund = 'cash_refund'; // سند صرف — مرتجع فاتورة نقدية
  static const kindDebitNote = 'debit_note'; // إشعار مدين — إضافة على فاتورة آجلة
  static const kindCreditNote = 'credit_note'; // إشعار دائن — مرتجع فاتورة آجلة

  static const double _eps = 0.005;

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        event_date TEXT NOT NULL,
        invoice_date TEXT,
        total_before REAL NOT NULL DEFAULT 0,
        total_after REAL NOT NULL DEFAULT 0,
        paid_before REAL NOT NULL DEFAULT 0,
        paid_after REAL NOT NULL DEFAULT 0,
        cash_before REAL NOT NULL DEFAULT 0,
        cash_after REAL NOT NULL DEFAULT 0,
        cost_before REAL NOT NULL DEFAULT 0,
        cost_after REAL NOT NULL DEFAULT 0,
        discount_before REAL NOT NULL DEFAULT 0,
        discount_after REAL NOT NULL DEFAULT 0,
        loading_before REAL NOT NULL DEFAULT 0,
        loading_after REAL NOT NULL DEFAULT 0,
        payment_before TEXT,
        payment_after TEXT,
        items_before TEXT,
        items_after TEXT,
        doc_kind TEXT,
        doc_no INTEGER,
        edited_at TEXT,
        summary TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_iee_invoice ON $table(invoice_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_iee_date ON $table(event_date)');
  }

  static Future<bool> exists(DatabaseExecutor db) async {
    final r = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [table]);
    return r.isNotEmpty;
  }

  static double _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);

  /// الجزء النقدي — نفس معادلة محرك الترحيل حرفياً (بلا تسويات الفاتورة).
  static double cashPartOf(String paymentType, double total, double paidOnInvoice) {
    var c = paymentType == 'نقد' ? total : paidOnInvoice;
    if (c > total) c = total;
    if (c < 0) c = 0;
    return c;
  }

  /// المدفوع — نفس SalesInvoiceFact.paid في التقارير.
  static double paidOf(String paymentType, double total, double paidOnInvoice) =>
      paymentType == 'نقد' ? total : (paidOnInvoice > total ? total : paidOnInvoice);

  /// يقرأ حال الفاتورة الآن. [costOf]: دالة كلفة محرك الترحيل (تُمرَّر لتجنّب الاعتماد الدائري).
  static Future<InvoiceMoneyState?> capture(
    DatabaseExecutor db,
    int invoiceId, {
    required Future<double> Function(DatabaseExecutor db, int invoiceId) costOf,
  }) async {
    final r = await db.query('invoices',
        columns: ['total_amount', 'amount_paid_on_invoice', 'discount', 'loading_fee', 'payment_type', 'invoice_date'],
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1);
    if (r.isEmpty) return null;
    final h = r.first;
    final total = _d(h['total_amount']);
    final paidOn = _d(h['amount_paid_on_invoice']);
    final pt = '${h['payment_type'] ?? ''}';
    final items = await db.rawQuery('''
      SELECT product_name, product_id, quantity_individual AS qi, quantity_large_unit AS ql,
             units_in_large_unit AS uilu, actual_cost_price AS actual_cost_per_unit,
             applied_price AS selling_price, sale_type, item_total
      FROM invoice_items WHERE invoice_id = ? ORDER BY id''', [invoiceId]);
    return InvoiceMoneyState(
      total: total,
      paid: paidOf(pt, total, paidOn),
      cash: cashPartOf(pt, total, paidOn),
      cost: await costOf(db, invoiceId),
      discount: _d(h['discount']),
      loadingFee: _d(h['loading_fee']),
      paymentType: pt,
      invoiceDate: '${h['invoice_date'] ?? ''}',
      items: [for (final it in items) Map<String, Object?>.from(it)],
    );
  }

  /// بصمة المواد بلا ترتيب الأسطر (إعادة ترتيب الأسطر وحدها ليست تعديلاً).
  static String _itemsSig(List<Map<String, Object?>> items) {
    final rows = [
      for (final it in items)
        jsonEncode([it['product_name'], it['sale_type'], _d(it['qi']), _d(it['ql']), _d(it['uilu']), _d(it['item_total'])])
    ]..sort();
    return rows.join('|');
  }

  /// نوع المستند حسب نوع الدفع بعد التعديل وإشارة فرق المجموع (null = لا فرق في المجموع).
  static String? docKindFor(String paymentAfter, double totalDelta) {
    if (totalDelta.abs() < 0.5) return null;
    final cash = paymentAfter == 'نقد';
    if (totalDelta > 0) return cash ? kindCashReceipt : kindDebitNote;
    return cash ? kindCashRefund : kindCreditNote;
  }

  /// يسجّل الحدث إن تغيّر ما له أثر مالي. يعيد معرّفه أو null. داخل معاملة الحفظ.
  static Future<int?> record(
    DatabaseExecutor txn, {
    required int invoiceId,
    required InvoiceMoneyState before,
    required InvoiceMoneyState after,
    String? user,
    String? summary,
  }) async {
    final changed = (after.total - before.total).abs() >= _eps ||
        (after.cash - before.cash).abs() >= _eps ||
        (after.cost - before.cost).abs() >= _eps ||
        (after.paid - before.paid).abs() >= _eps ||
        after.paymentType != before.paymentType ||
        _itemsSig(after.items) != _itemsSig(before.items);
    if (!changed) return null;
    await ensure(txn);
    String? editedAt;
    try {
      final r = await txn.rawQuery('SELECT MAX(edited_at) AS t FROM invoice_edit_changes WHERE invoice_id = ?', [invoiceId]);
      editedAt = r.first['t'] as String?;
    } catch (_) {}
    final kind = docKindFor(after.paymentType, after.total - before.total);
    int? docNo;
    if (kind != null) {
      final n = await txn.rawQuery('SELECT COALESCE(MAX(doc_no), 0) + 1 AS n FROM $table WHERE doc_kind = ?', [kind]);
      docNo = (n.first['n'] as num).toInt();
    }
    final now = DateTime.now().toIso8601String();
    return txn.insert(table, {
      'invoice_id': invoiceId,
      'event_date': now,
      'invoice_date': before.invoiceDate,
      'total_before': before.total,
      'total_after': after.total,
      'paid_before': before.paid,
      'paid_after': after.paid,
      'cash_before': before.cash,
      'cash_after': after.cash,
      'cost_before': before.cost,
      'cost_after': after.cost,
      'discount_before': before.discount,
      'discount_after': after.discount,
      'loading_before': before.loadingFee,
      'loading_after': after.loadingFee,
      'payment_before': before.paymentType,
      'payment_after': after.paymentType,
      'items_before': jsonEncode(before.items),
      'items_after': jsonEncode(after.items),
      'doc_kind': kind,
      'doc_no': docNo,
      'edited_at': editedAt,
      'summary': summary,
      'created_by': user,
      'created_at': now,
    });
  }

  /// قراءة حدث واحد.
  static Future<Map<String, Object?>?> byId(DatabaseExecutor db, int id) async {
    try {
      final r = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
      return r.isEmpty ? null : r.first;
    } catch (e) {
      debugPrint('⚠️ InvoiceEditEvents.byId: $e');
      return null;
    }
  }

  static List<Map<String, Object?>> decodeItems(Object? json) {
    if (json == null) return const [];
    try {
      final v = jsonDecode('$json');
      if (v is! List) return const [];
      return [for (final e in v) if (e is Map) Map<String, Object?>.from(e)];
    } catch (_) {
      return const [];
    }
  }
}
