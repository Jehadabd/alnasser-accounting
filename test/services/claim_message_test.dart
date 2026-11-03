// test/services/claim_message_test.dart

import 'package:alnaser/services/whatsapp/claim_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('نص المطالبة الرسمي', () {
    final t = ClaimMessage.build(
      customerName: ' جهاد عبد ',
      company: 'محل الناصر',
      balance: 250000,
      amount: 100000,
      lastPaid: DateTime(2026, 10, 1),
      invoiceNumber: '1-2026-10-0005',
      today: DateTime(2026, 11, 3),
    );
    expect(t, startsWith('السيد/السيدة جهاد عبد المحترم/المحترمة،'));
    expect(t, contains('المبلغ المستحق في ذمتكم لدى محل الناصر بتاريخ 2026/11/03 هو 100,000 دينار عراقي.'));
    expect(t, contains('الرصيد الكلي لحسابكم 250,000 دينار عراقي'));
    expect(t, contains('بالفاتورة رقم 1-2026-10-0005'));
    expect(t, contains('آخر سداد مسجّل في حسابكم بتاريخ 2026/10/01'));
    expect(t, endsWith('مع فائق التقدير والاحترام\nمحل الناصر'));
  });

  test('بلا مبلغ محدد: كامل الرصيد ولا سطر للرصيد الكلي', () {
    final t = ClaimMessage.build(customerName: 'علي', company: '', balance: 5000, today: DateTime(2026, 1, 1));
    expect(t, contains('في ذمتكم بتاريخ 2026/01/01 هو 5,000 دينار عراقي.'));
    expect(t, isNot(contains('الرصيد الكلي')));
    expect(t, endsWith('مع فائق التقدير والاحترام'));
  });

  test('رقم الهاتف بصيغة دولية', () {
    expect(WhatsAppLink.normalizePhone('0770 123 4567'), '9647701234567');
    expect(WhatsAppLink.normalizePhone('+964 770-123-4567'), '9647701234567');
    expect(WhatsAppLink.normalizePhone('00964 7701234567'), '9647701234567');
    expect(WhatsAppLink.normalizePhone('7701234567'), '9647701234567');
    expect(WhatsAppLink.normalizePhone('12'), isNull);
    expect(WhatsAppLink.normalizePhone(null), isNull);
  });
}
