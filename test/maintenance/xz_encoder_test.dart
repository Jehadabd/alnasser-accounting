// test/maintenance/xz_encoder_test.dart
//
// 🗜️ ضاغط XZ: هذه النسخة (Dart) يجب أن تعطي الملف نفسه بايتاً ببايت الذي أعطته
// النسخة المرجعية (Java) — والتي فكّها xz-utils/liblzma بلا خطأ — ثم يفكّها
// XZDecoder (مسار الاستعادة في البرنامج) إلى الأصل نفسه.
// التشغيل: flutter test test/maintenance/xz_encoder_test.dart

import 'dart:typed_data';

import 'package:alnaser/services/xz/xz_backup.dart';
import 'package:alnaser/services/xz/xz_encoder.dart';
import 'package:archive/archive.dart' show XZDecoder;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── مولّد بيانات حتمي مطابق للمولّد في النسخة المرجعية ───
int _x = 0;
int _next() {
  _x = (_x * 1103515245 + 12345) & 0x7FFFFFFF;
  return _x;
}

const _w = [
  'invoice', 'customer', 'debt', 'receipt', 'cash', 'total', 'discount', 'product', //
  'qty', 'price', '2026-10-29', 'IQD', 'box', 'note', 'paid', 'due',
];

Uint8List _gen(int n, int seed) {
  _x = seed;
  final b = Uint8List(n + 400);
  var len = 0;
  while (len < n) {
    final r = _next();
    final k = r % 10;
    if (k < 6) {
      for (final c in '${_w[(r >> 8) % _w.length]} '.codeUnits) {
        b[len++] = c;
      }
    } else if (k < 8) {
      final m = 1 + ((r >> 4) % 64);
      for (var i = 0; i < m; i++) {
        b[len++] = _next() & 0xFF;
      }
    } else if (len > 10) {
      final start = _next() % len;
      final l = 3 + _next() % 200;
      for (var i = 0; i < l; i++) {
        b[len++] = b[start + i];
      }
    }
  }
  return Uint8List.fromList(Uint8List.sublistView(b, 0, n));
}

/// نصفه عشوائي لا يُضغط ⇒ 24 جزء LZMA2 (0xE0 ثم 0x80)
Uint8List _genRandomish() {
  _x = 7;
  const n = 1500000;
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = ((i ~/ 50000) % 2 == 0) ? (_next() >> 16) & 0xFF : b[i - 50000 + (i % 7)];
  }
  return b;
}

class _V {
  final int n, fastBytes, xzLength;
  final String inSha, xzSha;
  const _V(this.n, this.fastBytes, this.xzLength, this.inSha, this.xzSha);
}

// مخرجات النسخة المرجعية (Java) — تحقق xz-utils من كل ملف منها
const _vectors = [
  _V(0, 64, 32, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      '14c80c40f5b247deead9e9d1d31b8b4f5f0b4f4425e6eb12291fd3e505fc8414'),
  _V(1, 64, 64, 'd3bb0d59e354ea843e790801303a46e880219996c6850ddd4c85a83e08c41d92',
      '106d7dcf6226661b08a1b7f25d09d1804169493d563daab33db802ee4287cae6'),
  _V(5, 64, 68, '644d1c048af445874499e8f2a19bede07baebd1cc39dbb84ca8852bcefb9af2a',
      '478bbea7aa8fcf2842f800eb9baf59cc46912586cfadd1c78b0792a14fbfb3e4'),
  _V(70000, 64, 5160, 'ce44d8c8ac283d3bcb9dac73d16884fda06c0db30706e266a0d818bd40210910',
      '89596d2755771498da09c67c49ad1620058edc2814d5624542f9b3153682336b'),
  _V(300000, 5, 44144, '5edeeeee52be4c37c437e263a46a07f02477550dc191f2a33f6c9176a23c3991',
      'ace97f0114bb79fa70c1ba438ee6d5154804063c87bc5c3eef8fa9c9d790ea3b'),
  _V(300000, 273, 19248, '5edeeeee52be4c37c437e263a46a07f02477550dc191f2a33f6c9176a23c3991',
      'f9d91b75d0f6418732c48242a19b00649199b1bcfda482df077c21424370166d'),
  _V(3000000, 64, 179080, '838fea6b6941fa49324230d80544b2570498c3b1d0308ab631238b161d25b0b6',
      'ea609029991351fc2168f0cb908ad9b759c92db16beaad86090410abc2bcfc86'),
];

void _expectRoundTrip(Uint8List input, Uint8List xz) {
  final back = XZDecoder().decodeBytes(xz, verify: true);
  expect(back.length, input.length);
  expect(sha256.convert(back).toString(), sha256.convert(input).toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('مطابقة النسخة المرجعية بايتاً ببايت', () {
    for (final v in _vectors) {
      test('${v.n} بايت، fastBytes=${v.fastBytes}', () {
        final input = _gen(v.n, 42);
        expect(sha256.convert(input).toString(), v.inSha, reason: 'المولّد لا يطابق المرجع');
        final xz = xzCompress(input, fastBytes: v.fastBytes);
        expect(xz.length, v.xzLength);
        expect(sha256.convert(xz).toString(), v.xzSha);
        _expectRoundTrip(input, xz);
      });
    }

    test('بيانات لا تُضغط: أجزاء LZMA2 كثيرة', () {
      final input = _genRandomish();
      expect(sha256.convert(input).toString(), 'd8b9936e8b9d1cc2b30ca864f3fd3a67dc07f0b4baa22f3c80499e0f9b31a6c0');
      final xz = xzCompress(input);
      expect(xz.length, 1520660);
      expect(sha256.convert(xz).toString(), '63f29faa502e99ab97f08a5bb24780bbe33b5671f71057f613385dfa29769a1a');
      _expectRoundTrip(input, xz);
    });
  });

  group('الضغط فعلي', () {
    test('بيانات متكررة تصغر كثيراً', () {
      final input = _gen(3000000, 42);
      final xz = xzCompress(input);
      expect(xz.length < input.length ~/ 10, isTrue, reason: '${xz.length} من ${input.length}');
    });

    test('سرعة الضغط (للمعلومة)', () {
      final input = _gen(20000000, 9);
      final sw = Stopwatch()..start();
      final xz = xzCompress(input);
      final s = sw.elapsedMilliseconds / 1000;
      // ignore: avoid_print
      print('🗜️ 20MB ← ${(xz.length / 1048576).toStringAsFixed(2)}MB في ${s.toStringAsFixed(1)} ث '
          '(${(20 / s).toStringAsFixed(1)} MB/ث)');
      _expectRoundTrip(input, xz);
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  group('XzBackup: معالج منفصل + تحقق', () {
    test('يعيد ملفاً يُفكّ إلى الأصل، والتقدّم يصل إلى 1', () async {
      final input = _gen(500000, 3);
      var last = 0.0;
      final xz = await XzBackup.compressVerified(input, onProgress: (p) => last = p);
      expect(xz, isNotNull);
      expect(last, 1.0);
      _expectRoundTrip(input, xz!);
    });
  });
}
