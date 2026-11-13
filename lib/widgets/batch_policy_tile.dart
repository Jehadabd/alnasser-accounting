// lib/widgets/batch_policy_tile.dart
//
// 📦 الإعدادات ← «الصلاحية والدفعات»: أي دفعة تخرج أولاً عند البيع (BatchSalePolicy).
// يحدد صلاحية القطعة المبيعة وضمانها المطبوعين على الفاتورة، وأي دفعة تبقى في المخزن.

import 'package:flutter/material.dart';

import '../erp/inventory/product_batches.dart';

class BatchPolicyTile extends StatefulWidget {
  const BatchPolicyTile({super.key});

  @override
  State<BatchPolicyTile> createState() => _BatchPolicyTileState();
}

class _BatchPolicyTileState extends State<BatchPolicyTile> {
  BatchSalePolicy _p = BatchSalePolicy.current;

  @override
  void initState() {
    super.initState();
    BatchSalePolicy.load().then((p) {
      if (mounted) setState(() => _p = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(
        'المادة نفسها قد تكون في المخزن بأكثر من صلاحية (دفعة قديمة ودفعة جديدة من فواتير الشراء). '
        'اختر أيها يخرج أولاً عند البيع: صلاحيته وضمانه هما ما يُطبع على الفاتورة.',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
      const SizedBox(height: 4),
      RadioGroup<BatchSalePolicy>(
        groupValue: _p,
        onChanged: (v) {
          if (v == null) return;
          setState(() => _p = v);
          BatchSalePolicy.save(v);
        },
        child: Column(children: [
          for (final p in BatchSalePolicy.values)
            RadioListTile<BatchSalePolicy>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: p,
              title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(p.help, style: const TextStyle(fontSize: 12, height: 1.45)),
            ),
        ]),
      ),
      const Text(
        'إعداد لهذا الجهاز: اجعله نفسه على كل أجهزة المتجر.',
        style: TextStyle(fontSize: 11.5, color: Colors.black54),
      ),
    ]);
  }
}
