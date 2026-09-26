import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import '../database/core/database_helpers.dart';
import '../database/business/stock_ledger.dart';
import 'firebase_sync_config.dart';
import 'uuid_helper.dart';
import '../../models/product.dart';

class ProductSyncService {
  FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ??= FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();
  String? _deviceId;
  bool _isListening = false;

  /// 🛡️ هوية هذا الجهاز = معرّف جهاز Firebase. كانت رقم ترقيم الفواتير
  /// (افتراضياً 1 على كل جهاز): جهازان بنفس الرقم يعدّ كلٌّ منهما منتجات
  /// الآخر «منتجاته هو» فيتجاهلها — لا يصل منتج جديد ولا تعديل إطلاقاً.
  Future<String> _myDeviceId() async =>
      _deviceId ??= await FirebaseSyncConfig.getDeviceId();

  Set<String>? _productColumns;

  Future<void> startSync() async {
    if (_isListening) return;
    await _myDeviceId();

    // 1. Upload pending products
    // 🛡️ بلا انتظار: بلا إنترنت لا يكتمل set() حتى يعود الاتصال، فكان يحجز
    // تهيئة المزامنة كلها (نفس خلل رفع الفواتير — 8.9).
    unawaited(syncPendingProducts());

    // 2. Download all remote products to ensure complete local catalog
    await downloadAllProducts().timeout(const Duration(seconds: 90), onTimeout: () {});

    // 3. Listen for incoming products
    _listenForIncomingProducts();
    _isListening = true;
  }

  Future<void> syncPendingProducts() async {
    try {
      final db = await _dbService.database;
      final me = await _myDeviceId();

      // 🛡️ المعلّق = ما لم يُرفع أو تغيّر بعد آخر رفع. كان «كل ما آخر من
      // عدّله أنا» فيُعاد رفع كل منتجات الجهاز عند كل تشغيل.
      final pendingProducts = await db.query(
        'products',
        where: "last_synced_at IS NULL OR sync_uuid IS NULL OR sync_uuid = '' "
            'OR (last_modified_by_device_id = ? AND last_modified_at > last_synced_at)',
        whereArgs: [me],
      );

      for (var p in pendingProducts) {
        String? uuid = p['sync_uuid'] as String?;
        if (uuid == null || uuid.isEmpty) {
          uuid = UuidHelper.newProductUuid();
          await db.update('products', {'sync_uuid': uuid}, where: 'id = ?', whereArgs: [p['id']]);
        }
        await uploadProductNow(uuid, productData: Map<String, dynamic>.from(p)..['sync_uuid'] = uuid);
      }
    } catch (e) {
      print('ProductSyncService - Error syncing pending products: $e');
    }
  }

  Future<void> downloadAllProducts() async {
    try {
      print('📦 [ProductSyncService] جاري تنزيل المنتجات من السحابة...');
      final snapshot = await _firestore.collection('products').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data.isNotEmpty) {
          await _processIncomingProduct(data);
        }
      }
      print('✅ [ProductSyncService] اكتمل جلب المنتجات: ${snapshot.docs.length} منتج');
    } catch (e) {
      print('❌ [ProductSyncService] خطأ أثناء تنزيل المنتجات: $e');
    }
  }

  Future<void> uploadProductNow(String syncUuid, {Map<String, dynamic>? productData}) async {
    try {
      final db = await _dbService.database;
      
      if (productData == null) {
        final res = await db.query('products', where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
        if (res.isEmpty) return;
        productData = res.first;
      }
      
      final me = await _myDeviceId();

      final payload = Map<String, dynamic>.from(productData!);
      payload['uploaded_at'] = FieldValue.serverTimestamp();
      payload['last_modified_by_device_id'] = me;
      // الكمية لا تُزامَن من هنا: دفتر المخزون (StockMovementSyncService) هو
      // المصدر، والمستقبِل يتجاهلها لمنتج قائم. تبقى للمنتج الجديد كقيمة مؤقتة.
      payload['sync_uuid'] = syncUuid;
      
      final productId = productData['id'] as int?;
      if (productId != null) {
        // 1. Fetch multiple barcodes
        final barcodes = await db.query('product_barcodes', where: 'product_id = ?', whereArgs: [productId]);
        if (barcodes.isNotEmpty) {
          payload['multiple_barcodes'] = barcodes.map((b) => {
            'barcode': b['barcode'],
            'variant_label': b['variant_label'],
            'cost_price': b['cost_price'],
            'sell_price': b['sell_price'],
            'is_default': b['is_default']
          }).toList();
        }
        
        // 2. Fetch category name
        final categoryId = productData['category_id'] as int?;
        if (categoryId != null && categoryId > 0) {
          final catRes = await db.query('categories', where: 'id = ?', whereArgs: [categoryId], limit: 1);
          if (catRes.isNotEmpty) {
            payload['category_name'] = catRes.first['name'];
            payload['category_description'] = catRes.first['description'];
          }
        }
      }
      
      await _firestore
          .collection('products')
          .doc(syncUuid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 60));
      
      await db.update('products', {'last_synced_at': DateTime.now().toIso8601String()}, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
      print('📦 [ProductSyncService] تم رفع المنتج بنجاح: ${payload['name']} ($syncUuid)');
    } catch (e) {
      print('ProductSyncService - Error uploading product $syncUuid: $e');
    }
  }

  void _listenForIncomingProducts() {
    _firestore.collection('products').snapshots().listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null) {
            await _processIncomingProduct(data);
          }
        }
      }
    });
  }

  Future<void> _processIncomingProduct(Map<String, dynamic> data) async {
    try {
      final syncUuid = data['sync_uuid'] as String?;
      if (syncUuid == null) return;
      
      final db = await _dbService.database;

      // مستندي أنا: نسختي المحلية هي المرجع — إلا إن غاب المنتج هنا (قاعدة
      // استُعيدت من نسخة احتياطية أقدم منه). كان يُتجاهل دائماً، فلا يعود
      // منتجي أبداً بعد الاستعادة بينما بنوده وحركاته موجودة (اختبار الكود الحقيقي).
      if (data['last_modified_by_device_id'] == await _myDeviceId()) {
        final mine = await db.query('products',
            columns: ['id'], where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
        if (mine.isNotEmpty) return;
      }

      // 1. البحث عن المنتج بـ sync_uuid أولاً
      var existing = await db.query('products', where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
      
      // 🔍 2. إذا لم نجد المنتج بـ sync_uuid، نبحث بالاسم المطبع لمنع تكرار المنتجات!
      if (existing.isEmpty) {
        final productName = data['name'] as String?;
        if (productName != null && productName.trim().isNotEmpty) {
          final normName = DatabaseHelpers.normalizeArabic(productName);
          existing = await db.query(
            'products',
            where: 'name = ? OR name_norm = ?',
            whereArgs: [productName.trim(), normName],
            limit: 1,
          );
        }
      }

      final incomingModifiedAtStr = data['last_modified_at'] as String?;
      if (incomingModifiedAtStr != null) {
        final incomingModifiedAt = DateTime.tryParse(incomingModifiedAtStr);
        if (incomingModifiedAt != null && existing.isNotEmpty) {
          final existingModifiedAtStr = existing.first['last_modified_at'] as String?;
          if (existingModifiedAtStr != null) {
            final existingModifiedAt = DateTime.tryParse(existingModifiedAtStr);
            if (existingModifiedAt != null && !incomingModifiedAt.isAfter(existingModifiedAt)) {
               return; // Local is newer or same
            }
          }
        }
      }
        
      final localData = Map<String, dynamic>.from(data);
      localData.remove('id'); // Keep local id
      localData.remove('uploaded_at');
      localData['sync_uuid'] = syncUuid; // ربط الـ UUID بالمنتج الموجود أو الجديد
      
      if (localData['name'] != null) {
        localData['name_norm'] = DatabaseHelpers.normalizeArabic(localData['name'] as String);
      }

      // 🚀 تحقق من إعداد المستخدم: هل يسمح بمزامنة المخزون المباشرة من تفاصيل المنتج؟
      final isDirectStockSyncEnabled = await FirebaseSyncSecuritySettings.isDirectStockSyncEnabled();
      if (existing.isNotEmpty && !isDirectStockSyncEnabled) {
        localData.remove('stock_quantity'); // عدم مسح الكمية للمنتج القائم عند إيقاف مزامنة المخزون
      }
      
      final categoryName = localData.remove('category_name') as String?;
      final categoryDescription = localData.remove('category_description') as String?;
      final multipleBarcodes = localData.remove('multiple_barcodes') as List<dynamic>?;
      
      // 📁 معالجة القسم: البحث بالاسم وإسناده، أو إنشاؤه تلقائياً إذا لم يكن موجوداً
      if (categoryName != null && categoryName.trim().isNotEmpty) {
        final trimmedCatName = categoryName.trim();
        final catRes = await db.query(
          'categories', 
          where: 'LOWER(TRIM(name)) = LOWER(?)', 
          whereArgs: [trimmedCatName], 
          limit: 1
        );
        if (catRes.isNotEmpty) {
          localData['category_id'] = catRes.first['id'];
        } else {
          final newCatId = await db.insert('categories', {
            'name': trimmedCatName,
            'description': categoryDescription,
          });
          localData['category_id'] = newCatId;
          print('📁 [ProductSyncService] تم إنشاء قسم جديد تلقائياً للجهاز الآخر: $trimmedCatName (ID: $newCatId)');
        }
      }

      // 🛡️ أعمدة هذا الجهاز فقط: عمود زائد من إصدار آخر كان يُفشل الإدراج
      // كله فلا يصل المنتج أبداً. ووصوله = مُزامَن (لا يُعاد رفعه من هنا).
      _productColumns ??= (await db.rawQuery('PRAGMA table_info(products)'))
          .map((c) => c['name'] as String)
          .toSet();
      localData.removeWhere((k, _) => !_productColumns!.contains(k));
      localData['last_synced_at'] = DateTime.now().toIso8601String();

      int localProductId;
      if (existing.isNotEmpty) {
        localProductId = existing.first['id'] as int;
        final oldUuid = existing.first['sync_uuid'] as String?;
        await db.transaction((txn) async {
          await txn.update('products', localData, where: 'id = ?', whereArgs: [localProductId]);
          // 📦 طوبق بالاسم فتغيّر معرّفه: بنوده وحركاته تتبعه، ورصيده
          // الافتتاحي يصير رصيد المعرّف الجديد (أو يُنشأ إن لم يصل بعد)
          if (oldUuid != null && oldUuid.isNotEmpty && oldUuid != syncUuid) {
            await StockLedger.rekeyProduct(txn, oldUuid, syncUuid);
          }
          await StockLedger.ensureOpenings(txn, onlyUuid: syncUuid, upload: false);
        });
        print('📦 [ProductSyncService] تم تحديث منتج محلي بالاسم/UUID: ${localData['name']} (ID: $localProductId)');
      } else {
        localProductId = await db.transaction((txn) async {
          final id = await txn.insert('products', localData);
          // 📦 منتج جديد هنا: رصيد افتتاحي مؤقت محلي (كميته في المستند) لا
          // يُرفع أبداً — رصيد منشئه يحلّ محله متى وصل (المعرّف واحد).
          await StockLedger.ensureOpenings(txn, onlyUuid: syncUuid, upload: false);
          return id;
        });
        print('📦 [ProductSyncService] تم إضافة منتج جديد من السحابة: ${localData['name']} (سعر: ${localData['unit_price'] ?? localData['price1']}, كمية: ${localData['stock_quantity']})');
      }
      
      // Handle multiple barcodes
      if (multipleBarcodes != null) {
        await db.delete('product_barcodes', where: 'product_id = ?', whereArgs: [localProductId]);
        for (var b in multipleBarcodes) {
          if (b is Map<String, dynamic>) {
            try {
              await db.insert('product_barcodes', {
                'product_id': localProductId,
                'barcode': b['barcode'] ?? '',
                'variant_label': b['variant_label'],
                'cost_price': b['cost_price'],
                'sell_price': b['sell_price'],
                'is_default': b['is_default'] ?? 0,
              });
            } catch (e) {
              print('Error inserting synced barcode: $e');
            }
          }
        }
      }
    } catch (e) {
      print('ProductSyncService - Error processing incoming product: $e');
    }
  }
}
