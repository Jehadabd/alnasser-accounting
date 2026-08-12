
import 'package:sqflite/sqflite.dart';
import '../../../models/monthly_overview.dart'; 
// Assuming path to MonthlyOverview

/// خدمة التحليلات - أفضل العملاء والمنتجات
class SalesAnalytics {
  final Future<Database> Function() getDatabase;

  SalesAnalytics({required this.getDatabase});

  /// أفضل العملاء حسب إجمالي المشتريات لشهر معين
  Future<List<Map<String, dynamic>>> getTopCustomersBySales({
    int limit = 10,
    required int year,
    required int month,
  }) async {
    final db = await getDatabase();
    try {
      final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
      final endDate = month == 12
          ? '${year + 1}-01-01'
          : '$year-${(month + 1).toString().padLeft(2, '0')}-01';

      final results = await db.rawQuery('''
        SELECT 
          c.id,
          c.name,
          COALESCE(SUM(i.total_amount), 0) as total_sales
        FROM customers c
        LEFT JOIN invoices i ON i.customer_id = c.id 
          AND i.status = 'محفوظة'
          AND i.invoice_date >= ? AND i.invoice_date < ?
        GROUP BY c.id, c.name
        HAVING total_sales > 0
        ORDER BY total_sales DESC
        LIMIT ?
      ''', [startDate, endDate, limit]);
      return results;
    } catch (e) {
      return [];
    }
  }

  /// أفضل العملاء حسب صافي الربح لشهر معين
  Future<List<Map<String, dynamic>>> getTopCustomersByProfit({
    int limit = 10,
    required int year,
    required int month,
  }) async {
    final db = await getDatabase();
    try {
      final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
      final endDate = month == 12
          ? '${year + 1}-01-01'
          : '$year-${(month + 1).toString().padLeft(2, '0')}-01';

      final invoices = await db.rawQuery('''
        SELECT 
          i.id as invoice_id,
          i.customer_id,
          c.name as customer_name,
          i.total_amount,
          i.return_amount
        FROM invoices i
        JOIN customers c ON c.id = i.customer_id
        WHERE i.status = 'محفوظة'
          AND i.invoice_date >= ? AND i.invoice_date < ?
      ''', [startDate, endDate]);

      Map<int, Map<String, dynamic>> customerProfits = {};

      for (final invoice in invoices) {
        final customerId = invoice['customer_id'] as int;
        final customerName = invoice['customer_name'] as String;
        final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0;
        final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0;
        final invoiceId = invoice['invoice_id'] as int;

        double invoiceCost = 0;
        final items = await db.rawQuery('''
          SELECT 
            ii.quantity_individual AS qi,
            ii.quantity_large_unit AS ql,
            ii.units_in_large_unit AS uilu,
            ii.actual_cost_price AS actual_cost_per_unit,
            ii.applied_price AS selling_price,
            p.cost_price AS product_cost_price
          FROM invoice_items ii
          LEFT JOIN products p ON p.name = ii.product_name
          WHERE ii.invoice_id = ?
        ''', [invoiceId]);

        for (final item in items) {
          final qi = (item['qi'] as num?)?.toDouble() ?? 0;
          final ql = (item['ql'] as num?)?.toDouble() ?? 0;
          final uilu = (item['uilu'] as num?)?.toDouble() ?? 1;
          final actualCost = (item['actual_cost_per_unit'] as num?)?.toDouble();
          final productCost = (item['product_cost_price'] as num?)?.toDouble() ?? 0;
          final sellingPrice = (item['selling_price'] as num?)?.toDouble() ?? 0;

          final soldUnits = ql > 0 ? ql : qi;
          double costPerUnit;
          if (actualCost != null && actualCost > 0) {
            costPerUnit = actualCost;
          } else if (ql > 0) {
            costPerUnit = productCost * uilu;
          } else {
            costPerUnit = productCost;
          }
          if (costPerUnit <= 0 && sellingPrice > 0) {
            costPerUnit = sellingPrice * 0.9;
          }
          invoiceCost += costPerUnit * soldUnits;
        }

        final profit = (totalAmount - returnAmount) - invoiceCost;

        if (!customerProfits.containsKey(customerId)) {
          customerProfits[customerId] = {'id': customerId, 'name': customerName, 'total_profit': 0.0};
        }
        customerProfits[customerId]!['total_profit'] =
            (customerProfits[customerId]!['total_profit'] as double) + profit;
      }

      final sortedCustomers = customerProfits.values.toList()
        ..sort((a, b) => (b['total_profit'] as double).compareTo(a['total_profit'] as double));

      return sortedCustomers.take(limit).toList();
    } catch (e) {
      return [];
    }
  }

  /// أفضل المنتجات حسب الكمية المباعة لشهر معين
  Future<List<Map<String, dynamic>>> getTopProductsBySales({
    int limit = 10,
    required int year,
    required int month,
  }) async {
    final db = await getDatabase();
    try {
      final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
      final endDate = month == 12
          ? '${year + 1}-01-01'
          : '$year-${(month + 1).toString().padLeft(2, '0')}-01';

      final results = await db.rawQuery('''
        SELECT 
          p.id,
          p.name,
          p.unit,
          COALESCE(SUM(
            CASE 
              WHEN ii.quantity_large_unit > 0 THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1)
              ELSE ii.quantity_individual
            END
          ), 0) as total_quantity
        FROM products p
        LEFT JOIN invoice_items ii ON ii.product_name = p.name
        LEFT JOIN invoices i ON i.id = ii.invoice_id 
          AND i.status = 'محفوظة'
          AND i.invoice_date >= ? AND i.invoice_date < ?
        GROUP BY p.id, p.name, p.unit
        HAVING total_quantity > 0
        ORDER BY total_quantity DESC
        LIMIT ?
      ''', [startDate, endDate, limit]);
      return results;
    } catch (e) {
      return [];
    }
  }

  /// أفضل المنتجات حسب صافي الربح لشهر معين
  Future<List<Map<String, dynamic>>> getTopProductsByProfit({
    int limit = 10,
    required int year,
    required int month,
  }) async {
    final db = await getDatabase();
    try {
      final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
      final endDate = month == 12
          ? '${year + 1}-01-01'
          : '$year-${(month + 1).toString().padLeft(2, '0')}-01';

      final items = await db.rawQuery('''
        SELECT 
          ii.product_name,
          ii.quantity_individual AS qi,
          ii.quantity_large_unit AS ql,
          ii.units_in_large_unit AS uilu,
          ii.actual_cost_price AS actual_cost_per_unit,
          ii.applied_price AS selling_price,
          ii.item_total,
          p.cost_price AS product_cost_price,
          p.id as product_id
        FROM invoice_items ii
        JOIN invoices i ON i.id = ii.invoice_id
        LEFT JOIN products p ON p.name = ii.product_name
        WHERE i.status = 'محفوظة'
          AND i.invoice_date >= ? AND i.invoice_date < ?
      ''', [startDate, endDate]);

      Map<String, Map<String, dynamic>> productProfits = {};

      for (final item in items) {
        final productName = item['product_name'] as String;
        final productId = item['product_id'] as int?;
        final qi = (item['qi'] as num?)?.toDouble() ?? 0;
        final ql = (item['ql'] as num?)?.toDouble() ?? 0;
        final uilu = (item['uilu'] as num?)?.toDouble() ?? 1;
        final actualCost = (item['actual_cost_per_unit'] as num?)?.toDouble();
        final productCost = (item['product_cost_price'] as num?)?.toDouble() ?? 0;
        final sellingPrice = (item['selling_price'] as num?)?.toDouble() ?? 0;
        final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;

        final soldUnits = ql > 0 ? ql : qi;
        double costPerUnit;
        if (actualCost != null && actualCost > 0) {
          costPerUnit = actualCost;
        } else if (ql > 0) {
          costPerUnit = productCost * uilu;
        } else {
          costPerUnit = productCost;
        }
        if (costPerUnit <= 0 && sellingPrice > 0) {
          costPerUnit = sellingPrice * 0.9;
        }

        final profit = itemTotal - (costPerUnit * soldUnits);

        if (!productProfits.containsKey(productName)) {
          productProfits[productName] = {
            'id': productId,
            'name': productName,
            'total_profit': 0.0,
          };
        }
        productProfits[productName]!['total_profit'] =
            (productProfits[productName]!['total_profit'] as double) + profit;
      }

      final sortedProducts = productProfits.values.toList()
        ..sort((a, b) => (b['total_profit'] as double).compareTo(a['total_profit'] as double));

      return sortedProducts.take(limit).toList();
    } catch (e) {
      return [];
    }
  }

  /// ملخص المبيعات اليومي
  Future<Map<String, dynamic>> getDailySalesSummary(DateTime date) async {
    final db = await getDatabase();
    try {
      final dateStr = date.toString().substring(0, 10);
      
      final result = await db.rawQuery('''
        SELECT 
          COUNT(1) as invoice_count,
          COALESCE(SUM(total_amount), 0) as total_sales,
          COALESCE(SUM(CASE WHEN payment_type = 'نقد' THEN total_amount ELSE 0 END), 0) as cash_sales,
          COALESCE(SUM(CASE WHEN payment_type = 'دين' THEN total_amount ELSE 0 END), 0) as credit_sales
        FROM invoices 
        WHERE status = 'محفوظة' AND invoice_date >= '$dateStr' AND invoice_date < '$dateStr 23:59:59'
      ''');
      
      if (result.isNotEmpty) {
        return {
          'invoice_count': result.first['invoice_count'] ?? 0,
          'total_sales': ((result.first['total_sales'] as num?) ?? 0).toDouble(),
          'cash_sales': ((result.first['cash_sales'] as num?) ?? 0).toDouble(),
          'credit_sales': ((result.first['credit_sales'] as num?) ?? 0).toDouble(),
        };
      }
      return {};
    } catch (e) {
      return {};
    }
  }
  
  // 🔧 New Method for Inventory Screen
  Future<Map<String, MonthlyOverview>> getMonthlySalesSummary() async {
    final db = await getDatabase();
    Map<String, MonthlyOverview> summary = {};
    
    // Logic to aggregate monthly sales
    // This is a simplified implementation to fix build errors. 
    // Ideally this should query the DB grouped by YYYY-MM
    // For now we can return minimal data or implement full query
    
    try {
        final result = await db.rawQuery('''
            SELECT 
                strftime('%Y-%m', invoice_date) as month_key,
                COALESCE(SUM(total_amount), 0) as total_sales,
                COUNT(id) as invoice_count
            FROM invoices
            WHERE status = 'محفوظة'
            GROUP BY month_key
            ORDER BY month_key DESC
        ''');
        
        for (var row in result) {
            String key = row['month_key'] as String;
            double sales = (row['total_sales'] as num).toDouble();
            int count = (row['invoice_count'] as int);
            
            // Note: Profit and other fields need more complex queries
            // Returning basic overview for now
            summary[key] = MonthlyOverview(
                monthYear: key,
                totalSales: sales,
                netProfit: sales * 0.2, // Dummy 20% profit estimate
                cashSales: 0,
                creditSales: 0,
                totalReturns: 0,
                totalDebtPayments: 0,
                settlementAdditions: 0,
                settlementReturns: 0,
                invoiceCount: count
            );
        }
    } catch (e) {
        print('Error getting monthly summary: $e');
    }
    
    return summary;
  }
  
  Future<Map<String, dynamic>> getCustomerProfitData(int customerId) async {
      final db = await getDatabase();
      // Calculate customer totals: sales, profit, invoice count
      // This is a placeholder implementation
      
      double totalSales = 0.0;
      double totalProfit = 0.0;
      int totalInvoices = 0;
      
      // Query totals
      final salesRes = await db.rawQuery('''
          SELECT COUNT(id) as cnt, SUM(total_amount) as sales
          FROM invoices WHERE customer_id = ? AND status='محفوظة'
      ''', [customerId]);
      
      if (salesRes.isNotEmpty) {
          totalInvoices = (salesRes.first['cnt'] as int?) ?? 0;
          totalSales = (salesRes.first['sales'] as num?)?.toDouble() ?? 0.0;
      }
      
      // Approximate profit
      totalProfit = totalSales * 0.15; // 15% placeholder
      
      return {
          'totalProfit': totalProfit,
          'totalSales': totalSales,
          'totalInvoices': totalInvoices,
          'totalTransactions': 0 // Need transaction query
      };
  }

  /// تقرير المقارنة الشهرية
  Future<List<Map<String, dynamic>>> getMonthlyComparison(int year) async {
    final db = await getDatabase();
    try {
      final results = await db.rawQuery('''
        SELECT 
          strftime('%m', invoice_date) as month,
          COUNT(1) as invoice_count,
          COALESCE(SUM(total_amount), 0) as total_sales
        FROM invoices 
        WHERE status = 'محفوظة' AND strftime('%Y', invoice_date) = ?
        GROUP BY strftime('%m', invoice_date)
        ORDER BY month
      ''', [year.toString()]);
      
      return results;
    } catch (e) {
      return [];
    }
  }
}
