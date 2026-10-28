// lib/owner/ai_invoice/ai_purchase_prefill.dart
//
// ما تنقله شاشة مراجعة الذكاء الاصطناعي إلى شاشة «فاتورة شراء» العادية.
// الحفظ نفسه (المخزون، الدين، القيود) يبقى في شاشة الشراء كما هو تماماً.

import '../../models/purchase_invoice_item.dart';

class AiPurchasePrefill {
  AiPurchasePrefill({
    required this.items,
    this.invoiceNumber = '',
    this.date,
    this.currency = 'IQD',
    this.isCash = false,
    this.paidAmount = 0,
    this.attachmentPath,
    this.supplierId,
    Map<String, String>? originalNames,
  }) : originalNames = originalNames ?? {};

  final List<PurchaseInvoiceItem> items; // productId = -1 ⇒ مادة جديدة تُعرَّف في شاشة الشراء
  final String invoiceNumber;
  final DateTime? date;
  final String currency;
  final bool isCash;
  final double paidAmount;
  final String? attachmentPath;
  final int? supplierId;

  /// اسم المادة الجديدة المقترح ← اسمها الأصلي في فاتورة المورد
  /// (حين تُعرَّف المادة في شاشة الشراء نتعلّم الاسم الأصلي لها)
  final Map<String, String> originalNames;
}
