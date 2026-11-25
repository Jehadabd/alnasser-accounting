import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/smart_price_engine.dart';

PriceSale s(double p, {int? c, double? cost, required DateTime d}) =>
    PriceSale(price: p, cost: cost, customerId: c, date: d);

void main() {
  final now = DateTime(2026, 11, 25);
  DateTime ago(int days) => now.subtract(Duration(days: days));

  group('الوحدات والتقريب', () {
    test('المرادفات فقط تُدمج: القطعة لا تختلط بالكرتون', () {
      expect(SmartPriceMath.normalizeUnit('piece'), 'قطعة');
      expect(SmartPriceMath.normalizeUnit('roll'), 'لفة');
      expect(SmartPriceMath.unitAliases('قطعة'), containsAll(['قطعة', 'piece']));
      expect(SmartPriceMath.unitAliases('كرتون'), ['كرتون']);
    });
    test('خطوة أسعار المتجر: 25 تحت 500، 50 حتى 10,000، 250 فوقها', () {
      expect(SmartPriceMath.roundPrice(90660), 90750);
      expect(SmartPriceMath.roundPrice(4620), 4600); // لا 4,500 كما في التقريب القديم
      expect(SmartPriceMath.roundPrice(1230), 1250);
      expect(SmartPriceMath.roundPrice(265), 275); // الكلاند: زيادة الكلفة لا تضيع
      expect(SmartPriceMath.roundPrice(10), 25);
      expect(SmartPriceMath.roundUp(105), 125);
    });
  });

  group('معامل الزبون', () {
    test('بلا تاريخ = 1', () {
      expect(SmartPriceMath.customerFactor([]).$1, 1.0);
    });
    test('مسحوب نحو 1 بتاريخ قصير، ويقترب من وسيطه بتاريخ طويل', () {
      final short = SmartPriceMath.customerFactor([0.9, 0.9]).$1; // 1 − 0.1×2/17
      expect(short, closeTo(0.9882, 0.001));
      final long = SmartPriceMath.customerFactor(List.filled(30, 0.9)).$1; // 1 − 0.1×30/45
      expect(long, closeTo(0.9333, 0.001));
    });
    test('نسب الخلط بين الوحدات (خارج 0.3..3) تُهمل', () {
      final f = SmartPriceMath.customerFactor([0.01, 50, 1.0, 1.0]);
      expect(f.$2, 2);
      expect(f.$1, 1.0);
    });
  });

  group('القرار', () {
    final market = [
      s(90000, c: 1, cost: 85200, d: ago(1)),
      s(88000, c: 2, cost: 85200, d: ago(2)),
      s(92000, c: 3, cost: 85200, d: ago(3)),
      s(90500, c: 4, cost: 85200, d: ago(5)),
      s(89000, c: 5, cost: 85200, d: ago(6)),
    ];

    test('آخر سعر للزبون خلال 120 يوماً يربح', () {
      final d = SmartPriceMath.decide(history: market, now: now, customerId: 3, currentCost: 85200)!;
      expect(d.path, 'own');
      expect(d.price, 92000);
    });

    test('تغيّرت الكلفة: يبقى مبلغ ربح الزبون (85,200 ← 87,360)', () {
      final d = SmartPriceMath.decide(history: market, now: now, customerId: 3, currentCost: 87360)!;
      expect(d.price, 94250); // 92,000 + 2,160 = 94,160 ⇒ أقرب 250
    });

    test('شراؤه أقدم من 120 يوماً ⇒ سعر السوق', () {
      final h = [...market, s(70000, c: 9, cost: 60000, d: ago(200))];
      final d = SmartPriceMath.decide(history: h, now: now, customerId: 9, currentCost: 85200)!;
      expect(d.path, 'market');
      expect(d.price, 90000); // وسيط آخر 5: 88,000 89,000 90,000 90,500 92,000
    });

    test('زبون كبير (معامل 0.97) ينزل عن سعر السوق ويلتقط أقرب سعر حقيقي', () {
      final d = SmartPriceMath.decide(history: market, now: now, customerId: 99, currentCost: 85200, factor: 0.97)!;
      expect(d.price, 88000); // 90,000 × 0.97 = 87,300 ⇒ 87,250 ⇒ أقرب سعر حقيقي ضمن 3%: 88,000
    });

    test('لا التقاط إن لم يوجد سعر حقيقي ضمن 3%', () {
      final d = SmartPriceMath.decide(history: market, now: now, customerId: 99, currentCost: 70000, factor: 0.9)!;
      expect(d.price, 81000); // 90,000 × 0.9 — أقرب سعر حقيقي 88,000 يبعد 8.6%
    });

    test('لا يقترح أقل من الكلفة + 2% — يُرفع ثم يلتقط سعراً حقيقياً فوق الأرضية', () {
      final d = SmartPriceMath.decide(history: market, now: now, customerId: 99, currentCost: 89000, factor: 0.9)!;
      // 81,000 < 90,780 ⇒ الكلفة + 5% = 93,450 ⇒ للأعلى 93,500 ⇒ أقرب حقيقي ضمن 3%: 92,000
      expect(d.price, 92000);
      expect(d.price, greaterThanOrEqualTo(89000 * 1.02));
    });

    test('الالتقاط لا ينزل تحت أرضية الربح', () {
      final h = [s(90000, c: 1, cost: 89500, d: ago(1))];
      final d = SmartPriceMath.decide(history: h, now: now, customerId: 99, currentCost: 89500)!;
      expect(d.price, 94000); // 90,000 < 91,290 ⇒ 93,975 ⇒ للأعلى 94,000؛ و90,000 تحت الأرضية فلا يُلتقط
    });

    test('مادة بلا مبيعات: الكلفة × هامش نطاقها', () {
      final d = SmartPriceMath.decide(history: const [], now: now, currentCost: 1000)!;
      expect(d.path, 'cold');
      expect(d.price, 1400); // 1,000 × 1.39 = 1,390 ⇒ 1,400
      final big = SmartPriceMath.decide(history: const [], now: now, currentCost: 1000, factor: 0.9)!;
      expect(big.price, 1250); // هامش الكبار 25%
    });

    test('بلا تاريخ ولا كلفة ⇒ لا اقتراح (الشاشة تستعمل سعر المادة)', () {
      expect(SmartPriceMath.decide(history: const [], now: now), isNull);
    });
  });
}
