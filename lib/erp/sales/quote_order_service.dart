// lib/erp/sales/quote_order_service.dart
//
// 📝 عروض الأسعار والطلبات (مثل الإداري):
//   • عرض السعر: مستند كتابي بلا أي أثر على المخزون أو الحسابات، له تاريخ صلاحية،
//     يُطبع، ويُحوَّل إلى فاتورة بمراجعة المستخدم.
//   • الطلب (مبيعات/مشتريات): كميات مطلوبة، تاريخ تسليم، أولوية، حجز كميات
//     اختياري (يظهر في الجرد كمحجوز)، وتسليم جزئي يُرحَّل إلى فاتورة.
// لا يغيّر أيٌّ منهما رصيداً ولا مخزوناً بنفسه — الفاتورة الناتجة هي التي تفعل
// ذلك بمسارها الأصلي.

import '../../accounting/ledger.dart';
import '../doc_lines.dart';
import '../erp_common.dart';
import '../stock_helpers.dart';

class QuoteOrderService {
  // ═══════════════════════════ عروض الأسعار ═══════════════════════════

  Future<int> saveQuotation({
    int? id,
    required DateTime date,
    DateTime? validUntil,
    int? customerId,
    required String customerName,
    String? phone,
    String? address,
    String? priceLevel,
    double discount = 0,
    String? notes,
    String? terms,
    required List<DocLine> lines,
  }) async {
    if (customerName.trim().isEmpty) throw ErpException('اكتب اسم الزبون');
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw ErpException('أضف مادة واحدة على الأقل');
    final total = linesTotal(valid);
    if (discount < 0 || discount > total) throw ErpException('الحسم غير صحيح');
    final db = await erpDb();
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final row = {
        'quote_date': date.toIso8601String(),
        'valid_until': validUntil == null ? null : isoDay(validUntil),
        'customer_id': customerId,
        'customer_name': customerName.trim(),
        'customer_phone': phone,
        'customer_address': address,
        'price_level': priceLevel,
        'discount': roundMoney(discount),
        'total': total,
        'notes': notes,
        'terms': terms,
        'updated_at': now,
      };
      int qid;
      if (id == null) {
        qid = await txn.insert('quotations', {
          ...row,
          'quote_no': await nextDocNumber(txn, 'quotations', 'quote_no'),
          'status': 'open',
          'created_by': currentUserName(),
          'created_at': now,
        });
      } else {
        qid = id;
        await txn.update('quotations', row, where: 'id = ?', whereArgs: [id]);
        await txn.delete('quotation_items', where: 'quotation_id = ?', whereArgs: [id]);
      }
      for (final l in valid) {
        await txn.insert('quotation_items', {
          'quotation_id': qid,
          'product_id': l.product.id,
          'product_name': l.product.name,
          'unit': l.product.unit,
          'sale_type': l.unit.name,
          'units_in_large': l.unit.factor,
          'quantity': l.quantity,
          'price': l.price,
          'discount_percent': l.discountPercent,
          'total': l.total,
        });
      }
      return qid;
    });
  }

  Future<List<Map<String, Object?>>> quotations({String? status}) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT q.*, (SELECT COUNT(*) FROM quotation_items i WHERE i.quotation_id = q.id) AS n_items
      FROM quotations q ${status == null ? '' : 'WHERE q.status = ?'}
      ORDER BY q.quote_date DESC, q.id DESC LIMIT 1000
    ''', status == null ? null : [status]);
  }

  Future<Map<String, Object?>?> quotation(int id) async {
    final db = await erpDb();
    final r = await db.query('quotations', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<DocLine>> quotationLines(int id) async {
    final db = await erpDb();
    final rows = await db.query('quotation_items', where: 'quotation_id = ?', whereArgs: [id], orderBy: 'id');
    final out = <DocLine>[];
    for (final r in rows) {
      final pid = r['product_id'] as int?;
      if (pid == null) continue;
      final p = await ErpStock.byId(db, pid);
      if (p == null) continue;
      out.add(DocLine(
        product: p,
        unit: p.unitNamed(r['sale_type'] as String?),
        quantity: d0(r['quantity']),
        price: d0(r['price']),
        discountPercent: d0(r['discount_percent']),
      ));
    }
    return out;
  }

  Future<void> setQuotationStatus(int id, String status) async {
    final db = await erpDb();
    await db.update('quotations', {'status': status, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteQuotation(int id) async {
    final db = await erpDb();
    await db.delete('quotations', where: 'id = ?', whereArgs: [id]);
    await db.delete('quotation_items', where: 'quotation_id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════ الطلبات ═══════════════════════════

  Future<int> saveOrder({
    int? id,
    required String orderType, // sales | purchase
    required DateTime date,
    DateTime? deliveryDate,
    int? partyId,
    required String partyName,
    int priority = 2,
    String? priceLevel,
    double discountPercent = 0,
    String currency = 'IQD',
    double fxRate = 1,
    String? shippingCompany,
    String? deliveryMethod,
    String? paymentMethod,
    String? sellerName,
    int? warehouseId,
    bool reserve = false,
    String? notes,
    required List<DocLine> lines,
  }) async {
    if (partyName.trim().isEmpty) throw ErpException('اختر الطرف الثاني');
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw ErpException('أضف مادة واحدة على الأقل');
    final db = await erpDb();
    return db.transaction((txn) async {
      final row = {
        'order_type': orderType,
        'order_date': date.toIso8601String(),
        'delivery_date': deliveryDate == null ? null : isoDay(deliveryDate),
        'party_type': orderType == 'sales' ? 'customer' : 'supplier',
        'party_id': partyId,
        'party_name': partyName.trim(),
        'priority': priority,
        'price_level': priceLevel,
        'discount_percent': discountPercent,
        'currency': currency,
        'fx_rate': fxRate,
        'shipping_company': shippingCompany,
        'delivery_method': deliveryMethod,
        'payment_method': paymentMethod,
        'seller_name': sellerName,
        'warehouse_id': warehouseId,
        'reserve': reserve ? 1 : 0,
        'notes': notes,
      };
      int oid;
      if (id == null) {
        oid = await txn.insert('orders', {
          ...row,
          'order_no': await nextDocNumber(txn, 'orders', 'order_no', where: 'order_type = ?', args: [orderType]),
          'status': 'open',
          'created_by': currentUserName(),
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        oid = id;
        // لا نسمح بتعديل طلب سُلّم منه شيء (حماية الكميات المسلّمة)
        final d = await txn.rawQuery(
            'SELECT COALESCE(SUM(delivered_base_qty), 0) AS d FROM order_items WHERE order_id = ?', [id]);
        if (d0(d.first['d']) > 0) throw ErpException('سُلّم جزء من هذا الطلب — لا يمكن تعديل مواده');
        await txn.update('orders', row, where: 'id = ?', whereArgs: [id]);
        await txn.delete('order_items', where: 'order_id = ?', whereArgs: [id]);
      }
      for (final l in valid) {
        await txn.insert('order_items', {
          'order_id': oid,
          'product_id': l.product.id,
          'product_name': l.product.name,
          'unit': l.product.unit,
          'sale_type': l.unit.name,
          'units_in_large': l.unit.factor,
          'quantity': l.quantity,
          'base_qty': l.baseQty,
          'delivered_base_qty': 0,
          'price': l.price,
          'discount_percent': l.discountPercent,
          'reserve': reserve ? 1 : 0,
          'notes': l.note,
        });
      }
      return oid;
    });
  }

  Future<List<Map<String, Object?>>> orders({required String orderType, bool includeClosed = false, int? partyId}) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT o.*,
        (SELECT COUNT(*) FROM order_items i WHERE i.order_id = o.id) AS n_items,
        (SELECT COALESCE(SUM(i.base_qty), 0) FROM order_items i WHERE i.order_id = o.id) AS qty,
        (SELECT COALESCE(SUM(i.delivered_base_qty), 0) FROM order_items i WHERE i.order_id = o.id) AS delivered,
        (SELECT COALESCE(SUM(i.quantity * i.price * (1 - i.discount_percent / 100.0)), 0) FROM order_items i WHERE i.order_id = o.id) AS total
      FROM orders o
      WHERE o.order_type = ? ${includeClosed ? '' : "AND o.status IN ('open', 'partial')"}
        ${partyId == null ? '' : 'AND o.party_id = $partyId'}
      ORDER BY o.priority, COALESCE(o.delivery_date, o.order_date), o.id
    ''', [orderType]);
  }

  Future<Map<String, Object?>?> order(int id) async {
    final db = await erpDb();
    final r = await db.query('orders', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<Map<String, Object?>>> orderItems(int id) async {
    final db = await erpDb();
    return db.query('order_items', where: 'order_id = ?', whereArgs: [id], orderBy: 'id');
  }

  Future<List<DocLine>> orderLines(int id, {bool remainingOnly = false}) async {
    final db = await erpDb();
    final rows = await orderItems(id);
    final out = <DocLine>[];
    for (final r in rows) {
      final pid = r['product_id'] as int?;
      if (pid == null) continue;
      final p = await ErpStock.byId(db, pid);
      if (p == null) continue;
      final u = p.unitNamed(r['sale_type'] as String?);
      var q = d0(r['quantity']);
      if (remainingOnly) {
        final remBase = d0(r['base_qty']) - d0(r['delivered_base_qty']);
        if (remBase <= 1e-9) continue;
        q = remBase / (u.factor == 0 ? 1 : u.factor);
      }
      out.add(DocLine(
        product: p,
        unit: u,
        quantity: q,
        price: d0(r['price']),
        discountPercent: d0(r['discount_percent']),
        note: '${r['id']}', // رقم سطر الطلب — للتسليم
      ));
    }
    return out;
  }

  /// تسجيل تسليم (كليّ أو جزئي) — [delivered]: رقم سطر الطلب ⇒ الكمية بالوحدة الأساسية.
  /// لا يتجاوز التسليم الكمية المطلوبة أبداً.
  Future<void> recordDelivery(int orderId, Map<int, double> delivered, {String? ref}) async {
    final db = await erpDb();
    await db.transaction((txn) async {
      for (final e in delivered.entries) {
        if (e.value <= 0) continue;
        final r = await txn.query('order_items', where: 'id = ? AND order_id = ?', whereArgs: [e.key, orderId], limit: 1);
        if (r.isEmpty) continue;
        final remaining = d0(r.first['base_qty']) - d0(r.first['delivered_base_qty']);
        final q = e.value > remaining ? remaining : e.value;
        if (q <= 1e-9) continue;
        await txn.rawUpdate('UPDATE order_items SET delivered_base_qty = delivered_base_qty + ? WHERE id = ?', [q, e.key]);
        await txn.insert('order_delivery_log', {
          'order_id': orderId,
          'order_item_id': e.key,
          'base_qty': q,
          'ref': ref,
          'created_by': currentUserName(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      await _refreshStatus(txn, orderId);
    });
  }

  /// يحسب ما سُلّم فعلاً من فاتورة بيع محفوظة ويسجّله على الطلب (بالمطابقة بالمادة).
  Future<void> deliverFromInvoice(int orderId, int invoiceId) async {
    final db = await erpDb();
    final sold = await db.rawQuery('''
      SELECT p.id AS pid,
             SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                      THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                      ELSE COALESCE(ii.quantity_individual, 0) END) AS q
      FROM invoice_items ii
      JOIN products p ON (p.sync_uuid = ii.product_sync_uuid OR (ii.product_sync_uuid IS NULL AND p.name = ii.product_name))
      WHERE ii.invoice_id = ? GROUP BY p.id
    ''', [invoiceId]);
    final available = {for (final r in sold) r['pid'] as int: d0(r['q'])};
    final items = await orderItems(orderId);
    final delivered = <int, double>{};
    for (final it in items) {
      final pid = it['product_id'] as int?;
      if (pid == null) continue;
      final a = available[pid] ?? 0;
      if (a <= 0) continue;
      final rem = d0(it['base_qty']) - d0(it['delivered_base_qty']);
      final q = a < rem ? a : rem;
      if (q > 0) {
        delivered[it['id'] as int] = q;
        available[pid] = a - q;
      }
    }
    await recordDelivery(orderId, delivered, ref: 'فاتورة #$invoiceId');
  }

  Future<void> _refreshStatus(dynamic txn, int orderId) async {
    final r = await txn.rawQuery('''
      SELECT COALESCE(SUM(base_qty), 0) AS q, COALESCE(SUM(delivered_base_qty), 0) AS d
      FROM order_items WHERE order_id = ?''', [orderId]);
    final q = d0(r.first['q']);
    final d = d0(r.first['d']);
    final status = d <= 1e-9 ? 'open' : (d + 1e-9 >= q ? 'closed' : 'partial');
    await txn.update('orders', {'status': status, 'closed_at': status == 'closed' ? DateTime.now().toIso8601String() : null},
        where: 'id = ?', whereArgs: [orderId]);
  }

  Future<void> closeOrder(int id) async {
    final db = await erpDb();
    await db.update('orders', {'status': 'closed', 'closed_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cancelOrder(int id) async {
    final db = await erpDb();
    final d = await db.rawQuery(
        'SELECT COALESCE(SUM(delivered_base_qty), 0) AS d FROM order_items WHERE order_id = ?', [id]);
    if (d0(d.first['d']) > 0) throw ErpException('سُلّم جزء من الطلب — أغلقه بدلاً من إلغائه');
    await db.update('orders', {'status': 'cancelled', 'closed_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// طلبات مادة معينة (مثل «إظهار طلبات مادة» في الإداري).
  Future<List<Map<String, Object?>>> productOrders(int productId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT o.order_type, o.order_no, o.order_date, o.delivery_date, o.party_name, o.status,
             i.quantity, i.sale_type, i.base_qty, i.delivered_base_qty
      FROM order_items i JOIN orders o ON o.id = i.order_id
      WHERE i.product_id = ? ORDER BY o.order_date DESC
    ''', [productId]);
  }

  /// طلب مشتريات تلقائي للمواد التي نزلت عن الحد الأدنى (مثل «كمية الطلب» في بطاقة الإداري).
  /// يُنشئ طلباً لكل مورد افتراضي. يعيد عدد الطلبات المنشأة.
  Future<int> autoReorder() async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.stock_quantity, d.min_qty, d.reorder_qty, d.max_qty, d.default_supplier_id,
             s.name AS supplier_name, p.cost_price
      FROM products p JOIN product_details d ON d.product_id = p.id
      LEFT JOIN suppliers s ON s.id = d.default_supplier_id
      WHERE COALESCE(p.is_deleted, 0) = 0 AND d.min_qty IS NOT NULL AND d.min_qty > 0
        AND COALESCE(p.stock_quantity, 0) <= d.min_qty AND COALESCE(d.is_active, 1) = 1
    ''');
    if (rows.isEmpty) return 0;
    // مواد في طلبات شراء مفتوحة لا تُطلب مرة ثانية
    final pending = await db.rawQuery('''
      SELECT DISTINCT i.product_id FROM order_items i JOIN orders o ON o.id = i.order_id
      WHERE o.order_type = 'purchase' AND o.status IN ('open', 'partial')
    ''');
    final pendingIds = {for (final r in pending) r['product_id'] as int?};
    final bySupplier = <int?, List<Map<String, Object?>>>{};
    for (final r in rows) {
      if (pendingIds.contains(r['id'])) continue;
      bySupplier.putIfAbsent(r['default_supplier_id'] as int?, () => []).add(r);
    }
    var n = 0;
    for (final e in bySupplier.entries) {
      final lines = <DocLine>[];
      for (final r in e.value) {
        final p = await ErpStock.byId(db, r['id'] as int);
        if (p == null) continue;
        final stock = d0(r['stock_quantity']);
        var qty = d0(r['reorder_qty']);
        if (qty <= 0) {
          final max = d0(r['max_qty']);
          qty = max > stock ? max - stock : d0(r['min_qty']) * 2 - stock;
        }
        if (qty <= 0) continue;
        lines.add(DocLine(product: p, unit: p.units.first, quantity: qty, price: p.cost));
      }
      if (lines.isEmpty) continue;
      await saveOrder(
        orderType: 'purchase',
        date: DateTime.now(),
        partyId: e.key,
        partyName: (e.value.first['supplier_name'] as String?) ?? 'مورد غير محدد',
        notes: 'طلب تلقائي: مواد وصلت الحد الأدنى',
        lines: lines,
      );
      n++;
    }
    return n;
  }
}

double qoRound(double v) => roundMoney(v);
