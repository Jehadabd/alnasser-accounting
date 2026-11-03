// lib/erp/purchases/purchase_price_history.dart
//
// 🏷️ سجل أسعار الشراء — قراءة فقط من فواتير الشراء المؤكدة:
//   • لكل مادة: آخر الأسعار من كل مورد (افتراضياً 3 لكل مورد).
//   • المقارنة بكلفة الوحدة الأساسية (سعر الوحدة ÷ معامل التحويل) — فشراء «كرتون»
//     يُقارن بشراء «قطعة» على أساس القطعة — وبالعملة نفسها فقط.
//   • تنبيه ارتفاع السعر عن آخر شراء من المورد نفسه بنسبة يحددها المستخدم
//     (إعداد على هذا الجهاز). لا يغيّر أي سعر ولا كلفة.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class PurchasePriceRow {
  PurchasePriceRow.fromRow(Map<String, Object?> r)
      : supplierId = (r['supplier_id'] as num?)?.toInt(),
        supplierName = '${r['supplier_name'] ?? ''}',
        date = DateTime.tryParse('${r['date'] ?? ''}'),
        invoiceNumber = '${r['invoice_number'] ?? ''}',
        unitName = '${r['unit_name'] ?? ''}',
        unitPrice = (r['unit_price'] as num?)?.toDouble() ?? 0,
        factor = ((r['conversion_factor'] as num?)?.toDouble() ?? 1) <= 0 ? 1 : (r['conversion_factor'] as num).toDouble(),
        currency = '${r['currency'] ?? 'IQD'}';

  final int? supplierId;
  final String supplierName;
  final DateTime? date;
  final String invoiceNumber;
  final String unitName;
  final double unitPrice;
  final double factor;
  final String currency;

  /// كلفة الوحدة الأساسية (قطعة/متر).
  double get baseCost => unitPrice / factor;
}

class PurchasePriceHistory {
  PurchasePriceHistory._();

  static const _kPct = 'purchase_price_alert_pct';
  static const double defaultAlertPct = 5;

  static Future<double> alertPct() async {
    try {
      final v = (await SharedPreferences.getInstance()).getDouble(_kPct);
      return (v == null || v.isNaN || v < 0) ? defaultAlertPct : v;
    } catch (_) {
      return defaultAlertPct;
    }
  }

  static Future<void> setAlertPct(double v) async =>
      (await SharedPreferences.getInstance()).setDouble(_kPct, v.clamp(0, 1000).toDouble());

  static const _select = '''
    SELECT pi.supplier_id, s.name AS supplier_name, pi.date, pi.invoice_number, pi.currency,
           it.unit_name, it.unit_price, it.conversion_factor
    FROM purchase_invoice_items it
    JOIN purchase_invoices pi ON pi.id = it.invoice_id
    LEFT JOIN suppliers s ON s.id = pi.supplier_id
    WHERE it.product_id = ? AND pi.status = 'confirmed' AND it.unit_price > 0''';

  /// آخر [perSupplier] أسعار من كل مورد للمادة، الأحدث أولاً.
  static Future<List<PurchasePriceRow>> forProduct(DatabaseExecutor db, int productId,
      {int? excludeInvoiceId, int perSupplier = 3}) async {
    final r = await db.rawQuery(
        '$_select${excludeInvoiceId == null ? '' : ' AND pi.id != ?'} ORDER BY pi.date DESC, pi.id DESC, it.id DESC',
        [productId, if (excludeInvoiceId != null) excludeInvoiceId]);
    final seen = <int?, int>{};
    final out = <PurchasePriceRow>[];
    for (final x in r) {
      final row = PurchasePriceRow.fromRow(x);
      final n = seen[row.supplierId] ?? 0;
      if (n >= perSupplier) continue;
      seen[row.supplierId] = n + 1;
      out.add(row);
    }
    return out;
  }

  /// آخر شراء للمادة من المورد نفسه وبالعملة نفسها (null إن لم يوجد).
  static Future<PurchasePriceRow?> last(DatabaseExecutor db,
      {required int productId, required int supplierId, required String currency, int? excludeInvoiceId}) async {
    final r = await db.rawQuery(
        "$_select AND pi.supplier_id = ? AND COALESCE(pi.currency, 'IQD') = ?"
        "${excludeInvoiceId == null ? '' : ' AND pi.id != ?'} ORDER BY pi.date DESC, pi.id DESC, it.id DESC LIMIT 1",
        [productId, supplierId, currency, if (excludeInvoiceId != null) excludeInvoiceId]);
    return r.isEmpty ? null : PurchasePriceRow.fromRow(r.first);
  }

  /// نسبة الارتفاع عن السعر السابق (موجبة = أغلى). null إن لا سعر سابق صالح.
  static double? risePct(double newBaseCost, double? lastBaseCost) {
    if (lastBaseCost == null || lastBaseCost <= 0 || newBaseCost <= 0) return null;
    return (newBaseCost - lastBaseCost) / lastBaseCost * 100;
  }
}
