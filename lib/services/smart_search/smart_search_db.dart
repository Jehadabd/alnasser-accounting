// lib/services/smart_search/smart_search_db.dart
// قاعدة بيانات منفصلة لنظام البحث الذكي

import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'smart_search_models.dart';

class SmartSearchDatabase {
  static SmartSearchDatabase? _instance;
  static Database? _database;

  SmartSearchDatabase._();

  static SmartSearchDatabase get instance {
    _instance ??= SmartSearchDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {

    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'smart_search.db');

    print('📂 Smart Search DB path: $path');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    print('🔧 Creating Smart Search database tables...');

    // جدول علاقات المنتجات (أي منتج يُشترى مع أي منتج)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_associations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id_a INTEGER NOT NULL,
        product_id_b INTEGER NOT NULL,
        product_name_a TEXT NOT NULL,
        product_name_b TEXT NOT NULL,
        co_occurrence_count INTEGER DEFAULT 1,
        strength REAL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(product_id_a, product_id_b)
      )
    ''');

    // فهرس للبحث السريع
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_associations_product_a 
      ON product_associations(product_id_a)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_associations_product_b 
      ON product_associations(product_id_b)
    ''');

    // جدول تفضيلات العملاء للعلامات التجارية
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_brand_preferences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        customer_name TEXT NOT NULL,
        brand TEXT NOT NULL,
        purchase_count INTEGER DEFAULT 1,
        percentage REAL DEFAULT 0.0,
        last_purchase TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(customer_id, brand),
        UNIQUE(customer_name, brand)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_prefs_customer 
      ON customer_brand_preferences(customer_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_customer_prefs_name 
      ON customer_brand_preferences(customer_name)
    ''');

    // جدول تفضيلات المُركّبين/المؤسسين للعلامات التجارية
    await db.execute('''
      CREATE TABLE IF NOT EXISTS installer_brand_preferences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        installer_name TEXT NOT NULL,
        brand TEXT NOT NULL,
        purchase_count INTEGER DEFAULT 1,
        percentage REAL DEFAULT 0.0,
        last_purchase TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(installer_name, brand)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_installer_prefs_name 
      ON installer_brand_preferences(installer_name)
    ''');

    // جدول إحصائيات التدريب
    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_invoices INTEGER,
        total_items INTEGER,
        total_associations INTEGER,
        total_customer_preferences INTEGER,
        total_installer_preferences INTEGER,
        unique_brands INTEGER,
        trained_at TEXT NOT NULL,
        training_duration_ms INTEGER
      )
    ''');

    // جدول العلامات التجارية المكتشفة
    await db.execute('''
      CREATE TABLE IF NOT EXISTS discovered_brands (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        brand TEXT UNIQUE NOT NULL,
        occurrence_count INTEGER DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // 🆕 جدول تتابع المنتجات (أ يليه ب) مع المسافة (Distance)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_sequences (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_product_id INTEGER NOT NULL,
        to_product_id INTEGER NOT NULL,
        distance INTEGER NOT NULL DEFAULT 1,
        count INTEGER DEFAULT 1,
        last_occurred TEXT NOT NULL,
        UNIQUE(from_product_id, to_product_id, distance)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sequences_from 
      ON product_sequences(from_product_id)
    ''');

    print('✅ Smart Search database tables created successfully');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // للترقيات المستقبلية
    if (oldVersion < 2) {
      print('🔄 Upgrading Smart Search database to version 2...');
      await db.execute('DROP TABLE IF EXISTS product_sequences');
      
      // 🆕 جدول تتابع المنتجات (أ يليه ب) مع المسافة (Distance)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_sequences (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          from_product_id INTEGER NOT NULL,
          to_product_id INTEGER NOT NULL,
          distance INTEGER NOT NULL DEFAULT 1,
          count INTEGER DEFAULT 1,
          last_occurred TEXT NOT NULL,
          UNIQUE(from_product_id, to_product_id, distance)
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sequences_from 
        ON product_sequences(from_product_id)
      ''');
      print('✅ Upgrade completed.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال علاقات المنتجات
  // ═══════════════════════════════════════════════════════════════════════════

  /// إضافة أو تحديث علاقة بين منتجين
  Future<void> upsertProductAssociation({
    required int productIdA,
    required int productIdB,
    required String productNameA,
    required String productNameB,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // ترتيب المنتجات لتجنب التكرار (A,B) و (B,A)
    final int idA = productIdA < productIdB ? productIdA : productIdB;
    final int idB = productIdA < productIdB ? productIdB : productIdA;
    final String nameA = productIdA < productIdB ? productNameA : productNameB;
    final String nameB = productIdA < productIdB ? productNameB : productNameA;

    await db.rawInsert('''
      INSERT INTO product_associations 
        (product_id_a, product_id_b, product_name_a, product_name_b, 
         co_occurrence_count, created_at, updated_at)
      VALUES (?, ?, ?, ?, 1, ?, ?)
      ON CONFLICT(product_id_a, product_id_b) DO UPDATE SET
        co_occurrence_count = co_occurrence_count + 1,
        updated_at = ?
    ''', [idA, idB, nameA, nameB, now, now, now]);
  }

  /// جلب المنتجات المرتبطة بمنتج معين
  Future<List<ProductAssociation>> getAssociatedProducts(int productId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT * FROM product_associations 
      WHERE product_id_a = ? OR product_id_b = ?
      ORDER BY co_occurrence_count DESC
      LIMIT 50
    ''', [productId, productId]);

    return results.map((m) => ProductAssociation.fromMap(m)).toList();
  }

  /// جلب المنتجات المرتبطة بقائمة منتجات
  Future<Map<int, Map<String, dynamic>>> getAssociatedProductsForList(List<int> productIds) async {
    if (productIds.isEmpty) return {};
    
    final db = await database;
    final placeholders = productIds.map((_) => '?').join(',');
    
    final results = await db.rawQuery('''
      SELECT 
        CASE 
          WHEN product_id_a IN ($placeholders) THEN product_id_b 
          ELSE product_id_a 
        END as associated_product_id,
        SUM(co_occurrence_count) as total_count,
        MAX(updated_at) as last_updated
      FROM product_associations 
      WHERE product_id_a IN ($placeholders) OR product_id_b IN ($placeholders)
      GROUP BY associated_product_id
      ORDER BY total_count DESC
    ''', [...productIds, ...productIds, ...productIds]);

    final Map<int, Map<String, dynamic>> associations = {};
    for (final row in results) {
      final productId = row['associated_product_id'] as int;
      final count = row['total_count'] as int;
      final lastUpdated = row['last_updated'] as String;
      // تجاهل المنتجات الموجودة في القائمة الأصلية
      if (!productIds.contains(productId)) {
        associations[productId] = {
          'count': count,
          'updated_at': lastUpdated,
        };
      }
    }
    return associations;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🆕 دوال تتابع المنتجات
  // ═══════════════════════════════════════════════════════════════════════════

  /// إضافة أو تحديث تتابع منتجين
  Future<void> upsertProductSequence({
    required int fromProductId,
    required int toProductId,
    int distance = 1,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.rawInsert('''
      INSERT INTO product_sequences 
        (from_product_id, to_product_id, distance, count, last_occurred)
      VALUES (?, ?, ?, 1, ?)
      ON CONFLICT(from_product_id, to_product_id, distance) DO UPDATE SET
        count = count + 1,
        last_occurred = ?
    ''', [fromProductId, toProductId, distance, now, now]);
  }

  /// جلب المنتجات التي تلي منتجاً معيناً
  Future<List<ProductSequence>> getSequencesFollowing(int fromProductId) async {
    final db = await database;
    final results = await db.query(
      'product_sequences',
      where: 'from_product_id = ?',
      whereArgs: [fromProductId],
      orderBy: 'count DESC',
      limit: 50,
    );

    return results.map((m) => ProductSequence.fromMap(m)).toList();
  }

  /// 🆕 جلب التتابعات لقائمة من المنتجات
  Future<List<ProductSequence>> getSequencesForList(List<int> productIds) async {
    if (productIds.isEmpty) return [];
    
    final db = await database;
    final placeholders = productIds.map((_) => '?').join(',');
    
    final results = await db.rawQuery('''
      SELECT * FROM product_sequences 
      WHERE from_product_id IN ($placeholders)
      ORDER BY count DESC
    ''', productIds);

    return results.map((m) => ProductSequence.fromMap(m)).toList();
  }

  /// جلب العلاقات المرتبطة بقائمة مع بيانات الوقت للتحلل الزمني
  Future<List<Map<String, dynamic>>> getAssociationsWithTime(List<int> productIds) async {
    if (productIds.isEmpty) return [];
    
    final db = await database;
    final placeholders = productIds.map((_) => '?').join(',');
    
    return await db.rawQuery('''
      SELECT 
        CASE 
          WHEN product_id_a IN ($placeholders) THEN product_id_b 
          ELSE product_id_a 
        END as associated_product_id,
        co_occurrence_count,
        updated_at
      FROM product_associations 
      WHERE product_id_a IN ($placeholders) OR product_id_b IN ($placeholders)
    ''', [...productIds, ...productIds, ...productIds]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال تفضيلات العملاء
  // ═══════════════════════════════════════════════════════════════════════════

  /// إضافة أو تحديث تفضيل علامة تجارية لعميل
  Future<void> upsertCustomerBrandPreference({
    int? customerId,
    required String customerName,
    required String brand,
    required DateTime purchaseDate,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final purchaseDateStr = purchaseDate.toIso8601String();

    if (customerId != null) {
      await db.rawInsert('''
        INSERT INTO customer_brand_preferences 
          (customer_id, customer_name, brand, purchase_count, last_purchase, created_at, updated_at)
        VALUES (?, ?, ?, 1, ?, ?, ?)
        ON CONFLICT(customer_id, brand) DO UPDATE SET
          purchase_count = purchase_count + 1,
          last_purchase = ?,
          updated_at = ?
      ''', [customerId, customerName, brand, purchaseDateStr, now, now, purchaseDateStr, now]);
    } else {
      await db.rawInsert('''
        INSERT INTO customer_brand_preferences 
          (customer_id, customer_name, brand, purchase_count, last_purchase, created_at, updated_at)
        VALUES (NULL, ?, ?, 1, ?, ?, ?)
        ON CONFLICT(customer_name, brand) DO UPDATE SET
          purchase_count = purchase_count + 1,
          last_purchase = ?,
          updated_at = ?
      ''', [customerName, brand, purchaseDateStr, now, now, purchaseDateStr, now]);
    }
  }

  /// جلب تفضيلات العميل
  Future<List<CustomerBrandPreference>> getCustomerPreferences({
    int? customerId,
    String? customerName,
  }) async {
    final db = await database;
    List<Map<String, dynamic>> results;

    if (customerId != null) {
      results = await db.query(
        'customer_brand_preferences',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'purchase_count DESC',
      );
    } else if (customerName != null) {
      results = await db.query(
        'customer_brand_preferences',
        where: 'customer_name = ?',
        whereArgs: [customerName],
        orderBy: 'purchase_count DESC',
      );
    } else {
      return [];
    }

    return results.map((m) => CustomerBrandPreference.fromMap(m)).toList();
  }

  /// جلب أفضل علامة تجارية للعميل
  Future<String?> getCustomerTopBrand({int? customerId, String? customerName}) async {
    final prefs = await getCustomerPreferences(
      customerId: customerId,
      customerName: customerName,
    );
    if (prefs.isEmpty) return null;
    return prefs.first.brand;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال تفضيلات المُركّبين
  // ═══════════════════════════════════════════════════════════════════════════

  /// إضافة أو تحديث تفضيل علامة تجارية لمُركّب
  Future<void> upsertInstallerBrandPreference({
    required String installerName,
    required String brand,
    required DateTime purchaseDate,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final purchaseDateStr = purchaseDate.toIso8601String();

    await db.rawInsert('''
      INSERT INTO installer_brand_preferences 
        (installer_name, brand, purchase_count, last_purchase, created_at, updated_at)
      VALUES (?, ?, 1, ?, ?, ?)
      ON CONFLICT(installer_name, brand) DO UPDATE SET
        purchase_count = purchase_count + 1,
        last_purchase = ?,
        updated_at = ?
    ''', [installerName, brand, purchaseDateStr, now, now, purchaseDateStr, now]);
  }

  /// جلب تفضيلات المُركّب
  Future<List<InstallerBrandPreference>> getInstallerPreferences(String installerName) async {
    final db = await database;
    final results = await db.query(
      'installer_brand_preferences',
      where: 'installer_name = ?',
      whereArgs: [installerName],
      orderBy: 'purchase_count DESC',
    );

    return results.map((m) => InstallerBrandPreference.fromMap(m)).toList();
  }

  /// جلب أفضل علامة تجارية للمُركّب
  Future<String?> getInstallerTopBrand(String installerName) async {
    final prefs = await getInstallerPreferences(installerName);
    if (prefs.isEmpty) return null;
    return prefs.first.brand;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال العلامات التجارية
  // ═══════════════════════════════════════════════════════════════════════════

  /// إضافة علامة تجارية مكتشفة
  Future<void> addDiscoveredBrand(String brand) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.rawInsert('''
      INSERT INTO discovered_brands (brand, occurrence_count, created_at)
      VALUES (?, 1, ?)
      ON CONFLICT(brand) DO UPDATE SET
        occurrence_count = occurrence_count + 1
    ''', [brand, now]);
  }
  
  /// 🆕 إضافة علامة تجارية مكتشفة تلقائياً مع عدد التكرار
  Future<void> addAutoDiscoveredBrand(String brand, int occurrenceCount) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.rawInsert('''
      INSERT INTO discovered_brands (brand, occurrence_count, created_at)
      VALUES (?, ?, ?)
      ON CONFLICT(brand) DO UPDATE SET
        occurrence_count = ?
    ''', [brand, occurrenceCount, now, occurrenceCount]);
  }
  
  /// 🆕 جلب الماركات المكتشفة تلقائياً (التي تظهر في 5+ منتجات)
  Future<List<String>> getAutoDiscoveredBrands({int minOccurrence = 5}) async {
    final db = await database;
    final results = await db.query(
      'discovered_brands',
      where: 'occurrence_count >= ?',
      whereArgs: [minOccurrence],
      orderBy: 'occurrence_count DESC',
    );
    return results.map((m) => m['brand'] as String).toList();
  }

  /// جلب جميع العلامات التجارية المكتشفة
  Future<List<String>> getDiscoveredBrands() async {
    final db = await database;
    final results = await db.query(
      'discovered_brands',
      orderBy: 'occurrence_count DESC',
    );
    return results.map((m) => m['brand'] as String).toList();
  }
  
  /// 🆕 جلب جميع العلامات التجارية مع عدد التكرار
  Future<List<Map<String, dynamic>>> getDiscoveredBrandsWithCount() async {
    final db = await database;
    final results = await db.query(
      'discovered_brands',
      orderBy: 'occurrence_count DESC',
    );
    return results.map((m) => <String, dynamic>{
      'brand': m['brand'] as String,
      'count': m['occurrence_count'] as int,
      'created_at': m['created_at'] as String,
    }).toList();
  }
  
  /// 🆕 حذف علامة تجارية
  Future<bool> deleteBrand(String brand) async {
    final db = await database;
    final deleted = await db.delete(
      'discovered_brands',
      where: 'brand = ?',
      whereArgs: [brand],
    );
    print('🗑️ Deleted brand: $brand (rows: $deleted)');
    return deleted > 0;
  }
  
  /// 🆕 إضافة علامة تجارية يدوياً
  Future<void> addManualBrand(String brand) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    
    // إضافة مع عدد تكرار عالي (999) لضمان ظهورها دائماً
    await db.rawInsert('''
      INSERT INTO discovered_brands (brand, occurrence_count, created_at)
      VALUES (?, 999, ?)
      ON CONFLICT(brand) DO UPDATE SET
        occurrence_count = 999
    ''', [brand, now]);
    print('➕ Added manual brand: $brand');
  }
  
  /// 🆕 التحقق من وجود علامة تجارية
  Future<bool> brandExists(String brand) async {
    final db = await database;
    final results = await db.query(
      'discovered_brands',
      where: 'brand = ?',
      whereArgs: [brand],
    );
    return results.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال الإحصائيات
  // ═══════════════════════════════════════════════════════════════════════════

  /// جلب إحصائيات بيانات التدريب
  Future<Map<String, dynamic>> getTrainingDataStats() async {
    final db = await database;

    final assocResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM product_associations');
    final assocCount = (assocResult.first['cnt'] as int?) ?? 0;

    final seqResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM product_sequences');
    final seqCount = (seqResult.first['cnt'] as int?) ?? 0;

    final custPrefResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM customer_brand_preferences');
    final custPrefCount = (custPrefResult.first['cnt'] as int?) ?? 0;

    final instPrefResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM installer_brand_preferences');
    final instPrefCount = (instPrefResult.first['cnt'] as int?) ?? 0;

    final brandsResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM discovered_brands');
    final brandsCount = (brandsResult.first['cnt'] as int?) ?? 0;

    final hasData = (assocCount + seqCount + custPrefCount + instPrefCount + brandsCount) > 0;

    // آخر تدريب
    String? lastTraining;
    final lastStats = await db.query(
      'training_stats',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (lastStats.isNotEmpty) {
      lastTraining = lastStats.first['trained_at'] as String?;
    }

    return {
      'has_data': hasData,
      'associations_count': assocCount,
      'sequences_count': seqCount,
      'customer_preferences_count': custPrefCount,
      'installer_preferences_count': instPrefCount,
      'brands_count': brandsCount,
      'last_training': lastTraining,
    };
  }

  /// حفظ إحصائيات التدريب
  Future<void> saveTrainingStats(TrainingStats stats) async {
    final db = await database;
    await db.insert('training_stats', stats.toMap());
  }

  /// جلب آخر إحصائيات تدريب
  Future<TrainingStats?> getLastTrainingStats() async {
    final db = await database;
    final results = await db.query(
      'training_stats',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return TrainingStats.fromMap(results.first);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال الصيانة
  // ═══════════════════════════════════════════════════════════════════════════

  /// تنظيف العلاقات والترتيبات القديمة (أقدم من سنة)
  Future<void> cleanUpOldData() async {
    final db = await database;
    // نحصل على التاريخ قبل سنة
    final oneYearAgo = DateTime.now().subtract(const Duration(days: 365)).toIso8601String();
    
    int deletedAssoc = await db.delete('product_associations', where: 'updated_at <= ?', whereArgs: [oneYearAgo]);
    int deletedSeq = await db.delete('product_sequences', where: 'last_occurred <= ?', whereArgs: [oneYearAgo]);
    
    if (deletedAssoc > 0 || deletedSeq > 0) {
      print('🧹 Cleaned up old data: $deletedAssoc associations, $deletedSeq sequences (older than 1 year)');
    }
  }

  /// مسح جميع البيانات (لإعادة التدريب)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('product_associations');
    await db.delete('customer_brand_preferences');
    await db.delete('installer_brand_preferences');
    await db.delete('discovered_brands');
    print('🗑️ Smart Search data cleared');
  }

  /// تحديث قوة العلاقات (بعد التدريب)
  Future<void> updateAssociationStrengths() async {
    final db = await database;
    
    // حساب أقصى عدد تكرار
    final maxResult = await db.rawQuery(
      'SELECT MAX(co_occurrence_count) as max_count FROM product_associations'
    );
    final maxCount = (maxResult.first['max_count'] as int?) ?? 1;

    // تحديث القوة كنسبة من الأقصى
    await db.rawUpdate('''
      UPDATE product_associations 
      SET strength = CAST(co_occurrence_count AS REAL) / ?
    ''', [maxCount]);

    print('✅ Association strengths updated (max: $maxCount)');
  }

  /// تحديث نسب تفضيلات العملاء
  Future<void> updateCustomerPreferencePercentages() async {
    final db = await database;

    // حساب إجمالي مشتريات كل عميل
    await db.rawUpdate('''
      UPDATE customer_brand_preferences 
      SET percentage = (
        SELECT CAST(purchase_count AS REAL) * 100 / 
          (SELECT SUM(purchase_count) FROM customer_brand_preferences cp2 
           WHERE cp2.customer_id = customer_brand_preferences.customer_id 
              OR cp2.customer_name = customer_brand_preferences.customer_name)
      )
    ''');

    print('✅ Customer preference percentages updated');
  }

  /// تحديث نسب تفضيلات المُركّبين
  Future<void> updateInstallerPreferencePercentages() async {
    final db = await database;

    await db.rawUpdate('''
      UPDATE installer_brand_preferences 
      SET percentage = (
        SELECT CAST(purchase_count AS REAL) * 100 / 
          (SELECT SUM(purchase_count) FROM installer_brand_preferences ip2 
           WHERE ip2.installer_name = installer_brand_preferences.installer_name)
      )
    ''');

    print('✅ Installer preference percentages updated');
  }

  /// إغلاق قاعدة البيانات
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
