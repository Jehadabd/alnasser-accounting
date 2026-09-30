// lib/models/invoice_entry_layout.dart
//
// 🧩 تخطيط جدول «إنشاء فاتورة»: أي الأعمدة تظهر وعرض كل عمود.
// يضبطه المستخدم من: الإعدادات ← الفاتورة والطباعة ← «أعمدة شاشة إنشاء الفاتورة».
// إعداد عرض فقط لهذا الجهاز — لا يغيّر أي بيانات.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class InvoiceEntryLayout {
  InvoiceEntryLayout({Map<String, int>? flex, Set<String>? hidden})
      : flex = {...defaultFlex, ...?flex},
        hidden = {...?hidden};

  static const String _prefsKey = 'invoice_entry_layout_v1';

  /// ترتيب الأعمدة كما تظهر (من اليمين)
  static const List<String> keys = ['index', 'details', 'qty', 'saleType', 'price', 'discount', 'units', 'total'];

  static const Map<String, String> labels = {
    'index': 'ت (رقم السطر)',
    'details': 'التفاصيل (اسم المادة)',
    'qty': 'العدد',
    'saleType': 'نوع البيع',
    'price': 'السعر',
    'discount': 'الخصم / الهدية',
    'units': 'عدد الوحدات',
    'total': 'الإجمالي',
  };

  static const Map<String, String> headers = {
    'index': 'ت',
    'details': 'التفاصيل',
    'qty': 'العدد',
    'saleType': 'نوع',
    'price': 'السعر',
    'discount': 'الخصم',
    'units': 'وحدة',
    'total': 'الإجمالي',
  };

  static const Map<String, int> defaultFlex = {
    'index': 1,
    'details': 7,
    'qty': 2,
    'saleType': 2,
    'price': 2,
    'discount': 2,
    'units': 2,
    'total': 2,
  };

  /// أعمدة يمكن إخفاؤها (البقية ضرورية لإدخال السطر)
  static const Set<String> hideable = {'index', 'discount', 'units'};

  final Map<String, int> flex;
  final Set<String> hidden;

  int f(String key) => (flex[key] ?? defaultFlex[key] ?? 2).clamp(1, 12);
  bool show(String key) => !hidden.contains(key);

  /// التخطيط الحالي (يُحمَّل عند فتح شاشة الفاتورة)
  static InvoiceEntryLayout current = InvoiceEntryLayout();

  static Future<InvoiceEntryLayout> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        current = InvoiceEntryLayout(
          flex: {for (final e in ((m['flex'] as Map?) ?? {}).entries) '${e.key}': (e.value as num).toInt()},
          hidden: {for (final h in ((m['hidden'] as List?) ?? const [])) '$h'}..retainAll(hideable),
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
    await prefs.setString(_prefsKey, jsonEncode({'flex': flex, 'hidden': hidden.toList()}));
  }
}
