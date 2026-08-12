// lib/models/invoice_input_data.dart
// 🎯 نموذج بيانات إدخال الفاتورة - مشترك بين InvoiceController و FinancialIntegrityGuard

import 'invoice.dart';
import 'invoice_item.dart';

class InvoiceInputData {
  final Invoice? invoiceToManage;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String? installerName;
  final double paidAmount;
  final double loadingFee;
  final double discount;
  final String paymentType;
  final DateTime selectedDate;
  final List<InvoiceItem> invoiceItems;

  bool get isNewInvoice => invoiceToManage == null;

  InvoiceInputData({
    this.invoiceToManage,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    this.installerName,
    required this.paidAmount,
    required this.loadingFee,
    required this.discount,
    required this.paymentType,
    required this.selectedDate,
    required this.invoiceItems,
  });
}
