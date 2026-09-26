// services/ocr_service_web.dart
// 🌐 نسخة الويب من خدمة OCR — ميزة native فقط (tesseract binary).
import 'dart:io';

class OcrService {
  Future<String> extractText(File file) async {
    throw UnsupportedError('قراءة النصوص من الصور متاحة على نسخة الكمبيوتر/أندرويد فقط');
  }
}
