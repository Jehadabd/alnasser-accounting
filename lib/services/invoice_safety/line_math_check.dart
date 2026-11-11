// lib/services/invoice_safety/line_math_check.dart
//
// 🚨 فحص حسابي مستقل لكل سطر قبل الحفظ: مبلغ السطر = الكمية × السعر.
// (منقول من التطبيق القديم debt_book، invoice_actions «_strictMathFailed»).
// يحمي من خلل في الشاشة يجعل مبلغ سطر لا يطابق كميته وسعره (تعديل سعر لم يُحدّث
// المبلغ، دمج سطرين…): الفاتورة تُحفظ بإجمالي صحيح الجمع لكنه خطأ في الأصل.
// لا يغيّر شيئاً: يمنع الحفظ ويطلب حذف السطر وإضافته من جديد.
//
// السماحية للتقريب وحده: السعر يُخزَّن بالفلس (appliedPriceCents) والمبلغ يُحسب من السعر
// قبل تقريبه (1750.5 × 0.99 = 1732.995)، فيفرق نصف فلس لكل قطعة؛ والسطر المدموج من
// إدخالين يجمع مبلغين مقرَّبين. لذلك: نصف فلس × الكمية + فلس، أو 0.01% من المبلغ، أو
// خمسة فلوس — أيها أكبر. الخلل الحقيقي يفرق بسعر وحدة على الأقل.

import '../../models/invoice_item.dart';

class LineMathCheck {
  LineMathCheck._();

  /// أول سطر لا يطابق مبلغه (الكمية × السعر) — null = كل الأسطر سليمة.
  static String? firstMismatch(Iterable<InvoiceItem> items) {
    for (final it in items) {
      if (it.productName.trim().isEmpty || it.isGift) continue;
      final qty = it.soldQuantity;
      if (qty <= 0) continue; // سطر ناقص: يرفضه فحص الأصناف المكتملة برسالته
      final expected = qty * it.appliedPrice;
      final tolerance = _max(_max(0.05, qty * 0.005 + 0.01), expected.abs() * 0.0001);
      if ((it.itemTotal - expected).abs() > tolerance) {
        return 'يوجد خلل حسابي في الصنف «${it.productName}»:\n'
            'المبلغ المسجّل ${_fmt(it.itemTotal)}، والحساب الفعلي '
            '(${_fmt(qty)} × ${_fmt(it.appliedPrice)}) = ${_fmt(expected)}.\n\n'
            'احذف هذا الصنف وأضفه من جديد، ثم احفظ.';
      }
    }
    return null;
  }

  static double _max(double a, double b) => a > b ? a : b;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}
