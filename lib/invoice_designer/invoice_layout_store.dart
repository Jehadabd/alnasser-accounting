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
  const PrintTarget(this.key, this.label, this.hint, this.roll, {this.kind = 'invoice'});
  final String key;
  final String label;
  final String hint;

  /// نوع التصاميم التي يقبلها ('invoice' أو نوع سند)
  final String kind;

  /// يقبل تصاميم الإيصال (80/58) لا A4
  final bool roll;

  static const invoiceA4 = PrintTarget('invoice_a4', 'فاتورة البيع — A4 (الجملة / الكبيرة)',
      'طباعة ومشاركة الفاتورة من شاشة إنشاء الفاتورة على ورق A4', false);
  static const invoiceRoll = PrintTarget('invoice_roll', 'فاتورة البيع — الطابعة الحرارية',
      'حين يكون نوع طباعة الفاتورة «حرارية» في إعدادات الطباعة', true);
  static const posReceipt = PrintTarget('pos_receipt', 'إيصال الكاشير — نقطة البيع',
      'الإيصال الذي يُطبع من شاشة نقطة البيع (الكاشير)', true);

  static const adjustmentVoucher = PrintTarget('adjustment_voucher', 'إشعار مدين / دائن — A4',
      'السند الذي يُطبع بعد إضافة أو إرجاع على فاتورة محفوظة', false);

  static const all = [invoiceA4, invoiceRoll, posReceipt, adjustmentVoucher];

  // 🧾 مصمم السندات — لكل نوع سند نوع طباعة (ورق A4)
  static const vReceipt = PrintTarget('voucher_receipt', 'سند قبض — تسديد دين',
      'بعد تسديد دين من سجل الديون، ووصل القبض لعدة عملاء', false, kind: 'receipt');
  static const vCashReceipt = PrintTarget('voucher_cash_receipt', 'سند قبض — إضافة على فاتورة نقدية',
      'تعديل فاتورة نقدية بالقلم وزاد مجموعها', false, kind: 'cash_receipt');
  static const vCashRefund = PrintTarget('voucher_cash_refund', 'سند صرف — مرتجع من فاتورة نقدية',
      'تعديل فاتورة نقدية بالقلم ونقص مجموعها', false, kind: 'cash_refund');
  static const vDebitNote = PrintTarget('voucher_debit_note', 'إشعار مدين — إضافة على فاتورة آجلة',
      'تعديل فاتورة آجلة بالقلم وزاد مجموعها', false, kind: 'debit_note');
  static const vCreditNote = PrintTarget('voucher_credit_note', 'إشعار دائن — مرتجع من فاتورة آجلة',
      'تعديل فاتورة آجلة بالقلم ونقص مجموعها', false, kind: 'credit_note');
  static const vouchers = [vReceipt, vCashReceipt, vCashRefund, vDebitNote, vCreditNote];
  static const everything = [...all, ...vouchers];

  /// أنواع الطباعة لمصمم نوع مستند واحد
  static List<PrintTarget> forKind(String kind) =>
      kind == 'invoice' ? all : [for (final t in vouchers) if (t.kind == kind) t];

  bool accepts(InvoiceLayout l) => l.kind == kind && (roll ? l.paper.isRoll : l.paper == LayoutPaper.a4);
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
      final layouts = list
          .whereType<Map>()
          .map((m) => InvoiceLayout.fromJson(Map<String, dynamic>.from(m)))
          .where((l) => l.id.isNotEmpty)
          .toList();
      await _migrateQrInvoiceInfoOnce(layouts);
      return layouts;
    } catch (_) {
      return <InvoiceLayout>[];
    }
  }

  static const _kQrInfoMigrated = 'invoice_layouts_qr_info_v1';

  /// مرة واحدة: رمز QR في التصاميم المحفوظة كان يحمل رقم الفاتورة وحده (افتراضي
  /// النماذج) — صار يحمل كل بيانات الفاتورة (الرقم، التاريخ والوقت، السيد، الهاتف).
  /// الباركود العادي وما اختاره المستخدم غير رقم الفاتورة لا يُمسّ.
  static Future<void> _migrateQrInvoiceInfoOnce(List<InvoiceLayout> layouts) async {
    final db = await erpDb();
    if ((await Ledger.getSetting(db, _kQrInfoMigrated)) == '1') return;
    var changed = false;
    for (final l in layouts) {
      for (final e in l.elements) {
        if (e.type == ElType.barcode &&
            (e.props['kind'] ?? 'qr') == 'qr' &&
            (e.props['data'] ?? 'invoiceNo') == 'invoiceNo') {
          e.props['data'] = 'invoiceInfo';
          changed = true;
        }
      }
    }
    if (changed) await saveAll(layouts);
    await Ledger.setSetting(db, _kQrInfoMigrated, '1');
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
      final t = PrintTarget.everything.firstWhere((x) => x.key == targetKey, orElse: () => PrintTarget.invoiceA4);
      for (final l in await loadAll()) {
        if (l.id == id && t.accepts(l)) return l;
      }
    } catch (_) {}
    return null;
  }
}
