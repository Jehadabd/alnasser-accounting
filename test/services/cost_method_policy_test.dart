import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/cost_method_policy.dart';

void main() {
  test('المتوسط المرجّح: 10 بـ1000 + 10 بـ1100 = 1050', () {
    expect(CostMethodPolicy.average(stock: 10, cost: 1000, qty: 10, newCost: 1100), 1050);
  });

  test('المخزون السالب أو الصفر لا يدخل المتوسط', () {
    expect(CostMethodPolicy.average(stock: -5, cost: 1000, qty: 10, newCost: 1100), 1100);
    expect(CostMethodPolicy.average(stock: 0, cost: 1000, qty: 10, newCost: 1100), 1100);
  });

  test('قيمة بطاقة المادة: القديمة «last» والفارغة ⇒ حسب الإعدادات', () {
    expect(CostMethodPolicy.itemValue('last'), CostMethodPolicy.itemDefault);
    expect(CostMethodPolicy.itemValue(null), CostMethodPolicy.itemDefault);
    expect(CostMethodPolicy.itemValue('fixed'), CostMethodPolicy.itemDefault);
    expect(CostMethodPolicy.itemValue('average'), CostMethodPolicy.itemAverage);
    expect(CostMethodPolicy.itemValue('ask'), CostMethodPolicy.itemAsk);
  });
}
