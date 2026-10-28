// lib/services/reports/cash_flow.dart
//
// 💵 المقبوض والمدفوع نقداً، وحركة دفتر الديون، لفترة — كل حدث في يومه الفعلي.
//
// «المبيعات» تقول كم بعت، ولا تقول كم دخل الصندوق: البيع الآجل لا يدخل شيئاً،
// وتسديد دين قديم يدخل مالاً بلا مبيعات. القواعد هنا (للقراءة فقط، لا تكتب شيئاً):
//
//   المقبوض:
//   • فاتورة نقدية ⇒ مجموعها يوم الفاتورة.
//   • فاتورة آجلة ⇒ المدفوع منها عند البيع يوم الفاتورة.
//   • فاتورة آجلة حُوّلت إلى نقد في يوم لاحق ⇒ يوم الفاتورة: ما دُفع عند البيع
//     (مجموعها − ما أُلغي من دينها لاحقاً)، ويوم التحويل: ما أُلغي من دينها.
//     (كانت تُحسب كلها يوم الفاتورة فيظهر في يوم مالٌ لم يدخل، ويغيب عن يوم دخل فيه)
//   • تسديد دين يدوي نقدي (لا خصم ولا صك ولا تسوية ولا مرتجع، ولا على صندوق بنك).
//   • سند قبض لتعديل فاتورة نقدية من يوم سابق (زاد مجموعها).
//   المدفوع:
//   • مرتجع مبيعات نقداً (أو الجزء النقدي من المختلط).
//   • سند صرف لتعديل فاتورة نقدية من يوم سابق (نقص مجموعها).
//   تعديل فاتورة نقدية بعد الفترة: مجموعها الحالي يُعاد إلى ما كان عليه في الفترة.
//
//   دفتر الديون: مجموع amount_changed للمعاملات الفعّالة لعملاء غير محذوفين —
//   هو نفسه مجموع أرصدة العملاء، فبداية الفترة + التغيّر = النهاية.

import 'package:sqflite/sqflite.dart';

import 'sales_facts.dart';

/// مجموعة حركات في دفتر الديون (زيادة وتنقيص).
class DebtGroup {
  DebtGroup(this.key, this.label);
  final String key;
  final String label;
  double up = 0; // ما زاد الديون (موجب)
  double down = 0; // ما أنقصها (سالب)
  int count = 0;
  double get net => up + down;
}

class CashFlow {
  CashFlow._();

  // ─── المقبوض ───
  double cashInvoices = 0;
  int cashInvoicesCount = 0;
  double downPayments = 0;
  int downPaymentsCount = 0;
  double conversions = 0;
  int conversionsCount = 0;
  double debtPayments = 0;
  int debtPaymentsCount = 0;
  double editReceipts = 0;
  int editReceiptsCount = 0;

  // ─── المدفوع ───
  double cashRefunds = 0;
  int cashRefundsCount = 0;
  double editRefunds = 0;
  int editRefundsCount = 0;

  // ─── سندات الصناديق النقدية (مصروف، إيراد، قبض، صرف، تحويل مع البنك) ───
  bool vouchersIncluded = false;
  double voucherIn = 0;
  int voucherInCount = 0;
  double voucherOut = 0;
  int voucherOutCount = 0;

  // ─── للعلم ───
  /// تسديدات لا تدخل الدرج: خصم مسموح، صك، تسوية، أو على صندوق بنك.
  double nonCashPayments = 0;
  int nonCashPaymentsCount = 0;

  /// فواتير الفترة النقدية الآن التي كانت آجلة وحُوّلت لاحقاً (تُحسب يوم التحويل).
  double laterConvertedTotal = 0;
  int laterConvertedCount = 0;

  /// ما أُعيد إلى فواتير الفترة لأنها عُدّلت بعد الفترة (+ أُعيد، − طُرح).
  double laterEditsAdjust = 0;

  // ─── دفتر الديون ───
  final Map<String, DebtGroup> debtGroups = {};

  /// null عند فلتر جهاز: رصيد «هذا الجهاز» لا معنى له.
  double? debtStart;
  double? get debtEnd => debtStart == null ? null : debtStart! + debtChange;

  double get debtIncrease => debtGroups.values.fold(0.0, (s, g) => s + g.up);
  double get debtDecrease => debtGroups.values.fold(0.0, (s, g) => s + g.down);
  double get debtChange => debtIncrease + debtDecrease;

  double get salesCashIn => cashInvoices + downPayments + conversions + debtPayments + editReceipts;
  double get salesCashOut => cashRefunds + editRefunds;

  /// المقبوض الصافي من البيع والديون.
  double get netCollected => salesCashIn - salesCashOut;

  /// صافي حركة الدرج = المقبوض الصافي ± سندات الصناديق.
  double get drawerNet => netCollected + voucherIn - voucherOut;

  static const _groupLabels = <String, String>{
    'invoices': 'فواتير آجلة وتعديلاتها',
    'type_change': 'تغيير نوع دفع فواتير (آجل ↔ نقد)',
    'manual_debt': 'ديون يدوية',
    'payments': 'تسديدات',
    'non_cash': 'خصم / صك / تسوية',
    'returns': 'مرتجعات على الحساب',
    'corrections': 'تصحيحات',
    'other': 'أخرى',
  };

  static const _validInv = "COALESCE(NULLIF(TRIM(i.status), ''), 'محفوظة') = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0";

  static Future<bool> _has(DatabaseExecutor db, String table) async =>
      (await db.rawQuery("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table])).isNotEmpty;

  static Future<bool> _hasCol(DatabaseExecutor db, String table, String col) async =>
      (await db.rawQuery('PRAGMA table_info($table)')).any((r) => r['name'] == col);

  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

  /// [facts] وقائع الفترة نفسها [from, to] وبالمصدر نفسه (من ReportsService.loadFacts).
  static Future<CashFlow> load(
    DatabaseExecutor db,
    SalesFacts facts, {
    required DateTime from,
    required DateTime to,
    String source = ReportSource.all,
  }) async {
    final f = CashFlow._();
    final a = SalesFacts.day(from), b = SalesFacts.day(to);
    // فلتر الجهاز للمعاملات بنفس صيغة الديون اليدوية في التقارير
    final txDev = source == ReportSource.thisDevice
        ? ' AND t.is_created_by_me = 1 '
        : (source == ReportSource.sync ? ' AND t.is_created_by_me = 0 ' : '');

    final hasReturns = await _has(db, 'returns');
    final hasExt = await _has(db, 'customer_tx_ext') && await _hasCol(db, 'transactions', 'transaction_uuid');
    final hasBoxes = await _has(db, 'cash_boxes');
    final isDbRet = hasReturns ? 'EXISTS (SELECT 1 FROM returns rr WHERE rr.transaction_id = t.id)' : '0';
    final extKind = hasExt
        ? '(SELECT x.kind FROM customer_tx_ext x WHERE x.transaction_uuid = t.transaction_uuid LIMIT 1)'
        : 'NULL';
    final extBank = hasExt && hasBoxes
        ? "EXISTS (SELECT 1 FROM customer_tx_ext x JOIN cash_boxes bx ON bx.id = x.cash_box_id "
            "WHERE x.transaction_uuid = t.transaction_uuid AND bx.kind <> 'cash')"
        : '0';

    // 1) فواتير نقدية حُوّلت من آجل في يوم لاحق: ما أُلغي من دينها (كل التحويلات اللاحقة)
    final laterConv = <int, double>{};
    final lc = await db.rawQuery('''
      SELECT t.invoice_id AS id, SUM(-t.amount_changed) AS s
      FROM transactions t JOIN invoices i ON i.id = t.invoice_id
      WHERE i.payment_type = 'نقد' AND t.transaction_type = 'invoice_payment_type_change'
        AND t.amount_changed < 0 AND COALESCE(t.is_deleted, 0) = 0
        AND substr(t.transaction_date, 1, 10) > substr(i.invoice_date, 1, 10)
        AND substr(i.invoice_date, 1, 10) >= ? AND substr(i.invoice_date, 1, 10) <= ?
      GROUP BY t.invoice_id''', [a, b]);
    for (final r in lc) {
      laterConv[(r['id'] as num).toInt()] = _d(r['s']);
    }

    // 2) تعديلات فواتير نقدية بسندات (الجدول يُنشأ مع أول سند)
    final laterEdit = <int, double>{}; // فاتورة في الفترة عُدّلت بعدها: + ما يُعاد
    if (await _has(db, 'invoice_edit_vouchers')) {
      final day = 'substr(COALESCE(v.edited_at, v.created_at), 1, 10)';
      final vr = await db.rawQuery('''
        SELECT v.kind AS k, v.amount AS amt, $day AS d, substr(i.invoice_date, 1, 10) AS idate, i.id AS iid
        FROM invoice_edit_vouchers v JOIN invoices i ON i.id = v.invoice_id
        WHERE $_validInv
          AND ((substr(i.invoice_date, 1, 10) >= ? AND substr(i.invoice_date, 1, 10) <= ? AND $day > ?)
            OR (substr(i.invoice_date, 1, 10) < ? AND $day >= ? AND $day <= ?))''', [a, b, b, a, a, b]);
      for (final r in vr) {
        final amt = _d(r['amt']);
        final refund = r['k'] == 'refund';
        if ('${r['idate']}'.compareTo(a) >= 0) {
          final id = (r['iid'] as num).toInt();
          laterEdit[id] = (laterEdit[id] ?? 0) + (refund ? amt : -amt);
        } else if (refund) {
          f.editRefunds += amt;
          f.editRefundsCount++;
        } else {
          f.editReceipts += amt;
          f.editReceiptsCount++;
        }
      }
    }

    // 3) الفواتير
    for (final inv in facts.invoices) {
      if (inv.isCash) {
        final conv = laterConv[inv.id];
        if (conv == null) {
          final adj = laterEdit[inv.id] ?? 0;
          f.cashInvoices += inv.total + adj;
          f.laterEditsAdjust += adj;
          f.cashInvoicesCount++;
        } else {
          f.laterConvertedTotal += inv.total;
          f.laterConvertedCount++;
          final rem = inv.total - conv;
          if (rem > 0.5) {
            f.downPayments += rem;
            f.downPaymentsCount++;
          }
        }
      } else {
        final p = inv.paid;
        if (p > 0.004) {
          f.downPayments += p;
          f.downPaymentsCount++;
        }
      }
    }

    // 4) آجلة حُوّلت إلى نقد في الفترة (فاتورة يوم سابق لها)
    final cv = await db.rawQuery('''
      SELECT COUNT(*) AS n, COALESCE(SUM(-t.amount_changed), 0) AS s
      FROM transactions t JOIN invoices i ON i.id = t.invoice_id
      WHERE $_validInv AND i.payment_type = 'نقد'
        AND t.transaction_type = 'invoice_payment_type_change' AND t.amount_changed < 0
        AND COALESCE(t.is_deleted, 0) = 0
        AND substr(t.transaction_date, 1, 10) > substr(i.invoice_date, 1, 10)
        AND substr(t.transaction_date, 1, 10) >= ? AND substr(t.transaction_date, 1, 10) <= ?
        $txDev''', [a, b]);
    f.conversions = _d(cv.first['s']);
    f.conversionsCount = _d(cv.first['n']).toInt();

    // 5) التسديدات اليدوية: نقدية أو لا
    final pr = await db.rawQuery('''
      SELECT t.amount_changed AS amt, $isDbRet AS r, $extKind AS k, $extBank AS bank
      FROM transactions t
      WHERE t.transaction_type = 'manual_payment' AND t.invoice_id IS NULL AND COALESCE(t.is_deleted, 0) = 0
        AND substr(t.transaction_date, 1, 10) >= ? AND substr(t.transaction_date, 1, 10) <= ?
        $txDev''', [a, b]);
    for (final r in pr) {
      if (_d(r['r']) != 0) continue; // تسديد دين راجع (بضاعة)
      final k = r['k'] as String?;
      if (k == 'sales_return') continue; // مرتجع مبيعات على الحساب
      final amt = -_d(r['amt']);
      if ((k == null || k == 'cash') && _d(r['bank']) == 0) {
        f.debtPayments += amt;
        f.debtPaymentsCount++;
      } else {
        f.nonCashPayments += amt;
        f.nonCashPaymentsCount++;
      }
    }

    // 6) مرتجعات المبيعات النقدية
    for (final r in facts.returns) {
      if (r.cashPart > 0.004) {
        f.cashRefunds += r.cashPart;
        f.cashRefundsCount++;
      }
    }

    // 7) سندات الصناديق النقدية — بلا علَم جهاز، فتُحسب مع «كل الأجهزة» فقط
    if (source == ReportSource.all && hasBoxes && await _has(db, 'vouchers')) {
      final vs = await db.rawQuery('''
        SELECT v.voucher_type AS ty, v.amount AS amt, b1.kind AS k1, b2.kind AS k2
        FROM vouchers v
        LEFT JOIN cash_boxes b1 ON b1.id = v.cash_box_id
        LEFT JOIN cash_boxes b2 ON b2.id = v.to_cash_box_id
        WHERE COALESCE(v.is_deleted, 0) = 0
          AND substr(v.voucher_date, 1, 10) >= ? AND substr(v.voucher_date, 1, 10) <= ?''', [a, b]);
      f.vouchersIncluded = true;
      for (final r in vs) {
        final amt = _d(r['amt']);
        final cash1 = r['k1'] == 'cash';
        final cash2 = r['k2'] == 'cash';
        switch ('${r['ty']}') {
          case 'income':
          case 'receipt':
            if (cash1) {
              f.voucherIn += amt;
              f.voucherInCount++;
            }
            break;
          case 'expense':
          case 'payment':
            if (cash1) {
              f.voucherOut += amt;
              f.voucherOutCount++;
            }
            break;
          case 'transfer':
            if (cash1 && !cash2) {
              f.voucherOut += amt;
              f.voucherOutCount++;
            } else if (!cash1 && cash2) {
              f.voucherIn += amt;
              f.voucherInCount++;
            }
            break;
          default: // opening: رصيد افتتاحي لصندوق — ليس حركة يوم
            break;
        }
      }
    }

    // 8) دفتر الديون
    for (final e in _groupLabels.entries) {
      f.debtGroups[e.key] = DebtGroup(e.key, e.value);
    }
    final dr = await db.rawQuery('''
      SELECT t.transaction_type AS ty, t.amount_changed AS amt, $isDbRet AS r, $extKind AS k
      FROM transactions t JOIN customers c ON c.id = t.customer_id
      WHERE COALESCE(t.is_deleted, 0) = 0 AND COALESCE(c.is_deleted, 0) = 0
        AND substr(t.transaction_date, 1, 10) >= ? AND substr(t.transaction_date, 1, 10) <= ?
        $txDev''', [a, b]);
    for (final r in dr) {
      final g = f.debtGroups[_groupOf('${r['ty']}', r['k'] as String?, _d(r['r']) != 0)]!;
      final amt = _d(r['amt']);
      if (amt >= 0) {
        g.up += amt;
      } else {
        g.down += amt;
      }
      g.count++;
    }
    f.debtGroups.removeWhere((_, g) => g.count == 0);
    if (source == ReportSource.all) {
      final s = await db.rawQuery('''
        SELECT COALESCE(SUM(t.amount_changed), 0) AS s
        FROM transactions t JOIN customers c ON c.id = t.customer_id
        WHERE COALESCE(t.is_deleted, 0) = 0 AND COALESCE(c.is_deleted, 0) = 0
          AND substr(t.transaction_date, 1, 10) < ?''', [a]);
      f.debtStart = _d(s.first['s']);
    }
    return f;
  }

  static String _groupOf(String type, String? kind, bool debtBookReturn) {
    if (debtBookReturn || kind == 'sales_return' || type == 'return_payment') return 'returns';
    if (type == 'invoice_payment_type_change') return 'type_change';
    if (type.startsWith('invoice_') || type == 'SETTLEMENT') return 'invoices';
    if (type.startsWith('تصحيح')) return 'corrections';
    if (kind == 'discount' || kind == 'cheque' || kind == 'cheque_bounce' || kind == 'reconcile') return 'non_cash';
    if (type == 'manual_debt' || type == 'opening_balance' || type == 'Debt_Added') return 'manual_debt';
    if (type == 'manual_payment' || type == 'Debt_Paid') return 'payments';
    return 'other';
  }
}
