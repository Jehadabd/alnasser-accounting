import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/erp/warranty/item_warranty.dart';
import 'package:alnaser/erp/warranty/warranty_desk.dart';

DeskLine _line({required DateTime end, double returnable = 20, double replaced = 0}) => DeskLine(
      productId: 1,
      name: 'مأخذ',
      saleUnit: 'كرتون',
      soldQty: 2,
      soldBase: 20,
      spec: const WarrantySpec(1, WarrantyUnit.year),
      end: end,
      terms: null,
      returnableBase: returnable,
      replacedBase: replaced,
    );

void main() {
  final today = DateTime.now();
  final d0 = DateTime(today.year, today.month, today.day);

  test('النهاية شاملة: اليوم الأخير داخل الضمان، وما بعده خارجه', () {
    expect(_line(end: d0).within, isTrue);
    expect(_line(end: d0).daysLeft, 0);
    expect(_line(end: d0.subtract(const Duration(days: 1))).within, isFalse);
    expect(_line(end: d0.add(const Duration(days: 30))).daysLeft, 30);
  });

  test('الحد الأعلى = المتبقي بعد المرتجع − ما استُبدل', () {
    expect(_line(end: d0, returnable: 20, replaced: 5).maxBase, 15);
    expect(_line(end: d0, returnable: 3, replaced: 5).maxBase, 0); // لا يصير سالباً
  });
}
