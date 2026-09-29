// lib/erp/purchases/purchase_return_service.dart
//
// ↩️ مرتجع المشتريات (مستند كامل مثل «مر. مشتريات» في الإداري و«مرتجع المشتريات» في سهل):
//   • مستند برقم وتاريخ، مرتبط اختيارياً بفاتورة الشراء الأصلية.
//   • لا يُرجَع أكثر مما اشتُري في الفاتورة (مطروحاً منه ما أُرجع سابقاً)،
//     ولا أكثر من المتوفر في المخزن المختار (إلا بإذن صريح).
//   • طريقة الاسترداد: من دين المورد، أو نقداً إلى صندوق، أو مختلط.
//
// الأمان (معاملة قاعدة بيانات واحدة — كلها أو لا شيء):
//   1. حركات مخزون سالبة عبر دفتر المخزون (ErpStock.move) بالمخزن المختار.
//   2. جزء الدين: حركة مورد «purchase_return» بالسالب ثم إعادة بناء رصيده
//      (نفس المسار الأصلي: دين المورد = مجموع حركاته). لا تُربط برقم الفاتورة
//      حتى لا يعدّها الحارس المحاسبي جزءاً من مساهمة الفاتورة فيلغيها.
//   3. الجزء النقدي: يشتق محرك الترحيل قيده من المستند (مدين الصندوق / دائن المخزون).
//   الإلغاء: حركات مخزون عكسية + حذف منطقي لحركة المورد + إعادة بناء رصيده.

import '../../accounting/ledger.dart';
import '../../accounting/screens/acc_ui.dart' show fmtMoney;
import '../../services/database/business/supplier_debt_reconciler.dart';
import '../../services/firebase_sync/uuid_helper.dart';
import '../activity/activity_log.dart';
import '../erp_common.dart';
import '../stock_helpers.dart';

class PurchaseReturnLine {
  PurchaseReturnLine({required this.product, required this.unit, required this.quantity, required this.price});
  final ProductLite product;
  UnitOption unit;
  double quantity;

  /// سعر الوحدة المختارة بعملة المرتجع.
  double price;

  double get baseQty => quantity * unit.factor;
  double get total => roundMoney(quantity * price);
}

/// الجزء النقدي (بعملة المرتجع).
double purchaseReturnCashPart(Map<String, Object?> r) {
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

double purchaseReturnDebtPart(Map<String, Object?> r) => roundMoney(d0(r['total']) - purchaseReturnCashPart(r));

class PurchaseReturnService {
  /// الكمية المشتراة بالوحدة الأساسية لكل مادة في فاتورة شراء، مطروحاً منها المُرجع.
  Future<Map<int, double>> returnableFromInvoice(int invoiceId) async {
    final db = await erpDb();
    final bought = await db.rawQuery('''
      SELECT product_id AS pid, SUM(quantity * COALESCE(NULLIF(conversion_factor, 0), 1)) AS q
      FROM purchase_invoice_items WHERE invoice_id = ? GROUP BY product_id''', [invoiceId]);
    final returned = await db.rawQuery('''
      SELECT i.product_id AS pid, SUM(i.base_qty) AS q
      FROM purchase_return_items i JOIN purchase_returns r ON r.id = i.return_id
      WHERE r.original_invoice_id = ? AND r.status = 'posted' GROUP BY i.product_id''', [invoiceId]);
    final out = <int, double>{for (final r in bought) r['pid'] as int: d0(r['q'])};
    for (final r in returned) {
      final pid = r['pid'] as int;
      out[pid] = (out[pid] ?? 0) - d0(r['q']);
    }
    return out;
  }

  /// بنود فاتورة الشراء بسعر وحدتها الأساسية (لتعبئة المرتجع).
  Future<List<Map<String, Object?>>> invoiceItems(int invoiceId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT i.product_id, i.unit_name, i.quantity, i.unit_price, COALESCE(NULLIF(i.conversion_factor, 0), 1) AS factor
      FROM purchase_invoice_items i WHERE i.invoice_id = ? ORDER BY i.id''', [invoiceId]);
  }

  Future<Map<String, Object?>?> invoiceHeader(int invoiceId) async {
    final db = await erpDb();
    final r = await db.rawQuery('''
      SELECT p.*, s.name AS supplier_name FROM purchase_invoices p LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.id = ?''', [invoiceId]);
    return r.isEmpty ? null : r.first;
  }

  /// فواتير شراء المورد المؤكدة (الأحدث أولاً).
  Future<List<Map<String, Object?>>> supplierInvoices(int supplierId) async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT id, invoice_number, date, total_amount, currency FROM purchase_invoices
      WHERE supplier_id = ? AND status = 'confirmed' ORDER BY date DESC, id DESC LIMIT 200''', [supplierId]);
  }

  Future<int> create({
    required int supplierId,
    required String supplierName,
    int? originalInvoiceId,
    required String currency,
    double fxRate = 1,
    required String refundMode, // debt | cash | mixed
    double cashAmount = 0,
    int? cashBoxId,
    int? warehouseId,
    required DateTime date,
    required List<PurchaseReturnLine> lines,
    String? notes,
    bool allowNegative = false,
  }) async {
    final valid = lines.where((l) => l.quantity > 0).toList();
    if (valid.isEmpty) throw ErpException('أضف مادة واحدة على الأقل بكمية أكبر من صفر');
    for (final l in valid) {
      if (l.price < 0) throw ErpException('سعر سالب للمادة ${l.product.name}');
      if (l.product.isService) throw ErpException('«${l.product.name}» خدمة — لا تُرجَع للمخزن');
    }
    if (refundMode != 'debt' && refundMode != 'cash' && refundMode != 'mixed') {
      throw ErpException('طريقة استرداد غير معروفة');
    }
    if (currency != 'IQD' && fxRate <= 0) throw ErpException('أدخل سعر الصرف');
    if (refundMode != 'debt' && cashBoxId == null) throw ErpException('اختر الصندوق الذي يُستلم فيه المبلغ');
    final total = roundMoney(valid.fold(0.0, (s, l) => s + l.total));
    if (total <= 0) throw ErpException('قيمة المرتجع يجب أن تكون أكبر من صفر');
    final cashPart = refundMode == 'cash' ? total : (refundMode == 'mixed' ? roundMoney(cashAmount) : 0.0);
    final debtPart = roundMoney(total - cashPart);
    if (refundMode == 'mixed' && (cashPart <= kMoneyEpsilon || cashPart >= total - kMoneyEpsilon)) {
      throw ErpException('في المختلط يكون المبلغ النقدي أكبر من صفر وأقل من الإجمالي (${fmtMoney(total)})');
    }
    await PeriodLock.assertOpen(date);
    final db = await erpDb();

    // لا يُرجَع أكثر مما اشتُري في الفاتورة
    if (originalInvoiceId != null) {
      final h = await invoiceHeader(originalInvoiceId);
      if (h == null) throw ErpException('فاتورة الشراء غير موجودة');
      if (h['supplier_id'] != supplierId) throw ErpException('الفاتورة لمورد آخر');
      if (h['status'] != 'confirmed') throw ErpException('فاتورة الشراء غير مؤكدة');
      final allowed = await returnableFromInvoice(originalInvoiceId);
      final want = <int, double>{};
      for (final l in valid) {
        want[l.product.id] = (want[l.product.id] ?? 0) + l.baseQty;
      }
      for (final e in want.entries) {
        final a = allowed[e.key] ?? 0;
        if (e.value > a + 1e-6) {
          final n = valid.firstWhere((l) => l.product.id == e.key).product.name;
          throw ErpException('«$n»: المُرجع (${fmtQty(e.value)}) أكبر من المتبقي في الفاتورة (${fmtQty(a)})');
        }
      }
    }
    // ولا أكثر من المتوفر في المخزن
    if (!allowNegative) {
      final need = <int, double>{};
      for (final l in valid) {
        need[l.product.id] = (need[l.product.id] ?? 0) + l.baseQty;
      }
      for (final e in need.entries) {
        final avail = await ErpStock.available(db, e.key, warehouseId: warehouseId);
        if (e.value > avail + 1e-6) {
          final n = valid.firstWhere((l) => l.product.id == e.key).product.name;
          throw ErpException('«$n»: المطلوب إرجاعه ${fmtQty(e.value)} والمتوفر في المخزن ${fmtQty(avail)}');
        }
      }
    }

    final id = await db.transaction((txn) async {
      final no = await nextDocNumber(txn, 'purchase_returns', 'return_no');
      String? txUuid;
      final rid = await txn.insert('purchase_returns', {
        'return_no': no,
        'return_date': date.toIso8601String(),
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'original_invoice_id': originalInvoiceId,
        'currency': currency,
        'fx_rate': currency == 'IQD' ? 1.0 : fxRate,
        'refund_mode': refundMode,
        'cash_amount': cashPart,
        'cash_box_id': refundMode == 'debt' ? null : cashBoxId,
        'warehouse_id': warehouseId,
        'total': total,
        'cost_total': 0,
        'notes': notes,
        'status': 'posted',
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
      var cost = 0.0;
      final names = <String>[];
      for (final l in valid) {
        final p = await ErpStock.byId(txn, l.product.id);
        final unitCost = p?.cost ?? l.product.cost;
        cost += roundMoney(unitCost * l.baseQty);
        final mv = await ErpStock.move(txn,
            productId: l.product.id,
            baseDelta: -l.baseQty,
            kind: 'purchase_return',
            note: 'مرتجع مشتريات $no',
            warehouseId: warehouseId);
        await txn.insert('purchase_return_items', {
          'return_id': rid,
          'product_id': l.product.id,
          'product_name': l.product.name,
          'unit_name': l.unit.name,
          'factor': l.unit.factor,
          'quantity': l.quantity,
          'base_qty': l.baseQty,
          'price': l.price,
          'total': l.total,
          'unit_cost': unitCost,
          'movement_uuid': mv,
        });
        names.add('${l.product.name} × ${fmtQty(l.quantity)} ${l.unit.name}');
      }
      if (debtPart > kMoneyEpsilon) {
        txUuid = UuidHelper.newTransactionUuid();
        final now = date.toIso8601String();
        await txn.insert('supplier_transactions', {
          'supplier_id': supplierId,
          'transaction_date': now,
          'amount_changed': -debtPart,
          'currency': currency,
          'balance_before': 0.0,
          'balance_after': 0.0,
          'transaction_type': 'purchase_return',
          'description': 'مرتجع مشتريات رقم $no${originalInvoiceId == null ? '' : ' من فاتورة #$originalInvoiceId'}: ${names.join('، ')}',
          'transaction_uuid': txUuid,
          'is_deleted': 0,
          'created_at': DateTime.now().toIso8601String(),
        });
        await SupplierDebtReconciler.rebuildSupplierBalances(txn, supplierId);
      }
      await txn.update('purchase_returns', {'cost_total': roundMoney(cost), 'tx_uuid': txUuid},
          where: 'id = ?', whereArgs: [rid]);
      return rid;
    });
    ActivityLog.log('إنشاء', 'مرتجع المشتريات', 'مرتجع مشتريات #$id — $supplierName — ${fmtMoney(total)} $currency');
    return id;
  }

  Future<void> voidReturn(int id, {String? reason}) async {
    final db = await erpDb();
    final r = await db.query('purchase_returns', where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) throw ErpException('المرتجع غير موجود');
    final h = r.first;
    if (h['status'] != 'posted') throw ErpException('المرتجع ملغى مسبقاً');
    await PeriodLock.assertOpen(parseDate(h['return_date']));
    await db.transaction((txn) async {
      final items = await txn.query('purchase_return_items', where: 'return_id = ?', whereArgs: [id]);
      for (final it in items) {
        if (it['movement_uuid'] == null) continue;
        await ErpStock.move(txn,
            productId: it['product_id'] as int,
            baseDelta: d0(it['base_qty']),
            kind: 'purchase_return_void',
            note: 'إلغاء مرتجع مشتريات ${h['return_no']}',
            warehouseId: h['warehouse_id'] as int?);
      }
      final tx = h['tx_uuid'] as String?;
      if (tx != null && tx.isNotEmpty) {
        await txn.update('supplier_transactions', {'is_deleted': 1}, where: 'transaction_uuid = ?', whereArgs: [tx]);
        await SupplierDebtReconciler.rebuildSupplierBalances(txn, h['supplier_id'] as int);
      }
      await txn.update('purchase_returns', {'status': 'void', 'notes': '${h['notes'] ?? ''} [ملغى: ${reason ?? ''}]'},
          where: 'id = ?', whereArgs: [id]);
    });
    ActivityLog.log('إلغاء', 'مرتجع المشتريات', 'إلغاء مرتجع مشتريات رقم ${h['return_no']} — ${reason ?? ''}');
  }

  Future<List<Map<String, Object?>>> list({DateTime? from, DateTime? to, int? supplierId}) async {
    final db = await erpDb();
    final where = <String>['r.return_date < ?'];
    final args = <Object?>[isoDayAfter(to ?? DateTime.now())];
    if (from != null) {
      where.add('r.return_date >= ?');
      args.add(isoDay(from));
    }
    if (supplierId != null) {
      where.add('r.supplier_id = ?');
      args.add(supplierId);
    }
    return db.rawQuery('''
      SELECT r.*, w.name AS warehouse_name, b.name AS box_name,
             (SELECT COUNT(*) FROM purchase_return_items i WHERE i.return_id = r.id) AS n_items,
             (SELECT invoice_number FROM purchase_invoices p WHERE p.id = r.original_invoice_id) AS invoice_number
      FROM purchase_returns r LEFT JOIN warehouses w ON w.id = r.warehouse_id LEFT JOIN cash_boxes b ON b.id = r.cash_box_id
      WHERE ${where.join(' AND ')} ORDER BY r.return_date DESC, r.id DESC LIMIT 1000''', args);
  }

  Future<List<Map<String, Object?>>> items(int id) async {
    final db = await erpDb();
    return db.query('purchase_return_items', where: 'return_id = ?', whereArgs: [id], orderBy: 'id');
  }
}
