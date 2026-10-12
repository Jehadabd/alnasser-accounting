// lib/invoice_designer/designer_widgets.dart
//
// أدوات واجهة مصمم الفاتورة: حقول متزامنة، أرقام صغيرة بـ + و −، لوحة ألوان،
// أقسام قابلة للطي، وبطاقات أدوات.

import 'package:flutter/material.dart';

class DesignerColors {
  DesignerColors._();
  static const navy = Color(0xFF0F3460);
  static const blue = Color(0xFF1E88E5);
  static const bg = Color(0xFFF1F4F8);
  static const border = Color(0xFFE2E8F0);
  static const muted = Color(0xFF64748B);
  static const text = Color(0xFF1E293B);
  static const soft = Color(0xFFF8FAFC);
}

/// حقل نص يتبع القيمة الخارجية ما دام المستخدم لا يكتب فيه
class SyncedField extends StatefulWidget {
  const SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.maxLines = 1,
    this.number = false,
    this.dense = true,
    this.prefixIcon,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final int maxLines;
  final bool number;
  final bool dense;
  final IconData? prefixIcon;

  @override
  State<SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<SyncedField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(covariant SyncedField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _f,
      maxLines: widget.maxLines,
      style: const TextStyle(fontSize: 13.5),
      keyboardType: widget.number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
      textDirection: widget.number ? TextDirection.ltr : TextDirection.rtl,
      textAlign: widget.number ? TextAlign.center : TextAlign.start,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        isDense: widget.dense,
        filled: true,
        fillColor: Colors.white,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DesignerColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: widget.onChanged,
    );
  }
}

String _fmtNum(double v, int decimals) {
  final s = v.toStringAsFixed(decimals);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// رقم صغير: عنوان فوق، وحقل بين زرّي − و +
class MiniNum extends StatelessWidget {
  const MiniNum({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = -9999,
    this.max = 9999,
    this.decimals = 1,
    this.suffix,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;
  final int decimals;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    void set(double v) => onChanged(v.clamp(min, max).toDouble());
    Widget btn(IconData i, VoidCallback f) => InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(6),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(i, size: 16, color: DesignerColors.muted)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(suffix == null ? label : '$label ($suffix)',
          style: const TextStyle(fontSize: 11.5, color: DesignerColors.muted)),
      const SizedBox(height: 3),
      Container(
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DesignerColors.border),
        ),
        child: Row(children: [
          btn(Icons.remove, () => set(value - step)),
          Expanded(
            child: _BareNumField(
              value: _fmtNum(value, decimals),
              onChanged: (s) {
                final v = double.tryParse(s.replaceAll(',', '.'));
                if (v != null) set(v);
              },
            ),
          ),
          btn(Icons.add, () => set(value + step)),
        ]),
      ),
    ]);
  }
}

class _BareNumField extends StatefulWidget {
  const _BareNumField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BareNumField> createState() => _BareNumFieldState();
}

class _BareNumFieldState extends State<_BareNumField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _f = FocusNode();

  @override
  void didUpdateWidget(covariant _BareNumField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _f,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
      onChanged: widget.onChanged,
    );
  }
}

/// (للتوافق) رقم بعنوان جانبي
class NumStepper extends StatelessWidget {
  const NumStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.min = -9999,
    this.max = 9999,
    this.decimals = 1,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;
  final int decimals;

  @override
  Widget build(BuildContext context) => MiniNum(
        label: label,
        value: value,
        onChanged: onChanged,
        step: step,
        min: min,
        max: max,
        decimals: decimals,
      );
}

/// لوحة ألوان (0 = بلا لون إن سُمح)
class ColorRow extends StatelessWidget {
  const ColorRow({super.key, required this.label, required this.value, required this.onChanged, this.allowNone = false});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool allowNone;

  static const palette = <int>[
    0xFF000000, 0xFF455A64, 0xFF9E9E9E, 0xFFFFFFFF,
    0xFF0F3460, 0xFF1565C0, 0xFF00838F, 0xFF2E7D32,
    0xFF558B2F, 0xFFF9A825, 0xFFEF6C00, 0xFFC62828,
    0xFFAD1457, 0xFF6A1B9A, 0xFF4E342E, 0xFFE8EEF5,
  ];

  @override
  Widget build(BuildContext context) {
    Widget dot(int c) {
      final sel = c == value;
      final light = c == 0 || c == 0xFFFFFFFF || c == 0xFFE8EEF5;
      return Tooltip(
        message: c == 0 ? 'بلا لون' : '',
        child: InkWell(
          onTap: () => onChanged(c),
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: c == 0 ? Colors.white : Color(c),
              shape: BoxShape.circle,
              border: Border.all(color: sel ? DesignerColors.blue : Colors.black12, width: sel ? 2.5 : 1),
              boxShadow: sel ? [BoxShadow(color: DesignerColors.blue.withValues(alpha: 0.35), blurRadius: 6)] : null,
            ),
            child: c == 0
                ? const Icon(Icons.block, size: 14, color: Colors.redAccent)
                : (sel ? Icon(Icons.check, size: 14, color: light ? Colors.black87 : Colors.white) : null),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11.5, color: DesignerColors.muted)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (allowNone) dot(0),
        for (final c in palette) dot(c),
      ]),
    ]);
  }
}

/// قسم في لوحة الخصائص: بطاقة بعنوان وأيقونة، ويُطوى بالضغط على عنوانه
class PropSection extends StatefulWidget {
  const PropSection(this.title, {super.key, required this.children, this.icon, this.initiallyOpen = true});
  final String title;
  final IconData? icon;
  final bool initiallyOpen;
  final List<Widget> children;

  @override
  State<PropSection> createState() => _PropSectionState();
}

class _PropSectionState extends State<PropSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesignerColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: DesignerColors.navy),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: DesignerColors.text)),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 160),
                child: const Icon(Icons.expand_more, size: 20, color: DesignerColors.muted),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 160),
          crossFadeState: _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          secondChild: const SizedBox(width: double.infinity),
          firstChild: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < widget.children.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                widget.children[i],
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// بطاقة أداة في قائمة «أضف إلى الورقة»
class ToolTile extends StatefulWidget {
  const ToolTile({super.key, required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<ToolTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            color: _hover ? widget.color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hover ? widget.color.withValues(alpha: 0.6) : DesignerColors.border),
            boxShadow: _hover ? [BoxShadow(color: widget.color.withValues(alpha: 0.15), blurRadius: 8)] : null,
          ),
          // مرن: الأيقونة والنص يتقلّصان مع حجم الخلية فلا يحدث فيض أبداً
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(widget.icon, size: 17, color: widget.color),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, height: 1.15, color: DesignerColors.text)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// زر أيقونة يُفعَّل ويُطفأ (عريض، محاذاة…)
class IconToggle extends StatelessWidget {
  const IconToggle({super.key, required this.icon, required this.on, required this.onTap, this.tooltip});
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 34,
          decoration: BoxDecoration(
            color: on ? DesignerColors.blue.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? DesignerColors.blue : DesignerColors.border),
          ),
          child: Icon(icon, size: 18, color: on ? DesignerColors.blue : DesignerColors.muted),
        ),
      ),
    );
  }
}

/// مفتاح تشغيل بسطر واحد وشرح صغير
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, color: DesignerColors.text)),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 11, color: DesignerColors.muted)),
          ]),
        ),
        Transform.scale(scale: 0.8, child: Switch(value: value, onChanged: onChanged)),
      ]),
    );
  }
}

/// خيار في [ChoiceRow]
class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, [this.icon]);
  final T value;
  final String label;
  final IconData? icon;
}

/// أزرار اختيار متجاورة تتقاسم العرض المتاح (لا تفيض على الشاشات الضيقة)
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({super.key, required this.options, required this.value, required this.onChanged});
  final List<ChoiceOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DesignerColors.border),
      ),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: InkWell(
              onTap: () => onChanged(o.value),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                decoration: BoxDecoration(
                  color: o.value == value ? DesignerColors.blue.withValues(alpha: 0.12) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (o.icon != null) ...[
                    Icon(o.icon, size: 16, color: o.value == value ? DesignerColors.blue : DesignerColors.muted),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      o.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: o.value == value ? DesignerColors.blue : DesignerColors.text,
                        fontWeight: o.value == value ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
