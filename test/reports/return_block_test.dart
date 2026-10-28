// test/reports/return_block_test.dart
//
// مرتجع فاتورة جاءت بالمزامنة: من جهازها أو بحساب محاسبها فقط.
// التشغيل: flutter test test/reports/return_block_test.dart

import 'package:alnaser/erp/sales/sales_return_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('فاتورة هذا الجهاز: مسموح دائماً', () {
    expect(
        SalesReturnService.returnBlockReasonFor(createdByMe: true, creatorUsername: 'ali', currentUsername: 'omar'),
        isNull);
  });

  test('فاتورة جهاز آخر بحساب محاسبها نفسه: مسموح (بلا حساسية لحالة الأحرف والمسافات)', () {
    expect(
        SalesReturnService.returnBlockReasonFor(createdByMe: false, creatorUsername: ' Ali ', currentUsername: 'ali'),
        isNull);
  });

  test('فاتورة جهاز آخر بحساب مختلف: ممنوع مع اسم المحاسب', () {
    final r = SalesReturnService.returnBlockReasonFor(createdByMe: false, creatorUsername: 'ali', currentUsername: 'omar');
    expect(r, isNotNull);
    expect(r, contains('ali'));
  });

  test('فاتورة جهاز آخر بلا اسم محاسب (قديمة): ممنوع', () {
    expect(
        SalesReturnService.returnBlockReasonFor(createdByMe: false, creatorUsername: null, currentUsername: 'omar'),
        isNotNull);
    expect(
        SalesReturnService.returnBlockReasonFor(createdByMe: false, creatorUsername: '', currentUsername: ''),
        isNotNull);
  });
}
