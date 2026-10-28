// lib/widgets/profit_discount_dialog.dart
//
// ٪ خصم بنسبة من ربح الفاتورة — نافذة بنفس لغة تصميم البرنامج:
//   • النسبة كبيرة في الوسط مع − / + وشريط سحب، وأزرار سريعة لنسب شائعة.
//   • النتيجة فوراً: مبلغ الخصم، وصافي الفاتورة بعده، وتوزيع الربح (لمن يرى الأرباح).
//   • Enter داخل خانة النسبة = تطبيق، Esc = إغلاق.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

const _navy = Color(0xFF0F3460);
const _ink = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE6EBF2);
const _red = Color(0xFFDC2626);
const _green = Color(0xFF047857);
const _bg = Color(0xFFF6F8FB);

String _fmt(num v) => NumberFormat('#,##0', 'en_US').format(v);

/// يعيد: null = إلغاء، 0 = بلا خصم، غير ذلك = مبلغ الخصم (مقرّب لأقرب دينار).
Future<double?> showProfitDiscountDialog(
  BuildContext context, {
  required double profit,
  required double invoiceTotal,
  required double defaultPercent,
  required bool canSeeProfit,
  double currentDiscount = 0,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _ProfitDiscountDialog(
      profit: profit,
      invoiceTotal: invoiceTotal,
      defaultPercent: defaultPercent,
      canSeeProfit: canSeeProfit,
      currentDiscount: currentDiscount,
    ),
  );
}

class _ProfitDiscountDialog extends StatefulWidget {
  const _ProfitDiscountDialog({
    required this.profit,
    required this.invoiceTotal,
    required this.defaultPercent,
    required this.canSeeProfit,
    required this.currentDiscount,
  });
  final double profit;
  final double invoiceTotal;
  final double defaultPercent;
  final bool canSeeProfit;
  final double currentDiscount;

  @override
  State<_ProfitDiscountDialog> createState() => _ProfitDiscountDialogState();
}

class _ProfitDiscountDialogState extends State<_ProfitDiscountDialog> {
  static const _quick = <double>[5, 10, 15, 20, 25, 30, 50];
  late final TextEditingController _ctrl;
  late double _pct;

  @override
  void initState() {
    super.initState();
    // إن كان على الفاتورة خصم الآن: نبدأ من نسبته، وإلا من النسبة الافتراضية في الإعدادات
    final fromCurrent = widget.profit > 0 && widget.currentDiscount > 0
        ? (widget.currentDiscount / widget.profit * 100)
        : null;
    _pct = (fromCurrent ?? widget.defaultPercent).clamp(0.0, 100.0).toDouble();
    _pct = double.parse(_pct.toStringAsFixed(1));
    _ctrl = TextEditingController(text: _pctText(_pct));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _pctText(double p) => p.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  double get _amount => (widget.profit * _pct / 100).roundToDouble();

  void _setPct(double p, {bool fromField = false}) {
    final v = p.clamp(0.0, 100.0).toDouble();
    setState(() => _pct = v);
    if (!fromField) {
      _ctrl.value = TextEditingValue(
        text: _pctText(v),
        selection: TextSelection.collapsed(offset: _pctText(v).length),
      );
    }
  }

  void _apply() => Navigator.pop(context, _amount);

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    final after = widget.invoiceTotal - amount;
    final keep = widget.profit - amount;
    return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _percentInput(),
                  const SizedBox(height: 6),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      activeTrackColor: _red,
                      inactiveTrackColor: const Color(0xFFFDE2E2),
                      thumbColor: _red,
                      overlayColor: _red.withValues(alpha: 0.12),
                    ),
                    child: Slider(value: _pct, min: 0, max: 100, divisions: 200, onChanged: (v) => _setPct(v)),
                  ),
                  _quickChips(),
                  const SizedBox(height: 18),
                  _resultCard(amount, after),
                  if (widget.canSeeProfit) ...[
                    const SizedBox(height: 14),
                    _profitSplit(amount, keep),
                  ],
                ]),
              ),
            ),
            _actions(amount),
          ]),
        ),
    );
  }

  Widget _header(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 8, 16),
        decoration: const BoxDecoration(
          color: Color(0xFFFEF6F6),
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFF87171), _red]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: _red.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.percent_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('خصم من الربح', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              SizedBox(height: 2),
              Text('اختر نسبة تُخصم من ربح هذه الفاتورة',
                  style: TextStyle(fontSize: 12.5, color: _muted, height: 1.4)),
            ]),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: _muted),
          ),
        ]),
      );

  Widget _percentInput() {
    Widget step(IconData icon, String tip, double delta) => Tooltip(
          message: tip,
          child: Material(
            color: _bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _setPct((_pct + delta).roundToDouble()),
              child: SizedBox(width: 52, height: 52, child: Icon(icon, color: _navy)),
            ),
          ),
        );
    return Row(children: [
      step(Icons.remove_rounded, 'إنقاص 1%', -1),
      const SizedBox(width: 12),
      Expanded(
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _ink, height: 1.1),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _bg,
            suffixText: '%',
            suffixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _muted),
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _line)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _red, width: 1.6)),
          ),
          onChanged: (t) => _setPct(double.tryParse(t.trim()) ?? 0.0, fromField: true),
          onSubmitted: (_) => _apply(),
        ),
      ),
      const SizedBox(width: 12),
      step(Icons.add_rounded, 'زيادة 1%', 1),
    ]);
  }

  Widget _quickChips() => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final q in _quick)
            _QuickChip(
              label: '${_pctText(q)}%',
              selected: (_pct - q).abs() < 0.05,
              onTap: () => _setPct(q),
            ),
        ],
      );

  Widget _resultCard(double amount, double after) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مبلغ الخصم', style: TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                child: FittedBox(
                  key: ValueKey(amount),
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('${_fmt(amount)} د.ع',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _red)),
                ),
              ),
            ]),
          ),
          Container(width: 1, height: 44, color: _line, margin: const EdgeInsets.symmetric(horizontal: 14)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الفاتورة بعد الخصم', style: TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text('${_fmt(after)} د.ع',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
              ),
              Text('بدل ${_fmt(widget.invoiceTotal)}', style: const TextStyle(fontSize: 11.5, color: _muted)),
            ]),
          ),
        ]),
      );

  Widget _profitSplit(double amount, double keep) {
    final share = widget.profit <= 0 ? 0.0 : (amount / widget.profit).clamp(0.0, 1.0).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.trending_up_rounded, size: 17, color: _green),
        const SizedBox(width: 6),
        Text('ربح الفاتورة ${_fmt(widget.profit)}', style: const TextStyle(fontSize: 12.5, color: _muted)),
        const Spacer(),
        Text('يبقى لك ${_fmt(keep)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _green)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 10,
          child: LayoutBuilder(builder: (context, c) {
            return Stack(children: [
              Container(color: const Color(0xFFD1FAE5)),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: c.maxWidth * share,
                color: _red,
              ),
            ]);
          }),
        ),
      ),
    ]);
  }

  Widget _actions(double amount) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          if (widget.currentDiscount > 0) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _red),
              onPressed: () => Navigator.pop(context, 0.0),
              icon: const Icon(Icons.backspace_outlined, size: 18),
              label: const Text('إزالة الخصم'),
            ),
          ],
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: amount <= 0 ? null : _apply,
            icon: const Icon(Icons.check_rounded, size: 20),
            label: Text('تطبيق خصم ${_fmt(amount)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? _red : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _red : _line),
          boxShadow: selected
              ? [BoxShadow(color: _red.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 3))]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : _ink)),
            ),
          ),
        ),
      );
}
