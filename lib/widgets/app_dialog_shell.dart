// lib/widgets/app_dialog_shell.dart
//
// 🪟 هيكل موحّد للنوافذ المنبثقة المهمة (رفع البيانات، تنبيهات المخزون، مطالبات اليوم):
// رأس متدرّج بلون النافذة وأيقونة وعنوان وشرح، ثم المحتوى، ثم الأزرار — بزوايا مستديرة
// وظل ناعم وظهور متحرك خفيف. شكل واحد في كل مكان.

import 'package:flutter/material.dart';

class AppDialogShell extends StatelessWidget {
  const AppDialogShell({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.subtitle,
    this.headerExtra,
    this.actions = const [],
    this.onClose,
    this.maxWidth = 560,
    this.maxHeight,
    this.iconWidget,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  /// تحت العنوان داخل الرأس (مثل أرقام ملخصة).
  final Widget? headerExtra;
  final Widget body;
  final List<Widget> actions;

  /// زر الإغلاق في الرأس (null = بلا زر).
  final VoidCallback? onClose;
  final double maxWidth;
  final double? maxHeight;

  /// بدل الأيقونة الثابتة (مثل أيقونة نابضة).
  final Widget? iconWidget;

  static Color _darker(Color c) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness * 0.62).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(horizontal: size.width < 600 ? 14 : 28, vertical: 24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.94, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (_, s, child) => Transform.scale(scale: s, child: child),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight ?? size.height * 0.88),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 40, offset: const Offset(0, 18)),
                  const BoxShadow(color: Color(0x1A0F172A), blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _header(),
                  Flexible(child: body),
                  if (actions.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
                      child: Row(children: actions),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 10, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [color, _darker(color)],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Center(child: iconWidget ?? Icon(icon, color: Colors.white, size: 26)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5, height: 1.4)),
                ],
              ]),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'إغلاق',
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.9)),
              ),
          ]),
          if (headerExtra != null) ...[const SizedBox(height: 14), headerExtra!],
        ]),
      );
}

/// رقم ملخّص صغير داخل رأس النافذة (مثلاً «12 ناقصة»).
class HeaderStat extends StatelessWidget {
  const HeaderStat({super.key, required this.value, required this.label, this.icon, this.selected = false, this.onTap});
  final String value;
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: selected ? 0.26 : 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: selected ? 0.7 : 0.2), width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 8)],
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.1)),
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5)),
            ]),
          ]),
        ),
      ),
    );
  }
}
