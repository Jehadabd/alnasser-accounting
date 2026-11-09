// lib/widgets/balance_mismatch_banner.dart
//
// 🛡️ تنبيه في شاشات الكشف: رصيد العميل المسجّل لا يساوي مجموع معاملاته (customer_balance_guard.dart)،
// وسؤال قبل المشاركة. لا يصحّح شيئاً — التصحيح قرار المستخدم.

import 'package:flutter/material.dart';

import '../services/customer_balance_guard.dart';

class BalanceMismatchBanner extends StatelessWidget {
  const BalanceMismatchBanner(this.check, {super.key});
  final BalanceCheck? check;

  @override
  Widget build(BuildContext context) {
    final c = check;
    if (c == null || c.ok) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.gpp_maybe_rounded, color: Color(0xFFB91C1C)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${c.message}.\nالكشف مبني من المعاملات، و«المطلوب» في الفواتير والمطالبات من الرصيد المسجّل — '
            'لن يُرسل عبر واتساب حتى يتطابقا. افحصه من «طبيب البيانات».',
            style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w700, height: 1.6),
          ),
        ),
      ]),
    );
  }

  /// قبل المشاركة اليدوية: true = يتابع (متطابق، أو اختار المستخدم المشاركة رغم الفرق).
  static Future<bool> confirmShare(BuildContext context, BalanceCheck? c) async {
    if (c == null || c.ok) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gpp_maybe_rounded, color: Color(0xFFB91C1C), size: 34),
        title: const Text('الكشف لا يطابق رصيد العميل'),
        content: Text('${c.message}.\n\nمشاركته الآن قد تعطي الزبون رقماً خاطئاً.', style: const TextStyle(height: 1.6)),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا تشارك')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('شارك رغم ذلك')),
        ],
      ),
    );
    return ok == true;
  }
}
