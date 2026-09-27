// lib/erp/accounting_plus/voucher_pdf.dart
//
// 🖨️ طباعة أي سند (بسيط أو مركّب) مع أسطر قيده والمبلغ كتابةً (التفقيط).
// قراءة فقط.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../accounting/screens/acc_ui.dart';
import '../../accounting/vouchers_service.dart';
import '../../services/settings_manager.dart';
import '../arabic_words.dart';
import '../erp_common.dart';
import '../report_export.dart';

String voucherLabel(String? type) {
  if (type == 'compound') return 'سند قيد';
  for (final t in VoucherType.values) {
    if (t.name == type) return voucherTypeLabels[t]!;
  }
  return 'سند';
}

class VoucherPdf {
  VoucherPdf._();

  static Future<void> printVoucher(BuildContext context, int voucherId) async {
    try {
      final bytes = await build(voucherId);
      if (context.mounted) await ReportExport.openPdf(context, bytes, 'سند $voucherId');
    } catch (e) {
      if (context.mounted) showError(context, 'تعذّرت طباعة السند: $e');
    }
  }

  static Future<Uint8List> build(int voucherId) async {
    final db = await erpDb();
    final vr = await db.rawQuery('''
      SELECT v.*, b.name AS box_name, tb.name AS to_box_name, a.name AS account_name
      FROM vouchers v LEFT JOIN cash_boxes b ON b.id = v.cash_box_id
      LEFT JOIN cash_boxes tb ON tb.id = v.to_cash_box_id LEFT JOIN accounts a ON a.id = v.account_id
      WHERE v.id = ?''', [voucherId]);
    if (vr.isEmpty) throw ErpException('السند غير موجود');
    final v = vr.first;
    final lines = await db.rawQuery('''
      SELECT l.debit, l.credit, l.currency, l.fc_amount, l.memo, a.code, a.name
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id JOIN accounts a ON a.id = l.account_id
      WHERE e.source_type = 'voucher' AND e.source_id = ? ORDER BY l.debit DESC, l.id''', [voucherId]);
    final f = await ReportExport.font();
    final settings = await SettingsManager.getAppSettings();
    final shop = settings.invoiceDesign.companyName.trim().isEmpty ? 'الناصر' : settings.invoiceDesign.companyName.trim();
    final branch = settings.branchName.trim();
    const navy = PdfColor.fromInt(0xFF0F3460);
    pw.TextStyle st(double s, {PdfColor? color}) => pw.TextStyle(font: f, fontSize: s, color: color);
    final amount = d0(v['amount']);
    final cur = (v['currency'] as String?) ?? 'IQD';
    final fc = d0(v['fc_amount']);
    final deleted = (v['is_deleted'] as int? ?? 0) == 1;
    final title = voucherLabel(v['voucher_type'] as String?);
    final party = v['voucher_type'] == 'transfer'
        ? '${v['box_name'] ?? ''} ← ${v['to_box_name'] ?? ''}'
        : '${v['account_name'] ?? ''}';

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5.landscape,
      margin: const pw.EdgeInsets.all(18),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: f, bold: f),
      build: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: navy, width: 1.4),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(shop, style: st(18, color: navy)),
              if (branch.isNotEmpty) pw.Text(branch, style: st(10, color: PdfColors.grey700)),
            ]),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              decoration: pw.BoxDecoration(color: deleted ? PdfColors.red : navy, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Text(deleted ? '$title (ملغى)' : title, style: st(17, color: PdfColors.white)),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('رقم: ${v['voucher_number']}', style: st(12)),
              pw.Text('التاريخ: ${fmtDate(parseDate(v['voucher_date']))}', style: st(11)),
              if ((v['reference'] as String?)?.isNotEmpty == true) pw.Text('المرجع: ${v['reference']}', style: st(10)),
            ]),
          ]),
          pw.SizedBox(height: 10),
          if (party.trim().isNotEmpty) pw.Text('الحساب: $party', style: st(12)),
          if (v['box_name'] != null && v['voucher_type'] != 'transfer') pw.Text('الصندوق: ${v['box_name']}', style: st(11)),
          pw.SizedBox(height: 6),
          if (lines.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: ['الرمز', 'الحساب', 'مدين', 'دائن', 'البيان'],
              data: [
                for (final l in lines)
                  [
                    '${l['code']}',
                    '${l['name']}',
                    d0(l['debit']) > 0 ? fmtMoney(d0(l['debit'])) : '',
                    d0(l['credit']) > 0 ? fmtMoney(d0(l['credit'])) : '',
                    '${l['memo'] ?? ''}${l['currency'] != null && l['currency'] != 'IQD' && d0(l['fc_amount']) > 0 ? ' (${fmtMoney(d0(l['fc_amount']))} ${l['currency']})' : ''}',
                  ],
              ],
              headerStyle: st(10, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: navy),
              cellStyle: st(10),
              cellAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            ),
          pw.SizedBox(height: 8),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('المبلغ: ${fmtMoney(amount)} دينار', style: st(14, color: navy)),
            if (cur != 'IQD' && fc > 0) pw.Text('${fmtMoney(fc)} $cur', style: st(12)),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            color: const PdfColor.fromInt(0xFFF1F5FB),
            child: pw.Text(cur != 'IQD' && fc > 0 ? ArabicWords.money(fc, currency: cur) : ArabicWords.money(amount),
                style: st(12)),
          ),
          if ((v['description'] as String?)?.isNotEmpty == true) pw.Text('البيان: ${v['description']}', style: st(11)),
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
            pw.Text('المستلم: ..................', style: st(11)),
            pw.Text('المحاسب: ..................', style: st(11)),
            pw.Text('المدير: ..................', style: st(11)),
          ]),
        ]),
      ),
    ));
    return doc.save();
  }
}
