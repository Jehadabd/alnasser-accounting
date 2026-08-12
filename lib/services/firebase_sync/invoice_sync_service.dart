// lib/services/firebase_sync/invoice_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'firebase_sync_config.dart';
import 'invoice_sync_coordinator.dart';
import '../database_service.dart';

/// مزامنة الفواتير عبر Firestore.
///
/// المبدأ: الفاتورة يملكها الجهاز الذي أنشأها. هو وحده يعدّلها ويرفعها، وبقية
/// الأجهزة تستقبلها للقراءة فقط. الهوية هي [invoice_uuid] حصراً، ووصول نفس
/// المعرّف مرتين لا يُنتج نسخة ثانية.
class InvoiceSyncService {
  static final InvoiceSyncService _instance = InvoiceSyncService._internal();
  factory InvoiceSyncService() => _instance;
  InvoiceSyncService._internal();

  // 🛡️ Lazy Init لمنع استدعاء FirebaseFirestore.instance قبل Firebase.initializeApp()
  FirebaseFirestore? _firestoreInstance;
  FirebaseFirestore get _firestore {
    _firestoreInstance ??= FirebaseFirestore.instance;
    return _firestoreInstance!;
  }

  final DatabaseService _db = DatabaseService();
  final InvoiceSyncCoordinator _coordinator = InvoiceSyncCoordinator();

  StreamSubscription? _invoicesListener;
  bool _isListening = false;
  Timer? _retryTimer;
  Timer? _orphanReprocessTimer; // 🔄 إعادة معالجة الفواتير المؤجّلة (بانتظار وصول العميل)

  /// الأعمدة التي يُسمح بكتابتها في جدول invoices محلياً.
  /// أي مفتاح آخر قادم من السحابة (مثل customer_id الخاص بجهاز المرسل، أو
  /// حقول أضافها إصدار أحدث) يُتجاهل بدل أن يُفشل عملية الإدراج بالكامل.
  /// ملاحظة: `serial_number` مستثنى عمداً — إنه UNIQUE محلياً، ونسخه من جهاز
  /// آخر يُفشل الإدراج. و`monthly_sequence_number` يبقى رقم عرض محلياً.
  static const _invoiceColumns = {
    'customer_name', 'customer_phone', 'customer_address', 'installer_name',
    'invoice_date', 'payment_type', 'total_amount', 'discount',
    'amount_paid_on_invoice', 'loading_fee', 'created_at', 'last_modified_at',
    'status', 'return_amount', 'points_rate', 'notes', 'final_total',
    'invoice_uuid', 'creator_device_id', 'version',
    'invoice_number', // ✅ رقم الفاتورة التجاري (Natural Key)
    'monthly_sequence_number',
    'invoice_year', 'invoice_month', // أعمدة السنة/الشهر للقيد الفريد المركّب
  };

  /// `product_id` مستثنى: رقم منتج محلي على جهاز المرسل قد يشير لمنتج مختلف
  /// عندنا. اسم المنتج كافٍ للعرض للقراءة فقط.
  static const _itemColumns = {
    'product_name', 'unit', 'unit_price', 'cost_price', 'actual_cost_price',
    'quantity_individual', 'quantity_large_unit', 'applied_price', 'item_total',
    'sale_type', 'units_in_large_unit', 'unique_id',
  };

  /// 🚀 بدء مزامنة الفواتير: رفع المعلّق، ثم الاستماع الدائم للوارد.
  Future<void> startSync() async {
    if (!await FirebaseSyncConfig.isEnabled()) {
      print('🧾 مزامنة الفواتير: المزامنة معطّلة (isEnabled=false)، تخطّي startSync');
      return;
    }

    print('🧾 بدء محرك مزامنة الفواتير...');

    // 🔄 تهيئة جدول الفواتير المؤجّلة (الأيتام) — لا نفشل كلياً إن تعذّر إنشاؤه.
    try {
      await _createInvoiceOrphanTable();
    } catch (e) {
      print('⚠️ تعذّر إنشاء جدول الفواتير المؤجّلة (متابعة بدونها): $e');
    }

    try {
      await syncPendingInvoices();
    } catch (e) {
      print('⚠️ تعذّر رفع الفواتير المعلقة أولية: $e');
    }

    // 🔒 الاستماع هو الأهم: يجب أن يبدأ حتى لو فشل رفع المعلّق.
    if (!_isListening) {
      try {
        await _startListening();
      } catch (e) {
        print('❌ فشل بدء الاستماع للفواتير: $e');
      }
    }

    // إعادة محاولة دورية لأي فاتورة لم تُرفع (انقطاع شبكة أثناء الحفظ مثلاً).
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => syncPendingInvoices(),
    );

    // 🔄 إعادة معالجة الفواتير المؤجّلة كل دقيقة: فاتورة وصلت قبل عميلها
    // تُحفظ مؤقتاً في sync_invoice_orphans، وهنا نحاول ربطها متى وصل العميل.
    _orphanReprocessTimer?.cancel();
    _orphanReprocessTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _reprocessOrphanInvoices(),
    );
  }

  /// 🛑 إيقاف المزامنة
  Future<void> stopSync() async {
    await _invoicesListener?.cancel();
    _retryTimer?.cancel();
    _orphanReprocessTimer?.cancel();
    _isListening = false;
    print('🛑 تم إيقاف محرك مزامنة الفواتير');
  }

  /// 📤 رفع الفواتير غير المرفوعة.
  ///
  /// تُرجع عدد الفواتير التي وصلت فعلاً. كل فاتورة تُرفع وتُؤشَّر على حدة، فلا
  /// يؤدي فشل واحدة إلى إسقاط البقية ولا إلى تأشير فواتير لم تصل.
  Future<int> syncPendingInvoices() async {
    if (!await FirebaseSyncConfig.isEnabled()) return 0;

    final pending = await _coordinator.getPendingInvoices();
    if (pending.isEmpty) return 0;

    print('📤 جاري رفع ${pending.length} فاتورة معلقة...');
    final collection = _firestore.collection('invoices');
    int uploaded = 0;

    for (final invMap in pending) {
      final uuid = invMap['invoice_uuid'] as String?;
      if (uuid == null || uuid.isEmpty) continue;

      try {
        final payload = Map<String, dynamic>.from(invMap);

        // ✅ نرفع invoice_number (رقم الفاتورة التجاري) صراحةً
        payload['invoice_number'] = invMap['invoice_number'];
        payload.remove('id');
        payload.remove('is_synced');

        // ربط الفاتورة بالعميل عبر معرّف المزامنة لا عبر الرقم المحلي.
        payload['customer_sync_uuid'] =
            await _customerSyncUuidFor(invMap['customer_id'] as int?);
        payload.remove('customer_id');

        final items = (invMap['items'] as List?) ?? const [];
        payload['items'] = items
            .map((it) => Map<String, dynamic>.from(it as Map)
              ..remove('id')
              ..remove('invoice_id'))
            .toList();

        payload['_uploaded_at'] = DateTime.now().toIso8601String();
        payload['uploadedAt'] = FieldValue.serverTimestamp(); // ⏰ للحذف التلقائي (TTL)

        await collection.doc(uuid).set(payload, SetOptions(merge: true));
        await _coordinator.markAsSynced(uuid);
        uploaded++;
      } catch (e) {
        // تبقى is_synced = 0 فتُعاد محاولتها تلقائياً في الدورة التالية.
        print('❌ فشل رفع الفاتورة $uuid: $e');
      }
    }

    print('✅ رُفعت $uploaded من ${pending.length} فاتورة');
    return uploaded;
  }

  Future<String?> _customerSyncUuidFor(int? customerId) async {
    if (customerId == null) return null;
    final db = await _db.database;
    final rows = await db.query('customers',
        columns: ['sync_uuid'], where: 'id = ?', whereArgs: [customerId], limit: 1);
    return rows.isEmpty ? null : rows.first['sync_uuid'] as String?;
  }

  /// 👂 الاستماع للفواتير القادمة من السحابة
  Future<void> _startListening() async {
    // استخراج آخر عملية مزامنة لجلب الجديد فقط (الاستماع الذكي)
    final db = await _db.database;
    final syncState = await db.query('sync_state', limit: 1);
    final lastSyncAt = syncState.isNotEmpty ? syncState.first['last_sync_at'] as String? : null;
    
    Query<Map<String, dynamic>> query = _firestore.collection('invoices');
    
    if (lastSyncAt != null) {
      print('🧠 تفعيل الاستماع الذكي للفواتير بدءاً من: $lastSyncAt');
      query = query.where('_uploaded_at', isGreaterThan: lastSyncAt);
    }
    
    _invoicesListener = query
        .snapshots()
        .listen((snapshot) async {
          final changes = snapshot.docChanges
              .where((c) =>
                  c.type == DocumentChangeType.added ||
                  c.type == DocumentChangeType.modified)
              .toList();
          if (changes.isNotEmpty) {
            print('🧾 استماع الفواتير: ${changes.length} تغيير وارد');
          }
          for (final change in changes) {
            final data = change.doc.data();
            if (data != null) {
              await _processIncomingInvoice(change.doc.id, data);
            }
          }
          
          // تحديث وقت آخر مزامنة بعد معالجة أي تغييرات (للاستماع الذكي)
          if (changes.isNotEmpty) {
            final db = await _db.database;
            final nowStr = DateTime.now().toIso8601String();
            final syncStateUpdate = await db.query('sync_state', limit: 1);
            if (syncStateUpdate.isNotEmpty) {
              await db.update('sync_state', {'last_sync_at': nowStr}, where: 'id = 1');
            } else {
              await db.insert('sync_state', {'id': 1, 'last_sync_at': nowStr});
            }
          }
        }, onError: (e) {
          print('❌ خطأ في استماع الفواتير: $e');
        });

    _isListening = true;
    print('👂 الاستماع لفواتير الأجهزة الأخرى فعّال');
  }

  /// 📥 معالجة فاتورة واردة
  Future<void> _processIncomingInvoice(String uuid, Map<String, dynamic> data) async {
    final myDeviceId = await FirebaseSyncConfig.getDeviceId();
    final creatorId = data['creator_device_id']?.toString() ?? 'unknown';

    // 🔍 تشخيص: تتبع وصول الفاتورة ومنع مقارنتها بمعرّف جهازي.
    print('🧾 فاتورة واردة: uuid=$uuid creator=$creatorId جهازي=$myDeviceId');

    // فاتورة من صنعي: نسختي المحلية هي المرجع.
    if (creatorId == myDeviceId) {
      print('⏭️ تخطّي فاتورة من صنع هذا الجهاز: $uuid');
      return;
    }

    final incomingVersion = (data['version'] as num?)?.toInt() ?? 1;
    final localVersion = await _coordinator.getLocalInvoiceVersion(uuid);
    final db = await _db.database;

    final existing = await db.query('invoices',
        columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [uuid], limit: 1);

    // 🔒 إدمبوتنت: نفس المعرّف بنفس النسخة (أو أقدم) لا يُطبَّق مرتين.
    if (existing.isNotEmpty && localVersion >= incomingVersion) {
      return;
    }

    final invoiceData = <String, dynamic>{};
    data.forEach((key, value) {
      if (_invoiceColumns.contains(key)) invoiceData[key] = value;
    });

    // 🛡️ تأمين القيم الافتراضية للحقول الإلزامية (NOT NULL) لتجنب أخطاء SQLite
    invoiceData['customer_name'] = invoiceData['customer_name'] ?? 'عميل مزامنة';
    invoiceData['invoice_date'] = invoiceData['invoice_date'] ?? DateTime.now().toIso8601String();
    invoiceData['payment_type'] = invoiceData['payment_type'] ?? 'نقد';
    invoiceData['total_amount'] = invoiceData['total_amount'] ?? 0.0;
    invoiceData['created_at'] = invoiceData['created_at'] ?? DateTime.now().toIso8601String();
    invoiceData['last_modified_at'] = invoiceData['last_modified_at'] ?? DateTime.now().toIso8601String();
    invoiceData['status'] = invoiceData['status'] ?? 'محفوظة';

    invoiceData['invoice_uuid'] = uuid;
    invoiceData['creator_device_id'] = creatorId;
    invoiceData['version'] = incomingVersion;
    // 1 = لا ترفعها ثانية؛ هذا الجهاز ليس مالكها.
    invoiceData['is_synced'] = 1;
    // 🔒 مملوكة لجهاز آخر ⇒ مقفلة للقراءة فقط على هذا الجهاز.
    invoiceData['is_locked'] = 1;
    invoiceData['is_created_by_me'] = 0; // 🔥 الفاتورة من جهاز آخر

    // 🔢 تأمين invoice_year/invoice_month إن لم يُرسلا (نشتقّهما من invoice_date)
    if (invoiceData['invoice_year'] == null || invoiceData['invoice_month'] == null) {
      try {
        final d = DateTime.parse(invoiceData['invoice_date'] as String);
        invoiceData['invoice_year'] = d.year;
        invoiceData['invoice_month'] = d.month;
      } catch (_) {
        // تعذّر تحليل التاريخ → القيم الافتراضية
      }
    }

    // ربط العميل عبر معرّف المزامنة، لا عبر الرقم المحلي للمرسل.
    final customerSyncUuid = data['customer_sync_uuid'] as String?;
    if (customerSyncUuid != null && customerSyncUuid.isNotEmpty) {
      final rows = await db.query('customers',
          columns: ['id'], where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
      if (rows.isEmpty) {
        // 👻 العميل لم يصل بعد: نحفظ الفاتورة في جدول الأيتام لإعادة
        // معالجتها تلقائياً عند وصول العميل، بدل أن تضيع نهائياً.
        await _addToInvoiceOrphans(uuid, data);
        return;
      }
      invoiceData['customer_id'] = rows.first['id'] as int;
    }

    final itemsList = (data['items'] as List<dynamic>?) ?? const [];

    try {
      await db.transaction((txn) async {
        // 🔒 إعادة الفحص داخل المعاملة: الفحص السابق تم خارجها، وقد تصل نفس
        // الوثيقة مرتين من مستمعَين متتاليين فتُدرج نسختان.
        final rows = await txn.query('invoices',
            columns: ['id', 'version'],
            where: 'invoice_uuid = ?', whereArgs: [uuid], limit: 1);

        int invoiceId;
        if (rows.isNotEmpty) {
          final currentVersion = (rows.first['version'] as num?)?.toInt() ?? 0;
          if (currentVersion >= incomingVersion) {
            print('🚫 رُفضت فاتورة واردة: النسخة المحلية أحدث أو مطابقة ($uuid)');
            return;
          }
          invoiceId = rows.first['id'] as int;
          await txn.update('invoices', invoiceData,
              where: 'invoice_uuid = ?', whereArgs: [uuid]);
          await txn.delete('invoice_items',
              where: 'invoice_id = ?', whereArgs: [invoiceId]);
        } else {
          // ✅ id يُولَّد تلقائياً (AUTOINCREMENT) - invoice_number محفوظ في invoiceData
          invoiceId = await txn.insert('invoices', invoiceData);
        }

        for (final item in itemsList) {
          final raw = Map<String, dynamic>.from(item as Map);
          final itemMap = <String, dynamic>{};
          raw.forEach((key, value) {
            if (_itemColumns.contains(key)) itemMap[key] = value;
          });
          
          // تأمين القيم الافتراضية للحقول الإلزامية (NOT NULL) في قاعدة البيانات
          itemMap['cost_price'] = itemMap['cost_price'] ?? 0.0;
          itemMap['quantity_large_unit'] = itemMap['quantity_large_unit'] ?? 0.0;
          itemMap['unit_price'] = itemMap['unit_price'] ?? 0.0;
          itemMap['quantity_individual'] = itemMap['quantity_individual'] ?? 0.0;
          itemMap['applied_price'] = itemMap['applied_price'] ?? 0.0;
          itemMap['item_total'] = itemMap['item_total'] ?? 0.0;
          itemMap['product_name'] = itemMap['product_name'] ?? 'منتج غير معروف';
          itemMap['unit'] = itemMap['unit'] ?? '';
          
          itemMap['invoice_id'] = invoiceId;
          await txn.insert('invoice_items', itemMap);
        }
      });

      print('📥 استُلمت فاتورة من جهاز $creatorId: $uuid (نسخة $incomingVersion)');
    } catch (e) {
      print('❌ فشل حفظ الفاتورة $uuid: $e');
    }
  }

  /// ⬇️ تنزيل جميع الفواتير من السحابة وتطبيقها محليًا (لزر مزامنة الطوارئ).
  ///
  /// تقرأ كل وثائق مجموعة `invoices` وتمرّر كل وثيقة عبر نفس مسار الاستقبال
  /// الإدمبوتنت `_processIncomingInvoice`، فالفواتير الخاصة بهذا الجهاز أو
  /// الأحدث نسخةً تُرفض تلقائيًا. هذا يضمن أن الجهاز يستوعب كل ما فاته.
  /// تُرجع عدد الوثائق التي حُاول تطبيقها.
  Future<int> downloadAllInvoices({
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      final snapshot = await _firestore.collection('invoices').get();
      final total = snapshot.docs.length;
      var processed = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // الفواتير لا تُحذف، نطبّق أي وثيقة موجودة.
        await _processIncomingInvoice(doc.id, data);
        processed++;
        if (total > 0 && onProgress != null) {
          final p = processed / total;
          onProgress(p, 'تنزيل الفواتير ($processed/$total)...');
        }
      }
      print('📥 downloadAllInvoices: عُولجت $processed فاتورة.');
      return processed;
    } catch (e) {
      print('❌ downloadAllInvoices فشلت: $e');
      return 0;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 👻 الفواتير المؤجّلة (Invoice Orphans)
  ///
  /// عندما تصل فاتورة من المزامنة قبل وصول عميلها، لا يمكن ربطها برقم عميل
  /// محلي صحيح. بدل رفضها نهائياً (كانت تضيع للأبد)، نحفظها في جدول مؤقت
  /// ونعيد معالجتها دورياً حتى يصل عميلها.
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> _createInvoiceOrphanTable() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_invoice_orphans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_uuid TEXT NOT NULL UNIQUE,
        data TEXT NOT NULL,
        customer_sync_uuid TEXT,
        received_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_invoice_orphans_customer
      ON sync_invoice_orphans(customer_sync_uuid)
    ''');
  }

  /// حفظ فاتورة مؤجّلة (عميلها لم يصل بعد).
  Future<void> _addToInvoiceOrphans(
      String uuid, Map<String, dynamic> data) async {
    final db = await _db.database;
    final customerSyncUuid = data['customer_sync_uuid'] as String?;

    // تحويل أي Timestamp إلى نص قبل jsonEncode لتجنب الأخطاء.
    final cleanData = _convertTimestampsToStrings(data);

    await db.insert(
      'sync_invoice_orphans',
      {
        'invoice_uuid': uuid,
        'data': jsonEncode(cleanData),
        'customer_sync_uuid': customerSyncUuid,
        'received_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('👻 فاتورة مؤجّلة بانتظار عميلها: $uuid (العميل: $customerSyncUuid)');
  }

  /// إعادة معالجة كل الفواتير المؤجّلة التي وصل عميلها أخيراً.
  Future<void> _reprocessOrphanInvoices() async {
    try {
      final db = await _db.database;
      final orphans = await db.query('sync_invoice_orphans', limit: 50);
      if (orphans.isEmpty) return;

      int resolved = 0;
      for (final orphan in orphans) {
        final uuid = orphan['invoice_uuid'] as String;
        final dataStr = orphan['data'] as String;
        final customerSyncUuid = orphan['customer_sync_uuid'] as String?;

        // إن لم يكن هناك عميل مرتبط أصلاً، لا يمكن الربط — نتركها.
        if (customerSyncUuid == null || customerSyncUuid.isEmpty) {
          // فاتورة بدون عميل: نحاول معالجتها مباشرة (قد تكون فاتورة نقدية
          // بدون حساب دين، فلا تحتاج عميلاً محلياً).
          try {
            final data = jsonDecode(dataStr) as Map<String, dynamic>;
            await _processIncomingInvoice(uuid, data);
            await db.delete('sync_invoice_orphans',
                where: 'invoice_uuid = ?', whereArgs: [uuid]);
            resolved++;
          } catch (_) {}
          continue;
        }

        // هل وصل العميل أخيراً؟
        final customerRows = await db.query('customers',
            columns: ['id'],
            where: 'sync_uuid = ?',
            whereArgs: [customerSyncUuid],
            limit: 1);
        if (customerRows.isNotEmpty) {
          try {
            final data = jsonDecode(dataStr) as Map<String, dynamic>;
            await _processIncomingInvoice(uuid, data);
            await db.delete('sync_invoice_orphans',
                where: 'invoice_uuid = ?', whereArgs: [uuid]);
            resolved++;
            print('✅ فاتورة مؤجّلة عُولجت بعد وصول عميلها: $uuid');
          } catch (e) {
            print('⚠️ فشلت إعادة معالجة الفاتورة المؤجّلة $uuid: $e');
          }
        }
      }
      if (resolved > 0) {
        print('👻 عُولجت $resolved فاتورة مؤجّلة هذا الدور');
      }
    } catch (e) {
      print('⚠️ خطأ في إعادة معالجة الفواتير المؤجّلة: $e');
    }
  }

  /// تحويل قيم Timestamp في خريطة إلى نصوص ISO8601 (لتجنب أخطاء jsonEncode).
  Map<String, dynamic> _convertTimestampsToStrings(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    data.forEach((key, value) {
      if (value is Timestamp) {
        result[key] = value.toDate().toIso8601String();
      } else if (value is Map) {
        result[key] =
            _convertTimestampsToStrings(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Timestamp) return item.toDate().toIso8601String();
          if (item is Map) {
            return _convertTimestampsToStrings(Map<String, dynamic>.from(item));
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }
}
