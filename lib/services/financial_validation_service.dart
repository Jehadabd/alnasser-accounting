// services/financial_validation_service.dart
// خدمة التحقق من صحة البيانات المالية

class ValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? warningMessage;

  ValidationResult.success()
      : isValid = true,
        errorMessage = null,
        warningMessage = null;

  ValidationResult.error(this.errorMessage)
      : isValid = false,
        warningMessage = null;

  ValidationResult.warning(this.warningMessage)
      : isValid = true,
        errorMessage = null;
}

class FinancialValidationService {
  // الحد الأقصى للمبالغ (مليار دينار)
  static const double MAX_AMOUNT = 1000000000.0;
  
  // الحد الأقصى للكميات
  static const double MAX_QUANTITY = 1000000.0;
  
  // نسبة الخصم القصوى (50%)
  static const double MAX_DISCOUNT_PERCENTAGE = 0.5;

  /// التحقق من صحة المبلغ
  static ValidationResult validateAmount(double amount, {String fieldName = 'المبلغ'}) {
    if (amount < 0) {
      return ValidationResult.error('$fieldName لا يمكن أن يكون سالباً');
    }
    if (amount == 0) {
      return ValidationResult.error('$fieldName يجب أن يكون أكبر من صفر');
    }
    if (amount > MAX_AMOUNT) {
      return ValidationResult.error('$fieldName أكبر من الحد المسموح به (${_formatNumber(MAX_AMOUNT)} دينار)');
    }
    return ValidationResult.success();
  }

  /// التحقق من صحة الكمية
  static ValidationResult validateQuantity(double quantity, {String fieldName = 'الكمية'}) {
    if (quantity < 0) {
      return ValidationResult.error('$fieldName لا يمكن أن تكون سالبة');
    }
    if (quantity == 0) {
      return ValidationResult.error('$fieldName يجب أن تكون أكبر من صفر');
    }
    if (quantity > MAX_QUANTITY) {
      return ValidationResult.error('$fieldName أكبر من الحد المسموح به (${_formatNumber(MAX_QUANTITY)})');
    }
    return ValidationResult.success();
  }

  /// التحقق من صحة الخصم
  static ValidationResult validateDiscount(double discount, double totalAmount) {
    if (discount < 0) {
      return ValidationResult.error('الخصم لا يمكن أن يكون سالباً');
    }
    if (discount >= totalAmount) {
      return ValidationResult.error(
        'الخصم (${_formatNumber(discount)} دينار) لا يمكن أن يساوي أو يتجاوز إجمالي الفاتورة (${_formatNumber(totalAmount)} دينار)'
      );
    }
    
    final discountPercentage = totalAmount > 0 ? (discount / totalAmount) : 0;
    if (discountPercentage > MAX_DISCOUNT_PERCENTAGE) {
      return ValidationResult.error(
        'الخصم (${(discountPercentage * 100).toStringAsFixed(1)}%) يتجاوز الحد الأقصى المسموح به (${(MAX_DISCOUNT_PERCENTAGE * 100).toStringAsFixed(0)}%)'
      );
    }
    
    // تحذير إذا كان الخصم كبيراً (أكثر من 30%)
    if (discountPercentage > 0.3) {
      return ValidationResult.warning(
        'تحذير: الخصم كبير نسبياً (${(discountPercentage * 100).toStringAsFixed(1)}%)'
      );
    }
    
    return ValidationResult.success();
  }

  /// التحقق من صحة المبلغ المدفوع
  static ValidationResult validatePaidAmount(
    double paidAmount, 
    double totalAmount, 
    String paymentType
  ) {
    if (paidAmount < 0) {
      return ValidationResult.error('المبلغ المدفوع لا يمكن أن يكون سالباً');
    }
    
    // في حالة الدفع النقدي، يجب أن يساوي المبلغ المدفوع الإجمالي
    if (paymentType == 'نقد') {
      if ((paidAmount - totalAmount).abs() > 0.01) {
        return ValidationResult.error(
          'في حالة الدفع النقدي، يجب أن يساوي المبلغ المدفوع (${_formatNumber(paidAmount)}) الإجمالي (${_formatNumber(totalAmount)})'
        );
      }
    }
    
    // في حالة الدين، لا يمكن أن يتجاوز المبلغ المدفوع الإجمالي
    if (paymentType == 'دين' && paidAmount > totalAmount) {
      return ValidationResult.error(
        'المبلغ المدفوع (${_formatNumber(paidAmount)}) لا يمكن أن يتجاوز إجمالي الفاتورة (${_formatNumber(totalAmount)})'
      );
    }
    
    return ValidationResult.success();
  }

  /// التحقق من صحة أجور التحميل
  static ValidationResult validateLoadingFee(double loadingFee) {
    if (loadingFee < 0) {
      return ValidationResult.error('أجور التحميل لا يمكن أن تكون سالبة');
    }
    if (loadingFee > MAX_AMOUNT) {
      return ValidationResult.error('أجور التحميل أكبر من الحد المسموح به');
    }
    return ValidationResult.success();
  }

  /// التحقق من صحة السعر
  static ValidationResult validatePrice(double price, {String fieldName = 'السعر'}) {
    if (price < 0) {
      return ValidationResult.error('$fieldName لا يمكن أن يكون سالباً');
    }
    if (price == 0) {
      return ValidationResult.warning('$fieldName يساوي صفر - تأكد من صحة البيانات');
    }
    if (price > MAX_AMOUNT) {
      return ValidationResult.error('$fieldName أكبر من الحد المسموح به');
    }
    return ValidationResult.success();
  }

  /// التحقق من صحة التكلفة
  static ValidationResult validateCost(double cost, double sellingPrice) {
    if (cost < 0) {
      return ValidationResult.error('التكلفة لا يمكن أن تكون سالبة');
    }
    if (cost == 0) {
      return ValidationResult.warning('التكلفة تساوي صفر - لن يتم حساب الربح بشكل صحيح');
    }
    if (cost > sellingPrice) {
      return ValidationResult.warning(
        'تحذير: التكلفة (${_formatNumber(cost)}) أكبر من سعر البيع (${_formatNumber(sellingPrice)}) - ستكون هناك خسارة'
      );
    }
    return ValidationResult.success();
  }

  /// التحقق من وجود أصناف في الفاتورة
  static ValidationResult validateInvoiceItems(int itemsCount) {
    if (itemsCount == 0) {
      return ValidationResult.error('لا يمكن حفظ فاتورة بدون أصناف');
    }
    return ValidationResult.success();
  }

  /// التحقق من صحة بيانات الصنف
  static ValidationResult validateInvoiceItem({
    required String productName,
    required double quantity,
    required double price,
    required double cost,
  }) {
    if (productName.trim().isEmpty) {
      return ValidationResult.error('اسم الصنف مطلوب');
    }
    
    final quantityResult = validateQuantity(quantity, fieldName: 'كمية الصنف');
    if (!quantityResult.isValid) return quantityResult;
    
    final priceResult = validatePrice(price, fieldName: 'سعر الصنف');
    if (!priceResult.isValid) return priceResult;
    
    final costResult = validateCost(cost, price);
    if (!costResult.isValid && costResult.errorMessage != null) {
      return costResult;
    }
    
    return ValidationResult.success();
  }

  /// التحقق من صحة معاملة الدين
  static ValidationResult validateDebtTransaction({
    required double amount,
    required double currentDebt,
    required bool isDebt,
  }) {
    final amountResult = validateAmount(amount, fieldName: 'مبلغ المعاملة');
    if (!amountResult.isValid) return amountResult;
    
    // إذا كانت تسديد، تحقق من أن المبلغ لا يتجاوز الدين الحالي
    if (!isDebt && amount > currentDebt) {
      return ValidationResult.error(
        'مبلغ التسديد (${_formatNumber(amount)}) يتجاوز الدين الحالي (${_formatNumber(currentDebt)})'
      );
    }
    
    return ValidationResult.success();
  }

  /// تنسيق الأرقام للعرض
  static String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)} مليون';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)} ألف';
    }
    return number.toStringAsFixed(0);
  }

  /// التحقق الشامل من الفاتورة قبل الحفظ
  static ValidationResult validateInvoiceBeforeSave({
    required int itemsCount,
    required double totalAmount,
    required double discount,
    required double paidAmount,
    required double loadingFee,
    required String paymentType,
  }) {
    // التحقق من وجود أصناف
    final itemsResult = validateInvoiceItems(itemsCount);
    if (!itemsResult.isValid) return itemsResult;
    
    // التحقق من الإجمالي
    final totalResult = validateAmount(totalAmount, fieldName: 'إجمالي الفاتورة');
    if (!totalResult.isValid) return totalResult;
    
    // التحقق من الخصم
    final discountResult = validateDiscount(discount, totalAmount);
    if (!discountResult.isValid) return discountResult;
    
    // التحقق من أجور التحميل
    final loadingFeeResult = validateLoadingFee(loadingFee);
    if (!loadingFeeResult.isValid) return loadingFeeResult;
    
    // حساب الإجمالي النهائي
    final finalTotal = (totalAmount + loadingFee) - discount;
    
    // التحقق من المبلغ المدفوع
    final paidResult = validatePaidAmount(paidAmount, finalTotal, paymentType);
    if (!paidResult.isValid) return paidResult;
    
    return ValidationResult.success();
  }
}
