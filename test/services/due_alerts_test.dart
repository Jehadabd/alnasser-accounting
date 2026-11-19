// test/services/due_alerts_test.dart
//
// 📅 تنبيه الاستحقاقات في نافذة التنبيهات: من يظهر، ومن يُستثنى لأن رسالة واتساب التلقائية
// تصله — بكود البرنامج نفسه على قاعدة في الذاكرة.
// التشغيل: flutter test test/services/due_alerts_test.dart

import 'package:alnaser/services/due_alerts.dart';
import 'package:alnaser/wa_messages/wa_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime(2026, 11, 19, 10);

Future<Database> _db() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, '
      'current_total_debt REAL, is_deleted INTEGER DEFAULT 0)');
  await db.execute('''CREATE TABLE due_items (id INTEGER PRIMARY KEY AUTOINCREMENT, due_no INTEGER, kind TEXT,
      party_type TEXT, party_id INTEGER, party_name TEXT, amount REAL, currency TEXT DEFAULT 'IQD', fx_rate REAL DEFAULT 1,
      issue_date TEXT, due_date TEXT, doc_no TEXT, installment_no INTEGER, installments_total INTEGER,
      status TEXT DEFAULT 'open', paid_amount REAL DEFAULT 0)''');
  await db.insert('customers', {'id': 1, 'name': 'أحمد', 'phone': '07701234567', 'current_total_debt': 500000});
  await db.insert('customers', {'id': 2, 'name': 'علي', 'phone': '', 'current_total_debt': 300000});
  await db.insert('customers', {'id': 3, 'name': 'محذوف', 'phone': '', 'current_total_debt': 100000, 'is_deleted': 1});
  return db;
}

Future<void> _due(Database db, int no, int party, String due,
        {String kind = 'installment', String partyType = 'customer', String status = 'open', double amount = 100000, double paid = 0}) =>
    db.insert('due_items', {
      'due_no': no,
      'kind': kind,
      'party_type': partyType,
      'party_id': party,
      'amount': amount,
      'paid_amount': paid,
      'issue_date': '2026-10-01T00:00:00.000',
      'due_date': due,
      'status': status,
      'installment_no': 2,
      'installments_total': 4,
    });

void main() {
  sqfliteFfiInit();

  test('تظهر الاستحقاقات التي حلّت (اليوم أو تأخرت) فقط، الأقدم أولاً', () async {
    final db = await _db();
    await _due(db, 1, 1, '2026-11-19T00:00:00.000'); // اليوم ✓
    await _due(db, 2, 2, '2026-10-20T00:00:00.000', kind: 'cheque_in', status: 'partial', paid: 40000); // متأخر ✓
    await _due(db, 3, 1, '2026-11-20T00:00:00.000'); // غداً ✗
    await _due(db, 4, 1, '2026-11-01T00:00:00.000', status: 'closed'); // مغلق ✗
    await _due(db, 5, 1, '2026-11-01T00:00:00.000', paid: 100000); // سُدّد كله ✗
    await _due(db, 6, 1, '2026-11-01T00:00:00.000', kind: 'cheque_out', partyType: 'supplier'); // دفع لمورد ✗
    await _due(db, 7, 3, '2026-11-01T00:00:00.000'); // عميل محذوف ✗
    await _due(db, 8, 1, '2026-11-01T00:00:00.000', status: 'cancelled'); // ملغى ✗

    final r = await DueAlerts.loadIn(db, now: _now);
    expect(r.items.map((d) => d.dueNo), [2, 1]);
    expect(r.waCovered, 0);
    final late = r.items.first;
    expect(late.customerName, 'علي');
    expect(late.remaining, 60000);
    expect(late.daysLate, 30);
    expect(late.kindLabel, 'شيك قبض');
    expect(r.items.last.daysLate, 0);
    await db.close();
  });

  test('من تصله رسالة واتساب التلقائية يُستثنى ويُعدّ', () async {
    final db = await _db();
    await _due(db, 1, 1, '2026-11-10T00:00:00.000'); // أحمد: رقم صالح
    await _due(db, 2, 2, '2026-11-10T00:00:00.000'); // علي: بلا رقم ⇒ لا تصله رسالة
    final rule = WaRule(id: 'r', name: 'شهري', audience: WaAudience.all, minDebt: 1000, auto: true);
    final r = await DueAlerts.loadIn(db, now: _now, rules: [rule]);
    expect(r.items.map((d) => d.customerName), ['علي']);
    expect(r.waCovered, 1);
    await db.close();
  });

  group('هل تصله رسالة واتساب التلقائية؟', () {
    const phone = '07701234567';
    bool cov(List<WaRule> rules, {int id = 1, double debt = 50000, String? p = phone}) =>
        DueAlerts.coveredByWa(rules, customerId: id, debt: debt, phone: p);

    test('بلا قاعدة، أو بلا رقم صالح ⇒ لا', () {
      expect(cov(const []), isFalse);
      expect(cov([WaRule(id: 'a', name: 'a')], p: ''), isFalse);
      expect(cov([WaRule(id: 'a', name: 'a')], p: '123'), isFalse);
    });

    test('القاعدة المطفأة، أو «بموافقتي» لا «تلقائي»، أو دين تحت حدها ⇒ لا', () {
      expect(cov([WaRule(id: 'a', name: 'a', enabled: false)]), isFalse);
      expect(cov([WaRule(id: 'a', name: 'a', auto: false)]), isFalse);
      expect(cov([WaRule(id: 'a', name: 'a', minDebt: 100000)]), isFalse);
      expect(cov([WaRule(id: 'a', name: 'a', minDebt: 100000)], debt: 150000), isTrue);
    });

    test('الجمهور: الكل، المختارون، الكل عدا، ومواعيد المطالبة لا تُحسب', () {
      expect(cov([WaRule(id: 'a', name: 'a')]), isTrue);
      expect(cov([WaRule(id: 'a', name: 'a', audience: WaAudience.selected, ids: {1})]), isTrue);
      expect(cov([WaRule(id: 'a', name: 'a', audience: WaAudience.selected, ids: {9})]), isFalse);
      expect(cov([WaRule(id: 'a', name: 'a', audience: WaAudience.except, ids: {1})]), isFalse);
      expect(cov([WaRule(id: 'a', name: 'a', audience: WaAudience.except, ids: {9})]), isTrue);
      expect(cov([WaRule(id: 'a', name: 'a', audience: WaAudience.dueReminders)]), isFalse);
    });
  });

  test('أيام التأخر بالتاريخ وحده', () {
    expect(DueAlerts.daysLate(DateTime(2026, 11, 19, 23, 59), _now), 0);
    expect(DueAlerts.daysLate(DateTime(2026, 11, 18), _now), 1);
    expect(DueAlerts.daysLate(DateTime(2026, 11, 25), _now), 0); // المستقبل لا يُعدّ تأخراً
  });
}
