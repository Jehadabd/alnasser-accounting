// lib/services/database/business/profit_calculator.dart
// حسابات الأرباح

import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../../../utils/money_calculator.dart';
import '../../settings_manager.dart' as import_settings;

/// خدمة حساب الأرباح
class ProfitCalculator {
  final Future<Database> Function() getDatabase;

  ProfitCalculator({required this.getDatabase});

  /// حساب ربح فاتورة معينة
  Future<double> calculateInvoiceProfit(int invoiceId) async {
    final db = await getDatabase();
    try {
      // جلب الفاتورة
      final invoiceMaps = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (invoiceMaps.isEmpty) return 0.0;
      
      final invoice = invoiceMaps.first;
      final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0;
      final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0;

      // حساب التكلفة
      double totalCost = 0.0;
      final items = await db.rawQuery('''
        SELECT 
          ii.quantity_individual AS qi,
          ii.quantity_large_unit AS ql,
          ii.units_in_large_unit AS uilu,
          ii.actual_cost_price AS actual_cost_per_unit,
          ii.applied_price AS selling_price,
          ii.sale_type AS sale_type,
          p.cost_price AS product_cost_price,
          p.unit AS product_unit,
          p.length_per_unit AS length_per_unit,
          p.unit_costs AS unit_costs
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
        final saleType = (item['sale_type'] as String?) ?? '';
        final productUnit = (item['product_unit'] as String?) ?? '';
        final lengthPerUnit = (item['length_per_unit'] as num?)?.toDouble();
        final unitCostsJson = item['unit_costs'] as String?;

        Map<String, dynamic> unitCosts = const {};
        if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
          try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
        }

        final bool soldAsLargeUnit = ql > 0;
        final double soldUnitsCount = soldAsLargeUnit ? ql : qi;

        double costPerSoldUnit;
        if (actualCost != null && actualCost > 0) {
          costPerSoldUnit = actualCost;
        } else if (soldAsLargeUnit) {
          final dynamic stored = unitCosts[saleType];
          if (stored is num && stored > 0) {
            costPerSoldUnit = stored.toDouble();
          } else {
            final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && saleType == 'لفة';
            costPerSoldUnit = isMeterRoll
                ? productCost * (lengthPerUnit)
                : productCost * uilu;
          }
        } else {
          costPerSoldUnit = productCost;
        }

        // إذا كانت التكلفة صفر، استخدم نسبة الربح المحددة في الإعدادات
        if (costPerSoldUnit <= 0 && sellingPrice > 0) {
          final settings = await import_settings.SettingsManager.getAppSettings();
          costPerSoldUnit = MoneyCalculator.getEffectiveCost(
            0, 
            sellingPrice, 
            profitMargin: settings.defaultAdHocProfitPercentage / 100.0
          );
        }

        totalCost += costPerSoldUnit * soldUnitsCount;
      }

      // صافي الربح
      final netSales = MoneyCalculator.subtract(totalAmount, returnAmount);
      return MoneyCalculator.subtract(netSales, totalCost);
    } catch (e) {
      print('Error calculating invoice profit: $e');
      return 0.0;
    }
  }

  /// حساب إجمالي الأرباح لفترة معينة
  Future<double> calculatePeriodProfit(DateTime start, DateTime end) async {
    final db = await getDatabase();
    try {
      final invoices = await db.query(
        'invoices',
        columns: ['id'],
        where: "status = 'محفوظة' AND invoice_date >= ? AND invoice_date <= ?",
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
      );

      double totalProfit = 0.0;
      for (final invoice in invoices) {
        final profit = await calculateInvoiceProfit(invoice['id'] as int);
        totalProfit += profit;
      }
      
      return totalProfit;
    } catch (e) {
      print('Error calculating period profit: $e');
      return 0.0;
    }
  }

  /// حساب ربح منتج معين
  Future<double> calculateProductProfit(int productId, {DateTime? start, DateTime? end}) async {
    final db = await getDatabase();
    try {
      String whereClause = "p.id = ? AND i.status = 'محفوظة'";
      List<dynamic> args = [productId];
      
      if (start != null) {
        whereClause += ' AND i.invoice_date >= ?';
        args.add(start.toIso8601String());
      }
      if (end != null) {
        whereClause += ' AND i.invoice_date <= ?';
        args.add(end.toIso8601String());
      }

      final items = await db.rawQuery('''
        SELECT 
          ii.quantity_individual AS qi,
          ii.quantity_large_unit AS ql,
          ii.units_in_large_unit AS uilu,
          ii.actual_cost_price AS actual_cost_per_unit,
          ii.item_total AS item_total,
          p.cost_price AS product_cost_price
        FROM invoice_items ii
        JOIN invoices i ON i.id = ii.invoice_id
        JOIN products p ON p.name = ii.product_name
        WHERE $whereClause
      ''', args);

      double totalProfit = 0.0;
      for (final item in items) {
        final qi = (item['qi'] as num?)?.toDouble() ?? 0;
        final ql = (item['ql'] as num?)?.toDouble() ?? 0;
        final uilu = (item['uilu'] as num?)?.toDouble() ?? 1;
        final actualCost = (item['actual_cost_per_unit'] as num?)?.toDouble();
        final productCost = (item['product_cost_price'] as num?)?.toDouble() ?? 0;
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

        totalProfit += itemTotal - (costPerUnit * soldUnits);
      }

      return totalProfit;
    } catch (e) {
      print('Error calculating product profit: $e');
      return 0.0;
    }
  }

  /// حساب ربح عميل معين
  Future<double> calculateCustomerProfit(int customerId, {DateTime? start, DateTime? end}) async {
    final db = await getDatabase();
    try {
      String whereClause = "i.customer_id = ? AND i.status = 'محفوظة'";
      List<dynamic> args = [customerId];
      
      if (start != null) {
        whereClause += ' AND i.invoice_date >= ?';
        args.add(start.toIso8601String());
      }
      if (end != null) {
        whereClause += ' AND i.invoice_date <= ?';
        args.add(end.toIso8601String());
      }

      final invoices = await db.rawQuery('''
        SELECT id FROM invoices i WHERE $whereClause
      ''', args);

      double totalProfit = 0.0;
      for (final invoice in invoices) {
        final profit = await calculateInvoiceProfit(invoice['id'] as int);
        totalProfit += profit;
      }
      
      return totalProfit;
    } catch (e) {
      print('Error calculating customer profit: $e');
      return 0.0;
    }
  }

  /// حساب هامش الربح للفاتورة
  Future<double> calculateInvoiceProfitMargin(int invoiceId) async {
    final db = await getDatabase();
    try {
      final invoiceMaps = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      if (invoiceMaps.isEmpty) return 0.0;
      
      final totalAmount = (invoiceMaps.first['total_amount'] as num?)?.toDouble() ?? 0;
      if (totalAmount <= 0) return 0.0;
      
      final profit = await calculateInvoiceProfit(invoiceId);
      return (profit / totalAmount) * 100;
    } catch (e) {
      return 0.0;
    }
  }
}
