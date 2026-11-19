import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/pdf_raster.dart';

void main() {
  test('onWhite: الشفاف يصبح أبيض، المعتم لا يتغير، نصف الشفاف يُدمج على الأبيض', () {
    final px = Uint8List.fromList([
      255, 255, 255, 0, // شفاف (خلفية printing)
      10, 20, 30, 255, // نص معتم
      0, 0, 0, 128, // حافة نصف شفافة سوداء
    ]);
    PdfRaster2Png.onWhite(px);
    expect(px.sublist(0, 4), [255, 255, 255, 255]);
    expect(px.sublist(4, 8), [10, 20, 30, 255]);
    expect(px.sublist(8, 12), [127, 127, 127, 255]);
  });
}
