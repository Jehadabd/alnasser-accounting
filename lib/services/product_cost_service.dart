// services/product_cost_service.dart
import 'dart:convert';
import '../models/product.dart';

class ProductCostService {
  /// حساب تكلفة الوحدة بناءً على نوع البيع
  static double? calculateUnitCost(Product product, String saleUnit, double quantity) {
    try {
      final unitCosts = product.getUnitCostsMap();
      
      // إذا كان نوع البيع هو الوحدة الأساسية
      if (saleUnit == product.unit) {
        return unitCosts['قطعة'];
      }
      
      // البحث في الوحدات الإضافية
      if (unitCosts.containsKey(saleUnit)) {
        return unitCosts[saleUnit];
      }
      
      // إذا لم يتم العثور على التكلفة، احسبها من الوحدة الأساسية
      return _calculateCostFromBaseUnit(product, saleUnit, quantity);
    } catch (e) {
      print('Error calculating unit cost: $e');
      return null;
    }
  }

  /// حساب التكلفة من الوحدة الأساسية
  static double? _calculateCostFromBaseUnit(Product product, String saleUnit, double quantity) {
    try {
      final baseUnitCost = product.getUnitCostsMap()['قطعة'];
      if (baseUnitCost == null) return null;
      
      final hierarchy = product.getUnitHierarchyList();
      double multiplier = 1.0;
      
      // البحث عن الوحدة في التسلسل الهرمي
      for (var item in hierarchy) {
        if (item['unit_name'] == saleUnit) {
          multiplier = (item['quantity'] as num).toDouble();
          break;
        }
      }
      
      return baseUnitCost * multiplier;
    } catch (e) {
      print('Error calculating cost from base unit: $e');
      return null;
    }
  }

  /// حساب الربح للمنتج المباع
  static double? calculateProfit(Product product, String saleUnit, double quantity, double sellingPrice) {
    try {
      final unitCost = calculateUnitCost(product, saleUnit, quantity);
      if (unitCost == null) return null;
      
      final totalCost = unitCost * quantity;
      final totalRevenue = sellingPrice * quantity;
      
      return totalRevenue - totalCost;
    } catch (e) {
      print('Error calculating profit: $e');
      return null;
    }
  }

  /// حساب نسبة الربح
  static double? calculateProfitMargin(Product product, String saleUnit, double quantity, double sellingPrice) {
    try {
      final profit = calculateProfit(product, saleUnit, quantity, sellingPrice);
      if (profit == null) return null;
      
      final totalRevenue = sellingPrice * quantity;
      if (totalRevenue == 0) return null;
      
      return (profit / totalRevenue) * 100;
    } catch (e) {
      print('Error calculating profit margin: $e');
      return null;
    }
  }

  /// الحصول على جميع مستويات الوحدات مع تكلفتها
  static Map<String, double?> getAllUnitCosts(Product product) {
    final costs = <String, double?>{};
    
    // إضافة الوحدة الأساسية
    costs[product.unit] = product.getUnitCostsMap()['قطعة'];
    
    // إضافة الوحدات الإضافية
    final hierarchy = product.getUnitHierarchyList();
    for (var item in hierarchy) {
      if (item['unit_name'] != null) {
        final unitName = item['unit_name'] as String;
        costs[unitName] = product.getUnitCostsMap()[unitName];
      }
    }
    
    return costs;
  }

  /// حساب التكلفة الإجمالية للمخزون
  static double? calculateTotalInventoryCost(Product product, Map<String, double> inventory) {
    try {
      double totalCost = 0.0;
      
      for (var entry in inventory.entries) {
        final unitCost = calculateUnitCost(product, entry.key, entry.value);
        if (unitCost != null) {
          totalCost += unitCost * entry.value;
        }
      }
      
      return totalCost;
    } catch (e) {
      print('Error calculating total inventory cost: $e');
      return null;
    }
  }

  /// تحديث تكلفة الوحدات بناءً على التكلفة الأساسية
  static Map<String, double> updateUnitCostsFromBase(Product product) {
    final updatedCosts = <String, double>{};
    final baseCost = product.getUnitCostsMap()['قطعة'];
    
    if (baseCost != null) {
      updatedCosts['قطعة'] = baseCost;
      
      final hierarchy = product.getUnitHierarchyList();
      for (var item in hierarchy) {
        if (item['unit_name'] != null && item['quantity'] != null) {
          final unitName = item['unit_name'] as String;
          final quantity = (item['quantity'] as num).toInt();
          updatedCosts[unitName] = baseCost * quantity;
        }
      }
    }
    
    return updatedCosts;
  }

  /// التحقق من صحة التكلفة
  static bool validateUnitCosts(Product product) {
    try {
      final costs = product.getUnitCostsMap();
      final hierarchy = product.getUnitHierarchyList();
      
      // التحقق من وجود تكلفة للوحدة الأساسية
      if (!costs.containsKey('قطعة') || costs['قطعة'] == null) {
        return false;
      }
      
      // التحقق من صحة التكلفة في التسلسل الهرمي
      for (var item in hierarchy) {
        if (item['unit_name'] != null && item['quantity'] != null) {
          final unitName = item['unit_name'] as String;
          final quantity = (item['quantity'] as num).toInt();
          final expectedCost = costs['قطعة']! * quantity;
          
          // التحقق من أن التكلفة المدخلة صحيحة أو فارغة
          if (costs.containsKey(unitName) && costs[unitName] != null) {
            if ((costs[unitName]! - expectedCost).abs() > 0.01) {
              return false;
            }
          }
        }
      }
      
      return true;
    } catch (e) {
      print('Error validating unit costs: $e');
      return false;
    }
  }
}
