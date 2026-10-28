// lib/widgets/report_kit.dart
//
// 📈 طقم شاشات التقارير — نفس هوية بقية البرنامج (رأس كحلي، بطاقات بيضاء):
//   • ReportScaffold — رأس + ثيم موحّد + محتوى بعرض مريح وظهور متتابع.
//   • SourceMenu — الكل / هذا الجهاز / المزامنة (بدل مفاتيح مختلفة في كل شاشة).
//   • PeriodNavigator — ◀ الفترة ▶ مع اختيار مباشر (الأشهر بالأرقام).
//   • KpiTile / KpiGrid — مؤشرات مرتّبة تتأقلم مع عرض الشاشة.
//   • MiniBars — رسم أعمدة خفيف بتلميحات (لا يحتاج مكتبة).
//   • RankRow — صف ترتيب بشريط نسبة.
//   • MoneyLabel — المبلغ السالب أحمر وبإشارته (كانت الخسارة تُعرض ربحاً).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../accounting/screens/acc_ui.dart' show accAppBar, FadeSlideIn, pickDate;
import '../erp/erp_kit.dart' show ErpTheme;
import '../models/app_user.dart' show AppPermissions;
import '../services/auth_service.dart';
import 'settings_kit.dart';

export 'settings_kit.dart'
    show SetCard, SetBanner, SetBannerKind, SetStatusPill, kSetNavy, kSetBg, kSetBorder, kSetText, kSetMuted, kSetGreen, kSetRed, kSetOrange, kSetBlue, setToast;

const kRepPurple = Color(0xFF6D28D9);
const kRepTeal = Color(0xFF0F766E);
const kRepAmber = Color(0xFFB45309);

final NumberFormat _money = NumberFormat('#,##0', 'en_US');
final NumberFormat _qty = NumberFormat('#,##0.##', 'en_US');
final DateFormat _day = DateFormat('yyyy/MM/dd', 'en_US');

/// مبلغ بلا كسور (الدينار) — السالب بإشارته.
String repMoney(num v) => (v < 0 ? '-' : '') + _money.format(v.abs());
String repQty(num v) => _qty.format(v);
String repDate(DateTime d) => _day.format(d);
String repMonth(int year, int month) => 'شهر $month / $year';
String repPercent(num v) => '${v.toStringAsFixed(1)}%';

/// شاشة تقرير بالشكل الموحّد.
class ReportScaffold extends StatelessWidget {
  const ReportScaffold({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.actions,
    this.children,
    this.body,
    this.loading = false,
    this.maxWidth = 1180,
    this.header,
    this.onRefresh,
    this.floatingActionButton,
  }) : assert(children != null || body != null || loading);

  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget>? actions;
  final List<Widget>? children;
  final Widget? body;
  final bool loading;
  final double maxWidth;

  /// عنصر ثابت أعلى المحتوى (شريط الفترة مثلاً) لا يتحرك مع التمرير.
  final Widget? header;
  final Future<void> Function()? onRefresh;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (body != null) {
      content = body!;
    } else {
      final list = children!;
      Widget lv = ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        children: [for (var i = 0; i < list.length; i++) FadeSlideIn(index: i, child: list[i])],
      );
      if (onRefresh != null) lv = RefreshIndicator(onRefresh: onRefresh!, child: lv);
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: lv),
      );
    }
    return Theme(
      data: ErpTheme.apply(Theme.of(context)),
      child: Scaffold(
        backgroundColor: kSetBg,
        appBar: accAppBar(title, icon: icon, subtitle: subtitle, actions: actions),
        floatingActionButton: floatingActionButton,
        body: Column(children: [
          if (header != null)
            Material(
              color: Colors.white,
              elevation: 0,
              child: Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kSetBorder))),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: header!),
                ),
              ),
            ),
          Expanded(child: content),
        ]),
      ),
    );
  }
}

/// اختيار مصدر البيانات (في رأس الشاشة).
class SourceMenu extends StatelessWidget {
  const SourceMenu({super.key, required this.value, required this.onChanged});
  final String value; // all | this_device | sync
  final ValueChanged<String> onChanged;

  static const _items = <(String, String, IconData)>[
    ('all', 'كل الأجهزة', Icons.all_inclusive_rounded),
    ('this_device', 'هذا الجهاز فقط', Icons.computer_rounded),
    ('sync', 'المزامنة فقط', Icons.sync_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final cur = _items.firstWhere((e) => e.$1 == value, orElse: () => _items.first);
    return PopupMenuButton<String>(
      tooltip: 'مصدر البيانات',
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        for (final e in _items)
          PopupMenuItem(
            value: e.$1,
            child: Row(children: [
              Icon(e.$3, size: 19, color: e.$1 == value ? kSetNavy : kSetMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(e.$2,
                    style: TextStyle(fontWeight: e.$1 == value ? FontWeight.w800 : FontWeight.w500, color: kSetText)),
              ),
              if (e.$1 == value) const Icon(Icons.check_rounded, size: 18, color: kSetNavy),
            ]),
          ),
      ],
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(cur.$3, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(cur.$2, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
        ]),
      ),
    );
  }
}

/// ◀ عنوان الفترة ▶ — الضغط على العنوان يفتح الاختيار.
class PeriodNavigator extends StatelessWidget {
  const PeriodNavigator({
    super.key,
    required this.label,
    this.caption,
    required this.onPrev,
    required this.onNext,
    this.onPick,
    this.canNext = true,
    this.trailing,
    this.leading,
  });
  final String label;
  final String? caption;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onPick;
  final bool canNext;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    // في RTL: «السابق» على اليمين (سهم يشير يميناً) و«التالي» على اليسار.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (leading != null) leading!,
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton.filledTonal(
              tooltip: 'السابق',
              onPressed: onPrev,
              // الأيقونة تنعكس في RTL: chevron_left يظهر «›» على اليمين
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            const SizedBox(width: 6),
            Material(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onPick,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (onPick != null) ...[
                        const Icon(Icons.event_rounded, size: 17, color: kSetNavy),
                        const SizedBox(width: 6),
                      ],
                      Text(label,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kSetText)),
                    ]),
                    if (caption != null)
                      Text(caption!, style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'التالي',
              onPressed: canNext ? onNext : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// مبلغ: السالب بالأحمر مع إشارته.
class MoneyLabel extends StatelessWidget {
  const MoneyLabel(this.value, {super.key, this.size = 14, this.bold = true, this.color, this.suffix = ''});
  final double value;
  final double size;
  final bool bold;
  final Color? color;
  final String suffix;
  @override
  Widget build(BuildContext context) => Text(
        '${repMoney(value)}$suffix',
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: value < 0 ? kSetRed : (color ?? kSetText),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

/// نسبة تغيّر ↑/↓ (الأخضر للتحسن). [inverse] للمؤشرات التي ارتفاعها سيئ (المرتجعات).
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.percent, {super.key, this.inverse = false, this.label});
  final double percent;
  final bool inverse;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final up = percent > 0.05;
    final down = percent < -0.05;
    final good = inverse ? down : up;
    final bad = inverse ? up : down;
    final c = good ? kSetGreen : (bad ? kSetRed : kSetMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.trending_up_rounded : (down ? Icons.trending_down_rounded : Icons.trending_flat_rounded),
            size: 14, color: c),
        const SizedBox(width: 3),
        Text('${percent.abs().toStringAsFixed(1)}%${label == null ? '' : ' $label'}',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
      ]),
    );
  }
}

/// مؤشر رقمي في بطاقة.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = kSetNavy,
    this.hint,
    this.delta,
    this.deltaInverse = false,
    this.onTap,
    this.money = true,
    this.emphasis = false,
  });
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final String? hint;
  final double? delta;
  final bool deltaInverse;
  final VoidCallback? onTap;

  /// false = عدد (فواتير…) بلا تلوين للسالب.
  final bool money;

  /// بطاقة بارزة (خلفية ملوّنة).
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final sub = emphasis ? Colors.white70 : kSetMuted;
    final valueColor = emphasis ? Colors.white : (money && value < 0 ? kSetRed : kSetText);
    return Material(
      color: emphasis ? color : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: emphasis ? color : kSetBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: emphasis ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: emphasis ? Colors.white : color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: sub, fontWeight: FontWeight.w600)),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: sub),
            ]),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  money ? repMoney(value) : repQty(value),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: valueColor),
                ),
              ),
            ),
            if (hint != null || delta != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (delta != null) DeltaChip(delta!, inverse: deltaInverse),
                if (hint != null) Text(hint!, style: TextStyle(fontSize: 11.5, color: sub)),
              ]),
            ],
            if (hint == null && delta == null) const SizedBox(height: 2),
          ]),
        ),
      ),
    );
  }
}

/// شبكة مؤشرات بعرض متكيّف.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children, this.minTileWidth = 200, this.spacing = 12});
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = math.max(1, ((c.maxWidth + spacing) / (minTileWidth + spacing)).floor());
      final n = math.min(cols, children.length);
      final w = (c.maxWidth - (n - 1) * spacing) / n;
      return Wrap(spacing: spacing, runSpacing: spacing, children: [
        for (final ch in children) SizedBox(width: w, child: ch),
      ]);
    });
  }
}

/// رسم أعمدة خفيف. [values] قد تحوي سالباً (يُرسم أحمر).
class MiniBars extends StatefulWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.labels,
    this.tooltips,
    this.color = kSetNavy,
    this.height = 180,
    this.highlight,
    this.onTap,
    this.showEveryLabel,
  });
  final List<double> values;
  final List<String> labels;
  final List<String>? tooltips;
  final Color color;
  final double height;

  /// عمود مميّز (اليوم الحالي مثلاً).
  final int? highlight;
  final ValueChanged<int>? onTap;

  /// إظهار عنوان كل n عمود (تلقائي حسب العدد إن لم يُحدد).
  final int? showEveryLabel;

  @override
  State<MiniBars> createState() => _MiniBarsState();
}

class _MiniBarsState extends State<MiniBars> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final vals = widget.values;
    final maxV = vals.fold<double>(0, (m, v) => math.max(m, v.abs()));
    final every = widget.showEveryLabel ?? (vals.length <= 14 ? 1 : (vals.length <= 31 ? 3 : 5));
    final barArea = widget.height - 22;
    return SizedBox(
      height: widget.height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < vals.length; i++)
          Expanded(
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = i),
              onExit: (_) => setState(() => _hover = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap == null ? null : () => widget.onTap!(i),
                child: Tooltip(
                  message: widget.tooltips != null ? widget.tooltips![i] : '${widget.labels[i]}\n${repMoney(vals[i])}',
                  waitDuration: const Duration(milliseconds: 150),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    AnimatedContainer(
                      duration: Duration(milliseconds: 260 + (i * 12).clamp(0, 400).toInt()),
                      curve: Curves.easeOutCubic,
                      height: maxV <= 0 ? 2 : math.max(2, barArea * vals[i].abs() / maxV),
                      margin: EdgeInsets.symmetric(horizontal: vals.length > 40 ? 0.5 : 2.5),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        color: vals[i] < 0
                            ? kSetRed
                            : (i == widget.highlight
                                ? kSetGreen
                                : (_hover == i ? widget.color : widget.color.withValues(alpha: 0.72))),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 14,
                      child: (i % every == 0 || i == vals.length - 1)
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(widget.labels[i], style: const TextStyle(fontSize: 10, color: kSetMuted)),
                            )
                          : null,
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// صف ترتيب: رقم + اسم + قيمة + شريط نسبة.
class RankRow extends StatelessWidget {
  const RankRow({
    super.key,
    required this.rank,
    required this.title,
    required this.value,
    this.subtitle,
    this.fraction = 0,
    this.color = kSetNavy,
    this.onTap,
    this.trailing,
  });
  final int rank;
  final String title;
  final String? subtitle;
  final double value;
  final double fraction;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final medal = rank == 1 ? const Color(0xFFD4A017) : (rank == 2 ? const Color(0xFF94A3B8) : (rank == 3 ? const Color(0xFFB45309) : null));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: medal ?? const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Text('$rank',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: medal != null ? Colors.white : kSetText)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: kSetMuted)),
              ]),
            ),
            const SizedBox(width: 8),
            trailing ?? MoneyLabel(value),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 5,
              color: value < 0 ? kSetRed : color,
              backgroundColor: const Color(0xFFF1F5F9),
            ),
          ),
        ]),
      ),
    );
  }
}

/// حالة فارغة.
class EmptyReport extends StatelessWidget {
  const EmptyReport({super.key, required this.title, this.text, this.icon = Icons.insights_rounded});
  final String title;
  final String? text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: Column(children: [
          Icon(icon, size: 52, color: const Color(0xFFB8C2CF)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: kSetText)),
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(text!, textAlign: TextAlign.center, style: const TextStyle(color: kSetMuted, height: 1.5)),
          ],
        ]),
      );
}

/// سطر «عنوان … قيمة» داخل بطاقة.
class ReportLine extends StatelessWidget {
  const ReportLine(this.label, this.value, {super.key, this.icon, this.color, this.bold = false, this.money = true, this.hint});
  final String label;
  final double value;
  final IconData? icon;
  final Color? color;
  final bool bold;
  final bool money;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 17, color: color ?? kSetMuted), const SizedBox(width: 8)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(color: bold ? kSetText : kSetMuted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
              if (hint != null) Text(hint!, style: const TextStyle(fontSize: 11, color: kSetMuted)),
            ]),
          ),
          money
              ? MoneyLabel(value, size: bold ? 15.5 : 14, color: color)
              : Text(repQty(value), style: TextStyle(fontWeight: FontWeight.w800, color: color ?? kSetText)),
        ]),
      );
}

/// اختيار شهر (سنة ← شهر بالأرقام).
Future<DateTime?> pickMonth(BuildContext context, {required DateTime initial, DateTime? first, DateTime? last}) {
  final lastD = last ?? DateTime.now();
  final firstD = first ?? DateTime(2018);
  var year = initial.year;
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                IconButton(
                  tooltip: 'السنة السابقة',
                  onPressed: year > firstD.year ? () => setD(() => year--) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text('$year',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kSetText)),
                ),
                IconButton(
                  tooltip: 'السنة التالية',
                  onPressed: year < lastD.year ? () => setD(() => year++) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ]),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.6,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var m = 1; m <= 12; m++)
                    Builder(builder: (_) {
                      final enabled = !DateTime(year, m, 1).isAfter(lastD) && !DateTime(year, m + 1, 0).isBefore(firstD);
                      final sel = year == initial.year && m == initial.month;
                      return Material(
                        color: sel ? kSetNavy : (enabled ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: enabled ? () => Navigator.pop(ctx, DateTime(year, m, 1)) : null,
                          child: Center(
                            child: Text('$m',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: sel ? Colors.white : (enabled ? kSetText : const Color(0xFFCBD5E1)),
                                )),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// اختيار يوم (نافذة التاريخ الموحّدة بالأرقام).
Future<DateTime?> pickReportDay(BuildContext context, DateTime initial) =>
    pickDate(context, initial: initial, help: 'اختر اليوم', last: DateTime.now());

/// هل يرى المستخدم الحالي الكلفة والأرباح؟ (صلاحية «رؤية الكلفة والأرباح»)
bool repCanSeeProfit() => AuthService().hasPermission(AppPermissions.viewCostProfit);

// ═══════════════════════════ دائرة التوزيع ═══════════════════════════

class DonutSlice {
  const DonutSlice(this.label, this.value, this.color, {this.hint});
  final String label;
  final double value;
  final Color color;
  final String? hint;
}

/// دائرة توزيع (Donut) مع مفتاح بالقيم والنسب. القيم السالبة تُهمل.
/// تتحول لعمود (الدائرة فوق المفتاح) في الشاشات الضيقة.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.size = 150,
    this.thickness = 22,
    this.centerTitle,
    this.centerValue,
    this.money = true,
    this.onTap,
  });
  final List<DonutSlice> slices;
  final double size;
  final double thickness;
  final String? centerTitle;
  final String? centerValue;
  final bool money;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, e) => s + (e.value > 0 ? e.value : 0));
    final donut = SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => CustomPaint(
          painter: _DonutPainter(slices, thickness, t),
          child: child,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(thickness + 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (centerTitle != null)
                Text(centerTitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: kSetMuted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  centerValue ?? (money ? repMoney(total) : repQty(total)),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kSetText),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    final legend = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < slices.length; i++)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap == null ? null : () => onTap!(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: slices[i].color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(slices[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText, fontSize: 13)),
                  if (slices[i].hint != null)
                    Text(slices[i].hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kSetMuted)),
                ]),
              ),
              const SizedBox(width: 8),
              Text(
                total > 0 && slices[i].value > 0 ? repPercent(slices[i].value / total * 100) : '—',
                style: const TextStyle(fontSize: 12, color: kSetMuted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: money
                      ? MoneyLabel(slices[i].value, size: 13)
                      : Text(repQty(slices[i].value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ]),
          ),
        ),
    ]);
    if (total <= 0) {
      return const EmptyReport(title: 'لا بيانات للتوزيع', icon: Icons.donut_large_rounded);
    }
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < size + 260
          ? Column(children: [donut, const SizedBox(height: 12), legend])
          : Row(children: [donut, const SizedBox(width: 20), Expanded(child: legend)]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.thickness, this.t);
  final List<DonutSlice> slices;
  final double thickness;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(thickness / 2, thickness / 2, size.width - thickness, size.height - thickness);
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = const Color(0xFFF1F5F9);
    canvas.drawArc(rect, 0, math.pi * 2, false, bg);
    final total = slices.fold<double>(0, (s, e) => s + (e.value > 0 ? e.value : 0));
    if (total <= 0) return;
    var start = -math.pi / 2;
    final positive = slices.where((s) => s.value > 0).length;
    final gap = positive > 1 ? 0.025 : 0.0;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * math.pi * 2 * t;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = s.color;
      canvas.drawArc(rect, start + gap / 2, math.max(0.0, sweep - gap), false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.t != t || old.slices != slices || old.thickness != thickness;
}

/// لوحة ألوان ثابتة للتوزيعات (أقسام، مواد…).
const kRepPalette = <Color>[
  Color(0xFF1E3A8A),
  Color(0xFF0F766E),
  Color(0xFFB45309),
  Color(0xFF6D28D9),
  Color(0xFFBE123C),
  Color(0xFF0369A1),
  Color(0xFF4D7C0F),
  Color(0xFF94A3B8),
];
