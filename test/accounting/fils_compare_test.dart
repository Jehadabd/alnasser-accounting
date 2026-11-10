// 🪙 مقارنة الديون بالفلس في موفِّق الفواتير: فرق فلس واحد ليس «متساوياً».
// (الحد القديم ≤ 0.01 ترك فلساً على عميل قديم بعد نقل فاتورته — اختبار التعذيب الكامل.)

import 'package:alnaser/services/database/business/invoice_debt_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('فرق فلس واحد يُعدّ فرقاً، ونصف فلس من ضجيج الحساب لا يُعدّ', () {
    expect(InvoiceDebtReconciler.sameFils(0.009999999999990905, 0), isFalse);
    expect(InvoiceDebtReconciler.sameFils(1250.26, 1250.25), isFalse);
    expect(InvoiceDebtReconciler.sameFils(25250.26 - 25250.25, 0.01), isTrue);
    expect(InvoiceDebtReconciler.sameFils(1003704773.4399991, 1003704773.44), isTrue);
  });

  test('صفر بالفلس، والتقريب إلى فلس', () {
    expect(InvoiceDebtReconciler.isZeroFils(0.004), isTrue);
    expect(InvoiceDebtReconciler.isZeroFils(0.009999999999990905), isFalse);
    expect(InvoiceDebtReconciler.toFils(0.009999999999990905), 0.01);
    expect(InvoiceDebtReconciler.toFils(14700.049999999988), 14700.05);
  });
}
