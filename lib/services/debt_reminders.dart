// lib/services/debt_reminders.dart
//
// 📅 مواعيد المطالبة بالدين.
//
//   • الموعد = أيام تختارها من الشهر (مثل 1 و2 و5) + شهر البداية + التكرار.
//   • لكل موعد «أشخاص» (عميل أو أكثر)، ولكل شخص مبلغ مطلوب اختياري وفاتورة اختيارية.
//   • تُضاف من: سجل الديون ← التحصيل والتقارير ← مواعيد المطالبة، أو «المزيد» في فاتورة الدين،
//     أو صفحة العميل.
//   • تظهر نافذة «مطالبات اليوم» عند التشغيل: أول تشغيل في اليوم أو كل تشغيل.
//   • الشخص الذي صار رصيده صفراً لا يظهر في التذكير.
//
// جداول محلية منفصلة (debt_reminders + debt_reminder_members) — لا تمس الفواتير ولا تُزامَن.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../models/app_user.dart';
import '../models/invoice.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// شخص داخل موعد
class ReminderMember {
  ReminderMember({
    this.id,
    required this.customerId,
    required this.customerName,
    this.amount,
    this.invoiceId,
    this.snoozeUntil,
    this.active = true,
  });

  int? id;
  int customerId;
  String customerName;
  double? amount; // المبلغ المطلوب — null = رصيده وقت التذكير
  int? invoiceId;
  DateTime? snoozeUntil;
  bool active;

  Map<String, Object?> toMap(int reminderId) => {
        if (id != null) 'id': id,
        'reminder_id': reminderId,
        'customer_id': customerId,
        'customer_name': customerName,
        'amount': amount,
        'invoice_id': invoiceId,
        'snooze_until': snoozeUntil?.toIso8601String(),
        'active': active ? 1 : 0,
      };

  factory ReminderMember.fromMap(Map<String, Object?> m) => ReminderMember(
        id: m['id'] as int?,
        customerId: m['customer_id'] as int,
        customerName: '${m['customer_name'] ?? ''}',
        amount: (m['amount'] as num?)?.toDouble(),
        invoiceId: m['invoice_id'] as int?,
        snoozeUntil: DateTime.tryParse('${m['snooze_until'] ?? ''}'),
        active: (m['active'] as int? ?? 1) == 1,
      );

  ReminderMember copy() => ReminderMember(
        id: id,
        customerId: customerId,
        customerName: customerName,
        amount: amount,
        invoiceId: invoiceId,
        snoozeUntil: snoozeUntil,
        active: active,
      );

  bool isSnoozed(DateTime d) {
    final s = snoozeUntil;
    return s != null && DateUtils.dateOnly(d).isBefore(DateUtils.dateOnly(s));
  }
}

class DebtReminder {
  DebtReminder({
    this.id,
    this.title,
    List<int>? days,
    required this.startYear,
    required this.startMonth,
    this.repeat = 'once',
    this.months,
    this.note,
    this.active = true,
    DateTime? createdAt,
    List<ReminderMember>? members,
  })  : days = _norm(days ?? const [1, 2, 3, 4, 5]),
        createdAt = createdAt ?? DateTime.now(),
        members = members ?? [];

  int? id;
  String? title;
  List<int> days; // أيام الشهر مرتبة بلا تكرار (1..31)
  int startYear;
  int startMonth;
  String repeat; // once | monthly
  int? months; // للشهري: عدد الأشهر، null = بلا نهاية (حتى يسدّد الجميع)
  String? note;
  bool active;
  DateTime createdAt;
  List<ReminderMember> members;

  static List<int> _norm(Iterable<int> d) => (d.where((x) => x >= 1 && x <= 31).toSet().toList()..sort());
  void setDays(Iterable<int> d) => days = _norm(d);

  bool get monthly => repeat == 'monthly';

  DebtReminder copy() => DebtReminder(
        id: id,
        title: title,
        days: [...days],
        startYear: startYear,
        startMonth: startMonth,
        repeat: repeat,
        months: months,
        note: note,
        active: active,
        createdAt: createdAt,
        members: members.map((m) => m.copy()).toList(),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'days': days.join(','),
        // أعمدة الإصدار الأول (ما زالت NOT NULL في الجدول)
        'customer_id': members.isEmpty ? 0 : members.first.customerId,
        'customer_name': members.isEmpty ? '' : members.first.customerName,
        'day_from': days.isEmpty ? 1 : days.first,
        'day_to': days.isEmpty ? 1 : days.last,
        'start_year': startYear,
        'start_month': startMonth,
        'repeat': repeat,
        'months': months,
        'note': note,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory DebtReminder.fromMap(Map<String, Object?> m, List<ReminderMember> members) {
    var days = '${m['days'] ?? ''}'
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    if (days.isEmpty) {
      final a = m['day_from'] as int? ?? 1, b = m['day_to'] as int? ?? a;
      days = [for (var i = a; i <= b; i++) i];
    }
    return DebtReminder(
      id: m['id'] as int?,
      title: m['title'] as String?,
      days: days,
      startYear: m['start_year'] as int,
      startMonth: m['start_month'] as int,
      repeat: '${m['repeat'] ?? 'once'}',
      months: m['months'] as int?,
      note: m['note'] as String?,
      active: (m['active'] as int? ?? 1) == 1,
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}'),
      members: members,
    );
  }

  int monthIndex(DateTime d) => (d.year - startYear) * 12 + (d.month - startMonth);

  bool coversMonth(DateTime d) {
    final i = monthIndex(d);
    if (i < 0) return false;
    if (!monthly) return i == 0;
    return months == null || i < months!;
  }

  /// أيام هذا الشهر فعلياً (يوم 31 في شهر من 30 يوماً = 30)
  List<int> daysIn(int year, int month) {
    final dim = DateUtils.getDaysInMonth(year, month);
    return (days.map((x) => x > dim ? dim : x).toSet().toList()..sort());
  }

  bool isDueOn(DateTime d) => active && coversMonth(d) && daysIn(d.year, d.month).contains(d.day);

  /// التاريخ القادم للتذكير (أو اليوم إن كان من أيامه)
  DateTime? nextDate(DateTime from) {
    if (days.isEmpty) return null;
    final f = DateUtils.dateOnly(from);
    for (var k = 0; k < 240; k++) {
      final d = DateTime(f.year, f.month + k, 1);
      if (monthIndex(d) < 0) continue;
      if (!coversMonth(d)) return null; // تجاوزنا آخر شهر
      for (final day in daysIn(d.year, d.month)) {
        final x = DateTime(d.year, d.month, day);
        if (!x.isBefore(f)) return x;
      }
    }
    return null;
  }

  bool isFinished(DateTime d) => nextDate(d) == null;

  String daysText() {
    if (days.isEmpty) return 'بلا أيام';
    // تجميع المتتالي: 1،2،3،5 ← «1–3، 5»
    final parts = <String>[];
    var s = days.first, p = days.first;
    for (final x in [...days.skip(1), -1]) {
      if (x == p + 1) {
        p = x;
        continue;
      }
      parts.add(s == p ? '$s' : (p == s + 1 ? '$s، $p' : '$s–$p'));
      s = p = x;
    }
    return '${days.length == 1 ? 'يوم' : 'أيام'} ${parts.join('، ')}';
  }

  String describe() {
    final start = '${DebtReminders.monthName(startMonth)} $startYear';
    if (!monthly) return '${daysText()} — $start فقط';
    final until = months == null ? 'بلا نهاية' : 'لمدة $months ${months == 1 ? 'شهر' : 'أشهر'}';
    return '${daysText()} من كل شهر — يبدأ $start، $until';
  }

  String get shownTitle => (title ?? '').trim().isNotEmpty
      ? title!.trim()
      : (members.length == 1 ? members.first.customerName : 'موعد ${daysText()}');
}

/// شخص مستحق التذكير اليوم مع رصيده الحالي
class DueReminder {
  const DueReminder(this.reminder, this.member, this.balance);
  final DebtReminder reminder;
  final ReminderMember member;
  final double balance;
}

class DebtReminders {
  // مرتبط بالقاعدة المفتوحة: قاعدة مستعادة تُجهَّز جداولها من جديد
  static int _readyGen = -1;
  static bool get _ready => _readyGen == DatabaseService.openGeneration;
  static set _ready(bool v) => _readyGen = v ? DatabaseService.openGeneration : -1;

  static const _kEnabled = 'debt_rem_enabled';
  static const _kFreq = 'debt_rem_freq'; // daily | startup
  static const _kLast = 'debt_rem_last';

  /// موعد ينتظر حفظ فاتورة جديدة (من «المزيد») — يُربط بها بعد الحفظ
  static DebtReminder? pendingForNewInvoice;

  static const _months = [
    'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
    'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
  ];
  static String monthName(int m) => '${_months[(m - 1).clamp(0, 11)]} ($m)';

  static Future<Database> _db() async {
    final db = await DatabaseService().database;
    if (_ready) return db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL DEFAULT 0,
        customer_name TEXT,
        invoice_id INTEGER,
        amount REAL,
        start_year INTEGER NOT NULL,
        start_month INTEGER NOT NULL,
        day_from INTEGER NOT NULL DEFAULT 1,
        day_to INTEGER NOT NULL DEFAULT 5,
        repeat TEXT NOT NULL DEFAULT 'once',
        months INTEGER,
        note TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        snooze_until TEXT
      )''');
    final cols = (await db.rawQuery('PRAGMA table_info(debt_reminders)')).map((r) => '${r['name']}').toSet();
    if (!cols.contains('title')) await db.execute('ALTER TABLE debt_reminders ADD COLUMN title TEXT');
    if (!cols.contains('days')) await db.execute('ALTER TABLE debt_reminders ADD COLUMN days TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_reminder_members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reminder_id INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        customer_name TEXT,
        amount REAL,
        invoice_id INTEGER,
        snooze_until TEXT,
        active INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_drm_rem ON debt_reminder_members(reminder_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_drm_cust ON debt_reminder_members(customer_id)');
    // مواعيد الإصدار الأول (شخص واحد في نفس الصف) ← صف شخص
    await db.execute('''
      INSERT INTO debt_reminder_members (reminder_id, customer_id, customer_name, amount, invoice_id, snooze_until, active)
      SELECT r.id, r.customer_id, r.customer_name, r.amount, r.invoice_id, r.snooze_until, 1
      FROM debt_reminders r
      WHERE r.customer_id > 0 AND NOT EXISTS (SELECT 1 FROM debt_reminder_members m WHERE m.reminder_id = r.id)''');
    _ready = true;
    return db;
  }

  // ─────────────────────────── الإعدادات ───────────────────────────

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? true;
  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_kEnabled, v);
  static Future<String> frequency() async => (await SharedPreferences.getInstance()).getString(_kFreq) ?? 'daily';
  static Future<void> setFrequency(String v) async => (await SharedPreferences.getInstance()).setString(_kFreq, v);

  // ─────────────────────────── القراءة والكتابة ───────────────────────────

  /// كل المواعيد، أو مواعيد عميل/فاتورة (المواعيد التي فيها هذا الشخص)
  static Future<List<DebtReminder>> list({int? customerId, int? invoiceId}) async {
    final db = await _db();
    final where = <String>[];
    final args = <Object?>[];
    if (customerId != null) {
      where.add('id IN (SELECT reminder_id FROM debt_reminder_members WHERE customer_id = ?)');
      args.add(customerId);
    }
    if (invoiceId != null) {
      where.add('id IN (SELECT reminder_id FROM debt_reminder_members WHERE invoice_id = ?)');
      args.add(invoiceId);
    }
    final rows = await db.query('debt_reminders',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'active DESC, start_year, start_month, id');
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final mRows = await db.query('debt_reminder_members',
        where: 'reminder_id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids, orderBy: 'id');
    final byRem = <int, List<ReminderMember>>{};
    for (final m in mRows) {
      byRem.putIfAbsent(m['reminder_id'] as int, () => []).add(ReminderMember.fromMap(m));
    }
    return [for (final r in rows) DebtReminder.fromMap(r, byRem[r['id'] as int] ?? [])];
  }

  /// حفظ الموعد مع أشخاصه (يستبدل قائمة الأشخاص بالكامل)
  static Future<int> save(DebtReminder r) async {
    final db = await _db();
    await db.transaction((txn) async {
      if (r.id == null) {
        r.id = await txn.insert('debt_reminders', r.toMap());
      } else {
        await txn.update('debt_reminders', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
      }
      await txn.delete('debt_reminder_members', where: 'reminder_id = ?', whereArgs: [r.id]);
      for (final m in r.members) {
        m.id = null;
        m.id = await txn.insert('debt_reminder_members', m.toMap(r.id!));
      }
    });
    return r.id!;
  }

  static Future<void> delete(int id) async {
    final db = await _db();
    await db.delete('debt_reminder_members', where: 'reminder_id = ?', whereArgs: [id]);
    await db.delete('debt_reminders', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> setActive(int id, bool active) async {
    final db = await _db();
    await db.update('debt_reminders', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> setMemberActive(int memberId, bool active) async {
    final db = await _db();
    await db.update('debt_reminder_members', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [memberId]);
  }

  static Future<void> snoozeMemberToTomorrow(int memberId) async {
    final db = await _db();
    final t = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    await db.update('debt_reminder_members', {'snooze_until': t.toIso8601String()},
        where: 'id = ?', whereArgs: [memberId]);
  }

  static Future<Map<int, double>> balances(Iterable<int> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    final db = await DatabaseService().database;
    final out = <int, double>{};
    // دفعات حتى لا يتجاوز حد متغيرات SQLite
    for (var i = 0; i < list.length; i += 500) {
      final part = list.sublist(i, (i + 500).clamp(0, list.length));
      final rows = await db.rawQuery(
          'SELECT id, current_total_debt FROM customers WHERE id IN (${List.filled(part.length, '?').join(',')})', part);
      for (final r in rows) {
        out[r['id'] as int] = (r['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return out;
  }

  static Future<double> balanceOf(int customerId) async => (await balances([customerId]))[customerId] ?? 0.0;

  /// كل العملاء للاختيار (الأكبر ديناً أولاً)
  static Future<List<({int id, String name, double debt})>> customers() async {
    final db = await DatabaseService().database;
    final rows = await db.query('customers',
        columns: ['id', 'name', 'current_total_debt'], orderBy: 'IFNULL(current_total_debt, 0) DESC, name');
    return [
      for (final r in rows)
        (id: r['id'] as int, name: '${r['name'] ?? ''}', debt: (r['current_total_debt'] as num?)?.toDouble() ?? 0.0),
    ];
  }

  /// المستحقون اليوم (من ما زال عليه دين)
  static Future<List<DueReminder>> dueToday({bool includeSnoozed = false}) async {
    final now = DateTime.now();
    final due = (await list()).where((r) => r.isDueOn(now)).toList();
    final bal = await balances([for (final r in due) ...r.members.map((m) => m.customerId)]);
    final out = <DueReminder>[];
    final seen = <int>{}; // نفس العميل في موعدين اليوم: مرة واحدة
    for (final r in due) {
      for (final m in r.members) {
        if (!m.active || (!includeSnoozed && m.isSnoozed(now))) continue;
        final b = bal[m.customerId] ?? 0.0;
        if (b <= 0.5 || !seen.add(m.customerId)) continue;
        out.add(DueReminder(r, m, b));
      }
    }
    out.sort((a, b) => b.balance.compareTo(a.balance));
    return out;
  }

  static Future<int?> customerIdByName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    final db = await DatabaseService().database;
    final r = await db.query('customers', columns: ['id'], where: 'name = ?', whereArgs: [n], limit: 1);
    return r.isEmpty ? null : r.first['id'] as int;
  }

  /// ربط الموعد المؤجَّل بالفاتورة بعد حفظها (من invoice_actions):
  /// الشخص الذي لم يُعرف رقمه بعد (customerId = 0) = عميل الفاتورة.
  static Future<void> commitPending(Invoice? saved) async {
    final p = pendingForNewInvoice;
    pendingForNewInvoice = null;
    if (p == null || saved == null || saved.id == null) return;
    final inv = saved;
    if (inv.paymentType != 'دين') return;
    try {
      final cid = inv.customerId ?? await customerIdByName(inv.customerName);
      if (cid == null) return;
      for (final m in p.members) {
        if (m.customerId == 0) {
          m
            ..customerId = cid
            ..customerName = inv.customerName.trim()
            ..invoiceId = inv.id;
        }
      }
      p.members.removeWhere((m) => m.customerId == 0);
      if (p.members.isEmpty) return;
      await save(p);
    } catch (e) {
      debugPrint('⚠️ موعد المطالبة: $e');
    }
  }

  /// عند تشغيل البرنامج: حسب الإعداد (أول تشغيل في اليوم / كل تشغيل)
  static Future<void> checkOnStartup(
      BuildContext context, Future<void> Function(BuildContext, List<DueReminder>) show) async {
    try {
      if (!AuthService().hasPermission(AppPermissions.debtRegister)) return;
      if (!await enabled()) return;
      final prefs = await SharedPreferences.getInstance();
      final today = DateUtils.dateOnly(DateTime.now()).toIso8601String();
      final freq = prefs.getString(_kFreq) ?? 'daily';
      if (freq == 'daily' && prefs.getString(_kLast) == today) return;
      final due = await dueToday();
      if (due.isEmpty || !context.mounted) return;
      await prefs.setString(_kLast, today);
      if (!context.mounted) return;
      await show(context, due);
    } catch (e) {
      debugPrint('⚠️ تذكيرات المطالبة: $e');
    }
  }
}
