import 'package:flutter/material.dart';
import 'font_settings.dart';
import 'invoice_design_settings.dart';

class AppSettings {
  final List<String> phoneNumbers;
  final int remainingAmountColor;
  final int discountColor;
  final int loadingFeesColor;
  final int totalBeforeDiscountColor;
  final int totalAfterDiscountColor;
  final int previousDebtColor;
  final int currentDebtColor;
  final int electricPhoneColor;
  final int healthPhoneColor;
  final int companyDescriptionColor;
  final String companyDescription;
  final int companyNameColor;
  final int itemSerialColor;
  final int itemDetailsColor;
  final int itemQuantityColor;
  final int itemPriceColor;
  final int itemTotalColor;
  final int noticeColor;
  final int paidAmountColor;
  final FontSettings fontSettings;
  

  
  // إعدادات الفاتورة
  final bool autoScrollInvoice; // التمرير التلقائي عند إضافة عنصر جديد للفاتورة
  
  // 🔄 إعدادات المزامنة
  final bool syncFullTransferMode; // وضع النقل الكامل - رفع جميع البيانات عند المزامنة
  final bool syncShowConfirmation; // إظهار رسالة تأكيد قبل المزامنة
  final bool syncAutoCreateCustomers; // إنشاء العملاء تلقائياً عند استلام معاملات
  
  // 📱 إعدادات قسم المحل (للنسخ الاحتياطي على Telegram)
  final String storeSection; // 'كهربائيات' أو 'صحيات'

  // 💰 إعدادات الأرباح
  final double defaultAdHocProfitPercentage; // نسبة الربح الافتراضية للمواد الخارجية (Ad-Hoc)
  final double manualDebtProfitPercentage; // نسبة الربح للمعاملات اليدوية (إضافة دين)
  
  // 🏪 اسم الفرع (للتمييز بين الفروع عند الرفع)
  final String branchName; // 'الفرع الرئيسي' أو 'الفرع الثاني' أو 'الفرع الثالث'
  
  // 🔔 إعدادات نظام التنبيهات
  final bool areAlertsEnabled;
  final String alertFrequency; // 'startup', 'daily', 'weekly', 'monthly'
  final DateTime? lastAlertShownDate;
  final int expiryAlertThresholdMonths; // ✅ تنبيه قبل انتهاء الصلاحية بـ X أشهر
  
  // 🧾 إعدادات تصميم الفاتورة
  final InvoiceDesignSettings invoiceDesign;
  
  // 📤 إعدادات تيليغرام (لرفع قاعدة البيانات)
  final String? telegramBotToken;
  final String? telegramChannelId;

  // 📦 إعدادات المخزون والتسعير
  final bool allowNegativeStock; // السماح بالبيع عند نفاذ الكمية
  final String costingMethod; // طريقة حساب التكلفة: 'avco' (المتوسط المرجح) أو 'last_purchase' (آخر سعر شراء)
  final int pricingMode; // 1: آخر سعر, 3: متوسط 3, 99: تسعير ذكي
  final double wholesaleCustomerLimit; // الحد الأدنى لتصنيف العميل كجملة (القيمة الافتراضية: 10000.0)
  
  // 📄 إعدادات نسخ التقارير (PDF)
  final bool backupDebtRecordsPdf;
  final bool backupAccountStatementsPdf;

  // 🧭 شريط التنقل الجانبي
  final bool showSideNav;

  AppSettings({
    this.phoneNumbers = const [],
    int? remainingAmountColor,
    int? discountColor,
    int? loadingFeesColor,
    int? totalBeforeDiscountColor,
    int? totalAfterDiscountColor,
    int? previousDebtColor,
    int? currentDebtColor,
    int? electricPhoneColor,
    int? healthPhoneColor,
    int? companyDescriptionColor,
    String? companyDescription,
    int? companyNameColor,
    int? itemSerialColor,
    int? itemDetailsColor,
    int? itemQuantityColor,
    int? itemPriceColor,
    int? itemTotalColor,
    int? noticeColor,
    int? paidAmountColor,
    FontSettings? fontSettings,

    bool? autoScrollInvoice,
    bool? syncFullTransferMode,
    bool? syncShowConfirmation,
    bool? syncAutoCreateCustomers,
    String? storeSection,
    String? branchName,
    bool? areAlertsEnabled,
    String? alertFrequency,
    DateTime? lastAlertShownDate,
    int? expiryAlertThresholdMonths,
    InvoiceDesignSettings? invoiceDesign,
    this.telegramBotToken,
    this.telegramChannelId,
    double? defaultAdHocProfitPercentage,
    double? manualDebtProfitPercentage,
    bool? allowNegativeStock,
    int? pricingMode,
    double? wholesaleCustomerLimit,

    String? costingMethod,
    bool? backupDebtRecordsPdf,
    bool? backupAccountStatementsPdf,
    bool? showSideNav,
  }) : remainingAmountColor = remainingAmountColor ?? Colors.black.value,
       discountColor = discountColor ?? Colors.black.value,
       loadingFeesColor = loadingFeesColor ?? Colors.black.value,
       totalBeforeDiscountColor = totalBeforeDiscountColor ?? Colors.black.value,
       totalAfterDiscountColor = totalAfterDiscountColor ?? Colors.black.value,
       previousDebtColor = previousDebtColor ?? Colors.black.value,
       currentDebtColor = currentDebtColor ?? Colors.black.value,
       electricPhoneColor = electricPhoneColor ?? Colors.black.value,
       healthPhoneColor = healthPhoneColor ?? Colors.black.value,
       companyDescriptionColor = companyDescriptionColor ?? Colors.black.value,
       companyDescription = companyDescription ?? 'لتجارة المواد الكهربائية والكيبلات و العدداليدوية والصحية',
       companyNameColor = companyNameColor ?? Colors.green.value,
       itemSerialColor = itemSerialColor ?? Colors.black.value,
       itemDetailsColor = itemDetailsColor ?? Colors.black.value,
       itemQuantityColor = itemQuantityColor ?? Colors.black.value,
       itemPriceColor = itemPriceColor ?? Colors.black.value,
       itemTotalColor = itemTotalColor ?? Colors.black.value,
       noticeColor = noticeColor ?? Colors.red.value,
       paidAmountColor = paidAmountColor ?? Colors.black.value,
       fontSettings = fontSettings ?? FontSettings(),

       autoScrollInvoice = autoScrollInvoice ?? true,
       syncFullTransferMode = syncFullTransferMode ?? false,
       syncShowConfirmation = syncShowConfirmation ?? true,
       syncAutoCreateCustomers = syncAutoCreateCustomers ?? true,
       storeSection = storeSection ?? 'كهربائيات',
       branchName = branchName ?? 'الفرع الرئيسي',
       areAlertsEnabled = areAlertsEnabled ?? true,
       alertFrequency = alertFrequency ?? 'startup',
       lastAlertShownDate = lastAlertShownDate,
       expiryAlertThresholdMonths = expiryAlertThresholdMonths ?? 3,
       invoiceDesign = invoiceDesign ?? InvoiceDesignSettings.defaultSettings(),
       defaultAdHocProfitPercentage = defaultAdHocProfitPercentage ?? 10.0,
       manualDebtProfitPercentage = manualDebtProfitPercentage ?? 15.0,
       allowNegativeStock = allowNegativeStock ?? false,
       pricingMode = pricingMode ?? 99,
       wholesaleCustomerLimit = wholesaleCustomerLimit ?? 5000000.0,
       costingMethod = costingMethod ?? 'last_purchase',
       backupDebtRecordsPdf = backupDebtRecordsPdf ?? false,
       backupAccountStatementsPdf = backupAccountStatementsPdf ?? false,
       showSideNav = showSideNav ?? false;

  Map<String, dynamic> toJson() => {
        'phoneNumbers': phoneNumbers,
        'remainingAmountColor': remainingAmountColor,
        'discountColor': discountColor,
        'loadingFeesColor': loadingFeesColor,
        'totalBeforeDiscountColor': totalBeforeDiscountColor,
        'totalAfterDiscountColor': totalAfterDiscountColor,
        'previousDebtColor': previousDebtColor,
        'currentDebtColor': currentDebtColor,
        'electricPhoneColor': electricPhoneColor,
        'healthPhoneColor': healthPhoneColor,
        'companyDescriptionColor': companyDescriptionColor,
        'companyDescription': companyDescription,
        'companyNameColor': companyNameColor,
        'itemSerialColor': itemSerialColor,
        'itemDetailsColor': itemDetailsColor,
        'itemQuantityColor': itemQuantityColor,
        'itemPriceColor': itemPriceColor,
        'itemTotalColor': itemTotalColor,
        'noticeColor': noticeColor,
        'paidAmountColor': paidAmountColor,
        'fontSettings': fontSettings.toJson(),

        'autoScrollInvoice': autoScrollInvoice,
        'syncFullTransferMode': syncFullTransferMode,
        'syncShowConfirmation': syncShowConfirmation,
        'syncAutoCreateCustomers': syncAutoCreateCustomers,
        'storeSection': storeSection,
        'branchName': branchName,
        'areAlertsEnabled': areAlertsEnabled,
        'alertFrequency': alertFrequency,
        'lastAlertShownDate': lastAlertShownDate?.toIso8601String(),
        'expiryAlertThresholdMonths': expiryAlertThresholdMonths,
        'invoiceDesign': invoiceDesign.toJson(),
        'telegramBotToken': telegramBotToken,
        'telegramChannelId': telegramChannelId,
        'defaultAdHocProfitPercentage': defaultAdHocProfitPercentage,
        'manualDebtProfitPercentage': manualDebtProfitPercentage,
        'allowNegativeStock': allowNegativeStock,
        'pricingMode': pricingMode,
        'wholesaleCustomerLimit': wholesaleCustomerLimit,

        'costingMethod': costingMethod,
        'backupDebtRecordsPdf': backupDebtRecordsPdf,
        'backupAccountStatementsPdf': backupAccountStatementsPdf,
        'showSideNav': showSideNav,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        phoneNumbers: List<String>.from(json['phoneNumbers'] ?? []),
        remainingAmountColor: json['remainingAmountColor'] ?? Colors.black.value,
        discountColor: json['discountColor'] ?? Colors.black.value,
        loadingFeesColor: json['loadingFeesColor'] ?? Colors.black.value,
        totalBeforeDiscountColor: json['totalBeforeDiscountColor'] ?? Colors.black.value,
        totalAfterDiscountColor: json['totalAfterDiscountColor'] ?? Colors.black.value,
        previousDebtColor: json['previousDebtColor'] ?? Colors.black.value,
        currentDebtColor: json['currentDebtColor'] ?? Colors.black.value,
        electricPhoneColor: json['electricPhoneColor'] ?? Colors.black.value,
        healthPhoneColor: json['healthPhoneColor'] ?? Colors.black.value,
        companyDescriptionColor: json['companyDescriptionColor'] ?? Colors.black.value,
        companyDescription: json['companyDescription'] ?? 'لتجارة المواد الكهربائية والكيبلات و العدداليدوية والصحية',
        companyNameColor: json['companyNameColor'] ?? Colors.green.value,
        itemSerialColor: json['itemSerialColor'] ?? Colors.black.value,
        itemDetailsColor: json['itemDetailsColor'] ?? Colors.black.value,
        itemQuantityColor: json['itemQuantityColor'] ?? Colors.black.value,
        itemPriceColor: json['itemPriceColor'] ?? Colors.black.value,
        itemTotalColor: json['itemTotalColor'] ?? Colors.black.value,
        noticeColor: json['noticeColor'] ?? Colors.red.value,
        paidAmountColor: json['paidAmountColor'] ?? Colors.black.value,
        fontSettings: FontSettings.fromJson(json['fontSettings'] ?? {}),

        autoScrollInvoice: json['autoScrollInvoice'] ?? true,
        syncFullTransferMode: json['syncFullTransferMode'] ?? false,
        syncShowConfirmation: json['syncShowConfirmation'] ?? true,
        syncAutoCreateCustomers: json['syncAutoCreateCustomers'] ?? true,
        storeSection: json['storeSection'] ?? 'كهربائيات',
        branchName: json['branchName'] ?? 'الفرع الرئيسي',
        areAlertsEnabled: json['areAlertsEnabled'] ?? true,
        alertFrequency: json['alertFrequency'] ?? 'startup',
        lastAlertShownDate: json['lastAlertShownDate'] != null ? DateTime.parse(json['lastAlertShownDate']) : null,
        expiryAlertThresholdMonths: json['expiryAlertThresholdMonths'] ?? 3,
        invoiceDesign: json['invoiceDesign'] != null 
            ? InvoiceDesignSettings.fromJson(json['invoiceDesign']) 
            : InvoiceDesignSettings.defaultSettings(),
        telegramBotToken: json['telegramBotToken'],
        telegramChannelId: json['telegramChannelId'],
        defaultAdHocProfitPercentage: (json['defaultAdHocProfitPercentage'] as num?)?.toDouble() ?? 10.0,
        manualDebtProfitPercentage: (json['manualDebtProfitPercentage'] as num?)?.toDouble() ?? 15.0,
        allowNegativeStock: json['allowNegativeStock'] ?? false,
        pricingMode: json['pricingMode'] ?? 99,
        wholesaleCustomerLimit: (json['wholesaleCustomerLimit'] as num?)?.toDouble() ?? 5000000.0,

        costingMethod: json['costingMethod'] ?? 'last_purchase',
        backupDebtRecordsPdf: json['backupDebtRecordsPdf'] ?? false,
        backupAccountStatementsPdf: json['backupAccountStatementsPdf'] ?? false,
        showSideNav: json['showSideNav'] ?? false,
      );

  AppSettings copyWith({
    List<String>? phoneNumbers,
    int? remainingAmountColor,
    int? discountColor,
    int? loadingFeesColor,
    int? totalBeforeDiscountColor,
    int? totalAfterDiscountColor,
    int? previousDebtColor,
    int? currentDebtColor,
    int? electricPhoneColor,
    int? healthPhoneColor,
    int? companyDescriptionColor,
    String? companyDescription,
    int? companyNameColor,
    int? itemSerialColor,
    int? itemDetailsColor,
    int? itemQuantityColor,
    int? itemPriceColor,
    int? itemTotalColor,
    int? noticeColor,
    int? paidAmountColor,
    FontSettings? fontSettings,

    bool? autoScrollInvoice,
    bool? syncFullTransferMode,
    bool? syncShowConfirmation,
    bool? syncAutoCreateCustomers,
    String? storeSection,
    String? branchName,
    bool? areAlertsEnabled,
    String? alertFrequency,
    DateTime? lastAlertShownDate,
    int? expiryAlertThresholdMonths,
    InvoiceDesignSettings? invoiceDesign,
    String? telegramBotToken,
    String? telegramChannelId,
    double? defaultAdHocProfitPercentage,
    double? manualDebtProfitPercentage,
    bool? allowNegativeStock,
    int? pricingMode,
    double? wholesaleCustomerLimit,

    String? costingMethod,
    bool? backupDebtRecordsPdf,
    bool? backupAccountStatementsPdf,
    bool? showSideNav,
  }) {
    return AppSettings(
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
      remainingAmountColor: remainingAmountColor ?? this.remainingAmountColor,
      discountColor: discountColor ?? this.discountColor,
      loadingFeesColor: loadingFeesColor ?? this.loadingFeesColor,
      totalBeforeDiscountColor: totalBeforeDiscountColor ?? this.totalBeforeDiscountColor,
      totalAfterDiscountColor: totalAfterDiscountColor ?? this.totalAfterDiscountColor,
      previousDebtColor: previousDebtColor ?? this.previousDebtColor,
      currentDebtColor: currentDebtColor ?? this.currentDebtColor,
      electricPhoneColor: electricPhoneColor ?? this.electricPhoneColor,
      healthPhoneColor: healthPhoneColor ?? this.healthPhoneColor,
      companyDescriptionColor: companyDescriptionColor ?? this.companyDescriptionColor,
      companyDescription: companyDescription ?? this.companyDescription,
      companyNameColor: companyNameColor ?? this.companyNameColor,
      itemSerialColor: itemSerialColor ?? this.itemSerialColor,
      itemDetailsColor: itemDetailsColor ?? this.itemDetailsColor,
      itemQuantityColor: itemQuantityColor ?? this.itemQuantityColor,
      itemPriceColor: itemPriceColor ?? this.itemPriceColor,
      itemTotalColor: itemTotalColor ?? this.itemTotalColor,
      noticeColor: noticeColor ?? this.noticeColor,
      paidAmountColor: paidAmountColor ?? this.paidAmountColor,
      fontSettings: fontSettings ?? this.fontSettings,

      autoScrollInvoice: autoScrollInvoice ?? this.autoScrollInvoice,
      syncFullTransferMode: syncFullTransferMode ?? this.syncFullTransferMode,
      syncShowConfirmation: syncShowConfirmation ?? this.syncShowConfirmation,
      syncAutoCreateCustomers: syncAutoCreateCustomers ?? this.syncAutoCreateCustomers,
      storeSection: storeSection ?? this.storeSection,
      branchName: branchName ?? this.branchName,
      areAlertsEnabled: areAlertsEnabled ?? this.areAlertsEnabled,
      alertFrequency: alertFrequency ?? this.alertFrequency,
      lastAlertShownDate: lastAlertShownDate ?? this.lastAlertShownDate,
      expiryAlertThresholdMonths: expiryAlertThresholdMonths ?? this.expiryAlertThresholdMonths,
      invoiceDesign: invoiceDesign ?? this.invoiceDesign,
      telegramBotToken: telegramBotToken ?? this.telegramBotToken,
      telegramChannelId: telegramChannelId ?? this.telegramChannelId,
      defaultAdHocProfitPercentage: defaultAdHocProfitPercentage ?? this.defaultAdHocProfitPercentage,
      manualDebtProfitPercentage: manualDebtProfitPercentage ?? this.manualDebtProfitPercentage,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      pricingMode: pricingMode ?? this.pricingMode,
      wholesaleCustomerLimit: wholesaleCustomerLimit ?? this.wholesaleCustomerLimit,

      costingMethod: costingMethod ?? this.costingMethod,
      backupDebtRecordsPdf: backupDebtRecordsPdf ?? this.backupDebtRecordsPdf,
      backupAccountStatementsPdf: backupAccountStatementsPdf ?? this.backupAccountStatementsPdf,
      showSideNav: showSideNav ?? this.showSideNav,
    );
  }
}
