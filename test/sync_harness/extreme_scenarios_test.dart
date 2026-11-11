// test/sync_harness/extreme_scenarios_test.dart
//
// 🌪️ السيناريوهات الغريبة والقصوى — كل سيناريو مقصود بعينه (لا عشوائي)، على الكود
// الحقيقي وجهازين يتزامنان:
//   1  أسماء عملاء غريبة: فاصلة عليا، علامات SQL، رموز تعبيرية، 300 حرف، مسافات، همزات.
//   2  مبالغ ضخمة: ترليون دينار ونصف، وفاتورة كاشير بخمسين مليار.
//   3  مبالغ أصغر من نصف دينار: يجب أن تُرفض (لا معاملة «صفر» صامتة).
//   4  جهازان بلا إنترنت يسددان الدين نفسه كاملاً في اللحظة نفسها.
//   5  تعديل معاملة على جهاز وتسديد على آخر، كلاهما بلا إنترنت.
//   6  خمس انقطاعات كهرباء متتالية في منتصف الحفظ على الجهاز نفسه.
//   7  استحقاقات غريبة: ارتداد مرتين، تحصيل بعد الارتداد، 60 قسطاً، شيك بالدولار بسعر كسري.
//   8  مطابقة كشف الحساب إلى صفر وإلى رصيد سالب.
//   9  الموردون: مدفوع أكبر من الفاتورة، مرتجع أكثر من المشترى، إلغاء مرتين، إلغاء دفعة
//      مرتين، رصيد افتتاحي يتغير خمس مرات.
//   10 استيراد الملف نفسه مرتين.
//   11 فاتورة كاشير بستين سطراً.
//   12 تسديد لعميل رصيده صفر (يصير له رصيد عندنا).
// ما كان سلوك التطبيق فيه «قراراً» لا «خطأ» يُطبع ملاحظةً لصاحب المحل، ولا يُعدّ فشلاً؛
// وكل شيء بعد ذلك يجب أن يبقى متسقاً: الأرصدة = مجموع المعاملات على الجهازين.
//
// التشغيل: claude_test_extreme.bat [seed]
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:alnaser/utils/iqd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _seedArg = int.fromEnvironment('SEED');

void main() {
  final seed = _seedArg != 0 ? _seedArg : DateTime.now().microsecondsSinceEpoch % 1000000 + 1;
  test('السيناريوهات الغريبة والقصوى seed=$seed', () async {
    final h = Harness(seed: seed);
    final rnd = Random(seed);
    final problems = <String>[];
    final notes = <String>[];
    final passed = <String>[];
    final out = Directory('test_results${Platform.pathSeparator}extreme')..createSync(recursive: true);
    var current = '';
    void bad(String p) {
      problems.add('[$current] $p');
      print('✗ [$current] $p');
    }

    void note(String p) {
      notes.add('[$current] $p');
      print('ℹ️ [$current] $p');
    }

    void near(String what, Object? got, double want, {double tol = 0.005}) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() > tol) bad('$what = $g والمتوقع $want');
    }

    var mk = 0;
    String marker() => 'X${seed}_${++mk}';

    Future<void> scenario(String name, Future<void> Function() body) async {
      current = name;
      final before = problems.length;
      print('▶ $name');
      try {
        await body();
      } catch (e, st) {
        bad('انهار السيناريو: $e\n${st.toString().split('\n').take(4).join('\n')}');
      }
      final errs = await h.settle();
      for (final e in errs.take(5)) {
        bad('بعد المزامنة: $e');
      }
      for (final d in const ['D1', 'D2']) {
        for (final p in (await h.rest(d, 'invariants') as List).cast<String>()) {
          bad('$d: $p');
        }
      }
      if (problems.length == before) passed.add(name);
    }

    /// معاملة يدوية بعلامة: تعيد معرّفها إن حُفظت، وتتبنّاها في الحقيقة بمبلغها المحفوظ.
    Future<String?> tx(String dev, String c, double amount) async {
      final m = marker();
      final r = (await h.rest(dev, 'tx', {'cust': c, 'amount': amount, 'marker': m}) as Map);
      if (r['ok'] != true) return null;
      final rows = (await h.rest(dev, 'byNote', {'marker': m}) as List).cast<List>();
      if (rows.length != 1) bad('المعاملة $m حُفظت ${rows.length} مرة');
      for (final t in rows) {
        h.truth.txs[t[0] as String] = TruthTx(c, dev, (t[2] as num).toDouble(), amount >= 0 ? 'manual_debt' : 'manual_payment');
      }
      return rows.isEmpty ? null : rows.first[0] as String;
    }

    Future<Map<String, Object?>> receipt(String dev, String c, double amount) async {
      final r = (await h.rest(dev, 'creceipt', {
        'lines': [
          {'cust': c, 'amount': amount, 'discount': 0.0}
        ],
        'currency': 'IQD',
        'fx': 1.0,
        'marker': marker(),
      }) as Map)
          .cast<String, Object?>();
      if (r['ok'] == true) {
        for (final l in (r['lines'] as List).cast<Map>()) {
          if (l['pay'] != null) {
            h.truth.txs[l['pay'] as String] = TruthTx(c, dev, -(l['amount'] as num).toDouble(), 'manual_payment');
          }
        }
      }
      return r;
    }

    Future<void> adopt(String dev, Map r) async {
      for (final t in ((r['txs'] as List?) ?? const []).cast<List>()) {
        h.truth.txs[t[0] as String] = TruthTx(t[1] as String, dev, (t[2] as num).toDouble(), '${t[3]}');
      }
    }

    try {
      await h.start(2);
      final prods = <String>[];
      for (final n in const ['عجيب أ', 'عجيب ب', 'عجيب ج']) {
        final p = await h.addProduct('D1', n, 1000000);
        if (p != null) prods.add(p);
      }
      Future<String> cust(String dev, String name) async {
        final c = await h.addCustomer(dev, name);
        if (c == null) throw StateError('لم يُنشأ العميل «$name»');
        return c;
      }

      await h.settle();

      // ── 1 ──
      await scenario('1 أسماء غريبة', () async {
        final names = [
          "O'Brien",
          '%_% \\ مئوية',
          '"; DROP TABLE customers; --',
          'زبون 🧾💵',
          'ا' * 300,
          '  مسافات حول الاسم  ',
          'أحمد الغريب',
          'احمد الغريب',
          'إحمد الغريب',
          'محمّد المشدّد',
          'Ahmed أحمد مختلط',
          '١٢٣ أرقام هندية',
        ];
        final made = <String, String>{};
        for (final n in names) {
          final c = await h.addCustomer('D1', n);
          if (c == null) {
            note('«${n.length > 40 ? '${n.substring(0, 40)}…' : n}» لم يُنشأ (رُفض أو اعتُبر مكرراً)');
            continue;
          }
          made[n] = c;
        }
        if (made.containsKey('أحمد الغريب') && made.containsKey('احمد الغريب') && made['أحمد الغريب'] != made['احمد الغريب']) {
          note('«أحمد الغريب» و«احمد الغريب» (بلا همزة) عميلان منفصلان');
        }
        for (final c in made.values.toSet()) {
          await tx('D1', c, 1000);
          final r = await receipt('D1', c, 250);
          if (r['ok'] != true) bad('وصل 250 رُفض لعميل اسمه غريب: ${r['err']}');
          final p = (await h.rest('D1', 'pos', {
            'cust': c,
            'items': [
              {'prod': prods[0], 'qty': 2.0, 'price': 1500.0}
            ],
            'ptype': 'دين',
            'discount': 0.0,
            'paid': 0.0,
          }) as Map)
              .cast<String, Object?>();
          if (p['ok'] != true) {
            bad('بيع كاشير رُفض لعميل اسمه غريب: ${p['err']}');
          } else {
            h.truth.invoices[p['uuid'] as String] = TruthInvoice(c, 'D1', 3000, 0, 'دين', 'محفوظة')..items = {prods[0]: 2};
          }
        }
      });

      // ── 2 ──
      await scenario('2 مبالغ ضخمة', () async {
        final c = await cust('D2', 'عميل الترليون');
        final u = await tx('D2', c, 999999999999.5);
        if (u == null) bad('دين ترليون رُفض');
        near('دين ترليون ونصف بعد التقريب', h.truth.txs[u]?.amount, 1000000000000);
        final p = await tx('D2', c, -999999999999.5);
        near('تسديد ترليون ونصف بعد التقريب', h.truth.txs[p]?.amount, -999999999999);
        final r = (await h.rest('D2', 'pos', {
          'cust': c,
          'items': [
            {'prod': prods[1], 'qty': 1000.0, 'price': 50000000.0}
          ],
          'ptype': 'دين',
          'discount': 0.5,
          'paid': 0.0,
        }) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          bad('فاتورة كاشير بخمسين مليار رُفضت: ${r['err']}');
        } else {
          near('إجمالي الخمسين مليار (الخصم 0.5 ⇒ صفر)', r['total'], 50000000000);
          h.truth.invoices[r['uuid'] as String] = TruthInvoice(c, 'D2', 50000000000, 0, 'دين', 'محفوظة')..items = {prods[1]: 1000};
        }
      });

      // ── 3 ──
      await scenario('3 أقل من نصف دينار', () async {
        final c = await cust('D1', 'عميل الفلوس');
        await tx('D1', c, 5000);
        final half = await tx('D1', c, 0.5);
        near('دين نصف دينار ⇒ دينار', h.truth.txs[half]?.amount, 1);
        if (await tx('D1', c, 0.49) != null) bad('حُفظ دين 0.49 (يجب أن يُرفض)');
        if (await tx('D1', c, -0.5) != null) bad('حُفظ تسديد نصف دينار (يصير صفراً — يجب أن يُرفض)');
        final r = await receipt('D1', c, 0.4);
        if (r['ok'] == true) bad('قُبل وصل قبض بـ 0.4');
        final d = (await h.rest('D1', 'dueCreate', {
          'kind': 'cheque_in', 'cust': c, 'amount': 0.4, 'currency': 'IQD', 'fx': 1.0, 'n': 1, 'affect': true,
        }) as Map);
        if (d['ok'] == true) bad('قُبل شيك بـ 0.4 دينار');
        final inst = (await h.rest('D1', 'dueCreate', {
          'kind': 'installment', 'cust': c, 'amount': 11.0, 'currency': 'IQD', 'fx': 1.0, 'n': 12, 'affect': false,
        }) as Map);
        if (inst['ok'] == true) bad('قُبل 11 ديناراً على 12 قسطاً (أقساط بصفر)');
      });

      // ── 4 ──
      await scenario('4 تسديد مزدوج بلا إنترنت', () async {
        final c = await cust('D1', 'عميل التسديد المزدوج');
        await tx('D1', c, 70000);
        await h.settle();
        await h.setOnline('D1', false);
        await h.setOnline('D2', false);
        final a = await receipt('D1', c, 70000);
        final b = await receipt('D2', c, 70000);
        if (a['ok'] != true || b['ok'] != true) bad('أحد التسديدين رُفض: ${a['err'] ?? b['err']}');
        await h.setOnline('D1', true);
        await h.setOnline('D2', true);
        await h.settle();
        note('بعد المزامنة رصيد العميل ${h.truth.balance(c)} (التسديدان محفوظان، صار له رصيد عندنا) — تنبيه '
            'التسديد المزدوج مسؤولية «فحص شامل لجميع العملاء» والكشف');
      });

      // ── 5 ──
      await scenario('5 تعديل وتسديد على جهازين بلا إنترنت', () async {
        final c = await cust('D1', 'عميل التعديل المتزامن');
        final u = await tx('D1', c, 10000);
        await h.settle();
        await h.setOnline('D1', false);
        await h.setOnline('D2', false);
        await h.d('D1').call('editTx', {'tx': u, 'amount': 20000.5});
        h.truth.txs[u]!.amount = Iqd.up(20000.5);
        await tx('D2', c, -5000);
        await h.setOnline('D2', true);
        await h.setOnline('D1', true);
        await h.settle();
        if ((h.truth.balance(c) - 15001).abs() > 0.005) bad('الرصيد المتوقع 15001 والحقيقة ${h.truth.balance(c)}');
      });

      // ── 6 ──
      await scenario('6 خمس انقطاعات متتالية', () async {
        final c = await cust('D1', 'عميل الانقطاعات');
        await tx('D1', c, 100000);
        for (var k = 0; k < 5; k++) {
          final m = marker();
          await h.rest('D1', 'spawn', {
            'op': 'tx',
            'args': {'cust': c, 'amount': -1000.0, 'marker': m},
            'delayMs': rnd.nextInt(8),
          });
          await h.restart('D1');
          final rows = (await h.rest('D1', 'byNote', {'marker': m}) as List).cast<List>();
          if (rows.length > 1) bad('الانقطاع ${k + 1}: المعاملة حُفظت ${rows.length} مرات');
          for (final t in rows) {
            h.truth.txs[t[0] as String] = TruthTx(c, 'D1', (t[2] as num).toDouble(), 'manual_payment');
          }
          note('الانقطاع ${k + 1}: ${rows.isEmpty ? 'لم تُحفظ' : 'حُفظت'}');
        }
      });

      // ── 7 ──
      await scenario('7 استحقاقات غريبة', () async {
        final c = await cust('D2', 'عميل الشيكات');
        await tx('D2', c, 500000);
        final ch = (await h.rest('D2', 'dueCreate', {
          'kind': 'cheque_in', 'cust': c, 'amount': 1250.5, 'currency': 'IQD', 'fx': 1.0, 'n': 1, 'affect': true,
        }) as Map)
            .cast<String, Object?>();
        if (ch['ok'] != true) throw StateError('شيك 1250.5: ${ch['err']}');
        await adopt('D2', ch);
        final id = ((ch['ids'] as List).first as num).toInt();
        final b1 = (await h.rest('D2', 'dueBounce', {'id': id}) as Map).cast<String, Object?>();
        if (b1['ok'] != true) bad('ارتداد الشيك رُفض: ${b1['err']}');
        await adopt('D2', b1);
        final net = [...(ch['txs'] as List), ...((b1['txs'] as List?) ?? const [])]
            .cast<List>()
            .fold(0.0, (a, t) => a + (t[2] as num).toDouble());
        near('صافي شيك 1250.5 بعد ارتداده', net, 0);
        if ((await h.rest('D2', 'dueBounce', {'id': id}) as Map)['ok'] == true) bad('ارتدّ الشيك نفسه مرتين');
        if ((await h.rest('D2', 'dueSettle', {'id': id, 'amount': 100.0}) as Map)['ok'] == true) bad('حُصّل من شيك مرتد');
        final inst = (await h.rest('D2', 'dueCreate', {
          'kind': 'installment', 'cust': c, 'amount': 100000.0, 'currency': 'IQD', 'fx': 1.0, 'n': 60, 'affect': false,
        }) as Map)
            .cast<String, Object?>();
        if (inst['ok'] != true) {
          bad('60 قسطاً رُفضت: ${inst['err']}');
        } else {
          final parts = (inst['dues'] as List).cast<Map>();
          near('مجموع الستين قسطاً', parts.fold(0.0, (a, p) => a + (p['amount'] as num).toDouble()), 100000);
          if (parts.any((p) => !Iqd.isWhole(p['amount'] as num))) bad('قسط بكسور من الستين');
          for (final p in parts.take(3)) {
            final s = (await h.rest('D2', 'dueSettle', {'id': p['id'], 'amount': p['amount']}) as Map);
            if (s['ok'] != true) bad('تحصيل قسط رُفض: ${s['err']}');
            await adopt('D2', s);
          }
        }
        final usd = (await h.rest('D2', 'dueCreate', {
          'kind': 'cheque_in', 'cust': c, 'amount': 33.33, 'currency': 'USD', 'fx': 1310.5, 'n': 1, 'affect': true,
        }) as Map)
            .cast<String, Object?>();
        if (usd['ok'] != true) {
          bad('شيك بالدولار رُفض: ${usd['err']}');
        } else {
          await adopt('D2', usd);
          final down = ((usd['txs'] as List).cast<List>()).fold(0.0, (a, t) => a + (t[2] as num).toDouble());
          near('شيك 33.33\$ × 1310.5 ينزل', down, -Iqd.down(33.33 * 1310.5));
          final bb = (await h.rest('D2', 'dueBounce', {'id': ((usd['ids'] as List).first as num).toInt()}) as Map);
          await adopt('D2', bb);
          final back = ((bb['txs'] as List?) ?? const []).cast<List>().fold(0.0, (a, t) => a + (t[2] as num).toDouble());
          near('ارتداد الشيك بالدولار يعيد ما نزل بالضبط', back + down, 0);
        }
      });

      // ── 8 ──
      await scenario('8 مطابقة إلى صفر وإلى سالب', () async {
        final c = await cust('D1', 'عميل المطابقة');
        await tx('D1', c, 987654321);
        final z = (await h.rest('D1', 'reconcile', {'cust': c, 'agreed': 0.0}) as Map);
        await adopt('D1', z);
        near('الرصيد بعد المطابقة إلى صفر', h.truth.balance(c), 0);
        final n = (await h.rest('D1', 'reconcile', {'cust': c, 'agreed': -5000.5}) as Map);
        await adopt('D1', n);
        near('الرصيد بعد المطابقة إلى −5000.5', h.truth.balance(c), -5000);
      });

      // ── 9 ──
      await scenario('9 موردون في أقصى الحالات', () async {
        final s = (await h.rest('D1', 'supAdd', {'name': 'مورد الغرائب', 'currency': 'IQD'}) as Map);
        final sid = (s['id'] as num).toInt();
        final over = (await h.rest('D1', 'supBuy', {
          'sup': sid, 'number': 'XP-${marker()}', 'currency': 'IQD', 'status': 'confirmed', 'paid': 5000.0,
          'items': [
            {'prod': prods[2], 'qty': 1.0, 'price': 1000.0}
          ],
        }) as Map)
            .cast<String, Object?>();
        note(over['ok'] == true
            ? 'فاتورة شراء 1000 بمدفوع 5000 قُبلت (المدفوع ${over['paid']}) — الزائد يصير رصيداً لنا عند المورد'
            : 'فاتورة شراء بمدفوع أكبر من إجماليها رُفضت: ${over['err']}');
        if (over['ok'] == true) h.truth.products[prods[2]]!.movements += 1;
        final inv = (await h.rest('D1', 'supBuy', {
          'sup': sid, 'number': 'XP-${marker()}', 'currency': 'IQD', 'status': 'confirmed', 'paid': 0.0,
          'items': [
            {'prod': prods[2], 'qty': 5.0, 'price': 1000.0}
          ],
        }) as Map)
            .cast<String, Object?>();
        if (inv['ok'] != true) throw StateError('فاتورة شراء: ${inv['err']}');
        h.truth.products[prods[2]]!.movements += 5;
        final iid = (inv['id'] as num).toInt();
        final tooMuch = (await h.rest('D1', 'supRet', {
          'sup': sid, 'inv': iid, 'currency': 'IQD', 'mode': 'debt', 'cash': 0.0,
          'items': [
            {'prod': prods[2], 'qty': 6.0, 'price': 1000.0}
          ],
        }) as Map);
        if (tooMuch['ok'] == true) {
          bad('قُبل مرتجع 6 من فاتورة اشتُري فيها 5');
          h.truth.products[prods[2]]!.movements -= 6;
        }
        final c1 = (await h.rest('D1', 'supCancel', {'id': iid}) as Map);
        if (c1['ok'] != true) bad('إلغاء فاتورة شراء سليمة رُفض: ${c1['err']}');
        if (c1['ok'] == true) h.truth.products[prods[2]]!.movements -= 5;
        if ((await h.rest('D1', 'supCancel', {'id': iid}) as Map)['ok'] == true) bad('أُلغيت فاتورة الشراء نفسها مرتين');
        final pay = (await h.rest('D1', 'supPay', {'sup': sid, 'amount': 777.5, 'currency': 'IQD', 'marker': marker()}) as Map);
        if (pay['ok'] != true || pay['id'] == null) bad('دفعة مورد رُفضت: ${pay['err']}');
        if (pay['id'] != null) {
          near('دفعة 777.5 بعد التقريب (لصالح المحل)', pay['amount'], 778);
          await h.rest('D1', 'supVoidPay', {'id': pay['id']});
          if ((await h.rest('D1', 'supVoidPay', {'id': pay['id']}) as Map)['ok'] == true) bad('أُلغيت الدفعة نفسها مرتين');
        }
        for (final v in const [100000.0, 25000.5, -3000.0, 0.0, 777.25]) {
          await h.rest('D1', 'supOpen', {'sup': sid, 'amount': v, 'currency': 'IQD'});
        }
        final st = (await h.rest('D1', 'supState') as List).cast<Map>().firstWhere((x) => x['id'] == sid);
        final overTotal = over['ok'] == true ? ((over['total'] as num) - (over['paid'] as num)).toDouble() : 0.0;
        near('رصيد المورد بعد خمسة أرصدة افتتاحية (الأخير 777.25 ⇒ 777)', st['iqd'], 777 + overTotal);
      });

      // ── 10 ──
      await scenario('10 استيراد الملف نفسه مرتين', () async {
        final rows = [
          ['الاسم', 'الرصيد'],
          ['مستورد مرتين أ', '15000'],
          ['مستورد مرتين ب', '2500.5'],
        ];
        for (var k = 0; k < 2; k++) {
          final r = (await h.rest('D2', 'import', {'kind': 'customers', 'rows': rows, 'source': 'same-file'},
              const Duration(minutes: 5)) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            note('الاستيراد ${k + 1} رُفض: ${r['err']}');
            continue;
          }
          for (final x in (r['custs'] as List).whereType<List>()) {
            h.truth.customers[x[0] as String] = TruthCustomer(x[1] as String, 'D2');
          }
          await adopt('D2', r);
          if (k == 1 && ((r['txs'] as List).isNotEmpty || (r['custs'] as List).whereType<List>().isNotEmpty)) {
            bad('الاستيراد الثاني للملف نفسه أضاف ${(r['custs'] as List).whereType<List>().length} عميلاً و${(r['txs'] as List).length} معاملة');
          }
        }
      });

      // ── 11 ──
      await scenario('11 فاتورة كاشير بستين سطراً', () async {
        final c = await cust('D1', 'عميل الفاتورة الطويلة');
        final items = [
          for (var k = 0; k < 60; k++) {'prod': prods[k % prods.length], 'qty': (1 + k % 7).toDouble(), 'price': 250.0 * (1 + k % 9)}
        ];
        final total = items.fold(0.0, (a, x) => a + (x['qty'] as double) * (x['price'] as double));
        final r = (await h.rest('D1', 'pos', {'cust': c, 'items': items, 'ptype': 'دين', 'discount': 0.0, 'paid': 0.0}) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          bad('فاتورة الستين سطراً رُفضت: ${r['err']}');
          return;
        }
        near('إجمالي الستين سطراً', r['total'], total);
        final ti = TruthInvoice(c, 'D1', total, 0, 'دين', 'محفوظة');
        for (final x in items) {
          ti.items[x['prod'] as String] = (ti.items[x['prod'] as String] ?? 0) + (x['qty'] as double);
        }
        h.truth.invoices[r['uuid'] as String] = ti;
      });

      // ── 12 ──
      await scenario('12 تسديد لعميل رصيده صفر', () async {
        final c = await cust('D2', 'عميل بلا دين');
        final r = await receipt('D2', c, 5000);
        note(r['ok'] == true
            ? 'وصل قبض 5000 لعميل رصيده صفر قُبل — صار له رصيد عندنا ${h.truth.balance(c)}'
            : 'وصل قبض لعميل رصيده صفر رُفض: ${r['err']}');
        final t = await tx('D2', c, -3000);
        note(t != null ? 'تسديد يدوي لعميل بلا دين قُبل' : 'تسديد يدوي لعميل بلا دين رُفض');
      });

      current = 'الفحص العميق الأخير';
      for (final d in const ['D1', 'D2']) {
        final r = (await h.d(d).call('deepCheck', const {}, const Duration(minutes: 5)) as Map).cast<String, Object?>();
        for (final e in (r['errors'] as List).take(5)) {
          bad('$d: $e');
        }
      }
      for (final e in (await h.deviceErrors()).take(5)) {
        bad('خطأ غير ممسوك: $e');
      }
    } finally {
      final s = StringBuffer()
        ..writeln('السيناريوهات الغريبة والقصوى — seed=$seed — ${problems.isEmpty ? 'PASS' : 'FAIL'}')
        ..writeln('نجح: ${passed.length} سيناريو — ${passed.join('، ')}')
        ..writeln('مشاكل: ${problems.length}')
        ..writeAll(problems.map((p) => '  ✗ $p\n'))
        ..writeln('ملاحظات (سلوك يقرّره صاحب المحل، ليست أخطاء):')
        ..writeAll(notes.map((p) => '  ℹ️ $p\n'));
      File('${out.path}${Platform.pathSeparator}summary.txt').writeAsStringSync(s.toString());
      print(s);
      await h.dispose();
    }
    expect(problems, isEmpty);
  }, timeout: const Timeout(Duration(hours: 2)));
}
