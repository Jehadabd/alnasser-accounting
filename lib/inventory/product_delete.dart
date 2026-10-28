// lib/inventory/product_delete.dart
//
// 🗑️ حذف مادة بعد تأكيد يوضّح أين تُستعمل (فواتير، كمية في المخزن) ويذكّر
// بالبديل الآمن: «إيقاف» المادة من بطاقتها بدل حذفها.

import 'package:flutter/material.dart';

import '../accounting/screens/acc_ui.dart';
import '../erp/erp_common.dart';
import '../erp/erp_ui.dart';
import '../services/database_service.dart';

/// يعيد true إن حُذفت المادة.
Future<bool> confirmAndDeleteProduct(
  BuildContext context, {
  required int id,
  required String name,
  double stock = 0,
  String unit = '',
}) async {
  int usedLines = 0;
  try {
    final db = await erpDb();
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM invoice_items WHERE product_id = ?', [id]);
    usedLines = (r.first['n'] as num?)?.toInt() ?? 0;
  } catch (_) {}
  if (!context.mounted) return false;

  Widget note(String text, IconData icon, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.5))),
          ],
        ),
      );

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => ErpDialog(
      title: 'حذف «$name»؟',
      subtitle: 'لا يمكن التراجع عن الحذف',
      icon: Icons.delete_forever_rounded,
      color: ErpColors.red,
      width: 460,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (usedLines > 0)
            note('مستعملة في ${fmtQty(usedLines)} سطر فاتورة — تبقى الفواتير كما هي، لكن المادة تختفي من القوائم.',
                Icons.receipt_long_rounded, ErpColors.orange),
          if (stock != 0)
            note('في المخزن ${fmtQty(stock)} $unit — تُحذف معها.', Icons.inventory_2_outlined, ErpColors.orange),
          note('لإخفائها دون حذف: افتح المادة ← «المزيد» ← الحالة ← إيقاف.', Icons.lightbulb_outline_rounded, ErpColors.blue),
        ],
      ),
      actions: erpDialogActions(ctx, ok: 'حذف نهائياً', color: ErpColors.red, icon: Icons.delete_outline_rounded),
    ),
  );
  if (ok != true) return false;
  try {
    await DatabaseService().deleteProduct(id);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, 'تعذّر الحذف: $e');
    return false;
  }
}
