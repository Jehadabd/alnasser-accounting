// lib/services/pdf_raster.dart
//
// 📄 تحويل صفحات PDF إلى صور PNG — من هذا المكان فقط.
//
// لماذا: حزمتا printing وpdfrx تستعملان ملف pdfium.dll نفسه داخل التطبيق.
// printing تُغلق المكتبة (FPDF_DestroyLibrary) بعد كل طباعة أو تحويل، فإن كانت pdfrx
// قد فتحتها (عرض ملف PDF) تبقى pdfrx تستعمل ذاكرة حُرّرت ⇒ 0xC0000005 داخل pdfium.dll
// ⇒ يُغلق التطبيق فجأة (سُجّل في native_errors.log يوم 2026-11-19).
// الحل: لا نستعمل pdfrx في أي مكان؛ كل تحويل يمر من هنا عبر Printing.raster وبالتسلسل،
// والطباعة تبقى كما هي.

import 'dart:typed_data';

import 'package:printing/printing.dart';

class PdfRaster2Png {
  PdfRaster2Png._();

  static Future<void> _tail = Future<void>.value();

  /// تحويل واحد في كل مرة (لا تتداخل طلبات pdfium).
  static Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// صور صفحات [pdf] بصيغة PNG على خلفية بيضاء، بدقة [dpi]، حتى [max] صفحة.
  static Future<List<Uint8List>> pages(Uint8List pdf, {double dpi = 150, int max = 8}) {
    return _serial(() async {
      final out = <Uint8List>[];
      // نحدد الصفحات مسبقاً بدل قطع البث (المكتبة تكمل عملها وتُغلق نفسها)
      await for (final page in Printing.raster(pdf, pages: [for (var i = 0; i < max; i++) i], dpi: dpi)) {
        onWhite(page.pixels);
        out.add(await page.toPng());
      }
      return out;
    });
  }

  /// خلفية printing شفافة — بعض النماذج تراها سوداء. ندمج البكسلات على الأبيض.
  static void onWhite(Uint8List rgba) {
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a == 255) continue;
      if (a == 0) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
      } else {
        final k = 255 * (255 - a);
        rgba[i] = (rgba[i] * a + k) ~/ 255;
        rgba[i + 1] = (rgba[i + 1] * a + k) ~/ 255;
        rgba[i + 2] = (rgba[i + 2] * a + k) ~/ 255;
      }
      rgba[i + 3] = 255;
    }
  }
}
