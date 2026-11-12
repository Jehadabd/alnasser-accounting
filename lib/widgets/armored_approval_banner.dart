// lib/widgets/armored_approval_banner.dart
//
// 🔐 كشف «بياناتي صحيحة» من جهاز آخر سيغيّر معاملات عميل على هذا الجهاز: لا يُطبَّق إلا
// بموافقة صاحب هذا الجهاز. هذا الشريط يعرضه في الشاشة الرئيسية بما سيحدث بالضبط (ما
// سيُضاف وما سيُبطل، والرصيد قبل وبعد) مع «موافق» و«رفض». لا يظهر شيء إن لم يكن طلب.

import 'package:flutter/material.dart';

import '../services/firebase_sync/armored_reconciliation_service.dart';
import '../services/save_lock.dart';

class ArmoredApprovalBanner extends StatefulWidget {
  const ArmoredApprovalBanner({super.key});

  @override
  State<ArmoredApprovalBanner> createState() => _ArmoredApprovalBannerState();
}

class _ArmoredApprovalBannerState extends State<ArmoredApprovalBanner> {
  @override
  void initState() {
    super.initState();
    ArmoredReconciliationService().loadPending();
  }

  @override
  Widget build(BuildContext context) {
    final service = ArmoredReconciliationService();
    return ValueListenableBuilder<List<ArmoredApproval>>(
      valueListenable: service.pendingApprovals,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final a in list) _ApprovalTile(approval: a)],
          ),
        );
      },
    );
  }
}

class _ApprovalTile extends StatelessWidget {
  const _ApprovalTile({required this.approval});

  final ArmoredApproval approval;

  @override
  Widget build(BuildContext context) {
    final p = approval.preview;
    final color = Colors.deepPurple.shade700;
    final expired = approval.isExpired;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.verified_user_outlined, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'جهاز آخر يطلب اعتماد كشفه للعميل «${approval.customerName}»',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (p.newCustomer) const Text('• العميل غير موجود على هذا الجهاز وسيُنشأ'),
            if (p.addCount > 0) Text('• يُضاف ${p.addCount} معاملة مجموعها ${ArmoredPreview.fmt(p.addSum)}'),
            if (p.voidCount > 0)
              Text('• يُبطل ${p.voidCount} معاملة مجموعها ${ArmoredPreview.fmt(p.voidSum)} '
                  '(لا أثر لها في السحابة ولا عند غيرك)'),
            Text('• رصيد العميل هنا: ${ArmoredPreview.fmt(p.balanceNow)} ← ${ArmoredPreview.fmt(p.balanceAfter)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (expired)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('انتهت صلاحية هذا الطلب (أقدم من ساعتين) — اطلب إعادة المطابقة',
                    style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _decide(context, approve: false),
                  child: Text(expired ? 'إزالة' : 'رفض'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: expired ? null : () => _confirmApprove(context),
                  child: const Text('موافق — طبّق الكشف'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmApprove(BuildContext context) async {
    final p = approval.preview;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تطبيق كشف الجهاز الآخر'),
        content: Text('سيتغيّر رصيد «${approval.customerName}» على هذا الجهاز من '
            '${ArmoredPreview.fmt(p.balanceNow)} إلى ${ArmoredPreview.fmt(p.balanceAfter)}.\n'
            'هل أنت متأكد أن بيانات الجهاز الآخر هي الصحيحة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، طبّق')),
        ],
      ),
    );
    if (ok == true && context.mounted) await _decide(context, approve: true);
  }

  Future<void> _decide(BuildContext context, {required bool approve}) async {
    final service = ArmoredReconciliationService();
    final msg = await SaveLock.run(
      () => approve ? service.approve(approval) : service.reject(approval),
      message: approve ? 'جارٍ تطبيق الكشف…' : 'جارٍ الرفض…',
    );
    if (msg == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
