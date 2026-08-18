// lib/services/database/dao/customer_dao.dart
// عمليات CRUD للعملاء

import 'package:sqflite/sqflite.dart';
import '../../../models/customer.dart';
import '../core/database_helpers.dart';

/// DAO للعملاء - عمليات CRUD الأساسية
class CustomerDao {
  final Future<Database> Function() getDatabase;

  CustomerDao({required this.getDatabase});

  /// إضافة عميل جديد
  /// ═══════════════════════════════════════════════════════════════════
  /// 🔒 Atomic Customer Creation (Multi-Session Safe)
  /// ═══════════════════════════════════════════════════════════════════
  Future<int> insertCustomer(Customer customer) async {
    final db = await getDatabase();
    
    return await db.transaction((txn) async {
      // إدراج العميل أولاً
      final customerId = await txn.insert('customers', customer.toMap());
      
      // إذا كان هناك دين مبدئي، أضف معاملة تلقائية
      if (customer.currentTotalDebt > 0) {
        final now = DateTime.now();
        await txn.insert('transactions', {
          'customer_id': customerId,
          'transaction_date': now.toIso8601String(),
          'amount_changed': customer.currentTotalDebt,
          'new_balance_after_transaction': customer.currentTotalDebt,
          'transaction_note': 'الدين المبدئي عند إضافة العميل',
          'transaction_type': 'opening_balance',
          'description': 'رصيد افتتاحي',
          'created_at': now.toIso8601String(),
          'invoice_id': null,
        });
        
        print('✅ تم إضافة معاملة الدين المبدئي: ${customer.currentTotalDebt} دينار للعميل: ${customer.name}');
      }
      
      return customerId;
    });
  }

  /// جلب جميع العملاء
  Future<List<Customer>> getAllCustomers({String orderBy = 'name ASC'}) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps =
          await db.query('customers', orderBy: orderBy);
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting all customers: $e');
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
      final String searchCondition = searchQuery.isNotEmpty 
          ? " AND (c.name LIKE ? OR c.phone LIKE ? OR c.address LIKE ?) " 
          : "";
      
      // تحديد فلتر الجهاز بناءً على المصدر
      String deviceFilter = "";
      if (reportSource == 'this_device') {
        deviceFilter = " AND i.is_created_by_me = 1 ";
      } else if (reportSource == 'sync') {
        deviceFilter = " AND i.is_created_by_me = 0 ";
      }

      final List<dynamic> args = [];
      if (searchQuery.isNotEmpty) {
        final likeQuery = '%$searchQuery%';
        args.addAll([likeQuery, likeQuery, likeQuery]);
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
        WHERE 1=1 $searchCondition
        ORDER BY total_sales_for_sort DESC, c.name ASC
        LIMIT ? OFFSET ?
      ''', args);
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting paginated customers: $e');
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
        WHERE EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = c.id LIMIT 1)
        ORDER BY ${orderBy.replaceAll("'", "")}
      ''');
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting customers for debt register: $e');
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
      String whereClause = '''
        EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = c.id LIMIT 1)
      ''';

      // بحث في SQL على الاسم والهاتف (بدل فلترة الذاكرة)
      if (searchQuery.isNotEmpty) {
        whereClause += ' AND (c.name LIKE ? OR COALESCE(c.phone, "") LIKE ?)';
        final sq = '%$searchQuery%';
        args.add(sq);
        args.add(sq);
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
      print('Error getting paginated customers for debt register: $e');
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
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id LIMIT 1)
        GROUP BY c.id
        ORDER BY last_debt_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      print('Error getting customers sorted by last debt added: $e');
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
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id LIMIT 1)
        GROUP BY c.id
        ORDER BY last_payment_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      print('Error getting customers sorted by last payment: $e');
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
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id LIMIT 1)
        GROUP BY c.id
        ORDER BY last_transaction_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      print('Error getting customers sorted by last transaction: $e');
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
      print('Error getting customer by ID $id: $e');
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
    return null;
  }

  /// تحديث عميل
  Future<int> updateCustomer(Customer customer) async {
    final db = await getDatabase();
    
    // 🔄 تتبع المزامنة: جلب البيانات القديمة قبل التحديث
    Map<String, dynamic>? oldData;
    String? syncUuid;
    try {
      final oldRows = await db.query('customers', where: 'id = ?', whereArgs: [customer.id], limit: 1);
      if (oldRows.isNotEmpty) {
        oldData = oldRows.first;
        syncUuid = oldData['sync_uuid'] as String?;
      }
    } catch (e) {
      print('⚠️ تحذير: فشل جلب بيانات العميل القديمة: $e');
    }
    
    final result = await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    
    return result;
  }

  /// حذف عميل
  Future<int> deleteCustomer(int id) async {
    final db = await getDatabase();
    try {
      // حذف المعاملات المرتبطة بالعميل يدوياً (لضمان الحذف حتى لو CASCADE لم يعمل)
      await db.delete(
        'transactions',
        where: 'customer_id = ?',
        whereArgs: [id],
      );
      
      // حذف سندات القبض المرتبطة بالعميل
      await db.delete(
        'customer_receipt_vouchers',
        where: 'customer_id = ?',
        whereArgs: [id],
      );
      
      // حذف العميل
      final result = await db.delete(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
      );
      
      return result;
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// بحث العملاء
  Future<List<Customer>> searchCustomers(String query) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'customers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'name ASC',
      );
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// البحث عن عميل بالاسم المطبع
  Future<Customer?> findCustomerByNormalizedName(String name, {String? phone}) async {
    final db = await getDatabase();
    final normalizedQuery = DatabaseHelpers.normalizeArabic(name.trim());
    
    try {
      List<Map<String, dynamic>> results;
      
      if (phone != null && phone.isNotEmpty) {
        results = await db.rawQuery('''
          SELECT * FROM customers 
          WHERE (name = ? OR name = ?)
            AND (phone = ? OR phone IS NULL OR phone = '')
          LIMIT 1
        ''', [name.trim(), normalizedQuery, phone]);
      } else {
        results = await db.rawQuery('''
          SELECT * FROM customers 
          WHERE name = ? OR name = ?
          LIMIT 1
        ''', [name.trim(), normalizedQuery]);
      }
      
      if (results.isNotEmpty) {
        return Customer.fromMap(results.first);
      }
      return null;
    } catch (e) {
      print('Error finding customer by normalized name: $e');
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
      print('Error getting customer balance from view: $e');
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
        WHERE last_modified_at LIKE '$todayString%'
        ORDER BY last_modified_at DESC
      ''');
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting customers modified today: $e');
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
        WHERE t.transaction_date >= ? AND t.transaction_date <= ?
        ORDER BY c.name ASC
      ''', [startDate, endDate]);
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting customers for month: $e');
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
        WHERE c.current_total_debt > 0
          AND c.last_modified_at < ?
        ORDER BY c.current_total_debt DESC
      ''', [cutoffDate.toIso8601String()]);
      
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting late customers: $e');
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
      print('Error getting customer by ID in transaction: $e');
    }
    return null;
  }
}
