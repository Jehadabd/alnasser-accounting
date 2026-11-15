// lib/widgets/summary_placement_tile.dart
//
// 📌 الإعدادات ← الفاتورة والطباعة: مكان ملخص الفاتورة (SummaryPlacementPref).
// يُحفظ فوراً، ويسري على كل فاتورة تُطبع بعده (الجديدة والمحفوظة سابقاً).

import 'package:flutter/material.dart';

import '../invoice_designer/summary_placement.dart';

class SummaryPlacementTile extends StatefulWidget {
  const SummaryPlacementTile({super.key});

  @override
  State<SummaryPlacementTile> createState() => _SummaryPlacementTileState();
}

class _SummaryPlacementTileState extends State<SummaryPlacementTile> {
  SummaryPlacement _p = SummaryPlacement.design;

  @override
  void initState() {
    super.initState();
    SummaryPlacementPref.get().then((p) {
      if (mounted) setState(() => _p = p);
    });
  }

  Future<void> _set(SummaryPlacement p) async {
    await SummaryPlacementPref.set(p);
    if (mounted) setState(() => _p = p);
  }

  @override
  Widget build(BuildContext context) {
    final hint = switch (_p) {
      SummaryPlacement.design =>
        'كل تصميم بمكانه الذي اخترته في «مصمم الفاتورة». التصميم الأصلي: تحت آخر بند.',
      SummaryPlacement.flow => 'المجاميع ودين العميل تلي آخر بند مباشرة في كل الفواتير والتصاميم.',
      SummaryPlacement.bottom => 'المجاميع ودين العميل في أسفل الورقة دائماً، مهما قلّت البنود.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
        'مربع المجاميع (الإجمالي، المدفوع، المتبقي، المطلوب الحالي) — يسري على كل فاتورة تُطبع، '
        'الجديدة والمحفوظة سابقاً.',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
      const SizedBox(height: 10),
      SegmentedButton<SummaryPlacement>(
        segments: const [
          ButtonSegment(value: SummaryPlacement.design, icon: Icon(Icons.design_services_rounded), label: Text('كما في التصميم')),
          ButtonSegment(value: SummaryPlacement.flow, icon: Icon(Icons.vertical_align_top_rounded), label: Text('تحت آخر بند')),
          ButtonSegment(value: SummaryPlacement.bottom, icon: Icon(Icons.vertical_align_bottom_rounded), label: Text('أسفل الورقة')),
        ],
        selected: {_p},
        onSelectionChanged: (s) => _set(s.first),
      ),
      const SizedBox(height: 8),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(hint, key: ValueKey(_p), style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.5)),
      ),
    ]);
  }
}
