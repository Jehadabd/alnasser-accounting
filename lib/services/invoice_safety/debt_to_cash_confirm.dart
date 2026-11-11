// lib/services/invoice_safety/debt_to_cash_confirm.dart
//
// 🛑 تأكيد صريح قبل تحويل فاتورة لها دين في سجل الديون إلى «نقد»
// (منقول من التطبيق القديم debt_book، invoice_actions._confirmDebtToCashConversion —
//  أُضيف بعد حادثتين حقيقيتين: الفاتورتان 438 و1675).
//
// التحويل يطرح دين الفاتورة من حساب العميل. إن كان صاحب المحل قد سجّل وصل قبض
// يدوياً بثمن هذه الفاتورة من قبل، فالتحويل يطرح المبلغ مرة ثانية فيُظلم الحساب.
// لذلك: نُظهر المبلغ الذي سيُطرح، ونحذّر بالأحمر إن وُجد وصل قبض بالمبلغ نفسه بعد
// إنشاء الفاتورة. لا يغيّر شيئاً في البيانات: سؤال فقط، والقرار للمستخدم.

import 'package:flutter/material.dart';

import '../../models/invoice.dart';
import '../database/business/invoice_debt_reconciler.dart';
import '../database_service.dart';

class DebtToCashCheck {
  const DebtToCashCheck({required this.ledgerDebt, this.samePaymentDate});

  /// دين الفاتورة المسجّل في سجل الديون (ما سيُطرح عند التحويل)
  final double ledgerDebt;

  /// تاريخ وصل قبض بالمبلغ نفسه بعد إنشاء الفاتورة (null = لا يوجد)
  final String? samePaymentDate;
}

class DebtToCashConfirm {
  DebtToCashConfirm._();

  /// ما الذي سيحدث لو حُفظت [invoice] بنوع الدفع [newPaymentType]؟
  /// null = لا حاجة للسؤال (فاتورة جديدة، أو تبقى دَيناً، أو لا دين لها في السجل).
  static Future<DebtToCashCheck?> check(Invoice? invoice, String newPaymentType) async {
    if (invoice == null || invoice.id == null || newPaymentType != 'نقد') return null;
    if (invoice.status != 'محفوظة') return null; // المعلّقة لا دين لها في السجل
    final custId = invoice.customerId;
    if (custId == null) return null;
    final db = await DatabaseService().database;
    final debt = await InvoiceDebtReconciler.recordedContribution(db, invoice.id!, custId);
    if (debt <= 0.001) return null;
    final same = await db.rawQuery(
      "SELECT transaction_date FROM transactions "
      "WHERE customer_id = ? AND transaction_type = 'manual_payment' "
      'AND (is_deleted IS NULL OR is_deleted = 0) '
      'AND ABS(amount_changed + ?) < 0.01 AND transaction_date >= ? '
      'ORDER BY transaction_date DESC LIMIT 1',
      <Object?>[custId, debt, invoice.createdAt.toIso8601String()],
    );
    final date = same.isEmpty ? null : '${same.first['transaction_date'] ?? ''}'.split('T').first;
    return DebtToCashCheck(ledgerDebt: debt, samePaymentDate: date);
  }

  /// يسأل المستخدم عند الحاجة. true = تابِع الحفظ.
  static Future<bool> ask(BuildContext context, Invoice? invoice, String newPaymentType) async {
    final DebtToCashCheck? c;
    try {
      c = await check(invoice, newPaymentType);
    } catch (e) {
      debugPrint('⚠️ فحص التحويل إلى نقد: $e');
      return true; // تعذّر الفحص لا يمنع الحفظ: قاعدة الرصيد السالب والحارس يبقيان
    }
    if (c == null) return true;
    if (!context.mounted) return false;
    final amount = c.ledgerDebt.toStringAsFixed(c.ledgerDebt == c.ledgerDebt.roundToDouble() ? 0 : 2);
    final dup = c.samePaymentDate != null;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          dup ? '⚠️ احتمال تسديد مكرر' : 'تحويل الفاتورة إلى نقد',
          style: TextStyle(color: dup ? Colors.red : null),
        ),
        content: Text(
          'لهذه الفاتورة دين مسجّل في حساب العميل قدره $amount.\n'
          'تحويلها إلى نقد سيطرح $amount من حساب العميل.\n\n'
          '${dup ? 'يوجد وصل قبض بنفس المبلغ بعد تاريخ الفاتورة (${c.samePaymentDate}).\n'
              'إن كان ذلك الوصل هو ثمن هذه الفاتورة نفسها فلا تحوّلها إلى نقد، '
              'لأن المبلغ سيُطرح مرتين.\n\n' : ''}'
          'هل تريد المتابعة؟',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نعم، اطرح $amount', style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
