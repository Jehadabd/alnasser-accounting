// lib/screens/pos/widgets/pos_style.dart
//
// 🎨 ألوان ومقاسات شاشة الكاشير في مكان واحد — هادئة ومريحة للعين،
// وبنفس الكحلي المستعمل في شاشة إنشاء الفاتورة.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PosColors {
  PosColors._();

  static const bg = Color(0xFFF3F5F9);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF8FAFC);
  static const border = Color(0xFFE3E8EF);
  static const text = Color(0xFF1E293B);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);

  /// كحلي — نفس لون شاشة الفاتورة
  static const primary = Color(0xFF0F3460);
  static const accent = Color(0xFF2563EB);
  static const accentSoft = Color(0xFFEFF4FF);

  static const cash = Color(0xFF16A34A);
  static const credit = Color(0xFFEA580C);
  static const danger = Color(0xFFDC2626);
  static const warn = Color(0xFFD97706);

  static const _tints = <Color>[
    Color(0xFF2563EB),
    Color(0xFF0D9488),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFF65A30D),
    Color(0xFF9333EA),
  ];

  /// لون ثابت هادئ لكل قسم أو مادة
  static Color tint(int? id) => _tints[(id ?? 0).abs() % _tints.length];
}

/// نقاط التحوّل في التخطيط
class PosBreakpoints {
  PosBreakpoints._();

  /// أقسام عمودية + مواد + سلة
  static const double wide = 1150;

  /// مواد (مع شريط أقسام أفقي) + سلة
  static const double medium = 760;
}

final NumberFormat _money = NumberFormat('#,##0.##', 'en');
final NumberFormat _qty = NumberFormat('#,##0.###', 'en');

String posMoney(num v) => _money.format(v);
String posQty(num v) => _qty.format(v);
