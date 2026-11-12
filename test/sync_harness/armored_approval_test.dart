// test/sync_harness/armored_approval_test.dart
//
// 🔐 المطابقة المحصّنة لا تكتب على جهاز آخر دون علم صاحبه.
//
// «بياناتي صحيحة» على جهاز D1 يرسل كشف العميل. على D2:
//   • كشف لا يغيّر شيئاً ⇐ يُرد عليه فوراً (نجاح) كما كان.
//   • كشف سيُبطل معاملة أو يضيف معاملة ⇐ لا يُطبَّق. يظهر لصاحب D2 بما سيحدث بالضبط
//     (العدد والمجموع والرصيد قبل وبعد)، ورصيده لا يتغيّر حتى يوافق.
//   • رفض ⇐ لا يتغيّر شيء، ويعلم D1 بالرفض.  موافقة ⇐ يُطبَّق الكشف نفسه، ويتطابق الرصيد.
//   • الطلب المنتظر يبقى بعد إعادة تشغيل D2 (محفوظ)، ولا يُطبَّق وحده بعدها.
//
// التشغيل: claude_test_armored.bat
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('🔐 المطابقة المحصّنة: لا كتابة على الجهاز الآخر إلا بموافقة صاحبه', () async {
    final h = Harness(seed: 41);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    void ok(String p) => print('✓ $p');
    double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;

    try {
      await h.start(2);
      Future<double> bal(String dev, String c) async =>
          dd(((await h.d(dev).call('custBalance', {'cust': c})) as Map)['sum']);
      Future<List<Map>> pending(String dev) async =>
          ((await h.d(dev).call('armoredPending')) as List).cast<Map>();
      Future<Map> push(String dev, String c) async =>
          (await h.d(dev).call('armoredPushWait', {'cust': c}, const Duration(minutes: 3))) as Map;
      Future<List<Map>> waitPending(String dev, int n) async {
        for (var i = 0; i < 60; i++) {
          final p = await pending(dev);
          if (p.length >= n) return p;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        return pending(dev);
      }

      // ── 1) كشف لا يغيّر شيئاً: نجاح فوري بلا موافقة ──
      final c1 = (await h.addCustomer('D1', 'زبون مطابقة متطابق'))!;
      await h.addTx('D1', c1, 2000);
      await h.addTx('D2', c1, -500);
      final e1 = await h.settle();
      if (e1.isNotEmpty) throw StateError('البداية: ${e1.join('\n')}');
      final r1 = await push('D1', c1);
      if (r1['ok'] != true) bad('كشف متطابق لم ينجح فوراً: $r1');
      if ((await pending('D2')).isNotEmpty) bad('كشف لا يغيّر شيئاً طُلبت له موافقة');
      if (r1['ok'] == true) ok('كشف لا يغيّر شيئاً: نجح فوراً بلا موافقة');

      // ── 2) معاملة عالقة بلا أثر على D2: الكشف سيبطلها ⇐ ينتظر الموافقة ──
      final c2 = (await h.addCustomer('D1', 'زبون مطابقة شبح'))!;
      await h.addTx('D1', c2, 3000);
      final e2 = await h.settle();
      if (e2.isNotEmpty) throw StateError('قبل الشبح: ${e2.join('\n')}');
      await h.d('D2').call('ghostTx', {'cust': c2, 'amount': 5000, 'tag': 'g1'});
      final before = await bal('D2', c2); // 3000 + 5000
      if ((before - 8000).abs() > 0.01) bad('رصيد D2 مع الشبح $before والمتوقع 8,000');

      final r2 = await push('D1', c2);
      if (r2['ok'] == true || r2['awaiting'] != true) bad('كشف سيغيّر D2 لم يُعلَّم «بانتظار الموافقة»: $r2');
      var p2 = await waitPending('D2', 1);
      if (p2.length != 1) {
        bad('لا طلب منتظر على D2 (${p2.length})');
      } else {
        final pv = p2.first;
        if (dd(pv['previewVoidCount']) != 1 || (dd(pv['previewVoidSum']) - 5000).abs() > 0.01) {
          bad('المعاينة لا تذكر إبطال الشبح 5,000: $pv');
        }
        if ((dd(pv['previewBalanceNow']) - 8000).abs() > 0.01 || (dd(pv['previewBalanceAfter']) - 3000).abs() > 0.01) {
          bad('المعاينة: الرصيد ${pv['previewBalanceNow']} ← ${pv['previewBalanceAfter']} والمتوقع 8,000 ← 3,000');
        }
        ok('المعاينة على D2: ${pv['previewVoidCount']} إبطال بمجموع ${pv['previewVoidSum']}، '
            'الرصيد ${pv['previewBalanceNow']} ← ${pv['previewBalanceAfter']}');
      }
      if ((await bal('D2', c2) - before).abs() > 0.01) bad('رصيد D2 تغيّر قبل الموافقة');

      // الطلب يبقى بعد إعادة تشغيل D2 ولا يُطبَّق وحده
      await h.restart('D2');
      p2 = await pending('D2');
      if (p2.length != 1) bad('الطلب المنتظر ضاع بعد إعادة تشغيل D2');
      if ((await bal('D2', c2) - before).abs() > 0.01) bad('رصيد D2 تغيّر بعد إعادة التشغيل دون موافقة');

      // ── رفض ──
      final rj = (await h.d('D2').call('armoredDecide', {'cust': c2, 'approve': false})) as Map;
      if (rj['ok'] != true) bad('الرفض فشل: $rj');
      if ((await pending('D2')).isNotEmpty) bad('بقي الطلب بعد الرفض');
      if ((await bal('D2', c2) - before).abs() > 0.01) bad('الرفض غيّر رصيد D2');
      if (rj['ok'] == true) ok('الرفض: لم يتغيّر شيء على D2');

      // ── موافقة ──
      final r3 = await push('D1', c2);
      if (r3['awaiting'] != true) bad('الطلب الثاني لم يُعلَّم «بانتظار الموافقة»: $r3');
      await waitPending('D2', 1);
      final ap = (await h.d('D2').call('armoredDecide', {'cust': c2, 'approve': true})) as Map;
      if (ap['ok'] != true) bad('الموافقة فشلت: $ap');
      final after = await bal('D2', c2);
      if ((after - 3000).abs() > 0.01) bad('بعد الموافقة رصيد D2 $after والمتوقع 3,000');
      if ((await pending('D2')).isNotEmpty) bad('بقي الطلب بعد الموافقة');
      if ((after - 3000).abs() <= 0.01) ok('الموافقة: طُبّق الكشف ورصيد D2 = 3,000 كـ D1');

      // ── كل الأجهزة متطابقة مع الحقيقة ──
      final e3 = await h.settle();
      for (final e in e3) {
        bad('بعد الموافقة: $e');
      }

      // ── 3) معاملة على D1 لم تصل D2: الكشف سيضيفها ⇐ ينتظر، ثم موافقة تضيفها ──
      final c3 = (await h.addCustomer('D1', 'زبون مطابقة ناقص'))!;
      await h.addTx('D1', c3, 1000);
      final e4 = await h.settle();
      if (e4.isNotEmpty) throw StateError('قبل الناقص: ${e4.join('\n')}');
      await h.d('D1').call('ghostTx', {'cust': c3, 'amount': 700, 'tag': 'm1', 'mine': true});
      final r4 = await push('D1', c3);
      if (r4['awaiting'] != true) bad('كشف سيضيف معاملة على D2 لم ينتظر الموافقة: $r4');
      final p4 = await waitPending('D2', 1);
      if (p4.isEmpty || dd(p4.first['previewAddCount']) != 1 || (dd(p4.first['previewAddSum']) - 700).abs() > 0.01) {
        bad('المعاينة لا تذكر إضافة 700: $p4');
      }
      if ((await bal('D2', c3) - 1000).abs() > 0.01) bad('D2 أضاف قبل الموافقة');
      await h.d('D2').call('armoredDecide', {'cust': c3, 'approve': true});
      if ((await bal('D2', c3) - 1700).abs() > 0.01) bad('بعد الموافقة رصيد D2 ${await bal('D2', c3)} والمتوقع 1,700');
      else ok('الإضافة بعد الموافقة: رصيد D2 = 1,700 كـ D1');

      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
      problems.addAll(await h.deviceErrors());
      print('\n${problems.isEmpty ? '✅ نجح: لا كتابة على الجهاز الآخر إلا بموافقة صاحبه' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
