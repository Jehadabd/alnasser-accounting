// lib/services/firebase_sync/invoice_resolution_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import 'firebase_sync_config.dart';
import 'invoice_sync_service.dart';

class InvoiceResolutionService {
  static final InvoiceResolutionService _instance = InvoiceResolutionService._internal();
  factory InvoiceResolutionService() => _instance;
  InvoiceResolutionService._internal();

  final DatabaseService _db = DatabaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// فرض مزامنة الفواتير (من الحاسوب الصحيح إلى بقية الأجهزة)
  /// يقوم بجلب الفواتير المحددة (أو كل الفواتير) وإعادة رفعها إلى Firebase
  Future<void> forceSyncInvoices(List<String> invoiceUuidsToForce) async {
    print('🔄 بدء عملية فرض المزامنة من الحاسوب الصحيح...');
    
    final db = await _db.database;
    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    if (groupId == null) throw Exception('مجموعة المزامنة غير معرفة');

    final batch = _firestore.batch();
    final collection = _firestore.collection('invoices');

    int uploadedCount = 0;

    for (final uuid in invoiceUuidsToForce) {
      // 1. جلب الفاتورة من SQLite
      final invoiceMaps = await db.query('invoices', where: 'invoice_uuid = ?', whereArgs: [uuid]);
      if (invoiceMaps.isEmpty) continue;
      
      final invoiceData = Map<String, dynamic>.from(invoiceMaps.first);
      final int invoiceId = invoiceData['id'] as int;
      
      // 2. جلب بنود الفاتورة
      final itemsMaps = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      
      // تجهيز بيانات البنود
      List<Map<String, dynamic>> itemsList = [];
      for (var itemMap in itemsMaps) {
        final item = Map<String, dynamic>.from(itemMap);
        // إزالة الحقول التي لا نريد رفعها (مثل الـ ID المحلي)
        item.remove('id');
        item.remove('invoice_id');
        itemsList.add(item);
      }
      
      // إضافة البنود لبيانات الفاتورة
      invoiceData['items'] = itemsList;
      invoiceData['_uploaded_at'] = FieldValue.serverTimestamp();
      
      // 🔒 لا نكتب groupSecret في السحابة (قواعد Firestore لا تطلبه، وكشفه
      // يسمح بتزوير توقيعات المعاملات).
      
      // 3. رفعها للفايربيس
      final docRef = collection.doc(uuid);
      batch.set(docRef, invoiceData);
      
      uploadedCount++;
    }

    if (uploadedCount > 0) {
      await batch.commit();
      print('✅ تم فرض مزامنة $uploadedCount فاتورة بنجاح!');
    } else {
      print('ℹ️ لم يتم العثور على أي فواتير لفرض مزامنتها.');
    }
  }

  /// فرض مزامنة جميع الفواتير من هذا الجهاز
  Future<void> forceSyncAllInvoices() async {
    final db = await _db.database;
    final invoicesMaps = await db.query('invoices', columns: ['invoice_uuid']);
    
    List<String> allUuids = [];
    for (var row in invoicesMaps) {
      final uuid = row['invoice_uuid'] as String?;
      if (uuid != null && uuid.isNotEmpty) {
        allUuids.add(uuid);
      }
    }
    
    if (allUuids.isNotEmpty) {
      await forceSyncInvoices(allUuids);
    }
  }
}
