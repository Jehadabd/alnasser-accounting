// lib/erp/accounting_plus/month_close_readiness.dart
//
// ✅ جاهزية إقفال الشهر — فحوص قراءة فقط تجمع ما يحتاجه المحاسب قبل التثبيت:
//   1) القيود محدّثة (محرك الترحيل نفسه — آمن للتكرار، يشتق القيود من المستندات).
//   2) توازن القيود: مدين = دائن لكل قيد في الشهر.
//   3) رصيد كل عميل = مجموع معاملاته.
//   4) رصيد كل مورد = مجموع دفتره لكل عملة.
//   5) فواتير «معلّقة» بتاريخ الشهر.
//   6) مواد برصيد سالب.
//   7) عدّ الدرج: أيام فيها مبيعات بلا عدّ، وعدّات بانتظار المراجعة.
//   8) مطابقة البنك حتى نهاية الشهر.
// لا يغيّر أي رقم. الفحص المتعذّر (جدول غير موجود) يُعرض «لا ينطبق» لا «سليم».
// التثبيت نفسه بالدالة الموجودة PeriodLock.setLockDate بعد تأكيد المستخدم.

import 'package:sqflite/sqflite.dart';

import '../../accounting/posting_engine.dart';
import '../erp_common.dart';

enum CheckLevel { ok, warn, fail, na }

class ReadinessCheck {
  ReadinessCheck(this.title, this.level, this.detail, {this.items = const []});
  final String title;
  final CheckLevel level;
  final String detail;

  /// أمثلة (حتى 8) لما يحتاج تصحيحاً.
  final List<String> items;
}

class MonthCloseReadiness {
  MonthCloseReadiness._();

  static const double _eps = 0.01;

  /// اليوم «YYYY-MM-DD» — المقارنة على أول 10 أحرف من العمود تصح أياً كانت صيغة
  /// الوقت المخزنة بعده (T أو مسافة).
  static String _day(DateTime d) => isoDay(d).substring(0, 10);

  static Future<bool> _has(DatabaseExecutor db, String table) async =>
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table])).isNotEmpty;

  static Future<bool> _hasCol(DatabaseExecutor db, String table, String col) async =>
      (await db.rawQuery('PRAGMA table_info($table)')).any((r) => r['name'] == col);

  /// يشغّل كل الفحوص للشهر [month] (أي يوم داخله). [progress] لعرض الخطوة.
  static Future<List<ReadinessCheck>> run(DateTime month, {void Function(String)? progress}) async {
    final out = <ReadinessCheck>[];
    Future<void> step(String name, Future<ReadinessCheck> Function() f) async {
      progress?.call(name);
      try {
        out.add(await f());
      } catch (e) {
        out.add(ReadinessCheck(name, CheckLevel.fail, 'تعذّر الفحص: $e'));
      }
    }

    await step('القيود محدّثة', () async {
      final s = await PostingEngine().syncAll();
      if (s.errors.isEmpty) {
        return ReadinessCheck('القيود محدّثة', CheckLevel.ok, 'كل المستندات لها قيود مطابقة ($s)');
      }
      return ReadinessCheck('القيود محدّثة', CheckLevel.fail, '${s.errors.length} مستند تعذّر ترحيله',
          items: s.errors.take(8).toList());
    });

    out.addAll(await checks(await erpDb(), month, progress: progress));
    return out;
  }

  /// الفحوص على قاعدة معطاة (بلا خطوة الترحيل) — للاختبار ولـ [run].
  static Future<List<ReadinessCheck>> checks(DatabaseExecutor db, DateTime month,
      {void Function(String)? progress}) async {
    final from = DateTime(month.year, month.month, 1);
    final next = DateTime(month.year, month.month + 1, 1);
    final out = <ReadinessCheck>[];
    Future<void> step(String name, Future<ReadinessCheck> Function() f) async {
      progress?.call(name);
      try {
        out.add(await f());
      } catch (e) {
        out.add(ReadinessCheck(name, CheckLevel.fail, 'تعذّر الفحص: $e'));
      }
    }

    await step('توازن القيود', () => _balanced(db, from, next));
    await step('أرصدة العملاء', () => _customers(db));
    await step('أرصدة الموردين', () => _suppliers(db));
    await step('فواتير معلّقة', () => _pending(db, from, next));
    await step('مواد برصيد سالب', () => _negativeStock(db));
    await step('عدّ الدرج', () => _cashCounts(db, from, next));
    await step('مطابقة البنك', () => _bank(db, next));
    return out;
  }

  static Future<ReadinessCheck> _balanced(DatabaseExecutor db, DateTime from, DateTime next) async {
    const t = 'توازن القيود';
    if (!await _has(db, 'journal_entries')) return ReadinessCheck(t, CheckLevel.na, 'المحاسبة غير مفعّلة');
    final r = await db.rawQuery('''
      SELECT e.entry_number, e.description, ROUND(SUM(l.debit) - SUM(l.credit), 2) AS d
      FROM journal_entries e JOIN journal_lines l ON l.entry_id = e.id
      WHERE substr(e.entry_date, 1, 10) >= ? AND substr(e.entry_date, 1, 10) < ?
      GROUP BY e.id HAVING ABS(SUM(l.debit) - SUM(l.credit)) > ?
      ORDER BY e.entry_number''', [_day(from), _day(next), _eps]);
    if (r.isEmpty) return ReadinessCheck(t, CheckLevel.ok, 'كل قيود الشهر متوازنة');
    return ReadinessCheck(t, CheckLevel.fail, '${r.length} قيد غير متوازن',
        items: [for (final x in r.take(8)) 'قيد ${x['entry_number']}: فرق ${x['d']} — ${x['description'] ?? ''}']);
  }

  static Future<ReadinessCheck> _customers(DatabaseExecutor db) async {
    const t = 'أرصدة العملاء';
    final r = await db.rawQuery('''
      SELECT c.name, ROUND(COALESCE(c.current_total_debt, 0), 2) AS card,
             ROUND(COALESCE((SELECT SUM(x.amount_changed) FROM transactions x
                             WHERE x.customer_id = c.id AND COALESCE(x.is_deleted, 0) = 0), 0), 2) AS tx
      FROM customers c
      WHERE COALESCE(c.is_deleted, 0) = 0
        AND ABS(COALESCE(c.current_total_debt, 0) - COALESCE((SELECT SUM(x.amount_changed) FROM transactions x
                 WHERE x.customer_id = c.id AND COALESCE(x.is_deleted, 0) = 0), 0)) > ?
      ORDER BY c.name''', [_eps]);
    if (r.isEmpty) return ReadinessCheck(t, CheckLevel.ok, 'رصيد كل عميل يساوي مجموع معاملاته');
    return ReadinessCheck(t, CheckLevel.fail,
        '${r.length} عميل رصيد بطاقته لا يساوي مجموع معاملاته — افتح حسابه واستعمل «فحص السلامة المالية»',
        items: [for (final x in r.take(8)) '${x['name']}: البطاقة ${x['card']} • المعاملات ${x['tx']}']);
  }

  static Future<ReadinessCheck> _suppliers(DatabaseExecutor db) async {
    const t = 'أرصدة الموردين';
    if (!await _has(db, 'supplier_transactions') || !await _hasCol(db, 'suppliers', 'total_debt_usd')) {
      return ReadinessCheck(t, CheckLevel.na, 'لا دفتر موردين');
    }
    final r = await db.rawQuery('''
      SELECT s.name,
             ROUND(COALESCE(s.total_debt_iqd, 0), 2) AS iqd,
             ROUND(COALESCE((SELECT SUM(x.amount_changed) FROM supplier_transactions x WHERE x.supplier_id = s.id
                    AND COALESCE(x.is_deleted, 0) = 0 AND COALESCE(x.currency, 'IQD') = 'IQD'), 0), 2) AS tx_iqd,
             ROUND(COALESCE(s.total_debt_usd, 0), 2) AS usd,
             ROUND(COALESCE((SELECT SUM(x.amount_changed) FROM supplier_transactions x WHERE x.supplier_id = s.id
                    AND COALESCE(x.is_deleted, 0) = 0 AND x.currency = 'USD'), 0), 2) AS tx_usd
      FROM suppliers s''');
    final bad = r.where((x) =>
        ((x['iqd'] as num) - (x['tx_iqd'] as num)).abs() > _eps || ((x['usd'] as num) - (x['tx_usd'] as num)).abs() > _eps);
    final list = bad.toList();
    if (list.isEmpty) return ReadinessCheck(t, CheckLevel.ok, 'رصيد كل مورد يساوي مجموع دفتره');
    return ReadinessCheck(t, CheckLevel.fail, '${list.length} مورد رصيده لا يساوي دفتره — افتح كشف حسابه ليُعاد بناؤه',
        items: [
          for (final x in list.take(8)) '${x['name']}: دينار ${x['iqd']}/${x['tx_iqd']} • دولار ${x['usd']}/${x['tx_usd']}'
        ]);
  }

  static Future<ReadinessCheck> _pending(DatabaseExecutor db, DateTime from, DateTime next) async {
    const t = 'فواتير معلّقة';
    final r = await db.rawQuery('''
      SELECT id, invoice_number, customer_name, invoice_date FROM invoices
      WHERE COALESCE(is_deleted, 0) = 0 AND TRIM(COALESCE(status, '')) = 'معلقة'
        AND substr(invoice_date, 1, 10) >= ? AND substr(invoice_date, 1, 10) < ?
      ORDER BY invoice_date''', [_day(from), _day(next)]);
    if (r.isEmpty) return ReadinessCheck(t, CheckLevel.ok, 'لا فواتير معلّقة بتاريخ الشهر');
    return ReadinessCheck(t, CheckLevel.warn, '${r.length} فاتورة معلّقة بتاريخ الشهر — لا تدخل المبيعات ولا القيود',
        items: [
          for (final x in r.take(8))
            '${x['invoice_number'] ?? '#${x['id']}'} — ${x['customer_name'] ?? ''} — ${'${x['invoice_date']}'.split('T').first}'
        ]);
  }

  static Future<ReadinessCheck> _negativeStock(DatabaseExecutor db) async {
    const t = 'مواد برصيد سالب';
    final r = await db.rawQuery('''
      SELECT name, stock_quantity FROM products
      WHERE COALESCE(is_deleted, 0) = 0 AND COALESCE(stock_quantity, 0) < -0.0001
      ORDER BY stock_quantity''');
    if (r.isEmpty) return ReadinessCheck(t, CheckLevel.ok, 'لا مادة رصيدها سالب');
    return ReadinessCheck(t, CheckLevel.warn, '${r.length} مادة رصيدها سالب — بيع بلا إدخال شراء، تكلفتها في الأرباح غير دقيقة',
        items: [for (final x in r.take(8)) '${x['name']}: ${x['stock_quantity']}']);
  }

  static Future<ReadinessCheck> _cashCounts(DatabaseExecutor db, DateTime from, DateTime next) async {
    const t = 'عدّ الدرج';
    if (!await _has(db, 'cash_counts')) return ReadinessCheck(t, CheckLevel.na, 'لم يُستعمل عدّ الدرج');
    final days = await db.rawQuery('''
      SELECT DISTINCT substr(invoice_date, 1, 10) AS d FROM invoices
      WHERE COALESCE(is_deleted, 0) = 0 AND COALESCE(NULLIF(TRIM(status), ''), 'محفوظة') = 'محفوظة'
        AND payment_type = 'نقد' AND substr(invoice_date, 1, 10) >= ? AND substr(invoice_date, 1, 10) < ?
        AND substr(invoice_date, 1, 10) NOT IN
            (SELECT substr(count_day, 1, 10) FROM cash_counts WHERE status != 'void')
      ORDER BY d''', [_day(from), _day(next)]);
    final pending = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM cash_counts WHERE status = 'pending' "
        'AND substr(count_day, 1, 10) >= ? AND substr(count_day, 1, 10) < ?',
        [_day(from), _day(next)]);
    final p = ((pending.first['n'] as num?) ?? 0).toInt();
    if (days.isEmpty && p == 0) return ReadinessCheck(t, CheckLevel.ok, 'كل أيام البيع النقدي لها عدّ معتمد');
    return ReadinessCheck(
      t,
      CheckLevel.warn,
      [
        if (days.isNotEmpty) '${days.length} يوم فيه بيع نقدي بلا عدّ درج',
        if (p > 0) '$p عدّ بانتظار مراجعة المدير',
      ].join(' • '),
      items: [for (final x in days.take(8)) '${x['d']}'],
    );
  }

  static Future<ReadinessCheck> _bank(DatabaseExecutor db, DateTime next) async {
    const t = 'مطابقة البنك';
    if (!await _has(db, 'cash_boxes')) return ReadinessCheck(t, CheckLevel.na, 'لا صناديق');
    final banks = await db.rawQuery("SELECT id, name FROM cash_boxes WHERE kind = 'bank' AND COALESCE(is_active, 1) = 1");
    if (banks.isEmpty) return ReadinessCheck(t, CheckLevel.na, 'لا حسابات بنكية');
    if (!await _has(db, 'bank_recs')) {
      return ReadinessCheck(t, CheckLevel.warn, '${banks.length} حساب بنكي لم يُطابق أبداً',
          items: [for (final b in banks) '${b['name']}']);
    }
    final monthEnd = _day(next.subtract(const Duration(days: 1)));
    final missing = <String>[];
    for (final b in banks) {
      final r = await db.rawQuery(
          "SELECT 1 FROM bank_recs WHERE box_id = ? AND status = 'final' AND substr(statement_date, 1, 10) >= ? LIMIT 1", [b['id'], monthEnd]);
      if (r.isEmpty) missing.add('${b['name']}');
    }
    if (missing.isEmpty) return ReadinessCheck(t, CheckLevel.ok, 'كل الحسابات البنكية مطابَقة حتى نهاية الشهر');
    return ReadinessCheck(t, CheckLevel.warn, '${missing.length} حساب بنكي غير مطابَق حتى نهاية الشهر', items: missing);
  }
}
