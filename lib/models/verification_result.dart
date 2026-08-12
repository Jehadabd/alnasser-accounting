// lib/models/verification_result.dart

/// نتيجة التحقق من الرصيد المالي
class VerifiedBalanceResult {
  /// هل الرصيد متطابق؟
  final bool isVerified;
  
  /// الرصيد المحسوب من المعاملات
  final double calculatedBalance;
  
  /// الرصيد المسجل في جدول العملاء
  final double recordedBalance;
  
  /// الفرق بينهما
  final double difference;
  
  /// هل تم إصلاحه تلقائياً؟
  final bool wasAutoFixed;
  
  /// ملاحظة الإصلاح التلقائي
  final String? autoFixNote;
  
  /// رسالة الخطأ (إذا وجدت)
  final String? errorMessage;
  
  /// هل يحتاج تدخل يدوي؟
  final bool needsManualFix;

  VerifiedBalanceResult({
    required this.isVerified,
    required this.calculatedBalance,
    required this.recordedBalance,
    required this.difference,
    this.wasAutoFixed = false,
    this.autoFixNote,
    this.errorMessage,
    this.needsManualFix = false,
  });

  @override
  String toString() {
    if (isVerified) {
      return 'VerifiedBalanceResult(✅ متحقق, رصيد: $calculatedBalance${wasAutoFixed ? ", تم إصلاح تلقائي" : ""})';
    } else {
      return 'VerifiedBalanceResult(❌ غير متحقق, محسوب: $calculatedBalance, مسجل: $recordedBalance, فرق: $difference)';
    }
  }
}

/// تقرير التحقق من Checksum
class ChecksumVerificationReport {
  final int totalChecked;
  final int totalPassed;
  final int totalFailed;
  final int totalMissing;
  final List<Map<String, dynamic>> failedDetails;
  final DateTime verifiedAt;
  
  ChecksumVerificationReport({
    required this.totalChecked,
    required this.totalPassed,
    required this.totalFailed,
    required this.totalMissing,
    required this.failedDetails,
    required this.verifiedAt,
  });
  
  bool get isHealthy => totalFailed == 0;
  double get passRate => totalChecked > 0 ? (totalPassed / (totalChecked - totalMissing)) * 100 : 100;
}

/// تفاصيل مشكلة في فاتورة
class InvoiceIssue {
  final int invoiceId;
  final String invoiceDate;
  final String description;
  final double difference;
  final List<String> details;

  InvoiceIssue({
    required this.invoiceId,
    required this.invoiceDate,
    required this.description,
    required this.difference,
    this.details = const [],
  });
}

/// تقرير سلامة البيانات المالية
class FinancialIntegrityReport {
  final int customerId;
  final String customerName; // اسم العميل
  final bool isHealthy;
  final List<String> issues;
  final List<String> warnings;
  final double calculatedBalance;
  final double recordedBalance;
  final int transactionCount;
  final List<InvoiceIssue> invoiceIssues;
  
  // 📊 ملخص كشف الحساب التجاري
  final int totalInvoices;           // إجمالي عدد الفواتير
  final int debtInvoices;            // عدد فواتير الدين
  final int cashInvoices;            // عدد الفواتير النقدية
  final double totalInvoiceAmount;   // إجمالي مبالغ الفواتير
  final double totalPayments;        // إجمالي المدفوعات

  FinancialIntegrityReport({
    required this.customerId,
    required this.customerName,
    required this.isHealthy,
    required this.issues,
    required this.warnings,
    required this.calculatedBalance,
    required this.recordedBalance,
    required this.transactionCount,
    this.invoiceIssues = const [],
    this.totalInvoices = 0,
    this.debtInvoices = 0,
    this.cashInvoices = 0,
    this.totalInvoiceAmount = 0.0,
    this.totalPayments = 0.0,
  });

  @override
  String toString() {
    return 'FinancialIntegrityReport(customerId: $customerId, customerName: $customerName, isHealthy: $isHealthy, issues: ${issues.length}, warnings: ${warnings.length}, invoiceIssues: ${invoiceIssues.length}, invoices: $totalInvoices)';
  }
}

/// نتيجة التحقق من المعاملة
class TransactionValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final double? currentBalance;
  final double? expectedNewBalance;

  TransactionValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    this.currentBalance,
    this.expectedNewBalance,
  });
}

/// نتيجة التحقق من الفاتورة
class InvoiceValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final double calculatedTotal;

  InvoiceValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    required this.calculatedTotal,
  });
}

/// نتيجة الفحص الدوري
class PeriodicCheckResult {
  final DateTime checkDate;
  final Duration duration;
  final int customersChecked;
  final int issuesFound;
  final int issuesFixed;
  final List<String> details;
  final bool success;

  PeriodicCheckResult({
    required this.checkDate,
    required this.duration,
    required this.customersChecked,
    required this.issuesFound,
    required this.issuesFixed,
    required this.details,
    required this.success,
  });

  @override
  String toString() {
    return 'PeriodicCheckResult(checked: $customersChecked, issues: $issuesFound, fixed: $issuesFixed, success: $success)';
  }
}

/// ملخص مالي
class FinancialSummary {
  final double totalCustomerDebt;
  final double totalCustomerCredit;
  final int totalCustomers;
  final int debtorCount;
  final int totalInvoices;
  final double totalInvoiceAmount;
  final DateTime generatedAt;

  FinancialSummary({
    required this.totalCustomerDebt,
    required this.totalCustomerCredit,
    required this.totalCustomers,
    required this.debtorCount,
    required this.totalInvoices,
    required this.totalInvoiceAmount,
    required this.generatedAt,
  });
}

/// نتيجة المطابقة اليومية
class DailyReconciliationResult {
  final DateTime date;
  final Duration duration;
  final int customersChecked;
  final int invoicesChecked;
  final int issuesFound;
  final int issuesFixed;
  final List<String> issues;
  final List<String> fixes;
  final bool success;

  DailyReconciliationResult({
    required this.date,
    required this.duration,
    required this.customersChecked,
    required this.invoicesChecked,
    required this.issuesFound,
    required this.issuesFixed,
    required this.issues,
    required this.fixes,
    required this.success,
  });

  @override
  String toString() {
    return 'DailyReconciliationResult(date: $date, customers: $customersChecked, invoices: $invoicesChecked, issues: $issuesFound, fixed: $issuesFixed, success: $success)';
  }
  
  /// هل البيانات سليمة 100%؟
  bool get isFullyHealthy => issuesFound == 0;
  
  /// نسبة الأمان
  double get healthPercentage {
    final total = customersChecked + invoicesChecked;
    if (total == 0) return 100.0;
    return ((total - issuesFound) / total) * 100;
  }
}

/// نتيجة الفحص السريع
class QuickIntegrityCheckResult {
  final DateTime checkDate;
  final Duration duration;
  final bool isHealthy;
  final List<String> warnings;
  final bool databaseIntegrity;

  QuickIntegrityCheckResult({
    required this.checkDate,
    required this.duration,
    required this.isHealthy,
    required this.warnings,
    required this.databaseIntegrity,
  });

  @override
  String toString() {
    return 'QuickIntegrityCheckResult(healthy: $isHealthy, warnings: ${warnings.length}, dbIntegrity: $databaseIntegrity)';
  }
}
