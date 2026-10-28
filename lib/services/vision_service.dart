// lib/services/vision_service.dart
//
// 🧠 طبقة «فهم بنية الفاتورة» (LayoutLMv3 عبر ONNX) — معطّلة.
//
// كان نموذجها assets/models/model.onnx (481 ميغا) قد أُزيل من البرنامج لتقليل
// الحجم، فكان تحميله يفشل دائماً بصمت وتعيد الخدمة نتيجة فارغة. بقي محرّكها
// onnxruntime.dll (9.6 ميغا) داخل كل تثبيت بلا فائدة، فأُزيلت المكتبة.
// هذه نسخة بنفس الواجهة حتى لا يتغيّر كود قراءة الفواتير (OCR) الذي يستدعيها.
// النسخة الكاملة السابقة: _backup_owner_20261015/vision_service.pre_onnx.dart

import 'dart:io';
import 'dart:ui' show Rect;

import 'ocr_service.dart';

class VisionService {
  /// لا نموذج: لا شيء يُحمَّل
  Future<void> loadModel() async {}

  /// بلا نموذج النتيجة فارغة دائماً (كما كانت فعلياً منذ إزالة النموذج)
  Future<List<VisionToken>> analyzeDocument(List<OCRWord> words, {File? imageFile}) async => const [];

  void dispose() {}
}

/// Represents a word classified by the AI
class VisionToken {
  final String text;
  final String label; // e.g., "B-TOTAL", "I-VENDOR"
  final double confidence;
  final Rect rect;

  VisionToken({
    required this.text,
    required this.label,
    required this.confidence,
    required this.rect,
  });
}
