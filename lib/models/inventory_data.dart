// models/inventory_data.dart
class MonthlySalesSummary {
  final String productName;
  final double totalQuantitySold;
  final double totalSalesAmount;
  final double totalProfit;
  final int totalInvoices;

  MonthlySalesSummary({
    required this.productName,
    required this.totalQuantitySold,
    required this.totalSalesAmount,
    required this.totalProfit,
    required this.totalInvoices,
  });

  factory MonthlySalesSummary.fromMap(Map<String, dynamic> map) {
    return MonthlySalesSummary(
      productName: map['productName'] as String? ?? '',
      totalQuantitySold: (map['totalQuantitySold'] as num?)?.toDouble() ?? 0.0,
      totalSalesAmount: (map['totalSalesAmount'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (map['totalProfit'] as num?)?.toDouble() ?? 0.0,
      totalInvoices: (map['totalInvoices'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'totalQuantitySold': totalQuantitySold,
      'totalSalesAmount': totalSalesAmount,
      'totalProfit': totalProfit,
      'totalInvoices': totalInvoices,
    };
  }
}

class ProductSalesData {
  final int productId;
  final String productName;
  final double totalQuantitySold;
  final double totalSalesAmount;
  final double totalProfit;
  final int totalInvoices;

  ProductSalesData({
    required this.productId,
    required this.productName,
    required this.totalQuantitySold,
    required this.totalSalesAmount,
    required this.totalProfit,
    required this.totalInvoices,
  });

  factory ProductSalesData.fromMap(Map<String, dynamic> map) {
    return ProductSalesData(
      productId: map['productId'] as int? ?? 0,
      productName: map['productName'] as String? ?? '',
      totalQuantitySold: (map['totalQuantitySold'] as num?)?.toDouble() ?? 0.0,
      totalSalesAmount: (map['totalSalesAmount'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (map['totalProfit'] as num?)?.toDouble() ?? 0.0,
      totalInvoices: (map['totalInvoices'] as num?)?.toInt() ?? 0,
    );
  }
} 