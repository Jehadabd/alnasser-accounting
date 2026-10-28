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
  final bool enableSmartSearchRamCache; // 🧠 ذاكرة مؤقتة لعلاقات الفاتورة الحالية (بحث أسرع)

  // 📤 رفع الفواتير إلى تيليغرام (مع زر الرفع): 'each' فاتورة فاتورة، 'combined' ملف PDF واحد، 'off' بلا رفع
  final String telegramRegularInvoicesMode; // فواتير «إنشاء فاتورة» (عادية/جملة)
  final String telegramPosInvoicesMode; // إيصالات الكاشير
  final bool telegramResendEdited; // فاتورة رُفعت ثم عُدّلت ⇒ تُرفع نسختها المعدّلة

  // 🏷️ الضغط على «الخصم» في الفاتورة: الخصم = هذه النسبة × ربح الفاتورة
  final double discountProfitPercent;

  // 🧾 إشعار مدين/دائن بعد كل إضافة أو إرجاع على فاتورة: 'ask' يسأل، 'never' لا يظهر
  final String adjustmentVoucherMode;

  // ☁️ زر «رفع البيانات»: ترتيب الوجهات والمطفأ منها (UploadTargets)
  final List<String> uploadOrder;
  final List<String> uploadDisabled;
  
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
    this.lastAlertShownDate,
    int? expiryAlertThresholdMonths,
    InvoiceDesignSettings? invoiceDesign,
    this.telegramBotToken,
    this.telegramChannelId,
    double? defaultAdHocProfitPercentage,
    double? manualDebtProfitPercentage,
    bool? allowNegativeStock,
    int? pricingMode,
    double? wholesaleCustomerLimit,
    bool? enableSmartSearchRamCache,
    String? telegramRegularInvoicesMode,
    String? telegramPosInvoicesMode,
    bool? telegramResendEdited,
    List<String>? uploadOrder,
    List<String>? uploadDisabled,
    double? discountProfitPercent,
    String? adjustmentVoucherMode,

    String? costingMethod,
    bool? backupDebtRecordsPdf,
    bool? backupAccountStatementsPdf,
    bool? showSideNav,
  }) : remainingAmountColor = remainingAmountColor ?? Colors.black.toARGB32(),
       discountColor = discountColor ?? Colors.black.toARGB32(),
       loadingFeesColor = loadingFeesColor ?? Colors.black.toARGB32(),
       totalBeforeDiscountColor = totalBeforeDiscountColor ?? Colors.black.toARGB32(),
       totalAfterDiscountColor = totalAfterDiscountColor ?? Colors.black.toARGB32(),
       previousDebtColor = previousDebtColor ?? Colors.black.toARGB32(),
       currentDebtColor = currentDebtColor ?? Colors.black.toARGB32(),
       electricPhoneColor = electricPhoneColor ?? Colors.black.toARGB32(),
       healthPhoneColor = healthPhoneColor ?? Colors.black.toARGB32(),
       companyDescriptionColor = companyDescriptionColor ?? Colors.black.toARGB32(),
       companyDescription = companyDescription ?? 'لتجارة المواد الكهربائية والكيبلات و العدداليدوية والصحية',
       companyNameColor = companyNameColor ?? Colors.green.toARGB32(),
       itemSerialColor = itemSerialColor ?? Colors.black.toARGB32(),
       itemDetailsColor = itemDetailsColor ?? Colors.black.toARGB32(),
       itemQuantityColor = itemQuantityColor ?? Colors.black.toARGB32(),
       itemPriceColor = itemPriceColor ?? Colors.black.toARGB32(),
       itemTotalColor = itemTotalColor ?? Colors.black.toARGB32(),
       noticeColor = noticeColor ?? Colors.red.toARGB32(),
       paidAmountColor = paidAmountColor ?? Colors.black.toARGB32(),
       fontSettings = fontSettings ?? FontSettings(),

       autoScrollInvoice = autoScrollInvoice ?? true,
       syncFullTransferMode = syncFullTransferMode ?? false,
       syncShowConfirmation = syncShowConfirmation ?? true,
       syncAutoCreateCustomers = syncAutoCreateCustomers ?? true,
       storeSection = storeSection ?? 'كهربائيات',
       branchName = branchName ?? 'الفرع الرئيسي',
       areAlertsEnabled = areAlertsEnabled ?? true,
       alertFrequency = alertFrequency ?? 'startup',
       expiryAlertThresholdMonths = expiryAlertThresholdMonths ?? 3,
       invoiceDesign = invoiceDesign ?? InvoiceDesignSettings.defaultSettings(),
       defaultAdHocProfitPercentage = defaultAdHocProfitPercentage ?? 10.0,
       manualDebtProfitPercentage = manualDebtProfitPercentage ?? 15.0,
       allowNegativeStock = allowNegativeStock ?? false,
       pricingMode = pricingMode ?? 99,
       wholesaleCustomerLimit = wholesaleCustomerLimit ?? 5000000.0,
       enableSmartSearchRamCache = enableSmartSearchRamCache ?? true,
       telegramRegularInvoicesMode = telegramRegularInvoicesMode ?? 'each',
       telegramPosInvoicesMode = telegramPosInvoicesMode ?? 'each',
       telegramResendEdited = telegramResendEdited ?? true,
       uploadOrder = uploadOrder ?? const ['telegram', 'dropbox', 'discord', 'gdrive'],
       uploadDisabled = uploadDisabled ?? const [],
       discountProfitPercent = discountProfitPercent ?? 10.0,
       adjustmentVoucherMode = adjustmentVoucherMode ?? 'ask',
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
        'enableSmartSearchRamCache': enableSmartSearchRamCache,
        'telegramRegularInvoicesMode': telegramRegularInvoicesMode,
        'telegramPosInvoicesMode': telegramPosInvoicesMode,
        'telegramResendEdited': telegramResendEdited,
        'uploadOrder': uploadOrder,
        'uploadDisabled': uploadDisabled,
        'discountProfitPercent': discountProfitPercent,
        'adjustmentVoucherMode': adjustmentVoucherMode,

        'costingMethod': costingMethod,
        'backupDebtRecordsPdf': backupDebtRecordsPdf,
        'backupAccountStatementsPdf': backupAccountStatementsPdf,
        'showSideNav': showSideNav,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        phoneNumbers: List<String>.from(json['phoneNumbers'] ?? []),
        remainingAmountColor: json['remainingAmountColor'] ?? Colors.black.toARGB32(),
        discountColor: json['discountColor'] ?? Colors.black.toARGB32(),
        loadingFeesColor: json['loadingFeesColor'] ?? Colors.black.toARGB32(),
        totalBeforeDiscountColor: json['totalBeforeDiscountColor'] ?? Colors.black.toARGB32(),
        totalAfterDiscountColor: json['totalAfterDiscountColor'] ?? Colors.black.toARGB32(),
        previousDebtColor: json['previousDebtColor'] ?? Colors.black.toARGB32(),
        currentDebtColor: json['currentDebtColor'] ?? Colors.black.toARGB32(),
        electricPhoneColor: json['electricPhoneColor'] ?? Colors.black.toARGB32(),
        healthPhoneColor: json['healthPhoneColor'] ?? Colors.black.toARGB32(),
        companyDescriptionColor: json['companyDescriptionColor'] ?? Colors.black.toARGB32(),
        companyDescription: json['companyDescription'] ?? 'لتجارة المواد الكهربائية والكيبلات و العدداليدوية والصحية',
        companyNameColor: json['companyNameColor'] ?? Colors.green.toARGB32(),
        itemSerialColor: json['itemSerialColor'] ?? Colors.black.toARGB32(),
        itemDetailsColor: json['itemDetailsColor'] ?? Colors.black.toARGB32(),
        itemQuantityColor: json['itemQuantityColor'] ?? Colors.black.toARGB32(),
        itemPriceColor: json['itemPriceColor'] ?? Colors.black.toARGB32(),
        itemTotalColor: json['itemTotalColor'] ?? Colors.black.toARGB32(),
        noticeColor: json['noticeColor'] ?? Colors.red.toARGB32(),
        paidAmountColor: json['paidAmountColor'] ?? Colors.black.toARGB32(),
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
        enableSmartSearchRamCache: json['enableSmartSearchRamCache'] ?? true,
        telegramRegularInvoicesMode: json['telegramRegularInvoicesMode'] as String? ?? 'each',
        telegramPosInvoicesMode: json['telegramPosInvoicesMode'] as String? ?? 'each',
        telegramResendEdited: json['telegramResendEdited'] ?? true,
        uploadOrder: (json['uploadOrder'] as List?)?.map((e) => '$e').toList(),
        uploadDisabled: (json['uploadDisabled'] as List?)?.map((e) => '$e').toList(),
        discountProfitPercent: (json['discountProfitPercent'] as num?)?.toDouble() ?? 10.0,
        adjustmentVoucherMode: json['adjustmentVoucherMode'] as String? ?? 'ask',

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
    bool? enableSmartSearchRamCache,
    String? telegramRegularInvoicesMode,
    String? telegramPosInvoicesMode,
    bool? telegramResendEdited,
    List<String>? uploadOrder,
    List<String>? uploadDisabled,
    double? discountProfitPercent,
    String? adjustmentVoucherMode,

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
      enableSmartSearchRamCache: enableSmartSearchRamCache ?? this.enableSmartSearchRamCache,
      telegramRegularInvoicesMode: telegramRegularInvoicesMode ?? this.telegramRegularInvoicesMode,
      telegramPosInvoicesMode: telegramPosInvoicesMode ?? this.telegramPosInvoicesMode,
      telegramResendEdited: telegramResendEdited ?? this.telegramResendEdited,
      uploadOrder: uploadOrder ?? this.uploadOrder,
      uploadDisabled: uploadDisabled ?? this.uploadDisabled,
      discountProfitPercent: discountProfitPercent ?? this.discountProfitPercent,
      adjustmentVoucherMode: adjustmentVoucherMode ?? this.adjustmentVoucherMode,

      costingMethod: costingMethod ?? this.costingMethod,
      backupDebtRecordsPdf: backupDebtRecordsPdf ?? this.backupDebtRecordsPdf,
      backupAccountStatementsPdf: backupAccountStatementsPdf ?? this.backupAccountStatementsPdf,
      showSideNav: showSideNav ?? this.showSideNav,
    );
  }
}
