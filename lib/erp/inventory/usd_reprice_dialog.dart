// lib/erp/inventory/usd_reprice_dialog.dart
//
// 💱 بعد تغيير سعر الدولار: الكلفة تغيّرت تلقائياً، والأسعار تبقى حتى توافق.
// نافذة تعرض مواد الدولار (الكلفة قبل ← بعد) وأسعار البيع المقترحة بنفس النسبة
// لكل مستوى سعر (مفرد، مفرد 2، منزل، جملة، جملة 2، أخرى) مع تقريب اختياري.
//   • كل سعر مقترح حقل يُعدَّل فوراً قبل الحفظ (ما تعدّله لا يغيّره التقريب بعدها).
//   • لكل مادة مربع اختيار: غير المختارة لا تُلمس أسعارها.
//   • «احفظ الأسعار» يكتب ما في الحقول، و«اترك الأسعار» لا يغيّر شيئاً.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../accounting/screens/acc_ui.dart' show fmtMoney, showError, showOk;
import 'price_tools.dart' show PriceTools, roundToStep;
import 'usd_cost_service.dart';

/// يعيد تسعير مواد الدولار بآخر سعر، ثم يسأل عن رفع الأسعار إن تغيّر شيء.
Future<void> repriceUsdProductsAndAsk(BuildContext context) async {
  RepriceResult r;
  try {
    r = await UsdCostService.repriceAll();
  } catch (e) {
    if (context.mounted) showError(context, 'تعذّر تحديث كلفة مواد الدولار: $e');
    return;
  }
  if (r.isEmpty || !context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _UsdRepriceDialog(result: r));
}

/// أسماء مستويات السعر كما في «نوع الفاتورة» (price1 … price6).
const _levelNames = ['مفرد', 'مفرد 2', 'منزل', 'جملة', 'جملة 2', 'أخرى'];

class _UsdRepriceDialog extends StatefulWidget {
  const _UsdRepriceDialog({required this.result});
  final RepriceResult result;
  @override
  State<_UsdRepriceDialog> createState() => _UsdRepriceDialogState();
}

class _UsdRepriceDialogState extends State<_UsdRepriceDialog> {
  double _step = 250;
  bool _busy = false;

  /// [مادة][مستوى] ← حقل السعر الجديد (للمستويات التي لها سعر فقط).
  final Map<int, Map<int, TextEditingController>> _ctl = {};

  /// الحقول التي عدّلها المستخدم بيده: لا يغيّرها تغيير التقريب.
  final Set<String> _edited = {};

  /// المواد المختارة للحفظ.
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    for (final p in widget.result.products) {
      _selected.add(p.productId);
      final m = <int, TextEditingController>{};
      for (var i = 0; i < 6; i++) {
        if (p.prices[i] > 0) m[i] = TextEditingController(text: _fmtPlain(_suggest(p, i)));
      }
      _ctl[p.productId] = m;
    }
  }

  @override
  void dispose() {
    for (final m in _ctl.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  double _suggest(RepricedProduct p, int i) => p.prices[i] > 0 ? roundToStep(p.prices[i] * p.ratio, _step) : 0;

  static String _fmtPlain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static double? _parse(String s) => double.tryParse(s.replaceAll(',', '').trim());

  void _setStep(double s) {
    setState(() {
      _step = s;
      for (final p in widget.result.products) {
        final m = _ctl[p.productId]!;
        m.forEach((i, c) {
          if (!_edited.contains('${p.productId}:$i')) c.text = _fmtPlain(_suggest(p, i));
        });
      }
    });
  }

  Future<void> _apply() async {
    // تحقق قبل أي حفظ: كل حقل مختار رقم موجب
    final bad = <String>[];
    for (final p in widget.result.products) {
      if (!_selected.contains(p.productId)) continue;
      _ctl[p.productId]!.forEach((i, c) {
        final v = _parse(c.text);
        if (v == null || v <= 0) bad.add('${p.name} (${_levelNames[i]})');
      });
    }
    if (bad.isNotEmpty) {
      showError(context, 'سعر غير صالح: ${bad.take(5).join('، ')}');
      return;
    }
    setState(() => _busy = true);
    var changed = 0, products = 0;
    final errors = <String>[];
    for (final p in widget.result.products) {
      if (!_selected.contains(p.productId)) continue;
      try {
        final n = await PriceTools().applyPrices(p.productId, {
          for (final e in _ctl[p.productId]!.entries) e.key + 1: _parse(e.value.text)!,
        });
        changed += n;
        if (n > 0) products++;
      } catch (e) {
        errors.add('${p.name}: $e');
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (errors.isEmpty) {
      showOk(context, 'حُفظت أسعار $products مادة ($changed سعر)');
    } else {
      showError(context, 'حُفظ بعضها، وتعذّر: ${errors.join('، ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final avg = r.products.fold<double>(0, (s, p) => s + p.changePct) / r.products.length;
    final all = _selected.length == r.products.length;
    return AlertDialog(
      title: const Text('تحديث كلفة مواد الدولار وأسعارها'),
      content: SizedBox(
        width: 900,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'سعر الدولار الآن ${fmtMoney(r.rate)}. تغيّرت كلفة ${r.products.length} مادة كلفتها بالدولار '
            '(${avg >= 0 ? '+' : '−'}${avg.abs().toStringAsFixed(1)}% في المتوسط).',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'أرباح ما بيع سابقاً لم تتغير: ثُبّتت كلفة ${r.frozenItems} بند بيع و${r.frozenAdjustments} تسوية كانت بلا كلفة محفوظة. '
            'الأسعار المقترحة بنفس نسبة تغيّر الكلفة — عدّل أي سعر مباشرة في حقله قبل الحفظ.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.5),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('تقريب المقترح:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('بلا')),
                  ButtonSegment(value: 250, label: Text('250')),
                  ButtonSegment(value: 500, label: Text('500')),
                  ButtonSegment(value: 1000, label: Text('1000')),
                ],
                selected: {_step},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (s) => _setStep(s.first),
              ),
            ]),
            TextButton.icon(
              onPressed: () => setState(() {
                if (all) {
                  _selected.clear();
                } else {
                  _selected.addAll(r.products.map((p) => p.productId));
                }
              }),
              icon: Icon(all ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18),
              label: Text(all ? 'إلغاء تحديد الكل' : 'تحديد الكل'),
            ),
            Text('${_selected.length} من ${r.products.length} مادة ستُحفظ',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
          ]),
          const SizedBox(height: 8),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: r.products.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (_, k) => _productRow(r.products[k]),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('اترك الأسعار')),
        FilledButton.icon(
          onPressed: _busy || _selected.isEmpty ? null : _apply,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded),
          label: const Text('احفظ الأسعار'),
        ),
      ],
    );
  }

  Widget _productRow(RepricedProduct p) {
    final on = _selected.contains(p.productId);
    final m = _ctl[p.productId]!;
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: on,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _selected.add(p.productId);
                      } else {
                        _selected.remove(p.productId);
                      }
                    }),
          ),
          SizedBox(
            width: 220,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('\$${p.usd.toStringAsFixed(2)} للوحدة الأساسية',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              Text('الكلفة ${fmtMoney(p.oldCost)} ← ${fmtMoney(p.newCost)}',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: p.newCost >= p.oldCost ? const Color(0xFFB91C1C) : const Color(0xFF047857))),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: m.isEmpty
                ? const Text('لا أسعار بيع لهذه المادة', style: TextStyle(color: Color(0xFF64748B)))
                : Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final e in m.entries)
                      SizedBox(
                        width: 128,
                        child: TextField(
                          controller: e.value,
                          enabled: on && !_busy,
                          textDirection: TextDirection.ltr,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                          onChanged: (_) => _edited.add('${p.productId}:${e.key}'),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: _levelNames[e.key],
                            helperText: 'الآن ${fmtMoney(p.prices[e.key])}',
                            helperStyle: const TextStyle(fontSize: 10.5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
