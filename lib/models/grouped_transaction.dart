// lib/models/grouped_transaction.dart
import 'transaction.dart';

/// نوع العنصر المجمع
enum GroupedTransactionType {
  manual,           // معاملة يدوية (للعرض التفصيلي)
  invoice,          // فاتورة (مجمعة)
  manualDebtGroup,  // مجموعة معاملات يدوية (إضافة دين) - محلية
  manualPaymentGroup, // مجموعة معاملات يدوية (تسديد) - محلية
  syncDebtGroup,    // 🔄 مجموعة معاملات مزامنة (إضافة دين) - من جهاز آخر
  syncPaymentGroup, // 🔄 مجموعة معاملات مزامنة (تسديد) - من جهاز آخر
}

/// عنصر معاملة مجمع - يمثل إما معاملة يدوية أو فاتورة مجمعة
class GroupedTransactionItem {
  /// نوع العنصر
  final GroupedTransactionType type;
  
  /// تاريخ العنصر
  final DateTime date;
  
  /// المبلغ (للمعاملة اليدوية: المبلغ الفعلي، للفاتورة: صافي المعاملات = المبلغ المتبقي)
  final double amount;
  
  /// الوصف
  final String description;
  
  /// نوع المعاملة (للمعاملات اليدوية فقط)
  final String? transactionType;
  
  /// رقم الفاتورة (للفواتير فقط) - الـ id الداخلي للربط التقني
  final int? invoiceId;

  /// 🔢 رقم الفاتورة التجاري (المرئي للمستخدم) - مثل "120260815"
  final String? invoiceNumber;
  
  /// إجمالي الفاتورة (للفواتير فقط)
  final double? invoiceTotal;
  
  /// المبلغ المسدد من الفاتورة (للفواتير فقط)
  final double? invoicePaid;
  
  /// نوع الدفع (للفواتير فقط)
  final String? paymentType;
  
  /// قائمة المعاملات التفصيلية
  final List<DebtTransaction> transactions;
  
  /// الرصيد قبل (للمعاملة اليدوية: الرصيد قبل، للفاتورة: الرصيد قبل أول معاملة)
  final double? balanceBefore;
  
  /// الرصيد بعد (للمعاملة اليدوية: الرصيد بعد، للفاتورة: الرصيد بعد آخر معاملة)
  final double? balanceAfter;
  

  GroupedTransactionItem({
    required this.type,
    required this.date,
    required this.amount,
    required this.description,
    this.transactionType,
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceTotal,
    this.invoicePaid,
    this.paymentType,
    required this.transactions,
    this.balanceBefore,
    this.balanceAfter,
  });

  /// هل هذا العنصر فاتورة؟
  bool get isInvoice => type == GroupedTransactionType.invoice;
  
  /// هل هذا العنصر معاملة يدوية؟
  bool get isManual => type == GroupedTransactionType.manual;
  
  /// هل هذا العنصر مجموعة معاملات يدوية (إضافة دين)؟
  bool get isManualDebtGroup => type == GroupedTransactionType.manualDebtGroup;
  
  /// هل هذا العنصر مجموعة معاملات يدوية (تسديد)؟
  bool get isManualPaymentGroup => type == GroupedTransactionType.manualPaymentGroup;
  
  /// هل هذا العنصر مجموعة معاملات يدوية (أي نوع)؟
  bool get isManualGroup => isManualDebtGroup || isManualPaymentGroup;
  
  /// 🔄 هل هذا العنصر مجموعة معاملات مزامنة (إضافة دين)؟
  bool get isSyncDebtGroup => type == GroupedTransactionType.syncDebtGroup;
  
  /// 🔄 هل هذا العنصر مجموعة معاملات مزامنة (تسديد)؟
  bool get isSyncPaymentGroup => type == GroupedTransactionType.syncPaymentGroup;
  
  /// 🔄 هل هذا العنصر مجموعة معاملات مزامنة (أي نوع)؟
  bool get isSyncGroup => isSyncDebtGroup || isSyncPaymentGroup;
  
  /// عدد المعاملات التفصيلية
  int get transactionCount => transactions.length;
  
  /// هل الفاتورة مسددة بالكامل؟
  bool get isFullyPaid => isInvoice && amount.abs() < 0.01;
  
  /// هل الفاتورة نقدية؟
  bool get isCashInvoice => isInvoice && paymentType == 'نقد';
  
  /// هل المبلغ موجب (دين)؟
  bool get isDebt => amount > 0;
  
  /// هل المبلغ سالب (تسديد)؟
  bool get isPayment => amount < 0;

  @override
  String toString() {
    if (isInvoice) {
      return 'GroupedTransactionItem(فاتورة #$invoiceNumber, متبقي: $amount, معاملات: $transactionCount)';
    } else if (isSyncGroup) {
      return 'GroupedTransactionItem(مزامنة, مبلغ: $amount, نوع: $transactionType)';
    } else {
      return 'GroupedTransactionItem(يدوية, مبلغ: $amount, نوع: $transactionType)';
    }
  }
}
