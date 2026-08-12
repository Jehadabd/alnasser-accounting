import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// أداة مساعدة لإجراء العمليات الحسابية المالية بدقة
/// تهدف إلى تقليل أخطاء الكسور العشرية (Floating Point Errors)
/// عن طريق التقريب المباشر بعد كل عملية.
class MoneyCalculator {
  static const int _precision = 3; // عدد المراتب العشرية للدقة الداخلية

  /// جمع رقمين
  static double add(double a, double b) {
    return _round(a + b);
  }

  /// طرح رقمين (a - b)
  static double subtract(double a, double b) {
    return _round(a - b);
  }

  /// ضرب رقمين
  static double multiply(double a, double b) {
    return _round(a * b);
  }

  /// قسمة رقمين (a / b)
  static double divide(double a, double b) {
    if (b == 0) return 0.0;
    return _round(a / b);
  }

  /// جمع قائمة من الأرقام
  static double sum(List<double> numbers) {
    double total = 0.0;
    for (var n in numbers) {
      total = add(total, n);
    }
    return total;
  }

  /// تقريب الرقم إلى عدد محدد من الخانات العشرية
  static double _round(double value) {
    num mod = pow(10.0, _precision);
    return ((value * mod).round().toDouble() / mod);
  }
  
  /// التحقق من تساوي رقمين (مع هامش خطأ ضئيل جداً)
  static bool areEqual(double a, double b) {
    return (a - b).abs() < 0.0001;
  }

  /// نسبة الربح الافتراضية عندما تكون التكلفة صفر (10% = مصاريف كهرباء/تشغيل)
  static const double defaultProfitMargin = 0.10;

  /// حساب التكلفة الفعلية - إذا كانت التكلفة صفر، يفترض أن الربح 10% فقط
  /// مثال: سعر البيع 10,000 والتكلفة 0 → التكلفة الفعلية = 9,000 والربح = 1,000
  static double getEffectiveCost(double costPrice, double sellingPrice, {double profitMargin = defaultProfitMargin}) {
    if (costPrice > 0) {
      return costPrice; // التكلفة موجودة، استخدمها كما هي
    }
    // التكلفة صفر → افترض أن الربح 10% فقط (أو النسبة المحددة)
    return multiply(sellingPrice, 1.0 - profitMargin);
  }

  /// حساب الربح مع مراعاة التكلفة الصفرية
  /// إذا كانت التكلفة صفر، الربح = 10% من سعر البيع (أو النسبة المحددة)
  static double calculateProfit(double sellingPrice, double costPrice, {double? profitMargin}) {
    final effectiveCost = getEffectiveCost(costPrice, sellingPrice, profitMargin: profitMargin ?? defaultProfitMargin);
    return subtract(sellingPrice, effectiveCost);
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 🔒 تحسينات الأمان المالي - للوصول إلى 98-99%
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// حساب Checksum للمعاملة المالية
  /// يُستخدم للتحقق من سلامة البيانات
  /// 🔒 مُفعّل ومستخدم في جميع العمليات المالية الحساسة
  static String calculateTransactionChecksum({
    required int customerId,
    required double amount,
    required double balanceBefore,
    required double balanceAfter,
    required DateTime date,
  }) {
    final data = '$customerId|${amount.toStringAsFixed(3)}|${balanceBefore.toStringAsFixed(3)}|${balanceAfter.toStringAsFixed(3)}|${date.millisecondsSinceEpoch}';
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // أول 16 حرف
  }
  
  /// التحقق من صحة Checksum
  static bool verifyTransactionChecksum({
    required int customerId,
    required double amount,
    required double balanceBefore,
    required double balanceAfter,
    required DateTime date,
    required String checksum,
  }) {
    final calculated = calculateTransactionChecksum(
      customerId: customerId,
      amount: amount,
      balanceBefore: balanceBefore,
      balanceAfter: balanceAfter,
      date: date,
    );
    return calculated == checksum;
  }
  
  /// حساب Checksum لرصيد العميل
  /// يُستخدم للتحقق من سلامة رصيد العميل
  static String calculateCustomerBalanceChecksum({
    required int customerId,
    required double balance,
    required DateTime lastModified,
  }) {
    final data = 'customer|$customerId|${balance.toStringAsFixed(3)}|${lastModified.millisecondsSinceEpoch}';
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
  
  /// حساب Checksum للفاتورة
  /// يُستخدم للتحقق من سلامة بيانات الفاتورة
  static String calculateInvoiceChecksum({
    required int invoiceId,
    required double totalAmount,
    required double discount,
    required double amountPaid,
    required DateTime date,
  }) {
    final data = 'invoice|$invoiceId|${totalAmount.toStringAsFixed(3)}|${discount.toStringAsFixed(3)}|${amountPaid.toStringAsFixed(3)}|${date.millisecondsSinceEpoch}';
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
  
  /// التحقق المزدوج من صحة العملية الحسابية
  /// Double-entry verification
  static VerificationResult verifyTransaction({
    required double balanceBefore,
    required double amountChanged,
    required double expectedBalanceAfter,
  }) {
    // حساب الرصيد المتوقع
    final calculatedBalance = add(balanceBefore, amountChanged);
    
    // التحقق من التطابق
    if (!areEqual(calculatedBalance, expectedBalanceAfter)) {
      return VerificationResult(
        isValid: false,
        errorMessage: 'عدم تطابق: الرصيد المحسوب ($calculatedBalance) ≠ الرصيد المتوقع ($expectedBalanceAfter)',
        calculatedBalance: calculatedBalance,
        expectedBalance: expectedBalanceAfter,
        difference: subtract(calculatedBalance, expectedBalanceAfter),
      );
    }
    
    return VerificationResult(
      isValid: true,
      calculatedBalance: calculatedBalance,
      expectedBalance: expectedBalanceAfter,
      difference: 0,
    );
  }
  
  /// التحقق من سلسلة المعاملات (Chain Verification)
  /// يتحقق من أن كل معاملة تبدأ من حيث انتهت السابقة
  static ChainVerificationResult verifyTransactionChain(List<TransactionData> transactions) {
    if (transactions.isEmpty) {
      return ChainVerificationResult(isValid: true, brokenAt: -1);
    }
    
    for (int i = 1; i < transactions.length; i++) {
      final prev = transactions[i - 1];
      final curr = transactions[i];
      
      // التحقق من أن الرصيد قبل المعاملة الحالية = الرصيد بعد المعاملة السابقة
      if (!areEqual(curr.balanceBefore, prev.balanceAfter)) {
        return ChainVerificationResult(
          isValid: false,
          brokenAt: i,
          errorMessage: 'انقطاع في السلسلة عند المعاملة رقم $i: '
              'الرصيد السابق (${prev.balanceAfter}) ≠ الرصيد الحالي (${curr.balanceBefore})',
        );
      }
    }
    
    return ChainVerificationResult(isValid: true, brokenAt: -1);
  }
  
  /// حساب الرصيد من سلسلة المعاملات
  static double calculateBalanceFromTransactions(
    double openingBalance,
    List<double> amountsChanged,
  ) {
    double balance = openingBalance;
    for (final amount in amountsChanged) {
      balance = add(balance, amount);
    }
    return balance;
  }
}

/// نتيجة التحقق من المعاملة
class VerificationResult {
  final bool isValid;
  final String? errorMessage;
  final double calculatedBalance;
  final double expectedBalance;
  final double difference;
  
  VerificationResult({
    required this.isValid,
    this.errorMessage,
    required this.calculatedBalance,
    required this.expectedBalance,
    required this.difference,
  });
}

/// نتيجة التحقق من سلسلة المعاملات
class ChainVerificationResult {
  final bool isValid;
  final int brokenAt;
  final String? errorMessage;
  
  ChainVerificationResult({
    required this.isValid,
    required this.brokenAt,
    this.errorMessage,
  });
}

/// بيانات المعاملة للتحقق
class TransactionData {
  final double balanceBefore;
  final double amountChanged;
  final double balanceAfter;
  
  TransactionData({
    required this.balanceBefore,
    required this.amountChanged,
    required this.balanceAfter,
  });
}
