import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/screens/purchase_sale_extras.dart';

void main() {
  test('التقريب للأعلى إلى 250', () {
    expect(SalePriceMath.roundUp(1265, 250), 1500);
    expect(SalePriceMath.roundUp(1250, 250), 1250);
    expect(SalePriceMath.roundUp(1250.0000000001, 250), 1250); // ضجيج الحساب
    expect(SalePriceMath.roundUp(1, 250), 250);
    expect(SalePriceMath.roundUp(333.4, 1), 334);
  });

  test('الكلفة + نسبة / + مبلغ', () {
    expect(SalePriceMath.fromCost(1100, percent: true, value: 15), 1500); // 1265 ← 1500
    expect(SalePriceMath.fromCost(1100, percent: false, value: 1000), 2250); // 2100 ← 2250
    expect(SalePriceMath.fromCost(1000, percent: true, value: 25), 1250);
  });

  test('نسبة الربح', () {
    expect(SalePriceMath.marginPct(1500, 1000), 50);
    expect(SalePriceMath.marginPct(900, 1000), -10);
    expect(SalePriceMath.marginPct(900, 0), isNull);
  });
}
