// lib/services/ai_models/ai_pdf_pages.dart
//
// 📄 ملف PDF ← صور صفحات (PNG) للنماذج التي لا تقرأ PDF مباشرة (Groq، OpenRouter).
// النموذج يقرأ صورة الفاتورة نفسها — لا تحويل إلى نص.
// التحويل عبر PdfRaster2Png (مكان واحد، بالتسلسل — انظر pdf_raster.dart).

import 'dart:typed_data';

import '../pdf_raster.dart';
import 'ai_vision_client.dart';

class AiPdfPages {
  AiPdfPages._();

  /// أقصى عدد صفحات تُرسل (فاتورة أطول نادرة، وتستهلك الحصة).
  static const maxPages = 8;

  /// صور الصفحات بدقة تكفي للأرقام الصغيرة دون تضخيم الطلب.
  static Future<List<AiBlob>> toImages(Uint8List pdf, {double dpi = 150, int max = maxPages}) async {
    final pngs = await PdfRaster2Png.pages(pdf, dpi: dpi, max: max);
    return [for (final b in pngs) AiBlob(b, 'image/png')];
  }

  /// ما يُرسل لمزوّد: PDF كما هو (Gemini)، أو صور صفحاته، أو الصورة كما هي.
  /// [cache] يحفظ الصور بين المحاولات (لا نحوّل مرتين).
  static Future<List<AiBlob>> forProvider(AiBlob file, {required bool nativePdf, List<AiBlob>? cache}) async {
    if (!file.isPdf || nativePdf) return [file];
    if (cache != null && cache.isNotEmpty) return cache;
    final pages = await toImages(file.bytes);
    cache?.addAll(pages);
    return pages;
  }
}
