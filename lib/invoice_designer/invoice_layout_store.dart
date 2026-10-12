// lib/invoice_designer/invoice_layout_store.dart
//
// 💾 حفظ تصاميم الفاتورة في قاعدة البيانات (جدول الإعدادات المحاسبية)، فتراها
// كل الأجهزة على الشبكة المحلية وتدخل في النسخ الاحتياطي. ولكل نوع طباعة
// تصميمه المختار (أو «التصميم الأصلي للبرنامج»).

import 'dart:convert';

import '../accounting/ledger.dart';
import '../erp/erp_common.dart';
import 'invoice_layout.dart';

/// أنواع الطباعة التي يمكن ربط تصميم بها
class PrintTarget {
  const PrintTarget(this.key, this.label, this.hint, this.roll);
  final String key;
  final String label;
  final String hint;

  /// يقبل تصاميم الإيصال (80/58) لا A4
  final bool roll;

  static const invoiceA4 = PrintTarget('invoice_a4', 'فاتورة البيع — A4 (الجملة / الكبيرة)',
      'طباعة ومشاركة الفاتورة من شاشة إنشاء الفاتورة على ورق A4', false);
  static const invoiceRoll = PrintTarget('invoice_roll', 'فاتورة البيع — الطابعة الحرارية',
      'حين يكون نوع طباعة الفاتورة «حرارية» في إعدادات الطباعة', true);
  static const posReceipt = PrintTarget('pos_receipt', 'إيصال الكاشير — نقطة البيع',
      'الإيصال الذي يُطبع من شاشة نقطة البيع (الكاشير)', true);

  static const all = [invoiceA4, invoiceRoll, posReceipt];

  bool accepts(InvoiceLayout l) => roll ? l.paper.isRoll : l.paper == LayoutPaper.a4;
}

class InvoiceLayoutStore {
  InvoiceLayoutStore._();

  static const _kLayouts = 'invoice_layouts_v1';
  static String _kTarget(String t) => 'invoice_layout_target_$t';

  static Future<List<InvoiceLayout>> loadAll() async {
    try {
      final db = await erpDb();
      final raw = await Ledger.getSetting(db, _kLayouts);
      if (raw == null || raw.isEmpty) return <InvoiceLayout>[];
      final list = jsonDecode(raw);
      if (list is! List) return <InvoiceLayout>[];
      return list
          .whereType<Map>()
          .map((m) => InvoiceLayout.fromJson(Map<String, dynamic>.from(m)))
          .where((l) => l.id.isNotEmpty)
          .toList();
    } catch (_) {
      return <InvoiceLayout>[];
    }
  }

  static Future<void> saveAll(List<InvoiceLayout> layouts) async {
    final db = await erpDb();
    await Ledger.setSetting(db, _kLayouts, jsonEncode(layouts.map((l) => l.toJson()).toList()));
  }

  /// معرّف التصميم المربوط بنوع الطباعة ('' = التصميم الأصلي للبرنامج)
  static Future<String> target(String key) async {
    try {
      final db = await erpDb();
      return (await Ledger.getSetting(db, _kTarget(key))) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> setTarget(String key, String layoutId) async {
    final db = await erpDb();
    await Ledger.setSetting(db, _kTarget(key), layoutId);
  }

  /// التصميم المستعمل لهذا النوع من الطباعة، أو null ⇒ التصميم الأصلي للبرنامج
  static Future<InvoiceLayout?> activeFor(String targetKey) async {
    try {
      final id = await target(targetKey);
      if (id.isEmpty) return null;
      final t = PrintTarget.all.firstWhere((x) => x.key == targetKey, orElse: () => PrintTarget.invoiceA4);
      for (final l in await loadAll()) {
        if (l.id == id && t.accepts(l)) return l;
      }
    } catch (_) {}
    return null;
  }
}
