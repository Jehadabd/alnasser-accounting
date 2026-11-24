// lib/wa_messages/wa_capacity.dart
//
// 📊 سعة الإرسال: كم رسالة في اليوم وفي الساعة.
//
//   • حد اليوم (افتراضياً 500) وحد الساعة (60) من «الأمان والسرعة» — يعدّلهما المستخدم.
//   • عند تعديل قاعدة: حمل كل يوم من الشهر من القواعد الأخرى، فإن امتلأ اليوم المختار
//     يُقترح أقرب يوم فيه متّسع (قبله أو بعده).
//   • وقت الإرسال: ما يزيد على حد اليوم يُرحَّل إلى اليوم التالي ويُرسل أولاً
//     (WaCarryOver في wa_outbox.dart)، وما يزيد على حد الساعة ينتظر حتى تفرغ.
//
// دوال صافية بلا قاعدة بيانات — مختبَرة في test/wa_messages/wa_capacity_test.dart.

import 'wa_rules.dart';

class WaCapacity {
  WaCapacity._();

  static int lastDayOf(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

  /// يوم القاعدة الفعلي في الشهر: 0 أو يوم أكبر من أيام الشهر = آخر يوم.
  static int resolveDay(int d, int lastDay) => (d == 0 || d >= lastDay) ? lastDay : d;

  /// متى يُسمح بالرسالة التالية إن امتلأت الساعة؟ null = الآن.
  /// [sentLastHour] أوقات الرسائل المرسلة في الساعة الأخيرة.
  static DateTime? hourGate(List<DateTime> sentLastHour, int maxPerHour, DateTime now) {
    final cap = maxPerHour < 1 ? 1 : maxPerHour;
    final since = now.subtract(const Duration(hours: 1));
    final inWindow = [for (final t in sentLastHour) if (t.isAfter(since)) t]..sort();
    if (inWindow.length < cap) return null;
    // تفرغ خانة حين تخرج الرسالة رقم (n - cap) من نافذة الساعة
    return inWindow[inWindow.length - cap].add(const Duration(hours: 1));
  }

  /// الرسائل المتوقعة في كل يوم من الشهر من قواعد أيامها محددة.
  /// [rules]: القاعدة وعدد من تنطبق عليهم الآن. «مرة واحدة» و«كل شهر» تُحسب في أول
  /// يوم مختار من الشهر (ترسل مرة واحدة)، و«كل عدد أيام» في كل يوم مختار.
  /// قواعد «أي يوم» لا يوم لها ⇒ لا تدخل هنا (حملها يتوزع حين يتحقق شرطها).
  static Map<int, int> monthLoad(Iterable<(WaRule, int)> rules, DateTime month) {
    final last = lastDayOf(month);
    final load = <int, int>{for (var d = 1; d <= last; d++) d: 0};
    for (final (r, n) in rules) {
      if (!r.enabled || n <= 0 || r.days.isEmpty) continue;
      final days = {for (final d in r.days) resolveDay(d, last)}.toList()..sort();
      final hit = r.repeat == WaRepeat.everyDays ? days : [days.first];
      for (final d in hit) {
        load[d] = (load[d] ?? 0) + n;
      }
    }
    return load;
  }

  /// أقرب يوم يتسع لـ[need] رسالة: يوم قبله ثم بعده، ثم يومان... null إن لم يوجد.
  /// [avoid] أيام لا تُقترح (المختارة أصلاً).
  static int? suggestDay(Map<int, int> load, {required int day, required int need, required int cap, Set<int> avoid = const {}}) {
    final last = load.keys.isEmpty ? 31 : load.keys.reduce((a, b) => a > b ? a : b);
    for (var k = 1; k < last; k++) {
      for (final d in [day - k, day + k]) {
        if (d < 1 || d > last || avoid.contains(d)) continue;
        if ((load[d] ?? 0) + need <= cap) return d;
      }
    }
    return null;
  }
}
