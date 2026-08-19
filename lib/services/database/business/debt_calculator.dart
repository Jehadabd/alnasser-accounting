// lib/services/database/business/debt_calculator.dart
// حسابات الديون

import 'package:sqflite/sqflite.dart';
import '../../../utils/money_calculator.dart';

/// خدمة حساب الديون
class DebtCalculator {
  final Future<Database> Function() getDatabase;

  DebtCalculator({required this.getDatabase});

  /// حساب إجمالي الديون لجميع العملاء
  Future<double> getTotalDebt() async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(current_total_debt), 0) as total 
        FROM customers 
        WHERE current_total_debt > 0
          AND (is_deleted IS NULL OR is_deleted = 0)
      ''');
      return ((result.first['total'] as num?) ?? 0).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  /// حساب عدد العملاء المدينين
  Future<int> getDebtorsCount() async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COUNT(1) as count FROM customers 
        WHERE current_total_debt > 0
          AND (is_deleted IS NULL OR is_deleted = 0)
      ''');
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// جلب العملاء المدينين مرتبين حسب المبلغ
  Future<List<Map<String, dynamic>>> getTopDebtors({int limit = 10}) async {
    final db = await getDatabase();
    try {
      return await db.rawQuery('''
        SELECT id, name, phone, current_total_debt 
        FROM customers 
        WHERE current_total_debt > 0
          AND (is_deleted IS NULL OR is_deleted = 0)
        ORDER BY current_total_debt DESC
        LIMIT ?
      ''', [limit]);
    } catch (e) {
      return [];
    }
  }

  /// حساب إجمالي التسديدات لفترة معينة
  Future<double> getTotalPaymentsForPeriod(DateTime start, DateTime end) async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(-amount_changed), 0) as total 
        FROM transactions 
        WHERE amount_changed < 0 
          AND transaction_date >= ? 
          AND transaction_date <= ?
          AND (is_deleted IS NULL OR is_deleted = 0)
      ''', [start.toIso8601String(), end.toIso8601String()]);
      return ((result.first['total'] as num?) ?? 0).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  /// حساب إجمالي الديون المضافة لفترة معينة
  Future<double> getTotalDebtsAddedForPeriod(DateTime start, DateTime end) async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total 
        FROM transactions 
        WHERE amount_changed > 0 
          AND transaction_date >= ? 
          AND transaction_date <= ?
          AND (is_deleted IS NULL OR is_deleted = 0)
      ''', [start.toIso8601String(), end.toIso8601String()]);
      return ((result.first['total'] as num?) ?? 0).toDouble();
    } catch (e) {
      return 0.0;
    }
  }

  /// التحقق من صحة رصيد العميل
  Future<bool> verifyCustomerBalance(int customerId) async {
    final db = await getDatabase();
    try {
      // جلب رصيد العميل المخزن
      final customerResult = await db.query(
        'customers', 
        columns: ['current_total_debt'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (customerResult.isEmpty) return false;
      
      final storedBalance = (customerResult.first['current_total_debt'] as num?)?.toDouble() ?? 0;
      
      // حساب الرصيد من المعاملات
      final calcResult = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total 
        FROM transactions 
        WHERE customer_id = ?
          AND (is_deleted IS NULL OR is_deleted = 0)
      ''', [customerId]);
      final calculatedBalance = ((calcResult.first['total'] as num?) ?? 0).toDouble();
      
      // المقارنة
      return MoneyCalculator.areEqual(storedBalance, calculatedBalance);
    } catch (e) {
      return false;
    }
  }

  /// إصلاح رصيد عميل معين
  Future<void> fixCustomerBalance(int customerId) async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total 
        FROM transactions 
        WHERE customer_id = ?
          AND (is_deleted IS NULL OR is_deleted = 0)
      ''', [customerId]);
      final correctBalance = ((result.first['total'] as num?) ?? 0).toDouble();
      final correctCents = (correctBalance * 100).round();
      
      await db.update(
        'customers',
        {
          'current_total_debt': correctBalance,
          'current_total_debt_cents': correctCents,
          'last_modified_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
    } catch (e) {
      print('Error fixing customer balance: $e');
    }
  }

  /// إصلاح أرصدة جميع العملاء
  Future<int> fixAllCustomerBalances() async {
    final db = await getDatabase();
    try {
      final customers = await db.query(
        'customers',
        columns: ['id'],
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );
      int fixed = 0;
      
      for (final customer in customers) {
        final id = customer['id'] as int;
        final isValid = await verifyCustomerBalance(id);
        if (!isValid) {
          await fixCustomerBalance(id);
          fixed++;
        }
      }
      
      return fixed;
    } catch (e) {
      print('Error fixing all customer balances: $e');
      return 0;
    }
  }

  /// تقرير الديون حسب الفترة الزمنية
  Future<Map<String, double>> getDebtAgingReport() async {
    final db = await getDatabase();
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final sixtyDaysAgo = now.subtract(const Duration(days: 60));
      final ninetyDaysAgo = now.subtract(const Duration(days: 90));
      
      // العملاء الذين آخر معاملة لهم في الفترات المختلفة
      final result = <String, double>{
        'current': 0.0,    // 0-30 يوم
        'overdue_30': 0.0, // 31-60 يوم
        'overdue_60': 0.0, // 61-90 يوم
        'overdue_90': 0.0, // أكثر من 90 يوم
      };
      
      final customers = await db.rawQuery('''
        SELECT c.id, c.current_total_debt, MAX(t.transaction_date) as last_tx_date
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0)
        WHERE c.current_total_debt > 0
          AND (c.is_deleted IS NULL OR c.is_deleted = 0)
        GROUP BY c.id
      ''');
      
      for (final customer in customers) {
        final debt = (customer['current_total_debt'] as num?)?.toDouble() ?? 0;
        final lastTxDate = customer['last_tx_date'] as String?;
        
        if (lastTxDate == null) {
          result['overdue_90'] = result['overdue_90']! + debt;
        } else {
          final txDate = DateTime.parse(lastTxDate);
          if (txDate.isAfter(thirtyDaysAgo)) {
            result['current'] = result['current']! + debt;
          } else if (txDate.isAfter(sixtyDaysAgo)) {
            result['overdue_30'] = result['overdue_30']! + debt;
          } else if (txDate.isAfter(ninetyDaysAgo)) {
            result['overdue_60'] = result['overdue_60']! + debt;
          } else {
            result['overdue_90'] = result['overdue_90']! + debt;
          }
        }
      }
      
      return result;
    } catch (e) {
      return {};
    }
  }
}
