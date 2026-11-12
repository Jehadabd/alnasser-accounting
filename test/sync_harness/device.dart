// test/sync_harness/device.dart
// «جهاز وهمي»: خيط منفصل يشغّل كود التطبيق الحقيقي (DatabaseService،
// AppProvider، FirebaseSyncService…) بقاعدة SQLite حقيقية خاصة به، وإعدادات
// خاصة، ومنصات وهمية. ينفّذ أوامر الاختبار عبر نفس الدوال التي تستدعيها الشاشات.

// ignore_for_file: avoid_print, implementation_imports

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:alnaser/accounting/accounting_reports.dart';
import 'package:alnaser/accounting/posting_engine.dart';
import 'package:alnaser/controllers/invoice_controller.dart';
import 'package:alnaser/erp/debts/customer_money.dart';
import 'package:alnaser/erp/erp_common.dart' show PeriodLock;
import 'package:alnaser/erp/purchases/purchase_return_service.dart';
import 'package:alnaser/erp/debts/receipts_service.dart';
import 'package:alnaser/erp/sales/sales_return_service.dart';
import 'package:alnaser/erp/stock_helpers.dart';
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
import 'package:alnaser/services/database/business/financial_deep_check.dart';
import 'package:alnaser/services/held_invoices.dart';
import 'package:alnaser/utils/iqd.dart'; // 💵
import 'rest_ops.dart'; // 🔨 اختبار البقية القاسي
import 'accounting_ops.dart'; // 🏦 الصندوق والمحاسبة
import 'features_ops.dart'; // 🧩 الميزات المتبقية
import 'scenario_ops.dart'; // 🧾 سيناريوهات الفاتورة
import 'gap_ops.dart'; // 🕳️ مسارات المال غير المغطاة
import 'package:alnaser/services/license_service.dart';
import 'package:alnaser/models/transaction.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/firebase_sync/armored_reconciliation_service.dart';
import 'package:alnaser/services/firebase_sync/firebase_sync_config.dart';
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
import 'package:sqflite_common/src/mixin/import_mixin.dart' show SqfliteInvokeHandler;
import 'package:alnaser/lan/lan_client.dart';
import 'package:alnaser/lan/lan_server.dart';
import 'package:alnaser/lan/lan_settings.dart';
import 'package:alnaser/services/database/core/database_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/isolate.dart' show SqfliteIsolate;
import 'package:sqflite_common_ffi/src/method_call.dart' show FfiMethodCall;

import 'fake_platforms.dart';
import 'protocol.dart';
import 'remote_firestore.dart';

const _fileLog = bool.fromEnvironment('DEVLOG');

/// ⚡ --dart-define=FAST_DISK=true: «PRAGMA synchronous = NORMAL» في إعدادات القاعدة
/// يصير OFF لأجهزة الاختبار فقط (لا انتظار لتأكيد القرص). الاختبارات لا تختبر انقطاع
/// الكهرباء أصلاً، فلا يتغير ما تختبره. كود التطبيق نفسه لا يُمسّ.
const _fastDisk = bool.fromEnvironment('FAST_DISK');
final _syncPragma = RegExp(r'^\s*PRAGMA\s+synchronous\s*=', caseSensitive: false);

Object? _fastDiskArgs(Object? arguments) {
  if (!_fastDisk || arguments is! Map) return arguments;
  final sql = arguments['sql'];
  if (sql is! String || !_syncPragma.hasMatch(sql)) return arguments;
  return {...arguments, 'sql': 'PRAGMA synchronous = OFF'};
}

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
        sqliteServer.handle(FfiMethodCall(method, _fastDiskArgs(arguments))),
  );
  PathProviderPlatform.instance = FakePathProvider(boot.dir);
  SharedPreferences.setMockInitialValues(boot.prefs);
  FlutterSecureStorage.setMockInitialValues(Map<String, String>.from(boot.secure));
  // 🔐 منذ 2026-10-12 لا تعمل المزامنة بلا ترخيص يسمح بها: ترخيص اختبار في الذاكرة
  LicenseService.debugInstallTestLicense();
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

/// 🖧 خادم الشبكة (حاسبة السيرفر) أو اتصال الطرفية في هذا الجهاز.
LanDatabaseServer? _lanServer;
LanClientConnection? _lanClient;

/// «أعد رفع معاملتي» جارٍ بلا انتظار (forceReuploadStart).
Future<bool>? _pendingForce;

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

    case 'renameCustomer':
      // ✏️ مسار «تعديل بيانات العميل» في بطاقته: AppProvider.updateCustomer بنسخة باسم جديد
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) return {'ok': false, 'err': 'العميل غير موجود على الجهاز'};
      final cur = await DatabaseService().getCustomerById(cid);
      if (cur == null) return {'ok': false, 'err': 'العميل غير موجود على الجهاز'};
      try {
        await AppProvider().updateCustomer(cur.copyWith(
          name: a['name'] as String,
          currentTotalDebt: cur.currentTotalDebt,
          lastModifiedAt: DateTime.now(),
        ));
        return {'ok': true};
      } catch (e) {
        return {'ok': false, 'err': '$e'};
      }

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
      // 'name' = ما يُكتب في حقل العميل (اسم جديد ⇒ التطبيق يُنشئ العميل)،
      // 'phone' = حقل الهاتف، 'date' = تاريخ الفاتورة، 'incomplete' = سطر ناقص.
      final nameField = a['name'] as String?;
      final cr = a['cust'] == null
          ? const <Map<String, Object?>>[]
          : await db.query('customers', where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      if (cr.isEmpty && nameField == null) throw StateError('customer not on device');
      final Map<String, Object?> cust = cr.isEmpty ? const {} : cr.first;
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
      // 💵 أسطر الأصناف مقرَّبة لأقرب دينار في InvoiceItem: البند المكمِّل يكمل
      //    المجموع المقرَّب (Iqd.up) فيبقى ديناراً صحيحاً هو الآخر
      final filler = Iqd.up(total - productTotal);
      final item = InvoiceItem(
        invoiceId: existing?.id ?? 0,
        productName: 'صنف اختبار',
        unit: 'قطعة',
        unitPrice: filler,
        quantityIndividual: 1,
        appliedPrice: filler,
        itemTotal: filler,
        saleType: 'قطعة',
      );
      final controller = InvoiceController(db: DatabaseService());
      final data = InvoiceInputData(
        invoiceToManage: existing,
        // كالشاشة: تعديل فاتورة يعرض اسم عميلها الحالي من بطاقته؛ و'storedName' = الاسم
        // المحفوظ فيها وقت البيع (كما تمرّره مسارات أخرى وتمرّره الشاشة قبل تعديل الحقل).
        // اختيار عميل آخر يكتب اسمه هو.
        customerName: nameField ??
            ((a['storedName'] == true &&
                    existing != null &&
                    existing.customerId != null &&
                    existing.customerId == cust['id'])
                ? existing.customerName
                : cust['name'] as String),
        customerPhone: (a['phone'] as String?) ?? (cust['phone'] as String?) ?? '',
        customerAddress: (cust['address'] as String?) ?? '',
        paidAmount: paid,
        loadingFee: (a['loadingFee'] as num?)?.toDouble() ?? 0,
        discount: (a['discount'] as num?)?.toDouble() ?? 0,
        paymentType: ptype,
        selectedDate: a['date'] == null ? DateTime.now() : DateTime.parse(a['date'] as String),
        invoiceItems: [
          if (filler.abs() > 0.001 || productItems.isEmpty) item,
          ...productItems,
          if (a['incomplete'] == true)
            InvoiceItem(
              invoiceId: existing?.id ?? 0,
              productName: 'سطر بلا كمية',
              unit: 'قطعة',
              unitPrice: 1000,
              appliedPrice: 1000,
              itemTotal: 0,
              saleType: 'قطعة',
            ),
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

    case 'liveRestore':
      // زر «استعادة قاعدة البيانات» في الإعدادات (أو Dropbox) والبرنامج يعمل — بلا إعادة تشغيل:
      // DatabaseService.restoreDatabaseFromFile كما تستدعيه الشاشة حرفياً
      return await DatabaseService().restoreDatabaseFromFile(File(a['path'] as String));

    // ─────────── 🖧 الشبكة المحلية: سيرفر في هذا الجهاز، أو طرفية تعمل على قاعدته ───────────
    case 'lanServe':
      // حاسبة السيرفر: خادم الشبكة على اتصال القاعدة نفسه الذي يستعمله البرنامج (كما في
      // LanRuntime._startServer)، على 127.0.0.1 ومنفذ يختاره النظام
      await DatabaseService().database;
      AppNetworkMode.current = LanSettings(mode: LanMode.server, secret: a['secret'] as String);
      _lanServer = LanDatabaseServer(
        databasePath: await DatabaseConfig.getDatabasePath(),
        secret: a['secret'] as String,
        port: 0,
        enableDiscovery: false,
        transactionIdleTimeout: const Duration(seconds: 5),
        handler: databaseFactory as SqfliteInvokeHandler,
        log: print,
      );
      await _lanServer!.start();
      return _lanServer!.boundPort;

    case 'lanJoin':
      // طرفية: كما في LanRuntime.beforeDatabase — اتصال ثم المصنع البعيد قبل أي فتح للقاعدة.
      // لا مزامنة على الطرفية (main: ownsDatabase وحده يشغّلها).
      AppNetworkMode.current = LanSettings(
          mode: LanMode.client,
          host: '127.0.0.1',
          port: (a['port'] as num).toInt(),
          secret: a['secret'] as String,
          clientName: 'طرفية ${a['name'] ?? ''}');
      final conn = LanClientConnection(
        host: '127.0.0.1',
        port: (a['port'] as num).toInt(),
        secret: a['secret'] as String,
        clientName: 'طرفية ${a['name'] ?? ''}',
        requestTimeout: const Duration(seconds: 60),
      );
      await conn.connect();
      _lanClient = conn;
      databaseFactory = createLanDatabaseFactory(conn);
      try {
        await DatabaseService().database;
        return {'ok': true};
      } catch (e) {
        return {'ok': false, 'err': '$e'.split('\n').first};
      }

    case 'lanDrop':
      // الشبكة سقطت (كابل، راوتر): الطرفية تعيد الاتصال وحدها عند الطلب التالي
      await _lanClient?.debugDropConnection();
      return true;

    case 'lanTxnDrop':
      // معاملة على الطرفية تكتب صف دين ثم تسقط الشبكة قبل أن تكتمل ⇒ لا شيء يُحفظ
      final db = await DatabaseService().database;
      final cid = await _customerId(a['cust'] as String);
      try {
        await db.transaction((txn) async {
          await txn.insert('transactions', {
            'customer_id': cid,
            'amount_changed': (a['amount'] as num).toDouble(),
            'transaction_type': 'manual_debt',
            'transaction_note': a['marker'],
            'transaction_date': DateTime.now().toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
            'transaction_uuid': 'lan_${a['marker']}',
            'sync_uuid': 'lan_${a['marker']}',
          });
          await _lanClient!.debugDropConnection();
          await txn.insert('transactions', {
            'customer_id': cid,
            'amount_changed': 1.0,
            'transaction_type': 'manual_debt',
            'transaction_note': '${a['marker']}_2',
            'transaction_date': DateTime.now().toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          });
        });
        return {'committed': true};
      } catch (e) {
        return {'committed': false, 'err': '$e'.split('\n').first};
      }

    case 'sqlRaw':
      // أمر SQL خام كما قد ترسله طرفية بإصدار قديم (مثل PRAGMA synchronous = NORMAL)
      final db = await DatabaseService().database;
      return await db.rawQuery(a['sql'] as String);

    case 'smartPipe':
      final r = await SmartPipeCleanupService().runManualCleanup();
      return r.deletedTransactions + r.deletedInvoices;

    case 'durability':
      // 🔌 إعداد الكتابة على القرص الفعّال الآن على اتصال التطبيق نفسه:
      // synchronous (2 = FULL: كل حفظ يُثبَّت على القرص قبل أن يعود) ووضع اليومية.
      final db = await DatabaseService().database;
      final s = await db.rawQuery('PRAGMA synchronous');
      final j = await db.rawQuery('PRAGMA journal_mode');
      return {
        'sync': (s.first.values.first as num).toInt(),
        'journal': '${j.first.values.first}'.toLowerCase(),
      };

    case 'txAlive':
      // هل المعاملة موجودة وغير محذوفة؟ (للتحقق بعد القتل المفاجئ)
      final row = await _txRow(a['tx'] as String);
      return row != null && ((row['is_deleted'] as int?) ?? 0) == 0;

    case 'armoredPush':
      // «بياناتي صحيحة» — لا ننتظرها (تنتظر ردود الأجهزة حتى 90 ثانية)
      unawaited(ArmoredReconciliationService()
          .pushMyTruthForCustomer(a['cust'] as String)
          .catchError((e) {
        print('⚠️ مطابقة: $e');
        return false;
      }));
      return true;

    case 'markArchive':
      // إعدادات المزامنة: «اعتبار الفواتير القديمة مرفوعة»
      final r = await FirebaseSyncService().markArchiveInvoicesAsSynced();
      return {'marked': r.marked, 'refused': r.refused};

    case 'forceReuploadStart':
      // «أعد رفع معاملتي» يبدأ ولا يُنتظر: يصنع تعديلاً حقيقياً أثناء الرفع (الأوامر متسلسلة)
      _pendingForce = FirebaseSyncService().forceReuploadOwnedTransaction(a['tx'] as String);
      return true;

    case 'forceReuploadAwait':
      final f = _pendingForce;
      _pendingForce = null;
      return f == null ? null : await f;

    case 'forceReupload':
      // شاشة المطابقة: «أعد رفع معاملتي» (FirebaseSyncService.forceReuploadOwnedTransaction)
      return await FirebaseSyncService().forceReuploadOwnedTransaction(a['tx'] as String);

    case 'armoredPushWait':
      // «بياناتي صحيحة» وانتظار نتيجتها (نجاح / بانتظار موافقة الجهاز الآخر / فشل)
      final svc = ArmoredReconciliationService();
      final ok = await svc.pushMyTruthForCustomer(a['cust'] as String);
      return {'ok': ok, 'awaiting': svc.lastPushAwaitingApproval};

    case 'armoredPending':
      // 🔐 الكشوف الواردة التي تنتظر موافقة صاحب هذا الجهاز (كما تحمّلها الشاشة الرئيسية)
      await ArmoredReconciliationService().loadPending();
      return [
        for (final p in ArmoredReconciliationService().pendingApprovals.value)
          {'cust': p.customerSyncUuid, 'name': p.customerName, ...p.preview.toJson()},
      ];

    case 'armoredDecide':
      final svc = ArmoredReconciliationService();
      final hit = svc.pendingApprovals.value.where((p) => p.customerSyncUuid == a['cust']).toList();
      if (hit.isEmpty) return {'ok': false, 'err': 'لا طلب منتظر لهذا العميل'};
      final msg = a['approve'] == true ? await svc.approve(hit.first) : await svc.reject(hit.first);
      return {'ok': true, 'msg': msg};

    case 'ghostTx':
      // صف معاملة بلا أي أثر في السحابة (بيانات قديمة/عالقة) — لصنع تباين حقيقي تكشفه المطابقة.
      // mine=true: من إنشاء هذا الجهاز ولم يُرفع قط؛ وإلا: «من جهاز آخر» بلا مستند ولا إقرار.
      final db = await DatabaseService().database;
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) throw StateError('customer not on device');
      final mine = a['mine'] == true;
      final uuid = 'ghost_${a['tag']}';
      final now = DateTime.now().toIso8601String();
      // صف من فاتورة (اختياري): يسافر داخل حزمة فاتورته
      final invUuid = a['inv'] as String?;
      int? invId;
      if (invUuid != null) {
        final ir = await db.query('invoices', columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [invUuid], limit: 1);
        if (ir.isEmpty) throw StateError('invoice not on device');
        invId = ir.first['id'] as int;
      }
      await db.insert('transactions', {
        if (invUuid != null) 'invoice_sync_uuid': invUuid,
        if (invId != null) 'invoice_id': invId,
        'customer_id': cid,
        'transaction_date': now,
        'amount_changed': (a['amount'] as num).toDouble(),
        'transaction_type': (a['amount'] as num) >= 0 ? 'manual_debt' : 'manual_payment',
        'transaction_note': 'شبح ${a['tag']}',
        'created_at': now,
        'is_created_by_me': mine ? 1 : 0,
        'is_uploaded': 1,
        'is_deleted': 0,
        'transaction_uuid': uuid,
        'sync_uuid': uuid,
        'origin_device_id': mine ? await FirebaseSyncConfig.getDeviceId() : 'ghost_device',
      });
      await DatabaseService().recalculateAndApplyCustomerDebt(cid);
      return uuid;

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

    // ═══════════ عمليات النسخة المحاسبية (نفس خدمات الشاشات) ═══════════

    case 'deleteInvoice':
      final db = await DatabaseService().database;
      final ir = await db.query('invoices', columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) throw StateError('invoice not on device');
      try {
        await DatabaseService().deleteInvoice(ir.first['id'] as int);
      } catch (e) {
        return {'ok': false, 'err': '$e'};
      }
      return {'ok': true};

    case 'receipt':
      // وصل قبض/خصم عبر البوابة الوحيدة CustomerMoney (يمر بـ AppProvider.addTransaction)
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) throw StateError('customer not on device');
      final kind = (a['kind'] as String?) == 'discount' ? CustomerTxKind.discount : CustomerTxKind.cash;
      final u = await CustomerMoney.post(null,
          provider: AppProvider(),
          customerId: cid,
          amount: -(a['amount'] as num).toDouble(),
          kind: kind,
          note: 'وصل اختبار ${a['marker'] ?? ''}');
      return u;

    case 'salesReturn':
      final db = await DatabaseService().database;
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) throw StateError('customer not on device');
      final cname = (await db.query('customers', columns: ['name'], where: 'id = ?', whereArgs: [cid])).first['name'] as String;
      int? invId;
      if (a['inv'] != null) {
        final ir = await db.query('invoices', columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
        if (ir.isEmpty) throw StateError('invoice not on device');
        invId = ir.first['id'] as int;
      }
      final lines = <ReturnLine>[];
      for (final it in (a['items'] as List).cast<Map>()) {
        final pr = await db.query('products', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [it['prod']], limit: 1);
        final p = await ErpStock.byId(db, pr.first['id'] as int);
        lines.add(ReturnLine(product: p!, unit: p.units.first, quantity: (it['qty'] as num).toDouble(),
            price: (it['price'] as num).toDouble()));
      }
      final box = await db.rawQuery('SELECT id FROM cash_boxes ORDER BY is_default DESC, id LIMIT 1');
      final before = await db.rawQuery('SELECT COALESCE(MAX(id), 0) AS m FROM transactions');
      try {
        final id = await SalesReturnService().create(null,
            provider: AppProvider(),
            customerId: cid,
            customerName: cname,
            originalInvoiceId: invId,
            refundMode: a['mode'] as String,
            cashAmount: ((a['cash'] as num?) ?? 0).toDouble(),
            cashBoxId: box.isEmpty ? null : box.first['id'] as int,
            date: DateTime.now(),
            lines: lines);
        // معاملات هذا المرتجع فقط: أنشأها هذا الجهاز، وليست معاملة فاتورة. (الأجهزة تعمل
        // معاً: معاملة واردة بالمزامنة في اللحظة نفسها كانت تُحسب منه — الشامل seed=653456)
        final tx = await db.rawQuery(
            'SELECT transaction_uuid AS u, amount_changed AS a FROM transactions WHERE id > ? AND customer_id = ? '
            "AND COALESCE(is_created_by_me, 1) = 1 AND (invoice_sync_uuid IS NULL OR invoice_sync_uuid = '')",
            [before.first['m'], cid]);
        return {'ok': true, 'id': id, 'txs': [for (final t in tx) [t['u'], (t['a'] as num).toDouble()]]};
      } catch (e) {
        return {'ok': false, 'err': '$e'};
      }

    case 'voidSalesReturn':
      final db = await DatabaseService().database;
      final before = await db.rawQuery('SELECT COALESCE(MAX(id), 0) AS m FROM transactions');
      try {
        await SalesReturnService().voidReturn(null, a['id'] as int, reason: 'اختبار', provider: AppProvider());
      } catch (e) {
        return {'ok': false, 'err': '$e'};
      }
      // معاملات هذا الإلغاء فقط (انظر salesReturn): معاملة فاتورة 15000.01 وصلت بالمزامنة أثناء
      // الإلغاء فحُسبت منه (الشامل seed=653456، عملية 3010)
      final tx = await db.rawQuery(
          'SELECT transaction_uuid AS u, amount_changed AS a FROM transactions WHERE id > ? '
          "AND COALESCE(is_created_by_me, 1) = 1 AND (invoice_sync_uuid IS NULL OR invoice_sync_uuid = '')",
          [before.first['m']]);
      return {'ok': true, 'txs': [for (final t in tx) [t['u'], (t['a'] as num).toDouble()]]};

    case 'purchaseReturn':
      final db = await DatabaseService().database;
      var sup = await db.query('suppliers', columns: ['id', 'name'], where: 'name = ?', whereArgs: ['مورد الاختبار'], limit: 1);
      if (sup.isEmpty) {
        await db.insert('suppliers', {
          'name': 'مورد الاختبار',
          'total_debt_iqd': 0.0,
          'total_debt_usd': 0.0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        sup = await db.query('suppliers', columns: ['id', 'name'], where: 'name = ?', whereArgs: ['مورد الاختبار'], limit: 1);
      }
      final pr = await db.query('products', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [a['prod']], limit: 1);
      final p = await ErpStock.byId(db, pr.first['id'] as int);
      final box = await db.rawQuery('SELECT id FROM cash_boxes ORDER BY is_default DESC, id LIMIT 1');
      try {
        final id = await PurchaseReturnService().create(
          supplierId: sup.first['id'] as int,
          supplierName: 'مورد الاختبار',
          currency: 'IQD',
          refundMode: a['mode'] as String,
          cashAmount: ((a['cash'] as num?) ?? 0).toDouble(),
          cashBoxId: box.isEmpty ? null : box.first['id'] as int,
          date: DateTime.now(),
          allowNegative: a['allowNegative'] == true,
          lines: [
            PurchaseReturnLine(product: p!, unit: p.units.first, quantity: (a['qty'] as num).toDouble(),
                price: (a['price'] as num).toDouble())
          ],
        );
        return {'ok': true, 'id': id};
      } catch (e) {
        return {'ok': false, 'err': '$e'};
      }

    case 'voidPurchaseReturn':
      try {
        await PurchaseReturnService().voidReturn(a['id'] as int, reason: 'اختبار');
        return {'ok': true};
      } catch (e) {
        return {'ok': false, 'err': '$e'};
      }

    case 'supplierFlows':
      // 🏭 سيناريو الموردين كاملاً عبر الخدمات الحقيقية — يعيد قائمة الإخفاقات (فارغة = نجاح):
      // فاتورة آجلة، دفعة وإلغاؤها، رصيد افتتاحي (يستبدل ولا يتراكم)، مرتجع يمنع
      // إلغاء الفاتورة وتحويلها لمسودة وإنقاص كميتها، إلغاء الفاتورة بعد إلغاء المرتجع، والحذف.
      final fails = <String>[];
      void expectEq(String label, num actual, num expected) {
        if ((actual - expected).abs() > 0.01) fails.add('$label: المتوقع $expected والفعلي $actual');
      }

      Future<void> expectThrows(String label, Future<void> Function() f) async {
        try {
          await f();
          fails.add('$label: كان يجب أن يُرفض');
        } catch (_) {}
      }

      final db = await DatabaseService().database;
      final ps = PurchaseService();
      Future<Map<String, double>> bal(int id) async {
        final r = await db.query('suppliers',
            columns: ['total_debt_iqd', 'total_debt_usd', 'total_payments'], where: 'id = ?', whereArgs: [id]);
        return {
          'iqd': (r.first['total_debt_iqd'] as num?)?.toDouble() ?? 0,
          'usd': (r.first['total_debt_usd'] as num?)?.toDouble() ?? 0,
          'pays': (r.first['total_payments'] as num?)?.toDouble() ?? 0,
        };
      }

      final pr = await db.query('products', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [a['prod']], limit: 1);
      if (pr.isEmpty) throw StateError('product not on device');
      final pid = pr.first['id'] as int;
      Future<double> stock() async {
        final r = await db.query('products', columns: ['stock_quantity'], where: 'id = ?', whereArgs: [pid]);
        return (r.first['stock_quantity'] as num?)?.toDouble() ?? 0;
      }

      final stock0 = await stock();
      final now = DateTime.now();
      final sid = await ps.addSupplier(Supplier(name: 'مورد السيناريو', createdAt: now, updatedAt: now));

      // 1) فاتورة آجلة مؤكدة 10 × 1000
      await ps.savePurchaseInvoice(
          PurchaseInvoice(invoiceNumber: 'S-1', supplierId: sid, totalAmount: 10000, status: 'confirmed', date: now),
          [PurchaseInvoiceItem(productId: pid, unitName: 'قطعة', quantity: 10, unitPrice: 1000, totalPrice: 10000)]);
      final inv = (await ps.getInvoicesForSupplier(sid)).first;
      expectEq('دين بعد الفاتورة', (await bal(sid))['iqd']!, 10000);
      expectEq('المخزون بعد الشراء', await stock(), stock0 + 10);

      // 2) دفعة 4,000 نقداً من صندوق
      final box = await db.rawQuery('SELECT id FROM cash_boxes ORDER BY is_default DESC, id LIMIT 1');
      await ReceiptsService().supplierPayment(
          supplierId: sid,
          amount: 4000,
          currency: 'IQD',
          method: 'cash',
          date: now,
          cashBoxId: box.isEmpty ? null : box.first['id'] as int);
      expectEq('دين بعد الدفعة', (await bal(sid))['iqd']!, 6000);
      final pay = (await ps.getPaymentsForSupplier(sid)).first;

      // 3) إلغاء السند: يعود الدين، والسند يبقى «ملغى»، ولا يُلغى مرتين
      await ps.voidPayment(pay.id!, reason: 'اختبار');
      var b = await bal(sid);
      expectEq('دين بعد إلغاء السند', b['iqd']!, 10000);
      expectEq('عدد الدفعات بعد الإلغاء', b['pays']!, 0);
      if (!(await ps.getPaymentsForSupplier(sid)).first.isVoid) fails.add('السند الملغى لا يظهر «ملغى»');
      await expectThrows('إلغاء السند مرتين', () => ps.voidPayment(pay.id!));

      // 4) الرصيد الافتتاحي: يستبدل ولا يتراكم، والصفر يحذفه
      final od = now.subtract(const Duration(days: 30));
      await ps.setOpeningBalance(sid, amount: 2500, currency: 'IQD', date: od);
      expectEq('بعد رصيد افتتاحي 2,500', (await bal(sid))['iqd']!, 12500);
      await ps.setOpeningBalance(sid, amount: 1500, currency: 'IQD', date: od);
      expectEq('بعد تعديله إلى 1,500', (await bal(sid))['iqd']!, 11500);
      await ps.setOpeningBalance(sid, amount: -500, currency: 'USD', date: od);
      expectEq('رصيد دولار لنا عنده', (await bal(sid))['usd']!, -500);
      await ps.setOpeningBalance(sid, amount: 0, currency: 'USD', date: od);
      await ps.setOpeningBalance(sid, amount: 0, currency: 'IQD', date: od);
      b = await bal(sid);
      expectEq('بعد حذف الافتتاحي (دينار)', b['iqd']!, 10000);
      expectEq('بعد حذف الافتتاحي (دولار)', b['usd']!, 0);

      // 5) مرتجع على الفاتورة يمنع إلغاءها وتحويلها لمسودة وإنقاص كميتها تحت المُرجع
      final p = await ErpStock.byId(db, pid);
      final retId = await PurchaseReturnService().create(
        supplierId: sid,
        supplierName: 'مورد السيناريو',
        originalInvoiceId: inv.id,
        currency: 'IQD',
        refundMode: 'debt',
        date: now,
        allowNegative: true,
        lines: [PurchaseReturnLine(product: p!, unit: p.units.first, quantity: 2, price: 1000)],
      );
      expectEq('دين بعد مرتجع 2', (await bal(sid))['iqd']!, 8000);
      await expectThrows('إلغاء فاتورة عليها مرتجع', () => ps.cancelPurchaseInvoice(inv.id!));
      final items = await ps.getInvoiceItems(inv.id!);
      await expectThrows(
          'تحويل فاتورة عليها مرتجع إلى مسودة',
          () => ps.updatePurchaseInvoiceWithReversal(
              inv,
              PurchaseInvoice(invoiceNumber: 'S-1', supplierId: sid, totalAmount: 10000, status: 'draft', date: now),
              items,
              items));
      await expectThrows(
          'إنقاص الكمية تحت المُرجع',
          () => ps.updatePurchaseInvoiceWithReversal(
                inv,
                PurchaseInvoice(invoiceNumber: 'S-1', supplierId: sid, totalAmount: 1000, status: 'confirmed', date: now),
                items,
                [PurchaseInvoiceItem(productId: pid, unitName: 'قطعة', quantity: 1, unitPrice: 1000, totalPrice: 1000)],
              ));
      expectEq('الدين لم يتغير بالمحاولات المرفوضة', (await bal(sid))['iqd']!, 8000);
      expectEq('المخزون لم يتغير بالمحاولات المرفوضة', await stock(), stock0 + 8);

      // 6) بعد إلغاء المرتجع تُلغى الفاتورة: يسقط دينها وتخرج كمياتها
      await PurchaseReturnService().voidReturn(retId, reason: 'اختبار');
      expectEq('دين بعد إلغاء المرتجع', (await bal(sid))['iqd']!, 10000);
      await ps.cancelPurchaseInvoice(inv.id!, reason: 'اختبار');
      expectEq('دين بعد إلغاء الفاتورة', (await bal(sid))['iqd']!, 0);
      expectEq('المخزون بعد إلغاء الفاتورة', await stock(), stock0);
      final st = (await ps.getInvoiceById(inv.id!))?.status;
      if (st != 'cancelled') fails.add('حالة الفاتورة بعد الإلغاء: $st');
      await expectThrows('إلغاء الفاتورة مرتين', () => ps.cancelPurchaseInvoice(inv.id!));

      // 7) الحذف: ممنوع لمن له مستندات، ومسموح لمورد بلا أثر
      if (await ps.supplierDeleteBlocker(sid) == null) fails.add('مورد له فاتورة يُسمح بحذفه');
      final empty = await ps.addSupplier(
          Supplier(name: 'مورد فارغ ${now.microsecondsSinceEpoch}', createdAt: now, updatedAt: now));
      try {
        await ps.deleteSupplier(empty);
      } catch (e) {
        fails.add('حذف مورد بلا أثر فشل: $e');
      }
      return {'fails': fails};

    case 'setLock':
      final v = a['date'] as String?;
      await PeriodLock.setLockDate(v == null ? null : DateTime.parse(v));
      return true;

    case 'custBalance':
      // دين العميل المخزّن + مجموع معاملاته الحيّة + هاتف بطاقته (سريع)
      final db = await DatabaseService().database;
      final r = await db.rawQuery('''
        SELECT c.current_total_debt AS debt, c.phone AS phone, c.is_deleted AS del, c.name AS name,
               (SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t
                WHERE t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0) AS sum
        FROM customers c WHERE c.sync_uuid = ? LIMIT 1''', [a['cust']]);
      if (r.isEmpty) return null;
      return {
        'debt': (r.first['debt'] as num?)?.toDouble() ?? 0.0,
        'sum': (r.first['sum'] as num?)?.toDouble() ?? 0.0,
        'phone': r.first['phone'],
        'del': r.first['del'],
        'name': r.first['name'],
      };

    case 'holdInvoice':
      // زر «تعليق» في شاشة الفاتورة: HeldInvoices.hold (جديدة أو معلّقة موجودة)
      final db = await DatabaseService().database;
      Invoice? existing;
      if (a['inv'] != null) {
        final ir = await db.query('invoices', where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
        if (ir.isEmpty) throw StateError('invoice not on device');
        existing = Invoice.fromMap(ir.first);
      }
      final cr = await db.query('customers', where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      if (cr.isEmpty) throw StateError('customer not on device');
      final total = (a['total'] as num).toDouble();
      final productItems = await _productItems(db, a['items'], existing?.id ?? 0);
      final productTotal = productItems.fold(0.0, (s, i) => s + i.itemTotal);
      final filler = Iqd.up(total - productTotal); // 💵 كما في saveInvoice
      try {
        final held = await HeldInvoices.hold(
          existing: existing,
          items: [
            if (filler.abs() > 0.001 || productItems.isEmpty)
              InvoiceItem(
                invoiceId: existing?.id ?? 0,
                productName: 'صنف اختبار',
                unit: 'قطعة',
                unitPrice: filler,
                quantityIndividual: 1,
                appliedPrice: filler,
                itemTotal: filler,
                saleType: 'قطعة',
              ),
            ...productItems,
          ],
          customerName: cr.first['name'] as String,
          customerPhone: cr.first['phone'] as String?,
          invoiceDate: DateTime.now(),
          paymentType: a['ptype'] as String? ?? 'دين',
          discount: (a['discount'] as num?)?.toDouble() ?? 0,
          loadingFee: (a['loadingFee'] as num?)?.toDouble() ?? 0,
          paid: (a['paid'] as num?)?.toDouble() ?? 0,
        );
        return {'ok': true, 'uuid': held.invoiceUuid};
      } catch (e) {
        return {'ok': false, 'err': '$e'};
      }

    case 'discardHeld':
      final db = await DatabaseService().database;
      final ir = await db.query('invoices', where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) throw StateError('invoice not on device');
      await HeldInvoices.discard(Invoice.fromMap(ir.first));
      return true;

    case 'deepCheck':
      // 🔬 الفحص العميق (قراءة فقط) على قاعدة هذا الجهاز
      final r = await FinancialDeepCheck(await DatabaseService().database).run();
      return {'errors': r.errors, 'warnings': r.warnings, 'text': r.asText()};

    case 'ledgerCheck':
      // ترحيل كامل ثم فحوص الدفتر: كل قيد متوازن، الميزان متوازن، ذمم العملاء =
      // سجل الديون (إجمالاً ولكل عميل)، ذمم الموردين = أرصدتهم، والترحيل الثاني لا يغيّر شيئاً.
      final db = await DatabaseService().database;
      final s1 = await PostingEngine().syncAll();
      final s2 = await PostingEngine().syncAll();
      final problems = <String>[...s1.errors, ...s2.errors];
      if (s2.created + s2.updated + s2.deleted > 0) {
        problems.add('الترحيل الثاني غيّر قيوداً (غير إدمبوتنت): $s2');
      }
      problems.addAll(await AccountingReports().integrityCheck());
      final unb = await db.rawQuery('''
        SELECT e.id, e.source_type, SUM(l.debit) AS d, SUM(l.credit) AS c FROM journal_entries e
        JOIN journal_lines l ON l.entry_id = e.id GROUP BY e.id HAVING ABS(SUM(l.debit) - SUM(l.credit)) > 0.004''');
      for (final r in unb) {
        problems.add('قيد غير متوازن #${r['id']} (${r['source_type']}): ${r['d']} ≠ ${r['c']}');
      }
      final neg = await db.rawQuery('SELECT COUNT(*) AS n FROM journal_lines WHERE debit < 0 OR credit < 0');
      if (((neg.first['n'] as num?) ?? 0) > 0) problems.add('أسطر قيد بمبالغ سالبة: ${neg.first['n']}');
      // ذمم كل عميل في الدفتر = رصيده في سجل الديون
      try {
        final arRow = await db.query('accounts', columns: ['id'], where: "system_key = 'ar_customers'", limit: 1);
        final ar = arRow.first['id'] as int;
        final per = await db.rawQuery('''
          SELECT c.name, c.current_total_debt AS reg,
                 COALESCE((SELECT SUM(l.debit - l.credit) FROM journal_lines l
                           WHERE l.account_id = ? AND l.party_type = 'customer' AND l.party_id = c.id), 0) AS led
          FROM customers c WHERE COALESCE(c.is_deleted, 0) = 0''', [ar]);
        for (final r in per) {
          final reg = (r['reg'] as num?)?.toDouble() ?? 0, led = (r['led'] as num?)?.toDouble() ?? 0;
          if ((reg - led).abs() > 0.01) problems.add('العميل ${r['name']}: الدفتر $led وسجل الديون $reg');
        }
      } catch (e) {
        problems.add('فحص ذمم العملاء: $e');
      }
      // الكمية المخزّنة = الافتتاحي + الحركات − المبيع (دفتر المخزون)
      final stockBad = await db.rawQuery('''
        SELECT p.name, p.stock_quantity AS q,
          COALESCE((SELECT SUM(m.delta) FROM stock_movements m WHERE m.product_sync_uuid = p.sync_uuid
                      AND (m.kind != 'opening' OR m.movement_uuid = 'opening_' || p.sync_uuid)), 0)
          - COALESCE((SELECT SUM(CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                        THEN ii.quantity_large_unit * COALESCE(NULLIF(ii.units_in_large_unit, 0), 1)
                        ELSE COALESCE(ii.quantity_individual, 0) END)
                      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
                      WHERE ii.product_sync_uuid = p.sync_uuid AND COALESCE(i.is_deleted, 0) = 0
                        AND COALESCE(i.status, '') != 'معلقة'), 0) AS calc
        FROM products p WHERE COALESCE(p.is_deleted, 0) = 0 AND p.sync_uuid IS NOT NULL
          AND EXISTS (SELECT 1 FROM stock_movements m0 WHERE m0.movement_uuid = 'opening_' || p.sync_uuid)''');
      for (final r in stockBad) {
        final q = (r['q'] as num?)?.toDouble() ?? 0, c = (r['calc'] as num?)?.toDouble() ?? 0;
        if ((q - c).abs() > 0.001) problems.add('المادة ${r['name']}: الكمية $q ودفتر المخزون $c');
      }
      final tb = await db.rawQuery('SELECT COALESCE(SUM(debit), 0) AS d FROM journal_lines');
      return {'problems': problems, 'entries': s1.created + s1.updated + s1.unchanged, 'volume': tb.first['d']};

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

    case 'acct':
      // 🏦 أفعال الصندوق والمحاسبة (accounting_ops.dart)
      return await acctOp(a['op'] as String, ((a['args'] as Map?) ?? const {}).cast<String, Object?>());

    case 'scen':
      // 🧾 سيناريوهات الفاتورة (scenario_ops.dart)
      return await scenOp(a['op'] as String, ((a['args'] as Map?) ?? const {}).cast<String, Object?>());

    case 'gap':
      // 🕳️ مسارات المال التي لم يمر بها اختبار (gap_ops.dart)
      return await gapOp(a['op'] as String, ((a['args'] as Map?) ?? const {}).cast<String, Object?>());

    case 'feat':
      // 🧩 أفعال الميزات المتبقية (features_ops.dart)
      return await featOp(a['op'] as String, ((a['args'] as Map?) ?? const {}).cast<String, Object?>());

    case 'rest':
      // 🔨 أفعال اختبار البقية (rest_ops.dart)
      return await restOp(a['op'] as String, ((a['args'] as Map?) ?? const {}).cast<String, Object?>());

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
    // 🎁 هدية (سعر صفر) أو خصم سطر بنسبة/مبلغ — كما يكتبها حقل الخصم في السطر
    final gift = m['gift'] == true;
    final pct = (m['discPct'] as num?)?.toDouble();
    final amt = (m['discAmt'] as num?)?.toDouble();
    if (gift || pct != null || amt != null) {
      final applied = gift ? 0.0 : (pct != null ? price * (1 - pct / 100) : price - amt!);
      out.add(InvoiceItem(
        invoiceId: invoiceId,
        productId: p['id'] as int,
        productName: p['name'] as String,
        unit: 'piece',
        unitPrice: 1,
        costPrice: 0.5 * baseQty,
        quantityIndividual: useLarge ? null : qty,
        quantityLargeUnit: useLarge ? qty : null,
        appliedPrice: applied,
        itemTotal: qty * applied,
        saleType: useLarge ? 'كرتون' : 'قطعة',
        unitsInLargeUnit: useLarge ? carton.toDouble() : null,
        priceBeforeDiscount: price,
        discountType: gift ? 'gift' : (pct != null ? 'percent' : 'amount'),
        discountValue: gift ? 100.0 : (pct ?? amt),
      ));
      continue;
    }
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
