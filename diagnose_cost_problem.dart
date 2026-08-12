// diagnose_cost_problem.dart
// ملف تشخيص مشكلة التكلفة العالية
// شغّل هذا الملف لفهم سبب التكلفة العالية في التقارير

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // تهيئة قاعدة البيانات
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  print('');
  print('╔═══════════════════════════════════════════════════════════════════╗');
  print('║  🔍 أداة تشخيص مشكلة التكلفة العالية');
  print('╚═══════════════════════════════════════════════════════════════════╝');
  print('');
  
  // فتح قاعدة البيانات - المسار الصحيح في AppData
  final dbPath = r'C:\Users\jihad\AppData\Roaming\com.example\debt_book\debt_book.db';
  print('📂 مسار قاعدة البيانات: $dbPath');
  
  // التحقق من وجود الملف
  final dbFile = File(dbPath);
  if (!await dbFile.exists()) {
    print('❌ قاعدة البيانات غير موجودة في المسار المحدد!');
    return;
  }
  print('✅ قاعدة البيانات موجودة');
  
  final db = await openDatabase(dbPath, readOnly: true);
  
  // عرض الجداول الموجودة
  final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
  print('📋 الجداول الموجودة: ${tables.map((t) => t['name']).toList()}');
  print('');
  
  if (tables.isEmpty) {
    print('❌ قاعدة البيانات فارغة!');
    print('💡 يبدو أن التطبيق يستخدم قاعدة بيانات مختلفة.');
    print('   جرب تشغيل التطبيق أولاً ثم أعد تشغيل هذا الملف.');
    await db.close();
    return;
  }
  
  // التحقق من وجود جدول invoices
  final hasInvoices = tables.any((t) => t['name'] == 'invoices');
  if (!hasInvoices) {
    print('❌ جدول invoices غير موجود!');
    await db.close();
    return;
  }
  
  // تحديد الشهر للتشخيص - شهر 12 (ديسمبر 2025)
  final year = 2025;
  final month = 12; // ديسمبر - الشهر الحالي
  
  final startDate = DateTime(year, month, 1);
  final endDate = DateTime(year, month + 1, 0);
  final startStr = startDate.toIso8601String().split('T')[0];
  final endStr = endDate.toIso8601String().split('T')[0];
  
  print('📅 فترة التشخيص: $startStr إلى $endStr');
  print('');
  
  // جلب جميع الفواتير المحفوظة بدون حد أقصى
  final invoices = await db.rawQuery('''
    SELECT id, total_amount, return_amount, customer_name, invoice_date
    FROM invoices
    WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
      AND status = 'محفوظة'
    ORDER BY id ASC
  ''', [startStr, endStr]);
  
  print('📄 عدد الفواتير: ${invoices.length}');
  print('');
  
  double grandTotalSales = 0.0;
  double grandTotalCost = 0.0;
  int problemItems = 0;
  int totalItems = 0;
  final problemProducts = <String, int>{};
  
  for (final invoice in invoices) {
    final invoiceId = invoice['id'] as int;
    final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
    final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0.0;
    final customerName = invoice['customer_name'] as String? ?? 'غير معروف';
    
    grandTotalSales += totalAmount;
    
    print('═══════════════════════════════════════════════════════════════════');
    print('📄 فاتورة #$invoiceId - $customerName');
    print('   إجمالي الفاتورة: $totalAmount');
    print('');
    
    // جلب بنود الفاتورة
    final items = await db.rawQuery('''
      SELECT 
        ii.product_name,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      JOIN products p ON p.name = ii.product_name
      WHERE ii.invoice_id = ?
    ''', [invoiceId]);
    
    // جلب البنود التي ليس لها منتج (LEFT JOIN)
    final allItems = await db.rawQuery('''
      SELECT 
        ii.product_name,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total
      FROM invoice_items ii
      WHERE ii.invoice_id = ?
    ''', [invoiceId]);
    
    print('   عدد البنود (مع منتج): ${items.length}');
    print('   عدد البنود (الكل): ${allItems.length}');
    
    if (items.length != allItems.length) {
      print('   ⚠️ هناك ${allItems.length - items.length} بند بدون منتج في قاعدة البيانات!');
      
      // البحث عن البنود المفقودة
      for (final item in allItems) {
        final productName = item['product_name'] as String?;
        final found = items.any((i) => i['product_name'] == productName);
        if (!found) {
          print('      ❌ منتج مفقود: $productName');
        }
      }
    }
    print('');
    
    double invoiceCost = 0.0;
    
    for (final item in items) {
      totalItems++;
      final productName = item['product_name'] as String? ?? 'غير معروف';
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
      final qi = (item['qi'] as num?)?.toDouble() ?? 0.0;
      final ql = (item['ql'] as num?)?.toDouble() ?? 0.0;
      final uilu = (item['uilu'] as num?)?.toDouble() ?? 0.0;
      final saleType = (item['sale_type'] as String?) ?? '';
      final productUnit = (item['product_unit'] as String?) ?? '';
      final productCost = (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
      final actualCostPerUnit = (item['actual_cost_per_unit'] as num?)?.toDouble();
      final sellingPrice = (item['selling_price'] as num?)?.toDouble() ?? 0.0;
      final unitCostsJson = item['unit_costs'] as String?;
      final unitHierarchyJson = item['unit_hierarchy'] as String?;
      
      final soldAsLargeUnit = ql > 0;
      final soldUnitsCount = soldAsLargeUnit ? ql : qi;
      
      // حساب التكلفة
      double costPerSoldUnit;
      String costSource;
      
      if (actualCostPerUnit != null && actualCostPerUnit > 0) {
        costPerSoldUnit = actualCostPerUnit;
        costSource = 'actualCostPerUnit';
      } else if (soldAsLargeUnit) {
        // محاولة قراءة من unit_costs
        Map<String, dynamic> unitCosts = {};
        if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
          try {
            unitCosts = Map<String, dynamic>.from(
              (await db.rawQuery("SELECT json('$unitCostsJson') as j")).first['j'] as Map? ?? {}
            );
          } catch (e) {
            // تجاهل
          }
        }
        
        final stored = unitCosts[saleType];
        if (stored is num && stored > 0) {
          costPerSoldUnit = stored.toDouble();
          costSource = 'unitCosts[$saleType]';
        } else if (uilu > 0) {
          costPerSoldUnit = productCost * uilu;
          costSource = 'uilu: $productCost * $uilu';
        } else {
          // حساب من hierarchy
          costPerSoldUnit = productCost; // افتراضي
          costSource = 'productCost (fallback)';
        }
      } else {
        costPerSoldUnit = productCost;
        costSource = 'productCost';
      }
      
      // إذا كانت التكلفة صفر
      if (costPerSoldUnit <= 0 && sellingPrice > 0) {
        costPerSoldUnit = sellingPrice * 0.9;
        costSource = 'estimated_10%';
      }
      
      final itemCost = costPerSoldUnit * soldUnitsCount;
      invoiceCost += itemCost;
      
      final profit = itemTotal - itemCost;
      final isProblem = itemCost > itemTotal * 1.5;
      
      if (isProblem) {
        problemItems++;
        problemProducts[productName] = (problemProducts[productName] ?? 0) + 1;
      }
      
      print('   ${isProblem ? "🔴" : "🟢"} $productName');
      print('      نوع البيع: $saleType | الكمية: ${soldAsLargeUnit ? "ql=$ql" : "qi=$qi"}');
      print('      سعر البيع: $sellingPrice | إجمالي: $itemTotal');
      print('      تكلفة المنتج: $productCost | uilu: $uilu');
      print('      actualCostPerUnit: $actualCostPerUnit');
      print('      unitCosts: $unitCostsJson');
      print('      ─────────────────────────────────────────');
      print('      مصدر التكلفة: $costSource');
      print('      تكلفة الوحدة: $costPerSoldUnit');
      print('      إجمالي التكلفة: $itemCost');
      print('      الربح: $profit ${isProblem ? "⚠️" : "✅"}');
      print('');
    }
    
    grandTotalCost += invoiceCost;
    
    final invoiceProfit = (totalAmount - returnAmount) - invoiceCost;
    print('   📊 ملخص الفاتورة:');
    print('      المبيعات: $totalAmount | التكلفة: $invoiceCost | الربح: $invoiceProfit');
    print('');
  }
  
  // ملخص التشخيص
  final grandProfit = grandTotalSales - grandTotalCost;
  final profitPercent = grandTotalSales > 0 ? (grandProfit / grandTotalSales) * 100 : 0.0;
  
  print('');
  print('╔═══════════════════════════════════════════════════════════════════╗');
  print('║  📊 ملخص التشخيص');
  print('╠═══════════════════════════════════════════════════════════════════╣');
  print('║  عدد الفواتير: ${invoices.length}');
  print('║  عدد البنود الإجمالي: $totalItems');
  print('║  عدد البنود المشكلة: $problemItems');
  print('║  ─────────────────────────────────────────────────────────────────');
  print('║  إجمالي المبيعات: $grandTotalSales');
  print('║  إجمالي التكلفة: $grandTotalCost');
  print('║  صافي الربح: $grandProfit');
  print('║  نسبة الربح: ${profitPercent.toStringAsFixed(1)}%');
  print('╠═══════════════════════════════════════════════════════════════════╣');
  
  if (problemProducts.isNotEmpty) {
    print('║  🚨 المنتجات الأكثر مشاكل:');
    final sorted = problemProducts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var i = 0; i < sorted.length && i < 10; i++) {
      print('║     ${i + 1}. ${sorted[i].key}: ${sorted[i].value} مرة');
    }
  }
  
  print('╚═══════════════════════════════════════════════════════════════════╝');
  
  // 🔍 تشخيص إضافي: البحث عن الفواتير ذات التكلفة العالية جداً
  print('');
  print('╔═══════════════════════════════════════════════════════════════════╗');
  print('║  🔍 تشخيص إضافي: فحص جميع الفواتير للبحث عن التكلفة الشاذة');
  print('╚═══════════════════════════════════════════════════════════════════╝');
  
  // جلب جميع الفواتير مع حساب التكلفة لكل واحدة
  final allInvoicesForCheck = await db.rawQuery('''
    SELECT id, total_amount, customer_name, invoice_date
    FROM invoices
    WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
      AND status = 'محفوظة'
    ORDER BY id ASC
  ''', [startStr, endStr]);
  
  final invoiceCostMap = <int, double>{};
  
  for (final inv in allInvoicesForCheck) {
    final invId = inv['id'] as int;
    final invTotal = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
    
    // جلب بنود الفاتورة مع بيانات المنتج
    final invItems = await db.rawQuery('''
      SELECT 
        ii.product_name,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      JOIN products p ON p.name = ii.product_name
      WHERE ii.invoice_id = ?
    ''', [invId]);
    
    double invCost = 0.0;
    for (final item in invItems) {
      final qi = (item['qi'] as num?)?.toDouble() ?? 0.0;
      final ql = (item['ql'] as num?)?.toDouble() ?? 0.0;
      final uilu = (item['uilu'] as num?)?.toDouble() ?? 0.0;
      final productCost = (item['product_cost_price'] as num?)?.toDouble() ?? 0.0;
      final actualCostPerUnit = (item['actual_cost_per_unit'] as num?)?.toDouble();
      final sellingPrice = (item['selling_price'] as num?)?.toDouble() ?? 0.0;
      
      final soldAsLargeUnit = ql > 0;
      final soldUnitsCount = soldAsLargeUnit ? ql : qi;
      
      double costPerSoldUnit;
      if (actualCostPerUnit != null && actualCostPerUnit > 0) {
        costPerSoldUnit = actualCostPerUnit;
      } else if (soldAsLargeUnit && uilu > 0) {
        costPerSoldUnit = productCost * uilu;
      } else {
        costPerSoldUnit = productCost;
      }
      
      if (costPerSoldUnit <= 0 && sellingPrice > 0) {
        costPerSoldUnit = sellingPrice * 0.9;
      }
      
      invCost += costPerSoldUnit * soldUnitsCount;
    }
    
    invoiceCostMap[invId] = invCost;
    
    // طباعة الفواتير ذات التكلفة الشاذة (أكثر من ضعف المبيعات)
    if (invCost > invTotal * 2) {
      print('');
      print('🚨 فاتورة شاذة #$invId:');
      print('   المبيعات: $invTotal');
      print('   التكلفة المحسوبة: $invCost');
      print('   الفرق: ${invCost - invTotal}');
    }
  }
  
  // حساب المجموع الصحيح
  double correctTotalCost = 0.0;
  for (final cost in invoiceCostMap.values) {
    correctTotalCost += cost;
  }
  
  print('');
  print('═══════════════════════════════════════════════════════════════════');
  print('📊 المقارنة:');
  print('   التكلفة المحسوبة في الحلقة الأولى: $grandTotalCost');
  print('   التكلفة المحسوبة في الحلقة الثانية: $correctTotalCost');
  print('   الفرق: ${grandTotalCost - correctTotalCost}');
  print('═══════════════════════════════════════════════════════════════════');
  
  await db.close();
}
