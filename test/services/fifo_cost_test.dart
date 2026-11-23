import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/fifo_cost.dart';

void main() {
  // الباقي: 10 بـ1000 (الأقدم) ثم 10 بـ1100
  final layers = [CostLayer(10, 1000), CostLayer(10, 1100)];

  test('أول 10 تُباع بكلفة 1000، والتالية بـ1100', () {
    expect(FifoCost.takeCost(layers, 10), 1000);
    expect(FifoCost.takeCost(layers, 10, skip: 10), 1100);
  });

  test('بيع يعبر طبقتين: 15 قطعة = (10×1000 + 5×1100) ÷ 15', () {
    expect(FifoCost.takeCost(layers, 15), closeTo((10 * 1000 + 5 * 1100) / 15, 1e-9));
  });

  test('بيع أكثر من الرصيد: الزائد بكلفة أحدث طبقة', () {
    expect(FifoCost.takeCost(layers, 25), closeTo((10 * 1000 + 15 * 1100) / 25, 1e-9));
  });

  test('قيمة الباقي', () {
    expect(FifoCost.valueOf(layers), 21000);
  });
}
