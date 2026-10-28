// lib/invoice_designer/layout_pdf_renderer.dart
//
// 🖨️ يحوّل تصميم الفاتورة + بياناتها إلى PDF بالمقاسات المصمَّمة بالضبط.
//   • A4: صفوف الجدول بقدر ارتفاعه؛ الزائد إلى صفحة جديدة. ما فوق الجدول يتكرر
//     في كل صفحة، وما تحته (المجاميع…) في الأخيرة فقط (إلا ما عُلّم «كل صفحة»).
//   • الإيصال: الورقة تطول مع عدد المواد، وما تحت الجدول ينزل معه.
// كل الصفوف تُبنى من اليسار لليمين صراحةً (والنصوص RTL) فلا يتغير الترتيب.

import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'invoice_layout.dart';
import 'invoice_print_data.dart';

class LayoutPdfRenderer {
  LayoutPdfRenderer._();

  static const double mm = PdfPageFormat.mm;
  static pw.Font? _base;
  static pw.Font? _bold;

  static Future<void> _fonts() async {
    _base ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
  }

  /// ارتفاع السطر التقريبي لخط Cairo (بالنقطة) لحجم خط معيّن
  static double lineHeight(double fontSize) => fontSize * 1.85;

  /// ⚫ تصميم «أبيض وأسود» قيد الرسم (العناصر تُبنى فوراً داخل render).
  static bool _mono = false;

  static Future<pw.Document> render(InvoiceLayout layout, InvoicePrintData data) async {
    await _fonts();
    _mono = layout.mono;
    final doc = pw.Document(title: 'فاتورة ${data.field('invoiceNo')}');
    final table = layout.table;
    final w = layout.widthMm;
    final rows = data.rows;

    if (table == null) {
      doc.addPage(_page(w, layout.heightMm, [
        for (final e in layout.elements) _place(e, data, 0),
      ]));
      return doc;
    }

    final cols = visibleColumns(table, rows);
    final rowH = table.d('rowHeight', 8).clamp(3.0, 60.0).toDouble();
    final headH = table.d('headerHeight', rowH).clamp(3.0, 60.0).toDouble();
    final tBottom = table.y + table.h;
    bool below(LayoutElement e) =>
        e.type != ElType.watermark && e.type != ElType.pageNo && e.y >= tBottom - 0.5;

    if (layout.paper.isRoll) {
      // 🧾 الإيصال: ورقة واحدة بطول المحتوى
      final need = headH + rows.length * rowH;
      final shift = need - table.h;
      final height = math.max(layout.heightMm + shift, table.y + need + 3);
      doc.addPage(_page(w, height, [
        for (final e in layout.elements)
          if (e.type == ElType.table)
            _at(e, 0, e.w, need, _table(e, cols, rows, 0, rows.length, rowH, headH, 0))
          else
            _place(e, data, below(e) ? shift : 0),
      ]));
      return doc;
    }

    // 📄 A4: صفحات بقدر ما يتسع الجدول
    final cap = math.max(1, ((table.h - headH) / rowH).floor());
    final pages = math.max(1, (rows.length / cap).ceil());
    final fill = table.b('fillRows', false);
    for (var p = 0; p < pages; p++) {
      final last = p == pages - 1;
      final start = p * cap;
      final end = math.min(rows.length, start + cap);
      doc.addPage(_page(w, layout.heightMm, [
        for (final e in layout.elements)
          if (e.type == ElType.table)
            _at(e, 0, e.w, e.h, _table(e, cols, rows, start, end, rowH, headH, fill ? cap - (end - start) : 0))
          else if (!below(e) || last || e.b('everyPage', false))
            _place(e, data, 0, page: p + 1, pages: pages),
      ]));
    }
    return doc;
  }

  /// أعمدة الجدول الظاهرة: «الخصم» و«السعر قبل الخصم» يختفيان إن لم يكن في
  /// الفاتورة صنف مخصوم (إلا إن أُطفئ «إخفاء إن كان فارغاً» للعمود).
  static List<Map<String, dynamic>> visibleColumns(LayoutElement t, List<Map<String, String>> rows) {
    return t.columns.where((c) {
      final id = '${c['id']}';
      final auto =
          c['hideIfEmpty'] is bool ? c['hideIfEmpty'] as bool : (id == 'discount' || id == 'priceBeforeDiscount');
      if (!auto) return true;
      return rows.any((r) => (r[id] ?? '').trim().isNotEmpty);
    }).toList();
  }

  static double flexOf(Map<String, dynamic> c) {
    final f = c['flex'];
    return f is num && f > 0 ? f.toDouble() : 1.0;
  }

  // ─────────────────────────── الصفحة والموضع ───────────────────────────

  static pw.Page _page(double wMm, double hMm, List<pw.Widget> children) => pw.Page(
        pageFormat: PdfPageFormat(wMm * mm, hMm * mm, marginAll: 0),
        theme: pw.ThemeData.withFont(base: _base!, bold: _bold!),
        textDirection: pw.TextDirection.ltr,
        build: (_) => pw.SizedBox(
          width: wMm * mm,
          height: hMm * mm,
          child: pw.Stack(children: children),
        ),
      );

  static pw.Widget _at(LayoutElement e, double dy, double wMm, double hMm, pw.Widget child) => pw.Positioned(
        left: e.x * mm,
        top: (e.y + dy) * mm,
        child: pw.SizedBox(width: wMm * mm, height: hMm * mm, child: child),
      );

  static pw.Widget _place(LayoutElement e, InvoicePrintData d, double dy, {int page = 1, int pages = 1}) =>
      _at(e, dy, e.w, e.h, _content(e, d, page, pages));

  /// 🔢 نص بلا حروف عربية (رقم سند، تسلسل، مبلغ…) يُرسم من اليسار لليمين.
  /// رسمه «من اليمين» في مكتبة PDF يُظهر الرقم المنفرد («1») علامةً صغيرة بدل الرقم.
  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');
  static pw.TextDirection _dirOf(String s) => _arabic.hasMatch(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  static pw.Widget _ltr(pw.Widget w) => pw.Directionality(textDirection: pw.TextDirection.ltr, child: w);

  static pw.Alignment _alignment(String a) => a == 'center'
      ? pw.Alignment.center
      : (a == 'left' ? pw.Alignment.centerLeft : pw.Alignment.centerRight);

  static pw.TextAlign _textAlign(String a) =>
      a == 'center' ? pw.TextAlign.center : (a == 'left' ? pw.TextAlign.left : pw.TextAlign.right);

  static PdfColor _c(int argb) {
    if (!_mono) return PdfColor.fromInt(argb);
    // تدرّج رمادي بإضاءة اللون نفسها (ما كان غامقاً يبقى غامقاً)
    final a = ((argb >> 24) & 0xFF) / 255.0;
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return PdfColor(l, l, l, a);
  }

  static pw.TextStyle _style(double fs, {bool bold = false, int color = 0xFF000000}) => pw.TextStyle(
        font: bold ? _bold : _base,
        fontFallback: [_base!],
        fontSize: fs,
        color: _c(color),
      );

  // ─────────────────────────── العناصر ───────────────────────────

  static pw.Widget _content(LayoutElement e, InvoicePrintData d, int page, int pages) {
    switch (e.type) {
      case ElType.logo:
        final bytes = d.company.logo;
        if (bytes == null || bytes.isEmpty) return pw.SizedBox();
        return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
      case ElType.companyName:
        return _textBox(e, d.company.name);
      case ElType.companyInfo:
        final keys = e.strings('lines');
        final text = [
          for (final k in keys)
            if ((d.company.lines[k] ?? '').isNotEmpty) d.company.lines[k]!,
        ].join('\n');
        return _textBox(e, text);
      case ElType.text:
        return _textBox(e, d.fill(e.s('text', '')));
      case ElType.field:
        final key = e.s('key', 'customer');
        final v = d.field(key);
        final label = e.s('label', LayoutCatalog.fields[key] ?? '');
        final show = e.b('showLabel', true) && label.trim().isNotEmpty;
        return _textBox(e, show ? '$label: $v' : v);
      case ElType.pageNo:
        return _textBox(e, 'صفحة $page من $pages');
      case ElType.line:
        final t = e.d('thickness', 0.8);
        final side = pw.BorderSide(
          width: t,
          color: _c(e.i('color', 0xFF000000)),
          style: e.b('dashed', false) ? pw.BorderStyle.dashed : pw.BorderStyle.solid,
        );
        final vertical = e.h > e.w;
        return pw.Center(
          child: vertical
              ? pw.Container(width: t, height: e.h * mm, decoration: pw.BoxDecoration(border: pw.Border(left: side)))
              : pw.Container(width: e.w * mm, height: t, decoration: pw.BoxDecoration(border: pw.Border(top: side))),
        );
      case ElType.box:
        return pw.Container(decoration: _boxDecoration(e, defaultBorder: 0.8));
      case ElType.barcode:
        final qr = e.s('kind', 'qr') == 'qr';
        final data = d.barcodeText(e.s('data', 'invoiceNo'), qr: qr);
        if (data.trim().isEmpty) return pw.SizedBox();
        return pw.BarcodeWidget(
          barcode: qr ? pw.Barcode.qrCode() : pw.Barcode.code128(),
          data: data,
          drawText: !qr,
          textStyle: _style(7),
        );
      case ElType.watermark:
        final t = e.s('text', '');
        final text = t.trim().isEmpty ? d.company.name : d.fill(t);
        return pw.Center(
          child: pw.Transform.rotate(
            angle: e.d('angle', 0.8),
            child: pw.Opacity(
              opacity: e.d('opacity', 0.08).clamp(0.01, 1.0).toDouble(),
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.Text(text,
                    textDirection: pw.TextDirection.rtl,
                    style: _style(e.d('fontSize', 100), bold: true, color: e.i('color', 0xFF9E9E9E))),
              ),
            ),
          ),
        );
      case ElType.totals:
        return _totals(e, d);
      default:
        return pw.SizedBox();
    }
  }

  static pw.BoxDecoration? _boxDecoration(LayoutElement e, {double defaultBorder = 0}) {
    final border = e.d('border', defaultBorder);
    final bg = e.i('bg', 0);
    final radius = e.d('radius', 0);
    if (border <= 0 && bg == 0) return null;
    return pw.BoxDecoration(
      color: bg != 0 ? _c(bg) : null,
      border: border > 0 ? pw.Border.all(width: border, color: _c(e.i('borderColor', 0xFF000000))) : null,
      borderRadius: radius > 0 ? pw.BorderRadius.circular(radius * mm) : null,
    );
  }

  /// نص في صندوق العنصر: سطر واحد يصغر ليتسع، أو عدة أسطر بقدر الارتفاع
  static pw.Widget _textBox(LayoutElement e, String text) {
    final fs = e.d('fontSize', 10);
    final align = e.s('align', 'right');
    final deco = _boxDecoration(e);
    final pad = deco != null ? 1.2 * mm : 0.0;
    final lines = math.max(1, ((e.h * mm - pad) / lineHeight(fs)).floor());
    final style = _style(fs, bold: e.b('bold', false), color: e.i('color', 0xFF000000));
    final multi = lines > 1 || text.contains('\n');
    final pw.Widget t = multi
        ? pw.Text(text,
            style: style,
            textAlign: _textAlign(align),
            textDirection: _dirOf(text),
            maxLines: math.max(lines, text.split('\n').length),
            overflow: pw.TextOverflow.clip)
        : pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            alignment: _alignment(align),
            child: pw.Text(text, style: style, textDirection: _dirOf(text), maxLines: 1),
          );
    return pw.Container(
      alignment: _alignment(align),
      padding: pw.EdgeInsets.symmetric(horizontal: pad),
      decoration: deco,
      child: t,
    );
  }

  // ─────────────────────────── جدول المواد ───────────────────────────

  static pw.Widget _table(LayoutElement t, List<Map<String, dynamic>> cols, List<Map<String, String>> rows,
      int start, int end, double rowH, double headH, int emptyRows) {
    if (cols.isEmpty) return pw.SizedBox();
    final fs = t.d('fontSize', 10);
    final mode = LayoutRules.tableBorders(t);
    final zebra = t.b('zebra', false);
    final lineColor = _c(t.i('gridColor', 0xFF9E9E9E));
    final lw = t.d('lineWidth', 0.4);
    final side = pw.BorderSide(width: lw, color: lineColor);
    final headerBg = t.i('headerBg', 0xFFE8EEF5);
    final headerColor = t.i('headerColor', 0xFF000000);
    final textColor = t.i('color', 0xFF000000);
    final flexes = [for (final c in cols) math.max(1, (flexOf(c) * 100).round())];
    final framed = mode == 'columns' || mode == 'outer';

    pw.Widget row(List<String> texts, {required bool header, int index = 0}) {
      final h = header ? headH : rowH;
      final lines = math.max(1, ((h * mm - 1) / lineHeight(fs)).floor());
      final cells = <pw.Widget>[];
      // من اليسار لليمين: العمود الأول في القائمة هو الأيمن
      for (var i = cols.length - 1; i >= 0; i--) {
        final align = header ? 'center' : '${cols[i]['align'] ?? 'center'}';
        final leftmost = i == cols.length - 1;
        pw.Border? b;
        if (mode == 'grid') {
          b = pw.Border.all(width: lw, color: lineColor);
        } else if (mode == 'columns' && !leftmost) {
          b = pw.Border(left: side);
        }
        cells.add(pw.Expanded(
          flex: flexes[i],
          child: pw.Container(
            height: h * mm,
            alignment: _alignment(align),
            padding: const pw.EdgeInsets.symmetric(horizontal: 0.8 * PdfPageFormat.mm),
            decoration: b == null ? null : pw.BoxDecoration(border: b),
            child: pw.Text(
              texts[i],
              style: _style(fs, bold: header, color: header ? headerColor : textColor),
              textAlign: _textAlign(align),
              textDirection: _dirOf(texts[i]),
              maxLines: header ? 1 : lines,
              overflow: pw.TextOverflow.clip,
            ),
          ),
        ));
      }
      final bg = header ? headerBg : (zebra && index.isOdd ? 0xFFF1F5F9 : 0);
      final underline = header ? (mode != 'grid' && mode != 'none') : mode == 'rows';
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: bg != 0 ? _c(bg) : null,
          border: underline ? pw.Border(bottom: side) : null,
        ),
        child: _ltr(pw.Row(children: cells)),
      );
    }

    final body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        row([for (final c in cols) '${c['label'] ?? ''}'], header: true),
        for (var r = start; r < end; r++)
          row([for (final c in cols) rows[r]['${c['id']}'] ?? ''], header: false, index: r),
        for (var r = 0; r < emptyRows; r++)
          row(List<String>.filled(cols.length, ''), header: false, index: end + r),
      ],
    );
    if (!framed) return body;
    return pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(width: lw * 1.5, color: lineColor)), child: body);
  }

  // ─────────────────────────── المجاميع / البيانات ───────────────────────────

  static pw.Widget _totals(LayoutElement e, InvoicePrintData d) {
    String valueOf(String k) => LayoutRules.isTotal(k) ? d.totalText(k) : d.field(k);
    final items = e
        .strings('items')
        .where((k) => !(LayoutRules.isTotal(k) && k != 'paymentType' && valueOf(k).isEmpty))
        .toList();
    if (items.isEmpty) return pw.SizedBox();
    final fs = e.d('fontSize', 10);
    final style = e.s('style', 'list');
    final mode = LayoutRules.boxMode(e);
    final hl = e.s('highlight', '');
    final bw = e.d('border', 0.6) > 0 ? e.d('border', 0.6) : 0.6;
    final bc = _c(e.i('borderColor', 0xFF90A4AE));
    final side = pw.BorderSide(width: bw, color: bc);
    final color = e.i('color', 0xFF000000);
    final labelColor = e.i('labelColor', 0xFF455A64);
    final hlColor = e.i('highlightColor', 0xFF0F3460);
    final stacked = e.s('labelPos', style == 'row' ? 'stacked' : 'side') == 'stacked';
    final radius = e.d('radius', 0);
    final title = e.s('title', '').trim();

    pw.Widget cell(String k, {bool lineBottom = false}) {
      final isHl = k == hl;
      final label = pw.Text(LayoutRules.itemLabel(e, k),
          textDirection: pw.TextDirection.rtl,
          maxLines: 1,
          style: _style(stacked ? fs * 0.85 : fs, color: isHl ? 0xFFFFFFFF : labelColor));
      final value = pw.Text(valueOf(k),
          textDirection: _dirOf(valueOf(k)),
          maxLines: 1,
          style: _style(stacked ? fs * 1.15 : fs * 1.05, bold: isHl, color: isHl ? 0xFFFFFFFF : color));
      pw.Border? b;
      if (mode == 'each') {
        b = pw.Border.all(width: bw, color: bc);
      } else if (mode == 'lines' && lineBottom) {
        b = pw.Border(bottom: side);
      }
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: isHl ? _c(hlColor) : null,
          border: b,
          borderRadius: (mode == 'each' && radius > 0) ? pw.BorderRadius.circular(radius * mm) : null,
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 1.5 * PdfPageFormat.mm),
        child: stacked
            ? pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.FittedBox(fit: pw.BoxFit.scaleDown, child: label),
                  pw.FittedBox(fit: pw.BoxFit.scaleDown, child: value),
                ],
              )
            : _ltr(pw.Row(children: [
                pw.FittedBox(fit: pw.BoxFit.scaleDown, child: value),
                pw.SizedBox(width: 2 * mm),
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.FittedBox(fit: pw.BoxFit.scaleDown, child: label),
                  ),
                ),
              ])),
      );
    }

    pw.Widget vGap() => mode == 'each' ? pw.SizedBox(height: 1 * mm) : pw.SizedBox();
    pw.Widget hGap() => mode == 'lines'
        ? pw.Container(width: bw, color: bc)
        : pw.SizedBox(width: (mode == 'each' ? 1.5 : 3) * mm);

    pw.Widget column(List<String> ks) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < ks.length; r++) ...[
              if (r > 0) vGap(),
              pw.Expanded(
                child: ks[r].isEmpty ? pw.SizedBox() : cell(ks[r], lineBottom: r < ks.length - 1),
              ),
            ],
          ],
        );

    pw.Widget body;
    if (style == 'row') {
      body = _ltr(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (var i = items.length - 1; i >= 0; i--) ...[
            pw.Expanded(child: cell(items[i])),
            if (i > 0) hGap(),
          ],
        ],
      ));
    } else if (style == 'grid') {
      final c = e.i('cols', 2).clamp(1, 6).toInt();
      final per = (items.length / c).ceil();
      final columns = <pw.Widget>[];
      // العمود 0 هو الأيمن: البنود من الأعلى للأسفل ثم العمود التالي يساراً
      for (var col = c - 1; col >= 0; col--) {
        final ks = [
          for (var r = 0; r < per; r++) (col * per + r) < items.length ? items[col * per + r] : '',
        ];
        columns.add(pw.Expanded(child: column(ks)));
        if (col > 0) columns.add(hGap());
      }
      body = _ltr(pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: columns));
    } else {
      body = column(items);
    }

    if (title.isNotEmpty) {
      body = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          height: fs * 1.9,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: _c(e.i('titleBg', 0xFF0F3460)),
            border: mode == 'lines' ? pw.Border(bottom: side) : null,
          ),
          child: pw.Text(title,
              textDirection: pw.TextDirection.rtl, style: _style(fs, bold: true, color: e.i('titleColor', 0xFFFFFFFF))),
        ),
        if (mode == 'each') pw.SizedBox(height: 1 * mm),
        pw.Expanded(child: body),
      ]);
    }
    if (mode == 'group' || mode == 'lines') {
      body = pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: bw, color: bc),
          borderRadius: radius > 0 ? pw.BorderRadius.circular(radius * mm) : null,
        ),
        child: body,
      );
    }
    return body;
  }
}
