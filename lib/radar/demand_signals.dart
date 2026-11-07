// lib/radar/demand_signals.dart
//
// 📈 إشارات الطلب — حساب خالص (بلا قاعدة بيانات) يستعمله «رادار التاجر»:
//
//   1) معامل الموسم لكل شهر، منسوباً إلى نشاط المحل نفسه:
//        حصة المادة في شهر = كميتها ÷ عدد فواتير المحل في ذلك الشهر
//        المعامل = متوسط حصتها في هذا الشهر من السنوات السابقة ÷ متوسط حصتها العام
//      النسبة إلى نشاط المحل تُبعد أثر نمو المحل: محل تضاعفت فواتيره خلال سنة كان
//      يبدو فيه كل شهر من السنة الماضية «موسماً ضعيفاً» لكل المواد.
//
//   2) «توقف بيعها فجأة»: مادة كانت تُباع بانتظام ولم تُبع منذ عدد من أيام العمل
//      يندر أن يحدث صدفة. تُعدّ أيام العمل فقط (أيام فيها فاتورة)، فإن توقف المحل كله
//      (عطلة، جهاز لم يُزامن) لا تظهر أي مادة.
//      احتمال الصمت صدفة = (1 − p)^s، p = نسبة أيام العمل التي بيعت فيها،
//      s = أيام العمل منذ آخر بيع. تُعلَّم إن قلّ عن 2%.

import 'dart:math' as math;

class DemandSignals {
  DemandSignals._();

  /// شهر لا يُعتمد عليه إن قلّت فواتير المحل فيه عن هذا (بداية استعمال البرنامج).
  static const int minShopInvoices = 15;

  /// أقل عدد أشهر صالحة للمادة قبل حساب أي موسم.
  static const int minMonths = 6;

  static String ym(int year, int month) {
    final d = DateTime(year, month, 1);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }

  static int _monthOf(String key) => int.tryParse(key.substring(5)) ?? 0;

  /// الأشهر الصالحة للمادة: من أول شهر بيعت فيه حتى الشهر الماضي، وفيها نشاط كافٍ للمحل.
  static List<String> _eligible(Map<String, double> qty, Map<String, int> shop, String currentYm) {
    final sold = qty.entries.where((e) => e.value > 0).map((e) => e.key).toList()..sort();
    if (sold.isEmpty) return const [];
    final first = sold.first;
    final keys = shop.keys.where((k) => k.compareTo(first) >= 0 && k.compareTo(currentYm) < 0).toList()..sort();
    return [for (final k in keys) if ((shop[k] ?? 0) >= minShopInvoices) k];
  }

  /// معامل الموسم لكل شهر من 1 إلى 12 (غير الموجود = 1.0) وعدد السنوات التي بُني عليها.
  /// [qty]: كمية المادة لكل شهر 'yyyy-mm'. [shop]: عدد فواتير المحل لكل شهر.
  static ({Map<int, double> index, Map<int, int> years}) seasonIndex(
    Map<String, double> qty,
    Map<String, int> shop,
    String currentYm,
  ) {
    final months = _eligible(qty, shop, currentYm);
    final index = <int, double>{};
    final years = <int, int>{};
    if (months.length < minMonths) return (index: index, years: years);
    var q = 0.0, n = 0;
    for (final k in months) {
      q += qty[k] ?? 0;
      n += shop[k] ?? 0;
    }
    if (q <= 0 || n <= 0) return (index: index, years: years);
    final avgShare = q / n;
    final byMonth = <int, List<double>>{};
    for (final k in months) {
      byMonth.putIfAbsent(_monthOf(k), () => []).add((qty[k] ?? 0) / (shop[k]!));
    }
    byMonth.forEach((m, shares) {
      final mean = shares.fold<double>(0, (s, v) => s + v) / shares.length;
      index[m] = (mean / avgShare).clamp(0.5, 2.5).toDouble();
      years[m] = shares.length;
    });
    return (index: index, years: years);
  }

  /// توقع البيع لشهر [targetMonth]: مستوى البيع في آخر 3 أشهر كاملة بعد إزالة أثر
  /// موسمها، ثم ضربه بمعامل الشهر المستهدف (فلا يُحسب الموسم مرتين).
  static double forecast({
    required Map<String, double> qty,
    required List<String> last3,
    required Map<int, double> index,
    required int targetMonth,
  }) {
    var level = 0.0;
    for (final k in last3) {
      level += (qty[k] ?? 0) / (index[_monthOf(k)] ?? 1.0);
    }
    level /= math.max(1, last3.length);
    return level * (index[targetMonth] ?? 1.0);
  }

  /// مادة توقف بيعها على غير عادتها؟ [activeDays] و[saleDays]: أيام (yyyy-mm-dd) مرتّبة تصاعدياً.
  /// يعيد null إن لم يكن الصمت لافتاً.
  static ({int silence, double everyDays, int saleDays})? stopped(
    List<String> activeDays,
    List<String> saleDays, {
    int minSaleDays = 6,
    int minSilence = 5,
    int maxSilence = 60,
    double threshold = 0.02,
  }) {
    if (saleDays.length < minSaleDays || activeDays.isEmpty) return null;
    final first = saleDays.first, last = saleDays.last;
    final span = activeDays.where((d) => d.compareTo(first) >= 0 && d.compareTo(last) <= 0).length;
    if (span <= 0) return null;
    final silence = activeDays.where((d) => d.compareTo(last) > 0).length;
    if (silence < minSilence || silence > maxSilence) return null;
    final p = (saleDays.length / span).clamp(0.0, 1.0).toDouble();
    if (p >= 1.0) {
      return (silence: silence, everyDays: 1.0, saleDays: saleDays.length);
    }
    final chance = math.pow(1 - p, silence).toDouble();
    if (chance >= threshold) return null;
    return (silence: silence, everyDays: 1 / p, saleDays: saleDays.length);
  }
}
