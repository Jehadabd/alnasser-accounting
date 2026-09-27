// lib/erp/sales/doc_pdf.dart
//
// 🖨️ طباعة المستندات التجارية (عرض سعر، طلب، مرتجع، مستند مخزني) بتصميم موحّد.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../accounting/screens/acc_ui.dart';
import '../../services/settings_manager.dart';
import '../arabic_words.dart';
import '../report_export.dart';

class DocPdf {
  DocPdf._();

  static Future<Uint8List> build({
    required String title,
    required String number,
    required DateTime date,
    required String partyLabel,
    required String partyName,
    String? partyExtra,
    List<MapEntry<String, String>> infos = const [],
    required List<String> headers,
    required List<List<String>> rows,
    required double total,
    double discount = 0,
    String? notes,
    String? terms,
    bool showWords = true,
    String currency = 'IQD',
  }) async {
    final f = await ReportExport.font();
    final settings = await SettingsManager.getAppSettings();
    final branch = settings.branchName.trim();
    final shopName = settings.invoiceDesign.companyName.trim().isEmpty ? 'الناصر' : settings.invoiceDesign.companyName.trim();
    const navy = PdfColor.fromInt(0xFF0F3460);
    const cyan = PdfColor.fromInt(0xFF00B4D8);
    pw.TextStyle st(double s, {PdfColor? c}) => pw.TextStyle(font: f, fontSize: s, color: c);
    final net = total - discount;
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: f, bold: f),
      header: (ctx) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(shopName, style: st(24, c: navy)),
            if (branch.isNotEmpty) pw.Text(branch, style: st(10, c: PdfColors.grey700)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: pw.BoxDecoration(color: navy, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text(title, style: st(16, c: PdfColors.white)),
            ),
            pw.SizedBox(height: 4),
            pw.Text('رقم: $number', style: st(11)),
            pw.Text('التاريخ: ${fmtDate(date)}', style: st(11)),
          ]),
        ]),
        pw.Container(height: 2, color: cyan, margin: const pw.EdgeInsets.symmetric(vertical: 8)),
      ]),
      footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('شكراً لتعاملكم معنا', style: st(9, c: PdfColors.grey600)),
        pw.Text('صفحة ${ctx.pageNumber} / ${ctx.pagesCount}', style: st(9, c: PdfColors.grey600)),
      ]),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF3F6FA),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('$partyLabel: $partyName', style: st(13)),
              if (partyExtra != null && partyExtra.isNotEmpty) pw.Text(partyExtra, style: st(10, c: PdfColors.grey700)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              for (final i in infos) pw.Text('${i.key}: ${i.value}', style: st(10)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: st(10, c: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: navy),
          cellStyle: st(10),
          cellAlignment: pw.Alignment.centerRight,
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F9FC)),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        ),
        pw.SizedBox(height: 10),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Container(
            width: 220,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: navy), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              _kv('الإجمالي', fmtMoney(total), st(11)),
              if (discount > 0) _kv('الحسم', fmtMoney(discount), st(11)),
              pw.Divider(color: PdfColors.grey400),
              _kv('الصافي', fmtMoney(net), st(13, c: navy)),
            ]),
          ),
        ]),
        if (showWords) ...[
          pw.SizedBox(height: 6),
          pw.Text(ArabicWords.money(net, currency: currency), style: st(11)),
        ],
        if (notes != null && notes.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('ملاحظات: $notes', style: st(10)),
        ],
        if (terms != null && terms.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text('الشروط: $terms', style: st(10, c: PdfColors.grey800)),
        ],
      ],
    ));
    return doc.save();
  }

  static pw.Widget _kv(String k, String v, pw.TextStyle s) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(k, style: s), pw.Text(v, style: s)],
      );
}
