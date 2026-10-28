// services/ai_extraction_service.dart
// خدمة استخراج بيانات الفواتير باستخدام Gemini مع مطابقة المنتجات

import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:io';
import 'gemini_service.dart';
import 'database_service.dart';

/// خدمة استخراج البيانات من الصور باستخدام Gemini
class AIExtractionService {
  AIExtractionService({
    required this.geminiApiKey,
    this.geminiApiKey2,
    this.geminiApiKey3,
  });

  final String geminiApiKey;
  final String? geminiApiKey2;
  final String? geminiApiKey3;

  /// جلب قائمة المنتجات من قاعدة البيانات
  Future<List<Map<String, dynamic>>> _getProductsForMatching() async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.query(
        'products',
        columns: ['id', 'name', 'cost_price', 'unit_price', 'unit'],
      );
      
      final products = rows.map((row) => {
        'id': row['id'],
        'name': row['name'],
        'cost_price': row['cost_price'] ?? 0,
        'unit': row['unit'],
      }).toList();
      
      debugPrint('📦 تم جلب ${products.length} منتج للمطابقة');
      return products;
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب المنتجات: $e');
      return [];
    }
  }

  /// استخراج بيانات الفاتورة أو السند من الصورة
  Future<ExtractionResult> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
  }) async {
    debugPrint('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🤖 استخراج البيانات باستخدام Gemini');
    debugPrint('📄 نوع الملف: $fileMimeType');
    debugPrint('📋 نوع الاستخراج: $extractType');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    try {
      // جلب المنتجات للمطابقة (فقط للفواتير)
      List<Map<String, dynamic>>? products;
      if (extractType == 'invoice') {
        products = await _getProductsForMatching();
      }

      final geminiService = GeminiService(
        apiKey: geminiApiKey,
        apiKey2: geminiApiKey2,
        apiKey3: geminiApiKey3,
      );

      final result = await geminiService.extractInvoiceOrReceiptStructured(
        fileBytes: fileBytes,
        fileMimeType: fileMimeType,
        extractType: extractType,
        products: products,
      );

      if (result.isNotEmpty && !result.containsKey('error')) {
        final items = result['line_items'] as List? ?? [];
        debugPrint('✅ نجح Gemini! تم استخراج ${items.length} بند');
        
        // طباعة تفاصيل المطابقة
        for (final item in items) {
          if (item is Map) {
            final name = item['name'] ?? '';
            final originalName = item['original_name'] ?? '';
            final isNew = item['is_new_product'] == true;
            final oldCost = item['old_cost_price'];
            final newCost = item['price'];
            final confidence = item['confidence'];
            final reason = item['reason'] ?? '';
            
            if (isNew) {
              debugPrint('  🆕 منتج جديد: $name');
              if (reason.isNotEmpty) debugPrint('     📝 السبب: $reason');
            } else {
              final confPercent = confidence != null ? '${(confidence * 100).toStringAsFixed(0)}%' : '?';
              debugPrint('  ✅ تطابق ($confPercent): "$originalName" → "$name"');
              if (reason.isNotEmpty) debugPrint('     📝 السبب: $reason');
              if (oldCost != null && newCost != null && oldCost > 0) {
                final diff = ((newCost - oldCost) / oldCost * 100).toStringAsFixed(1);
                debugPrint('     💰 التكلفة: $oldCost → $newCost ($diff%)');
              }
            }
          }
        }
        
        return ExtractionResult(
          data: result,
          source: 'Gemini',
          success: true,
        );
      } else {
        final error = result['error']?.toString() ?? 'فشل الاستخراج';
        debugPrint('❌ فشل Gemini: $error');
        return ExtractionResult(
          data: {},
          source: 'Gemini',
          success: false,
          error: error,
        );
      }
    } on HttpException catch (e) {
      debugPrint('❌ خطأ HTTP من Gemini: ${e.message}');
      return ExtractionResult(
        data: {},
        source: 'Gemini',
        success: false,
        error: e.message,
      );
    } catch (e) {
      debugPrint('❌ خطأ من Gemini: $e');
      return ExtractionResult(
        data: {},
        source: 'Gemini',
        success: false,
        error: e.toString(),
      );
    }
  }
}

/// نتيجة عملية الاستخراج
class ExtractionResult {
  final Map<String, dynamic> data;
  final String source;
  final bool success;
  final String? error;

  ExtractionResult({
    required this.data,
    required this.source,
    required this.success,
    this.error,
  });
}
