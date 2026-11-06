// lib/services/receipt_paper.dart
//
// 🧻 عرض ورق الطابعة الحرارية لهذا الجهاز (لكل «مقعد» كالطابعة نفسها): 80 أو 58 ملم.
// يُطبَّق على إيصال الكاشير الأصلي وعلى «فاتورة البيع — الطابعة الحرارية».
//   80 ملم ← مساحة طباعة فعلية ~72 ملم (الحجم الأصلي للتصميم).
//   58 ملم ← مساحة طباعة فعلية ~48 ملم، والخطوط والأعمدة تصغر بنسبة ثابتة لتتسع.
// (التصاميم من «مصمم الفاتورة» تحمل عرضها بنفسها.)

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seat_service.dart';

class ReceiptPaper {
  ReceiptPaper._();

  static String get _key => SeatService.key('pos_receipt_paper_mm');

  /// القيمة الحالية (80 افتراضياً).
  static final ValueNotifier<int> current = ValueNotifier<int>(80);

  static Future<int> get() async {
    try {
      final v = (await SharedPreferences.getInstance()).getInt(_key);
      current.value = v == 58 ? 58 : 80;
    } catch (_) {}
    return current.value;
  }

  static Future<void> set(int mm) async {
    final v = mm == 58 ? 58 : 80;
    current.value = v;
    try {
      await (await SharedPreferences.getInstance()).setInt(_key, v);
    } catch (_) {}
  }

  /// مساحة الطباعة الفعلية بالملّيمتر.
  static double printableMm(int mm) => mm == 58 ? 48 : 72;

  /// معامل تصغير الخطوط والأعمدة مقارنةً بتصميم 80 ملم.
  static double scale(int mm) => mm == 58 ? 0.78 : 1.0;
}
