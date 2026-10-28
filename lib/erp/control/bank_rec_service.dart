// lib/erp/control/bank_rec_service.dart
//
// 🏦 مطابقة كشف البنك: تعلّم حركات صندوق البنك في الدفتر التي ظهرت في كشف البنك،
// حتى يساوي «الرصيد المطابَق» رصيد الكشف. لا يغيّر قيداً ولا رصيداً — يعلّم فقط.
//
//   الرصيد المطابَق = مجموع الحركات المعلَّمة في المطابقات المعتمدة السابقة + المعلَّمة الآن.
//   الفرق = رصيد الكشف − الرصيد المطابَق. لا تُعتمد المطابقة إلا والفرق صفر.
//
// مفتاح الحركة = نوع مصدر القيد ومعرّفه (أو رقم القيد)؛ ويُحفظ مبلغها لحظة التعليم.
// إن تغيّر مبلغ قيد بعد مطابقته (عُدّل مستنده) تعود الحركة «غير مطابقة» تلقائياً.

import 'package:sqflite/sqflite.dart';

import '../activity/activity_log.dart';
import '../erp_common.dart';
import 'control_common.dart';

class BankLine {
  BankLine({required this.key, required this.date, required this.amount, required this.description, required this.entryNo});
  final String key;
  final DateTime date;

  /// موجب = داخل البنك (إيداع)، سالب = خارج (سحب/دفع).
  final double amount;
  final String description;
  final int entryNo;
}

class BankRec {
  BankRec.fromRow(Map<String, Object?> r)
      : id = r['id'] as int,
        boxId = r['box_id'] as int,
        boxName = r['box_name'] as String?,
        statementDate = parseDate(r['statement_date']),
        statementBalance = d0(r['statement_balance']),
        clearedBalance = d0(r['cleared_balance']),
        status = '${r['status']}',
        note = r['note'] as String?,
        createdBy = r['created_by'] as String?,
        finalizedAt = r['finalized_at'] == null ? null : parseDate(r['finalized_at']);
  final int id;
  final int boxId;
  final String? boxName;
  final DateTime statementDate;
  final double statementBalance;
  final double clearedBalance;
  final String status;
  final String? note;
  final String? createdBy;
  final DateTime? finalizedAt;
  bool get isFinal => status == 'final';
}

/// حال مطابقة مفتوحة: كل الحركات حتى تاريخ الكشف، وما عُلّم منها.
class BankRecState {
  BankRecState({
    required this.rec,
    required this.lines,
    required this.marked,
    required this.priorCleared,
    required this.bookBalance,
  });
  final BankRec rec;

  /// الحركات غير المطابقة سابقاً حتى تاريخ الكشف.
  final List<BankLine> lines;

  /// المفاتيح المعلَّمة في هذه المطابقة.
  final Set<String> marked;

  /// مجموع المطابق في المطابقات المعتمدة السابقة.
  final double priorCleared;

  /// رصيد الدفتر حتى تاريخ الكشف.
  final double bookBalance;

  double get clearedNow => lines.where((l) => marked.contains(l.key)).fold<double>(0, (s, l) => s + l.amount);
  double get clearedBalance => round2(priorCleared + clearedNow);
  double get difference => round2(rec.statementBalance - clearedBalance);
  double get unclearedIn =>
      lines.where((l) => !marked.contains(l.key) && l.amount > 0).fold<double>(0, (s, l) => s + l.amount);
  double get unclearedOut =>
      lines.where((l) => !marked.contains(l.key) && l.amount < 0).fold<double>(0, (s, l) => s - l.amount);
  bool get balanced => difference.abs() < 0.01;
}

class BankRecService {
  BankRecService._();

  static Future<List<Map<String, Object?>>> boxes() async {
    final db = await controlDb();
    return db.rawQuery("SELECT id, name, kind, account_id FROM cash_boxes WHERE is_active = 1 ORDER BY kind = 'bank' DESC, id");
  }

  static Future<List<BankRec>> list({int? boxId}) async {
    final db = await controlDb();
    final rows = await db.rawQuery('''
      SELECT r.*, b.name AS box_name FROM bank_recs r LEFT JOIN cash_boxes b ON b.id = r.box_id
      ${boxId == null ? '' : 'WHERE r.box_id = ?'}
      ORDER BY r.statement_date DESC, r.id DESC''', [if (boxId != null) boxId]);
    return rows.map(BankRec.fromRow).toList();
  }

  static Future<int> _accountOf(DatabaseExecutor db, int boxId) async {
    final r = await db.query('cash_boxes', columns: ['account_id'], where: 'id = ?', whereArgs: [boxId], limit: 1);
    if (r.isEmpty) throw ErpException('الصندوق غير موجود');
    return r.first['account_id'] as int;
  }

  /// حركات الصندوق في الدفتر حتى تاريخ [upTo] — صافي كل قيد سطراً واحداً.
  static Future<List<BankLine>> _lines(DatabaseExecutor db, int accountId, DateTime upTo) async {
    final rows = await db.rawQuery('''
      SELECT e.id AS eid, e.entry_number AS no, e.entry_date AS d, e.description AS descr,
             e.source_type AS st, e.source_id AS sid, SUM(l.debit - l.credit) AS amt
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? AND e.entry_date < ?
      GROUP BY e.id
      HAVING ABS(SUM(l.debit - l.credit)) >= 0.005
      ORDER BY e.entry_date, e.id''', [accountId, isoDayAfter(upTo)]);
    return [
      for (final r in rows)
        BankLine(
          key: '${r['st']}:${r['sid'] ?? 'e${r['eid']}'}',
          date: parseDate(r['d']),
          amount: round2(d0(r['amt'])),
          description: (r['descr'] as String?) ?? '',
          entryNo: ((r['no'] as num?) ?? 0).toInt(),
        ),
    ];
  }

  /// المفاتيح المطابقة في المطابقات المعتمدة لهذا الصندوق، بمبلغها.
  static Future<Map<String, double>> _finalMarks(DatabaseExecutor db, int boxId, {int? excludeRec}) async {
    final rows = await db.rawQuery('''
      SELECT m.line_key AS k, m.amount AS a FROM bank_rec_marks m JOIN bank_recs r ON r.id = m.rec_id
      WHERE r.box_id = ? AND r.status = 'final' ${excludeRec == null ? '' : 'AND r.id <> ?'}
      ORDER BY r.statement_date, r.id''',
        [boxId, if (excludeRec != null) excludeRec]);
    return {for (final r in rows) '${r['k']}': d0(r['a'])};
  }

  static Future<int> create({required int boxId, required DateTime statementDate, required double statementBalance, String? note}) async {
    final db = await controlDb();
    final id = await db.transaction((txn) async {
      final draft = await txn.query('bank_recs',
          columns: ['id'], where: "box_id = ? AND status = 'draft'", whereArgs: [boxId], limit: 1);
      if (draft.isNotEmpty) throw ErpException('توجد مطابقة مفتوحة لهذا الصندوق — أكملها أو احذفها أولاً');
      final last = await txn.rawQuery(
          "SELECT MAX(statement_date) AS d FROM bank_recs WHERE box_id = ? AND status = 'final'", [boxId]);
      final lastD = last.first['d'] as String?;
      if (lastD != null && isoDay(statementDate).compareTo(lastD.substring(0, 10)) < 0) {
        throw ErpException('تاريخ الكشف قبل آخر مطابقة معتمدة (${lastD.substring(0, 10)})');
      }
      return txn.insert('bank_recs', {
        'box_id': boxId,
        'statement_date': isoDay(statementDate),
        'statement_balance': round2(statementBalance),
        'status': 'draft',
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'created_by': currentUserName(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    ActivityLog.log('إضافة', 'مطابقة البنك', 'كشف بتاريخ ${isoDay(statementDate).substring(0, 10)} برصيد ${statementBalance.round()}')
        .catchError((_) {});
    return id;
  }

  static Future<BankRecState> load(int recId) async {
    final db = await controlDb();
    final r = await db.rawQuery(
        'SELECT r.*, b.name AS box_name FROM bank_recs r LEFT JOIN cash_boxes b ON b.id = r.box_id WHERE r.id = ?', [recId]);
    if (r.isEmpty) throw ErpException('المطابقة غير موجودة');
    final rec = BankRec.fromRow(r.first);
    final acc = await _accountOf(db, rec.boxId);
    final all = await _lines(db, acc, rec.statementDate);
    final prior = await _finalMarks(db, rec.boxId, excludeRec: rec.id);
    // المطابق سابقاً بالمبلغ نفسه لا يُعرض؛ ما تغيّر مبلغه يعود غير مطابق
    final open = [
      for (final l in all)
        if (!(prior.containsKey(l.key) && (prior[l.key]! - l.amount).abs() < 0.005)) l
    ];
    final priorCleared = all
        .where((l) => prior.containsKey(l.key) && (prior[l.key]! - l.amount).abs() < 0.005)
        .fold<double>(0, (s, l) => s + l.amount);
    final mine = await db.query('bank_rec_marks', where: 'rec_id = ?', whereArgs: [recId]);
    final mineMap = {for (final m in mine) '${m['line_key']}': d0(m['amount'])};
    final marked = <String>{
      for (final l in open)
        if (mineMap.containsKey(l.key) && (mineMap[l.key]! - l.amount).abs() < 0.005) l.key
    };
    return BankRecState(
      rec: rec,
      lines: open,
      marked: marked,
      priorCleared: round2(priorCleared),
      bookBalance: round2(all.fold<double>(0, (s, l) => s + l.amount)),
    );
  }

  /// يعلّم/يلغي تعليم حركة في مطابقة مفتوحة.
  static Future<void> toggle(int recId, BankLine line, bool mark) async {
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('bank_recs', columns: ['status'], where: 'id = ?', whereArgs: [recId], limit: 1);
      if (r.isEmpty || r.first['status'] != 'draft') throw ErpException('المطابقة معتمدة — لا تُعدَّل');
      await txn.delete('bank_rec_marks', where: 'rec_id = ? AND line_key = ?', whereArgs: [recId, line.key]);
      if (mark) {
        await txn.insert('bank_rec_marks', {
          'rec_id': recId,
          'line_key': line.key,
          'amount': line.amount,
          'entry_date': isoDay(line.date),
        });
      }
    });
  }

  /// يعتمد المطابقة إن كان الفرق صفراً.
  static Future<void> finalize(int recId) async {
    final st = await load(recId);
    if (st.rec.isFinal) return;
    if (!st.balanced) throw ErpException('الفرق ليس صفراً (${st.difference}) — لا تُعتمد المطابقة');
    final db = await controlDb();
    await db.transaction((txn) async {
      // تنظيف علامات حركات لم تعد ضمن المفتوح (تغيّر مبلغها)
      final keep = st.marked.toList();
      final all = await txn.query('bank_rec_marks', columns: ['id', 'line_key'], where: 'rec_id = ?', whereArgs: [recId]);
      for (final m in all) {
        if (!keep.contains('${m['line_key']}')) {
          await txn.delete('bank_rec_marks', where: 'id = ?', whereArgs: [m['id']]);
        }
      }
      await txn.update(
          'bank_recs',
          {'status': 'final', 'cleared_balance': st.clearedBalance, 'finalized_at': DateTime.now().toIso8601String()},
          where: "id = ? AND status = 'draft'",
          whereArgs: [recId]);
    });
    ActivityLog.log('اعتماد', 'مطابقة البنك', 'مطابقة رقم $recId').catchError((_) {});
  }

  /// يحذف مطابقة مفتوحة (لم تُعتمد).
  static Future<void> deleteDraft(int recId) async {
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('bank_recs', columns: ['status'], where: 'id = ?', whereArgs: [recId], limit: 1);
      if (r.isEmpty) return;
      if (r.first['status'] != 'draft') throw ErpException('مطابقة معتمدة — استعمل «إلغاء الاعتماد»');
      await txn.delete('bank_rec_marks', where: 'rec_id = ?', whereArgs: [recId]);
      await txn.delete('bank_recs', where: 'id = ?', whereArgs: [recId]);
    });
  }

  /// يعيد آخر مطابقة معتمدة لصندوق إلى «مفتوحة» (المدير فقط).
  static Future<void> reopen(int recId) async {
    if (!await currentIsAdmin()) throw ErpException('إلغاء اعتماد المطابقة للمدير فقط');
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('bank_recs', where: 'id = ?', whereArgs: [recId], limit: 1);
      if (r.isEmpty) return;
      final rec = BankRec.fromRow(r.first);
      if (!rec.isFinal) return;
      final later = await txn.rawQuery(
          "SELECT 1 FROM bank_recs WHERE box_id = ? AND id <> ? AND (status = 'draft' OR (status = 'final' AND statement_date > ?)) LIMIT 1",
          [rec.boxId, rec.id, isoDay(rec.statementDate)]);
      if (later.isNotEmpty) throw ErpException('توجد مطابقة بعدها — أعِد فتح الأحدث أولاً أو احذف المفتوحة');
      await txn.update('bank_recs', {'status': 'draft', 'finalized_at': null}, where: 'id = ?', whereArgs: [recId]);
    });
    ActivityLog.log('إلغاء', 'مطابقة البنك', 'إعادة فتح مطابقة رقم $recId').catchError((_) {});
  }
}
