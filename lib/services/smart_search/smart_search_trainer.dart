// lib/services/smart_search/smart_search_trainer.dart
// خدمة التدريب على الفواتير السابقة

import '../database_service.dart';
import 'smart_search_db.dart';
import 'smart_search_models.dart';

class SmartSearchTrainer {
  final DatabaseService _mainDb;
  final SmartSearchDatabase _smartDb;
  
  // كاش للمنتجات (للبحث بالاسم)
  Map<String, int>? _productNameToIdCache;
  
  // 🆕 الحد الأدنى لاعتبار كلمة كماركة مكتشفة تلقائياً
  static const int _minBrandOccurrence = 5;

  SmartSearchTrainer({
    DatabaseService? mainDb,
    SmartSearchDatabase? smartDb,
  })  : _mainDb = mainDb ?? DatabaseService(),
        _smartDb = smartDb ?? SmartSearchDatabase.instance;

  /// بناء كاش أسماء المنتجات
  Future<void> _buildProductCache() async {
    if (_productNameToIdCache != null) return;
    
    print('📦 بناء كاش المنتجات...');
    final products = await _mainDb.getAllProducts();
    _productNameToIdCache = {};
    for (final product in products) {
      if (product.id != null) {
        _productNameToIdCache![product.name.toLowerCase().trim()] = product.id!;
      }
    }
    print('✅ تم بناء كاش ${_productNameToIdCache!.length} منتج');
  }

  /// الحصول على productId من الاسم (مع كاش)
  int? _getProductIdByName(String productName) {
    if (_productNameToIdCache == null) return null;
    return _productNameToIdCache![productName.toLowerCase().trim()];
  }

  /// التدريب الأولي على جميع الفواتير
  Future<TrainingStats> trainOnAllInvoices({
    Function(int current, int total, String message)? onProgress,
  }) async {
    final startTime = DateTime.now();
    print('🚀 بدء التدريب على جميع الفواتير...');

    // مسح البيانات القديمة
    await _smartDb.clearAllData();
    
    // بناء كاش المنتجات
    await _buildProductCache();
    
    // 🆕 اكتشاف الماركات تلقائياً من أسماء المنتجات
    onProgress?.call(0, 0, 'جاري اكتشاف الماركات تلقائياً...');
    await _discoverBrandsFromProducts();

    // جلب جميع الفواتير
    onProgress?.call(0, 0, 'جاري جلب الفواتير...');
    final invoices = await _mainDb.getAllInvoices();
    final totalInvoices = invoices.length;
    print('📊 عدد الفواتير: $totalInvoices');

    int processedInvoices = 0;
    int totalItems = 0;
    int totalAssociationsBuilt = 0;
    final Set<String> discoveredBrands = {};

    // معالجة كل فاتورة
    for (final invoice in invoices) {
      processedInvoices++;
      
      if (processedInvoices % 50 == 0) {
        onProgress?.call(processedInvoices, totalInvoices, 
          'معالجة الفاتورة $processedInvoices من $totalInvoices...');
        print('📝 معالجة الفاتورة $processedInvoices من $totalInvoices');
      }

      // جلب أصناف الفاتورة
      if (invoice.id == null) continue;
      final items = await _mainDb.getInvoiceItems(invoice.id!);
      if (items.isEmpty) continue;

      totalItems += items.length;

      // استخراج العلامات التجارية من الأصناف
      for (final item in items) {
        final brand = SessionContext.extractBrand(item.productName);
        if (brand != null) {
          discoveredBrands.add(brand);
          await _smartDb.addDiscoveredBrand(brand);

          // تحديث تفضيلات العميل
          await _smartDb.upsertCustomerBrandPreference(
            customerId: invoice.customerId,
            customerName: invoice.customerName,
            brand: brand,
            purchaseDate: invoice.invoiceDate,
          );

          // تحديث تفضيلات المُركّب (إذا موجود)
          if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
            await _smartDb.upsertInstallerBrandPreference(
              installerName: invoice.installerName!,
              brand: brand,
              purchaseDate: invoice.invoiceDate,
            );
          }
        }
      }

      // بناء علاقات المنتجات (كل منتج مع كل منتج في نفس الفاتورة)
      for (int i = 0; i < items.length; i++) {
        for (int j = i + 1; j < items.length; j++) {
          final itemA = items[i];
          final itemB = items[j];
          
          // تجاهل الأصناف الفارغة
          if (itemA.productName.isEmpty || itemB.productName.isEmpty) continue;

          // الحصول على productId (من الصنف أو من الكاش)
          final productIdA = itemA.productId ?? _getProductIdByName(itemA.productName);
          final productIdB = itemB.productId ?? _getProductIdByName(itemB.productName);

          if (productIdA != null && productIdB != null && productIdA != productIdB) {
            await _smartDb.upsertProductAssociation(
              productIdA: productIdA,
              productIdB: productIdB,
              productNameA: itemA.productName,
              productNameB: itemB.productName,
            );
            totalAssociationsBuilt++;
          }
        }
      }

      // 🆕 بناء علاقات الترتيب والتتابع (المنتج والمنتجات التي تليه) مع حساب المسافة
      // هذا يحقق فكرة أن المنتج العاشر يتأثر بالتاسع والثامن والسابع...
      for (int i = 0; i < items.length - 1; i++) {
        final itemA = items[i];
        if (itemA.productName.isEmpty) continue;
        final productIdA = itemA.productId ?? _getProductIdByName(itemA.productName);
        if (productIdA == null) continue;

        // نربط المنتج الحالي بالمنتجات التي تأتي بعده (بحد أقصى 10 منتجات للأمام لتجنب التضخم الزائد)
        final maxLookAhead = (items.length - i < 11) ? items.length - i : 11;
        for (int offset = 1; offset < maxLookAhead; offset++) {
          final itemB = items[i + offset];
          if (itemB.productName.isEmpty) continue;
          final productIdB = itemB.productId ?? _getProductIdByName(itemB.productName);
          
          if (productIdB != null && productIdA != productIdB) {
            await _smartDb.upsertProductSequence(
              fromProductId: productIdA,
              toProductId: productIdB,
              distance: offset, // المسافة: 1 = يليه مباشرة، 2 = بعده بمنتج، وهكذا
            );
          }
        }
      }
    }

    // تحديث القوة والنسب
    onProgress?.call(totalInvoices, totalInvoices, 'جاري حساب القوة والنسب...');
    print('📊 تحديث قوة العلاقات...');
    await _smartDb.updateAssociationStrengths();
    
    print('📊 تحديث نسب تفضيلات العملاء...');
    await _smartDb.updateCustomerPreferencePercentages();
    
    print('📊 تحديث نسب تفضيلات المُركّبين...');
    await _smartDb.updateInstallerPreferencePercentages();

    // حساب الإحصائيات
    final db = await _smartDb.database;
    final associationsCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM product_associations'
    )).first['count'] as int;
    
    final customerPrefsCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM customer_brand_preferences'
    )).first['count'] as int;
    
    final installerPrefsCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM installer_brand_preferences'
    )).first['count'] as int;

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    final stats = TrainingStats(
      totalInvoices: totalInvoices,
      totalItems: totalItems,
      totalAssociations: associationsCount,
      totalCustomerPreferences: customerPrefsCount,
      totalInstallerPreferences: installerPrefsCount,
      uniqueBrands: discoveredBrands.length,
      trainedAt: endTime,
      trainingDuration: duration,
    );

    // حفظ الإحصائيات
    await _smartDb.saveTrainingStats(stats);
    
    // 🆕 تحميل الماركات المكتشفة إلى SessionContext
    final allBrands = await _smartDb.getDiscoveredBrands();
    SessionContext.setAutoDiscoveredBrands(allBrands.toSet());
    
    // مسح الكاش
    _productNameToIdCache = null;

    print('✅ اكتمل التدريب!');
    print('📊 علاقات تم بناؤها: $totalAssociationsBuilt');
    print(stats.toString());

    return stats;
  }
  
  /// 🆕 اكتشاف الماركات تلقائياً من أسماء المنتجات
  Future<void> _discoverBrandsFromProducts() async {
    print('🔍 اكتشاف الماركات تلقائياً من المنتجات...');
    
    final products = await _mainDb.getAllProducts();
    
    // حساب تكرار الكلمات الأخيرة
    final Map<String, int> lastWordCounts = {};
    
    for (final product in products) {
      final lastWord = SessionContext.extractLastWord(product.name);
      if (lastWord != null) {
        lastWordCounts[lastWord] = (lastWordCounts[lastWord] ?? 0) + 1;
      }
    }
    
    // الكلمات التي تظهر في 5+ منتجات تُعتبر ماركات
    final discoveredBrands = <String>[];
    for (final entry in lastWordCounts.entries) {
      if (entry.value >= _minBrandOccurrence) {
        discoveredBrands.add(entry.key);
        // حفظ في قاعدة البيانات مع عدد التكرار
        await _smartDb.addAutoDiscoveredBrand(entry.key, entry.value);
      }
    }
    
    print('🏷️ تم اكتشاف ${discoveredBrands.length} ماركة تلقائياً:');
    for (final brand in discoveredBrands.take(20)) {
      print('   - $brand (${lastWordCounts[brand]} منتج)');
    }
    if (discoveredBrands.length > 20) {
      print('   ... و ${discoveredBrands.length - 20} ماركة أخرى');
    }
    
    // تحديث SessionContext
    SessionContext.setAutoDiscoveredBrands(discoveredBrands.toSet());
  }

  /// التدريب على فاتورة واحدة جديدة (تعلم تدريجي)
  Future<void> trainOnSingleInvoice(int invoiceId) async {
    print('📝 تدريب على الفاتورة: $invoiceId');

    final invoice = await _mainDb.getInvoiceById(invoiceId);
    if (invoice == null) {
      print('⚠️ الفاتورة غير موجودة: $invoiceId');
      return;
    }

    final items = await _mainDb.getInvoiceItems(invoiceId);
    if (items.isEmpty) {
      print('⚠️ الفاتورة فارغة: $invoiceId');
      return;
    }

    // استخراج العلامات التجارية
    for (final item in items) {
      final brand = SessionContext.extractBrand(item.productName);
      if (brand != null) {
        await _smartDb.addDiscoveredBrand(brand);

        // تحديث تفضيلات العميل
        await _smartDb.upsertCustomerBrandPreference(
          customerId: invoice.customerId,
          customerName: invoice.customerName,
          brand: brand,
          purchaseDate: invoice.invoiceDate,
        );

        // تحديث تفضيلات المُركّب
        if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
          await _smartDb.upsertInstallerBrandPreference(
            installerName: invoice.installerName!,
            brand: brand,
            purchaseDate: invoice.invoiceDate,
          );
        }
      }
    }

    // بناء علاقات المنتجات
    for (int i = 0; i < items.length; i++) {
      for (int j = i + 1; j < items.length; j++) {
        final itemA = items[i];
        final itemB = items[j];
        
        // تجاهل الأصناف الفارغة
        if (itemA.productName.isEmpty || itemB.productName.isEmpty) continue;

        // للتعلم التدريجي، نستخدم productId مباشرة (يجب أن يكون موجوداً في الفواتير الجديدة)
        if (itemA.productId != null && itemB.productId != null && itemA.productId != itemB.productId) {
          await _smartDb.upsertProductAssociation(
            productIdA: itemA.productId!,
            productIdB: itemB.productId!,
            productNameA: itemA.productName,
            productNameB: itemB.productName,
          );
        }
      }
    }

    // 🆕 بناء علاقات الترتيب (Sequence) التراكمية مع حساب المسافة
    for (int i = 0; i < items.length - 1; i++) {
      final itemA = items[i];
      if (itemA.productName.isEmpty || itemA.productId == null) continue;
      
      final maxLookAhead = (items.length - i < 11) ? items.length - i : 11;
      for (int offset = 1; offset < maxLookAhead; offset++) {
        final itemB = items[i + offset];
        if (itemB.productName.isEmpty || itemB.productId == null) continue;
        
        if (itemA.productId != itemB.productId) {
          await _smartDb.upsertProductSequence(
            fromProductId: itemA.productId!,
            toProductId: itemB.productId!,
            distance: offset,
          );
        }
      }
    }
    
    // 🆕 تنفيذ صيانة دورية خفيفة جداً لحذف العلاقات الميتة منذ سنة
    _smartDb.cleanUpOldData().catchError((e) => print('⚠️ Error in cleanup: $e'));

    print('✅ تم التدريب على الفاتورة: $invoiceId');
  }

  /// جلب إحصائيات آخر تدريب
  Future<TrainingStats?> getLastTrainingStats() async {
    return await _smartDb.getLastTrainingStats();
  }

  /// التحقق من وجود بيانات تدريب
  Future<bool> hasTrainingData() async {
    final stats = await getLastTrainingStats();
    return stats != null && stats.totalInvoices > 0;
  }
}
