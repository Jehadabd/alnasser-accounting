import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/wa_messages/wa_capacity.dart';
import 'package:alnaser/wa_messages/wa_rules.dart';

WaRule rule(String id, List<int> days, {WaRepeat repeat = WaRepeat.once, bool enabled = true}) =>
    WaRule(id: id, name: id, days: days, repeat: repeat, enabled: enabled);

void main() {
  group('حد الساعة', () {
    final now = DateTime(2026, 11, 24, 15, 0);
    test('أقل من الحد ⇒ الآن', () {
      final sent = [for (var i = 0; i < 59; i++) now.subtract(Duration(minutes: i))];
      expect(WaCapacity.hourGate(sent, 60, now), isNull);
    });
    test('امتلأت ⇒ ينتظر حتى تخرج أقدم رسالة من الساعة', () {
      final sent = [for (var i = 0; i < 60; i++) now.subtract(Duration(minutes: i))];
      // أقدمها قبل 59 دقيقة ⇒ تفرغ خانة بعد دقيقة
      expect(WaCapacity.hourGate(sent, 60, now), now.add(const Duration(minutes: 1)));
    });
    test('ما خرج من الساعة لا يُحسب', () {
      final sent = [for (var i = 0; i < 60; i++) now.subtract(Duration(minutes: 61 + i))];
      expect(WaCapacity.hourGate(sent, 60, now), isNull);
    });
  });

  group('حمل أيام الشهر', () {
    final nov = DateTime(2026, 11, 1);
    test('«مرة واحدة» في أول يوم مختار، و«كل عدد أيام» في كل يوم', () {
      final load = WaCapacity.monthLoad([
        (rule('a', [12, 20]), 300),
        (rule('b', [12], repeat: WaRepeat.everyDays), 250),
        (rule('c', [5, 6], repeat: WaRepeat.everyDays), 10),
      ], nov);
      expect(load[12], 550);
      expect(load[20], 0);
      expect(load[5], 10);
      expect(load[6], 10);
    });
    test('آخر الشهر و31 في شهر من 30 يوماً = يوم 30', () {
      final load = WaCapacity.monthLoad([(rule('a', [0]), 7), (rule('b', [31]), 3)], nov);
      expect(load[30], 10);
    });
    test('القاعدة المطفأة و«أي يوم» لا تدخل', () {
      final load = WaCapacity.monthLoad([(rule('a', [3], enabled: false), 9), (rule('b', []), 9)], nov);
      expect(load.values.every((v) => v == 0), isTrue);
    });
  });

  group('اقتراح يوم بديل', () {
    test('اليوم ممتلئ ⇒ أقرب يوم فيه متّسع (قبل ثم بعد)', () {
      final load = {for (var d = 1; d <= 30; d++) d: 0}..addAll({12: 450, 11: 480, 13: 100});
      expect(WaCapacity.suggestDay(load, day: 12, need: 120, cap: 500), 13);
      expect(WaCapacity.suggestDay(load, day: 12, need: 10, cap: 500), 11);
    });
    test('لا يقترح يوماً مختاراً أصلاً، ولا شيء إن امتلأ الشهر', () {
      final load = {for (var d = 1; d <= 30; d++) d: 0}..[11] = 0;
      expect(WaCapacity.suggestDay(load, day: 12, need: 5, cap: 500, avoid: {11}), 13);
      final full = {for (var d = 1; d <= 30; d++) d: 500};
      expect(WaCapacity.suggestDay(full, day: 12, need: 1, cap: 500), isNull);
    });
  });
}
