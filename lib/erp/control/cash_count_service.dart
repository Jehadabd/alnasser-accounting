// lib/erp/control/cash_count_service.dart
//
// 💵 عدّ الدرج — يُحفظ ولا يُعدَّل:
//   • المحاسب يحفظ العدّ من «إقفال اليوم»: المتوقع لحظتها، المعدود، والفرق — لقطة ثابتة.
//   • المدير وحده يراجعه: «اعتماد فقط» (يبقى سجلاً) أو «اعتماد وترحيل الفرق»
//     (قيد: عجز ⇒ مدين فروقات الصندوق / دائن الصندوق؛ زيادة ⇒ العكس) أو «إلغاء».
//   • لا شيء يُرحَّل تلقائياً: القيد لا يوجد إلا بحالة 'posted' التي يضعها المدير،
//     ويُشتق في ErpPosting كبقية المستندات (إلغاء العدّ يحذف قيده).
//   • الفترة المثبّتة تمنع الترحيل والإلغاء بتاريخ داخلها.

import 'package:sqflite/sqflite.dart';

import '../activity/activity_log.dart';
import '../erp_common.dart';
import 'control_common.dart';

class CashCountStatus {
  CashCountStatus._();
  static const pending = 'pending'; // بانتظار مراجعة المدير
  static const approved = 'approved'; // اعتُمد سجلاً فقط (بلا قيد)
  static const posted = 'posted'; // اعتُمد ورُحّل فرقه إلى الدفتر
  static const voided = 'void'; // أُلغي

  static String label(String s) => switch (s) {
        pending => 'بانتظار المراجعة',
        approved => 'معتمد (بلا قيد)',
        posted => 'معتمد ومرحّل',
        voided => 'ملغى',
        _ => s,
      };
}

class CashCount {
  CashCount.fromRow(Map<String, Object?> r)
      : id = r['id'] as int,
        no = (r['count_no'] as num).toInt(),
        day = parseDate(r['count_day']),
        countedAt = parseDate(r['counted_at']),
        source = (r['source'] as String?) ?? '',
        boxId = r['box_id'] as int?,
        boxName = r['box_name'] as String?,
        opening = d0(r['opening']),
        expected = d0(r['expected']),
        counted = d0(r['counted']),
        diff = d0(r['diff']),
        countedBy = (r['counted_by'] as String?) ?? '',
        note = r['note'] as String?,
        status = (r['status'] as String?) ?? CashCountStatus.pending,
        reviewNote = r['review_note'] as String?,
        reviewedBy = r['reviewed_by'] as String?,
        reviewedAt = r['reviewed_at'] == null ? null : parseDate(r['reviewed_at']);

  final int id;
  final int no;
  final DateTime day;
  final DateTime countedAt;
  final String source;
  final int? boxId;
  final String? boxName;
  final double opening;
  final double expected;
  final double counted;
  final double diff;
  final String countedBy;
  final String? note;
  final String status;
  final String? reviewNote;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  bool get isShort => diff <= -kCountTolerance;
  bool get isOver => diff >= kCountTolerance;
  bool get matched => !isShort && !isOver;
}

/// ملخص محاسب واحد في فترة.
class CashierSummary {
  CashierSummary(this.user);
  final String user;
  int counts = 0;
  int shortCount = 0;
  int overCount = 0;
  double shortTotal = 0; // موجب: مجموع العجز
  double overTotal = 0;
  double get net => overTotal - shortTotal;
}

class CashCountService {
  CashCountService._();

  /// يحفظ عدّاً جديداً. الفرق يُحسب هنا لا من الواجهة (المعدود − المتوقع).
  static Future<int> save({
    required DateTime day,
    required String source,
    int? boxId,
    required double opening,
    required double expected,
    required double counted,
    String? note,
  }) async {
    if (counted < 0 || opening < 0) throw ErpException('المبالغ لا تكون سالبة');
    final db = await controlDb();
    final now = DateTime.now().toIso8601String();
    final diff = round2(counted - expected);
    final user = currentUserName();
    final id = await db.transaction((txn) async {
      final no = await nextDocNumber(txn, 'cash_counts', 'count_no');
      return txn.insert('cash_counts', {
        'count_no': no,
        'count_day': isoDay(day),
        'counted_at': now,
        'source': source,
        'box_id': boxId,
        'opening': round2(opening),
        'expected': round2(expected),
        'counted': round2(counted),
        'diff': diff,
        'counted_by': user,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'status': CashCountStatus.pending,
        'created_at': now,
      });
    });
    ActivityLog.log('إضافة', 'عدّ الدرج',
            'عدّ رقم $id ليوم ${isoDay(day).substring(0, 10)}: المتوقع ${expected.round()} المعدود ${counted.round()} الفرق ${diff.round()}')
        .catchError((_) {});
    return id;
  }

  static Future<List<CashCount>> list({DateTime? from, DateTime? to, String? status, String? user}) async {
    final db = await controlDb();
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('c.count_day >= ?');
      args.add(isoDay(from));
    }
    if (to != null) {
      where.add('c.count_day < ?');
      args.add(isoDayAfter(to));
    }
    if (status != null) {
      where.add('c.status = ?');
      args.add(status);
    }
    if (user != null) {
      where.add('c.counted_by = ?');
      args.add(user);
    }
    final rows = await db.rawQuery('''
      SELECT c.*, b.name AS box_name FROM cash_counts c
      LEFT JOIN cash_boxes b ON b.id = c.box_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY c.counted_at DESC, c.id DESC''', args);
    return rows.map(CashCount.fromRow).toList();
  }

  static Future<int> pendingCount() async {
    try {
      final db = await controlDb();
      final r = await db.rawQuery("SELECT COUNT(*) AS n FROM cash_counts WHERE status = 'pending'");
      return ((r.first['n'] as num?) ?? 0).toInt();
    } catch (_) {
      return 0;
    }
  }

  /// ملخص العجز والزيادة لكل محاسب (الملغى لا يُحسب).
  static List<CashierSummary> summarize(List<CashCount> counts) {
    final m = <String, CashierSummary>{};
    for (final c in counts) {
      if (c.status == CashCountStatus.voided) continue;
      final s = m.putIfAbsent(c.countedBy, () => CashierSummary(c.countedBy));
      s.counts++;
      if (c.isShort) {
        s.shortCount++;
        s.shortTotal += -c.diff;
      } else if (c.isOver) {
        s.overCount++;
        s.overTotal += c.diff;
      }
    }
    final list = m.values.toList()..sort((a, b) => b.shortTotal.compareTo(a.shortTotal));
    return list;
  }

  /// مراجعة المدير: [post] = ترحيل الفرق إلى الدفتر.
  static Future<void> review(int id, {required bool post, String? note}) async {
    if (!await currentIsAdmin()) throw ErpException('مراجعة العدّ للمدير فقط');
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('cash_counts', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) throw ErpException('العدّ غير موجود');
      final c = CashCount.fromRow(r.first);
      if (c.status != CashCountStatus.pending) {
        throw ErpException('هذا العدّ رُوجع سابقاً (${CashCountStatus.label(c.status)})');
      }
      final willPost = post && !c.matched;
      if (willPost) {
        await PeriodLock.assertOpen(c.day, txn);
        if (c.boxId == null) throw ErpException('لا صندوق لهذا العدّ — لا يمكن ترحيل فرقه');
      }
      await txn.update(
          'cash_counts',
          {
            'status': willPost ? CashCountStatus.posted : CashCountStatus.approved,
            'review_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
            'reviewed_by': currentUserName(),
            'reviewed_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ? AND status = ?',
          whereArgs: [id, CashCountStatus.pending]);
    });
    ActivityLog.log('اعتماد', 'عدّ الدرج', 'عدّ رقم $id: ${post ? 'اعتماد وترحيل الفرق' : 'اعتماد بلا قيد'}')
        .catchError((_) {});
  }

  /// إلغاء عدّ (المدير فقط، بسبب مكتوب). إن كان مرحّلاً يُحذف قيده عند الترحيل التالي.
  static Future<void> voidCount(int id, String reason) async {
    if (!await currentIsAdmin()) throw ErpException('إلغاء العدّ للمدير فقط');
    if (reason.trim().isEmpty) throw ErpException('اكتب سبب الإلغاء');
    final db = await controlDb();
    await db.transaction((txn) async {
      final r = await txn.query('cash_counts', where: 'id = ?', whereArgs: [id], limit: 1);
      if (r.isEmpty) throw ErpException('العدّ غير موجود');
      final c = CashCount.fromRow(r.first);
      if (c.status == CashCountStatus.voided) return;
      if (c.status == CashCountStatus.posted) await PeriodLock.assertOpen(c.day, txn);
      await txn.update(
          'cash_counts',
          {
            'status': CashCountStatus.voided,
            'review_note': 'ملغى: ${reason.trim()}',
            'reviewed_by': currentUserName(),
            'reviewed_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id]);
    });
    ActivityLog.log('إلغاء', 'عدّ الدرج', 'عدّ رقم $id: $reason').catchError((_) {});
  }

  /// مصادر الترحيل: الأعداد المعتمدة للترحيل بفرق فعلي.
  static Future<List<Map<String, Object?>>> postableRows(DatabaseExecutor db) async {
    final t = await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type='table' AND name='cash_counts'");
    if (t.isEmpty) return const [];
    return db.rawQuery(
        "SELECT * FROM cash_counts WHERE status = 'posted' AND box_id IS NOT NULL AND ABS(diff) >= ?",
        [kCountTolerance]);
  }
}
