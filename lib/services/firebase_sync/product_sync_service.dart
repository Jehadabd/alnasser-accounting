import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import '../database/core/database_helpers.dart';
import '../database/business/stock_ledger.dart';
import 'firebase_sync_config.dart';
import 'sync_health.dart';
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
    unawaited(checkLocalDuplicateNames());

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
    await uploadPendingCopies();
  }

  /// يرفع مستندات النسخ المحلية التي دُمجت قبل أن تُرفع (انظر
  /// _processIncomingProduct). «أنشئ إن غاب» فلا يكتب فوق مستند قائم، ويُعاد
  /// مع كل رفع للمعلّق حتى ينجح.
  Future<void> uploadPendingCopies() async {
    try {
      final db = await _dbService.database;
      final rows = await db.query('product_uuid_alias',
          columns: ['old_uuid', 'pending_doc'], where: 'pending_doc IS NOT NULL');
      for (final r in rows) {
        final uuid = r['old_uuid'] as String;
        try {
          final payload =
              Map<String, dynamic>.from(jsonDecode(r['pending_doc'] as String) as Map);
          payload['sync_uuid'] = uuid;
          payload['uploaded_at'] = FieldValue.serverTimestamp();
          payload['last_modified_by_device_id'] = await _myDeviceId();
          final catId = payload['category_id'] as int?;
          if (catId != null && catId > 0) {
            final cat = await db.query('categories', where: 'id = ?', whereArgs: [catId], limit: 1);
            if (cat.isNotEmpty) {
              payload['category_name'] = cat.first['name'];
              payload['category_description'] = cat.first['description'];
            }
          }
          final ref = _firestore.collection('products').doc(uuid);
          await _firestore.runTransaction((txn) async {
            final snap = await txn.get(ref);
            if (!snap.exists) txn.set(ref, payload);
          }).timeout(const Duration(seconds: 30));
          await db.update('product_uuid_alias', {'pending_doc': null},
              where: 'old_uuid = ?', whereArgs: [uuid]);
        } catch (e) {
          print('⚠️ [ProductSyncService] تعذّر رفع النسخة المدموجة $uuid: $e (يُعاد لاحقاً)');
        }
      }
    } catch (e) {
      print('⚠️ [ProductSyncService] النسخ المدموجة: $e');
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
      // القائمة كاملة من السيرفر: ما عندي وغاب منها يُعاد (بلا قراءة إضافية)
      if (!snapshot.metadata.isFromCache) {
        unawaited(rebroadcastMissingProducts(
                cloudIds: snapshot.docs.map((d) => d.id).toSet())
            .catchError((_) => 0));
      }
    } catch (e) {
      print('❌ [ProductSyncService] خطأ أثناء تنزيل المنتجات: $e');
    }
  }

  /// 🛡️ يعيد إنشاء مستندات أصناف هذا الجهاز الغائبة من السحابة — «أنشئ إن
  /// غاب»، لا يكتب فوق مستند قائم. لا شيء في التطبيق يحذف مستندات الأصناف،
  /// فغيابها = بيانات السحابة حُذفت من خارج التطبيق (لوحة Firebase) أو نُقلت
  /// المجموعة لمشروع جديد؛ وبدونها يستلم الجهاز الجديد بنوداً وحركات بلا أصناف.
  /// [cloudIds] = معرّفات السحابة إن قُرئت للتو؛ وإلا تُقرأ من السيرفر.
  Future<int> rebroadcastMissingProducts({Set<String>? cloudIds, void Function()? onTick}) async {
    final ids = cloudIds ??
        (await _firestore
                .collection('products')
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 60)))
            .docs
            .map((d) => d.id)
            .toSet();
    final db = await _dbService.database;
    final rows = (await db.query('products', where: "sync_uuid IS NOT NULL AND sync_uuid != ''"))
        .where((r) => !ids.contains(r['sync_uuid']))
        .toList();
    var n = 0;
    for (final r in rows) {
      final uuid = r['sync_uuid'] as String;
      try {
        final payload = await _productPayload(uuid, r);
        // إعادة لما كان: صاحب آخر تعديل يبقى كما هو لا «أنا»
        final by = r['last_modified_by_device_id'];
        if (by != null) payload['last_modified_by_device_id'] = by;
        final ref = _firestore.collection('products').doc(uuid);
        final created = await _firestore.runTransaction<bool>((txn) async {
          final snap = await txn.get(ref);
          if (snap.exists) return false;
          txn.set(ref, payload);
          return true;
        }).timeout(const Duration(seconds: 30));
        if (created) n++;
      } catch (e) {
        print('⚠️ [ProductSyncService] إعادة إنشاء الصنف $uuid: $e');
      }
      onTick?.call();
    }
    if (n > 0) print('📦 [ProductSyncService] أُعيد إنشاء $n مستند صنف غاب من السحابة');
    return n;
  }

  /// حمولة مستند الصنف من صفه المحلي (+ الباركودات واسم القسم).
  Future<Map<String, dynamic>> _productPayload(String syncUuid, Map<String, dynamic> productData) async {
    final db = await _dbService.database;
    final me = await _myDeviceId();

    final payload = Map<String, dynamic>.from(productData);
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
    return payload;
  }

  Future<void> uploadProductNow(String syncUuid, {Map<String, dynamic>? productData}) async {
    try {
      final db = await _dbService.database;

      if (productData == null) {
        final res = await db.query('products', where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
        if (res.isEmpty) return;
        productData = res.first;
      }

      final payload = await _productPayload(syncUuid, productData!);

      await _firestore
          .collection('products')
          .doc(syncUuid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 60));
      SyncHealth.reportUploadOk('products');

      await db.update('products', {'last_synced_at': DateTime.now().toIso8601String()}, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
      print('📦 [ProductSyncService] تم رفع المنتج بنجاح: ${payload['name']} ($syncUuid)');
    } catch (e) {
      SyncHealth.reportUploadError('products', e);
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

  /// هل تغلب النسخة الواردة النسخة المحلية من المنتج نفسه؟ وقت التعديل الأحدث،
  /// والوقت المعروف يغلب المجهول، وعند التساوي المعرّف الأكبر — ترتيب كامل
  /// لا يتوقف على الجهاز ولا على ترتيب الوصول.
  static bool _copyWins(Object? inMod, String inUuid, Object? localMod, String localUuid) {
    final a = DateTime.tryParse(inMod?.toString() ?? '');
    final b = DateTime.tryParse(localMod?.toString() ?? '');
    if (a != null && b != null) {
      if (a.isAfter(b)) return true;
      if (b.isAfter(a)) return false;
    } else if (a != null || b != null) {
      return a != null;
    }
    return inUuid.compareTo(localUuid) > 0;
  }

  /// تنبيه دمج نسختين (SyncHealth) على الجهاز الذي أُدخلت عليه إحداهما فقط:
  /// هناك يعرف المستخدم الرصيد الذي أدخله ويراجع الكمية. [loserUuid] يثبّت
  /// التنبيه لكل دمج فلا يتكرر.
  Future<void> _noticeMerge(String loserUuid, Map<String, dynamic> localRow,
      Map<String, dynamic> incoming) async {
    try {
      final me = await _myDeviceId();
      if (localRow['created_by_device_id'] != me && incoming['created_by_device_id'] != me) {
        return;
      }
      await SyncHealth.addMergeNotice(
          id: loserUuid, productName: (incoming['name'] ?? localRow['name'] ?? '').toString());
    } catch (_) {}
  }

  /// 🛡️ المستندات الواردة تُعالَج واحداً تلو الآخر (لكل نسخ الخدمة). المستمع
  /// والتنزيل الكامل كانا يعالجان نسختين من المستند نفسه في آن واحد: كلتاهما
  /// لا تجد الصف فتُدرجه، فتفشل الأحدث (UNIQUE) وتبقى الأقدم للأبد — ومع
  /// نسختين من المنتج نفسه يبقى جهاز على الخاسرة (اختبار الكود الحقيقي).
  static Future<void> _incomingQueue = Future<void>.value();

  Future<void> _processIncomingProduct(Map<String, dynamic> data) {
    final run = _incomingQueue.then((_) => _applyIncomingProduct(data));
    _incomingQueue = run.catchError((Object _) {});
    return run;
  }

  /// عملية على الأصناف لا تتداخل مع معالجة المستندات الواردة (الطابور نفسه):
  /// إضافة صنف تفحص أن اسمه غير موجود ثم تُدرجه دون أن يُدرج الوارد بينهما.
  /// [action] لا تنتظر أي معالجة واردة (وإلا انتظرت نفسها).
  static Future<T> runExclusive<T>(Future<T> Function() action) {
    final run = _incomingQueue.then((_) => action());
    _incomingQueue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// أصناف متكررة الاسم على هذا الجهاز (من إصدارات سابقة سمحت بها): المزامنة
  /// تعدّ الاسم نفسه صنفاً واحداً، فجهاز ينضم لاحقاً يدمجهما — تنبيه للمستخدم.
  Future<void> checkLocalDuplicateNames() async {
    try {
      final db = await _dbService.database;
      final rows = await db.rawQuery('''
        SELECT MIN(TRIM(name)) AS n FROM products
        WHERE sync_uuid IS NOT NULL AND sync_uuid != ''
        GROUP BY COALESCE(NULLIF(name_norm, ''), TRIM(name))
        HAVING COUNT(*) > 1''');
      SyncHealth.setLocalDuplicates([for (final r in rows) (r['n'] ?? '').toString()]);
    } catch (e) {
      print('⚠️ [ProductSyncService] فحص الأسماء المكررة: $e');
    }
  }

  Future<void> _applyIncomingProduct(Map<String, dynamic> data) async {
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

      final existingUuid = existing.isEmpty ? null : existing.first['sync_uuid'] as String?;
      if (existingUuid != null && existingUuid.isNotEmpty && existingUuid != syncUuid) {
        // 🛡️ نسختان من المنتج نفسه (الاسم نفسه أُنشئ على جهازين قبل أن يتزامنا).
        // الباقية تُختار بترتيب كامل (وقت التعديل ثم المعرّف) فيتفق عليها كل
        // جهاز مهما كان ترتيب الوصول — كان «الوقت فقط» يُبقي عند التساوي
        // نسخة مختلفة على كل جهاز. والخاسرة الواردة لا تُهمل: كل ما يشير إليها
        // (حركات، بنود فواتير) يتبع الباقية هنا، الآن ولاحقاً.
        if (!_copyWins(data['last_modified_at'], syncUuid,
            existing.first['last_modified_at'], existingUuid)) {
          final known = await db.query('product_uuid_alias',
              columns: ['old_uuid'],
              where: 'old_uuid = ? AND new_uuid = ?',
              whereArgs: [syncUuid, existingUuid],
              limit: 1);
          await db.transaction((txn) => StockLedger.rekeyProduct(txn, syncUuid, existingUuid));
          if (known.isEmpty) {
            await _noticeMerge(syncUuid, existing.first, data);
          }
          return;
        }
      } else {
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
        final merged = oldUuid != null && oldUuid.isNotEmpty && oldUuid != syncUuid;
        // 🛡️ نسخة محلية لم يُرفع مستندها قط وتُستبدل الآن: يُرفع رغم ذلك،
        // وإلا لا تعرف الأجهزة الأخرى أن معرّفها هو هذا المنتج، فتبقى بنود
        // فواتير هذا الجهاز وحركاته المرفوعة به عندها بلا منتج
        final unsentCopy = merged && existing.first['last_synced_at'] == null;
        await db.transaction((txn) async {
          await txn.update('products', localData, where: 'id = ?', whereArgs: [localProductId]);
          // 📦 طوبق بالاسم فتغيّر معرّفه: بنوده وحركاته تتبعه، ورصيده
          // الافتتاحي يصير رصيد المعرّف الجديد (أو يُنشأ إن لم يصل بعد)
          if (merged) {
            await StockLedger.rekeyProduct(txn, oldUuid, syncUuid);
            if (unsentCopy) {
              await txn.update('product_uuid_alias',
                  {'pending_doc': jsonEncode(Map<String, dynamic>.from(existing.first)..remove('id'))},
                  where: 'old_uuid = ?', whereArgs: [oldUuid]);
            }
          }
          await StockLedger.ensureOpenings(txn, onlyUuid: syncUuid, upload: false);
        });
        if (unsentCopy) unawaited(uploadPendingCopies());
        if (merged) await _noticeMerge(oldUuid, existing.first, data);
        print('📦 [ProductSyncService] تم تحديث منتج محلي بالاسم/UUID: ${localData['name']} (ID: $localProductId)');
      } else {
        localProductId = await db.transaction((txn) async {
          final id = await txn.insert('products', localData);
          // صار حيّاً هنا (أُعيدت تسميته بعد دمج قديم مثلاً): ما يصل بمعرّفه
          // من الآن يبقى له، لا يُحوَّل للصنف الذي دُمج فيه
          await txn.delete('product_uuid_alias', where: 'old_uuid = ?', whereArgs: [syncUuid]);
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
