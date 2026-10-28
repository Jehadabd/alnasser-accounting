// lib/invoice_designer/layout_canvas.dart
//
// 🖼️ رسم التصميم على الشاشة (المصمم والمعاينات المصغّرة) بنفس منطق الطباعة:
// المقاسات بالمليمتر × [scale] بكسل لكل مليمتر. في وضع التحرير: سحب العناصر
// لتحريكها، ومقبض الزاوية لتغيير حجمها.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'invoice_layout.dart';
import 'invoice_print_data.dart';

class LayoutCanvas extends StatelessWidget {
  const LayoutCanvas({
    super.key,
    required this.layout,
    required this.data,
    required this.scale,
    this.selectedId,
    this.interactive = false,
    this.showGrid = false,
    this.onSelect,
    this.onDragStart,
    this.onMove,
    this.onResize,
    this.onDragEnd,
    this.labelOf,
  });

  final InvoiceLayout layout;
  final InvoicePrintData data;

  /// بكسل لكل مليمتر
  final double scale;
  final String? selectedId;
  final bool interactive;
  final bool showGrid;
  final void Function(String? id)? onSelect;
  final void Function(String id)? onDragStart;
  final void Function(String id, double dxMm, double dyMm)? onMove;

  /// تغيير الحجم من زاوية: 'tl' / 'tr' / 'bl' / 'br'
  final void Function(String id, String corner, double dxMm, double dyMm)? onResize;
  final VoidCallback? onDragEnd;

  /// اسم العنصر في الشارة الزرقاء فوق المحدد
  final String Function(LayoutElement e)? labelOf;

  /// ⚫ معاينة «أبيض وأسود» كما ستُطبع
  static const _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final page = _pageWidget(context);
    return layout.mono ? ColorFiltered(colorFilter: _grey, child: page) : page;
  }

  Widget _pageWidget(BuildContext context) {
    final s = scale;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: layout.widthMm * s,
        height: layout.heightMm * s,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? () => onSelect?.call(null) : null,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: Container(color: Colors.white)),
              if (showGrid) Positioned.fill(child: CustomPaint(painter: _GridPainter(s))),
              for (final e in layout.elements) _positioned(e, s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positioned(LayoutElement e, double s) {
    Widget child = ElementPreview(element: e, data: data, scale: s);
    if (interactive) {
      child = _ElementFrame(
        element: e,
        scale: s,
        selected: e.id == selectedId,
        label: labelOf?.call(e) ?? '',
        onSelect: () => onSelect?.call(e.id),
        onDragStart: () => onDragStart?.call(e.id),
        onMove: (dx, dy) => onMove?.call(e.id, dx, dy),
        onResize: (c, dx, dy) => onResize?.call(e.id, c, dx, dy),
        onDragEnd: () => onDragEnd?.call(),
        child: child,
      );
    }
    return Positioned(
      left: e.x * s,
      top: e.y * s,
      width: math.max(1, e.w * s),
      height: math.max(1, e.h * s),
      child: child,
    );
  }
}

/// إطار التحرير حول العنصر: تحويم، تحديد، سحب، وأربع زوايا لتغيير الحجم
class _ElementFrame extends StatefulWidget {
  const _ElementFrame({
    required this.element,
    required this.scale,
    required this.selected,
    required this.label,
    required this.onSelect,
    required this.onDragStart,
    required this.onMove,
    required this.onResize,
    required this.onDragEnd,
    required this.child,
  });

  final LayoutElement element;
  final double scale;
  final bool selected;
  final String label;
  final VoidCallback onSelect;
  final VoidCallback onDragStart;
  final void Function(double dx, double dy) onMove;
  final void Function(String corner, double dx, double dy) onResize;
  final VoidCallback onDragEnd;
  final Widget child;

  @override
  State<_ElementFrame> createState() => _ElementFrameState();
}

class _ElementFrameState extends State<_ElementFrame> {
  bool _hover = false;
  static const _blue = Color(0xFF1E88E5);

  Widget _handle(String corner) {
    final cursor = (corner == 'tl' || corner == 'br')
        ? SystemMouseCursors.resizeUpLeftDownRight
        : SystemMouseCursors.resizeUpRightDownLeft;
    return Positioned(
      left: corner.endsWith('l') ? 0 : null,
      right: corner.endsWith('r') ? 0 : null,
      top: corner.startsWith('t') ? 0 : null,
      bottom: corner.startsWith('b') ? 0 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => widget.onDragStart(),
        onPanUpdate: (d) => widget.onResize(corner, d.delta.dx / widget.scale, d.delta.dy / widget.scale),
        onPanEnd: (_) => widget.onDragEnd(),
        child: MouseRegion(
          cursor: cursor,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _blue, width: 2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onPanStart: (_) {
          widget.onSelect();
          widget.onDragStart();
        },
        onPanUpdate: (d) => widget.onMove(d.delta.dx / widget.scale, d.delta.dy / widget.scale),
        onPanEnd: (_) => widget.onDragEnd(),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: widget.child),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: sel ? _blue.withValues(alpha: 0.05) : (_hover ? _blue.withValues(alpha: 0.03) : null),
                  border: Border.all(
                    color: sel ? _blue : (_hover ? _blue.withValues(alpha: 0.55) : const Color(0x14000000)),
                    width: sel ? 1.6 : 1,
                  ),
                ),
              ),
            ),
          ),
          if (sel && widget.label.isNotEmpty)
            Positioned(
              left: 14,
              top: -16,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(widget.label,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.2)),
                ),
              ),
            ),
          if (sel) ...[_handle('tl'), _handle('tr'), _handle('bl'), _handle('br')],
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x11000000)
      ..strokeWidth = 1;
    final step = 5 * s; // كل 5 ملم
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.s != s;
}

/// رسم عنصر واحد (يحاكي الطباعة)
class ElementPreview extends StatelessWidget {
  const ElementPreview({super.key, required this.element, required this.data, required this.scale});

  final LayoutElement element;
  final InvoicePrintData data;
  final double scale;

  /// النقطة الطباعية ← بكسل
  double _pt(double pt) => pt * 0.3528 * scale;

  static Alignment _alignment(String a) =>
      a == 'center' ? Alignment.center : (a == 'left' ? Alignment.centerLeft : Alignment.centerRight);
  static TextAlign _textAlign(String a) =>
      a == 'center' ? TextAlign.center : (a == 'left' ? TextAlign.left : TextAlign.right);

  TextStyle _style(double fs, {bool bold = false, int color = 0xFF000000}) => TextStyle(
        fontSize: math.max(1.0, _pt(fs)),
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: Color(color),
        height: 1.25,
      );

  BoxDecoration? _boxDecoration(LayoutElement e, {double defaultBorder = 0}) {
    final border = e.d('border', defaultBorder);
    final bg = e.i('bg', 0);
    final radius = e.d('radius', 0);
    if (border <= 0 && bg == 0) return null;
    return BoxDecoration(
      color: bg != 0 ? Color(bg) : null,
      border: border > 0
          ? Border.all(width: math.max(0.5, _pt(border)), color: Color(e.i('borderColor', 0xFF000000)))
          : null,
      borderRadius: radius > 0 ? BorderRadius.circular(radius * scale) : null,
    );
  }

  Widget _textBox(LayoutElement e, String text) {
    final fs = e.d('fontSize', 10);
    final align = e.s('align', 'right');
    final deco = _boxDecoration(e);
    final style = _style(fs, bold: e.b('bold', false), color: e.i('color', 0xFF000000));
    final lines = math.max(1, ((e.h * scale) / (style.fontSize! * 1.25)).floor());
    final multi = lines > 1 || text.contains('\n');
    return Container(
      alignment: _alignment(align),
      padding: EdgeInsets.symmetric(horizontal: deco != null ? 1.2 * scale : 0),
      decoration: deco,
      child: multi
          ? Text(text,
              style: style,
              textAlign: _textAlign(align),
              textDirection: TextDirection.rtl,
              maxLines: math.max(lines, text.split('\n').length),
              overflow: TextOverflow.clip)
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: _alignment(align),
              child: Text(text, style: style, textDirection: TextDirection.rtl, maxLines: 1),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = element;
    final d = data;
    switch (e.type) {
      case ElType.logo:
        final bytes = d.company.logo;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: const Color(0xFFF1F5F9),
            alignment: Alignment.center,
            child: const FittedBox(
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.image_outlined, color: Colors.blueGrey),
                  Text('الشعار', style: TextStyle(color: Colors.blueGrey, fontSize: 11)),
                ]),
              ),
            ),
          );
        }
        return Image.memory(bytes, fit: BoxFit.contain);
      case ElType.companyName:
        return _textBox(e, d.company.name);
      case ElType.companyInfo:
        final text = [
          for (final k in e.strings('lines'))
            if ((d.company.lines[k] ?? '').isNotEmpty) d.company.lines[k]!,
        ].join('\n');
        return _textBox(e, text.isEmpty ? 'معلومات الشركة' : text);
      case ElType.text:
        return _textBox(e, d.fill(e.s('text', '')));
      case ElType.field:
        final key = e.s('key', 'customer');
        final v = d.field(key);
        final label = e.s('label', LayoutCatalog.fields[key] ?? '');
        final show = e.b('showLabel', true) && label.trim().isNotEmpty;
        return _textBox(e, show ? '$label: $v' : v);
      case ElType.pageNo:
        return _textBox(e, 'صفحة 1 من 1');
      case ElType.line:
        final t = math.max(0.6, _pt(e.d('thickness', 0.8)));
        final c = Color(e.i('color', 0xFF000000));
        final vertical = e.h > e.w;
        return Center(
          child: vertical
              ? Container(width: t, color: c)
              : (e.b('dashed', false)
                  ? CustomPaint(size: Size(e.w * scale, t), painter: _DashPainter(c, t))
                  : Container(height: t, color: c)),
        );
      case ElType.box:
        return Container(decoration: _boxDecoration(e, defaultBorder: 0.8));
      case ElType.barcode:
        final qr = e.s('kind', 'qr') == 'qr';
        return FittedBox(
          child: Icon(qr ? Icons.qr_code_2 : Icons.view_week_outlined, color: Colors.black87),
        );
      case ElType.watermark:
        final t = e.s('text', '');
        final text = t.trim().isEmpty ? d.company.name : d.fill(t);
        return Center(
          child: Transform.rotate(
            angle: -e.d('angle', 0.8),
            child: Opacity(
              opacity: e.d('opacity', 0.08).clamp(0.01, 1.0).toDouble(),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text,
                    textDirection: TextDirection.rtl,
                    style: _style(e.d('fontSize', 100), bold: true, color: e.i('color', 0xFF9E9E9E))),
              ),
            ),
          ),
        );
      case ElType.table:
        return _table(e);
      case ElType.totals:
        return _totals(e);
      default:
        return const SizedBox();
    }
  }

  // ── جدول المواد ──

  Widget _table(LayoutElement t) {
    final cols = t.columns;
    if (cols.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
        alignment: Alignment.center,
        child: const Text('جدول المواد — أضف أعمدة من الخصائص', textDirection: TextDirection.rtl),
      );
    }
    final rowH = t.d('rowHeight', 8).clamp(3.0, 60.0).toDouble();
    final headH = t.d('headerHeight', rowH).clamp(3.0, 60.0).toDouble();
    final fs = t.d('fontSize', 10);
    final mode = LayoutRules.tableBorders(t);
    final zebra = t.b('zebra', false);
    final lineColor = Color(t.i('gridColor', 0xFF9E9E9E));
    final lw = math.max(0.5, _pt(t.d('lineWidth', 0.4)));
    final side = BorderSide(width: lw, color: lineColor);
    double flex(Map<String, dynamic> c) => (c['flex'] is num && (c['flex'] as num) > 0) ? (c['flex'] as num).toDouble() : 1.0;
    final flexes = [for (final c in cols) math.max(1, (flex(c) * 100).round())];
    final cap = math.max(0, ((t.h - headH) / rowH).floor());
    final rows = data.rows;
    final framed = mode == 'columns' || mode == 'outer';

    Widget row(List<String> texts, {required bool header, int index = 0}) {
      final h = (header ? headH : rowH) * scale;
      final cells = <Widget>[];
      for (var i = cols.length - 1; i >= 0; i--) {
        final align = header ? 'center' : '${cols[i]['align'] ?? 'center'}';
        final leftmost = i == cols.length - 1;
        Border? b;
        if (mode == 'grid') {
          b = Border.all(width: lw, color: lineColor);
        } else if (mode == 'columns' && !leftmost) {
          b = Border(left: side);
        }
        cells.add(Expanded(
          flex: flexes[i],
          child: Container(
            height: h,
            alignment: _alignment(align),
            padding: EdgeInsets.symmetric(horizontal: 0.8 * scale),
            decoration: b == null ? null : BoxDecoration(border: b),
            child: Text(
              texts[i],
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: _textAlign(align),
              textDirection: TextDirection.rtl,
              style: _style(fs,
                  bold: header, color: header ? t.i('headerColor', 0xFF000000) : t.i('color', 0xFF000000)),
            ),
          ),
        ));
      }
      final bg = header ? t.i('headerBg', 0xFFE8EEF5) : (zebra && index.isOdd ? 0xFFF1F5F9 : 0);
      final underline = header ? (mode != 'grid' && mode != 'none') : mode == 'rows';
      return Container(
        decoration: BoxDecoration(
          color: bg != 0 ? Color(bg) : null,
          border: underline ? Border(bottom: side) : null,
        ),
        child: Row(children: cells),
      );
    }

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row([for (final c in cols) '${c['label'] ?? ''}'], header: true),
        for (var r = 0; r < cap; r++)
          row([for (final c in cols) r < rows.length ? (rows[r]['${c['id']}'] ?? '') : ''], header: false, index: r),
      ],
    );
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxHeight: double.infinity,
        child: framed
            ? Container(
                decoration: BoxDecoration(border: Border.all(width: lw * 1.5, color: lineColor)),
                child: body,
              )
            : body,
      ),
    );
  }

  // ── المجاميع / البيانات ──

  Widget _totals(LayoutElement e) {
    String valueOf(String k) => LayoutRules.isTotal(k) ? data.totalText(k) : data.field(k);
    final items = e.strings('items');
    if (items.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
        alignment: Alignment.center,
        child: const Text('اختر البنود من الخصائص', textDirection: TextDirection.rtl),
      );
    }
    final fs = e.d('fontSize', 10);
    final style = e.s('style', 'list');
    final mode = LayoutRules.boxMode(e);
    final hl = e.s('highlight', '');
    final bwPt = e.d('border', 0.6) > 0 ? e.d('border', 0.6) : 0.6;
    final bw = math.max(0.5, _pt(bwPt));
    final bc = Color(e.i('borderColor', 0xFF90A4AE));
    final side = BorderSide(width: bw, color: bc);
    final color = e.i('color', 0xFF000000);
    final labelColor = e.i('labelColor', 0xFF455A64);
    final hlColor = e.i('highlightColor', 0xFF0F3460);
    final stacked = e.s('labelPos', style == 'row' ? 'stacked' : 'side') == 'stacked';
    final radius = e.d('radius', 0);
    final title = e.s('title', '').trim();

    Widget cell(String k, {bool lineBottom = false}) {
      final isHl = k == hl;
      final label = Text(LayoutRules.itemLabel(e, k),
          textDirection: TextDirection.rtl,
          maxLines: 1,
          style: _style(stacked ? fs * 0.85 : fs, color: isHl ? 0xFFFFFFFF : labelColor));
      final value = Text(valueOf(k),
          textDirection: TextDirection.rtl,
          maxLines: 1,
          style: _style(stacked ? fs * 1.15 : fs * 1.05, bold: isHl, color: isHl ? 0xFFFFFFFF : color));
      Border? b;
      if (mode == 'each') {
        b = Border.all(width: bw, color: bc);
      } else if (mode == 'lines' && lineBottom) {
        b = Border(bottom: side);
      }
      return Container(
        decoration: BoxDecoration(
          color: isHl ? Color(hlColor) : null,
          border: b,
          borderRadius: (mode == 'each' && radius > 0) ? BorderRadius.circular(radius * scale) : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: 1.5 * scale),
        child: stacked
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: label)),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: value)),
              ])
            : Row(children: [
                FittedBox(fit: BoxFit.scaleDown, child: value),
                SizedBox(width: 2 * scale),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: label),
                  ),
                ),
              ]),
      );
    }

    Widget vGap() => mode == 'each' ? SizedBox(height: 1 * scale) : const SizedBox.shrink();
    Widget hGap() => mode == 'lines' ? Container(width: bw, color: bc) : SizedBox(width: (mode == 'each' ? 1.5 : 3) * scale);

    Widget column(List<String> ks) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < ks.length; r++) ...[
              if (r > 0) vGap(),
              Expanded(child: ks[r].isEmpty ? const SizedBox() : cell(ks[r], lineBottom: r < ks.length - 1)),
            ],
          ],
        );

    Widget body;
    if (style == 'row') {
      body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = items.length - 1; i >= 0; i--) ...[
          Expanded(child: cell(items[i])),
          if (i > 0) hGap(),
        ],
      ]);
    } else if (style == 'grid') {
      final c = e.i('cols', 2).clamp(1, 6).toInt();
      final per = (items.length / c).ceil();
      final columns = <Widget>[];
      for (var col = c - 1; col >= 0; col--) {
        final ks = [for (var r = 0; r < per; r++) (col * per + r) < items.length ? items[col * per + r] : ''];
        columns.add(Expanded(child: column(ks)));
        if (col > 0) columns.add(hGap());
      }
      body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns);
    } else {
      body = column(items);
    }

    if (title.isNotEmpty) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: _pt(fs * 1.9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color(e.i('titleBg', 0xFF0F3460)),
            border: mode == 'lines' ? Border(bottom: side) : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(title,
                textDirection: TextDirection.rtl, style: _style(fs, bold: true, color: e.i('titleColor', 0xFFFFFFFF))),
          ),
        ),
        if (mode == 'each') SizedBox(height: 1 * scale),
        Expanded(child: body),
      ]);
    }
    if (mode == 'group' || mode == 'lines') {
      body = Container(
        decoration: BoxDecoration(
          border: Border.all(width: bw, color: bc),
          borderRadius: radius > 0 ? BorderRadius.circular(radius * scale) : null,
        ),
        clipBehavior: radius > 0 ? Clip.antiAlias : Clip.none,
        child: body,
      );
    }
    return body;
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = t;
    const dash = 4.0;
    for (double x = 0; x < size.width; x += dash * 2) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(math.min(x + dash, size.width), size.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color || old.t != t;
}
