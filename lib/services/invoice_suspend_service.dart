// services/invoice_suspend_service.dart
import '../models/invoice_item.dart';
import '../models/invoice.dart';
import 'package:get_storage/get_storage.dart';
import '../services/database_service.dart';
import '../models/customer.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';

class InvoiceSuspendService {
  static Future<void> suspendInvoice({
    required GlobalKey<FormState> formKey,
    required List<InvoiceItem> invoiceItems,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required Invoice? invoiceToManage,
    required DatabaseService db,
    required void Function(Invoice?) setInvoiceToManage,
    required void Function(bool) setSavedOrSuspended,
    required void Function() onSuccess,
    required void Function(String) onError,
    required TextEditingController returnAmountController,
  }) async {
    if (!formKey.currentState!.validate()) return;
    for (int i = invoiceItems.length - 1; i >= 0; i--) {
      if (invoiceItems[i].productName.isEmpty) {
        invoiceItems.removeAt(i);
      }
    }
    Customer? customer;
    int? customerId;
    if (customerNameController.text.trim().isNotEmpty) {
      final customers =
          await db.searchCustomers(customerNameController.text.trim());
      customer = customers.isNotEmpty ? customers.first : null;
      customerId = customer?.id;
    }
    double currentTotalAmount =
        invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    double totalAmount = currentTotalAmount - discount;
    double paid = double.tryParse(paidAmountController.text.trim()) ?? 0.0;
    final invoice = Invoice(
      id: invoiceToManage?.id,
      customerName: customerNameController.text.trim(),
      customerPhone: customerPhoneController.text.trim(),
      customerAddress: customerAddressController.text.trim(),
      installerName: installerNameController.text.trim(),
      invoiceDate: selectedDate,
      paymentType: paymentType,
      totalAmount: totalAmount,
      discount: discount,
      amountPaidOnInvoice: paid,
      createdAt: invoiceToManage?.createdAt ?? DateTime.now(),
      lastModifiedAt: DateTime.now(),
      customerId: customerId,
      status: 'معلقة',
      isLocked: false,
      returnAmount: returnAmountController.text.isNotEmpty
          ? double.tryParse(returnAmountController.text) ?? 0.0
          : 0.0,
    );
    int invoiceId;
    if (invoiceToManage != null) {
      invoiceId = invoiceToManage.id!;
      final oldItems = await db.getInvoiceItems(invoiceId);
      for (var oldItem in oldItems) {
        await db.deleteInvoiceItem(oldItem.id!);
      }
      for (final item in invoiceItems) {
        await db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
      }
      await db.updateInvoice(invoice);
      setInvoiceToManage(invoice);
    } else {
      invoiceId = await db.insertInvoice(invoice);
      for (final item in invoiceItems) {
        await db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
      }
      setInvoiceToManage(invoice.copyWith(id: invoiceId));
    }
    setSavedOrSuspended(true);
    onSuccess();
  }

  static Future<Invoice?> suspendInvoiceWithBusinessLogic({
    required GlobalKey<FormState> formKey,
    required List<InvoiceItem> invoiceItems,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required Invoice? invoiceToManage,
    required DatabaseService db,
    required TextEditingController returnAmountController,
    required GetStorage storage,
    required TextEditingController loadingFeeController,
  }) async {
    if (!formKey.currentState!.validate()) return null;
    for (int i = invoiceItems.length - 1; i >= 0; i--) {
      if (invoiceItems[i].productName.isEmpty) {
        invoiceItems.removeAt(i);
      }
    }
    Customer? customer;
    int? customerId;
    if (customerNameController.text.trim().isNotEmpty) {
      final customers =
          await db.searchCustomers(customerNameController.text.trim());
      customer = customers.isNotEmpty ? customers.first : null;
      customerId = customer?.id;
    }
    double currentTotalAmount =
        invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final double loadingFee =
        double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
            0.0;
    double totalAmount = (currentTotalAmount + loadingFee) - discount;
    double paid = double.tryParse(paidAmountController.text.trim()) ?? 0.0;
    final invoice = Invoice(
      id: invoiceToManage?.id,
      customerName: customerNameController.text.trim(),
      customerPhone: customerPhoneController.text.trim(),
      customerAddress: customerAddressController.text.trim(),
      installerName: installerNameController.text.trim(),
      invoiceDate: selectedDate,
      paymentType: paymentType,
      totalAmount: totalAmount,
      discount: discount,
      amountPaidOnInvoice: paid,
      loadingFee: loadingFee,
      createdAt: invoiceToManage?.createdAt ?? DateTime.now(),
      lastModifiedAt: DateTime.now(),
      customerId: customerId,
      status: 'معلقة',
      isLocked: false,
      returnAmount: returnAmountController.text.isNotEmpty
          ? double.tryParse(returnAmountController.text) ?? 0.0
          : 0.0,
    );
    int invoiceId;
    if (invoiceToManage != null) {
      invoiceId = invoiceToManage.id!;
      final oldItems = await db.getInvoiceItems(invoiceId);
      for (var oldItem in oldItems) {
        await db.deleteInvoiceItem(oldItem.id!);
      }
      for (final item in invoiceItems) {
        await db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
      }
      await db.updateInvoice(invoice);
      return invoice;
    } else {
      invoiceId = await db.insertInvoice(invoice);
      for (final item in invoiceItems) {
        await db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
      }
      return invoice.copyWith(id: invoiceId);
    }
  }

  static Future<void> autoSaveSuspendedInvoice({
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
    required DatabaseService db,
    required void Function(Invoice) setInvoiceToManage,
  }) async {
    if (invoiceToManage == null ||
        invoiceToManage.status != 'معلقة' ||
        (invoiceToManage.isLocked)) return;
    Customer? customer;
    if (customerNameController.text.trim().isNotEmpty) {
      final customers = await db.getAllCustomers();
      try {
        customer = customers.firstWhere(
          (c) =>
              c.name.trim() == customerNameController.text.trim() &&
              (c.phone == null ||
                  c.phone!.isEmpty ||
                  customerPhoneController.text.trim().isEmpty ||
                  c.phone == customerPhoneController.text.trim()),
        );
      } catch (e) {
        customer = null;
      }
    }
    double currentTotalAmount =
        invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    // احرص على إزالة فواصل الآلاف قبل تحويل النص إلى رقم لتفادي فشل التحويل
    double paid =
        double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
            0.0;
    double totalAmount = currentTotalAmount - discount;
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
      lastModifiedAt: DateTime.now(),
      customerId: customer?.id,
      returnAmount: returnAmountController.text.isNotEmpty
          ? double.parse(returnAmountController.text)
          : 0.0,
      isLocked: false,
    );
    int invoiceId = invoiceToManage.id!;
    final oldItems = await db.getInvoiceItems(invoiceId);
    for (var oldItem in oldItems) {
      await db.deleteInvoiceItem(oldItem.id!);
    }
    for (var item in invoiceItems) {
      item.invoiceId = invoiceId;
      await db.insertInvoiceItem(item);
    }
    await db.updateInvoice(invoice);
    setInvoiceToManage(invoice);
  }

  static void resetInvoiceScreen({
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required TextEditingController productSearchController,
    required TextEditingController quantityController,
    required TextEditingController paidAmountController,
    required TextEditingController discountController,
    required void Function(double) setDiscount,
    required void Function(double?) setSelectedPriceLevel,
    required void Function(Product?) setSelectedProduct,
    required void Function(bool) setUseLargeUnit,
    required void Function(String) setPaymentType,
    required void Function(DateTime) setSelectedDate,
    required List<InvoiceItem> invoiceItems,
    required List<dynamic> focusNodesList,
    required void Function(List<InvoiceItem>) setInvoiceItems,
    required void Function(List<dynamic>) setFocusNodesList,
    required void Function(List<Product>) setSearchResults,
    required TextEditingController totalAmountController,
    required void Function(bool) setSavedOrSuspended,
    required GetStorage storage,
  }) {
    customerNameController.clear();
    customerPhoneController.clear();
    customerAddressController.clear();
    installerNameController.clear();
    productSearchController.clear();
    quantityController.clear();
    paidAmountController.clear();
    discountController.clear();
    setDiscount(0.0);
    setSelectedPriceLevel(null);
    setSelectedProduct(null);
    setUseLargeUnit(false);
    setPaymentType('نقد');
    setSelectedDate(DateTime.now());
    invoiceItems.clear();
    for (final node in focusNodesList) {
      node.dispose();
    }
    focusNodesList.clear();
    setInvoiceItems([]);
    setFocusNodesList([]);
    setSearchResults([]);
    totalAmountController.text = '0';
    setSavedOrSuspended(false);
    storage.remove('temp_invoice_data');
  }
}
