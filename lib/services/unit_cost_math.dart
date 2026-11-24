// lib/services/unit_cost_math.dart
//
// 📐 تحويل الوحدات وكلفتها — مصدر واحد للحقيقة.
//
// على نهج أنظمة ERP (SAP «Alternative UoM»، Odoo «UoM Category»، Dynamics «Unit
// conversion»): للمادة وحدة أساس واحدة هي الأصغر، والكلفة تُحفظ للأساس وحده.
// لكل وحدة أكبر «معامل تحويل» إلى الأساس = حاصل ضرب مستويات الهرم حتى تلك الوحدة،
// وكلفتها = كلفة الأساس × المعامل. لا تُدخَل كلفة كل وحدة يدوياً فتتباعد.
//
// الهرم: [{'unit_name': 'علبة', 'quantity': 12}, {'unit_name': 'كرتون', 'quantity': 10}]
// يعني: علبة = 12 أساس، كرتون = 10 علب = 120 أساس.
//
// دوال صافية بلا قاعدة بيانات — مختبَرة في test/services/unit_cost_math_test.dart.

import 'dart:convert';

class UnitCostMath {
  UnitCostMath._();

  /// اسم الأساس كما يُعرض ويُخزَّن في unit_costs: 'piece' ← «قطعة»، 'meter' ← «متر».
  static String baseLabel(String unit) {
    final u = unit.trim();
    if (u == 'piece') return 'قطعة';
    if (u == 'meter') return 'متر';
    return u;
  }

  /// مستويات الهرم بالترتيب (من الأصغر إلى الأكبر): (الاسم، كم من المستوى السابق).
  /// يتحمّل JSON بعلامات مفردة ومفتاح 'name' القديم وكمية نصية.
  static List<(String, double)> levels(String? hierarchy) {
    if (hierarchy == null || hierarchy.trim().isEmpty) return const [];
    List<dynamic> raw;
    try {
      raw = jsonDecode(hierarchy) as List<dynamic>;
    } catch (_) {
      try {
        raw = jsonDecode(hierarchy.replaceAll("'", '"')) as List<dynamic>;
      } catch (_) {
        return const [];
      }
    }
    final out = <(String, double)>[];
    for (final l in raw) {
      if (l is! Map) continue;
      final name = '${l['unit_name'] ?? l['name'] ?? ''}'.trim();
      final q = l['quantity'];
      final qty = q is num ? q.toDouble() : (double.tryParse('${q ?? ''}'.replaceAll(',', '')) ?? 0);
      out.add((name, qty));
    }
    return out;
  }

  /// كم وحدة أساس في [unit]: 1 للأساس، وnull لوحدة غير معروفة أو سلسلة مكسورة
  /// (مستوى قبلها بلا كمية صحيحة) — فلا تُخمَّن كلفة خاطئة.
  static double? factorOf({
    required String baseUnit,
    required String unit,
    String? hierarchy,
    double? lengthPerUnit,
  }) {
    final u = unit.trim();
    if (u.isEmpty) return null;
    if (u == baseUnit.trim() || u == baseLabel(baseUnit)) return 1;
    // المتر واللفة: طول اللفة المسجَّل على المادة يسبق الهرم (كما في حساب الأرباح).
    if (baseUnit.trim() == 'meter' && u == 'لفة' && (lengthPerUnit ?? 0) > 0) return lengthPerUnit;
    var f = 1.0;
    for (final (name, qty) in levels(hierarchy)) {
      if (qty <= 0) return null;
      f *= qty;
      if (name == u) return f;
    }
    return null;
  }

  /// كلفة [unit] من كلفة الأساس، أو null إن لم يُعرف معاملها.
  static double? costOf({
    required String baseUnit,
    required String unit,
    required double baseCost,
    String? hierarchy,
    double? lengthPerUnit,
  }) {
    final f = factorOf(baseUnit: baseUnit, unit: unit, hierarchy: hierarchy, lengthPerUnit: lengthPerUnit);
    return f == null ? null : baseCost * f;
  }

  /// جدول كلفة كل الوحدات (يُخزَّن في unit_costs) لأي وحدة أساس — لا القطعة وحدها.
  static Map<String, double> unitCosts({
    required String baseUnit,
    required double baseCost,
    String? hierarchy,
    double? lengthPerUnit,
  }) {
    final m = <String, double>{baseLabel(baseUnit): baseCost};
    if (baseUnit.trim() == 'meter' && (lengthPerUnit ?? 0) > 0) m['لفة'] = baseCost * lengthPerUnit!;
    var f = 1.0;
    for (final (name, qty) in levels(hierarchy)) {
      if (qty <= 0) break;
      f *= qty;
      if (name.isNotEmpty) m.putIfAbsent(name, () => baseCost * f);
    }
    return m;
  }

  /// كلفة الأساس من سعر شراء [buyUnit]: سعر الشراء ÷ معاملها. null إن لم يُعرف المعامل.
  static double? baseCostFromBuy({
    required String baseUnit,
    required String buyUnit,
    required double buyCost,
    String? hierarchy,
    double? lengthPerUnit,
  }) {
    final f = factorOf(baseUnit: baseUnit, unit: buyUnit, hierarchy: hierarchy, lengthPerUnit: lengthPerUnit);
    return (f == null || f <= 0) ? null : buyCost / f;
  }
}
