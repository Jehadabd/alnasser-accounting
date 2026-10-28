// lib/services/edit_return_doc.dart
// ↩️ «مستند مرتجع» لما حُذف أو نقص من فاتورة آجلة بتعديلها بعد الحفظ.
//
// الفاتورة النقدية لها «سند صرف — مرتجع بضاعة» (InvoiceEditVoucher). الآجلة لم
// يكن لها مستند يُطبع: المبلغ يُنزل من دين العميل مع الحفظ. هذا المستند يعرض
// المواد المُرجعة ومبلغها كما يعرضها مستند «مرتجع من هذه الفاتورة».
//
// طباعة فقط — لا يغيّر رصيداً ولا مخزوناً (الأثر حدث مع حفظ الفاتورة).
// رسالة الطباعة تتبع الإعداد نفسه: اسألني / اطبع دائماً / لا تُظهر.

import 'package:flutter/material.dart';

import '../erp/report_export.dart';
import '../erp/sales/doc_pdf.dart';
import 'database_service.dart';
import 'invoice_edit_log.dart';
import 'settings_manager.dart';

class EditReturnDoc {
  EditReturnDoc._();

  /// بعد حفظ تعديل فاتورة آجلة: ما أُرجع في هذا الحفظ (منذ [since]) يُعرض للطباعة.
  static Future<void> offer(BuildContext context, {required int invoiceId, required DateTime since}) async {
    final db = await DatabaseService().database;
    await InvoiceEditLog.ensure(db);
    final rows = await db.rawQuery('''
      SELECT c.*, i.invoice_number, i.customer_name
      FROM invoice_edit_changes c JOIN invoices i ON i.id = c.invoice_id
      WHERE c.invoice_id = ? AND c.kind = ? AND c.edited_at >= ?
        AND c.amount_before - c.amount_after > 0.004
      ORDER BY c.id''', [invoiceId, InvoiceEditLog.kindReturn, since.toIso8601String()]);
    if (rows.isEmpty || !context.mounted) return;

    final mode = (await SettingsManager.getAppSettings()).adjustmentVoucherMode;
    if (mode == 'never' || !context.mounted) return;
    final total = rows.fold<double>(0, (s, r) => s + InvoiceEditLog.returnedAmount(r));
    if (mode != 'always') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('طباعة مستند المرتجع؟'),
          content: Text('أُرجعت ${rows.length} مادة بمبلغ ${_money(total)} دينار، أُنزل من دين العميل.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.print_rounded),
              label: const Text('طباعة'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }

    final first = rows.first;
    final n = (first['invoice_number'] as String?)?.trim();
    final invNo = (n != null && n.isNotEmpty) ? n : '#$invoiceId';
    final bytes = await DocPdf.build(
      title: 'مرتجع مبيعات (تعديل فاتورة)',
      number: invNo,
      date: DateTime.tryParse('${first['edited_at']}') ?? DateTime.now(),
      partyLabel: 'الزبون',
      partyName: '${first['customer_name'] ?? ''}',
      infos: [
        const MapEntry('طريقة الرد', 'من الحساب (ينقص الدين)'),
        MapEntry('الفاتورة الأصلية', invNo),
      ],
      headers: const ['#', 'المادة', 'الوحدة', 'الكمية المُرجعة', 'المبلغ'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            '${i + 1}',
            '${rows[i]['product_name']}',
            '${rows[i]['unit'] ?? ''}',
            _qty(((rows[i]['qty_before'] as num?)?.toDouble() ?? 0) - ((rows[i]['qty_after'] as num?)?.toDouble() ?? 0)),
            _money(InvoiceEditLog.returnedAmount(rows[i])),
          ],
      ],
      total: total,
    );
    if (context.mounted) await ReportExport.openPdf(context, bytes, 'مرتجع فاتورة $invNo');
  }

  static String _money(double v) => v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  static String _qty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
