// lib/services/firebase_sync/discrepancy_resolution_service.dart
// 🩹 خدمة معالجة الفروقات: تستعيد المعاملة المفقودة من مصدرها.
// 🔒 لا تحتوي على أي طريق لاختراع مبلغ تصحيحي — المعاملة تُجلب أو لا شيء.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import 'firebase_sync_config.dart';
import '../../models/transaction.dart';

enum ResolutionType {
  restoreMissing, // استعادة معاملات مفقودة
  /// فرق وُجد لكن لم تُحدد المعاملة الناقصة — لا نخترع مبلغاً تصحيحيّاً.
  unresolved,
  none, // لا يوجد خلل
}

class ResolutionAssessment {
  final ResolutionType type;
  final List<String> missingTransactionUuids;
  final double discrepancyAmount;
  final String message;

  ResolutionAssessment({
    required this.type,
    this.missingTransactionUuids = const [],
    this.discrepancyAmount = 0.0,
    required this.message,
  });
}

class DiscrepancyResolutionService {
  static final DiscrepancyResolutionService _instance = DiscrepancyResolutionService._internal();
  factory DiscrepancyResolutionService() => _instance;
  DiscrepancyResolutionService._internal();

  final DatabaseService _db = DatabaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔍 فحص عميل محدد للبحث عن الفروقات وتحديد سببها
  Future<ResolutionAssessment> analyzeCustomer(String customerSyncUuid, double localBalance, double remoteBalance) async {
    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    if (groupId == null) return ResolutionAssessment(type: ResolutionType.none, message: 'المزامنة غير مفعلة');

    final diff = (remoteBalance - localBalance);
    if (diff.abs() < 0.01) {
      return ResolutionAssessment(type: ResolutionType.none, message: 'البيانات متطابقة');
    }

    try {
      // 1. جلب قائمة UUIDs للمعاملات المحلية لهذا العميل (من غير المحذوفة)
      final db = await _db.database;
      final localTxResults = await db.rawQuery('''
        SELECT t.transaction_uuid 
        FROM transactions t
        INNER JOIN customers c ON t.customer_id = c.id
        WHERE c.sync_uuid = ? AND (t.is_deleted IS NULL OR t.is_deleted = 0)
      ''', [customerSyncUuid]);
      
      final Set<String> localUuids = localTxResults
          .map((row) => row['transaction_uuid'] as String?)
          .where((uuid) => uuid != null)
          .cast<String>()
          .toSet();

      // 2. جلب قائمة UUIDs للمعاملات في Firebase لهذا العميل
      // ملاحظة: هذا قد يكون مكلفاً إذا كان العدد كبيراً، لكننا نفعله عند الطلب فقط
      final remoteTxDocs = await _firestore
          .collection('transactions')
          .where('customerSyncUuid', isEqualTo: customerSyncUuid)
          .where('isDeleted', isNotEqualTo: true)
          .get();

      final Set<String> remoteUuids = remoteTxDocs.docs
          .map((doc) => doc.id)
          .toSet();

      // 3. تحديد المعاملات المفقودة (موجودة في السحابة وغير موجودة محلياً)
      final missingUuids = remoteUuids.difference(localUuids).toList();

      if (missingUuids.isNotEmpty) {
        return ResolutionAssessment(
          type: ResolutionType.restoreMissing,
          missingTransactionUuids: missingUuids,
          discrepancyAmount: diff,
          message: 'تم العثور على ${missingUuids.length} معاملة مفقودة في هذا الجهاز.',
        );
      } else {
        // إذا كانت الـ UUIDs متطابقة ولكن الأرقام تختلف، فهذا يعني تعديل في القيم
        // أو معاملات موجودة محلياً وغير مرفوعة (وهو ما لا يفسر نقص الرصيد المحلي عادةً إلا إذا كانت خصم)
        // أو معاملات محذوفة محلياً ولكن ليس سحابياً (وهو ما تغطيه النقطة 3 لأننا فلترنا المحذوف محلياً)
        return ResolutionAssessment(
          type: ResolutionType.unresolved,
          discrepancyAmount: diff,
          message:
              'القيم تختلف دون معاملة ناقصة ظاهرة. استخدم شاشة المطابقة بين الأجهزة.',
        );
      }
    } catch (e) {
      print('❌ خطأ في تحليل العميل: $e');
      return ResolutionAssessment(
        type: ResolutionType.unresolved,
        discrepancyAmount: diff,
        message: 'حدث خطأ أثناء التحليل. استخدم شاشة المطابقة بين الأجهزة.',
      );
    }
  }

  /// 🩹 تنفيذ الإصلاح: استعادة المعاملات المفقودة
  Future<int> restoreMissingTransactions(List<String> missingUuids) async {
    final groupId = await FirebaseSyncConfig.getSyncGroupId();
    if (groupId == null) return 0;

    int restoredCount = 0;
    // نستخدم الـ view_transaction tool منطقياً هنا عن طريق استدعاء خدمة المزامنة
    // لكن بما أننا داخل Service، سنستدعي逻辑 الإدخال مباشرة أو عبر FirebaseSyncService
    // لتجنب التعقيد، سنقرأ من Firestore وندخلها في DB مباشرة باستخدام DatabaseService
    
    final dbService = DatabaseService();

    for (final uuid in missingUuids) {
      try {
        final doc = await _firestore
            .collection('transactions')
            .doc(uuid)
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          await _insertRestoredTransaction(dbService, uuid, data);
          restoredCount++;
        }
      } catch (e) {
        print('❌ فشل استعادة المعاملة $uuid: $e');
      }
    }
    
    // إعادة حساب رصيد العميل بعد الاستعادة
    // (يتم ضمنياً إذا استخدمنا الدوال الصحيحة، لكن للتأكيد)
    return restoredCount;
  }

  /// إدخال المعاملة المستعادة
  Future<void> _insertRestoredTransaction(DatabaseService dbService, String transactionUuid, Map<String, dynamic> data) async {
    final customerSyncUuid = data['customerSyncUuid'] as String?;
    if (customerSyncUuid == null) return;

    // البحث عن العميل المحلي
    final db = await _db.database;
    final custRow = await db.query(
      'customers',
      columns: ['id'],
      where: 'sync_uuid = ?',
      whereArgs: [customerSyncUuid],
    );

    if (custRow.isEmpty) return; // العميل غير موجود!
    final customerId = custRow.first['id'] as int;

    final tx = DebtTransaction(
      id: 0, // Auto increment
      customerId: customerId,
      transactionDate: data['transactionDate'] is String 
          ? DateTime.parse(data['transactionDate']) 
          : (data['transactionDate'] as Timestamp).toDate(),
      amountChanged: (data['amountChanged'] as num).toDouble(),
      balanceBeforeTransaction: 0.0, // سيُعاد حسابه
      newBalanceAfterTransaction: 0.0, // سيُعاد حسابه
      transactionNote: (data['transactionNote'] ?? '') + ' (تمت الاستعادة 🩹)',
      transactionType: data['transactionType'] ?? 'restored',
      description: data['description'],
      createdAt: data['createdAt'] is String 
          ? DateTime.parse(data['createdAt']) 
          : (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      audioNotePath: data['audioNotePath'],
      isCreatedByMe: false, // ليست من إنشائي
      isUploaded: true, // موجودة بالفعل
      transactionUuid: transactionUuid,
    );

    await dbService.insertTransaction(tx);
    // ملاحظة: insertTransaction في DatabaseService تقوم بإعادة حساب الأرصدة
  }

}
