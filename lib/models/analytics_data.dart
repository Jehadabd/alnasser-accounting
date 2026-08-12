// lib/models/analytics_data.dart
import 'invoice.dart';
import 'person_data.dart'; // Import to use PersonMonthData if needed, or keep separate

// أنواع البيانات لنظام التقارير
class ProductInvoiceAnalytics { // Renamed from InvoiceWithProductData
  final Invoice invoice;
  final double quantitySold;
  final double saleUnitsCount;
  final double profit;
  final double sellingPrice;
  final double unitCostAtSale;

  ProductInvoiceAnalytics({
    required this.invoice,
    required this.quantitySold,
    required this.saleUnitsCount,
    required this.profit,
    required this.sellingPrice,
    required this.unitCostAtSale,
  });
}

class AnalyticsPersonYearData { // Renamed from PersonYearData
  final double totalProfit;
  final double totalSales;
  final int totalInvoices;
  final int totalTransactions;
  final double averageSellingPrice;
  final double totalQuantity;

  AnalyticsPersonYearData({
    required this.totalProfit,
    required this.totalSales,
    required this.totalInvoices,
    required this.totalTransactions,
    required this.averageSellingPrice,
    required this.totalQuantity,
  });
}

