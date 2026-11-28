// test/services/customer_claim_key_test.dart
//
// 🔒 حجز اسم العميل بين الأجهزة: مفتاح الحجز = هوية الحساب (الاسم بلا مسافات).
// كان المفتاح يدمج المسافات فقط، فـ«جهاد عبد الناصر» و«جهاد عبدالناصر» — حساب واحد —
// يُحجزان بمفتاحين، ويكتب جهازان فاتورتين للحساب نفسه في اللحظة نفسها.

import 'package:alnaser/services/database/business/customer_locking.dart';
import 'package:alnaser/services/database/business/customer_name_rule.dart';
import 'package:alnaser/services/database/business/invoice_customer_claim.dart';
import 'package:flutter_test/flutter_test.dart';

int k(String s) => InvoiceCustomerClaim.keyOf(InvoiceCustomerClaim.normalize(s));

void main() {
  test('كل كتابات الحساب الواحد ⇒ حجز واحد', () {
    final a = k('جهاد عبد الناصر');
    expect(k('جهاد عبدالناصر'), a);
    expect(k('جهاد          عبد الناصر'), a);
    expect(k('  جهاد\tعبد الناصر‏ '), a);
  });

  test('مفتاح الحجز يطابق هوية الحساب في سجل الديون', () {
    for (final n in ['جهاد عبد الناصر', 'جهادعبدالناصر', 'Ali  Hasan']) {
      expect(InvoiceCustomerClaim.normalize(n), CustomerNameRule.key(n).toLowerCase());
    }
  });

  test('حسابان مختلفان ⇒ حجزان مختلفان', () {
    expect(k('جهاد عبد الناصر') == k('جهاد عبد الله'), isFalse);
  });

  test('الأحرف الكبيرة والصغيرة لا تفرّق', () {
    expect(k('Ali Hasan'), k('ali hasan'));
  });

  group('الحجز الفعلي بكود البرنامج (جدول أقفال مشترك وهمي)', () {
    test('جهازان: الثاني يُمنع بأي كتابة للحساب نفسه، ويُسمح بعد التحرير', () async {
      final table = <int, String>{};
      final a = InvoiceCustomerClaim(_FakeLocks('ipad', table));
      final b = InvoiceCustomerClaim(_FakeLocks('pc', table));
      expect(await a.claim('جهاد عبد الناصر'), isNull);
      expect(await b.claim('جهاد عبدالناصر'), isNotNull);
      await a.release();
      expect(await b.claim('جهاد عبدالناصر'), isNull);
      await b.release();
      expect(table, isEmpty);
    });

    test('جهاز قديم حجز الاسم بمفتاحه القديم ⇒ الجديد يُمنع أيضاً', () async {
      final table = <int, String>{};
      // النسخة السابقة: المفتاح = الاسم بمسافة واحدة
      table[InvoiceCustomerClaim.keyOf(InvoiceCustomerClaim.legacyNormalize('جهاد عبد الناصر'))] = 'old-tablet';
      final b = InvoiceCustomerClaim(_FakeLocks('pc', table));
      expect(await b.claim('جهاد عبد الناصر'), isNotNull);
      // ولم يبقَ له حجز معلّق بعد الرفض
      expect(table.values.where((v) => v == 'pc'), isEmpty);
    });

    test('شاشتان على الجهاز نفسه (كاشير + فاتورة) ⇒ الثانية تُمنع', () async {
      final table = <int, String>{};
      final pos = InvoiceCustomerClaim(_FakeLocks('pc', table));
      final inv = InvoiceCustomerClaim(_FakeLocks('pc', table));
      expect(await pos.claim('جهاد عبد الناصر'), isNull);
      final msg = await inv.claim('جهاد   عبد الناصر');
      expect(msg, contains('على هذا الجهاز'));
      await pos.release();
      expect(await inv.claim('جهاد عبد الناصر'), isNull);
      await inv.release();
    });

    test('تغيير الاسم يحرر الحجز السابق', () async {
      final table = <int, String>{};
      final a = InvoiceCustomerClaim(_FakeLocks('ipad', table));
      final b = InvoiceCustomerClaim(_FakeLocks('pc', table));
      expect(await a.claim('علي حسن'), isNull);
      expect(await a.claim('محمد كاظم'), isNull);
      expect(await b.claim('علي حسن'), isNull);
      await a.release();
      await b.release();
    });
  });
}

/// جدول أقفال مشترك في الذاكرة: يمنع جهازاً آخر، ويسمح للجهاز نفسه (كجدول resource_locks)
class _FakeLocks implements LockService {
  _FakeLocks(this.device, this.table);
  final String device;
  final Map<int, String> table;

  @override
  Future<LockResult> acquireLock({required String resourceType, required int resourceId}) async {
    final owner = table[resourceId];
    if (owner != null && owner != device) return LockResult(success: false, lockedBy: owner);
    table[resourceId] = device;
    return LockResult(success: true);
  }

  @override
  Future<void> releaseLock({required String resourceType, required int resourceId}) async {
    if (table[resourceId] == device) table.remove(resourceId);
  }

  @override
  Future<bool> keepAlive({required String resourceType, required int resourceId}) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
