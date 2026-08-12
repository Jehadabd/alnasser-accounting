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

  /// جلب العملاء لسجل الديون
  Future<List<Customer>> getCustomersForDebtRegister({String orderBy = 'name ASC'}) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.*
        FROM customers c
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = c.id LIMIT 1)
        ORDER BY ${orderBy.replaceAll("'", "")}
      ''');
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting customers for debt register: $e');
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
