// lib/erp/inventory/barcode_labels.dart
//
// 🏷️ طباعة ملصقات الباركود وقوائم الأسعار (مثل الإداري وسهل).
//   • ملصق لكل مادة: الاسم + باركود Code128 + السعر المختار، بعدد نسخ.
//   • قائمة أسعار PDF بمستويات الأسعار المطلوبة.
// قراءة فقط — لا تغيّر أي بيانات.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../accounting/screens/acc_ui.dart';
import '../erp_common.dart';
import '../report_export.dart';
import '../stock_helpers.dart';

class LabelOptions {
  LabelOptions({
    this.copies = 1,
    this.priceLevel = 1,
    this.showPrice = true,
    this.columns = 3,
    this.labelHeight = 30,
  });
  int copies;

  /// 1..6
  int priceLevel;
  bool showPrice;

  /// عدد الأعمدة على صفحة A4 (2..5)
  int columns;

  /// ارتفاع الملصق بالمليمتر
  double labelHeight;
}

class BarcodeLabels {
  BarcodeLabels._();

  static String _codeOf(ProductLite p) {
    final b = (p.barcode ?? '').trim();
    if (b.isNotEmpty) return b;
    final c = (p.itemCode ?? '').trim();
    if (c.isNotEmpty) return c;
    return p.id.toString().padLeft(6, '0');
  }

  /// يعرض نافذة الخيارات ثم يطبع الملصقات.
  static Future<void> printForProducts(BuildContext context, List<int> productIds, {int copies = 1}) async {
    if (productIds.isEmpty) return;
    final opts = await _askOptions(context, LabelOptions(copies: copies));
    if (opts == null || !context.mounted) return;
    try {
      final db = await erpDb();
      final items = <ProductLite>[];
      for (final id in productIds) {
        final p = await ErpStock.byId(db, id);
        if (p != null) items.add(p);
      }
      if (items.isEmpty) {
        if (context.mounted) showError(context, 'لا توجد مواد للطباعة');
        return;
      }
      final bytes = await _labelsPdf(items, opts);
      if (context.mounted) await ReportExport.openPdf(context, bytes, 'ملصقات باركود');
    } catch (e) {
      if (context.mounted) showError(context, 'تعذّرت طباعة الملصقات: $e');
    }
  }

  static Future<LabelOptions?> _askOptions(BuildContext context, LabelOptions o) {
    final copiesCtl = TextEditingController(text: '${o.copies}');
    return showDialog<LabelOptions>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.qr_code_2_rounded, color: Color(0xFF0F3460)),
            SizedBox(width: 8),
            Text('طباعة ملصقات باركود'),
          ]),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: copiesCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'عدد النسخ لكل مادة', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إظهار السعر'),
                value: o.showPrice,
                onChanged: (v) => setS(() => o.showPrice = v),
              ),
              if (o.showPrice)
                DropdownButtonFormField<int>(
                  value: o.priceLevel,
                  decoration: const InputDecoration(labelText: 'مستوى السعر', border: OutlineInputBorder()),
                  items: [
                    for (var i = 0; i < priceLevelNames.length; i++)
                      DropdownMenuItem(value: i + 1, child: Text(priceLevelNames[i])),
                  ],
                  onChanged: (v) => setS(() => o.priceLevel = v ?? 1),
                ),
              const SizedBox(height: 10),
              Row(children: [
                const Text('الأعمدة في الصفحة:'),
                Expanded(
                  child: Slider(
                    value: o.columns.toDouble(),
                    min: 2,
                    max: 5,
                    divisions: 3,
                    label: '${o.columns}',
                    onChanged: (v) => setS(() => o.columns = v.round()),
                  ),
                ),
                Text('${o.columns}'),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton.icon(
              icon: const Icon(Icons.print_rounded),
              label: const Text('طباعة'),
              onPressed: () {
                final n = int.tryParse(copiesCtl.text.trim()) ?? 1;
                o.copies = n < 1 ? 1 : (n > 500 ? 500 : n);
                Navigator.pop(ctx, o);
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<Uint8List> _labelsPdf(List<ProductLite> items, LabelOptions o) async {
    final f = await ReportExport.font();
    final doc = pw.Document();
    final cells = <pw.Widget>[];
    for (final p in items) {
      final code = _codeOf(p);
      final idx = (o.priceLevel - 1) < 0 ? 0 : ((o.priceLevel - 1) > 5 ? 5 : o.priceLevel - 1);
      final price = p.prices.length > idx ? p.prices[idx] : 0.0;
      for (var c = 0; c < o.copies; c++) {
        cells.add(pw.Container(
          height: o.labelHeight * PdfPageFormat.mm,
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(p.name,
                  maxLines: 1,
                  textDirection: pw.TextDirection.rtl,
                  style: pw.TextStyle(font: f, fontSize: 8)),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: code,
                    drawText: true,
                    textStyle: pw.TextStyle(font: f, fontSize: 6),
                  ),
                ),
              ),
              if (o.showPrice)
                pw.Text('${fmtMoney(price)} د.ع',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(font: f, fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ));
      }
    }
    final rows = <pw.TableRow>[];
    for (var i = 0; i < cells.length; i += o.columns) {
      rows.add(pw.TableRow(children: [
        for (var j = 0; j < o.columns; j++)
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: (i + j) < cells.length ? cells[i + j] : pw.SizedBox(),
          ),
      ]));
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(12),
      build: (ctx) => [pw.Table(children: rows)],
    ));
    return doc.save();
  }

  /// قائمة أسعار PDF لمجموعة مواد بالمستويات المختارة (1..6).
  static Future<void> priceList(BuildContext context, List<int> productIds, List<int> levels,
      {String title = 'قائمة الأسعار'}) async {
    try {
      final db = await erpDb();
      final rows = <List<String>>[];
      for (final id in productIds) {
        final p = await ErpStock.byId(db, id);
        if (p == null) continue;
        rows.add([
          p.itemCode ?? '',
          p.name,
          p.baseUnitName,
          for (final l in levels) fmtMoney(p.prices.length >= l ? p.prices[l - 1] : 0),
        ]);
      }
      if (!context.mounted) return;
      await ReportExport.exportPdf(
        context,
        title: title,
        headers: ['الرمز', 'المادة', 'الوحدة', for (final l in levels) priceLevelNames[l - 1]],
        rows: rows,
      );
    } catch (e) {
      if (context.mounted) showError(context, 'تعذّر إنشاء قائمة الأسعار: $e');
    }
  }
}
