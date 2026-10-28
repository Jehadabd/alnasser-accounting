// services/pdf_header.dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:alnaser/models/app_settings.dart';

pw.Widget buildPdfHeader(
    pw.Font font, pw.Font alnaserFont, pw.ImageProvider? logoImage,
    {double logoSize = 150, required AppSettings appSettings}) {
  // الحصول على إعدادات تصميم الفاتورة
  final invoiceDesign = appSettings.invoiceDesign;
  
  return pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.SizedBox(height: 0),
                pw.Center(
                  child: pw.Text(
                    appSettings.invoiceDesign.companyName,
                    style: pw.TextStyle(
                      font: alnaserFont,
                      fontFallback: [font],
                      fontSize: 45,
                      height: 0,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(appSettings.companyNameColor),
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    appSettings.companyDescription,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 17,
                      color: PdfColor.fromInt(appSettings.companyDescriptionColor),
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    invoiceDesign.companyAddress,
                    style: pw.TextStyle(font: font, fontSize: 13),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                // أرقام الهواتف بدون تسميات (كهربائيات/صحيات)
                pw.SizedBox(height: 4),
                // عرض أرقام الهواتف من إعدادات تصميم الفاتورة (حد أقصى 2)
                if (invoiceDesign.phoneNumbers.isNotEmpty) ...[
                  pw.Center(
                    child: pw.Directionality(
                      textDirection: pw.TextDirection.ltr,
                      child: pw.Text(
                        invoiceDesign.labeledPhones.take(4).join('  |  '),
                        style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black),
                      ),
                    ),
                  ),
                ] else if (appSettings.phoneNumbers.isNotEmpty) ...[
                  // الرجوع لأرقام الهاتف القديمة إذا لم تُحدد أرقام جديدة
                  pw.Center(
                    child: pw.Directionality(
                      textDirection: pw.TextDirection.ltr,
                      child: pw.Text(
                        appSettings.phoneNumbers.take(2).join('  |  '),
                        style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black),
                      ),
                    ),
                  ),
                ],
                // 🧾 الرقم الضريبي والسجل التجاري (إن كُتبا في تصميم القائمة)
                if (invoiceDesign.taxNumber.trim().isNotEmpty ||
                    invoiceDesign.commercialRegister.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Center(
                    child: pw.Text(
                      [
                        if (invoiceDesign.taxNumber.trim().isNotEmpty)
                          'الرقم الضريبي: ${invoiceDesign.taxNumber.trim()}',
                        if (invoiceDesign.commercialRegister.trim().isNotEmpty)
                          'السجل التجاري: ${invoiceDesign.commercialRegister.trim()}',
                      ].join('   |   '),
                      style: pw.TextStyle(font: font, fontSize: 11),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          // عرض اللوجو فقط إذا كان موجودًا
          if (logoImage != null)
            pw.Container(
              width: logoSize,
              height: logoSize,
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            )
          else
            pw.SizedBox(width: logoSize), // مساحة فارغة بنفس الحجم للحفاظ على التنسيق
        ],
      ),
      pw.SizedBox(height: 4),
    ],
  );
}
