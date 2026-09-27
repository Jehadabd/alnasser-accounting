// lib/accounting/ledger.dart
//
// 📒 الدفتر العام: الحسابات والقيود.
//
// القاعدة الذهبية: لا يُكتب قيد غير متوازن أبداً (مجموع المدين = مجموع الدائن).

import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';

/// الفرق المسموح بسبب كسور الأرقام العشرية.
const double kMoneyEpsilon = 0.005;

double roundMoney(double v) => (v * 100).roundToDouble() / 100;

class Account {
  Account({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    this.parentId,
    this.isGroup = false,
    this.isControl = false,
    this.systemKey,
    this.currency = 'IQD',
    this.isActive = true,
    this.notes,
  });

  final int id;
  final String code;
  final String name;
  final String type; // asset | liability | equity | revenue | expense
  final int? parentId;
  final bool isGroup;
  final bool isControl;
  final String? systemKey;
  final String currency;
  final bool isActive;
  final String? notes;

  /// الحسابات ذات الطبيعة المدينة: الرصيد = مدين − دائن.
  bool get isDebitNature => type == 'asset' || type == 'expense';

  String get typeLabel => accountTypeLabels[type] ?? type;

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int,
        code: m['code'] as String,
        name: m['name'] as String,
        type: m['type'] as String,
        parentId: m['parent_id'] as int?,
        isGroup: (m['is_group'] as int? ?? 0) == 1,
        isControl: (m['is_control'] as int? ?? 0) == 1,
        systemKey: m['system_key'] as String?,
        currency: (m['currency'] as String?) ?? 'IQD',
        isActive: (m['is_active'] as int? ?? 1) == 1,
        notes: m['notes'] as String?,
      );

  @override
  String toString() => '$code - $name';
}

const Map<String, String> accountTypeLabels = {
  'asset': 'أصول',
  'liability': 'خصوم',
  'equity': 'حقوق ملكية',
  'revenue': 'إيرادات',
  'expense': 'مصاريف',
};

/// سطر قيد قبل الحفظ.
class JournalLineInput {
  JournalLineInput({
    required this.accountId,
    this.debit = 0,
    this.credit = 0,
    this.partyType,
    this.partyId,
    this.currency = 'IQD',
    this.fcAmount,
    this.exchangeRate,
    this.memo,
  });

  final int accountId;
  final double debit;
  final double credit;
  final String? partyType; // customer | supplier
  final int? partyId;
  final String currency;
  final double? fcAmount;
  final double? exchangeRate;
  final String? memo;

  Map<String, Object?> toMap(int entryId) => {
        'entry_id': entryId,
        'account_id': accountId,
        'debit': roundMoney(debit),
        'credit': roundMoney(credit),
        'party_type': partyType,
        'party_id': partyId,
        'currency': currency,
        'fc_amount': fcAmount,
        'exchange_rate': exchangeRate,
        'memo': memo,
      };
}

class UnbalancedEntryException implements Exception {
  UnbalancedEntryException(this.debit, this.credit);
  final double debit;
  final double credit;
  @override
  String toString() =>
      'القيد غير متوازن: مدين ${debit.toStringAsFixed(2)} ≠ دائن ${credit.toStringAsFixed(2)}';
}

class LedgerException implements Exception {
  LedgerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// الوصول إلى الحسابات والقيود.
class Ledger {
  Ledger({Future<Database> Function()? getDatabase})
      : _getDb = getDatabase ?? (() => DatabaseService().database);

  final Future<Database> Function() _getDb;

  Future<Database> get db => _getDb();

  // ───────────────────────── الحسابات ─────────────────────────

  Future<List<Account>> allAccounts({bool activeOnly = false}) async {
    final d = await db;
    final rows = await d.query('accounts',
        where: activeOnly ? 'is_active = 1' : null, orderBy: 'code');
    return rows.map(Account.fromMap).toList();
  }

  /// الحسابات التي يجوز الترحيل عليها (ليست مجموعات).
  Future<List<Account>> postableAccounts({bool excludeControl = false}) async {
    final d = await db;
    final rows = await d.query('accounts',
        where: 'is_group = 0 AND is_active = 1${excludeControl ? ' AND is_control = 0' : ''}',
        orderBy: 'code');
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> accountById(int id) async {
    final d = await db;
    final r = await d.query('accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : Account.fromMap(r.first);
  }

  /// يجلب حساباً نظامياً بمفتاحه — يرمي إن لم يوجد (يعني أن المخطط لم يُهيّأ).
  static Future<int> systemAccountId(DatabaseExecutor d, String key) async {
    final r = await d.query('accounts',
        columns: ['id'], where: 'system_key = ?', whereArgs: [key], limit: 1);
    if (r.isEmpty) {
      throw LedgerException('الحساب النظامي «$key» غير موجود في شجرة الحسابات');
    }
    return r.first['id'] as int;
  }

  Future<List<Account>> childrenOf(int? parentId) async {
    final d = await db;
    final rows = await d.query('accounts',
        where: parentId == null ? 'parent_id IS NULL' : 'parent_id = ?',
        whereArgs: parentId == null ? null : [parentId],
        orderBy: 'code');
    return rows.map(Account.fromMap).toList();
  }

  /// رمز مقترح لحساب جديد تحت [parent]: رمز الأب + رقمان متتاليان.
  Future<String> suggestChildCode(Account parent) async {
    final kids = await childrenOf(parent.id);
    var max = 0;
    for (final k in kids) {
      if (k.code.startsWith(parent.code)) {
        final tail = int.tryParse(k.code.substring(parent.code.length));
        if (tail != null && tail > max) max = tail;
      }
    }
    final width = parent.code.length >= 2 ? 2 : 2;
    return '${parent.code}${(max + 1).toString().padLeft(width, '0')}';
  }

  Future<int> createAccount({
    required String code,
    required String name,
    required int parentId,
    bool isGroup = false,
    String? notes,
  }) async {
    final d = await db;
    final parent = await accountById(parentId);
    if (parent == null) throw LedgerException('الحساب الأب غير موجود');
    if (!parent.isGroup) {
      throw LedgerException('لا يمكن إضافة حساب تحت حساب فرعي — اختر حساباً رئيسياً');
    }
    final dup = await d.query('accounts', where: 'code = ?', whereArgs: [code], limit: 1);
    if (dup.isNotEmpty) throw LedgerException('الرمز $code مستخدم لحساب آخر');
    return d.insert('accounts', {
      'code': code,
      'name': name.trim(),
      'parent_id': parentId,
      'type': parent.type,
      'is_group': isGroup ? 1 : 0,
      'is_control': 0,
      'currency': parent.currency,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> renameAccount(int id, String name, {String? notes}) async {
    final d = await db;
    await d.update('accounts', {'name': name.trim(), 'notes': notes},
        where: 'id = ?', whereArgs: [id]);
  }

  /// إيقاف حساب: يُمنع إن كان له رصيد أو كان حساباً نظامياً.
  Future<void> setAccountActive(int id, bool active) async {
    final d = await db;
    final acc = await accountById(id);
    if (acc == null) return;
    if (!active) {
      if (acc.systemKey != null) {
        throw LedgerException('لا يمكن إيقاف حساب يستخدمه النظام (${acc.name})');
      }
      final bal = await d.rawQuery(
          'SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines WHERE account_id = ?',
          [id]);
      final b = (bal.first['b'] as num?)?.toDouble() ?? 0;
      if (b.abs() > kMoneyEpsilon) {
        throw LedgerException('لا يمكن إيقاف حساب رصيده ليس صفراً');
      }
    }
    await d.update('accounts', {'is_active': active ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  // ───────────────────────── القيود ─────────────────────────

  static Future<int> _nextEntryNumber(DatabaseExecutor d) async {
    final r = await d.rawQuery('SELECT COALESCE(MAX(entry_number), 0) + 1 AS n FROM journal_entries');
    return (r.first['n'] as num).toInt();
  }

  static void _checkBalanced(List<JournalLineInput> lines) {
    var dr = 0.0, cr = 0.0;
    for (final l in lines) {
      if (l.debit < 0 || l.credit < 0) {
        throw LedgerException('لا يجوز مبلغ سالب في سطر قيد');
      }
      dr += l.debit;
      cr += l.credit;
    }
    if ((dr - cr).abs() > kMoneyEpsilon) throw UnbalancedEntryException(dr, cr);
    if (dr <= kMoneyEpsilon) throw LedgerException('القيد فارغ');
  }

  /// يحذف السطور الصفرية ويدمج سطرين لنفس الحساب/الطرف في الاتجاه نفسه.
  static List<JournalLineInput> normalize(List<JournalLineInput> lines) {
    final out = <JournalLineInput>[];
    for (final l in lines) {
      var dr = l.debit, cr = l.credit;
      // سطر بمدين ودائن معاً يُحوّل إلى صافٍ
      if (dr > 0 && cr > 0) {
        final net = dr - cr;
        dr = net > 0 ? net : 0;
        cr = net < 0 ? -net : 0;
      }
      if (dr.abs() < kMoneyEpsilon && cr.abs() < kMoneyEpsilon) continue;
      out.add(JournalLineInput(
        accountId: l.accountId,
        debit: dr,
        credit: cr,
        partyType: l.partyType,
        partyId: l.partyId,
        currency: l.currency,
        fcAmount: l.fcAmount,
        exchangeRate: l.exchangeRate,
        memo: l.memo,
      ));
    }
    return out;
  }

  /// يكتب قيداً (أو يستبدل قيد المصدر نفسه إن وُجد). يُستدعى داخل معاملة.
  static Future<int> writeEntry(
    DatabaseExecutor d, {
    required String sourceType,
    int? sourceId,
    String? sourceHash,
    required DateTime date,
    required String description,
    required List<JournalLineInput> lines,
    int branchId = 1,
    int? userId,
  }) async {
    final norm = normalize(lines);
    _checkBalanced(norm);

    int? existingId;
    int? existingNumber;
    if (sourceId != null) {
      final ex = await d.query('journal_entries',
          columns: ['id', 'entry_number'],
          where: 'source_type = ? AND source_id = ?',
          whereArgs: [sourceType, sourceId],
          limit: 1);
      if (ex.isNotEmpty) {
        existingId = ex.first['id'] as int;
        existingNumber = ex.first['entry_number'] as int;
      }
    }

    int entryId;
    if (existingId != null) {
      entryId = existingId;
      await d.delete('journal_lines', where: 'entry_id = ?', whereArgs: [entryId]);
      await d.update(
        'journal_entries',
        {
          'entry_date': date.toIso8601String(),
          'description': description,
          'source_hash': sourceHash,
          'branch_id': branchId,
          'entry_number': existingNumber,
        },
        where: 'id = ?',
        whereArgs: [entryId],
      );
    } else {
      entryId = await d.insert('journal_entries', {
        'entry_number': await _nextEntryNumber(d),
        'entry_date': date.toIso8601String(),
        'description': description,
        'source_type': sourceType,
        'source_id': sourceId,
        'source_hash': sourceHash,
        'branch_id': branchId,
        'created_by_user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    for (final l in norm) {
      await d.insert('journal_lines', l.toMap(entryId));
    }
    return entryId;
  }

  static Future<void> deleteBySource(
      DatabaseExecutor d, String sourceType, int sourceId) async {
    final ex = await d.query('journal_entries',
        columns: ['id'],
        where: 'source_type = ? AND source_id = ?',
        whereArgs: [sourceType, sourceId]);
    for (final r in ex) {
      await d.delete('journal_lines', where: 'entry_id = ?', whereArgs: [r['id']]);
      await d.delete('journal_entries', where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  /// قيد يدوي — يمنع حسابات المراقبة (ذمم العملاء/الموردين).
  Future<int> postManualEntry({
    required DateTime date,
    required String description,
    required List<JournalLineInput> lines,
    int branchId = 1,
    int? userId,
  }) async {
    final d = await db;
    for (final l in lines) {
      final acc = await accountById(l.accountId);
      if (acc == null) throw LedgerException('حساب غير موجود');
      if (acc.isGroup) throw LedgerException('«${acc.name}» حساب رئيسي — اختر حساباً فرعياً');
      if (acc.isControl) {
        throw LedgerException(
            '«${acc.name}» حساب مراقبة — استعمل سجل الديون أو شاشة الموردين بدلاً من القيد اليدوي');
      }
    }
    return d.transaction((txn) async {
      // القيود اليدوية لها مصدر فريد: رقمها السالب حتى لا يتعارض مع UNIQUE
      final r = await txn.rawQuery(
          "SELECT COALESCE(MAX(source_id), 0) + 1 AS n FROM journal_entries WHERE source_type = 'manual'");
      final sid = (r.first['n'] as num).toInt();
      return writeEntry(txn,
          sourceType: 'manual',
          sourceId: sid,
          date: date,
          description: description,
          lines: lines,
          branchId: branchId,
          userId: userId);
    });
  }

  Future<void> deleteManualEntry(int entryId) async {
    final d = await db;
    final e = await d.query('journal_entries',
        columns: ['source_type'], where: 'id = ?', whereArgs: [entryId], limit: 1);
    if (e.isEmpty) return;
    if (e.first['source_type'] != 'manual') {
      throw LedgerException('هذا القيد مولَّد من مستند — عدّل المستند نفسه وسيتعدّل قيده');
    }
    await d.transaction((txn) async {
      await txn.delete('journal_lines', where: 'entry_id = ?', whereArgs: [entryId]);
      await txn.delete('journal_entries', where: 'id = ?', whereArgs: [entryId]);
    });
  }

  Future<List<Map<String, Object?>>> entries({
    DateTime? from,
    DateTime? to,
    String? sourceType,
    int limit = 500,
    int offset = 0,
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('e.entry_date >= ?');
      args.add(_dayStart(from));
    }
    if (to != null) {
      where.add('e.entry_date < ?');
      args.add(_dayAfter(to));
    }
    if (sourceType != null) {
      where.add('e.source_type = ?');
      args.add(sourceType);
    }
    return d.rawQuery('''
      SELECT e.*, COALESCE(SUM(l.debit), 0) AS total
      FROM journal_entries e LEFT JOIN journal_lines l ON l.entry_id = e.id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      GROUP BY e.id
      HAVING COALESCE(SUM(l.debit), 0) > 0
      ORDER BY e.entry_date DESC, e.id DESC
      LIMIT $limit OFFSET $offset
    ''', args);
  }

  Future<List<Map<String, Object?>>> entryLines(int entryId) async {
    final d = await db;
    return d.rawQuery('''
      SELECT l.*, a.code AS account_code, a.name AS account_name
      FROM journal_lines l JOIN accounts a ON a.id = l.account_id
      WHERE l.entry_id = ?
      ORDER BY l.debit DESC, l.id
    ''', [entryId]);
  }

  static String _dayStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String();
  static String _dayAfter(DateTime d) =>
      DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).toIso8601String();

  // ───────────────────────── الإعدادات ─────────────────────────

  static Future<String?> getSetting(DatabaseExecutor d, String key) async {
    final r = await d.query('accounting_settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  static Future<void> setSetting(DatabaseExecutor d, String key, String value) async {
    await d.rawInsert(
        'INSERT INTO accounting_settings(key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value]);
  }

  static Future<double> usdRate(DatabaseExecutor d) async {
    final v = await getSetting(d, 'usd_rate');
    final r = double.tryParse(v ?? '');
    return (r == null || r <= 0) ? 1310 : r;
  }
}
