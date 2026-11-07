// lib/erp/inventory/margin_alert.dart
//
// 📉 «مواد نزل ربحها» — حساب فقط، لا يغيّر أي سعر:
//   • بعد فاتورة شراء: مواد ارتفعت كلفتها وبقي سعر بيعها كما هو. المقترح لكل مستوى سعر
//     = السعر × (الكلفة الجديدة ÷ القديمة)، أي يعود ربح كل مستوى إلى نسبته السابقة.
//   • في «أدوات الأسعار»: مواد ربح سعر المفرد فيها أقل من حد تختاره (ومنها ما يُباع بخسارة).
//     المقترح = الكلفة ÷ (1 − الحد).
// المقترح يُقرَّب إلى الأعلى (5 / 50 / 250 دينار حسب حجم السعر).
// التطبيق عبر PriceTools.apply (دفعة في سجل الدفعات قابلة للتراجع) — بضغطة المستخدم فقط.
// الكلفة وأسعار البيع للوحدة الأساسية نفسها (كما تُخزَّن في المادة).

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/product.dart';
import 'price_tools.dart';

class MarginRow {
  MarginRow({
    required this.product,
    required this.oldCost,
    required this.newCost,
    required this.current,
    required this.suggested,
  });

  final Product product;

  /// الكلفة قبل الشراء (تساوي [newCost] في فحص «أقل من الحد»).
  final double oldCost;
  final double newCost;

  /// مستوى السعر (1..6) ← السعر الحالي (الموجب فقط).
  final Map<int, double> current;

  /// مستوى السعر ← المقترح.
  final Map<int, double> suggested;

  /// نسبة الربح من سعر البيع لمستوى، بكلفة [cost].
  static double marginPct(double price, double cost) => price <= 0 ? 0 : (price - cost) / price * 100;

  double marginNow(int level) => marginPct(current[level] ?? 0, newCost);
  double marginBefore(int level) => marginPct(current[level] ?? 0, oldCost);
}

class MarginAlert {
  MarginAlert._();

  static const _kMin = 'margin_alert_min_pct';

  /// حد الربح الأدنى لفحص «أقل من الحد» (افتراضياً 10%).
  static Future<double> minPct() async {
    try {
      return (await SharedPreferences.getInstance()).getDouble(_kMin) ?? 10;
    } catch (_) {
      return 10;
    }
  }

  static Future<void> setMinPct(double v) async {
    try {
      await (await SharedPreferences.getInstance()).setDouble(_kMin, v.clamp(0, 95).toDouble());
    } catch (_) {}
  }

  /// تقريب إلى الأعلى بخطوة تناسب حجم السعر.
  static double ceilStep(double v) {
    if (v <= 0) return 0;
    final step = v >= 5000 ? 250.0 : (v >= 1000 ? 50.0 : 5.0);
    // −1e-6: كسور الحساب العشري (1800.0000000002) لا تقفز خطوة كاملة
    return ((v - 1e-6) / step).ceilToDouble() * step;
  }

  static Map<int, double> _prices(Product p) => {
        for (var l = 1; l <= 6; l++)
          if (PriceTools.priceOf(p, l) > 0) l: PriceTools.priceOf(p, l),
      };

  /// مواد ارتفعت كلفتها: [before] كلفة كل مادة قبل الحفظ، [after] المواد بعد الحفظ.
  static List<MarginRow> afterCostRise(Map<int, double> before, List<Product> after) {
    final out = <MarginRow>[];
    for (final p in after) {
      final id = p.id;
      if (id == null) continue;
      final oldCost = before[id] ?? 0;
      final newCost = p.costPrice ?? 0;
      // لا كلفة سابقة = لا أساس للمقارنة؛ والارتفاع أقل من نصف بالمئة لا يُذكر
      if (oldCost <= 0 || newCost <= oldCost * 1.005) continue;
      final cur = _prices(p);
      if (cur.isEmpty) continue;
      final factor = newCost / oldCost;
      final sug = <int, double>{
        for (final e in cur.entries) e.key: ceilStep(e.value * factor),
      };
      out.add(MarginRow(product: p, oldCost: oldCost, newCost: newCost, current: cur, suggested: sug));
    }
    out.sort((a, b) => a.marginNow(1).compareTo(b.marginNow(1)));
    return out;
  }

  /// مواد ربح سعر المفرد فيها أقل من [minPct]% (الأسوأ أولاً).
  static List<MarginRow> belowMinimum(List<Product> products, double minPct) {
    final out = <MarginRow>[];
    final m = (minPct.clamp(0, 95)) / 100;
    for (final p in products) {
      final cost = p.costPrice ?? 0;
      if (cost <= 0 || p.price1 <= 0) continue;
      if (MarginRow.marginPct(p.price1, cost) >= minPct - 1e-9) continue;
      final cur = _prices(p);
      out.add(MarginRow(
        product: p,
        oldCost: cost,
        newCost: cost,
        current: cur,
        suggested: {1: ceilStep(cost / (1 - m))},
      ));
    }
    out.sort((a, b) => a.marginNow(1).compareTo(b.marginNow(1)));
    return out;
  }

  /// تغييرات الأسعار للمواد المختارة (لـ PriceTools.apply).
  static List<PriceChange> changesFor(Iterable<MarginRow> rows) => [
        for (final r in rows)
          for (final e in r.suggested.entries)
            if ((e.value - (r.current[e.key] ?? 0)).abs() > 0.004)
              PriceChange(r.product.id!, r.product.name, e.key, r.current[e.key] ?? 0, e.value),
      ];
}
