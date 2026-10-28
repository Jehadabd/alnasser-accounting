// lib/erp/control/landed_cost_dialog.dart
//
// 🚢 نافذة «مصاريف الشحن والجمارك» من «إدخال بضاعة» ← المزيد.
// تحسب الكلفة النهائية للوحدة وتعيد خطة تُطبَّق على حقل الكلفة؛ السجل والقيد
// يُكتبان فقط بعد نجاح حفظ المادة.

import 'package:flutter/material.dart';

import '../../accounting/screens/acc_ui.dart' show fmtMoney;
import '../erp_common.dart';
import '../pickers.dart' show CashBoxDropdown;
import 'landed_cost_service.dart';

class _Row {
  _Row(String name, [double amount = 0])
      : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount > 0 ? fmtMoney(amount) : '');
  final TextEditingController name;
  final TextEditingController amount;
  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

/// يعيد الخطة أو null إن أُلغي.
Future<LandedPlan?> showLandedCostDialog(
  BuildContext context, {
  required double purchaseUnitCost,
  required double baseQty,
  required String unitLabel,
  LandedPlan? initial,
}) {
  return showDialog<LandedPlan>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LandedDialog(
      purchaseUnitCost: purchaseUnitCost,
      baseQty: baseQty,
      unitLabel: unitLabel,
      initial: initial,
    ),
  );
}

class _LandedDialog extends StatefulWidget {
  const _LandedDialog({required this.purchaseUnitCost, required this.baseQty, required this.unitLabel, this.initial});
  final double purchaseUnitCost;
  final double baseQty;
  final String unitLabel;
  final LandedPlan? initial;
  @override
  State<_LandedDialog> createState() => _LandedDialogState();
}

class _LandedDialogState extends State<_LandedDialog> {
  final List<_Row> _rows = [];
  String _mode = LandedMode.box;
  int? _box;
  int? _expenseAccount;
  List<Map<String, Object?>> _expenseAccounts = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      for (final e in init.extras) {
        _rows.add(_Row(e.name, e.amount));
      }
      _mode = init.mode;
      _box = init.boxId;
      _expenseAccount = init.expenseAccountId;
    } else {
      _rows.addAll([_Row('شحن ونقل'), _Row('جمارك')]);
    }
    LandedCostService.expenseAccounts().then((a) {
      if (!mounted) return;
      setState(() {
        _expenseAccounts = a;
        _expenseAccount ??= _guessTransport(a);
      });
    });
  }

  static int? _guessTransport(List<Map<String, Object?>> a) {
    for (final r in a) {
      if ('${r['name']}'.contains('نقل') || '${r['name']}'.contains('شحن')) return r['id'] as int;
    }
    return a.isEmpty ? null : a.first['id'] as int;
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  LandedPlan get _plan => LandedPlan(
        purchaseUnitCost: widget.purchaseUnitCost,
        baseQty: widget.baseQty,
        extras: [
          for (final r in _rows)
            if ((parseMoney(r.amount.text) ?? 0) != 0)
              LandedExtra(r.name.text.trim().isEmpty ? 'مصروف' : r.name.text.trim(), parseMoney(r.amount.text) ?? 0),
        ],
        mode: _mode,
        boxId: _box,
        expenseAccountId: _expenseAccount,
      );

  void _apply() {
    final p = _plan;
    try {
      LandedCostService.validate(p);
      Navigator.pop(context, p);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _plan;
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.local_shipping_rounded, color: Color(0xFF0891B2)),
        SizedBox(width: 8),
        Expanded(child: Text('مصاريف الشحن والجمارك', style: TextStyle(fontSize: 17))),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                'تُوزَّع على ${fmtQty(widget.baseQty)} ${widget.unitLabel} (الرصيد الافتتاحي) وتُضاف إلى كلفة الوحدة.',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 8),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: TextBox(controller: _rows[i].name, label: 'البند')),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 170,
                      child: MoneyField(controller: _rows[i].amount, label: 'المبلغ', onChanged: (_) => setState(() {}))),
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    onPressed: () => setState(() => _rows.removeAt(i).dispose()),
                  ),
                ]),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _rows.add(_Row(''))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة بند'),
              ),
            ),
            const Divider(),
            Text(
              'المجموع ${fmtMoney(p.totalExtra)} ÷ ${fmtQty(widget.baseQty)} = +${fmtMoney(p.perUnit)} للوحدة\n'
              'كلفة الوحدة: ${fmtMoney(widget.purchaseUnitCost)} ← ${fmtMoney(p.finalUnitCost)}',
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.6),
            ),
            const Divider(),
            const Text('كيف دُفعت؟', style: TextStyle(fontWeight: FontWeight.w700)),
            RadioGroup<String>(
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v ?? _mode),
              child: Column(children: [
                for (final m in [LandedMode.box, LandedMode.reclass, LandedMode.none])
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: m,
                    title: Text(LandedMode.label(m)),
                    subtitle: Text(switch (m) {
                      LandedMode.box => 'قيد: مدين المخزون / دائن الصندوق',
                      LandedMode.reclass => 'قيد: مدين المخزون / دائن حساب المصروف — حتى لا تُحسب مرتين من الربح',
                      _ => 'ترتفع الكلفة فقط. انتبه: إن سجّلت الدفع بسند مصروف فستُحسب مرتين',
                    }),
                  ),
              ]),
            ),
            if (_mode == LandedMode.box)
              CashBoxDropdown(value: _box, width: 340, onChanged: (b) => setState(() => _box = b?.id)),
            if (_mode == LandedMode.reclass)
              DropdownButtonFormField<int>(
                key: ValueKey('acc${_expenseAccounts.length}'),
                initialValue: _expenseAccounts.any((a) => a['id'] == _expenseAccount) ? _expenseAccount : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'حساب المصروف الذي سُجّلت عليه'),
                items: [
                  for (final a in _expenseAccounts)
                    DropdownMenuItem(value: a['id'] as int, child: Text('${a['code']} - ${a['name']}')),
                ],
                onChanged: (v) => setState(() => _expenseAccount = v),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton.icon(onPressed: _apply, icon: const Icon(Icons.check_rounded), label: const Text('تطبيق على الكلفة')),
      ],
    );
  }
}
