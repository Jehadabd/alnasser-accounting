// test/services/customer_claim_key_test.dart
//
// 🔒 حجز اسم العميل بين الأجهزة: مفتاح الحجز = هوية الحساب (الاسم بلا مسافات).
// كان المفتاح يدمج المسافات فقط، فـ«جهاد عبد الناصر» و«جهاد عبدالناصر» — حساب واحد —
// يُحجزان بمفتاحين، ويكتب جهازان فاتورتين للحساب نفسه في اللحظة نفسها.

import 'package:alnaser/services/database/business/customer_name_rule.dart';
import 'package:alnaser/services/database/business/invoice_customer_claim.dart';
import 'package:flutter_test/flutter_test.dart';

int k(String s) => InvoiceCustomerClaim.keyOf(InvoiceCustomerClaim.normalize(s));

void main() {
  test('كل كتابات الحساب الواحد ⇒ حجز واحد', () {
    final a = k('جهاد عبد الناصر');
    expect(k('جهاد عبدالناصر'), a);
    expect(k('جهاد          عبد الناصر'), a);
    expect(k('  جهاد\tعبد الناصر‏ '), a);
  });

  test('مفتاح الحجز يطابق هوية الحساب في سجل الديون', () {
    for (final n in ['جهاد عبد الناصر', 'جهادعبدالناصر', 'Ali  Hasan']) {
      expect(InvoiceCustomerClaim.normalize(n), CustomerNameRule.key(n).toLowerCase());
    }
  });

  test('حسابان مختلفان ⇒ حجزان مختلفان', () {
    expect(k('جهاد عبد الناصر') == k('جهاد عبد الله'), isFalse);
  });

  test('الأحرف الكبيرة والصغيرة لا تفرّق', () {
    expect(k('Ali Hasan'), k('ali hasan'));
  });
}
