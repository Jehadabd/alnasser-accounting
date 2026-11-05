// test/maintenance/xz_ratio_probe_test.dart
//
// 🔬 قياس فقط (لا يغيّر شيئاً): كم يضغط ضاغط XZ في البرنامج نسخةً حقيقية من القاعدة،
// بإعداده الحالي وبإعدادات أقوى، مع زمن كل منها والتحقق بالفك.
// للمقارنة: xz-utils (‎-6‎) على النسخة نفسها أعطى ‎4,148,120‎ بايت، بينما نسخة الرفع
// الأخيرة كانت ‎5,762,452‎ — نريد معرفة سبب الفرق قبل أي تعديل.
//
// الملف: ‎.dart_tool/claude_patches/xz_probe.db‎ (نسخة مؤقتة؛ يُحذف بعد القياس).
// التشغيل: flutter test test/maintenance/xz_ratio_probe_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:alnaser/services/xz/xz_encoder.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final f = File('.dart_tool/claude_patches/xz_probe.db');

  test('XZ ratio probe', () {
    final db = f.readAsBytesSync();
    final archive = Archive()..addFile(ArchiveFile('probe/debt_book.db', db.length, db));
    final tarData = TarEncoder().encode(archive);
    final tar = tarData is Uint8List ? tarData : Uint8List.fromList(tarData);
    // ignore: avoid_print
    print('input tar: ${tar.length} bytes');

    for (final (fb, dict) in const [(64, 1 << 23), (273, 1 << 23)]) {
      final sw = Stopwatch()..start();
      final xz = xzCompress(tar, fastBytes: fb, dictSizeMax: dict);
      final t = sw.elapsedMilliseconds;
      final back = XZDecoder().decodeBytes(xz, verify: true);
      var same = back.length == tar.length;
      for (var i = 0; same && i < tar.length; i++) {
        if (back[i] != tar[i]) same = false;
      }
      // ignore: avoid_print
      print('fastBytes=$fb dict=${dict >> 20}MB → ${xz.length} bytes, $t ms, verified=$same');
      expect(same, isTrue);
    }
  }, skip: f.existsSync() ? false : 'xz_probe.db غير موجود', timeout: const Timeout(Duration(minutes: 20)));
}
