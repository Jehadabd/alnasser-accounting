import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/supplier.dart';
import '../models/purchase_invoice.dart';
import '../models/supplier_payment.dart';
import '../models/attachment.dart';
import '../models/supplier_invoice_item.dart';
import '../models/supplier_delegate.dart';

import 'database_service.dart';
import 'financial_audit_service.dart';
import '../utils/money_calculator.dart';
import '../services/database/dao/supplier_dao.dart';
import '../services/database/dao/supplier_delegate_dao.dart';

typedef SupplierInvoice = PurchaseInvoice;
typedef SupplierReceipt = SupplierPayment;

class SuppliersService {
  final DatabaseService _dbService = DatabaseService();
  late SupplierDao _supplierDao;
  late SupplierDelegateDao _delegateDao;

  // 🚀 متغير ثابت للتأكد من تشغيل ensureTables مرة واحدة فقط
  static bool _tablesEnsured = false;
  static final List<Supplier> _suppliersCache = [];
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  /// 🚀 التحقق من صلاحية Cache الموردين
  bool get _isCacheValid {
    if (_lastCacheUpdate == null) return false;
    return DateTime.now().difference(_lastCacheUpdate!) < _cacheValidDuration;
  }

  /// 🚀 إبطال Cache الموردين
  void _invalidateSuppliersCache() {
    _lastCacheUpdate = null;
    _suppliersCache.clear();
  }

  SuppliersService() {
    _supplierDao = SupplierDao(getDatabase: () => _dbService.database);
    _delegateDao = SupplierDelegateDao(getDatabase: () => _dbService.database);
  }

  Future<Database> get _db async => _dbService.database;

  /// 🚀 التأكد من وجود الجداول - يعمل مرة واحدة فقط
  Future<void> ensureTables() async {
    // 🚀 تحسين: تشغيل مرة واحدة فقط في الجلسة
    if (_tablesEnsured) return;  // إذا تم التشغيل، لا تعيد
    
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_name TEXT NOT NULL,
        tax_number TEXT,
        phone_number TEXT,
        email_address TEXT,
        address TEXT,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        current_balance REAL NOT NULL DEFAULT 0.0,
        total_purchases REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        invoice_number TEXT,
        invoice_date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0.0,
        amount_paid REAL NOT NULL DEFAULT 0.0,
        currency TEXT NOT NULL DEFAULT 'IQD',
        status TEXT NOT NULL DEFAULT 'آجل',
        payment_type TEXT NOT NULL DEFAULT 'دين',
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');

    // Ensure migration for older databases: add missing columns
    try {
      final cols = await db.rawQuery('PRAGMA table_info(supplier_invoices);');
      final hasPaymentType = cols.any((c) => (c['name'] == 'payment_type'));
      if (!hasPaymentType) {
        await db.execute(
            "ALTER TABLE supplier_invoices ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'دين';");
      }
      final hasAmountPaid = cols.any((c) => (c['name'] == 'amount_paid'));
      if (!hasAmountPaid) {
        await db.execute(
            'ALTER TABLE supplier_invoices ADD COLUMN amount_paid REAL NOT NULL DEFAULT 0.0;');
      }
    } catch (_) {}
    // Migration for suppliers.total_purchases
    try {
      final colsSup = await db.rawQuery('PRAGMA table_info(suppliers);');
      final hasTotalPurchases = colsSup.any((c) => (c['name'] == 'total_purchases'));
      if (!hasTotalPurchases) {
        await db.execute('ALTER TABLE suppliers ADD COLUMN total_purchases REAL NOT NULL DEFAULT 0.0;');
      }
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        receipt_number TEXT,
        receipt_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        delegate_id INTEGER,
        receipt_number TEXT,
        receipt_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE,
        FOREIGN KEY (delegate_id) REFERENCES supplier_delegates(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_delegates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        position TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');

    // Add notes column if it doesn't exist (for existing databases)
    try {
      await db.execute("ALTER TABLE supplier_delegates ADD COLUMN notes TEXT;");
    } catch (e) {}

    // Migration for supplier_payments delegate_id
    try {
      final cols = await db.rawQuery('PRAGMA table_info(supplier_payments);');
      if (!cols.any((c) => c['name'] == 'delegate_id')) {
        await db.execute('ALTER TABLE supplier_payments ADD COLUMN delegate_id INTEGER REFERENCES supplier_delegates(id) ON DELETE SET NULL;');
      }
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_type TEXT NOT NULL,
        owner_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        extracted_text TEXT,
        extraction_confidence REAL,
        uploaded_at TEXT NOT NULL
      )
    ''');
    
    // جدول بنود فواتير الموردين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL,
        unit TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES supplier_invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    
    // 🚀 تم التأكد من الجداول
    _tablesEnsured = true;
  }

  /// 🚀 جلب الموردين مع Cache ذكي
  Future<List<Supplier>> getAllSuppliers() async {
    // 🚀 تحقق من Cache أولاً
    if (_isCacheValid && _suppliersCache.isNotEmpty) {
      return List.from(_suppliersCache);  // نسخة آمنة
    }
    
    await ensureTables();  // سريع الآن (يتخطى إذا تم)
    final db = await _db;
    final rows = await db.query('suppliers', orderBy: 'company_name COLLATE NOCASE');
    final suppliers = rows.map((e) => Supplier.fromMap(e)).toList();
    
    // 🚀 تحديث Cache
    _suppliersCache.clear();
    _suppliersCache.addAll(suppliers);
    _lastCacheUpdate = DateTime.now();
    
    return suppliers;
  }

  /// 🔒 إدراج مورد - يذهب للهارد مباشرة
  Future<int> insertSupplier(Supplier supplier) async {
    await ensureTables();
    final db = await _db;
    final map = supplier.toMap();
    map['last_modified_at'] = DateTime.now().toIso8601String();
    final result = await db.insert('suppliers', map);
    
    // 🚀 إبطال Cache بعد الكتابة
    _invalidateSuppliersCache();
    
    return result;
  }

  Future<int> insertSupplierInvoice(SupplierInvoice invoice) async {
    await ensureTables();
    final db = await _db;
    
    int invoiceId = await db.transaction((txn) async {
      final id = await txn.insert('supplier_invoices', invoice.toMap());
      final double remaining = MoneyCalculator.subtract(invoice.totalAmount, invoice.paidAmount);
      
      // Update supplier balance and total purchases
      final supplierRows = await txn.query('suppliers', where: 'id = ?', whereArgs: [invoice.supplierId]);
      if (supplierRows.isNotEmpty) {
         final s = Supplier.fromMap(supplierRows.first);
         final newTotalPurchases = s.totalPurchases + invoice.totalAmount;
         // If remaining > 0, debt increases (currentBalance increases)
         final double balanceChange = remaining > 0 ? remaining : 0.0;
         final newBalance = s.currentBalance + balanceChange;
         
         await txn.update('suppliers', {
           'total_purchases': newTotalPurchases,
           'current_balance': newBalance,
           'last_modified_at': DateTime.now().toIso8601String(),
         }, where: 'id = ?', whereArgs: [invoice.supplierId]);
      }
      return id;
    });
    
    // Audit log
    try {
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: 'supplier_invoice_create',
        entityType: 'supplier',
        entityId: invoice.supplierId,
        newValues: {
          'invoice_id': invoiceId,
          'total_amount': invoice.totalAmount,
          'amount_paid': invoice.paidAmount,
          'status': invoice.status,
        },
        notes: 'فاتورة مورد جديدة بقيمة ${invoice.totalAmount}',
      );
    } catch (e) {
      print('خطأ في تسجيل التدقيق: $e');
    }
    
    return invoiceId;
  }

  Future<int> insertSupplierReceipt(SupplierReceipt receipt) async {
    await ensureTables();
    final db = await _db;
    
    int receiptId = await db.transaction((txn) async {
      final id = await txn.insert('supplier_payments', receipt.toMap());
      
      // Update supplier balance (payment reduces debt)
      final supplierRows = await txn.query('suppliers', where: 'id = ?', whereArgs: [receipt.supplierId]);
      if (supplierRows.isNotEmpty) {
        final s = Supplier.fromMap(supplierRows.first);
        final newBalance = s.currentBalance - receipt.amount;
        
        await txn.update('suppliers', {
          'current_balance': newBalance,
          'last_modified_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [receipt.supplierId]);
      }
      return id;
    });
    
    // Audit log
    try {
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: 'supplier_payment_create',
        entityType: 'supplier',
        entityId: receipt.supplierId,
        newValues: {
          'receipt_id': receiptId,
          'amount': receipt.amount,
        },
        notes: 'سند دفع مورد بقيمة ${receipt.amount}',
      );
    } catch (e) {
      print('خطأ في تسجيل التدقيق: $e');
    }
    
    return receiptId;
  }

  Future<int> insertAttachment(Attachment attachment) async {
    await ensureTables();
    final db = await _db;
    return await db.insert('attachments', attachment.toMap());
  }

  Future<String> saveAttachmentFile({required List<int> bytes, required String extension}) async {
    final dir = await getApplicationSupportDirectory();
    final attachmentsDir = Directory(p.join(dir.path, 'attachments'));
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    final fileName = 'att_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = p.join(attachmentsDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }
  
  // --- Delegate Methods ---
  
  Future<List<SupplierDelegate>> getDelegates(int supplierId) async {
    await ensureTables();
    return await _delegateDao.getBySupplierId(supplierId);
  }

  Future<int> addDelegate(SupplierDelegate delegate) async {
    await ensureTables();
    return await _delegateDao.insert(delegate);
  }

  Future<int> updateDelegate(SupplierDelegate delegate) async {
    await ensureTables();
    return await _delegateDao.update(delegate);
  }

  Future<void> deleteDelegate(int id) async {
    await ensureTables();
    await _delegateDao.delete(id);
  }

  Future<List<SupplierInvoice>> getSupplierInvoices(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'supplier_invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return rows.map((e) => SupplierInvoice.fromMap(e)).toList();
  }

  Future<List<SupplierReceipt>> getSupplierReceipts(int supplierId) async {
    await ensureTables();
    final db = await _db;
    // Note: table name is supplier_payments for Invoice/Receipt unification usually, 
    // but code uses supplier_payments mixed with supplier_receipts in sql queries above.
    // I created both tables in ensureTables to be safe, but let's stick to 'supplier_payments' as per insertSupplierReceipt.
    final rows = await db.query(
      'supplier_payments',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return rows.map((e) => SupplierReceipt.fromMap(e)).toList();
  }

  Future<List<Attachment>> getAttachmentsForSupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final invoiceIds = await db.query('supplier_invoices',
        columns: ['id'], where: 'supplier_id = ?', whereArgs: [supplierId]);
    // Checking supplier_payments for receipts
    final receiptIds = await db.query('supplier_payments',
        columns: ['id'], where: 'supplier_id = ?', whereArgs: [supplierId]);
        
    final invIds = invoiceIds.map((e) => e['id'] as int).toList();
    final recIds = receiptIds.map((e) => e['id'] as int).toList();

    final List<Map<String, Object?>> rows = [];
    if (invIds.isNotEmpty) {
      final inPlaceholders = List.filled(invIds.length, '?').join(',');
      final r = await db.rawQuery(
          'SELECT * FROM attachments WHERE owner_type = "SupplierInvoice" AND owner_id IN ($inPlaceholders)',
          invIds);
      rows.addAll(r);
    }
    if (recIds.isNotEmpty) {
      final inPlaceholders = List.filled(recIds.length, '?').join(',');
      final r = await db.rawQuery(
          'SELECT * FROM attachments WHERE owner_type = "SupplierReceipt" AND owner_id IN ($inPlaceholders)',
          recIds);
      rows.addAll(r);
    }
    return rows.map((e) => Attachment.fromMap(e)).toList();
  }

  Future<List<Attachment>> getAttachmentsForOwner({
    required String ownerType,
    required int ownerId,
  }) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('attachments',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: [ownerType, ownerId],
        orderBy: 'uploaded_at DESC');
    return rows.map((e) => Attachment.fromMap(e)).toList();
  }

  // --- Invoice Items Methods ---
  
  Future<int> insertInvoiceItem(SupplierInvoiceItem item) async {
    await ensureTables();
    final db = await _db;
    return await db.insert('supplier_invoice_items', item.toMap());
  }

  Future<List<SupplierInvoiceItem>> getInvoiceItems(int invoiceId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'supplier_invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at ASC',
    );
    return rows.map((e) => SupplierInvoiceItem.fromMap(e)).toList();
  }

  Future<void> deleteInvoiceItems(int invoiceId) async {
    await ensureTables();
    final db = await _db;
    await db.delete(
      'supplier_invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );
  }

  /// Update product costs from invoice items
  /// Update product costs AND STOCK from invoice items
  Future<List<String>> updateProductStatsFromInvoice(int invoiceId) async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔄 Starting updateProductStatsFromInvoice for invoice: $invoiceId');
    
    final items = await getInvoiceItems(invoiceId);
    final db = await _db;
    final List<String> updatedProducts = [];
    
    final Map<int, List<SupplierInvoiceItem>> itemsByProduct = {};
    for (var item in items) {
      if (item.productId != null) {
        itemsByProduct.putIfAbsent(item.productId!, () => []).add(item);
      }
    }
    
    for (var entry in itemsByProduct.entries) {
      final productId = entry.key;
      final productItems = entry.value;
      
      try {
        final productMaps = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        if (productMaps.isEmpty) continue;
        
        final productMap = productMaps.first;
        final unitHierarchyJson = productMap['unit_hierarchy'] as String?;
        final oldCost = (productMap['cost_price'] as num?)?.toDouble() ?? 0.0;
        final productName = productMap['name'] as String;

        // 1. Calculate Stock Increase (handling units)
        double totalStockIncrease = 0.0;
        
        for (var item in productItems) {
           double multiplier = 1.0;
           // If unit is not 'قطعة' (Base Unit), look for multiplier in hierarchy
           if (item.unit != 'قطعة' && item.unit != null && unitHierarchyJson != null) {
              try {
                final List<dynamic> hierarchy = json.decode(unitHierarchyJson);
                int currentCumulative = 1;
                for (var level in hierarchy) {
                   final uName = level['unit_name'];
                   final uQty = level['quantity'] as int? ?? 1;
                   currentCumulative *= uQty;
                   if (uName == item.unit) {
                      multiplier = currentCumulative.toDouble();
                      break;
                   }
                }
              } catch (e) {
                print('Error parsing hierarchy for stock: $e');
              }
           }
           totalStockIncrease += (item.quantity * multiplier);
        }
        
        // 2. Update Stock
        if (totalStockIncrease > 0) {
           await db.rawUpdate(
             'UPDATE products SET stock_quantity = stock_quantity + ? WHERE id = ?',
             [totalStockIncrease, productId],
           );
           print('  📈 $productName: Stock increased by $totalStockIncrease items');
        }

        // 3. Update Cost (Using the item with 'قطعة' or converting from largest unit)
        // Strategy: prefer 'قطعة' item. If not found, use first item and convert cost.
        SupplierInvoiceItem? bestItem;
        for (var item in productItems) {
          if (item.unit == 'قطعة') {
            bestItem = item;
            break;
          }
        }
        bestItem ??= productItems.first;
        
        // Calculate new cost per PIECE
        double newCostPerPiece = bestItem.unitPrice; 
        if (bestItem.unit != 'قطعة' && bestItem.unit != null && unitHierarchyJson != null) {
            try {
                final List<dynamic> hierarchy = json.decode(unitHierarchyJson);
                int currentCumulative = 1;
                double conversion = 1.0;
                 for (var level in hierarchy) {
                   final uName = level['unit_name'];
                   final uQty = level['quantity'] as int? ?? 1;
                   currentCumulative *= uQty;
                   if (uName == bestItem!.unit) {
                      conversion = currentCumulative.toDouble();
                      break;
                   }
                }
                if (conversion > 0) {
                  newCostPerPiece = bestItem.unitPrice / conversion;
                }
            } catch(e) {
               print('Error converting cost: $e');
            }
        }
        
        // Only update if cost changed significantly
        if ((oldCost - newCostPerPiece).abs() > 0.01) {
          String? newUnitCosts;
          final unit = productMap['unit'] as String?;
          
          if (unit == 'piece' && unitHierarchyJson != null && unitHierarchyJson.isNotEmpty) {
            try {
              final List<dynamic> hierarchy = json.decode(unitHierarchyJson);
              final Map<String, double> unitCosts = {};
              double currentCost = newCostPerPiece;
              unitCosts['قطعة'] = currentCost;
              
              for (var level in hierarchy) {
                final unitName = level['unit_name'] as String?;
                final qty = level['quantity'] as int?;
                if (unitName != null && qty != null && qty > 0) {
                  currentCost = currentCost * qty;
                  unitCosts[unitName] = currentCost;
                }
              }
              newUnitCosts = json.encode(unitCosts);
            } catch (e) {
              print('Error calculating unit costs: $e');
            }
          } else if (unit == 'meter') {
             final lengthPerUnit = (productMap['length_per_unit'] as num?)?.toDouble() ?? 0.0;
             if (lengthPerUnit > 0) {
               newUnitCosts = json.encode({
                 'متر': newCostPerPiece,
                 'لفة': newCostPerPiece * lengthPerUnit,
               });
             }
          }
          
          if (newUnitCosts != null) {
            await db.rawUpdate(
              'UPDATE products SET cost_price = ?, unit_costs = ?, last_modified_at = ? WHERE id = ?',
              [newCostPerPiece, newUnitCosts, DateTime.now().toIso8601String(), productId],
            );
          } else {
            await db.rawUpdate(
              'UPDATE products SET cost_price = ?, last_modified_at = ? WHERE id = ?',
              [newCostPerPiece, DateTime.now().toIso8601String(), productId],
            );
          }
          updatedProducts.add('$productName: ${oldCost.toStringAsFixed(2)} -> ${newCostPerPiece.toStringAsFixed(2)}');
        }
      } catch (e) {
        print('Error updating product $productId: $e');
      }
    }
    return updatedProducts;
  }
}
