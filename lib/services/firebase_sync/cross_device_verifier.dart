// lib/services/firebase_sync/cross_device_verifier.dart
// 🛡️ خدمة التحقق المتبادل بين الأجهزة (Cross-Device Verification)
// تقوم بمقارنة "ما يدعي الجهاز الآخر أنه أرسله" مع "ما استقبله هذا الجهاز فعلياً"

import '../database_service.dart';
import 'device_snapshot_service.dart';

class VerificationDiscrepancy {
  final String customerName;
  final String customerSyncUuid;
  final double remoteClaimedAmount; // المبلغ في لقطة الجهاز الآخر (ما أرسله)
  final double localReceivedAmount; // المبلغ الموجود محلياً من الجهاز الآخر (ما استلمناه)
  final double difference;

  VerificationDiscrepancy({
    required this.customerName,
    required this.customerSyncUuid,
    required this.remoteClaimedAmount,
    required this.localReceivedAmount,
  }) : difference = remoteClaimedAmount - localReceivedAmount;

  @override
  String toString() {
    return 'خلاف للعميل $customerName: الجهاز الآخر يقول $remoteClaimedAmount، لدينا فقط $localReceivedAmount (الفرق: $difference)';
  }
}

class VerificationReport {
  final DateTime timestamp;
  final int totalCustomersChecked;
  final int totalDiscrepancies;
  final List<VerificationDiscrepancy> discrepancies;
  final double totalDebtDifference;

  VerificationReport({
    required this.timestamp,
    required this.totalCustomersChecked,
    required this.discrepancies,
  }) : totalDiscrepancies = discrepancies.length,
       totalDebtDifference = discrepancies.fold(0, (sum, item) => sum + item.difference.abs());
}

class CrossDeviceVerifier {
  static final CrossDeviceVerifier _instance = CrossDeviceVerifier._internal();
  factory CrossDeviceVerifier() => _instance;
  CrossDeviceVerifier._internal();

  final DatabaseService _db = DatabaseService();
  final DeviceSnapshotService _snapshotService = DeviceSnapshotService();

  /// 🛡️ تنفيذ عملية التحقق الشاملة
  Future<VerificationReport> runVerification() async {
    print('🛡️ بدء عملية التدقيق المالي المتبادل...');
    final startTime = DateTime.now();
    
    // 1. جلب لقطات الأجهزة الأخرى (Remote Claims)
    final snapshots = await _snapshotService.fetchOtherDevicesSnapshots();
    
    if (snapshots.isEmpty) {
      print('ℹ️ لا توجد لقطات من أجهزة أخرى للمقارنة');
      return VerificationReport(
        timestamp: startTime,
        totalCustomersChecked: 0,
        discrepancies: [],
      );
    }

    // 2. تجميع الديون المتوقعة لكل عميل من جميع الأجهزة الأخرى (Global Remote Truth)
    // Map<CustomerSyncUuid, TotalAmount>
    final Map<String, double> remoteClaims = {};
    
    for (var snapshot in snapshots) {
      snapshot.customerDebts.forEach((uuid, amount) {
        remoteClaims[uuid] = (remoteClaims[uuid] ?? 0.0) + amount;
      });
    }

    // 3. حساب ما تم استلامه محلياً (Local Receipts)
    // نجمع المعاملات التي:
    // - ليست من إنشائي (is_created_by_me = 0)
    // - ولها transaction_uuid (جاءت من المزامنة)
    final db = await _db.database;
    final localReceiptsQuery = await db.rawQuery('''
      SELECT 
        c.sync_uuid,
        c.name,
        SUM(t.amount_changed) as local_received
      FROM transactions t
      INNER JOIN customers c ON t.customer_id = c.id
      WHERE t.is_created_by_me = 0
      AND t.transaction_uuid IS NOT NULL
      AND c.sync_uuid IS NOT NULL
      GROUP BY c.sync_uuid
    ''');

    final Map<String, double> localReceipts = {};
    final Map<String, String> customerNames = {}; // uuid -> name

    for (var row in localReceiptsQuery) {
      final uuid = row['sync_uuid'] as String;
      localReceipts[uuid] = (row['local_received'] as num).toDouble();
      customerNames[uuid] = row['name'] as String;
    }

    // 4. المقارنة واكتشاف الفوارق (The Audit)
    final List<VerificationDiscrepancy> discrepancies = [];
    final Set<String> allCustomerUuids = {...remoteClaims.keys, ...localReceipts.keys};

    for (var uuid in allCustomerUuids) {
      final claimed = remoteClaims[uuid] ?? 0.0;
      final received = localReceipts[uuid] ?? 0.0;
      final diff = (claimed - received).abs();

      // السماح بفرق بسيط جداً (Floating Point Error)
      if (diff > 0.01) {
        // محاولة العثور على اسم العميل إذا لم يكن موجوداً في localReceipts
        String name = customerNames[uuid] ?? 'عميل غير معروف';
        if (name == 'عميل غير معروف') {
           // محاولة جلبه من الـ DB حتى لو لم يكن له معاملات واردة
           final custRow = await db.query('customers', 
             columns: ['name'], 
             where: 'sync_uuid = ?', 
             whereArgs: [uuid], 
             limit: 1
           );
           if (custRow.isNotEmpty) {
             name = custRow.first['name'] as String;
           }
        }

        discrepancies.add(VerificationDiscrepancy(
          customerName: name,
          customerSyncUuid: uuid,
          remoteClaimedAmount: claimed,
          localReceivedAmount: received,
        ));
      }
    }

    final report = VerificationReport(
      timestamp: startTime,
      totalCustomersChecked: allCustomerUuids.length,
      discrepancies: discrepancies,
    );

    print('🛡️ اكتمل التدقيق: تم فحص ${report.totalCustomersChecked} عميل، وجد ${report.totalDiscrepancies} خلاف.');
    for (var d in discrepancies) {
      print('🔴 $d');
    }

    return report;
  }
}
