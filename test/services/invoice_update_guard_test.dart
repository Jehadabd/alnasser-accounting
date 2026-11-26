// test/services/invoice_update_guard_test.dart
//
// 🛡️ حادثة فاتورة غسان (1202610191): «تعليق» فاتورة دين محفوظة غيّر عميلها بصمت،
// ثم ضاعف الحفظُ دينها. هنا نتأكد بكود البرنامج نفسه أن:
//   1) InvoiceDao.updateInvoice يرفض تغيير عميل/مال/حالة فاتورة محفوظة، ولا يكتب شيئاً.
//   2) الفاتورة المعلّقة تبقى قابلة للتحديث كما كانت، لكنها لا تتحول إلى محفوظة من هنا.
//   3) قسم «حركات سجل الديون» في تاريخ الفاتورة يكشف الأثر المتبقي على عميل آخر.
// التشغيل: flutter test test/services/invoice_update_guard_test.dart

import 'package:alnaser/models/invoice.dart';
import 'package:alnaser/screens/invoice_history/invoice_ledger_moves.dart';
import 'package:alnaser/services/database/business/invoice_update_guard.dart';
import 'package:alnaser/services/database/dao/invoice_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _saved = 'محفوظة';
const _held = 'معلقة';

Future<Database> _openDb() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''CREATE TABLE invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT, customer_name TEXT, customer_phone TEXT,
      customer_address TEXT, installer_name TEXT, invoice_date TEXT, payment_type TEXT,
      total_amount REAL, total_amount_cents INTEGER, discount REAL, discount_cents INTEGER,
      amount_paid_on_invoice REAL, amount_paid_cents INTEGER, loading_fee REAL,
      created_at TEXT, last_modified_at TEXT, customer_id INTEGER, status TEXT,
      return_amount REAL, is_locked INTEGER, points_rate REAL, created_by_user_id INTEGER,
      created_by_username TEXT, notes TEXT, invoice_uuid TEXT, creator_device_id TEXT,
      version INTEGER, monthly_sequence_number INTEGER, invoice_number TEXT,
      invoice_year INTEGER, invoice_month INTEGER, is_created_by_me INTEGER,
      is_synced INTEGER, restored_mark INTEGER)''');
  await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)');
  await db.execute('''CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER, invoice_id INTEGER, amount_changed REAL, transaction_type TEXT,
      transaction_date TEXT, created_at TEXT, transaction_note TEXT,
      created_by_username TEXT, is_deleted INTEGER DEFAULT 0)''');
  return db;
}

Future<int> _addInvoice(Database db, {required String status, int? customerId = 814}) =>
    db.insert('invoices', {
      'customer_name': 'غسان الرشيد',
      'invoice_date': '2026-10-25T14:07:17',
      'payment_type': 'دين',
      'total_amount': 130625.0,
      'discount': 0.0,
      'amount_paid_on_invoice': 0.0,
      'loading_fee': 0.0,
      'created_at': '2026-10-25T14:07:53',
      'last_modified_at': '2026-10-25T14:07:53',
      'customer_id': customerId,
      'status': status,
      'return_amount': 0.0,
      'is_locked': 0,
      'points_rate': 1.0,
      'invoice_uuid': 'inv_test',
      'version': 1,
      'invoice_number': '1202610191',
      'is_created_by_me': 1,
    });

Future<Map<String, Object?>> _row(Database db, int id) async =>
    (await db.query('invoices', where: 'id = ?', whereArgs: [id])).first;

Future<Invoice> _inv(Database db, int id) async =>
    Invoice.fromMap(Map<String, dynamic>.from(await _row(db, id)));

void main() {
  sqfliteFfiInit();

  group('InvoiceUpdateGuard.violation (القاعدة وحدها)', () {
    final saved = <String, Object?>{
      'status': _saved,
      'customer_id': 814,
      'payment_type': 'دين',
      'total_amount': 130625.0,
      'amount_paid_on_invoice': 0.0,
      'discount': 0.0,
      'loading_fee': 0.0,
    };

    test('لا صف في القاعدة ⇒ لا شيء نحرسه', () {
      expect(InvoiceUpdateGuard.violation(null, {'status': _held}), isNull);
    });

    test('محفوظة بلا تغيير مالي (ملاحظة/قفل) ⇒ مسموح', () {
      expect(InvoiceUpdateGuard.violation(saved, {...saved, 'notes': 'x', 'is_locked': 1}), isNull);
    });

    test('فروق تقريب أقل من نصف فلس لا تُعد تغييراً، والعميل null و0 سواء', () {
      expect(InvoiceUpdateGuard.violation(saved, {...saved, 'total_amount': 130625.004}), isNull);
      final noCust = {...saved, 'customer_id': null};
      expect(InvoiceUpdateGuard.violation(noCust, {...noCust, 'customer_id': 0}), isNull);
    });

    test('حادثة غسان: تعليق محفوظة بعميل آخر ⇒ مرفوض ويذكر الحالة والعميل', () {
      final why = InvoiceUpdateGuard.violation(saved, {...saved, 'status': _held, 'customer_id': 421});
      expect(why, isNotNull);
      expect(why, contains('الحالة'));
      expect(why, contains('العميل'));
    });

    test('كل حقل يحدد الدين مرفوض وحده', () {
      for (final change in <Map<String, Object?>>[
        {'customer_id': 421},
        {'customer_id': null},
        {'payment_type': 'نقد'},
        {'total_amount': 130000.0},
        {'amount_paid_on_invoice': 625.0},
        {'discount': 625.0},
        {'loading_fee': 1000.0},
        {'status': 'ملغاة'},
      ]) {
        expect(InvoiceUpdateGuard.violation(saved, {...saved, ...change}), isNotNull, reason: '$change');
      }
    });

    test('المعلّقة: تتغير بحرية لكنها لا تصير محفوظة من هنا', () {
      final held = {...saved, 'status': _held};
      expect(InvoiceUpdateGuard.violation(held, {...held, 'customer_id': 421, 'total_amount': 5000.0}), isNull);
      expect(InvoiceUpdateGuard.violation(held, {...held, 'status': _saved}), isNotNull);
    });
  });

  group('InvoiceDao.updateInvoice (مسار البرنامج الحقيقي على قاعدة SQLite)', () {
    late Database db;
    late InvoiceDao dao;
    setUp(() async {
      db = await _openDb();
      dao = InvoiceDao(getDatabase: () async => db);
    });
    tearDown(() => db.close());

    test('تعليق فاتورة دين محفوظة بعميل آخر ⇒ يُرفض ولا يتغير أي شيء في الصف', () async {
      final id = await _addInvoice(db, status: _saved);
      final before = await _row(db, id);
      final attempt = (await _inv(db, id)).copyWith(status: _held, customerId: 421);
      await expectLater(dao.updateInvoice(attempt), throwsA(isA<StateError>()));
      expect(await _row(db, id), before); // الصف كما هو حرفياً، حتى رقم النسخة
    });

    test('تغيير الإجمالي أو نوع الدفع لمحفوظة ⇒ يُرفض', () async {
      final id = await _addInvoice(db, status: _saved);
      final inv = await _inv(db, id);
      await expectLater(dao.updateInvoice(inv.copyWith(totalAmount: 100000)), throwsA(isA<StateError>()));
      await expectLater(dao.updateInvoice(inv.copyWith(paymentType: 'نقد')), throwsA(isA<StateError>()));
      expect((await _row(db, id))['total_amount'], 130625.0);
      expect((await _row(db, id))['payment_type'], 'دين');
    });

    test('ملاحظة على فاتورة محفوظة ⇒ تُكتب كما كانت، والنسخة تزيد', () async {
      final id = await _addInvoice(db, status: _saved);
      await dao.updateInvoice((await _inv(db, id)).copyWith(notes: 'ملاحظة'));
      final r = await _row(db, id);
      expect(r['notes'], 'ملاحظة');
      expect(r['version'], 2);
      expect(r['customer_id'], 814);
    });

    test('فاتورة معلّقة: تغيير عميلها وبنودها مسموح كما كان', () async {
      final id = await _addInvoice(db, status: _held, customerId: null);
      await dao.updateInvoice((await _inv(db, id)).copyWith(customerId: 421, totalAmount: 5000));
      final r = await _row(db, id);
      expect(r['customer_id'], 421);
      expect(r['status'], _held);
    });

    test('فاتورة معلّقة لا تتحول إلى محفوظة عبر التحديث', () async {
      final id = await _addInvoice(db, status: _held);
      await expectLater(
          dao.updateInvoice((await _inv(db, id)).copyWith(status: _saved)), throwsA(isA<StateError>()));
      expect((await _row(db, id))['status'], _held);
    });

    test('شاشة قديمة تظن الفاتورة معلّقة وهي محفوظة في القاعدة ⇒ يُرفض', () async {
      final id = await _addInvoice(db, status: _held);
      final stale = await _inv(db, id); // نسخة الشاشة: معلّقة
      await db.update('invoices', {'status': _saved}, where: 'id = ?', whereArgs: [id]); // حُفظت في مكان آخر
      await expectLater(dao.updateInvoice(stale.copyWith(customerId: 421)), throwsA(isA<StateError>()));
      expect((await _row(db, id))['status'], _saved);
      expect((await _row(db, id))['customer_id'], 814);
    });
  });

  group('حركات سجل الديون في تاريخ الفاتورة (قراءة فقط)', () {
    late Database db;
    setUp(() async {
      db = await _openDb();
      await db.insert('customers', {'id': 814, 'name': 'غسان الرشيد '});
      await db.insert('customers', {'id': 421, 'name': 'علي ابو طيبة / غسان الرشيد '});
    });
    tearDown(() => db.close());

    Future<void> tx(int cid, double amount, String type, {int deleted = 0}) => db.insert('transactions', {
          'customer_id': cid,
          'invoice_id': 2589,
          'amount_changed': amount,
          'transaction_type': type,
          'transaction_date': '2026-11-08T16:00:57',
          'is_deleted': deleted,
        });

    test('حالة غسان كما وقعت: أثر سالب على عميل آخر ⇒ تنبيه، ودين مضاعف على عميل الفاتورة', () async {
      await tx(814, 130625, 'invoice_debt');
      await tx(421, -130625, 'invoice_customer_change');
      await tx(814, 130625, 'invoice_customer_change');
      final s = await InvoiceLedgerMoves.load(db, 2589, currentCustomerId: 814);
      expect(s.moves.length, 3);
      expect(s.nets.first.customerId, 814); // عميل الفاتورة أولاً
      expect(s.nets.first.net, 261250);
      expect(s.stray.length, 1);
      expect(s.stray.single.customerId, 421);
      expect(s.stray.single.net, -130625);
      expect(s.touchedSeveralCustomers, isTrue);
    });

    test('بعد تصحيح الحارس المحاسبي: لا تنبيه، والصافي = دين الفاتورة مرة واحدة', () async {
      await tx(814, 130625, 'invoice_debt');
      await tx(421, -130625, 'invoice_customer_change');
      await tx(814, 130625, 'invoice_customer_change');
      await tx(421, 130625, 'invoice_debt_sync');
      await tx(814, -130625, 'invoice_debt_sync');
      final s = await InvoiceLedgerMoves.load(db, 2589, currentCustomerId: 814);
      expect(s.stray, isEmpty);
      expect(s.nets.firstWhere((n) => n.customerId == 814).net, 130625);
      expect(s.nets.firstWhere((n) => n.customerId == 421).net, 0);
    });

    test('التسديد المرتبط يظهر لكنه لا يدخل في صافي دين الفاتورة، والمحذوف لا يظهر', () async {
      await tx(814, 130625, 'invoice_debt');
      await tx(814, -50000, 'manual_payment');
      await tx(814, 999, 'invoice_edit', deleted: 1);
      final s = await InvoiceLedgerMoves.load(db, 2589, currentCustomerId: 814);
      expect(s.moves.length, 2);
      expect(s.moves.last.contributes, isFalse);
      expect(s.nets.single.net, 130625);
      expect(s.stray, isEmpty);
    });

    test('جدول ناقص أو خطأ قراءة ⇒ ملخص فارغ ولا تفشل الشاشة', () async {
      await db.execute('DROP TABLE transactions');
      final s = await InvoiceLedgerMoves.load(db, 2589, currentCustomerId: 814);
      expect(s.isEmpty, isTrue);
    });
  });
}
