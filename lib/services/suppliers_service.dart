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
import 'database/business/stock_ledger.dart'; // 📦 دفتر المخزون المشترك
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

    // ⚠️ حُذفت من هنا تعريفات: suppliers / supplier_invoices / supplier_receipts
    //    / supplier_payments / supplier_invoice_items / supplier_delegates.
    //
    // كانت تُعرّف الجداول نفسها التي يُعرّفها DatabaseMigrations بأعمدة مختلفة
    // تماماً (company_name مقابل name، current_balance مقابل total_debt_iqd،
    // supplier_invoices مقابل purchase_invoices...). وبما أن الطرفين يستخدمان
    // CREATE TABLE IF NOT EXISTS فمن ينشئ الجدول أولاً يفرض تعريفه والآخر يجد
    // جدولاً ينقصه كل ما يحتاجه — والخطأ يُبتلع بصمت. لهذا لم تكن وحدة
    // الموردين تعمل إطلاقاً.
    //
    // المرجع الوحيد الآن هو DatabaseMigrations._ensureSupplierSchema.

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
    // 🛡️ العمود اسمه name في مخطط نظام المشتريات (company_name كان مخطط
    //    SuppliersService القديم، وقد لا يوجد إطلاقاً)
    final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
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

  static const String _movedMsg =
      'فواتير وسندات الموردين انتقلت إلى نظام المشتريات (PurchaseService). '
      'استخدم CreatePurchaseInvoiceScreen و registerPayment.';

  /// ⚠️ لم تعد مدعومة — انظر [_movedMsg].
  ///
  /// كانت تُدرج في جدول `supplier_invoices` بمفاتيح نموذج `purchase_invoices`
  /// (`date` و`paid_amount` مقابل `invoice_date` و`amount_paid`)، فترمي
  /// «no such column: date» عند أول محاولة حفظ. ثم تُعدّل `current_balance`
  /// مباشرةً بلا دفتر حركات ولا مسار تعديل أو عكس.
  @Deprecated('استخدم PurchaseService.savePurchaseInvoice')
  Future<int> insertSupplierInvoice(SupplierInvoice invoice) async {
    throw UnsupportedError(_movedMsg);
  }

  /// ⚠️ لم تعد مدعومة — انظر [_movedMsg].
  @Deprecated('استخدم PurchaseService.registerPayment')
  Future<int> insertSupplierReceipt(SupplierReceipt receipt) async {
    throw UnsupportedError(_movedMsg);
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

  /// فواتير المورد — من نظام المشتريات.
  ///
  /// كانت تقرأ من `supplier_invoices` وترتّب بـ `date`، والعمود اسمه
  /// `invoice_date` ⇒ استثناء عند مجرد فتح القائمة.
  Future<List<SupplierInvoice>> getSupplierInvoices(int supplierId) async {
    final db = await _db;
    final rows = await db.query(
      'purchase_invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return rows.map((e) => SupplierInvoice.fromMap(e)).toList();
  }

  /// سندات دفع المورد — من نظام المشتريات.
  Future<List<SupplierReceipt>> getSupplierReceipts(int supplierId) async {
    final db = await _db;
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
           // 📦 حركة شراء في دفتر المخزون المشترك (تصل لكل الأجهزة)
           final productUuid = await StockLedger.productSyncUuidForId(db, productId);
           if (productUuid != null) {
             await StockLedger.addMovement(db,
                 productSyncUuid: productUuid,
                 delta: totalStockIncrease,
                 kind: 'purchase',
                 note: 'فاتورة مورد');
           }
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
