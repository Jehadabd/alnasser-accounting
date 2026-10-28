// lib/models/invoice_entry_layout.dart
//
// 🧩 تخطيط جدول «إنشاء فاتورة» على طريقة الإداري: شبكة مضغوطة، أي عدد من
// الأعمدة، عرض كل عمود بالبكسل، وتمرير أفقي إذا زادت الأعمدة عن عرض الشاشة.
// يضبطه المستخدم من: الإعدادات ← الفاتورة والطباعة ← «أعمدة شاشة إنشاء الفاتورة».
// ومعه ترتيب تنقل زر Enter بين خانات السطر.
// إعداد عرض فقط لهذا الجهاز — لا يغيّر أي بيانات.

import 'dart:convert';

import 'package:flutter/material.dart' show Color, BorderSide;
import 'package:shared_preferences/shared_preferences.dart';

class InvoiceEntryLayout {
  InvoiceEntryLayout({
    Map<String, double>? widths,
    Set<String>? hidden,
    this.rowHeight = 34,
    this.showEntryBar = true,
    List<String>? enterOrder,
    this.discountTypedAsPercent = true,
    this.gridLineWidth = 1.0,
    this.gridLineDarkness = 0,
  })  : widths = {...defaultWidths, ...?widths},
        hidden = hidden ?? {...defaultHidden},
        enterOrder = cleanEnterOrder(enterOrder ?? defaultEnterOrder);

  static const String _prefsKey = 'invoice_entry_layout_v2';

  /// ترتيب الأعمدة كما تظهر (من اليمين)
  static const List<String> keys = [
    'index', 'code', 'itemCode', 'barcode', 'details', 'qty', 'saleType', 'price', 'listPrice', 'discount', 'units', 'total',
    'stock', 'cost', 'profit',
  ];

  static const Map<String, String> labels = {
    'index': 'ت (رقم السطر)',
    'code': 'المعرّف الداخلي ID (للعرض فقط)',
    'itemCode': 'رمز المادة (يُكتب فيه للبحث)',
    'barcode': 'الباركود (يُكتب فيه للبحث)',
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
    'code': 'ID',
    'itemCode': 'رمز المادة',
    'barcode': 'الباركود',
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
    'itemCode': 96,
    'barcode': 128,
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
  static const Set<String> defaultHidden = {'code', 'itemCode', 'barcode', 'listPrice', 'stock', 'cost', 'profit'};

  /// أعمدة أُضيفت بعد أن حفظ المستخدمون تخطيطهم: تبقى مخفية عندهم حتى يُظهروها
  static const Set<String> addedLater = {'itemCode', 'barcode'};

  /// أعمدة ضرورية لإدخال السطر (لا تُخفى)
  static const Set<String> required = {'details', 'qty', 'saleType', 'price', 'total'};

  /// أعمدة تحتاج صلاحية رؤية الكلفة والأرباح
  static const Set<String> costColumns = {'cost', 'profit'};

  /// 🧭 الخانات التي يمكن أن يقف عندها زر Enter بعد «اسم المادة» (الأعمدة القابلة
  /// للكتابة فقط؛ الإجمالي والرصيد والكلفة للعرض ولا يُكتب فيها)
  static const List<String> enterStopKeys = ['qty', 'saleType', 'price', 'discount'];

  /// الترتيب الافتراضي = السلوك القديم: الكمية ← الوحدة ← السعر ← السطر التالي
  static const List<String> defaultEnterOrder = ['qty', 'saleType', 'price'];

  /// يُبقي الخانات المعروفة فقط بلا تكرار وبالترتيب المعطى
  static List<String> cleanEnterOrder(Iterable<String> order) {
    final out = <String>[];
    for (final k in order) {
      if (enterStopKeys.contains(k) && !out.contains(k)) out.add(k);
    }
    return List.unmodifiable(out);
  }

  static const double minWidth = 30;
  static const double maxWidth = 500;

  final Map<String, double> widths;
  final Set<String> hidden;

  /// ارتفاع السطر بالبكسل (مضغوط 30، عادي 34، واسع 42)
  final double rowHeight;

  /// شريط الإدخال الأخضر فوق الجدول (بدونه يُكتب مباشرة في آخر سطر من الجدول كما في الإداري)
  final bool showEntryBar;

  /// 🧭 ترتيب الخانات التي يمر عليها Enter بعد «اسم المادة»؛ الخانة غير الموجودة هنا
  /// يتخطاها Enter (الكمية تبقى 1، الوحدة الأساسية، السعر المقترح، بلا خصم)
  final List<String> enterOrder;

  /// الرقم المكتوب في خانة الخصم بالجدول: نسبة % (true) أو مبلغ من سعر الوحدة (false).
  /// كتابة % بعد الرقم تجعله نسبة دائماً.
  final bool discountTypedAsPercent;

  /// ▦ خطوط الجدول بين الأسطر والأعمدة: السماكة (1–3 بكسل) ودرجة اللون
  /// (0 = رمادي فاتح كما كان، 100 = أسود)
  final double gridLineWidth;
  final int gridLineDarkness;

  static const Color _gridLight = Color(0xFFE2E8F0);
  Color get gridColor => Color.lerp(_gridLight, const Color(0xFF000000), gridLineDarkness / 100.0)!;
  BorderSide get gridSide => BorderSide(color: gridColor, width: gridLineWidth);

  /// مسار Enter الفعلي في سطر الجدول: «اسم المادة» أولاً ثم الخانات الظاهرة حسب الترتيب
  List<String> enterStops(Iterable<String> visibleColumns) {
    final shown = visibleColumns.toSet();
    return ['details', for (final k in enterOrder) if (shown.contains(k)) k];
  }

  double w(String key) => (widths[key] ?? defaultWidths[key] ?? 80).clamp(minWidth, maxWidth).toDouble();
  bool show(String key) => !hidden.contains(key) || required.contains(key);

  /// الأعمدة الظاهرة فعلاً في هذه الشاشة
  /// [force]: أعمدة تُظهَر مؤقتاً ولو كانت مخفية أو بلا صلاحية (Ctrl+D لحساب المالك)
  List<String> visibleKeys({required bool isViewOnly, required bool canSeeCost, Set<String> force = const {}}) => [
        for (final k in keys)
          if ((show(k) || force.contains(k)) &&
              !(k == 'units' && isViewOnly) &&
              (canSeeCost || force.contains(k) || !costColumns.contains(k)))
            k,
      ];

  /// عرض كل عمود بعد التوزيع: إن كان مجموع الأعمدة أقل من عرض الشاشة يتّسع
  /// «اسم المادة» ليملأ الباقي؛ وإن زاد يبقى كما هو ويظهر شريط تمرير أفقي.
  Map<String, double> resolve(double available,
      {required bool isViewOnly, required bool canSeeCost, Set<String> force = const {}}) {
    final ks = visibleKeys(isViewOnly: isViewOnly, canSeeCost: canSeeCost, force: force);
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
    List<String>? enterOrder,
    bool? discountTypedAsPercent,
    double? gridLineWidth,
    int? gridLineDarkness,
  }) =>
      InvoiceEntryLayout(
        widths: widths ?? this.widths,
        hidden: hidden ?? this.hidden,
        rowHeight: rowHeight ?? this.rowHeight,
        showEntryBar: showEntryBar ?? this.showEntryBar,
        enterOrder: enterOrder ?? this.enterOrder,
        discountTypedAsPercent: discountTypedAsPercent ?? this.discountTypedAsPercent,
        gridLineWidth: gridLineWidth ?? this.gridLineWidth,
        gridLineDarkness: gridLineDarkness ?? this.gridLineDarkness,
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
          hidden: {
            for (final h in ((m['hidden'] as List?) ?? const [])) '$h',
            // عمود جديد لم يكن موجوداً عند حفظ التخطيط ⇒ مخفي (لا يظهر فجأة)
            for (final k in addedLater)
              if (!((m['known'] as List?) ?? const []).contains(k)) k,
          },
          rowHeight: ((m['rowHeight'] as num?) ?? 34).toDouble().clamp(26, 56).toDouble(),
          showEntryBar: (m['showEntryBar'] as bool?) ?? true,
          // غير موجود في الإعدادات القديمة ⇒ الترتيب الافتراضي (نفس السلوك السابق)
          enterOrder: m['enterOrder'] is List ? [for (final k in m['enterOrder'] as List) '$k'] : null,
          discountTypedAsPercent: (m['discountTypedAsPercent'] as bool?) ?? true,
          gridLineWidth: ((m['gridLineWidth'] as num?) ?? 1).toDouble().clamp(0.5, 3).toDouble(),
          gridLineDarkness: ((m['gridLineDarkness'] as num?) ?? 0).toInt().clamp(0, 100).toInt(),
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
        'known': keys,
        'rowHeight': rowHeight,
        'showEntryBar': showEntryBar,
        'enterOrder': enterOrder,
        'discountTypedAsPercent': discountTypedAsPercent,
        'gridLineWidth': gridLineWidth,
        'gridLineDarkness': gridLineDarkness,
      }),
    );
  }
}
