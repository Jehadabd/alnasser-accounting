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
//   4. التحويل من دين إلى نقد: يُقبض دين الفاتورة نفسها فقط (من معاملاتها هي)، ودين
//      العميل ينقص بقدره لا أكثر؛ وتحويل يُنزل الرصيد تحت الصفر يُرفض كما كان.
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

      // ── 4) التحويل من دين إلى نقد (قاعدة صاحب المحل) ──
      //   فاتورة 100,000 دين سُدّد عليها 25,000 ⇒ دينها 75,000. تحويلها إلى نقد = سُدّدت
      //   بالكامل: يُقبض الآن 75,000 (دين هذه الفاتورة من معاملاتها هي فقط)، ودين العميل
      //   ينقص 75,000 لا أكثر. معاملات العميل الأخرى (فواتير أخرى، وصولات) لا تُمس.
      const name = 'زبون التحويل';
      final items = [
        {'prodId': prod, 'qty': 1, 'price': 100000}
      ];
      Map<String, Object?> save(String? inv, String ptype, double paid, [String n = name, Object? it]) => {
            if (inv != null) 'inv': inv,
            'name': n,
            'items': it ?? items,
            'discount': 0,
            'fee': 0,
            'paid': paid,
            'ptype': ptype,
          };

      final box0 = await boxTotal();
      final s1 = await op('scen', 'invSave', save(null, 'دين', 25000));
      if (s1['ok'] != true) throw StateError('فاتورة الدين: ${s1['stage']} ${s1['err']}');
      await checkDisk('فاتورة دين');
      final inv = s1['uuid'] as String;
      final box1 = await boxTotal();
      if (!near(box1 - box0, 25000)) bad('فاتورة دين بمسدد 25,000 غيّرت الصندوق بـ ${box1 - box0}');
      if (!near(((s1['cust'] as Map?) ?? const {})['txsum'], 75000)) bad('دين العميل ${(s1['cust'] as Map?)?['txsum']} والمتوقع 75,000');

      final s2 = await op('scen', 'invSave', save(inv, 'نقد', 100000));
      if (s2['ok'] != true) throw StateError('التحويل إلى نقد: ${s2['stage']} ${s2['err']}');
      await checkDisk('تحويل دين إلى نقد');
      if (s2['ptype'] != 'نقد' || !near(s2['paid'], 100000)) bad('بعد التحويل: ${s2['ptype']} مسدد ${s2['paid']} والمتوقع نقد 100,000');
      if (!near(s2['linked'], 0)) bad('بعد التحويل بقي على الفاتورة في حساب العميل ${s2['linked']}');
      final box2 = await boxTotal();
      if (!near(box2 - box1, 75000)) bad('التحويل غيّر الصندوق بـ ${box2 - box1} والمتوقع 75,000');
      if (!near(((s2['cust'] as Map?) ?? const {})['txsum'], 0)) bad('بعد التحويل دين العميل ${(s2['cust'] as Map?)?['txsum']} والمتوقع صفر');
      print('  التحويل: يُقبض 75,000، الصندوق كله +${box2 - box0} (ثمن الفاتورة)، دين العميل صفر');
      // 🧾 سند قبض — تسديد فاتورة بما قُبض الآن
      final ev = (s2['editEvent'] as Map?) ?? const {};
      if (ev['kind'] != 'invoice_settlement' || !near(ev['amount'], 75000)) {
        bad('سند التحويل: النوع ${ev['kind']} والمبلغ ${ev['amount']} — المتوقع «سند قبض — تسديد فاتورة» بـ 75,000');
      } else {
        print('  سند قبض — تسديد فاتورة رقم ${ev['no']} بمبلغ ${ev['amount']}');
      }

      // الحفظ نفسه مرة ثانية لا يغيّر شيئاً
      final s3 = await op('scen', 'invSave', save(inv, 'نقد', 100000));
      if (s3['ok'] != true) bad('إعادة الحفظ رُفضت: ${s3['stage']} ${s3['err']}');
      if (!near(await boxTotal(), box2)) bad('إعادة الحفظ غيّرت الصندوق');

      // ── 5) قتل مفاجئ بعد التحويل: كل شيء كما حُفظ ──
      await h.restart(dev);
      final after = await op('scen', 'invInfo', {'inv': inv});
      for (final k in const ['ptype', 'paid', 'linked']) {
        if ('${after[k]}' != '${s3[k]}') bad('بعد القتل المفاجئ: $k كان ${s3[k]} وصار ${after[k]}');
      }
      if (!near(await boxTotal(), box2)) bad('بعد القتل المفاجئ: الصندوق تغيّر');

      // ── 6) للعميل فاتورتان ووصل: التحويل يطرح دين الفاتورة المحوَّلة فقط ──
      const name2 = 'زبون فاتورتين';
      final itA = [
        {'prodId': prod, 'qty': 1, 'price': 50000}
      ];
      final a1 = await op('scen', 'invSave', save(null, 'دين', 0, name2, itA));
      final b1 = await op('scen', 'invSave', save(null, 'دين', 10000, name2));
      if (a1['ok'] != true || b1['ok'] != true) throw StateError('فاتورتا العميل: ${a1['err']} ${b1['err']}');
      final c3 = ((b1['cust'] as Map?)?['uuid']) as String;
      await h.d(dev).call('addTx', {'cust': c3, 'amount': -25000.0, 'marker': 'وصل عام'});
      // الرصيد: 50,000 + 90,000 − 25,000 = 115,000
      final boxB = await boxTotal();
      final b2 = await op('scen', 'invSave', save(b1['uuid'] as String, 'نقد', 100000, name2));
      if (b2['ok'] != true) throw StateError('تحويل الثانية: ${b2['stage']} ${b2['err']}');
      if (!near(await boxTotal() - boxB, 90000)) bad('تحويل الثانية غيّر الصندوق بـ ${await boxTotal() - boxB} والمتوقع 90,000 (دينها)');
      if (!near(((b2['cust'] as Map?) ?? const {})['txsum'], 25000)) {
        bad('بعد التحويل رصيد العميل ${(b2['cust'] as Map?)?['txsum']} والمتوقع 25,000 (الأولى 50,000 − الوصل)');
      }
      final aInfo = await op('scen', 'invInfo', {'inv': a1['uuid']});
      if (!near(aInfo['linked'], 50000)) bad('الفاتورة الأولى تغيّر دينها إلى ${aInfo['linked']}');

      // ── 7) فاتورة واحدة ووصل منفصل يجعل التحويل يُنزل الرصيد تحت الصفر ⇒ يُرفض كما كان ──
      const name3 = 'زبون وصل منفصل';
      final d1 = await op('scen', 'invSave', save(null, 'دين', 0, name3));
      if (d1['ok'] != true) throw StateError('فاتورة الوصل المنفصل: ${d1['err']}');
      await h.d(dev).call('addTx', {'cust': ((d1['cust'] as Map?)?['uuid']) as String, 'amount': -25000.0, 'marker': 'وصل منفصل'});
      final boxD = await boxTotal();
      final d2 = await op('scen', 'invSave', save(d1['uuid'] as String, 'نقد', 100000, name3));
      if (d2['ok'] == true) bad('تحويل يجعل رصيد العميل −25,000 قُبل (كان يُرفض)');
      if (d2['ok'] != true && d2['stage'] != 'debt') bad('الرفض من غير فحص الرصيد السالب: ${d2['stage']}');
      if (!near(await boxTotal(), boxD)) bad('التحويل المرفوض غيّر الصندوق');
      if (d2['ok'] != true) print('  وصل منفصل ثم تحويل يُنزل الرصيد تحت الصفر: رُفض بلا تغيير (كما كان)');

      print('\n${problems.isEmpty ? '✅ نجح: كل حفظ على القرص فوراً، ولا شيء ضاع، والصندوق صحيح' : '❌ هنا وقع خطأ: ${problems.length} مشكلة'}');
      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
