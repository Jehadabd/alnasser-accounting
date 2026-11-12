// test/sync_harness/lan_money_test.dart
//
// 🖧 الشبكة المحلية بكود التطبيق الحقيقي: «حاسبة السيرفر» (D1) تشغّل خادم الشبكة على اتصال
// قاعدتها نفسه، وطرفيتان (T1، T2) تعملان على قاعدتها عبر الشبكة — كل جهاز خيط مستقل كما
// هو برنامج مستقل في المحل. ما يُفحص:
//   1. ديون وتسديدات من الطرفيتين والسيرفر في اللحظة نفسها ⇒ لا تضيع ولا تتكرر، ودين
//      العميل المخزّن = مجموع معاملاته.
//   2. فواتير آجلة ونقدية من الطرفيتين معاً ⇒ دين العميل صحيح وأرقام الفواتير بلا تكرار.
//   3. سقوط الشبكة في منتصف معاملة على الطرفية ⇒ لا يُحفظ منها شيء، والسيرفر لا يتجمّد،
//      والطرفية تعيد الاتصال وتحفظ بعدها.
//   4. سقوط الشبكة بين عمليتين ⇒ الطرفية تعيد الاتصال وحدها ولا يضيع شيء.
//   5. طرفية بإصدار قديم ترسل «PRAGMA synchronous = NORMAL» ⇒ السيرفر يبقى FULL (الحفظ
//      على القرص لا يُضعَف من طرفية).
//   6. سيرفر بإصدار قاعدة أقدم من الطرفية ⇒ الطرفية ترفض العمل برسالة واضحة.
//   7. فحص المال الشامل على قاعدة السيرفر في النهاية (rest invariants).
//
// التشغيل: claude_test_lan.bat
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('🖧 الشبكة المحلية: سيرفر وطرفيتان بكود التطبيق', () async {
    final h = Harness(seed: 61);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    void ok(String p) => print('✓ $p');
    double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    bool near(double a, double b) => (a - b).abs() <= 0.011;
    const secret = 'lan-test-secret';

    try {
      // السيرفر: جهاز عادي (قاعدته ومزامنته) + خادم الشبكة
      await h.spawn('D1');
      await h.initDevice('D1');
      final port = (await h.d('D1').call('lanServe', {'secret': secret})) as int;
      ok('خادم الشبكة يعمل على المنفذ $port');

      // الطرفيتان: بلا تهيئة مزامنة، قاعدتهما قاعدة السيرفر عبر الشبكة
      for (final t in ['T1', 'T2']) {
        await h.spawn(t, online: false);
        final j = (await h.d(t).call('lanJoin', {'port': port, 'secret': secret, 'name': t})) as Map;
        if (j['ok'] != true) throw StateError('$t لم تتصل: ${j['err']}');
      }
      ok('الطرفيتان متصلتان');

      Future<Map> bal(String dev, String c) async => (await h.d(dev).call('custBalance', {'cust': c})) as Map;
      Future<void> invariants(String stage) async {
        for (final e in ((await h.rest('D1', 'invariants')) as List).cast<String>()) {
          bad('$stage: $e');
        }
      }

      // ── 1) دين وتسديد من الأجهزة الثلاثة معاً ──
      final c = (await h.addCustomer('T1', 'زبون الشبكة'))!;
      final rnd = Random(61);
      var expected = 0.0;
      final futures = <Future<void>>[];
      for (final dev in ['D1', 'T1', 'T2']) {
        futures.add(() async {
          for (var i = 0; i < 25; i++) {
            final amount = (rnd.nextBool() ? 1 : -1) * (100 + rnd.nextInt(20) * 50).toDouble();
            final tu = await h.addTx(dev, c, amount);
            if (tu != null) expected += amount;
          }
        }());
      }
      await Future.wait(futures);
      for (final dev in ['D1', 'T1', 'T2']) {
        final b = await bal(dev, c);
        if (!near(dd(b['sum']), expected) || !near(dd(b['debt']), expected)) {
          bad('1: $dev يرى الدين ${b['debt']} (مجموع المعاملات ${b['sum']}) والمتوقع $expected');
        }
      }
      if (problems.isEmpty) ok('1: 75 معاملة من 3 أجهزة معاً — الدين $expected على الجميع، مخزّناً ومجموعاً');
      await invariants('1');

      // ── 2) فواتير من الطرفيتين معاً ──
      final p2 = problems.length;
      await h.d('T1').call('addProduct', {'name': 'مادة الشبكة', 'stock': 100000});
      final prods = ((await h.d('T1').call('scen', {'op': 'prodIds', 'args': const {}})) as Map)['rows'] as List;
      final pid = ((prods.firstWhere((r) => (r as Map)['name'] == 'مادة الشبكة') as Map)['id'] as num).toInt();
      final c2name = 'زبون فواتير الشبكة';
      var invDebt = 0.0;
      final invUuids = <String>[];
      Future<void> invoices(String dev) async {
        for (var i = 0; i < 6; i++) {
          final credit = i.isEven;
          final price = 1000.0 + i * 250;
          final r = (await h.d(dev).call('scen', {
            'op': 'invSave',
            'args': {
              'name': c2name,
              'items': [
                {'prodId': pid, 'qty': 2, 'price': price}
              ],
              'discount': 0,
              'fee': 0,
              'paid': credit ? 500 : 2 * price,
              'ptype': credit ? 'دين' : 'نقد',
            },
          }, const Duration(minutes: 3))) as Map;
          if (r['ok'] != true) {
            bad('2: $dev فاتورة ${i + 1} رُفضت: ${r['stage']} ${r['err']}');
            continue;
          }
          invUuids.add(r['uuid'] as String);
          if (credit) invDebt += 2 * price - 500;
        }
      }

      await Future.wait([invoices('T1'), invoices('T2')]);
      if (invUuids.toSet().length != invUuids.length) bad('2: فواتير بنفس المعرّف');
      final c2 = (((await h.d('D1').call('scen', {'op': 'custByName', 'args': {'name': c2name}})) as Map)['rows'] as List);
      if (c2.length != 1) {
        bad('2: عميل الفواتير ${c2.length} بطاقة والمتوقع واحدة');
      } else if (!near(dd((c2.first as Map)['debt']), invDebt)) {
        bad('2: دين عميل الفواتير ${(c2.first as Map)['debt']} والمتوقع $invDebt');
      }
      final nums = ((await h.d('D1').call('sqlRaw', {
        'sql': "SELECT invoice_number AS n, COUNT(*) AS k FROM invoices WHERE customer_name = '$c2name' "
            'GROUP BY invoice_number HAVING COUNT(*) > 1'
      })) as List);
      if (nums.isNotEmpty) bad('2: أرقام فواتير مكررة: $nums');
      if (problems.length == p2) ok('2: 12 فاتورة من طرفيتين معاً — الدين $invDebt وأرقام بلا تكرار');
      await invariants('2');

      // ── 3) سقوط الشبكة في منتصف معاملة على الطرفية ──
      final p3 = problems.length;
      final before3 = dd((await bal('D1', c))['sum']);
      final r3 = (await h.d('T1').call('lanTxnDrop', {'cust': c, 'amount': 7777, 'marker': 'سقوط3'})) as Map;
      if (r3['committed'] == true) bad('3: معاملة سقطت شبكتها في منتصفها حُفظت');
      final seen = (await h.d('D1').call('sqlRaw', {
        'sql': "SELECT COUNT(*) AS n FROM transactions WHERE transaction_note LIKE 'سقوط3%'"
      })) as List;
      if (((seen.first as Map)['n'] as num) != 0) bad('3: بقي من المعاملة الساقطة ${(seen.first as Map)['n']} صف');
      // السيرفر لا يتجمّد: يكتب فوراً
      final tS = await h.addTx('D1', c, 10).timeout(const Duration(seconds: 15));
      if (tS != null) expected += 10;
      // والطرفية تعيد الاتصال وتحفظ
      final t3 = await h.addTx('T1', c, 20);
      if (t3 != null) expected += 20;
      final after3 = dd((await bal('D1', c))['sum']);
      if (!near(after3, before3 + 30)) bad('3: الدين $after3 والمتوقع ${before3 + 30}');
      if (problems.length == p3) ok('3: سقوط الشبكة وسط معاملة: لم يُحفظ منها شيء، والسيرفر والطرفية يكملان');

      // ── 4) سقوط الشبكة بين عمليتين ──
      final p4 = problems.length;
      await h.d('T2').call('lanDrop');
      final t4 = await h.addTx('T2', c, -55);
      if (t4 == null) bad('4: التسديد بعد سقوط الشبكة لم يُحفظ');
      if (t4 != null) expected -= 55;
      if (!near(dd((await bal('D1', c))['sum']), expected)) bad('4: الدين بعد إعادة الاتصال ${(await bal('D1', c))['sum']} والمتوقع $expected');
      if (problems.length == p4) ok('4: سقوط الشبكة بين عمليتين: الطرفية أعادت الاتصال وحفظت');

      // ── 5) طرفية تحاول إضعاف الحفظ على القرص ──
      await h.d('T1').call('sqlRaw', {'sql': 'PRAGMA synchronous = NORMAL'});
      final dur = (await h.d('D1').call('durability')) as Map;
      if (dur['sync'] != 2) {
        bad('5: طرفية أنزلت الحفظ على القرص عند السيرفر إلى ${dur['sync']}');
      } else {
        ok('5: «PRAGMA synchronous = NORMAL» من طرفية ⇒ السيرفر بقي FULL');
      }

      // ── 6) سيرفر بإصدار قاعدة أقدم من الطرفية ⇒ رفض واضح ──
      final ver = (((await h.d('D1').call('sqlRaw', {'sql': 'PRAGMA user_version'})) as List).first as Map).values.first as int;
      await h.d('D1').call('sqlRaw', {'sql': 'PRAGMA user_version = ${ver - 1}'});
      await h.spawn('T3', online: false);
      final j3 = (await h.d('T3').call('lanJoin', {'port': port, 'secret': secret, 'name': 'T3'})) as Map;
      await h.d('D1').call('sqlRaw', {'sql': 'PRAGMA user_version = $ver'});
      if (j3['ok'] == true) {
        bad('6: طرفية أحدث عملت على قاعدة سيرفر أقدم (الإصدار ${ver - 1})');
      } else if (!'${j3['err']}'.contains('أقدم')) {
        bad('6: الرفض بلا رسالة واضحة: ${j3['err']}');
      } else {
        ok('6: سيرفر أقدم ⇒ الطرفية رفضت: ${j3['err']}');
      }

      // ── 7) الفحص الشامل النهائي ──
      await invariants('7');
      for (final dev in ['D1', 'T1', 'T2']) {
        final b = await bal(dev, c);
        if (!near(dd(b['sum']), expected)) bad('7: $dev يرى ${b['sum']} والمتوقع $expected');
      }
      problems.addAll(await h.deviceErrors());
      print('\n${problems.isEmpty ? '✅ نجح: الشبكة المحلية لا تضيّع مالاً ولا تكرره' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
