// lib/screens/deep_check/deep_check_widgets.dart
//
// 🎨 قطع شاشة «الفحص العميق»: ملخص بالأرقام، بطاقة كل ملاحظة (تنفتح بحركة ناعمة)،
// وبطاقة الفحوص السليمة — بألوان وأشكال «settings_kit» نفسها في باقي البرنامج.

import 'package:flutter/material.dart';

import '../../services/database/business/financial_deep_check.dart';
import '../../widgets/settings_kit.dart';

const kDeepAmber = Color(0xFFB45309);

({Color color, IconData icon, String label}) deepSeverityStyle(DeepSeverity s) => switch (s) {
      DeepSeverity.error => (color: kSetRed, icon: Icons.error_rounded, label: 'خطأ'),
      DeepSeverity.warning => (color: kDeepAmber, icon: Icons.warning_amber_rounded, label: 'تنبيه'),
      DeepSeverity.info => (color: kSetNavy, icon: Icons.info_outline_rounded, label: 'معلومة'),
    };

/// ثلاثة أرقام: أخطاء، تنبيهات، سليم — ثم مدة الفحص.
class DeepSummary extends StatelessWidget {
  const DeepSummary(this.r, {super.key});
  final DeepCheckReport r;

  @override
  Widget build(BuildContext context) {
    final ok = r.errors == 0 && r.warnings == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kSetBorder),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(ok ? Icons.verified_rounded : Icons.fact_check_rounded, color: ok ? kSetGreen : kSetNavy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(ok ? 'لم يُعثر على أي خلل' : 'نتيجة الفحص',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: kSetText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: kSetBg, borderRadius: BorderRadius.circular(20)),
            child: Text('${(r.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} ثانية',
                style: const TextStyle(fontSize: 12, color: kSetMuted, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final tiles = [
            _Stat('أخطاء', r.errors, kSetRed, Icons.error_rounded),
            _Stat('تنبيهات', r.warnings, kDeepAmber, Icons.warning_amber_rounded),
            _Stat('فحوص سليمة', r.passed.length, kSetGreen, Icons.check_circle_rounded),
          ];
          if (c.maxWidth < 420) {
            return Column(children: [
              for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: 8), child: t),
            ]);
          }
          return Row(children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: tiles[i]),
            ],
          ]);
        }),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color, this.icon);
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final active = value > 0 || color == kSetGreen;
    final c = active ? color : kSetMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: c.withValues(alpha: 0.07),
        border: Border.all(color: c.withValues(alpha: 0.20)),
      ),
      child: Row(children: [
        Icon(icon, color: c, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w700))),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Text('${v.round()}',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: c, height: 1)),
        ),
      ]),
    );
  }
}

/// بطاقة ملاحظة: شريط لون جانبي، عنوان، وتنفتح لتعرض الشرح والأسطر (ولكل فاتورة «معالجة»).
class DeepFindingCard extends StatefulWidget {
  const DeepFindingCard({super.key, required this.f, required this.onRepair, this.busy = false});
  final DeepFinding f;
  final Future<void> Function(int invoiceId) onRepair;
  final bool busy;

  @override
  State<DeepFindingCard> createState() => _DeepFindingCardState();
}

class _DeepFindingCardState extends State<DeepFindingCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final st = deepSeverityStyle(f.severity);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _open ? st.color.withValues(alpha: 0.35) : kSetBorder),
        boxShadow: [
          BoxShadow(
            color: _open ? st.color.withValues(alpha: 0.10) : const Color(0x0A0F172A),
            blurRadius: _open ? 18 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // شريط اللون الجانبي فوق المحتوى (بلا IntrinsicHeight: يحسب الحجم مرة واحدة)
      child: Stack(children: [
        Padding(
            padding: const EdgeInsetsDirectional.only(start: 5),
            child: Material(
              type: MaterialType.transparency,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: st.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(st.icon, color: st.color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(f.title,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: kSetText)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            _chip(st.label, st.color),
                            _chip(f.area, kSetMuted),
                            if (f.total > 0) _chip('${f.total}', st.color, filled: true),
                          ]),
                        ]),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(Icons.expand_more_rounded, color: kSetMuted),
                      ),
                    ]),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: _details(f, st.color),
                ),
              ]),
            ),
          ),
        PositionedDirectional(start: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(color: st.color)),
      ]),
    );
  }

  Widget _details(DeepFinding f, Color color) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (f.explain.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kSetBg, borderRadius: BorderRadius.circular(12)),
              child: Text(f.explain, style: const TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFF334155))),
            ),
          for (var k = 0; k < f.rows.length; k++) _row(f, k, color),
          if (f.total > f.rows.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('… و${f.total - f.rows.length} غيرها — يظهر أول ${f.rows.length} فقط',
                  style: const TextStyle(fontSize: 12, color: kSetMuted)),
            ),
        ]),
      );

  Widget _row(DeepFinding f, int k, Color color) {
    final ref = k < f.invoiceRefs.length ? f.invoiceRefs[k] : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF2F7)),
      ),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Text('${k + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(f.rows[k], style: const TextStyle(fontSize: 12.8, height: 1.5, color: kSetText))),
        if (ref != null) ...[
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'معالجة الفاتورة',
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: kSetNavy.withValues(alpha: 0.08),
                foregroundColor: kSetNavy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: widget.busy ? null : () => widget.onRepair(ref),
              icon: const Icon(Icons.healing_rounded, size: 17),
              label: const Text('معالجة'),
            ),
          ),
        ],
      ]),
    );
  }

  static Widget _chip(String t, Color c, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: filled ? c : c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: filled ? Colors.white : c)),
      );
}

/// الفحوص السليمة.
class DeepPassedCard extends StatelessWidget {
  const DeepPassedCard(this.passed, {super.key});
  final List<String> passed;

  @override
  Widget build(BuildContext context) => SetCard(
        title: 'فحوص سليمة',
        subtitle: '${passed.length} فحصاً بلا ملاحظات',
        icon: Icons.verified_rounded,
        color: kSetGreen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in passed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_rounded, size: 17, color: kSetGreen),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(p, style: const TextStyle(fontSize: 13, height: 1.5, color: kSetText))),
              ]),
            ),
        ]),
      );
}
