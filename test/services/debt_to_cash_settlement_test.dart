// test/services/debt_to_cash_settlement_test.dart
//
// 🔁 تحويل فاتورة دين إلى «نقد» بعد وصل قبض — بأرقام ثابتة مكتوبة يدوياً (لا تُشتق من الكود):
// ما سُدّد منها سابقاً لا يُقبض مرتين، والفاتورة تُحفظ «آجل — مسددة بالكامل».

import 'package:alnaser/models/invoice.dart';
import 'package:alnaser/models/invoice_input_data.dart';
import 'package:alnaser/services/invoice_safety/debt_to_cash_settlement.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceInputData _data({double paid = 100000, String ptype = 'نقد'}) => InvoiceInputData(
      customerName: 'زبون',
      customerPhone: '',
      customerAddress: '',
      paidAmount: paid,
      loadingFee: 0,
      discount: 0,
      paymentType: ptype,
      selectedDate: DateTime(2026, 11, 12),
      invoiceItems: const [],
    );

DebtToCashPlan _plan({required double r, required double b, double paidBefore = 0, double total = 100000}) =>
    DebtToCashPlan(
      recordedDebt: r,
      customerBalance: b,
      suggestedPrepaid: DebtToCashSettlement.suggestPrepaid(recordedDebt: r, customerBalance: b),
      paidBefore: paidBefore,
      newTotal: total,
    );

void main() {
  group('المقترح: ما سُدّد من الفاتورة سابقاً', () {
    test('مثال صاحب المحل: فاتورة 100,000 دين، وصل 25,000 ⇒ سُدّد منها 25,000', () {
      expect(DebtToCashSettlement.suggestPrepaid(recordedDebt: 100000, customerBalance: 75000), 25000);
    });
    test('لا وصل (الرصيد = دين الفاتورة) ⇒ صفر: تحويل عادي إلى نقد', () {
      expect(DebtToCashSettlement.suggestPrepaid(recordedDebt: 100000, customerBalance: 100000), 0);
    });
    test('للعميل فاتورة دين أخرى (رصيده أكبر) ⇒ لا يُستنتج تسديد', () {
      expect(DebtToCashSettlement.suggestPrepaid(recordedDebt: 100000, customerBalance: 175000), 0);
    });
    test('سدّد كل دينه بوصولات ⇒ الفاتورة كلها مسددة', () {
      expect(DebtToCashSettlement.suggestPrepaid(recordedDebt: 100000, customerBalance: 0), 100000);
    });
    test('سدّد أكثر من دينه (له رصيد) ⇒ لا يتجاوز دين الفاتورة', () {
      expect(DebtToCashSettlement.suggestPrepaid(recordedDebt: 100000, customerBalance: -20000), 100000);
    });
    test('فاتورة بلا دين مسجّل ⇒ صفر', () {
      expect(DebtToCashSettlement.suggestPrepaid(recordedDebt: 0, customerBalance: -5000), 0);
    });
  });

  group('الحفظ بعد الموافقة', () {
    test('100,000 دين + وصل 25,000 ⇒ آجل مسددة: المسدد 75,000 ويُقبض الآن 75,000', () {
      final p = _plan(r: 100000, b: 75000);
      final d = DebtToCashSettlement.apply(_data(), p, p.suggestedPrepaid);
      expect(d.paymentType, 'دين');
      expect(d.paidAmount, 75000);
      expect(d.prepaidByReceipts, 25000);
      expect(p.collectNow(25000), 75000);
      // الصندوق كله: الوصل 25,000 + الآن 75,000 = ثمن الفاتورة 100,000؛ ودين العميل:
      // (الإجمالي − المسدد) − الوصل = 25,000 − 25,000 = صفر
      expect(25000 + p.collectNow(25000), 100000);
      expect((100000 - d.paidAmount) - 25000, 0);
    });

    test('مسدد 30,000 على الفاتورة نفسها + وصل 20,000 ⇒ يُقبض الآن 50,000 فقط', () {
      // الإجمالي 100,000، المسدد عليها 30,000 ⇒ دينها 70,000؛ الوصل 20,000 ⇒ الرصيد 50,000
      final p = _plan(r: 70000, b: 50000, paidBefore: 30000);
      expect(p.suggestedPrepaid, 20000);
      final d = DebtToCashSettlement.apply(_data(), p, p.suggestedPrepaid);
      expect(d.paidAmount, 80000);
      expect(p.collectNow(20000), 50000);
      expect((100000 - d.paidAmount) - 20000, 0);
    });

    test('تعديل الإجمالي مع التحويل (120,000) ⇒ يُقبض الباقي كله إلا ما سُدّد', () {
      final p = _plan(r: 100000, b: 75000, total: 120000);
      final d = DebtToCashSettlement.apply(_data(paid: 120000), p, 25000);
      expect(d.paidAmount, 95000);
      expect(d.prepaidByReceipts, 25000);
      expect(p.collectNow(25000), 95000);
    });

    test('الإجمالي الجديد أقل مما سُدّد ⇒ المسدد صفر والعميل له الفرق', () {
      final p = _plan(r: 100000, b: 75000, total: 10000);
      final d = DebtToCashSettlement.apply(_data(paid: 10000), p, 25000);
      expect(d.paidAmount, 0);
      expect(d.prepaidByReceipts, 10000);
      // دين العميل = (الإجمالي − المسدد) − الوصل = 10,000 − 25,000 = −15,000 (له عندنا)
      expect((10000 - d.paidAmount) - 25000, -15000);
    });

    test('المستخدم يصحّح المقترح إلى صفر ⇒ تحويل عادي إلى نقد', () {
      final p = _plan(r: 100000, b: 75000);
      final d = DebtToCashSettlement.apply(_data(), p, 0);
      expect(d.paymentType, 'نقد');
      expect(d.paidAmount, 100000);
      expect(d.prepaidByReceipts, 0);
    });

    test('ما يكتبه المستخدم يُقصّ إلى [0، دين الفاتورة] وإلى دينار صحيح', () {
      final p = _plan(r: 100000, b: 75000);
      expect(p.clampPrepaid(250000), 100000);
      expect(p.clampPrepaid(-5), 0);
      expect(p.clampPrepaid(24999.6), 24999); // للأدنى دائماً، لا للأقرب
      expect(p.clampPrepaid(24999.99999999), 25000); // فرق تمثيل double لا يُسقط ديناراً
    });

    test('دين مسجّل بكسر قديم 99,999.6 وسدّد كل شيء ⇒ 99,999 (لا يتجاوز الدين)', () {
      expect(DebtToCashSettlement.suggestPrepaid(recordedDebt: 99999.6, customerBalance: 0), 99999);
    });
  });

  group('التسمية والعرض', () {
    Invoice inv({required String ptype, required double paid, double prepaid = 0}) => Invoice(
          customerName: 'زبون',
          invoiceDate: DateTime(2026, 11, 12),
          paymentType: ptype,
          totalAmount: 100000,
          amountPaidOnInvoice: paid,
          createdAt: DateTime(2026, 11, 12),
          lastModifiedAt: DateTime(2026, 11, 12),
          prepaidByReceipts: prepaid,
        );

    test('آجل سُدّد منها 25,000 بوصل والباقي عليها ⇒ «آجل — مسددة بالكامل» بلا باقٍ', () {
      final i = inv(ptype: 'دين', paid: 75000, prepaid: 25000);
      expect(i.paymentLabel, 'آجل — مسددة بالكامل');
      expect(i.settledAmount, 100000);
      expect(i.remainingAmount, 0);
    });
    test('آجل عادي ⇒ «آجل» وباقيه ظاهر', () {
      final i = inv(ptype: 'دين', paid: 30000);
      expect(i.paymentLabel, 'آجل');
      expect(i.remainingAmount, 70000);
    });
    test('نقد ⇒ «نقد» ولا باقٍ', () {
      final i = inv(ptype: 'نقد', paid: 100000);
      expect(i.paymentLabel, 'نقد');
      expect(i.remainingAmount, 0);
    });
    test('الحقل لا يُكتب في toMap (لا يمسّه أي كاتب آخر) ويُقرأ من القاعدة', () {
      final i = inv(ptype: 'دين', paid: 75000, prepaid: 25000);
      expect(i.toMap().containsKey('prepaid_by_receipts'), isFalse);
      final m = i.toMap()..['prepaid_by_receipts'] = 25000.0;
      expect(Invoice.fromMap(m).prepaidByReceipts, 25000);
    });
  });
}
