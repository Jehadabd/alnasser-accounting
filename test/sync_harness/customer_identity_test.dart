// test/sync_harness/customer_identity_test.dart
//
// 👤 الفاتورة لعميلها بالمعرّف لا بالاسم (قرار المالك 2026-11-11):
//   • تعديل فاتورة بالاسم المحفوظ فيها، أو باسم العميل الحالي بعد تغييره، أو به مع
//     مسافات زائدة ⇒ العميل نفسه، والدين لا يتحرك ولا يُنشأ حساب.
//   • التحقق من الرصيد السالب لا يعدّ ذلك «تغيير عميل» (كان يرفض الحفظ).
//   • اسم عميل آخر ⇒ تنتقل إليه؛ اسم غير موجود ⇒ عميل جديد بصمت (كما اليوم).
//   • تغيير الاسم من جهاز العميل يصل الجهاز الآخر؛ ومن غيره يُرفض.
// على كود التطبيق الحقيقي (InvoiceController، AppProvider، المزامنة) بجهازين.
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('الفاتورة لعميلها بالمعرّف: تغيير الاسم والمسافات ونقل الفاتورة وعميل جديد', () async {
    final h = Harness(seed: 11);
    try {
      await h.start(2);
      final a = (await h.addCustomer('D1', 'سامي الكرخي'))!;
      final b = (await h.addCustomer('D1', 'نزار البصري'))!;
      final prod = (await h.addProduct('D1', 'مسمار هوية', 100000))!;
      expect(await h.settle(), isEmpty);

      Future<Map<String, Object?>> bal(String dev, String c) async =>
          ((await h.d(dev).call('custBalance', {'cust': c}) as Map?) ?? const {}).cast<String, Object?>();

      Future<Map<String, Object?>> save({
        String? inv,
        required String cust,
        String? name,
        required double qty,
        double price = 5000,
        bool storedName = false,
      }) async =>
          (await h.d('D1').call('saveInvoice', {
            'cust': name == null ? cust : null,
            'name': name,
            'phone': null,
            'date': DateTime.now().toIso8601String(),
            'total': qty * price,
            'paid': 0.0,
            'ptype': 'دين',
            'inv': inv,
            'items': [
              {'prod': prod, 'qty': qty, 'large': false, 'price': price}
            ],
            'discount': 0.0,
            'loadingFee': 0.0,
            'incomplete': false,
            'storedName': storedName,
          }) as Map)
              .cast<String, Object?>();

      Future<void> expectDebt(String c, double want, String why) async {
        final r = await bal('D1', c);
        expect((r['debt'] as num).toDouble(), closeTo(want, 0.001), reason: '$why: الدين المخزّن');
        expect((r['sum'] as num).toDouble(), closeTo(want, 0.001), reason: '$why: مجموع المعاملات');
      }

      // فاتورة دين لـ«سامي» 10,000
      var r = await save(cust: a, qty: 2);
      expect(r['ok'], isTrue, reason: '${r['err']}');
      final inv = r['uuid'] as String;
      expect(r['cust'], a);
      await expectDebt(a, 10000, 'بعد الفاتورة');

      // تغيير اسمه على جهازه
      var rn = (await h.d('D1').call('renameCustomer', {'cust': a, 'name': 'سامي الكرخي الجديد'}) as Map);
      expect(rn['ok'], isTrue, reason: '${rn['err']}');

      // (أ) بالاسم المحفوظ في الفاتورة (القديم) ⇒ سامي نفسه
      r = await save(inv: inv, cust: a, qty: 3, storedName: true);
      expect(r['ok'], isTrue, reason: 'الاسم المحفوظ: ${r['err']}');
      expect(r['cust'], a, reason: 'الاسم المحفوظ: عميل آخر');
      await expectDebt(a, 15000, 'الاسم المحفوظ');

      // (ب) باسمه الحالي كما تعرضه الشاشة ⇒ سامي نفسه
      r = await save(inv: inv, cust: a, qty: 4);
      expect(r['ok'], isTrue, reason: 'الاسم الحالي: ${r['err']}');
      expect(r['cust'], a, reason: 'الاسم الحالي: عميل آخر');
      await expectDebt(a, 20000, 'الاسم الحالي');

      // (ج) اسمه الحالي بمسافات زائدة مكتوباً بيد ⇒ سامي نفسه
      r = await save(inv: inv, cust: a, name: '  سامي   الكرخي  الجديد ', qty: 4);
      expect(r['ok'], isTrue, reason: 'مسافات: ${r['err']}');
      expect(r['cust'], a, reason: 'مسافات: عميل آخر');
      await expectDebt(a, 20000, 'مسافات');

      // (د) اسم عميل آخر ⇒ تنتقل إليه بدينها
      r = await save(inv: inv, cust: a, name: 'نزار البصري', qty: 4);
      expect(r['ok'], isTrue, reason: 'نقل: ${r['err']}');
      expect(r['cust'], b, reason: 'نقل: لم تنتقل إلى نزار');
      await expectDebt(a, 0, 'نقل (القديم)');
      await expectDebt(b, 20000, 'نقل (الجديد)');

      // (هـ) وتعود إلى سامي باسمه الحالي
      r = await save(inv: inv, cust: b, name: 'سامي الكرخي الجديد', qty: 4);
      expect(r['ok'], isTrue, reason: 'إعادة: ${r['err']}');
      expect(r['cust'], a);
      await expectDebt(a, 20000, 'إعادة');
      await expectDebt(b, 0, 'إعادة (نزار)');

      // (و) رصيده أقل من متبقي الفاتورة (وصل 15,000) ثم تغيير اسمه مرة ثانية،
      //     وتعديل الفاتورة باسمه الأحدث ⇒ يُقبل (كان يُرفض «رصيد سالب للعميل القديم»)
      final pay = await h.d('D1').call('receipt', {'cust': a, 'amount': 15000.0, 'marker': 'هوية'});
      expect(pay, isNotNull);
      await expectDebt(a, 5000, 'بعد الوصل');
      rn = (await h.d('D1').call('renameCustomer', {'cust': a, 'name': 'سامي ك'}) as Map);
      expect(rn['ok'], isTrue, reason: '${rn['err']}');
      r = await save(inv: inv, cust: a, name: ' سامي  ك ', qty: 4);
      expect(r['ok'], isTrue, reason: 'رصيد أقل من الفاتورة: ${r['err']}');
      expect(r['cust'], a);
      await expectDebt(a, 5000, 'رصيد أقل من الفاتورة');

      // (ز) اسم غير موجود ⇒ عميل جديد بصمت ودينها معه
      r = await save(cust: b, qty: 1, price: 3000);
      expect(r['ok'], isTrue);
      final inv2 = r['uuid'] as String;
      await expectDebt(b, 3000, 'فاتورة نزار الثانية');
      r = await save(inv: inv2, cust: b, name: 'عميل هوية جديد', qty: 1, price: 3000);
      expect(r['ok'], isTrue, reason: 'عميل جديد: ${r['err']}');
      final c = r['cust'] as String;
      expect(c, isNot(anyOf(a, b)), reason: 'لم يُنشأ عميل جديد');
      await expectDebt(b, 0, 'عميل جديد (نزار)');
      await expectDebt(c, 3000, 'عميل جديد');

      // (ح) تغيير اسم «سامي» من الجهاز الآخر ⇒ يُرفض (قاعدة المالك) ولا يتغير شيء
      // (settle يقارن بـ«حقيقة» المحاكي التي لا يسجّلها هذا الاختبار — نفحص بأنفسنا)
      await h.settle();
      rn = (await h.d('D2').call('renameCustomer', {'cust': a, 'name': 'اسم من جهاز آخر'}) as Map);
      expect(rn['ok'], isFalse, reason: 'غيّر جهاز آخر اسم عميل لم ينشئه');

      // بعد المزامنة: الجهاز الآخر يرى الأسماء الحالية والديون نفسها
      await h.settle();
      for (final (cust, name, debt) in [(a, 'سامي ك', 5000.0), (b, 'نزار البصري', 0.0), (c, 'عميل هوية جديد', 3000.0)]) {
        final d2 = await bal('D2', cust);
        expect(d2['name'], name, reason: 'الاسم على D2');
        expect((d2['debt'] as num).toDouble(), closeTo(debt, 0.001), reason: 'دين $name على D2');
      }
      final errs = await h.deviceErrors();
      expect(errs, isEmpty, reason: errs.join('\n'));
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
