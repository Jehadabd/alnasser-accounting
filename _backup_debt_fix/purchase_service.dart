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
    final result = await db.rawQuery('SELECT MAX(receipt_number) as max_num FROM supplier_payments');
    final maxNum = result.first['max_num'] as int?;
    return (maxNum ?? 0) + 1;
  }

  // --- Invoice Actions ---
  
  /// تعديل فاتورة مشتريات موجودة مع إرجاع التأثيرات السابقة وتطبيق التأثيرات الجديدة
  Future<void> updatePurchaseInvoiceWithReversal(PurchaseInvoice oldInvoice, PurchaseInvoice newInvoice, List<PurchaseInvoiceItem> oldItems, List<PurchaseInvoiceItem> newItems) async {
    final db = await _db.database;
    
    String costingMethod = 'last_purchase';
    try {
      final settings = await SettingsManager.getAppSettings();
      costingMethod = settings.costingMethod;
    } catch (e) {
      print('Warning: Could not load costingMethod: $e');
    }
    
    await db.transaction((txn) async {
      // 1. Revert Old Effects (if invoice was confirmed)
      if (oldInvoice.status == 'confirmed') {
        for (var item in oldItems) {
          await _reverseProductStock(txn, item);
        }
        await _reverseSupplierDebtOnInvoice(txn, oldInvoice.supplierId, oldInvoice.totalAmount, oldInvoice.paidAmount, oldInvoice.currency);
      }
      
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
          await _updateProductStockAndCost(txn, item, costingMethod);
        }
        await _updateSupplierDebtOnInvoice(txn, newInvoice.supplierId, newInvoice.totalAmount, newInvoice.paidAmount, newInvoice.currency);
      }
    });
    
    notifyListeners();
  }

  Future<void> savePurchaseInvoice(PurchaseInvoice invoice, List<PurchaseInvoiceItem> items, {bool confirm = false}) async {
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
    
    await db.transaction((txn) async {
      // 1. Insert/Update Invoice
      int invoiceId;
      final invoiceMap = invoice.toMap();
      invoiceMap.remove('id');
      
      if (invoice.id != null) {
        invoiceId = invoice.id!;
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

      // 3. If Confirmed, Update Stock, Cost, and Debt
      if (confirm && invoice.status == 'confirmed') {
        for (var item in items) {
          await _updateProductStockAndCost(txn, item, costingMethod);
        }
        await _updateSupplierDebtOnInvoice(txn, invoice.supplierId, invoice.totalAmount, invoice.paidAmount, invoice.currency);
        await _updateSupplierInvoiceCount(txn, invoice.supplierId);
      }
    });

    notifyListeners();
  }

  Future<void> _updateProductStockAndCost(Transaction txn, PurchaseInvoiceItem item, String costingMethod) async {
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
      double totalOldValue = currentStock * currentCost;
      double totalNewValue = newQty * newUnitCost;
      finalCost = totalQty > 0 ? (totalOldValue + totalNewValue) / totalQty : newUnitCost;
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
        'stock_quantity': totalQty,
        'cost_price': finalCost,
        'unit_costs': unitCostsJson,
      },
      where: 'id = ?',
      whereArgs: [item.productId],
    );
    
    print('💾 DB_UPDATE: ✅ Product updated successfully!');
  }

  Future<void> _reverseProductStock(Transaction txn, PurchaseInvoiceItem item) async {
    final List<Map<String, dynamic>> products = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
    if (products.isEmpty) return;
    
    final product = products.first;
    double currentStock = (product['stock_quantity'] as num?)?.toDouble() ?? 0.0;
    double oldQty = item.baseQuantity;
    
    double newStock = currentStock - oldQty;
    if (newStock < 0) newStock = 0.0; // Prevent negative stock due to manual edits
    
    await txn.update(
      'products', 
      {'stock_quantity': newStock},
      where: 'id = ?',
      whereArgs: [item.productId],
    );
  }

  Future<void> _updateSupplierDebtOnInvoice(Transaction txn, int supplierId, double totalAmount, double paidAmount, String currency) async {
    final List<Map<String, dynamic>> suppliers = await txn.query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
    if (suppliers.isEmpty) return;

    double addedDebt = totalAmount - paidAmount;
    
    // Update the correct currency debt column
    if (currency == 'USD') {
      double currentDebt = (suppliers.first['total_debt_usd'] as num?)?.toDouble() ?? 0.0;
      await txn.update(
        'suppliers',
        {'total_debt_usd': currentDebt + addedDebt},
        where: 'id = ?',
        whereArgs: [supplierId],
      );
    } else {
      double currentDebt = (suppliers.first['total_debt_iqd'] as num?)?.toDouble() ?? 0.0;
      await txn.update(
        'suppliers',
        {'total_debt_iqd': currentDebt + addedDebt},
        where: 'id = ?',
        whereArgs: [supplierId],
      );
    }
  }

  Future<void> _reverseSupplierDebtOnInvoice(Transaction txn, int supplierId, double totalAmount, double paidAmount, String currency) async {
    final List<Map<String, dynamic>> suppliers = await txn.query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
    if (suppliers.isEmpty) return;

    double subtractedDebt = totalAmount - paidAmount;
    
    if (currency == 'USD') {
      double currentDebt = (suppliers.first['total_debt_usd'] as num?)?.toDouble() ?? 0.0;
      await txn.update(
        'suppliers',
        {'total_debt_usd': currentDebt - subtractedDebt},
        where: 'id = ?',
        whereArgs: [supplierId],
      );
    } else {
      double currentDebt = (suppliers.first['total_debt_iqd'] as num?)?.toDouble() ?? 0.0;
      await txn.update(
        'suppliers',
        {'total_debt_iqd': currentDebt - subtractedDebt},
        where: 'id = ?',
        whereArgs: [supplierId],
      );
    }
  }

  Future<void> _updateSupplierInvoiceCount(Transaction txn, int supplierId) async {
    await txn.rawUpdate(
      'UPDATE suppliers SET total_invoices = total_invoices + 1 WHERE id = ?',
      [supplierId],
    );
  }

  Future<void> _updateSupplierPaymentCount(Transaction txn, int supplierId) async {
    await txn.rawUpdate(
      'UPDATE suppliers SET total_payments = total_payments + 1 WHERE id = ?',
      [supplierId],
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
      await txn.insert('supplier_payments', paymentMap);

      // 2. Update Supplier Debt (Decrease based on currency)
      final List<Map<String, dynamic>> suppliers = await txn.query('suppliers', where: 'id = ?', whereArgs: [payment.supplierId]);
      if (suppliers.isNotEmpty) {
        if (payment.currency == 'USD') {
          double currentDebt = (suppliers.first['total_debt_usd'] as num?)?.toDouble() ?? 0.0;
          await txn.update(
            'suppliers',
            {'total_debt_usd': (currentDebt - payment.amount).clamp(0.0, double.infinity)},
            where: 'id = ?',
            whereArgs: [payment.supplierId],
          );
        } else {
          double currentDebt = (suppliers.first['total_debt_iqd'] as num?)?.toDouble() ?? 0.0;
          await txn.update(
            'suppliers',
            {'total_debt_iqd': (currentDebt - payment.amount).clamp(0.0, double.infinity)},
            where: 'id = ?',
            whereArgs: [payment.supplierId],
          );
        }
      }

      // 3. Update payment count
      await _updateSupplierPaymentCount(txn, payment.supplierId);
    });

    notifyListeners();
  }
}
