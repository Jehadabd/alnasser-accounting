// ⭐ اسم ملف PDF كما يصل للزبون في واتساب (p172)
import 'package:alnaser/erp/report_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final d = DateTime(2026, 11, 15);

  test('سند من الأرشيف: بلا شرطات ولا رقم نسخة', () {
    expect(ReportExport.shareFileName('سند قبض 12 - أحمد علي_نسخة_2', date: d),
        'سند قبض 12 - أحمد علي - 2026-11-15.pdf');
  });

  test('الأسماء القديمة بالشرطات تصير كلمات', () {
    expect(ReportExport.shareFileName('وصل_قبض_7', date: d), 'وصل قبض 7 - 2026-11-15.pdf');
  });

  test('رموز ممنوعة في أسماء الملفات تُزال', () {
    expect(ReportExport.shareFileName('فاتورة 5 - علي/حسن: "ب"', date: d), 'فاتورة 5 - علي حسن ب - 2026-11-15.pdf');
  });

  test('اسم فارغ', () {
    expect(ReportExport.shareFileName('  ', date: d), 'مستند - 2026-11-15.pdf');
  });

  test('ويندوز: اسم إنجليزي بنوع المستند ورقمه', () {
    expect(ReportExport.latinShareFileName('فاتورة 12026113 - ثثث', date: DateTime(2026, 11, 12)),
        'Invoice 12026113 - 2026-11-12.pdf');
    expect(ReportExport.latinShareFileName('سند قبض 12 - أحمد علي_نسخة_2', date: d),
        'Receipt-Voucher 12 - 2026-11-15.pdf');
    expect(ReportExport.latinShareFileName('كشف_حساب_أحمد', date: d), 'Account-Statement - 2026-11-15.pdf');
    expect(ReportExport.latinShareFileName('ملف غريب', date: d), 'Document - 2026-11-15.pdf');
  });
}
