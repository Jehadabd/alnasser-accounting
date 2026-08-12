// lib/services/database/dao/transaction_dao.dart
// عمليات CRUD للمعاملات المالية

import 'package:sqflite/sqflite.dart';
import '../../../models/transaction.dart';
import '../../../models/customer.dart';
import '../../../utils/money_calculator.dart';
import '../core/database_helpers.dart';
import '../business/customer_locking.dart';
import '../../../utils/uuid_helper.dart';
import '../../sync/sync_security.dart';

/// DAO للمعاملات المالية - عمليات CRUD والأمان
class TransactionDao {
  final Future<Database> Function() getDatabase;
  final LockService lockingService;

  TransactionDao({
    required this.getDatabase,
    required this.lockingService,
  });

  /// إدراج معاملة جديدة مع التحققات الأمنية
  Future<int> insertTransaction(DebtTransaction transaction) async {
    final db = await getDatabase();
    
    // 🔒 الحصول على قفل للعميل
    final lockResult = await lockingService.acquireLock(resourceType: 'customer', resourceId: transaction.customerId);
    if (!lockResult.success) {
      throw Exception(lockResult.message ?? 'فشل الحصول على قفل العميل - يرجى المحاولة مرة أخرى');
    }
    
    try {
      // 🛡️ تفعيل الكتابة الفورية للقرص (أعلى مستوى أمان)
      // هذا يضمن أن البيانات تُكتب فعلياً على القرص قبل إرجاع النتيجة
      await db.rawQuery('PRAGMA synchronous = FULL');
      
      final result = await db.transaction((txn) async {
        // 🔒 0. فحص UUID لمنع المعاملات المكررة (حماية إضافية)
        if (transaction.transactionUuid != null && transaction.transactionUuid!.isNotEmpty) {
          final existingTx = await txn.query(
            'transactions',
            columns: ['id'],
            where: 'transaction_uuid = ?',
            whereArgs: [transaction.transactionUuid],
            limit: 1,
          );
          if (existingTx.isNotEmpty) {
            print('⚠️ تم اكتشاف معاملة مكررة بنفس UUID: ${transaction.transactionUuid}');
            // إرجاع ID المعاملة الموجودة بدلاً من إضافة مكررة
            return existingTx.first['id'] as int;
          }
        }
        
        // 1. جلب العميل
        final List<Map<String, dynamic>> customerMaps = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [transaction.customerId],
          limit: 1,
        );
        if (customerMaps.isEmpty) {
          throw Exception('لم يتم العثور على العميل');
        }
        final customer = Customer.fromMap(customerMaps.first);
        
        // 2. جلب آخر معاملة للتحقق من التسلسل
        final List<Map<String, dynamic>> lastTxRows = await txn.query(
          'transactions',
          where: 'customer_id = ?',
          whereArgs: [transaction.customerId],
          orderBy: 'transaction_date DESC, id DESC',
          limit: 1,
        );
        
        double verifiedBalanceBefore = customer.currentTotalDebt;

        // 🔒 التحقق الصارم من سلامة البيانات
        if (lastTxRows.isNotEmpty) {
          final lastTx = DebtTransaction.fromMap(lastTxRows.first);
          final balanceDiff = (verifiedBalanceBefore - (lastTx.newBalanceAfterTransaction ?? 0)).abs();
          if (balanceDiff > 1.0) {
            throw Exception(
              'خطأ أمني حرج: رصيد العميل (${verifiedBalanceBefore.toStringAsFixed(2)}) '
              'لا يتطابق مع آخر معاملة (${lastTx.newBalanceAfterTransaction?.toStringAsFixed(2)}). '
              'الفرق: ${balanceDiff.toStringAsFixed(2)} دينار.'
            );
          }
        }
        
        // 3. حساب الرصيد الجديد
        double newBalanceAfterTransaction = MoneyCalculator.add(
          verifiedBalanceBefore, 
          transaction.amountChanged
        );
        
        // 🔒 التحقق المزدوج
        final verification = MoneyCalculator.verifyTransaction(
          balanceBefore: verifiedBalanceBefore,
          amountChanged: transaction.amountChanged,
          expectedBalanceAfter: newBalanceAfterTransaction,
        );
        
        if (!verification.isValid) {
          throw Exception('خطأ في التحقق الحسابي: ${verification.errorMessage}');
        }
        
        // 🔒 حساب Checksum
        final checksum = MoneyCalculator.calculateTransactionChecksum(
          customerId: transaction.customerId,
          amount: transaction.amountChanged,
          balanceBefore: verifiedBalanceBefore,
          balanceAfter: newBalanceAfterTransaction,
          date: transaction.transactionDate,
        );
        
        // 4. تجهيز المعاملة وتوليد المعرفات
        String? newSyncUuid = transaction.syncUuid;
        String? newTxUuid = transaction.transactionUuid;
        
        if ((newSyncUuid == null || newSyncUuid.isEmpty) && 
            (newTxUuid == null || newTxUuid.isEmpty)) {
          final generated = SyncSecurity.generateUuid();
          newSyncUuid = generated;
          newTxUuid = generated;
        } else if (newSyncUuid == null || newSyncUuid.isEmpty) {
          newSyncUuid = newTxUuid;
        } else if (newTxUuid == null || newTxUuid.isEmpty) {
          newTxUuid = newSyncUuid;
        }

        final updatedTransaction = transaction.copyWith(
          balanceBeforeTransaction: verifiedBalanceBefore,
          newBalanceAfterTransaction: newBalanceAfterTransaction,
          syncUuid: newSyncUuid,
          transactionUuid: newTxUuid,
        );
        
        // 5. إدراج المعاملة
        final transactionMap = updatedTransaction.toMap();
        transactionMap['checksum'] = checksum;
        final id = await txn.insert('transactions', transactionMap);

        // 6. تحديث رصيد العميل
        await txn.update(
          'customers',
          {
            'current_total_debt': newBalanceAfterTransaction,
            'last_modified_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [transaction.customerId],
        );
        
        // 🔒 التحقق بعد الحفظ
        final List<Map<String, dynamic>> verifyCustomer = await txn.query(
          'customers',
          columns: ['current_total_debt'],
          where: 'id = ?',
          whereArgs: [transaction.customerId],
          limit: 1,
        );
        
        if (verifyCustomer.isNotEmpty) {
          final savedBalance = (verifyCustomer.first['current_total_debt'] as num).toDouble();
          if (!MoneyCalculator.areEqual(savedBalance, newBalanceAfterTransaction)) {
            throw Exception(
              'خطأ أمني حرج بعد الحفظ: الرصيد المحفوظ ($savedBalance) '
              '≠ الرصيد المتوقع ($newBalanceAfterTransaction)'
            );
          }
        }
        
        return id;
      });
      
      // 🛡️ ضمان الكتابة الفورية للقرص (WAL Checkpoint)
      // هذا يضمن أن المعاملة محفوظة على القرص الدائم وليس في الذاكرة
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {
        // تجاهل أي خطأ في الـ checkpoint - الـ transaction نجحت
      }
      
      // 🔄 إعادة synchronous للوضع الطبيعي (لتحسين الأداء)
      try {
        await db.rawQuery('PRAGMA synchronous = NORMAL');
      } catch (_) {}
      
      return result;
    } finally {
      lockingService.releaseLock(resourceType: 'customer', resourceId: transaction.customerId);
    }
  }

  /// جلب معاملة بالمعرف
  Future<DebtTransaction?> getTransactionById(int id) async {
    final db = await getDatabase();
    try {
      final maps = await db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
      if (maps.isNotEmpty) {
        return DebtTransaction.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب معاملات العميل
  Future<List<DebtTransaction>> getCustomerTransactions(
    int customerId, {
    String orderBy = 'transaction_date DESC, id DESC'
  }) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: orderBy,
      );
      return List.generate(maps.length, (i) => DebtTransaction.fromMap(maps[i]));
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب معاملة الدين المرتبطة بفاتورة
  Future<DebtTransaction?> getInvoiceDebtTransaction(int invoiceId) async {
    final db = await getDatabase();
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'transactions',
        where: 'invoice_id = ? AND amount_changed > 0',
        whereArgs: [invoiceId],
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return DebtTransaction.fromMap(maps.first);
      }
    } catch (e) {
      print('Error getting invoice debt transaction for invoice $invoiceId: $e');
    }
    return null;
  }

  /// تحديث معاملة يدوية
  /// تحديث معاملة يدوية
  Future<void> updateManualTransaction(DebtTransaction updated, {bool fromSync = false}) async {
    final db = await getDatabase();
    if (updated.id == null) {
      throw Exception('لا يمكن تعديل معاملة بدون معرّف');
    }

    // 🔒 الحصول على قفل للعميل
    final lockResult = await lockingService.acquireLock(resourceType: 'customer', resourceId: updated.customerId);
    if (!lockResult.success) {
      throw Exception(lockResult.message ?? 'فشل الحصول على قفل العميل - يرجى المحاولة مرة أخرى');
    }

    try {
      // 🛡️ تفعيل الكتابة الفورية (تجاوز الـ RAM)
      await db.rawQuery('PRAGMA synchronous = FULL');

      await db.transaction((txn) async {
        final oldTxRes = await txn.query('transactions', where: 'id = ?', whereArgs: [updated.id], limit: 1);
        if (oldTxRes.isEmpty) {
          throw Exception('لم يتم العثور على المعاملة المراد تعديلها');
        }
        final oldTx = DebtTransaction.fromMap(oldTxRes.first);

        if (oldTx.invoiceId != null) {
          throw Exception('لا يمكن تعديل معاملة مرتبطة بفاتورة من هنا');
        }

        // 🔥 حماية الملكية: لا تعديل محلي لمعاملة من إنشاء جهاز آخر (إلا من المزامنة)
        if (!fromSync && !oldTx.isCreatedByMe) {
          throw Exception('هذه المعاملة أُنشئت على جهاز آخر ولا يمكن تعديلها من هذا الجهاز.');
        }

        // جلب المعاملات السابقة لحساب الرصيد
        final transactionsRes = await txn.query(
          'transactions',
          where: 'customer_id = ?',
          whereArgs: [oldTx.customerId],
          orderBy: 'transaction_date ASC, id ASC'
        );
        final transactions = transactionsRes.map((map) => DebtTransaction.fromMap(map)).toList();
        
        int currentIndex = transactions.indexWhere((t) => t.id == oldTx.id);
        if (currentIndex == -1) {
           // قد يكون تم حذفها بواسطة جلسة أخرى، لكن القفل يمنع ذلك
           throw Exception('لم يتم العثور على المعاملة في القائمة');
        }
        
        double balanceBeforeTransaction = 0.0;
        if (currentIndex > 0) {
          balanceBeforeTransaction = transactions[currentIndex - 1].newBalanceAfterTransaction ?? 0.0;
        }
        
        final String newType = updated.amountChanged >= 0 ? 'manual_debt' : 'manual_payment';
        final double newBalanceAfter = MoneyCalculator.add(balanceBeforeTransaction, updated.amountChanged);
        
        // تحديث المعاملة الحالية
        await txn.update(
          'transactions',
          {
            'amount_changed': updated.amountChanged,
            'transaction_note': updated.transactionNote,
            'transaction_date': updated.transactionDate.toIso8601String(),
            'transaction_type': newType,
            'new_balance_after_transaction': newBalanceAfter,
            'balance_before_transaction': balanceBeforeTransaction,
            // 🔥 is_uploaded: التعديل المحلي يعيد الطابور (0)، المزامنة لا (1)
            'is_uploaded': fromSync ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [updated.id],
        );
        
        // تحديث أرصدة المعاملات اللاحقة
        if (currentIndex < transactions.length - 1) {
          double runningBalance = newBalanceAfter;
          for (int i = currentIndex + 1; i < transactions.length; i++) {
            double newBalance = MoneyCalculator.add(runningBalance, transactions[i].amountChanged);
            // نحسب checksum أيضاً هنا لضمان السلامة
            await txn.update(
              'transactions',
              {
                'balance_before_transaction': runningBalance,
                'new_balance_after_transaction': newBalance,
              },
              where: 'id = ?',
              whereArgs: [transactions[i].id],
            );
            runningBalance = newBalance;
          }
        }
      });
      
      // إعادة حساب رصيد العميل بناءً على التعديلات
      // هذه الدالة ستقوم بحساب الرصيد النهائي وتحديث العميل
      await recalculateAndApplyCustomerDebt(updated.customerId);

      // 🛡️ ضمان الحفظ الفوري
      try { await db.rawQuery('PRAGMA wal_checkpoint(FULL)'); } catch (_) {}
      
      // 🔄 إعادة الوضع للطبيعي
      try { await db.rawQuery('PRAGMA synchronous = NORMAL'); } catch (_) {}

    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    } finally {
      lockingService.releaseLock(resourceType: 'customer', resourceId: updated.customerId);
    }
  }

  /// تحويل نوع المعاملة
  Future<void> convertTransactionType(int transactionId) async {
    final db = await getDatabase();
    
    try {
      final transaction = await getTransactionById(transactionId);
      if (transaction == null) {
        throw Exception('لم يتم العثور على المعاملة المراد تحويلها');
      }
      
      if (transaction.invoiceId != null) {
        throw Exception('لا يمكن تحويل نوع معاملة مرتبطة بفاتورة');
      }
      
      final transactions = await getCustomerTransactions(
        transaction.customerId, 
        orderBy: 'transaction_date ASC, id ASC'
      );
      
      int currentIndex = transactions.indexWhere((t) => t.id == transactionId);
      if (currentIndex == -1) {
        throw Exception('لم يتم العثور على المعاملة في قائمة معاملات العميل');
      }
      
      double balanceBeforeTransaction = 0.0;
      if (currentIndex > 0) {
        balanceBeforeTransaction = transactions[currentIndex - 1].newBalanceAfterTransaction ?? 0.0;
      }
      
      final double newAmount = -transaction.amountChanged;
      final String newType = newAmount >= 0 ? 'manual_debt' : 'manual_payment';
      final double newBalanceAfter = MoneyCalculator.add(balanceBeforeTransaction, newAmount);
      
      await db.update(
        'transactions',
        {
          'amount_changed': newAmount,
          'transaction_type': newType,
          'new_balance_after_transaction': newBalanceAfter,
          'balance_before_transaction': balanceBeforeTransaction,
        },
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      
      // تحديث أرصدة المعاملات اللاحقة
      if (currentIndex < transactions.length - 1) {
        double runningBalance = newBalanceAfter;
        for (int i = currentIndex + 1; i < transactions.length; i++) {
          await db.update(
            'transactions',
            {
              'balance_before_transaction': runningBalance,
              'new_balance_after_transaction': MoneyCalculator.add(runningBalance, transactions[i].amountChanged),
            },
            where: 'id = ?',
            whereArgs: [transactions[i].id],
          );
          runningBalance = MoneyCalculator.add(runningBalance, transactions[i].amountChanged);
        }
      }
      
      await recalculateAndApplyCustomerDebt(transaction.customerId);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// إعادة حساب وتطبيق رصيد العميل
  Future<double> recalculateAndApplyCustomerDebt(int customerId) async {
    final lockResult = await lockingService.acquireLock(resourceType: 'customer', resourceId: customerId);
    if (!lockResult.success) {
      throw Exception(lockResult.message ?? 'فشل الحصول على قفل العميل لإعادة الحساب');
    }
    
    try {
      final db = await getDatabase();
      final res = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS total FROM transactions WHERE customer_id = ?;',
        [customerId]
      );
      final double total = ((res.first['total'] as num?) ?? 0).toDouble();

      await db.update(
        'customers',
        {
          'current_total_debt': total,
          'last_modified_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );
      
      return total;
    } finally {
      lockingService.releaseLock(resourceType: 'customer', resourceId: customerId);
    }
  }

  /// إعادة حساب أرصدة المعاملات لعميل معين
  Future<void> recalculateCustomerTransactionBalances(int customerId) async {
    final lockResult = await lockingService.acquireLock(resourceType: 'customer', resourceId: customerId);
    if (!lockResult.success) {
      throw Exception(lockResult.message ?? 'فشل الحصول على قفل العميل لإعادة حساب الأرصدة');
    }
    
    try {
      final db = await getDatabase();
      final transactions = await getCustomerTransactions(customerId, orderBy: 'transaction_date ASC, id ASC');
      
      double runningBalance = 0.0;
      
      for (final transaction in transactions) {
        final double balanceBefore = runningBalance;
        runningBalance = MoneyCalculator.add(runningBalance, transaction.amountChanged);
        
        final checksum = MoneyCalculator.calculateTransactionChecksum(
          customerId: customerId,
          amount: transaction.amountChanged,
          balanceBefore: balanceBefore,
          balanceAfter: runningBalance,
          date: transaction.transactionDate,
        );
        
        await db.update(
          'transactions',
          {
            'balance_before_transaction': balanceBefore,
            'new_balance_after_transaction': runningBalance,
            'checksum': checksum,
          },
          where: 'id = ?',
          whereArgs: [transaction.id],
        );
      }
    } finally {
      lockingService.releaseLock(resourceType: 'customer', resourceId: customerId);
    }
  }

  /// جلب المعاملات لفترة معينة
  Future<List<DebtTransaction>> getTransactionsForPeriod(
    DateTime start, 
    DateTime end
  ) async {
    final db = await getDatabase();
    try {
      final maps = await db.query(
        'transactions',
        where: 'transaction_date >= ? AND transaction_date <= ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'transaction_date DESC',
      );
      return maps.map((m) => DebtTransaction.fromMap(m)).toList();
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب إحصائيات المعاملات
  Future<Map<String, dynamic>> getTransactionStats(int customerId) async {
    final db = await getDatabase();
    try {
      final totalDebts = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total 
        FROM transactions 
        WHERE customer_id = ? AND amount_changed > 0
      ''', [customerId]);
      
      final totalPayments = await db.rawQuery('''
        SELECT COALESCE(SUM(-amount_changed), 0) as total 
        FROM transactions 
        WHERE customer_id = ? AND amount_changed < 0
      ''', [customerId]);
      
      final count = await db.rawQuery('''
        SELECT COUNT(1) as count FROM transactions WHERE customer_id = ?
      ''', [customerId]);
      
      return {
        'total_debts': ((totalDebts.first['total'] as num?) ?? 0).toDouble(),
        'total_payments': ((totalPayments.first['total'] as num?) ?? 0).toDouble(),
        'transaction_count': (count.first['count'] as int?) ?? 0,
      };
    } catch (e) {
      return {};
    }
  }
}
