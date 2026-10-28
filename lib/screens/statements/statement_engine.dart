// lib/screens/statements/statement_engine.dart
//
// 📄 محرك كشوفات حساب العميل — قراءة فقط، لا يكتب شيئاً.
//
// الفترة:   شامل | من آخر مرة كان رصيده صفراً | من تاريخ إلى تاريخ
// التفصيل:  تفصيلي (كل معاملة، ومواد الفاتورة، وتعديلاتها) | ملخص (سطر واحد لكل
//           فاتورة بصافي أثرها، بلا عمليات التعديل)
// والكشف التجاري لصاحب المتجر: كم سحب بالدين وبالنقد، بالفواتير وبالمعاملات
// اليدوية، وكم سدّد، وكل فاتورة بمبلغها.
//
// الرصيد: رصيد العميل في البرنامج = مجموع معاملاته الفعّالة، فالكشف يحسب
// الرصيد التراكمي من المعاملات نفسها بالترتيب (التاريخ ثم الرقم) — آخر رصيد
// في الكشف الشامل يساوي رصيد العميل حرفياً.

import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../../services/invoice_edit_log.dart';

enum StmtPeriodKind { all, sinceZero, range }

enum StmtDetail { detailed, summary }

class StmtPeriod {
  final StmtPeriodKind kind;
  final DateTime? from;
  final DateTime? to;
  const StmtPeriod.all()
      : kind = StmtPeriodKind.all,
        from = null,
        to = null;
  const StmtPeriod.sinceZero()
      : kind = StmtPeriodKind.sinceZero,
        from = null,
        to = null;
  const StmtPeriod.range(DateTime this.from, DateTime this.to) : kind = StmtPeriodKind.range;

  String get label {
    switch (kind) {
      case StmtPeriodKind.all:
        return 'شامل';
      case StmtPeriodKind.sinceZero:
        return 'من آخر رصيد صفر';
      case StmtPeriodKind.range:
        return 'من ${_d(from!)} إلى ${_d(to!)}';
    }
  }
}

String _d(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
String stmtDate(DateTime d) => _d(d);

class StmtLine {
  final String name;
  final String unit;
  final double qty;
  final double price;
  final double total;
  const StmtLine(this.name, this.unit, this.qty, this.price, this.total);
}

class StmtInvoice {
  final int id;
  final String number;
  final DateTime date;
  final String paymentType;
  final double total;
  final double paid;
  final double discount;
  final double loadingFee;
  final String status;
  final List<StmtLine> lines;
  final List<InvoiceEditChange> edits;
  StmtInvoice({
    required this.id,
    required this.number,
    required this.date,
    required this.paymentType,
    required this.total,
    required this.paid,
    required this.discount,
    required this.loadingFee,
    required this.status,
    required this.lines,
    required this.edits,
  });
  bool get isDebt => paymentType == 'دين';
  double get remaining => isDebt ? total - paid : 0;
  double get editAdds =>
      edits.where((e) => e.kind == InvoiceEditLog.kindAdd).fold(0.0, (a, e) => a + e.amountDelta);
  double get editReturns =>
      edits.where((e) => e.kind == InvoiceEditLog.kindReturn).fold(0.0, (a, e) => a - e.amountDelta);
}

/// نوع السطر (للون والأيقونة)
enum StmtKind { invoice, invoiceEdit, debt, payment, discount, salesReturn, opening, other }

class StmtRow {
  final DateTime date;
  final String title;
  final String? note;
  final double amount; // + يزيد الدين، − ينقصه
  final StmtKind kind;
  final StmtInvoice? invoice;

  /// تفصيلي: تُعرض مواد الفاتورة وتعديلاتها تحت أول سطر لها فقط
  final bool showInvoiceBody;
  double balanceAfter = 0;
  StmtRow({
    required this.date,
    required this.title,
    required this.amount,
    required this.kind,
    this.note,
    this.invoice,
    this.showInvoiceBody = false,
  });
  bool get isDebit => amount > 0;
}

class StatementResult {
  final String customerName;
  final StmtPeriod period;
  final StmtDetail detail;
  final DateTime? fromDate;
  final DateTime? toDate;
  final double opening;
  final double closing;
  final double debit;
  final double credit;
  final List<StmtRow> rows;

  /// لكشف «من آخر رصيد صفر»: تاريخ آخر مرة صار رصيده صفراً (null = لم يكن صفراً)
  final DateTime? zeroAt;
  const StatementResult({
    required this.customerName,
    required this.period,
    required this.detail,
    required this.fromDate,
    required this.toDate,
    required this.opening,
    required this.closing,
    required this.debit,
    required this.credit,
    required this.rows,
    this.zeroAt,
  });

  String get periodText {
    switch (period.kind) {
      case StmtPeriodKind.all:
        return 'كل الحركات منذ البداية';
      case StmtPeriodKind.sinceZero:
        return zeroAt == null
            ? 'لم يكن رصيده صفراً من قبل — كل الحركات منذ البداية'
            : 'منذ صار رصيده صفراً في ${_d(zeroAt!)}';
      case StmtPeriodKind.range:
        return period.label;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// الكشف التجاري
// ─────────────────────────────────────────────────────────────────────────────

class CommercialResult {
  final String customerName;
  final StmtPeriod period;
  final String periodText;
  final double opening;
  final double closing;

  // بالدين
  final List<StmtInvoice> debtInvoices;
  final double manualDebt;
  final int manualDebtCount;

  // بالنقد
  final List<StmtInvoice> cashInvoices;

  // ما نقص الدين
  final double payments;
  final int paymentCount;
  final double discounts;
  final double returnsCredit; // مرتجعات نزلت من حسابه (معاملات)
  final double other; // تصحيحات/تسويات/رصيد افتتاحي
  final int otherCount;

  // مرتجع نقداً من الصندوق (سندات مرتجع) — لا تمس الدين
  final double cashReturns;
  final int cashReturnsCount;

  /// كل ما زاد الدين / نقصه في الفترة (فواتير ويدوي) — لشريط الرصيد
  final double windowDebit;
  final double windowCredit;

  const CommercialResult({
    required this.customerName,
    required this.period,
    required this.periodText,
    required this.opening,
    required this.closing,
    required this.debtInvoices,
    required this.manualDebt,
    required this.manualDebtCount,
    required this.cashInvoices,
    required this.payments,
    required this.paymentCount,
    required this.discounts,
    required this.returnsCredit,
    required this.other,
    required this.otherCount,
    required this.cashReturns,
    required this.cashReturnsCount,
    required this.windowDebit,
    required this.windowCredit,
  });

  double get debtInvoicesTotal => debtInvoices.fold(0.0, (a, i) => a + i.total);
  double get debtInvoicesPaid => debtInvoices.fold(0.0, (a, i) => a + i.paid);
  double get debtInvoicesRemaining => debtInvoices.fold(0.0, (a, i) => a + i.remaining);
  double get cashInvoicesTotal => cashInvoices.fold(0.0, (a, i) => a + i.total);
  double get totalWithdrawn => debtInvoicesTotal + manualDebt + cashInvoicesTotal;
  double get editReturns =>
      [...debtInvoices, ...cashInvoices].fold(0.0, (a, i) => a + i.editReturns);
  double get editAdds => [...debtInvoices, ...cashInvoices].fold(0.0, (a, i) => a + i.editAdds);
}

// ─────────────────────────────────────────────────────────────────────────────

class _Tx {
  final int id;
  final DateTime date;
  final double amount;
  final String? type;
  final String? kind;
  final String? note;
  final int? invoiceId;
  _Tx(this.id, this.date, this.amount, this.type, this.kind, this.note, this.invoiceId);
}

class _Window {
  final int start; // أول فهرس داخل الفترة
  final int end; // آخر فهرس داخل الفترة (قد يكون < start ⇒ فارغة)
  final double opening;
  final DateTime? from;
  final DateTime? to;
  final DateTime? zeroAt;
  _Window(this.start, this.end, this.opening, this.from, this.to, this.zeroAt);
}

class StatementEngine {
  StatementEngine._();

  static const double _zeroEps = 0.5; // أقل من نصف دينار = صفر

  static Future<List<_Tx>> _loadTx(DatabaseExecutor db, int customerId) async {
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery('''
        SELECT t.id, t.transaction_date, t.amount_changed, t.transaction_type, t.transaction_note,
               t.invoice_id, e.kind AS ext_kind
        FROM transactions t
        LEFT JOIN customer_tx_ext e ON e.transaction_uuid = t.transaction_uuid
        WHERE t.customer_id = ? AND COALESCE(t.is_deleted, 0) = 0
        ORDER BY t.transaction_date ASC, t.id ASC''', [customerId]);
    } catch (_) {
      // قاعدة بلا جدول customer_tx_ext
      rows = await db.rawQuery('''
        SELECT id, transaction_date, amount_changed, transaction_type, transaction_note, invoice_id,
               NULL AS ext_kind
        FROM transactions
        WHERE customer_id = ? AND COALESCE(is_deleted, 0) = 0
        ORDER BY transaction_date ASC, id ASC''', [customerId]);
    }
    return [
      for (final r in rows)
        _Tx(
          r['id'] as int,
          DateTime.tryParse('${r['transaction_date']}') ?? DateTime(2000),
          (r['amount_changed'] as num?)?.toDouble() ?? 0.0,
          r['transaction_type'] as String?,
          r['ext_kind'] as String?,
          (r['transaction_note'] as String?)?.trim(),
          r['invoice_id'] as int?,
        ),
    ];
  }

  static _Window _window(List<_Tx> txs, StmtPeriod p) {
    final n = txs.length;
    final run = List<double>.filled(n, 0);
    var acc = 0.0;
    for (var i = 0; i < n; i++) {
      acc += txs[i].amount;
      run[i] = acc;
    }
    switch (p.kind) {
      case StmtPeriodKind.all:
        return _Window(0, n - 1, 0, null, null, null);
      case StmtPeriodKind.sinceZero:
        // آخر مرة صار فيها الرصيد صفراً قبل الحركة الأخيرة (إن كان الآن صفراً
        // فالكشف هو الدورة التي انتهت بالصفر)
        var z = -1;
        for (var i = n - 2; i >= 0; i--) {
          if (run[i].abs() < _zeroEps) {
            z = i;
            break;
          }
        }
        final s = z + 1;
        return _Window(s, n - 1, z >= 0 ? run[z] : 0, s < n ? txs[s].date : null, null,
            z >= 0 ? txs[z].date : null);
      case StmtPeriodKind.range:
        final from = DateTime(p.from!.year, p.from!.month, p.from!.day);
        final to = DateTime(p.to!.year, p.to!.month, p.to!.day, 23, 59, 59, 999);
        var s = 0;
        while (s < n && txs[s].date.isBefore(from)) {
          s++;
        }
        var e = s - 1;
        while (e + 1 < n && !txs[e + 1].date.isAfter(to)) {
          e++;
        }
        return _Window(s, e, s > 0 ? run[s - 1] : 0, from, to, null);
    }
  }

  static Future<Map<int, StmtInvoice>> _loadInvoices(DatabaseExecutor db, Iterable<int> ids) async {
    final list = ids.toSet().toList();
    final out = <int, StmtInvoice>{};
    if (list.isEmpty) return out;
    final edits = await InvoiceEditLog.forInvoices(db, list);
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.sublist(i, (i + 400).clamp(0, list.length));
      final ph = List.filled(chunk.length, '?').join(',');
      final heads = await db.rawQuery(
          'SELECT id, invoice_number, invoice_date, payment_type, total_amount, amount_paid_on_invoice, '
          'discount, loading_fee, status FROM invoices WHERE id IN ($ph)',
          chunk);
      final items = await db.rawQuery(
          'SELECT invoice_id, product_name, sale_type, quantity_individual, quantity_large_unit, '
          'applied_price, item_total FROM invoice_items WHERE invoice_id IN ($ph) ORDER BY id',
          chunk);
      final byInv = <int, List<StmtLine>>{};
      for (final r in items) {
        final q = (r['quantity_individual'] as num?)?.toDouble() ??
            (r['quantity_large_unit'] as num?)?.toDouble() ??
            0.0;
        byInv.putIfAbsent(r['invoice_id'] as int, () => []).add(StmtLine(
              '${r['product_name'] ?? ''}',
              '${r['sale_type'] ?? ''}',
              q,
              (r['applied_price'] as num?)?.toDouble() ?? 0,
              (r['item_total'] as num?)?.toDouble() ?? 0,
            ));
      }
      for (final h in heads) {
        final id = h['id'] as int;
        final no = '${h['invoice_number'] ?? ''}'.trim();
        out[id] = StmtInvoice(
          id: id,
          number: no.isEmpty ? '$id' : no,
          date: DateTime.tryParse('${h['invoice_date']}') ?? DateTime(2000),
          paymentType: '${h['payment_type'] ?? ''}',
          total: (h['total_amount'] as num?)?.toDouble() ?? 0,
          paid: (h['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0,
          discount: (h['discount'] as num?)?.toDouble() ?? 0,
          loadingFee: (h['loading_fee'] as num?)?.toDouble() ?? 0,
          status: '${h['status'] ?? ''}',
          lines: byInv[id] ?? const [],
          edits: edits[id] ?? const [],
        );
      }
    }
    return out;
  }

  static StmtKind _kindOf(_Tx t) {
    if (t.invoiceId != null) return StmtKind.invoice;
    switch (t.kind) {
      case 'discount':
        return StmtKind.discount;
      case 'sales_return':
        return StmtKind.salesReturn;
    }
    switch (t.type) {
      case 'opening_balance':
        return StmtKind.opening;
      case 'manual_debt':
      case 'Debt_Added':
        return StmtKind.debt;
      case 'manual_payment':
      case 'Debt_Paid':
        return StmtKind.payment;
      case 'return_payment':
        return StmtKind.salesReturn;
      case 'correction':
      case 'SETTLEMENT':
      case 'تصحيح_زيادة':
      case 'تصحيح_نقص':
        return StmtKind.other;
    }
    if (t.type == null || t.type!.isEmpty) return t.amount >= 0 ? StmtKind.debt : StmtKind.payment;
    return StmtKind.other;
  }

  static String _invoiceTxLabel(String? type, double amount, bool first) {
    switch (type) {
      case 'invoice_debt':
        return 'دين الفاتورة';
      case 'invoice_edit':
      case 'invoice_live_update':
      case 'Invoice_Debt_Adjustment':
        return 'تعديل الفاتورة';
      case 'invoice_payment_type_change':
        return 'تغيير طريقة الدفع';
      case 'invoice_customer_change':
        return 'نقل الفاتورة بين العملاء';
      case 'Invoice_Debt_Reversal':
        return 'حذف الفاتورة';
      case 'invoice_debt_sync':
        return first ? 'دين الفاتورة' : 'تعديل الفاتورة';
    }
    return first ? 'دين الفاتورة' : 'تعديل الفاتورة';
  }

  static String _plainLabel(StmtKind k, _Tx t) {
    switch (k) {
      case StmtKind.debt:
        return 'دين يدوي';
      case StmtKind.payment:
        return 'تسديد';
      case StmtKind.discount:
        return 'خصم مسموح';
      case StmtKind.salesReturn:
        return 'مرتجع من حسابه';
      case StmtKind.opening:
        return 'رصيد افتتاحي';
      case StmtKind.other:
        return t.amount >= 0 ? 'تصحيح (زيادة)' : 'تصحيح (نقص)';
      case StmtKind.invoice:
      case StmtKind.invoiceEdit:
        return 'فاتورة';
    }
  }

  /// كشف الحساب
  static Future<StatementResult> account({
    required int customerId,
    required String customerName,
    required StmtPeriod period,
    required StmtDetail detail,
  }) async {
    final db = await DatabaseService().database;
    final txs = await _loadTx(db, customerId);
    final w = _window(txs, period);
    final inWin = w.end >= w.start ? txs.sublist(w.start, w.end + 1) : <_Tx>[];

    // أول ظهور لكل فاتورة في القاعدة كلها (لتمييز «دين الفاتورة» من «تعديلها»)
    final firstIdx = <int, int>{};
    for (var i = 0; i < txs.length; i++) {
      final inv = txs[i].invoiceId;
      if (inv != null) firstIdx.putIfAbsent(inv, () => i);
    }
    final invoices = await _loadInvoices(db, inWin.map((t) => t.invoiceId).whereType<int>());

    final rows = <StmtRow>[];
    if (detail == StmtDetail.detailed) {
      final bodyShown = <int>{};
      for (var k = 0; k < inWin.length; k++) {
        final t = inWin[k];
        final kind = _kindOf(t);
        if (t.invoiceId != null) {
          final inv = invoices[t.invoiceId];
          final first = firstIdx[t.invoiceId] == w.start + k;
          final show = inv != null && bodyShown.add(t.invoiceId!);
          rows.add(StmtRow(
            date: t.date,
            title: 'فاتورة ${inv?.number ?? t.invoiceId} — ${_invoiceTxLabel(t.type, t.amount, first)}',
            note: t.note,
            amount: t.amount,
            kind: first ? StmtKind.invoice : StmtKind.invoiceEdit,
            invoice: inv,
            showInvoiceBody: show,
          ));
        } else {
          rows.add(StmtRow(date: t.date, title: _plainLabel(kind, t), note: t.note, amount: t.amount, kind: kind));
        }
      }
    } else {
      // ملخص: سطر واحد لكل فاتورة (صافي أثرها في الفترة) في موضع أول حركة لها
      final pos = <int, int>{};
      final sums = <int, double>{};
      for (final t in inWin) {
        if (t.invoiceId == null) {
          final kind = _kindOf(t);
          rows.add(StmtRow(date: t.date, title: _plainLabel(kind, t), note: t.note, amount: t.amount, kind: kind));
        } else {
          sums[t.invoiceId!] = (sums[t.invoiceId!] ?? 0) + t.amount;
          if (!pos.containsKey(t.invoiceId)) {
            pos[t.invoiceId!] = rows.length;
            rows.add(StmtRow(date: t.date, title: '', amount: 0, kind: StmtKind.invoice)); // يُستبدل أدناه
          }
        }
      }
      pos.forEach((invId, i) {
        final inv = invoices[invId];
        final old = rows[i];
        rows[i] = StmtRow(
          date: inv?.date ?? old.date,
          title: 'فاتورة ${inv?.number ?? invId}',
          note: inv == null
              ? null
              : '${inv.isDebt ? 'دين' : 'نقد'} • الإجمالي ${_m(inv.total)}'
                  '${inv.isDebt && inv.paid > 0 ? ' • مسدد عليها ${_m(inv.paid)}' : ''}'
                  ' • ${inv.lines.length} مادة',
          amount: sums[invId] ?? 0,
          kind: StmtKind.invoice,
          invoice: inv,
        );
      });
    }

    var bal = w.opening;
    double debit = 0, credit = 0;
    for (final r in rows) {
      bal += r.amount;
      r.balanceAfter = bal;
      if (r.amount > 0) debit += r.amount;
      if (r.amount < 0) credit += -r.amount;
    }
    return StatementResult(
      customerName: customerName,
      period: period,
      detail: detail,
      fromDate: w.from,
      toDate: w.to,
      opening: w.opening,
      closing: bal,
      debit: debit,
      credit: credit,
      rows: rows,
      zeroAt: w.zeroAt,
    );
  }

  /// الكشف التجاري
  static Future<CommercialResult> commercial({
    required int customerId,
    required String customerName,
    required StmtPeriod period,
  }) async {
    final db = await DatabaseService().database;
    final txs = await _loadTx(db, customerId);
    final w = _window(txs, period);
    final inWin = w.end >= w.start ? txs.sublist(w.start, w.end + 1) : <_Tx>[];

    // فواتير الدين: التي بدأ أثرها داخل الفترة
    final firstIdx = <int, int>{};
    for (var i = 0; i < txs.length; i++) {
      final inv = txs[i].invoiceId;
      if (inv != null) firstIdx.putIfAbsent(inv, () => i);
    }
    final startedHere = <int>{
      for (final e in firstIdx.entries)
        if (e.value >= w.start && e.value <= w.end) e.key,
    };

    // فواتير النقد لا تحرّك الدين: تُؤخذ بتاريخها داخل الفترة
    final where = StringBuffer("customer_id = ? AND payment_type = 'نقد' AND status = 'محفوظة'");
    final args = <Object?>[customerId];
    final from = period.kind == StmtPeriodKind.all ? null : w.from;
    DateTime? to = w.to;
    if (period.kind == StmtPeriodKind.sinceZero) {
      if (w.zeroAt != null) {
        where.write(' AND invoice_date > ?');
        args.add(w.zeroAt!.toIso8601String());
      }
    } else if (period.kind == StmtPeriodKind.range) {
      where.write(' AND invoice_date >= ? AND invoice_date <= ?');
      args.add(from!.toIso8601String());
      args.add(to!.toIso8601String());
    }
    List<int> cashIds = const [];
    try {
      cashIds = [
        for (final r in await db.query('invoices', columns: ['id'], where: '$where', whereArgs: args)) r['id'] as int
      ];
    } catch (_) {}

    final invoices = await _loadInvoices(db, {...startedHere, ...cashIds});
    final debtInv = <StmtInvoice>[];
    final cashInv = <StmtInvoice>[];
    for (final inv in invoices.values) {
      if (inv.isDebt) {
        if (startedHere.contains(inv.id)) debtInv.add(inv);
      } else if (cashIds.contains(inv.id) || startedHere.contains(inv.id)) {
        cashInv.add(inv);
      }
    }
    debtInv.sort((a, b) => a.date.compareTo(b.date));
    cashInv.sort((a, b) => a.date.compareTo(b.date));

    double manualDebt = 0, payments = 0, discounts = 0, returnsCredit = 0, other = 0;
    var manualDebtCount = 0, paymentCount = 0, otherCount = 0;
    var bal = w.opening;
    double wDebit = 0, wCredit = 0;
    for (final t in inWin) {
      bal += t.amount;
      if (t.amount > 0) wDebit += t.amount;
      if (t.amount < 0) wCredit += -t.amount;
      if (t.invoiceId != null) continue;
      switch (_kindOf(t)) {
        case StmtKind.debt:
          manualDebt += t.amount;
          manualDebtCount++;
          break;
        case StmtKind.payment:
          payments += -t.amount;
          paymentCount++;
          break;
        case StmtKind.discount:
          discounts += -t.amount;
          break;
        case StmtKind.salesReturn:
          returnsCredit += -t.amount;
          break;
        default:
          other += t.amount;
          otherCount++;
      }
    }

    // مرتجع نقداً من الصندوق (لا يمس الدين)
    double cashReturns = 0;
    var cashReturnsCount = 0;
    try {
      final rw = StringBuffer("customer_id = ? AND refund_mode = 'cash' AND status = 'posted'");
      final ra = <Object?>[customerId];
      if (period.kind == StmtPeriodKind.sinceZero && w.zeroAt != null) {
        rw.write(' AND return_date > ?');
        ra.add(w.zeroAt!.toIso8601String());
      } else if (period.kind == StmtPeriodKind.range) {
        rw.write(' AND return_date >= ? AND return_date <= ?');
        ra.add(from!.toIso8601String());
        ra.add(to!.toIso8601String());
      }
      final r = await db.rawQuery(
          'SELECT COUNT(*) AS n, COALESCE(SUM(total), 0) AS s FROM sales_returns WHERE $rw', ra);
      cashReturnsCount = (r.first['n'] as num?)?.toInt() ?? 0;
      cashReturns = (r.first['s'] as num?)?.toDouble() ?? 0;
    } catch (_) {}

    String periodText;
    switch (period.kind) {
      case StmtPeriodKind.all:
        periodText = 'كل الحركات منذ البداية';
        break;
      case StmtPeriodKind.sinceZero:
        periodText = w.zeroAt == null
            ? 'لم يكن رصيده صفراً من قبل — كل الحركات منذ البداية'
            : 'منذ صار رصيده صفراً في ${_d(w.zeroAt!)}';
        break;
      case StmtPeriodKind.range:
        periodText = period.label;
    }

    return CommercialResult(
      customerName: customerName,
      period: period,
      periodText: periodText,
      opening: w.opening,
      closing: bal,
      debtInvoices: debtInv,
      manualDebt: manualDebt,
      manualDebtCount: manualDebtCount,
      cashInvoices: cashInv,
      payments: payments,
      paymentCount: paymentCount,
      discounts: discounts,
      returnsCredit: returnsCredit,
      other: other,
      otherCount: otherCount,
      cashReturns: cashReturns,
      cashReturnsCount: cashReturnsCount,
      windowDebit: wDebit,
      windowCredit: wCredit,
    );
  }

  static String _m(double v) {
    final s = v.abs().round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return v < 0 ? '-$s' : s;
  }
}
