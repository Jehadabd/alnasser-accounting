// lib/services/firebase_sync/device_snapshot_service.dart
// 📸 خدمة لقطة الجهاز (Device Snapshot Service)
// تقوم بحساب وإرسال "ما قام به هذا الجهاز" ليتم التحقق منه في الأجهزة الأخرى

import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import 'firebase_sync_config.dart';

class DeviceSnapshot {
  final String deviceId;
  final DateTime timestamp;
  final int totalTransactions;
  final double totalDebtCreated;
  final int totalCustomersCreated;
  
  // تفصيل الديون لكل عميل (المعاملات التي أنشأها هذا الجهاز فقط)
  // Map<CustomerSyncUuid, TotalAmount>
  final Map<String, double> customerDebts;

  DeviceSnapshot({
    required this.deviceId,
    required this.timestamp,
    required this.totalTransactions,
    required this.totalDebtCreated,
    required this.totalCustomersCreated,
    required this.customerDebts,
  });

  Map<String, dynamic> toMap() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'total_transactions': totalTransactions,
      'total_debt_created': totalDebtCreated,
      'total_customers_created': totalCustomersCreated,
      'customer_debts': customerDebts, // Firestore يدعم Map
    };
  }
}

class DeviceSnapshotService {
  static final DeviceSnapshotService _instance = DeviceSnapshotService._internal();
  factory DeviceSnapshotService() => _instance;
  DeviceSnapshotService._internal();

  final DatabaseService _db = DatabaseService();
  FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore => _firestoreInstance ??= FirebaseFirestore.instance;

  /// 📸 إنشاء لقطة شاملة لما قام به هذا الجهاز
  Future<DeviceSnapshot> createSnapshot() async {
    final db = await _db.database;
    final deviceId = await FirebaseSyncConfig.getDeviceId();
    
    // 1. حساب إحصائيات المعاملات (فقط التي أنشأها هذا الجهاز)
    // is_created_by_me = 1
    final txStats = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        SUM(amount_changed) as total_amount
      FROM transactions
      WHERE is_created_by_me = 1
    ''');
    
    final totalTx = (txStats.first['count'] as int?) ?? 0;
    final totalAmount = (txStats.first['total_amount'] as num?)?.toDouble() ?? 0.0;

    // 2. حساب عدد العملاء الذين أنشأهم هذا الجهاز (تقريبياً، الذين لديهم transactions منه أو...)
    // الأفضل: ليس لدينا dirty flag للعميل CreatedByMe بشكل صريح في الجدول الحالي
    // لكن يمكننا عد العملاء الذين لديهم sync_uuid (إذا كنا ننشئ UUID محلياً)
    // للتبسيط: سنعد المعاملات، أما العملاء "المنشؤون" قد يكون صعب تحديده بدقة بدون عمود خاص
    // سنستخدم عدد العملاء الذين لديهم معاملات من هذا الجهاز كمؤشر
    final custCount = await db.rawQuery('''
      SELECT COUNT(DISTINCT customer_id) as count
      FROM transactions
      WHERE is_created_by_me = 1
    ''');
    final totalCust = (custCount.first['count'] as int?) ?? 0;

    // 3. 🔍 تفصيل الديون لكل عميل (الأهم للمطابقة)
    // نحتاج sync_uuid للعميل لأن ID المحلي يختلف بين الأجهزة
    final breakdownQuery = await db.rawQuery('''
      SELECT 
        c.sync_uuid,
        SUM(t.amount_changed) as local_debt
      FROM transactions t
      INNER JOIN customers c ON t.customer_id = c.id
      WHERE t.is_created_by_me = 1
      AND c.sync_uuid IS NOT NULL
      GROUP BY c.sync_uuid
    ''');

    final Map<String, double> customerDebts = {};
    for (final row in breakdownQuery) {
      final uuid = row['sync_uuid'] as String;
      final amount = (row['local_debt'] as num).toDouble();
      if (amount.abs() > 0.01) { // تجاهل الأصفار لتقليل الحجم
        customerDebts[uuid] = amount;
      }
    }

    print('📸 تم إنشاء لقطة الجهاز: $totalTx معاملة، $totalAmount دين، ${customerDebts.length} عميل نشط');

    return DeviceSnapshot(
      deviceId: deviceId,
      timestamp: DateTime.now(),
      totalTransactions: totalTx,
      totalDebtCreated: totalAmount,
      totalCustomersCreated: totalCust,
      customerDebts: customerDebts,
    );
  }

  /// ☁️ رفع اللقطة إلى Firebase
  Future<void> uploadSnapshot() async {
    try {
      final snapshot = await createSnapshot();
      final groupId = await FirebaseSyncConfig.getSyncGroupId();
      
      if (groupId == null) return;

      // المسار: sync_groups/{groupId}/snapshots/{deviceId}
      // نستخدم set لعمل overwrite دائماً (نريد أحدث حالة)
      await _firestore
          .collection('snapshots')
          .doc(snapshot.deviceId)
          .set(snapshot.toMap());
          
      print('☁️ ✅ تم رفع لقطة الجهاز بنجاح');
    } catch (e) {
      print('⚠️ فشل رفع لقطة الجهاز: $e');
      rethrow;
    }
  }

  /// 📥 تحميل لقطات جميع الأجهزة الأخرى
  Future<List<DeviceSnapshot>> fetchOtherDevicesSnapshots() async {
    try {
      final groupId = await FirebaseSyncConfig.getSyncGroupId();
      final myDeviceId = await FirebaseSyncConfig.getDeviceId();
      
      if (groupId == null) return [];

      final query = await _firestore
          .collection('snapshots')
          .get();

      return query.docs
          .where((doc) => doc.id != myDeviceId) // استبعاد جهازي
          .map((doc) {
            final data = doc.data();
            // تحويل Map<String, dynamic> إلى Map<String, double>
            final debtsMap = Map<String, double>.from(
              (data['customer_debts'] as Map? ?? {}).map(
                (k, v) => MapEntry(k, (v as num).toDouble()),
              ),
            );

            return DeviceSnapshot(
              deviceId: data['device_id'],
              timestamp: DateTime.parse(data['timestamp']),
              totalTransactions: data['total_transactions'],
              totalDebtCreated: (data['total_debt_created'] as num).toDouble(),
              totalCustomersCreated: data['total_customers_created'],
              customerDebts: debtsMap,
            );
          })
          .toList();
    } catch (e) {
      print('⚠️ فشل تحميل لقطات الأجهزة: $e');
      return [];
    }
  }
}
