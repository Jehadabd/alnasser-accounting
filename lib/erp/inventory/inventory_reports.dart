// lib/erp/inventory/inventory_reports.dart
//
// 📊 تقارير المخزون (مثل الإداري) — قراءة فقط:
//   • المواد الراكدة، المتجاوزة للحدود (أدنى/أعلى/مخصص/مغلقة)
//   • تقرير حركات المواد: أول المدة + وارد (مشتريات، مرتجعات، إدخال، تحويل) −
//     صادر (مبيعات، إخراج) = آخر المدة
//   • الجرد بتاريخ سابق، وتقييم المخزون بطرق كلفة مختلفة
//   • الصلاحية القريبة، الكميات المحجوزة والمتاحة

import '../../accounting/ledger.dart';
import '../currency_service.dart';
import '../erp_common.dart';
import '../stock_helpers.dart';

/// كمية بند الفاتورة بالوحدة الأساسية (نفس تعريف دفتر المخزون).
const String kItemBaseQty = '''
  CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
       THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
       ELSE COALESCE(ii.quantity_individual, 0) END''';

class MovementRow {
  MovementRow(this.productId, this.name, this.unit, this.cost);
  final int productId;
  final String name;
  final String unit;
  final double cost;
  double opening = 0;
  double purchases = 0;
  double returnsIn = 0;
  double otherIn = 0;
  double sales = 0;
  double otherOut = 0;
  double get totalIn => purchases + returnsIn + otherIn;
  double get totalOut => sales + otherOut;
  double get closing => opening + totalIn - totalOut;
  bool get moved => totalIn.abs() > 1e-9 || totalOut.abs() > 1e-9;
}

class InventoryReports {
  /// الكمية بتاريخ لكل مادة (قبل نهاية ذلك اليوم). productSyncUuid ⇒ الكمية.
  Future<Map<String, double>> _qtyAt(DateTime? at) async {
    final db = await erpDb();
    final limit = at == null ? null : isoDayAfter(at);
    final mv = await db.rawQuery('''
      SELECT m.product_sync_uuid AS u, SUM(m.delta) AS q FROM stock_movements m
      WHERE (m.kind != 'opening' OR m.movement_uuid = 'opening_' || m.product_sync_uuid)
        ${limit == null ? '' : 'AND m.created_at < ?'}
      GROUP BY m.product_sync_uuid
    ''', limit == null ? null : [limit]);
    final sold = await db.rawQuery('''
      SELECT ii.product_sync_uuid AS u, SUM($kItemBaseQty) AS q
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة' AND ii.product_sync_uuid IS NOT NULL
        ${limit == null ? '' : 'AND i.invoice_date < ?'}
      GROUP BY ii.product_sync_uuid
    ''', limit == null ? null : [limit]);
    final out = <String, double>{};
    for (final r in mv) {
      final u = r['u'] as String?;
      if (u != null) out[u] = (out[u] ?? 0) + d0(r['q']);
    }
    for (final r in sold) {
      final u = r['u'] as String?;
      if (u != null) out[u] = (out[u] ?? 0) - d0(r['q']);
    }
    return out;
  }

  /// تقرير حركات المواد لفترة (كل المواد أو قسم).
  Future<List<MovementRow>> movements({required DateTime from, required DateTime to, int? categoryId}) async {
    final db = await erpDb();
    final products = await ErpStock.all(db,
        where: categoryId == null ? null : 'p.category_id = ?', args: categoryId == null ? null : [categoryId]);
    final opening = await _qtyAt(from.subtract(const Duration(days: 1)));
    final byUuid = <String, MovementRow>{};
    final rows = <MovementRow>[];
    for (final p in products) {
      final r = MovementRow(p.id, p.name, p.baseUnitName, p.cost);
      if (p.syncUuid != null) {
        r.opening = opening[p.syncUuid] ?? 0;
        byUuid[p.syncUuid!] = r;
      }
      rows.add(r);
    }
    final a = isoDay(from), b = isoDayAfter(to);
    final mv = await db.rawQuery('''
      SELECT m.product_sync_uuid AS u, m.kind, SUM(m.delta) AS q FROM stock_movements m
      WHERE m.created_at >= ? AND m.created_at < ?
        AND (m.kind != 'opening' OR m.movement_uuid = 'opening_' || m.product_sync_uuid)
        AND m.kind != 'transfer'
      GROUP BY m.product_sync_uuid, m.kind
    ''', [a, b]);
    for (final x in mv) {
      final r = byUuid[x['u']];
      if (r == null) continue;
      final q = d0(x['q']);
      final kind = (x['kind'] as String?) ?? '';
      if (kind == 'purchase' || kind == 'purchase_reverse' || kind == 'purchase_return') {
        r.purchases += q; // الإلغاء والمرتجع سالبان فيُطرحان
      } else if (kind == 'sales_return' || kind == 'sales_return_void') {
        r.returnsIn += q;
      } else if (q >= 0) {
        r.otherIn += q;
      } else {
        r.otherOut += -q;
      }
    }
    final sold = await db.rawQuery('''
      SELECT ii.product_sync_uuid AS u, SUM($kItemBaseQty) AS q
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة'
        AND i.invoice_date >= ? AND i.invoice_date < ?
      GROUP BY ii.product_sync_uuid
    ''', [a, b]);
    for (final x in sold) {
      final r = byUuid[x['u']];
      if (r != null) r.sales += d0(x['q']);
    }
    return rows;
  }

  /// الجرد بتاريخ: الكمية والقيمة بالكلفة الحالية.
  Future<List<Map<String, Object?>>> stockAt(DateTime at, {bool hideZero = true}) async {
    final db = await erpDb();
    final q = await _qtyAt(at);
    final products = await ErpStock.all(db);
    return [
      for (final p in products)
        if (!hideZero || (q[p.syncUuid] ?? 0).abs() > 1e-9)
          {
            'id': p.id,
            'name': p.name,
            'unit': p.baseUnitName,
            'qty': q[p.syncUuid] ?? 0.0,
            'cost': p.cost,
            'value': roundMoney((q[p.syncUuid] ?? 0) * p.cost),
          },
    ];
  }

  /// تقييم المخزون الحالي بطريقة كلفة: current | last_purchase | avg_purchase.
  Future<List<Map<String, Object?>>> valuation(String method, {int? warehouseId}) async {
    final db = await erpDb();
    final products = await ErpStock.all(db, where: "COALESCE(d.item_type, 'trade') != 'service'");
    final lastCost = <int, double>{};
    final avgCost = <int, double>{};
    if (method != 'current') {
      final rows = await db.rawQuery('''
        SELECT i.product_id, i.quantity, i.unit_price, COALESCE(NULLIF(i.conversion_factor, 0), 1) AS f,
               p.currency, p.date
        FROM purchase_invoice_items i JOIN purchase_invoices p ON p.id = i.invoice_id
        WHERE p.status = 'confirmed' ORDER BY p.date, p.id
      ''');
      final sumQ = <int, double>{};
      final sumV = <int, double>{};
      for (final r in rows) {
        final pid = r['product_id'] as int;
        final f = d0(r['f']);
        final baseQ = d0(r['quantity']) * f;
        if (baseQ <= 0) continue;
        var unit = d0(r['unit_price']) / f;
        if (r['currency'] == 'USD') unit *= await CurrencyService.rateAt(db, 'USD', parseDate(r['date']));
        lastCost[pid] = unit;
        sumQ[pid] = (sumQ[pid] ?? 0) + baseQ;
        sumV[pid] = (sumV[pid] ?? 0) + baseQ * unit;
      }
      sumQ.forEach((pid, q) {
        if (q > 0) avgCost[pid] = (sumV[pid] ?? 0) / q;
      });
    }
    final out = <Map<String, Object?>>[];
    for (final p in products) {
      final qty = warehouseId == null ? p.stock : await ErpStock.available(db, p.id, warehouseId: warehouseId);
      if (qty.abs() < 1e-9) continue;
      final cost = method == 'last_purchase'
          ? (lastCost[p.id] ?? p.cost)
          : method == 'avg_purchase'
              ? (avgCost[p.id] ?? p.cost)
              : p.cost;
      out.add({
        'id': p.id,
        'name': p.name,
        'unit': p.baseUnitName,
        'qty': qty,
        'cost': cost,
        'value': roundMoney(qty * cost),
        'sale_value': roundMoney(qty * p.prices[0]),
      });
    }
    return out;
  }

  /// المواد الراكدة: لم تتحرك (بيعاً/شراءً/مطلقاً) أو تحركت بأقل من حد خلال الفترة.
  Future<List<Map<String, Object?>>> stagnant({
    required DateTime from,
    required DateTime to,
    String type = 'sales', // sales | purchase | any
    double maxQty = 0,
    double maxAmount = 0,
  }) async {
    final db = await erpDb();
    final a = isoDay(from), b = isoDayAfter(to);
    final sales = await db.rawQuery('''
      SELECT ii.product_sync_uuid AS u, SUM($kItemBaseQty) AS q, SUM(ii.item_total) AS v
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE COALESCE(i.is_deleted, 0) = 0 AND i.status = 'محفوظة' AND i.invoice_date >= ? AND i.invoice_date < ?
      GROUP BY ii.product_sync_uuid
    ''', [a, b]);
    final purchases = await db.rawQuery('''
      SELECT m.product_sync_uuid AS u, SUM(m.delta) AS q FROM stock_movements m
      WHERE m.kind = 'purchase' AND m.created_at >= ? AND m.created_at < ? GROUP BY m.product_sync_uuid
    ''', [a, b]);
    final sq = {for (final r in sales) r['u']: d0(r['q'])};
    final sv = {for (final r in sales) r['u']: d0(r['v'])};
    final pq = {for (final r in purchases) r['u']: d0(r['q'])};
    final products = await ErpStock.all(db, where: "COALESCE(d.item_type, 'trade') != 'service'");
    final out = <Map<String, Object?>>[];
    for (final p in products) {
      final s = sq[p.syncUuid] ?? 0;
      final v = sv[p.syncUuid] ?? 0;
      final pu = pq[p.syncUuid] ?? 0;
      bool stagnant;
      switch (type) {
        case 'purchase':
          stagnant = pu <= maxQty;
          break;
        case 'any':
          stagnant = s <= maxQty && pu <= maxQty && (maxAmount <= 0 || v <= maxAmount);
          break;
        default:
          stagnant = s <= maxQty && (maxAmount <= 0 || v <= maxAmount);
      }
      if (!stagnant) continue;
      if (p.stock <= 1e-9 && type != 'purchase') continue; // لا رصيد ⇒ ليست راكدة فعلياً
      out.add({
        'id': p.id,
        'name': p.name,
        'unit': p.baseUnitName,
        'stock': p.stock,
        'sold_qty': s,
        'sold_value': v,
        'purchased_qty': pu,
        'stock_value': roundMoney(p.stock * p.cost),
      });
    }
    out.sort((x, y) => d0(y['stock_value']).compareTo(d0(x['stock_value'])));
    return out;
  }

  /// المواد المتجاوزة للحدود. mode: below_min | above_max | custom | zero | reorder
  Future<List<Map<String, Object?>>> limits(String mode, {double? customMin, double? customMax}) async {
    final db = await erpDb();
    final reserved = await ErpStock.reserved(db);
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.unit, p.stock_quantity, p.cost_price, d.min_qty, d.max_qty, d.reorder_qty,
             s.name AS supplier_name
      FROM products p LEFT JOIN product_details d ON d.product_id = p.id
      LEFT JOIN suppliers s ON s.id = d.default_supplier_id
      WHERE COALESCE(p.is_deleted, 0) = 0 AND COALESCE(d.item_type, 'trade') != 'service'
      ORDER BY p.name
    ''');
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final stock = d0(r['stock_quantity']);
      final avail = stock - (reserved[r['id']] ?? 0);
      final min = (r['min_qty'] as num?)?.toDouble();
      final max = (r['max_qty'] as num?)?.toDouble();
      bool hit;
      switch (mode) {
        case 'above_max':
          hit = max != null && max > 0 && stock > max;
          break;
        case 'custom':
          hit = (customMin != null && stock < customMin) || (customMax != null && stock > customMax);
          break;
        case 'zero':
          hit = stock.abs() < 1e-9;
          break;
        default: // below_min / reorder
          hit = min != null && min > 0 && avail <= min;
      }
      if (!hit) continue;
      double suggest = 0;
      if (min != null && min > 0) {
        final rq = d0(r['reorder_qty']);
        suggest = rq > 0 ? rq : ((max ?? 0) > avail ? max! - avail : min * 2 - avail);
        if (suggest < 0) suggest = 0;
      }
      out.add({
        ...r,
        'reserved': reserved[r['id']] ?? 0.0,
        'available': avail,
        'suggest': suggest,
      });
    }
    return out;
  }

  /// المواد التي تنتهي صلاحيتها خلال [days] يوماً (أو انتهت).
  Future<List<Map<String, Object?>>> expiring(int days) async {
    final db = await erpDb();
    try {
      return await db.rawQuery('''
        SELECT id, name, unit, stock_quantity, expiry_date FROM products
        WHERE COALESCE(is_deleted, 0) = 0 AND COALESCE(has_expiry, 0) = 1 AND expiry_date IS NOT NULL
          AND expiry_date < ? AND COALESCE(stock_quantity, 0) > 0
        ORDER BY expiry_date
      ''', [isoDayAfter(DateTime.now().add(Duration(days: days)))]);
    } catch (_) {
      return const [];
    }
  }

  /// حركة مادة واحدة تفصيلياً (كل الحركات + المبيعات) برصيد تراكمي.
  Future<List<Map<String, Object?>>> productCard(int productId) async {
    final db = await erpDb();
    final p = await ErpStock.byId(db, productId);
    if (p == null || p.syncUuid == null) return const [];
    final mv = await db.rawQuery('''
      SELECT created_at AS d, delta AS q, kind, note FROM stock_movements
      WHERE product_sync_uuid = ? AND (kind != 'opening' OR movement_uuid = 'opening_' || product_sync_uuid)
    ''', [p.syncUuid]);
    final sold = await db.rawQuery('''
      SELECT i.invoice_date AS d, -($kItemBaseQty) AS q, 'sale' AS kind,
             'فاتورة #' || i.id || ' — ' || COALESCE(i.customer_name, '') AS note
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE ii.product_sync_uuid = ? AND COALESCE(i.is_deleted, 0) = 0 AND COALESCE(i.status, '') != 'معلقة'
    ''', [p.syncUuid]);
    final all = [...mv, ...sold].map((r) => Map<String, Object?>.from(r)).toList()
      ..sort((a, b) => ('${a['d']}').compareTo('${b['d']}'));
    var bal = 0.0;
    for (final r in all) {
      bal += d0(r['q']);
      r['balance'] = bal;
    }
    return all.reversed.toList();
  }
}

const Map<String, String> movementKindLabels = {
  'opening': 'رصيد افتتاحي',
  'purchase': 'شراء',
  'purchase_return': 'مرتجع مشتريات',
  'purchase_reverse': 'إلغاء شراء',
  'adjust': 'تعديل يدوي',
  'transfer': 'تحويل مخزني',
  'sales_return': 'مرتجع مبيعات',
  'sales_return_void': 'إلغاء مرتجع',
  'doc_in': 'سند إدخال',
  'doc_out': 'سند إخراج',
  'doc_opening': 'بضاعة أول المدة',
  'doc_count': 'تسوية جرد',
  'doc_production': 'تصنيع',
  'doc_void': 'إلغاء مستند',
  'sale': 'بيع',
};

double invRound(double v) => roundMoney(v);
