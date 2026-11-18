// test/invoice_designer/print_date_test.dart
//
// 📅 تاريخ الطباعة في مصمم الفاتورة، وحدود مساحة الطباعة للإيصال — بكود البرنامج نفسه.
// التشغيل: flutter test test/invoice_designer/print_date_test.dart

import 'package:alnaser/invoice_designer/invoice_layout.dart';
import 'package:alnaser/invoice_designer/invoice_print_data.dart';
import 'package:alnaser/invoice_designer/layout_canvas.dart' show rollMarginMm;
import 'package:alnaser/services/receipt_paper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('تاريخ الطباعة = يوم الطباعة، لا تاريخ الفاتورة', () {
    final created = DateTime(2026, 1, 3, 9, 30);
    final d = InvoicePrintData(
      company: const PrintCompany(name: 'الاختبار'),
      fields: {'date': InvoicePrintData.dateText(created), 'invoiceNo': '15'},
      rows: const [],
      totals: const {'net': 1000.0},
    );
    final today = InvoicePrintData.dateText(DateTime.now());
    expect(d.field('printedDate'), today);
    expect(d.field('printedAt'), startsWith(today));
    expect(d.field('date'), '03-01-2026'); // تاريخ الفاتورة كما هو
    expect(LayoutCatalog.fields['printedDate'], 'تاريخ الطباعة');
  });

  test('هامش الإيصال في المصمم = (عرض الورق − مساحة الطباعة) ÷ 2', () {
    expect(LayoutPaper.roll80.widthMm - 2 * rollMarginMm(LayoutPaper.roll80), ReceiptPaper.printableMm(80));
    expect(LayoutPaper.roll58.widthMm - 2 * rollMarginMm(LayoutPaper.roll58), ReceiptPaper.printableMm(58));
    expect(rollMarginMm(LayoutPaper.a4), 0);
  });
}
