// lib/services/database/dao/product_dao.dart
// عمليات CRUD للمنتجات

import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/firebase_sync/uuid_helper.dart';
import '../../../models/product.dart';
import '../core/database_helpers.dart';

/// DAO للمنتجات - عمليات CRUD الأساسية
class ProductDao {
  final Future<Database> Function() getDatabase;

  ProductDao({required this.getDatabase});

  /// إضافة منتج جديد
  Future<int> insertProduct(Product product) async {
    final db = await getDatabase();
    try {
      // تطبيع اسم المنتج وحفظه في العمود المطبع
      final productMap = product.toMap();
      productMap['name_norm'] = DatabaseHelpers.normalizeArabic(product.name);

      // 🔄 توليد sync_uuid للمنتج الجديد إن لم يوجد (لمزامنة الكتالوج)
      if (product.syncUuid == null || product.syncUuid!.isEmpty) {
        productMap['sync_uuid'] = UuidHelper.newProductUuid();
      }
      // last_synced_at = null ليُلتقط من قبل مزامنة المنتجات
      productMap['last_synced_at'] = null;
      
      // بناء unit_costs تلقائياً عند وجود تكلفة أساس أو طول/هرمية
      try {
        if (product.costPrice != null && product.costPrice! > 0) {
          final Map<String, dynamic> newUnitCosts = {};
          if (product.unit == 'piece') {
            double currentCost = product.costPrice!;
            newUnitCosts['قطعة'] = currentCost;
            if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                final List<dynamic> hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"')) as List<dynamic>;
                for (final level in hierarchy) {
                  final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                  final double qty = (level['quantity'] is num)
                      ? (level['quantity'] as num).toDouble()
                      : double.tryParse(level['quantity'].toString()) ?? 1.0;
                  currentCost = currentCost * qty;
                  if (unitName.isNotEmpty) {
                    newUnitCosts[unitName] = currentCost;
                  }
                }
              } catch (_) {}
            }
          } else if (product.unit == 'meter') {
            newUnitCosts['متر'] = product.costPrice!;
            if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
              newUnitCosts['لفة'] = product.costPrice! * product.lengthPerUnit!;
            }
          } else {
            newUnitCosts[product.unit] = product.costPrice!;
          }
          productMap['unit_costs'] = jsonEncode(newUnitCosts);
        }
      } catch (e) {
        print('WARN: Failed to build unit_costs on insert: $e');
      }
      
      return await db.insert('products', productMap);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب جميع المنتجات
  Future<List<Product>> getAllProducts({String orderBy = 'name ASC'}) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps =
          await db.query('products', orderBy: orderBy);
      return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب المنتجات لتقارير البضاعة مع التحميل التدريجي (Pagination)
  Future<List<Product>> getPaginatedProductsForReports({
    required int limit,
    required int offset,
    String searchQuery = '',
    bool onlyThisDevice = false,
  }) async {
    final db = await getDatabase();
    try {
      final String searchCondition = searchQuery.isNotEmpty 
          ? " AND (p.name LIKE ? OR p.name_norm LIKE ? OR p.barcode LIKE ?) " 
          : "";
      
      final String deviceFilter = onlyThisDevice ? " AND i.is_created_by_me = 1 " : "";

      final List<dynamic> args = [];
      if (searchQuery.isNotEmpty) {
        final likeQuery = '%$searchQuery%';
        final normalizedQuery = '%${DatabaseHelpers.normalizeArabic(searchQuery)}%';
        args.addAll([likeQuery, normalizedQuery, likeQuery]);
      }
      args.addAll([limit, offset]);

      // ترتيب المنتجات حسب إجمالي الكمية المباعة باستخدام COALESCE و LEFT JOIN
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT p.*, 
          COALESCE((
            SELECT SUM(ii.quantity_individual + (ii.quantity_large_unit * ii.units_in_large_unit))
            FROM invoice_items ii
            JOIN invoices i ON i.id = ii.invoice_id
            WHERE ii.product_name = p.name AND i.status = 'محفوظة' $deviceFilter
          ), 0) as total_quantity_for_sort
        FROM products p
        WHERE 1=1 $searchCondition
        ORDER BY total_quantity_for_sort DESC, p.name ASC
        LIMIT ? OFFSET ?
      ''', args);
      
      return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    } catch (e) {
      print('Error getting paginated products: $e');
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// حذف منتج
  Future<int> deleteProduct(int id) async {
    final db = await getDatabase();
    try {
      return await db.delete(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب منتج بالمعرف
  Future<Product?> getProductById(int productId) async {
    final db = await getDatabase();
    try {
      final maps = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return Product.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// بحث المنتجات العادي
  Future<List<Product>> searchProducts(String query) async {
    final db = await getDatabase();
    try {
      final normalizedQuery = DatabaseHelpers.normalizeArabic(query);
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT * FROM products 
        WHERE name LIKE ? OR name_norm LIKE ? OR barcode LIKE ?
        ORDER BY 
          CASE 
            WHEN name LIKE ? THEN 1
            WHEN name_norm LIKE ? THEN 2
            ELSE 3
          END,
          name ASC
        LIMIT 50
      ''', [
        '%$query%',
        '%$normalizedQuery%',
        '%$query%',
        '$query%',
        '$normalizedQuery%',
      ]);
      
      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// بحث المنتجات بالبادئة
  Future<List<Product>> searchProductsByIdPrefix(String prefix, {int limit = 8}) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT * FROM products 
        WHERE CAST(id AS TEXT) LIKE ?
        ORDER BY id ASC
        LIMIT ?
      ''', ['$prefix%', limit]);
      
      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// تحديث منتج
  Future<int> updateProduct(Product product) async {
    final db = await getDatabase();
    try {
      final productMap = product.toMap();
      productMap['name_norm'] = DatabaseHelpers.normalizeArabic(product.name);
      
      // إعادة بناء unit_costs إذا تغيرت التكلفة
      try {
        if (product.costPrice != null && product.costPrice! > 0) {
          final Map<String, dynamic> newUnitCosts = {};
          if (product.unit == 'piece') {
            double currentCost = product.costPrice!;
            newUnitCosts['قطعة'] = currentCost;
            if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                final List<dynamic> hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"')) as List<dynamic>;
                for (final level in hierarchy) {
                  final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                  final double qty = (level['quantity'] is num)
                      ? (level['quantity'] as num).toDouble()
                      : double.tryParse(level['quantity'].toString()) ?? 1.0;
                  currentCost = currentCost * qty;
                  if (unitName.isNotEmpty) {
                    newUnitCosts[unitName] = currentCost;
                  }
                }
              } catch (_) {}
            }
          } else if (product.unit == 'meter') {
            newUnitCosts['متر'] = product.costPrice!;
            if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
              newUnitCosts['لفة'] = product.costPrice! * product.lengthPerUnit!;
            }
          } else {
            newUnitCosts[product.unit] = product.costPrice!;
          }
          productMap['unit_costs'] = jsonEncode(newUnitCosts);
        }
      } catch (e) {
        print('WARN: Failed to build unit_costs on update: $e');
      }

      // 📝 سجل التعديلات: نقارن القديم بالجديد ونسجّل كل حقل تغيّر
      try {
        final oldRows = await db.query('products',
            where: 'id = ?', whereArgs: [product.id], limit: 1);
        if (oldRows.isNotEmpty) {
          final old = oldRows.first;
          final deviceBatch = await _getDeviceId();
          final batchHist = db.batch();
          _recordFieldDiff(batchHist, product.id, old, productMap, 'name', 'الاسم');
          _recordFieldDiff(batchHist, product.id, old, productMap, 'unit_price', 'السعر الأساسي');
          _recordFieldDiff(batchHist, product.id, old, productMap, 'price1', 'السعر 1');
          _recordFieldDiff(batchHist, product.id, old, productMap, 'price2', 'السعر 2');
          _recordFieldDiff(batchHist, product.id, old, productMap, 'price3', 'السعر 3');
          _recordFieldDiff(batchHist, product.id, old, productMap, 'cost_price', 'سعر التكلفة');
          _recordFieldDiff(batchHist, product.id, old, productMap, 'stock_quantity', 'المخزون');
          if (deviceBatch != null) await batchHist.commit(noResult: true);
        }
      } catch (e) {
        print('WARN: Failed to record product edit history: $e');
      }

      // 🔄 حقول المزامنة: آخر جهاز عدّل + إعادة جدولة الرفع (last_synced_at يصبح
      // أقدم من last_modified_at فتلتقطه syncPendingProducts)
      productMap['last_modified_by_device_id'] = await _getDeviceIdStr();

      return await db.update(
        'products',
        productMap,
        where: 'id = ?',
        whereArgs: [product.id],
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// يسجّل فرق حقل واحد في جدول product_edit_history
  void _recordFieldDiff(dynamic batch, int? productId,
      Map<String, dynamic> old, Map<String, dynamic> newMap,
      String column, String label) {
    final oldVal = old[column]?.toString();
    final newVal = newMap[column]?.toString();
    if (oldVal != newVal) {
      batch.insert('product_edit_history', {
        'product_id': productId,
        'product_sync_uuid': old['sync_uuid'],
        'field_changed': column,
        'old_value': oldVal,
        'new_value': newVal,
        'edit_type': 'manual_edit',
        'device_id': _lastKnownDeviceId,
        'note': 'تعديل $label',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// cache لمعرّف الجهاز (تفادي قراءة التخزين الآمن لكل حقل)
  static String _lastKnownDeviceId = 'local';
  Future<dynamic> _getDeviceId() async {
    _lastKnownDeviceId = await _getDeviceIdStr();
    return _lastKnownDeviceId;
  }

  Future<String> _getDeviceIdStr() async {
    try {
      // استيراد مؤجل لتفادي الاعتماد الدائري مع خدمات المزامنة
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('firebase_sync_device_id') ??
          (prefs.getInt('invoice_device_id') ?? 1).toString();
    } catch (_) {
      return 'local';
    }
  }

  /// البحث الذكي متعدد الطبقات
  Future<List<Product>> searchProductsSmart(String query) async {
    final db = await getDatabase();
    final normalizedQuery = DatabaseHelpers.normalizeArabic(query);
    
    try {
      // المحاولة 1: البحث باستخدام FTS5
      List<Product> results = await _searchWithFTS(db, normalizedQuery);
      if (results.isNotEmpty) return results;
      
      // المحاولة 2: البحث باستخدام LIKE subsequence
      results = await _searchWithLike(db, normalizedQuery);
      if (results.isNotEmpty) return results;
      
      // المحاولة 3: البحث العادي
      return await _fallbackSearch(db, query);
    } catch (e) {
      print('Error in smart search: $e');
      return await _fallbackSearch(db, query);
    }
  }

  /// البحث باستخدام FTS5
  Future<List<Product>> _searchWithFTS(Database db, String normalizedQuery) async {
    try {
      // إصلاح صيغة البحث: استخدام استعلام بسيط يبحث عن النص كبادئة
      // صيغة FTS5 تدعم * كبادئة فقط في نهاية الكلمة أو العبارة
      // تفادي استخدام * في البداية أو بشكل متكرر غير صحيح
      String ftsQuery = '"$normalizedQuery"*'; 
      
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT p.* FROM products p
        INNER JOIN products_fts fts ON p.id = fts.rowid
        WHERE products_fts MATCH ?
        ORDER BY rank
        LIMIT 50
      ''', [ftsQuery]);
      
      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      print('FTS search failed: $e');
      return [];
    }
  }

  /// البحث باستخدام LIKE subsequence
  Future<List<Product>> _searchWithLike(Database db, String normalizedQuery) async {
    try {
      final likePattern = '%${normalizedQuery.split('').join('%')}%';
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT * FROM products 
        WHERE name_norm LIKE ?
        ORDER BY 
          CASE WHEN name_norm LIKE ? THEN 1 ELSE 2 END,
          LENGTH(name) ASC
        LIMIT 50
      ''', [likePattern, '$normalizedQuery%']);
      
      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      print('LIKE search failed: $e');
      return [];
    }
  }

  /// البحث العادي كـ fallback
  Future<List<Product>> _fallbackSearch(Database db, String query) async {
    try {
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT * FROM products 
        WHERE name LIKE ? OR barcode LIKE ?
        ORDER BY name ASC
        LIMIT 50
      ''', ['%$query%', '%$query%']);
      
      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      return [];
    }
  }

  /// إعادة بناء فهرس FTS5
  Future<void> rebuildFTSIndex() async {
    final db = await getDatabase();
    try {
      await db.execute("INSERT INTO products_fts(products_fts) VALUES('rebuild');");
      print('✅ تم إعادة بناء فهرس FTS5');
    } catch (e) {
      print('❌ خطأ في إعادة بناء فهرس FTS5: $e');
    }
  }

  /// التحقق من حالة FTS5
  Future<Map<String, dynamic>> checkFTSStatus() async {
    final db = await getDatabase();
    try {
      final productCount = await db.rawQuery('SELECT COUNT(1) as c FROM products;');
      final ftsCount = await db.rawQuery('SELECT COUNT(1) as c FROM products_fts;');
      
      return {
        'products': (productCount.first['c'] as int?) ?? 0,
        'fts': (ftsCount.first['c'] as int?) ?? 0,
        'synced': (productCount.first['c'] as int?) == (ftsCount.first['c'] as int?),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// تهيئة FTS للمنتجات الموجودة
  Future<void> initializeFTSForExistingProducts() async {
    final db = await getDatabase();
    try {
      // تحديث العمود المطبع للمنتجات التي لا تحتوي عليه
      final products = await db.rawQuery('''
        SELECT id, name FROM products 
        WHERE name_norm IS NULL OR name_norm = ''
      ''');
      
      for (final product in products) {
        final id = product['id'] as int;
        final name = product['name'] as String;
        final normalizedName = DatabaseHelpers.normalizeArabic(name);
        
        await db.update(
          'products',
          {'name_norm': normalizedName},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      
      print('✅ تم تهيئة FTS لـ ${products.length} منتج');
    } catch (e) {
      print('❌ خطأ في تهيئة FTS: $e');
    }
  }

  /// إصلاح تكاليف الوحدات للمنتجات ذات النظام الهرمي
  Future<void> repairHierarchicalUnitCosts() async {
    final db = await getDatabase();
    try {
      final products = await db.rawQuery('''
        SELECT id, name, unit, cost_price, unit_hierarchy, length_per_unit
        FROM products 
        WHERE cost_price IS NOT NULL AND cost_price > 0
      ''');
      
      int updated = 0;
      for (final product in products) {
        try {
          final id = product['id'] as int;
          final unit = product['unit'] as String? ?? 'piece';
          final costPrice = (product['cost_price'] as num?)?.toDouble() ?? 0.0;
          final unitHierarchy = product['unit_hierarchy'] as String?;
          final lengthPerUnit = (product['length_per_unit'] as num?)?.toDouble();
          
          final Map<String, dynamic> newUnitCosts = {};
          
          if (unit == 'piece') {
            double currentCost = costPrice;
            newUnitCosts['قطعة'] = currentCost;
            
            if (unitHierarchy != null && unitHierarchy.isNotEmpty) {
              try {
                final List<dynamic> hierarchy = jsonDecode(unitHierarchy.replaceAll("'", '"')) as List<dynamic>;
                for (final level in hierarchy) {
                  final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                  final double qty = (level['quantity'] is num)
                      ? (level['quantity'] as num).toDouble()
                      : double.tryParse(level['quantity'].toString()) ?? 1.0;
                  currentCost = currentCost * qty;
                  if (unitName.isNotEmpty) {
                    newUnitCosts[unitName] = currentCost;
                  }
                }
              } catch (_) {}
            }
          } else if (unit == 'meter') {
            newUnitCosts['متر'] = costPrice;
            if (lengthPerUnit != null && lengthPerUnit > 0) {
              newUnitCosts['لفة'] = costPrice * lengthPerUnit;
            }
          } else {
            newUnitCosts[unit] = costPrice;
          }
          
          await db.update(
            'products',
            {'unit_costs': jsonEncode(newUnitCosts)},
            where: 'id = ?',
            whereArgs: [id],
          );
          updated++;
        } catch (e) {
          print('Error repairing unit costs for product ${product['id']}: $e');
        }
      }
      
      print('✅ تم إصلاح تكاليف الوحدات لـ $updated منتج');
    } catch (e) {
      print('❌ خطأ في إصلاح تكاليف الوحدات: $e');
    }
  }

  Future<Product?> getProductByName(String name) async {
    final db = await getDatabase();
    final res = await db.query('products', where: 'name = ?', whereArgs: [name], limit: 1);
    if (res.isNotEmpty) return Product.fromMap(res.first);
    return null;
  }

  double calculateUnitCost(Product product, String saleUnit) {
    if ((product.unit == 'piece' && saleUnit == 'قطعة') ||
        (product.unit == 'meter' && saleUnit == 'متر')) {
      return product.costPrice ?? 0.0;
    }
    Map<String, double> unitCosts = const {};
    try {
      unitCosts = product.getUnitCostsMap();
    } catch (_) {}
    final double? stored = unitCosts[saleUnit];
    if (stored != null && stored > 0) {
      return stored;
    }
    if (product.unit == 'meter' && saleUnit == 'لفة') {
      final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
      return (product.costPrice ?? 0.0) * lengthPerUnit;
    }
    // Hierarchy check
     if (product.unit == 'piece' &&
        product.unitHierarchy != null &&
        product.unitHierarchy!.isNotEmpty) {
      try {
        final List<dynamic> hierarchy =
            jsonDecode(product.unitHierarchy!) as List<dynamic>;
        double multiplier = 1.0;
        final baseCost = product.costPrice ?? 0.0;
        if ((product.unit == 'piece' && saleUnit == 'قطعة')) return baseCost;

        for (final level in hierarchy) {
          final String unitName =
              (level['unit_name'] ?? level['name'] ?? '').toString();
          final double qty = (level['quantity'] is num)
              ? (level['quantity'] as num).toDouble()
              : double.tryParse(level['quantity'].toString()) ?? 1.0;
          multiplier *= qty;
          if (unitName == saleUnit) {
            return baseCost * multiplier;
          }
        }
      } catch (e) {
        print('خطأ في حساب التكلفة الهيراركية: $e');
      }
    }
    return product.costPrice ?? 0.0;
  }

  // -------------------------------------------------------------
  // 🏷️ 1NF: عمليات شرائح الأسعار والوحدات المُنظمة (Product Prices & Units)
  // -------------------------------------------------------------

  /// جلب شرائح الأسعار الخاصة بالمنتج من جدول product_prices المنظم
  Future<List<ProductPrice>> getProductPrices(int productId) async {
    final db = await getDatabase();
    try {
      final maps = await db.query(
        'product_prices',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'tier_index ASC',
      );
      return maps.map((m) => ProductPrice.fromMap(m)).toList();
    } catch (e) {
      return [];
    }
  }

  /// جلب الوحدات وتراكيبها المُنظمة للمنتج من جدول product_units
  Future<List<ProductUnit>> getProductUnits(int productId) async {
    final db = await getDatabase();
    try {
      final maps = await db.query(
        'product_units',
        where: 'product_id = ?',
        whereArgs: [productId],
      );
      return maps.map((m) => ProductUnit.fromMap(m)).toList();
    } catch (e) {
      return [];
    }
  }

  /// حفظ شريحة سعر جديدة للمنتج (1NF)
  Future<int> insertProductPrice(ProductPrice price) async {
    final db = await getDatabase();
    return await db.insert(
      'product_prices',
      price.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// حفظ وحدة جديدة للمنتج (1NF)
  Future<int> insertProductUnit(ProductUnit unit) async {
    final db = await getDatabase();
    return await db.insert(
      'product_units',
      unit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

