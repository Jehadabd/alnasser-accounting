class FontSettings {
  // إعدادات الخط لكل عنصر من عناصر الفاتورة
  final FontElementSettings serialNumber;      // التسلسل
  final FontElementSettings productId;         // الـ ID
  final FontElementSettings productDetails;    // التفاصيل
  final FontElementSettings quantity;          // العدد
  final FontElementSettings unitsCount;        // عدد الوحدات
  final FontElementSettings price;             // السعر
  final FontElementSettings amount;            // المبلغ
  final FontElementSettings remainingAmount;   // المبلغ المتبقي
  final FontElementSettings paidAmount;        // المبلغ المدفوع
  final FontElementSettings totalBeforeDiscount; // الإجمالي قبل الخصم
  final FontElementSettings discount;          // الخصم
  final FontElementSettings totalAfterDiscount; // الإجمالي بعد الخصم
  final FontElementSettings previousDebt;     // الدين السابق
  final FontElementSettings previousRequiredAmount; // المبلغ المطلوب السابق
  final FontElementSettings currentRequiredAmount; // المبلغ المطلوب الحالي
  final FontElementSettings shippingFees;     // أجور التحميل

  FontSettings({
    FontElementSettings? serialNumber,
    FontElementSettings? productId,
    FontElementSettings? productDetails,
    FontElementSettings? quantity,
    FontElementSettings? unitsCount,
    FontElementSettings? price,
    FontElementSettings? amount,
    FontElementSettings? remainingAmount,
    FontElementSettings? paidAmount,
    FontElementSettings? totalBeforeDiscount,
    FontElementSettings? discount,
    FontElementSettings? totalAfterDiscount,
    FontElementSettings? previousDebt,
    FontElementSettings? previousRequiredAmount,
    FontElementSettings? currentRequiredAmount,
    FontElementSettings? shippingFees,
  }) : 
    serialNumber = serialNumber ?? FontElementSettings(),
    productId = productId ?? FontElementSettings(),
    productDetails = productDetails ?? FontElementSettings(),
    quantity = quantity ?? FontElementSettings(),
    unitsCount = unitsCount ?? FontElementSettings(),
    price = price ?? FontElementSettings(),
    amount = amount ?? FontElementSettings(),
    remainingAmount = remainingAmount ?? FontElementSettings(),
    paidAmount = paidAmount ?? FontElementSettings(),
    totalBeforeDiscount = totalBeforeDiscount ?? FontElementSettings(),
    discount = discount ?? FontElementSettings(),
    totalAfterDiscount = totalAfterDiscount ?? FontElementSettings(),
    previousDebt = previousDebt ?? FontElementSettings(),
    previousRequiredAmount = previousRequiredAmount ?? FontElementSettings(),
    currentRequiredAmount = currentRequiredAmount ?? FontElementSettings(),
    shippingFees = shippingFees ?? FontElementSettings();

  Map<String, dynamic> toJson() => {
        'serialNumber': serialNumber.toJson(),
        'productId': productId.toJson(),
        'productDetails': productDetails.toJson(),
        'quantity': quantity.toJson(),
        'unitsCount': unitsCount.toJson(),
        'price': price.toJson(),
        'amount': amount.toJson(),
        'remainingAmount': remainingAmount.toJson(),
        'paidAmount': paidAmount.toJson(),
        'totalBeforeDiscount': totalBeforeDiscount.toJson(),
        'discount': discount.toJson(),
        'totalAfterDiscount': totalAfterDiscount.toJson(),
        'previousDebt': previousDebt.toJson(),
        'previousRequiredAmount': previousRequiredAmount.toJson(),
        'currentRequiredAmount': currentRequiredAmount.toJson(),
        'shippingFees': shippingFees.toJson(),
      };

  factory FontSettings.fromJson(Map<String, dynamic> json) => FontSettings(
        serialNumber: FontElementSettings.fromJson(json['serialNumber'] ?? {}),
        productId: FontElementSettings.fromJson(json['productId'] ?? {}),
        productDetails: FontElementSettings.fromJson(json['productDetails'] ?? {}),
        quantity: FontElementSettings.fromJson(json['quantity'] ?? {}),
        unitsCount: FontElementSettings.fromJson(json['unitsCount'] ?? {}),
        price: FontElementSettings.fromJson(json['price'] ?? {}),
        amount: FontElementSettings.fromJson(json['amount'] ?? {}),
        remainingAmount: FontElementSettings.fromJson(json['remainingAmount'] ?? {}),
        paidAmount: FontElementSettings.fromJson(json['paidAmount'] ?? {}),
        totalBeforeDiscount: FontElementSettings.fromJson(json['totalBeforeDiscount'] ?? {}),
        discount: FontElementSettings.fromJson(json['discount'] ?? {}),
        totalAfterDiscount: FontElementSettings.fromJson(json['totalAfterDiscount'] ?? {}),
        previousDebt: FontElementSettings.fromJson(json['previousDebt'] ?? {}),
        previousRequiredAmount: FontElementSettings.fromJson(json['previousRequiredAmount'] ?? {}),
        currentRequiredAmount: FontElementSettings.fromJson(json['currentRequiredAmount'] ?? {}),
        shippingFees: FontElementSettings.fromJson(json['shippingFees'] ?? {}),
      );

  FontSettings copyWith({
    FontElementSettings? serialNumber,
    FontElementSettings? productId,
    FontElementSettings? productDetails,
    FontElementSettings? quantity,
    FontElementSettings? unitsCount,
    FontElementSettings? price,
    FontElementSettings? amount,
    FontElementSettings? remainingAmount,
    FontElementSettings? paidAmount,
    FontElementSettings? totalBeforeDiscount,
    FontElementSettings? discount,
    FontElementSettings? totalAfterDiscount,
    FontElementSettings? previousDebt,
    FontElementSettings? previousRequiredAmount,
    FontElementSettings? currentRequiredAmount,
    FontElementSettings? shippingFees,
  }) {
    return FontSettings(
      serialNumber: serialNumber ?? this.serialNumber,
      productId: productId ?? this.productId,
      productDetails: productDetails ?? this.productDetails,
      quantity: quantity ?? this.quantity,
      unitsCount: unitsCount ?? this.unitsCount,
      price: price ?? this.price,
      amount: amount ?? this.amount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      totalBeforeDiscount: totalBeforeDiscount ?? this.totalBeforeDiscount,
      discount: discount ?? this.discount,
      totalAfterDiscount: totalAfterDiscount ?? this.totalAfterDiscount,
      previousDebt: previousDebt ?? this.previousDebt,
      previousRequiredAmount: previousRequiredAmount ?? this.previousRequiredAmount,
      currentRequiredAmount: currentRequiredAmount ?? this.currentRequiredAmount,
      shippingFees: shippingFees ?? this.shippingFees,
    );
  }

  @override
  String toString() {
    return 'FontSettings(serialNumber: $serialNumber, productId: $productId, productDetails: $productDetails, quantity: $quantity, unitsCount: $unitsCount, price: $price, amount: $amount, remainingAmount: $remainingAmount, paidAmount: $paidAmount, totalBeforeDiscount: $totalBeforeDiscount, discount: $discount, totalAfterDiscount: $totalAfterDiscount, previousDebt: $previousDebt, previousRequiredAmount: $previousRequiredAmount, currentRequiredAmount: $currentRequiredAmount, shippingFees: $shippingFees)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FontSettings &&
        other.serialNumber == serialNumber &&
        other.productId == productId &&
        other.productDetails == productDetails &&
        other.quantity == quantity &&
        other.unitsCount == unitsCount &&
        other.price == price &&
        other.amount == amount &&
        other.remainingAmount == remainingAmount &&
        other.paidAmount == paidAmount &&
        other.totalBeforeDiscount == totalBeforeDiscount &&
        other.discount == discount &&
        other.totalAfterDiscount == totalAfterDiscount &&
        other.previousDebt == previousDebt &&
        other.previousRequiredAmount == previousRequiredAmount &&
        other.currentRequiredAmount == currentRequiredAmount &&
        other.shippingFees == shippingFees;
  }

  @override
  int get hashCode => Object.hashAll([
        serialNumber,
        productId,
        productDetails,
        quantity,
        unitsCount,
        price,
        amount,
        remainingAmount,
        paidAmount,
        totalBeforeDiscount,
        discount,
        totalAfterDiscount,
        previousDebt,
        previousRequiredAmount,
        currentRequiredAmount,
        shippingFees,
      ]);
}

/// إعدادات الخط لعنصر واحد من عناصر الفاتورة
class FontElementSettings {
  final String fontFamily;
  final String fontWeight;

  // الأوزان المتاحة للخط
  static const List<String> availableWeights = [
    'عادي',
    'متوسط', 
    'غامق',
    'غامق جداً',
    'غامق جداً جداً جداً',
  ];

  FontElementSettings({
    this.fontFamily = 'Amiri-Regular',
    this.fontWeight = 'عادي',
  });

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'fontWeight': fontWeight,
      };

  factory FontElementSettings.fromJson(Map<String, dynamic> json) => FontElementSettings(
        fontFamily: json['fontFamily'] ?? 'Amiri-Regular',
        fontWeight: json['fontWeight'] ?? 'عادي',
      );

  FontElementSettings copyWith({
    String? fontFamily,
    String? fontWeight,
  }) {
    return FontElementSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
    );
  }

  @override
  String toString() {
    return 'FontElementSettings(fontFamily: $fontFamily, fontWeight: $fontWeight)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FontElementSettings &&
        other.fontFamily == fontFamily &&
        other.fontWeight == fontWeight;
  }

  @override
  int get hashCode => fontFamily.hashCode ^ fontWeight.hashCode;
}
