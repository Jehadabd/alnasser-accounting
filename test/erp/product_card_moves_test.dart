// test/erp/product_card_moves_test.dart
//
// 🗂️ حركة المادة: البيع بكميته الأصلية ثم كل تعديل «كانت X صارت Y» — بأرقام ثابتة.
// القاعدة في كل حالة: مجموع حركات الفاتورة = − كميتها الآن (التعديلات لا تغيّر الرصيد النهائي).

import 'package:alnaser/erp/inventory/inventory_reports.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> _moves(double current, List<(String, double)> edits, {String customer = 'أحمد'}) =>
    InventoryReports.saleMovesFor(
      number: '1050',
      invoiceDate: '2026-11-01T09:00:00.000',
      customer: customer,
      currentQty: current,
      edits: edits,
    );

double _sum(List<Map<String, Object?>> rows) => rows.fold(0.0, (s, r) => s + (r['q'] as num).toDouble());

void main() {
  group('saleMovesFor', () {
    test('بيع بلا تعديل: حركة واحدة برقم الفاتورة المطبوع', () {
      final r = _moves(10, const []);
      expect(r, hasLength(1));
      expect(r.single['q'], -10);
      expect(r.single['kind'], 'sale');
      expect(r.single['d'], '2026-11-01T09:00:00.000');
      expect(r.single['note'], 'فاتورة رقم 1050 — أحمد');
    });

    test('بيع 10 ثم تعديل إلى 7: −10 ثم +3 «كانت 10 صارت 7» بتاريخ التعديل', () {
      final r = _moves(7, const [('2026-11-05T14:30:00.000', -3)]);
      expect(r, hasLength(2));
      expect(r[0]['q'], -10);
      expect(r[0]['note'], 'فاتورة رقم 1050 — أحمد');
      expect(r[1]['q'], 3);
      expect(r[1]['kind'], 'sale_edit');
      expect(r[1]['d'], '2026-11-05T14:30:00.000');
      expect(r[1]['note'], 'تعديل الفاتورة رقم 1050: كانت 10 صارت 7 — أحمد');
      expect(_sum(r), -7);
    });

    test('تعديلان: 10 ← 12 ← 4', () {
      final r = _moves(4, const [('2026-11-02T10:00:00.000', 2), ('2026-11-03T10:00:00.000', -8)]);
      expect([for (final m in r) m['q']], [-10, -2, 8]);
      expect(r[1]['note'], 'تعديل الفاتورة رقم 1050: كانت 10 صارت 12 — أحمد');
      expect(r[2]['note'], 'تعديل الفاتورة رقم 1050: كانت 12 صارت 4 — أحمد');
      expect(_sum(r), -4);
    });

    test('أُزيلت المادة من الفاتورة بالتعديل: −5 ثم +5 «كانت 5 صارت 0»', () {
      final r = _moves(0, const [('2026-11-02T10:00:00.000', -5)]);
      expect([for (final m in r) m['q']], [-5, 5]);
      expect(r[1]['note'], 'تعديل الفاتورة رقم 1050: كانت 5 صارت 0 — أحمد');
      expect(_sum(r), 0);
    });

    test('أُضيفت المادة بالتعديل: لا بيع أصلي، حركة تعديل واحدة «كانت 0 صارت 6»', () {
      final r = _moves(6, const [('2026-11-02T10:00:00.000', 6)]);
      expect(r, hasLength(1));
      expect(r.single['q'], -6);
      expect(r.single['note'], 'تعديل الفاتورة رقم 1050: كانت 0 صارت 6 — أحمد');
    });

    test('كسور الكمية (متر): 2.5 ← 1.75 بلا أخطاء تقريب', () {
      final r = _moves(1.75, const [('2026-11-02T10:00:00.000', -0.75)]);
      expect([for (final m in r) m['q']], [-2.5, 0.75]);
      expect(r[1]['note'], 'تعديل الفاتورة رقم 1050: كانت 2.5 صارت 1.75 — أحمد');
      expect(_sum(r), closeTo(-1.75, 1e-9));
    });

    test('بلا اسم عميل: لا شَرطة معلّقة', () {
      expect(_moves(3, const [], customer: '  ').single['note'], 'فاتورة رقم 1050');
    });
  });

  group('baseQtyOf', () {
    const json = '[{"product_id":12,"qi":3,"ql":0,"uilu":24},'
        '{"product_id":12,"qi":0,"ql":2,"uilu":24},'
        '{"product_id":123,"qi":9,"ql":0,"uilu":0},'
        '{"product_id":12,"qi":0,"ql":1.5,"uilu":0}]';

    test('القطعة كما هي، والكرتون × محتواه، ومحتوى صفر = 1', () {
      expect(InventoryReports.baseQtyOf(json, 12), 3 + 48 + 1.5);
    });

    test('مادة رقمها يبدأ بالرقم نفسه (123 ≠ 12) لا تختلط', () {
      expect(InventoryReports.baseQtyOf(json, 123), 9);
      expect(InventoryReports.baseQtyOf(json, 1), 0);
    });

    test('لقطة فارغة أو تالفة = صفر لا استثناء', () {
      expect(InventoryReports.baseQtyOf(null, 12), 0);
      expect(InventoryReports.baseQtyOf('', 12), 0);
      expect(InventoryReports.baseQtyOf('[]', 12), 0);
      expect(InventoryReports.baseQtyOf('{bad', 12), 0);
    });
  });

  group('saleMomentOf', () {
    test('تاريخ مختار من التقويم في يوم الحفظ نفسه ⇒ وقت الحفظ', () {
      expect(InventoryReports.saleMomentOf('2026-11-12T00:00:00.000', '2026-11-12T15:20:00.000'),
          '2026-11-12T15:20:00.000');
    });

    test('فاتورة بتاريخ سابق ⇒ تاريخ الفاتورة', () {
      expect(InventoryReports.saleMomentOf('2026-11-01T00:00:00.000', '2026-11-12T15:20:00.000'),
          '2026-11-01T00:00:00.000');
    });

    test('وقت حفظ مفقود ⇒ تاريخ الفاتورة', () {
      expect(InventoryReports.saleMomentOf('2026-11-01T00:00:00.000', ''), '2026-11-01T00:00:00.000');
    });
  });

  group('ProductCard', () {
    test('آخر رصيد = الكمية المسجّلة ⇒ مطابق', () {
      const c = ProductCard(rows: [], storedQty: 110, ledgerQty: 110);
      expect(c.matches, isTrue);
      expect(c.unexplained, 0);
    });

    test('فرق 5 ⇒ تنبيه صريح بالأرقام', () {
      const c = ProductCard(rows: [], storedQty: 115, ledgerQty: 110);
      expect(c.matches, isFalse);
      expect(c.unexplained, 5);
      expect(c.mismatchText, contains('115'));
      expect(c.mismatchText, contains('110'));
      expect(c.mismatchText, contains('فرق 5'));
    });
  });
}
