// lib/widgets/setup_guide.dart
//
// 🧭 شرح الربط خطوة بخطوة (تيليجرام، ديسكورد، دروب بوكس، فايربيس) — لمن معرفته
// التقنية بسيطة جداً: كل خطوة جملة قصيرة، وتحتها زر يفتح الصفحة المطلوبة مباشرة،
// أو نص جاهز يُنسخ بضغطة (أمر، اسم مقترح)، أو تنبيه صغير لما قد يفاجئ المستخدم.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_kit.dart';

class GuideLink {
  const GuideLink(this.label, this.url, {this.icon = Icons.open_in_new_rounded});
  final String label;
  final String url;
  final IconData icon;
}

class GuideStep {
  const GuideStep(
    this.text, {
    this.links = const [],
    this.copies = const [],
    this.note,
    this.warn = false,
    this.extra,
  });

  /// نص الخطوة.
  final String text;

  /// أزرار تفتح صفحات.
  final List<GuideLink> links;

  /// نصوص جاهزة للنسخ (أمر أو اسم مقترح).
  final List<String> copies;

  /// ملاحظة صغيرة تحت الخطوة (تنبيه إن كان [warn]).
  final String? note;
  final bool warn;

  /// عنصر إضافي (خانة إدخال أو زر خاص).
  final Widget? extra;
}

/// يفتح رابطاً في المتصفح (أو التطبيق المناسب). يعيد false إن تعذّر.
Future<bool> openGuideLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) setToast(context, 'تعذّر فتح الرابط — نُسخ، الصقه في المتصفح', error: true);
  }
  return ok;
}

/// قائمة خطوات مرقّمة بروابط ونسخ جاهز.
class SetupGuide extends StatelessWidget {
  const SetupGuide({super.key, required this.steps, this.color = kSetNavy, this.start = 1});

  final List<GuideStep> steps;
  final Color color;

  /// رقم الخطوة الأولى (للأجزاء المتتالية من الشرح).
  final int start;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < steps.length; i++)
        _StepTile(number: start + i, step: steps[i], color: color, last: i == steps.length - 1),
    ]);
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.step, required this.color, required this.last});
  final int number;
  final GuideStep step;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    // بلا IntrinsicHeight: الخطوة قد تحوي خانة إدخال أو LayoutBuilder
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsetsDirectional.only(end: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 2 : 14, top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.text, style: const TextStyle(fontSize: 13.5, height: 1.6, color: kSetText)),
              if (step.links.isNotEmpty || step.copies.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final l in step.links) _LinkChip(link: l, color: color),
                  for (final c in step.copies) _CopyChip(text: c, color: color),
                ]),
              ],
              if (step.extra != null) ...[const SizedBox(height: 8), step.extra!],
              if (step.note != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: step.warn ? const Color(0xFFFFF7ED) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(step.warn ? Icons.warning_amber_rounded : Icons.lightbulb_outline_rounded,
                        size: 16, color: step.warn ? kSetOrange : kSetMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(step.note!,
                          style: TextStyle(fontSize: 12, height: 1.5, color: step.warn ? kSetOrange : kSetMuted)),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ]);
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.link, required this.color});
  final GuideLink link;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: link.url,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.45)),
          backgroundColor: color.withValues(alpha: 0.05),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () => openGuideLink(context, link.url),
        icon: Icon(link.icon, size: 16),
        label: Text(link.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
      ),
    );
  }
}

class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kSetBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) setToast(context, 'نُسخ «$text» — الصقه في المكان المطلوب');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(text,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: kSetText, letterSpacing: 0.3)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 15, color: color),
          ]),
        ),
      ),
    );
  }
}

/// شرح قابل للطي («كيف أحصل على…؟») — مفتوح تلقائياً قبل الربط.
class GuideToggle extends StatefulWidget {
  const GuideToggle({super.key, required this.label, required this.child, this.color = kSetNavy, this.initiallyOpen = false});
  final String label;
  final Widget child;
  final Color color;
  final bool initiallyOpen;

  @override
  State<GuideToggle> createState() => _GuideToggleState();
}

class _GuideToggleState extends State<GuideToggle> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: c, textStyle: const TextStyle(fontWeight: FontWeight.w800)),
          onPressed: () => setState(() => _open = !_open),
          icon: AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more_rounded),
          ),
          label: Text(widget.label),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: AlignmentDirectional.topStart,
        child: !_open
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.withValues(alpha: 0.16)),
                ),
                child: widget.child,
              ),
      ),
    ]);
  }
}

/// أسماء مقترحة بالإنجليزية من اسم عربي أو إنجليزي (لاسم مستخدم البوت أو المشروع).
class NameSuggest {
  NameSuggest._();

  static const _ar = <String, String>{
    'ا': 'a', 'أ': 'a', 'إ': 'e', 'آ': 'a', 'ء': '', 'ؤ': 'o', 'ئ': 'e', 'ب': 'b', 'ت': 't', 'ث': 'th',
    'ج': 'j', 'ح': 'h', 'خ': 'kh', 'د': 'd', 'ذ': 'th', 'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'sh',
    'ص': 's', 'ض': 'd', 'ط': 't', 'ظ': 'z', 'ع': 'a', 'غ': 'gh', 'ف': 'f', 'ق': 'q', 'ك': 'k',
    'ل': 'l', 'م': 'm', 'ن': 'n', 'ه': 'h', 'ة': 'a', 'و': 'w', 'ي': 'y', 'ى': 'a', ' ': '_', '-': '_',
  };

  /// حروف إنجليزية صغيرة وأرقام و _ فقط، تبدأ بحرف، بطول [max] على الأكثر.
  static String slug(String input, {int max = 20}) {
    final b = StringBuffer();
    for (final ch in input.trim().toLowerCase().split('')) {
      if (RegExp(r'[a-z0-9_]').hasMatch(ch)) {
        b.write(ch);
      } else {
        b.write(_ar[ch] ?? (RegExp(r'\s').hasMatch(ch) ? '_' : ''));
      }
    }
    var s = b.toString().replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    if (s.isEmpty || !RegExp(r'^[a-z]').hasMatch(s)) s = 'shop${s.isEmpty ? '' : '_$s'}';
    if (s.length > max) s = s.substring(0, max).replaceAll(RegExp(r'_$'), '');
    return s;
  }

  /// أسماء مستخدم لبوت تيليجرام (5–32 حرفاً، تنتهي بـ bot). [salt] لتنويع الرقم.
  static List<String> telegramBot(String name, {int salt = 0}) {
    final s = slug(name.isEmpty ? 'alnaser shop' : name, max: 18);
    final n = (100 + (salt.abs() % 900)).toString();
    final out = <String>{
      '${s}_backup_bot',
      '${s}_store_bot',
      '${s}_${n}_bot',
    };
    return [for (final x in out) if (x.length >= 5 && x.length <= 32) x];
  }
}
