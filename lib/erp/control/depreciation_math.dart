// lib/erp/control/depreciation_math.dart
//
// 📉 حساب الإهلاك (قسط ثابت) — دوال صافية بلا قاعدة، لتُختبر وحدها.
//
//   القسط الشهري = (الكلفة − قيمة الخردة) ÷ العمر بالأشهر، مقرّباً إلى فلسين.
//   لا يتجاوز المجمّع أبداً (الكلفة − الخردة): آخر قسط يأخذ الباقي فقط.
//   الشهر المؤهل: من شهر بدء الإهلاك حتى ما قبل شهر الاستبعاد (شهر الاستبعاد لا يُهلك).

/// شهر بصيغة YYYY-MM.
String periodOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// أول يوم في الشهر.
DateTime periodStart(String period) {
  final p = period.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), 1);
}

/// آخر يوم في الشهر (تاريخ قيد الإهلاك).
DateTime periodEnd(String period) {
  final s = periodStart(period);
  return DateTime(s.year, s.month + 1, 0);
}

/// هل الصيغة YYYY-MM صحيحة؟
bool validPeriod(String p) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(p);
  if (m == null) return false;
  final mo = int.parse(m.group(2)!);
  return mo >= 1 && mo <= 12;
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// القسط الشهري الاسمي.
double monthlyDepreciation({required double cost, required double salvage, required int lifeMonths}) {
  if (lifeMonths <= 0) return 0;
  final base = cost - salvage;
  if (base <= 0) return 0;
  return _r2(base / lifeMonths);
}

/// قسط شهر [period] لأصل، بعد ما أُهلك منه فعلاً [accumulated].
/// [startPeriod]: شهر بدء الإهلاك. [disposedPeriod]: شهر الاستبعاد (null = قائم).
double depreciationFor({
  required String period,
  required String startPeriod,
  String? disposedPeriod,
  required double cost,
  required double salvage,
  required int lifeMonths,
  required double accumulated,
}) {
  if (period.compareTo(startPeriod) < 0) return 0;
  if (disposedPeriod != null && period.compareTo(disposedPeriod) >= 0) return 0;
  final base = _r2(cost - salvage);
  final remaining = _r2(base - accumulated);
  if (remaining <= 0) return 0;
  final m = monthlyDepreciation(cost: cost, salvage: salvage, lifeMonths: lifeMonths);
  if (m <= 0) return 0;
  // آخر قسط يأخذ الباقي كله (ومعه فلوس التقريب) حتى لا يبقى كسر معلّق
  return _r2(remaining - m) <= 0.01 ? remaining : m;
}

/// قيد استبعاد أصل: ما يُقبض، مجمّع إهلاكه، وكلفته ⇒ ربح (+) أو خسارة (−).
double disposalGain({required double cost, required double accumulated, required double proceeds}) =>
    _r2(proceeds - (cost - accumulated));

/// القيمة الدفترية الآن.
double bookValue({required double cost, required double accumulated}) => _r2(cost - accumulated);
