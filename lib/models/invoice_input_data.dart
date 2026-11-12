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

  /// 👷 نقاط المؤسس لكل 100,000 لهذه الفاتورة (ميزة حساب المالك). 0 = بلا نقاط.
  final double pointsRate;
  final double paidAmount;
  final double loadingFee;
  final double discount;
  final String paymentType;
  final DateTime selectedDate;
  final List<InvoiceItem> invoiceItems;

  /// 🔁 ما سُدّد من هذه الفاتورة سابقاً بوصولات قبض (فاتورة «آجل — مسددة بالكامل»).
  /// null = يبقى كما هو في الفاتورة المحفوظة (ويُصفَّر إن صارت نقداً).
  final double? prepaidByReceipts;

  bool get isNewInvoice => invoiceToManage == null;

  InvoiceInputData({
    this.invoiceToManage,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    this.installerName,
    this.pointsRate = 0.0,
    required this.paidAmount,
    required this.loadingFee,
    required this.discount,
    required this.paymentType,
    required this.selectedDate,
    required this.invoiceItems,
    this.prepaidByReceipts,
  });

  InvoiceInputData copyWith({
    String? paymentType,
    double? paidAmount,
    double? loadingFee,
    double? discount,
    double? prepaidByReceipts,
  }) =>
      InvoiceInputData(
        invoiceToManage: invoiceToManage,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        installerName: installerName,
        pointsRate: pointsRate,
        paidAmount: paidAmount ?? this.paidAmount,
        loadingFee: loadingFee ?? this.loadingFee,
        discount: discount ?? this.discount,
        paymentType: paymentType ?? this.paymentType,
        selectedDate: selectedDate,
        invoiceItems: invoiceItems,
        prepaidByReceipts: prepaidByReceipts ?? this.prepaidByReceipts,
      );
}
