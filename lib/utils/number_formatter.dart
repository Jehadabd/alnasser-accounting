import 'package:intl/intl.dart';

/// تنسيق الأرقام بشكل موحد في التطبيق
class NumberFormatter {
  /// تنسيق الرقم مع إضافة فواصل للآلاف
  /// إذا كان [forceDecimal] صحيحاً، سيتم إظهار الكسور دائماً
  static String format(num value, {bool forceDecimal = false}) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  /// تنسيق معرف المنتج - إظهار القيمة الأصلية بدون أصفار في البداية
  static String formatProductId(int? id) {
    if (id == null) return '';
    return id.toString();
  }

  /// تنسيق معرف المنتج مع إضافة أصفار في البداية (5 خانات)
  static String formatProductIdPadded(int? id) {
    if (id == null) return '-----';
    return id.toString().padLeft(5, '0');
  }
}