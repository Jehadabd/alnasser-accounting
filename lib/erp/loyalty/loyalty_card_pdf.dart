// lib/erp/loyalty/loyalty_card_pdf.dart
//
// 🪪 بطاقة الولاء PDF بمقاس البطاقة البنكية (85.6×54 مم) فيها رمز QR برقم البطاقة —
// تُطبع، أو تُرسل للزبون صورةً/ملفاً يحفظه في هاتفه (بديل محفظة الهاتف التي تحتاج حساب
// مطوّر مدفوعاً من Apple وGoogle).

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'loyalty_models.dart';

Future<Uint8List> buildLoyaltyCardPdf({
  required LoyaltyMember member,
  required String shopName,
  required LoyaltyBalance balance,
  required LoyaltySettings settings,
}) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
  final style = pw.TextStyle(font: font, fontSize: 9, color: PdfColors.white);
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(85.6 * PdfPageFormat.mm, 54 * PdfPageFormat.mm, marginAll: 0),
    textDirection: pw.TextDirection.rtl,
    build: (_) => pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(colors: [PdfColor.fromInt(0xFF0F3460), PdfColor.fromInt(0xFF047857)]),
      ),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(shopName.isEmpty ? 'بطاقة الولاء' : shopName, style: style.copyWith(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Text(member.name, style: style.copyWith(fontSize: 11)),
            pw.Text('رقم البطاقة: ${member.cardNo}', style: style),
            pw.Text('الرصيد: ${balance.available} ${settings.unitName} • المكافأة كل ${settings.unitsPerReward}', style: style.copyWith(fontSize: 8)),
          ]),
        ),
        pw.SizedBox(width: 8),
        pw.Container(
          width: 70,
          padding: const pw.EdgeInsets.all(4),
          color: PdfColors.white,
          child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: 'LOYALTY:${member.cardNo}'),
        ),
      ]),
    ),
  ));
  return doc.save();
}
