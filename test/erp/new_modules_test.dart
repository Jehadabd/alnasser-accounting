// test/erp/new_modules_test.dart
//
// الوحدات الجديدة: تغيير السعر، نطاق المخازن، التوصيل، الولاء، الرواتب، المتغيّرات،
// الدفعات، والتسويق — الدوال الصافية، وتسوية التوصيل على قاعدة في الذاكرة.
// التشغيل: flutter test test/erp/new_modules_test.dart

import 'package:alnaser/erp/batches/batch_models.dart';
import 'package:alnaser/erp/control/approval_gate.dart';
import 'package:alnaser/erp/control/price_list.dart';
import 'package:alnaser/erp/delivery/delivery_models.dart';
import 'package:alnaser/erp/delivery/delivery_store.dart';
import 'package:alnaser/erp/hr/hr_models.dart';
import 'package:alnaser/erp/loyalty/loyalty_models.dart';
import 'package:alnaser/erp/variants/variant_models.dart';
import 'package:alnaser/marketing/marketing_store.dart';
import 'package:alnaser/models/app_user.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/org/warehouse_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

InvoiceItem _item(String name, double price, {double? before, double? large, double? perLarge, int? productId}) => InvoiceItem(
      invoiceId: 0,
      productId: productId,
      productName: name,
      unit: 'piece',
      quantityIndividual: large == null ? 1 : 0,
      quantityLargeUnit: large,
      unitsInLargeUnit: perLarge,
      appliedPrice: price,
      itemTotal: price * (large ?? 1),
      saleType: large == null ? 'قطعة' : 'كرتون',
      discountType: before != null ? 'amount' : null,
      priceBeforeDiscount: before,
      discountValue: before == null ? null : before - price,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('🏷️ تغيير السعر', () {
    const list = [1000.0, 900.0];
    test('سعر من القائمة (أو مضروباً بعدد قطع الكرتون) = لا تغيير', () {
      expect(PriceList.matches(_item('سلك', 1000), list), isTrue);
      expect(PriceList.matches(_item('سلك', 900), list), isTrue);
      expect(PriceList.matches(_item('سلك', 12000, large: 1, perLarge: 12), list), isTrue);
      expect(PriceList.matches(_item('سلك', 1003), list), isTrue, reason: 'ضمن الهامش (دينار أو 0.5٪)');
    });
    test('سعر آخر = تغيير، والخصم لا يُحسب تغييراً', () {
      expect(PriceList.matches(_item('سلك', 1200), list), isFalse);
      expect(PriceList.matches(_item('سلك', 800, before: 1000), list), isTrue, reason: 'السعر قبل الخصم من القائمة');
    });
    test('القاعدة مطفأة افتراضياً، وصاحب الصلاحية لا يُسأل', () {
      final off = ApprovalSettings(pastDate: false, belowCost: false, discountPct: 0);
      final on = off.copyWith(priceChange: true);
      final items = [_item('سلك', 1500, productId: 7)];
      final prices = {'id:7': list};
      final today = DateTime(2026, 11, 9);
      expect(invoiceViolations(settings: off, items: items, invoiceDiscount: 0, selectedDate: today, today: today, listPrices: prices), isEmpty);
      expect(
          invoiceViolations(settings: on, items: items, invoiceDiscount: 0, selectedDate: today, today: today, listPrices: prices)
              .map((v) => v.rule),
          [ApprovalRule.priceChange]);
      expect(
          invoiceViolations(
              settings: on, items: items, invoiceDiscount: 0, selectedDate: today, today: today, listPrices: prices, canChangePrice: true),
          isEmpty);
    });
    test('copyWith لا يمحو الإعدادات الأخرى', () {
      final s = ApprovalSettings(pastDate: true, belowCost: true, discountPct: 7, priceChange: true, cashTransfer: true, cashTransferMin: 50000);
      final t = s.copyWith(pastDate: false);
      expect([t.belowCost, t.discountPct, t.priceChange, t.cashTransfer, t.cashTransferMin], [true, 7, true, true, 50000]);
    });
  });

  group('🔐 نطاق المخازن', () {
    AppUser u(List<String> p, {String role = 'accountant'}) =>
        AppUser(username: 'x', passwordHash: '', role: role, createdAt: DateTime(2026), permissions: p);
    test('بلا مفاتيح = غير مقيّد، والمدير لا يُقيَّد', () {
      expect(WarehouseScope.codesOf(u(['reports'])), isEmpty);
      expect(WarehouseScope.codesOf(u(['scope_wh:W2'], role: 'admin')), isEmpty);
      expect(WarehouseScope.allows(const {}, 'W9'), isTrue);
    });
    test('مقيّد بمخزنين', () {
      final c = WarehouseScope.codesOf(u(['reports', 'scope_wh:W1', 'scope_wh:W3']));
      expect(c, {'W1', 'W3'});
      expect(WarehouseScope.allows(c, 'W3'), isTrue);
      expect(WarehouseScope.allows(c, 'W2'), isFalse);
      expect(WarehouseScope.allows(c, null), isFalse);
    });
  });

  group('🚚 التوصيل', () {
    DeliveryOrder o(DeliveryStatus s, int cod, int fee, {int? settlement}) => DeliveryOrder(
        id: cod + fee, companyId: 1, customerName: 'ز', codFils: cod, feeFils: fee, status: s, createdAt: DateTime(2026), settlementId: settlement);
    test('الصافي = تحصيل المسلّم − أجور المسلّم والراجع، والمُسوّى لا يدخل', () {
      final b = DeliveryBalance.of([
        o(DeliveryStatus.delivered, 5000000, 500000),
        o(DeliveryStatus.returned, 3000000, 500000),
        o(DeliveryStatus.out, 2000000, 500000),
        o(DeliveryStatus.cancelled, 1000000, 500000),
        o(DeliveryStatus.delivered, 7000000, 500000, settlement: 1),
      ]);
      expect(b.codFils, 5000000);
      expect(b.feeFils, 1000000);
      expect(b.netFils, 4000000);
      expect([b.delivered, b.returned, b.open, b.orders.length], [1, 1, 1, 2]);
    });
    test('انتقالات الحالة', () {
      expect(DeliveryStatus.pending.next, contains(DeliveryStatus.out));
      expect(DeliveryStatus.pending.next, isNot(contains(DeliveryStatus.delivered)));
      expect(DeliveryStatus.delivered.next, [DeliveryStatus.returned]);
    });
    test('التسوية على قاعدة: تحسب من القاعدة، تعلّم الطلبات، ولا تُسوّى مرتين', () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false));
      await DeliveryStore.ensureSchema(db);
      final s = DeliveryStore(db: () async => db);
      final cid = await s.saveCompany(DeliveryCompany(name: 'شركة', defaultFeeFils: 500000));
      Future<DeliveryOrder> add(int cod) async {
        final id = await s.saveOrder(DeliveryOrder(companyId: cid, customerName: 'ز', codFils: cod, feeFils: 500000, createdAt: DateTime.now()));
        return (await s.orders(companyId: cid)).firstWhere((x) => x.id == id);
      }

      var a = await add(5000000);
      await s.setStatus(a, DeliveryStatus.out);
      a = (await s.orders(companyId: cid)).firstWhere((x) => x.id == a.id);
      await s.setStatus(a, DeliveryStatus.delivered);
      await add(1000000); // جديد: لا يدخل
      await expectLater(s.setStatus(a, DeliveryStatus.cancelled), throwsA(anything), reason: 'نسخة قديمة / انتقال غير مسموح');
      final r = await s.settle(cid);
      expect(r.balance.netFils, 4500000);
      expect((await s.orders(companyId: cid, unsettledOnly: true)).length, 1);
      await expectLater(s.settle(cid), throwsA(anything));
      await db.close();
    });
  });

  group('🎁 الولاء', () {
    const s = LoyaltySettings(enabled: true, filsPerPoint: 100000, rewardCost: 100);
    test('النقاط من الصافي بعد المرتجع، والمتاح بعد المصروف', () {
      final b = LoyaltyBalance.of(s, invoiceNetFils: [5000000, 7000000], returnsFils: 1500000, redeemed: 50);
      expect(b.earned, 105); // 105,000 دينار
      expect(b.available, 55);
      expect(b.rewardsAvailable, 0);
      expect(b.toNextReward, 45);
    });
    test('الأختام: فاتورة فوق الحد = ختم', () {
      const st = LoyaltySettings(mode: LoyaltyMode.stamps, stampMinFils: 1000000, stampsPerReward: 3);
      final b = LoyaltyBalance.of(st, invoiceNetFils: [1000000, 999999, 2000000, 1500000, -100]);
      expect(b.earned, 3);
      expect(b.rewardsAvailable, 1);
    });
    test('مرتجع أكبر من المبيعات لا يعطي نقاطاً سالبة، والمصروف الزائد لا يجعل المتاح سالباً', () {
      final b = LoyaltyBalance.of(s, invoiceNetFils: [100000], returnsFils: 900000, redeemed: 10);
      expect(b.earned, 0);
      expect(b.available, 0);
    });
    test('الإعدادات تُحفظ وتُقرأ، والقيم الفاسدة تعود للافتراضي', () {
      final t = LoyaltySettings.fromMap(s.toMap());
      expect(t.toMap(), s.toMap());
      expect(LoyaltySettings.fromMap({'fils_per_point': '-5', 'reward_cost': 'x'}).filsPerPoint, const LoyaltySettings().filsPerPoint);
    });
  });

  group('👥 الرواتب', () {
    test('الصافي = الأساسي + المكافأة − الخصم − السلف، والمصروف لا يحسب السلفة مرتين', () {
      const p = Payslip(employeeId: 1, month: '2026-11', baseFils: 50000000, bonusFils: 5000000, deductionFils: 2000000, advancesFils: 10000000);
      expect(p.netFils, 43000000);
      expect(p.expenseFils, 53000000);
      expect(p.error, isNull);
      expect(const Payslip(employeeId: 1, month: '2026-11', baseFils: 100, advancesFils: 200).error, isNotNull);
    });
    test('السلف المفتوحة حتى نهاية الشهر فقط', () {
      final adv = [
        HrAdvance(1, 1, DateTime(2026, 11, 3), 1000, '', null),
        HrAdvance(2, 1, DateTime(2026, 11, 30, 23), 2000, '', null),
        HrAdvance(3, 1, DateTime(2026, 12, 1), 4000, '', null),
        HrAdvance(4, 1, DateTime(2026, 10, 1), 8000, '', 5), // مخصومة
        HrAdvance(5, 2, DateTime(2026, 11, 3), 16000, '', null), // موظف آخر
      ];
      expect(Payslip.openAdvances(adv, 1, '2026-11'), 3000);
    });
    test('دقائق العمل', () {
      expect(workedMinutes(DateTime(2026, 1, 1, 8), DateTime(2026, 1, 1, 16, 30)), 510);
      expect(workedMinutes(DateTime(2026, 1, 1, 8), null), isNull);
    });
  });

  group('👕 المتغيّرات', () {
    test('حاصل الضرب والأسماء، والخاصية الفارغة تُتجاهل', () {
      final c = Variants.combos([VariantAxis('المقاس', VariantAxis.split('S، M ,L, M')), VariantAxis('اللون', ['أحمر', 'أزرق'])]);
      expect(c.length, 6);
      expect(Variants.name('قميص', c.first), 'قميص - S - أحمر');
      expect(Variants.combos([VariantAxis('المقاس', ['S']), VariantAxis('اللون', [])]).length, 1);
      expect(Variants.combos([VariantAxis('أ', [])]), isEmpty);
    });
    test('سقف التركيبات', () {
      final many = [for (var i = 0; i < 30; i++) '$i'];
      expect(() => Variants.combos([VariantAxis('أ', many), VariantAxis('ب', many)]), throwsStateError);
    });
  });

  group('🧪 الدفعات', () {
    StockLot l(int id, DateTime exp, double q) => StockLot(id: id, productId: 1, lotNo: '$id', expiry: exp, qty: q, receivedAt: DateTime(2026));
    test('الكمية الحالية تبقى في الأبعد انتهاءً (FEFO)', () {
      final r = Lots.allocate(15, [l(1, DateTime(2026, 12, 1), 10), l(2, DateTime(2027, 3, 1), 10), l(3, DateTime(2027, 1, 1), 10)]);
      final m = {for (final x in r) x.lot.id: x.remaining};
      expect(m, {1: 0, 3: 5, 2: 10});
      expect(r.first.lot.id, 1, reason: 'مرتبة بالأقرب انتهاءً للعرض');
    });
    test('كمية سالبة أو أكبر من الدفعات', () {
      expect(Lots.allocate(-3, [l(1, DateTime(2027), 5)]).single.remaining, 0);
      expect(Lots.allocate(100, [l(1, DateTime(2027), 5)]).single.remaining, 5);
    });
  });

  group('📣 التسويق', () {
    test('شروط المنشور قبل النشر', () {
      expect(MkPost(text: '', at: DateTime(2026)).problem, isNotNull);
      expect(MkPost(text: 'عرض', at: DateTime(2026), facebook: false).problem, isNotNull);
      expect(MkPost(text: 'عرض', at: DateTime(2026), instagram: true, imageUrl: 'http://x').problem, isNotNull, reason: 'Meta تشترط https');
      expect(MkPost(text: 'عرض', at: DateTime(2026), instagram: true, imageUrl: 'https://x/a.jpg').problem, isNull);
      expect(MkPost(text: 'عرض', at: DateTime(2026)).problem, isNull);
    });
  });
}
