// lib/services/firebase_sync/invoice_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
// نخفي Transaction من sqflite لأن الملف يستخدم Transaction بمعنى Firestore
// (دالة db.transaction تستقبل DatabaseTransaction الذي هو نفسه Transaction هنا).
// لإزالة الالتباس نستخدم alias.
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:sqflite/sqflite.dart' as sqflite show Transaction;
import 'package:uuid/uuid.dart';
import 'firebase_sync_config.dart';
import 'invoice_sync_coordinator.dart';
import 'smart_pipe_cleanup_service.dart';
import 'sync_event_bus.dart';
import '../database_service.dart';
import '../../utils/inventory_helpers.dart';

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
    'invoice_date', 'payment_type', 'total_amount', 'total_amount_cents', 'discount', 'discount_cents',
    'amount_paid_on_invoice', 'amount_paid_cents', 'loading_fee', 'created_at', 'last_modified_at',
    'status', 'return_amount', 'points_rate', 'notes', 'final_total',
    'invoice_uuid', 'creator_device_id', 'version',
    'invoice_number', // ✅ رقم الفاتورة التجاري (Natural Key)
    'monthly_sequence_number',
    'invoice_year', 'invoice_month', // أعمدة السنة/الشهر للقيد الفريد المركّب
  };

  /// أعمدة المعاملات المسموح بكتابتها محلياً. أي حقل إضافي من السحابة
  /// (Timestamp، معرّفات المرسل، إلخ) يُتجاهل حتى لا يفشل الإدراج بالكامل.
  static const _txColumns = {
    'transaction_date', 'amount_changed', 'balance_before_transaction',
    'new_balance_after_transaction', 'transaction_note', 'transaction_type',
    'description', 'created_at', 'transaction_uuid', 'sync_uuid',
    'invoice_sync_uuid', 'audio_note_path', 'is_deleted',
  };

  /// `product_id` مستثنى: رقم منتج محلي على جهاز المرسل قد يشير لمنتج مختلف
  /// عندنا. بدلاً منه نستخدم `product_sync_uuid` لمطابقة المنتج عبر الأجهزة
  /// (مما يُمكّن خصم المخزون بشكل صحيح على الجهاز المستقبِل).
  static const _itemColumns = {
    'product_name', 'unit', 'unit_price', 'unit_price_cents', 'cost_price', 'cost_price_cents', 'actual_cost_price',
    'quantity_individual', 'quantity_large_unit', 'applied_price', 'applied_price_cents', 'item_total', 'item_total_cents',
    'sale_type', 'units_in_large_unit', 'unique_id',
    'product_sync_uuid', // 🔄 ربط ذري بالمنتج عبر sync_uuid (لخصم المخزون)
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

    try {
      await _repairCreditInvoicesMissingCustomers();
    } catch (e) {
      print('⚠️ تعذّر إصلاح فواتير الدين الناقصة: $e');
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
  ///
  /// 🔒 المزامنة الذرية: كل فاتورة تُرفع مع معاملاتها المالية المدمجة في
  ///    وثيقة واحدة (`payload['transactions']`)، بحيث يصل أثرها المالي على
  ///    العميل على الأجهزة الأخرى مع الفاتورة نفسها — لا حالة وسطية.
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
        final payload = await _buildInvoiceBundlePayload(invMap, collection);
        if (payload == null) continue;

        // 🔒 رفع ذري: الفاتورة + معاملاتها + items في وثيقة واحدة
        await collection.doc(uuid).set(payload, SetOptions(merge: true));

        await _coordinator.markAsSynced(uuid);
        // تأشير معاملات الفاتورة كمرفوعة أيضاً (لمنع إعادة رفعها مستقلة)
        await _markInvoiceTransactionsAsSynced(invMap);
        uploaded++;
      } catch (e) {
        // تبقى is_synced = 0 فتُعاد محاولتها تلقائياً في الدورة التالية.
        print('❌ فشل رفع الفاتورة $uuid: $e');
      }
    }

    print('✅ رُفعت $uploaded من ${pending.length} فاتورة');
    return uploaded;
  }

  /// 🚀 رفع فوري لحزمة فاتورة واحدة بعد حفظها مباشرة.
  ///
  /// يستهدف تقليل زمن الوصول (latency) إلى ثوانٍ بدل انتظار المؤقت الدوري.
  /// آمنة للاستدعاء المتزامن: تتجاهل الفاتورة إن كانت مرفوعة بالفعل.
  /// عند الفشل تبقى is_synced = 0 فيلتقطها المؤقت الدوري لاحقاً (ضمان عدم الفقدان).
  Future<bool> syncInvoiceBundleNow(String invoiceUuid) async {
    if (!await FirebaseSyncConfig.isEnabled()) return false;
    if (invoiceUuid.isEmpty) return false;

    try {
      final fullInvoice = await _coordinator.getFullInvoiceByUuid(invoiceUuid);
      if (fullInvoice == null) {
        print('⚠️ الفاتورة $invoiceUuid غير موجودة محلياً للرفع');
        return false;
      }
      // تخطّي إن كانت مرفوعة بالفعل
      if ((fullInvoice['is_synced'] as int?) == 1) return true;

      final collection = _firestore.collection('invoices');
      final payload = await _buildInvoiceBundlePayload(fullInvoice, collection);
      if (payload == null) return false;

      await collection.doc(invoiceUuid).set(payload, SetOptions(merge: true));
      await _coordinator.markAsSynced(invoiceUuid);
      await _markInvoiceTransactionsAsSynced(fullInvoice);

      print('⚡ رفع فوري ناجح لحزمة الفاتورة $invoiceUuid');
      return true;
    } catch (e) {
      print('❌ فشل الرفع الفوري للفاتورة $invoiceUuid: $e');
      return false;
    }
  }

  /// يبني حمولة (payload) وثيقة الفاتورة الكاملة المدمجة مع items و transactions.
  /// يُرجع null لو فشل جلب معرّف العميل للمزامنة (فاتورة بدون عميل معروف).
  Future<Map<String, dynamic>?> _buildInvoiceBundlePayload(
    Map<String, dynamic> invMap,
    CollectionReference collection,
  ) async {
    final uuid = invMap['invoice_uuid'] as String?;
    if (uuid == null || uuid.isEmpty) return null;

    final payload = Map<String, dynamic>.from(invMap);

    // ✅ نرفع invoice_number (رقم الفاتورة التجاري) صراحةً
    payload['invoice_number'] = invMap['invoice_number'];
    payload.remove('id');
    payload.remove('is_synced');

    // ربط الفاتورة بالعميل عبر معرّف المزامنة لا عبر الرقم المحلي.
    // إن لم يكن للعميل sync_uuid نولّده ونحفظه حتى لا تصل الفاتورة بلا هوية عميل.
    payload['customer_sync_uuid'] =
        await _customerSyncUuidFor(invMap['customer_id'] as int?);
    payload.remove('customer_id');

    // لقطة العميل داخل الحزمة: الجهاز المستقبِل ينشئ سجل الديون حتى لو
    // وثيقة العميل المستقلة لم تصل بعد (أو كانت من إصدار قديم بلا UUID).
    final embeddedCustomer = invMap['customer'];
    if (embeddedCustomer is Map) {
      final customerSnap = Map<String, dynamic>.from(embeddedCustomer);
      customerSnap.remove('id');
      customerSnap.remove('current_total_debt');
      if ((customerSnap['sync_uuid'] as String?) == null ||
          (customerSnap['sync_uuid'] as String).isEmpty) {
        customerSnap['sync_uuid'] = payload['customer_sync_uuid'];
      }
      payload['customer'] = customerSnap;
    }

    // items مدمجة
    final items = (invMap['items'] as List?) ?? const [];
    payload['items'] = items
        .map((it) => Map<String, dynamic>.from(it as Map)
          ..remove('id')
          ..remove('invoice_id'))
        .toList();

    // 🔒 معاملات الفاتورة المالية مدمجة (مزامنة ذرية)
    final transactions = (invMap['transactions'] as List?) ?? const [];
    payload['transactions'] = transactions
        .map((tx) {
          final txMap = Map<String, dynamic>.from(tx as Map);
          // إزالة المعرّفات المحلية قبل الرفع
          txMap.remove('id');
          txMap.remove('invoice_id');
          txMap.remove('customer_id');
          txMap.remove('is_uploaded');
          txMap.remove('is_read_by_others');
          // ضمان وجود sync_uuid حتى تلتقطها المطابقة الحية لاحقاً
          final txUuid = (txMap['transaction_uuid'] as String?) ??
              (txMap['sync_uuid'] as String?);
          if (txUuid != null && txUuid.isNotEmpty) {
            txMap['transaction_uuid'] = txUuid;
            txMap['sync_uuid'] = txUuid;
          }
          return txMap;
        })
        .toList();

    payload['_uploaded_at'] = DateTime.now().toIso8601String();
    payload['uploadedAt'] = FieldValue.serverTimestamp(); // ⏰ للحذف التلقائي (TTL)

    return payload;
  }

  /// يؤشّر معاملات الفاتورة كمرفوعة بعد نجاح رفع الحزمة المدمجة.
  Future<void> _markInvoiceTransactionsAsSynced(Map<String, dynamic> invMap) async {
    final transactions = (invMap['transactions'] as List?) ?? const [];
    for (final tx in transactions) {
      final txUuid = (tx as Map)['transaction_uuid'] as String?;
      if (txUuid != null && txUuid.isNotEmpty) {
        try {
          await _coordinator.markTransactionAsSynced(txUuid);
        } catch (_) {}
      }
    }
  }

  Future<String?> _customerSyncUuidFor(int? customerId) async {
    if (customerId == null || customerId == 0) return null;
    final db = await _db.database;
    final rows = await db.query('customers',
        columns: ['sync_uuid'], where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (rows.isEmpty) return null;
    var uuid = rows.first['sync_uuid'] as String?;
    // عميل قديم بلا معرّف مزامنة: نولّده الآن وإلا تصل الفاتورة للجهاز الآخر بلا عميل.
    if (uuid == null || uuid.isEmpty) {
      uuid = const Uuid().v4();
      await db.update('customers', {'sync_uuid': uuid},
          where: 'id = ?', whereArgs: [customerId]);
    }
    return uuid;
  }

  /// 👂 الاستماع للفواتير القادمة من السحابة
  Future<void> _startListening() async {
    // 🔒 استماع شامل بدون فلتر زمني:
    // الفلتر الزمني السابق كان يعتمد على `_uploaded_at` (وقت جهاز المُرسِل)،
    // ما يسبب فقدان الفواتير عند اختلاف ساعات الأجهزة. عوضاً عن ذلك، نعتمد
    // كلياً على الإدمبوتنت: كل وثيقة تُفلتر عبر (invoice_uuid + version) داخل
    // _processIncomingInvoice، فالوثائق المكررة/القديمة تُرفض محلياً بلا أثر.
    // هذا يضمن عدم ضياع أي فاتورة مهما كان فرق التوقيت بين الأجهزة.
    Query<Map<String, dynamic>> query = _firestore.collection('invoices');

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
        }, onError: (e) {
          print('❌ خطأ في استماع الفواتير: $e');
        });

    _isListening = true;
    print('👂 الاستماع الشامل لفواتير الأجهزة الأخرى فعّال (إدمبوتنت بلا فلتر زمني)');
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

    // ربط العميل: عبر معرّف المزامنة، أو لقطة العميل المدمجة، أو الاسم.
    // فاتورة الدين يجب أن تُنشئ سجل العميل حتى لو وصل المستند من إصدار قديم
    // بلا customer_sync_uuid وبلا مصفوفة transactions.
    Map<String, dynamic>? embeddedCustomer;
    final rawCustomer = data['customer'];
    if (rawCustomer is Map) {
      embeddedCustomer = Map<String, dynamic>.from(rawCustomer);
    }
    var customerSyncUuid = data['customer_sync_uuid'] as String?;
    if (customerSyncUuid == null || customerSyncUuid.isEmpty) {
      customerSyncUuid = embeddedCustomer?['sync_uuid'] as String?;
    }

    final isCreditInvoice = (invoiceData['payment_type'] as String?) == 'دين';
    int? resolvedCustomerId;
    if (isCreditInvoice ||
        (customerSyncUuid != null && customerSyncUuid.isNotEmpty) ||
        embeddedCustomer != null) {
      resolvedCustomerId = await _resolveOrCreateLocalCustomer(
        db: db,
        customerSyncUuid: customerSyncUuid,
        customerName: invoiceData['customer_name'] as String?,
        customerPhone: invoiceData['customer_phone'] as String?,
        customerAddress: invoiceData['customer_address'] as String?,
        embedded: embeddedCustomer,
      );
    }
    invoiceData['customer_id'] = resolvedCustomerId;

    final itemsList = (data['items'] as List<dynamic>?) ?? const [];
    // 🔒 معاملات الفاتورة المالية المدمجة (مزامنة ذرية)
    final transactionsList = (data['transactions'] as List<dynamic>?) ?? const [];
    final localCustomerId = resolvedCustomerId;

    try {
      await db.transaction((txn) async {
        // 🔒 إعادة الفحص داخل المعاملة: الفحص السابق تم خارجها، وقد تصل نفس
        // الوثيقة مرتين من مستمعَين متتاليين فتُدرج نسختان.
        final rows = await txn.query('invoices',
            columns: ['id', 'version'],
            where: 'invoice_uuid = ?', whereArgs: [uuid], limit: 1);

        int invoiceId;
        final bool isUpdate;
        // 🛡️ تأمين حقول السنتات للفاتورة
        final totalAmount = (invoiceData['total_amount'] as num?)?.toDouble() ?? 0.0;
        invoiceData['total_amount_cents'] = (totalAmount * 100).round();
        final discount = (invoiceData['discount'] as num?)?.toDouble() ?? 0.0;
        invoiceData['discount_cents'] = (discount * 100).round();
        final paid = (invoiceData['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
        invoiceData['amount_paid_cents'] = (paid * 100).round();

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
          isUpdate = true;
        } else {
          // ✅ id يُولَّد تلقائياً (AUTOINCREMENT) - invoice_number محفوظ في invoiceData
          invoiceId = await txn.insert('invoices', invoiceData);
          isUpdate = false;
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

          // 🛡️ تأمين حقول السنتات للأصناف الواردة
          final uPrice = (itemMap['unit_price'] as num?)?.toDouble() ?? 0.0;
          itemMap['unit_price_cents'] = (uPrice * 100).round();
          final appPrice = (itemMap['applied_price'] as num?)?.toDouble() ?? 0.0;
          itemMap['applied_price_cents'] = (appPrice * 100).round();
          final iTotal = (itemMap['item_total'] as num?)?.toDouble() ?? 0.0;
          itemMap['item_total_cents'] = (iTotal * 100).round();
          final cPrice = (itemMap['cost_price'] as num?)?.toDouble() ?? 0.0;
          itemMap['cost_price_cents'] = (cPrice * 100).round();

          itemMap['invoice_id'] = invoiceId;
          await txn.insert('invoice_items', itemMap);

          // 🔄 خصم المخزون عند استقبال فاتورة مستوردة (إدراج جديد فقط).
          //    الفاتورة المُنشئة محلياً خُصمت بالفعل عند البيع (في invoice_manager)،
          //    لذا لا نخصمها هنا. فقط المستوردة (is_created_by_me = 0) الجديدة.
          //    منع الخصم المزدوج: isUpdate=false يعني فاتورة جديدة كلياً محلياً.
          if (!isUpdate) {
            final productName = itemMap['product_name'] as String? ?? '';
            final productSyncUuid = itemMap['product_sync_uuid'] as String?;
            final saleType = itemMap['sale_type'] as String? ?? '';
            final double saleUnitsCount =
                (itemMap['quantity_large_unit'] as num?)?.toDouble() != null &&
                        (itemMap['quantity_large_unit'] as num).toDouble() > 0
                    ? (itemMap['quantity_large_unit'] as num).toDouble()
                    : (itemMap['quantity_individual'] as num?)?.toDouble() ?? 0.0;
            if (productName.isNotEmpty && saleUnitsCount > 0.0001) {
              try {
                await InventoryHelpers.adjustProductStock(
                  txn,
                  productName,
                  saleType,
                  saleUnitsCount,
                  productSyncUuid: productSyncUuid,
                  isAddition: false, // خصم
                );
              } catch (stockErr) {
                print('⚠️ تعذّر خصم مخزون المنتج "$productName": $stockErr');
              }
            }
          }
        }

        // 🔒 معالجة المعاملات المالية المدمجة (مزامنة ذرية)
        //    تُحفظ بنفس الـ invoice_id المحلي و invoice_sync_uuid = uuid الفاتورة.
        //    عند التحديث: نحذف المعاملات القديمة المرتبطة بالفاتورة ثم نُدرج الجديدة
        //    لضمان الاتساق الكامل مع نسخة المرسل.
        if (isUpdate) {
          await txn.delete('transactions',
              where: 'invoice_sync_uuid = ?', whereArgs: [uuid]);
        }
        for (final txRaw in transactionsList) {
          if (txRaw is! Map) continue;
          final raw = Map<String, dynamic>.from(txRaw);
          final txMap = <String, dynamic>{};
          raw.forEach((key, value) {
            if (_txColumns.contains(key)) {
              txMap[key] = _sqliteValue(value);
            }
          });
          if (localCustomerId != null) {
            txMap['customer_id'] = localCustomerId;
          } else {
            // معاملة بلا عميل محلي لا يمكن إدراجها (customer_id NOT NULL)
            print('⚠️ تخطّي معاملة فاتورة $uuid: لا يوجد عميل محلي');
            continue;
          }
          txMap['invoice_id'] = invoiceId;
          txMap['invoice_sync_uuid'] = uuid;
          txMap['is_created_by_me'] = 0;
          txMap['is_uploaded'] = 1;
          txMap['created_at'] = txMap['created_at'] ?? DateTime.now().toIso8601String();
          txMap['transaction_date'] =
              txMap['transaction_date'] ?? txMap['created_at'];
          txMap['amount_changed'] = txMap['amount_changed'] ?? 0.0;
          txMap['transaction_type'] = txMap['transaction_type'] ?? 'invoice_debt';
          final txUuid = (txMap['transaction_uuid'] as String?) ??
              (txMap['sync_uuid'] as String?);
          if (txUuid != null && txUuid.isNotEmpty) {
            txMap['transaction_uuid'] = txUuid;
            txMap['sync_uuid'] = txUuid;
          }

          if (txUuid != null && txUuid.isNotEmpty) {
            final existingTx = await txn.query('transactions',
                columns: ['id'],
                where: 'transaction_uuid = ? OR sync_uuid = ?',
                whereArgs: [txUuid, txUuid],
                limit: 1);
            if (existingTx.isNotEmpty) {
              await txn.update('transactions', txMap,
                  where: 'id = ?', whereArgs: [existingTx.first['id']]);
              continue;
            }
          }
          await txn.insert('transactions', txMap,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // إن وصلت فاتورة دين بلا معاملات (إصدار قديم أو رفع ناقص)، نُنشئ
        // أثر الدين محلياً حتى يظهر العميل في سجل الديون فوراً.
        if (localCustomerId != null && localCustomerId != 0) {
          await _ensureCreditTransaction(
            txn: txn,
            invoiceId: invoiceId,
            invoiceUuid: uuid,
            customerId: localCustomerId,
            invoiceData: invoiceData,
          );
          await _recalculateCustomerBalanceInsideTxn(txn, localCustomerId);
        }
      });

      print('📥 استُلمت فاتورة من جهاز $creatorId: $uuid (نسخة $incomingVersion، '
          '${transactionsList.length} معاملة، عميل=${localCustomerId ?? "بدون"})');
      if (localCustomerId != null) {
        syncBus.success(
          SyncPhase.applyRemote,
          'فاتورة دين وصلت وأُنشئ/حُدّث سجل العميل',
          entityType: 'invoice',
          entityUuid: uuid,
        );
      }

      // 🧾 إرسال ACK قراءة الفاتورة — لا تُحذف من السحابة إلا به
      // (SmartPipeCleanupService يفحص invoice_read_acks قبل أي حذف)
      try {
        await SmartPipeCleanupService().markInvoiceRead(
          groupId: 'default_sync_group',
          invoiceUuid: uuid,
          deviceId: myDeviceId,
          groupSecret: data['groupSecret'] as String? ?? '',
        );
      } catch (_) {
        // ACK غير حرج للاستلام — يُعاد عند وصول نسخة أحدث
      }
    } catch (e) {
      print('❌ فشل حفظ الفاتورة $uuid: $e');
    }
  }

  /// 🔁 إعادة حساب رصيد العميل من مجموع معاملاته (شباك أمان محاسبي).
  /// يستخدم داخل transaction نشطة لضمان الاتساق.
  Future<void> _recalculateCustomerBalanceInsideTxn(
      sqflite.Transaction txn, int customerId) async {
    try {
      final result = await txn.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
      ''', [customerId]);
      final total = (result.first['total'] as num?)?.toDouble() ?? 0.0;
      await txn.update('customers',
          {'current_total_debt': total, 'last_modified_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [customerId]);
    } catch (e) {
      print('⚠️ تعذّر إعادة حساب رصيد العميل $customerId: $e');
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

  /// إصلاح فواتير الدين التي وصلت سابقاً بلا عميل أو بلا معاملة
  /// (إصدارات قديمة كانت ترفع الفاتورة فقط).
  Future<void> _repairCreditInvoicesMissingCustomers() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT * FROM invoices
      WHERE payment_type = 'دين'
        AND (is_deleted IS NULL OR is_deleted = 0)
        AND (is_created_by_me IS NULL OR is_created_by_me = 0)
    ''');
    if (rows.isEmpty) return;

    var repaired = 0;
    for (final row in rows) {
      final invoiceId = row['id'] as int;
      final uuid = row['invoice_uuid'] as String?;
      var customerId = row['customer_id'] as int?;

      if (customerId == null || customerId == 0) {
        customerId = await _resolveOrCreateLocalCustomer(
          db: db,
          customerName: row['customer_name'] as String?,
          customerPhone: row['customer_phone'] as String?,
          customerAddress: row['customer_address'] as String?,
        );
        if (customerId != null) {
          await db.update('invoices', {'customer_id': customerId},
              where: 'id = ?', whereArgs: [invoiceId]);
        }
      }
      if (customerId == null || customerId == 0) continue;
      final cid = customerId;

      await db.transaction((txn) async {
        await _ensureCreditTransaction(
          txn: txn,
          invoiceId: invoiceId,
          invoiceUuid: uuid ?? 'inv_local_$invoiceId',
          customerId: cid,
          invoiceData: Map<String, dynamic>.from(row),
        );
        await _recalculateCustomerBalanceInsideTxn(txn, cid);
      });
      repaired++;
    }
    if (repaired > 0) {
      print('🔧 أُصلحت $repaired فاتورة دين واردة (عميل + معاملة)');
      syncBus.success(
        SyncPhase.applyRemote,
        'أُصلحت $repaired فاتورة دين واردة في سجل الديون',
        entityType: 'invoice',
      );
    }
  }

  /// تحويل قيم Firestore (Timestamp/bool) إلى أنواع يقبلها SQLite.
  dynamic _sqliteValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is bool) return value ? 1 : 0;
    return value;
  }

  /// إيجاد العميل محلياً أو إنشاؤه من بيانات الفاتورة حتى يظهر في سجل الديون.
  Future<int?> _resolveOrCreateLocalCustomer({
    required Database db,
    String? customerSyncUuid,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    Map<String, dynamic>? embedded,
  }) async {
    final name = (customerName ?? embedded?['name'] as String?)?.trim();
    final phone = (customerPhone ?? embedded?['phone'] as String?)?.trim();
    final address = customerAddress ?? embedded?['address'] as String?;
    var uuid = customerSyncUuid;
    if (uuid != null && uuid.isEmpty) uuid = null;
    uuid ??= (embedded?['sync_uuid'] as String?)?.trim();
    if (uuid != null && uuid.isEmpty) uuid = null;

    if (uuid != null) {
      final byUuid = await db.query('customers',
          columns: ['id'], where: 'sync_uuid = ?', whereArgs: [uuid], limit: 1);
      if (byUuid.isNotEmpty) return byUuid.first['id'] as int;
    }

    if (name != null && name.isNotEmpty) {
      final normalized = name.replaceAll(' ', '');
      List<Map<String, dynamic>> byName;
      if (phone != null && phone.isNotEmpty) {
        byName = await db.rawQuery(
          "SELECT id, sync_uuid FROM customers WHERE REPLACE(name, ' ', '') = ? "
          "AND (phone = ? OR phone IS NULL OR phone = '') LIMIT 1",
          [normalized, phone],
        );
      } else {
        byName = await db.rawQuery(
          "SELECT id, sync_uuid FROM customers WHERE REPLACE(name, ' ', '') = ? LIMIT 1",
          [normalized],
        );
      }
      if (byName.isNotEmpty) {
        final id = byName.first['id'] as int;
        final existingUuid = byName.first['sync_uuid'] as String?;
        if ((existingUuid == null || existingUuid.isEmpty) && uuid != null) {
          await db.update('customers', {'sync_uuid': uuid},
              where: 'id = ?', whereArgs: [id]);
        }
        return id;
      }
    }

    if (name == null || name.isEmpty) return null;

    uuid ??= const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    try {
      final newId = await db.insert('customers', {
        'name': name,
        'phone': (phone == null || phone.isEmpty) ? null : phone,
        'address': address,
        'current_total_debt': 0.0,
        'sync_uuid': uuid,
        'is_created_by_me': 0,
        'is_deleted': 0,
        'created_at': now,
        'last_modified_at': now,
        'synced_at': now,
      });
      print('👤 أُنشئ عميل من فاتورة واردة: $name (id=$newId)');
      return newId;
    } catch (e) {
      // UNIQUE(name, phone) — نستخدم السجل الموجود بدل تعليق الفاتورة.
      final fallback = await db.rawQuery(
        "SELECT id FROM customers WHERE REPLACE(name, ' ', '') = ? LIMIT 1",
        [name.replaceAll(' ', '')],
      );
      if (fallback.isNotEmpty) return fallback.first['id'] as int;
      print('⚠️ تعذّر إنشاء العميل من الفاتورة: $e');
      return null;
    }
  }

  /// إن وصلت فاتورة دين بلا معاملات مدمجة، نُنشئ معاملة الدين محلياً
  /// حتى يظهر العميل في سجل الديون (الذي يشترط وجود معاملة).
  Future<void> _ensureCreditTransaction({
    required sqflite.Transaction txn,
    required int invoiceId,
    required String invoiceUuid,
    required int customerId,
    required Map<String, dynamic> invoiceData,
  }) async {
    final paymentType = invoiceData['payment_type'] as String? ?? 'نقد';
    if (paymentType != 'دين') return;

    final total = (invoiceData['total_amount'] as num?)?.toDouble() ?? 0.0;
    final paid =
        (invoiceData['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
    final remaining = total - paid;
    if (remaining <= 0.001) return;

    final already = await txn.query(
      'transactions',
      columns: ['id'],
      where: '(invoice_sync_uuid = ? AND invoice_sync_uuid IS NOT NULL AND invoice_sync_uuid != "") OR (invoice_id = ? AND invoice_id IS NOT NULL)',
      whereArgs: [invoiceUuid, invoiceId],
      limit: 1,
    );
    if (already.isNotEmpty) return;

    // 🔍 حماية فائقة ضد التكرار: البحث عن معاملة وصلت عبر مزامنة المعاملات لنفس العميل والمبلغ ولم تُرطب بالفاتورة بعد
    final unlinkedMatch = await txn.query(
      'transactions',
      columns: ['id'],
      where: '''customer_id = ?
                AND ABS(amount_changed - ?) < 0.01
                AND (invoice_sync_uuid IS NULL OR invoice_sync_uuid = '')
                AND (is_deleted IS NULL OR is_deleted = 0)''',
      whereArgs: [customerId, remaining],
      limit: 1,
    );

    if (unlinkedMatch.isNotEmpty) {
      final matchId = unlinkedMatch.first['id'] as int;
      await txn.update(
        'transactions',
        {
          'invoice_id': invoiceId,
          'invoice_sync_uuid': invoiceUuid,
        },
        where: 'id = ?',
        whereArgs: [matchId],
      );
      print('🔗 [InvoiceSync] رُبطت المعاملة الواردة (id=$matchId) بالفاتورة $invoiceUuid بدلاً من مضاعفة الدين');
      return;
    }

    final custRows = await txn.query('customers',
        columns: ['current_total_debt'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1);
    final before = custRows.isEmpty
        ? 0.0
        : (custRows.first['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    final after = before + remaining;
    final now = DateTime.now().toIso8601String();
    final txUuid = 'tx_debt_${invoiceUuid.replaceAll('/', '_')}';
    final invoiceNumber = invoiceData['invoice_number'] as String?;

    await txn.insert('transactions', {
      'customer_id': customerId,
      'transaction_date': invoiceData['invoice_date'] ?? now,
      'amount_changed': remaining,
      'balance_before_transaction': before,
      'new_balance_after_transaction': after,
      'transaction_type': 'invoice_debt',
      'description': 'دين فاتورة ${invoiceNumber ?? invoiceUuid}',
      'invoice_id': invoiceId,
      'transaction_uuid': txUuid,
      'sync_uuid': txUuid,
      'invoice_sync_uuid': invoiceUuid,
      'is_created_by_me': 0,
      'is_uploaded': 1,
      'created_at': now,
    });
    print('💳 أُنشئت معاملة دين محلية لفاتورة واردة بلا معاملات: $invoiceUuid '
        '(المتبقي=$remaining)');
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
