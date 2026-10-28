// test/invoice_entry_layout_test.dart
//
// 🧭 مسار زر Enter في جدول «إنشاء فاتورة»: الترتيب الافتراضي، التنظيف، الأعمدة
// المخفية، والحفظ/التحميل (بما فيه الإعدادات القديمة بلا ترتيب).
// التشغيل: flutter test test/invoice_entry_layout_test.dart

import 'dart:convert';

import 'package:alnaser/models/invoice_entry_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('الافتراضي = السلوك القديم: الكمية ← الوحدة ← السعر', () {
    final l = InvoiceEntryLayout();
    expect(l.enterOrder, ['qty', 'saleType', 'price']);
    expect(l.discountTypedAsPercent, isTrue);
  });

  test('التنظيف: يحذف المجهول والمكرر ويحفظ الترتيب', () {
    expect(InvoiceEntryLayout.cleanEnterOrder(['price', 'x', 'qty', 'price', 'total', 'discount']),
        ['price', 'qty', 'discount']);
  });

  test('المسار يبدأ باسم المادة ويتخطى العمود المخفي', () {
    final l = InvoiceEntryLayout(enterOrder: ['qty', 'discount', 'price']);
    expect(l.enterStops(['details', 'qty', 'saleType', 'price', 'discount', 'total']),
        ['details', 'qty', 'discount', 'price']);
    // عمود الخصم مخفي ⇒ لا يقف عنده
    expect(l.enterStops(['details', 'qty', 'saleType', 'price', 'total']), ['details', 'qty', 'price']);
  });

  test('مسار فارغ: اسم المادة فقط ثم السطر التالي', () {
    final l = InvoiceEntryLayout(enterOrder: const []);
    expect(l.enterStops(['details', 'qty', 'price']), ['details']);
  });

  test('copyWith يحفظ الترتيب ونوع الخصم', () {
    final l = InvoiceEntryLayout(enterOrder: ['price', 'qty'], discountTypedAsPercent: false);
    final c = l.copyWith(rowHeight: 42);
    expect(c.enterOrder, ['price', 'qty']);
    expect(c.discountTypedAsPercent, isFalse);
  });

  test('حفظ ثم تحميل: الترتيب (حتى الفارغ) ونوع الخصم', () async {
    SharedPreferences.setMockInitialValues({});
    await InvoiceEntryLayout(enterOrder: const [], discountTypedAsPercent: false).save();
    final a = await InvoiceEntryLayout.load();
    expect(a.enterOrder, isEmpty);
    expect(a.discountTypedAsPercent, isFalse);

    await InvoiceEntryLayout(enterOrder: ['qty', 'price', 'saleType', 'discount']).save();
    final b = await InvoiceEntryLayout.load();
    expect(b.enterOrder, ['qty', 'price', 'saleType', 'discount']);
  });

  test('إعدادات قديمة بلا enterOrder ⇒ الترتيب الافتراضي', () async {
    SharedPreferences.setMockInitialValues({
      'invoice_entry_layout_v2': jsonEncode({
        'widths': {'details': 300},
        'hidden': ['code'],
        'rowHeight': 30,
        'showEntryBar': false,
      }),
    });
    final l = await InvoiceEntryLayout.load();
    expect(l.enterOrder, ['qty', 'saleType', 'price']);
    expect(l.discountTypedAsPercent, isTrue);
    expect(l.showEntryBar, isFalse);
  });
}
