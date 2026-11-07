// test/erp/margin_alert_test.dart
import 'package:alnaser/erp/inventory/margin_alert.dart';
import 'package:alnaser/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

Product _p(int id, {double cost = 0, double p1 = 0, double? p4}) => Product(
      id: id,
      name: 'مادة $id',
      unit: 'piece',
      unitPrice: p1,
      costPrice: cost,
      price1: p1,
      price4: p4,
      createdAt: DateTime(2026),
      lastModifiedAt: DateTime(2026),
    );

void main() {
  test('cost rise keeps each level margin (rounded up)', () {
    final rows = MarginAlert.afterCostRise({1: 1000}, [_p(1, cost: 1200, p1: 1500, p4: 1250)]);
    expect(rows, hasLength(1));
    final r = rows.first;
    // 1500 × 1.2 = 1800 ؛ 1250 × 1.2 = 1500
    expect(r.suggested[1], 1800);
    expect(r.suggested[4], 1500);
    expect(r.marginNow(1), closeTo(20, 1e-9)); // (1500-1200)/1500
  });

  test('no row when cost did not rise or was unknown', () {
    expect(MarginAlert.afterCostRise({1: 1000}, [_p(1, cost: 1000, p1: 1500)]), isEmpty);
    expect(MarginAlert.afterCostRise({1: 0}, [_p(1, cost: 1200, p1: 1500)]), isEmpty);
    expect(MarginAlert.afterCostRise({1: 1000}, [_p(1, cost: 900, p1: 1500)]), isEmpty);
  });

  test('below minimum: worst first, suggestion reaches the minimum', () {
    final rows = MarginAlert.belowMinimum([
      _p(1, cost: 950, p1: 1000), // 5%
      _p(2, cost: 1100, p1: 1000), // خسارة
      _p(3, cost: 500, p1: 1000), // 50% — لا تظهر
    ], 10);
    expect(rows.map((r) => r.product.id), [2, 1]);
    // 950 / 0.9 = 1055.6 ← 1100 (خطوة 50)
    expect(rows.last.suggested[1], 1100);
    expect(MarginRow.marginPct(rows.last.suggested[1]!, 950), greaterThanOrEqualTo(10));
  });

  test('ceilStep', () {
    expect(MarginAlert.ceilStep(1801), 1850);
    expect(MarginAlert.ceilStep(5001), 5250);
    expect(MarginAlert.ceilStep(333), 335);
  });

  test('changes only where the price moves', () {
    final rows = MarginAlert.afterCostRise({1: 1000}, [_p(1, cost: 1200, p1: 1500)]);
    final ch = MarginAlert.changesFor(rows);
    expect(ch, hasLength(1));
    expect(ch.first.level, 1);
    expect(ch.first.newValue, 1800);
  });
}
