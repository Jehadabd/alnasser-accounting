// lib/screens/statements/statement_pdf.dart
//
// 🖨️ طباعة كشف الحساب والكشف التجاري (PDF بترويسة المحل نفسها).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/logo_service.dart';
import '../../services/pdf_header.dart';
import '../../services/settings_manager.dart';
import '../../services/invoice_edit_log.dart';
import 'statement_engine.dart';

final _nf = NumberFormat('#,##0', 'en_US');
String _n(num v) => v < 0 ? '(${_nf.format(v.abs())})' : _nf.format(v);
String _q(num v) => NumberFormat('#,##0.###', 'en_US').format(v);

class _Fonts {
  final pw.Font body;
  final pw.Font brand;
  _Fonts(this.body, this.brand);
}

Future<_Fonts> _fonts() async => _Fonts(
      pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF')),
    );

pw.Widget _cell(String t, pw.Font f, {double size = 8, bool bold = false, pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Text(t,
          style: pw.TextStyle(font: f, fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null, color: color),
          textAlign: align),
    );

Future<pw.Widget> _header(_Fonts f, String title, String customer, String period) async {
  final app = await SettingsManager.getAppSettings();
  final logo = await LogoService.getLogoImage(appSettings: app);
  final now = DateTime.now();
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    buildPdfHeader(f.body, f.brand, logo, appSettings: app, logoSize: 90),
    pw.SizedBox(height: 4),
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(title, style: pw.TextStyle(font: f.body, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.Text('السيد: $customer', style: pw.TextStyle(font: f.body, fontSize: 11)),
        pw.Text('${now.year}/${now.month}/${now.day}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            style: pw.TextStyle(font: f.body, fontSize: 9)),
      ]),
    ),
    pw.SizedBox(height: 2),
    pw.Text('الفترة: $period', style: pw.TextStyle(font: f.body, fontSize: 9, color: PdfColors.grey700)),
    pw.SizedBox(height: 4),
  ]);
}

pw.Widget _footer(pw.Context c, _Fonts f) => pw.Align(
      alignment: pw.Alignment.center,
      child: pw.Text('صفحة ${c.pageNumber} من ${c.pagesCount}',
          style: pw.TextStyle(font: f.body, fontSize: 8, color: PdfColors.grey)),
    );

String _invoiceBody(StmtRow r) {
  final inv = r.invoice!;
  final b = StringBuffer();
  for (final l in inv.lines) {
    b.writeln('• ${l.name}  ${_q(l.qty)} ${l.unit} × ${_n(l.price)} = ${_n(l.total)}');
  }
  if (inv.discount > 0) b.writeln('• خصم ${_n(inv.discount)}');
  if (inv.loadingFee > 0) b.writeln('• أجور ${_n(inv.loadingFee)}');
  for (final e in inv.edits.reversed) {
    final sign = e.amountDelta >= 0 ? '+' : '-';
    b.writeln('- ${e.kind}: ${e.productName} من ${_q(e.qtyBefore)} إلى ${_q(e.qtyAfter)}  $sign${_nf.format(e.amountDelta.abs())}');
  }
  return b.toString().trimRight();
}

/// كشف الحساب (شامل/من آخر صفر/فترة × تفصيلي/ملخص)
Future<Uint8List> buildAccountStatementPdf(StatementResult s) async {
  final f = await _fonts();
  final title = s.detail == StmtDetail.summary ? 'كشف حساب (ملخص)' : 'كشف حساب (تفصيلي)';
  final head = await _header(f, title, s.customerName, s.periodText);
  final pdf = pw.Document();
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(14),
    textDirection: pw.TextDirection.rtl,
    header: (c) => c.pageNumber == 1 ? head : pw.SizedBox(),
    footer: (c) => _footer(c, f),
    build: (c) => [
      pw.Table(
        border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey600),
        columnWidths: const {
          0: pw.FixedColumnWidth(62),
          1: pw.FixedColumnWidth(58),
          2: pw.FixedColumnWidth(58),
          3: pw.FlexColumnWidth(),
          4: pw.FixedColumnWidth(54),
          5: pw.FixedColumnWidth(22),
        },
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
            _cell('الرصيد', f.body, bold: true, size: 9),
            _cell('تسديد', f.body, bold: true, size: 9),
            _cell('دين', f.body, bold: true, size: 9),
            _cell('البيان', f.body, bold: true, size: 9),
            _cell('التاريخ', f.body, bold: true, size: 9),
            _cell('ت', f.body, bold: true, size: 9),
          ]),
          pw.TableRow(children: [
            _cell(_n(s.opening), f.body, bold: true),
            _cell('', f.body),
            _cell('', f.body),
            _cell('الرصيد في بداية الفترة', f.body, bold: true, align: pw.TextAlign.right),
            _cell(s.fromDate == null ? '' : stmtDate(s.fromDate!), f.body),
            _cell('', f.body),
          ]),
          for (var i = 0; i < s.rows.length; i++)
            pw.TableRow(children: [
              _cell(_n(s.rows[i].balanceAfter), f.body),
              _cell(s.rows[i].amount < 0 ? _nf.format(-s.rows[i].amount) : '', f.body, color: PdfColors.green800),
              _cell(s.rows[i].amount > 0 ? _nf.format(s.rows[i].amount) : '', f.body, color: PdfColors.red800),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(s.rows[i].title, style: pw.TextStyle(font: f.body, fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  if ((s.rows[i].note ?? '').isNotEmpty)
                    pw.Text(s.rows[i].note!, style: pw.TextStyle(font: f.body, fontSize: 7.5, color: PdfColors.grey800)),
                  if (s.detail == StmtDetail.detailed && s.rows[i].showInvoiceBody && s.rows[i].invoice != null)
                    pw.Text(_invoiceBody(s.rows[i]), style: pw.TextStyle(font: f.body, fontSize: 7, color: PdfColors.grey800)),
                ]),
              ),
              _cell(stmtDate(s.rows[i].date), f.body),
              _cell('${i + 1}', f.body),
            ]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('بداية الفترة: ${_n(s.opening)}', style: pw.TextStyle(font: f.body, fontSize: 10)),
          pw.Text('دين: ${_n(s.debit)}', style: pw.TextStyle(font: f.body, fontSize: 10, color: PdfColors.red800)),
          pw.Text('تسديد: ${_n(s.credit)}', style: pw.TextStyle(font: f.body, fontSize: 10, color: PdfColors.green800)),
          pw.Text('الرصيد المستحق: ${_n(s.closing)} دينار',
              style: pw.TextStyle(font: f.body, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
    ],
  ));
  return pdf.save();
}

/// الكشف التجاري لصاحب المتجر
Future<Uint8List> buildCommercialStatementPdf(CommercialResult r) async {
  final f = await _fonts();
  final head = await _header(f, 'الكشف التجاري', r.customerName, r.periodText);
  pw.Widget kv(String k, String v, {bool bold = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: pw.TextStyle(font: f.body, fontSize: 9.5))),
          pw.Text(v,
              style: pw.TextStyle(font: f.body, fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null, color: color)),
        ]),
      );
  pw.Widget box(String title, List<pw.Widget> children) => pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey600)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(title, style: pw.TextStyle(font: f.body, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Divider(height: 4, thickness: 0.4),
          ...children,
        ]),
      );
  pw.Widget invTable(String title, List<StmtInvoice> list) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.SizedBox(height: 8),
        pw.Text('$title (${list.length})', style: pw.TextStyle(font: f.body, fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        if (list.isEmpty)
          pw.Text('لا توجد', style: pw.TextStyle(font: f.body, fontSize: 9, color: PdfColors.grey))
        else
          pw.Table(
            border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey600),
            columnWidths: const {
              0: pw.FixedColumnWidth(60),
              1: pw.FixedColumnWidth(60),
              2: pw.FixedColumnWidth(60),
              3: pw.FixedColumnWidth(70),
              4: pw.FixedColumnWidth(36),
              5: pw.FixedColumnWidth(54),
              6: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
                _cell('المتبقي', f.body, bold: true),
                _cell('المسدد عليها', f.body, bold: true),
                _cell('مرتجع/إضافة', f.body, bold: true),
                _cell('الإجمالي', f.body, bold: true),
                _cell('مواد', f.body, bold: true),
                _cell('التاريخ', f.body, bold: true),
                _cell('رقم الفاتورة', f.body, bold: true),
              ]),
              for (final i in list)
                pw.TableRow(children: [
                  _cell(i.isDebt ? _nf.format(i.remaining) : '—', f.body),
                  _cell(i.isDebt ? _nf.format(i.paid) : _nf.format(i.total), f.body),
                  _cell(
                      [
                        if (i.editReturns > 0) '-${_nf.format(i.editReturns)}',
                        if (i.editAdds > 0) '+${_nf.format(i.editAdds)}',
                      ].join(' '),
                      f.body),
                  _cell(_nf.format(i.total), f.body, bold: true),
                  _cell('${i.lines.length}', f.body),
                  _cell(stmtDate(i.date), f.body),
                  _cell(i.number, f.body, align: pw.TextAlign.right),
                ]),
            ],
          ),
      ]);

  final pdf = pw.Document();
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(14),
    textDirection: pw.TextDirection.rtl,
    header: (c) => c.pageNumber == 1 ? head : pw.SizedBox(),
    footer: (c) => _footer(c, f),
    build: (c) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: box('سحب بالدين', [
            kv('فواتير بالدين (${r.debtInvoices.length})', _n(r.debtInvoicesTotal)),
            kv('  منها مسدد على الفواتير نفسها', _n(r.debtInvoicesPaid)),
            kv('  المتبقي منها على الحساب', _n(r.debtInvoicesRemaining)),
            kv('معاملات دين يدوية (${r.manualDebtCount})', _n(r.manualDebt)),
          ]),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: box('سحب بالنقد', [
            kv('فواتير نقد (${r.cashInvoices.length})', _n(r.cashInvoicesTotal)),
            kv('معاملات نقد يدوية', 'لا يوجد'),
          ]),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: box('ما نزل من حسابه', [
            kv('تسديدات (${r.paymentCount})', _n(r.payments)),
            if (r.discounts > 0) kv('خصومات', _n(r.discounts)),
            if (r.returnsCredit > 0) kv('مرتجعات من الحساب', _n(r.returnsCredit)),
            if (r.otherCount > 0) kv('تصحيحات وأرصدة (${r.otherCount})', _n(r.other)),
          ]),
        ),
      ]),
      pw.SizedBox(height: 6),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('مجموع المسحوب: ${_n(r.totalWithdrawn)}', style: pw.TextStyle(font: f.body, fontSize: 10)),
          pw.Text('بداية الفترة: ${_n(r.opening)}', style: pw.TextStyle(font: f.body, fontSize: 10)),
          pw.Text('الرصيد المستحق: ${_n(r.closing)} دينار',
              style: pw.TextStyle(font: f.body, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
      if (r.editReturns > 0 || r.editAdds > 0 || r.cashReturnsCount > 0)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            [
              if (r.editReturns > 0) 'مرتجعات بتعديل الفواتير: ${_n(r.editReturns)} (محسوبة ضمن إجمالي الفواتير)',
              if (r.editAdds > 0) 'إضافات بتعديل الفواتير: ${_n(r.editAdds)}',
              if (r.cashReturnsCount > 0) 'مرتجع نقداً من الصندوق (${r.cashReturnsCount}): ${_n(r.cashReturns)}',
            ].join('   •   '),
            style: pw.TextStyle(font: f.body, fontSize: 8.5, color: PdfColors.grey800),
          ),
        ),
      invTable('فواتير الدين', r.debtInvoices),
      invTable('فواتير النقد', r.cashInvoices),
    ],
  ));
  return pdf.save();
}

/// فتح الملف: ويندوز يحفظ في المستندات ويفتحه، غيره نافذة الطباعة.
Future<String?> deliverStatementPdf(Uint8List bytes, String baseName) async {
  final safe = baseName.replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
  final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
  final name = '${safe}_$stamp.pdf';
  if (kIsWeb) {
    await Printing.sharePdf(bytes: bytes, filename: name);
    return null;
  }
  if (Platform.isWindows) {
    final dir = Directory('${Platform.environment['USERPROFILE']}/Documents/account_statements');
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(bytes);
    await Process.start('cmd', ['/c', 'start', '/min', '', path]);
    return path;
  }
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  return null;
}

// يستعمله الكشف للتسمية فقط
String editKindLabel(String k) => k == InvoiceEditLog.kindPrice ? 'تعديل سعر' : k;
