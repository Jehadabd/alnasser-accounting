// lib/erp/report_export.dart
//
// 📤 تصدير أي تقرير إلى Excel (CSV بترميز UTF-8 يفتحه Excel بالعربي) أو PDF.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../accounting/screens/acc_ui.dart';
import '../models/app_settings.dart';
import '../services/settings_manager.dart';

class ReportExport {
  ReportExport._();

  static String _csvCell(String s) {
    final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
    final t = s.replaceAll('"', '""');
    return needsQuote ? '"$t"' : t;
  }

  static String toCsv(List<String> headers, List<List<String>> rows) {
    final b = StringBuffer();
    b.writeln(headers.map(_csvCell).join(','));
    for (final r in rows) {
      b.writeln(r.map(_csvCell).join(','));
    }
    return b.toString();
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');

  static Future<Directory> _exportDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}alnaser_exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _open(String path) async {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', path], runInShell: false);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path]);
    } else {
      await Share.shareXFiles([XFile(path)]);
    }
  }

  /// يحفظ الجدول ملف CSV ويفتحه (Excel على ويندوز).
  static Future<String?> exportCsv(
    BuildContext context, {
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    if (kIsWeb) {
      showError(context, 'التصدير غير متاح في نسخة المتصفح');
      return null;
    }
    try {
      final dir = await _exportDir();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final path = '${dir.path}${Platform.pathSeparator}${_safeName(title)}_$stamp.csv';
      // BOM حتى يقرأ Excel العربية صحيحاً
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(headers, rows))];
      await File(path).writeAsBytes(bytes, flush: true);
      await _open(path);
      if (context.mounted) showOk(context, 'حُفظ الملف: $path');
      return path;
    } catch (e) {
      if (context.mounted) showError(context, 'فشل التصدير: $e');
      return null;
    }
  }

  static pw.Font? _font;
  static pw.Font? _bold;

  static Future<pw.Font> font() async =>
      _font ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));

  static Future<pw.Font> boldFont() async =>
      _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));

  /// PDF لجدول بعنوان (أفقي تلقائياً إن كانت الأعمدة كثيرة).
  static Future<Uint8List> tablePdf({
    required String title,
    String? subtitle,
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? footer,
    List<String> summaryLines = const [],
  }) async {
    final f = await font();
    final settings = await SettingsManager.getAppSettings();
    final shop = _shopName(settings);
    final doc = pw.Document();
    final landscape = headers.length > 6;
    final style = pw.TextStyle(font: f, fontSize: 9);
    final head = pw.TextStyle(font: f, fontSize: 9, color: PdfColors.white);
    doc.addPage(pw.MultiPage(
      pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: f, bold: f),
      header: (ctx) => pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(shop, style: pw.TextStyle(font: f, fontSize: 14)),
          pw.Text(title, style: pw.TextStyle(font: f, fontSize: 14, color: PdfColor.fromInt(0xFF0F3460))),
          pw.Text(fmtDate(DateTime.now()), style: pw.TextStyle(font: f, fontSize: 10)),
        ]),
        if (subtitle != null && subtitle.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(subtitle, style: pw.TextStyle(font: f, fontSize: 10, color: PdfColors.grey700)),
          ),
        pw.Divider(color: PdfColors.grey400),
      ]),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text('صفحة ${ctx.pageNumber} من ${ctx.pagesCount}', style: pw.TextStyle(font: f, fontSize: 8)),
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: [...rows, if (footer != null) footer],
          headerStyle: head,
          cellStyle: style,
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0F3460)),
          cellAlignment: pw.Alignment.centerRight,
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F6FA)),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        ),
        if (summaryLines.isNotEmpty) pw.SizedBox(height: 10),
        for (final l in summaryLines) pw.Text(l, style: pw.TextStyle(font: f, fontSize: 11)),
      ],
    ));
    return doc.save();
  }

  static String _shopName(AppSettings settings) {
    final n = settings.invoiceDesign.companyName.trim().isEmpty ? 'الناصر' : settings.invoiceDesign.companyName.trim();
    final b = settings.branchName.trim();
    return b.isEmpty ? n : '$n — $b';
  }

  /// يفتح PDF: على ويندوز بالعارض الافتراضي، وغيره بنافذة الطباعة.
  static Future<void> openPdf(BuildContext context, Uint8List bytes, String name) async {
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final dir = await _exportDir();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}${Platform.pathSeparator}${_safeName(name)}_$stamp.pdf';
        await File(path).writeAsBytes(bytes, flush: true);
        await _open(path);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      }
    } catch (e) {
      if (context.mounted) showError(context, 'تعذّر فتح الملف: $e');
    }
  }

  static Future<void> exportPdf(
    BuildContext context, {
    required String title,
    String? subtitle,
    required List<String> headers,
    required List<List<String>> rows,
    List<String>? footer,
    List<String> summaryLines = const [],
  }) async {
    try {
      final bytes = await tablePdf(
          title: title,
          subtitle: subtitle,
          headers: headers,
          rows: rows,
          footer: footer,
          summaryLines: summaryLines);
      if (context.mounted) await openPdf(context, bytes, title);
    } catch (e) {
      if (context.mounted) showError(context, 'فشل إنشاء PDF: $e');
    }
  }
}

/// زرّا «Excel» و«PDF» لشريط العنوان.
List<Widget> exportActions(
  BuildContext context, {
  required String title,
  required List<String> Function() headers,
  required List<List<String>> Function() rows,
  List<String>? Function()? footer,
  String? Function()? subtitle,
}) =>
    [
      IconButton(
        tooltip: 'تصدير Excel',
        icon: const Icon(Icons.grid_on),
        onPressed: () => ReportExport.exportCsv(context,
            title: title,
            headers: headers(),
            rows: [...rows(), if (footer != null && footer() != null) footer()!]),
      ),
      IconButton(
        tooltip: 'طباعة / PDF',
        icon: const Icon(Icons.picture_as_pdf),
        onPressed: () => ReportExport.exportPdf(context,
            title: title,
            subtitle: subtitle?.call(),
            headers: headers(),
            rows: rows(),
            footer: footer?.call()),
      ),
    ];
