// test/sync_harness/full_accounting_scenarios_test.dart
//
// 🧪 اختبار شامل للأمان الحسابي على كود التطبيق الحقيقي وثلاثة أجهزة متزامنة:
//   • عميل بعشر فواتير: فاتورتان نقد وثمانٍ دين.
//   • كل تحويلات الدفع: نقد ← دين ← نقد، دين جزئي، تغيير المسدد، تغيير البنود،
//     نقل الفاتورة لعميل آخر ثم إرجاعها، حذف فاتورة، رفض ما يجب رفضه.
//   • معاملات يدوية (تسديد/دين، تعديل، قلب النوع) من أجهزة مختلفة وبانقطاع.
//   • وصولات القبض والخصم، مرتجعات المبيعات (حساب/نقد/مختلط/إلغاء/تجاوز الكمية)،
//     مرتجعات المشتريات (دين/نقد/مختلط/إلغاء/تجاوز المتوفر).
//   • تثبيت الإدخالات: رفض الفاتورة والمعاملة داخل الفترة المثبّتة.
//   • نسخة احتياطية واستعادة، وجهاز جديد ينضم متأخراً.
// بعد كل مرحلة: كل الأجهزة = «الحقيقة» (أرصدة ومخزون)، وعلى كل جهاز:
//   الترحيل متوازن قيداً قيداً، الميزان متوازن، ذمم كل عميل في الدفتر = رصيده،
//   ذمم الموردين = أرصدتهم، الكمية = دفتر المخزون، والترحيل الثاني لا يغيّر شيئاً.
//
//   flutter test test/sync_harness/full_accounting_scenarios_test.dart
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('سيناريوهات حسابية شاملة: 10 فواتير + تحويلات + مرتجعات + مزامنة + تثبيت', () async {
    final h = Harness(seed: 2026);
    final problems = <String>[];
    var phase = '';

    void expectNear(String what, double got, double want) {
      if ((got - want).abs() > 0.01) problems.add('[$phase] $what = $got والمتوقع $want');
    }

    Future<void> checkpoint(String name) async {
      phase = name;
      final errs = await h.settle();
      for (final e in errs) {
        problems.add('[$name] مزامنة: $e');
      }
      for (final dev in h.devices.keys.toList()) {
        final r = (await h.d(dev).call('ledgerCheck', const {}, const Duration(minutes: 5)) as Map)
            .cast<String, Object?>();
        for (final p in (r['problems'] as List)) {
          problems.add('[$name] دفتر $dev: $p');
        }
      }
      final de = await h.deviceErrors();
      for (final e in de) {
        problems.add('[$name] خطأ غير ممسوك: $e');
      }
      print('✓ $name — ${problems.length} مشكلة حتى الآن');
    }

    /// فاتورة: يُرجع المعرّف، ويسجّل رفضاً غير متوقع كمشكلة.
    Future<String?> inv(String dev, String cust, double total, double paid, String ptype,
        {String? edit, List<Map<String, Object?>> items = const [], bool expectOk = true, String label = ''}) async {
      final u = await h.saveInvoice(dev, cust, total, paid, ptype, inv: edit, items: items);
      if (u == null && expectOk) problems.add('[$phase] $label: رُفضت والمتوقع قبولها');
      if (u != null && !expectOk) problems.add('[$phase] $label: قُبلت والمتوقع رفضها');
      return u;
    }

    List<Map<String, Object?>> it(String prod, double qty, double price, {bool large = false}) =>
        [
          {'prod': prod, 'qty': qty, 'price': price, 'large': large}
        ];

    try {
      await h.start(3);
      phase = 'التهيئة';
      final x = (await h.addCustomer('D1', 'زبون العشر فواتير'))!;
      final y = (await h.addCustomer('D2', 'زبون ثانٍ'))!;
      final a = (await h.addProduct('D1', 'مادة أ', 500))!;
      final b = (await h.addProduct('D1', 'مادة ب كرتون', 240, carton: 12))!;
      final c = (await h.addProduct('D1', 'مادة ج', 100))!;
      await checkpoint('التهيئة');

      // ══════════ 1) عشر فواتير: 2 نقد + 8 دين ══════════
      phase = 'عشر فواتير';
      final i1 = (await inv('D1', x, 2000, 2000, 'نقد', items: it(a, 2, 1000), label: 'ف1 نقد'))!;
      final i2 = (await inv('D1', x, 7500, 7500, 'نقد', items: it(c, 3, 2500), label: 'ف2 نقد'))!;
      final i3 = (await inv('D1', x, 5000, 0, 'دين', items: it(a, 5, 1000), label: 'ف3'))!;
      final i4 = (await inv('D1', x, 10000, 3000, 'دين', items: it(b, 1, 10000, large: true), label: 'ف4'))!;
      final i5 = (await inv('D1', x, 10000, 0, 'دين', items: it(c, 4, 2500), label: 'ف5'))!;
      final i6 = (await inv('D1', x, 3500, 500, 'دين',
          items: [...it(a, 1, 1000), ...it(c, 1, 2500)], label: 'ف6'))!;
      final i7 = (await inv('D1', x, 20000, 0, 'دين', items: it(b, 2, 10000, large: true), label: 'ف7'))!;
      final i8 = (await inv('D1', x, 10000, 2500, 'دين', items: it(a, 10, 1000), label: 'ف8'))!;
      final i9 = (await inv('D1', x, 1500, 0, 'دين', label: 'ف9 بلا مواد'))!;
      final i10 = (await inv('D1', x, 5000, 1000, 'دين', items: it(c, 2, 2500), label: 'ف10'))!;
      await checkpoint('عشر فواتير');
      expectNear('رصيد العميل بعد العشر', h.truth.balance(x), 58000);
      expectNear('مخزون أ', h.truth.stock(a), 482);
      expectNear('مخزون ب', h.truth.stock(b), 204);
      expectNear('مخزون ج', h.truth.stock(c), 90);

      // ══════════ 2) الفواتير النقدية: نقد ← دين ← نقد ← دين جزئي ══════════
      phase = 'تحويل النقد';
      await inv('D1', x, 2000, 0, 'دين', edit: i1, items: it(a, 2, 1000), label: 'ف1 نقد←دين');
      await checkpoint('ف1 نقد←دين');
      await inv('D1', x, 2000, 2000, 'نقد', edit: i1, items: it(a, 2, 1000), label: 'ف1 دين←نقد');
      await checkpoint('ف1 دين←نقد');
      await inv('D1', x, 3000, 500, 'دين', edit: i1, items: it(a, 3, 1000), label: 'ف1 نقد←دين جزئي بزيادة بند');
      await inv('D1', x, 5000, 5000, 'نقد', edit: i2, items: it(c, 2, 2500), label: 'ف2 نقد بإنقاص بند');
      await inv('D1', x, 5000, 0, 'دين', edit: i2, items: it(c, 2, 2500), label: 'ف2 نقد←دين');
      await inv('D1', x, 7500, 7500, 'نقد', edit: i2, items: it(c, 3, 2500), label: 'ف2 دين←نقد بزيادة بند');
      await inv('D1', x, 7500, 5000, 'نقد', edit: i2, items: it(c, 3, 2500), expectOk: false, label: 'نقد بمسدد ناقص');
      await checkpoint('تحويلات الفواتير النقدية');

      // ══════════ 3) فواتير الدين: كل التعديلات ══════════
      phase = 'تعديل الدين';
      await inv('D1', x, 7000, 0, 'دين', edit: i3, items: it(a, 7, 1000), label: 'ف3 زيادة بنود');
      await inv('D1', x, 7000, 3000, 'دين', edit: i3, items: it(a, 7, 1000), label: 'ف3 زيادة المسدد');
      await inv('D1', x, 7000, 1000, 'دين', edit: i3, items: it(a, 7, 1000), label: 'ف3 إنقاص المسدد');
      await inv('D1', x, 10000, 10000, 'نقد', edit: i4, items: it(b, 1, 10000, large: true), label: 'ف4 دين←نقد');
      await inv('D1', y, 10000, 0, 'دين', edit: i5, items: it(c, 4, 2500), label: 'ف5 نقل لعميل آخر');
      await checkpoint('نقل فاتورة لعميل آخر');
      await inv('D1', x, 10000, 0, 'دين', edit: i5, items: it(c, 4, 2500), label: 'ف5 إرجاع للعميل الأول');
      await inv('D1', x, 1000, 500, 'دين', edit: i6, items: it(a, 1, 1000), label: 'ف6 حذف بند');
      await inv('D1', x, 400, 500, 'دين', edit: i6, items: it(a, 1, 400), expectOk: false, label: 'مجموع تحت المسدد');
      await inv('D1', x, 10000, 0, 'دين', edit: i7, items: it(b, 1, 10000, large: true), label: 'ف7 إرجاع كرتون');
      await inv('D1', x, 10000, 10000, 'نقد', edit: i8, items: it(a, 10, 1000), label: 'ف8 دين←نقد');
      await inv('D1', x, 10000, 0, 'دين', edit: i8, items: it(a, 10, 1000), label: 'ف8 نقد←دين');
      final del = (await h.d('D1').call('deleteInvoice', {'inv': i9}) as Map).cast<String, Object?>();
      if (del['ok'] == true) {
        h.truth.invoices[i9]!.status = 'محذوفة';
      } else {
        problems.add('[$phase] حذف ف9 رُفض: ${del['err']}');
      }
      await checkpoint('تعديلات فواتير الدين والحذف');

      // ══════════ 4) معاملات يدوية من أجهزة مختلفة وبانقطاع ══════════
      phase = 'معاملات يدوية';
      final t1 = await h.addTx('D2', x, -4000);
      final t2 = await h.addTx('D3', x, 1500);
      await checkpoint('معاملات يدوية');
      await h.editTx('D2', t1!, -3500);
      await h.convertTx('D3', t2!);
      await checkpoint('تعديل وقلب معاملة');

      phase = 'انقطاع';
      await h.setOnline('D2', false);
      await h.setOnline('D3', false);
      await h.addTx('D2', x, -2000); // تسديد بلا إنترنت
      await h.addTx('D3', x, -1000); // تسديد متزامن على جهاز آخر بلا إنترنت
      await h.addTx('D3', y, 750);
      await inv('D1', x, 5000, 2000, 'دين', edit: i10, items: it(c, 2, 2500), label: 'ف10 تغيير المسدد أثناء انقطاع غيره');
      final i11 = await inv('D1', y, 3000, 0, 'دين', items: it(a, 3, 1000), label: 'فاتورة للعميل الثاني');
      await checkpoint('عودة الاتصال بعد الانقطاع');

      // ══════════ 5) وصولات القبض والخصم ══════════
      phase = 'وصولات';
      final r1 = await h.d('D2').call('receipt', {'cust': x, 'amount': 1500.0, 'marker': 'R1'}) as String?;
      if (r1 != null) h.truth.txs[r1] = TruthTx(x, 'D2', -1500, 'manual_payment');
      final r2 = await h.d('D1').call('receipt', {'cust': x, 'amount': 500.0, 'kind': 'discount', 'marker': 'R2'}) as String?;
      if (r2 != null) h.truth.txs[r2] = TruthTx(x, 'D1', -500, 'manual_payment');
      await checkpoint('وصولات القبض والخصم');

      // ══════════ 6) مرتجعات المبيعات ══════════
      phase = 'مرتجعات المبيعات';
      Future<int?> salesReturn(String inv, String cust, String prod, double qty, double price, String mode,
          {double cash = 0, bool expectOk = true, String label = ''}) async {
        final r = (await h.d('D1').call('salesReturn', {
          'inv': inv,
          'cust': cust,
          'items': [
            {'prod': prod, 'qty': qty, 'price': price}
          ],
          'mode': mode,
          'cash': cash,
        }) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          if (expectOk) problems.add('[$phase] $label: رُفض (${r['err']})');
          return null;
        }
        if (!expectOk) problems.add('[$phase] $label: قُبل والمتوقع رفضه');
        for (final t in (r['txs'] as List).cast<List>()) {
          h.truth.txs[t[0] as String] = TruthTx(cust, 'D1', (t[1] as num).toDouble(), 'manual_payment');
        }
        h.truth.products[prod]!.movements += qty;
        return r['id'] as int;
      }

      final sr1 = await salesReturn(i5, x, c, 1, 2500, 'credit', label: 'مرتجع على الحساب');
      await salesReturn(i5, x, c, 10, 2500, 'credit', expectOk: false, label: 'إرجاع أكثر من المباع');
      await salesReturn(i3, x, a, 2, 1000, 'mixed', cash: 500, label: 'مرتجع مختلط');
      await salesReturn(i2, x, c, 1, 2500, 'cash', label: 'مرتجع نقدي من فاتورة نقد');
      await salesReturn(i3, x, a, 1, 1000, 'mixed', cash: 1000, expectOk: false, label: 'مختلط نقده = الإجمالي');
      await checkpoint('مرتجعات المبيعات');
      if (sr1 != null) {
        final v = (await h.d('D1').call('voidSalesReturn', {'id': sr1}) as Map).cast<String, Object?>();
        if (v['ok'] != true) {
          problems.add('[$phase] إلغاء المرتجع رُفض: ${v['err']}');
        } else {
          for (final t in (v['txs'] as List).cast<List>()) {
            h.truth.txs[t[0] as String] = TruthTx(x, 'D1', (t[1] as num).toDouble(), 'manual_debt');
          }
          h.truth.products[c]!.movements -= 1;
        }
        final v2 = (await h.d('D1').call('voidSalesReturn', {'id': sr1}) as Map).cast<String, Object?>();
        if (v2['ok'] == true) problems.add('[$phase] إلغاء مرتجع ملغى مسبقاً قُبل');
      }
      await checkpoint('إلغاء مرتجع مبيعات');

      // ══════════ 7) مرتجعات المشتريات ══════════
      phase = 'مرتجعات المشتريات';
      Future<int?> purchaseReturn(String prod, double qty, double price, String mode,
          {double cash = 0, bool expectOk = true, String label = ''}) async {
        final r = (await h.d('D1').call('purchaseReturn', {'prod': prod, 'qty': qty, 'price': price, 'mode': mode, 'cash': cash})
                as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          if (expectOk) problems.add('[$phase] $label: رُفض (${r['err']})');
          return null;
        }
        if (!expectOk) problems.add('[$phase] $label: قُبل والمتوقع رفضه');
        h.truth.products[prod]!.movements -= qty;
        return r['id'] as int;
      }

      await purchaseReturn(a, 3, 500, 'debt', label: 'مرتجع مشتريات من الدين');
      final pr2 = await purchaseReturn(b, 12, 800, 'cash', label: 'مرتجع مشتريات نقداً');
      await purchaseReturn(c, 1, 1200, 'mixed', cash: 700, label: 'مرتجع مشتريات مختلط');
      await purchaseReturn(a, 100000, 1, 'debt', expectOk: false, label: 'إرجاع أكثر من المتوفر');
      await checkpoint('مرتجعات المشتريات');
      if (pr2 != null) {
        final v = (await h.d('D1').call('voidPurchaseReturn', {'id': pr2}) as Map).cast<String, Object?>();
        if (v['ok'] != true) {
          problems.add('[$phase] إلغاء مرتجع المشتريات رُفض: ${v['err']}');
        } else {
          h.truth.products[b]!.movements += 12;
        }
      }
      await checkpoint('إلغاء مرتجع مشتريات');

      // ══════════ 8) تثبيت الإدخالات ══════════
      phase = 'تثبيت الإدخالات';
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await h.d('D1').call('setLock', {'date': DateTime(tomorrow.year, tomorrow.month, tomorrow.day).toIso8601String()});
      await inv('D1', x, 7000, 2000, 'دين', edit: i3, items: it(a, 7, 1000), expectOk: false, label: 'تعديل فاتورة مثبّتة');
      await inv('D1', x, 999, 0, 'دين', expectOk: false, label: 'فاتورة جديدة في فترة مثبّتة');
      try {
        await h.d('D1').call('addTx', {'cust': x, 'amount': 123.0, 'marker': 'LOCKED'});
        problems.add('[$phase] معاملة داخل فترة مثبّتة قُبلت');
      } catch (_) {/* مرفوضة كما يجب */}
      final pl = (await h.d('D1').call('purchaseReturn', {'prod': a, 'qty': 1, 'price': 1, 'mode': 'debt'}) as Map)
          .cast<String, Object?>();
      if (pl['ok'] == true) {
        problems.add('[$phase] مرتجع مشتريات داخل فترة مثبّتة قُبل');
        h.truth.products[a]!.movements -= 1;
      }
      await h.d('D1').call('setLock', {'date': null});
      await checkpoint('تثبيت الإدخالات');

      // ══════════ 9) نسخة احتياطية، استعادة، وجهاز جديد ══════════
      phase = 'نسخ واستعادة';
      await h.backup('D3');
      await h.addTx('D1', x, -250);
      await inv('D1', x, 10000, 1000, 'دين', edit: i8, items: it(a, 10, 1000), label: 'ف8 مسدد جزئي بعد النسخة');
      await checkpoint('بعد النسخة الاحتياطية');
      final restored = await h.restoreBackup('D3');
      if (!restored) print('ℹ️ الاستعادة لم تُنفّذ (عمل غير مرفوع)');
      await checkpoint('بعد الاستعادة');
      await h.joinNewDevice();
      await checkpoint('جهاز جديد ينضم');

      // ══════════ النهاية ══════════
      phase = 'النهاية';
      print('رصيد ${h.truth.customers[x]!.name} = ${h.truth.balance(x)}');
      print('رصيد ${h.truth.customers[y]!.name} = ${h.truth.balance(y)}');
      print('مخزون أ=${h.truth.stock(a)} ب=${h.truth.stock(b)} ج=${h.truth.stock(c)}');
      print('فاتورة العميل الثاني: $i11');
      if (problems.isNotEmpty) {
        print('════ المشكلات (${problems.length}) ════');
        print(problems.join('\n'));
      } else {
        print('════ لا مشكلات: كل الأرصدة والمخزون والقيود مطابقة على كل الأجهزة ════');
      }
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}
