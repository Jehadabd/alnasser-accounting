// test/accounting/journal_history_test.dart
//
// ⭐ p173: لا يُمحى قيد من الدفتر دون أثر.
// كل حذف أو استبدال غيّر شيئاً يُنسخ حرفياً إلى journal_history، والدفتر الحي
// يبقى كما كان تماماً (الأرصدة والقيود كما لو لم توجد الميزة).
// التشغيل: flutter test test/accounting/journal_history_test.dart

import 'dart:convert';

import 'package:alnaser/accounting/accounting_schema.dart';
import 'package:alnaser/accounting/ledger.dart';
import 'package:alnaser/accounting/vouchers_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await AccountingSchema.ensure(db);
  });

  tearDown(() async => db.close());

  Future<List<Map<String, Object?>>> history() =>
      db.query(Ledger.historyTable, orderBy: 'id');

  Future<int> liveEntries() async =>
      ((await db.rawQuery('SELECT COUNT(*) AS n FROM journal_entries')).first['n'] as num).toInt();

  Future<List<Map<String, Object?>>> balances() => db.rawQuery(
      'SELECT account_id, SUM(debit) AS d, SUM(credit) AS c FROM journal_lines GROUP BY account_id ORDER BY account_id');

  test('حذف سند: يختفي من الدفتر كما كان، ويُنسخ حرفياً إلى السجل', () async {
    final v = VouchersService(getDatabase: () async => db);
    final rent = (await db.query('accounts', where: "code = '5201'")).first['id'] as int;
    final box = (await v.cashBoxes()).firstWhere((b) => b.isDefault);
    final before = await balances();
    final id = await v.create(
        type: VoucherType.expense, amount: 2000.75, date: DateTime(2026, 9, 5), cashBoxId: box.id, accountId: rent);

    final entry = (await db.query('journal_entries', where: "source_type = 'voucher' AND source_id = ?", whereArgs: [id])).single;
    final lines = await db.query('journal_lines', where: 'entry_id = ?', whereArgs: [entry['id']], orderBy: 'id');
    expect(lines, hasLength(2));

    await v.delete(id, userId: 7);

    // الدفتر الحي: كما لو لم يوجد السند (السلوك القديم نفسه)
    expect(await liveEntries(), 0);
    expect(await balances(), before);

    // السجل: نسخة حرفية
    final h = (await history()).single;
    expect(h['action'], 'deleted');
    expect(h['reason'], 'حذف سند');
    expect(h['archived_by_user_id'], 7);
    expect(h['source_type'], 'voucher');
    expect(h['source_id'], id);
    expect(jsonDecode(h['entry_json'] as String), entry);
    expect(jsonDecode(h['lines_json'] as String), lines);
  });

  test('الأرقام تُحفظ بتّةً بتّة (بلا تقريب)', () async {
    final ledger = Ledger(getDatabase: () async => db);
    final cash = await Ledger.systemAccountId(db, 'cash_main');
    final cap = await Ledger.systemAccountId(db, 'capital');
    final entryId = await ledger.postManualEntry(date: DateTime(2026, 9, 6), description: 'رأس مال', lines: [
      JournalLineInput(accountId: cash, debit: 1234567.89),
      JournalLineInput(accountId: cap, credit: 1234567.89),
    ]);
    final stored = await db.query('journal_lines', where: 'entry_id = ?', whereArgs: [entryId], orderBy: 'id');

    await ledger.deleteManualEntry(entryId, userId: 3);

    expect(await liveEntries(), 0);
    final h = (await history()).single;
    expect(h['reason'], 'حذف قيد يدوي');
    final archived = (jsonDecode(h['lines_json'] as String) as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < stored.length; i++) {
      for (final k in ['debit', 'credit']) {
        final a = (archived[i][k] as num).toDouble(), s = (stored[i][k] as num).toDouble();
        // مساواة تامة لا تقريبية
        expect(a == s, isTrue, reason: '$k: $a ≠ $s');
      }
    }
  });

  test('استبدال بالقيم نفسها لا يملأ السجل، واستبدال غيّر مبلغاً يُؤرشف القديم', () async {
    final cash = await Ledger.systemAccountId(db, 'cash_main');
    final cap = await Ledger.systemAccountId(db, 'capital');
    Future<int> write(double amount) => db.transaction((txn) => Ledger.writeEntry(txn,
        sourceType: 'test_doc',
        sourceId: 1,
        sourceHash: 'h$amount',
        date: DateTime(2026, 9, 7),
        description: 'مستند تجربة',
        lines: [
          JournalLineInput(accountId: cash, debit: amount),
          JournalLineInput(accountId: cap, credit: amount),
        ]));

    final id1 = await write(1000);
    final id2 = await write(1000); // ترحيل متكرر بالقيم نفسها
    expect(id2, id1);
    expect(await history(), isEmpty);

    await write(800); // تصحيح المبلغ
    final h = (await history()).single;
    expect(h['action'], 'replaced');
    final old = (jsonDecode(h['lines_json'] as String) as List).cast<Map<String, dynamic>>();
    expect(old.map((l) => (l['debit'] as num) + (l['credit'] as num)), everyElement(1000));

    // الدفتر الحي بالقيمة الجديدة وحدها، بالرقم نفسه للقيد
    final live = await db.query('journal_lines', where: 'entry_id = ?', whereArgs: [id1]);
    expect(live.map((l) => (l['debit'] as num) + (l['credit'] as num)), everyElement(800));
    expect(await liveEntries(), 1);
  });

  test('قاعدة قديمة بلا جدول السجل: يُنشأ وقت الحاجة ولا يفشل الحذف', () async {
    final cash = await Ledger.systemAccountId(db, 'cash_main');
    final cap = await Ledger.systemAccountId(db, 'capital');
    await db.execute('DROP TABLE ${Ledger.historyTable}');
    await db.transaction((txn) => Ledger.writeEntry(txn,
        sourceType: 'test_doc',
        sourceId: 2,
        date: DateTime(2026, 9, 8),
        description: 'قديم',
        lines: [
          JournalLineInput(accountId: cash, debit: 50),
          JournalLineInput(accountId: cap, credit: 50),
        ]));
    await db.transaction((txn) => Ledger.deleteBySource(txn, 'test_doc', 2, reason: 'تجربة'));
    expect(await liveEntries(), 0);
    expect((await history()).single['reason'], 'تجربة');
  });
}
