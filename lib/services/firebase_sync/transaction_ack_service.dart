// lib/services/firebase_sync/transaction_ack_service.dart
// خدمة تأكيد استلام المعاملات (ACK System)
// لضمان وصول المعاملات للأجهزة الأخرى

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../database_service.dart';
import '../sync/sync_security.dart';

/// حالة تأكيد المعاملة
enum AckStatus {
  pending,    // في انتظار التأكيد
  received,   // تم الاستلام
  failed,     // فشل الاستلام
}

/// نموذج تأكيد استلام معاملة
class TransactionAck {
  final String transactionUuid;
  final String senderDeviceId;
  final String receiverDeviceId;
  final String receiverDeviceName;
  final DateTime receivedAt;
  final AckStatus status;
  final String? errorMessage;

  TransactionAck({
    required this.transactionUuid,
    required this.senderDeviceId,
    required this.receiverDeviceId,
    required this.receiverDeviceName,
    required this.receivedAt,
    required this.status,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
    'transactionUuid': transactionUuid,
    'senderDeviceId': senderDeviceId,
    'receiverDeviceId': receiverDeviceId,
    'receiverDeviceName': receiverDeviceName,
    'receivedAt': receivedAt.toIso8601String(),
    'status': status.name,
    'errorMessage': errorMessage,
  };

  factory TransactionAck.fromMap(Map<String, dynamic> map) {
    return TransactionAck(
      transactionUuid: map['transactionUuid'] ?? map['transactionSyncUuid'] as String,
      senderDeviceId: map['senderDeviceId'] as String,
      receiverDeviceId: map['receiverDeviceId'] as String,
      receiverDeviceName: map['receiverDeviceName'] as String? ?? 'جهاز غير معروف',
      receivedAt: DateTime.parse(map['receivedAt'] as String),
      status: AckStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => AckStatus.pending,
      ),
      errorMessage: map['errorMessage'] as String?,
    );
  }
}

/// خدمة تأكيد استلام المعاملات
class TransactionAckService {
  static TransactionAckService? _instance;
  static TransactionAckService get instance {
    _instance ??= TransactionAckService._();
    return _instance!;
  }

  TransactionAckService._();

  final DatabaseService _db = DatabaseService();
  FirebaseFirestore? _firestore;
  String? _deviceId;
  String? _groupId;
  String? _deviceName;
  bool _isInitialized = false;

  // Stream للإشعار عند استلام ACK
  final _ackReceivedController = StreamController<TransactionAck>.broadcast();
  Stream<TransactionAck> get onAckReceived => _ackReceivedController.stream;

  // الاستماع لتأكيدات الاستلام
  StreamSubscription? _ackListener;

  /// تهيئة الخدمة
  Future<void> initialize({
    required FirebaseFirestore firestore,
    required String deviceId,
    required String groupId,
    String? deviceName,
  }) async {
    _firestore = firestore;
    _deviceId = deviceId;
    _groupId = groupId;
    _deviceName = deviceName ?? 'جهاز غير مسمى';
    _isInitialized = true;

    // إنشاء جدول ACK المحلي
    await _createLocalAckTable();

    // بدء الاستماع لتأكيدات الاستلام
    _startListeningForAcks();

    print('✅ تم تهيئة TransactionAckService');
  }

  /// إيقاف الخدمة
  void dispose() {
    _ackListener?.cancel();
    _ackReceivedController.close();
    _isInitialized = false;
  }

  /// إنشاء جدول ACK المحلي
  Future<void> _createLocalAckTable() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_acks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_uuid TEXT NOT NULL,
        sender_device_id TEXT NOT NULL,
        receiver_device_id TEXT NOT NULL,
        receiver_device_name TEXT,
        received_at TEXT NOT NULL,
        status TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(transaction_uuid, receiver_device_id)
      )
    ''');
    
    // محاولة ترقية الجدول القديم إذا كان موجوداً
    try {
      final tableInfo = await db.rawQuery('PRAGMA table_info(transaction_acks)');
      final hasOldColumn = tableInfo.any((column) => column['name'] == 'transaction_sync_uuid');
      if (hasOldColumn) {
        await db.execute('ALTER TABLE transaction_acks RENAME COLUMN transaction_sync_uuid TO transaction_uuid');
      }
    } catch (e) {
      print('Error migrating transaction_acks table: $e');
    }

    // فهرس للبحث السريع
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_acks_transaction 
      ON transaction_acks(transaction_uuid)
    ''');
  }

  /// إرسال تأكيد استلام معاملة
  /// يُستدعى عند استقبال معاملة من جهاز آخر بنجاح
  Future<void> sendAck({
    required String transactionUuid,
    required String senderDeviceId,
    AckStatus status = AckStatus.received,
    String? errorMessage,
  }) async {
    if (!_isInitialized || _firestore == null || _groupId == null) return;

    // لا نرسل ACK لأنفسنا
    if (senderDeviceId == _deviceId) return;

    try {
      final now = DateTime.now().toUtc();
      // معرّف الـ ACK مبني على معرّف المعاملة، فأي فاصل مسار فيه ينتقل إليه
      final ackId = SyncSecurity.sanitizeDocumentId('${transactionUuid}_$_deviceId');

      await _firestore!
          .collection('transaction_acks')
          .doc(ackId)
          .set({
        'transactionUuid': transactionUuid,
        'senderDeviceId': senderDeviceId,
        'receiverDeviceId': _deviceId,
        'receiverDeviceName': _deviceName,
        'receivedAt': now.toIso8601String(),
        'status': status.name,
        'errorMessage': errorMessage,
        'createdAt': DateTime.now().toIso8601String(),
      });

      print('✅ تم قراءة البيانات في هذا الحاسوب بنجاح! (جاري إعلام المرسل...)');
      print('📤 تم إرسال تأكيد استلام (ACK) للمعاملة: $transactionUuid');
    } catch (e) {
      print('❌ فشل إرسال ACK: $e');
    }
  }

  // 🔧 تحديد عدد ACKs المستلمة لتجنب الإغراق
  int _receivedAcksCount = 0;
  static const int _maxAcksPerSession = 2000; // الحد الأقصى للرسائل في الجلسة
  bool _isFirstLoad = true; // 🆕 لتجاهل الرسائل القديمة عند التحميل الأول

  /// الاستماع لتأكيدات الاستلام للمعاملات المرسلة من هذا الجهاز
  void _startListeningForAcks() {
    if (_firestore == null || _groupId == null || _deviceId == null) return;

    // 🔧 إزالة orderBy لتجنب الحاجة لفهرس مركب في Firebase
    _ackListener = _firestore!
        .collection('transaction_acks')
        .where('senderDeviceId', isEqualTo: _deviceId)
        .limit(2000) // 🔧 تحديد عدد الرسائل
        .snapshots()
        .listen((snapshot) {
      // 🔧 تجاهل التحميل الأول (الرسائل القديمة)
      if (_isFirstLoad) {
        _isFirstLoad = false;
        print('📬 تم تحميل ${snapshot.docs.length} ACK قديم (تم تجاهلهم)');
        return;
      }
      
      for (final change in snapshot.docChanges) {
        // 🔧 معالجة الرسائل الجديدة فقط
        if (change.type == DocumentChangeType.added) {
          // 🔧 التحقق من الحد الأقصى
          if (_receivedAcksCount >= _maxAcksPerSession) {
            print('⚠️ تم تجاوز الحد الأقصى للـ ACKs في هذه الجلسة');
            continue;
          }
          
          final data = change.doc.data();
          if (data != null) {
            final ack = TransactionAck.fromMap(data);
            _saveAckLocally(ack);
            _ackReceivedController.add(ack);
            _receivedAcksCount++;
            // 🔧 طباعة مختصرة
            if (_receivedAcksCount <= 10) {
              print('📩 الحاسوب الآخر (${ack.receiverDeviceName}) قرأ البيانات بنجاح! ✅');
              print('   - المعاملة: ${ack.transactionUuid}');
            } else if (_receivedAcksCount == 6) {
              print('📬 ... وأكثر (تم إيقاف الطباعة)');
            }
          }
        }
      }
    });
  }

  /// حفظ ACK محلياً
  Future<void> _saveAckLocally(TransactionAck ack) async {
    final db = await _db.database;
    try {
      await db.insert('transaction_acks', {
        'transaction_uuid': ack.transactionUuid,
        'sender_device_id': ack.senderDeviceId,
        'receiver_device_id': ack.receiverDeviceId,
        'receiver_device_name': ack.receiverDeviceName,
        'received_at': ack.receivedAt.toIso8601String(),
        'status': ack.status.name,
        'error_message': ack.errorMessage,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // قد يكون موجوداً مسبقاً - تحديث
      await db.update(
        'transaction_acks',
        {
          'status': ack.status.name,
          'received_at': ack.receivedAt.toIso8601String(),
        },
        where: 'transaction_uuid = ? AND receiver_device_id = ?',
        whereArgs: [ack.transactionUuid, ack.receiverDeviceId],
      );
    }
  }

  /// جلب حالة تأكيد معاملة معينة
  Future<List<TransactionAck>> getAcksForTransaction(String transactionUuid) async {
    if (!_isInitialized || _firestore == null || _groupId == null) return [];

    try {
      final snapshot = await _firestore!
          .collection('transaction_acks')
          .where('transactionUuid', isEqualTo: transactionUuid)
          .get();

      return snapshot.docs
          .map((doc) => TransactionAck.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('❌ خطأ في جلب ACKs: $e');
      return [];
    }
  }

  /// جلب المعاملات التي لم يتم تأكيد استلامها
  Future<List<String>> getPendingAckTransactions() async {
    if (!_isInitialized || _firestore == null || _groupId == null) return [];

    try {
      // جلب جميع المعاملات المرسلة من هذا الجهاز
      final txSnapshot = await _firestore!
          .collection('transactions')
          .where('deviceId', isEqualTo: _deviceId)
          .get();

      // جلب جميع الأجهزة المتصلة
      final devicesSnapshot = await _firestore!
          .collection('devices')
          .where('isOnline', isEqualTo: true)
          .get();

      final otherDevices = devicesSnapshot.docs
          .where((d) => d.id != _deviceId)
          .map((d) => d.id)
          .toList();

      if (otherDevices.isEmpty) return [];

      final pendingTxIds = <String>[];

      for (final txDoc in txSnapshot.docs) {
        final txUuid = txDoc.id;

        // جلب ACKs لهذه المعاملة
        final acks = await getAcksForTransaction(txUuid);
        final ackedDevices = acks.map((a) => a.receiverDeviceId).toSet();

        // التحقق من أن جميع الأجهزة أكدت الاستلام
        final missingAcks = otherDevices.where((d) => !ackedDevices.contains(d)).toList();

        if (missingAcks.isNotEmpty) {
          pendingTxIds.add(txUuid);
        }
      }

      return pendingTxIds;
    } catch (e) {
      print('❌ خطأ في جلب المعاملات المعلقة: $e');
      return [];
    }
  }

  /// جلب ملخص حالة التأكيدات
  Future<Map<String, dynamic>> getAckSummary() async {
    if (!_isInitialized || _firestore == null || _groupId == null) {
      return {'error': 'غير مُعد'};
    }

    try {
      // عدد المعاملات المرسلة
      final sentTxCount = await _firestore!
          .collection('transactions')
          .where('deviceId', isEqualTo: _deviceId)
          .count()
          .get();

      // عدد التأكيدات المستلمة
      final acksCount = await _firestore!
          .collection('transaction_acks')
          .where('senderDeviceId', isEqualTo: _deviceId)
          .count()
          .get();

      // المعاملات المعلقة
      final pendingTx = await getPendingAckTransactions();

      return {
        'sentTransactions': sentTxCount.count ?? 0,
        'receivedAcks': acksCount.count ?? 0,
        'pendingAcks': pendingTx.length,
        'pendingTransactionIds': pendingTx,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// تنظيف التأكيدات القديمة (أكثر من 30 يوم)
  Future<int> cleanupOldAcks() async {
    if (!_isInitialized || _firestore == null || _groupId == null) return 0;

    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      final cutoffStr = cutoffDate.toIso8601String();

      // حذف من Firebase
      final oldAcks = await _firestore!
          .collection('transaction_acks')
          .where('receivedAt', isLessThan: cutoffStr)
          .get();

      int deletedCount = 0;
      for (final doc in oldAcks.docs) {
        await doc.reference.delete();
        deletedCount++;
      }

      // حذف من قاعدة البيانات المحلية
      final db = await _db.database;
      await db.delete(
        'transaction_acks',
        where: 'received_at < ?',
        whereArgs: [cutoffStr],
      );

      print('🧹 تم حذف $deletedCount تأكيد قديم');
      return deletedCount;
    } catch (e) {
      print('❌ خطأ في تنظيف التأكيدات: $e');
      return 0;
    }
  }
}
