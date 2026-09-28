import 'dart:convert';
import 'package:sqflite/sqflite.dart'; // For Transaction
import 'package:flutter/foundation.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_invoice_item.dart';
import '../models/supplier.dart';
import '../models/supplier_payment.dart';
import '../models/supplier_delegate.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import '../services/database/business/supplier_debt_reconciler.dart';
import '../services/database/business/stock_ledger.dart'; // 📦 دفتر المخزون المشترك
import '../erp/activity/activity_log.dart';

/// خدمة المشتريات والموردين (Odoo-Style)
class PurchaseService with ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  // --- Suppliers ---
  Future<List<Supplier>> getSuppliers({String query = ''}) async {
    final db = await _db.database;
    String whereClause = '';
    List<dynamic> args = [];

    if (query.isNotEmpty) {
      whereClause = 'WHERE name LIKE ? OR phone LIKE ?';
      args = ['%$query%', '%$query%'];
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT * FROM suppliers $whereClause ORDER BY name ASC',
      args,
    );

    return List.generate(maps.length, (i) => Supplier.fromMap(maps[i]));
  }

  Future<Supplier?> getSupplierById(int id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Supplier.fromMap(maps.first);
  }

  Future<int> addSupplier(Supplier supplier) async {
    final db = await _db.database;
    final supplierMap = supplier.toMap();
    supplierMap.remove('id');
    final id = await db.insert('suppliers', supplierMap);
    notifyListeners();
    return id;
  }

  Future<void> updateSupplier(Supplier supplier) async {
    final db = await _db.database;
    await db.update(
      'suppliers',
      supplier.toMap(),
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
    notifyListeners();
  }

  Future<void> deleteSupplier(int id) async {
    final db = await _db.database;
    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // --- Purchase Invoices ---
  Future<List<PurchaseInvoice>> getInvoicesForSupplier(int supplierId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchase_invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => PurchaseInvoice.fromMap(maps[i]));
  }

  Future<List<PurchaseInvoice>> getInvoicesForDelegate(int delegateId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchase_invoices',
      where: 'delegate_id = ?',
      whereArgs: [delegateId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => PurchaseInvoice.fromMap(maps[i]));
  }

  Future<PurchaseInvoice?> getInvoiceById(int id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchase_invoices',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return PurchaseInvoice.fromMap(maps.first);
  }

  Future<List<PurchaseInvoiceItem>> getInvoiceItems(int invoiceId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT pii.*, p.name as product_name
      FROM purchase_invoice_items pii
      LEFT JOIN products p ON pii.product_id = p.id
      WHERE pii.invoice_id = ?
    ''', [invoiceId]);
    return List.generate(maps.length, (i) => PurchaseInvoiceItem.fromMap(maps[i]));
  }



  // --- Supplier Payments ---


  Future<List<SupplierPayment>> getPaymentsForSupplier(int supplierId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'supplier_payments',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => SupplierPayment.fromMap(maps[i]));
  }

  Future<int> _getNextReceiptNumber() async {
    final db = await _db.database;
    // 🛡️ receipt_number عمود نصّي؛ قراءته مباشرةً كـ int كانت ترمي استثناءً
    // عند أول سند. نحوّله صراحةً قبل أخذ الأكبر.
    final result = await db.rawQuery(
        'SELECT MAX(CAST(receipt_number AS INTEGER)) as max_num FROM supplier_payments');
    final maxNum = (result.first['max_num'] as num?)?.toInt();
    return (maxNum ?? 0) + 1;
  }

  // --- Invoice Actions ---
  
  /// تعديل فاتورة مشتريات موجودة مع إرجاع التأثيرات السابقة وتطبيق التأثيرات الجديدة
  Future<void> updatePurchaseInvoiceWithReversal(PurchaseInvoice oldInvoice, PurchaseInvoice newInvoice, List<PurchaseInvoiceItem> oldItems, List<PurchaseInvoiceItem> newItems,
      {int? warehouseId, int? cashBoxId}) async {
    final db = await _db.database;
    
    String costingMethod = 'last_purchase';
    try {
      final settings = await SettingsManager.getAppSettings();
      costingMethod = settings.costingMethod;
    } catch (e) {
      print('Warning: Could not load costingMethod: $e');
    }
    
    await db.transaction((txn) async {
      // 1. عكس أثر المخزون القديم (الدين يتكفّل به الحارس المحاسبي لاحقاً)
      //    🛡️ الحالة القديمة تُقرأ من قاعدة البيانات لا من الكائن الممرَّر:
      //    كائن الشاشة قد يكون قديماً، وهذا بالضبط ما ضاعف ديون العملاء سابقاً.
      final oldRows = await txn.query('purchase_invoices',
          columns: ['status'], where: 'id = ?', whereArgs: [oldInvoice.id], limit: 1);
      final String oldStatus =
          oldRows.isEmpty ? 'draft' : ((oldRows.first['status'] as String?) ?? 'draft');

      // 🏬 المخزن القديم للفاتورة (العكس يعود إليه نفسه)
      final oldExt = await PurchaseExt.read(txn, oldInvoice.id!);
      if (oldStatus == 'confirmed') {
        for (var item in oldItems) {
          await _reverseProductStock(txn, item, warehouseId: oldExt.warehouseId);
        }
      }
      await PurchaseExt.write(txn, oldInvoice.id!, warehouseId: warehouseId, cashBoxId: cashBoxId);
      
      // 2. Delete Old Items
      await txn.delete('purchase_invoice_items', where: 'invoice_id = ?', whereArgs: [oldInvoice.id]);
      
      // 3. Update Invoice Record
      final invoiceMap = newInvoice.toMap();
      invoiceMap.remove('id');
      await txn.update('purchase_invoices', invoiceMap, where: 'id = ?', whereArgs: [oldInvoice.id]);
      
      // 4. Insert New Items
      for (var item in newItems) {
        final itemMap = item.toMap();
        itemMap['invoice_id'] = oldInvoice.id;
        itemMap.remove('id');
        itemMap.remove('product_name');
        await txn.insert('purchase_invoice_items', itemMap);
      }
      
      // 5. Apply New Effects (if new invoice is confirmed)
      if (newInvoice.status == 'confirmed') {
        for (var item in newItems) {
          await _updateProductStockAndCost(txn, item, costingMethod, warehouseId: warehouseId);
        }
      }

      // 6. 🛡️ الحارس المحاسبي: مساهمة الفاتورة = الإجمالي − المدفوع (للمؤكدة)
      //    إدمبوتنت ويقرأ الصف من قاعدة البيانات، فلا عكسٌ ولا تراكم.
      await SupplierDebtReconciler.reconcileInvoice(txn, oldInvoice.id!,
          reason: 'تعديل');
    });
    ActivityLog.log('تعديل', 'فواتير الشراء', 'تعديل فاتورة شراء ${newInvoice.invoiceNumber} — ${newInvoice.totalAmount}');
    
    notifyListeners();
  }

  Future<void> savePurchaseInvoice(PurchaseInvoice invoice, List<PurchaseInvoiceItem> items,
      {bool confirm = false, int? warehouseId, int? cashBoxId}) async {
    final db = await _db.database;
    
    // Load costing method from settings
    String costingMethod = 'last_purchase'; // Default
    try {
      final settings = await SettingsManager.getAppSettings();
      costingMethod = settings.costingMethod;
      print('📊 Loaded costingMethod from settings: $costingMethod');
    } catch (e) {
      print('Warning: Could not load costingMethod from settings: $e');
    }
    
    // الحالة المؤكدة تُحسم هنا مرة واحدة، ويُكتب أثرها في الصف نفسه، كي
    // يقرأها الحارس المحاسبي لاحقاً من قاعدة البيانات لا من معطيات الاستدعاء.
    final bool nowConfirmed = confirm || invoice.status == 'confirmed';

    await db.transaction((txn) async {
      // 1. Insert/Update Invoice
      int invoiceId;
      final invoiceMap = invoice.toMap();
      invoiceMap.remove('id');
      if (nowConfirmed) invoiceMap['status'] = 'confirmed';
      
      if (invoice.id != null) {
        invoiceId = invoice.id!;

        // 🛡️ عكس أثر المخزون القديم قبل تطبيق الجديد.
        //    كان هذا المسار يطبّق الأثر الجديد بلا عكس القديم إطلاقاً، فكل
        //    تعديل لفاتورة مؤكدة كان يُضاعف المخزون والدين.
        final oldRows = await txn.query('purchase_invoices',
            columns: ['status'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
        final String oldStatus = oldRows.isEmpty
            ? 'draft'
            : ((oldRows.first['status'] as String?) ?? 'draft');

        if (oldStatus == 'confirmed') {
          final oldExt = await PurchaseExt.read(txn, invoiceId);
          final oldItemRows = await txn.query('purchase_invoice_items',
              where: 'invoice_id = ?', whereArgs: [invoiceId]);
          for (final m in oldItemRows) {
            await _reverseProductStock(txn, PurchaseInvoiceItem.fromMap(m), warehouseId: oldExt.warehouseId);
          }
        }

        await txn.update('purchase_invoices', invoiceMap, where: 'id = ?', whereArgs: [invoiceId]);
        // Delete old items if updating
        await txn.delete('purchase_invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      } else {
        invoiceId = await txn.insert('purchase_invoices', invoiceMap);
      }

      // 2. Insert Items
      for (var item in items) {
        final itemMap = item.toMap();
        itemMap['invoice_id'] = invoiceId;
        itemMap.remove('id');
        itemMap.remove('product_name'); // Not stored in DB
        await txn.insert('purchase_invoice_items', itemMap);
      }

      // 🏬 المخزن المستلم والصندوق/البنك المدفوع منه (امتداد محلي)
      await PurchaseExt.write(txn, invoiceId, warehouseId: warehouseId, cashBoxId: cashBoxId);

      // 3. If Confirmed, Update Stock and Cost
      if (nowConfirmed) {
        for (var item in items) {
          await _updateProductStockAndCost(txn, item, costingMethod, warehouseId: warehouseId);
        }
      }

      // 4. 🛡️ الحارس المحاسبي — يتولّى الدين والعدّادات معاً.
      //    عدّادا total_invoices و total_payments صارا مشتقّين بالعدّ بدل
      //    عدّاد تراكمي كان يزيد ولا ينقص أبداً.
      await SupplierDebtReconciler.reconcileInvoice(txn, invoiceId,
          reason: invoice.id != null ? 'تعديل' : 'حفظ');
    });
    ActivityLog.log(invoice.id != null ? 'تعديل' : 'إنشاء', 'فواتير الشراء',
        'فاتورة شراء ${invoice.invoiceNumber} — ${invoice.totalAmount}${nowConfirmed ? ' (مؤكدة)' : ' (مسودة)'}');

    notifyListeners();
  }

  Future<void> _updateProductStockAndCost(Transaction txn, PurchaseInvoiceItem item, String costingMethod,
      {int? warehouseId}) async {
    print('💾 DB_UPDATE: Starting stock/cost update for product ID: ${item.productId}');
    print('💾 DB_UPDATE: Item baseQuantity: ${item.baseQuantity}, baseUnitCost: ${item.baseUnitCost}');
    print('💾 DB_UPDATE: Costing method: $costingMethod');
    
    final List<Map<String, dynamic>> products = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
    if (products.isEmpty) {
      print('💾 DB_UPDATE: ❌ Product not found!');
      return;
    }
    
    final product = products.first;
    double currentStock = (product['stock_quantity'] as num?)?.toDouble() ?? 0.0;
    double currentCost = (product['cost_price'] as num?)?.toDouble() ?? 0.0;
    String? currentUnitCosts = product['unit_costs'] as String?;
    String baseUnit = product['unit'] as String? ?? 'piece';

    print('💾 DB_UPDATE: Current stock: $currentStock, Current cost: $currentCost');

    // Calculate new quantity in base units (e.g., pieces)
    double newQty = item.baseQuantity;
    
    // Calculate new cost per base unit from this purchase
    double newUnitCost = item.baseUnitCost;

    double totalQty = currentStock + newQty;
    double finalCost;

    if (costingMethod == 'avco') {
      // Weighted Average Cost Formula (AVCO):
      // ((OldStock * OldCost) + (NewQty * NewCost)) / (OldStock + NewQty)
      // 🛡️ المخزون السالب (بيع متزامن على جهازين) بِيع فعلاً بالكلفة القديمة:
      // لا يدخل في المتوسط. كان يدخل بقيمة سالبة فتخرج الكلفة أضعاف السعر
      // (−19 بكلفة 5 ثم شراء 20 بـ 6 ← 25 بدل 6).
      final costBasisQty = currentStock > 0 ? currentStock : 0.0;
      double totalOldValue = costBasisQty * currentCost;
      double totalNewValue = newQty * newUnitCost;
      final basisTotal = costBasisQty + newQty;
      finalCost = basisTotal > 0 ? (totalOldValue + totalNewValue) / basisTotal : newUnitCost;
      print('💾 DB_UPDATE: Using AVCO - New stock: $totalQty, New avg cost: $finalCost');
    } else {
      // Last Purchase Price - simply use the new unit cost
      finalCost = newUnitCost;
      print('💾 DB_UPDATE: Using Last Purchase Price - New stock: $totalQty, New cost: $finalCost');
    }

    // ✅ Also update unitCosts to keep in sync with cost_price
    // This is used by reports and invoice creation screens
    Map<String, dynamic> updatedUnitCosts = {};
    if (currentUnitCosts != null && currentUnitCosts.isNotEmpty) {
      try {
        updatedUnitCosts = Map<String, dynamic>.from(json.decode(currentUnitCosts));
      } catch (e) {
        print('💾 DB_UPDATE: Could not parse existing unitCosts: $e');
      }
    }
    
    // Update base unit cost in unitCosts
    String baseUnitKey = baseUnit == 'piece' ? 'قطعة' : (baseUnit == 'meter' ? 'متر' : baseUnit);
    updatedUnitCosts[baseUnitKey] = finalCost;
    
    // Encode back to JSON
    String unitCostsJson = json.encode(updatedUnitCosts);
    
    print('💾 DB_UPDATE: Updated unitCosts: $unitCostsJson');

    await txn.update(
      'products',
      {
        'cost_price': finalCost,
        'unit_costs': unitCostsJson,
      },
      where: 'id = ?',
      whereArgs: [item.productId],
    );

    // 📦 الكمية: حركة شراء في دفتر المخزون المشترك (تصل لكل الأجهزة؛ بيانات
    //    المورد نفسها تبقى محلية). كانت تُكتب رقماً مطلقاً على هذا الجهاز وحده.
    final productUuid = await StockLedger.productSyncUuidForId(txn, item.productId);
    if (productUuid != null) {
      final mv = await StockLedger.addMovement(txn,
          productSyncUuid: productUuid, delta: newQty, kind: 'purchase', note: 'فاتورة شراء');
      await PurchaseExt.stampWarehouse(txn, mv, warehouseId);
    }

    print('💾 DB_UPDATE: ✅ Product updated successfully!');
  }

  Future<void> _reverseProductStock(Transaction txn, PurchaseInvoiceItem item, {int? warehouseId}) async {
    final List<Map<String, dynamic>> products = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
    if (products.isEmpty) return;
    
    // 📦 إلغاء أثر فاتورة شراء (تعديلها أو حذفها): حركة عكسية في الدفتر.
    //    لا حدّ عند الصفر — كان يجعل الكمية تتوقف على ترتيب العمليات.
    final productUuid = await StockLedger.productSyncUuidForId(txn, item.productId);
    if (productUuid == null) return;
    final mv = await StockLedger.addMovement(txn,
        productSyncUuid: productUuid,
        delta: -item.baseQuantity,
        kind: 'purchase_reverse',
        note: 'إلغاء/تعديل فاتورة شراء');
    await PurchaseExt.stampWarehouse(txn, mv, warehouseId);
  }

  // ⚠️ حُذفت هنا أربع دوال تراكمية:
  //   _updateSupplierDebtOnInvoice / _reverseSupplierDebtOnInvoice
  //   _updateSupplierInvoiceCount  / _updateSupplierPaymentCount
  //
  // الأوليان كانتا تزيدان وتنقصان `total_debt_iqd` مباشرةً بمبالغ يمرّرها
  // المستدعي من كائن قد يكون قديماً — نفس علّة «الحالة 2» التي ضاعفت ديون
  // العملاء. والأخريان عدّادان يزيدان بواحد ولا ينقصان أبداً.
  //
  // البديل: SupplierDebtReconciler — دين المورد = مجموع حركات دفتره،
  // والعدّادات تُحسب بالعدّ لا بالتراكم.

  /// كشف حساب المورد: حركاته مرتّبة زمنياً (دين موجب، دفعة سالبة).
  Future<List<Map<String, dynamic>>> getSupplierLedger(int supplierId) async {
    final db = await _db.database;
    // 🛡️ شبكة أمان: وفّق مساهمات الفواتير قبل العرض
    try {
      await db.transaction((txn) async {
        await SupplierDebtReconciler.reconcileSupplierLedger(txn, supplierId,
            reason: 'عرض كشف الحساب');
      });
    } catch (e) {
      print('⚠️ تعذّرت تسوية دفتر المورد قبل العرض: $e');
    }
    return db.query(
      'supplier_transactions',
      where: 'supplier_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [supplierId],
      orderBy: 'transaction_date DESC, id DESC',
    );
  }

  // --- Delegates ---
  Future<List<SupplierDelegate>> getDelegatesForSupplier(int supplierId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'supplier_delegates',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
    );
    return List.generate(maps.length, (i) => SupplierDelegate.fromMap(maps[i]));
  }

  Future<int> addDelegate(SupplierDelegate delegate) async {
    final db = await _db.database;
    final map = delegate.toMap();
    map.remove('id');
    final id = await db.insert('supplier_delegates', map);
    notifyListeners();
    return id;
  }

  // --- Payment Actions ---
  Future<void> registerPayment(SupplierPayment payment) async {
    final db = await _db.database;
    final receiptNumber = await _getNextReceiptNumber();
    
    await db.transaction((txn) async {
      // 1. Insert Payment with receipt number
      final paymentMap = payment.toMap();
      paymentMap.remove('id');
      paymentMap['receipt_number'] = receiptNumber;
      final paymentId = await txn.insert('supplier_payments', paymentMap);

      // 2. 🛡️ تُسجَّل الدفعة كحركة في دفتر المورد، والرصيد يُشتق من مجموع
      //    الحركات. لا `clamp` هنا عمداً: الدفع الزائد كان يُمحى بصمت،
      //    والصحيح أن يصير رصيداً لنا عند المورد.
      await SupplierDebtReconciler.recordPayment(
        txn,
        paymentId: paymentId,
        supplierId: payment.supplierId,
        amount: payment.amount,
        currency: payment.currency,
        description: payment.notes == null || payment.notes!.isEmpty
            ? 'سند دفع رقم $receiptNumber'
            : 'سند دفع رقم $receiptNumber — ${payment.notes}',
        date: payment.date.toIso8601String(),
      );
    });

    notifyListeners();
  }
}


/// 🏬 امتداد فاتورة الشراء (مثل سهل): المخزن المستلم والصندوق/البنك المدفوع منه.
/// جدول محلي `purchase_invoice_ext`؛ الفاتورة نفسها ودين المورد لا يتغيران.
class PurchaseExt {
  PurchaseExt(this.warehouseId, this.cashBoxId);
  final int? warehouseId;
  final int? cashBoxId;

  static Future<void> _ensure(DatabaseExecutor d) => d.execute('''
    CREATE TABLE IF NOT EXISTS purchase_invoice_ext (
      invoice_id INTEGER PRIMARY KEY,
      warehouse_id INTEGER,
      cash_box_id INTEGER
    )''');

  static Future<PurchaseExt> read(DatabaseExecutor d, int invoiceId) async {
    await _ensure(d);
    final r = await d.query('purchase_invoice_ext', where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
    if (r.isEmpty) return PurchaseExt(null, null);
    return PurchaseExt(r.first['warehouse_id'] as int?, r.first['cash_box_id'] as int?);
  }

  static Future<void> write(DatabaseExecutor d, int invoiceId, {int? warehouseId, int? cashBoxId}) async {
    await _ensure(d);
    if (warehouseId == null && cashBoxId == null) {
      await d.delete('purchase_invoice_ext', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      return;
    }
    await d.insert('purchase_invoice_ext', {'invoice_id': invoiceId, 'warehouse_id': warehouseId, 'cash_box_id': cashBoxId},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// يربط حركة المخزون بمخزن غير الرئيسي (الرئيسي = الكلي − غيره فلا يُختم).
  static Future<void> stampWarehouse(DatabaseExecutor d, String? movementUuid, int? warehouseId) async {
    if (movementUuid == null || warehouseId == null) return;
    final main = await d.query('warehouses', columns: ['id'], where: 'is_default = 1', orderBy: 'id', limit: 1);
    final mainId = main.isEmpty ? 1 : main.first['id'] as int;
    if (warehouseId == mainId) return;
    await d.update('stock_movements', {'warehouse_id': warehouseId},
        where: 'movement_uuid = ?', whereArgs: [movementUuid]);
  }
}
