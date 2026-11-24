import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/erp/stock_reservations.dart';
import 'package:alnaser/models/invoice_item.dart';

InvoiceItem line(int? pid, {double? qi, double? ql, double? uilu}) => InvoiceItem(
      invoiceId: 0,
      productId: pid,
      productName: 'م$pid',
      unit: 'piece',
      quantityIndividual: qi,
      quantityLargeUnit: ql,
      unitsInLargeUnit: uilu,
      appliedPrice: 1,
      itemTotal: 1,
      saleType: ql != null ? 'كرتون' : 'قطعة',
    );

void main() {
  final book = StockReservations.instance;
  tearDown(() {
    book.release('a');
    book.release('b');
    book.release('pos');
  });

  group('الكمية بالوحدة الأساسية (صيغة دفتر المخزون)', () {
    test('قطع، وكرتون × معامله، وبلا مادة تُتجاهل', () {
      final m = StockReservations.baseByProduct([
        line(1, qi: 3),
        line(1, ql: 2, uilu: 12),
        line(2, ql: 1), // معامل غير محفوظ = 1 كما في الدفتر
        line(null, qi: 5),
      ]);
      expect(m, {1: 27.0, 2: 1.0});
    });
  });

  group('سيناريو جهاد ومحمد: كوب ماء رصيده 10', () {
    test('فاتورة محمد تحجز 10 ⇒ المتاح لفاتورة جهاد 0', () {
      book.set('a', {7: 10}, label: 'فاتورة محمد');
      expect(book.reservedByOthers(7, 'b'), 10);
      expect(10 - book.reservedByOthers(7, 'b'), 0);
      // فاتورة محمد نفسها لا ترى حجزها كحجز لغيرها
      expect(book.reservedByOthers(7, 'a'), 0);
      expect(book.holdersText(7, 'b'), 'محجوز: فاتورة محمد 10');
    });
    test('إغلاق فاتورة محمد أو حفظها يزيل الحجز', () {
      book.set('a', {7: 10}, label: 'فاتورة محمد');
      book.release('a');
      expect(book.reservedByOthers(7, 'b'), 0);
    });
    test('أكثر من مسودّة: الكاشير وفاتورة', () {
      book.set('a', {7: 4}, label: 'فاتورة محمد');
      book.set('pos', {7: 3}, label: 'الكاشير');
      expect(book.reservedByOthers(7, 'b'), 7);
    });
  });

  group('تعديل فاتورة محفوظة', () {
    test('يحجز الزيادة فقط؛ النقص لا يحرّر قبل الحفظ', () {
      expect(StockReservations.delta({1: 12, 2: 3}, {1: 10, 2: 5}), {1: 2.0});
      expect(StockReservations.delta({1: 10}, {1: 10}), isEmpty);
    });
  });

  test('لا إشعار إن لم يتغير الحجز', () {
    var n = 0;
    void l() => n++;
    book.addListener(l);
    book.set('a', {1: 2}, label: 'x');
    book.set('a', {1: 2}, label: 'x');
    book.set('a', {1: 3}, label: 'x');
    book.removeListener(l);
    expect(n, 2);
  });
}
