// lib/invoice_designer/print_choices_dialog.dart
//
// 🖨️ «ما يُطبع الآن»: لكل نوع طباعة بطاقة فيها الخيارات أزراراً ظاهرة (التصميم الأصلي
// أو أحد تصاميمك) — الاختيار يُحفظ فوراً. ولأنواع الطابعة الحرارية: عرض الورق 80 / 58 ملم.

import 'package:flutter/material.dart';

import '../services/receipt_paper.dart';
import '../widgets/app_dialog_shell.dart';
import 'invoice_layout.dart';
import 'invoice_layout_store.dart';

const _navy = Color(0xFF0F3460);
const _teal = Color(0xFF0F766E);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);

class PrintChoicesDialog extends StatefulWidget {
  const PrintChoicesDialog({
    super.key,
    required this.targets,
    required this.layouts,
    required this.current,
    required this.onChange,
  });

  final List<PrintTarget> targets;
  final List<InvoiceLayout> layouts;

  /// المختار الآن لكل نوع ('' = الأصلي).
  final Map<String, String> current;

  /// يحفظ الاختيار (يُستدعى فور الضغط).
  final Future<void> Function(PrintTarget target, String layoutId) onChange;

  @override
  State<PrintChoicesDialog> createState() => _PrintChoicesDialogState();
}

class _PrintChoicesDialogState extends State<PrintChoicesDialog> {
  late final Map<String, String> _sel = Map.of(widget.current);
  String? _saving;

  @override
  void initState() {
    super.initState();
    ReceiptPaper.get(); // يحدّث القيمة المعروضة
  }

  IconData _icon(PrintTarget t) {
    if (t.key == PrintTarget.posReceipt.key) return Icons.point_of_sale_rounded;
    if (t.roll) return Icons.receipt_long_rounded;
    if (t.kind != 'invoice' || t.key == PrintTarget.adjustmentVoucher.key) return Icons.request_quote_rounded;
    return Icons.description_rounded;
  }

  Future<void> _pick(PrintTarget t, String id) async {
    if (_sel[t.key] == id) return;
    setState(() {
      _sel[t.key] = id;
      _saving = t.key;
    });
    try {
      await widget.onChange(t, id);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRoll = widget.targets.any((t) => t.roll);
    return AppDialogShell(
      icon: Icons.print_rounded,
      color: _navy,
      title: 'ما يُطبع الآن',
      subtitle: 'لكل نوع طباعة: التصميم الأصلي أو أحد تصاميمك — يُحفظ فور الضغط',
      onClose: () => Navigator.pop(context),
      maxWidth: 620,
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        children: [
          if (hasRoll) ...[_paperCard(), const SizedBox(height: 12)],
          for (final t in widget.targets) ...[_targetCard(t), const SizedBox(height: 10)],
        ],
      ),
      actions: [
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size(110, 44)),
          onPressed: () => Navigator.pop(context),
          child: const Text('تم'),
        ),
      ],
    );
  }

  /// 🧻 عرض ورق الطابعة الحرارية (لهذا الجهاز)
  Widget _paperCard() => ValueListenableBuilder<int>(
        valueListenable: ReceiptPaper.current,
        builder: (_, mm, __) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_teal.withValues(alpha: 0.08), _teal.withValues(alpha: 0.02)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _teal.withValues(alpha: 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.straighten_rounded, color: _teal, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('عرض ورق الطابعة الحرارية',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _text)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text('لهذا الجهاز — يُطبَّق على إيصال الكاشير وفاتورة البيع الحرارية بالتصميم الأصلي',
                style: TextStyle(fontSize: 12, color: _muted, height: 1.4)),
            const SizedBox(height: 10),
            Row(children: [
              for (final w in const [80, 58]) ...[
                Expanded(
                  child: _PaperOption(
                    mm: w,
                    selected: mm == w,
                    onTap: () => ReceiptPaper.set(w),
                  ),
                ),
                if (w == 80) const SizedBox(width: 10),
              ],
            ]),
          ]),
        ),
      );

  Widget _targetCard(PrintTarget t) {
    final options = widget.layouts.where(t.accepts).toList();
    final cur = _sel[t.key] ?? '';
    final curValid = cur.isEmpty || options.any((l) => l.id == cur);
    final selected = curValid ? cur : '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _navy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Icon(_icon(t), color: _navy, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _text)),
              const SizedBox(height: 2),
              Text(t.hint, style: const TextStyle(fontSize: 12, color: _muted, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
            child: Text(t.roll ? 'حراري' : 'A4',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _muted)),
          ),
          if (_saving == t.key) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Choice(
            label: 'التصميم الأصلي',
            icon: Icons.auto_awesome_rounded,
            selected: selected.isEmpty,
            onTap: () => _pick(t, ''),
          ),
          for (final l in options)
            _Choice(
              label: l.name,
              icon: Icons.brush_rounded,
              selected: selected == l.id,
              onTap: () => _pick(t, l.id),
            ),
        ]),
        if (options.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('لا تصاميم لهذا الورق بعد — صمّم واحداً ليظهر هنا.',
                style: TextStyle(fontSize: 11.5, color: _muted)),
          ),
      ]),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? _navy : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? _navy : _line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(selected ? Icons.check_circle_rounded : icon, size: 17, color: selected ? Colors.white : _muted),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: selected ? Colors.white : _text,
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PaperOption extends StatelessWidget {
  const _PaperOption({required this.mm, required this.selected, required this.onTap});
  final int mm;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // شريط ورق مصغّر بعرض نسبي — يرى المستخدم الفرق بعينه
    final stripW = mm == 80 ? 34.0 : 25.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _teal : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? _teal : _line, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Container(
              width: stripW,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? Colors.white : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: selected ? Colors.white : const Color(0xFFCBD5E1)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 1.5),
                    height: 2,
                    width: stripW - 10,
                    color: selected ? _teal.withValues(alpha: 0.5) : const Color(0xFFCBD5E1),
                  ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$mm ملم',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: selected ? Colors.white : _text)),
                Text(mm == 80 ? 'الأشيع للكاشير' : 'الطابعات الصغيرة',
                    style: TextStyle(fontSize: 11.5, color: selected ? Colors.white70 : _muted)),
              ]),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          ]),
        ),
      ),
    );
  }
}
