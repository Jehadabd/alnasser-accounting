// lib/models/invoice_entry_layout.dart
//
// 🧩 تخطيط جدول «إنشاء فاتورة» على طريقة الإداري: شبكة مضغوطة، أي عدد من
// الأعمدة، عرض كل عمود بالبكسل، وتمرير أفقي إذا زادت الأعمدة عن عرض الشاشة.
// يضبطه المستخدم من: الإعدادات ← الفاتورة والطباعة ← «أعمدة شاشة إنشاء الفاتورة».
// إعداد عرض فقط لهذا الجهاز — لا يغيّر أي بيانات.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class InvoiceEntryLayout {
  InvoiceEntryLayout({
    Map<String, double>? widths,
    Set<String>? hidden,
    this.rowHeight = 34,
    this.showEntryBar = true,
  })  : widths = {...defaultWidths, ...?widths},
        hidden = hidden ?? {...defaultHidden};

  static const String _prefsKey = 'invoice_entry_layout_v2';

  /// ترتيب الأعمدة كما تظهر (من اليمين)
  static const List<String> keys = [
    'index', 'code', 'details', 'qty', 'saleType', 'price', 'listPrice', 'discount', 'units', 'total',
    'stock', 'cost', 'profit',
  ];

  static const Map<String, String> labels = {
    'index': 'ت (رقم السطر)',
    'code': 'رقم المادة',
    'details': 'اسم المادة',
    'qty': 'الكمية',
    'saleType': 'الوحدة',
    'price': 'السعر (الصافي)',
    'listPrice': 'السعر قبل الخصم',
    'discount': 'الخصم / الهدية',
    'units': 'عدد القطع في الوحدة',
    'total': 'الإجمالي',
    'stock': 'الرصيد في المخزن',
    'cost': 'الكلفة',
    'profit': 'الربح',
  };

  static const Map<String, String> headers = {
    'index': 'ت',
    'code': 'رقم',
    'details': 'اسم المادة',
    'qty': 'الكمية',
    'saleType': 'الوحدة',
    'price': 'السعر',
    'listPrice': 'قبل الخصم',
    'discount': 'الخصم',
    'units': 'قطع',
    'total': 'الإجمالي',
    'stock': 'الرصيد',
    'cost': 'الكلفة',
    'profit': 'الربح',
  };

  /// العرض الافتراضي بالبكسل
  static const Map<String, double> defaultWidths = {
    'index': 36,
    'code': 64,
    'details': 260,
    'qty': 80,
    'saleType': 92,
    'price': 104,
    'listPrice': 100,
    'discount': 80,
    'units': 56,
    'total': 120,
    'stock': 80,
    'cost': 96,
    'profit': 96,
  };

  /// المخفية افتراضياً (يظهرها المستخدم من الإعدادات)
  static const Set<String> defaultHidden = {'code', 'listPrice', 'stock', 'cost', 'profit'};

  /// أعمدة ضرورية لإدخال السطر (لا تُخفى)
  static const Set<String> required = {'details', 'qty', 'saleType', 'price', 'total'};

  /// أعمدة تحتاج صلاحية رؤية الكلفة والأرباح
  static const Set<String> costColumns = {'cost', 'profit'};

  static const double minWidth = 30;
  static const double maxWidth = 500;

  final Map<String, double> widths;
  final Set<String> hidden;

  /// ارتفاع السطر بالبكسل (مضغوط 30، عادي 34، واسع 42)
  final double rowHeight;

  /// شريط الإدخال الأخضر فوق الجدول (بدونه يُكتب مباشرة في آخر سطر من الجدول كما في الإداري)
  final bool showEntryBar;

  double w(String key) => (widths[key] ?? defaultWidths[key] ?? 80).clamp(minWidth, maxWidth).toDouble();
  bool show(String key) => !hidden.contains(key) || required.contains(key);

  /// الأعمدة الظاهرة فعلاً في هذه الشاشة
  List<String> visibleKeys({required bool isViewOnly, required bool canSeeCost}) => [
        for (final k in keys)
          if (show(k) && !(k == 'units' && isViewOnly) && (canSeeCost || !costColumns.contains(k))) k,
      ];

  /// عرض كل عمود بعد التوزيع: إن كان مجموع الأعمدة أقل من عرض الشاشة يتّسع
  /// «اسم المادة» ليملأ الباقي؛ وإن زاد يبقى كما هو ويظهر شريط تمرير أفقي.
  Map<String, double> resolve(double available, {required bool isViewOnly, required bool canSeeCost}) {
    final ks = visibleKeys(isViewOnly: isViewOnly, canSeeCost: canSeeCost);
    final out = {for (final k in ks) k: w(k)};
    final sum = out.values.fold<double>(0, (a, b) => a + b);
    if (sum < available && out.containsKey('details')) {
      out['details'] = out['details']! + (available - sum);
    }
    return out;
  }

  InvoiceEntryLayout copyWith({
    Map<String, double>? widths,
    Set<String>? hidden,
    double? rowHeight,
    bool? showEntryBar,
  }) =>
      InvoiceEntryLayout(
        widths: widths ?? this.widths,
        hidden: hidden ?? this.hidden,
        rowHeight: rowHeight ?? this.rowHeight,
        showEntryBar: showEntryBar ?? this.showEntryBar,
      );

  /// التخطيط الحالي (يُحمَّل عند فتح شاشة الفاتورة)
  static InvoiceEntryLayout current = InvoiceEntryLayout();

  static Future<InvoiceEntryLayout> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        current = InvoiceEntryLayout(
          widths: {
            for (final e in ((m['widths'] as Map?) ?? {}).entries) '${e.key}': (e.value as num).toDouble(),
          },
          hidden: {for (final h in ((m['hidden'] as List?) ?? const [])) '$h'},
          rowHeight: ((m['rowHeight'] as num?) ?? 34).toDouble().clamp(26, 56).toDouble(),
          showEntryBar: (m['showEntryBar'] as bool?) ?? true,
        );
      }
    } catch (_) {
      current = InvoiceEntryLayout();
    }
    return current;
  }

  Future<void> save() async {
    current = this;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'widths': widths,
        'hidden': hidden.toList(),
        'rowHeight': rowHeight,
        'showEntryBar': showEntryBar,
      }),
    );
  }
}
