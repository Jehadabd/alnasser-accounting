// lib/erp/sales/return_prefill.dart
//
// ↩️ المرتجع من فاتورة يبدأ «كلياً»: كل سطر بكميته المتبقية (ما بيع منه ناقص ما أُرجع
// سابقاً)، كما في أنظمة ERP المعروفة (Odoo: Reverse). المستخدم يُنقص الكمية أو يحذف
// السطر للمرتجع الجزئي. لا يُحفظ شيء تلقائياً — هذا اقتراح للشاشة فقط، والخدمة تبقى
// تتحقق من كل كمية مقابل المتبقي قبل الحفظ.

/// سطر من الفاتورة: المادة، ما بيع فيه بالوحدة الأساسية، ومعامل وحدته الحالية.
class ReturnPrefillLine {
  const ReturnPrefillLine({required this.productId, required this.soldBase, required this.factor});
  final int productId;
  final double soldBase;
  final double factor;
}

/// كمية كل سطر (بوحدته) في المرتجع الكلي.
/// [remaining]: المتبقي القابل للإرجاع لكل مادة بالوحدة الأساسية.
/// • لا يتجاوز سطرٌ ما بيع فيه، ولا تتجاوز أسطر المادة الواحدة معاً المتبقي منها.
/// • وحدة كبرى (معامل > 1) لا تأخذ كسراً منها: يُؤخذ العدد الصحيح فقط، والباقي يكتبه
///   المستخدم بالوحدة التي يريدها (لا تخمين بأسعار مقسومة).
List<double> fullReturnQuantities(List<ReturnPrefillLine> lines, Map<int, double> remaining) {
  const eps = 1e-6;
  final left = Map<int, double>.of(remaining);
  final out = <double>[];
  for (final l in lines) {
    final rem = left[l.productId] ?? 0;
    final f = l.factor > 0 ? l.factor : 1.0;
    final avail = l.soldBase < rem ? l.soldBase : rem;
    if (avail <= eps) {
      out.add(0);
      continue;
    }
    var q = avail / f;
    if (f > 1 + eps) {
      final r = q.roundToDouble();
      q = (q - r).abs() < eps ? r : q.floorToDouble();
    } else {
      q = double.parse(q.toStringAsFixed(6));
    }
    if (q < eps) q = 0;
    out.add(q);
    left[l.productId] = rem - q * f;
  }
  return out;
}
