// services/receipt_voucher_pdf_service.dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'pdf_header.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:intl/intl.dart';

class ReceiptVoucherPdfService {
  // دالة تنسيق الأرقام مع فاصلة كل 3 خانات
  static String _formatNumber(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  static Future<pw.Document> generateReceiptVoucherPdf({
    required String customerName,
    required double beforePayment,
    required double paidAmount,
    required double afterPayment,
    required DateTime dateTime,
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage? logoImage,
    int? receiptNumber, // رقم سند القبض (اختياري)
  }) async {
    // تحميل الإعدادات العامة
    final appSettings = await SettingsManager.getAppSettings();
    
    // تحميل خط الناصر الصحيح (نفس خط الفاتورة)
    final alnaserFontCorrect = pw.Font.ttf(
        await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
    
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.only(top: 0, bottom: 10, left: 10, right: 10),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الصفحة - نفس تصميم الفاتورة
                buildPdfHeader(font, alnaserFontCorrect, logoImage,
                    appSettings: appSettings),
                pw.SizedBox(height: 4),
                // معلومات السند
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('السيد: $customerName',
                        style: pw.TextStyle(font: font, fontSize: 12)),
                    pw.Text('رقم السند: ${receiptNumber ?? '-'}',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text(
                        'الوقت: ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
                        style: pw.TextStyle(font: font, fontSize: 11)),
                    pw.Text(
                        'التاريخ: ${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')}',
                        style: pw.TextStyle(font: font, fontSize: 11)),
                  ],
                ),
                pw.Divider(height: 5, thickness: 0.5),
                pw.SizedBox(height: 16),
                // عنوان سند القبض
                pw.Center(
                  child: pw.Container(
                    padding: pw.EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 2),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'سند قبض',
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
                pw.SizedBox(height: 30),
                // جدول المبالغ
                pw.Container(
                  padding: pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 1),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('إجمالي الدين قبل التسديد:',
                              style: pw.TextStyle(font: font, fontSize: 16)),
                          pw.Text('${_formatNumber(beforePayment)} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                      pw.SizedBox(height: 16),
                      pw.Divider(thickness: 0.5),
                      pw.SizedBox(height: 16),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('المبلغ المسدد:',
                              style: pw.TextStyle(font: font, fontSize: 18, color: PdfColors.green800)),
                          pw.Text('${_formatNumber(paidAmount)} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 20,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.green800)),
                        ],
                      ),
                      pw.SizedBox(height: 16),
                      pw.Divider(thickness: 0.5),
                      pw.SizedBox(height: 16),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('إجمالي الدين بعد التسديد:',
                              style: pw.TextStyle(font: font, fontSize: 16)),
                          pw.Text('${_formatNumber(afterPayment)} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: afterPayment > 0 ? PdfColors.red : PdfColors.green)),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 50),
                // تنبيه
                pw.Center(
                  child: pw.Container(
                    padding: pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red50,
                      border: pw.Border.all(color: PdfColors.red),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      'يجب حفظ هذه الورقة لحفظ جميع حقوقك',
                      style: pw.TextStyle(
                          font: font, fontSize: 14, color: PdfColors.red800, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return pdf;
  }
}
