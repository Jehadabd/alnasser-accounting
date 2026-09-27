// دمج نسختين من المنتج نفسه: الاسم نفسه أُنشئ على جهازين قبل أن يتزامنا.
// المطلوب: كل الأجهزة تبقي النسخة نفسها (قاعدة واحدة مهما كان ترتيب الوصول)،
// وكميتها = الرصيد الافتتاحي للباقية + حركات النسختين − مبيعهما، على كل جهاز
// وعلى جهاز ينضم لاحقاً، وبعد إعادة تشغيل الجميع.
//   flutter test test/sync_harness/product_merge_test.dart
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<void> _expectSettled(Harness h, String stage, List<String> watch) async {
  final errs = await h.settle();
  if (errs.isNotEmpty) {
    for (final p in watch) {
      print(await h.explainStock(p));
    }
    for (final d in h.devices.values) {
      final logs = (await d.call('logs', {'n': 4000}) as List).cast<String>();
      print('── سجل منتجات ${d.name}');
      for (final l in logs.where((l) => l.contains('ProductSyncService'))) {
        print('   $l');
      }
    }
  }
  expect(errs, isEmpty, reason: '$stage:\n${errs.join('\n')}');
}

void main() {
  test('نسختان بلا إنترنت + بيع وحركات على كلتيهما ← نسخة واحدة وكمية واحدة', () async {
    final h = Harness(seed: 11);
    try {
      await h.start(3);
      final c = await h.addCustomer('D3', 'زبون الدمج');
      await _expectSettled(h, 'البداية', const []);

      await h.setOnline('D1', false);
      await h.setOnline('D2', false);
      final a = (await h.addProduct('D1', 'سكر', 100, carton: 12))!;
      final b = (await h.addProduct('D2', 'سكر', 40, carton: 12))!;
      await h.saveInvoice('D1', c!, 500, 0, 'دين', items: [
        {'prod': a, 'qty': 2.0, 'large': true}, // 24 قطعة
      ]);
      await h.purchase('D1', a, 10);
      final invB = await h.saveInvoice('D2', c, 300, 300, 'نقد', items: [
        {'prod': b, 'qty': 3.0, 'large': false},
      ]);
      await h.adjustStock('D2', b, -2);

      await _expectSettled(h, 'بعد الدمج', [a, b]);
      final s = h.truth.survivor(a);
      expect(h.truth.survivor(b), s);
      expect(h.cloud.collection('products').keys, containsAll([a, b]),
          reason: 'مستند النسخة الخاسرة يجب أن يبقى في السحابة');
      print('الباقية=$s — الكمية=${h.truth.stock(s)} '
          '(افتتاحي ${h.truth.products[s]!.opening} + 10 − 2 − 24 − 3)');

      // تنبيه «دُمج صنفان» على الجهازين اللذين أُدخلت عليهما النسختان فقط
      Future<List<String>> merges(String dev) async =>
          ((await h.d(dev).call('syncHealth')) as List)
              .map((w) => (w as Map)['id'] as String)
              .where((id) => id.startsWith('merge:'))
              .toList();
      expect(await merges('D1'), hasLength(1));
      expect(await merges('D2'), hasLength(1));
      expect(await merges('D3'), isEmpty);
      // D1 راجع الكمية ← يختفي عنده ولا يعود (حتى بعد إعادة التشغيل أدناه)
      await h.d('D1').call('dismissHealth', {'id': (await merges('D1')).single});
      expect(await merges('D1'), isEmpty);

      // بعد الدمج: بيع وشراء على الباقية، وإرجاع في فاتورة قديمة بنودها
      // بمعرّف النسخة الخاسرة ربما
      await h.saveInvoice('D1', c, 200, 0, 'دين', items: [
        {'prod': s, 'qty': 5.0, 'large': false},
      ]);
      await h.purchase('D2', s, 6);
      await h.saveInvoice('D2', c, 100, 100, 'نقد', inv: invB, items: [
        {'prod': b, 'qty': 1.0, 'large': false},
      ]);
      await _expectSettled(h, 'بعد عمليات على الباقية', [s]);

      await h.joinNewDevice();
      await _expectSettled(h, 'بعد انضمام جهاز جديد', [s]);

      await h.restartAll();
      await _expectSettled(h, 'بعد إعادة تشغيل الجميع', [s]);
      expect(await merges('D1'), isEmpty, reason: 'تنبيه رُوجع لا يعود');
      expect(await merges('D2'), hasLength(1), reason: 'تنبيه لم يُراجع يبقى');
      expect(await merges('D4'), isEmpty, reason: 'جهاز جديد لا يرى دمجاً قديماً');
      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('الباقية تُحدَّد بآخر تعديل لا بترتيب الإنشاء + شاشة تعديل فُتحت قبل الدمج', () async {
    final h = Harness(seed: 12);
    try {
      await h.start(3);
      final c = await h.addCustomer('D3', 'زبون الشاشة');
      await _expectSettled(h, 'البداية', const []);

      await h.setOnline('D1', false);
      await h.setOnline('D2', false);
      final a = (await h.addProduct('D1', 'رز', 50))!; // أولاً
      final b = (await h.addProduct('D2', 'رز', 20))!; // ثانياً
      // D2: شاشة تعديل تُفتح الآن (كائن بمعرّف b) وتبقى مفتوحة حتى بعد الدمج
      await h.d('D2').call('openProductScreen', {'prod': b, 'label': 'stale'});
      // D1 يعدّل منتجه بعد إنشاء b: نسخته صارت الأحدث فتبقى هي
      await h.d('D1').call('openProductScreen', {'prod': a, 'label': 'e1'});
      await h.d('D1').call('saveProductScreen', {'label': 'e1', 'price': 2.5});
      await h.saveInvoice('D2', c!, 400, 0, 'دين', items: [
        {'prod': b, 'qty': 4.0, 'large': false},
      ]);
      await h.adjustStock('D1', a, 5);

      await _expectSettled(h, 'بعد الدمج', [a, b]);
      expect(h.truth.survivor(b), a, reason: 'النسخة المعدّلة أخيراً هي الباقية');

      // حفظ الشاشة القديمة: لا يعيد المعرّف b ولا يفصل المنتج عن بنوده
      await h.d('D2').call('saveProductScreen', {'label': 'stale', 'price': 3.0});
      await _expectSettled(h, 'بعد حفظ شاشة فُتحت قبل الدمج', [a]);
      expect(h.truth.survivor(b), a);
      final d2 = (await h.d('D2').call('products') as List).cast<Map>();
      expect(d2.where((p) => p['name'] == 'رز').map((p) => p['uuid']), [a]);

      await h.joinNewDevice();
      await _expectSettled(h, 'بعد انضمام جهاز جديد', [a]);
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('نسخة محلية لم تُرفع بعد تُدمج قبل رفعها ← مستندها يصل ويُعرف معرّفها', () async {
    final h = Harness(seed: 13);
    try {
      await h.start(3);
      final c = await h.addCustomer('D3', 'زبون السباق');
      await _expectSettled(h, 'البداية', const []);

      await h.setOnline('D1', false);
      final a = (await h.addProduct('D1', 'شاي', 30))!; // أقدم، بلا إنترنت
      await h.saveInvoice('D1', c!, 150, 0, 'دين', items: [
        {'prod': a, 'qty': 3.0, 'large': false},
      ]);
      await h.purchase('D1', a, 12);
      final b = (await h.addProduct('D2', 'شاي', 8))!; // أحدث، متصل فيُرفع فوراً
      // على منشئه: جهاز آخر قد لا يكون وصله الصنف بعد (فلا يبيعه أصلاً)
      await h.saveInvoice('D2', c, 90, 0, 'دين', items: [
        {'prod': b, 'qty': 1.0, 'large': false},
      ]);

      await _expectSettled(h, 'بعد عودة D1', [a, b]);
      expect(h.truth.survivor(a), b);
      expect(h.cloud.collection('products').keys, contains(a),
          reason: 'مستند النسخة المدموجة قبل رفعها يجب أن يصل للسحابة');

      await h.joinNewDevice();
      await _expectSettled(h, 'بعد انضمام جهاز جديد', [b]);
      await h.restartAll();
      await _expectSettled(h, 'بعد إعادة تشغيل الجميع', [b]);
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
