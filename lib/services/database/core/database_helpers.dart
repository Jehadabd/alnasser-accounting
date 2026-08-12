// lib/services/database/core/database_helpers.dart
// دوال مساعدة لقاعدة البيانات

import 'package:sqflite/sqflite.dart';
import 'dart:convert';

/// دوال مساعدة لقاعدة البيانات
class DatabaseHelpers {
  /// معالجة أخطاء قاعدة البيانات وتحويلها إلى رسائل مفهومة
  static String handleDatabaseError(dynamic e) {
    String errorMessage = 'حدث خطأ غير معروف في قاعدة البيانات.';
    if (e is DatabaseException) {
      if (e.toString().contains('UNIQUE constraint failed')) {
        errorMessage =
            'فشل العملية: البيانات المدخلة موجودة بالفعل (مثلاً اسم مكرر).';
      } else if (e.toString().contains('NOT NULL constraint failed')) {
        errorMessage = 'فشل العملية: هناك بيانات مطلوبة لم يتم إدخالها.';
      } else {
        errorMessage = 'حدث خطأ في قاعدة البيانات: ${e.toString()}';
      }
    } else if (e is Exception) {
      errorMessage = 'حدث خطأ غير متوقع: ${e.toString()}';
    }
    return errorMessage;
  }

  /// دالة تطبيع النص العربي - حذف التشكيل والتوحيد
  static String normalizeArabic(String input) {
    if (input.isEmpty) return input;
    
    // حذف التشكيل والتطويل
    final diacritics = RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]');
    String s = input.replaceAll(diacritics, '').replaceAll('\u0640', '');
    
    // توحيد الألف والهمزات والياء والتاء المربوطة
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    
    // إزالة مسافات زائدة
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return s;
  }

  /// حساب التكلفة من النظام الهرمي للوحدات (النسخة القديمة)
  static double calculateCostFromHierarchyOld(
    String? unitHierarchy, 
    String? unitCosts, 
    String saleUnit, 
    double quantity
  ) {
    try {
      if (unitHierarchy == null || unitCosts == null) return 0.0;
      
      // تحليل JSON
      final hierarchy = List<Map<String, dynamic>>.from(
        jsonDecode(unitHierarchy) as List,
      );
      final costs = Map<String, double>.from(
        jsonDecode(unitCosts) as Map,
      );
      
      // البحث عن التكلفة المباشرة
      if (costs.containsKey(saleUnit)) {
        return costs[saleUnit]!;
      }
      
      // البحث في التسلسل الهرمي
      for (var item in hierarchy) {
        if (item['unit_name'] == saleUnit) {
          // حساب التكلفة من الوحدة الأساسية
          final baseCost = costs['قطعة'] ?? costs['متر'];
          if (baseCost != null) {
            final multiplier = (item['quantity'] as num).toDouble();
            return baseCost * multiplier;
          }
        }
      }
      
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }
  
  /// 🔧 حساب التكلفة من unit_hierarchy عندما لا تتوفر بيانات أخرى
  static double calculateCostFromHierarchy({
    required double productCost,
    required String saleType,
    required String? unitHierarchyJson,
  }) {
    // إذا لم يكن هناك تسلسل هرمي، نرجع التكلفة الأساسية
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty) {
      return productCost;
    }
    
    try {
      final List<dynamic> hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final double qty = (level['quantity'] is num)
            ? (level['quantity'] as num).toDouble()
            : double.tryParse(level['quantity'].toString()) ?? 1.0;
        multiplier *= qty;
        
        // إذا وصلنا لوحدة البيع المطلوبة، نرجع التكلفة المحسوبة
        if (unitName == saleType) {
          return productCost * multiplier;
        }
      }
      
      // إذا لم نجد الوحدة في التسلسل، نرجع التكلفة الأساسية
      return productCost;
    } catch (e) {
      // في حالة خطأ التحليل، نرجع التكلفة الأساسية
      return productCost;
    }
  }

  /// التحقق من وجود عمود في جدول
  static Future<bool> columnExists(Database db, String table, String column) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table);');
      return info.any((col) => col['name'] == column);
    } catch (e) {
      return false;
    }
  }

  /// إضافة عمود إذا لم يكن موجوداً
  static Future<void> addColumnIfNotExists(
    Database db, 
    String table, 
    String column, 
    String definition
  ) async {
    if (!await columnExists(db, table, column)) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $definition;');
      } catch (e) {
        // تجاهل الخطأ
      }
    }
  }
}
