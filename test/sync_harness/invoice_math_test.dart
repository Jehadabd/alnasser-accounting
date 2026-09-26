// اختبار حسابات الفاتورة: سيناريوهات بأرقام معروفة مسبقاً على كود التطبيق
// الحقيقي (InvoiceController + الحارس المحاسبي + دفتر المخزون)، ثم التحقق
// على الجهاز المنشئ وعلى جهاز آخر استلمها بالمزامنة.
//   flutter test test/sync_harness/invoice_math_test.dart
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  test('حسابات الفاتورة: مجموع، خصم، تحميل، مسدد، سنتات، دين، مخزون، إرجاع، تحويل، تغيير عميل',
      () async {
    final h = Harness(seed: 11);
    final problems = <String>[];
    void expectNear(String what, Object? got, double want) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() > 0.001) problems.add('$what = $g والمتوقع $want');
    }

    try {
      await h.start(2);
      final x = (await h.addCustomer('D1', 'زبون الحساب'))!;
      final y = (await h.addCustomer('D1', 'زبون آخر'))!;
      final a = (await h.addProduct('D1', 'صنف حساب أ', 100))!; // بالقطعة
      final b = (await h.addProduct('D1', 'صنف حساب ب', 240, carton: 12))!; // كرتون 12
      final c = (await h.addProduct('D1', 'صنف كسور', 50))!;
      var errs = await h.settle();
      expect(errs, isEmpty, reason: errs.join('\n'));

      /// يحفظ فاتورة بمسار الشاشة ويسجّل ما يجب أن يكون في «الحقيقة».
      Future<String?> save({
        required String cust,
        required List<Map<String, Object?>> items,
        required double itemsTotal,
        double discount = 0,
        double fee = 0,
        required double paid,
        required String ptype,
        String? inv,
        bool expectOk = true,
        String label = '',
      }) async {
        final r = (await h.d('D1').call('saveInvoice', {
          'cust': cust,
          'total': itemsTotal,
          'paid': paid,
          'ptype': ptype,
          'inv': inv,
          'items': items,
          'discount': discount,
          'loadingFee': fee,
        }) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          if (expectOk) problems.add('$label: رُفضت والمتوقع قبولها (${r['err']})');
          return null;
        }
        if (!expectOk) {
          problems.add('$label: قُبلت والمتوقع رفضها');
          return null;
        }
        final uuid = r['uuid'] as String;
        final total = itemsTotal + fee - discount;
        final prev = h.truth.invoices[uuid];
        h.truth.invoices[uuid] = TruthInvoice(cust, 'D1', total, paid, ptype, 'محفوظة')
          ..voidedFor = {...?prev?.voidedFor}
          ..items = {
            for (final it in items)
              it['prod'] as String: (it['qty'] as double) *
                  ((it['large'] == true) ? (h.truth.products[it['prod']]!.carton ?? 1) : 1)
          };
        return uuid;
      }

      /// يتحقق من الحقول المخزّنة للفاتورة على جهازين.
      Future<void> verifyStored(String inv, String label,
          {required double total,
          required double paid,
          required double discount,
          required double fee,
          required String ptype,
          required String cust,
          required List<double> itemTotals,
          required double recon}) async {
        for (final dev in ['D1', 'D2']) {
          final r = (await h.d(dev).call('invoiceDetail', {'inv': inv}) as Map?)
              ?.cast<String, Object?>();
          if (r == null) {
            problems.add('$label/$dev: الفاتورة غائبة');
            continue;
          }
          final i = (r['invoice'] as Map).cast<String, Object?>();
          expectNear('$label/$dev total_amount', i['total_amount'], total);
          expectNear('$label/$dev total_amount_cents', i['total_amount_cents'], (total * 100).roundToDouble());
          expectNear('$label/$dev amount_paid_on_invoice', i['amount_paid_on_invoice'], paid);
          expectNear('$label/$dev discount', i['discount'], discount);
          expectNear('$label/$dev loading_fee', i['loading_fee'], fee);
          if (i['payment_type'] != ptype) problems.add('$label/$dev payment_type = ${i['payment_type']}');
          if (i['cust_uuid'] != cust) problems.add('$label/$dev العميل = ${i['cust_uuid']}');
          final items = (r['items'] as List).cast<Map>();
          final totals = [for (final it in items) (it['item_total'] as num).toDouble()]..sort();
          final want = [...itemTotals]..sort();
          if (totals.length != want.length) {
            problems.add('$label/$dev عدد البنود ${totals.length} والمتوقع ${want.length}');
          } else {
            for (var k = 0; k < want.length; k++) {
              expectNear('$label/$dev item_total[$k]', totals[k], want[k]);
            }
          }
          for (final it in items) {
            expectNear('$label/$dev item_total_cents', it['item_total_cents'],
                ((it['item_total'] as num).toDouble() * 100).roundToDouble());
          }
          // دين الفاتورة المسجّل للعميل = المتبقي (للدين) أو صفر (للنقد)
          final txs = (r['txs'] as List).cast<Map>();
          final active = txs.where((t) => (t['del'] ?? 0) == 0 && t['cust'] == cust);
          final sum = active.fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
          expectNear('$label/$dev دين الفاتورة للعميل', sum, recon);
          final others = txs.where((t) => (t['del'] ?? 0) == 0 && t['cust'] != cust);
          final otherSum = others.fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
          expectNear('$label/$dev دين الفاتورة لعميل آخر', otherSum, 0);
        }
      }

      // ── 1) فاتورة دين: 3 × 250 + كرتونان × 1200 + تحميل 50 − خصم 100، مسدد 1000
      final inv = await save(
        label: 'فاتورة دين',
        cust: x,
        items: [
          {'prod': a, 'qty': 3.0, 'price': 250.0},
          {'prod': b, 'qty': 2.0, 'large': true, 'price': 1200.0},
        ],
        itemsTotal: 750 + 2400,
        fee: 50,
        discount: 100,
        paid: 1000,
        ptype: 'دين',
      );
      errs = await h.settle();
      problems.addAll(errs);
      await verifyStored(inv!, 'فاتورة دين',
          total: 3100, paid: 1000, discount: 100, fee: 50, ptype: 'دين', cust: x,
          itemTotals: [750, 2400], recon: 2100);
      expectNear('مخزون أ بعد البيع', h.truth.stock(a), 97);
      expectNear('مخزون ب بعد البيع', h.truth.stock(b), 216);

      // ── 2) إرجاع قطعة من أ (تعديل الفاتورة نفسها): 2 × 250
      await save(
        label: 'إرجاع قطعة',
        cust: x,
        inv: inv,
        items: [
          {'prod': a, 'qty': 2.0, 'price': 250.0},
          {'prod': b, 'qty': 2.0, 'large': true, 'price': 1200.0},
        ],
        itemsTotal: 500 + 2400,
        fee: 50,
        discount: 100,
        paid: 1000,
        ptype: 'دين',
      );
      errs = await h.settle();
      problems.addAll(errs);
      await verifyStored(inv, 'إرجاع قطعة',
          total: 2850, paid: 1000, discount: 100, fee: 50, ptype: 'دين', cust: x,
          itemTotals: [500, 2400], recon: 1850);
      expectNear('مخزون أ بعد الإرجاع', h.truth.stock(a), 98);

      // ── 3) إرجاع كرتون كامل من ب وحذف بند أ كله
      await save(
        label: 'إرجاع كرتون وحذف بند',
        cust: x,
        inv: inv,
        items: [
          {'prod': b, 'qty': 1.0, 'large': true, 'price': 1200.0},
        ],
        itemsTotal: 1200,
        fee: 50,
        discount: 100,
        paid: 1000,
        ptype: 'دين',
      );
      errs = await h.settle();
      problems.addAll(errs);
      await verifyStored(inv, 'إرجاع كرتون',
          total: 1150, paid: 1000, discount: 100, fee: 50, ptype: 'دين', cust: x,
          itemTotals: [1200], recon: 150);
      expectNear('مخزون أ بعد حذف البند', h.truth.stock(a), 100);
      expectNear('مخزون ب بعد إرجاع كرتون', h.truth.stock(b), 228);

      // ── 4) مرفوض: إنقاص المجموع تحت المسدد (1000)
      await save(
        label: 'مجموع تحت المسدد',
        cust: x,
        inv: inv,
        items: [
          {'prod': a, 'qty': 1.0, 'price': 500.0},
        ],
        itemsTotal: 500,
        paid: 1000,
        ptype: 'دين',
        expectOk: false,
      );

      // ── 5) تحويل إلى نقد: المسدد = المجموع، ولا دين
      await save(
        label: 'تحويل لنقد',
        cust: x,
        inv: inv,
        items: [
          {'prod': b, 'qty': 1.0, 'large': true, 'price': 1200.0},
        ],
        itemsTotal: 1200,
        fee: 50,
        discount: 100,
        paid: 1150,
        ptype: 'نقد',
      );
      errs = await h.settle();
      problems.addAll(errs);
      await verifyStored(inv, 'تحويل لنقد',
          total: 1150, paid: 1150, discount: 100, fee: 50, ptype: 'نقد', cust: x,
          itemTotals: [1200], recon: 0);

      // ── 6) عودة للدين بلا مسدد، ثم نقلها لعميل آخر
      await save(
        label: 'عودة للدين',
        cust: x,
        inv: inv,
        items: [
          {'prod': b, 'qty': 1.0, 'large': true, 'price': 1200.0},
        ],
        itemsTotal: 1200,
        fee: 50,
        discount: 100,
        paid: 0,
        ptype: 'دين',
      );
      await h.settle();
      await save(
        label: 'تغيير العميل',
        cust: y,
        inv: inv,
        items: [
          {'prod': b, 'qty': 1.0, 'large': true, 'price': 1200.0},
        ],
        itemsTotal: 1200,
        fee: 50,
        discount: 100,
        paid: 0,
        ptype: 'دين',
      );
      errs = await h.settle();
      problems.addAll(errs);
      await verifyStored(inv, 'تغيير العميل',
          total: 1150, paid: 0, discount: 100, fee: 50, ptype: 'دين', cust: y,
          itemTotals: [1200], recon: 1150);
      expectNear('رصيد العميل الأول بعد النقل', h.truth.balance(x), 0);
      expectNear('رصيد العميل الثاني بعد النقل', h.truth.balance(y), 1150);

      // ── 7) كسور: 3 × 333.33 − خصم 0.99 = 999.00 (سنتات بلا انجراف)
      final inv2 = await save(
        label: 'كسور',
        cust: y,
        items: [
          {'prod': c, 'qty': 3.0, 'price': 333.33},
        ],
        itemsTotal: 999.99,
        discount: 0.99,
        paid: 0.5,
        ptype: 'دين',
      );
      errs = await h.settle();
      problems.addAll(errs);
      await verifyStored(inv2!, 'كسور',
          total: 999.0, paid: 0.5, discount: 0.99, fee: 0, ptype: 'دين', cust: y,
          itemTotals: [999.99], recon: 998.5);

      // ── 8) تحقق الإدخال: كل هذه مرفوضة
      await save(label: 'خصم = المجموع', cust: y, items: [{'prod': c, 'qty': 1.0, 'price': 100.0}],
          itemsTotal: 100, discount: 100, paid: 0, ptype: 'دين', expectOk: false);
      await save(label: 'خصم سالب', cust: y, items: [{'prod': c, 'qty': 1.0, 'price': 100.0}],
          itemsTotal: 100, discount: -5, paid: 0, ptype: 'دين', expectOk: false);
      await save(label: 'تحميل سالب', cust: y, items: [{'prod': c, 'qty': 1.0, 'price': 100.0}],
          itemsTotal: 100, fee: -1, paid: 0, ptype: 'دين', expectOk: false);
      await save(label: 'مسدد > المجموع', cust: y, items: [{'prod': c, 'qty': 1.0, 'price': 100.0}],
          itemsTotal: 100, paid: 150, ptype: 'دين', expectOk: false);
      await save(label: 'نقد بمسدد ناقص', cust: y, items: [{'prod': c, 'qty': 1.0, 'price': 100.0}],
          itemsTotal: 100, paid: 60, ptype: 'نقد', expectOk: false);

      // ── النهاية: كل الأجهزة = الحقيقة (أرصدة ومخزون)
      errs = await h.settle();
      problems.addAll(errs);
      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
      if (problems.isNotEmpty) print(problems.join('\n'));
      expect(problems, isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
