import 'package:alnaser/radar/demand_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('seasonIndex', () {
    test('growth of the shop is not mistaken for a season', () {
      // المحل تضاعف: فواتيره 100 ثم 200؛ المادة نفس الحصة (10% من الفواتير) كل شهر
      final shop = <String, int>{};
      final qty = <String, double>{};
      for (var m = 1; m <= 12; m++) {
        final k = DemandSignals.ym(2025, m);
        shop[k] = m <= 6 ? 100 : 200;
        qty[k] = shop[k]! * 0.1;
      }
      final s = DemandSignals.seasonIndex(qty, shop, '2026-01');
      for (var m = 1; m <= 12; m++) {
        expect(s.index[m], closeTo(1.0, 1e-9), reason: 'month $m');
      }
    });

    test('a real summer peak is detected', () {
      final shop = <String, int>{};
      final qty = <String, double>{};
      for (var m = 1; m <= 12; m++) {
        final k = DemandSignals.ym(2025, m);
        shop[k] = 100;
        qty[k] = (m == 7 || m == 8) ? 30 : 10;
      }
      final s = DemandSignals.seasonIndex(qty, shop, '2026-01');
      expect(s.index[7]!, greaterThan(2.0));
      expect(s.index[1]!, lessThan(1.0));
      expect(s.years[7], 1);
    });

    test('months before using the app are ignored', () {
      final shop = {'2025-01': 3, '2025-02': 2}; // بداية الاستعمال: فواتير قليلة
      final qty = <String, double>{'2025-01': 3, '2025-02': 2};
      for (var m = 3; m <= 10; m++) {
        shop[DemandSignals.ym(2025, m)] = 100;
        qty[DemandSignals.ym(2025, m)] = 10;
      }
      final s = DemandSignals.seasonIndex(qty, shop, '2025-11');
      expect(s.index.containsKey(1), isFalse);
      expect(s.index[5], closeTo(1.0, 1e-9));
    });

    test('too little history gives no season', () {
      final s = DemandSignals.seasonIndex({'2025-01': 5, '2025-02': 5}, {'2025-01': 100, '2025-02': 100}, '2025-03');
      expect(s.index, isEmpty);
    });
  });

  test('forecast removes the season of recent months before applying the target season', () {
    // آخر 3 أشهر كانت موسماً (×2): المستوى الحقيقي 10 لا 20
    final f = DemandSignals.forecast(
      qty: {'2025-06': 20, '2025-07': 20, '2025-08': 20},
      last3: const ['2025-08', '2025-07', '2025-06'],
      index: const {6: 2.0, 7: 2.0, 8: 2.0, 9: 1.0},
      targetMonth: 9,
    );
    expect(f, closeTo(10, 1e-9));
  });

  group('stopped', () {
    List<String> days(int n) => [for (var i = 1; i <= n; i++) '2026-01-${i.toString().padLeft(2, '0')}'];

    test('a daily seller silent for 10 work days is flagged', () {
      final active = days(30);
      final sold = active.sublist(0, 20);
      final r = DemandSignals.stopped(active, sold);
      expect(r, isNotNull);
      expect(r!.silence, 10);
    });

    test('an occasional seller is not flagged by a normal gap', () {
      final active = days(30);
      final sold = [active[0], active[5], active[10], active[15], active[20], active[24]];
      expect(DemandSignals.stopped(active, sold), isNull);
    });

    test('shop closed (no work days after last sale) flags nothing', () {
      final active = days(20);
      expect(DemandSignals.stopped(active, active), isNull);
    });
  });
}
