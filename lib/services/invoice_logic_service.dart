// services/invoice_logic_service.dart
// جميع منطق الفاتورة والدوال المساعدة (بدون UI)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/customer.dart';
import '../models/installer.dart';
import '../models/transaction.dart';
import '../services/database_service.dart';
import '../models/printer_device.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import '../services/drive_service.dart';
import '../services/financial_validation_service.dart';
import '../services/financial_audit_service.dart';
import '../utils/money_calculator.dart'; // Added import

class InvoiceLogicService {
  // هنا يتم نقل جميع الدوال المنطقية من شاشة الفاتورة
  // كل دالة يجب أن تأخذ كل المتغيرات المطلوبة كـ parameters
  // لا تستعمل setState أو ScaffoldMessenger هنا
  // فقط منطق الأعمال (Business Logic)

  // دالة تنسيق الأرقام مع فواصل كل ثلاث خانات
  static String _formatNumber(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  // مثال على دالة: (الباقي يتم نقله بنفس الأسلوب)
  static void loadAutoSavedData({
    required bool isViewOnly,
    required Invoice? existingInvoice,
    required GetStorage storage,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required void Function(DateTime) setSelectedDate,
    required void Function(String) setPaymentType,
    required void Function(double) setDiscount,
    required TextEditingController discountController,
    required TextEditingController paidAmountController,
    required void Function(List<InvoiceItem>) setInvoiceItems,
    required TextEditingController totalAmountController,
  }) {
    if (isViewOnly || existingInvoice != null) {
      return;
    }
    final data = storage.read('temp_invoice_data');
    if (data == null) return;
    customerNameController.text = data['customerName'] ?? '';
    customerPhoneController.text = data['customerPhone'] ?? '';
    customerAddressController.text = data['customerAddress'] ?? '';
    installerNameController.text = data['installerName'] ?? '';
    if (data['selectedDate'] != null) {
      setSelectedDate(DateTime.parse(data['selectedDate']));
    }
    setPaymentType(data['paymentType'] ?? 'نقد');
    setDiscount(data['discount'] ?? 0);
    discountController.text = _formatNumber(data['discount'] ?? 0);
    paidAmountController.text = data['paidAmount'] ?? '';
    final items = (data['invoiceItems'] as List<dynamic>).map((item) {
      return InvoiceItem(
        invoiceId: 0,
        productName: item['productName'],
        unit: item['unit'],
        unitPrice: item['unitPrice'],
        costPrice: item['costPrice'] ?? 0,
        quantityIndividual: item['quantityIndividual'],
        quantityLargeUnit: item['quantityLargeUnit'],
        appliedPrice: item['appliedPrice'],
        itemTotal: item['itemTotal'],
        saleType: item['saleType'],
        unitsInLargeUnit: item['unitsInLargeUnit'],
      );
    }).toList();
    setInvoiceItems(items);
    totalAmountController.text = _formatNumber(items
        .fold(0.0, (sum, item) => sum + item.itemTotal));
  }

  // حفظ البيانات تلقائياً
  static void autoSave({
    required bool savedOrSuspended,
    required bool isViewOnly,
    required Invoice? existingInvoice,
    required GetStorage storage,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required List<InvoiceItem> invoiceItems,
  }) {
    if (savedOrSuspended || isViewOnly || existingInvoice != null) {
      return;
    }
    final data = {
      'customerName': customerNameController.text,
      'customerPhone': customerPhoneController.text,
      'customerAddress': customerAddressController.text,
      'installerName': installerNameController.text,
      'selectedDate': selectedDate.toIso8601String(),
      'paymentType': paymentType,
      'discount': discount,
      'paidAmount': paidAmountController.text,
      'invoiceItems': invoiceItems
          .map((item) => {
                'productName': item.productName,
                'unit': item.unit,
                'unitPrice': item.unitPrice,
                'costPrice': item.costPrice,
                'quantityIndividual': item.quantityIndividual,
                'quantityLargeUnit': item.quantityLargeUnit,
                'appliedPrice': item.appliedPrice,
                'itemTotal': item.itemTotal,
                'saleType': item.saleType,
                'unitsInLargeUnit': item.unitsInLargeUnit,
              })
          .toList(),
    };
    storage.write('temp_invoice_data', data);
  }

  // معالج تغيير الحقول مع تأخير
  static void onFieldChanged({
    required Timer? debounceTimer,
    required void Function() autoSave,
    required void Function(Timer) setDebounceTimer,
  }) {
    if (debounceTimer?.isActive ?? false) {
      debounceTimer!.cancel();
    }
    final timer = Timer(const Duration(seconds: 1), autoSave);
    setDebounceTimer(timer);
  }

  // باقي الدوال يتم نقلها بنفس الأسلوب ...

  static void recalculateTotals({
    required List<InvoiceItem> invoiceItems,
    required TextEditingController totalAmountController,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required void Function(void Function()) setState,
  }) {
    double total = invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
    totalAmountController.text = _formatNumber(total);
    if (paymentType == 'نقد') {
      paidAmountController.text = _formatNumber(total - discount);
    }
    setState(() {});
  }

  static Future<Invoice?> saveInvoiceWithBusinessLogic({
    required GlobalKey<FormState> formKey,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required TextEditingController loadingFeeController,
    required List<InvoiceItem> invoiceItems,
    required Invoice? invoiceToManage,
    required DatabaseService db,
    required TextEditingController returnAmountController,
    required GetStorage storage,
    // يمكن إضافة أي متغيرات أخرى حسب الحاجة
  }) async {
    if (!formKey.currentState!.validate()) return null;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // التحقق من صحة البيانات المالية (Financial Validation)
    // ═══════════════════════════════════════════════════════════════════════════
    
    try {
      // 1. التحقق من وجود أصناف
      final itemsValidation = FinancialValidationService.validateInvoiceItems(invoiceItems.length);
      if (!itemsValidation.isValid) {
        throw Exception(itemsValidation.errorMessage ?? 'لا يمكن حفظ فاتورة بدون أصناف');
      }
      
      // 2. حساب المبالغ
      double currentTotalAmount = invoiceItems.fold(0.0, (sum, item) => MoneyCalculator.add(sum, item.itemTotal));
      double paid = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
      final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
      
      // 3. التحقق من أجور التحميل
      final loadingFeeValidation = FinancialValidationService.validateLoadingFee(loadingFee);
      if (!loadingFeeValidation.isValid) {
        throw Exception(loadingFeeValidation.errorMessage ?? 'أجور التحميل غير صحيحة');
      }
      
      // 4. التحقق من الخصم
      final discountValidation = FinancialValidationService.validateDiscount(discount, currentTotalAmount);
      if (!discountValidation.isValid) {
        throw Exception(discountValidation.errorMessage ?? 'الخصم غير صحيح');
      }
      
      // 5. حساب الإجمالي النهائي
      double totalAmount = MoneyCalculator.subtract(MoneyCalculator.add(currentTotalAmount, loadingFee), discount);
      
      // 6. التحقق من المبلغ المدفوع
      final paidValidation = FinancialValidationService.validatePaidAmount(paid, totalAmount, paymentType);
      if (!paidValidation.isValid) {
        throw Exception(paidValidation.errorMessage ?? 'المبلغ المدفوع غير صحيح');
      }
      
      // 7. التحقق الشامل من الفاتورة
      final invoiceValidation = FinancialValidationService.validateInvoiceBeforeSave(
        itemsCount: invoiceItems.length,
        totalAmount: totalAmount,
        discount: discount,
        paidAmount: paid,
        loadingFee: loadingFee,
        paymentType: paymentType,
      );
      if (!invoiceValidation.isValid) {
        throw Exception(invoiceValidation.errorMessage ?? 'بيانات الفاتورة غير صحيحة');
      }
      
      // ═══════════════════════════════════════════════════════════════════════════
      // حفظ الفاتورة (بعد التحقق من صحة البيانات)
      // ═══════════════════════════════════════════════════════════════════════════
      
      // ═══════════════════════════════════════════════════════════════════════════
      // حفظ الفاتورة (بعد التحقق من صحة البيانات)
      // ═══════════════════════════════════════════════════════════════════════════
      
      try {
        // تحضير بيانات العميل
        Customer? customerData;
        if (customerNameController.text.trim().isNotEmpty) {
          customerData = Customer(
            id: null, // سيتم تحديده أو إنشاؤه داخل الترانزاكشن
            name: customerNameController.text.trim(),
            phone: customerPhoneController.text.trim().isEmpty
                ? null
                : customerPhoneController.text.trim(),
            address: customerAddressController.text.trim(),
            createdAt: DateTime.now(),
            lastModifiedAt: DateTime.now(),
            currentTotalDebt: 0.0,
          );
        }

        // تحديد الحالة الجديدة
        String newStatus = 'محفوظة';
        bool newIsLocked = invoiceToManage?.isLocked ?? false;
        if (invoiceToManage != null) {
          if (invoiceToManage.status == 'معلقة') {
            newStatus = 'محفوظة';
            newIsLocked = false;
          }
        } else {
          newIsLocked = false;
        }

        // تحضير كائن الفاتورة
        Invoice invoice = Invoice(
          id: invoiceToManage?.id,
          customerName: customerNameController.text,
          customerPhone: customerPhoneController.text,
          customerAddress: customerAddressController.text,
          installerName: installerNameController.text.isEmpty
              ? null
              : installerNameController.text,
          invoiceDate: selectedDate,
          paymentType: paymentType,
          totalAmount: totalAmount,
          discount: discount,
          amountPaidOnInvoice: paid,
          loadingFee: loadingFee,
          createdAt: invoiceToManage?.createdAt ?? DateTime.now(),
          lastModifiedAt: DateTime.now(),
          customerId: invoiceToManage?.customerId, // سيتم تحديثه داخل الترانزاكشن إذا لزم الأمر
          status: newStatus,
          returnAmount: returnAmountController.text.isNotEmpty
              ? double.parse(returnAmountController.text)
              : 0.0,
          isLocked: false,
        );

        // استدعاء الحفظ الآمن (Transaction)
        final savedInvoice = await db.saveCompleteInvoice(
          invoice: invoice,
          items: invoiceItems,
          customerData: customerData,
          isUpdate: invoiceToManage != null,
          oldInvoice: invoiceToManage,
          createdBy: 'System', // يمكن تحسينه لاحقاً لإضافة اسم المستخدم
        );

        storage.remove('temp_invoice_data');
        return savedInvoice;

      } catch (e) {
        // إعادة رمي الاستثناء مع رسالة واضحة
        print('خطأ في حفظ الفاتورة: $e');
        rethrow;
      }
    } catch (validationError) {
      // خطأ في التحقق من البيانات
      print('خطأ في التحقق من البيانات: $validationError');
      rethrow;
    }
  }

  static Future<Invoice?> autoSaveSuspendedInvoiceWithBusinessLogic({
    required Invoice? invoiceToManage,
    required List<InvoiceItem> invoiceItems,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required TextEditingController returnAmountController,
    required TextEditingController loadingFeeController,
    required DatabaseService db,
  }) async {
    if (invoiceToManage == null ||
        invoiceToManage.status != 'معلقة' ||
        (invoiceToManage.isLocked)) return null;
    // تحضير بيانات العميل
    Customer? customerData;
    if (customerNameController.text.trim().isNotEmpty) {
      customerData = Customer(
        id: null, // سيتم التعامل معه في الترانزاكشن
        name: customerNameController.text.trim(),
        phone: customerPhoneController.text.trim().isEmpty
            ? null
            : customerPhoneController.text.trim(),
        address: customerAddressController.text.trim(),
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
        currentTotalDebt: 0.0,
      );
    }

    double currentTotalAmount =
        invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    // إزالة فواصل الآلاف قبل التحويل
    double paid =
        double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
            0.0;
    final double loadingFee =
        double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
            0.0;
    double totalAmount = (currentTotalAmount + loadingFee) - discount;
    
    Invoice invoice = invoiceToManage.copyWith(
      customerName: customerNameController.text,
      customerPhone: customerPhoneController.text,
      customerAddress: customerAddressController.text,
      installerName: installerNameController.text.isEmpty
          ? null
          : installerNameController.text,
      invoiceDate: selectedDate,
      paymentType: paymentType,
      totalAmount: totalAmount,
      discount: discount,
      amountPaidOnInvoice: paid,
      loadingFee: loadingFee,
      lastModifiedAt: DateTime.now(),
      customerId: invoiceToManage.customerId, // سيتم تحديثه في الترانزاكشن
      returnAmount: returnAmountController.text.isNotEmpty
          ? double.parse(returnAmountController.text)
          : 0.0,
      isLocked: false,
    );

    // استدعاء الحفظ الآمن
    final savedInvoice = await db.saveCompleteInvoice(
      invoice: invoice,
      items: invoiceItems,
      customerData: customerData,
      isUpdate: true,
      oldInvoice: invoiceToManage,
      createdBy: 'AutoSave',
    );
    
    return savedInvoice;
  }
}
