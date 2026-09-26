// ترقية المخزون: أجهزة على الإصدار القديم (كميات مطلقة مختلفة بينها، بلا دفتر
// حركات) ثم تحديث الجميع. المطلوب: رصيد افتتاحي واحد للمجموعة، وكمية واحدة
// على كل الأجهزة = الافتتاحي الفائز − المبيع، بلا تكرار للرصيد الافتتاحي.
//   flutter test test/sync_harness/stock_migration_test.dart
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('ترقية: كميات قديمة مختلفة بين الأجهزة ← رصيد افتتاحي واحد وكمية واحدة', () async {
    final h = Harness(seed: 7);
    try {
      await h.start(3);
      final c = await h.addCustomer('D1', 'زبون الترقية');
      final a = await h.addProduct('D1', 'صنف قديم أ', 100, carton: 12);
      final b = await h.addProduct('D2', 'صنف قديم ب', 40);
      var errs = await h.settle();
      expect(errs, isEmpty, reason: errs.join('\n'));

      // مبيعات قبل الترقية على أجهزة مختلفة
      await h.saveInvoice('D1', c!, 500, 500, 'نقد', items: [
        {'prod': a, 'qty': 2.0, 'large': true}, // 24 قطعة
        {'prod': b, 'qty': 3.0, 'large': false},
      ]);
      await h.saveInvoice('D3', c, 750, 0, 'دين', items: [
        {'prod': a, 'qty': 5.0, 'large': false},
      ]);
      errs = await h.settle();
      expect(errs, isEmpty, reason: errs.join('\n'));

      // «الإصدار القديم»: لا دفتر، وكمية كل جهاز رقم مطلق مختلف (انحراف
      // الأخطاء القديمة: خصم مزدوج، مخزون لا يتزامن...)
      h.cloud.clearCollection('stock_movements');
      final legacy = <String, Map<String, double>>{
        'D1': {a!: 60, b!: 30},
        'D2': {a: 71, b: 37},
        'D3': {a: 55, b: 33},
      };
      for (final e in legacy.entries) {
        await h.d(e.key).call('legacyStock', {'stocks': e.value});
      }

      // تحديث الجميع: إعادة تشغيل = فتح القاعدة بالإصدار الجديد (ترقية)
      await h.restartAll();
      errs = await h.settle();
      // الحقيقة لا تعرف الفائز مسبقاً: نأخذ الرصيد الافتتاحي المعتمد في السحابة
      final cloudMv = h.cloud.collection('stock_movements');
      for (final p in [a, b]) {
        final op = cloudMv['opening_$p'];
        expect(op, isNotNull, reason: 'لا رصيد افتتاحي في السحابة للمنتج $p');
        h.truth.products[p]!.opening = (op!['delta'] as num).toDouble();
        h.truth.products[p]!.movements = 0;
      }
      errs = await h.check();
      print('الافتتاحي الفائز: ${[a, b].map((p) => h.truth.products[p]!.opening).toList()} '
          '— الكميات: ${[a, b].map(h.truth.stock).toList()}');
      if (errs.isNotEmpty) {
        for (final p in [a, b]) {
          print(await h.explainStock(p));
        }
      }
      expect(errs, isEmpty, reason: errs.join('\n'));
      // الفائز = كمية أحد الأجهزة القديمة + ما باعه (لا تكرار ولا مزج)
      final soldA = 24 + 5.0, soldB = 3.0;
      expect(legacy.values.map((m) => m[a]! + soldA), contains(h.truth.products[a]!.opening));
      expect(legacy.values.map((m) => m[b]! + soldB), contains(h.truth.products[b]!.opening));
      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
