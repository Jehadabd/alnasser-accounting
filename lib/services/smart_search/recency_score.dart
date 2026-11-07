// lib/services/smart_search/recency_score.dart
//
// ⏳ قوة علاقة «تُشترى معاً» حسب تاريخ كل مرة حدثت فيها — لا حسب آخر مرة فقط.
// كل مرة شراء تضيف 1 ثم يتناقص أثرها تدريجياً (يتنصّف كل [halfLifeDays] يوماً):
//   100 مرة قبل سنتين + مرة أمس  ⇒ ≈ 1.0 + 100×(0.5^6) ≈ 2.6  (لا 101 كما كان)
//   30 مرة خلال الشهر الأخير      ⇒ ≈ 27                     (علاقة حيّة قوية)
// تُخزَّن قيمة واحدة مع تاريخها المرجعي (آخر مرة)، وتُحسب «قيمتها الآن» عند القراءة.
// دالة صافية بلا قاعدة بيانات — تُختبر وحدها.

import 'dart:math' as math;

class RecencyScore {
  RecencyScore._();

  /// كل 120 يوماً يتنصّف أثر المرة الواحدة (بعد سنة ≈ 12%، بعد سنتين ≈ 1.5%).
  static const double halfLifeDays = 120;

  static double _factor(double days) => days <= 0 ? 1.0 : math.pow(0.5, days / halfLifeDays).toDouble();

  static double _days(DateTime from, DateTime to) => to.difference(from).inMinutes / 1440.0;

  /// يضيف مرة حدثت في [at] إلى قيمة [score] المرجعية عند [ref].
  /// يقبل الترتيب غير الزمني (فاتورة قديمة تُدرَّب بعد أحدث منها). يعيد القيمة والمرجع الجديدين.
  static (double, DateTime) add(double? score, DateTime? ref, DateTime at) {
    if (score == null || ref == null) return (1.0, at);
    if (!at.isBefore(ref)) {
      // الأحدث يصير المرجع: القديم يتناقص حتى [at] ثم +1
      return (score * _factor(_days(ref, at)) + 1.0, at);
    }
    // مرة أقدم من المرجع: تُضاف متناقصةً بقدر قِدَمها عنه
    return (score + _factor(_days(at, ref)), ref);
  }

  /// قيمة العلاقة الآن.
  static double valueAt(double score, DateTime ref, DateTime now) => score * _factor(_days(ref, now));
}
