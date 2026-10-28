// lib/accounting/screens/acc_ui.dart
//
// عناصر واجهة مشتركة لشاشات المحاسبة (هوية «سهل»: كحلي + سماوي):
//   • accAppBar — رأس متدرّج بزوايا سفلية مستديرة (نفس رأس ErpPage).
//   • PeriodBar — فترة (من/إلى) بأزرار سريعة مجزّأة وتواريخ رقمية.
//   • pickDate — نافذة تاريخ موحّدة الشكل (الأشهر بالأرقام).
//   • accRoute — انتقال ناعم بين الشاشات + ثيم المحاسبة الموحّد.


import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../erp/erp_kit.dart' show ErpTheme;
import '../../lan/lan_settings.dart';
import '../../services/auth_service.dart';

class AccColors {
  static const navy = Color(0xFF0F3460);
  static const navyDark = Color(0xFF020F2B);
  static const blue = Color(0xFF2563EB);
  static const cyan = Color(0xFF00B4D8);
  static const bg = Color(0xFFF3F6FB);
  static const text = Color(0xFF1F2937);
  static const muted = Color(0xFF6C757D);
  static const green = Color(0xFF047857);
  static const red = Color(0xFFB91C1C);
  static const orange = Color(0xFFC2410C);
  static const purple = Color(0xFF6B21A8);
  static const border = Color(0xFFE6EBF2);
  static const soft = Color(0xFFF1F4F9);
}

final NumberFormat _money = NumberFormat('#,##0.##', 'en');
final DateFormat _date = DateFormat('yyyy/MM/dd', 'en_US');

String fmtMoney(num v) => _money.format(v);
String fmtDate(DateTime d) => _date.format(d);

/// مبلغ ملوّن: أحمر للسالب.
class MoneyText extends StatelessWidget {
  const MoneyText(this.value, {super.key, this.bold = false, this.size, this.color});
  final double value;
  final bool bold;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        fmtMoney(value),
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: color ?? (value < -0.004 ? AccColors.red : AccColors.text),
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontSize: size,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

const _headerGradient = LinearGradient(
  colors: [AccColors.navyDark, AccColors.navy, Color(0xFF16508A)],
  begin: Alignment.topRight,
  end: Alignment.bottomLeft,
);

/// شريط العنوان الموحّد: متدرّج كحلي بزوايا سفلية مستديرة.
PreferredSizeWidget accAppBar(String title, {List<Widget>? actions, IconData? icon, String? subtitle}) => AppBar(
      toolbarHeight: subtitle == null ? 62 : 68,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
      // SizedBox.expand: الـ AppBar يضع flexibleSpace في Stack بقيود «مرنة»، و DecoratedBox
      // بلا ابن يأخذ أصغر حجم (صفر) فلا يظهر التدرّج ويبقى النص الأبيض على خلفية فاتحة.
      flexibleSpace: const SizedBox.expand(child: DecoratedBox(decoration: BoxDecoration(gradient: _headerGradient))),
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      title: Row(children: [
        if (icon != null)
          Container(
            margin: const EdgeInsetsDirectional.only(end: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5)),
            ],
          ),
        ),
      ]),
      actions: actions == null ? null : [...actions, const SizedBox(width: 6)],
    );

// ═══════════════════════════ التنقّل ═══════════════════════════

/// انتقال ناعم (ظهور تدريجي + انزلاق خفيف للأعلى) مع ثيم المحاسبة الموحّد،
/// فتأخذ كل شاشة تُفتح من مركز المحاسبة نفس شكل الأزرار والحقول والحوارات.
Route<T> accRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Theme(data: ErpTheme.apply(Theme.of(ctx)), child: page),
      transitionsBuilder: (ctx, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(c),
            child: child,
          ),
        );
      },
    );

// ═══════════════════════════ التاريخ ═══════════════════════════

/// ثيم نافذة التاريخ: رأس كحلي، زوايا مستديرة، زر اختيار ممتلئ.
ThemeData accDatePickerTheme(ThemeData base) {
  final font = base.textTheme.bodyMedium?.fontFamily;
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AccColors.navy,
      onPrimary: Colors.white,
      surface: Colors.white,
      surfaceTint: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      headerBackgroundColor: AccColors.navy,
      headerForegroundColor: Colors.white,
      dividerColor: AccColors.border,
      todayBorder: const BorderSide(color: AccColors.blue, width: 1.5),
      confirmButtonStyle: TextButton.styleFrom(
        backgroundColor: AccColors.navy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w700),
      ),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: AccColors.muted,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// نافذة اختيار تاريخ موحّدة (الشهر يظهر رقماً: «شهر 10 - 2026»).
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  String? help,
  DateTime? first,
  DateTime? last,
}) {
  final f = first ?? DateTime(2015);
  final l = last ?? DateTime(2100);
  var init = DateTime(initial.year, initial.month, initial.day);
  if (init.isBefore(f)) init = f;
  if (init.isAfter(l)) init = l;
  return showDatePicker(
    context: context,
    initialDate: init,
    firstDate: f,
    lastDate: l,
    helpText: help,
    confirmText: 'اختيار',
    cancelText: 'إلغاء',
    builder: (ctx, child) => Theme(data: accDatePickerTheme(Theme.of(ctx)), child: child!),
  );
}

/// زر تاريخ على شكل «بطاقة»: عنوان صغير + التاريخ بالأرقام.
class DatePill extends StatefulWidget {
  const DatePill({
    super.key,
    required this.label,
    required this.value,
    required this.onPicked,
    this.emptyText = 'البداية',
    this.help,
    this.dense = false,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPicked;
  final String emptyText;
  final String? help;
  final bool dense;

  @override
  State<DatePill> createState() => _DatePillState();
}

class _DatePillState extends State<DatePill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _hover ? AccColors.blue : AccColors.border, width: _hover ? 1.4 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final d = await pickDate(context, initial: v ?? DateTime.now(), help: widget.help);
            if (d != null) widget.onPicked(d);
          },
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(8, widget.dense ? 6 : 7, 14, widget.dense ? 6 : 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _hover ? AccColors.navy : AccColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.calendar_month_rounded, size: 17, color: _hover ? Colors.white : AccColors.navy),
              ),
              const SizedBox(width: 9),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: const TextStyle(fontSize: 11, color: AccColors.muted, height: 1.1)),
                  Text(
                    v == null ? widget.emptyText : fmtDate(v),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AccColors.text,
                      height: 1.25,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ شريط الفترة ═══════════════════════════

enum _Preset { today, month, year, all }

/// اختيار فترة (من/إلى) بأزرار سريعة مجزّأة.
class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.from,
    required this.to,
    required this.onChanged,
    this.showFrom = true,
    this.trailing,
  });
  final DateTime? from;
  final DateTime to;
  final bool showFrom;
  final void Function(DateTime? from, DateTime to) onChanged;

  /// عنصر إضافي في نهاية الشريط (عدد النتائج مثلاً).
  final Widget? trailing;

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  _Preset? _active(DateTime now) {
    if (!_sameDay(to, now)) return null;
    final f = from;
    if (f == null) return _Preset.all;
    if (_sameDay(f, now)) return _Preset.today;
    if (_sameDay(f, DateTime(now.year, now.month, 1))) return _Preset.month;
    if (_sameDay(f, DateTime(now.year, 1, 1))) return _Preset.year;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = _active(now);
    void apply(_Preset p) {
      final n = DateTime.now();
      switch (p) {
        case _Preset.today:
          onChanged(DateTime(n.year, n.month, n.day), n);
        case _Preset.month:
          onChanged(DateTime(n.year, n.month, 1), n);
        case _Preset.year:
          onChanged(DateTime(n.year, 1, 1), n);
        case _Preset.all:
          onChanged(null, n);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          if (showFrom)
            _Segments(
              items: const [
                (_Preset.today, 'اليوم', Icons.today_rounded),
                (_Preset.month, 'هذا الشهر', Icons.calendar_view_month_rounded),
                (_Preset.year, 'هذه السنة', Icons.date_range_rounded),
                (_Preset.all, 'الكل', Icons.all_inclusive_rounded),
              ],
              selected: active,
              onSelect: apply,
            ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (showFrom) ...[
              DatePill(
                label: 'من',
                value: from,
                help: 'من تاريخ',
                onPicked: (d) => onChanged(d, to),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: AccColors.muted),
              ),
            ],
            DatePill(
              label: showFrom ? 'إلى' : 'حتى',
              value: to,
              help: showFrom ? 'إلى تاريخ' : 'حتى تاريخ',
              onPicked: (d) => onChanged(from, d),
            ),
          ]),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// أزرار مجزّأة: الخيار المحدد بخلفية بيضاء وظل خفيف (حركة انتقال ناعمة).
class _Segments extends StatelessWidget {
  const _Segments({required this.items, required this.selected, required this.onSelect});
  final List<(_Preset, String, IconData)> items;
  final _Preset? selected;
  final ValueChanged<_Preset> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AccColors.soft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AccColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (p, label, icon) in items) _SegmentButton(
          label: label,
          icon: icon,
          selected: selected == p,
          onTap: () => onSelect(p),
        ),
      ]),
    );
  }
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final fg = sel ? AccColors.navy : (_hover ? AccColors.text : AccColors.muted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? Colors.white : (_hover ? Colors.white.withValues(alpha: 0.55) : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            boxShadow: sel
                ? [BoxShadow(color: AccColors.navy.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))]
                : const [],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(widget.label,
                style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w800 : FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════ بطاقات ═══════════════════════════

/// بطاقة قسم بعنوان.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.color, this.icon, this.trailing});
  final String title;
  final Widget child;
  final Color? color;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = color ?? AccColors.navy;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AccColors.border),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 10),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon ?? Icons.folder_open_rounded, size: 17, color: c),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AccColors.text, fontSize: 15)),
                ),
                if (trailing != null) trailing!,
              ]),
            ),
            const Divider(height: 1, color: AccColors.border),
            child,
          ],
        ),
      ),
    );
  }
}

/// صف (اسم ← مبلغ).
class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.value, {super.key, this.bold = false, this.indent = 0});
  final String label;
  final double value;
  final bool bold;
  final int indent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(right: 16.0 + indent * 16, left: 16, top: 6, bottom: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
            MoneyText(value, bold: bold),
          ],
        ),
      );
}

// ═══════════════════════════ حركة وبطاقات رأس ═══════════════════════════

/// ظهور تدريجي مع انزلاق خفيف للأعلى؛ [index] يؤخّر العنصر قليلاً (تتابع).
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 14});
  final Widget child;
  final int index;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final delay = 40.0 * index.clamp(0, 12);
    final total = 300.0 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total.round()),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, offset * (1 - t)), child: c),
      ),
    );
  }
}

/// مؤشر صغير «زجاجي» داخل الرأس المتدرّج (رقم + عنوان + أيقونة).
class HeaderStat extends StatelessWidget {
  const HeaderStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = Colors.white,
    this.onTap,
    this.tooltip,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Colors.white.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 16, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11.5)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  value,
                  key: ValueKey(value),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    return tooltip == null ? card : Tooltip(message: tooltip!, child: card);
  }
}

// ═══════════════════════════ رسائل ═══════════════════════════

SnackBar _snack(String text, Color color, IconData icon) => SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
      ]),
    );

String _errText(Object e) {
  final s = e.toString();
  for (final p in const ['Exception: ', 'LedgerException: ', 'ErpException: ']) {
    if (s.startsWith(p)) return s.substring(p.length);
  }
  return s;
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(_snack(_errText(e), AccColors.red, Icons.error_outline_rounded));
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(_snack(msg, AccColors.green, Icons.check_circle_rounded));
}

/// فحص صلاحية مع رسالة. يعيد true إن كان مسموحاً.
bool requirePermission(BuildContext context, String key) {
  if (AuthService().hasPermission(key)) return true;
  ScaffoldMessenger.of(context).showSnackBar(
      _snack('ليس لديك صلاحية لهذه العملية', AccColors.red, Icons.lock_outline_rounded));
  return false;
}

/// يكفي امتلاك أي صلاحية من القائمة.
bool requireAnyPermission(BuildContext context, List<String> keys) {
  final auth = AuthService();
  if (keys.any(auth.hasPermission)) return true;
  return requirePermission(context, keys.first);
}

/// على الطرفية لا يعمل محرك الترحيل — السيرفر يرحّل تلقائياً كل دقيقتين.
bool get canRunPosting => AppNetworkMode.ownsDatabase;
