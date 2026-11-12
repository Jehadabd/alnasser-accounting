// lib/erp/inventory/move_mismatch_note.dart
//
// ⚠️ تنبيه بطاقة حركة المادة: آخر رصيد في الحركات لا يطابق كمية المادة المسجّلة.
// يُعرض فوق الحركات بلا اختراع حركة تسدّ الفرق (ProductCard.mismatchText).

import 'package:flutter/material.dart';

class MoveMismatchNote extends StatelessWidget {
  const MoveMismatchNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.5, fontSize: 13))),
      ]),
    );
  }
}
