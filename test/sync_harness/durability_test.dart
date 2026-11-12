// test/sync_harness/durability_test.dart
//
// 🔌 «حُفظ» يعني محفوظاً على القرص — لا في ذاكرة ويندوز.
//
// SQLite في وضع WAL مع synchronous = NORMAL يُنهي الحفظ قبل أن يُثبَّت ملف WAL على
// القرص: انقطاع الكهرباء بعد رسالة «تم الحفظ» قد يُضيّع آخر العمليات. مع FULL يُثبَّت
// كل حفظ على القرص (fsync) قبل أن يعود، فلا تظهر «تم» إلا لما هو على القرص فعلاً.
//
// ما يثبته هذا الاختبار آلياً:
//   1. لا يوجد في كود التطبيق أي سطر يُنزل الإعداد إلى NORMAL أو OFF.
//   2. على اتصال التطبيق الحقيقي: الإعداد FULL منذ الفتح، ويبقى FULL بعد كل عملية مال
//      (إضافة دين، تسديد، فاتورة دين، فاتورة نقد، تحويل دين إلى نقد).
//   3. القتل المفاجئ للتطبيق مباشرة بعد «تم الحفظ»: العملية موجودة بعد إعادة التشغيل.
//   4. تحويل فاتورة دين إلى نقد بعد وصل قبض (التجربة اليدوية آلياً): الصندوق يزيد
//      بثمن الفاتورة بالضبط، ودين العميل صفر، والفاتورة «آجل — مسددة بالكامل».
//
// ما لا يثبته أي اختبار برمجي: فصل الكهرباء الفعلي (ذاكرة القرص نفسه). ذلك بتجربة يدوية.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _full = 2; // PRAGMA synchronous: 0 OFF، 1 NORMAL، 2 FULL، 3 EXTRA

void main() {
  test('🔌 لا سطر في كود التطبيق يُنزل الكتابة على القرص عن FULL', () {
    final weak = RegExp(r'''PRAGMA\s+(?:\w+\.)?synchronous\s*=\s*['"]?(?:NORMAL|OFF|0|1)\b''', caseSensitive: false);
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (weak.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    if (hits.isNotEmpty) print('هنا وقع خطأ — أسطر تُضعف الحفظ:\n${hits.join('\n')}');
    expect(hits, isEmpty);
  });

  test('🔌 الحفظ على القرص فوراً + القتل المفاجئ + تحويل الدين إلى نقد والصندوق', () async {
    final h = Harness(seed: 7);
    final problems = <String>[];
    void bad(String p) {
      problems.add(p);
      print('✗ هنا وقع خطأ: $p');
    }

    double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
    bool near(Object? a, Object? b) => (dd(a) - dd(b)).abs() <= 0.011;

    try {
      await h.start(1);
      const dev = 'D1';
      Future<Map<String, Object?>> op(String group, String n, [Map<String, Object?> a = const {}]) async {
        final r = await h.d(dev).call(group, {'op': n, 'args': a}, const Duration(minutes: 3));
        return r is Map ? r.cast<String, Object?>() : {'ok': true, 'value': r};
      }

      Future<void> checkDisk(String after) async {
        final m = (await h.d(dev).call('durability', const {}) as Map).cast<String, Object?>();
        final ok = m['sync'] == _full && m['journal'] == 'wal';
        print('${ok ? '✓' : '✗'} بعد $after: synchronous=${m['sync']} journal=${m['journal']}');
        if (!ok) bad('بعد $after: الحفظ لا يُثبَّت على القرص (synchronous=${m['sync']}، المطلوب $_full)');
      }

      Future<double> boxTotal() async {
        final m = await op('acct', 'boxBalances');
        if (m['ok'] == false) throw StateError('أرصدة الصناديق: ${m['err']}');
        return m.values.fold<double>(0, (s, v) => s + dd(v));
      }

      // ── 1) منذ الفتح ──
      await checkDisk('فتح القاعدة');

      // ── 2) بعد كل عملية مال ──
      await op('acct', 'setup');
      await h.d(dev).call('addProduct', {'name': 'مادة الكهرباء', 'stock': 1000});
      final prod = ((((await op('scen', 'prodIds'))['rows']) as List).cast<Map>().first['id'] as num).toInt();
      final cust = await h.addCustomer(dev, 'زبون الكهرباء');
      if (cust == null) throw StateError('تعذّر إنشاء العميل');
      await checkDisk('إضافة عميل');
      final debtTx = await h.addTx(dev, cust, 40000);
      await checkDisk('إضافة دين');
      final payTx = await h.addTx(dev, cust, -40000);
      await checkDisk('تسديد دين');

      // ── 3) قتل مفاجئ مباشرة بعد «تم الحفظ» ──
      await h.restart(dev);
      for (final t in [debtTx, payTx]) {
        if (t == null || await h.d(dev).call('txAlive', {'tx': t}) != true) {
          bad('بعد القتل المفاجئ: معاملة حُفظت ثم اختفت ($t)');
        }
      }
      await checkDisk('إعادة التشغيل بعد القتل');

      // ── 4) التجربة اليدوية آلياً: فاتورة دين 100,000 ← وصل 25,000 ← تحويل إلى نقد ──
      const name = 'زبون التحويل';
      final box0 = await boxTotal();
      final items = [
        {'prodId': prod, 'qty': 1, 'price': 100000}
      ];
      final s1 = await op('scen', 'invSave',
          {'name': name, 'items': items, 'discount': 0, 'fee': 0, 'paid': 0, 'ptype': 'دين'});
      if (s1['ok'] != true) throw StateError('فاتورة الدين: ${s1['stage']} ${s1['err']}');
      await checkDisk('فاتورة دين');
      final inv = s1['uuid'] as String;
      final c2 = ((s1['cust'] as Map?)?['uuid']) as String?;
      if (c2 == null) throw StateError('فاتورة الدين بلا عميل');
      final box1 = await boxTotal();
      if (!near(box1 - box0, 0)) bad('فاتورة دين غيّرت الصندوق بـ ${box1 - box0} (المتوقع صفر)');

      final rc = await h.d(dev).call('addTx', {'cust': c2, 'amount': -25000.0, 'marker': 'وصل الكهرباء'});
      if (rc is! String) bad('وصل القبض 25,000 لم يُحفظ');
      await checkDisk('وصل قبض');
      final box2 = await boxTotal();
      if (!near(box2 - box1, 25000)) bad('وصل 25,000 غيّر الصندوق بـ ${box2 - box1}');

      final s2 = await op('scen', 'invSave',
          {'inv': inv, 'name': name, 'items': items, 'discount': 0, 'fee': 0, 'paid': 100000, 'ptype': 'نقد'});
      if (s2['ok'] != true) throw StateError('التحويل إلى نقد: ${s2['stage']} ${s2['err']}');
      await checkDisk('تحويل دين إلى نقد');
      final plan = (s2['plan'] as Map?) ?? const {};
      print('  الخطة: دين الفاتورة ${plan['R']}، رصيد العميل ${plan['B']}، سُدّد سابقاً ${plan['S']}');
      if (!near(plan['S'], 25000)) bad('المقترح «سُدّد سابقاً» ${plan['S']} والمتوقع 25,000');
      if (s2['ptype'] != 'دين') bad('نوع الدفع المحفوظ ${s2['ptype']} والمتوقع دين (آجل — مسددة بالكامل)');
      if (!near(s2['paid'], 75000)) bad('المسدد على الفاتورة ${s2['paid']} والمتوقع 75,000');
      if (!near(s2['prepaid'], 25000)) bad('المسدد بوصولات ${s2['prepaid']} والمتوقع 25,000');
      if (!near(s2['linked'], 25000)) bad('دين الفاتورة في حساب العميل ${s2['linked']} والمتوقع 25,000');
      final custAfter = (s2['cust'] as Map?) ?? const {};
      if (!near(custAfter['txsum'], 0)) bad('رصيد العميل ${custAfter['txsum']} والمتوقع صفر');
      if (!near(custAfter['debt'], 0)) bad('الدين المعروض للعميل ${custAfter['debt']} والمتوقع صفر');
      final box3 = await boxTotal();
      if (!near(box3 - box2, 75000)) bad('التحويل غيّر الصندوق بـ ${box3 - box2} والمتوقع 75,000');
      if (!near(box3 - box0, 100000)) bad('الصندوق كله زاد ${box3 - box0} والمتوقع ثمن الفاتورة 100,000');

      // الحفظ نفسه مرة ثانية لا يغيّر شيئاً (لا يُقبض مرتين)
      final s3 = await op('scen', 'invSave',
          {'inv': inv, 'name': name, 'items': items, 'discount': 0, 'fee': 0, 'paid': 100000, 'ptype': 'نقد'});
      if (s3['ok'] != true) bad('إعادة التحويل رُفضت: ${s3['stage']} ${s3['err']}');
      final box4 = await boxTotal();
      if (!near(box4, box3)) bad('إعادة التحويل غيّرت الصندوق بـ ${box4 - box3}');
      if (!near(((s3['cust'] as Map?) ?? const {})['txsum'], 0)) bad('إعادة التحويل غيّرت رصيد العميل');

      // ── 5) قتل مفاجئ بعد التحويل: كل شيء كما حُفظ ──
      await h.restart(dev);
      final after = await op('scen', 'invInfo', {'inv': inv});
      for (final k in const ['ptype', 'paid', 'prepaid', 'linked']) {
        if ('${after[k]}' != '${s3[k]}') bad('بعد القتل المفاجئ: $k كان ${s3[k]} وصار ${after[k]}');
      }
      final box5 = await boxTotal();
      if (!near(box5, box4)) bad('بعد القتل المفاجئ: الصندوق تغيّر بـ ${box5 - box4}');

      // ── 6) للعميل فاتورتان: الوصل يُحسب على الأقدم أولاً ──
      //   يناير 50,000 دين، ثم فبراير 100,000 دين، ثم وصل 25,000 (يسدّد الأقدم).
      //   تحويل فاتورة فبراير إلى نقد ⇒ لم يُسدَّد منها شيء ⇒ تُقبض كاملة 100,000،
      //   ويبقى على العميل 25,000 من فاتورة يناير. ثم تحويل يناير ⇒ يُقبض 25,000 فقط.
      const name2 = 'زبون فاتورتين';
      final a1 = await op('scen', 'invSave',
          {'name': name2, 'items': [{'prodId': prod, 'qty': 1, 'price': 50000}], 'discount': 0, 'fee': 0, 'paid': 0, 'ptype': 'دين'});
      if (a1['ok'] != true) throw StateError('فاتورة يناير: ${a1['stage']} ${a1['err']}');
      final b1 = await op('scen', 'invSave',
          {'name': name2, 'items': [{'prodId': prod, 'qty': 1, 'price': 100000}], 'discount': 0, 'fee': 0, 'paid': 0, 'ptype': 'دين'});
      if (b1['ok'] != true) throw StateError('فاتورة فبراير: ${b1['stage']} ${b1['err']}');
      final c3 = ((b1['cust'] as Map?)?['uuid']) as String;
      await h.d(dev).call('addTx', {'cust': c3, 'amount': -25000.0, 'marker': 'وصل الأقدم'});
      final boxB0 = await boxTotal();
      final b2 = await op('scen', 'invSave', {
        'inv': b1['uuid'], 'name': name2, 'items': [{'prodId': prod, 'qty': 1, 'price': 100000}],
        'discount': 0, 'fee': 0, 'paid': 100000, 'ptype': 'نقد'});
      if (b2['ok'] != true) throw StateError('تحويل فبراير: ${b2['stage']} ${b2['err']}');
      print('  فبراير: سُدّد سابقاً ${((b2['plan'] as Map?) ?? const {})['S']} (المتوقع 0 — الوصل للأقدم)');
      if (!near(((b2['plan'] as Map?) ?? const {})['S'], 0)) bad('فاتورة فبراير اعتُبر منها مسدداً ${(b2['plan'] as Map?)?['S']} والوصل للأقدم');
      if (!near(await boxTotal() - boxB0, 100000)) bad('تحويل فبراير غيّر الصندوق بـ ${await boxTotal() - boxB0} والمتوقع 100,000');
      if (!near(((b2['cust'] as Map?) ?? const {})['txsum'], 25000)) bad('بعد تحويل فبراير رصيد العميل ${(b2['cust'] as Map?)?['txsum']} والمتوقع 25,000 (باقي يناير)');
      final boxA0 = await boxTotal();
      final a2 = await op('scen', 'invSave', {
        'inv': a1['uuid'], 'name': name2, 'items': [{'prodId': prod, 'qty': 1, 'price': 50000}],
        'discount': 0, 'fee': 0, 'paid': 50000, 'ptype': 'نقد'});
      if (a2['ok'] != true) throw StateError('تحويل يناير: ${a2['stage']} ${a2['err']}');
      if (!near(((a2['plan'] as Map?) ?? const {})['S'], 25000)) bad('فاتورة يناير: سُدّد سابقاً ${(a2['plan'] as Map?)?['S']} والمتوقع 25,000');
      if (!near(await boxTotal() - boxA0, 25000)) bad('تحويل يناير غيّر الصندوق بـ ${await boxTotal() - boxA0} والمتوقع 25,000');
      if (!near(((a2['cust'] as Map?) ?? const {})['txsum'], 0)) bad('بعد التحويلين رصيد العميل ${(a2['cust'] as Map?)?['txsum']} والمتوقع صفر');

      print('\n${problems.isEmpty ? '✅ نجح: كل حفظ على القرص فوراً، ولا شيء ضاع، والصندوق صحيح' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
