// lib/owner/ai_invoice/ai_new_units_dialog.dart
//
// 📦 «وحدات المادة الجديدة» — من سطر فاتورة شراء مقروءة بالذكاء الاصطناعي لمادة غير موجودة.
//
//   الفاتورة: «كرتون بـ 1,000». السؤال: هل «كرتون» أصغر وحدة تبيعها؟
//     • نعم ⇒ الكرتون هو الوحدة الأساسية.
//     • لا  ⇒ سلسلة: الكرتون يحتوي 10 باكيت ← الباكيت يحتوي 10 قطعة …
//   والكلفة تتوزع وحدها: الباكيت 100، القطعة 10 — وتُحمل إلى بطاقة المادة عند تعريفها
//   في شاشة الشراء (الوحدة الأساسية، هرم الوحدات، كلفة الأصغر).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'ai_purchase_prefill.dart';

const _aiA = Color(0xFF4F46E5);
const _aiB = Color(0xFF7C3AED);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF5F6FB);
const _good = Color(0xFF16A34A);
const _warn = Color(0xFFEA580C);

final _fmt = intl.NumberFormat('#,##0.##', 'en_US');

/// يفتح النافذة. null = أُلغيت.
Future<AiUnitPlan?> showNewUnitsDialog(
  BuildContext context, {
  required String productName,
  required String buyUnit,
  required double buyPrice,
  required double qty,
  AiUnitPlan? current,
}) =>
    showDialog<AiUnitPlan>(
      context: context,
      builder: (_) => _NewUnitsDialog(productName: productName, buyUnit: buyUnit, buyPrice: buyPrice, qty: qty, current: current),
    );

/// مستوى في السلسلة (من الأكبر إلى الأصغر): «الوحدة السابقة تحتوي [qty] من [name]».
class _Level {
  _Level({String name = '', String qty = ''})
      : name = TextEditingController(text: name),
        qty = TextEditingController(text: qty);
  final TextEditingController name;
  final TextEditingController qty;

  String get n => name.text.trim();
  double get q => double.tryParse(qty.text.replaceAll(',', '').replaceAll('٫', '.').trim()) ?? 0;

  void dispose() {
    name.dispose();
    qty.dispose();
  }
}

class _NewUnitsDialog extends StatefulWidget {
  const _NewUnitsDialog({required this.productName, required this.buyUnit, required this.buyPrice, required this.qty, this.current});
  final String productName;
  final String buyUnit;
  final double buyPrice;
  final double qty;
  final AiUnitPlan? current;

  @override
  State<_NewUnitsDialog> createState() => _NewUnitsDialogState();
}

class _NewUnitsDialogState extends State<_NewUnitsDialog> {
  static const _suggest = ['قطعة', 'باكيت', 'علبة', 'حبة', 'درزن', 'كيس', 'شدة', 'متر', 'كغم', 'غرام', 'لتر'];

  bool? _smallest;
  final List<_Level> _chain = [];

  String get _buy => widget.buyUnit.trim().isEmpty ? 'وحدة الشراء' : widget.buyUnit.trim();

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    if (c != null) {
      final units = c.units; // من الأصغر إلى الأكبر
      if (c.levels.isEmpty) {
        _smallest = true;
      } else if (units.last == _buy) {
        _smallest = false;
        for (var i = c.levels.length - 1; i >= 0; i--) {
          _chain.add(_Level(name: units[i], qty: _n((c.levels[i]['quantity'] as num).toDouble())));
        }
      }
    }
  }

  @override
  void dispose() {
    for (final l in _chain) {
      l.dispose();
    }
    super.dispose();
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// خطأ المستوى [i] أو null.
  String? _errorOf(int i) {
    final l = _chain[i];
    if (l.q <= 0) return 'اكتب العدد';
    if (l.n.isEmpty) return 'اكتب اسم الوحدة';
    final parent = i == 0 ? _buy : _chain[i - 1].n;
    if (l.n == parent || l.n == _buy) return 'الاسم نفس وحدة أكبر';
    for (var j = 0; j < i; j++) {
      if (_chain[j].n == l.n) return 'الاسم مكرر';
    }
    if (l.q == 1) return 'العدد 1 يعني الوحدة نفسها';
    return null;
  }

  bool get _chainValid => _chain.isNotEmpty && [for (var i = 0; i < _chain.length; i++) _errorOf(i)].every((e) => e == null);
  bool get _canSave => _smallest == true || (_smallest == false && _chainValid);

  /// [الاسم، الكلفة] من الأكبر إلى الأصغر للمستويات الصالحة.
  List<(String, double, double)> _flow() {
    final out = <(String, double, double)>[(_buy, widget.buyPrice, 1)];
    var cost = widget.buyPrice, total = 1.0;
    for (var i = 0; i < _chain.length; i++) {
      if (_errorOf(i) != null) break;
      cost /= _chain[i].q;
      total *= _chain[i].q;
      out.add((_chain[i].n, cost, total));
    }
    return out;
  }

  AiUnitPlan _plan() {
    if (_smallest == true) return AiUnitPlan(baseUnit: _buy, levels: const [], baseCost: widget.buyPrice);
    // السلسلة من الأكبر: [ (n1,q1), (n2,q2) ] ⇒ الأصغر n2، والمستويات: n1×q2، ثم الشراء×q1
    final names = [_buy, ..._chain.map((l) => l.n)];
    final levels = <Map<String, dynamic>>[
      for (var i = _chain.length - 1; i >= 0; i--) {'unit_name': names[i], 'quantity': _chain[i].q},
    ];
    final total = _chain.fold<double>(1, (s, l) => s * l.q);
    return AiUnitPlan(baseUnit: _chain.last.n, levels: levels, baseCost: total > 0 ? widget.buyPrice / total : widget.buyPrice);
  }

  void _choose(bool smallest) => setState(() {
        _smallest = smallest;
        if (!smallest && _chain.isEmpty) _chain.add(_Level());
      });

  void _addLevel() => setState(() => _chain.add(_Level()));

  void _removeLevel(int i) {
    final gone = _chain[i];
    setState(() => _chain.removeAt(i));
    // بعد أن تُزال حقوله من الشاشة
    WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: _bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(opacity: ((v - 0.96) / 0.04).clamp(0.0, 1.0), child: Transform.scale(scale: v, child: child)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 580, maxHeight: h * 0.9),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _invoiceCard(),
                  const SizedBox(height: 18),
                  Text('هل «$_buy» أصغر وحدة تبيعها؟',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 10),
                  LayoutBuilder(builder: (context, c) {
                    final yes = _ChoiceCard(
                      icon: Icons.check_circle_rounded,
                      title: 'نعم، هي الأصغر',
                      subtitle: 'أبيع «$_buy» كما هو',
                      selected: _smallest == true,
                      color: _good,
                      onTap: () => _choose(true),
                    );
                    final no = _ChoiceCard(
                      icon: Icons.account_tree_rounded,
                      title: 'لا، فيها وحدات أصغر',
                      subtitle: 'مثلاً: باكيت ثم قطعة',
                      selected: _smallest == false,
                      color: _aiA,
                      onTap: () => _choose(false),
                    );
                    if (c.maxWidth < 420) return Column(children: [yes, const SizedBox(height: 10), no]);
                    return Row(children: [Expanded(child: yes), const SizedBox(width: 10), Expanded(child: no)]);
                  }),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: AlignmentDirectional.topStart,
                    child: _smallest == false ? _chainEditor() : const SizedBox(width: double.infinity),
                  ),
                  if (_smallest != null) ...[
                    const SizedBox(height: 16),
                    _preview(),
                  ],
                ]),
              ),
            ),
            _footer(),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_aiA, _aiB], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: const Icon(Icons.account_tree_rounded, color: Colors.white, size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('وحدات المادة الجديدة', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(widget.productName,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
            ]),
          ),
          IconButton(
            tooltip: 'إغلاق',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ]),
      );

  Widget _invoiceCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
          boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _aiA.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.receipt_long_rounded, color: _aiA),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('في فاتورة المورد', style: TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 2),
              Text('${_fmt.format(widget.qty)} × $_buy',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('سعر «$_buy»', style: const TextStyle(fontSize: 12, color: _muted)),
            Text(_fmt.format(widget.buyPrice), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _aiA)),
          ]),
        ]),
      );

  Widget _chainEditor() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ما الذي في داخلها؟', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _muted)),
        const SizedBox(height: 8),
        for (var i = 0; i < _chain.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Icon(Icons.keyboard_double_arrow_down_rounded, color: _aiB, size: 22),
            ),
          _levelCard(i),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _chainValid ? _addLevel : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: _aiA,
              side: BorderSide(color: _aiA.withValues(alpha: _chainValid ? 0.6 : 0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(_chain.isEmpty ? 'وحدة أصغر' : 'وحدة أصغر من «${_chain.last.n.isEmpty ? '…' : _chain.last.n}»'),
          ),
        ),
      ]),
    );
  }

  Widget _levelCard(int i) {
    final l = _chain[i];
    final parent = i == 0 ? _buy : (_chain[i - 1].n.isEmpty ? '…' : _chain[i - 1].n);
    final err = _errorOf(i);
    final touched = l.n.isNotEmpty || l.qty.text.trim().isNotEmpty;
    final showErr = err != null && touched;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: showErr ? _warn.withValues(alpha: 0.6) : (err == null ? _aiA.withValues(alpha: 0.45) : _line), width: 1.3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _unitTag(parent),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('يحتوي', style: TextStyle(color: _muted, fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 82,
            child: TextField(
              controller: l.qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              onChanged: (_) => setState(() {}),
              decoration: _dec('العدد'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: l.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
              onChanged: (_) => setState(() {}),
              decoration: _dec('اسم الوحدة'),
            ),
          ),
          if (_chain.length > 1 && i == _chain.length - 1)
            IconButton(
              tooltip: 'حذف',
              onPressed: () => _removeLevel(i),
              icon: const Icon(Icons.delete_outline_rounded, color: _warn),
            )
          else
            const SizedBox(width: 8),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in _suggest)
            if (s != _buy && !_chain.take(i).any((x) => x.n == s))
              _SuggestChip(
                label: s,
                selected: l.n == s,
                onTap: () => setState(() => l.name.text = s),
              ),
        ]),
        if (showErr)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, size: 15, color: _warn),
              const SizedBox(width: 5),
              Text(err ?? '', style: const TextStyle(fontSize: 12, color: _warn, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }

  Widget _unitTag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_aiA, _aiB]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: _bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _aiA, width: 1.6)),
      );

  /// معاينة: كلفة كل وحدة، وكم وحدة صغرى في وحدة الشراء.
  Widget _preview() {
    final flow = _smallest == true ? [(_buy, widget.buyPrice, 1.0)] : _flow();
    final smallest = flow.last;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(flow.map((e) => '${e.$1}${e.$2}').join('|')),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_good.withValues(alpha: 0.08), _good.withValues(alpha: 0.03)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _good.withValues(alpha: 0.30)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.price_change_rounded, color: _good, size: 20),
            SizedBox(width: 6),
            Text('الكلفة لكل وحدة', style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var i = 0; i < flow.length; i++) ...[
              if (i > 0) const Icon(Icons.chevron_left_rounded, color: _muted),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: i == flow.length - 1 ? _good : _line, width: i == flow.length - 1 ? 1.5 : 1),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(flow[i].$1, style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w700)),
                  Text(_fmt.format(flow[i].$2),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: i == flow.length - 1 ? _good : _ink)),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Text(
            _smallest == true
                ? 'الوحدة الأساسية «$_buy» بكلفة ${_fmt.format(widget.buyPrice)}.'
                : '«$_buy» = ${_fmt.format(smallest.$3)} ${smallest.$1} • كلفة «${smallest.$1}» ${_fmt.format(smallest.$2)} '
                    '• تدخل المخزون ${_fmt.format(widget.qty * smallest.$3)} ${smallest.$1}.',
            style: const TextStyle(color: _ink, height: 1.6, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }

  Widget _footer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
        child: Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _aiA,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _canSave ? () => Navigator.pop(context, _plan()) : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('حفظ الوحدات', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

/// بطاقة اختيار كبيرة (نعم / لا).
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: title,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? color : _line, width: selected ? 1.8 : 1),
            boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.16), blurRadius: 16, offset: const Offset(0, 6))] : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: selected ? color : color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: selected ? Colors.white : color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? color : _ink)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _SuggestChip extends StatelessWidget {
  const _SuggestChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? _aiA : _aiA.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : _aiA)),
            ),
          ),
        ),
      );
}
