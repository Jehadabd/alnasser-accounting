// lib/services/internal_barcode.dart
// 🏷️ باركود داخلي للمواد التي لا باركود لها من المصنع.
//
// الصيغة: 10 أرقام تبدأ بـ 99 (مثل 9900000017) وتُطبع Code128.
// • لا تتعارض مع باركودات المصانع: EAN-13 و UPC-A و EAN-8 أطوالها 13 و12 و8.
// • لا تتعارض مع باركود الميزان: يبدأ ببادئة الميزان (2 افتراضياً) وطوله 13.
// • تسلسلية: التالي = أكبر رقم داخلي مستعمل + 1 (في المواد والباركودات الإضافية).

import 'database_service.dart';

class InternalBarcode {
  InternalBarcode._();

  static const String prefix = '99';
  static const int length = 10;
  static const String _glob = '99[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]';

  /// هل [code] باركود داخلي بهذه الصيغة؟
  static bool isInternal(String code) =>
      code.length == length && code.startsWith(prefix) && int.tryParse(code) != null;

  /// الباركود الداخلي التالي غير المستعمل.
  static Future<String> next() async {
    final db = await DatabaseService().database;
    var maxSeq = 0;
    Future<void> scan(String table) async {
      try {
        final r = await db.rawQuery('SELECT MAX(barcode) AS m FROM $table WHERE barcode GLOB ?', [_glob]);
        final m = r.first['m'] as String?;
        final seq = m == null ? null : int.tryParse(m.substring(prefix.length));
        if (seq != null && seq > maxSeq) maxSeq = seq;
      } catch (_) {
        // جدول الباركودات الإضافية قد لا يوجد في نسخ قديمة
      }
    }

    await scan('products');
    await scan('product_barcodes');
    return '$prefix${(maxSeq + 1).toString().padLeft(length - prefix.length, '0')}';
  }
}
