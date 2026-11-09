// lib/erp/variants/variant_screen.dart
//
// 👕 «المتغيّرات»: اختر مادة أساساً، واكتب المقاسات والألوان (أو أي خاصيتين)، فتُنشأ مادة لكل
// تركيبة بأسعار الأساس وكميتها صفر — ثم تُدخل كمياتها بالشراء أو الجرد كأي مادة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../widgets/settings_kit.dart';
import '../pickers.dart';
import '../stock_helpers.dart' show ProductLite;
import 'variant_models.dart';
import 'variant_store.dart';

final _q = NumberFormat('#,##0.##', 'en');

class VariantScreen extends StatefulWidget {
  const VariantScreen({super.key});
  @override
  State<VariantScreen> createState() => _VariantScreenState();
}

class _VariantScreenState extends State<VariantScreen> {
  final _store = VariantStore();
  final _axis1 = TextEditingController(text: 'المقاس');
  final _axis2 = TextEditingController(text: 'اللون');
  final _values1 = TextEditingController();
  final _values2 = TextEditingController();
  ProductLite? _base;
  List<VariantFamily>? _families;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_axis1, _axis2, _values1, _values2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final f = await _store.families();
    if (mounted) setState(() => _families = f);
  }

  List<VariantCombo> _combos() => Variants.combos([
        VariantAxis(_axis1.text.trim().isEmpty ? 'الخاصية 1' : _axis1.text.trim(), VariantAxis.split(_values1.text)),
        VariantAxis(_axis2.text.trim().isEmpty ? 'الخاصية 2' : _axis2.text.trim(), VariantAxis.split(_values2.text)),
      ]);

  Future<void> _create() async {
    final base = _base;
    if (base == null) return;
    List<VariantCombo> combos;
    try {
      combos = _combos();
    } on StateError catch (e) {
      setToast(context, e.message, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _store.create(base.id, combos);
      if (!mounted) return;
      setToast(context, 'أُنشئ ${r.created} متغيّراً${r.skipped.isEmpty ? '' : ' — ${r.skipped.length} موجود من قبل'}');
      _values1.clear();
      _values2.clear();
      await _load();
    } catch (e) {
      if (mounted) setToast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<VariantCombo> preview = const [];
    String? previewErr;
    try {
      preview = _combos();
    } on StateError catch (e) {
      previewErr = e.message;
    }
    return SettingsScaffold(
      title: 'متغيّرات المواد',
      icon: Icons.style_rounded,
      subtitle: 'مقاس × لون: مادة مستقلة لكل تركيبة بكمية وباركود خاصين',
      children: [
        SetCard(
          title: 'إنشاء متغيّرات',
          icon: Icons.add_box_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_rounded),
              title: Text(_base?.name ?? 'اختر المادة الأساس'),
              subtitle: const Text('تُنسخ أسعارها وكلفتها ووحداتها إلى كل متغيّر'),
              trailing: TextButton(
                onPressed: () async {
                  final p = await Pickers.product(context, title: 'المادة الأساس');
                  if (p != null) setState(() => _base = p);
                },
                child: const Text('اختيار'),
              ),
            ),
            Row(children: [
              SizedBox(width: 120, child: TextField(controller: _axis1, decoration: const InputDecoration(labelText: 'الخاصية'))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: _values1,
                    decoration: const InputDecoration(labelText: 'القيم (بفاصلة): S، M، L'),
                    onChanged: (_) => setState(() {})),
              ),
            ]),
            Row(children: [
              SizedBox(width: 120, child: TextField(controller: _axis2, decoration: const InputDecoration(labelText: 'الخاصية'))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: _values2,
                    decoration: const InputDecoration(labelText: 'القيم (اختياري): أحمر، أزرق'),
                    onChanged: (_) => setState(() {})),
              ),
            ]),
            const SizedBox(height: 8),
            if (previewErr != null)
              Text(previewErr, style: const TextStyle(color: kSetRed))
            else if (_base != null && preview.isNotEmpty)
              Text('${preview.length} متغيّراً: ${preview.take(6).map((c) => Variants.name(_base!.name, c)).join('، ')}${preview.length > 6 ? '…' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: kSetMuted)),
            const SizedBox(height: 8),
            SetPrimaryButton(
              label: 'إنشاء',
              icon: Icons.auto_awesome_rounded,
              busy: _busy,
              onPressed: _base == null || preview.isEmpty || previewErr != null ? null : _create,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_families == null)
          const LinearProgressIndicator()
        else
          for (final f in _families!)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetCard(
                title: f.name,
                subtitle: '${f.members.length} متغيّر • الكمية الكلية ${_q.format(f.stock)}',
                icon: Icons.style_rounded,
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final m in f.members)
                    Chip(label: Text('${m.attrs.values.join(' / ')}: ${_q.format(m.stock)}')),
                ]),
              ),
            ),
        const SizedBox(height: 40),
      ],
    );
  }
}
