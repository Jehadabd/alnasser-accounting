import 'package:alnaser/owner/wa_auto/wa_auto_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

WaAutoSettings _s(int day) => WaAutoSettings(
    enabled: true, riskAccepted: true, minDebt: 0, day: day, template: '', minDelay: 30, maxDelay: 90,
    maxPerDay: 100, autoStart: true, loadWait: 4);

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
}
