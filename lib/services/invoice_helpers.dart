// services/invoice_helpers.dart
// جميع الدوال المساعدة الخاصة بالفواتير

import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/invoice_item.dart';
import '../models/product.dart';

String formatNumber(num value, {bool forceDecimal = false}) {
  if (forceDecimal) {
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }
  return value.toInt().toString();
}

String buildUnitConversionString(InvoiceItem item, List<Product> allProducts) {
  // المنتجات التي تباع بالامتار
  if (item.unit == 'meter') {
    if (item.saleType == 'لفة' && item.unitsInLargeUnit != null) {
      return item.unitsInLargeUnit!.toString();
    } else {
      return '';
    }
  }
  // المنتجات التي تباع بالقطعة ولها تسلسل هرمي
  final product = allProducts.firstWhere(
    (p) => p.name == item.productName,
    orElse: () => Product(
      id: null,
      name: item.productName,
      unit: item.unit,
      unitPrice: item.unitPrice,
      costPrice: null,
      piecesPerUnit: null,
      lengthPerUnit: null,
      price1: item.unitPrice,
      createdAt: DateTime.now(),
      lastModifiedAt: DateTime.now(),
    ),
  );
  if (product.unitHierarchy == null || product.unitHierarchy!.isEmpty) {
    return item.unitsInLargeUnit?.toString() ?? '';
  }
  try {
    final List<dynamic> hierarchy =
        json.decode(product.unitHierarchy!.replaceAll("'", '"'));
    // ابحث عن تسلسل التحويل للوحدة المختارة
    List<String> factors = [];
    for (int i = 0; i < hierarchy.length; i++) {
      final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
      final quantity = hierarchy[i]['quantity'];
      factors.add(quantity.toString());
      if (unitName == item.saleType) {
        break;
      }
    }
    if (factors.isEmpty) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
    return factors.join(' × ');
  } catch (e) {
    return item.unitsInLargeUnit?.toString() ?? '';
  }
}

// دالة مساعدة للتحقق من اكتمال صف الفاتورة
bool isInvoiceItemComplete(InvoiceItem item) {
  return (item.productName.isNotEmpty &&
      (item.quantityIndividual != null || item.quantityLargeUnit != null) &&
      item.appliedPrice > 0 &&
      item.itemTotal > 0 &&
      (item.saleType != null && item.saleType!.isNotEmpty));
}
