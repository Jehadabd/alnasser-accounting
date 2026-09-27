// lib/erp/debts/receipt_pdf.dart
//
// 🖨️ طباعة وصل القبض بالمبلغ كتابةً (التفقيط).

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../accounting/screens/acc_ui.dart';
import '../../services/settings_manager.dart';
import '../arabic_words.dart';
import '../erp_common.dart';
import '../report_export.dart';

class ReceiptPdf {
  ReceiptPdf._();

  static Future<Uint8List> build({
    required String title,
    required int number,
    required DateTime date,
    required String boxName,
    required String currency,
    required double fxRate,
    required List<Map<String, Object?>> lines, // customer_name, amount, discount, fc_amount, balance_before, balance_after
    String? docNo,
    String? notes,
    double commission = 0,
  }) async {
    final f = await ReportExport.font();
    final settings = await SettingsManager.getAppSettings();
    final branch = settings.branchName.trim();
    final shopName = settings.invoiceDesign.companyName.trim().isEmpty ? 'الناصر' : settings.invoiceDesign.companyName.trim();
    final isBase = currency == 'IQD';
    final total = lines.fold<double>(0, (s, l) => s + d0(l['amount']));
    final totalFc = lines.fold<double>(0, (s, l) => s + d0(l['fc_amount']));
    final totalDisc = lines.fold<double>(0, (s, l) => s + d0(l['discount']));
    pw.TextStyle st(double size, {PdfColor? color}) => pw.TextStyle(font: f, fontSize: size, color: color);
    const navy = PdfColor.fromInt(0xFF0F3460);

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
              pw.Text(shopName, style: st(20, color: navy)),
              if (branch.isNotEmpty) pw.Text(branch, style: st(10, color: PdfColors.grey700)),
            ]),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              decoration: pw.BoxDecoration(color: navy, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Text(title, style: st(18, color: PdfColors.white)),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('رقم: $number', style: st(12)),
              pw.Text('التاريخ: ${fmtDate(date)}', style: st(11)),
              if (docNo != null && docNo.isNotEmpty) pw.Text('المستند: $docNo', style: st(10)),
            ]),
          ]),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'العميل',
              if (!isBase) 'المبلغ ($currency)',
              'المبلغ (دينار)',
              'الحسم',
              'الرصيد قبل',
              'الرصيد بعد',
            ],
            data: [
              for (final l in lines)
                [
                  '${l['customer_name'] ?? ''}',
                  if (!isBase) fmtMoney(d0(l['fc_amount'])),
                  fmtMoney(d0(l['amount'])),
                  fmtMoney(d0(l['discount'])),
                  l['balance_before'] == null ? '' : fmtMoney(d0(l['balance_before'])),
                  l['balance_after'] == null ? '' : fmtMoney(d0(l['balance_after'])),
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
            pw.Text('الصندوق: $boxName', style: st(11)),
            if (!isBase) pw.Text('سعر التعادل: ${fmtMoney(fxRate)}', style: st(11)),
            pw.Text('المجموع: ${fmtMoney(total)} دينار', style: st(13, color: navy)),
            if (totalDisc > 0) pw.Text('الحسم: ${fmtMoney(totalDisc)}', style: st(11)),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            color: const PdfColor.fromInt(0xFFF1F5FB),
            child: pw.Text(
                isBase ? ArabicWords.money(total) : ArabicWords.money(totalFc, currency: currency),
                style: st(12)),
          ),
          if (commission > 0) pw.Text('عمولة التحصيل: ${fmtMoney(commission)}', style: st(10)),
          if (notes != null && notes.isNotEmpty) pw.Text('البيان: $notes', style: st(10)),
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
            pw.Text('توقيع المستلم: ..................', style: st(11)),
            pw.Text('توقيع المحاسب: ..................', style: st(11)),
          ]),
        ]),
      ),
    ));
    return doc.save();
  }
}
