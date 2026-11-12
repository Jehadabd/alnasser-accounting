// test/erp/delivery_edit_test.dart
//
// 🚚 تعديل طلب توصيل (DeliveryStore.saveOrder بطلب له معرّف): يُعدَّل قبل التسوية، ويُرفض
// بعدها فلا تتغيّر أرقام تسوية دُفعت. على قاعدة في الذاكرة بكود التطبيق نفسه.
// التشغيل: claude_test_gaps.bat

import 'package:alnaser/erp/delivery/delivery_models.dart';
import 'package:alnaser/erp/delivery/delivery_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('🚚 تعديل طلب التوصيل: مسموح قبل التسوية، مرفوض بعدها', () async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    addTearDown(db.close);
    await DeliveryStore.ensureSchema(db);
    final s = DeliveryStore(db: () async => db);
    final cid = await s.saveCompany(DeliveryCompany(name: 'شركة التعديل', defaultFeeFils: 500000));
    final created = DateTime(2026, 11, 1, 10);
    DeliveryOrder order({int? id, required int cod, String phone = ''}) => DeliveryOrder(
        id: id, companyId: cid, customerName: 'زبون التوصيل', phone: phone, codFils: cod, feeFils: 500000, createdAt: created);
    Future<DeliveryOrder> byId(int id) async => (await s.orders(companyId: cid)).firstWhere((o) => o.id == id);

    final id = await s.saveOrder(order(cod: 5000000));

    // تعديل قبل التسوية: المبلغ والهاتف يتغيّران، ولا يُنشأ طلب ثانٍ
    expect(await s.saveOrder(order(id: id, cod: 7000000, phone: '0770')), id);
    var o = await byId(id);
    expect(o.codFils, 7000000);
    expect(o.phone, '0770');
    expect((await s.orders(companyId: cid)).length, 1);

    // مبالغ سالبة واسم فارغ مرفوضة ولا تغيّر شيئاً
    await expectLater(s.saveOrder(order(id: id, cod: -1)), throwsA(anything));
    expect((await byId(id)).codFils, 7000000);

    // التسوية: صافي 7,000,000 − 500,000
    await s.setStatus(o, DeliveryStatus.out);
    o = await byId(id);
    await s.setStatus(o, DeliveryStatus.delivered);
    final st = await s.settle(cid);
    expect(st.balance.netFils, 6500000);

    // بعد التسوية: التعديل مرفوض والأرقام كما سُوّيت
    await expectLater(s.saveOrder(order(id: id, cod: 9000000)), throwsA(anything));
    o = await byId(id);
    expect(o.codFils, 7000000);
    expect(o.settled, isTrue);
    final rows = await s.settlements(cid);
    expect(rows.single['net_fils'], 6500000);
  });
}
