// test/services/return_name_rtl_test.dart
//
// p246 — بكود البرنامج نفسه:
//   1) المرتجع من فاتورة يبدأ كلياً بالمتبقي، ولا يتجاوز ما بيع ولا ما بقي.
//   2) تنظيف اسم العميل: تعدد المسافات/Tab/مسافة اللصق/علامات الاتجاه ⇐ مسافة واحدة.
//   3) جداول PDF: العمود الأول يُرسم أقصى اليمين، والصف الناقص لا تنزاح أعمدته.

import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/erp/sales/return_prefill.dart';
import 'package:alnaser/services/customer_name_clean.dart';
import 'package:alnaser/services/database/business/customer_name_rule.dart';
import 'package:alnaser/services/name_search.dart';
import 'package:alnaser/services/pdf_rtl.dart';

void main() {
  group('المرتجع الكلي الافتراضي', () {
    test('فاتورة بمادة واحدة لم يُرجع منها شيء ⇒ كل الكمية', () {
      final q = fullReturnQuantities(
        [const ReturnPrefillLine(productId: 1, soldBase: 5, factor: 1)],
        {1: 5},
      );
      expect(q, [5]);
    });

    test('أُرجع منها سابقاً ⇒ المتبقي فقط', () {
      final q = fullReturnQuantities(
        [const ReturnPrefillLine(productId: 1, soldBase: 5, factor: 1)],
        {1: 2},
      );
      expect(q, [2]);
    });

    test('أُرجعت كاملة ⇒ صفر (لا شيء يُرجع)', () {
      final q = fullReturnQuantities(
        [const ReturnPrefillLine(productId: 1, soldBase: 5, factor: 1)],
        {1: 0},
      );
      expect(q, [0]);
    });

    test('كرتون + قطع للمادة نفسها: لا يتجاوز المجموع المتبقي', () {
      // بيع 1 كرتون (12) + 5 قطع = 17، أُرجعت 3 قطع ⇒ المتبقي 14
      final q = fullReturnQuantities([
        const ReturnPrefillLine(productId: 7, soldBase: 12, factor: 12),
        const ReturnPrefillLine(productId: 7, soldBase: 5, factor: 1),
      ], {7: 14});
      expect(q, [1, 2]);
      expect(q[0] * 12 + q[1] * 1, 14);
    });

    test('كسر كرتون لا يُخمَّن: يبقى للمستخدم', () {
      // المتبقي 9 قطع وسطر بالكرتون (12) ⇒ لا يُكتب 0.75 كرتون
      final q = fullReturnQuantities(
        [const ReturnPrefillLine(productId: 7, soldBase: 12, factor: 12)],
        {7: 9},
      );
      expect(q, [0]);
    });

    test('كمية كسرية بالوحدة الأساسية (متر/كيلو) تبقى كما هي', () {
      final q = fullReturnQuantities(
        [const ReturnPrefillLine(productId: 3, soldBase: 2.5, factor: 1)],
        {3: 2.5},
      );
      expect(q, [2.5]);
    });

    test('مادة غير موجودة في المتبقي ⇒ صفر', () {
      final q = fullReturnQuantities(
        [const ReturnPrefillLine(productId: 9, soldBase: 4, factor: 1)],
        const {},
      );
      expect(q, [0]);
    });
  });

  group('تنظيف اسم العميل', () {
    test('عشر مسافات ⇐ مسافة واحدة', () {
      expect(CustomerNameClean.clean('جهاد          عبد الناصر'), 'جهاد عبد الناصر');
    });

    test('Tab ومسافة اللصق وعلامات الاتجاه والأطراف', () {
      expect(CustomerNameClean.clean('  جهاد\t عبد‏ الناصر‎  '), 'جهاد عبد الناصر');
    });

    test('لا يغيّر حرفاً ظاهراً', () {
      expect(CustomerNameClean.clean('أبو مصطفى / بيه'), 'أبو مصطفى / بيه');
    });

    test('بعد التنظيف: نفس الحساب حسب قاعدة سجل الديون', () {
      final a = CustomerNameRule.key(CustomerNameClean.clean('جهاد\t\t عبد الناصر'));
      expect(a, CustomerNameRule.key('جهاد عبد الناصر'));
      expect(a, CustomerNameRule.key('جهادعبدالناصر'));
    });

    test('اقتراح العملاء في الكاشير يتجاهل عدد المسافات', () {
      expect(NameSearch.matches('جهاد عبد الناصر', 'جهاد          عبد'), isTrue);
      expect(NameSearch.matches('جهاد عبد الناصر', 'جهادعبد'), isTrue);
      expect(NameSearch.matches('جهاد عبد الناصر', 'محمد'), isFalse);
    });
  });

  group('جداول PDF من اليمين', () {
    test('الصف يُعكس: الأول يُرسم أقصى اليمين', () {
      expect(PdfRtl.row(['#', 'المادة', 'الإجمالي']), ['الإجمالي', 'المادة', '#']);
    });

    test('صف ناقص يُكمَّل قبل العكس', () {
      expect(PdfRtl.rows([
        ['1', 'أ', '100'],
        ['المجموع'],
      ], 3), [
        ['100', 'أ', '1'],
        ['', '', 'المجموع'],
      ]);
    });

    test('أرقام الأعمدة تُعكس', () {
      expect(PdfRtl.columns({0: 'a', 2: 'c'}, 3), {2: 'a', 0: 'c'});
    });
  });
}
