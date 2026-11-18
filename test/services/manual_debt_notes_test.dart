// test/services/manual_debt_notes_test.dart
//
// 🧾 إشعار مدين للدين اليدوي (بضاعة بلا فاتورة): الترقيم وقراءة الحركة — بكود البرنامج نفسه.
// التشغيل: flutter test test/services/manual_debt_notes_test.dart

import 'package:alnaser/erp/control/control_schema.dart';
import 'package:alnaser/invoice_designer/invoice_layout_store.dart';
import 'package:alnaser/invoice_designer/invoice_layout_templates.dart';
import 'package:alnaser/services/manual_debt_notes.dart';
import 'package:alnaser/services/printed_vouchers.dart';
import 'package:alnaser/services/voucher_print.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _db() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, address TEXT)');
  await db.execute('''CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, customer_id INTEGER,
      transaction_date TEXT, amount_changed REAL, balance_before_transaction REAL, new_balance_after_transaction REAL,
      transaction_note TEXT, transaction_type TEXT, transaction_uuid TEXT, is_deleted INTEGER DEFAULT 0,
      created_by_username TEXT)''');
  await ControlSchema.ensure(db);
  await db.insert('customers', {'id': 1, 'name': 'محمد أحمد', 'phone': '07701234567', 'address': 'الموصل'});
  return db;
}

Future<void> _tx(Database db, String uuid, double amount, String type,
        {double before = 100000, int deleted = 0, String? note}) =>
    db.insert('transactions', {
      'customer_id': 1,
      'transaction_date': '2026-11-18T10:00:00',
      'amount_changed': amount,
      'balance_before_transaction': before,
      'new_balance_after_transaction': before + amount,
      'transaction_note': note,
      'transaction_type': type,
      'transaction_uuid': uuid,
      'is_deleted': deleted,
      'created_by_username': 'ali',
    });

void main() {
  sqfliteFfiInit();

  group('ترقيم إشعار الدين اليدوي', () {
    test('أرقام متسلسلة، والحركة نفسها تأخذ رقمها نفسه دائماً', () async {
      final db = await _db();
      final a = await ManualDebtNotes.assignIn(db, uuid: 'u-1', customerId: 1, amount: 50000);
      final b = await ManualDebtNotes.assignIn(db, uuid: 'u-2', customerId: 1, amount: 20000);
      final again = await ManualDebtNotes.assignIn(db, uuid: 'u-1', customerId: 1, amount: 50000);
      expect(a, 1);
      expect(b, 2);
      expect(again, 1);
      final n = await db.rawQuery('SELECT COUNT(*) AS n FROM ${ManualDebtNotes.table}');
      expect(n.first['n'], 2);
    });

    test('حركة بلا معرّف لا تُرقَّم', () async {
      final db = await _db();
      expect(() => ManualDebtNotes.assignIn(db, uuid: '  ', amount: 1000), throwsA(anything));
    });
  });

  group('قراءة الإشعار من سجل الديون', () {
    test('دين يدوي ⇒ إشعار بمبلغه ورصيديه، ويُرقَّم إن لم يُرقَّم', () async {
      final db = await _db();
      await _tx(db, 'd-1', 75000, 'manual_debt', before: 250000, note: 'مواد متفرقة');
      final n = await ManualDebtNotes.loadIn(db, 'd-1', createdBy: 'admin');
      expect(n, isNotNull);
      expect(n!.noteNo, 1);
      expect(n.amount, 75000);
      expect(n.before, 250000);
      expect(n.after, 325000);
      expect(n.customerName, 'محمد أحمد');
      expect(n.note, 'مواد متفرقة');
      expect(n.recordedBy, 'ali'); // من سجّل الحركة لا من يطبع
      // قراءة ثانية: الرقم نفسه
      expect((await ManualDebtNotes.loadIn(db, 'd-1'))!.noteNo, 1);
    });

    test('تسديد أو حركة محذوفة أو غير موجودة ⇒ لا إشعار ولا رقم', () async {
      final db = await _db();
      await _tx(db, 'p-1', -30000, 'manual_payment');
      await _tx(db, 'd-del', 40000, 'manual_debt', deleted: 1);
      expect(await ManualDebtNotes.loadIn(db, 'p-1'), isNull);
      expect(await ManualDebtNotes.loadIn(db, 'd-del'), isNull);
      expect(await ManualDebtNotes.loadIn(db, 'missing'), isNull);
      final n = await db.rawQuery('SELECT COUNT(*) AS n FROM ${ManualDebtNotes.table}');
      expect(n.first['n'], 0);
    });

    test('الإشعار لا يغيّر حركة الدين ولا رصيدها', () async {
      final db = await _db();
      await _tx(db, 'd-2', 10000, 'manual_debt');
      final before = await db.query('transactions');
      await ManualDebtNotes.loadIn(db, 'd-2');
      expect(await db.query('transactions'), before);
    });
  });

  group('نوع السند في مصمم السندات', () {
    test('لكل نوع سند نوع طباعة، وللدين اليدوي قالبه الخاص', () {
      for (final k in VoucherKinds.all) {
        expect(PrintTarget.vouchers.where((t) => t.kind == k && t.key == VoucherKinds.targetKey(k)), isNotEmpty,
            reason: k);
      }
      expect(VoucherKinds.manualDebt, PrintedVoucherKind.manualDebt);
      expect(VoucherKinds.title(VoucherKinds.manualDebt), 'إشعار مدين');
      expect(InvoiceLayoutTemplates.forKind(VoucherKinds.manualDebt).first.key, 'vm_official');
      final l = InvoiceLayoutTemplates.defaultFor(VoucherKinds.manualDebt);
      expect(l.name, 'إشعار مدين رسمي بإطار');
    });
  });
}
