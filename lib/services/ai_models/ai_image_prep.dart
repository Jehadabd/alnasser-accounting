// lib/services/ai_models/ai_image_prep.dart
//
// 🗜️ تصغير صور الفاتورة قبل إرسالها للذكاء الاصطناعي.
//
// صورة الهاتف 3–8 ميغابايت، وتُرسل بترميز base64 (+33%) ⇒ 4–11 ميغابايت رفعاً لكل صورة.
// على إنترنت متوسط (رفع 2–4 ميغابت/ثانية) هذا وحده 10–45 ثانية قبل أن يبدأ النموذج.
// والنموذج نفسه يصغّر الصورة داخلياً (Gemini: ~3000 بكسل كحد عملي)، فالدقة الزائدة لا
// تُحسّن القراءة. لذلك: أطول ضلع 2400 بكسل، JPEG بجودة 85 — النص الصغير والخط اليدوي
// يبقيان واضحين، والحجم ≈ 300–900 كيلوبايت.
//
// أمان: أي فشل (صيغة لا تُفك مثل HEIC، صورة تالفة) ⇒ تُرسل الأصلية كما هي. لا يُصغَّر ملف
// أصغر من 700 كيلوبايت، ولا تُستبدل الأصلية إن لم يصغر الحجم فعلاً. الـ PDF لا يُلمس.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'ai_vision_client.dart';

class AiImagePrep {
  AiImagePrep._();

  static const int maxSide = 2400;
  static const int quality = 85;
  static const int minBytesToShrink = 700 * 1024;

  /// يصغّر الصور الكبيرة (في Isolate منفصل كي لا تتجمد الشاشة).
  static Future<List<AiBlob>> shrinkAll(List<AiBlob> files) async {
    final out = <AiBlob>[];
    for (final f in files) {
      out.add(await shrink(f));
    }
    return out;
  }

  static Future<AiBlob> shrink(AiBlob f) async {
    if (f.isPdf || f.bytes.length < minBytesToShrink) return f;
    try {
      final r = await compute(_shrinkBytes, f.bytes);
      if (r == null || r.length >= f.bytes.length) return f;
      return AiBlob(r, 'image/jpeg');
    } catch (_) {
      return f;
    }
  }

  /// يعمل داخل Isolate. null = اترك الأصلية.
  @visibleForTesting
  static Uint8List? shrinkBytesForTest(Uint8List bytes) => _shrinkBytes(bytes);

  static Uint8List? _shrinkBytes(Uint8List bytes) {
    try {
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      // صورة بشفافية (لقطة شاشة PNG): JPEG يُسوّد الشفاف — تُرسل كما هي
      if (image.numChannels == 4) return null;
      // صورة الهاتف قد تحمل اتجاهها في EXIF: نطبّقه قبل حذف البيانات الوصفية
      image = img.bakeOrientation(image);
      final w = image.width, h = image.height;
      final longest = w > h ? w : h;
      if (longest > maxSide) {
        image = w >= h ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
            : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    } catch (_) {
      return null;
    }
  }
}
