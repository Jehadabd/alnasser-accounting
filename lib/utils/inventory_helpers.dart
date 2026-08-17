// lib/utils/inventory_helpers.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/invoice_item.dart';

class InventoryHelpers {
  /// Adjusts stock for a single product based on its name and sale type.
  /// Handles hierarchical unit conversions.
  static Future<void> adjustProductStock(
    dynamic txn,
    String productName,
    String saleType,
    double saleUnitsCount, {
    int? productId, // أضفنا هذا لدقة المطابقة
    String? productSyncUuid, // 🔄 مطابقة عبر sync_uuid (لمزامنة المخزون بين الأجهزة)
    required bool isAddition,
  }) async {
    print('STOCK_DEBUG: ---------------- START ADJUSTMENT ----------------');
    print('STOCK_DEBUG: Product: $productName');
    print('STOCK_DEBUG: ID passed: $productId');
    print('STOCK_DEBUG: sync_uuid passed: $productSyncUuid');
    print('STOCK_DEBUG: SaleType: $saleType');
    print('STOCK_DEBUG: Units: $saleUnitsCount');
    print('STOCK_DEBUG: Operation: ${isAddition ? "ADD (+)" : "DEDUCT (-)"}');

    if (productName.isEmpty || saleUnitsCount <= 0.0001) {
      print('STOCK_DEBUG: Skipped (empty name or zero units)');
      return;
    }

    // 🔄 ترتيب أولوية المطابقة: sync_uuid > productId > name
    //    sync_uuid يضمن مطابقة نفس المنتج عبر الأجهزة المختلفة.
    String whereClause = 'name = ?';
    List<dynamic> whereArgs = [productName];
    if (productSyncUuid != null && productSyncUuid.isNotEmpty) {
      whereClause = 'sync_uuid = ?';
      whereArgs = [productSyncUuid];
      print('STOCK_DEBUG: Using sync_uuid match ($productSyncUuid)');
    } else if (productId != null) {
      whereClause = 'id = ?';
      whereArgs = [productId];
      print('STOCK_DEBUG: Using strict ID match (id=$productId)');
    } else {
      print('STOCK_DEBUG: Using Name match (Fallback)');
    }

    // 1. Get Product hierarchy to determine conversion rate
    print('STOCK_DEBUG: Querying product properties...');
    final productMaps = await txn.rawQuery(
      'SELECT id, name, unit, unit_hierarchy, stock_quantity FROM products WHERE $whereClause LIMIT 1', 
      whereArgs
    );
    
    if (productMaps.isEmpty) {
      print('STOCK_DEBUG: ❌ PRODUCT NOT FOUND IN DB! (Clause: $whereClause)');
      if (productId != null) {
          print('STOCK_DEBUG: WARNING: Product ID $productId exists in Memory/Search but NOT in main DB.');
      }
      return;
    }
    
    print('STOCK_DEBUG: ✅ Found Product: ${productMaps.first}');
    final currentStock = productMaps.first['stock_quantity'];
    print('STOCK_DEBUG: Current Stock in DB: $currentStock');
    
    final String baseUnit = productMaps.first['unit'] ?? '';
    final String? hierarchyJson = productMaps.first['unit_hierarchy'];
    
    double conversionRate = 1.0;
    
    // Truly Dynamic Matching: Check if saleType matches base unit OR its translation
    final String translatedBase = baseUnit == 'piece' ? 'قطعة' : (baseUnit == 'meter' ? 'متر' : baseUnit);
    
    if (saleType == baseUnit || saleType == translatedBase) {
      conversionRate = 1.0;
      print('STOCK_DEBUG: Conversion Rate: 1.0 (Base Unit Matched)');
    } 
    else if (hierarchyJson != null && hierarchyJson.isNotEmpty) {
      try {
        final List<dynamic> hierarchy = jsonDecode(hierarchyJson) as List<dynamic>;
        double multiplier = 1.0;
        
        for (final level in hierarchy) {
          final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
          final double qty = (level['quantity'] is num) ? (level['quantity'] as num).toDouble() : 1.0;
          multiplier *= qty;
          
          if (unitName == saleType) {
            conversionRate = multiplier;
             print('STOCK_DEBUG: Match Found in Hierarchy: $unitName -> Multiplier: $multiplier');
            break;
          }
        }
      } catch (e) {
        print('STOCK_DEBUG: Error parsing hierarchy for stock adjustment: $e');
      }
    } else {
       print('STOCK_DEBUG: No hierarchy found, defaulting to rate 1.0');
    }

    final double baseQuantityDelta = saleUnitsCount * conversionRate;
    print('STOCK_DEBUG: Final Stock Delta: $baseQuantityDelta (Units * Rate)');
    
    int rows = 0;
    final double currentStockNum = (currentStock as num?)?.toDouble() ?? 0.0;
    
    if (isAddition) {
      rows = await txn.rawUpdate('''
        UPDATE products 
        SET stock_quantity = COALESCE(stock_quantity, 0) + ?,
            last_modified_at = ?
        WHERE $whereClause
      ''', [baseQuantityDelta, DateTime.now().toIso8601String(), ...whereArgs]);
      print('STOCK_DEBUG: UPDATE (ADD) Executed.');
    } else {
      // منطق الطرح المعدل: 
      // - إذا كان المخزون الحالي صفر أو أقل، لا نطرح أي شيء
      // - إذا كانت الكمية المطلوبة أكبر من المخزون، نطرح المخزون المتوفر فقط
      if (currentStockNum <= 0) {
        print('STOCK_DEBUG: ⚠️ Current stock is zero or negative ($currentStockNum). SKIPPING DEDUCTION.');
        print('STOCK_DEBUG: Sale will proceed but inventory remains unchanged.');
        print('STOCK_DEBUG: ---------------- END ADJUSTMENT ----------------');
        return; // لا نطرح شيء إذا المخزون صفر
      }
      
      // نطرح فقط الكمية المتوفرة (لا نذهب تحت الصفر)
      final double actualDeduction = baseQuantityDelta > currentStockNum ? currentStockNum : baseQuantityDelta;
      
      rows = await txn.rawUpdate('''
        UPDATE products 
        SET stock_quantity = COALESCE(stock_quantity, 0) - ?,
            last_modified_at = ?
        WHERE $whereClause
      ''', [actualDeduction, DateTime.now().toIso8601String(), ...whereArgs]);
      print('STOCK_DEBUG: UPDATE (DEDUCT) Executed. Actual deduction: $actualDeduction');
    }
    
    print('STOCK_DEBUG: Database Rows Affected: $rows');
    if (rows == 0) {
       print('STOCK_DEBUG: ⚠️ WTF? Found product earlier but Update affected 0 rows?!');
    } else {
       print('STOCK_DEBUG: ✅ SUCCESS! Stock updated.');
    }
    print('STOCK_DEBUG: ---------------- END ADJUSTMENT ----------------');
  }

  /// Adjusts stock for a list of invoice items.
  static Future<void> adjustStockForItems(
    dynamic txn, 
    List<InvoiceItem> items, {
    required bool isAddition,
  }) async {
    print('STOCK_DEBUG: Batch Adjusting ${items.length} items...');
    for (final item in items) {
      if (item.productName.isEmpty) continue;
      
      final double saleUnitsCount = (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0)
          ? item.quantityLargeUnit!
          : (item.quantityIndividual ?? 0.0);
          
      if (saleUnitsCount <= 0.0001) continue;

      await adjustProductStock(
        txn,
        item.productName,
        item.saleType ?? '',
        saleUnitsCount,
        productId: item.productId, // تمرير المعرف
        productSyncUuid: item.productSyncUuid, // 🔄 مطابقة عبر sync_uuid
        isAddition: isAddition
      );
    }
  }
}
