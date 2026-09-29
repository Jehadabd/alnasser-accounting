// lib/erp/sales/sales_return_service.dart
//
// ↩️ مرتجع المبيعات المستقل (مثل «مر. مبيعات» في الإداري): مستند برقم، يعيد
// البضاعة للمخزن ويردّ المبلغ نقداً من صندوق أو يُنزله من دين العميل.
//
// الترتيب المالي الآمن:
//   1. على الحساب: معاملة «مرتجع» على العميل أولاً (المسار الأصلي). إن فشلت لا
//      يُكتب شيء.
//   2. المستند + حركات المخزون في معاملة قاعدة بيانات واحدة (كلها أو لا شيء).
//      إن فشلت بعد نجاح الخطوة 1 تُلغى معاملة العميل بمعاملة عكسية فوراً.
//   3. القيد (نقدي + عودة الكلفة) يشتقه محرك الترحيل من المستند.
//
// المرتجع المرتبط بفاتورة: لا يُسمح بإرجاع كمية أكبر مما بيع فيها (مطروحاً
// منه ما أُرجع سابقاً منها).

import 'package:flutter/material.dart';

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart' show fmtMoney;
import '../../providers/app_provider.dart';
import '../debts/customer_money.dart';
import '../activity/activity_log.dart';
import '../erp_common.dart';
import '../stock_helpers.dart';

class ReturnLine {
  ReturnLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.price,
  });
  final ProductLite product;
  UnitOption unit;
  double quantity;

  /// سعر الوحدة المختارة.
  double price;

  double get baseQty => quantity * unit.factor;
  double get total => roundMoney(quantity * price);
}

/// الجزء النقدي من مرتجع (من الصندوق).
double returnCashPart(Map<String, Object?> r) {
  final total = d0(r['total']);
  switch (r['refund_mode']) {
    case 'cash':
      return total;
    case 'mixed':
      return roundMoney(d0(r['cash_amount']));
    default:
      return 0;
  }
}

/// الجزء الذي نزل من دين العميل.
double returnCreditPart(Map<String, Object?> r) => roundMoney(d0(r['total']) - returnCashPart(r));

class SalesReturnService {
  /// الكمية المباعة (بالوحدة الأساسية) من كل مادة في فاتورة، مطروحاً منها المُرجع سابقاً.
  Future<Map<int, double>> returnableFromInvoice(int invoiceId) async {
    final db = await erpDb();
    final sold = await db.rawQuery('''
      SELECT p.id AS pid,
             SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                      THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                      ELSE COALESCE(ii.quantity_individual, 0) END) AS q
      FROM invoice_items ii
      JOIN products p ON (p.sync_uuid = ii.product_sync_uuid OR (ii.product_sync_uuid IS NULL AND p.name = ii.product_name))
      WHERE ii.invoice_id = ?
      GROUP BY p.id
    ''', [invoiceId]);
    final returned = await db.rawQuery('''
      SELECT i.product_id AS pid, SUM(i.base_qty) AS q
      FROM sales_return_items i JOIN sales_returns r ON r.id = i.return_id
      WHERE r.original_invoice_id = ? AND r.status = 'posted'
      GROUP BY i.product_id
    ''', [invoiceId]);
    final out = <int, double>{for (final r in sold) r['pid'] as int: d0(r['q'])};
    for (final r in returned) {
      final pid = r['pid'] as int;
      out[pid] = (out[pid] ?? 0) - d0(r['q']);
    }
    return out;
  }

  Future<Map<String, Object?>?> invoiceHeader(int invoiceId) async {
    final db = await erpDb();
    final r = await db.query('invoices', where: 'id = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [invoiceId], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  /// كلفة الوحدة الأساسية لكل مادة كما بيعت في الفاتورة الأصلية (لتعود بالكلفة نفسها).
  Future<Map<int, double>> invoiceBaseCosts(int invoiceId) async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT p.id AS pid, ii.actual_cost_price AS c, ii.quantity_large_unit AS ql, ii.quantity_individual AS qi,
             COALESCE(NULLIF(ii.units_in_large_unit, 0), 1) AS u
      FROM invoice_items ii
      JOIN products p ON (p.sync_uuid = ii.product_sync_uuid OR (ii.product_sync_uuid IS NULL AND p.name = ii.product_name))
      WHERE ii.invoice_id = ? AND COALESCE(ii.actual_cost_price, 0) > 0''', [invoiceId]);
    final qty = <int, double>{}, val = <int, double>{};
    for (final r in rows) {
      final pid = r['pid'] as int;
      final large = d0(r['ql']) > 0;
      final soldUnits = large ? d0(r['ql']) : d0(r['qi']);
      final base = large ? soldUnits * d0(r['u']) : soldUnits;
      if (base <= 0) continue;
      qty[pid] = (qty[pid] ?? 0) + base;
      val[pid] = (val[pid] ?? 0) + d0(r['c']) * soldUnits;
    }
    return {for (final e in qty.entries) if (e.value > 0) e.key: (val[e.key] ?? 0) / e.value};
  }

  /// البحث عن فاتورة برقمها التجاري أو بمعرّفها.
  Future<int?> findInvoice(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    final db = await erpDb();
    final byNo = await db.query('invoices',
        columns: ['id'], where: 'invoice_number = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [t], limit: 1);
    if (byNo.isNotEmpty) return byNo.first['id'] as int;
    final id = int.tryParse(t);
    if (id == null) return null;
    final r = await db.query('invoices', columns: ['id'], where: 'id = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : id;
  }

  Future<int> create(
    BuildContext? context, {
    AppProvider? provider,
    int? customerId,
    required String customerName,
    int? originalInvoiceId,
    required String refundMode, // cash | credit | mixed
    int? cashBoxId,
    double cashAmount = 0, // للمختلط: الجزء المردود نقداً، والباقي يُنزل من الدين
    int? warehouseId,
    required DateTime date,
    required List<ReturnLine> lines,
    String? notes,
  }) async {
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw ErpException('أضف مادة واحدة على الأقل بكمية أكبر من صفر');
    for (final l in valid) {
      if (l.price < 0) throw ErpException('سعر سالب للمادة ${l.product.name}');
    }
    if (refundMode != 'cash' && refundMode != 'credit' && refundMode != 'mixed') {
      throw ErpException('طريقة ردّ غير معروفة');
    }
    if (refundMode != 'cash' && customerId == null) {
      throw ErpException('المرتجع على الحساب يحتاج عميلاً مسجّلاً');
    }
    if (refundMode != 'credit' && cashBoxId == null) throw ErpException('اختر الصندوق الذي يُردّ منه المبلغ');
    await PeriodLock.assertOpen(date);

    // التحقق من كميات الفاتورة الأصلية
    if (originalInvoiceId != null) {
      final allowed = await returnableFromInvoice(originalInvoiceId);
      final want = <int, double>{};
      for (final l in valid) {
        want[l.product.id] = (want[l.product.id] ?? 0) + l.baseQty;
      }
      for (final e in want.entries) {
        final a = allowed[e.key] ?? 0;
        if (e.value > a + 1e-6) {
          final name = valid.firstWhere((l) => l.product.id == e.key).product.name;
          throw ErpException('«$name»: الكمية المُرجعة (${fmtQty(e.value)}) أكبر من المتبقي في الفاتورة (${fmtQty(a)})');
        }
      }
    }

    final total = roundMoney(valid.fold(0.0, (s, l) => s + l.total));
    final cashPart = refundMode == 'cash' ? total : (refundMode == 'mixed' ? roundMoney(cashAmount) : 0.0);
    final creditPart = roundMoney(total - cashPart);
    if (refundMode == 'mixed') {
      if (cashPart <= kMoneyEpsilon || cashPart >= total - kMoneyEpsilon) {
        throw ErpException('في المرتجع المختلط يكون المبلغ النقدي أكبر من صفر وأقل من إجمالي المرتجع (${fmtMoney(total)})');
      }
    }
    final db = await erpDb();
    final number = await db.transaction((txn) => nextDocNumber(txn, 'sales_returns', 'return_no'));

    // 1) الأثر على دين العميل أولاً (على الحساب)
    String? txUuid;
    // الكلفة بسعرها يوم البيع (من الفاتورة الأصلية)، وإلا الكلفة الحالية
    final origCosts = originalInvoiceId == null ? const <int, double>{} : await invoiceBaseCosts(originalInvoiceId);
    if (creditPart > kMoneyEpsilon) {
      if (context != null && !context.mounted) throw ErpException('أُغلقت الشاشة');
      txUuid = await CustomerMoney.post(
        context,
        provider: provider,
        customerId: customerId!,
        amount: -creditPart,
        kind: CustomerTxKind.salesReturn,
        note: 'مرتجع مبيعات رقم $number${originalInvoiceId == null ? '' : ' من فاتورة #$originalInvoiceId'}',
        date: date,
        refType: 'sales_return',
      );
    }

    // 2) المستند والمخزون
    try {
      final id = await db.transaction((txn) async {
        var costTotal = 0.0;
        final rid = await txn.insert('sales_returns', {
          'return_no': number,
          'return_date': date.toIso8601String(),
          'customer_id': customerId,
          'customer_name': customerName,
          'original_invoice_id': originalInvoiceId,
          'refund_mode': refundMode,
          'cash_box_id': refundMode == 'credit' ? null : cashBoxId,
          'cash_amount': cashPart,
          'warehouse_id': warehouseId,
          'total': total,
          'cost_total': 0,
          'tx_uuid': txUuid,
          'notes': notes,
          'status': 'posted',
          'created_by': currentUserName(),
          'created_at': DateTime.now().toIso8601String(),
        });
        for (final l in valid) {
          final p = await ErpStock.byId(txn, l.product.id);
          final unitCost = origCosts[l.product.id] ?? p?.cost ?? l.product.cost;
          final lineCost = roundMoney(unitCost * l.baseQty);
          costTotal += lineCost;
          final mv = p != null && p.isService
              ? null
              : await ErpStock.move(txn,
                  productId: l.product.id,
                  baseDelta: l.baseQty,
                  kind: 'sales_return',
                  note: 'مرتجع مبيعات $number',
                  warehouseId: warehouseId);
          await txn.insert('sales_return_items', {
            'return_id': rid,
            'product_id': l.product.id,
            'product_name': l.product.name,
            'sale_type': l.unit.name,
            'units_in_large': l.unit.factor,
            'quantity': l.quantity,
            'base_qty': l.baseQty,
            'price': l.price,
            'total': l.total,
            'unit_cost': unitCost,
            'movement_uuid': mv,
          });
        }
        await txn.update('sales_returns', {'cost_total': roundMoney(costTotal)}, where: 'id = ?', whereArgs: [rid]);
        if (txUuid != null) {
          await txn.update('customer_tx_ext', {'ref_id': rid}, where: 'transaction_uuid = ?', whereArgs: [txUuid]);
        }
        return rid;
      });
      ActivityLog.log('إنشاء', 'مرتجع المبيعات', 'مرتجع رقم $number — $customerName — ${fmtMoney(total)}');
      return id;
    } catch (e) {
      // تعويض: إلغاء أثر الدين إن كان قد سُجّل
      if (txUuid != null && (context == null || context.mounted)) {
        try {
          await CustomerMoney.post(
            context,
            provider: provider,
            customerId: customerId!,
            amount: creditPart,
            kind: CustomerTxKind.salesReturn,
            note: 'إلغاء مرتجع مبيعات رقم $number (فشل الحفظ)',
            date: date,
            refType: 'sales_return',
          );
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// إلغاء مرتجع: تخرج البضاعة ثانية، ويعود المبلغ ديناً (إن كان على الحساب).
  Future<void> voidReturn(BuildContext? context, int id, {String? reason, AppProvider? provider}) async {
    final db = await erpDb();
    final r = await db.query('sales_returns', where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) throw ErpException('المرتجع غير موجود');
    final h = r.first;
    if (h['status'] != 'posted') throw ErpException('المرتجع ملغى مسبقاً');
    await PeriodLock.assertOpen(parseDate(h['return_date']));
    await PeriodLock.assertOpen(DateTime.now());
    final creditPart = returnCreditPart(h);
    if (creditPart > kMoneyEpsilon && h['customer_id'] != null) {
      if (context != null && !context.mounted) throw ErpException('أُغلقت الشاشة');
      await CustomerMoney.post(
        context,
        provider: provider,
        customerId: h['customer_id'] as int,
        amount: creditPart,
        kind: CustomerTxKind.salesReturn,
        note: 'إلغاء مرتجع مبيعات رقم ${h['return_no']}${reason == null || reason.isEmpty ? '' : ' — $reason'}',
        refType: 'sales_return_void',
        refId: id,
      );
    }
    await db.transaction((txn) async {
      final items = await txn.query('sales_return_items', where: 'return_id = ?', whereArgs: [id]);
      for (final it in items) {
        if (it['movement_uuid'] == null) continue;
        await ErpStock.move(txn,
            productId: it['product_id'] as int,
            baseDelta: -d0(it['base_qty']),
            kind: 'sales_return_void',
            note: 'إلغاء مرتجع ${h['return_no']}',
            warehouseId: h['warehouse_id'] as int?);
      }
      await txn.update('sales_returns', {'status': 'void', 'notes': '${h['notes'] ?? ''} [ملغى: ${reason ?? ''}]'},
          where: 'id = ?', whereArgs: [id]);
    });
    ActivityLog.log('إلغاء', 'مرتجع المبيعات', 'إلغاء مرتجع رقم ${h['return_no']} — ${reason ?? ''}');
  }

  Future<List<Map<String, Object?>>> list({DateTime? from, DateTime? to}) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT r.*, (SELECT COUNT(*) FROM sales_return_items i WHERE i.return_id = r.id) AS n_items
      FROM sales_returns r
      WHERE (? IS NULL OR r.return_date >= ?) AND r.return_date < ?
      ORDER BY r.return_date DESC, r.id DESC
    ''', [from == null ? null : isoDay(from), from == null ? null : isoDay(from), isoDayAfter(to ?? DateTime.now())]);
  }

  Future<List<Map<String, Object?>>> items(int id) async {
    final db = await erpDb();
    return db.query('sales_return_items', where: 'return_id = ?', whereArgs: [id], orderBy: 'id');
  }
}
