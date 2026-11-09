// lib/erp/hr/hr_store.dart
//
// 🗄️ جداول الموارد البشرية (محلية): الموظفون، الحضور، السلف، قسائم الرواتب، المسابقات،
// وإعداد التفعيل (مطفأ حتى يفعّله المدير). صرف المال (سلفة أو راتب) يمر عبر سندات المحاسبة
// المعتمدة (VouchersService) داخل الحفظ نفسه — لا يكتب هذا الملف في الصناديق مباشرة.

import 'package:sqflite/sqflite.dart';

import '../../accounting/vouchers_service.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../erp_common.dart';
import 'hr_models.dart';

class HrStore {
  HrStore({Future<Database> Function()? db}) : _getDb = db ?? (() => DatabaseService().database);
  final Future<Database> Function() _getDb;
  static int _readyGen = -1;

  Future<Database> _db() async {
    final db = await _getDb();
    if (_readyGen != DatabaseService.openGeneration) {
      await ensureSchema(db);
      _readyGen = DatabaseService.openGeneration;
    }
    return db;
  }

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS hr_settings (k TEXT PRIMARY KEY, v TEXT)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hr_employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, phone TEXT, job TEXT,
        salary_fils INTEGER NOT NULL DEFAULT 0 CHECK (salary_fils >= 0),
        username TEXT, active INTEGER NOT NULL DEFAULT 1, start_date TEXT
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hr_attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL, day TEXT NOT NULL,
        in_at TEXT, out_at TEXT, note TEXT,
        UNIQUE (employee_id, day)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hr_advances (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL, date TEXT NOT NULL,
        amount_fils INTEGER NOT NULL CHECK (amount_fils > 0),
        note TEXT, voucher_id INTEGER, payslip_id INTEGER
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hr_payslips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL, month TEXT NOT NULL,
        base_fils INTEGER NOT NULL, bonus_fils INTEGER NOT NULL, deduction_fils INTEGER NOT NULL,
        advances_fils INTEGER NOT NULL, net_fils INTEGER NOT NULL,
        voucher_id INTEGER, paid_at TEXT, by_user TEXT,
        UNIQUE (employee_id, month)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hr_competitions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL, from_day TEXT NOT NULL, to_day TEXT NOT NULL, prize TEXT
      )''');
  }

  // ───────────── التفعيل ─────────────

  Future<bool> enabled() async {
    final db = await _db();
    final r = await db.query('hr_settings', where: "k = 'enabled'");
    return r.isNotEmpty && r.first['v'] == '1';
  }

  Future<void> setEnabled(bool on) async {
    final db = await _db();
    await db.insert('hr_settings', {'k': 'enabled', 'v': on ? '1' : '0'}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ───────────── الموظفون ─────────────

  Future<List<HrEmployee>> employees({bool activeOnly = false}) async {
    final db = await _db();
    return (await db.query('hr_employees', where: activeOnly ? 'active = 1' : null, orderBy: 'active DESC, name'))
        .map(HrEmployee.fromMap)
        .toList();
  }

  Future<int> saveEmployee(HrEmployee e) async {
    if (e.name.trim().isEmpty) throw ErpException('اكتب اسم الموظف');
    if (e.salaryFils < 0) throw ErpException('الراتب لا يكون سالباً');
    final db = await _db();
    if (e.id == null) return db.insert('hr_employees', e.toMap());
    await db.update('hr_employees', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    return e.id!;
  }

  // ───────────── الحضور ─────────────

  static String day(DateTime d) => isoDay(d).substring(0, 10);

  Future<Map<int, Map<String, Object?>>> attendanceOn(DateTime d) async {
    final db = await _db();
    return {
      for (final r in await db.query('hr_attendance', where: 'day = ?', whereArgs: [day(d)])) r['employee_id'] as int: r,
    };
  }

  /// يسجّل حضوراً (إن لم يُسجَّل) أو انصرافاً (بعد الحضور) لليوم.
  Future<String> punch(int employeeId, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    final db = await _db();
    final cur = await db.query('hr_attendance', where: 'employee_id = ? AND day = ?', whereArgs: [employeeId, day(now)]);
    if (cur.isEmpty) {
      await db.insert('hr_attendance', {'employee_id': employeeId, 'day': day(now), 'in_at': now.toIso8601String()});
      return 'حضور';
    }
    await db.update('hr_attendance', {'out_at': now.toIso8601String()}, where: 'id = ?', whereArgs: [cur.first['id']]);
    return 'انصراف';
  }

  Future<List<Map<String, Object?>>> attendanceMonth(int employeeId, String month) async {
    final db = await _db();
    return db.query('hr_attendance', where: "employee_id = ? AND day LIKE ?", whereArgs: [employeeId, '$month-%'], orderBy: 'day');
  }

  // ───────────── السلف ─────────────

  Future<List<HrAdvance>> advances({int? employeeId}) async {
    final db = await _db();
    final rows = await db.query('hr_advances',
        where: employeeId == null ? null : 'employee_id = ?', whereArgs: employeeId == null ? null : [employeeId], orderBy: 'date DESC, id DESC');
    return [
      for (final r in rows)
        HrAdvance(r['id'] as int, r['employee_id'] as int, DateTime.tryParse('${r['date']}') ?? DateTime(2000),
            (r['amount_fils'] as num).toInt(), '${r['note'] ?? ''}', r['payslip_id'] as int?),
    ];
  }

  /// يصرف سلفة: سند مصروف على [accountId] من [cashBoxId] ثم يسجّلها. أي فشل ⇒ لا شيء يُحفظ هنا.
  Future<void> payAdvance({
    required HrEmployee e,
    required int amountFils,
    required int cashBoxId,
    required int accountId,
    String note = '',
  }) async {
    if (amountFils <= 0) throw ErpException('أدخل مبلغ السلفة');
    final voucherId = await VouchersService().create(
      type: VoucherType.expense,
      amount: amountFils / 100.0,
      date: DateTime.now(),
      cashBoxId: cashBoxId,
      accountId: accountId,
      description: 'سلفة: ${e.name}${note.trim().isEmpty ? '' : ' — ${note.trim()}'}',
      userId: AuthService().currentUser?.id,
    );
    final db = await _db();
    await db.insert('hr_advances', {
      'employee_id': e.id,
      'date': DateTime.now().toIso8601String(),
      'amount_fils': amountFils,
      'note': note.trim(),
      'voucher_id': voucherId,
    });
  }

  // ───────────── الرواتب ─────────────

  Future<Map<int, Map<String, Object?>>> payslips(String month) async {
    final db = await _db();
    return {for (final r in await db.query('hr_payslips', where: 'month = ?', whereArgs: [month])) r['employee_id'] as int: r};
  }

  /// يصرف راتب شهر مرة واحدة: سند بالصافي ثم القسيمة ثم تعليم السلف «مخصومة».
  Future<void> payPayslip({
    required HrEmployee e,
    required Payslip p,
    required int cashBoxId,
    required int accountId,
  }) async {
    final err = p.error;
    if (err != null) throw ErpException(err);
    final db = await _db();
    final exists = await db.query('hr_payslips', where: 'employee_id = ? AND month = ?', whereArgs: [e.id, p.month]);
    if (exists.isNotEmpty) throw ErpException('راتب ${p.month} لـ${e.name} مصروف من قبل');
    // السلف من القاعدة لحظة الصرف (لا من الشاشة)
    final fresh = Payslip.openAdvances(await advances(employeeId: e.id), e.id!, p.month);
    if (fresh != p.advancesFils) throw ErpException('تغيّرت السلف — أعد فتح الشاشة');
    int? voucherId;
    if (p.netFils > 0) {
      voucherId = await VouchersService().create(
        type: VoucherType.expense,
        amount: p.netFils / 100.0,
        date: DateTime.now(),
        cashBoxId: cashBoxId,
        accountId: accountId,
        description: 'راتب ${p.month}: ${e.name}',
        userId: AuthService().currentUser?.id,
      );
    }
    await db.transaction((txn) async {
      final id = await txn.insert('hr_payslips', {
        'employee_id': e.id,
        'month': p.month,
        'base_fils': p.baseFils,
        'bonus_fils': p.bonusFils,
        'deduction_fils': p.deductionFils,
        'advances_fils': p.advancesFils,
        'net_fils': p.netFils,
        'voucher_id': voucherId,
        'paid_at': DateTime.now().toIso8601String(),
        'by_user': currentUserName(),
      });
      await txn.update('hr_advances', {'payslip_id': id},
          where: 'employee_id = ? AND payslip_id IS NULL AND date <= ?',
          whereArgs: [e.id, Payslip.monthEnd(p.month).toIso8601String()]);
    });
  }

  // ───────────── المسابقات ─────────────

  Future<List<Map<String, Object?>>> competitions() async {
    final db = await _db();
    return db.query('hr_competitions', orderBy: 'id DESC');
  }

  Future<void> addCompetition(String title, DateTime from, DateTime to, String prize) async {
    if (title.trim().isEmpty) throw ErpException('اكتب عنوان المسابقة');
    if (to.isBefore(from)) throw ErpException('نهاية المسابقة قبل بدايتها');
    final db = await _db();
    await db.insert('hr_competitions', {'title': title.trim(), 'from_day': day(from), 'to_day': day(to), 'prize': prize.trim()});
  }
}
