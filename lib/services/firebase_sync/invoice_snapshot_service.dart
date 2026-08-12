// lib/services/firebase_sync/invoice_snapshot_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import '../invoice_settings_service.dart';
import 'firebase_sync_config.dart';

class InvoiceSnapshot {
  final String deviceId;
  final DateTime timestamp;
  final int totalInvoices;
  final double totalAmount;
  // Map<invoiceUuid, version>
  final Map<String, int> invoiceVersions;

  InvoiceSnapshot({
    required this.deviceId,
    required this.timestamp,
    required this.totalInvoices,
    required this.totalAmount,
    required this.invoiceVersions,
  });

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'total_invoices': totalInvoices,
      'total_amount': totalAmount,
      'invoice_versions': invoiceVersions,
    };
  }
}

class InvoiceSnapshotService {
  static final InvoiceSnapshotService _instance = InvoiceSnapshotService._internal();
  factory InvoiceSnapshotService() => _instance;
  InvoiceSnapshotService._internal();

  final DatabaseService _db = DatabaseService();
  FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore {
    _firestoreInstance ??= FirebaseFirestore.instance;
    return _firestoreInstance!;
  }

  /// 📸 إنشاء لقطة شاملة لفواتير هذا الجهاز
  Future<InvoiceSnapshot> createSnapshot() async {
    final db = await _db.database;
    final deviceId = await FirebaseSyncConfig.getDeviceId();
    
    // جلب جميع الفواتير (حتى الملغاة لمعرفة أحدث نسخة)
    final invoicesList = await db.query('invoices');
    
    int totalInvoices = 0;
    double totalAmount = 0.0;
    Map<String, int> invoiceVersions = {};
    
    for (var invoiceData in invoicesList) {
      final String? uuid = invoiceData['invoice_uuid'] as String?;
      final int version = (invoiceData['version'] as num?)?.toInt() ?? 1;
      final double amount = (invoiceData['total_amount'] as num?)?.toDouble() ?? 0.0;
      final int isCancelled = (invoiceData['is_cancelled'] as num?)?.toInt() ?? 0;
      
      if (uuid != null && uuid.isNotEmpty) {
        invoiceVersions[uuid] = version;
        
        // لا نحسب الفواتير الملغاة ضمن المجموع الكلي
        if (isCancelled == 0) {
          totalInvoices++;
          totalAmount += amount;
        }
      }
    }

    print('📸 تم إنشاء لقطة الفواتير: $totalInvoices فاتورة، $totalAmount إجمالي');

    return InvoiceSnapshot(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      totalInvoices: totalInvoices,
      totalAmount: totalAmount,
      invoiceVersions: invoiceVersions,
    );
  }

  /// ☁️ رفع لقطة الفواتير إلى Firebase
  Future<void> uploadSnapshot() async {
    try {
      final snapshot = await createSnapshot();
      final groupId = await FirebaseSyncConfig.getSyncGroupId();
      
      if (groupId == null) return;

      // المسار: sync_groups/{groupId}/invoice_snapshots/{deviceId}
      await _firestore
          .collection('invoice_snapshots')
          .doc(snapshot.deviceId)
          .set(snapshot.toMap());
          
      print('☁️ ✅ تم رفع لقطة الفواتير بنجاح (الجهاز ${snapshot.deviceId})');
    } catch (e) {
      print('⚠️ فشل رفع لقطة الفواتير: $e');
      rethrow;
    }
  }

  /// 📥 تحميل لقطات جميع الأجهزة الأخرى
  Future<List<InvoiceSnapshot>> fetchOtherDevicesSnapshots() async {
    try {
      final groupId = await FirebaseSyncConfig.getSyncGroupId();
      final myDeviceId = await FirebaseSyncConfig.getDeviceId();
      
      if (groupId == null) return [];

      final query = await _firestore
          .collection('invoice_snapshots')
          .get();

      return query.docs
          .where((doc) => doc.id != myDeviceId) // استبعاد جهازي
          .map((doc) {
            final data = doc.data();
            
            // تحويل Map<String, dynamic> إلى Map<String, int>
            final versionsMap = Map<String, int>.from(
              (data['invoice_versions'] as Map? ?? {}).map(
                (k, v) => MapEntry(k, (v as num).toInt()),
              ),
            );

            return InvoiceSnapshot(
              deviceId: data['device_id'],
              timestamp: DateTime.parse(data['timestamp']),
              totalInvoices: data['total_invoices'] ?? 0,
              totalAmount: (data['total_amount'] as num?)?.toDouble() ?? 0.0,
              invoiceVersions: versionsMap,
            );
          })
          .toList();
    } catch (e) {
      print('⚠️ فشل تحميل لقطات فواتير الأجهزة: $e');
      return [];
    }
  }
}
