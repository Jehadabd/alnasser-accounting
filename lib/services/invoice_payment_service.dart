// services/invoice_payment_service.dart
import '../models/invoice_item.dart';
import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import '../models/transaction.dart';
import 'package:uuid/uuid.dart';

class InvoicePaymentService {
  // دالة تنسيق الأرقام مع فواصل كل ثلاث خانات
  static String _formatNumber(num value) {
    // إزالة الأصفار الزائدة بعد الفاصلة العشرية
    if (value == value.toInt()) {
      return value.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
    }
    String formatted = value.toStringAsFixed(2);
    // إزالة الأصفار الزائدة
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }
    // إضافة الفواصل
    final parts = formatted.split('.');
    parts[0] = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return parts.join('.');
  }

  // دالة لإعادة حساب المجاميع
  static void recalculateTotals(
      List<InvoiceItem> invoiceItems,
      TextEditingController totalAmountController,
      String paymentType,
      double discount,
      TextEditingController paidAmountController,
      void Function(void Function()) setState) {
    double total = invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
    totalAmountController.text = _formatNumber(total);
    if (paymentType == 'نقد') {
      paidAmountController.text = _formatNumber(total - discount);
    }
    setState(() {});
  }

  // دالة مركزية لحماية الخصم
  static void guardDiscount({
    required List<InvoiceItem> invoiceItems,
    required double discount,
    required TextEditingController discountController,
    required void Function(double) setDiscount,
  }) {
    final currentTotalAmount =
        invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    // الحد الأعلى للخصم هو أقل من نصف الإجمالي
    final maxDiscount = (currentTotalAmount / 2) - 1;
    double newDiscount = discount;
    if (discount > maxDiscount) {
      newDiscount = maxDiscount > 0 ? maxDiscount : 0.0;
      discountController.text = _formatNumber(newDiscount);
    }
    if (discount < 0) {
      newDiscount = 0.0;
      discountController.text = '0';
    }
    setDiscount(newDiscount);
  }

  // دالة لتحديث المبلغ المسدد تلقائيًا إذا كان الدفع نقد
  static void updatePaidAmountIfCash({
    required String paymentType,
    required List<InvoiceItem> invoiceItems,
    required double discount,
    required TextEditingController paidAmountController,
  }) {
    if (paymentType == 'نقد') {
      final currentTotalAmount =
          invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final total = currentTotalAmount - discount;
      paidAmountController.text =
          _formatNumber(total.clamp(0, double.infinity));
    }
  }

  static Future<void> saveReturnAmount({
    required Invoice? invoiceToManage,
    required DatabaseService db,
    required double value,
    required void Function(Invoice?) setInvoiceToManage,
    required void Function(bool) setIsViewOnly,
  }) async {
    if (invoiceToManage == null || invoiceToManage.isLocked) return;
    final updatedInvoice =
        invoiceToManage.copyWith(returnAmount: value, isLocked: true);
    await db.updateInvoice(updatedInvoice);
    if (updatedInvoice.installerName != null &&
        updatedInvoice.installerName!.isNotEmpty) {
      final installer =
          await db.getInstallerByName(updatedInvoice.installerName!);
      if (installer != null) {
        final newTotal =
            (installer.totalBilledAmount - value).clamp(0.0, double.infinity);
        final updatedInstaller =
            installer.copyWith(totalBilledAmount: newTotal);
        await db.updateInstaller(updatedInstaller);
      }
    }
    if (updatedInvoice.paymentType == 'دين' &&
        updatedInvoice.customerId != null &&
        value > 0) {
      final customer = await db.getCustomerById(updatedInvoice.customerId!);
      if (customer != null) {
        final newDebt =
            (customer.currentTotalDebt - value).clamp(0.0, double.infinity);
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: newDebt,
          lastModifiedAt: DateTime.now(),
        );
        await db.updateCustomer(updatedCustomer);
        final txUuid = const Uuid().v4();
        await db.insertTransaction(
          DebtTransaction(
            id: null,
            customerId: customer.id!,
            invoiceId: updatedInvoice.id!,
            amountChanged: -value,
            transactionDate: DateTime.now(),
            newBalanceAfterTransaction: newDebt,
            transactionNote: 'تسديد راجع على الفاتورة رقم ${updatedInvoice.id}',
            transactionType: 'return_payment',
            createdAt: DateTime.now(),
            transactionUuid: txUuid,
          ),
        );
      }
    }
    final updatedInvoiceFromDb = await db.getInvoiceById(invoiceToManage.id!);
    setInvoiceToManage(updatedInvoiceFromDb);
    setIsViewOnly(true);
  }
}
