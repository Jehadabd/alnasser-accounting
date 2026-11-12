// test/sync_harness/armored_gaps_test.dart
//
// 🔐 المطابقة المحصّنة — فروع لم يمر بها اختبار، بكود التطبيق الحقيقي:
//   • الجهاز المرسل (D1) عنده معاملة من إصدار قديم بلا معرّف مزامنة ⇒ يُعطيها معرّفاً قبل بناء
//     الكشف، فتصل الجهاز الآخر ولا تضيع (_buildCustomerLedger).
//   • الجهاز المطبِّق (D2) عنده معاملة من إنشائه لم يعرفها المرسل، وصف فاتورة من إنشائه لم
//     يعرفه ⇒ يُصانان ويُعادان للرفع (المعاملة وحدها، وصف الفاتورة داخل حزمتها) فيصلان D1
//     (_applyCustomerLedger). والمعاملة العالقة الغريبة تُبطَل بموافقة صاحب D2.
// النتيجة: الجهازان على الرصيد نفسه 6,000.
//
// التشغيل: claude_test_gaps.bat
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('🔐 المحصّنة: معاملة قديمة بلا معرّف، ومعاملات المطبِّق التي لم يعرفها المرسل', () async {
    final h = Harness(seed: 1610);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    void ok(String p) => print('✓ $p');
    double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    bool near(double a, double b) => (a - b).abs() <= 0.01;

    try {
      await h.start(2);
      Future<double> bal(String dev, String c) async =>
          dd(((await h.d(dev).call('custBalance', {'cust': c})) as Map)['sum']);
      Future<List<Map>> pending(String dev) async => ((await h.d(dev).call('armoredPending')) as List).cast<Map>();
      Future<List<Map>> waitPending(String dev, int n) async {
        for (var i = 0; i < 60; i++) {
          final p = await pending(dev);
          if (p.length >= n) return p;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        return pending(dev);
      }

      Future<void> invariants(String dev, String stage) async {
        for (final e in ((await h.rest(dev, 'invariants')) as List).cast<String>()) {
          bad('$stage ($dev) — فحص المال الشامل: $e');
        }
      }

      final c = (await h.addCustomer('D1', 'زبون المحصّنة المصونة'))!;
      await h.addTx('D1', c, 3000);
      final inv = (await h.saveInvoice('D2', c, 2000, 0, 'دين'))!;
      final e0 = await h.settle();
      if (e0.isNotEmpty) throw StateError('البداية: ${e0.join('\n')}');

      // D1: معاملة من إصدار قديم — بلا معرّف مزامنة ولم تُرفع قط
      await h.d('D1').call('ghostTx', {'cust': c, 'amount': 400, 'tag': 'leg', 'mine': true});
      await h.d('D1').call('sqlRaw', {
        'sql': "UPDATE transactions SET transaction_uuid = NULL, sync_uuid = NULL WHERE transaction_uuid = 'ghost_leg'"
      });
      // D2: معاملة غريبة عالقة (تُبطَل)، ومعاملة من إنشائه وصف فاتورة من إنشائه لم يعرفهما D1
      await h.d('D2').call('ghostTx', {'cust': c, 'amount': 5000, 'tag': 'stale'});
      await h.d('D2').call('ghostTx', {'cust': c, 'amount': 600, 'tag': 'own', 'mine': true});
      await h.d('D2').call('ghostTx', {'cust': c, 'amount': 0, 'tag': 'invrow', 'mine': true, 'inv': inv});

      final r = (await h.d('D1').call('armoredPushWait', {'cust': c}, const Duration(minutes: 3))) as Map;
      if (r['awaiting'] != true) bad('الكشف سيغيّر D2 ولم ينتظر موافقته: $r');
      final p = await waitPending('D2', 1);
      if (p.length != 1) {
        bad('لا طلب منتظر على D2 (${p.length})');
      } else {
        final pv = p.first;
        if (dd(pv['previewVoidCount']) != 1 || !near(dd(pv['previewVoidSum']), 5000)) {
          bad('المعاينة لا تذكر إبطال العالقة 5,000: $pv');
        }
        if (dd(pv['previewAddCount']) != 1 || !near(dd(pv['previewAddSum']), 400)) {
          bad('المعاينة لا تذكر إضافة القديمة 400: $pv');
        }
        if (!near(dd(pv['previewBalanceAfter']), 6000)) bad('المعاينة: الرصيد بعد ${pv['previewBalanceAfter']} والمتوقع 6,000');
        await h.d('D2').call('armoredDecide', {'cust': c, 'approve': true});
      }

      final legacy = (await h.d('D1').call('sqlRaw', {
        'sql': 'SELECT transaction_uuid AS u FROM transactions WHERE amount_changed = 400 AND COALESCE(is_deleted, 0) = 0'
      })) as List;
      final lu = legacy.isEmpty ? '' : '${(legacy.first as Map)['u'] ?? ''}';
      if (!lu.startsWith('txb_')) bad('المعاملة القديمة على D1 لم تُعطَ معرّفاً قبل الكشف ($lu)');
      else ok('D1: المعاملة القديمة أُعطيت معرّفاً ($lu) قبل بناء الكشف');

      final d2 = await bal('D2', c);
      if (!near(d2, 6000)) bad('رصيد D2 بعد الموافقة $d2 والمتوقع 6,000 (3,000 + 2,000 + 400 + 600)');
      else ok('D2 بعد الموافقة: 6,000 — أُبطلت العالقة، وأُضيفت القديمة، وبقيت معاملته وصف فاتورته');

      // ما صانه D2 يُعاد رفعه فيصل D1
      var d1 = await bal('D1', c);
      for (var i = 0; i < 12 && !near(d1, 6000); i++) {
        await h.d('D2').call('kick');
        await h.waitCloudQuiet();
        await h.d('D1').call('kick');
        d1 = await bal('D1', c);
      }
      if (!near(d1, 6000)) bad('رصيد D1 بعد رفع ما صانه D2: $d1 والمتوقع 6,000');
      else ok('D1 استلم ما صانه D2: الجهازان 6,000');
      final row = (await h.d('D1').call('sqlRaw', {
        'sql': "SELECT COUNT(*) AS n FROM transactions WHERE transaction_uuid = 'ghost_invrow'"
      })) as List;
      if (dd((row.first as Map)['n']) != 1) bad('صف الفاتورة الذي صانه D2 لم يصل D1 داخل حزمتها');
      else ok('صف الفاتورة وصل D1 داخل حزمة فاتورته');

      await invariants('D1', 'النهاية');
      await invariants('D2', 'النهاية');
      problems.addAll(await h.deviceErrors());
      print('\n${problems.isEmpty ? '✅ نجح: المحصّنة لا تُضيّع معاملة قديمة ولا معاملات المطبِّق' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
