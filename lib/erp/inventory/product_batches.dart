// lib/erp/inventory/product_batches.dart
//
// 📦 دفعات الشراء: لكل كمية مشتراة صلاحيتها وضمانها وشروطه.
//
//   • الدفعة = حركة شراء في دفتر المخزون (stock_movements، kind = 'purchase')، ومعها
//     batch_date (تاريخ فاتورة الشراء) و expiry_date و warranty_spec و warranty_terms.
//     الحركة تصل لكل الأجهزة، فالدفعات واحدة على كل الأجهزة.
//   • لا حالة جديدة للمخزون: الباقي من كل دفعة يُشتق من رصيد المادة نفسه بقاعدة «الأقدم
//     يخرج أولاً» (FIFO): الرصيد الحالي يُنسب للدفعات من الأحدث إلى الأقدم، فما يبقى
//     هو أحدث ما اشتُري، وأول ما يخرج في البيع التالي هو أقدم دفعة لها باقٍ.
//     الرصيد الذي لا تغطيه دفعات (افتتاحي، جرد، دفعات بلا تفاصيل) = «بلا دفعة»، وهو الأقدم.
//   • البيع: ضمان السطر من الدفعة التي تخرج منها أول قطعة فيه (ItemWarranty).
//   • الصلاحية: تاريخ صلاحية المادة = أقرب صلاحية بين دفعاتها التي بقي منها شيء
//     (refreshExpiry)، فتعمل التنبيهات والتقارير كما هي.
//
// قراءة واشتقاق فقط: لا مال ولا قيود، ولا تغيير في كمية أي مادة.

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../models/purchase_invoice_item.dart';
import '../warranty/item_warranty.dart';

class StockBatch {
  StockBatch({
    required this.movementUuid,
    required this.date,
    required this.qty,
    required this.remaining,
    this.expiry,
    this.warranty,
    this.terms,
  });

  final String movementUuid;

  /// تاريخ فاتورة الشراء (أو يوم تسجيل الحركة لحركات بلا تاريخ).
  final DateTime date;

  /// الكمية المشتراة بالوحدة الأساسية.
  final double qty;

  /// الباقي منها الآن (FIFO).
  final double remaining;
  final DateTime? expiry;
  final WarrantySpec? warranty;
  final String? terms;

  bool get hasDetails => expiry != null || (warranty != null && !warranty!.isNone) || (terms ?? '').isNotEmpty;
}

/// دفعات مادة الآن: الأقدم أولاً، و[unbatched] = رصيد لا تغطيه دفعة (يخرج قبلها، فهو الأقدم).
class BatchSet {
  const BatchSet(this.batches, this.unbatched);
  static const empty = BatchSet([], 0);

  final List<StockBatch> batches;
  final double unbatched;

  /// الدفعة التي تخرج منها القطعة رقم [offset] + 1 في البيع التالي (FIFO).
  /// null إن خرجت من الرصيد «بلا دفعة»، أو تجاوزت الرصيد كله (بيع بالسالب).
  StockBatch? at(double offset) {
    var pos = offset - unbatched;
    if (pos < -1e-9) return null;
    for (final b in batches) {
      if (b.remaining <= 1e-9) continue;
      if (pos < b.remaining - 1e-9) return b;
      pos -= b.remaining;
    }
    return null;
  }
}

class ProductBatches {
  ProductBatches._();

  static const columns = ['batch_date', 'expiry_date', 'warranty_spec', 'warranty_terms'];

  /// اسم الحقل في مستند الحركة السحابي (batch_date ← batchDate).
  static String docKey(String column) => switch (column) {
        'batch_date' => 'batchDate',
        'expiry_date' => 'expiryDate',
        'warranty_spec' => 'warrantySpec',
        _ => 'warrantyTerms',
      };

  /// أعمدة الدفعة لحركة شراء من سطر فاتورة الشراء وتاريخها.
  static Map<String, Object?> batchFields(PurchaseInvoiceItem item, DateTime? purchaseDate) {
    final w = WarrantySpec.parse(item.warrantySpec);
    final t = (item.warrantyTerms ?? '').trim();
    final e = DateTime.tryParse((item.expiryDate ?? '').trim());
    return {
      if (purchaseDate != null) 'batch_date': ItemWarranty.iso(purchaseDate),
      if (e != null) 'expiry_date': ItemWarranty.iso(e),
      if (w != null && !w.isNone) 'warranty_spec': w.encode(),
      if (w != null && !w.isNone && t.isNotEmpty) 'warranty_terms': t,
    };
  }

  static bool _ready = false;

  static Future<bool> ready(DatabaseExecutor d) async {
    if (_ready) return true;
    try {
      final c = (await d.rawQuery('PRAGMA table_info(stock_movements)')).map((r) => r['name']).toSet();
      _ready = c.containsAll(columns);
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// كل دفعات المادة من الأقدم إلى الأحدث، ومعها الباقي من كل منها الآن.
  /// [stock]: رصيد مفترض بدل رصيد المادة الحالي (للاختبار وللحساب داخل حفظ فاتورة).
  static Future<BatchSet> of(DatabaseExecutor d, String productSyncUuid, {double? stock}) async {
    if (productSyncUuid.isEmpty || !await ready(d)) return BatchSet.empty;
    final rows = await d.rawQuery('''
      SELECT movement_uuid, delta, created_at, ${columns.join(', ')} FROM stock_movements
      WHERE kind = 'purchase' AND delta > 0
        AND (product_sync_uuid = ?
             OR product_sync_uuid IN (SELECT old_uuid FROM product_uuid_alias WHERE new_uuid = ?))
    ''', [productSyncUuid, productSyncUuid]);
    if (rows.isEmpty) return BatchSet.empty;
    var left = stock;
    if (left == null) {
      final p = await d.query('products',
          columns: ['stock_quantity'], where: 'sync_uuid = ?', whereArgs: [productSyncUuid], limit: 1);
      left = p.isEmpty ? 0.0 : ((p.first['stock_quantity'] as num?)?.toDouble() ?? 0.0);
    }
    DateTime dateOf(Map<String, Object?> r) =>
        DateTime.tryParse('${r['batch_date'] ?? ''}') ?? DateTime.tryParse('${r['created_at'] ?? ''}') ?? DateTime(2000);
    // الأحدث أولاً للنسبة؛ التعادل بوقت التسجيل
    final sorted = [...rows]..sort((a, b) {
        final c = dateOf(b).compareTo(dateOf(a));
        return c != 0 ? c : '${b['created_at']}'.compareTo('${a['created_at']}');
      });
    final out = <StockBatch>[];
    for (final r in sorted) {
      final q = (r['delta'] as num).toDouble();
      final take = left! <= 0 ? 0.0 : (left < q ? left : q);
      left -= take;
      final t = '${r['warranty_terms'] ?? ''}'.trim();
      out.add(StockBatch(
        movementUuid: '${r['movement_uuid']}',
        date: dateOf(r),
        qty: q,
        remaining: take,
        expiry: DateTime.tryParse('${r['expiry_date'] ?? ''}'),
        warranty: WarrantySpec.parse(r['warranty_spec']),
        terms: t.isEmpty ? null : t,
      ));
    }
    return BatchSet(out.reversed.toList(), left! > 0 ? left : 0.0); // الأقدم أولاً
  }

  /// يجعل تاريخ صلاحية المادة أقرب صلاحية بين دفعاتها التي بقي منها شيء.
  /// يمسّ فقط المواد التي لها دفعة بصلاحية؛ المادة بلا دفعات تبقى بتاريخها اليدوي.
  /// لا يرفع المادة للمزامنة (الصلاحية تُشتق على كل جهاز من الحركات نفسها).
  static Future<int> refreshExpiry(DatabaseExecutor d, {String? productSyncUuid}) async {
    if (!await ready(d)) return 0;
    final targets = await d.rawQuery('''
      SELECT DISTINCT COALESCE(a.new_uuid, m.product_sync_uuid) AS u FROM stock_movements m
      LEFT JOIN product_uuid_alias a ON a.old_uuid = m.product_sync_uuid
      WHERE m.kind = 'purchase' AND m.delta > 0 AND m.expiry_date IS NOT NULL AND m.expiry_date != ''
      ${productSyncUuid == null ? '' : 'AND COALESCE(a.new_uuid, m.product_sync_uuid) = ?'}
    ''', [if (productSyncUuid != null) productSyncUuid]);
    var changed = 0;
    for (final t in targets) {
      final u = '${t['u'] ?? ''}';
      if (u.isEmpty) continue;
      final live = (await of(d, u)).batches.where((b) => b.remaining > 1e-9 && b.expiry != null).toList();
      DateTime? soonest;
      for (final b in live) {
        if (soonest == null || b.expiry!.isBefore(soonest)) soonest = b.expiry;
      }
      final p = await d.query('products',
          columns: ['has_expiry', 'expiry_date'], where: 'sync_uuid = ?', whereArgs: [u], limit: 1);
      if (p.isEmpty) continue;
      final cur = DateTime.tryParse('${p.first['expiry_date'] ?? ''}');
      final hasExpiry = (p.first['has_expiry'] as num?)?.toInt() == 1;
      final Map<String, Object?> values;
      if (soonest == null) {
        // كل الدفعات ذات الصلاحية نفدت: لا تاريخ يُنبَّه عليه
        if (cur == null) continue;
        values = {'expiry_date': null};
      } else {
        if (hasExpiry && cur != null && ItemWarranty.iso(cur) == ItemWarranty.iso(soonest)) continue;
        values = {'expiry_date': '${ItemWarranty.iso(soonest)}T00:00:00.000', 'has_expiry': 1};
      }
      await d.update('products', values, where: 'sync_uuid = ?', whereArgs: [u]);
      changed++;
    }
    return changed;
  }
}
