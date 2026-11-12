// lib/widgets/incomplete_receipts_banner.dart
//
// 🧾 وصل قبض انقطع تسجيله في منتصفه (انطفاء الكهرباء أو إغلاق البرنامج بين عميل وآخر):
// بعض أسطره سُجّلت وبعضها لا. لا يُكمَل ولا يُلغى وحده — هذا الشريط يعرضه في الشاشة
// الرئيسية بما سُجّل وما بقي، والقرار لصاحب المحل:
//   • «أكمل الوصل»: تُسجَّل الأسطر الناقصة فقط (لا تكرار لما سُجّل).
//   • «أبقِ ما سُجّل»: لا يُضاف شيء، ويُصحَّح الوصل ليصف ما سُجّل فعلاً.

import 'package:flutter/material.dart';

import '../erp/debts/receipts_service.dart';
import '../services/save_lock.dart';

class IncompleteReceiptsBanner extends StatefulWidget {
  const IncompleteReceiptsBanner({super.key});

  @override
  State<IncompleteReceiptsBanner> createState() => _IncompleteReceiptsBannerState();
}

class _IncompleteReceiptsBannerState extends State<IncompleteReceiptsBanner> {
  List<IncompleteReceipt> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ReceiptsService().incompleteReceipts();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      debugPrint('⚠️ تعذّر فحص الوصولات المنقطعة: $e');
    }
  }

  String _fmt(double v) =>
      v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final color = Colors.red.shade700;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in _items)
            Card(
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
                      Icon(Icons.receipt_long, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('وصل القبض رقم ${r.receiptNo} لم يكتمل تسجيله (انقطع في منتصفه)',
                            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('• سُجّل ${r.postedLines} من ${r.plannedLines} عميل — مجموع ما سُجّل ${_fmt(r.postedAmount)}'),
                    Text('• لم يُسجَّل بعد: ${_fmt(r.missingAmount)}'),
                    Text('• العملاء: ${r.customers.join('، ')}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _keep(r),
                          child: const Text('أبقِ ما سُجّل فقط'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _complete(r),
                          child: const Text('أكمل الوصل'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم')),
          ],
        ),
      ) ==
      true;

  Future<void> _complete(IncompleteReceipt r) async {
    if (!await _confirm('إكمال الوصل ${r.receiptNo}',
        'تُسجَّل الأسطر الناقصة فقط بمجموع ${_fmt(r.missingAmount)}. ما سُجّل لا يتكرر.')) {
      return;
    }
    if (!mounted) return;
    final res = await SaveLock.run(() => ReceiptsService().completeIncomplete(context, r.receiptId));
    if (!mounted || res == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.errors.isEmpty
          ? '✅ اكتمل وصل القبض رقم ${r.receiptNo}'
          : '⚠️ أُكمل جزئياً: ${res.errors.join(' — ')}'),
    ));
    await _load();
  }

  Future<void> _keep(IncompleteReceipt r) async {
    if (!await _confirm('إبقاء ما سُجّل من الوصل ${r.receiptNo}',
        'لن يُسجَّل الباقي (${_fmt(r.missingAmount)}). يُصحَّح الوصل ليطابق ما سُجّل فعلاً.')) {
      return;
    }
    final ok = await SaveLock.run(() async {
      await ReceiptsService().keepPostedOnly(r.receiptId);
      return true;
    });
    if (!mounted || ok == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('الوصل ${r.receiptNo} صار يصف ما سُجّل فقط')));
    await _load();
  }
}
