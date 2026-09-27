// lib/accounting/accounting_reports.dart
//
// 📊 التقارير المحاسبية: ميزان المراجعة، قائمة الدخل، الميزانية العمومية،
// كشف حساب (دفتر أستاذ).

import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import 'ledger.dart';

class AccountBalanceRow {
  AccountBalanceRow({
    required this.account,
    required this.depth,
    this.openingDebit = 0,
    this.openingCredit = 0,
    this.periodDebit = 0,
    this.periodCredit = 0,
  });

  final Account account;
  final int depth;
  double openingDebit;
  double openingCredit;
  double periodDebit;
  double periodCredit;

  double get totalDebit => openingDebit + periodDebit;
  double get totalCredit => openingCredit + periodCredit;

  /// الرصيد الختامي بإشارة طبيعة الحساب (موجب = في اتجاهه الطبيعي).
  double get natureBalance => account.isDebitNature
      ? totalDebit - totalCredit
      : totalCredit - totalDebit;

  double get closingDebit => totalDebit > totalCredit ? totalDebit - totalCredit : 0;
  double get closingCredit => totalCredit > totalDebit ? totalCredit - totalDebit : 0;

  bool get isEmpty =>
      openingDebit.abs() < kMoneyEpsilon &&
      openingCredit.abs() < kMoneyEpsilon &&
      periodDebit.abs() < kMoneyEpsilon &&
      periodCredit.abs() < kMoneyEpsilon;
}

class IncomeStatement {
  IncomeStatement(this.revenues, this.cogs, this.expenses);
  final List<AccountBalanceRow> revenues;
  final List<AccountBalanceRow> cogs;
  final List<AccountBalanceRow> expenses;

  double _sum(List<AccountBalanceRow> r) =>
      r.fold(0.0, (s, x) => s + x.periodCredit - x.periodDebit);

  double get totalRevenue => _sum(revenues);
  double get totalCogs => -_sum(cogs);
  double get grossProfit => totalRevenue - totalCogs;
  double get totalExpenses => -_sum(expenses);
  double get netProfit => grossProfit - totalExpenses;
}

class BalanceSheet {
  BalanceSheet(this.assets, this.liabilities, this.equity, this.currentProfit);
  final List<AccountBalanceRow> assets;
  final List<AccountBalanceRow> liabilities;
  final List<AccountBalanceRow> equity;

  /// صافي الربح غير المُقفل (الإيرادات − المصاريف حتى التاريخ).
  final double currentProfit;

  double get totalAssets => assets.fold(0.0, (s, r) => s + r.natureBalance);
  double get totalLiabilities => liabilities.fold(0.0, (s, r) => s + r.natureBalance);
  double get totalEquity =>
      equity.fold(0.0, (s, r) => s + r.natureBalance) + currentProfit;
  double get difference => totalAssets - totalLiabilities - totalEquity;
}

class LedgerLine {
  LedgerLine({
    required this.date,
    required this.entryId,
    required this.entryNumber,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.memo,
    this.sourceType,
    this.sourceId,
  });
  final DateTime date;
  final int entryId;
  final int entryNumber;
  final String description;
  final double debit;
  final double credit;
  final double balance;
  final String? memo;
  final String? sourceType;
  final int? sourceId;
}

class AccountStatement {
  AccountStatement(this.account, this.openingBalance, this.lines);
  final Account account;
  final double openingBalance;
  final List<LedgerLine> lines;
  double get closingBalance => lines.isEmpty ? openingBalance : lines.last.balance;
}

class AccountingReports {
  AccountingReports({Future<Database> Function()? getDatabase})
      : _getDb = getDatabase ?? (() => DatabaseService().database);

  final Future<Database> Function() _getDb;

  static String _start(DateTime d) => DateTime(d.year, d.month, d.day).toIso8601String();
  static String _after(DateTime d) =>
      DateTime(d.year, d.month, d.day).add(const Duration(days: 1)).toIso8601String();

  /// أرصدة كل الحسابات (الفرعية) لفترة، مع أرصدة ما قبلها.
  Future<Map<int, List<double>>> _rawBalances(
      DatabaseExecutor db, DateTime? from, DateTime to, {int? branchId}) async {
    final branchFilter = branchId == null ? '' : 'AND e.branch_id = $branchId';
    final fromS = from == null ? '0000' : _start(from);
    final rows = await db.rawQuery('''
      SELECT l.account_id,
             SUM(CASE WHEN e.entry_date < ? THEN l.debit ELSE 0 END) AS od,
             SUM(CASE WHEN e.entry_date < ? THEN l.credit ELSE 0 END) AS oc,
             SUM(CASE WHEN e.entry_date >= ? THEN l.debit ELSE 0 END) AS pd,
             SUM(CASE WHEN e.entry_date >= ? THEN l.credit ELSE 0 END) AS pc
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE e.entry_date < ? $branchFilter
      GROUP BY l.account_id
    ''', [fromS, fromS, fromS, fromS, _after(to)]);
    return {
      for (final r in rows)
        r['account_id'] as int: [
          (r['od'] as num?)?.toDouble() ?? 0,
          (r['oc'] as num?)?.toDouble() ?? 0,
          (r['pd'] as num?)?.toDouble() ?? 0,
          (r['pc'] as num?)?.toDouble() ?? 0,
        ]
    };
  }

  /// ميزان المراجعة الهرمي: كل حساب رئيسي يجمع أبناءه.
  Future<List<AccountBalanceRow>> trialBalance({
    DateTime? from,
    required DateTime to,
    bool hideEmpty = true,
    int? branchId,
  }) async {
    final db = await _getDb();
    final accounts = (await db.query('accounts', orderBy: 'code')).map(Account.fromMap).toList();
    final raw = await _rawBalances(db, from, to, branchId: branchId);

    final byId = {for (final a in accounts) a.id: a};
    final children = <int?, List<Account>>{};
    for (final a in accounts) {
      children.putIfAbsent(a.parentId, () => []).add(a);
    }

    final out = <AccountBalanceRow>[];
    AccountBalanceRow visit(Account a, int depth) {
      final row = AccountBalanceRow(account: a, depth: depth);
      out.add(row);
      final own = raw[a.id];
      if (own != null) {
        row.openingDebit += own[0];
        row.openingCredit += own[1];
        row.periodDebit += own[2];
        row.periodCredit += own[3];
      }
      for (final k in children[a.id] ?? const <Account>[]) {
        final kr = visit(k, depth + 1);
        row.openingDebit += kr.openingDebit;
        row.openingCredit += kr.openingCredit;
        row.periodDebit += kr.periodDebit;
        row.periodCredit += kr.periodCredit;
      }
      return row;
    }

    for (final root in children[null] ?? const <Account>[]) {
      visit(root, 0);
    }
    // حسابات يتيمة (أبوها محذوف) تظهر في الجذر
    for (final a in accounts) {
      if (a.parentId != null && !byId.containsKey(a.parentId)) visit(a, 0);
    }
    return hideEmpty ? out.where((r) => !r.isEmpty).toList() : out;
  }

  Future<IncomeStatement> incomeStatement({
    required DateTime from,
    required DateTime to,
    int? branchId,
  }) async {
    final db = await _getDb();
    final accounts = (await db.query('accounts', where: 'is_group = 0', orderBy: 'code'))
        .map(Account.fromMap)
        .toList();
    final raw = await _rawBalances(db, from, to, branchId: branchId);
    final cogsId = await Ledger.systemAccountId(db, 'cogs');
    final rev = <AccountBalanceRow>[], cogs = <AccountBalanceRow>[], exp = <AccountBalanceRow>[];
    for (final a in accounts) {
      final b = raw[a.id];
      if (b == null) continue;
      final row = AccountBalanceRow(account: a, depth: 0, periodDebit: b[2], periodCredit: b[3]);
      if (row.isEmpty) continue;
      if (a.type == 'revenue') {
        rev.add(row);
      } else if (a.id == cogsId) {
        cogs.add(row);
      } else if (a.type == 'expense') {
        exp.add(row);
      }
    }
    return IncomeStatement(rev, cogs, exp);
  }

  Future<BalanceSheet> balanceSheet({required DateTime asOf, int? branchId}) async {
    final db = await _getDb();
    final accounts = (await db.query('accounts', where: 'is_group = 0', orderBy: 'code'))
        .map(Account.fromMap)
        .toList();
    final raw = await _rawBalances(db, null, asOf, branchId: branchId);
    final assets = <AccountBalanceRow>[], liab = <AccountBalanceRow>[], eq = <AccountBalanceRow>[];
    var profit = 0.0;
    for (final a in accounts) {
      final b = raw[a.id];
      if (b == null) continue;
      final row = AccountBalanceRow(account: a, depth: 0, periodDebit: b[2], periodCredit: b[3]);
      if (row.isEmpty) continue;
      switch (a.type) {
        case 'asset':
          assets.add(row);
          break;
        case 'liability':
          liab.add(row);
          break;
        case 'equity':
          eq.add(row);
          break;
        case 'revenue':
          profit += row.periodCredit - row.periodDebit;
          break;
        case 'expense':
          profit -= row.periodDebit - row.periodCredit;
          break;
      }
    }
    return BalanceSheet(assets, liab, eq, profit);
  }

  /// كشف حساب: رصيد أول المدة + الحركات برصيد تراكمي.
  /// [partyType]/[partyId] لكشف عميل/مورد من حساب المراقبة.
  Future<AccountStatement> accountStatement({
    required int accountId,
    DateTime? from,
    required DateTime to,
    String? partyType,
    int? partyId,
  }) async {
    final db = await _getDb();
    final acc = Account.fromMap(
        (await db.query('accounts', where: 'id = ?', whereArgs: [accountId])).first);
    final sign = acc.isDebitNature ? 1.0 : -1.0;
    final party = partyType == null ? '' : 'AND l.party_type = ? AND l.party_id = ?';
    final partyArgs = partyType == null ? <Object?>[] : <Object?>[partyType, partyId];

    var opening = 0.0;
    if (from != null) {
      final o = await db.rawQuery('''
        SELECT COALESCE(SUM(l.debit - l.credit), 0) AS b
        FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
        WHERE l.account_id = ? AND e.entry_date < ? $party
      ''', [accountId, _start(from), ...partyArgs]);
      opening = ((o.first['b'] as num?)?.toDouble() ?? 0) * sign;
    }
    final rows = await db.rawQuery('''
      SELECT e.id AS entry_id, e.entry_number, e.entry_date, e.description,
             e.source_type, e.source_id, l.debit, l.credit, l.memo
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? AND e.entry_date < ?
        ${from == null ? '' : 'AND e.entry_date >= ?'} $party
      ORDER BY e.entry_date, e.id, l.id
    ''', [accountId, _after(to), if (from != null) _start(from), ...partyArgs]);
    var bal = opening;
    final lines = <LedgerLine>[];
    for (final r in rows) {
      final d = (r['debit'] as num).toDouble();
      final c = (r['credit'] as num).toDouble();
      bal += (d - c) * sign;
      lines.add(LedgerLine(
        date: DateTime.parse(r['entry_date'] as String),
        entryId: r['entry_id'] as int,
        entryNumber: r['entry_number'] as int,
        description: (r['description'] as String?) ?? '',
        debit: d,
        credit: c,
        balance: bal,
        memo: r['memo'] as String?,
        sourceType: r['source_type'] as String?,
        sourceId: r['source_id'] as int?,
      ));
    }
    return AccountStatement(acc, opening, lines);
  }

  /// فحص سلامة: هل يطابق الدفترُ سجلَّ الديون؟ يعيد رسالة لكل اختلاف.
  Future<List<String>> integrityCheck() async {
    final db = await _getDb();
    final problems = <String>[];
    final tb = await db.rawQuery(
        'SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c FROM journal_lines');
    final d = (tb.first['d'] as num).toDouble(), c = (tb.first['c'] as num).toDouble();
    if ((d - c).abs() > 0.05) {
      problems.add('ميزان المراجعة غير متوازن: الفرق ${(d - c).toStringAsFixed(2)}');
    }
    final ar = await Ledger.systemAccountId(db, 'ar_customers');
    final arBal = await db.rawQuery(
        'SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines WHERE account_id = ?', [ar]);
    final cust = await db.rawQuery(
        'SELECT COALESCE(SUM(current_total_debt), 0) AS b FROM customers WHERE COALESCE(is_deleted, 0) = 0');
    final diff = (arBal.first['b'] as num).toDouble() - (cust.first['b'] as num).toDouble();
    if (diff.abs() > 1) {
      problems.add('ذمم العملاء في الدفتر تختلف عن سجل الديون بمقدار ${diff.toStringAsFixed(0)} '
          '— شغّل «ترحيل الآن» ثم أعد الفحص');
    }
    return problems;
  }
}
