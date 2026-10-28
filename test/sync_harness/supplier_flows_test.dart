// اختبار الموردين: يشغّل الكود الحقيقي (PurchaseService، وصل الدفع، المرتجعات،
// محرك الترحيل) على جهاز وهمي، ثم يفحص الدفتر.
// التشغيل: flutter test test/sync_harness/supplier_flows_test.dart
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('الموردون: فاتورة، دفعة وإلغاؤها، رصيد افتتاحي، مرتجع يمنع الإلغاء، إلغاء فاتورة، الحذف', () async {
    final h = Harness(seed: 7);
    try {
      await h.start(1);
      final prod = await h.addProduct('D1', 'مادة اختبار الموردين', 50);
      expect(prod, isNotNull);

      final r = (await h.d('D1').call('supplierFlows', {'prod': prod}, const Duration(minutes: 5))) as Map;
      final fails = (r['fails'] as List).cast<String>();
      for (final f in fails) {
        print('✗ $f');
      }
      if (fails.isEmpty) print('✓ كل خطوات سيناريو الموردين نجحت');
      expect(fails, isEmpty);

      final lc = (await h.d('D1').call('ledgerCheck', const {}, const Duration(minutes: 5))) as Map;
      final problems = (lc['problems'] as List).cast<String>();
      for (final p in problems) {
        print('✗ الدفتر: $p');
      }
      if (problems.isEmpty) print('✓ الدفتر متوازن ومطابق بعد السيناريو');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
