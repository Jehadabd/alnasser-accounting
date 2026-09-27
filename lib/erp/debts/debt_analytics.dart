// lib/erp/debts/debt_analytics.dart
//
// 📈 تحليلات الديون (للقراءة فقط — لا تغيّر أي رصيد):
//   • أعمار الديون: توزيع رصيد كل عميل/مورد على فترات حسب عمر الدين،
//     بطريقة «الأقدم يُسدَّد أولاً» (FIFO) كما يفعل الإداري.
//   • الفواتير غير المسددة: الجزء المتبقي من كل فاتورة آجلة بنفس الطريقة.
//   • نسب التحصيل: ما حُصّل من المستحق خلال فترة.
//
// الضمان: مجموع فترات كل عميل = رصيده بالضبط (يُفحص في الكود).

import '../../accounting/ledger.dart';
import '../erp_common.dart';

class _OpenDebit {
  _OpenDebit(this.date, this.amount, this.invoiceId);
  final DateTime date;
  double amount;
  final int? invoiceId;
}

class AgingRow {
  AgingRow({
    required this.partyId,
    required this.name,
    required this.phone,
    required this.balance,
    required this.buckets,
    required this.credit,
    this.oldestDate,
  });
  final int partyId;
  final String name;
  final String? phone;
  final double balance;

  /// مبالغ كل فترة (الأحدث أولاً).
  final List<double> buckets;

  /// رصيد دائن (دفعة مقدمة) إن وُجد.
  final double credit;
  final DateTime? oldestDate;
}

class OpenInvoice {
  OpenInvoice({
    required this.invoiceId,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.debtAmount,
    required this.remaining,
  });
  final int invoiceId;
  final int customerId;
  final String customerName;
  final DateTime date;
  final double debtAmount;
  final double remaining;
  int get ageDays => DateTime.now().difference(date).inDays;
}

class CollectionRow {
  CollectionRow({
    required this.customerId,
    required this.name,
    required this.opening,
    required this.charged,
    required this.collected,
    required this.closing,
  });
  final int customerId;
  final String name;
  final double opening;
  final double charged;
  final double collected;
  final double closing;

  /// نسبة التحصيل = المحصّل ÷ (الرصيد المدين أول الفترة + ما استُحق خلالها).
  double get ratio {
    final base = (opening > 0 ? opening : 0) + charged;
    return base <= 0 ? 0 : collected / base * 100;
  }
}

class _FifoResult {
  _FifoResult(this.open, this.creditPool);
  final List<_OpenDebit> open;
  final double creditPool;
}

class DebtAnalytics {
  /// FIFO على حركات طرف واحد مرتبة زمنياً.
  static _FifoResult _fifo(List<Map<String, Object?>> txs, {String amountKey = 'amount_changed'}) {
    final queue = <_OpenDebit>[];
    var pool = 0.0;
    for (final t in txs) {
      var amt = d0(t[amountKey]);
      final date = parseDate(t['transaction_date']);
      if (amt > 0) {
        if (pool > 0) {
          final use = amt < pool ? amt : pool;
          pool -= use;
          amt -= use;
        }
        if (amt > kMoneyEpsilon) queue.add(_OpenDebit(date, amt, t['invoice_id'] as int?));
      } else if (amt < 0) {
        var pay = -amt;
        while (pay > kMoneyEpsilon && queue.isNotEmpty) {
          final head = queue.first;
          if (head.amount <= pay + 1e-9) {
            pay -= head.amount;
            queue.removeAt(0);
          } else {
            head.amount -= pay;
            pay = 0;
          }
        }
        if (pay > kMoneyEpsilon) pool += pay;
      }
    }
    return _FifoResult(queue, pool);
  }

  /// أعمار ديون العملاء. [periodDays] طول الفترة، [periods] عددها (الأخيرة مفتوحة).
  Future<List<AgingRow>> customerAging({
    DateTime? asOf,
    int periodDays = 30,
    int periods = 4,
    int? groupId,
  }) async {
    final db = await erpDb();
    final at = asOf ?? DateTime.now();
    final rows = await db.rawQuery('''
      SELECT t.customer_id AS pid, t.transaction_date, t.amount_changed, t.invoice_id
      FROM transactions t JOIN customers c ON c.id = t.customer_id
      ${groupId == null ? '' : 'JOIN customer_ext x ON x.customer_id = c.id AND x.group_id = $groupId'}
      WHERE COALESCE(t.is_deleted, 0) = 0 AND COALESCE(c.is_deleted, 0) = 0
        AND t.transaction_date < ?
      ORDER BY t.customer_id, t.transaction_date, t.id
    ''', [isoDayAfter(at)]);
    final names = <int, List<String?>>{};
    for (final c in await db.rawQuery('SELECT id, name, phone FROM customers')) {
      names[c['id'] as int] = [c['name'] as String?, c['phone'] as String?];
    }
    return _aging(rows, names, at, periodDays, periods);
  }

  /// أعمار ديون الموردين بعملة (ما علينا لهم).
  Future<List<AgingRow>> supplierAging({
    DateTime? asOf,
    int periodDays = 30,
    int periods = 4,
    String currency = 'IQD',
  }) async {
    final db = await erpDb();
    final at = asOf ?? DateTime.now();
    final rows = await db.rawQuery('''
      SELECT supplier_id AS pid, transaction_date, amount_changed, invoice_id
      FROM supplier_transactions
      WHERE COALESCE(is_deleted, 0) = 0 AND currency = ? AND transaction_date < ?
      ORDER BY supplier_id, transaction_date, id
    ''', [currency, isoDayAfter(at)]);
    final names = <int, List<String?>>{};
    for (final c in await db.rawQuery('SELECT id, name, phone FROM suppliers')) {
      names[c['id'] as int] = [c['name'] as String?, c['phone'] as String?];
    }
    return _aging(rows, names, at, periodDays, periods);
  }

  List<AgingRow> _aging(List<Map<String, Object?>> rows, Map<int, List<String?>> names, DateTime at,
      int periodDays, int periods) {
    final byParty = <int, List<Map<String, Object?>>>{};
    for (final r in rows) {
      byParty.putIfAbsent(r['pid'] as int, () => []).add(r);
    }
    final out = <AgingRow>[];
    final today = DateTime(at.year, at.month, at.day);
    byParty.forEach((pid, txs) {
      final res = _fifo(txs);
      final buckets = List<double>.filled(periods, 0);
      DateTime? oldest;
      var openSum = 0.0;
      for (final d in res.open) {
        final day = DateTime(d.date.year, d.date.month, d.date.day);
        final age = today.difference(day).inDays;
        var idx = age < 0 ? 0 : age ~/ periodDays;
        if (idx >= periods) idx = periods - 1;
        buckets[idx] += d.amount;
        openSum += d.amount;
        if (oldest == null || d.date.isBefore(oldest)) oldest = d.date;
      }
      final balance = roundMoney(openSum - res.creditPool);
      // فحص الضمان: الفترات − الرصيد الدائن = مجموع الحركات
      final txSum = txs.fold<double>(0, (s, t) => s + d0(t['amount_changed']));
      assert((balance - txSum).abs() < 0.05, 'aging mismatch for $pid');
      if (balance.abs() < kMoneyEpsilon && openSum < kMoneyEpsilon) return;
      out.add(AgingRow(
        partyId: pid,
        name: names[pid]?[0] ?? '#$pid',
        phone: names[pid]?[1],
        balance: roundMoney(txSum),
        buckets: buckets.map(roundMoney).toList(),
        credit: roundMoney(res.creditPool),
        oldestDate: oldest,
      ));
    });
    out.sort((a, b) => b.balance.compareTo(a.balance));
    return out;
  }

  /// الفواتير الآجلة التي لم تُسدَّد بالكامل (FIFO على حركات كل عميل).
  Future<List<OpenInvoice>> openInvoices({int? customerId}) async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT t.customer_id AS pid, t.transaction_date, t.amount_changed, t.invoice_id, c.name
      FROM transactions t JOIN customers c ON c.id = t.customer_id
      WHERE COALESCE(t.is_deleted, 0) = 0 AND COALESCE(c.is_deleted, 0) = 0
        ${customerId == null ? '' : 'AND t.customer_id = $customerId'}
      ORDER BY t.customer_id, t.transaction_date, t.id
    ''');
    final byParty = <int, List<Map<String, Object?>>>{};
    final names = <int, String>{};
    for (final r in rows) {
      final pid = r['pid'] as int;
      byParty.putIfAbsent(pid, () => []).add(r);
      names[pid] = (r['name'] as String?) ?? '';
    }
    // المبلغ الآجل الأصلي لكل فاتورة (مجموع معاملاتها الموجبة)
    final original = <int, double>{};
    for (final r in rows) {
      final inv = r['invoice_id'] as int?;
      final a = d0(r['amount_changed']);
      if (inv != null && a > 0) original[inv] = (original[inv] ?? 0) + a;
    }
    final out = <OpenInvoice>[];
    byParty.forEach((pid, txs) {
      final res = _fifo(txs);
      final remainingByInvoice = <int, double>{};
      final dateByInvoice = <int, DateTime>{};
      for (final d in res.open) {
        if (d.invoiceId == null) continue;
        remainingByInvoice[d.invoiceId!] = (remainingByInvoice[d.invoiceId!] ?? 0) + d.amount;
        dateByInvoice.putIfAbsent(d.invoiceId!, () => d.date);
      }
      remainingByInvoice.forEach((inv, rem) {
        if (rem < kMoneyEpsilon) return;
        out.add(OpenInvoice(
          invoiceId: inv,
          customerId: pid,
          customerName: names[pid] ?? '',
          date: dateByInvoice[inv]!,
          debtAmount: roundMoney(original[inv] ?? rem),
          remaining: roundMoney(rem),
        ));
      });
    });
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// نسب التحصيل لفترة.
  Future<List<CollectionRow>> collection({required DateTime from, required DateTime to}) async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT c.id, c.name,
        COALESCE(SUM(CASE WHEN t.transaction_date < ? THEN t.amount_changed ELSE 0 END), 0) AS opening,
        COALESCE(SUM(CASE WHEN t.transaction_date >= ? AND t.transaction_date < ? AND t.amount_changed > 0
                          THEN t.amount_changed ELSE 0 END), 0) AS charged,
        COALESCE(SUM(CASE WHEN t.transaction_date >= ? AND t.transaction_date < ? AND t.amount_changed < 0
                          THEN -t.amount_changed ELSE 0 END), 0) AS collected,
        COALESCE(SUM(CASE WHEN t.transaction_date < ? THEN t.amount_changed ELSE 0 END), 0) AS closing
      FROM customers c JOIN transactions t ON t.customer_id = c.id AND COALESCE(t.is_deleted, 0) = 0
      WHERE COALESCE(c.is_deleted, 0) = 0
      GROUP BY c.id
    ''', [isoDay(from), isoDay(from), isoDayAfter(to), isoDay(from), isoDayAfter(to), isoDayAfter(to)]);
    final out = <CollectionRow>[];
    for (final r in rows) {
      final row = CollectionRow(
        customerId: r['id'] as int,
        name: (r['name'] as String?) ?? '',
        opening: d0(r['opening']),
        charged: d0(r['charged']),
        collected: d0(r['collected']),
        closing: d0(r['closing']),
      );
      if (row.opening.abs() < kMoneyEpsilon &&
          row.charged < kMoneyEpsilon &&
          row.collected < kMoneyEpsilon) {
        continue;
      }
      out.add(row);
    }
    out.sort((a, b) => b.closing.compareTo(a.closing));
    return out;
  }

  /// العملاء المتجاوزون لسقف الدين.
  Future<List<Map<String, Object?>>> overCreditLimit() async {
    final db = await erpDb();
    return db.rawQuery('''
      SELECT c.id, c.name, c.phone, c.current_total_debt AS balance, x.credit_limit
      FROM customers c JOIN customer_ext x ON x.customer_id = c.id
      WHERE COALESCE(c.is_deleted, 0) = 0 AND COALESCE(x.credit_limit, 0) > 0
        AND c.current_total_debt > x.credit_limit
      ORDER BY (c.current_total_debt - x.credit_limit) DESC
    ''');
  }
}
