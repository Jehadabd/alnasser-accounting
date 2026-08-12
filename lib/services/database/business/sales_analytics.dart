// lib/services/database/business/sales_analytics.dart
import 'package:sqflite/sqflite.dart';
import '../../../models/analytics_data.dart';
import '../../../models/invoice.dart';
import '../../../models/monthly_overview.dart'; // ✅ Added
import '../../../models/person_data.dart'; // ✅ Added for PersonYearData
import '../../settings_manager.dart';
import '../../../utils/money_calculator.dart';


class SalesAnalytics {
  final Future<Database> Function() getDatabase;

  SalesAnalytics({required this.getDatabase});

  /// بيانات ربحية العميل
  Future<Map<String, dynamic>> getCustomerProfitData(int customerId) async {
      // Stub implementation to fix build
      return {
        'totalProfit': 0.0,
        'totalSales': 0.0,
        'totalInvoices': 0,
        'totalTransactions': 0,
      };
  }

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

      // جلب إعدادات التطبيق لنسبة الربح
      final settings = await SettingsManager.getAppSettings();
      final adHocProfit = settings.defaultAdHocProfitPercentage / 100.0;

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
            costPerUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice, profitMargin: adHocProfit);
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

      return await db.rawQuery('''
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
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTopProductsByProfit({
    int limit = 10,
    required int year,
    required int month,
  }) async {
     // Similar implementation needed
     return [];
  }
  
  // دالة لجلب ملخص مالي
  Future<Map<String, dynamic>> getFinancialSummary() async {
    final db = await getDatabase();
    
    // إحصائيات العملاء والديون
    final customerResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as totalCustomers,
        SUM(CASE WHEN current_total_debt > 0 THEN 1 ELSE 0 END) as debtorCount,
        SUM(CASE WHEN current_total_debt > 0 THEN current_total_debt ELSE 0 END) as totalCustomerDebt,
        SUM(CASE WHEN current_total_debt < 0 THEN ABS(current_total_debt) ELSE 0 END) as totalCustomerCredit
      FROM customers
    ''');

    // إحصائيات الفواتير
    final invoiceResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as totalInvoices,
        SUM(total_amount) as totalInvoiceAmount
      FROM invoices
    ''');

    // مبيعات اليوم
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final todayResult = await db.rawQuery('''
      SELECT SUM(total_amount) as todaySales
      FROM invoices
      WHERE date(invoice_date) = ?
    ''', [todayStr]);

    return {
      'totalCustomers': customerResult.first['totalCustomers'] ?? 0,
      'debtorCount': customerResult.first['debtorCount'] ?? 0,
      'totalCustomerDebt': customerResult.first['totalCustomerDebt'] ?? 0.0,
      'totalCustomerCredit': customerResult.first['totalCustomerCredit'] ?? 0.0,
      'totalInvoices': invoiceResult.first['totalInvoices'] ?? 0,
      'totalInvoiceAmount': invoiceResult.first['totalInvoiceAmount'] ?? 0.0,
      'todaySales': todayResult.first['todaySales'] ?? 0.0,
    };
  }

  // دوال أخرى يمكن إضافتها لاحقاً حسب الحاجة
  Future<PersonYearData?> getCustomerYearlyData(int customerId, int year) async {
    // Placeholder
    return null;
  }
  // 🔧 New Method for Inventory Screen
  Future<Map<String, MonthlyOverview>> getMonthlySalesSummary() async {
    final db = await getDatabase();
    final appSettings = await SettingsManager.getAppSettings();
    Map<String, MonthlyOverview> summary = {};
    
    try {
        // الاستعلام المحسن لجلب المبيعات والتكاليف والأرباح
        final result = await db.rawQuery('''
            SELECT 
                strftime('%Y-%m', i.invoice_date) as month_key,
                COUNT(DISTINCT i.id) as invoice_count,
                
                -- إجمالي المبيعات (المبلغ الإجمالي للفواتير)
                COALESCE(SUM(i.total_amount), 0) as total_sales,
                
                -- إجمالي المبيعات النقدية
                COALESCE(SUM(CASE WHEN i.payment_type = 'نقد' THEN i.total_amount ELSE 0 END), 0) as cash_sales,
                
                -- إجمالي المبيعات الآجلة (صافي)
                COALESCE(SUM(CASE WHEN i.payment_type = 'دين' THEN (i.total_amount - i.amount_paid_on_invoice) ELSE 0 END), 0) as credit_sales,
                
                -- إجمالي التكلفة (مجموع تكلفة كل صنف * الكمية)
                -- 🔧 إصلاح: إذا كانت التكلفة صفر، استخدم النسبة الديناميكية من الإعدادات
                COALESCE(SUM(
                    (CASE 
                        WHEN ii.quantity_large_unit > 0 THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1)
                        ELSE ii.quantity_individual 
                    END) 
                    * 
                    (CASE 
                        WHEN COALESCE(ii.actual_cost_price, ii.cost_price, 0) > 0 THEN COALESCE(ii.actual_cost_price, ii.cost_price, 0)
                        ELSE ii.applied_price * (1.0 - ?)
                    END)
                ), 0) as total_cost,

                -- إجمالي المرتجعات
                COALESCE(SUM(i.return_amount), 0) as total_returns

            FROM invoices i
            LEFT JOIN invoice_items ii ON i.id = ii.invoice_id
            WHERE i.status = 'محفوظة'
            GROUP BY month_key
            ORDER BY month_key DESC
        ''', [appSettings.defaultAdHocProfitPercentage / 100.0]);
        
        // جلب بيانات الديون اليدوية والتسديدات منفصلة لأنها في جدول المعاملات
        // تم تحديث أنواع المعاملات لتطابق ما يتم استخدامه في TransactionsListDialog
        
        final transactionsResult = await db.rawQuery('''
            SELECT 
                strftime('%Y-%m', transaction_date) as month_key,
                -- إضافة 'opening_balance' لقائمة الديون لضمان تطابق الأرقام مع القائمة
                COALESCE(SUM(CASE WHEN transaction_type IN ('manual_debt', 'إضافة دين', 'opening_balance') THEN amount_changed ELSE 0 END), 0) as manual_debt,
                
                -- إضافة 'manual_payment' لقائمة التسديدات
                COALESCE(SUM(CASE WHEN transaction_type IN ('payment', 'تسديد', 'manual_payment') THEN ABS(amount_changed) ELSE 0 END), 0) as total_payments,
                
                -- عداد المعاملات
                COALESCE(SUM(CASE WHEN transaction_type IN ('manual_debt', 'إضافة دين', 'opening_balance') THEN 1 ELSE 0 END), 0) as manual_debt_count,
                COALESCE(SUM(CASE WHEN transaction_type IN ('payment', 'تسديد', 'manual_payment') THEN 1 ELSE 0 END), 0) as payment_count
            FROM transactions
            GROUP BY month_key
        ''');
        
        Map<String, Map<String, dynamic>> txMap = {};
        for(var row in transactionsResult) {
            if(row['month_key'] != null) {
                txMap[row['month_key'] as String] = row;
            }
        }

        // تحويل نتائج الفواتير إلى Map لتسهيل الدمج
        Map<String, Map<String, dynamic>> invoiceMap = {};
        for (var row in result) {
            if (row['month_key'] != null) {
               invoiceMap[row['month_key'] as String] = row;
            }
        }

        // جميع الأشهر المتاحة من المصدرين
        Set<String> allOneMonths = {};
        allOneMonths.addAll(invoiceMap.keys);
        allOneMonths.addAll(txMap.keys);
        
        // ترتيب الأشهر تنازلياً
        List<String> sortedMonths = allOneMonths.toList()..sort((a, b) => b.compareTo(a));

        for (String key in sortedMonths) {
            double sales = 0; 
            double profit = 0; 
            double cost = 0;
            double returns = 0;
            double cashSales = 0;
            double creditSales = 0;
            int invoiceCount = 0;

            if (invoiceMap.containsKey(key)) {
                final row = invoiceMap[key]!;
                sales = (row['total_sales'] as num).toDouble();
                cost = (row['total_cost'] as num).toDouble();
                returns = (row['total_returns'] as num).toDouble();
                cashSales = (row['cash_sales'] as num).toDouble();
                creditSales = (row['credit_sales'] as num).toDouble();
                invoiceCount = (row['invoice_count'] as int);
                
                // صافي الربح = المبيعات - المرتجعات - التكلفة
                profit = (sales - returns) - cost;
            }

            double manualDebt = 0;
            double totalPayments = 0;
            int manualDebtCount = 0;
            int paymentCount = 0;
            
            if (txMap.containsKey(key)) {
                final tx = txMap[key]!;
                manualDebt = (tx['manual_debt'] as num).toDouble();
                totalPayments = (tx['total_payments'] as num).toDouble();
                manualDebtCount = (tx['manual_debt_count'] as int);
                paymentCount = (tx['payment_count'] as int);
            }

            
            // جلب إعدادات التطبيق لمعرفة نسبة الربح
            final appSettings = await SettingsManager.getAppSettings();
            double profitPercentage = appSettings.manualDebtProfitPercentage / 100.0;
            
            // حساب الربح بناءً على النسبة المحددة
            double manualDebtProfit = manualDebt * profitPercentage;

            summary[key] = MonthlyOverview(
                monthYear: key,
                totalSales: sales,
                netProfit: profit,
                totalCost: cost, 
                cashSales: cashSales,
                creditSales: creditSales,
                totalReturns: returns,
                totalManualDebt: manualDebt,
                totalDebtPayments: totalPayments,
                manualDebtProfit: manualDebtProfit, // الربح المحسوب
                manualDebtCount: manualDebtCount,
                manualPaymentCount: paymentCount,
                invoiceCount: invoiceCount,
                settlementAdditions: 0, 
                settlementReturns: 0,
            );
        }
    } catch (e) {
        print('Error getting monthly summary: $e');
    }
    
    return summary;
  }
}
