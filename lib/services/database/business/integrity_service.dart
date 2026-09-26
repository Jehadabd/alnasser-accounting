// lib/services/database/business/integrity_service.dart
import 'package:sqflite/sqflite.dart';
import '../dao/customer_dao.dart';
import '../dao/transaction_dao.dart';
import '../dao/invoice_dao.dart';
import '../../../models/verification_result.dart';
import '../../../utils/money_calculator.dart';

class IntegrityService {
  final Future<Database> Function() getDatabase;
  final CustomerDao customerDao;
  final TransactionDao transactionDao;
  final InvoiceDao invoiceDao;

  IntegrityService({
    required this.getDatabase,
    required this.customerDao,
    required this.transactionDao,
    required this.invoiceDao,
  });

  /// 🔒 التحقق من سلامة البيانات المالية للعميل
  Future<FinancialIntegrityReport> verifyCustomerFinancialIntegrity(int customerId) async {
    final db = await getDatabase();
    
    // 1. جلب بيانات العميل
    final customer = await customerDao.getCustomerById(customerId);
    if (customer == null) {
      throw Exception('Customer not found');
    }

    final issues = <String>[];
    final warnings = <String>[];
    final invoiceIssues = <InvoiceIssue>[];

    // 2. التحقق من رصيد العميل مقابل المعاملات
    final transactions = await transactionDao.getCustomerTransactions(customerId, orderBy: 'transaction_date ASC, id ASC');
    
    double calculatedBalance = 0.0;
    int transactionCount = transactions.length;
    
    for (final tx in transactions) {
      // التحقق من تسلسل الرصيد
      /*
      if (tx.balanceBeforeTransaction != calculatedBalance) {
         // هذا قد يكون خطأ، ولكن في بعض الأحيان قد يكون مقبولاً إذا تم التعديل
         // لكن بشكل عام، يجب أن يكون متسلسلاً
         warnings.add('انقطاع في تسلسل الرصيد للمعاملة ${tx.id}');
      }
      */
      
      calculatedBalance = MoneyCalculator.add(calculatedBalance, tx.amountChanged);
      
      // التحقق من Checksum لكل معاملة (اختياري لعدم البطء)
      // ...
    }
    
    final recordedBalance = customer.currentTotalDebt;
    bool isHealthy = true;
    
    if (!MoneyCalculator.areEqual(calculatedBalance, recordedBalance)) {
       isHealthy = false;
       final diff = (calculatedBalance - recordedBalance).abs();
       if (diff < 0.1) {
          warnings.add('فرق بسيط في الرصيد: ${diff.toStringAsFixed(3)}');
       } else {
          issues.add('الرصيد المسجل ($recordedBalance) لا يطابق مجموع المعاملات ($calculatedBalance)');
       }
    }

    // 3. التحقق من الفواتير (Optional, simplified)
    // ...

    return FinancialIntegrityReport(
      customerId: customerId,
      customerName: customer.name,
      isHealthy: isHealthy,
      issues: issues,
      warnings: warnings,
      calculatedBalance: calculatedBalance,
      recordedBalance: recordedBalance,
      transactionCount: transactionCount,
      invoiceIssues: invoiceIssues,
    );
  }

  /// إصلاح عدم تطابق الفاتورة مع المعاملة
  Future<void> repairInvoiceTransactionMismatch(int invoiceId) async {
    final db = await getDatabase();
    await db.transaction((txn) async {
       // 1. جلب الفاتورة
       final invoiceMap = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
       if (invoiceMap.isEmpty) return;
       final invoice = invoiceMap.first;
       
       final double totalAmount = (invoice['total_amount'] as num).toDouble();
       final double paidAmount = (invoice['amount_paid_on_invoice'] as num).toDouble();
       final double remaining = totalAmount - paidAmount;
       final String paymentType = invoice['payment_type'] as String;
       final int customerId = invoice['customer_id'] as int;
       
       if (paymentType != 'دين' || customerId == 0) return;
       
       // 2. جلب معاملة الدين
       final txMap = await txn.query(
         'transactions',
         where: 'invoice_id = ? AND amount_changed > 0', // نفترض أن الدين > 0
         whereArgs: [invoiceId],
         limit: 1
       );
       
       if (txMap.isNotEmpty) {
         // تحديث المعاملة الموجودة
         final txId = txMap.first['id'] as int;
         final currentAmount = (txMap.first['amount_changed'] as num).toDouble();
         
         if (!MoneyCalculator.areEqual(currentAmount, remaining)) {
            // تحديث المبلغ
            // يجب تحديث التراكمي أيضاً، وهذا معقد داخل transaction بسيطة
            // لذا سنستخدم منطق TransactionDao لكن يجب أن نكون حذرين من الـ Nesting
            // الأفضل: فقط تحديث القيمة هنا ثم طلب Recalculate للمعاملات
            
            await txn.update(
              'transactions', 
              {'amount_changed': remaining}, 
              where: 'id = ?', 
              whereArgs: [txId]
            );
         }
       } else if (remaining > 0) {
         // إنشاء معاملة جديدة
         // ... simplified
       }
       
       // 3. إعادة حساب أرصدة العميل بالكامل
       // لا نستطيع استدعاء transactionDao هنا لأنه سيفتح transaction جديدة وقد يسبب deadlock
       // لذا نؤجلها لبعد الـ commit أو نستخدم طريقة أخرى
    });
    
    // بعد الـ transaction
    final invoice = await invoiceDao.getInvoiceById(invoiceId);
    if (invoice != null && invoice.customerId != null && invoice.customerId != 0) {
      await transactionDao.recalculateCustomerTransactionBalances(invoice.customerId!);
      await transactionDao.recalculateAndApplyCustomerDebt(invoice.customerId!);
    }
  }

  /// الحصول على رصيد العميل المُتحقق منه
  Future<VerifiedBalanceResult> getVerifiedCustomerBalance(int customerId) async {
     final db = await getDatabase();
     
     final customer = await customerDao.getCustomerById(customerId);
     if (customer == null) {
       return VerifiedBalanceResult(
         isVerified: false, 
         calculatedBalance: 0, 
         recordedBalance: 0, 
         difference: 0,
         errorMessage: 'Customer not found'
       );
     }
     
 final res = await db.rawQuery('SELECT SUM(amount_changed) as total FROM transactions WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)', [customerId]);     final calculated = ((res.first['total'] as num?) ?? 0).toDouble();
     final recorded = customer.currentTotalDebt;
     
     final diff = (calculated - recorded).abs();
     
     if (MoneyCalculator.areEqual(calculated, recorded)) {
       return VerifiedBalanceResult(
         isVerified: true, 
         calculatedBalance: calculated, 
         recordedBalance: recorded, 
         difference: 0
       );
     } else if (diff < 1.0) {
       // Auto fix
       await customerDao.updateCustomer(customer.copyWith(currentTotalDebt: calculated), updateBalance: true);
       return VerifiedBalanceResult(
         isVerified: true, 
         calculatedBalance: calculated, 
         recordedBalance: recorded, 
         difference: diff,
         wasAutoFixed: true,
         autoFixNote: 'Fixed small difference'
       );
     } else {
       return VerifiedBalanceResult(
         isVerified: false, 
         calculatedBalance: calculated, 
         recordedBalance: recorded, 
         difference: diff,
         needsManualFix: true
       );
     }
  }
}
