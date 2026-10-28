// lib/invoice_designer/voucher_designer_screen.dart
//
// 🧾 مصمم السندات — مستقل عن مصمم الفاتورة.
// تختار نوع السند، فترى تصميمه الحالي وإعداد طباعته، وتفتح قوالبه الجاهزة
// (خاصة بكل نوع) أو تصمّمه من الصفر. لا يغيّر أي رقم — شكل الطباعة فقط.

import 'package:flutter/material.dart';

import '../services/voucher_print.dart';
import 'invoice_designer_screen.dart';
import 'invoice_layout.dart';
import 'invoice_layout_store.dart';

class VoucherDesignerScreen extends StatefulWidget {
  const VoucherDesignerScreen({super.key});
  @override
  State<VoucherDesignerScreen> createState() => _VoucherDesignerScreenState();
}

class _VoucherDesignerScreenState extends State<VoucherDesignerScreen> {
  static const _navy = Color(0xFF0F3460);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFE6EBF2);

  bool _loading = true;
  final Map<String, String> _mode = {};
  final Map<String, String> _designName = {};
  final Map<String, int> _designsCount = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final layouts = await InvoiceLayoutStore.loadAll();
    for (final k in VoucherKinds.all) {
      _mode[k] = await VoucherPrint.modeFor(k);
      final id = await InvoiceLayoutStore.target(VoucherKinds.targetKey(k));
      InvoiceLayout? chosen;
      for (final l in layouts) {
        if (l.id == id && l.kind == k) chosen = l;
      }
      _designName[k] = chosen?.name ?? '';
      _designsCount[k] = layouts.where((l) => l.kind == k).length;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open(String kind) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDesignerScreen(docKind: kind)));
    _load();
  }

  Future<void> _setMode(String kind, String mode) async {
    setState(() => _mode[kind] = mode);
    try {
      await VoucherPrint.setMode(kind, mode);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر الحفظ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.request_page_rounded),
          SizedBox(width: 10),
          Text('مصمم السندات', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _navy.withValues(alpha: 0.12)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded, color: _navy),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'اختر نوع السند ثم «تصميم وقوالب». لكل نوع قوالبه الجاهزة، وما لم تختر له تصميماً يُطبع بشكل البرنامج الحالي. '
                        'الحقول (المحاسب، وقت الطباعة، الأرصدة، المبلغ كتابةً…) تُملأ تلقائياً عند الطباعة.',
                        style: TextStyle(height: 1.6, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                for (final k in VoucherKinds.all) _card(k),
              ],
            ),
    );
  }

  Widget _card(String kind) {
    final c = VoucherKinds.color(kind);
    final name = _designName[kind] ?? '';
    final count = _designsCount[kind] ?? 0;
    final mode = _mode[kind] ?? 'ask';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(VoucherKinds.icon(kind), color: c, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(VoucherKinds.label(kind), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(VoucherKinds.hint(kind), style: const TextStyle(color: _muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c),
              onPressed: () => _open(kind),
              icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
              label: const Text('تصميم وقوالب'),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: name.isEmpty ? const Color(0xFFF1F5F9) : c.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(name.isEmpty ? Icons.description_outlined : Icons.check_circle_rounded,
                    size: 16, color: name.isEmpty ? _muted : c),
                const SizedBox(width: 6),
                Text(name.isEmpty ? 'يُطبع بشكل البرنامج الحالي' : 'يُطبع بتصميم: $name',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: name.isEmpty ? _muted : c)),
              ]),
            ),
            if (count > 0)
              Text('$count تصميم محفوظ', style: const TextStyle(fontSize: 12, color: _muted)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ask', label: Text('اسألني'), icon: Icon(Icons.help_outline, size: 16)),
                ButtonSegment(value: 'always', label: Text('اطبع دائماً'), icon: Icon(Icons.print_rounded, size: 16)),
                ButtonSegment(value: 'never', label: Text('لا تُظهر'), icon: Icon(Icons.block, size: 16)),
              ],
              selected: {mode},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (s) => _setMode(kind, s.first),
            ),
          ]),
        ]),
      ),
    );
  }
}
