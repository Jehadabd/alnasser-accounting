// lib/theme/ui_tokens.dart
//
// 🎨 ألوان ومقاسات موحّدة للشاشات المعاد تصميمها (المواد وتعديلها…) — هادئة
// ومريحة للعين، وبنفس كحلي شاشة الفاتورة والكاشير.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UiColors {
  UiColors._();

  static const bg = Color(0xFFF3F5F9);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF8FAFC);
  static const border = Color(0xFFE3E8EF);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);

  static const primary = Color(0xFF0F3460);
  static const accent = Color(0xFF2563EB);
  static const accentSoft = Color(0xFFEFF4FF);

  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFDCFCE7);
  static const warn = Color(0xFFD97706);
  static const warnSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);

  static const _tints = <Color>[
    Color(0xFF2563EB),
    Color(0xFF0D9488),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFF65A30D),
    Color(0xFF9333EA),
  ];

  /// لون ثابت هادئ لكل قسم أو مادة
  static Color tint(int? id) => _tints[(id ?? 0).abs() % _tints.length];
}

final NumberFormat _money = NumberFormat('#,##0.##', 'en');
final NumberFormat _qty = NumberFormat('#,##0.###', 'en');

String uiMoney(num v) => _money.format(v);
String uiQty(num v) => _qty.format(v);

/// حقل إدخال موحّد الشكل (العنوان داخل الحقل)
InputDecoration uiInput({
  String? label,
  String? hint,
  String? helper,
  Color? helperColor,
  IconData? icon,
  Widget? suffix,
  bool dense = true,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperStyle: TextStyle(fontSize: 11.5, color: helperColor ?? UiColors.muted),
    labelStyle: const TextStyle(fontSize: 13, color: UiColors.muted),
    floatingLabelStyle: const TextStyle(fontSize: 13, color: UiColors.accent, fontWeight: FontWeight.w600),
    hintStyle: const TextStyle(fontSize: 13, color: UiColors.faint),
    prefixIcon: icon == null ? null : Icon(icon, size: 19, color: UiColors.muted),
    suffixIcon: suffix,
    isDense: dense,
    filled: true,
    fillColor: UiColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    border: border(UiColors.border),
    enabledBorder: border(UiColors.border),
    focusedBorder: border(UiColors.accent, 1.5),
    errorBorder: border(UiColors.danger),
    focusedErrorBorder: border(UiColors.danger, 1.5),
  );
}

/// بطاقة قسم: عنوان بأيقونة ثم المحتوى
class UiSection extends StatelessWidget {
  const UiSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.tint = UiColors.accent,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    // Material (لا Container ملوّن) حتى تظهر تأثيرات الأزرار والقوائم داخله
    return Material(
      color: UiColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: UiColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: UiColors.text)),
                      if (subtitle != null)
                        Text(subtitle!, style: const TextStyle(fontSize: 11.5, color: UiColors.muted)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1, color: UiColors.border),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

/// شارة صغيرة ملوّنة
class UiChip extends StatelessWidget {
  const UiChip(this.text, {super.key, this.fg = UiColors.muted, this.bg = UiColors.surfaceAlt, this.icon});

  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
