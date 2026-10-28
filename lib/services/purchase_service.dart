import 'dart:convert';
import 'package:sqflite/sqflite.dart'; // For Transaction
import 'package:flutter/foundation.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_invoice_item.dart';
import '../models/supplier.dart';
import '../models/supplier_payment.dart';
import '../models/supplier_delegate.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import '../services/database/business/supplier_debt_reconciler.dart';
import '../services/database/business/stock_ledger.dart'; // 📦 دفتر المخزون المشترك
import '../erp/activity/activity_log.dart';
import '../erp/erp_common.dart' show PeriodLock;
import '../erp/inventory/usd_cost_service.dart' show UsdCostService;
import '../accounting/ledger.dart' show roundMoney;
import 'database/supplier_compat.dart';
import 'name_search.dart'; // 🔤 الأسماء بلا مسافات

/// خدمة المشتريات والموردين (Odoo-Style)
class PurchaseService with ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  // --- Suppliers ---
  Future<List<Supplier>> getSuppliers({String query = ''}) async {
    final db = await _db.database;
    String whereClause = '';
    List<dynamic> args = [];

    var orderBy = 'name ASC';
    final w = NameSearch.where('name', query, phoneCol: 'phone');
    if (w != null) {
      final o = NameSearch.order('name', query);
      whereClause = 'WHERE ${w.sql}';
      orderBy = o.sql;
      args = [...w.args, ...o.args];
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT * FROM suppliers $whereClause ORDER BY $orderBy',
      args,
    );

    return List.generate(maps.length, (i) => Supplier.fromMap(maps[i]));
  }

  Future<Supplier?> getSupplierById(int id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Supplier.fromMap(maps.first);
  }

  Future<int> addSupplier(Supplier supplier) async {
    final db = await _db.database;
    final supplierMap = supplier.toMap();
    supplierMap.remove('id');
    final id = await db.insert('suppliers', await supplierInsertCompat(db, supplierMap));
    notifyListeners();
    return id;
  }

  /// تعديل بيانات المورد الوصفية فقط (الاسم، الهاتف، العنوان، العملة المفضلة،
  /// شروط الدفع، أيام الآجل، الملاحظات).
  ///
  /// 🛡️ كانت تكتب toMap() كاملاً، بما فيه total_debt_iqd/usd وعدّادات الفواتير
  /// والدفعات من كائن الشاشة — وقد يكون قديماً — فتطمس الرصيد المشتق من دفتر
  /// المورد (supplier_transactions). هذه الأعمدة يملكها SupplierDebtReconciler وحده.
  Future<void> updateSupplier(Supplier supplier) async {
    if (supplier.id == null) {
      throw ArgumentError('لا يمكن تعديل مورد بلا معرّف');
    }
    final db = await _db.database;
    final map = supplier.toMap();
    for (final k in const [
      'id',
      'created_at',
      'total_debt_iqd',
      'total_debt_usd',
      'total_purchases',
      'current_balance',
      'total_invoices',
      'total_payments',
    ]) {
      map.remove(k);
    }
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update(
      'suppliers',
      await supplierUpdateCompat(db, map),
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
    ActivityLog.log('تعديل', 'الموردون', 'تعديل بيانات المورد ${supplier.name}');
    notifyListeners();
  }

  static Future<bool> _tableExists(DatabaseExecutor d, String table) async {
    final r = await d.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1", [table]);
    return r.isNotEmpty;
  }

  /// سبب منع حذف المورد (نص عربي)، أو null إن كان الحذف آمناً.
  ///
  /// لا يُحذف مورد له أي أثر مالي أو مستندي: فواتير شراء (حتى المسودات)،
  /// دفعات، حركات في دفتره، مرتجعات، طلبات شراء، قيود، استحقاقات، أو رصيد غير صفري.
  /// (الجداول المرتبطة معرّفة بـ ON DELETE CASCADE، فالحذف كان سيمحو سجله المالي.)
  Future<String?> supplierDeleteBlocker(int supplierId, [DatabaseExecutor? executor]) async {
    final DatabaseExecutor d = executor ?? await _db.database;

    // -1 = تعذّر العدّ ⇒ نمنع الحذف احتياطاً
    Future<int> count(String table, String where, List<Object?> args) async {
      try {
        if (!await _tableExists(d, table)) return 0;
        final r = await d.rawQuery('SELECT COUNT(*) AS c FROM $table WHERE $where', args);
        return (r.first['c'] as num?)?.toInt() ?? 0;
      } catch (_) {
        return -1;
      }
    }

    final s = await d.query('suppliers',
        columns: ['total_debt_iqd', 'total_debt_usd'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
    if (s.isEmpty) return 'المورد غير موجود (ربما حُذف مسبقاً)';
    final double iqd = (s.first['total_debt_iqd'] as num?)?.toDouble() ?? 0.0;
    final double usd = (s.first['total_debt_usd'] as num?)?.toDouble() ?? 0.0;

    final invoices = await count('purchase_invoices', 'supplier_id = ?', [supplierId]);
    final payments = await count('supplier_payments', 'supplier_id = ?', [supplierId]);
    final returns = await count('purchase_returns', 'supplier_id = ?', [supplierId]);
    final txs = await count(
        'supplier_transactions', 'supplier_id = ? AND COALESCE(is_deleted, 0) = 0', [supplierId]);
    final orders = await count('orders', "party_type = 'supplier' AND party_id = ?", [supplierId]);
    final journal = await count('journal_lines', "party_type = 'supplier' AND party_id = ?", [supplierId]);
    final dues = await count('due_items', "party_type = 'supplier' AND party_id = ?", [supplierId]);

    if ([invoices, payments, returns, txs, orders, journal, dues].any((c) => c < 0)) {
      return 'تعذّر التحقق من ارتباطات المورد، لذلك لم يُحذف. أعد المحاولة لاحقاً.';
    }

    final reasons = <String>[];
    if (invoices > 0) reasons.add('$invoices فاتورة شراء');
    if (payments > 0) reasons.add('$payments دفعة');
    if (returns > 0) reasons.add('$returns مرتجع مشتريات');
    if (orders > 0) reasons.add('$orders طلب شراء');
    if (dues > 0) reasons.add('$dues استحقاق');
    if (journal > 0) reasons.add('قيود محاسبية مرتبطة به');
    if (txs > 0 && reasons.isEmpty) reasons.add('$txs حركة في كشف حسابه');
    if (iqd.abs() > 0.01 || usd.abs() > 0.01) reasons.add('رصيد غير صفري');
    if (reasons.isEmpty) return null;
    return 'لا يمكن حذف هذا المورد لأن لديه: ${reasons.join('، ')}.\n'
        'حذفه يُفقد سجله المالي. يمكنك تعديل بياناته بدلاً من حذفه.';
  }

  /// حذف مورد لا أثر مالياً له. يرمي [SupplierDeleteBlocked] إن كان له أي أثر.
  Future<void> deleteSupplier(int id) async {
    final db = await _db.database;
    String? name;
    await db.transaction((txn) async {
      // 🛡️ الفحص داخل المعاملة نفسها: لا فاتورة أو دفعة تُضاف بين الفحص والحذف
      final blocker = await supplierDeleteBlocker(id, txn);
      if (blocker != null) throw SupplierDeleteBlocked(blocker);
      final r = await txn.query('suppliers', columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
      name = r.isEmpty ? null : r.first['name'] as String?;
      if (await _tableExists(txn, 'supplier_delegates')) {
        await txn.delete('supplier_delegates', where: 'supplier_id = ?', whereArgs: [id]);
      }
      if (await _tableExists(txn, 'party_links')) {
        await txn.delete('party_links', where: 'supplier_id = ?', whereArgs: [id]);
      }
      if (await _tableExists(txn, 'product_details')) {
        await txn.update('product_details', {'default_supplier_id': null},
            where: 'default_supplier_id = ?', whereArgs: [id]);
      }
      await txn.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    });
    ActivityLog.log('حذف', 'الموردون', 'حذف المورد ${name ?? '#$id'}');
    notifyListeners();
  }

  /// إجمالي فواتير الشراء المؤكدة لكل عملة (لبطاقة «حجم المشتريات»).
  ///
  /// عمود suppliers.total_purchases لا يحدّثه أي مسار، فكان الرقم صفراً دائماً.
  Future<Map<String, double>> getConfirmedPurchaseTotals({int? supplierId}) async {
    final db = await _db.database;
    final String bySupplier = supplierId == null ? '' : ' AND supplier_id = ?';
    final rows = await db.rawQuery(
      "SELECT COALESCE(currency, 'IQD') AS cur, COALESCE(SUM(total_amount), 0) AS total "
      "FROM purchase_invoices WHERE status = 'confirmed'$bySupplier "
      "GROUP BY COALESCE(currency, 'IQD')",
      supplierId == null ? <Object?>[] : <Object?>[supplierId],
    );
    final out = <String, double>{};
    for (final r in rows) {
      out['${r['cur']}'] = (r['total'] as num?)?.toDouble() ?? 0.0;
    }
    return out;
  }

  // --- Purchase Invoices ---
  Future<List<PurchaseInvoice>> getInvoicesForSupplier(int supplierId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchase_invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => PurchaseInvoice.fromMap(maps[i]));
  }

  Future<List<PurchaseInvoice>> getInvoicesForDelegate(int delegateId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchase_invoices',
      where: 'delegate_id = ?',
      whereArgs: [delegateId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => PurchaseInvoice.fromMap(maps[i]));
  }

  Future<PurchaseInvoice?> getInvoiceById(int id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'purchase_invoices',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return PurchaseInvoice.fromMap(maps.first);
  }

  Future<List<PurchaseInvoiceItem>> getInvoiceItems(int invoiceId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT pii.*, p.name as product_name
      FROM purchase_invoice_items pii
      LEFT JOIN products p ON pii.product_id = p.id
      WHERE pii.invoice_id = ?
    ''', [invoiceId]);
    return List.generate(maps.length, (i) => PurchaseInvoiceItem.fromMap(maps[i]));
  }



  // --- Supplier Payments ---


  Future<List<SupplierPayment>> getPaymentsForSupplier(int supplierId) async {
    final db = await _db.database;
    await _ensurePaymentColumns(db);
    final List<Map<String, dynamic>> maps = await db.query(
      'supplier_payments',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC, id DESC',
    );
    return List.generate(maps.length, (i) => SupplierPayment.fromMap(_normalizePaymentRow(maps[i])));
  }

  /// 🛡️ receipt_number عمود نصّي (TEXT) فيُقرأ '12' لا 12، والنموذج يتوقع int؛
  /// كان ذلك يرمي TypeError فتفشل شاشة المورد كلها عند أول سند دفع.
  static Map<String, dynamic> _normalizePaymentRow(Map<String, dynamic> row) {
    final rn = row['receipt_number'];
    if (rn == null || rn is int) return row;
    final m = Map<String, dynamic>.from(row);
    m['receipt_number'] = rn is num ? rn.toInt() : int.tryParse('$rn'.trim());
    return m;
  }

  /// 🛡️ قاعدة جديدة تُنشئ supplier_payments من createTables بلا عمودي
  /// receipt_number و delegate_id (وبـ payment_number NOT NULL)، فكان تسجيل أي
  /// دفعة لمورد يفشل بـ «no such column». نكمّل الأعمدة الناقصة قبل الكتابة.
  // مرتبط بالقاعدة المفتوحة: قاعدة مستعادة تُجهَّز جداولها من جديد
  static int _paymentColumnsEnsuredGen = -1;
  static bool get _paymentColumnsEnsured => _paymentColumnsEnsuredGen == DatabaseService.openGeneration;
  static set _paymentColumnsEnsured(bool v) => _paymentColumnsEnsuredGen = v ? DatabaseService.openGeneration : -1;
  Future<Set<String>> _ensurePaymentColumns(DatabaseExecutor d) async {
    Future<Set<String>> cols() async => {
          for (final c in await d.rawQuery('PRAGMA table_info(supplier_payments)'))
            ('${c['name']}').toLowerCase(),
        };
    var have = await cols();
    if (!_paymentColumnsEnsured) {
      if (!have.contains('receipt_number')) {
        await d.execute('ALTER TABLE supplier_payments ADD COLUMN receipt_number TEXT');
      }
      if (!have.contains('delegate_id')) {
        await d.execute('ALTER TABLE supplier_payments ADD COLUMN delegate_id INTEGER');
      }
      // 🚫 إلغاء سند الدفع (يبقى في السجل «ملغى» بلا أثر على الرصيد)
      if (!have.contains('is_void')) {
        await d.execute('ALTER TABLE supplier_payments ADD COLUMN is_void INTEGER DEFAULT 0');
      }
      if (!have.contains('void_reason')) {
        await d.execute('ALTER TABLE supplier_payments ADD COLUMN void_reason TEXT');
      }
      if (!have.contains('voided_at')) {
        await d.execute('ALTER TABLE supplier_payments ADD COLUMN voided_at TEXT');
      }
      _paymentColumnsEnsured = true;
      have = await cols();
    }
    return have;
  }


  // --- Invoice Actions ---
  
  /// تعديل فاتورة مشتريات موجودة مع إرجاع التأثيرات السابقة وتطبيق التأثيرات الجديدة
  Future<void> updatePurchaseInvoiceWithReversal(PurchaseInvoice oldInvoice, PurchaseInvoice newInvoice, List<PurchaseInvoiceItem> oldItems, List<PurchaseInvoiceItem> newItems,
      {int? warehouseId, int? cashBoxId}) async {
    final db = await _db.database;
    
    String costingMethod = 'last_purchase';
    try {
      final settings = await SettingsManager.getAppSettings();
      costingMethod = settings.costingMethod;
    } catch (e) {
      debugPrint('Warning: Could not load costingMethod: $e');
    }
    
    await db.transaction((txn) async {
      // 1. عكس أثر المخزون القديم (الدين يتكفّل به الحارس المحاسبي لاحقاً)
      //    🛡️ الحالة القديمة تُقرأ من قاعدة البيانات لا من الكائن الممرَّر:
      //    كائن الشاشة قد يكون قديماً، وهذا بالضبط ما ضاعف ديون العملاء سابقاً.
      final oldRows = await txn.query('purchase_invoices',
          columns: ['status'], where: 'id = ?', whereArgs: [oldInvoice.id], limit: 1);
      final String oldStatus =
          oldRows.isEmpty ? 'draft' : ((oldRows.first['status'] as String?) ?? 'draft');

      // 🛡️ مرتجعات مُرحَّلة على الفاتورة تقيّد تعديلها
      if (oldStatus == 'confirmed') {
        await _assertReturnsAllow(txn, oldInvoice.id!,
            keepsConfirmed: newInvoice.status == 'confirmed', newItems: newItems);
      }

      // 🏬 المخزن القديم للفاتورة (العكس يعود إليه نفسه)
      final oldExt = await PurchaseExt.read(txn, oldInvoice.id!);
      if (oldStatus == 'confirmed') {
        for (var item in oldItems) {
          await _reverseProductStock(txn, item, warehouseId: oldExt.warehouseId);
        }
      }
      await PurchaseExt.write(txn, oldInvoice.id!, warehouseId: warehouseId, cashBoxId: cashBoxId);
      
      // 2. Delete Old Items
      await txn.delete('purchase_invoice_items', where: 'invoice_id = ?', whereArgs: [oldInvoice.id]);
      
      // 3. Update Invoice Record
      final invoiceMap = newInvoice.toMap();
      invoiceMap.remove('id');
      await txn.update('purchase_invoices', invoiceMap, where: 'id = ?', whereArgs: [oldInvoice.id]);
      
      // 4. Insert New Items
      for (var item in newItems) {
        final itemMap = item.toMap();
        itemMap['invoice_id'] = oldInvoice.id;
        itemMap.remove('id');
        itemMap.remove('product_name');
        await txn.insert('purchase_invoice_items', itemMap);
      }
      
      // 5. Apply New Effects (if new invoice is confirmed)
      if (newInvoice.status == 'confirmed') {
        for (var item in newItems) {
          await _updateProductStockAndCost(txn, item, costingMethod, warehouseId: warehouseId, currency: newInvoice.currency);
        }
      }

      // 6. 🛡️ الحارس المحاسبي: مساهمة الفاتورة = الإجمالي − المدفوع (للمؤكدة)
      //    إدمبوتنت ويقرأ الصف من قاعدة البيانات، فلا عكسٌ ولا تراكم.
      await SupplierDebtReconciler.reconcileInvoice(txn, oldInvoice.id!,
          reason: 'تعديل');
    });
    ActivityLog.log('تعديل', 'فواتير الشراء', 'تعديل فاتورة شراء ${newInvoice.invoiceNumber} — ${newInvoice.totalAmount}');
    
    notifyListeners();
  }

  Future<void> savePurchaseInvoice(PurchaseInvoice invoice, List<PurchaseInvoiceItem> items,
      {bool confirm = false, int? warehouseId, int? cashBoxId}) async {
    final db = await _db.database;
    
    // Load costing method from settings
    String costingMethod = 'last_purchase'; // Default
    try {
      final settings = await SettingsManager.getAppSettings();
      costingMethod = settings.costingMethod;
      debugPrint('📊 Loaded costingMethod from settings: $costingMethod');
    } catch (e) {
      debugPrint('Warning: Could not load costingMethod from settings: $e');
    }
    
    // الحالة المؤكدة تُحسم هنا مرة واحدة، ويُكتب أثرها في الصف نفسه، كي
    // يقرأها الحارس المحاسبي لاحقاً من قاعدة البيانات لا من معطيات الاستدعاء.
    final bool nowConfirmed = confirm || invoice.status == 'confirmed';

    await db.transaction((txn) async {
      // 1. Insert/Update Invoice
      int invoiceId;
      final invoiceMap = invoice.toMap();
      invoiceMap.remove('id');
      if (nowConfirmed) invoiceMap['status'] = 'confirmed';
      
      if (invoice.id != null) {
        invoiceId = invoice.id!;

        // 🛡️ عكس أثر المخزون القديم قبل تطبيق الجديد.
        //    كان هذا المسار يطبّق الأثر الجديد بلا عكس القديم إطلاقاً، فكل
        //    تعديل لفاتورة مؤكدة كان يُضاعف المخزون والدين.
        final oldRows = await txn.query('purchase_invoices',
            columns: ['status'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
        final String oldStatus = oldRows.isEmpty
            ? 'draft'
            : ((oldRows.first['status'] as String?) ?? 'draft');

        if (oldStatus == 'confirmed') {
          await _assertReturnsAllow(txn, invoiceId, keepsConfirmed: nowConfirmed, newItems: items);
          final oldExt = await PurchaseExt.read(txn, invoiceId);
          final oldItemRows = await txn.query('purchase_invoice_items',
              where: 'invoice_id = ?', whereArgs: [invoiceId]);
          for (final m in oldItemRows) {
            await _reverseProductStock(txn, PurchaseInvoiceItem.fromMap(m), warehouseId: oldExt.warehouseId);
          }
        }

        await txn.update('purchase_invoices', invoiceMap, where: 'id = ?', whereArgs: [invoiceId]);
        // Delete old items if updating
        await txn.delete('purchase_invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      } else {
        invoiceId = await txn.insert('purchase_invoices', invoiceMap);
      }

      // 2. Insert Items
      for (var item in items) {
        final itemMap = item.toMap();
        itemMap['invoice_id'] = invoiceId;
        itemMap.remove('id');
        itemMap.remove('product_name'); // Not stored in DB
        await txn.insert('purchase_invoice_items', itemMap);
      }

      // 🏬 المخزن المستلم والصندوق/البنك المدفوع منه (امتداد محلي)
      await PurchaseExt.write(txn, invoiceId, warehouseId: warehouseId, cashBoxId: cashBoxId);

      // 3. If Confirmed, Update Stock and Cost
      if (nowConfirmed) {
        for (var item in items) {
          await _updateProductStockAndCost(txn, item, costingMethod, warehouseId: warehouseId, currency: invoice.currency);
        }
      }

      // 4. 🛡️ الحارس المحاسبي — يتولّى الدين والعدّادات معاً.
      //    عدّادا total_invoices و total_payments صارا مشتقّين بالعدّ بدل
      //    عدّاد تراكمي كان يزيد ولا ينقص أبداً.
      await SupplierDebtReconciler.reconcileInvoice(txn, invoiceId,
          reason: invoice.id != null ? 'تعديل' : 'حفظ');
    });
    ActivityLog.log(invoice.id != null ? 'تعديل' : 'إنشاء', 'فواتير الشراء',
        'فاتورة شراء ${invoice.invoiceNumber} — ${invoice.totalAmount}${nowConfirmed ? ' (مؤكدة)' : ' (مسودة)'}');

    notifyListeners();
  }

  /// 💱 [currency] عملة فاتورة الشراء. كلفة المادة تُحفظ بالدينار دائماً، وفاتورة
  /// الدولار تجعل المادة «دولارية»: تُحفظ كلفتها بالدولار وتتبع آخر سعر للدولار
  /// (UsdCostService). كانت فاتورة الدولار تكتب السعر الدولاري كما هو (5$ ← كلفة
  /// 5 دنانير) فيتضخم الربح في التقارير. وقبل تغيير الكلفة تُثبَّت كلفة ما بيع سابقاً.
  Future<void> _updateProductStockAndCost(Transaction txn, PurchaseInvoiceItem item, String costingMethod,
      {int? warehouseId, String currency = 'IQD'}) async {
    debugPrint('💾 DB_UPDATE: Starting stock/cost update for product ID: ${item.productId}');
    debugPrint('💾 DB_UPDATE: Item baseQuantity: ${item.baseQuantity}, baseUnitCost: ${item.baseUnitCost}');
    debugPrint('💾 DB_UPDATE: Costing method: $costingMethod');
    
    final List<Map<String, dynamic>> products = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
    if (products.isEmpty) {
      debugPrint('💾 DB_UPDATE: ❌ Product not found!');
      return;
    }
    
    final product = products.first;
    double currentStock = (product['stock_quantity'] as num?)?.toDouble() ?? 0.0;
    double currentCost = (product['cost_price'] as num?)?.toDouble() ?? 0.0;
    String? currentUnitCosts = product['unit_costs'] as String?;
    String baseUnit = product['unit'] as String? ?? 'piece';

    debugPrint('💾 DB_UPDATE: Current stock: $currentStock, Current cost: $currentCost');

    // Calculate new quantity in base units (e.g., pieces)
    double newQty = item.baseQuantity;
    
    // Calculate new cost per base unit from this purchase
    final bool isUsd = currency == 'USD';
    double newUnitCost = item.baseUnitCost;

    double totalQty = currentStock + newQty;
    double finalCost;
    double? finalUsd;

    if (isUsd) {
      // كلفة الوحدة الأساسية بالدولار (متوسط مرجّح بالدولار لطريقة المتوسط)، ثم بالدينار بآخر سعر
      final rate = await UsdCostService.currentRate(txn);
      final newUsd = item.baseUnitCost;
      double usdCost = newUsd;
      if (costingMethod == 'avco') {
        final cur = await UsdCostService.read(txn, item.productId);
        final oldUsd = (cur.currency == 'USD' && (cur.usd ?? 0) > 0)
            ? cur.usd!
            : (rate > 1 ? currentCost / rate : 0.0);
        final basisQty = currentStock > 0 ? currentStock : 0.0;
        final basisTotal = basisQty + newQty;
        if (basisTotal > 0) usdCost = (basisQty * oldUsd + newQty * newUsd) / basisTotal;
      }
      finalUsd = usdCost;
      finalCost = rate > 1 ? roundMoney(usdCost * rate) : usdCost;
      if (rate <= 1) debugPrint('⚠️ لا يوجد سعر دولار — كلفة فاتورة الدولار حُفظت بلا تحويل');
    } else if (costingMethod == 'avco') {
      // Weighted Average Cost Formula (AVCO):
      // ((OldStock * OldCost) + (NewQty * NewCost)) / (OldStock + NewQty)
      // 🛡️ المخزون السالب (بيع متزامن على جهازين) بِيع فعلاً بالكلفة القديمة:
      // لا يدخل في المتوسط. كان يدخل بقيمة سالبة فتخرج الكلفة أضعاف السعر
      // (−19 بكلفة 5 ثم شراء 20 بـ 6 ← 25 بدل 6).
      final costBasisQty = currentStock > 0 ? currentStock : 0.0;
      double totalOldValue = costBasisQty * currentCost;
      double totalNewValue = newQty * newUnitCost;
      final basisTotal = costBasisQty + newQty;
      finalCost = basisTotal > 0 ? (totalOldValue + totalNewValue) / basisTotal : newUnitCost;
      debugPrint('💾 DB_UPDATE: Using AVCO - New stock: $totalQty, New avg cost: $finalCost');
    } else {
      // Last Purchase Price - simply use the new unit cost
      finalCost = newUnitCost;
      debugPrint('💾 DB_UPDATE: Using Last Purchase Price - New stock: $totalQty, New cost: $finalCost');
    }

    // ✅ Also update unitCosts to keep in sync with cost_price
    // This is used by reports and invoice creation screens
    Map<String, dynamic> updatedUnitCosts = {};
    if (currentUnitCosts != null && currentUnitCosts.isNotEmpty) {
      try {
        updatedUnitCosts = Map<String, dynamic>.from(json.decode(currentUnitCosts));
      } catch (e) {
        debugPrint('💾 DB_UPDATE: Could not parse existing unitCosts: $e');
      }
    }
    
    // كلفة الوحدات الأكبر (كرتون…) تتبع الوحدة الأساسية بالنسبة نفسها؛ كانت تبقى
    // قديمة فيُكلَّف بيع الكرتون بكلفة ما قبل الشراء.
    if (currentCost > 0 && updatedUnitCosts.isNotEmpty) {
      final ratio = finalCost / currentCost;
      updatedUnitCosts = {
        for (final e in updatedUnitCosts.entries)
          e.key: e.value is num ? roundMoney((e.value as num).toDouble() * ratio) : e.value,
      };
    }

    // Update base unit cost in unitCosts
    String baseUnitKey = baseUnit == 'piece' ? 'قطعة' : (baseUnit == 'meter' ? 'متر' : baseUnit);
    updatedUnitCosts[baseUnitKey] = finalCost;
    
    // Encode back to JSON
    String unitCostsJson = json.encode(updatedUnitCosts);
    
    debugPrint('💾 DB_UPDATE: Updated unitCosts: $unitCostsJson');

    // أرباح ما بيع سابقاً لا تتغير بتغيّر الكلفة (بنود بلا كلفة محفوظة تُثبَّت أولاً)
    if ((finalCost - currentCost).abs() >= 0.005) {
      await UsdCostService.freezePastCosts(txn, {item.productId});
    }

    await txn.update(
      'products',
      {
        'cost_price': finalCost,
        'unit_costs': unitCostsJson,
      },
      where: 'id = ?',
      whereArgs: [item.productId],
    );

    // عملة الكلفة = عملة آخر شراء
    try {
      await UsdCostService.writeCurrency(txn, item.productId, currency: isUsd ? 'USD' : 'IQD', usd: finalUsd);
    } catch (e) {
      debugPrint('⚠️ تعذّر حفظ عملة الكلفة: $e');
    }

    // 📦 الكمية: حركة شراء في دفتر المخزون المشترك (تصل لكل الأجهزة؛ بيانات
    //    المورد نفسها تبقى محلية). كانت تُكتب رقماً مطلقاً على هذا الجهاز وحده.
    final productUuid = await StockLedger.productSyncUuidForId(txn, item.productId);
    if (productUuid != null) {
      final mv = await StockLedger.addMovement(txn,
          productSyncUuid: productUuid, delta: newQty, kind: 'purchase', note: 'فاتورة شراء');
      await PurchaseExt.stampWarehouse(txn, mv, warehouseId);
    }

    debugPrint('💾 DB_UPDATE: ✅ Product updated successfully!');
  }

  Future<void> _reverseProductStock(Transaction txn, PurchaseInvoiceItem item, {int? warehouseId}) async {
    final List<Map<String, dynamic>> products = await txn.query('products', where: 'id = ?', whereArgs: [item.productId]);
    if (products.isEmpty) return;
    
    // 📦 إلغاء أثر فاتورة شراء (تعديلها أو حذفها): حركة عكسية في الدفتر.
    //    لا حدّ عند الصفر — كان يجعل الكمية تتوقف على ترتيب العمليات.
    final productUuid = await StockLedger.productSyncUuidForId(txn, item.productId);
    if (productUuid == null) return;
    final mv = await StockLedger.addMovement(txn,
        productSyncUuid: productUuid,
        delta: -item.baseQuantity,
        kind: 'purchase_reverse',
        note: 'إلغاء/تعديل فاتورة شراء');
    await PurchaseExt.stampWarehouse(txn, mv, warehouseId);
  }

  // ⚠️ حُذفت هنا أربع دوال تراكمية:
  //   _updateSupplierDebtOnInvoice / _reverseSupplierDebtOnInvoice
  //   _updateSupplierInvoiceCount  / _updateSupplierPaymentCount
  //
  // الأوليان كانتا تزيدان وتنقصان `total_debt_iqd` مباشرةً بمبالغ يمرّرها
  // المستدعي من كائن قد يكون قديماً — نفس علّة «الحالة 2» التي ضاعفت ديون
  // العملاء. والأخريان عدّادان يزيدان بواحد ولا ينقصان أبداً.
  //
  // البديل: SupplierDebtReconciler — دين المورد = مجموع حركات دفتره،
  // والعدّادات تُحسب بالعدّ لا بالتراكم.

  /// كشف حساب المورد: حركاته مرتّبة زمنياً (دين موجب، دفعة سالبة).
  Future<List<Map<String, dynamic>>> getSupplierLedger(int supplierId) async {
    final db = await _db.database;
    // 🛡️ شبكة أمان: وفّق مساهمات الفواتير قبل العرض
    try {
      await db.transaction((txn) async {
        await SupplierDebtReconciler.reconcileSupplierLedger(txn, supplierId,
            reason: 'عرض كشف الحساب');
      });
    } catch (e) {
      debugPrint('⚠️ تعذّرت تسوية دفتر المورد قبل العرض: $e');
    }
    return db.query(
      'supplier_transactions',
      where: 'supplier_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [supplierId],
      orderBy: 'transaction_date DESC, id DESC',
    );
  }

  // --- Delegates ---
  Future<List<SupplierDelegate>> getDelegatesForSupplier(int supplierId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'supplier_delegates',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
    );
    return List.generate(maps.length, (i) => SupplierDelegate.fromMap(maps[i]));
  }

  Future<int> addDelegate(SupplierDelegate delegate) async {
    final db = await _db.database;
    final map = delegate.toMap();
    map.remove('id');
    final id = await db.insert('supplier_delegates', map);
    notifyListeners();
    return id;
  }

  // --- Payment Actions ---
  /// يسجّل سند دفع لمورد ويعيد معرّفه.
  Future<int> registerPayment(SupplierPayment payment) async {
    final db = await _db.database;
    await _ensurePaymentColumns(db);

    final newId = await db.transaction((txn) async {
      // 🛡️ الرقم يُحسب داخل المعاملة نفسها: حسابه قبلها كان يسمح بسندين بالرقم نفسه
      final mx = await txn.rawQuery(
          'SELECT MAX(CAST(receipt_number AS INTEGER)) AS max_num FROM supplier_payments');
      final receiptNumber = ((mx.first['max_num'] as num?)?.toInt() ?? 0) + 1;
      // 1. Insert Payment with receipt number
      final cols = await _ensurePaymentColumns(txn);
      final paymentMap = payment.toMap();
      paymentMap.remove('id');
      paymentMap['receipt_number'] = '$receiptNumber';
      // تعريف createTables يجعل payment_number إلزامياً (NOT NULL بلا قيمة افتراضية)
      if (cols.contains('payment_number')) paymentMap['payment_number'] = '$receiptNumber';
      // لا نكتب عموداً غير موجود في هذا المخطط
      paymentMap.removeWhere((k, _) => !cols.contains(k.toLowerCase()));
      final paymentId = await txn.insert('supplier_payments', paymentMap);

      // 2. 🛡️ تُسجَّل الدفعة كحركة في دفتر المورد، والرصيد يُشتق من مجموع
      //    الحركات. لا `clamp` هنا عمداً: الدفع الزائد كان يُمحى بصمت،
      //    والصحيح أن يصير رصيداً لنا عند المورد.
      await SupplierDebtReconciler.recordPayment(
        txn,
        paymentId: paymentId,
        supplierId: payment.supplierId,
        amount: payment.amount,
        currency: payment.currency,
        description: payment.notes == null || payment.notes!.isEmpty
            ? 'سند دفع رقم $receiptNumber'
            : 'سند دفع رقم $receiptNumber — ${payment.notes}',
        date: payment.date.toIso8601String(),
      );
      return paymentId;
    });

    notifyListeners();
    return newId;
  }

  // ═══════════════════════════ إلغاء سند دفع ═══════════════════════════

  /// يلغي سند دفع لمورد: يبقى في السجل «ملغى» (برقمه وسببه) ويُحذف أثره من
  /// دفتر المورد، فيعود الدين كما كان، ويحذف محرك الترحيل قيده تلقائياً.
  /// ممنوع داخل فترة مثبّتة، ولا يُلغى السند مرتين.
  Future<void> voidPayment(int paymentId, {String? reason}) async {
    final db = await _db.database;
    await _ensurePaymentColumns(db);
    final rows = await db.query('supplier_payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
    if (rows.isEmpty) throw SupplierActionBlocked('سند الدفع غير موجود');
    final row = rows.first;
    if (((row['is_void'] as num?)?.toInt() ?? 0) == 1) {
      throw SupplierActionBlocked('هذا السند ملغى مسبقاً');
    }
    final date = DateTime.tryParse('${row['date']}') ?? DateTime.now();
    await PeriodLock.assertOpen(date, db);
    final supplierId = row['supplier_id'] as int;
    await db.transaction((txn) async {
      await txn.update(
        'supplier_payments',
        {
          'is_void': 1,
          'void_reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
          'voided_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      // أثر السند في دفتر المورد (حذف منطقي يحفظه للتدقيق)
      var n = await txn.update('supplier_transactions', {'is_deleted': 1},
          where: 'transaction_uuid = ? AND COALESCE(is_deleted, 0) = 0',
          whereArgs: [SupplierDebtReconciler.paymentUuid(paymentId)]);
      if (n == 0) {
        try {
          n = await txn.update('supplier_transactions', {'is_deleted': 1},
              where: "payment_id = ? AND transaction_type = 'supplier_payment' AND COALESCE(is_deleted, 0) = 0",
              whereArgs: [paymentId]);
        } catch (_) {}
      }
      // 🛡️ بلا أثر في الدفتر = إلغاؤه لن يغيّر الرصيد؛ نتراجع بدل إلغاء شكلي صامت
      if (n == 0) {
        throw SupplierActionBlocked('لم يُعثر على أثر هذا السند في دفتر المورد، فلم يُلغَ (الرصيد لم يتغير)');
      }
      await SupplierDebtReconciler.rebuildSupplierBalances(txn, supplierId);
    });
    ActivityLog.log('إلغاء', 'دفعة لمورد',
        'إلغاء سند دفع رقم ${row['receipt_number'] ?? paymentId} للمورد #$supplierId — ${row['amount']} ${row['currency'] ?? ''}'
        '${(reason ?? '').trim().isEmpty ? '' : ' — السبب: ${reason!.trim()}'}');
    notifyListeners();
  }

  // ═══════════════════════════ الرصيد الافتتاحي ═══════════════════════════

  /// الرصيد الافتتاحي الحالي للمورد لكل عملة.
  Future<Map<String, double>> getOpeningBalances(int supplierId) async {
    final db = await _db.database;
    return {
      for (final c in const ['IQD', 'USD']) c: await SupplierDebtReconciler.openingBalance(db, supplierId, c),
    };
  }

  /// أقدم تاريخ حركة للمورد (اقتراح لتاريخ الرصيد الافتتاحي).
  Future<DateTime?> getFirstActivityDate(int supplierId) async {
    final db = await _db.database;
    final r = await db.rawQuery(
        'SELECT MIN(transaction_date) AS d FROM supplier_transactions WHERE supplier_id = ? AND COALESCE(is_deleted, 0) = 0',
        [supplierId]);
    final v = r.isEmpty ? null : r.first['d'];
    return v == null ? null : DateTime.tryParse('$v');
  }

  /// يضبط رصيد المورد الافتتاحي بعملة: موجب = له علينا، سالب = لنا عنده، صفر = إلغاء.
  /// يستبدل القيمة السابقة (لا يُراكم)، ويُرحَّل على «الأرصدة الافتتاحية».
  Future<void> setOpeningBalance(
    int supplierId, {
    required double amount,
    required String currency,
    required DateTime date,
    String? note,
  }) async {
    final db = await _db.database;
    await PeriodLock.assertOpen(date, db);
    final old = await db.query('supplier_transactions',
        columns: ['transaction_date'],
        where: 'transaction_uuid = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [SupplierDebtReconciler.openingUuid(supplierId, currency)],
        limit: 1);
    if (old.isNotEmpty) {
      final d = DateTime.tryParse('${old.first['transaction_date']}');
      if (d != null) await PeriodLock.assertOpen(d, db);
    }
    await db.transaction((txn) async {
      await SupplierDebtReconciler.setOpeningBalance(txn,
          supplierId: supplierId, amount: amount, currency: currency, date: date, description: note);
    });
    ActivityLog.log('تعديل', 'الموردون', 'رصيد افتتاحي للمورد #$supplierId: $amount $currency');
    notifyListeners();
  }

  // ═══════════════════════════ إلغاء فاتورة شراء ═══════════════════════════

  /// يلغي فاتورة شراء (مؤكدة أو مسودة): تُخرج كمياتها من المخزون إن كانت مؤكدة،
  /// وتصير «ملغاة» فيسقط دينها على المورد وقيدها من الدفتر. تبقى في السجل للمراجعة.
  /// ممنوع إن كان عليها مرتجعات مُرحَّلة أو كانت داخل فترة مثبّتة.
  Future<void> cancelPurchaseInvoice(int invoiceId, {String? reason}) async {
    final db = await _db.database;
    final rows = await db.query('purchase_invoices',
        columns: ['date', 'status', 'invoice_number', 'notes', 'total_amount', 'currency'],
        where: 'id = ?',
        whereArgs: [invoiceId],
        limit: 1);
    if (rows.isEmpty) throw SupplierActionBlocked('الفاتورة غير موجودة');
    final row = rows.first;
    final status = (row['status'] as String?) ?? 'draft';
    if (status == 'cancelled') throw SupplierActionBlocked('الفاتورة ملغاة مسبقاً');
    final date = DateTime.tryParse('${row['date']}') ?? DateTime.now();
    await PeriodLock.assertOpen(date, db);
    final why = (reason ?? '').trim();
    await db.transaction((txn) async {
      await _assertReturnsAllow(txn, invoiceId, keepsConfirmed: false);
      if (status == 'confirmed') {
        final ext = await PurchaseExt.read(txn, invoiceId);
        final items = await txn.query('purchase_invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
        for (final m in items) {
          await _reverseProductStock(txn, PurchaseInvoiceItem.fromMap(m), warehouseId: ext.warehouseId);
        }
      }
      final oldNotes = ((row['notes'] as String?) ?? '').trim();
      await txn.update(
        'purchase_invoices',
        {
          'status': 'cancelled',
          'notes': [if (oldNotes.isNotEmpty) oldNotes, why.isEmpty ? '[ملغاة]' : '[ملغاة: $why]'].join(' '),
          'last_modified_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
      await SupplierDebtReconciler.reconcileInvoice(txn, invoiceId, reason: 'إلغاء');
    });
    ActivityLog.log('إلغاء', 'فواتير الشراء',
        'إلغاء فاتورة شراء ${row['invoice_number']} — ${row['total_amount']} ${row['currency'] ?? ''}${why.isEmpty ? '' : ' — $why'}');
    notifyListeners();
  }

  /// 🛡️ مرتجعات مُرحَّلة على فاتورة شراء: لا تُلغى الفاتورة ولا تصير مسودة،
  /// ولا تُنقص كمية مادة تحت ما أُرجع منها — وإلا خرجت البضاعة المرتجعة من
  /// المخزون مرتين وصار للمورد رصيد دائن بلا أساس.
  static Future<void> _assertReturnsAllow(
    DatabaseExecutor d,
    int invoiceId, {
    required bool keepsConfirmed,
    List<PurchaseInvoiceItem>? newItems,
  }) async {
    if (!await _tableExists(d, 'purchase_returns') || !await _tableExists(d, 'purchase_return_items')) return;
    final ret = await d.rawQuery('''
      SELECT i.product_id AS pid, SUM(i.base_qty) AS q
      FROM purchase_return_items i JOIN purchase_returns r ON r.id = i.return_id
      WHERE r.original_invoice_id = ? AND r.status = 'posted' GROUP BY i.product_id''', [invoiceId]);
    if (ret.isEmpty) return;
    if (!keepsConfirmed) {
      throw SupplierActionBlocked(
          'على هذه الفاتورة مرتجعات مشتريات مُرحَّلة — ألغِ المرتجعات أولاً من «سجل مرتجعات المشتريات» ثم أعد المحاولة');
    }
    final newQty = <int, double>{};
    for (final it in newItems ?? const <PurchaseInvoiceItem>[]) {
      newQty[it.productId] = (newQty[it.productId] ?? 0) + it.baseQuantity;
    }
    for (final r in ret) {
      final pid = r['pid'] as int;
      final q = (r['q'] as num?)?.toDouble() ?? 0;
      if ((newQty[pid] ?? 0) + 1e-6 < q) {
        throw SupplierActionBlocked(
            'لا يمكن إنقاص كمية مادة في الفاتورة تحت ما أُرجع منها (${q.toStringAsFixed(q == q.roundToDouble() ? 0 : 2)}) — ألغِ المرتجع أولاً');
      }
    }
  }

  // ═══════════════════════════ سجل فواتير الشراء ═══════════════════════════

  /// فواتير الشراء لكل الموردين (للسجل العام) مع اسم المورد.
  Future<List<Map<String, Object?>>> getAllPurchaseInvoices({DateTime? from, DateTime? to}) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('p.date >= ?');
      args.add(DateTime(from.year, from.month, from.day).toIso8601String());
    }
    if (to != null) {
      where.add('p.date < ?');
      args.add(DateTime(to.year, to.month, to.day).add(const Duration(days: 1)).toIso8601String());
    }
    return db.rawQuery('''
      SELECT p.*, s.name AS supplier_name
      FROM purchase_invoices p LEFT JOIN suppliers s ON s.id = p.supplier_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY p.date DESC, p.id DESC
      LIMIT 5000''', args);
  }

  // ═══════════════════════════ المندوبون ═══════════════════════════

  /// سبب منع حذف مندوب (فواتير مرتبطة به)، أو null.
  Future<String?> delegateDeleteBlocker(int delegateId) async {
    final db = await _db.database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM purchase_invoices WHERE delegate_id = ?', [delegateId]);
    final n = (r.first['c'] as num?)?.toInt() ?? 0;
    return n == 0 ? null : 'المندوب مرتبط بـ $n فاتورة شراء — عدّل اسمه بدلاً من حذفه';
  }
}

/// يُرمى عند منع عملية على مورد أو مستنداته؛ [message] جاهزة للعرض.
class SupplierActionBlocked implements Exception {
  SupplierActionBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}


/// يُرمى عند محاولة حذف مورد له أثر مالي؛ [message] جاهزة للعرض.
class SupplierDeleteBlocked implements Exception {
  SupplierDeleteBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 🏬 امتداد فاتورة الشراء (مثل سهل): المخزن المستلم والصندوق/البنك المدفوع منه.
/// جدول محلي `purchase_invoice_ext`؛ الفاتورة نفسها ودين المورد لا يتغيران.
class PurchaseExt {
  PurchaseExt(this.warehouseId, this.cashBoxId);
  final int? warehouseId;
  final int? cashBoxId;

  static Future<void> _ensure(DatabaseExecutor d) => d.execute('''
    CREATE TABLE IF NOT EXISTS purchase_invoice_ext (
      invoice_id INTEGER PRIMARY KEY,
      warehouse_id INTEGER,
      cash_box_id INTEGER
    )''');

  static Future<PurchaseExt> read(DatabaseExecutor d, int invoiceId) async {
    await _ensure(d);
    final r = await d.query('purchase_invoice_ext', where: 'invoice_id = ?', whereArgs: [invoiceId], limit: 1);
    if (r.isEmpty) return PurchaseExt(null, null);
    return PurchaseExt(r.first['warehouse_id'] as int?, r.first['cash_box_id'] as int?);
  }

  static Future<void> write(DatabaseExecutor d, int invoiceId, {int? warehouseId, int? cashBoxId}) async {
    await _ensure(d);
    if (warehouseId == null && cashBoxId == null) {
      await d.delete('purchase_invoice_ext', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      return;
    }
    await d.insert('purchase_invoice_ext', {'invoice_id': invoiceId, 'warehouse_id': warehouseId, 'cash_box_id': cashBoxId},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// يربط حركة المخزون بمخزن غير الرئيسي (الرئيسي = الكلي − غيره فلا يُختم).
  static Future<void> stampWarehouse(DatabaseExecutor d, String? movementUuid, int? warehouseId) async {
    if (movementUuid == null || warehouseId == null) return;
    final main = await d.query('warehouses', columns: ['id'], where: 'is_default = 1', orderBy: 'id', limit: 1);
    final mainId = main.isEmpty ? 1 : main.first['id'] as int;
    if (warehouseId == mainId) return;
    await d.update('stock_movements', {'warehouse_id': warehouseId},
        where: 'movement_uuid = ?', whereArgs: [movementUuid]);
  }
}
