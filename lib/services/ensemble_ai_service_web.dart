// services/ensemble_ai_service_web.dart
// 🌐 نسخة الويب من خدمة AI — ميزة native فقط (onnxruntime/tesseract/python).
// استخراج فاتورة بالصورة غير متاح على الويب؛ مطابقة المنتجات تعمل محلياً.

import 'dart:io';
import 'dart:typed_data';

class EnsembleAIService {
  Future<Map<String, dynamic>> extractInvoiceData(File file) async {
    throw UnsupportedError(
        'استخراج الفاتورة بالذكاء الاصطناعي متاح على نسخة الكمبيوتر/أندرويد فقط');
  }

  /// مطابقة أسماء الأصناف مع منتجات القاعدة — نسخة نصية بحتة تعمل على الويب.
  Future<List<Map<String, dynamic>>> matchProducts(
      List<Map<String, dynamic>> items, List<dynamic> dbProducts) async {
    final results = <Map<String, dynamic>>[];
    for (final item in items) {
      final name = (item['name'] ?? item['description'] ?? '').toString().trim();
      Map<String, dynamic>? best;
      int bestScore = 0;
      for (final p in dbProducts) {
        final pname = (p is Map ? (p['name'] ?? '') : '').toString();
        if (pname.isEmpty || name.isEmpty) continue;
        final score = name.toLowerCase() == pname.toLowerCase()
            ? 100
            : (pname.toLowerCase().contains(name.toLowerCase()) ||
                    name.toLowerCase().contains(pname.toLowerCase()))
                ? 60
                : 0;
        if (score > bestScore) {
          bestScore = score;
          best = (p is Map) ? Map<String, dynamic>.from(p) : null;
        }
      }
      if (best != null) {
        results.add({...best, 'score': bestScore, 'input': name});
      }
    }
    return results;
  }
}
