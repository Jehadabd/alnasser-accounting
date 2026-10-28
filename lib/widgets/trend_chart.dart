// lib/widgets/trend_chart.dart
//
// 📈 منحنى التوجهات — نفس منحنى «المبيعات الشهرية» في التقرير السنوي السابق
// (خط ناعم بتعبئة متدرجة، خط عمودي منقّط، ونافذة داكنة: التاريخ، المبيعات،
// الأرباح، التكلفة، الفواتير)، معمّم لأي فترة: ساعات يوم، أيام، أو أشهر.
// يدعم القيم السالبة (ربح سالب) ونقطة واحدة، ويُخفي الربح والكلفة عمّن لا يملك صلاحيتها.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'report_kit.dart' show repMoney;

class TrendPoint {
  const TrendPoint({
    required this.title,
    this.axisLabel,
    required this.sales,
    required this.cost,
    required this.profit,
    required this.invoices,
  });

  /// يظهر في النافذة (مثلاً «الأحد 16/8»).
  final String title;

  /// يُكتب تحت المحور (null = بلا عنوان لهذه النقطة).
  final String? axisLabel;
  final double sales;
  final double cost;
  final double profit;
  final int invoices;
}

/// المقاييس: sales | cost | profit | invoices | compareAll
class TrendMetric {
  static const sales = 'sales';
  static const cost = 'cost';
  static const profit = 'profit';
  static const invoices = 'invoices';
  static const compareAll = 'compareAll';

  static Color line(String m) => switch (m) {
        profit => const Color(0xFF059669),
        cost => const Color(0xFFDC2626),
        invoices => const Color(0xFF7C3AED),
        compareAll => const Color(0xFF4F46E5),
        _ => const Color(0xFF2563EB),
      };
}

class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    required this.metric,
    required this.canProfit,
    required this.selected,
    required this.onSelect,
  });

  final List<TrendPoint> points;
  final String metric;
  final bool canProfit;
  final int selected;
  final ValueChanged<int> onSelect;

  static const double _marginX = 24.0;

  void _touch(Offset p, double width) {
    final n = points.length;
    if (n == 0) return;
    if (n == 1) {
      onSelect(0);
      return;
    }
    final availW = width - _marginX * 2;
    if (availW <= 0) return;
    final i = (((p.dx - _marginX) / availW) * (n - 1)).round().clamp(0, n - 1).toInt();
    if (i != selected) onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Center(child: Text('لا توجد بيانات'));
    return LayoutBuilder(
      builder: (context, c) => MouseRegion(
        onHover: (e) => _touch(e.localPosition, c.maxWidth),
        child: GestureDetector(
          onTapDown: (d) => _touch(d.localPosition, c.maxWidth),
          onPanStart: (d) => _touch(d.localPosition, c.maxWidth),
          onPanUpdate: (d) => _touch(d.localPosition, c.maxWidth),
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _TrendPainter(
              points: points,
              metric: metric,
              canProfit: canProfit,
              selected: selected.clamp(0, points.length - 1).toInt(),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.metric, required this.canProfit, required this.selected});

  final List<TrendPoint> points;
  final String metric;
  final bool canProfit;
  final int selected;

  static const double marginX = 24.0;
  static const double marginYTop = 36.0;
  static const double marginYBottom = 32.0;

  List<double> _values(String m) => [
        for (final p in points)
          switch (m) {
            TrendMetric.profit => p.profit,
            TrendMetric.cost => p.cost,
            TrendMetric.invoices => p.invoices.toDouble(),
            _ => p.sales,
          }
      ];

  List<Offset> _offsets(List<double> v, double minV, double maxV, double chartW, double chartH) {
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    return [
      for (var i = 0; i < v.length; i++)
        Offset(
          v.length == 1 ? marginX + chartW / 2 : marginX + (i / (v.length - 1)) * chartW,
          marginYTop + chartH - ((v[i] - minV) / range).clamp(0.0, 1.0) * chartH,
        )
    ];
  }

  void _curve(Canvas canvas, Size size, List<Offset> pts, Color color, double baseY, {required bool fill, required double chartH}) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, 4, Paint()..color = color);
      return;
    }
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    final area = Path()
      ..moveTo(pts[0].dx, baseY)
      ..lineTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i], p1 = pts[i + 1];
      final mx = p0.dx + (p1.dx - p0.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
      area.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    area
      ..lineTo(pts.last.dx, baseY)
      ..close();
    if (fill) {
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.01)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(Rect.fromLTWH(0, marginYTop, size.width, chartH)),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final chartW = size.width - marginX * 2;
    final chartH = size.height - marginYTop - marginYBottom;
    final compare = metric == TrendMetric.compareAll;
    final lineColor = TrendMetric.line(metric);

    final main = _values(compare ? TrendMetric.sales : metric);
    final series = compare
        ? [
            _values(TrendMetric.sales),
            if (canProfit) _values(TrendMetric.cost),
            if (canProfit) _values(TrendMetric.profit),
          ]
        : [main];
    var maxV = 0.0, minV = 0.0;
    for (final s in series) {
      for (final v in s) {
        maxV = math.max(maxV, v);
        minV = math.min(minV, v);
      }
    }
    if (maxV == minV) maxV = minV + 1;

    // شبكة أفقية + خط الصفر إن وُجدت قيم سالبة
    final grid = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = marginYTop + chartH / 3 * i;
      canvas.drawLine(Offset(marginX, y), Offset(size.width - marginX, y), grid);
    }
    final zeroY = marginYTop + chartH - ((0 - minV) / (maxV - minV)) * chartH;
    if (minV < 0) {
      canvas.drawLine(Offset(marginX, zeroY), Offset(size.width - marginX, zeroY),
          Paint()
            ..color = const Color(0xFFCBD5E1)
            ..strokeWidth = 1);
    }

    final mainPts = _offsets(main, minV, maxV, chartW, chartH);
    if (compare) {
      _curve(canvas, size, mainPts, const Color(0xFF2563EB), zeroY, fill: true, chartH: chartH);
      if (canProfit) {
        _curve(canvas, size, _offsets(series[1], minV, maxV, chartW, chartH), const Color(0xFFDC2626), zeroY,
            fill: false, chartH: chartH);
        _curve(canvas, size, _offsets(series[2], minV, maxV, chartW, chartH), const Color(0xFF059669), zeroY,
            fill: false, chartH: chartH);
      }
    } else {
      _curve(canvas, size, mainPts, lineColor, zeroY, fill: true, chartH: chartH);
    }

    // عناوين المحور
    const axisStyle = TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600);
    var lastRight = -1e9;
    for (var i = 0; i < points.length; i++) {
      final label = points[i].axisLabel;
      if (label == null) continue;
      final tp = TextPainter(text: TextSpan(text: label, style: axisStyle), textDirection: TextDirection.rtl)..layout();
      final x = mainPts[i].dx - tp.width / 2;
      if (x < lastRight + 4) continue; // لا تتراكب العناوين
      tp.paint(canvas, Offset(x, size.height - marginYBottom + 8));
      lastRight = x + tp.width;
    }

    // الخط المنقّط والنقطة المختارة
    final i = selected;
    final p = mainPts[i];
    final dash = Paint()
      ..color = lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 1.5;
    for (var y = marginYTop; y < size.height - marginYBottom; y += 8) {
      canvas.drawLine(Offset(p.dx, y), Offset(p.dx, math.min(y + 4, size.height - marginYBottom)), dash);
    }
    canvas.drawCircle(p, 10, Paint()..color = lineColor.withValues(alpha: 0.25));
    canvas.drawCircle(p, 6, Paint()..color = lineColor);
    canvas.drawCircle(p, 3, Paint()..color = Colors.white);

    // النافذة الداكنة
    final pt = points[i];
    final tip = TextPainter(
      text: TextSpan(children: [
        TextSpan(
            text: '  ${pt.title}  \n',
            style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w900)),
        TextSpan(
            text: '• المبيعات: ${repMoney(pt.sales)} د.ع${canProfit ? '\n' : ''}',
            style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 10, fontWeight: FontWeight.bold)),
        if (canProfit) ...[
          TextSpan(
              text: '• الأرباح: ${repMoney(pt.profit)} د.ع\n',
              style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 10, fontWeight: FontWeight.bold)),
          TextSpan(
              text: '• التكلفة: ${repMoney(pt.cost)} د.ع',
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 10, fontWeight: FontWeight.bold)),
        ],
        TextSpan(
            text: '\n• الفواتير: ${pt.invoices} فاتورة',
            style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
      textDirection: TextDirection.rtl,
    )..layout();
    final w = tip.width + 20, h = tip.height + 14;
    var x = p.dx + 12;
    if (x + w > size.width - 8) x = p.dx - w - 12;
    if (x < 4) x = 4;
    var y = p.dy - h / 2;
    if (y < marginYTop) y = marginYTop;
    if (y + h > size.height - marginYBottom) y = size.height - marginYBottom - h;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(12));
    canvas.drawRRect(r.shift(const Offset(0, 4)), Paint()..color = Colors.black.withValues(alpha: 0.3));
    canvas.drawRRect(r, Paint()..color = const Color(0xFF0F172A));
    canvas.drawRRect(
        r,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    tip.paint(canvas, Offset(x + 10, y + 7));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points || old.metric != metric || old.selected != selected || old.canProfit != canProfit;
}
