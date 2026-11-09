// lib/erp/control/price_list.dart
//
// 🏷️ أسعار القائمة لكل مادة (price1..price6 بالوحدة الأساسية) — لقاعدة «تغيير السعر»:
// سطر بيع سعره قبل الخصم ليس من أسعار مادته (بالوحدة الأساسية، أو مضروباً بعدد قطع
// الوحدة الكبيرة) ⇒ «تغيير سعر» يحتاج صلاحية أو موافقة المدير. الخصم له قاعدته الخاصة.
// قراءة فقط.

import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../models/invoice_item.dart';

class PriceList {
  PriceList._();

  /// هامش لا يُعد تغييراً (تقريب الكرتون): الأكبر من دينار واحد و0.5٪.
  static const tolerancePct = 0.5;

  static String _idKey(int id) => 'id:$id';
  static String _nameKey(String n) => 'n:${n.trim()}';

  /// أسعار القائمة للمواد في [items]: المفتاح بالمعرّف وبالاسم.
  static Future<Map<String, List<double>>> forItems(DatabaseExecutor db, List<InvoiceItem> items) async {
    final ids = {for (final it in items) if ((it.productId ?? 0) > 0) it.productId!};
    final names = {for (final it in items) if (it.productName.trim().isNotEmpty) it.productName.trim()};
    final out = <String, List<double>>{};
    Future<void> load(String where, List<Object?> args) async {
      if (args.isEmpty) return;
      final rows = await db.rawQuery(
          'SELECT id, name, price1, price2, price3, price4, price5, price6 FROM products '
          'WHERE COALESCE(is_deleted, 0) = 0 AND $where IN (${List.filled(args.length, '?').join(',')})',
          args);
      for (final r in rows) {
        final prices = <double>[
          for (final k in const ['price1', 'price2', 'price3', 'price4', 'price5', 'price6'])
            if (((r[k] as num?)?.toDouble() ?? 0) > 0) (r[k] as num).toDouble(),
        ];
        if (prices.isEmpty) continue;
        out[_idKey(r['id'] as int)] = prices;
        out.putIfAbsent(_nameKey('${r['name']}'), () => prices);
      }
    }

    await load('id', ids.toList());
    await load('name', names.toList());
    return out;
  }

  static List<double>? lookup(Map<String, List<double>> m, InvoiceItem it) =>
      ((it.productId ?? 0) > 0 ? m[_idKey(it.productId!)] : null) ?? m[_nameKey(it.productName)];

  /// دالة صافية: هل سعر السطر قبل الخصم من أسعار القائمة؟ null = لا حكم (بلا سعر أو بلا قائمة).
  static bool? matches(InvoiceItem it, List<double> base) {
    final pre = it.priceBeforeDiscount ?? it.appliedPrice;
    if (pre <= 0 || base.isEmpty) return null;
    final large = (it.quantityLargeUnit ?? 0) > 0;
    final factor = large && (it.unitsInLargeUnit ?? 0) > 0 ? it.unitsInLargeUnit! : 1.0;
    for (final p in base) {
      for (final f in {1.0, factor}) {
        final want = p * f;
        final tol = max(1.0, want * tolerancePct / 100);
        if ((pre - want).abs() <= tol) return true;
      }
    }
    return false;
  }
}
