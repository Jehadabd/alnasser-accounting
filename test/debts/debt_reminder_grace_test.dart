// test/debts/debt_reminder_grace_test.dart
//
// 💸 «من سدّد مؤخراً لا يُطالَب» + 🔤 البحث بلا فواصل.
// التشغيل: flutter test test/debts/debt_reminder_grace_test.dart

import 'package:alnaser/services/debt_reminders.dart';
import 'package:alnaser/services/name_search.dart';
import 'package:flutter_test/flutter_test.dart';

DebtReminder _rem(List<int> days, {int? grace}) =>
    DebtReminder(days: days, startYear: 2026, startMonth: 1, repeat: 'monthly', graceDays: grace);

void main() {
  group('بداية أيام المطالبة', () {
    test('الأيام 1–5: كل يوم منها يبدأ من 1', () {
      final r = _rem([1, 2, 3, 4, 5]);
      for (var d = 1; d <= 5; d++) {
        expect(r.windowStart(DateTime(2026, 3, d)), DateTime(2026, 3, 1));
      }
      expect(r.windowStart(DateTime(2026, 3, 6)), isNull);
    });

    test('أيام متفرقة: 1،2،15،16 ⇒ يوم 16 يبدأ من 15', () {
      final r = _rem([1, 2, 15, 16]);
      expect(r.windowStart(DateTime(2026, 3, 16)), DateTime(2026, 3, 15));
      expect(r.windowStart(DateTime(2026, 3, 2)), DateTime(2026, 3, 1));
    });
  });

  group('من سدّد مؤخراً', () {
    final r = _rem([1, 2, 3, 4, 5]);
    final day3 = DateTime(2026, 3, 3, 10);

    test('مهلة 10 أيام: تسديد يوم 19 شباط (قبل البداية بـ10) يستثنيه', () {
      // 1 آذار − 10 = 19 شباط (شباط 2026 = 28 يوماً)
      expect(r.paidRecently(DateTime(2026, 2, 19, 23), day3, 10), isTrue);
      expect(r.paidRecently(DateTime(2026, 2, 18, 9), day3, 10), isFalse);
    });

    test('تسديد أثناء أيام المطالبة يستثنيه حتى بمهلة 0', () {
      expect(r.paidRecently(DateTime(2026, 3, 2), day3, 0), isTrue);
      expect(r.paidRecently(DateTime(2026, 2, 28), day3, 0), isFalse);
    });

    test('مهلة شهر (30 يوماً)', () {
      expect(r.paidRecently(DateTime(2026, 1, 30), day3, 30), isTrue); // 1 آذار − 30 = 30 كانون الثاني
      expect(r.paidRecently(DateTime(2026, 1, 29), day3, 30), isFalse);
    });

    test('لا استثناء (-1) أو لم يسدّد أبداً ⇒ يُطالَب', () {
      expect(r.paidRecently(DateTime(2026, 3, 2), day3, -1), isFalse);
      expect(r.paidRecently(null, day3, 30), isFalse);
    });

    test('ليس يوم مطالبة ⇒ لا معنى للاستثناء', () {
      expect(r.paidRecently(DateTime(2026, 3, 7), DateTime(2026, 3, 8), 10), isFalse);
    });

    test('المهلة تُحفظ مع الموعد وتعود كما هي', () {
      final m = _rem([1, 2], grace: 30).toMap();
      expect(m['paid_grace_days'], 30);
      final back = DebtReminder.fromMap({...m, 'id': 1}, const []);
      expect(back.graceDays, 30);
      expect(DebtReminder.fromMap({..._rem([1]).toMap(), 'id': 2}, const []).graceDays, isNull);
    });
  });

  group('البحث بلا فواصل', () {
    test('المسافات والشَّرطات لا قيمة لها', () {
      for (final q in ['جهاد عبد', 'جهادعبد', 'جهاد          عبد', 'جهاد-عبد', 'جهاد_عبد', ' جهاد . عبد ']) {
        expect(NameSearch.matches('جهاد عبد الله', q), isTrue, reason: q);
      }
      expect(NameSearch.matches('جهادعبدالله', 'جهاد عبد'), isTrue);
    });

    test('الهمزات والتاء المربوطة', () {
      expect(NameSearch.matches('إبراهيم حمزة', 'ابراهيم حمزه'), isTrue);
    });

    test('كلمة غير موجودة لا تطابق', () {
      expect(NameSearch.matches('جهاد عبد الله', 'جهاد علي'), isFalse);
    });

    test('SQL و Dart بالفواصل نفسها', () {
      final sql = NameSearch.sqlNorm('name');
      for (final s in NameSearch.separators) {
        expect(sql.contains("'$s'"), isTrue, reason: s);
      }
    });
  });
}
