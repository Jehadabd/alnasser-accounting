// lib/widgets/settings_kit.dart
//
// ⚙️ طقم شاشات الإعدادات الفرعية (الموظفون، الترخيص، تيليجرام، ديسكورد،
// دروب بوكس، فايربيس، التنبيهات…) — شكل واحد في كل مكان:
//   • SettingsScaffold — رأس كحلي متدرّج + ثيم الأزرار والحقول الموحّد +
//     محتوى في الوسط بعرض مريح وظهور متتابع ناعم.
//   • SetHero — بطاقة تعريف أعلى الشاشة (أيقونة كبيرة + عنوان + شرح + حالة).
//   • SetCard — بطاقة قسم بعنوان وأيقونة.
//   • SetSwitch / SetBanner / SetStatusPill / SetSteps / SetActionRow.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart' show accAppBar, FadeSlideIn;
import '../erp/erp_kit.dart' show ErpTheme;

const kSetNavy = Color(0xFF0F3460);
const kSetBg = Color(0xFFF3F6FB);
const kSetBorder = Color(0xFFE6EBF2);
const kSetText = Color(0xFF1E293B);
const kSetMuted = Color(0xFF64748B);
const kSetGreen = Color(0xFF047857);
const kSetRed = Color(0xFFB91C1C);
const kSetOrange = Color(0xFFC2410C);
const kSetBlue = Color(0xFF2563EB);

/// شاشة إعدادات فرعية بالشكل الموحّد.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.actions,
    this.children,
    this.body,
    this.bottom,
    this.floatingActionButton,
    this.maxWidth = 820,
    this.loading = false,
  }) : assert(children != null || body != null || loading);

  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget>? actions;

  /// محتوى عادي (قائمة قابلة للتمرير) — أو [body] لمحتوى خاص.
  final List<Widget>? children;
  final Widget? body;
  final Widget? bottom;
  final Widget? floatingActionButton;
  final double maxWidth;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final list = children ?? const <Widget>[];
    return Theme(
      data: ErpTheme.apply(Theme.of(context)),
      child: Scaffold(
        backgroundColor: kSetBg,
        appBar: accAppBar(title, icon: icon, subtitle: subtitle, actions: actions),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottom,
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : body ??
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                      children: [
                        for (var i = 0; i < list.length; i++) FadeSlideIn(index: i, child: list[i]),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}

/// بطاقة تعريف أعلى الشاشة.
class SetHero extends StatelessWidget {
  const SetHero({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.color = kSetNavy,
    this.status,
  });
  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Color.alphaBlend(color.withValues(alpha: 0.10), Colors.white), Colors.white],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kSetText)),
            const SizedBox(height: 3),
            Text(text, style: const TextStyle(fontSize: 13, color: kSetMuted, height: 1.5)),
            if (status != null) ...[const SizedBox(height: 8), status!],
          ]),
        ),
      ]),
    );
  }
}

/// بطاقة قسم: عنوان بأيقونة ثم المحتوى.
class SetCard extends StatelessWidget {
  const SetCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.color = kSetNavy,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 16),
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Color color;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kSetBorder),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 10),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: kSetText)),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.4)),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFEEF2F7)),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
  }
}

/// مفتاح تشغيل/إيقاف بعنوان وشرح.
class SetSwitch extends StatelessWidget {
  const SetSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.color = kSetNavy,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      // thumbColor/trackColor بدل activeColor (مهملة في الإصدارات الحديثة) و activeThumbColor
      // (غير موجودة في الإصدارات الأقدم) — تعمل على كل الإصدارات.
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF94A3B8)),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? color : const Color(0xFFE2E8F0)),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      secondary: icon == null
          ? null
          : Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (value ? color : kSetMuted).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: value ? color : kSetMuted),
            ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: kSetText)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.4)),
    );
  }
}

enum SetBannerKind { info, ok, warn, error }

/// شريط معلومة/تنبيه داخل البطاقات.
class SetBanner extends StatelessWidget {
  const SetBanner(this.text, {super.key, this.kind = SetBannerKind.info, this.icon});
  final String text;
  final SetBannerKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, IconData ic) = switch (kind) {
      SetBannerKind.info => (kSetNavy, const Color(0xFFEFF4FF), Icons.info_outline_rounded),
      SetBannerKind.ok => (kSetGreen, const Color(0xFFECFDF5), Icons.check_circle_outline_rounded),
      SetBannerKind.warn => (kSetOrange, const Color(0xFFFFF7ED), Icons.warning_amber_rounded),
      SetBannerKind.error => (kSetRed, const Color(0xFFFEF2F2), Icons.error_outline_rounded),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.20)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? ic, size: 19, color: fg),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: fg, height: 1.55))),
      ]),
    );
  }
}

/// شارة حالة صغيرة (متصل/غير متصل…).
class SetStatusPill extends StatelessWidget {
  const SetStatusPill(this.text, {super.key, required this.ok, this.icon});
  final String text;
  final bool ok;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = ok ? kSetGreen : kSetOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon ?? (ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded), size: 15, color: c),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

/// خطوات مرقّمة (طريقة الإعداد).
class SetSteps extends StatelessWidget {
  const SetSteps(this.steps, {super.key, this.color = kSetNavy});
  final List<String> steps;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text('${i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 13, height: 1.55, color: kSetText))),
          ]),
        ),
    ]);
  }
}

/// صف إجراء قابل للضغط داخل بطاقة (أيقونة + عنوان + شرح + سهم).
class SetActionRow extends StatelessWidget {
  const SetActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color = kSetNavy,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color color;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? kSetRed : color;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hoverColor: c.withValues(alpha: 0.05),
      enabled: onTap != null,
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, size: 20, color: c),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: danger ? kSetRed : kSetText)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: kSetMuted, height: 1.4)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Color(0xFFB8C2CF)),
    );
  }
}

/// زر رئيسي عريض بحالة انتظار.
class SetPrimaryButton extends StatelessWidget {
  const SetPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.color = kSetNavy,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 50)),
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 15)),
        ),
      );
}

/// رسالة سريعة موحّدة (نجاح/خطأ).
void setToast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? kSetRed : kSetGreen,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
    ));
}
