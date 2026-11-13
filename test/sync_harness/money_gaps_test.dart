// test/sync_harness/money_gaps_test.dart
//
// 🕳️ مسارات المال التي لم يمر بها أي اختبار (تقرير claude_money_coverage.bat) — الدفعتان 1 و2،
// على حاسبة محل بلا مزامنة (S1) بكود التطبيق الحقيقي. بعد كل بند: فحص المال الشامل.
//   1. فاتورة شراء تُعاد حفظها بمعرّفها: تأكيد مسودة، تعديل مؤكدة، إرجاعها مسودة (لا مضاعفة).
//   2. إلغاء دفعة مورد صفّها من إصدار قديم (بلا معرّفها الثابت)، ورفض إلغاء ما لا أثر له.
//   3. دمج حسابين مكررين: الفواتير والمعاملات تنتقل، الرصيد = المجموع، والفاتورة تُعدَّل بعده.
//   4. نقاط المؤسسين: خصم «تسديد دين راجع» نسبةً وبلا تجاوز، حذف الحركة، وقاعدة مستوردة.
//   5. زر الإصلاح في الفحص العميق: «اعتمد سجل الديون»، و«اعتمد الفاتورة» على فاتورة مستعادة.
// الدفعة 2:
//   6. فاتورة الكاشير تُختم بصندوق الطرفية ومخزنها وتُرحَّل إلى صندوقها.
//   7. معاملة رُفضت بعد كتابة وصفها: لا وصف يتيم.
//   8. «أبقِ ما سُجّل» لوصل قبض انقطع داخل سطر (بعد التسديد وقبل الخصم).
//   9. تثبيت كلفة بنود قديمة بلا كلفة قبل تغيّر كلفة المادة.
//  10. قيد صفري لفاتورة صفرية قديمة بلا كلفة ولا مقبوض (لا يتكرر، والميزان متوازن).
//  11. البائع وعمولته (نسبة، يدوية، سالبة مرفوضة، فترة مثبّتة).
//  12. عملاء ليسوا في سجل الديون: الكشف والاستعادة بلا تغيير معاملة.
//  13. ربط فاتورة نقدية قديمة بعميلها بالاسم.
//  14. فاتورة الشاشة العادية والمعلّقة حين تُحفظ تُختمان بصندوق الحاسبة ومخزنها، والتعديل لا يغيّر الختم.
//
// التشغيل: claude_test_gaps.bat
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('🕳️ مسارات المال غير المغطاة — الدفعتان 1 و2', () async {
    final h = Harness(seed: 1601);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    void ok(String p) => print('✓ $p');
    double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    const dev = 'S1';

    try {
      await h.spawn(dev, prefs: const {}, online: false); // محل بلا مزامنة
      final d = h.d(dev);
      late final int pid; // معرّف مادة الاختبار على الجهاز

      Future<void> invariants(String stage) async {
        for (final e in ((await h.rest(dev, 'invariants')) as List).cast<String>()) {
          bad('$stage — فحص المال الشامل: $e');
        }
      }

      Future<Object?> gapRaw(String op, [Map<String, Object?> args = const {}]) =>
          d.call('gap', {'op': op, 'args': args}, const Duration(minutes: 3));

      Future<void> gap(String title, String op, [Map<String, Object?> args = const {}]) async {
        final r = (await gapRaw(op, args)) as Map;
        final fails = (r['fails'] as List).cast<String>();
        for (final f in fails) {
          bad('$title: $f');
        }
        if (fails.isEmpty) ok('$title — ${(r['notes'] as List).join('؛ ')}');
        await invariants(title);
      }

      Future<String> invSave(String name, double qty, double price, double paid, String ptype,
          {String? inv, String? installer, double rate = 0}) async {
        final r = (await d.call('scen', {
          'op': 'invSave',
          'args': {
            'inv': inv,
            'name': name,
            'items': [
              {'prodId': pid, 'qty': qty, 'price': price}
            ],
            'discount': 0,
            'fee': 0,
            'paid': paid,
            'ptype': ptype,
            'installer': installer,
            'rate': rate,
          },
        }, const Duration(minutes: 2))) as Map;
        if (r['ok'] != true) throw StateError('حفظ فاتورة «$name» رُفض: ${r['stage']} ${r['err']}');
        return r['uuid'] as String;
      }

      Future<Map> cust(String uuid) async =>
          (await d.call('scen', {'op': 'custByUuid', 'args': {'cust': uuid}})) as Map;

      final prod = (await h.addProduct(dev, 'مادة الفجوات', 1000))!;
      final prods = ((await d.call('scen', {'op': 'prodIds', 'args': const {}})) as Map)['rows'] as List;
      pid = ((prods.firstWhere((r) => (r as Map)['uuid'] == prod) as Map)['id'] as num).toInt();

      // ── 1، 2: المشتريات والموردون ──
      await gap('1 فاتورة شراء تُعاد حفظها بمعرّفها', 'purResave', {'prod': prod});
      await gap('2 إلغاء دفعة مورد من إصدار قديم', 'supVoidLegacy', {'prod': prod});

      // ── 3: دمج حسابين مكررين ──
      final p3 = problems.length;
      final a = (await h.addCustomer(dev, 'أحمد علي'))!;
      await h.addTx(dev, a, 1000);
      await h.addTx(dev, a, -200);
      final inv = await invSave('أحمد علي', 5, 1000, 1000, 'دين'); // دين 4,000
      final dup = await gapRaw('dupCustomer', {'name': 'أحمد  علي'});
      if (dup is! String) {
        bad('3: تعذّر صنع الحساب المكرر: $dup');
      } else {
        final b = dup;
        await h.addTx(dev, b, 700);
        final m = (await gapRaw('merge', {'survivor': b, 'merged': [a]})) as Map;
        if (m['ok'] != true) {
          bad('3: الدمج رُفض: ${m['err']}');
        } else {
          if ((dd(m['before']) - 5500).abs() > 0.005 || (dd(m['after']) - 5500).abs() > 0.005) {
            bad('3: الرصيد قبل/بعد الدمج ${m['before']}/${m['after']} والمتوقع 5500');
          }
          if (m['index'] != true) bad('3: قيد «الاسم فريد» لم يُفعَّل بعد زوال التكرار');
          final ca = await cust(a), cb = await cust(b);
          if (dd(ca['del']) != 1) bad('3: الحساب المدموج ما زال ظاهراً');
          if ((dd(cb['debt']) - 5500).abs() > 0.005 || (dd(cb['txsum']) - 5500).abs() > 0.005) {
            bad('3: الحساب الباقي ${cb['debt']} (معاملاته ${cb['txsum']}) والمتوقع 5500');
          }
          final owner = (await d.call('sqlRaw', {
            'sql': 'SELECT c.sync_uuid AS u FROM invoices i JOIN customers c ON c.id = i.customer_id '
                "WHERE i.invoice_uuid = '$inv'"
          })) as List;
          if (owner.isEmpty || (owner.first as Map)['u'] != b) bad('3: الفاتورة لم تنتقل إلى الحساب الباقي');
          await invSave('أحمد  علي', 5, 1000, 3000, 'دين', inv: inv); // تسديد 2,000 على الفاتورة
          final cb2 = await cust(b);
          if ((dd(cb2['debt']) - 3500).abs() > 0.005) bad('3: بعد تعديل الفاتورة المنقولة الدين ${cb2['debt']} والمتوقع 3500');
        }
      }
      if (problems.length == p3) ok('3 دمج حسابين مكررين — 4,800 + 700 = 5,500، الفاتورة انتقلت وعُدّلت بعده (3,500)');
      await invariants('3');

      // ── 4: المؤسسون ──
      final inv1 = await invSave('زبون المؤسس', 1, 1000000, 0, 'دين', installer: 'فني الاختبار', rate: 1);
      await gap('4أ نقاط المؤسس و«تسديد دين راجع»', 'founderReturn', {'inv': inv1});
      final inv2 = await invSave('زبون المؤسس', 1, 300000, 300000, 'نقد', installer: 'مؤسس مستورد', rate: 1);
      await gap('4ب مؤسس من قاعدة مستوردة', 'founderImported', {'inv': inv2});

      // ── 5: زر الإصلاح ──
      final inv3 = await invSave('زبون الإصلاح', 10, 1000, 0, 'دين');
      await gap('5أ «اعتمد سجل الديون»', 'repairLedger', {'inv': inv3});
      await gap('5ب «اعتمد الفاتورة» على فاتورة مستعادة', 'repairRestored', {'inv': inv3});

      // ══════════════ الدفعة 2 ══════════════
      await gap('6 صندوق ومخزن الطرفية على فاتورة الكاشير', 'posStamp', {'prod': prod});
      await gap('7 معاملة رُفضت بعد كتابة وصفها', 'moneyPostFail');

      // ── 8: «أبقِ ما سُجّل» لوصل انقطع داخل سطر ──
      final p8 = problems.length;
      final k = (await h.addCustomer(dev, 'زبون الوصل المنقطع'))!;
      await h.addTx(dev, k, 10000);
      final crash = (await h.rest(dev, 'receiptCrash', {
        'stopInside': 0,
        'marker': 'وصل-فجوة',
        'lines': [
          {'cust': k, 'amount': 2000, 'discount': 500},
        ],
      })) as Map;
      if (crash['ok'] != true) bad('8: الانقطاع لم يحدث: ${crash['err']}');
      final inc = ((await h.rest(dev, 'receiptsIncomplete')) as List).cast<Map>();
      if (inc.length != 1) {
        bad('8: الوصل المنقطع ${inc.length} والمتوقع واحد');
      } else {
        final kept = (await h.rest(dev, 'receiptKeep', {'id': inc.first['id']})) as Map;
        final lines = (kept['lines'] as List? ?? const []).cast<Map>();
        if (kept['status'] != 'partial') bad('8: حالة الوصل ${kept['status']} والمتوقع ناقص (partial)');
        if (lines.length != 1 || dd(lines.first['amount']) != 2000 || dd(lines.first['discount']) != 0) {
          bad('8: أسطر الوصل بعد «أبقِ» $lines والمتوقع سطر واحد: تسديد 2,000 بلا خصم');
        }
        if (dd(kept['total']) != 2000 || dd(kept['disc']) != 0) bad('8: رأس الوصل ${kept['total']}+${kept['disc']} والمتوقع 2,000+0');
        final ck = await cust(k);
        if ((dd(ck['debt']) - 8000).abs() > 0.005) bad('8: رصيد العميل ${ck['debt']} والمتوقع 8,000 (الخصم لم يُسجَّل)');
      }
      if (problems.length == p8) ok('8 «أبقِ ما سُجّل» بعد انقطاع داخل السطر — التسديد 2,000 وُصف بسطره، والخصم الذي لم يُسجَّل لا يظهر');
      await invariants('8');

      final invF = await invSave('زبون الكلفة', 3, 2000, 6000, 'نقد');
      await gap('9 تثبيت كلفة ما بيع قبل تغيّر كلفة المادة', 'freezeCosts', {'inv': invF});

      await gap('10 قيد فاتورة بلا كلفة ولا مقبوض (فاتورة صفرية قديمة)', 'zeroEntry', {'inv': inv3}); // نسخة صفرية من فاتورة آجلة

      final invE = await invSave('زبون العمولة', 10, 10000, 100000, 'نقد');
      await gap('11 البائع وعمولته على الفاتورة', 'extras', {'inv': invE});

      final gone = (await h.addCustomer(dev, 'عميل سيُحذف صفه'))!;
      await h.addTx(dev, gone, 2500);
      final hidden = (await h.addCustomer(dev, 'عميل سيُخفى'))!;
      await h.addTx(dev, hidden, 700);
      await gap('12 عملاء ليسوا في سجل الديون', 'orphans', {'gone': gone, 'hidden': hidden});

      final lc = (await h.addCustomer(dev, 'زبون نقدي قديم'))!;
      final invL = await invSave('زبون نقدي قديم', 1, 1000, 1000, 'نقد');
      await gap('13 ربط فاتورة نقدية قديمة بعميلها', 'linkOldCash', {'inv': invL, 'cust': lc});
      await gap('14 الفاتورة العادية تُختم بصندوق الحاسبة ومخزنها', 'regularStamp', {'prod': prod});

      problems.addAll(await h.deviceErrors());
      print('\n${problems.isEmpty ? '✅ نجح: الدفعتان 1 و2 من مسارات المال' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
