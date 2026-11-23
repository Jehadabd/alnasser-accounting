// lib/screens/cost_method_dialog.dart
//
// 💰 «كيف تُحسب كلفة هذه المادة؟» — تظهر عند «تأكيد واستلام» فقط للمواد التي:
//   طريقتها «اسألني» (من بطاقتها أو من الإعداد العام) + لها رصيد قبل الشراء +
//   كلفة الشراء الجديدة تختلف عن كلفتها الحالية.
// لكل مادة: الباقي وكلفته، الجديد وكلفته، والنتيجة بكل طريقة بالأرقام، مع
// «تذكّر لهذه المادة» و«طبّق على الكل». لا يُكتب شيء هنا — النتيجة تذهب للحفظ.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../services/cost_method_policy.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF5F7FB);
const _navy = Color(0xFF0F3460);
const _blue = Color(0xFF1D4ED8);
const _teal = Color(0xFF0D9488);
const _amber = Color(0xFFD97706);

final _fmt = intl.NumberFormat('#,##0.##', 'en_US');

class CostCase {
  CostCase({
    required this.productId,
    required this.name,
    required this.baseUnit,
    required this.stock,
    required this.cost,
    required this.qty,
    required this.newCost,
  });
  final int productId;
  final String name;
  final String baseUnit;
  final double stock, cost, qty, newCost;

  double get average => CostMethodPolicy.average(stock: stock, cost: cost, qty: qty, newCost: newCost);
}

class CostChoice {
  CostChoice(this.methods, this.remember);

  /// رقم المادة ← avco / last_purchase
  final Map<int, String> methods;

  /// المواد التي اخترت «تذكّر لهذه المادة»
  final Set<int> remember;
}

/// null = ألغيت (لا حفظ).
Future<CostChoice?> showCostMethodDialog(BuildContext context, List<CostCase> cases) =>
    showDialog<CostChoice>(context: context, barrierDismissible: false, builder: (_) => _CostDialog(cases));

class _CostDialog extends StatefulWidget {
  const _CostDialog(this.cases);
  final List<CostCase> cases;
  @override
  State<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends State<_CostDialog> {
  late final Map<int, String> _m = {for (final c in widget.cases) c.productId: CostMethodPolicy.avco};
  final Set<int> _remember = {};

  void _all(String m) => setState(() {
        for (final c in widget.cases) {
          _m[c.productId] = m;
        }
      });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [_navy, _blue])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.price_change_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('كيف تُحسب الكلفة؟', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('${widget.cases.length} مادة تغيّرت كلفتها ولها رصيد قبل هذا الشراء',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _allChip('الكل: المتوسط المرجّح', CostMethodPolicy.avco),
                _allChip('الكل: آخر سعر شراء', CostMethodPolicy.last),
              ]),
            ]),
          ),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              shrinkWrap: true,
              itemCount: widget.cases.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _card(widget.cases[i]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء الحفظ')),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, CostChoice(Map.of(_m), Set.of(_remember))),
                style: FilledButton.styleFrom(
                  backgroundColor: _navy,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('متابعة الحفظ', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _allChip(String label, String m) {
    final on = widget.cases.every((c) => _m[c.productId] == m);
    return ActionChip(
      onPressed: () => _all(m),
      avatar: Icon(on ? Icons.check_circle_rounded : Icons.done_all_rounded, size: 18, color: on ? _navy : Colors.white),
      label: Text(label, style: TextStyle(color: on ? _navy : Colors.white, fontWeight: FontWeight.w700)),
      backgroundColor: on ? Colors.white : Colors.white.withValues(alpha: 0.14),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
      shape: const StadiumBorder(),
    );
  }

  Widget _card(CostCase c) {
    final m = _m[c.productId]!;
    final up = c.newCost > c.cost;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: up ? _amber : _teal),
          const SizedBox(width: 8),
          Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: _ink))),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: _fact('الباقي عندك', '${_fmt.format(c.stock)} ${c.baseUnit}', 'بكلفة ${_fmt.format(c.cost)}')),
            const Icon(Icons.add_rounded, color: _muted),
            Expanded(child: _fact('الشراء الجديد', '${_fmt.format(c.qty)} ${c.baseUnit}', 'بكلفة ${_fmt.format(c.newCost)}')),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _option(c, CostMethodPolicy.avco, 'المتوسط المرجّح', c.average, 'مُوصى به — يوزّع الفرق على كل القطع', m),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _option(c, CostMethodPolicy.last, 'آخر سعر شراء', c.newCost, 'كل القطع بكلفة الشراء الأخير', m),
          ),
        ]),
        const SizedBox(height: 4),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: _remember.contains(c.productId),
          onChanged: (v) => setState(() => v == true ? _remember.add(c.productId) : _remember.remove(c.productId)),
          title: const Text('تذكّر هذه الطريقة لهذه المادة (لا تسألني عنها ثانية)', style: TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _fact(String t, String v, String s) => Column(children: [
        Text(t, style: const TextStyle(color: _muted, fontSize: 11.5)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
        Text(s, style: const TextStyle(color: _muted, fontSize: 12)),
      ]);

  Widget _option(CostCase c, String value, String title, double result, String hint, String current) {
    final on = current == value;
    final color = value == CostMethodPolicy.avco ? _blue : _teal;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _m[c.productId] = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? color : _line, width: on ? 1.8 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 18, color: on ? color : _muted),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: on ? color : _ink))),
          ]),
          const SizedBox(height: 6),
          Text('${_fmt.format(result)} / ${c.baseUnit}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: on ? color : _ink)),
          Text(hint, style: const TextStyle(color: _muted, fontSize: 11.5)),
        ]),
      ),
    );
  }
}
