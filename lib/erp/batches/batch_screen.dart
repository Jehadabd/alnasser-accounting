// lib/erp/batches/batch_screen.dart
//
// 🧪 «الدفعات والصلاحية»: تسجيل دفعة (مادة، رقم الدفعة، تاريخ الانتهاء، الكمية) والتنبيه بما
// يقترب انتهاؤه. المتبقي تقدير بقاعدة «الأقرب انتهاءً يخرج أولاً» من الكمية الحالية.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../widgets/settings_kit.dart';
import '../erp_common.dart';
import '../pickers.dart';
import 'batch_models.dart';
import 'batch_store.dart';

final _q = NumberFormat('#,##0.##', 'en');
final _d = DateFormat('yyyy/MM/dd', 'en');

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});
  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final _store = BatchStore();
  List<ProductLots>? _all;
  int _within = 60; // يوماً
  bool _onlySoon = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await _store.all();
    if (mounted) setState(() => _all = a);
  }

  Future<void> _add() async {
    final p = await Pickers.product(context, title: 'مادة الدفعة');
    if (p == null || !mounted) return;
    final lotNo = TextEditingController();
    final qty = TextEditingController();
    DateTime? expiry;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('دفعة: ${p.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: lotNo, decoration: const InputDecoration(labelText: 'رقم الدفعة (اختياري)')),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'الكمية المستلمة (بالوحدة الأساسية)'), keyboardType: TextInputType.number),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(expiry == null ? 'تاريخ الانتهاء' : _d.format(expiry!)),
              onTap: () async {
                final d = await showDatePicker(
                    context: ctx, initialDate: DateTime.now().add(const Duration(days: 180)), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) set(() => expiry = d);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final q = parseMoney(qty.text) ?? 0;
    final no = lotNo.text;
    lotNo.dispose();
    qty.dispose();
    if (ok != true) return;
    if (expiry == null || q <= 0) {
      if (mounted) setToast(context, 'أدخل الكمية وتاريخ الانتهاء', error: true);
      return;
    }
    try {
      await _store.add(StockLot(productId: p.id, lotNo: no, expiry: expiry!, qty: q, receivedAt: DateTime.now()));
      await _load();
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final all = _all;
    final rows = <({ProductLots p, LotRemaining l})>[
      for (final p in all ?? const <ProductLots>[])
        for (final l in p.lots)
          if (!_onlySoon || (l.remaining > 0 && l.daysLeft(now) <= _within)) (p: p, l: l),
    ];
    return SettingsScaffold(
      title: 'الدفعات والصلاحية',
      icon: Icons.event_busy_rounded,
      subtitle: 'ما يقترب انتهاؤه وكم بقي منه (تقديراً)',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('دفعة')),
      children: [
        const SetBanner(
          'سجل صلاحيات فقط: لا يغيّر كمية أي مادة. المتبقي من كل دفعة يُقدَّر من الكمية الحالية بقاعدة '
          '«الأقرب انتهاءً يُباع أولاً» — إن لم تبع بهذا الترتيب فالتقدير تقريبي.',
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilterChip(label: const Text('ما يقترب فقط'), selected: _onlySoon, onSelected: (v) => setState(() => _onlySoon = v)),
          if (_onlySoon)
            for (final d in const [30, 60, 90, 180])
              ChoiceChip(label: Text('$d يوماً'), selected: _within == d, onSelected: (_) => setState(() => _within = d)),
        ]),
        const SizedBox(height: 8),
        if (all == null)
          const LinearProgressIndicator()
        else if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا شيء يقترب انتهاؤه')))
        else
          for (final r in rows)
            Builder(builder: (_) {
              final days = r.l.daysLeft(now);
              final c = days < 0 ? kSetRed : (days <= 30 ? kSetOrange : kSetGreen);
              return Card(
                elevation: 0,
                child: ListTile(
                  leading: Icon(days < 0 ? Icons.dangerous_rounded : Icons.event_rounded, color: c),
                  title: Text('${r.p.name}${r.l.lot.lotNo.isEmpty ? '' : ' — دفعة ${r.l.lot.lotNo}'}'),
                  subtitle: Text('تنتهي ${_d.format(r.l.lot.expiry)} (${days < 0 ? 'منتهية منذ ${-days} يوماً' : 'بعد $days يوماً'}) • '
                      'المتبقي تقديراً ${_q.format(r.l.remaining)} من ${_q.format(r.l.lot.qty)}'),
                  trailing: IconButton(
                    tooltip: 'حذف الدفعة من السجل',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final ok = await confirmDialog(context, 'حذف الدفعة', 'تُحذف من سجل الصلاحيات فقط — الكمية لا تتغير.', ok: 'حذف');
                      if (ok && r.l.lot.id != null) {
                        await _store.remove(r.l.lot.id!);
                        await _load();
                      }
                    },
                  ),
                ),
              );
            }),
        const SizedBox(height: 80),
      ],
    );
  }
}
