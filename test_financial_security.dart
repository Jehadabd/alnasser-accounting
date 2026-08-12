// test_financial_security.dart
// اختبار نظام الأمان المالي

import 'package:alnaser/services/financial_validation_service.dart';

void main() {
  print('═══════════════════════════════════════════════════════════════');
  print('🔒 اختبار نظام الأمان المالي');
  print('═══════════════════════════════════════════════════════════════\n');

  // اختبار 1: التحقق من المبالغ
  print('📊 اختبار 1: التحقق من المبالغ');
  print('─────────────────────────────────────');
  
  testAmount(100000, true, 'مبلغ صحيح');
  testAmount(-5000, false, 'مبلغ سالب');
  testAmount(0, false, 'مبلغ صفر');
  testAmount(2000000000, false, 'مبلغ أكبر من الحد المسموح');
  
  print('');

  // اختبار 2: التحقق من الكميات
  print('📦 اختبار 2: التحقق من الكميات');
  print('─────────────────────────────────────');
  
  testQuantity(10, true, 'كمية صحيحة');
  testQuantity(-5, false, 'كمية سالبة');
  testQuantity(0, false, 'كمية صفر');
  testQuantity(2000000, false, 'كمية أكبر من الحد المسموح');
  
  print('');

  // اختبار 3: التحقق من الخصومات
  print('💰 اختبار 3: التحقق من الخصومات');
  print('─────────────────────────────────────');
  
  testDiscount(5000, 100000, true, 'خصم 5% - صحيح');
  testDiscount(30000, 100000, true, 'خصم 30% - تحذير');
  testDiscount(60000, 100000, false, 'خصم 60% - خطأ');
  testDiscount(100000, 100000, false, 'خصم 100% - خطأ');
  testDiscount(-1000, 100000, false, 'خصم سالب - خطأ');
  
  print('');

  // اختبار 4: التحقق من المبلغ المدفوع
  print('💵 اختبار 4: التحقق من المبلغ المدفوع');
  print('─────────────────────────────────────');
  
  testPaidAmount(100000, 100000, 'نقد', true, 'نقد - مبلغ مطابق');
  testPaidAmount(90000, 100000, 'نقد', false, 'نقد - مبلغ أقل');
  testPaidAmount(50000, 100000, 'دين', true, 'دين - دفع جزئي');
  testPaidAmount(120000, 100000, 'دين', false, 'دين - مبلغ أكبر');
  testPaidAmount(-5000, 100000, 'دين', false, 'مبلغ سالب');
  
  print('');

  // اختبار 5: التحقق من أجور التحميل
  print('🚚 اختبار 5: التحقق من أجور التحميل');
  print('─────────────────────────────────────');
  
  testLoadingFee(5000, true, 'أجور صحيحة');
  testLoadingFee(0, true, 'بدون أجور');
  testLoadingFee(-1000, false, 'أجور سالبة');
  
  print('');

  // اختبار 6: التحقق الشامل من الفاتورة
  print('📄 اختبار 6: التحقق الشامل من الفاتورة');
  print('─────────────────────────────────────');
  
  testInvoice(
    itemsCount: 5,
    totalAmount: 100000,
    discount: 5000,
    paidAmount: 95000,
    loadingFee: 0,
    paymentType: 'نقد',
    shouldPass: true,
    description: 'فاتورة نقدية صحيحة',
  );
  
  testInvoice(
    itemsCount: 0,
    totalAmount: 100000,
    discount: 0,
    paidAmount: 100000,
    loadingFee: 0,
    paymentType: 'نقد',
    shouldPass: false,
    description: 'فاتورة بدون أصناف',
  );
  
  testInvoice(
    itemsCount: 3,
    totalAmount: 100000,
    discount: 60000,
    paidAmount: 40000,
    loadingFee: 0,
    paymentType: 'نقد',
    shouldPass: false,
    description: 'خصم أكثر من 50%',
  );
  
  print('');
  print('═══════════════════════════════════════════════════════════════');
  print('✅ انتهى الاختبار');
  print('═══════════════════════════════════════════════════════════════');
}

// دوال مساعدة للاختبار

void testAmount(double amount, bool shouldPass, String description) {
  final result = FinancialValidationService.validateAmount(amount);
  final passed = result.isValid == shouldPass;
  print('${passed ? "✅" : "❌"} $description: ${amount.toStringAsFixed(0)}');
  if (!result.isValid && result.errorMessage != null) {
    print('   ↳ ${result.errorMessage}');
  }
}

void testQuantity(double quantity, bool shouldPass, String description) {
  final result = FinancialValidationService.validateQuantity(quantity);
  final passed = result.isValid == shouldPass;
  print('${passed ? "✅" : "❌"} $description: ${quantity.toStringAsFixed(0)}');
  if (!result.isValid && result.errorMessage != null) {
    print('   ↳ ${result.errorMessage}');
  }
}

void testDiscount(double discount, double total, bool shouldPass, String description) {
  final result = FinancialValidationService.validateDiscount(discount, total);
  final passed = result.isValid == shouldPass;
  print('${passed ? "✅" : "❌"} $description');
  if (!result.isValid && result.errorMessage != null) {
    print('   ↳ ${result.errorMessage}');
  } else if (result.warningMessage != null) {
    print('   ⚠️ ${result.warningMessage}');
  }
}

void testPaidAmount(double paid, double total, String paymentType, bool shouldPass, String description) {
  final result = FinancialValidationService.validatePaidAmount(paid, total, paymentType);
  final passed = result.isValid == shouldPass;
  print('${passed ? "✅" : "❌"} $description');
  if (!result.isValid && result.errorMessage != null) {
    print('   ↳ ${result.errorMessage}');
  }
}

void testLoadingFee(double fee, bool shouldPass, String description) {
  final result = FinancialValidationService.validateLoadingFee(fee);
  final passed = result.isValid == shouldPass;
  print('${passed ? "✅" : "❌"} $description: ${fee.toStringAsFixed(0)}');
  if (!result.isValid && result.errorMessage != null) {
    print('   ↳ ${result.errorMessage}');
  }
}

void testInvoice({
  required int itemsCount,
  required double totalAmount,
  required double discount,
  required double paidAmount,
  required double loadingFee,
  required String paymentType,
  required bool shouldPass,
  required String description,
}) {
  final result = FinancialValidationService.validateInvoiceBeforeSave(
    itemsCount: itemsCount,
    totalAmount: totalAmount,
    discount: discount,
    paidAmount: paidAmount,
    loadingFee: loadingFee,
    paymentType: paymentType,
  );
  final passed = result.isValid == shouldPass;
  print('${passed ? "✅" : "❌"} $description');
  if (!result.isValid && result.errorMessage != null) {
    print('   ↳ ${result.errorMessage}');
  }
}
