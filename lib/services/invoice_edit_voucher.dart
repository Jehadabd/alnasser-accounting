// lib/services/invoice_edit_voucher.dart
//
// 🧾 سند لتعديل فاتورة نقدية بعد حفظها:
//   • نقص مجموعها (مواد أُرجعت) ⇒ «سند صرف — مرتجع بضاعة»: ما رُدّ للزبون نقداً.
//   • زاد مجموعها (مواد أُضيفت) ⇒ «سند قبض — إضافة على فاتورة»: ما قُبض منه.
// مرقّم ومطبوع بالمواد التي تغيّرت (من سجل InvoiceEditLog).
//
// ⚠️ مستند فقط — لا يحرّك الصندوق ولا الدين: الفاتورة نفسها بعد التعديل هي ما
// يُرحَّل (PostingEngine يعيد قيدها بمجموعها الجديد)، فلو حرّك السند الصندوق أيضاً
// لاحتُسب المبلغ مرتين.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'logo_service.dart';
import 'pdf_header.dart';
import 'settings_manager.dart';
import '../screens/statements/statement_pdf.dart' show deliverStatementPdf;

class InvoiceEditVoucher {
  InvoiceEditVoucher._();

  static final _nf = NumberFormat('#,##0', 'en_US');
  static String _q(num v) => NumberFormat('#,##0.###', 'en_US').format(v);

  static Future<void> _ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_edit_vouchers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        kind TEXT NOT NULL,           -- refund (صرف) | receipt (قبض)
        amount REAL NOT NULL,
        total_before REAL NOT NULL,
        total_after REAL NOT NULL,
        edited_at TEXT,               -- يربطه بأسطر invoice_edit_changes
        created_by TEXT,
        created_at TEXT NOT NULL
      )''');
  }

  /// مجموع الفاتورة ونوع دفعها في القاعدة الآن (يُقرأ قبل الحفظ).
  static Future<({double total, String payment})?> snapshot(int invoiceId) async {
    try {
      final db = await DatabaseService().database;
      final r = await db.query('invoices',
          columns: ['total_amount', 'payment_type'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (r.isEmpty) return null;
      return (
        total: (r.first['total_amount'] as num?)?.toDouble() ?? 0,
        payment: '${r.first['payment_type'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  /// بعد حفظ تعديل: فاتورة نقدية قبله وبعده وتغيّر مجموعها ⇒ يُنشأ سند ويُعاد رقمه.
  static Future<int?> recordIfCash({
    required int invoiceId,
    required ({double total, String payment}) before,
    required double totalAfter,
    required String paymentAfter,
    String? user,
  }) async {
    if (before.payment != 'نقد' || paymentAfter != 'نقد') return null;
    final delta = totalAfter - before.total;
    if (delta.abs() < 0.5) return null;
    final db = await DatabaseService().database;
    await _ensure(db);
    String? editedAt;
    try {
      final r = await db.rawQuery(
          'SELECT MAX(edited_at) AS t FROM invoice_edit_changes WHERE invoice_id = ?', [invoiceId]);
      editedAt = r.first['t'] as String?;
    } catch (_) {}
    return db.insert('invoice_edit_vouchers', {
      'invoice_id': invoiceId,
      'kind': delta < 0 ? 'refund' : 'receipt',
      'amount': delta.abs(),
      'total_before': before.total,
      'total_after': totalAfter,
      'edited_at': editedAt,
      'created_by': user,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// نافذة بعد الحفظ: كم يُرد/يُقبض، وزر الطباعة.
  static Future<void> offer(BuildContext context, int voucherId) async {
    // اسأل / اطبع دائماً / لا تُظهر — من الإعدادات ← الفاتورة والطباعة
    final mode = (await SettingsManager.getAppSettings()).adjustmentVoucherMode;
    if (mode == 'never') return;
    if (mode == 'always') {
      await printVoucher(voucherId);
      return;
    }
    if (!context.mounted) return;
    final db = await DatabaseService().database;
    final r = await db.query('invoice_edit_vouchers', where: 'id = ?', whereArgs: [voucherId], limit: 1);
    if (r.isEmpty || !context.mounted) return;
    final v = r.first;
    final refund = v['kind'] == 'refund';
    final amount = (v['amount'] as num).toDouble();
    final c = refund ? const Color(0xFFB54708) : const Color(0xFF067647);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [
            Icon(refund ? Icons.assignment_return_rounded : Icons.add_card_rounded, color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(refund ? 'سند صرف — مرتجع بضاعة' : 'سند قبض — إضافة على الفاتورة')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(refund ? 'رُدّ للزبون نقداً:' : 'يُقبض من الزبون نقداً:', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('${_nf.format(amount)} دينار',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: c)),
            const SizedBox(height: 8),
            Text('رقم السند $voucherId — مجموع الفاتورة من ${_nf.format(v['total_before'] as num)} إلى ${_nf.format(v['total_after'] as num)}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c),
              onPressed: () async {
                Navigator.pop(ctx);
                await printVoucher(voucherId);
              },
              icon: const Icon(Icons.print_rounded),
              label: const Text('طباعة السند'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> printVoucher(int voucherId) async {
    final bytes = await buildPdf(voucherId);
    if (bytes == null) return;
    await deliverStatementPdf(bytes, 'سند_تعديل_فاتورة_$voucherId');
  }

  static Future<Uint8List?> buildPdf(int voucherId) async {
    final db = await DatabaseService().database;
    final vr = await db.query('invoice_edit_vouchers', where: 'id = ?', whereArgs: [voucherId], limit: 1);
    if (vr.isEmpty) return null;
    final v = vr.first;
    final invId = v['invoice_id'] as int;
    final inv = await db.query('invoices',
        columns: ['invoice_number', 'customer_name', 'invoice_date'], where: 'id = ?', whereArgs: [invId], limit: 1);
    List<Map<String, Object?>> lines = const [];
    try {
      if (v['edited_at'] != null) {
        lines = await db.query('invoice_edit_changes',
            where: 'invoice_id = ? AND edited_at = ?', whereArgs: [invId, v['edited_at']], orderBy: 'id');
      }
    } catch (_) {}

    final refund = v['kind'] == 'refund';
    final title = refund ? 'سند صرف — مرتجع بضاعة' : 'سند قبض — إضافة على فاتورة';
    final amount = (v['amount'] as num).toDouble();
    final number = inv.isEmpty ? '$invId' : '${inv.first['invoice_number'] ?? invId}';
    final customer = inv.isEmpty ? '' : '${inv.first['customer_name'] ?? ''}';
    final when = DateTime.tryParse('${v['created_at']}') ?? DateTime.now();

    final body = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final brand = pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
    final app = await SettingsManager.getAppSettings();
    final logo = await LogoService.getLogoImage(appSettings: app);
    pw.TextStyle st(double s, {bool b = false, PdfColor? c}) =>
        pw.TextStyle(font: body, fontSize: s, fontWeight: b ? pw.FontWeight.bold : null, color: c);
    pw.Widget cell(String t, {bool b = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(t, style: st(9, b: b), textAlign: pw.TextAlign.center));

    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(18),
      textDirection: pw.TextDirection.rtl,
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        buildPdfHeader(body, brand, logo, appSettings: app, logoSize: 70),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(title, style: st(13, b: true)),
            pw.Text('رقم $voucherId', style: st(11, b: true)),
          ]),
        ),
        pw.SizedBox(height: 6),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('السيد: $customer', style: st(10)),
          pw.Text('التاريخ: ${when.year}/${when.month}/${when.day}', style: st(10)),
        ]),
        pw.Text('عن الفاتورة رقم $number — مجموعها من ${_nf.format(v['total_before'] as num)} إلى ${_nf.format(v['total_after'] as num)}',
            style: st(9.5, c: PdfColors.grey800)),
        pw.SizedBox(height: 8),
        if (lines.isNotEmpty)
          pw.Table(
            border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey600),
            columnWidths: const {
              0: pw.FixedColumnWidth(70),
              1: pw.FixedColumnWidth(50),
              2: pw.FixedColumnWidth(50),
              3: pw.FlexColumnWidth(),
              4: pw.FixedColumnWidth(46),
            },
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey300), children: [
                cell('المبلغ', b: true),
                cell('بعد', b: true),
                cell('قبل', b: true),
                cell('المادة', b: true),
                cell('النوع', b: true),
              ]),
              for (final l in lines)
                pw.TableRow(children: [
                  cell(_nf.format(((l['amount_after'] as num) - (l['amount_before'] as num)).abs())),
                  cell(_q(l['qty_after'] as num)),
                  cell(_q(l['qty_before'] as num)),
                  pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      child: pw.Text('${l['product_name']} ${l['unit'] ?? ''}', style: st(9))),
                  cell('${l['kind']}'),
                ]),
            ],
          ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(refund ? 'المبلغ المردود للزبون نقداً' : 'المبلغ المقبوض من الزبون نقداً', style: st(11)),
            pw.Text('${_nf.format(amount)} دينار', style: st(15, b: true)),
          ]),
        ),
        pw.Spacer(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(refund ? 'المستلم: ____________' : 'الدافع: ____________', style: st(10)),
          pw.Text('المحاسب: ____________', style: st(10)),
        ]),
      ]),
    ));
    return pdf.save();
  }
}
