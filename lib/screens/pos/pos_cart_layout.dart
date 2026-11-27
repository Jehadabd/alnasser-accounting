// lib/screens/pos/pos_cart_layout.dart
//
// 🧩 تخطيط سلة الكاشير جدولاً مصغّراً (مثل جدول «إنشاء فاتورة»):
//   • الأعمدة الظاهرة يختارها المستخدم، وعرض كل عمود بالسحب من حافة رأسه
//   • «اسم المادة» يتّسع ليملأ الباقي؛ وإن زادت الأعمدة عن عرض السلة يظهر تمرير أفقي
//   • ارتفاع السطر (مضغوط/عادي/واسع)
//   • عرض مساحة السلة نفسها (يُسحب الفاصل بين المواد والسلة) — شبكة المواد تعيد
//     ترتيب أعمدتها تلقائياً حسب المساحة الباقية
// إعداد عرض فقط لهذا الجهاز — لا يغيّر أي بيانات.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PosCartLayout {
  PosCartLayout({
    Map<String, double>? widths,
    Set<String>? hidden,
    this.rowHeight = 44,
    this.cartWidth,
  })  : widths = {...defaultWidths, ...?widths},
        hidden = hidden ?? {...defaultHidden};

  static const String _prefsKey = 'pos_cart_layout_v1';

  /// ترتيب الأعمدة كما تظهر (من اليمين)
  static const List<String> keys = ['index', 'name', 'unit', 'price', 'qty', 'total', 'stock', 'barcode'];

  static const Map<String, String> labels = {
    'index': 'ت (رقم السطر)',
    'name': 'اسم المادة',
    'unit': 'الوحدة',
    'price': 'السعر',
    'qty': 'الكمية',
    'total': 'الإجمالي',
    'stock': 'الرصيد في المخزن',
    'barcode': 'الباركود',
  };

  static const Map<String, String> headers = {
    'index': 'ت',
    'name': 'المادة',
    'unit': 'الوحدة',
    'price': 'السعر',
    'qty': 'الكمية',
    'total': 'الإجمالي',
    'stock': 'الرصيد',
    'barcode': 'الباركود',
  };

  /// العرض الافتراضي بالبكسل
  static const Map<String, double> defaultWidths = {
    'index': 34,
    'name': 150,
    'unit': 86,
    'price': 92,
    'qty': 104,
    'total': 96,
    'stock': 72,
    'barcode': 118,
  };

  /// أصغر عرض لكل عمود (الكمية تحتاج زرّي − و +)
  static const Map<String, double> minWidths = {
    'index': 26,
    'name': 90,
    'unit': 56,
    'price': 64,
    'qty': 92,
    'total': 64,
    'stock': 50,
    'barcode': 70,
  };

  static const double maxWidth = 420;

  /// المخفية افتراضياً
  static const Set<String> defaultHidden = {'stock', 'barcode'};

  /// أعمدة ضرورية للبيع (لا تُخفى)
  static const Set<String> required = {'name', 'price', 'qty', 'total'};

  /// ارتفاعات السطر المتاحة (final لا const: مفاتيح double لا تصلح في خريطة ثابتة)
  static final Map<double, String> rowHeights = {38: 'سطر مضغوط', 44: 'سطر عادي', 52: 'سطر واسع'};

  /// عرض مساحة السلة: الحدود
  static const double minCartWidth = 320;
  static const double minProductsWidth = 300;

  final Map<String, double> widths;
  final Set<String> hidden;
  final double rowHeight;

  /// عرض مساحة السلة بالبكسل (null = الافتراضي حسب الشاشة)
  final double? cartWidth;

  double w(String key) =>
      (widths[key] ?? defaultWidths[key] ?? 80).clamp(minWidths[key] ?? 30, maxWidth).toDouble();

  bool show(String key) => !hidden.contains(key) || required.contains(key);

  List<String> get visibleKeys => [for (final k in keys) if (show(k)) k];

  /// عرض كل عمود بعد التوزيع: إن كان المجموع أقل من [available] يتّسع «اسم المادة»
  /// ليملأ الباقي؛ وإن زاد ينكمش «اسم المادة» أولاً حتى أقل عرض له (فيبقى الإجمالي
  /// ظاهراً)، وبعدها فقط يظهر التمرير الأفقي.
  Map<String, double> resolve(double available) {
    final out = {for (final k in visibleKeys) k: w(k)};
    final sum = out.values.fold<double>(0, (a, b) => a + b);
    final name = out['name'];
    if (name == null) return out;
    if (sum < available) {
      out['name'] = name + (available - sum);
    } else if (sum > available) {
      final minName = minWidths['name'] ?? 90;
      final shrunk = name - (sum - available);
      out['name'] = shrunk < minName ? (name < minName ? name : minName) : shrunk;
    }
    return out;
  }

  /// عرض السلة الفعلي ضمن [total] (عرض المساحة كلها) بعد طرح [reserved] (شريط الأقسام).
  double resolveCartWidth(double total, {required double fallback, double reserved = 0}) {
    final maxW = total - reserved - minProductsWidth;
    final hi = maxW < minCartWidth ? minCartWidth : maxW;
    return (cartWidth ?? fallback).clamp(minCartWidth, hi).toDouble();
  }

  PosCartLayout copyWith({
    Map<String, double>? widths,
    Set<String>? hidden,
    double? rowHeight,
    double? cartWidth,
    bool resetCartWidth = false,
  }) =>
      PosCartLayout(
        widths: widths ?? this.widths,
        hidden: hidden ?? this.hidden,
        rowHeight: rowHeight ?? this.rowHeight,
        cartWidth: resetCartWidth ? null : (cartWidth ?? this.cartWidth),
      );

  /// التخطيط الحالي (يُحمَّل عند فتح الكاشير)
  static PosCartLayout current = PosCartLayout();

  static Future<PosCartLayout> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) current = fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      current = PosCartLayout();
    }
    return current;
  }

  static PosCartLayout fromJson(Map<String, dynamic> m) {
    final cw = (m['cartWidth'] as num?)?.toDouble();
    return PosCartLayout(
      widths: {
        for (final e in ((m['widths'] as Map?) ?? const {}).entries)
          if (e.value is num) '${e.key}': (e.value as num).toDouble(),
      },
      hidden: {for (final h in ((m['hidden'] as List?) ?? const [])) '$h'},
      rowHeight: ((m['rowHeight'] as num?) ?? 44).toDouble().clamp(34, 60).toDouble(),
      cartWidth: cw != null && cw > 0 ? cw : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'widths': widths,
        'hidden': hidden.toList(),
        'rowHeight': rowHeight,
        if (cartWidth != null) 'cartWidth': cartWidth,
      };

  Future<void> save() async {
    current = this;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(toJson()));
    } catch (_) {}
  }
}
