// lib/erp/erp_ui.dart
//
// 🎨 عناصر التصميم العصري للشاشات الجديدة: رأس متدرّج، بطاقات أقسام بظل ناعم،
// بطاقات مؤشرات (KPI)، شارات حالة، وشبكة حقول متجاوبة.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart';
import 'activity/activity_log.dart';

class ErpColors {
  static const navy = AccColors.navy;
  static const navyDark = AccColors.navyDark;
  static const cyan = AccColors.cyan;
  static const bg = Color(0xFFF3F6FB);
  static const card = Colors.white;
  static const border = Color(0xFFE6EBF2);
  static const text = AccColors.text;
  static const muted = AccColors.muted;
  static const green = AccColors.green;
  static const red = AccColors.red;
  static const orange = AccColors.orange;
  static const purple = AccColors.purple;
  static const blue = AccColors.blue;
  static const gold = Color(0xFFB7791F);
}

/// صفحة كاملة برأس متدرّج.
class ErpPage extends StatelessWidget {
  const ErpPage({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions,
    required this.body,
    this.floatingActionButton,
    this.bottom,
    this.headerExtra,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottom;
  final Widget? headerExtra;

  @override
  Widget build(BuildContext context) {
    ActivityLog.viewed(title);
    return Scaffold(
      backgroundColor: ErpColors.bg,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottom,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [ErpColors.navyDark, ErpColors.navy, Color(0xFF16508A)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (Navigator.of(context).canPop())
                          IconButton(
                            icon: const Icon(Icons.arrow_forward, color: Colors.white),
                            tooltip: 'رجوع',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        if (icon != null)
                          Container(
                            margin: const EdgeInsets.only(left: 10, right: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: Colors.white, size: 22),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                              if (subtitle != null)
                                Text(subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5)),
                            ],
                          ),
                        ),
                        if (actions != null)
                          IconTheme(
                            data: const IconThemeData(color: Colors.white),
                            child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
                          ),
                      ],
                    ),
                    if (headerExtra != null) ...[
                      const SizedBox(height: 10),
                      headerExtra!,
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// بطاقة قسم بعنوان وأيقونة.
class ErpSection extends StatelessWidget {
  const ErpSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.color = ErpColors.navy,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final Color color;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ErpColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ErpColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                if (icon != null)
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                if (icon != null) const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: color)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// بطاقة مؤشر رقمي.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = ErpColors.navy,
    this.hint,
    this.onTap,
    this.width = 210,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ErpColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 12, color: ErpColors.muted)),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(value,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                      ),
                      if (hint != null)
                        Text(hint!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: ErpColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شارة حالة ملوّنة.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.color = ErpColors.navy});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// شبكة حقول متجاوبة: كل حقل بعرض ثابت، تلتف تلقائياً.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children, this.spacing = 12});
  final List<Widget> children;
  final double spacing;
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: spacing, runSpacing: spacing, crossAxisAlignment: WrapCrossAlignment.center, children: children);
}

/// صف معلومة: عنوان صغير + قيمة.
class InfoTile extends StatelessWidget {
  const InfoTile(this.label, this.value, {super.key, this.color, this.width = 180});
  final String label;
  final String value;
  final Color? color;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: ErpColors.muted)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color ?? ErpColors.text)),
          ],
        ),
      );
}

/// زر أساسي عريض.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check,
    this.color = ErpColors.navy,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final bool busy;
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon),
        label: Text(label),
      );
}

/// شريط بحث مستدير.
class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.hint, required this.onChanged, this.controller, this.autofocus = false});
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ErpColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ErpColors.border),
          ),
        ),
      );
}

/// حالة فارغة لطيفة.
class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: ErpColors.muted.withOpacity(0.5)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: ErpColors.muted, fontSize: 15)),
          ]),
        ),
      );
}

/// قائمة منسدلة بسيطة بتصميم موحّد.
class DropBox<T> extends StatelessWidget {
  const DropBox({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 220,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
