// lib/screens/purchase_new_item_spec.dart
//
// 🆕 تعريف مادة جديدة من سطرها في فاتورة الشراء (السطر الأزرق «مادة جديدة»)
// عند «تأكيد واستلام» أو «حفظ» — بلا فتح بطاقة المادة.
//
// ما يُؤخذ من السطر نفسه (كما راجعه المستخدم):
//   • الاسم
//   • الوحدة الأصغر: وحدة السطر إن كانت تعبئتها 1 (المستخدم اختارها أصغر وحدة)؛
//     وإن كانت أكبر (كرتون × 24) ⇒ الأصغر «قطعة» والكرتون فوقها بـ 24
//     (أو وحدات المراجعة كما عرّفها إن وُجدت)
//   • كلفة الوحدة الأصغر = سعر السطر ÷ التعبئة (بالدينار)
//   • له صلاحية إن كُتبت صلاحية للسطر
// الكمية تدخل المخزون مع الفاتورة نفسها (الرصيد الأول 0)، وسعر البيع من «تسعير سريع»
// أو خانة سعر المفرد يُحفظ بعد نجاح الفاتورة بمساره المعتاد مع سجله.

import 'dart:convert';

import '../models/product.dart';
import '../owner/ai_invoice/ai_purchase_prefill.dart' show AiUnitPlan;

class PurchaseNewItemSpec {
  PurchaseNewItemSpec._();

  static const String piece = 'قطعة';

  /// الوحدة الأصغر ومستويات التعبئة فوقها (كل مستوى نسبةً للذي قبله — صيغة unit_hierarchy).
  /// null = لا يمكن التعريف التلقائي (وحدة السطر هي «قطعة» وتعبئتها أكبر من 1: متناقض).
  static ({String baseUnit, List<Map<String, dynamic>> levels})? units(String unitName, double factor,
      {AiUnitPlan? plan}) {
    final u = unitName.trim().isEmpty ? piece : unitName.trim();
    if (plan != null && plan.units.contains(u)) {
      return (baseUnit: plan.baseUnit, levels: [for (final l in plan.levels) Map<String, dynamic>.from(l)]);
    }
    if (factor <= 1.0001) return (baseUnit: u, levels: const <Map<String, dynamic>>[]);
    if (u == piece) return null;
    return (
      baseUnit: piece,
      levels: <Map<String, dynamic>>[
        {'unit_name': u, 'quantity': factor},
      ],
    );
  }

  /// اسم الوحدة الأساسية كما يُخزَّن في المادة (قطعة ⇒ piece، متر ⇒ meter).
  static String storedUnit(String baseUnit) => baseUnit == piece ? 'piece' : (baseUnit == 'متر' ? 'meter' : baseUnit);

  /// المادة الجديدة من سطرها. null = لا يمكن تعريفها تلقائياً (انظر [units]).
  static Product? build({
    required String name,
    required String unitName,
    required double factor,
    required double baseCostIqd,
    String? expiryDate,
    AiUnitPlan? plan,
    DateTime? now,
  }) {
    final n = name.trim();
    if (n.isEmpty) return null;
    final u = units(unitName, factor, plan: plan);
    if (u == null) return null;
    final at = now ?? DateTime.now();
    return Product(
      name: n,
      unit: storedUnit(u.baseUnit),
      unitPrice: 0,
      price1: 0, // سعر البيع يُكتب بعد نجاح الفاتورة (PriceTools) — لا قبلها
      costPrice: baseCostIqd > 0 ? baseCostIqd : null,
      unitHierarchy: jsonEncode(u.levels),
      hasExpiry: (expiryDate ?? '').trim().isNotEmpty,
      alertUnit: u.baseUnit,
      stockQuantity: 0, // الكمية تدخل مع الفاتورة نفسها
      createdAt: at,
      lastModifiedAt: at,
    );
  }
}
