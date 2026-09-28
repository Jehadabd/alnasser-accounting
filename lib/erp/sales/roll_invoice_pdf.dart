// lib/erp/sales/roll_invoice_pdf.dart
//
// 🧾 فاتورة بحجم الطابعة الحرارية 80mm (مثل خيار الطباعة الافتراضية في سهل).
// تُختار من «إعدادات الطباعة»؛ الكميات الكسرية (أمتار، كيلو) تُطبع كما هي.
// طباعة فقط — لا تغيّر شيئاً.

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart';
import '../../models/invoice_item.dart';
import '../../services/settings_manager.dart';
import '../arabic_words.dart';
import '../erp_common.dart';
import '../report_export.dart';

/// إعداد نوع طباعة فاتورة البيع: a4 (الافتراضي) أو 80mm.
class InvoicePrintFormat {
  InvoicePrintFormat._();
  static const String key = 'invoice_print_format';

  static Future<String> get() async {
    try {
      final db = await erpDb();
      return (await Ledger.getSetting(db, key)) ?? 'a4';
    } catch (_) {
      return 'a4';
    }
  }

  static Future<void> set(String v) async {
    final db = await erpDb();
    await Ledger.setSetting(db, key, v);
  }
}

class RollInvoicePdf {
  RollInvoicePdf._();

  static double _qty(InvoiceItem i) {
    final l = i.quantityLargeUnit ?? 0;
    if (l > 0) return l;
    return i.quantityIndividual ?? 0;
  }

  static Future<pw.Document> build({
    required List<InvoiceItem> items,
    required String customerName,
    required DateTime date,
    required double discount,
    required double loadingFee,
    required double paid,
    required String paymentType,
    String? invoiceNumber,
  }) async {
    final f = await ReportExport.font();
    final settings = await SettingsManager.getAppSettings();
    final shop = settings.invoiceDesign.companyName.trim().isEmpty ? 'الناصر' : settings.invoiceDesign.companyName.trim();
    final branch = settings.branchName.trim();
    final gross = items.fold<double>(0, (s, i) => s + i.itemTotal);
    final total = roundMoney(gross + loadingFee - discount);
    final isCash = paymentType == 'نقد';
    final paidShown = isCash ? total : paid;
    pw.TextStyle st(double s, {bool bold = false}) =>
        pw.TextStyle(font: f, fontSize: s, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    pw.Widget kv(String k, String v, {double size = 9, bool bold = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [pw.Text(k, style: st(size, bold: bold)), pw.Text(v, style: st(size, bold: bold))],
        );
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 8, marginRight: 8, marginTop: 8, marginBottom: 8),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: f, bold: f),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Center(child: pw.Text(shop, style: st(14, bold: true))),
        if (branch.isNotEmpty) pw.Center(child: pw.Text(branch, style: st(9))),
        pw.SizedBox(height: 4),
        kv('فاتورة', invoiceNumber ?? '-'),
        kv('التاريخ', '${fmtDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'),
        if (customerName.trim().isNotEmpty) kv('الزبون', customerName),
        pw.Divider(thickness: .6),
        for (final i in items) ...[
          pw.Text(i.productName, style: st(9, bold: true)),
          kv('${fmtQty(_qty(i))} ${i.saleType ?? ''} × ${fmtMoney(i.appliedPrice)}', fmtMoney(i.itemTotal)),
          pw.SizedBox(height: 2),
        ],
        pw.Divider(thickness: .6),
        kv('المجموع', fmtMoney(gross)),
        if (loadingFee > 0) kv('أجور التحميل', fmtMoney(loadingFee)),
        if (discount > 0) kv('الخصم', fmtMoney(discount)),
        kv('الصافي', fmtMoney(total), size: 12, bold: true),
        kv('المدفوع', fmtMoney(paidShown)),
        if (total - paidShown > 0.004) kv('المتبقي', fmtMoney(total - paidShown), bold: true),
        pw.SizedBox(height: 4),
        pw.Text(ArabicWords.money(total), style: st(8)),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('شكراً لتعاملكم معنا', style: st(9))),
      ]),
    ));
    return doc;
  }
}
