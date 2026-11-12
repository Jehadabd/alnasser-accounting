// test/sync_harness/compound_receipt_test.dart
//
// 🧾 الوصل المركّب (عدة عملاء في وصل واحد) لا يبقى نصف مسجّل بلا علم صاحب المحل.
//
// الانقطاع (انطفاء الكهرباء / إغلاق البرنامج) بين عميل وآخر، أو داخل سطر عميل بين
// تسديده وخصمه، ثم إعادة تشغيل مفاجئة:
//   • الوصل يظهر «لم يكتمل» بما سُجّل وما بقي — لا يُكمل ولا يُلغى وحده.
//   • «أكمل»: تُسجَّل الأسطر الناقصة فقط — لا تكرار لما سُجّل، والصندوق والعملاء صحيحون.
//   • «أبقِ ما سُجّل»: لا يُضاف شيء، والوصل يصف ما سُجّل فعلاً (مجموعه وعمولته).
//   • وصل لم يُسجَّل منه شيء ثم «أبقِ»: يُحذف رأسه الفارغ ولا يتغيّر مال.
//   • وصل فشل أحد أسطره (لا انقطاع): مجموع رأسه = ما سُجّل لا ما خُطّط.
//
// التشغيل: claude_test_compound_receipt.bat
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('🧾 الوصل المركّب بعد انقطاع في منتصفه', () async {
    final h = Harness(seed: 51);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    void ok(String p) => print('✓ $p');
    double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    bool near(double a, double b) => (a - b).abs() <= 0.011;

    try {
      await h.start(1);
      const dev = 'D1';
      Future<Map> rest(String op, [Map<String, Object?> a = const {}]) async {
        final r = await h.rest(dev, op, a, const Duration(minutes: 3));
        if (r is Map && r['ok'] == false && r['err'] != null) throw StateError('$op: ${r['err']}');
        return r is Map ? r : {'value': r};
      }

      Future<double> bal(String c) async => dd(((await h.d(dev).call('custBalance', {'cust': c})) as Map)['sum']);
      Future<double> box() async {
        final m = (await h.d(dev).call('acct', {'op': 'boxBalances', 'args': const {}}, const Duration(minutes: 3)) as Map);
        if (m['ok'] == false) throw StateError('boxBalances: ${m['err']}');
        return m.values.fold<double>(0, (s, v) => s + dd(v));
      }

      Future<List<Map>> incomplete() async => ((await h.rest(dev, 'receiptsIncomplete')) as List).cast<Map>();
      Future<void> invariants(String stage) async {
        for (final e in ((await h.rest(dev, 'invariants')) as List).cast<String>()) {
          bad('$stage: $e');
        }
      }

      Future<List<String>> customers(String tag) async {
        final out = <String>[];
        for (final n in ['أ', 'ب', 'ج']) {
          final c = (await h.addCustomer(dev, 'زبون وصل $tag $n'))!;
          await h.addTx(dev, c, 10000);
          out.add(c);
        }
        return out;
      }

      // ═══ 1) انقطاع بعد العميل الأول ثم «أكمل» ═══
      var cs = await customers('1');
      var box0 = await box();
      await rest('receiptCrash', {
        'stopAfter': 1,
        'commission': 250,
        'marker': 'وصل1',
        'lines': [
          {'cust': cs[0], 'amount': 3000, 'discount': 500},
          {'cust': cs[1], 'amount': 4000, 'discount': 0},
          {'cust': cs[2], 'amount': 2000, 'discount': 0},
        ],
      });
      await h.restart(dev); // ⚡ انطفأ الحاسوب
      var inc = await incomplete();
      if (inc.length != 1) {
        bad('1: الوصل المنقطع لا يظهر (${inc.length})');
      } else {
        final r = inc.first;
        if (r['planned'] != 3 || r['posted'] != 1) bad('1: سُجّل ${r['posted']} من ${r['planned']} والمتوقع 1 من 3');
        if (!near(dd(r['postedAmount']), 3500) || !near(dd(r['missing']), 6000)) {
          bad('1: ما سُجّل ${r['postedAmount']} والباقي ${r['missing']} والمتوقع 3,500 و6,000');
        }
        ok('1: الوصل المنقطع ظاهر: سُجّل ${r['posted']} من ${r['planned']} (${r['postedAmount']})، الباقي ${r['missing']}');
        if (!near(await bal(cs[0]), 6500) || !near(await bal(cs[1]), 10000) || !near(await bal(cs[2]), 10000)) {
          bad('1: الأرصدة بعد الانقطاع ${await bal(cs[0])} / ${await bal(cs[1])} / ${await bal(cs[2])} والمتوقع 6,500 / 10,000 / 10,000');
        }
        if (!near(await box() - box0, 3000)) bad('1: الصندوق بعد الانقطاع +${await box() - box0} والمتوقع +3,000');

        final done = await rest('receiptComplete', {'id': r['id']});
        if ((done['errors'] as List).isNotEmpty) bad('1: الإكمال أخطأ: ${done['errors']}');
        if (done['status'] != 'complete') bad('1: حالة الوصل بعد الإكمال ${done['status']}');
        if (!near(dd(done['total']), 9000) || !near(dd(done['disc']), 500)) {
          bad('1: مجموع الوصل ${done['total']} وخصمه ${done['disc']} والمتوقع 9,000 و500');
        }
        if ((done['lines'] as List).length != 3) bad('1: أسطر الوصل ${(done['lines'] as List).length} والمتوقع 3');
        if (!near(await bal(cs[0]), 6500) || !near(await bal(cs[1]), 6000) || !near(await bal(cs[2]), 8000)) {
          bad('1: الأرصدة بعد الإكمال ${await bal(cs[0])} / ${await bal(cs[1])} / ${await bal(cs[2])} والمتوقع 6,500 / 6,000 / 8,000');
        }
        // الصندوق: 3,000 + 4,000 + 2,000 قبض − 250 عمولة
        if (!near(await box() - box0, 8750)) bad('1: الصندوق بعد الإكمال +${await box() - box0} والمتوقع +8,750');
        // إكمال ثانٍ مرفوض ولا يكرر شيئاً
        final again = await h.rest(dev, 'receiptComplete', {'id': r['id']});
        if (again is Map && again['ok'] == true) bad('1: إكمال ثانٍ قُبل');
        if (!near(await bal(cs[1]), 6000) || !near(await box() - box0, 8750)) bad('1: الإكمال الثاني غيّر المال');
        if ((await incomplete()).isNotEmpty) bad('1: بقي الوصل منقطعاً بعد الإكمال');
        if (problems.isEmpty) ok('1: أُكمل بلا تكرار — الأرصدة 6,500 / 6,000 / 8,000 والصندوق +8,750');
      }
      await invariants('1');

      // ═══ 2) انقطاع بعد عميلين ثم «أبقِ ما سُجّل» ═══
      final p2 = problems.length;
      cs = await customers('2');
      box0 = await box();
      await rest('receiptCrash', {
        'stopAfter': 2,
        'commission': 300,
        'marker': 'وصل2',
        'lines': [
          {'cust': cs[0], 'amount': 3000, 'discount': 500},
          {'cust': cs[1], 'amount': 4000, 'discount': 0},
          {'cust': cs[2], 'amount': 2000, 'discount': 0},
        ],
      });
      await h.restart(dev);
      inc = await incomplete();
      if (inc.length != 1) {
        bad('2: الوصل المنقطع لا يظهر (${inc.length})');
      } else {
        final kept = await rest('receiptKeep', {'id': inc.first['id']});
        if (kept['status'] != 'partial') bad('2: الحالة ${kept['status']} والمتوقع partial');
        if (!near(dd(kept['total']), 7000) || !near(dd(kept['disc']), 500)) {
          bad('2: مجموع الوصل ${kept['total']} وخصمه ${kept['disc']} والمتوقع 7,000 و500');
        }
        if (!near(dd(kept['commission']), 0)) bad('2: عمولة لم يُنشأ سندها بقيت ${kept['commission']}');
        if (!near(await bal(cs[2]), 10000)) bad('2: العميل الثالث تغيّر رصيده ${await bal(cs[2])}');
        if (!near(await box() - box0, 7000)) bad('2: الصندوق +${await box() - box0} والمتوقع +7,000');
        if ((await incomplete()).isNotEmpty) bad('2: بقي الوصل منقطعاً');
        if (problems.length == p2) ok('2: أُبقي ما سُجّل — الوصل 7,000 + خصم 500 بلا عمولة، والثالث لم يُمس');
      }
      await invariants('2');

      // ═══ 3) انقطاع داخل سطر (بعد التسديد وقبل الخصم) ثم «أكمل» ═══
      final p3 = problems.length;
      cs = await customers('3');
      box0 = await box();
      await rest('receiptCrash', {
        'stopInside': 0,
        'marker': 'وصل3',
        'lines': [
          {'cust': cs[0], 'amount': 3000, 'discount': 500},
          {'cust': cs[1], 'amount': 1000, 'discount': 0},
        ],
      });
      await h.restart(dev);
      inc = await incomplete();
      if (inc.length != 1) {
        bad('3: الوصل المنقطع لا يظهر (${inc.length})');
      } else {
        if (inc.first['posted'] != 0 || !near(dd(inc.first['postedAmount']), 3000)) {
          bad('3: المعروض: أسطر كاملة ${inc.first['posted']} وما سُجّل ${inc.first['postedAmount']} — المتوقع 0 و3,000');
        }
        final done = await rest('receiptComplete', {'id': inc.first['id']});
        if (!near(await bal(cs[0]), 6500)) bad('3: رصيد الأول ${await bal(cs[0])} والمتوقع 6,500 (تسديد مرة واحدة + خصم)');
        if (!near(await bal(cs[1]), 9000)) bad('3: رصيد الثاني ${await bal(cs[1])} والمتوقع 9,000');
        if (!near(await box() - box0, 4000)) bad('3: الصندوق +${await box() - box0} والمتوقع +4,000');
        final l0 = (done['lines'] as List).cast<Map>().first;
        if (!near(dd(l0['before']), 10000) || !near(dd(l0['after']), 6500)) {
          bad('3: سطر الأول «قبل ${l0['before']} بعد ${l0['after']}» والمتوقع 10,000 ← 6,500');
        }
        if (problems.length == p3) ok('3: انقطاع داخل السطر: التسديد لم يتكرر، والخصم أُكمل، والرصيد قبل/بعد صحيح');
      }
      await invariants('3');

      // ═══ 4) انقطاع قبل أي سطر ثم «أبقِ» ⇐ يُحذف الرأس الفارغ ═══
      cs = await customers('4');
      box0 = await box();
      await rest('receiptCrash', {
        'stopAfter': 0,
        'marker': 'وصل4',
        'lines': [
          {'cust': cs[0], 'amount': 3000, 'discount': 0},
        ],
      });
      await h.restart(dev);
      inc = await incomplete();
      if (inc.length != 1) {
        bad('4: الوصل المنقطع لا يظهر');
      } else {
        final kept = await rest('receiptKeep', {'id': inc.first['id']});
        if (kept['exists'] != false) bad('4: بقي رأس وصل فارغ');
        if (!near(await bal(cs[0]), 10000) || !near(await box(), box0)) bad('4: تغيّر مال في وصل لم يُسجَّل منه شيء');
        else ok('4: وصل لم يُسجَّل منه شيء: حُذف رأسه ولم يتغيّر مال');
      }
      await invariants('4');

      problems.addAll(await h.deviceErrors());
      print('\n${problems.isEmpty ? '✅ نجح: الوصل المركّب لا يبقى نصف مسجّل بلا علم، ولا يتكرر عند الإكمال' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
