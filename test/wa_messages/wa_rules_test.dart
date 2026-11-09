// اختبارات منطق قواعد رسائل واتساب وتأليف الرسالة (دوال صافية، بلا قاعدة بيانات ولا شبكة).
import 'package:alnaser/owner/wa_auto/wa_auto_reminder.dart';
import 'package:alnaser/screens/statements/statement_engine.dart';
import 'package:alnaser/wa_messages/wa_compose.dart';
import 'package:alnaser/wa_messages/wa_rules.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day, [int h = 12]) => DateTime(y, m, day, h);

WaFacts f(int id, double debt, {DateTime? since}) =>
    WaFacts(id: id, name: 'ع$id', phone: '96477000000$id', debt: debt, since: since);

void main() {
  group('اليوم والساعة', () {
    test('أي يوم', () {
      final r = WaRule(id: 'x', name: 'x', days: [], hour: -1);
      expect(WaRuleEval.isDueNow(r, d(2026, 11, 9, 3)), isTrue);
    });
    test('يوم 5 من الساعة 10', () {
      final r = WaRule(id: 'x', name: 'x', days: [5], hour: 10);
      expect(WaRuleEval.isDueNow(r, d(2026, 11, 5, 9)), isFalse);
      expect(WaRuleEval.isDueNow(r, d(2026, 11, 5, 10)), isTrue);
      expect(WaRuleEval.isDueNow(r, d(2026, 11, 6, 10)), isFalse);
    });
    test('يوم 31 في شهر من 30 يوماً = آخر يوم، و0 = آخر يوم', () {
      final r31 = WaRule(id: 'x', name: 'x', days: [31], hour: -1);
      expect(WaRuleEval.dayMatches(r31, d(2026, 11, 30)), isTrue);
      expect(WaRuleEval.dayMatches(r31, d(2026, 11, 29)), isFalse);
      expect(WaRuleEval.dayMatches(WaRule(id: 'x', name: 'x', days: [0]), d(2026, 2, 28)), isTrue);
      expect(WaRuleEval.dayMatches(WaRule(id: 'x', name: 'x', days: [30]), d(2026, 2, 28)), isTrue);
    });
    test('قاعدة مطفأة لا تستحق', () {
      final r = WaRule(id: 'x', name: 'x', days: [], hour: -1, enabled: false);
      expect(WaRuleEval.isDueNow(r, d(2026, 11, 9)), isFalse);
    });
  });

  group('شرط التأخر — مثال: دين يوم 2026/11/09 و«3 أشهر»', () {
    final r = WaRule(id: 'x', name: 'x', lateValue: 3, lateUnit: 'month');
    final since = d(2026, 11, 9);
    test('قبل 3 أشهر كاملة لا', () => expect(WaRuleEval.lateEnough(r, since, d(2027, 2, 8)), isFalse));
    test('بعد 3 أشهر نعم', () => expect(WaRuleEval.lateEnough(r, since, d(2027, 2, 9)), isTrue));
    test('بالأيام', () {
      final rd = WaRule(id: 'x', name: 'x', lateValue: 60, lateUnit: 'day');
      expect(WaRuleEval.lateEnough(rd, since, since.add(const Duration(days: 59))), isFalse);
      expect(WaRuleEval.lateEnough(rd, since, since.add(const Duration(days: 60))), isTrue);
    });
    test('بلا شرط (0) = كل مدين، وبلا دين قائم = لا', () {
      expect(WaRuleEval.lateEnough(WaRule(id: 'x', name: 'x', lateValue: 0), null, since), isTrue);
      expect(WaRuleEval.lateEnough(r, null, d(2030, 1, 1)), isFalse);
    });
  });

  group('التكرار', () {
    final now = d(2027, 3, 1);
    test('مرة حتى يسدّد: لا تكرار حتى يسدّد، ثم يعود', () {
      final r = WaRule(id: 'x', name: 'x', repeat: WaRepeat.once);
      expect(WaRuleEval.repeatAllows(r, null, d(2026, 11, 9), now), isTrue);
      expect(WaRuleEval.repeatAllows(r, d(2027, 2, 10), d(2026, 11, 9), now), isFalse);
      // سدّد جزءاً في 2027/02/20 بعد الرسالة ⇒ دورة جديدة
      expect(WaRuleEval.repeatAllows(r, d(2027, 2, 10), d(2027, 2, 20), now), isTrue);
    });
    test('مرة كل شهر', () {
      final r = WaRule(id: 'x', name: 'x', repeat: WaRepeat.monthly);
      expect(WaRuleEval.repeatAllows(r, d(2027, 3, 1, 9), null, d(2027, 3, 20)), isFalse);
      expect(WaRuleEval.repeatAllows(r, d(2027, 2, 28), null, d(2027, 3, 1)), isTrue);
    });
    test('كل 10 أيام', () {
      final r = WaRule(id: 'x', name: 'x', repeat: WaRepeat.everyDays, repeatDays: 10);
      expect(WaRuleEval.repeatAllows(r, d(2027, 2, 25), null, d(2027, 3, 6)), isFalse);
      expect(WaRuleEval.repeatAllows(r, d(2027, 2, 25), null, d(2027, 3, 7)), isTrue);
    });
  });

  group('من تصله الرسالة', () {
    final now = d(2027, 3, 1);
    final people = [
      f(1, 500000, since: d(2026, 11, 1)), // متأخر 4 أشهر
      f(2, 100000, since: d(2027, 2, 1)), // شهر واحد
      f(3, 900, since: d(2026, 1, 1)), // دين صغير
      f(4, 300000, since: d(2026, 6, 1)),
    ];
    test('كل المدينين المتأخرين 3 أشهر فوق 1000', () {
      final r = WaRule(id: 'x', name: 'x', lateValue: 3, minDebt: 1000);
      expect(WaRuleEval.select(r, people, lastSent: {}, now: now).map((p) => p.id), [1, 4]);
    });
    test('عملاء مختارون (جهاد وحده)', () {
      final r = WaRule(id: 'x', name: 'x', audience: WaAudience.selected, ids: {4}, lateValue: 3);
      expect(WaRuleEval.select(r, people, lastSent: {}, now: now).map((p) => p.id), [4]);
    });
    test('الكل عدا', () {
      final r = WaRule(id: 'x', name: 'x', audience: WaAudience.except, ids: {1}, lateValue: 0, minDebt: 1);
      expect(WaRuleEval.select(r, people, lastSent: {}, now: now).map((p) => p.id), [2, 3, 4]);
    });
    test('مواعيد المطالبة اليوم', () {
      final r = WaRule(id: 'x', name: 'x', audience: WaAudience.dueReminders, lateValue: 0);
      expect(WaRuleEval.select(r, people, lastSent: {}, dueToday: {2}, now: now).map((p) => p.id), [2]);
    });
    test('من أُرسل له بالقاعدة ولم يسدّد لا تصله ثانية', () {
      final r = WaRule(id: 'x', name: 'x', lateValue: 3);
      expect(WaRuleEval.select(r, people, lastSent: {1: d(2027, 2, 15)}, now: now).map((p) => p.id), [4]);
    });
  });

  test('القاعدة تُحفظ وتُقرأ كما هي', () {
    final r = WaRule(
      id: 'r1',
      name: 'مطالبة',
      audience: WaAudience.selected,
      ids: {3, 1},
      lateValue: 45,
      lateUnit: 'day',
      minDebt: 5000,
      days: [5, 0],
      hour: 21,
      repeat: WaRepeat.everyDays,
      repeatDays: 15,
      auto: false,
      options: const WaMessageOptions(template: 'مرحبا {الاسم}', address: false, attach: WaAttach.pdf),
    );
    final b = WaRule.fromJson(r.toJson());
    expect(b.toJson(), r.toJson());
    expect(b.ids, {1, 3});
    expect(b.options.attach, WaAttach.pdf);
  });

  test('بدء التأخر: من الدين بعد رصيد صفر، ويتقدم مع كل تسديد', () {
    final m = WaAutoReminder.lateSinceFrom([
      (1, d(2026, 1, 1), 100.0, 'manual_debt'),
      (1, d(2026, 2, 1), -100.0, 'manual_payment'), // صفر
      (1, d(2026, 11, 9), 50000.0, 'manual_debt'), // دين جديد اليوم
      (2, d(2026, 5, 1), 1000.0, 'manual_debt'),
      (2, d(2026, 8, 1), -200.0, 'manual_payment'),
      (3, d(2026, 5, 1), 1000.0, 'manual_debt'),
      (3, d(2026, 6, 1), -1000.0, 'manual_payment'), // لا دين قائم
    ]);
    expect(m[1], d(2026, 11, 9));
    expect(m[2], d(2026, 8, 1));
    expect(m.containsKey(3), isFalse);
  });

  group('تأليف الرسالة', () {
    final t = WaTarget(id: 0, name: 'أحمد', phone: '', debt: 125000);
    test('العنوان يُضاف في آخرها إن لم يُكتب {العنوان}', () {
      final s = WaCompose.renderText('عليك {المبلغ}', t, 'محل', address: 'الموصل');
      expect(s.endsWith('📍 العنوان: الموصل'), isTrue);
      expect(s.contains('125,000'), isTrue);
    });
    test('{العنوان} في النص = لا تكرار', () {
      final s = WaCompose.renderText('نحن في {العنوان}', t, 'محل', address: 'الموصل');
      expect('الموصل'.allMatches(s).length, 1);
    });
    test('بلا عنوان = بلا سطر عنوان', () {
      expect(WaCompose.renderText('عليك {المبلغ}', t, 'محل').contains('العنوان'), isFalse);
    });
    test('الكشف النصي: آخر الحركات ضمن الحد، والرصيد في آخره', () {
      final rows = [
        for (var i = 1; i <= 60; i++)
          StmtRow(date: DateTime(2026, 9, 1).add(Duration(days: i)), title: 'فاتورة $i', amount: 1000, kind: StmtKind.invoice),
      ];
      final s = StatementResult(
        customerName: 'أحمد',
        period: const StmtPeriod.sinceZero(),
        detail: StmtDetail.summary,
        fromDate: null,
        toDate: null,
        opening: 0,
        closing: 60000,
        debit: 60000,
        credit: 0,
        rows: rows,
        zeroAt: DateTime(2026, 9, 1),
      );
      final txt = WaCompose.statementText(s, budget: 700);
      expect(txt.length <= 700, isTrue);
      expect(txt.contains('فاتورة 60'), isTrue); // الأحدث موجود
      expect(txt.contains('حركة أقدم'), isTrue);
      expect(txt.trim().endsWith('الرصيد الحالي: 60,000 دينار'), isTrue);
    });
  });
}
