// lib/erp/control/business_math.dart
//
// 🧮 حسابات قرارات صاحب العمل — دوال صافية بلا قاعدة، لتُختبر وحدها.

/// نقطة التعادل.
class BreakEven {
  BreakEven({required this.fixedMonthly, required this.marginPct, required this.daysInMonth});

  /// المصاريف الثابتة للشهر.
  final double fixedMonthly;

  /// هامش الربح الإجمالي % (ربح البضاعة ÷ صافي المبيعات).
  final double marginPct;
  final int daysInMonth;

  /// هل يمكن الحساب؟ (هامش موجب ومصاريف موجبة)
  bool get valid => marginPct > 0 && fixedMonthly > 0 && daysInMonth > 0;

  /// المبيعات الشهرية اللازمة لتغطية المصاريف الثابتة.
  double get monthlySales => valid ? fixedMonthly / (marginPct / 100) : 0;

  /// المبيعات اليومية اللازمة.
  double get dailySales => valid ? monthlySales / daysInMonth : 0;

  /// ربح البضاعة اللازم يومياً.
  double get dailyProfit => daysInMonth > 0 ? fixedMonthly / daysInMonth : 0;

  /// اللازم حتى اليوم [day] من الشهر (1..daysInMonth).
  double requiredToDate(int day) => dailySales * day.clamp(0, daysInMonth);

  /// نسبة تغطية المصاريف الثابتة من ربح البضاعة المحقق.
  double coveredPct(double grossProfitToDate) =>
      fixedMonthly > 0 ? (grossProfitToDate / fixedMonthly * 100).clamp(0, 1000).toDouble() : 0;
}

/// عدد أيام شهر.
int daysInMonthOf(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

/// اقتراح كمية شراء لمادة.
class ReorderInput {
  ReorderInput({
    required this.soldBaseQty,
    required this.lookbackDays,
    required this.stockBaseQty,
    required this.leadDays,
    required this.coverDays,
    this.minStock = 0,
  });

  final double soldBaseQty;
  final int lookbackDays;
  final double stockBaseQty;
  final int leadDays;
  final int coverDays;

  /// حد التنبيه/الأدنى (بالوحدة الأساسية).
  final double minStock;

  double get dailyVelocity => lookbackDays > 0 ? soldBaseQty / lookbackDays : 0;

  /// الأيام التي يكفيها الرصيد الحالي (null = لا مبيعات).
  double? get daysLeft => dailyVelocity > 0 ? (stockBaseQty > 0 ? stockBaseQty / dailyVelocity : 0) : null;

  /// الرصيد المطلوب بعد وصول الطلبية: يغطي مدة التوريد + مدة التغطية، ولا يقل عن الحد الأدنى.
  double get targetStock {
    final t = dailyVelocity * (leadDays + coverDays);
    return t > minStock ? t : (dailyVelocity > 0 || minStock > 0 ? minStock : 0);
  }

  /// الكمية المقترحة (مقرّبة لأعلى، صفر إن كفى الرصيد).
  double get suggested {
    final need = targetStock - (stockBaseQty > 0 ? stockBaseQty : 0);
    if (need <= 0.0001) return 0;
    return need.ceilToDouble();
  }

  /// عاجل: سينفد قبل وصول الطلبية.
  bool get urgent => daysLeft != null && daysLeft! <= leadDays;
}

/// تحويل كمية أساسية إلى وحدة كبرى (كرتون مثلاً) مع تقريب لأعلى.
double toLargeUnits(double baseQty, double unitsPerLarge) =>
    unitsPerLarge > 1 ? (baseQty / unitsPerLarge).ceilToDouble() : baseQty;
