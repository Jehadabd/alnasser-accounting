// test/smart_search/recency_score_test.dart
import 'package:alnaser/services/smart_search/recency_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 7);

  test('one occurrence today = 1', () {
    final (s, r) = RecencyScore.add(null, null, now);
    expect(RecencyScore.valueAt(s, r, now), closeTo(1, 1e-9));
  });

  test('half-life halves the weight', () {
    final (s, r) = RecencyScore.add(null, null, now.subtract(const Duration(days: 120)));
    expect(RecencyScore.valueAt(s, r, now), closeTo(0.5, 1e-3));
  });

  test('100 old + 1 recent is weak; 30 recent is strong', () {
    double? s;
    DateTime? r;
    final old = now.subtract(const Duration(days: 730));
    for (var i = 0; i < 100; i++) {
      (s, r) = RecencyScore.add(s, r, old);
    }
    (s, r) = RecencyScore.add(s, r, now.subtract(const Duration(days: 1)));
    final oldHeavy = RecencyScore.valueAt(s!, r!, now);

    double? s2;
    DateTime? r2;
    for (var d = 0; d < 30; d++) {
      (s2, r2) = RecencyScore.add(s2, r2, now.subtract(Duration(days: d)));
    }
    final recent = RecencyScore.valueAt(s2!, r2!, now);
    expect(oldHeavy, lessThan(4));
    expect(recent, greaterThan(25));
    expect(recent, greaterThan(oldHeavy));
  });

  test('order of training does not matter', () {
    final dates = [
      now.subtract(const Duration(days: 300)),
      now.subtract(const Duration(days: 10)),
      now.subtract(const Duration(days: 90)),
    ];
    double? a;
    DateTime? ar;
    for (final d in dates) {
      (a, ar) = RecencyScore.add(a, ar, d);
    }
    double? b;
    DateTime? br;
    for (final d in dates.reversed) {
      (b, br) = RecencyScore.add(b, br, d);
    }
    expect(RecencyScore.valueAt(a!, ar!, now), closeTo(RecencyScore.valueAt(b!, br!, now), 1e-9));
  });
}
