// خدمة استيراد المنتجات من ملف JSON
// تُستخدم لمرة واحدة فقط لاستيراد المنتجات بعد الفورمات

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class ProductsImportService {
  static const String _importedKey = 'products_imported_v1';
  static const String _backupFileName = 'assets/products_backup.json';

  final DatabaseService _db = DatabaseService();

  /// التحقق مما إذا كان الاستيراد قد تم مسبقاً
  Future<bool> hasImported() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_importedKey) ?? false;
  }

  /// التحقق من وجود ملف النسخة الاحتياطية
  Future<bool> hasBackupFile() async {
    try {
      await rootBundle.loadString(_backupFileName);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// هل يجب إظهار زر الاستيراد؟
  /// الآن يظهر دائماً إذا كان ملف النسخة الاحتياطية موجوداً
  Future<bool> shouldShowImportButton() async {
    final hasFile = await hasBackupFile();
    return hasFile;
  }

  /// استيراد المنتجات من ملف JSON
  Future<ImportResult> importProducts() async {
    try {
      // قراءة ملف JSON
      final jsonString = await rootBundle.loadString(_backupFileName);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      
      final products = data['products'] as List<dynamic>;
      final totalCount = products.length;
      
      int imported = 0;
      int skipped = 0;
      final errors = <String>[];

      // الحصول على قاعدة البيانات
      final db = await _db.database;

      // استيراد كل منتج
      for (final productData in products) {
        try {
          final name = productData['name'] as String;
          
          // التحقق من عدم وجود المنتج مسبقاً
          final existing = await db.query(
            'products',
            where: 'name = ?',
            whereArgs: [name],
          );
          
          if (existing.isNotEmpty) {
            skipped++;
            continue;
          }

          // تحضير بيانات المنتج للإدخال
          final productMap = <String, dynamic>{
            'name': name,
            'unit': productData['unit'] ?? 'piece',
            'unit_price': (productData['unit_price'] as num?)?.toDouble() ?? 0.0,
            'cost_price': (productData['cost_price'] as num?)?.toDouble(),
            'pieces_per_unit': productData['pieces_per_unit'],
            'length_per_unit': (productData['length_per_unit'] as num?)?.toDouble(),
            'price1': (productData['price1'] as num?)?.toDouble() ?? 0.0,
            'price2': (productData['price2'] as num?)?.toDouble(),
            'price3': (productData['price3'] as num?)?.toDouble(),
            'price4': (productData['price4'] as num?)?.toDouble(),
            'price5': (productData['price5'] as num?)?.toDouble(),
            'unit_hierarchy': productData['unit_hierarchy'],
            'unit_costs': productData['unit_costs'],
            'created_at': DateTime.now().toIso8601String(),
            'last_modified_at': DateTime.now().toIso8601String(),
          };

          await db.insert('products', productMap);
          imported++;
        } catch (e) {
          errors.add('خطأ في استيراد ${productData['name']}: $e');
        }
      }

      // لم نعد نحفظ علامة الاستيراد - الزر يبقى متاحاً دائماً

      return ImportResult(
        success: true,
        totalCount: totalCount,
        importedCount: imported,
        skippedCount: skipped,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        totalCount: 0,
        importedCount: 0,
        skippedCount: 0,
        errors: ['خطأ عام: $e'],
      );
    }
  }

  /// إعادة تعيين حالة الاستيراد (للاختبار فقط)
  Future<void> resetImportStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_importedKey);
  }
}

class ImportResult {
  final bool success;
  final int totalCount;
  final int importedCount;
  final int skippedCount;
  final List<String> errors;

  ImportResult({
    required this.success,
    required this.totalCount,
    required this.importedCount,
    required this.skippedCount,
    required this.errors,
  });

  String get message {
    if (!success) {
      return 'فشل الاستيراد: ${errors.join(', ')}';
    }
    return 'تم استيراد $importedCount منتج من أصل $totalCount'
        '${skippedCount > 0 ? ' (تم تخطي $skippedCount موجود مسبقاً)' : ''}';
  }
}
