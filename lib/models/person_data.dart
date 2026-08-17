// models/person_data.dart
import 'customer.dart';

class PersonReportData {
  final Customer customer;
  final double totalProfit;
  final double totalSales;
  final int totalInvoices;
  final int totalInvoicesGlobal;
  final int totalTransactions;

  PersonReportData({
    required this.customer,
    required this.totalProfit,
    required this.totalSales,
    required this.totalInvoices,
    this.totalInvoicesGlobal = 0,
    required this.totalTransactions,
  });
}

class PersonYearData {
  final double totalProfit;
  final double totalSales;
  final int totalInvoices;
  final int totalTransactions;
  final Map<String, dynamic> monthlyData;
  final double averageSellingPrice; // From analytics_data.dart
  final double totalQuantity; // From analytics_data.dart

  PersonYearData({
    required this.totalProfit,
    required this.totalSales,
    required this.totalInvoices,
    required this.totalTransactions,
    required this.monthlyData,
    this.averageSellingPrice = 0.0,
    this.totalQuantity = 0.0,
  });

  factory PersonYearData.fromMap(Map<String, dynamic> map) {
    return PersonYearData(
      totalProfit: (map['totalProfit'] as num?)?.toDouble() ?? 0.0,
      totalSales: (map['totalSales'] as num?)?.toDouble() ?? 0.0,
      totalInvoices: (map['totalInvoices'] as num?)?.toInt() ?? 0,
      totalTransactions: (map['totalTransactions'] as num?)?.toInt() ?? 0,
      monthlyData: map['monthlyData'] as Map<String, dynamic>? ?? {},
      averageSellingPrice: (map['averageSellingPrice'] as num?)?.toDouble() ?? 0.0,
      totalQuantity: (map['totalQuantity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PersonMonthData {
  final double totalProfit;
  final double totalSales;
  final int totalInvoices;
  final int totalTransactions;
  final double totalQuantity;
  final List<InvoiceWithProductData> invoices;

  PersonMonthData({
    required this.totalProfit,
    required this.totalSales,
    required this.totalInvoices,
    required this.totalTransactions,
    this.totalQuantity = 0.0,
    required this.invoices,
  });

  factory PersonMonthData.fromMap(Map<String, dynamic> map) {
    return PersonMonthData(
      totalProfit: (map['totalProfit'] as num?)?.toDouble() ?? 0.0,
      totalSales: (map['totalSales'] as num?)?.toDouble() ?? 0.0,
      totalInvoices: (map['totalInvoices'] as num?)?.toInt() ?? 0,
      totalTransactions: (map['totalTransactions'] as num?)?.toInt() ?? 0,
      totalQuantity: (map['totalQuantity'] as num?)?.toDouble() ?? 0.0,
      invoices: (map['invoices'] as List<dynamic>?)
              ?.map((e) => InvoiceWithProductData.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class InvoiceWithProductData {
  final int invoiceId;
  final DateTime invoiceDate;
  final String customerName;
  final double totalAmount;
  final double discount;
  final double profit;
  final List<InvoiceItemData> items;

  InvoiceWithProductData({
    required this.invoiceId,
    required this.invoiceDate,
    required this.customerName,
    required this.totalAmount,
    required this.discount,
    required this.profit,
    required this.items,
  });

  factory InvoiceWithProductData.fromMap(Map<String, dynamic> map) {
    return InvoiceWithProductData(
      invoiceId: map['invoiceId'] as int? ?? 0,
      invoiceDate: DateTime.parse(map['invoiceDate'] as String),
      customerName: map['customerName'] as String? ?? '',
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      profit: (map['profit'] as num?)?.toDouble() ?? 0.0,
      items: (map['items'] as List<dynamic>?)
              ?.map((e) => InvoiceItemData.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class InvoiceItemData {
  final String productName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double totalPrice;
  final double costPrice;
  final double profit;

  InvoiceItemData({
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.totalPrice,
    required this.costPrice,
    required this.profit,
  });

  factory InvoiceItemData.fromMap(Map<String, dynamic> map) {
    return InvoiceItemData(
      productName: map['productName'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] as String? ?? '',
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (map['totalPrice'] as num?)?.toDouble() ?? 0.0,
      costPrice: (map['costPrice'] as num?)?.toDouble() ?? 0.0,
      profit: (map['profit'] as num?)?.toDouble() ?? 0.0,
    );
  }
} 