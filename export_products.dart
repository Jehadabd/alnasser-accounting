// سكربت استخراج جميع المنتجات من قاعدة البيانات إلى ملف JSON
// تشغيل: dart run export_products.dart

import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('═══════════════════════════════════════════════════════════════');
  print('   📦 أداة استخراج المنتجات من قاعدة البيانات');
  print('═══════════════════════════════════════════════════════════════');
  print('');

  // تهيئة sqflite_ffi
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // مسار قاعدة البيانات
  final dbPath = '${Platform.environment['USERPROFILE']}\\AppData\\Roaming\\com.example\\debt_book\\debt_book.db';
  
  print('📂 مسار قاعدة البيانات: $dbPath');
  
  final dbFile = File(dbPath);
  if (!await dbFile.exists()) {
    print('❌ قاعدة البيانات غير موجودة في المسار المحدد!');
    print('   جرب المسارات التالية:');
    print('   - %USERPROFILE%\\Documents\\alnaser_data\\alnaser.db');
    exit(1);
  }

  print('✅ تم العثور على قاعدة البيانات');
  print('');

  try {
    final db = await openDatabase(dbPath, readOnly: true);
    
    // جلب جميع المنتجات
    final products = await db.rawQuery('SELECT * FROM products ORDER BY id');
    
    print('📊 عدد المنتجات: ${products.length}');
    print('');

    // تحويل المنتجات إلى قائمة مفصلة
    final List<Map<String, dynamic>> exportedProducts = [];

    for (final product in products) {
      final Map<String, dynamic> exportedProduct = {
        'id': product['id'],
        'name': product['name'],
        'unit': product['unit'], // piece أو meter
        'unit_arabic': product['unit'] == 'meter' ? 'متر' : 'قطعة',
        
        // الأسعار
        'prices': {
          'unit_price': product['unit_price'], // سعر الوحدة الأساسية
          'cost_price': product['cost_price'], // سعر التكلفة
          'price1': product['price1'], // سعر مفرد
          'price2': product['price2'], // سعر جملة
          'price3': product['price3'], // سعر جملة بيوت
          'price4': product['price4'], // سعر بيوت
          'price5': product['price5'], // سعر أخرى
        },
        
        // معلومات الوحدات
        'unit_info': {
          'pieces_per_unit': product['pieces_per_unit'], // عدد القطع في الوحدة الكبيرة
          'length_per_unit': product['length_per_unit'], // طول اللفة (للمنتجات المترية)
        },
        
        // التسلسل الهرمي للوحدات
        'unit_hierarchy': _parseUnitHierarchy(product['unit_hierarchy'] as String?),
        'unit_hierarchy_raw': product['unit_hierarchy'],
        
        // تكاليف الوحدات المختلفة
        'unit_costs': _parseUnitCosts(product['unit_costs'] as String?),
        'unit_costs_raw': product['unit_costs'],
        
        // التواريخ
        'created_at': product['created_at'],
        'last_modified_at': product['last_modified_at'],
      };

      // إضافة شرح مفصل للتسلسل الهرمي
      exportedProduct['hierarchy_explanation'] = _explainHierarchy(
        product['unit'] as String,
        product['unit_hierarchy'] as String?,
        product['unit_costs'] as String?,
        product['cost_price'] as num?,
        product['length_per_unit'] as num?,
      );

      exportedProducts.add(exportedProduct);
    }

    // إنشاء الملف النهائي
    final output = {
      'export_date': DateTime.now().toIso8601String(),
      'total_products': exportedProducts.length,
      'database_path': dbPath,
      'products': exportedProducts,
    };

    // حفظ الملف
    final outputPath = 'products_export.json';
    final outputFile = File(outputPath);
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(output),
      encoding: utf8,
    );

    print('✅ تم تصدير المنتجات بنجاح!');
    print('📄 مسار الملف: ${outputFile.absolute.path}');
    print('');
    
    // طباعة ملخص
    print('═══════════════════════════════════════════════════════════════');
    print('   📋 ملخص التصدير');
    print('═══════════════════════════════════════════════════════════════');
    
    int meterProducts = 0;
    int pieceProducts = 0;
    int withHierarchy = 0;
    int withCosts = 0;
    
    for (final p in products) {
      if (p['unit'] == 'meter') meterProducts++;
      if (p['unit'] == 'piece') pieceProducts++;
      if (p['unit_hierarchy'] != null && (p['unit_hierarchy'] as String).isNotEmpty) withHierarchy++;
      if (p['unit_costs'] != null && (p['unit_costs'] as String).isNotEmpty) withCosts++;
    }
    
    print('   📦 إجمالي المنتجات: ${products.length}');
    print('   🔢 منتجات بالقطعة: $pieceProducts');
    print('   📏 منتجات بالمتر: $meterProducts');
    print('   🏗️ منتجات لها تسلسل هرمي: $withHierarchy');
    print('   💰 منتجات لها تكاليف وحدات: $withCosts');
    print('═══════════════════════════════════════════════════════════════');
    
    // طباعة أمثلة
    print('');
    print('📝 أمثلة على المنتجات:');
    print('─────────────────────────────────────────────────────────────────');
    
    int count = 0;
    for (final p in exportedProducts) {
      if (count >= 5) break;
      
      print('');
      print('🔹 ${p['name']} (ID: ${p['id']})');
      print('   الوحدة: ${p['unit_arabic']}');
      print('   سعر التكلفة: ${p['prices']['cost_price'] ?? 'غير محدد'}');
      print('   سعر البيع: ${p['prices']['unit_price']}');
      
      if (p['hierarchy_explanation'] != null && (p['hierarchy_explanation'] as String).isNotEmpty) {
        print('   ${p['hierarchy_explanation']}');
      }
      
      count++;
    }
    
    await db.close();
    
  } catch (e, stack) {
    print('❌ خطأ: $e');
    print('Stack trace: $stack');
    exit(1);
  }
}

/// تحليل التسلسل الهرمي للوحدات
List<Map<String, dynamic>>? _parseUnitHierarchy(String? json) {
  if (json == null || json.isEmpty) return null;
  
  try {
    final decoded = jsonDecode(json.replaceAll("'", '"'));
    if (decoded is List) {
      return List<Map<String, dynamic>>.from(
        decoded.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
  } catch (e) {
    print('⚠️ خطأ في تحليل unit_hierarchy: $e');
  }
  return null;
}

/// تحليل تكاليف الوحدات
Map<String, dynamic>? _parseUnitCosts(String? json) {
  if (json == null || json.isEmpty) return null;
  
  try {
    final decoded = jsonDecode(json.replaceAll("'", '"'));
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (e) {
    print('⚠️ خطأ في تحليل unit_costs: $e');
  }
  return null;
}

/// شرح التسلسل الهرمي بشكل مفهوم
String _explainHierarchy(
  String unit,
  String? hierarchyJson,
  String? costsJson,
  num? costPrice,
  num? lengthPerUnit,
) {
  final List<String> explanations = [];
  
  // للمنتجات المترية
  if (unit == 'meter') {
    explanations.add('📏 يُباع بالمتر');
    if (lengthPerUnit != null && lengthPerUnit > 0) {
      explanations.add('🔄 اللفة = $lengthPerUnit متر');
      if (costPrice != null && costPrice > 0) {
        final rollCost = costPrice * lengthPerUnit;
        explanations.add('💰 تكلفة اللفة = $rollCost (${costPrice} × $lengthPerUnit)');
      }
    }
  }
  
  // تحليل التسلسل الهرمي
  if (hierarchyJson != null && hierarchyJson.isNotEmpty) {
    try {
      final hierarchy = jsonDecode(hierarchyJson.replaceAll("'", '"')) as List;
      
      for (final level in hierarchy) {
        final unitName = level['unit_name'] ?? level['name'] ?? '';
        final quantity = level['quantity'] ?? 1;
        
        if (unitName.isNotEmpty) {
          explanations.add('📦 $unitName = $quantity ${unit == 'meter' ? 'متر' : 'قطعة'}');
        }
      }
    } catch (e) {
      // تجاهل الأخطاء
    }
  }
  
  // تحليل تكاليف الوحدات
  if (costsJson != null && costsJson.isNotEmpty) {
    try {
      final costs = jsonDecode(costsJson.replaceAll("'", '"')) as Map;
      
      for (final entry in costs.entries) {
        explanations.add('💵 تكلفة ${entry.key}: ${entry.value}');
      }
    } catch (e) {
      // تجاهل الأخطاء
    }
  }
  
  return explanations.join(' | ');
}
