// test/models/invoice_item_uid_test.dart
//
// 🔑 مفاتيح أسطر الفاتورة: كانت «item_<الوقت بالميكروثانية>» فتتكرر لكل أسطر إيصال الكاشير
// (ساعة Windows أخشن من الميكروثانية) ⇒ صفوف مكررة المفتاح في شاشة الفاتورة.

import 'package:alnaser/models/invoice_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مفاتيح متتالية في اللحظة نفسها لا تتكرر', () {
    final ids = {for (var i = 0; i < 1000; i++) InvoiceItem.newUid()};
    expect(ids.length, 1000);
  });

  test('صفوف قديمة بمفتاح واحد ⇒ مفتاح فريد لكل سطر، والمبالغ كما هي', () {
    final rows = <Map<String, dynamic>>[
      {'id': 1, 'unique_id': 'item_1795442407938793', 'item_total': 1.0},
      {'id': 2, 'unique_id': 'item_1795442407938793', 'item_total': 300.0},
      {'id': 3, 'unique_id': 'item_1795442407938793', 'item_total': 1.0},
      {'id': 4, 'unique_id': null, 'item_total': 2.0},
    ];
    final out = InvoiceItem.uniqueRowIds(rows);
    expect(out.map((r) => r['unique_id']).toSet().length, 4);
    expect(out.first['unique_id'], 'item_1795442407938793'); // الأول يبقى
    expect(out.map((r) => r['item_total']).toList(), [1.0, 300.0, 1.0, 2.0]);
    expect(out.map((r) => r['id']).toList(), [1, 2, 3, 4]);
  });
}
