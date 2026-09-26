// اختبار دخان: جهازان حقيقيا الكود، عميل ومعاملة، ثم تطابق الأرصدة.
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('جهازان: عميل + معاملة تصل للجهاز الآخر', () async {
    final h = Harness(seed: 1);
    try {
      await h.start(2);
      final c = await h.addCustomer('D1', 'زبون الدخان');
      expect(c, isNotNull);
      await h.addTx('D1', c!, 1000);
      await h.addTx('D1', c, -250);
      final errs = await h.settle();
      if (errs.isNotEmpty) {
        print(errs.join('\n'));
        for (final d in h.devices.values) {
          print('──── سجل ${d.name}');
          print(((await d.call('logs', {'n': 80})) as List).join('\n'));
        }
      }
      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
      expect(errs, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
