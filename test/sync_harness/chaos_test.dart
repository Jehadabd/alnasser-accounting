// تجارب فوضى على كود التطبيق الحقيقي.
//   flutter test test/sync_harness/chaos_test.dart --dart-define=SEEDS=5 --dart-define=DEVICES=10 --dart-define=OPS=400
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _seeds = int.fromEnvironment('SEEDS', defaultValue: 3);
const _seed0 = int.fromEnvironment('SEED0', defaultValue: 0);
const _devices = int.fromEnvironment('DEVICES', defaultValue: 4);
const _ops = int.fromEnvironment('OPS', defaultValue: 100);
const _restarts = bool.fromEnvironment('RESTARTS', defaultValue: true);
const _harsh = bool.fromEnvironment('HARSH', defaultValue: false);

void main() {
  for (var s = _seed0; s < _seed0 + _seeds; s++) {
    test('فوضى${_harsh ? ' قاسية' : ''} seed=$s ($_devices أجهزة × $_ops عملية)', () async {
      final h = Harness(seed: s)..harsh = _harsh;
      final sw = Stopwatch()..start();
      var failed = true;
      Harness.progress('J ===== seed=$s root=${h.root.path}');
      try {
        await h.start(_devices);
        await h.chaos(_ops, restarts: _restarts);
        var errs = await h.settle();
        final phase1 = sw.elapsed.inSeconds;
        if (errs.isEmpty && _restarts) {
          await h.restartAll();
          errs = await h.settle();
          errs = errs.map((e) => 'بعد إعادة تشغيل الجميع: $e').toList();
        }
        final uncaught = await h.deviceErrors();
        print('seed=$s: ${h.truth.customers.length} عميل، ${h.truth.txs.length} معاملة، '
            '${h.truth.invoices.length} فاتورة (رُفض ${h.rejectedInvoices})، '
            'استعادات=${h.restores} تنظيف=${h.cleanups} انضمام=${h.joins} مطابقة=${h.armored}، '
            'منتجات=${h.truth.products.length} مبيع=${h.truth.invoices.values.where((i) => i.status == 'محفوظة').fold(0.0, (s, i) => s + i.items.values.fold(0.0, (a, b) => a + b))} '
            'حركات=${h.truth.products.values.fold(0.0, (s, p) => s + p.movements)}، '
            'كتابات سحابية=${h.cloud.totalWrites}، زمن=${phase1}ث/${sw.elapsed.inSeconds}ث، '
            'أخطاء عمليات=${h.opErrors.length}، أخطاء غير ممسوكة=${uncaught.length}');
        for (final e in h.opErrors.take(5)) {
          print('  عملية: ${e.split('\n').first}');
        }
        for (final e in uncaught.take(5)) {
          print('  غير ممسوك: ${e.split('\n').take(9).join(' | ')}');
        }
        if (errs.isNotEmpty) {
          print('❌ ${errs.length} خلل:');
          for (final e in errs.take(20)) {
            print('  $e');
          }
          // شرح أول منتج مختلف الكمية
          for (final e in h.truth.products.entries) {
            if (errs.any((x) => x.contains('مخزون ${e.value.name} ='))) {
              print(await h.explainStock(e.key));
              break;
            }
          }
          // شرح أول عميلين مختلفين (رصيد أو ظهور)
          var explained = 0;
          for (final e in h.truth.customers.entries) {
            if (explained >= 2) break;
            if (errs.any((x) =>
                x.contains('${e.value.name} =') || x.contains('العميل ${e.value.name} '))) {
              print(await h.explain(e.key));
              explained++;
            }
          }
        }
        failed = errs.isNotEmpty;
        expect(errs, isEmpty);
      } finally {
        await h.dispose(keepFiles: failed);
      }
    }, timeout: const Timeout(Duration(minutes: 30)));
  }
}
