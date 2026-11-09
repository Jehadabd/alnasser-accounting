import 'package:alnaser/owner/wa_auto/wa_auto_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

WaAutoSettings _s(int day, {int hour = -1}) => WaAutoSettings(
    enabled: true, riskAccepted: true, minDebt: 0, day: day, template: '', minDelay: 30, maxDelay: 90,
    maxPerDay: 100, autoStart: true, loadWait: 4, onlySelected: true, selected: const {}, hour: hour, refocus: true);

void main() {
  test('phone numbers become international without +', () {
    expect(WaAutoReminder.normalizePhone('0770 123 4567'), '9647701234567');
    expect(WaAutoReminder.normalizePhone('+964 770 123 4567'), '9647701234567');
    expect(WaAutoReminder.normalizePhone('00964-770-123-4567'), '9647701234567');
    expect(WaAutoReminder.normalizePhone('7701234567'), '9647701234567');
    expect(WaAutoReminder.normalizePhone('123'), isNull);
    expect(WaAutoReminder.normalizePhone(''), isNull);
  });

  test('message has name, whole-dinar amount and shop', () {
    final t = WaTarget(id: 4, name: 'أحمد', phone: '9647701234567', debt: 125000.4);
    final m = WaAutoReminder.render('السيد {الاسم} عليك {المبلغ} — {المحل}', t, 'محل الناصر');
    expect(m, contains('أحمد'));
    expect(m, contains('125,000'));
    expect(m, isNot(contains('.4')));
    expect(m, contains('محل الناصر'));
  });

  test('due day: last day of month or from the chosen day', () {
    expect(WaAutoReminder.isDueDay(_s(0), DateTime(2026, 2, 28)), isTrue);
    expect(WaAutoReminder.isDueDay(_s(0), DateTime(2026, 2, 27)), isFalse);
    expect(WaAutoReminder.isDueDay(_s(0), DateTime(2026, 11, 30)), isTrue);
    expect(WaAutoReminder.isDueDay(_s(25), DateTime(2026, 11, 26)), isTrue);
    expect(WaAutoReminder.isDueDay(_s(25), DateTime(2026, 11, 24)), isFalse);
  });

  test('due now waits for the chosen hour', () {
    expect(WaAutoReminder.isDueNow(_s(25, hour: 22), DateTime(2026, 11, 26, 21, 59)), isFalse);
    expect(WaAutoReminder.isDueNow(_s(25, hour: 22), DateTime(2026, 11, 26, 22, 0)), isTrue);
    expect(WaAutoReminder.isDueNow(_s(25), DateTime(2026, 11, 26, 8)), isTrue);
  });

  group('التأخر عن التسديد', () {
    final now = DateTime(2026, 11, 9);
    DateTime d(int y, int m, int day) => DateTime(y, m, day);

    test('أشهر كاملة', () {
      expect(WaAutoReminder.monthsBetween(d(2026, 8, 9), now), 3);
      expect(WaAutoReminder.monthsBetween(d(2026, 8, 10), now), 2);
      expect(WaAutoReminder.monthsBetween(d(2026, 12, 1), now), 0);
    });

    test('منذ آخر تسديد على الدين القائم', () {
      final late = WaAutoReminder.lateFrom([
        (1, d(2026, 1, 1), 100000.0, 'manual_debt'),
        (1, d(2026, 6, 5), -20000.0, 'manual_payment'), // آخر تسديد
        (1, d(2026, 10, 1), 5000.0, 'invoice_debt_sync'),
      ], now);
      expect(late[1], 5);
    });

    test('لم يسدّد أبداً: منذ أول دين', () {
      final late = WaAutoReminder.lateFrom([(2, d(2026, 7, 1), 50000.0, 'manual_debt')], now);
      expect(late[2], 4);
    });

    test('سدّد كل دينه ثم استدان من جديد: يُحسب من الدين الجديد', () {
      final late = WaAutoReminder.lateFrom([
        (3, d(2025, 1, 1), 10000.0, 'manual_debt'),
        (3, d(2025, 2, 1), -10000.0, 'manual_payment'),
        (3, d(2026, 11, 1), 7000.0, 'manual_debt'),
      ], now);
      expect(late[3], 0);
    });

    test('من رصيده صفر لا يظهر', () {
      final late = WaAutoReminder.lateFrom([
        (4, d(2026, 1, 1), 10000.0, 'manual_debt'),
        (4, d(2026, 2, 1), -10000.0, 'manual_payment'),
      ], now);
      expect(late.containsKey(4), isFalse);
    });
  });
}
