import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/report_search_engine.dart';

String top(String q) => ReportCatalog.match(ReportQuery.parse(q, now: DateTime(2026, 11, 23))).first.id;

void main() {
  group('توحيد الكتابة', () {
    test('همزات وتاء مربوطة وتشكيل وأرقام هندية', () {
      expect(ArabicNorm.normalize('الأرباحُ'), 'الارباح');
      expect(ArabicNorm.normalize('صيانة'), 'صيانه');
      expect(ArabicNorm.normalize('٢٠٢٥'), '2025');
      expect(ArabicNorm.normalize('مستشفى'), 'مستشفي');
    });
    test('الجذع: «الأرباح» و«أرباح» شيء واحد', () {
      expect(ArabicNorm.wordMatch('الارباح', 'ارباح'), 3);
      expect(ArabicNorm.wordMatch('مرتجعات', 'مرتجع') > 0, isTrue);
    });
  });

  group('الفترة من الكلام', () {
    final now = DateTime(2026, 11, 23);
    test('سنة صريحة', () {
      final q = ReportQuery.parse('الربح 2025', now: now);
      expect(q.period!.from, DateTime(2025, 1, 1));
      expect(q.period!.to, DateTime(2025, 12, 31));
      expect(q.period!.year, 2025);
      expect(q.words, ['الربح']);
    });
    test('هذه السنة لا تتجاوز اليوم', () {
      final q = ReportQuery.parse('مبيعات هذه السنة', now: now);
      expect(q.period!.from, DateTime(2026, 1, 1));
      expect(q.period!.to, DateTime(2026, 11, 23));
    });
    test('الشهر الماضي', () {
      final q = ReportQuery.parse('كم بعت الشهر الماضي', now: now);
      expect(q.period!.from, DateTime(2026, 10, 1));
      expect(q.period!.to, DateTime(2026, 10, 31));
      expect(q.words, ['بعت']);
    });
    test('اسم شهر مع سنة', () {
      final q = ReportQuery.parse('مرتجعات شباط 2024', now: now);
      expect(q.period!.from, DateTime(2024, 2, 1));
      expect(q.period!.to, DateTime(2024, 2, 29));
    });
    test('اسم شهر قادم بلا سنة ← السنة الماضية', () {
      final q = ReportQuery.parse('ديسمبر', now: now);
      expect(q.period!.from, DateTime(2025, 12, 1));
    });
    test('أمس', () {
      final q = ReportQuery.parse('مبيعات امس', now: now);
      expect(q.period!.from, DateTime(2026, 11, 22));
    });
    test('رقم ليس سنة يبقى رقماً (فاتورة/باركود)', () {
      final q = ReportQuery.parse('1532', now: now);
      expect(q.period, isNull);
      expect(q.numbers, ['1532']);
    });
  });

  group('المعنى لا الكلمة الحرفية', () {
    test('سند قبض', () => expect(top('سند قبض'), 'vouchers_receipt'));
    test('سندات القبض', () => expect(top('سندات القبض'), 'vouchers_receipt'));
    test('الضمان ← مرتجعات الضمان', () => expect(top('الضمان'), 'warranty_returns'));
    test('أثر الدولار', () => expect(top('أثر الدولار'), 'usd'));
    test('سعر الصرف', () => expect(top('سعر الصرف'), 'usd'));
    test('الأرباح / كم ربحت / خسائر', () {
      expect(top('الأرباح'), 'profit');
      expect(top('كم ربحت'), 'profit');
      expect(top('خساير'), 'profit'); // خطأ حرف
    });
    test('كم بعت', () => expect(top('كم بعت'), 'sales'));
    test('مقارنة', () => expect(top('مقارنة'), 'compare'));
    test('مسحوبات المالك', () => expect(top('مسحوبات المالك'), 'drawings'));
    test('المرتجعات', () => expect(top('المرتجعات'), 'returns'));
    test('المواد الراكدة', () => expect(top('المواد الراكدة'), 'stagnant'));
    test('الكهرباء ← المصاريف', () => expect(top('الكهرباء'), 'expenses'));
    test('الموظفين', () => expect(top('الموظفين'), 'employees'));
  });

  group('الأسماء', () {
    test('جزء من الاسم وخطأ حرف', () {
      expect(ReportCatalog.nameScore(['احمد'], 'أحمد علي') > 0, isTrue);
      expect(ReportCatalog.nameScore(['كاسيو'], 'ساعة كاسيو رجالي') > 0, isTrue);
      expect(ReportCatalog.nameScore(['محمود'], 'أحمد علي'), 0);
    });
    test('كلمة المعنى تُفصل عن الاسم', () {
      expect(ReportCatalog.isConcept('الربح'), isTrue);
      expect(ReportCatalog.isConcept('احمد'), isFalse);
    });
  });
}
