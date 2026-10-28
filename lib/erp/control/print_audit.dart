// lib/erp/control/print_audit.dart
//
// 🖨️ تتبّع طباعة الفواتير، وكشف «فاتورة طُبعت ثم أُنقصت».
//
// النمط الذي يكشفه: تُطبع الفاتورة ويُستلم ثمنها كاملاً، ثم تُعدَّل لاحقاً فينقص
// مجموعها أو نقدها، ويذهب الفرق خارج الصندوق. أحداث التعديل (invoice_edit_events)
// تحفظ «قبل/بعد» لكل تعديل، وهذا الملف يضيف «متى طُبعت ومن طبعها».
// لا يغيّر شيئاً — يسجّل ويقرأ فقط. فشل التسجيل لا يوقف الطباعة.

import 'package:flutter/foundation.dart' show debugPrint;

import '../../services/invoice_edit_events.dart';
import '../erp_common.dart';
import 'control_common.dart';

class PrintAudit {
  PrintAudit._();

  /// يسجّل طباعة فاتورة محفوظة. [kind]: a4 | roll | share.
  static Future<void> record(int? invoiceId, {String kind = 'a4'}) async {
    if (invoiceId == null || invoiceId <= 0) return;
    try {
      final db = await controlDb();
      final ok = await db.query('invoices', columns: ['id'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (ok.isEmpty) return;
      await db.insert('invoice_prints', {
        'invoice_id': invoiceId,
        'printed_at': DateTime.now().toIso8601String(),
        'printed_by': currentUserName(),
        'kind': kind,
      });
    } catch (e) {
      debugPrint('⚠️ تسجيل طباعة الفاتورة: $e');
    }
  }

  static Future<int> printCount(int invoiceId) async {
    try {
      final db = await controlDb();
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM invoice_prints WHERE invoice_id = ?', [invoiceId]);
      return ((r.first['n'] as num?) ?? 0).toInt();
    } catch (_) {
      return 0;
    }
  }
}

/// تعديل أنقص فاتورة.
class ReducingEdit {
  ReducingEdit.fromRow(Map<String, Object?> r)
      : eventId = r['id'] as int,
        invoiceId = r['invoice_id'] as int,
        invoiceNo = r['invoice_number'] as String?,
        customer = (r['customer_name'] as String?) ?? '',
        invoiceDate = parseDate(r['invoice_date']),
        editedAt = parseDate(r['edited_at'] ?? r['created_at']),
        editedBy = (r['created_by'] as String?) ?? '—',
        totalBefore = d0(r['total_before']),
        totalAfter = d0(r['total_after']),
        cashBefore = d0(r['cash_before']),
        cashAfter = d0(r['cash_after']),
        paymentBefore = (r['payment_before'] as String?) ?? '',
        paymentAfter = (r['payment_after'] as String?) ?? '',
        firstPrintAt = r['first_print'] == null ? null : parseDate(r['first_print']),
        firstPrintBy = r['first_print_by'] as String?,
        printsBefore = ((r['prints_before'] as num?) ?? 0).toInt();

  final int eventId;
  final int invoiceId;
  final String? invoiceNo;
  final String customer;
  final DateTime invoiceDate;
  final DateTime editedAt;
  final String editedBy;
  final double totalBefore;
  final double totalAfter;
  final double cashBefore;
  final double cashAfter;
  final String paymentBefore;
  final String paymentAfter;
  final DateTime? firstPrintAt;
  final String? firstPrintBy;
  final int printsBefore;

  double get totalDrop => totalBefore - totalAfter;
  double get cashDrop => cashBefore - cashAfter;

  /// ما خرج من الصندوق فعلاً بهذا التعديل (أكبر الهبوطين).
  double get drop => cashDrop > totalDrop ? cashDrop : totalDrop;
  bool get afterPrint => printsBefore > 0;
  bool get cashToCredit => paymentBefore == 'نقد' && paymentAfter != 'نقد';
}

class EditorSummary {
  EditorSummary(this.user);
  final String user;
  int edits = 0;
  int afterPrint = 0;
  double drop = 0;
  double dropAfterPrint = 0;
}

class ReducingEditsReport {
  ReducingEditsReport._();

  /// كل تعديل أنقص مجموع الفاتورة أو نقدها، مع حالة طباعتها قبل التعديل.
  static Future<List<ReducingEdit>> load({required DateTime from, required DateTime to}) async {
    final db = await controlDb();
    if (!await InvoiceEditEvents.exists(db)) return const [];
    final rows = await db.rawQuery('''
      SELECT e.*, i.invoice_number, i.customer_name,
             (SELECT MIN(p.printed_at) FROM invoice_prints p
               WHERE p.invoice_id = e.invoice_id AND p.printed_at < COALESCE(e.edited_at, e.created_at)) AS first_print,
             (SELECT p.printed_by FROM invoice_prints p
               WHERE p.invoice_id = e.invoice_id AND p.printed_at < COALESCE(e.edited_at, e.created_at)
               ORDER BY p.printed_at LIMIT 1) AS first_print_by,
             (SELECT COUNT(*) FROM invoice_prints p
               WHERE p.invoice_id = e.invoice_id AND p.printed_at < COALESCE(e.edited_at, e.created_at)) AS prints_before
      FROM ${InvoiceEditEvents.table} e
      LEFT JOIN invoices i ON i.id = e.invoice_id
      WHERE e.event_date >= ? AND e.event_date < ?
        AND (e.total_after < e.total_before - 0.5 OR e.cash_after < e.cash_before - 0.5)
      ORDER BY e.event_date DESC, e.id DESC''', [isoDay(from), isoDayAfter(to)]);
    return rows.map(ReducingEdit.fromRow).toList();
  }

  static List<EditorSummary> byUser(List<ReducingEdit> edits) {
    final m = <String, EditorSummary>{};
    for (final e in edits) {
      final s = m.putIfAbsent(e.editedBy, () => EditorSummary(e.editedBy));
      s.edits++;
      s.drop += e.drop;
      if (e.afterPrint) {
        s.afterPrint++;
        s.dropAfterPrint += e.drop;
      }
    }
    return m.values.toList()..sort((a, b) => b.dropAfterPrint.compareTo(a.dropAfterPrint));
  }
}
