// lib/services/database/dao/customer_dao.dart
// عمليات CRUD للعملاء

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import '../../../models/customer.dart';
import '../core/database_helpers.dart';
import '../business/customer_name_rule.dart';
import '../../name_search.dart'; // 🔤 الأسماء بلا مسافات
import '../business/tx_author.dart';
import '../../../utils/iqd.dart'; // 💵
import '../../../services/firebase_sync/uuid_helper.dart';
import '../../../services/sync/sync_security.dart';
import '../business/customer_owner_rule.dart';

/// DAO للعملاء - عمليات CRUD الأساسية
class CustomerDao {
  final Future<Database> Function() getDatabase;

  CustomerDao({required this.getDatabase});

  /// 🆔 توليد sync_uuid فريد للعميل (نفس نمط الإصلاح الشامل)
  static String newCustomerUuid() =>
      UuidHelper.sanitizeId('cust_${SyncSecurity.generateUuid()}');

  /// إضافة عميل جديد
  /// ═══════════════════════════════════════════════════════════════════
  /// 🔒 Atomic Customer Creation (Multi-Session Safe)
  /// ═══════════════════════════════════════════════════════════════════
  Future<int> insertCustomer(Customer customer, {DateTime? openingDate}) async {
    final db = await getDatabase();
    return await db.transaction((txn) => insertCustomerIn(txn, customer, openingDate: openingDate));
  }

  /// نفس [insertCustomer] داخل معاملة قائمة — يستعمله الاستيراد من Excel ليضيف
  /// كل العملاء في معاملة واحدة (كلهم أو لا أحد). [openingDate] تاريخ الرصيد
  /// الافتتاحي (الافتراضي: الآن). الرصيد السالب (له علينا) يُسجَّل أيضاً.
  /// [openingNote] ملاحظة معاملة الرصيد (الاستيراد: الملف والصف ومن قام به)،
  /// و[openingUuid] معرّفها الثابت (يمنع تكرار استيراد الملف نفسه).
  static Future<int> insertCustomerIn(Transaction txn, Customer customer,
      {DateTime? openingDate, String? openingNote, String? openingUuid}) async {
    {
      // 🛡️ سجل الديون: لا حسابان بالاسم نفسه (بتجاهل المسافات)
      await CustomerNameRule.ensureAvailable(txn, customer.name);

      // 🆔 هوية مزامنة فورية للعميل الجديد:
      // بدونها يبقى sync_uuid فارغاً فلا يراه أي مسار رفع أبداً
      // (كان هذا سبب عدم وصول العملاء الجدد للأجهزة الأخرى).
      final customerMap = customer.toMap();
      // 💵 الرصيد الافتتاحي دينار صحيح، والنصف لصالح المحل (نحو +∞)
      final opening = Iqd.up(customer.currentTotalDebt);
      customerMap['current_total_debt'] = opening;
      customerMap['current_total_debt_cents'] = (opening * 100).round();
      if ((customerMap['sync_uuid'] as String?)?.isEmpty != false) {
        customerMap['sync_uuid'] = newCustomerUuid();
      }
      // 🏷️ هذا الجهاز هو المنشئ — شرط ملكية الرفع
      customerMap['is_created_by_me'] = 1;

      // 🛡️ التحقق من وجود عميل محذوف سابقاً بنفس الاسم ورقم الهاتف لإعادة تنشيطه بدلاً من تضارب القيد الفريد
      final normalizedQuery = DatabaseHelpers.normalizeArabic(customer.name.trim());
      final existingRows = await txn.rawQuery('''
        SELECT * FROM customers
        WHERE (name = ? OR name = ?)
          AND (phone = ? OR (phone IS NULL AND ? IS NULL))
        LIMIT 1
      ''', [customer.name.trim(), normalizedQuery, customer.phone, customer.phone]);

      int customerId;
      if (existingRows.isNotEmpty) {
        final existingId = existingRows.first['id'] as int;
        final isDeleted = ((existingRows.first['is_deleted'] as int?) ?? 0) == 1;
        if (isDeleted) {
          // إعادة تنشيط العميل المحذوف وتحديث بياناته (مع الحفاظ على هويته الأصلية)
          final oldSyncUuid = existingRows.first['sync_uuid'] as String?;
          final updatedCustomer = customer.copyWith(
            id: existingId,
            isDeleted: false,
            lastModifiedAt: DateTime.now(),
            syncUuid: oldSyncUuid ?? (customerMap['sync_uuid'] as String),
          );
          final updateMap = updatedCustomer.toMap();
          updateMap['current_total_debt'] = opening; // 💵
          updateMap['current_total_debt_cents'] = (opening * 100).round();
          updateMap['is_created_by_me'] = existingRows.first['is_created_by_me'];
          updateMap['last_modified_at'] = DateTime.now().toIso8601String();
          // 🛡️ إعادة تنشيط صريحة: تُرفع isDeleted=false مرة واحدة لتلغي شاهد الحذف
          final prevTomb = (existingRows.first['tombstoned'] as int?) ?? 0;
          updateMap['tombstoned'] = (prevTomb == 1 || prevTomb == 2) ? 3 : 0;
          await txn.update(
            'customers',
            updateMap,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          customerId = existingId;
        } else {
          customerId = await txn.insert('customers', customerMap);
        }
      } else {
        customerId = await txn.insert('customers', customerMap);
      }

      // إذا كان هناك رصيد مبدئي، أضف معاملة تلقائية (موجب = عليه، سالب = له)
      // كان الشرط «> 0»: رصيد سالب يُكتب في بطاقة العميل بلا معاملة تسنده.
      if (opening.abs() > 0.0005) {
        final now = openingDate ?? DateTime.now();
        final txUuid = openingUuid ?? UuidHelper.newTransactionUuid();
        await txn.insert('transactions', await TxAuthor.stamped(txn, {
          'customer_id': customerId,
          'transaction_uuid': txUuid, // 🆔 هوية فورية — لا ننتظر backfill الإقلاع
          'sync_uuid': txUuid,
          'transaction_date': now.toIso8601String(),
          'amount_changed': opening,
          'new_balance_after_transaction': opening,
          'transaction_note': openingNote ?? 'الدين المبدئي عند إضافة العميل',
          'transaction_type': 'opening_balance',
          'description': 'رصيد افتتاحي',
          'created_at': DateTime.now().toIso8601String(), // وقت الإدخال الفعلي (التاريخ أعلاه قد يكون سابقاً)
          'invoice_id': null,
          'is_deleted': 0,
          'is_created_by_me': 1, // 🏷️ ملكية الرفع لهذا الجهاز
          'is_uploaded': 0,
        }));

        debugPrint('✅ تم إضافة معاملة الدين المبدئي: $opening دينار للعميل: ${customer.name}');
      }

      return customerId;
    }
  }

  /// جلب جميع العملاء النشطين
  Future<List<Customer>> getAllCustomers({String orderBy = 'name ASC'}) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps =
          await db.query(
            'customers',
            where: 'is_deleted IS NULL OR is_deleted = 0',
            orderBy: orderBy,
          );
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      debugPrint('Error getting all customers: $e');
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب العملاء لتقارير الأشخاص مع دعم التحميل التدريجي (Pagination) والبحث والترتيب حسب المبيعات
  /// reportSource: 'all' = الكل, 'this_device' = هذا الجهاز فقط, 'sync' = المزامنة فقط
  Future<List<Customer>> getPaginatedCustomersForReports({
    required int limit,
    required int offset,
    String searchQuery = '',
    String reportSource = 'all',
  }) async {
    final db = await getDatabase();
    try {
      final nameQ = NameSearch.where('c.name', searchQuery, phoneCol: 'c.phone');
      final String searchCondition = nameQ != null ? " AND (${nameQ.sql} OR c.address LIKE ?) " : "";
      
      // تحديد فلتر الجهاز بناءً على المصدر
      String deviceFilter = "";
      if (reportSource == 'this_device') {
        deviceFilter = " AND i.is_created_by_me = 1 ";
      } else if (reportSource == 'sync') {
        deviceFilter = " AND i.is_created_by_me = 0 ";
      }

      final List<dynamic> args = [];
      if (nameQ != null) {
        args.addAll(nameQ.args);
        args.add('%${searchQuery.trim()}%');
      }
      args.addAll([limit, offset]);

      // نقوم بجلب العملاء وترتيبهم حسب إجمالي المبيعات باستخدام COALESCE و LEFT JOIN
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.*, 
          COALESCE((
            SELECT SUM(i.total_amount) 
            FROM invoices i 
            WHERE (i.customer_id = c.id OR ((i.customer_id IS NULL OR i.customer_id = 0) AND i.customer_name = c.name)) AND i.status = 'محفوظة' $deviceFilter
          ), 0) as total_sales_for_sort
        FROM customers c
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0) $searchCondition
        ORDER BY total_sales_for_sort DESC, c.name ASC
        LIMIT ? OFFSET ?
      ''', args);
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      debugPrint('Error getting paginated customers: $e');
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب العملاء لسجل الديون
  Future<List<Customer>> getCustomersForDebtRegister({String orderBy = 'name ASC'}) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.*
        FROM customers c
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          AND (COALESCE(c.current_total_debt, 0) != 0 OR EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0) LIMIT 1))
        ORDER BY ${orderBy.replaceAll("'", "")}
      ''');
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      debugPrint('Error getting customers for debt register: $e');
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// 📄 جلب العملاء لسجل الديون بشكل صفحات (Pagination) مع بحث في SQL.
  /// هذا يحل مشكلة بطء التحميل عند وجود آلاف العملاء (بدل تحميل الكل دفعة واحدة).
  ///
  /// [limit] حجم الصفحة، [offset] موضع البداية، [searchQuery] بحث في الاسم والهاتف.
  Future<List<Customer>> getCustomersForDebtRegisterPaginated({
    required int limit,
    required int offset,
    String searchQuery = '',
    String orderBy = 'name ASC',
  }) async {
    final db = await getDatabase();
    try {
      final List<dynamic> args = [];
      String whereClause = '(c.is_deleted IS NULL OR c.is_deleted = 0)';

      final trimmedQuery = searchQuery.trim();
      if (trimmedQuery.isEmpty) {
        whereClause += '''
          AND (COALESCE(c.current_total_debt, 0) != 0 OR EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0) LIMIT 1))
        ''';
      } else {
        // 🔎 الفواصل لا قيمة لها: «جهاد عبد» = «جهادعبد» = «جهاد     عبد» = «جهاد-عبد»
        // (كل كلمة في الاسم بأي ترتيب، والاسم يُقارن بلا فواصل)، والهاتف بلا مسافات.
        final nameQ = NameSearch.where('c.name', trimmedQuery, phoneCol: 'c.phone');
        if (nameQ != null) {
          whereClause += ' AND ${nameQ.sql}';
          args.addAll(nameQ.args);
        }
      }

      final safeOrderBy = orderBy.replaceAll("'", "");
      args.add(limit);
      args.add(offset);

      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.*
        FROM customers c
        WHERE $whereClause
        ORDER BY $safeOrderBy
        LIMIT ? OFFSET ?
      ''', args);
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      debugPrint('Error getting paginated customers for debt register: $e');
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// ترتيب العملاء حسب آخر إضافة دين
  Future<List<int>> getCustomerIdsSortedByLastDebtAdded() async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.id, MAX(t.transaction_date) as last_debt_date
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id 
          AND t.transaction_type IN ('manual_debt', 'DEBT_ADDITION', 'debt_addition')
          AND (t.is_deleted IS NULL OR t.is_deleted = 0)
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          AND (c.current_total_debt > 0 OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id AND (t2.is_deleted IS NULL OR t2.is_deleted = 0) LIMIT 1))
        GROUP BY c.id
        ORDER BY last_debt_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      debugPrint('Error getting customers sorted by last debt added: $e');
      return [];
    }
  }

  /// ترتيب العملاء حسب آخر تسديد
  Future<List<int>> getCustomerIdsSortedByLastPayment() async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.id, MAX(t.transaction_date) as last_payment_date
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id 
          AND t.transaction_type IN ('debt_payment', 'DEBT_PAYMENT')
          AND (t.is_deleted IS NULL OR t.is_deleted = 0)
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          AND (c.current_total_debt > 0 OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id AND (t2.is_deleted IS NULL OR t2.is_deleted = 0) LIMIT 1))
        GROUP BY c.id
        ORDER BY last_payment_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      debugPrint('Error getting customers sorted by last payment: $e');
      return [];
    }
  }

  /// ترتيب العملاء حسب آخر معاملة
  Future<List<int>> getCustomerIdsSortedByLastTransaction() async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.id, MAX(t.transaction_date) as last_transaction_date
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id
          AND (t.is_deleted IS NULL OR t.is_deleted = 0)
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          AND (c.current_total_debt > 0 OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id AND (t2.is_deleted IS NULL OR t2.is_deleted = 0) LIMIT 1))
        GROUP BY c.id
        ORDER BY last_transaction_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      debugPrint('Error getting customers sorted by last transaction: $e');
      return [];
    }
  }

  /// جلب عميل بالمعرف
  Future<Customer?> getCustomerById(int id) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return Customer.fromMap(maps.first);
      }
    } catch (e) {
      debugPrint('Error getting customer by ID $id: $e');
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
    return null;
  }

  /// تحديث عميل.
  ///
  /// 🛡️ [updateBalance] افتراضياً `false`: لا تُكتب أعمدة الرصيد
  /// (`current_total_debt`) من الكائن الممرَّر، لأنه قد يكون نسخة قديمة من
  /// الذاكرة فيُعيد رصيد العميل إلى الخلف. الرصيد ملك لمنظومة المعاملات وحدها
  /// ([InvoiceDebtReconciler] و[TransactionDao])، ولا يُكتب من هنا إلا بطلب
  /// صريح كزر «اعتمد المجموع» أو الإصلاح المتعمَّد.
  Future<int> updateCustomer(Customer customer, {bool updateBalance = false}) async {
    final db = await getDatabase();

    // 🛡️ تغيير الاسم إلى اسم حساب آخر مرفوض (لا حسابان بالاسم نفسه)
    if (customer.id != null) {
      final current = await db.query('customers',
          columns: ['name', 'is_created_by_me'], where: 'id = ?', whereArgs: [customer.id], limit: 1);
      final oldName = current.isEmpty ? null : current.first['name'] as String?;
      if (oldName == null || CustomerNameRule.key(oldName) != CustomerNameRule.key(customer.name)) {
        // 🔐 الاسم يغيّره الجهاز الذي أنشأ العميل فقط (customer_owner_rule.dart)
        if (oldName != null && !CustomerOwnerRule.isMine(current.first['is_created_by_me'])) {
          throw CustomerRenameNotOwnedException(oldName);
        }
        await CustomerNameRule.ensureAvailable(db, customer.name, excludeId: customer.id);
      }
    }
    
    final Map<String, dynamic> values = customer.toMap();
    if (!updateBalance) {
      values.remove('current_total_debt');
      values.remove('current_total_debt_cents');
    }

    final result = await db.update(
      'customers',
      values,
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    
    return result;
  }

  /// حذف عميل منطقياً (Soft Delete) مع حفظ الفواتير وحجب العميل ومعاملاته النشطة
  Future<int> deleteCustomer(int id) async {
    final db = await getDatabase();
    final now = DateTime.now().toIso8601String();
    try {
      return await db.transaction((txn) async {
        // 1) وضع علامة الحذف على المعاملات المرتبطة بالعميل (Soft Delete)
        // is_uploaded = 0 لكل معاملة (حتى معاملات الأجهزة الأخرى): محرك
        // المزامنة يرفع لكل واحدة «شاهد حذف» فيُبطلها كل جهاز كما أُبطلت هنا.
        await txn.update(
          'transactions',
          {
            'is_deleted': 1,
            'is_uploaded': 0,
            'restored_mark': 0,
          },
          where: 'customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
          whereArgs: [id],
        );

        // 2) وضع علامة الحذف على العميل (Soft Delete) وتصفير رصيد الدين
        //    tombstoned = 2: حذف محلي بانتظار رفع شاهده إلى السحابة.
        final result = await txn.update(
          'customers',
          {
            'is_deleted': 1,
            'tombstoned': 2,
            'current_total_debt': 0.0,
            'current_total_debt_cents': 0,
            'last_modified_at': now,
            'sync_last_update_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        
        return result;
      });
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// بحث العملاء النشطين
  Future<List<Customer>> searchCustomers(String query) async {
    final db = await getDatabase();
    try {
      // 🔤 «ابراهيممحمد» و«إبراهيم    محمد» يجدان «إبراهيم محمد العسكر»؛ المطابق تماماً أولاً
      final w = NameSearch.where('name', query, phoneCol: 'phone');
      if (w == null) return [];
      final o = NameSearch.order('name', query);
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        'SELECT * FROM customers WHERE ${w.sql} AND (is_deleted IS NULL OR is_deleted = 0) ORDER BY ${o.sql}',
        [...w.args, ...o.args],
      );
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// البحث عن عميل نشط بالاسم المطبع
  Future<Customer?> findCustomerByNormalizedName(String name, {String? phone}) async {
    final db = await getDatabase();
    final normalizedQuery = DatabaseHelpers.normalizeArabic(name.trim());
    
    try {
      // 🛡️ نفس قاعدة حفظ الفاتورة: الاسم بلا مسافات يحدد الحساب (الهاتف لا يفرّق)
      final active = await CustomerNameRule.findActive(db, name.trim());
      if (active != null) return Customer.fromMap(active);

      List<Map<String, dynamic>> results;
      
      if (phone != null && phone.isNotEmpty) {
        results = await db.rawQuery('''
          SELECT * FROM customers 
          WHERE (name = ? OR name = ?)
            AND (phone = ? OR phone IS NULL OR phone = '')
            AND (is_deleted IS NULL OR is_deleted = 0)
          LIMIT 1
        ''', [name.trim(), normalizedQuery, phone]);
      } else {
        results = await db.rawQuery('''
          SELECT * FROM customers 
          WHERE (name = ? OR name = ?)
            AND (is_deleted IS NULL OR is_deleted = 0)
          LIMIT 1
        ''', [name.trim(), normalizedQuery]);
      }
      
      if (results.isNotEmpty) {
        return Customer.fromMap(results.first);
      }
      return null;
    } catch (e) {
      debugPrint('Error finding customer by normalized name: $e');
      return null;
    }
  }

  /// 📊 3NF: استعلام رصيد العميل المحسوب ديناميكياً من customer_balances_view كمرجع موثوق 100%
  Future<double> getCustomerBalanceFromView(int customerId) async {
    final db = await getDatabase();
    try {
      final res = await db.rawQuery(
        'SELECT calculated_total_debt FROM customer_balances_view WHERE customer_id = ?',
        [customerId],
      );
      if (res.isNotEmpty && res.first['calculated_total_debt'] != null) {
        return (res.first['calculated_total_debt'] as num).toDouble();
      }
      return 0.0;
    } catch (e) {
      debugPrint('Error getting customer balance from view: $e');
      return 0.0;
    }
  }

  /// جلب العملاء المُعدّلين اليوم
  Future<List<Customer>> getCustomersModifiedToday() async {
    final db = await getDatabase();
    try {
      final today = DateTime.now();
      final todayString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT * FROM customers 
        WHERE (is_deleted IS NULL OR is_deleted = 0)
          AND last_modified_at LIKE '$todayString%'
        ORDER BY last_modified_at DESC
      ''');
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      debugPrint('Error getting customers modified today: $e');
      return [];
    }
  }

  /// جلب العملاء لشهر معين
  Future<List<Customer>> getCustomersForMonth(int year, int month) async {
    final db = await getDatabase();
    try {
      final monthString = month.toString().padLeft(2, '0');
      final startDate = '$year-$monthString-01';
      final endDate = '$year-$monthString-31';
      
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT DISTINCT c.* FROM customers c
        INNER JOIN transactions t ON t.customer_id = c.id
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          AND t.transaction_date >= ? AND t.transaction_date <= ?
        ORDER BY c.name ASC
      ''', [startDate, endDate]);
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      debugPrint('Error getting customers for month: $e');
      return [];
    }
  }

  /// جلب العملاء المتأخرين
  Future<List<Customer>> getLateCustomers(int months) async {
    final db = await getDatabase();
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: months * 30));
      
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.* FROM customers c
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          AND c.current_total_debt > 0
          AND c.last_modified_at < ?
        ORDER BY c.current_total_debt DESC
      ''', [cutoffDate.toIso8601String()]);
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      debugPrint('Error getting late customers: $e');
      return [];
    }
  }

  /// جلب عميل بالمعرف باستخدام Transaction
  Future<Customer?> getCustomerByIdUsingTransaction(DatabaseExecutor txn, int id) async {
    try {
      final List<Map<String, dynamic>> maps = await txn.query(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return Customer.fromMap(maps.first);
      }
    } catch (e) {
      debugPrint('Error getting customer by ID in transaction: $e');
    }
    return null;
  }
}
