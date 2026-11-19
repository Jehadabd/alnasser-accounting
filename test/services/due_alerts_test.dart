// test/services/due_alerts_test.dart
//
// 📅 تنبيه الاستحقاقات في نافذة التنبيهات بإعداداته الثلاثة: من يظهر (اليوم / الشهر)، المتأخر
// (يومياً / يوم استحقاقه)، ومن وصلته رسالة واتساب (لا يظهر / يوم استحقاقه / يومياً) — بكود
// البرنامج نفسه على قاعدة في الذاكرة.
// التشغيل: flutter test test/services/due_alerts_test.dart

import 'package:alnaser/services/due_alerts.dart';
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
  await db.execute('CREATE TABLE wa_message_log (id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT, customer_id INTEGER, status TEXT)');
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
  const today = DueAlertSettings(scope: DueScope.today);

  test('المفتوح الذي حلّ يظهر، الأقدم أولاً؛ والمغلق والمسدد والمورد والمحذوف والملغى لا', () async {
    final db = await _db();
    await _due(db, 1, 1, '2026-11-19T00:00:00.000'); // اليوم ✓
    await _due(db, 2, 2, '2026-10-20T00:00:00.000', kind: 'cheque_in', status: 'partial', paid: 40000); // متأخر ✓
    await _due(db, 3, 1, '2026-11-20T00:00:00.000'); // غداً: خارج «اليوم» ✗
    await _due(db, 4, 1, '2026-11-01T00:00:00.000', status: 'closed');
    await _due(db, 5, 1, '2026-11-01T00:00:00.000', paid: 100000);
    await _due(db, 6, 1, '2026-11-01T00:00:00.000', kind: 'cheque_out', partyType: 'supplier');
    await _due(db, 7, 3, '2026-11-01T00:00:00.000');
    await _due(db, 8, 1, '2026-11-01T00:00:00.000', status: 'cancelled');

    final r = await DueAlerts.loadIn(db, now: _now, settings: today);
    expect(r.items.map((d) => d.dueNo), [2, 1]);
    final late = r.items.first;
    expect(late.customerName, 'علي');
    expect(late.remaining, 60000);
    expect(late.daysLate, 30);
    expect(late.kindLabel, 'شيك قبض');
    expect(r.items.last.daysLate, 0);
    await db.close();
  });

  test('① «اليوم وباقي الشهر»: يظهر ما يستحق لاحقاً هذا الشهر، لا الشهر القادم', () async {
    final db = await _db();
    await _due(db, 1, 1, '2026-11-25T00:00:00.000');
    await _due(db, 2, 1, '2026-12-01T00:00:00.000');
    final month = await DueAlerts.loadIn(db, now: _now, settings: const DueAlertSettings(scope: DueScope.month));
    expect(month.items.map((d) => d.dueNo), [1]);
    expect(month.items.single.upcoming, isTrue);
    expect(month.items.single.daysUntil, 6);
    expect((await DueAlerts.loadIn(db, now: _now, settings: today)).items, isEmpty);
    await db.close();
  });

  test('② المتأخر: يومياً حتى يسدّد، أو يوم استحقاقه فقط', () async {
    final db = await _db();
    await _due(db, 1, 2, '2026-08-19T00:00:00.000'); // متأخر 3 أشهر
    await _due(db, 2, 2, '2026-11-19T00:00:00.000'); // اليوم
    final daily = await DueAlerts.loadIn(db, now: _now, settings: today);
    expect(daily.items.map((d) => d.dueNo), [1, 2]);
    final once = await DueAlerts.loadIn(db, now: _now, settings: today.copyWith(overdue: DueOverdue.dueDay));
    expect(once.items.map((d) => d.dueNo), [2]);
    await db.close();
  });

  test('③ من وصلته رسالة واتساب بعد حلول استحقاقه: لا يظهر / يوم استحقاقه / يومياً بعلامة', () async {
    final db = await _db();
    await _due(db, 1, 1, '2026-11-10T00:00:00.000'); // أحمد: متأخر 9 أيام
    await _due(db, 2, 1, '2026-11-19T00:00:00.000'); // أحمد: اليوم
    await _due(db, 3, 2, '2026-11-10T00:00:00.000'); // علي: لم تصله رسالة
    await db.insert('wa_message_log', {'at': '2026-11-19T08:00:00.000', 'customer_id': 1, 'status': 'sent'});
    await db.insert('wa_message_log', {'at': '2026-11-19T09:00:00.000', 'customer_id': 2, 'status': 'failed'}); // فشلت ⇒ لم تصله

    final hide = await DueAlerts.loadIn(db, now: _now, settings: today);
    expect(hide.items.map((d) => d.dueNo), [3]);
    expect(hide.waHidden, 2);

    final dueDay = await DueAlerts.loadIn(db, now: _now, settings: today.copyWith(wa: DueWa.dueDay));
    expect(dueDay.items.map((d) => d.dueNo), [3, 2]);
    expect(dueDay.waHidden, 1);

    final daily = await DueAlerts.loadIn(db, now: _now, settings: today.copyWith(wa: DueWa.daily));
    expect(daily.items.map((d) => d.dueNo), [1, 3, 2]);
    expect(daily.items.first.waSentAt, DateTime(2026, 11, 19, 8));
    expect(daily.items[1].waSentAt, isNull);
    await db.close();
  });

  test('رسالة قبل حلول الاستحقاق لا تُحسب «وصلته»', () async {
    final db = await _db();
    await _due(db, 1, 1, '2026-11-15T00:00:00.000');
    await db.insert('wa_message_log', {'at': '2026-11-14T08:00:00.000', 'customer_id': 1, 'status': 'sent'});
    final r = await DueAlerts.loadIn(db, now: _now, settings: today);
    expect(r.items.single.waSentAt, isNull);
    expect(r.waHidden, 0);
    await db.close();
  });

  test('بلا جدول سجل واتساب (لم يُرسل شيء قط) يعمل', () async {
    final db = await _db();
    await db.execute('DROP TABLE wa_message_log');
    await _due(db, 1, 1, '2026-11-19T00:00:00.000');
    expect((await DueAlerts.loadIn(db, now: _now, settings: today)).items, hasLength(1));
    await db.close();
  });

  test('أيام التأخر بالتاريخ وحده', () {
    expect(DueAlerts.daysLate(DateTime(2026, 11, 19, 23, 59), _now), 0);
    expect(DueAlerts.daysLate(DateTime(2026, 11, 18), _now), 1);
    expect(DueAlerts.daysLate(DateTime(2026, 11, 25), _now), 0);
  });
}
