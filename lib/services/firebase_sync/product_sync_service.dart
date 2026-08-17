import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import '../invoice_settings_service.dart';
import 'firebase_sync_config.dart';
import '../../models/product.dart';

class ProductSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();
  String? _deviceId;
  bool _isListening = false;

  Future<void> startSync() async {
    if (_isListening) return;
    _deviceId = (await InvoiceSettingsService.getInvoiceDeviceId()).toString();
    
    // 1. Upload pending products
    await syncPendingProducts();
    
    // 2. Listen for incoming products
    _listenForIncomingProducts();
    _isListening = true;
  }

  Future<void> syncPendingProducts() async {
    try {
      final db = await _dbService.database;
      final pendingProducts = await db.query(
        'products',
        where: 'last_synced_at IS NULL OR last_modified_by_device_id = ?',
        whereArgs: [_deviceId],
      );

      for (var p in pendingProducts) {
        if (p['sync_uuid'] != null) {
          await uploadProductNow(p['sync_uuid'] as String, productData: p);
        }
      }
    } catch (e) {
      print('ProductSyncService - Error syncing pending products: \$e');
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
      
      _deviceId ??= (await InvoiceSettingsService.getInvoiceDeviceId()).toString();

      final payload = Map<String, dynamic>.from(productData!);
      payload['uploaded_at'] = FieldValue.serverTimestamp();
      
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
        if (categoryId != null) {
          final catRes = await db.query('categories', where: 'id = ?', whereArgs: [categoryId], limit: 1);
          if (catRes.isNotEmpty) {
            payload['category_name'] = catRes.first['name'];
          }
        }
      }
      
      await _firestore.collection('products').doc(syncUuid).set(payload, SetOptions(merge: true));
      
      await db.update('products', {'last_synced_at': DateTime.now().toIso8601String()}, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
    } catch (e) {
      print('ProductSyncService - Error uploading product \$syncUuid: \$e');
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
      
      _deviceId ??= (await InvoiceSettingsService.getInvoiceDeviceId()).toString();
      
      if (data['last_modified_by_device_id'] == _deviceId) {
        return; // Ignore updates that we created ourselves
      }

      final db = await _dbService.database;
      final existing = await db.query('products', where: 'sync_uuid = ?', whereArgs: [syncUuid], limit: 1);
      
      final incomingModifiedAtStr = data['last_modified_at'] as String?;
      if (incomingModifiedAtStr == null) return;
      final incomingModifiedAt = DateTime.tryParse(incomingModifiedAtStr);
      if (incomingModifiedAt == null) return;

      if (existing.isNotEmpty) {
        final existingModifiedAtStr = existing.first['last_modified_at'] as String?;
        if (existingModifiedAtStr != null) {
          final existingModifiedAt = DateTime.tryParse(existingModifiedAtStr);
          if (existingModifiedAt != null && !incomingModifiedAt.isAfter(existingModifiedAt)) {
             return; // Local is newer or same
          }
        }
      }
        
        final localData = Map<String, dynamic>.from(data);
        localData.remove('id'); // Keep local id
        localData.remove('uploaded_at');
        
        // 🚀 تحقق من إعداد المستخدم: هل يسمح بمزامنة المخزون المباشرة من تفاصيل المنتج؟
        final isDirectStockSyncEnabled = await FirebaseSyncSecuritySettings.isDirectStockSyncEnabled();
        if (!isDirectStockSyncEnabled) {
          localData.remove('stock_quantity'); // الوضع الآمن الافتراضي: تحديث المخزون فقط عبر الفواتير
        }
        
        final categoryName = localData.remove('category_name') as String?;
        final multipleBarcodes = localData.remove('multiple_barcodes') as List<dynamic>?;
        
        if (categoryName != null && categoryName.isNotEmpty) {
          final catRes = await db.query('categories', where: 'name = ?', whereArgs: [categoryName], limit: 1);
          if (catRes.isNotEmpty) {
            localData['category_id'] = catRes.first['id'];
          } else {
            final newCatId = await db.insert('categories', {'name': categoryName});
            localData['category_id'] = newCatId;
          }
        }

        int localProductId;
        if (existing.isNotEmpty) {
          localProductId = existing.first['id'] as int;
          await db.update('products', localData, where: 'sync_uuid = ?', whereArgs: [syncUuid]);
        } else {
          if (!isDirectStockSyncEnabled) {
            localData['stock_quantity'] = 0.0;
          }
          localProductId = await db.insert('products', localData);
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
      print('ProductSyncService - Error processing incoming product: \$e');
    }
  }
}
