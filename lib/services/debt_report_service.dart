import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;
import '../services/database_service.dart';

class DebtReportService {
  static final _currencyFormat = intl.NumberFormat('#,##0', 'en_US');

  // Method to generate PDF bytes (for backup or sharing)
  static Future<Uint8List> generateReportPdf() async {
    final db = DatabaseService();
    
    // 1. Fetch Data
    // We assume we want *all* currently indebted customers.
    final rawData = await db.database.then((d) => d.rawQuery('''
      SELECT * FROM customers 
      WHERE current_total_debt > 0 
        AND EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = customers.id LIMIT 1)
      ORDER BY name ASC
    '''));
    
    final customers = rawData;
    
    // Calculate totals
    double totalDebt = 0;
    for (var c in customers) {
      totalDebt += (c['current_total_debt'] as num?)?.toDouble() ?? 0;
    }

    // 2. Load Fonts
    final fontData = await rootBundle.load("assets/fonts/Cairo-Regular.ttf");
    final ttf = pw.Font.ttf(fontData);

    // 3. Create PDF
    final pdf = pw.Document();
    
    final now = DateTime.now();
    final dateStr = intl.DateFormat('yyyy-MM-dd', 'en').format(now);
    final timeStr = intl.DateFormat('hh:mm a', 'en').format(now);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: ttf,
          bold: ttf,
        ),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return [
            // Header
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('تقرير الديون الشامل', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttf)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('تاريخ الإنشاء: $dateStr', style: const pw.TextStyle(fontSize: 12)),
                      pw.Text('الوقت: $timeStr', style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                color: PdfColors.grey100,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(children: [
                    pw.Text('عدد العملاء', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('${customers.length}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
                  ]),
                  pw.Column(children: [
                    pw.Text('إجمالي الديون', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text(_currencyFormat.format(totalDebt), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Table
            pw.Table.fromTextArray(
              headers: ['المبلغ', 'رقم الهاتف', 'العنوان', 'الاسم', 'ت'],
              data: List<List<dynamic>>.generate(
                customers.length,
                (index) {
                  final c = customers[index];
                  return [
                    _currencyFormat.format(c['current_total_debt'] ?? 0),
                    c['phone'] ?? '-',
                    c['address'] ?? '-',
                    c['name'] ?? '-',
                    '${index + 1}',
                  ];
                },
              ),
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              columnWidths: {
                0: const pw.FlexColumnWidth(2),    // Amount
                1: const pw.FlexColumnWidth(2),    // Phone
                2: const pw.FlexColumnWidth(2),    // Address
                3: const pw.FlexColumnWidth(3),    // Name
                4: const pw.FixedColumnWidth(30),  // Index
              },
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> generateAndShareReport() async {
    try {
      final pdfBytes = await generateReportPdf();
      
      final now = DateTime.now();
      final dateStr = intl.DateFormat('yyyy-MM-dd', 'en').format(now);
      final fileName = 'debt_report_${dateStr}_${now.millisecondsSinceEpoch}.pdf';
      
      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
    } catch (e) {
      // ignore
      print('Error generated pdf: $e');
      rethrow;
    }
  }
}
