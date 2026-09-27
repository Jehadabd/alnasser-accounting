// test/sync_harness/device.dart
// «جهاز وهمي»: خيط منفصل يشغّل كود التطبيق الحقيقي (DatabaseService،
// AppProvider، FirebaseSyncService…) بقاعدة SQLite حقيقية خاصة به، وإعدادات
// خاصة، ومنصات وهمية. ينفّذ أوامر الاختبار عبر نفس الدوال التي تستدعيها الشاشات.

// ignore_for_file: avoid_print, implementation_imports

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:alnaser/controllers/invoice_controller.dart';
import 'package:alnaser/models/customer.dart';
import 'package:alnaser/models/invoice.dart';
import 'package:alnaser/models/invoice_input_data.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/models/product.dart';
import 'package:alnaser/models/purchase_invoice.dart';
import 'package:alnaser/models/purchase_invoice_item.dart';
import 'package:alnaser/models/supplier.dart';
import 'package:alnaser/services/purchase_service.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/services/database/business/stock_ledger.dart';
import 'package:alnaser/models/transaction.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/firebase_sync/armored_reconciliation_service.dart';
import 'package:alnaser/services/firebase_sync/firebase_sync_helper.dart';
import 'package:alnaser/services/firebase_sync/smart_pipe_cleanup_service.dart';
import 'package:alnaser/services/firebase_sync/firebase_sync_service.dart';
import 'package:alnaser/services/firebase_sync/invoice_sync_service.dart';
import 'package:alnaser/services/firebase_sync/sync_health.dart';
import 'package:alnaser/services/firebase_sync/product_sync_service.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/src/mixin/factory.dart' show buildDatabaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/isolate.dart' show SqfliteIsolate;
import 'package:sqflite_common_ffi/src/method_call.dart' show FfiMethodCall;

import 'fake_platforms.dart';
import 'protocol.dart';
import 'remote_firestore.dart';

const _fileLog = bool.fromEnvironment('DEVLOG');

/// نقطة دخول خيط الجهاز.
void deviceMain(DeviceBoot boot) {
  final logs = <String>[];
  final errors = <String>[];
  runZonedGuarded(
    () => _run(boot, logs, errors),
    (e, st) {
      // أسطر كود التطبيق أولاً (package:alnaser): تدلّ على موضع الخطأ
      final lines = st.toString().split('\n');
      final app = lines.where((l) => l.contains('package:alnaser')).take(8).toList();
      errors.add('$e\n${(app.isNotEmpty ? app : lines.take(8)).join('\n')}');
    },
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      if (_fileLog) {
        try {
          File('${boot.dir}${Platform.pathSeparator}device.log')
              .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
        } catch (_) {}
      }
      logs.add(line);
      if (logs.length > 4000) logs.removeRange(0, 1000);
    }),
  );
}

Future<void> _run(DeviceBoot boot, List<String> logs, List<String> errors) async {
  Directory(boot.dir).createSync(recursive: true);

  // ── المنصات الوهمية ──
  // SQLite عبر خادم مشترك: مكتبة SQLite في بيئة اختبار ويندوز تُفسد اتصالات
  // خيط إذا استخدمها خيط آخر في الوقت نفسه. خادم واحد = خيط واحد يلمس SQLite.
  final sqliteServer = SqfliteIsolate(sendPort: boot.sqlite);
  databaseFactory = buildDatabaseFactory(
    tag: 'harness',
    invokeMethod: (String method, [Object? arguments]) =>
        sqliteServer.handle(FfiMethodCall(method, arguments)),
  );
  PathProviderPlatform.instance = FakePathProvider(boot.dir);
  SharedPreferences.setMockInitialValues(boot.prefs);
  FlutterSecureStorage.setMockInitialValues(Map<String, String>.from(boot.secure));
  FirebasePlatform.instance = FakeFirebaseCore();
  FirebaseAuthPlatform.instance = FakeAuth('uid-${boot.name}');
  final link = CloudLink(boot.name, boot.cloud);
  FirebaseFirestorePlatform.instance = RemoteFirestore(link);
  FieldValueFactoryPlatform.instance = RemoteFieldValueFactory();
  final connectivity = FakeConnectivity(boot.online);
  ConnectivityPlatform.instance = connectivity;

  final cmdPort = ReceivePort();
  boot.controller.send(cmdPort.sendPort);

  await for (final msg in cmdPort) {
    if (msg is! DeviceCommand) continue;
    try {
      final v = await _exec(msg, connectivity, logs, errors);
      boot.controller.send(DeviceReply(msg.id, v));
      if (msg.op == 'shutdown') {
        link.close();
        cmdPort.close();
        // يُجمِّد المتحكّم هذا الخيط (لا إغلاق للقاعدة ولا إنهاء قد يُسقط SQLite)
      }
    } catch (e, st) {
      boot.controller.send(DeviceReply(
          msg.id, null, '$e\n${st.toString().split('\n').take(10).join('\n')}'));
    }
  }
}

/// شاشات تعديل منتج مفتوحة (الكائن كما حُمّل لحظة الفتح).
final Map<String, Product> _openProductScreens = {};

Future<int?> _customerId(String uuid) async {
  final db = await DatabaseService().database;
  final r = await db.query('customers',
      columns: ['id'], where: 'sync_uuid = ?', whereArgs: [uuid], limit: 1);
  return r.isEmpty ? null : r.first['id'] as int;
}

Future<Map<String, Object?>?> _txRow(String uuid) async {
  final db = await DatabaseService().database;
  final r = await db.query('transactions',
      where: 'transaction_uuid = ?', whereArgs: [uuid], limit: 1);
  return r.isEmpty ? null : r.first;
}

Future<Object?> _exec(DeviceCommand c, FakeConnectivity connectivity, List<String> logs,
    List<String> errors) async {
  final a = c.args;
  switch (c.op) {
    case 'init':
      return await FirebaseSyncService().initialize();

    case 'addCustomer':
      final name = a['name'] as String;
      await AppProvider().addCustomer(Customer(name: name, phone: a['phone'] as String?));
      final db = await DatabaseService().database;
      final r = await db.query('customers',
          columns: ['sync_uuid'],
          where: 'name = ? AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
          whereArgs: [name],
          orderBy: 'id DESC',
          limit: 1);
      return r.isEmpty ? null : r.first['sync_uuid'];

    case 'addTx':
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) throw StateError('customer not on device');
      final amount = (a['amount'] as num).toDouble();
      final marker = a['marker'] as String;
      await AppProvider().addTransaction(DebtTransaction(
        customerId: cid,
        amountChanged: amount,
        transactionType: amount >= 0 ? 'manual_debt' : 'manual_payment',
        transactionNote: marker,
      ));
      final db = await DatabaseService().database;
      final r = await db.query('transactions',
          columns: ['transaction_uuid'],
          where: 'customer_id = ? AND transaction_note = ? AND is_created_by_me = 1',
          whereArgs: [cid, marker],
          orderBy: 'id DESC',
          limit: 1);
      return r.isEmpty ? null : r.first['transaction_uuid'];

    case 'editTx':
      final row = await _txRow(a['tx'] as String);
      if (row == null) throw StateError('tx not on device');
      final t = DebtTransaction.fromMap(row);
      final amount = (a['amount'] as num).toDouble();
      // شاشة العميل: db.updateTransaction(updated)
      try {
        await DatabaseService().updateTransaction(t.copyWith(amountChanged: amount));
      } on RestoredRecordLockedException {
        return {'locked': true}; // سجل مستعاد أثناء الاستعادة: رفضه التطبيق
      }
      return true;

    case 'convertTx':
      final row = await _txRow(a['tx'] as String);
      if (row == null) throw StateError('tx not on device');
      try {
        await DatabaseService().convertTransactionType(row['id'] as int);
      } on RestoredRecordLockedException {
        return {'locked': true};
      }
      // التحويل يقلب ما يراه المستخدم على هذا الجهاز (قد يكون قديماً إن كان
      // الجهاز يلحق بالمجموعة بعد استعادة نسخة): الحقيقة تأخذ الناتج الفعلي.
      final after = await _txRow(a['tx'] as String);
      return {
        'amount': (after?['amount_changed'] as num?)?.toDouble(),
        'type': after?['transaction_type'],
      };

    case 'deleteCustomer':
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) throw StateError('customer not on device');
      final db = await DatabaseService().database;
      // ما حذفه التطبيق فعلاً = المحذوف بعد الحذف ناقص المحذوف قبله. قائمة
      // «النشط قبل الحذف» كانت تفوّت معاملة وصلت بين الاستعلام والحذف —
      // والتطبيق يحذفها (كانت موجودة لحظة الحذف) فتختلف الحقيقة عنه.
      Future<Map<String, String?>> deleted() async {
        final r = await db.query('transactions',
            columns: ['transaction_uuid', 'invoice_sync_uuid'],
            where: 'customer_id = ? AND is_deleted = 1 AND transaction_uuid IS NOT NULL',
            whereArgs: [cid]);
        return {
          for (final x in r) x['transaction_uuid'] as String: x['invoice_sync_uuid'] as String?
        };
      }
      final before = await deleted();
      try {
        await AppProvider().deleteCustomer(cid);
      } on RestoredRecordLockedException {
        return {'locked': true, 'txs': <String>[], 'invs': <String>[]};
      }
      final after = await deleted();
      final newly = after.keys.where((u) => !before.containsKey(u)).toList();
      final invs = {
        for (final u in newly)
          if ((after[u] ?? '').isNotEmpty) after[u]!
      };
      return {'txs': newly, 'invs': invs.toList()};

    case 'addProduct':
      // شاشة إضافة منتج: DatabaseService.insertProduct (الكمية الأولى = رصيد افتتاحي)
      final carton = (a['carton'] as num?)?.toInt();
      final int id;
      try {
        id = await DatabaseService().insertProduct(Product(
        name: a['name'] as String,
        unit: 'piece',
        unitPrice: 1,
        price1: 1,
        costPrice: 0.5,
        stockQuantity: (a['stock'] as num).toDouble(),
        unitHierarchy: carton == null ? null : '[{"unit_name":"كرتون","quantity":$carton}]',
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ));
      } on DuplicateProductNameException {
        return null; // وصل صنف بالاسم نفسه لحظة الحفظ: رفضه التطبيق
      }
      final db = await DatabaseService().database;
      final r = await db.query('products', columns: ['sync_uuid'], where: 'id = ?', whereArgs: [id]);
      return r.first['sync_uuid'];

    case 'products':
      final db = await DatabaseService().database;
      final r = await db.query('products',
          columns: ['sync_uuid', 'name', 'stock_quantity', 'unit_hierarchy'],
          where: "sync_uuid IS NOT NULL AND sync_uuid != ''");
      return [
        for (final x in r)
          {
            'uuid': x['sync_uuid'],
            'name': x['name'],
            'stock': (x['stock_quantity'] as num?)?.toDouble() ?? 0.0,
            'carton': _carton(x['unit_hierarchy'] as String?),
          }
      ];

    case 'openProductScreen':
      // شاشة تعديل منتج تُفتح الآن وتبقى مفتوحة (الكائن يُحمَّل لحظة الفتح)
      final db = await DatabaseService().database;
      final pr = await db.query('products', where: 'sync_uuid = ?', whereArgs: [a['prod']], limit: 1);
      if (pr.isEmpty) throw StateError('product not on device');
      _openProductScreens[a['label'] as String] = Product.fromMap(pr.first);
      return true;

    case 'saveProductScreen':
      // حفظ الشاشة المفتوحة: DatabaseService.updateProduct بكائن لحظة الفتح
      final p = _openProductScreens.remove(a['label'] as String)!;
      final price = (a['price'] as num).toDouble();
      await DatabaseService().updateProduct(
          p.copyWith(price1: price, unitPrice: price, lastModifiedAt: DateTime.now()));
      return true;

    case 'avcoPurchase':
      // فاتورة شراء مؤكدة عبر PurchaseService بطريقة المتوسط المرجّح ← الكلفة الناتجة
      final settings = await SettingsManager.getAppSettings();
      await SettingsManager.saveAppSettings(settings.copyWith(costingMethod: 'avco'));
      final db = await DatabaseService().database;
      final pr = await db.query('products', where: 'sync_uuid = ?', whereArgs: [a['prod']], limit: 1);
      if (pr.isEmpty) throw StateError('product not on device');
      final ps = PurchaseService();
      final sid = await ps.addSupplier(
          Supplier(name: 'مورد ${DateTime.now().microsecondsSinceEpoch}',
              createdAt: DateTime.now(), updatedAt: DateTime.now()));
      final qty = (a['qty'] as num).toDouble();
      final price = (a['price'] as num).toDouble();
      await ps.savePurchaseInvoice(
          PurchaseInvoice(
              invoiceNumber: 'P${DateTime.now().microsecondsSinceEpoch}',
              supplierId: sid,
              totalAmount: qty * price,
              status: 'confirmed',
              date: DateTime.now()),
          [
            PurchaseInvoiceItem(
                productId: pr.first['id'] as int,
                unitName: 'قطعة',
                quantity: qty,
                unitPrice: price,
                totalPrice: qty * price),
          ]);
      final after = await db.query('products',
          columns: ['cost_price', 'stock_quantity'], where: 'id = ?', whereArgs: [pr.first['id']]);
      return {
        'cost': (after.first['cost_price'] as num).toDouble(),
        'stock': (after.first['stock_quantity'] as num).toDouble(),
      };

    case 'renameProduct':
      // شاشة تعديل المنتج: DatabaseService.updateProduct باسم جديد
      final db = await DatabaseService().database;
      final pr = await db.query('products', where: 'sync_uuid = ?', whereArgs: [a['prod']], limit: 1);
      if (pr.isEmpty) throw StateError('product not on device');
      try {
        await DatabaseService().updateProduct(Product.fromMap(pr.first)
            .copyWith(name: a['name'] as String, lastModifiedAt: DateTime.now()));
      } on DuplicateProductNameException {
        return {'refused': true};
      }
      return {'refused': false};

    case 'legacyDuplicate':
      // إصدار سابق سمح بصنفين بالاسم نفسه على جهاز واحد: صف ثانٍ مباشرة
      final db = await DatabaseService().database;
      await db.insert('products', {
        'name': a['name'],
        'name_norm': a['name'],
        'unit': 'piece',
        'unit_price': 1.0,
        'cost_price': 0.5,
        'price1': 1.0,
        'stock_quantity': 0.0,
        'created_at': DateTime.now().toIso8601String(),
        'last_modified_at': DateTime.now().toIso8601String(),
        'sync_uuid': 'prod_legacy_${DateTime.now().microsecondsSinceEpoch}',
      });
      return true;

    case 'checkLocalDuplicates':
      await ProductSyncService().checkLocalDuplicateNames();
      return true;

    case 'syncHealth':
      // تنبيهات الشريط في الشاشة الرئيسية
      await SyncHealth.load();
      return [
        for (final w in SyncHealth.warnings.value) {'id': w.id, 'title': w.title}
      ];

    case 'checkGroupHealth':
      await FirebaseSyncService().checkGroupHealth();
      return true;

    case 'setClockOffset':
      SyncHealth.debugClockOffset = Duration(minutes: (a['minutes'] as num).toInt());
      return true;

    case 'dismissHealth':
      await SyncHealth.dismiss(a['id'] as String);
      return true;

    case 'productAliases':
      final db = await DatabaseService().database;
      return await db.query('product_uuid_alias');

    case 'adjustStock':
      // نافذة «تعديل المخزون»: DatabaseService.adjustProductStock
      final db = await DatabaseService().database;
      final pr = await db.query('products',
          columns: ['id'], where: 'sync_uuid = ?', whereArgs: [a['prod']], limit: 1);
      if (pr.isEmpty) throw StateError('product not on device');
      await DatabaseService().adjustProductStock(
          productId: pr.first['id'] as int, quantityChange: (a['delta'] as num).toDouble());
      return true;

    case 'purchase':
      // الشراء يمرّ بنفس دالة الدفتر التي تستدعيها خدمة المشتريات
      final db = await DatabaseService().database;
      final pr = await db.query('products',
          columns: ['id'], where: 'sync_uuid = ?', whereArgs: [a['prod']], limit: 1);
      if (pr.isEmpty) throw StateError('product not on device');
      final u = await StockLedger.productSyncUuidForId(db, pr.first['id'] as int);
      await StockLedger.addMovement(db,
          productSyncUuid: u!, delta: (a['qty'] as num).toDouble(), kind: 'purchase');
      return true;

    case 'legacyStock':
      // محاكاة الإصدار القديم: لا دفتر حركات، والكمية رقم مطلق
      final db = await DatabaseService().database;
      await db.transaction((txn) async {
        await txn.delete('stock_movements');
        final stocks = (a['stocks'] as Map).cast<String, Object?>();
        for (final e in stocks.entries) {
          await txn.update('products', {'stock_quantity': (e.value as num).toDouble()},
              where: 'sync_uuid = ?', whereArgs: [e.key]);
        }
      });
      return true;

    case 'invoiceDetail':
      final db = await DatabaseService().database;
      final inv = await db.rawQuery('''
        SELECT i.*, c.sync_uuid AS cust_uuid FROM invoices i
        LEFT JOIN customers c ON c.id = i.customer_id WHERE i.invoice_uuid = ?''', [a['inv']]);
      if (inv.isEmpty) return null;
      final items = await db.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [inv.first['id']], orderBy: 'id');
      final txs = await db.rawQuery('''
        SELECT t.amount_changed AS amount, t.is_deleted AS del, t.transaction_type AS type,
               c.sync_uuid AS cust FROM transactions t
        LEFT JOIN customers c ON c.id = t.customer_id
        WHERE t.invoice_sync_uuid = ?''', [a['inv']]);
      return {'invoice': inv.first, 'items': items, 'txs': txs};

    case 'stockDetail':
      final db = await DatabaseService().database;
      final mv = await db.query('stock_movements',
          columns: ['movement_uuid', 'delta', 'kind', 'is_uploaded'],
          where: 'product_sync_uuid = ?', whereArgs: [a['prod']], orderBy: 'id');
      final items = await db.rawQuery('''
        SELECT i.invoice_uuid AS inv, i.status AS status, i.is_deleted AS del,
               ii.quantity_individual AS qi, ii.quantity_large_unit AS ql,
               ii.units_in_large_unit AS u
        FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
        WHERE ii.product_sync_uuid = ? ORDER BY ii.id''', [a['prod']]);
      final pr = await db.query('products',
          columns: ['stock_quantity'], where: 'sync_uuid = ?', whereArgs: [a['prod']]);
      return {
        'stock': pr.isEmpty ? null : pr.first['stock_quantity'],
        'movements': mv,
        'items': items,
      };

    case 'viewCustomer':
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) return false;
      await DatabaseService().getGroupedCustomerTransactions(cid);
      return true;

    case 'saveInvoice':
      // مسار شاشة الفاتورة: InvoiceController.saveInvoice ثم الرفع الفوري
      final db = await DatabaseService().database;
      final cr = await db.query('customers',
          where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      if (cr.isEmpty) throw StateError('customer not on device');
      final cust = cr.first;
      Invoice? existing;
      final invUuid = a['inv'] as String?;
      if (invUuid != null) {
        final ir = await db.query('invoices',
            where: 'invoice_uuid = ?', whereArgs: [invUuid], limit: 1);
        if (ir.isEmpty) throw StateError('invoice not on device');
        existing = Invoice.fromMap(ir.first);
      }
      final total = (a['total'] as num).toDouble();
      final ptype = a['ptype'] as String;
      final paid = (a['paid'] as num).toDouble();
      // 📦 بنود أصناف حقيقية (تخصم من المخزون) + بند اختبار يكمل المجموع
      final productItems = await _productItems(db, a['items'], existing?.id ?? 0);
      final productTotal = productItems.fold(0.0, (s, i) => s + i.itemTotal);
      final item = InvoiceItem(
        invoiceId: existing?.id ?? 0,
        productName: 'صنف اختبار',
        unit: 'قطعة',
        unitPrice: total - productTotal,
        quantityIndividual: 1,
        appliedPrice: total - productTotal,
        itemTotal: total - productTotal,
        saleType: 'قطعة',
      );
      final controller = InvoiceController(db: DatabaseService());
      final data = InvoiceInputData(
        invoiceToManage: existing,
        customerName: cust['name'] as String,
        customerPhone: (cust['phone'] as String?) ?? '',
        customerAddress: (cust['address'] as String?) ?? '',
        paidAmount: paid,
        loadingFee: (a['loadingFee'] as num?)?.toDouble() ?? 0,
        discount: (a['discount'] as num?)?.toDouble() ?? 0,
        paymentType: ptype,
        selectedDate: DateTime.now(),
        invoiceItems: [
          if ((total - productTotal).abs() > 1e-9 || productItems.isEmpty) item,
          ...productItems,
        ],
      );
      final v = controller.validateInvoiceData(data);
      if (!v.isValid) return {'ok': false, 'err': v.errorMessage};
      final dv = await controller.validateDebtChangeWontCauseNegativeBalance(data);
      if (!dv.isValid) return {'ok': false, 'err': dv.errorMessage};
      final res = await controller.saveInvoice(data);
      if (!res.success || res.invoice == null) return {'ok': false, 'err': res.errorMessage};
      final saved = res.invoice!;
      // بعد الحفظ (invoice_actions): رفع الحزمة ثم وثيقة العميل — دون انتظار
      unawaited(() async {
        try {
          final u = saved.invoiceUuid;
          if (u != null && u.isNotEmpty) await InvoiceSyncService().syncInvoiceBundleNow(u);
          final cid = saved.customerId;
          if (cid != null && cid != 0) {
            final c = await DatabaseService().getCustomerById(cid);
            if (c != null && (c.syncUuid ?? '').isNotEmpty) {
              await FirebaseSyncHelper().syncCustomer(c.toMap());
            }
          }
        } catch (e) {
          print('⚠️ الرفع الفوري تأجّل: $e');
        }
      }());
      String? savedCust;
      if (saved.customerId != null) {
        final sc = await db.query('customers',
            columns: ['sync_uuid'], where: 'id = ?', whereArgs: [saved.customerId], limit: 1);
        if (sc.isNotEmpty) savedCust = sc.first['sync_uuid'] as String?;
      }
      return {
        'ok': true,
        'uuid': saved.invoiceUuid,
        'cust': savedCust,
        'paid': saved.amountPaidOnInvoice,
      };

    case 'ownInvoices':
      final db = await DatabaseService().database;
      final r = await db.rawQuery(
          'SELECT i.invoice_uuid AS u, c.sync_uuid AS cs, i.total_amount AS total, '
          'i.payment_type AS pt FROM invoices i JOIN customers c ON c.id = i.customer_id '
          'WHERE i.is_created_by_me = 1 '
          'AND (i.is_deleted IS NULL OR i.is_deleted = 0) '
          'AND (c.is_deleted IS NULL OR c.is_deleted = 0) AND i.invoice_uuid IS NOT NULL');
      return [
        for (final x in r) [x['u'], x['cs'], (x['total'] as num?)?.toDouble(), x['pt']]
      ];

    case 'custDetail':
      final db = await DatabaseService().database;
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) return {'missing': true};
      final invs = await db.rawQuery(
          'SELECT invoice_uuid, total_amount, amount_paid_on_invoice, payment_type, status, '
          'version, is_synced, is_created_by_me, is_deleted, restored_mark FROM invoices '
          'WHERE customer_id = ?',
          [cid]);
      final txs = await db.rawQuery(
          'SELECT transaction_uuid, amount_changed, transaction_type, is_deleted, '
          'is_created_by_me, is_uploaded, invoice_sync_uuid, invoice_id FROM transactions '
          'WHERE customer_id = ? ORDER BY id',
          [cid]);
      return {'invoices': invs, 'txs': txs};

    case 'suspendInvoice':
      // InvoiceSuspendService.suspendInvoice (بلا التحقق من نموذج الواجهة)
      final dbs = DatabaseService();
      final db = await dbs.database;
      final cr = await db.query('customers',
          where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      if (cr.isEmpty) throw StateError('customer not on device');
      final name = cr.first['name'] as String;
      final found = await dbs.searchCustomers(name);
      final customer = found.isNotEmpty ? found.first : null;
      final total = (a['total'] as num).toDouble();
      final invoice = Invoice(
        customerName: name,
        customerPhone: (cr.first['phone'] as String?) ?? '',
        customerAddress: (cr.first['address'] as String?) ?? '',
        installerName: '',
        invoiceDate: DateTime.now(),
        paymentType: a['ptype'] as String,
        totalAmount: total,
        discount: 0,
        amountPaidOnInvoice: (a['paid'] as num).toDouble(),
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id,
        status: 'معلقة',
        isLocked: false,
        returnAmount: 0.0,
      );
      final invoiceId = await dbs.insertInvoice(invoice);
      for (final pi in await _productItems(db, a['items'], invoiceId)) {
        await dbs.insertInvoiceItem(pi);
      }
      await dbs.insertInvoiceItem(InvoiceItem(
        invoiceId: invoiceId,
        productName: 'صنف اختبار',
        unit: 'قطعة',
        unitPrice: total,
        quantityIndividual: 1,
        appliedPrice: total,
        itemTotal: total,
        saleType: 'قطعة',
      ));
      final ir = await db.rawQuery(
          'SELECT i.invoice_uuid AS u, c.sync_uuid AS cs FROM invoices i '
          'LEFT JOIN customers c ON c.id = i.customer_id WHERE i.id = ?',
          [invoiceId]);
      return {'uuid': ir.first['u'], 'cust': ir.first['cs']};

    case 'pendingOwnWork':
      final db = await DatabaseService().database;
      final tx = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM transactions WHERE (is_uploaded = 0 OR is_uploaded IS NULL) '
          'AND ((is_created_by_me = 1 OR is_created_by_me IS NULL) OR is_deleted = 1) '
          'AND transaction_uuid IS NOT NULL');
      final inv = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM invoices WHERE (is_synced = 0 OR is_synced IS NULL) '
          'AND (is_created_by_me = 1 OR is_created_by_me IS NULL)');
      final cu = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM customers WHERE tombstoned IN (2, 3) OR '
          '((is_created_by_me = 1 OR is_created_by_me IS NULL) AND sync_uuid IS NOT NULL '
          'AND (synced_at IS NULL OR last_modified_at > synced_at))');
      // 📦 حركات مخزون ومنتجات لم تُرفع بعد: الاستعادة تُضيّعها حتماً (كالمعاملات)
      final mv = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM stock_movements WHERE is_uploaded = 0');
      final pr = await db.rawQuery(
          "SELECT COUNT(*) AS n FROM products WHERE last_synced_at IS NULL "
          "AND sync_uuid IS NOT NULL AND sync_uuid != ''");
      return (tx.first['n'] as int) +
          (inv.first['n'] as int) +
          (cu.first['n'] as int) +
          (mv.first['n'] as int) +
          (pr.first['n'] as int);

    case 'backup':
      final db = await DatabaseService().database;
      final target = (a['path'] as String).replaceAll("'", "''");
      await db.execute("VACUUM INTO '$target'");
      return true;

    case 'smartPipe':
      final r = await SmartPipeCleanupService().runManualCleanup();
      return r.deletedTransactions + r.deletedInvoices;

    case 'armoredPush':
      // «بياناتي صحيحة» — لا ننتظرها (تنتظر ردود الأجهزة حتى 90 ثانية)
      unawaited(ArmoredReconciliationService()
          .pushMyTruthForCustomer(a['cust'] as String)
          .catchError((e) {
        print('⚠️ مطابقة: $e');
        return false;
      }));
      return true;

    case 'setOnline':
      connectivity.setOnline(a['online'] as bool);
      return true;

    case 'kick':
      await FirebaseSyncService().debugRunBackgroundCycle();
      await FirebaseSyncService().performFullCatchUp();
      return true;

    case 'visibleCustomers':
      final db = await DatabaseService().database;
      final r = await db.query('customers',
          columns: ['sync_uuid'],
          where: "(is_deleted IS NULL OR is_deleted = 0) AND sync_uuid IS NOT NULL AND sync_uuid != ''");
      return [for (final x in r) x['sync_uuid'] as String];

    case 'ownManualTxs':
      final db = await DatabaseService().database;
      final r = await db.query('transactions',
          columns: ['transaction_uuid', 'transaction_type', 'amount_changed'],
          where: "is_created_by_me = 1 AND (is_deleted IS NULL OR is_deleted = 0) "
              "AND invoice_id IS NULL AND transaction_type IN ('manual_debt','manual_payment') "
              "AND transaction_uuid IS NOT NULL");
      return [
        for (final x in r)
          [x['transaction_uuid'], x['transaction_type'], (x['amount_changed'] as num).toDouble()]
      ];

    case 'state':
      final db = await DatabaseService().database;
      final customers = await db.rawQuery('''
        SELECT c.sync_uuid AS uuid, c.name AS name, c.current_total_debt AS debt,
               c.is_deleted AS del, c.tombstoned AS tomb, c.is_created_by_me AS mine,
               (SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t
                 WHERE t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0)) AS sum,
               (SELECT COUNT(*) FROM transactions t
                 WHERE t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0)) AS cnt
        FROM customers c
      ''');
      final pending = await db.rawQuery('''
        SELECT COUNT(*) AS n FROM transactions
        WHERE (is_uploaded = 0 OR is_uploaded IS NULL)
          AND ((is_created_by_me = 1 OR is_created_by_me IS NULL) OR is_deleted = 1)
          AND transaction_uuid IS NOT NULL
      ''');
      final txs = await db.rawQuery('''
        SELECT t.transaction_uuid AS uuid, c.sync_uuid AS cust, t.amount_changed AS amount,
               t.is_deleted AS del, t.is_created_by_me AS mine, t.is_uploaded AS up,
               t.invoice_sync_uuid AS inv
        FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
      ''');
      return {
        'customers': [
          for (final r in customers)
            {
              'uuid': r['uuid'],
              'name': r['name'],
              'debt': (r['debt'] as num?)?.toDouble() ?? 0.0,
              'sum': (r['sum'] as num?)?.toDouble() ?? 0.0,
              'cnt': r['cnt'],
              'del': r['del'],
              'tomb': r['tomb'],
              'mine': r['mine'],
            }
        ],
        'txs': [
          for (final r in txs)
            {
              'uuid': r['uuid'],
              'cust': r['cust'],
              'amount': (r['amount'] as num?)?.toDouble() ?? 0.0,
              'del': r['del'],
              'mine': r['mine'],
              'up': r['up'],
              'inv': r['inv'],
            }
        ],
        'pending': pending.first['n'],
        'products': {
          for (final x in await db.query('products',
              columns: ['sync_uuid', 'stock_quantity'],
              where: "sync_uuid IS NOT NULL AND sync_uuid != ''"))
            x['sync_uuid'] as String: (x['stock_quantity'] as num?)?.toDouble() ?? 0.0
        },
        'recovering': FirebaseSyncService().isRecovering,
        'bootstrapping': FirebaseSyncService().debugBootstrapping,
        'errors': errors.length,
      };

    case 'logs':
      final n = (a['n'] as int?) ?? 200;
      return logs.length <= n ? List<String>.from(logs) : logs.sublist(logs.length - n);

    case 'errors':
      return List<String>.from(errors);

    case 'shutdown':
      print('[harness] shutdown: prefs');
      final prefs = await SharedPreferences.getInstance();
      final prefMap = <String, Object>{};
      for (final k in prefs.getKeys()) {
        final v = prefs.get(k);
        if (v != null) prefMap[k] = v is List ? List<String>.from(v) : v;
      }
      print('[harness] shutdown: secure');
      final secure = await const FlutterSecureStorage().readAll();
      // إعادة التشغيل = قتل مفاجئ للعملية: لا dispose ولا إغلاق للقاعدة
      // (إغلاقها بينما كود المزامنة يعمل عليها يُسقط SQLite الأصلية).
      // نسخة متسقة لحظية من القاعدة = ما كان محفوظاً على القرص لحظة القتل.
      final copyTo = a['copyTo'] as String?;
      if (copyTo != null) {
        final db = await DatabaseService().database;
        final target = copyTo.replaceAll("'", "''");
        await db.execute("VACUUM INTO '$target'");
      }
      return {'prefs': prefMap, 'secure': secure};
  }
  throw UnsupportedError('unknown command ${c.op}');
}

/// بنود أصناف حقيقية كما تبنيها شاشة الفاتورة: [{prod, qty, large}] ← بند
/// بسعر 1 للوحدة الأساسية، ووحدة كبيرة (كرتون) بمعامل تحويلها.
Future<List<InvoiceItem>> _productItems(dynamic db, Object? spec, int invoiceId) async {
  final out = <InvoiceItem>[];
  for (final raw in (spec as List?) ?? const []) {
    final m = (raw as Map).cast<String, Object?>();
    var pr = await db.query('products', where: 'sync_uuid = ?', whereArgs: [m['prod']], limit: 1);
    if (pr.isEmpty) {
      // نسخة دُمجت في غيرها (الاسم نفسه على جهازين): الشاشة تعمل على الصف
      // نفسه، والصف صار بمعرّف الباقية
      final al = await db.query('product_uuid_alias',
          columns: ['new_uuid'], where: 'old_uuid = ?', whereArgs: [m['prod']], limit: 1);
      if (al.isNotEmpty) {
        pr = await db.query('products',
            where: 'sync_uuid = ?', whereArgs: [al.first['new_uuid']], limit: 1);
      }
    }
    if (pr.isEmpty) continue;
    final p = pr.first;
    final qty = (m['qty'] as num).toDouble();
    final large = m['large'] == true;
    final carton = _carton(p['unit_hierarchy'] as String?);
    final useLarge = large && carton != null;
    final baseQty = useLarge ? qty * carton : qty;
    final price = (m['price'] as num?)?.toDouble() ?? (useLarge ? carton.toDouble() : 1.0);
    out.add(InvoiceItem(
      invoiceId: invoiceId,
      productId: p['id'] as int,
      productName: p['name'] as String,
      unit: 'piece',
      unitPrice: 1,
      costPrice: 0.5 * baseQty,
      quantityIndividual: useLarge ? null : qty,
      quantityLargeUnit: useLarge ? qty : null,
      appliedPrice: price,
      itemTotal: qty * price,
      saleType: useLarge ? 'كرتون' : 'قطعة',
      unitsInLargeUnit: useLarge ? carton.toDouble() : null,
    ));
  }
  return out;
}

int? _carton(String? hierarchy) {
  if (hierarchy == null) return null;
  final m = RegExp(r'"quantity"\s*:\s*(\d+)').firstMatch(hierarchy);
  return m == null ? null : int.parse(m.group(1)!);
}
