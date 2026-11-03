// test/services/owner_summary_test.dart
//
// تنسيق ملخص المالك: الأرقام، تهريب HTML، الأقسام المتعذّرة، وحد طول تيليجرام.

import 'package:alnaser/services/owner_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('الأرقام والأقسام', () {
    final d = OwnerSummaryData(DateTime(2026, 11, 3))
      ..shopName = 'محل <النور> & أولاده'
      ..invoiceCount = 12
      ..sales = 1250000
      ..cashSales = 1000000
      ..creditSales = 250000
      ..profit = 180000.5
      ..netCollected = 1100000
      ..debtPayments = 100000
      ..debtIncrease = 250000
      ..debtDecrease = -100000
      ..drawerNet = 1050000
      ..boxes = {'صندوق الكاشير': 900000}
      ..sensitiveCount = 1
      ..sensitive = const [OwnerSensitiveOp('أحمد', 'حذف', 'السندات — حذف سند #5')]
      ..outOfStock = 2
      ..outOfStockNames = const ['سلك 2.5', 'قاطع 32']
      ..claimsTomorrow = 3
      ..claimsTomorrowTotal = 450000;
    final s = OwnerSummary.format(d);
    expect(s, contains('ملخص يوم 2026/11/03 — محل &lt;النور&gt; &amp; أولاده'));
    expect(s, contains('1,250,000 (12 فاتورة)'));
    expect(s, contains('نقداً 1,000,000 • آجلاً 250,000'));
    expect(s, contains('الربح التقديري: 180,000.5'));
    expect(s, contains('زادت 250,000 • نقصت 100,000'));
    expect(s, contains('صندوق الكاشير: 900,000'));
    expect(s, contains('أحمد — حذف: السندات — حذف سند #5'));
    expect(s, contains('مطالبات الغد: 3 عميل — 450,000'));
    expect(s, isNot(contains('<النور>')));
  });

  test('قسم تعذّر حسابه لا يُخفى ولا يصير صفراً', () {
    final s = OwnerSummary.format(OwnerSummaryData(DateTime(2026, 1, 1)));
    expect(s, contains('المبيعات:</b> تعذّر حسابه'));
    expect(s, contains('العمليات الحساسة: تعذّر حسابها'));
  });

  test('حد تيليجرام: يُقطع عند نهاية سطر', () {
    final d = OwnerSummaryData(DateTime(2026, 1, 1))
      ..sensitiveCount = 8
      ..boxes = {for (var i = 0; i < 8; i++) 'صندوق ${'س' * 300} $i': 1}
      ..sensitive = [for (var i = 0; i < 8; i++) OwnerSensitiveOp('x' * 50, 'تعديل', 'y' * 300)];
    final s = OwnerSummary.format(d);
    expect(s.length, lessThanOrEqualTo(OwnerSummary.maxLength));
    expect('<b>'.allMatches(s).length, '</b>'.allMatches(s).length);
  });
}
