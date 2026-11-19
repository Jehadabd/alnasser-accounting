// lib/owner/ai_invoice/ai_purchase_prefill.dart
//
// ما تنقله شاشة مراجعة الذكاء الاصطناعي إلى شاشة «فاتورة شراء» العادية.
// الحفظ نفسه (المخزون، الدين، القيود) يبقى في شاشة الشراء كما هو تماماً.

import '../../models/purchase_invoice_item.dart';

class AiPurchasePrefill {
  AiPurchasePrefill({
    required this.items,
    this.invoiceNumber = '',
    this.date,
    this.currency = 'IQD',
    this.isCash = false,
    this.paidAmount = 0,
    this.attachmentPath,
    this.supplierId,
    Map<String, String>? originalNames,
    Map<String, AiUnitPlan>? unitPlans,
  })  : originalNames = originalNames ?? {},
        unitPlans = unitPlans ?? {};

  final List<PurchaseInvoiceItem> items; // productId = -1 ⇒ مادة جديدة تُعرَّف في شاشة الشراء
  final String invoiceNumber;
  final DateTime? date;
  final String currency;
  final bool isCash;
  final double paidAmount;
  final String? attachmentPath;
  final int? supplierId;

  /// اسم المادة الجديدة المقترح ← اسمها الأصلي في فاتورة المورد
  /// (حين تُعرَّف المادة في شاشة الشراء نتعلّم الاسم الأصلي لها)
  final Map<String, String> originalNames;

  /// اسم المادة الجديدة ← وحداتها كما عرّفتها في المراجعة (الأصغر، والأكبر منها، والكلفة)
  final Map<String, AiUnitPlan> unitPlans;
}

/// 📦 وحدات مادة جديدة عرّفها المستخدم في مراجعة الفاتورة.
///   مثال: الفاتورة «كرتون بـ 1,000»، والكرتون = 10 باكيت، والباكيت = 10 قطعة ⇒
///   baseUnit «قطعة»، levels [باكيت×10، كرتون×10] (كل مستوى نسبةً للذي قبله — نفس
///   صيغة unit_hierarchy في المادة)، baseCost = 1,000 ÷ 100 = 10.
class AiUnitPlan {
  const AiUnitPlan({required this.baseUnit, required this.levels, required this.baseCost});

  /// أصغر وحدة (تُباع بها وتُحسب بها الكلفة والمخزون).
  final String baseUnit;

  /// من الأصغر إلى الأكبر: {'unit_name': ..., 'quantity': كم من المستوى السابق}.
  final List<Map<String, dynamic>> levels;

  /// كلفة الوحدة الأصغر.
  final double baseCost;

  /// كل الوحدات من الأصغر إلى الأكبر.
  List<String> get units => [baseUnit, ...levels.map((l) => '${l['unit_name']}')];

  /// كم وحدة أصغر في [unit] (1 للأصغر نفسها).
  double factorOf(String unit) {
    if (unit == baseUnit) return 1;
    var f = 1.0;
    for (final l in levels) {
      f *= (l['quantity'] as num).toDouble();
      if (l['unit_name'] == unit) return f;
    }
    return 1;
  }

  /// كلفة [unit] = كلفة الأصغر × عدد ما فيها.
  double costOf(String unit) => baseCost * factorOf(unit);

  /// «كرتون = 10 باكيت • باكيت = 10 قطعة».
  String describe() {
    if (levels.isEmpty) return '«$baseUnit» أصغر وحدة';
    final names = units;
    return [
      for (var i = levels.length - 1; i >= 0; i--)
        '${names[i + 1]} = ${_n((levels[i]['quantity'] as num).toDouble())} ${names[i]}',
    ].join(' • ');
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
