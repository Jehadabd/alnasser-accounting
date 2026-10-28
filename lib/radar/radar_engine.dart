// lib/radar/radar_engine.dart
//
// 📡 «رادار التاجر» — محرك حسابات فقط (لا ذكاء اصطناعي، لا إنترنت، لا كلفة):
//   1) المحقق المالي: تنبيهات بقواعد ثابتة وجمل جاهزة تُملأ بالأرقام، وكل تنبيه
//      يعرض العمليات التي بُني عليها.
//   2) السيولة المتوقعة 30/60/90 يوماً مع سيناريوهات.
//   3) أولوية التحصيل: من نتابع أولاً، ولماذا.
//   4) الشراء الذكي: الكمية المقترحة لكل مادة حسب البيع الأخير وموسم الشهر.
//
// للقراءة فقط: لا يغيّر أي رصيد أو مستند.
// منطق الكلفة نفسه المستعمل في «تفاصيل المبيعات» (finance_reports.dart).

import 'dart:math' as math;

import '../accounting/ledger.dart' show roundMoney, kMoneyEpsilon;
import '../accounting/screens/acc_ui.dart' show fmtMoney;
import '../accounting/vouchers_service.dart' show VouchersService;
import '../erp/debts/debt_analytics.dart';
import '../erp/erp_common.dart';
import '../erp/inventory/usd_cost_service.dart';

// ───────────────────────── نماذج ─────────────────────────

enum RadarLevel { high, medium, info }

class RadarItem {
  const RadarItem(this.title, this.value, {this.sub});
  final String title;
  final String value;
  final String? sub;
}

class RadarAlert {
  RadarAlert({
    required this.id,
    required this.level,
    required this.title,
    required this.body,
    required this.action,
    this.items = const [],
  });
  final String id;
  final RadarLevel level;
  final String title;
  final String body; // لماذا: بالأرقام
  final String action; // ماذا أفعل
  final List<RadarItem> items; // العمليات التي بُني عليها
}

class RadarKpis {
  RadarKpis({
    required this.revenue30,
    required this.profit30,
    required this.margin30,
    required this.marginPrev30,
    required this.receivables,
    required this.overdue90,
    required this.cashNow,
  });
  final double revenue30;
  final double profit30;
  final double margin30; // %
  final double marginPrev30; // %
  final double receivables;
  final double overdue90;
  final double cashNow;
}

class CashFlows {
  CashFlows({
    required this.cashNow,
    required this.spanDays,
    required this.salesIn,
    required this.collectionsIn,
    required this.otherIn,
    required this.suppliersOut,
    required this.otherOut,
    required this.receivables,
    required this.duesIqd,
    required this.duesUsd,
    required this.usdRate,
    required this.hasLedger,
  });
  final double cashNow;
  final int spanDays; // الأيام التي حُسب منها المعدل (حتى 90)
  // معدلات يومية من حركات الصناديق الفعلية
  final double salesIn;
  final double collectionsIn;
  final double otherIn;
  final double suppliersOut;
  final double otherOut;
  final double receivables;
  /// مستحقات الموردين المؤكدة حسب تاريخ الاستحقاق: [أيام حتى الاستحقاق, المبلغ]
  final List<(int, double)> duesIqd;
  final List<(int, double)> duesUsd;
  final double usdRate;
  final bool hasLedger;

  double duesWithin(int days, {double usdChangePct = 0}) {
    var s = 0.0;
    for (final d in duesIqd) {
      if (d.$1 <= days) s += d.$2;
    }
    final rate = usdRate * (1 + usdChangePct / 100);
    for (final d in duesUsd) {
      if (d.$1 <= days) s += d.$2 * rate;
    }
    return s;
  }
}

class CashProjection {
  CashProjection({
    required this.days,
    required this.inflow,
    required this.outflow,
    required this.end,
    required this.collections,
    required this.suppliers,
  });
  final int days;
  final double inflow;
  final double outflow;
  final double end;
  final double collections;
  final double suppliers;
}

class CollectionTarget {
  CollectionTarget({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.balance,
    required this.oldestDays,
    required this.daysSincePay,
    required this.overLimit,
    required this.score,
    required this.reasons,
  });
  final int customerId;
  final String name;
  final String? phone;
  final double balance;
  final int oldestDays;
  final int? daysSincePay; // null = لم يسدد أبداً
  final double overLimit; // تجاوز السقف (0 = لا)
  final int score; // 0..100
  final List<String> reasons;
}

class BuySuggestion {
  BuySuggestion({
    required this.productId,
    required this.name,
    required this.unit,
    required this.stock,
    required this.recentMonthly,
    required this.seasonIndex,
    required this.forecast30,
    required this.suggestQty,
    required this.coverDays,
    required this.cost,
  });
  final int productId;
  final String name;
  final String unit;
  final double stock;
  final double recentMonthly;
  final double seasonIndex;
  final double forecast30;
  final double suggestQty;
  final double? coverDays; // null = لا بيع
  final double cost;
  double get value => suggestQty * cost;
}

// ───────────────────────── المحرك ─────────────────────────

class RadarEngine {
  /// كلفة سطر الفاتورة — نفس منطق «تفاصيل المبيعات»
  static const _lineCost = '''
    CASE WHEN COALESCE(ii.actual_cost_price, 0) > 0
         THEN ii.actual_cost_price * (CASE WHEN COALESCE(ii.quantity_large_unit, 0) > 0
                                           THEN ii.quantity_large_unit ELSE COALESCE(ii.quantity_individual, 0) END)
         WHEN COALESCE(p.cost_price, 0) > 0
         THEN p.cost_price * (COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)
              * CASE WHEN COALESCE(ii.units_in_large_unit, 0) > 0 THEN ii.units_in_large_unit ELSE 1 END)
         ELSE ii.item_total * 0.9 END''';

  /// الكمية بالوحدة الأساسية
  static const _baseQty = '''
    (COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)
     * CASE WHEN COALESCE(ii.units_in_large_unit, 0) > 0 THEN ii.units_in_large_unit ELSE 1 END)''';

  static const _saved = "i.status = 'محفوظة' AND COALESCE(i.is_deleted, 0) = 0";

  static String _m(double v) => fmtMoneyCompact(v);

  // ═════════════ ملخص ═════════════

  Future<RadarKpis> kpis() async {
    final now = DateTime.now();
    final a = await _period(now.subtract(const Duration(days: 30)), now);
    final b = await _period(now.subtract(const Duration(days: 60)), now.subtract(const Duration(days: 30)));
    final aging = await DebtAnalytics().customerAging(periodDays: 30, periods: 4);
    final receivables = aging.fold<double>(0, (s, r) => s + (r.balance > 0 ? r.balance : 0.0));
    final overdue = aging.fold<double>(0, (s, r) => s + r.buckets.last);
    final cash = await _cashNow();
    return RadarKpis(
      revenue30: a.$1,
      profit30: a.$1 - a.$2,
      margin30: a.$1 > 0 ? (a.$1 - a.$2) / a.$1 * 100 : 0,
      marginPrev30: b.$1 > 0 ? (b.$1 - b.$2) / b.$1 * 100 : 0,
      receivables: receivables,
      overdue90: overdue,
      cashNow: cash,
    );
  }

  /// (الإيراد بعد الخصم، الكلفة) لفترة
  Future<(double, double)> _period(DateTime from, DateTime to) async {
    final db = await erpDb();
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(ii.item_total), 0) AS gross, COALESCE(SUM($_lineCost), 0) AS cost
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE $_saved AND i.invoice_date >= ? AND i.invoice_date < ?''', [isoDay(from), isoDayAfter(to)]);
    final disc = await db.rawQuery('''
      SELECT COALESCE(SUM(COALESCE(i.discount, 0)), 0) AS d FROM invoices i
      WHERE $_saved AND i.invoice_date >= ? AND i.invoice_date < ?''', [isoDay(from), isoDayAfter(to)]);
    return (d0(r.first['gross']) - d0(disc.first['d']), d0(r.first['cost']));
  }

  Future<double> _cashNow() async {
    try {
      final m = await VouchersService().cashBoxBalances();
      return m.values.fold<double>(0, (s, v) => s + v);
    } catch (_) {
      return 0;
    }
  }

  // ═════════════ 1) المحقق المالي ═════════════

  Future<List<RadarAlert>> alerts() async {
    final out = <RadarAlert>[];
    Future<void> run(Future<RadarAlert?> Function() f) async {
      try {
        final a = await f();
        if (a != null) out.add(a);
      } catch (_) {
        // قاعدة واحدة تتعطل (جدول ناقص في قاعدة قديمة) لا تُسقط البقية
      }
    }

    await run(_marginDrop);
    await run(_belowCost);
    await run(_bigDiscounts);
    await run(_overCreditLimit);
    await run(_oldDebts);
    await run(_frequentReturns);
    await run(_shrinkage);
    await run(_lowMarginBestSellers);
    await run(_outOfStockSellers);
    out.sort((a, b) => a.level.index.compareTo(b.level.index));
    return out;
  }

  Future<RadarAlert?> _marginDrop() async {
    final db = await erpDb();
    final now = DateTime.now();
    Future<Map<String, (double, double)>> byProduct(DateTime from, DateTime to) async {
      final rows = await db.rawQuery('''
        SELECT ii.product_name AS n, SUM(ii.item_total) AS rev, SUM($_lineCost) AS cost
        FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
        LEFT JOIN products p ON p.name = ii.product_name
        WHERE $_saved AND i.invoice_date >= ? AND i.invoice_date < ?
        GROUP BY ii.product_name''', [isoDay(from), isoDayAfter(to)]);
      return {for (final r in rows) '${r['n']}': (d0(r['rev']), d0(r['cost']))};
    }

    final cur = await byProduct(now.subtract(const Duration(days: 30)), now);
    final prev = await byProduct(now.subtract(const Duration(days: 60)), now.subtract(const Duration(days: 30)));
    double margin(Map<String, (double, double)> m) {
      final rev = m.values.fold<double>(0, (s, v) => s + v.$1);
      final cost = m.values.fold<double>(0, (s, v) => s + v.$2);
      return rev > 0 ? (rev - cost) / rev * 100 : 0;
    }

    final revCur = cur.values.fold<double>(0, (s, v) => s + v.$1);
    final revPrev = prev.values.fold<double>(0, (s, v) => s + v.$1);
    if (revCur <= 0 || revPrev <= 0) return null;
    final mc = margin(cur), mp = margin(prev);
    if (mp - mc < 3) return null;
    // أكبر المساهمين في الهبوط: مبيعات المادة الآن × (هامشها السابق − هامشها الآن)
    final contrib = <(String, double, double, double)>[];
    cur.forEach((name, v) {
      final p = prev[name];
      if (p == null || p.$1 <= 0 || v.$1 <= 0) return;
      final m1 = (p.$1 - p.$2) / p.$1 * 100, m2 = (v.$1 - v.$2) / v.$1 * 100;
      final lost = v.$1 * (m1 - m2) / 100;
      if (lost > 0) contrib.add((name, lost, m1, m2));
    });
    contrib.sort((a, b) => b.$2.compareTo(a.$2));
    final salesUp = revCur > revPrev;
    return RadarAlert(
      id: 'margin_drop',
      level: RadarLevel.high,
      title: salesUp ? 'الربح يتراجع رغم ارتفاع المبيعات' : 'هامش الربح يتراجع',
      body: 'هامش الربح آخر 30 يوماً ${mc.toStringAsFixed(1)}% مقابل ${mp.toStringAsFixed(1)}% في الثلاثين التي قبلها '
          '(المبيعات ${_m(revCur)} مقابل ${_m(revPrev)}).',
      action: 'راجع أسعار بيع المواد أدناه: كلفتها ارتفعت أو سعرها نزل.',
      items: [
        for (final c in contrib.take(6))
          RadarItem(c.$1, 'خسارة ${_m(c.$2)}', sub: 'الهامش ${c.$3.toStringAsFixed(1)}% ← ${c.$4.toStringAsFixed(1)}%'),
      ],
    );
  }

  Future<RadarAlert?> _belowCost() async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT ii.product_name AS n, i.invoice_number AS num, i.id AS iid, i.customer_name AS c,
             ii.item_total AS total, ($_lineCost) AS cost
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE $_saved AND i.invoice_date >= ? AND ii.item_total > 0
        AND (COALESCE(ii.actual_cost_price, 0) > 0 OR COALESCE(p.cost_price, 0) > 0)
        AND ($_lineCost) > ii.item_total + 0.5''', [isoDay(DateTime.now().subtract(const Duration(days: 30)))]);
    if (rows.isEmpty) return null;
    final loss = rows.fold<double>(0, (s, r) => s + d0(r['cost']) - d0(r['total']));
    final sorted = [...rows]..sort((a, b) => (d0(b['cost']) - d0(b['total'])).compareTo(d0(a['cost']) - d0(a['total'])));
    return RadarAlert(
      id: 'below_cost',
      level: RadarLevel.high,
      title: 'بيع تحت الكلفة',
      body: '${rows.length} سطراً في آخر 30 يوماً بِيعت بأقل من كلفتها، بخسارة ${_m(loss)}.',
      action: 'تأكد أنها مقصودة (تصفية، عرض) وليست خطأ سعر أو كلفة غير محدّثة.',
      items: [
        for (final r in sorted.take(8))
          RadarItem('${r['n']}', 'خسارة ${_m(d0(r['cost']) - d0(r['total']))}',
              sub: 'فاتورة ${r['num'] ?? '#${r['iid']}'} • ${r['c'] ?? ''}'),
      ],
    );
  }

  Future<RadarAlert?> _bigDiscounts() async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT i.id, i.invoice_number AS num, i.customer_name AS c, COALESCE(i.discount, 0) AS d,
             (SELECT COALESCE(SUM(ii.item_total), 0) FROM invoice_items ii WHERE ii.invoice_id = i.id) AS gross
      FROM invoices i WHERE $_saved AND i.invoice_date >= ?''',
        [isoDay(DateTime.now().subtract(const Duration(days: 30)))]);
    final pct = <(Map<String, Object?>, double)>[];
    for (final r in rows) {
      final g = d0(r['gross']);
      if (g > 0 && d0(r['d']) > 0) pct.add((r, d0(r['d']) / g * 100));
    }
    if (pct.length < 3) return null;
    final mean = pct.fold<double>(0, (s, p) => s + p.$2) / pct.length;
    final sd = math.sqrt(pct.fold<double>(0, (s, p) => s + math.pow(p.$2 - mean, 2).toDouble()) / pct.length);
    final limit = math.max(10.0, mean + 2 * sd);
    final hits = pct.where((p) => p.$2 >= limit).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    if (hits.isEmpty) return null;
    return RadarAlert(
      id: 'big_discounts',
      level: RadarLevel.medium,
      title: 'خصومات أعلى من المعتاد',
      body: '${hits.length} فاتورة بخصم ${limit.toStringAsFixed(0)}% أو أكثر، والمعتاد عندك ${mean.toStringAsFixed(1)}%.',
      action: 'راجع من أعطى هذه الخصومات ولماذا.',
      items: [
        for (final h in hits.take(8))
          RadarItem('فاتورة ${h.$1['num'] ?? '#${h.$1['id']}'}', '${h.$2.toStringAsFixed(1)}%',
              sub: '${h.$1['c'] ?? ''} • خصم ${_m(d0(h.$1['d']))}'),
      ],
    );
  }

  Future<RadarAlert?> _overCreditLimit() async {
    final rows = await DebtAnalytics().overCreditLimit();
    if (rows.isEmpty) return null;
    final over = rows.fold<double>(0, (s, r) => s + d0(r['balance']) - d0(r['credit_limit']));
    return RadarAlert(
      id: 'credit_limit',
      level: RadarLevel.high,
      title: 'عملاء تجاوزوا سقف الدين',
      body: '${rows.length} عميلاً تجاوزوا السقف المحدد لهم بمجموع ${_m(over)}.',
      action: 'أوقف البيع الآجل لهم حتى يسددوا، أو راجع السقف.',
      items: [
        for (final r in rows.take(8))
          RadarItem('${r['name']}', 'تجاوز ${_m(d0(r['balance']) - d0(r['credit_limit']))}',
              sub: 'الرصيد ${_m(d0(r['balance']))} • السقف ${_m(d0(r['credit_limit']))}'),
      ],
    );
  }

  Future<RadarAlert?> _oldDebts() async {
    final aging = await DebtAnalytics().customerAging(periodDays: 30, periods: 4);
    final old = aging.where((r) => r.buckets.last > kMoneyEpsilon).toList()
      ..sort((a, b) => b.buckets.last.compareTo(a.buckets.last));
    if (old.isEmpty) return null;
    final total = old.fold<double>(0, (s, r) => s + r.buckets.last);
    final all = aging.fold<double>(0, (s, r) => s + (r.balance > 0 ? r.balance : 0.0));
    return RadarAlert(
      id: 'old_debts',
      level: total > all * 0.3 ? RadarLevel.high : RadarLevel.medium,
      title: 'ديون أقدم من 90 يوماً',
      body: '${_m(total)} عند ${old.length} عميلاً لم تُسدد منذ أكثر من 90 يوماً'
          '${all > 0 ? ' (${(total / all * 100).toStringAsFixed(0)}% من كل ديون العملاء)' : ''}.',
      action: 'ابدأ بهم من تبويب «التحصيل».',
      items: [
        for (final r in old.take(8))
          RadarItem(r.name, _m(r.buckets.last),
              sub: r.oldestDate == null ? null : 'منذ ${DateTime.now().difference(r.oldestDate!).inDays} يوماً'),
      ],
    );
  }

  Future<RadarAlert?> _frequentReturns() async {
    final db = await erpDb();
    final since = isoDay(DateTime.now().subtract(const Duration(days: 60)));
    final rows = await db.rawQuery('''
      SELECT r.customer_name AS n, COUNT(*) AS k, SUM(r.total) AS t,
        (SELECT COALESCE(SUM(i.total_amount), 0) FROM invoices i
          WHERE $_saved AND i.customer_name = r.customer_name AND i.invoice_date >= ?) AS sales
      FROM sales_returns r WHERE r.status = 'posted' AND r.return_date >= ?
      GROUP BY r.customer_name''', [since, since]);
    final hits = rows.where((r) {
      final k = (r['k'] as num?)?.toInt() ?? 0, t = d0(r['t']), s = d0(r['sales']);
      return k >= 3 || (s > 0 && t / s >= 0.2 && k >= 2);
    }).toList()
      ..sort((a, b) => d0(b['t']).compareTo(d0(a['t'])));
    if (hits.isEmpty) return null;
    return RadarAlert(
      id: 'returns',
      level: RadarLevel.medium,
      title: 'مرتجعات متكررة',
      body: '${hits.length} عميلاً أرجعوا بضاعة مرات متكررة أو بنسبة كبيرة من مشترياتهم خلال 60 يوماً.',
      action: 'تحقق من سبب الإرجاع: جودة المادة، أو خطأ في التجهيز، أو تلاعب.',
      items: [
        for (final r in hits.take(8))
          RadarItem('${r['n']}', '${r['k']} مرتجع • ${_m(d0(r['t']))}',
              sub: d0(r['sales']) > 0 ? '${(d0(r['t']) / d0(r['sales']) * 100).toStringAsFixed(0)}% من مشترياته' : null),
      ],
    );
  }

  Future<RadarAlert?> _shrinkage() async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT p.name AS n, SUM(-m.delta) AS q, SUM(-m.delta * COALESCE(p.cost_price, 0)) AS v
      FROM stock_movements m JOIN products p ON p.sync_uuid = m.product_sync_uuid
      WHERE m.kind = 'adjust' AND m.delta < 0 AND m.created_at >= ?
      GROUP BY p.id ORDER BY v DESC''', [isoDay(DateTime.now().subtract(const Duration(days: 30)))]);
    if (rows.isEmpty) return null;
    final total = rows.fold<double>(0, (s, r) => s + d0(r['v']));
    if (total <= 0) return null;
    return RadarAlert(
      id: 'shrinkage',
      level: RadarLevel.medium,
      title: 'نقص في المخزون بلا بيع',
      body: 'نُقص من المخزون يدوياً (تعديل أو جرد) ما قيمته ${_m(total)} في آخر 30 يوماً، لـ${rows.length} مادة.',
      action: 'تأكد أن النقص له سبب مسجّل (تلف، عيّنة) وليس ضياعاً.',
      items: [
        for (final r in rows.take(8)) RadarItem('${r['n']}', _m(d0(r['v'])), sub: 'الكمية ${fmtQty(d0(r['q']))}'),
      ],
    );
  }

  Future<RadarAlert?> _lowMarginBestSellers() async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT ii.product_name AS n, SUM(ii.item_total) AS rev, SUM($_lineCost) AS cost
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      LEFT JOIN products p ON p.name = ii.product_name
      WHERE $_saved AND i.invoice_date >= ?
      GROUP BY ii.product_name ORDER BY rev DESC LIMIT 20''',
        [isoDay(DateTime.now().subtract(const Duration(days: 30)))]);
    final total = rows.fold<double>(0, (s, r) => s + d0(r['rev']));
    final hits = rows.where((r) {
      final rev = d0(r['rev']), cost = d0(r['cost']);
      return rev > 0 && total > 0 && rev / total >= 0.02 && (rev - cost) / rev * 100 < 5;
    }).toList();
    if (hits.isEmpty) return null;
    return RadarAlert(
      id: 'low_margin',
      level: RadarLevel.info,
      title: 'مواد تبيع كثيراً وربحها ضعيف',
      body: '${hits.length} من أكثر 20 مادة مبيعاً هامشها أقل من 5%.',
      action: 'ارفع سعرها قليلاً أو فاوض المورد على الكلفة — أثرها كبير لأنها تبيع كثيراً.',
      items: [
        for (final r in hits)
          RadarItem('${r['n']}', 'هامش ${((d0(r['rev']) - d0(r['cost'])) / d0(r['rev']) * 100).toStringAsFixed(1)}%',
              sub: 'مبيعات ${_m(d0(r['rev']))}'),
      ],
    );
  }

  Future<RadarAlert?> _outOfStockSellers() async {
    final db = await erpDb();
    final rows = await db.rawQuery('''
      SELECT p.name AS n, p.stock_quantity AS s, SUM($_baseQty) AS q
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      JOIN products p ON p.name = ii.product_name
      WHERE $_saved AND i.invoice_date >= ? AND COALESCE(p.stock_quantity, 0) <= 0
        AND COALESCE(p.is_deleted, 0) = 0
      GROUP BY p.id ORDER BY q DESC''', [isoDay(DateTime.now().subtract(const Duration(days: 30)))]);
    if (rows.isEmpty) return null;
    return RadarAlert(
      id: 'out_of_stock',
      level: RadarLevel.medium,
      title: 'مواد نفدت وهي مطلوبة',
      body: '${rows.length} مادة رصيدها صفر أو أقل، وبيعت في آخر 30 يوماً.',
      action: 'اطلبها من المورد — كل يوم بلا بضاعة مبيعات ضائعة. الكميات المقترحة في تبويب «الشراء الذكي».',
      items: [
        for (final r in rows.take(10)) RadarItem('${r['n']}', 'بِيع ${fmtQty(d0(r['q']))}', sub: 'الرصيد ${fmtQty(d0(r['s']))}'),
      ],
    );
  }

  // ═════════════ 2) السيولة المتوقعة ═════════════

  Future<CashFlows> cashFlows() async {
    final db = await erpDb();
    final now = DateTime.now();
    final cashNow = await _cashNow();
    // حركات الصناديق الفعلية آخر 90 يوماً، مصنّفة حسب مصدرها.
    // التحويل بين صندوقين (كل أطراف القيد صناديق) والرصيد الافتتاحي ليسا تدفقاً.
    final since = now.subtract(const Duration(days: 90));
    var span = 90;
    var hasLedger = false;
    double sales = 0, coll = 0, othIn = 0, supp = 0, othOut = 0;
    try {
      final first = await db.rawQuery('''
        SELECT MIN(je.entry_date) AS d FROM journal_lines l JOIN journal_entries je ON je.id = l.entry_id
        WHERE l.account_id IN (SELECT account_id FROM cash_boxes)''');
      final fd = first.first['d'];
      if (fd != null) {
        hasLedger = true;
        final days = now.difference(parseDate(fd)).inDays;
        span = days < 90 ? math.max(7, days) : 90;
      }
      final rows = await db.rawQuery('''
        SELECT je.source_type AS st, COALESCE(v.voucher_type, '') AS vt,
               COALESCE(SUM(l.debit), 0) AS din, COALESCE(SUM(l.credit), 0) AS dout
        FROM journal_lines l
        JOIN journal_entries je ON je.id = l.entry_id
        LEFT JOIN vouchers v ON je.source_type = 'voucher' AND v.id = je.source_id
        WHERE l.account_id IN (SELECT account_id FROM cash_boxes) AND je.entry_date >= ?
          AND EXISTS (SELECT 1 FROM journal_lines o WHERE o.entry_id = l.entry_id
                      AND o.account_id NOT IN (SELECT account_id FROM cash_boxes))
        GROUP BY je.source_type, vt''', [isoDay(since)]);
      for (final r in rows) {
        final st = '${r['st']}', vt = '${r['vt']}';
        final din = d0(r['din']), dout = d0(r['dout']);
        if (vt == 'opening' || vt == 'transfer') continue;
        if (st == 'invoice' || st == 'sales_return') {
          sales += din;
          othOut += dout;
        } else if (st == 'customer_tx') {
          coll += din;
          othOut += dout;
        } else if (st == 'purchase_invoice' || st == 'supplier_tx' || st == 'purchase_return') {
          supp += dout;
          othIn += din;
        } else {
          othIn += din;
          othOut += dout;
        }
      }
    } catch (_) {}

    // ديون العملاء (سقف ما يمكن تحصيله)
    final aging = await DebtAnalytics().customerAging(periodDays: 30, periods: 4);
    final receivables = aging.fold<double>(0, (s, r) => s + (r.balance > 0 ? r.balance : 0.0));

    // مستحقات الموردين: فواتير شراء مؤكدة بتاريخ استحقاق والمتبقي منها
    final duesIqd = <(int, double)>[], duesUsd = <(int, double)>[];
    try {
      final dues = await db.rawQuery('''
        SELECT due_date, currency, total_amount - paid_amount AS rest FROM purchase_invoices
        WHERE status = 'confirmed' AND due_date IS NOT NULL AND due_date <> ''
          AND total_amount - paid_amount > 0.01''');
      for (final d in dues) {
        final days = math.max(0, parseDate(d['due_date']).difference(DateTime(now.year, now.month, now.day)).inDays);
        (d['currency'] == 'USD' ? duesUsd : duesIqd).add((days, d0(d['rest'])));
      }
    } catch (_) {}
    var rate = 0.0;
    try {
      rate = await UsdCostService.currentRate(db);
    } catch (_) {}
    return CashFlows(
      cashNow: cashNow,
      spanDays: span,
      salesIn: sales / span,
      collectionsIn: coll / span,
      otherIn: othIn / span,
      suppliersOut: supp / span,
      otherOut: othOut / span,
      receivables: receivables,
      duesIqd: duesIqd,
      duesUsd: duesUsd,
      usdRate: rate > 1 ? rate : 0,
      hasLedger: hasLedger,
    );
  }

  /// [delayPct]: نسبة التحصيل المتأخرة. [salesChangePct]: تغيّر المبيعات.
  /// [usdChangePct]: تغيّر سعر الدولار (على مستحقات الموردين بالدولار).
  /// [newPurchase]: شراء جديد يُدفع الآن.
  static List<CashProjection> project(
    CashFlows f, {
    double delayPct = 0,
    double salesChangePct = 0,
    double usdChangePct = 0,
    double newPurchase = 0,
  }) {
    return [
      for (final days in const [30, 60, 90])
        () {
          final collections = math.min(f.collectionsIn * days * (1 - delayPct / 100), f.receivables);
          final inflow = f.salesIn * days * (1 + salesChangePct / 100) + collections + f.otherIn * days;
          // الموردون: الأكبر بين معدل الدفع المعتاد والمستحقات المسجلة حتى ذلك اليوم
          final suppliers = math.max(f.suppliersOut * days, f.duesWithin(days, usdChangePct: usdChangePct));
          final outflow = suppliers + f.otherOut * days + newPurchase;
          return CashProjection(
            days: days,
            inflow: roundMoney(inflow),
            outflow: roundMoney(outflow),
            end: roundMoney(f.cashNow + inflow - outflow),
            collections: roundMoney(collections),
            suppliers: roundMoney(suppliers),
          );
        }(),
    ];
  }

  // ═════════════ 3) أولوية التحصيل ═════════════

  Future<List<CollectionTarget>> collectionTargets() async {
    final db = await erpDb();
    final aging = (await DebtAnalytics().customerAging(periodDays: 30, periods: 4)).where((r) => r.balance > 1).toList();
    if (aging.isEmpty) return const [];
    final lastPay = <int, DateTime>{};
    for (final r in await db.rawQuery('''
        SELECT customer_id AS c, MAX(transaction_date) AS d FROM transactions
        WHERE amount_changed < 0 AND COALESCE(is_deleted, 0) = 0 GROUP BY customer_id''')) {
      if (r['c'] is int && r['d'] != null) lastPay[r['c'] as int] = parseDate(r['d']);
    }
    final limits = <int, double>{};
    try {
      for (final r in await db.rawQuery('SELECT customer_id AS c, credit_limit AS l FROM customer_ext WHERE COALESCE(credit_limit, 0) > 0')) {
        limits[r['c'] as int] = d0(r['l']);
      }
    } catch (_) {}
    final maxBal = aging.fold<double>(0, (m, r) => math.max(m, r.balance));
    final now = DateTime.now();
    final out = <CollectionTarget>[];
    for (final r in aging) {
      final oldest = r.oldestDate == null ? 0 : now.difference(r.oldestDate!).inDays;
      final lp = lastPay[r.partyId];
      final since = lp == null ? null : now.difference(lp).inDays;
      final lim = limits[r.partyId];
      final over = lim != null && r.balance > lim ? r.balance - lim : 0.0;
      // درجة الأولوية: حجم الدين 40 + عمر أقدم دين 30 + مدة الانقطاع عن السداد 20 + تجاوز السقف 10
      final sBal = maxBal > 0 ? math.sqrt(r.balance / maxBal) : 0.0; // الجذر: لا يطغى عميل واحد كبير
      final sAge = math.min(oldest / 120, 1.0);
      final sPay = since == null ? 1.0 : math.min(since / 90, 1.0);
      final score = (40 * sBal + 30 * sAge + 20 * sPay + (over > 0 ? 10 : 0)).round();
      final reasons = <String>[
        'الرصيد ${_m(r.balance)}',
        if (oldest >= 30) 'أقدم دين منذ $oldest يوماً',
        since == null ? 'لم يسدد أي دفعة' : (since >= 30 ? 'آخر دفعة قبل $since يوماً' : 'سدد قبل $since يوماً'),
        if (over > 0) 'تجاوز السقف بـ${_m(over)}',
      ];
      out.add(CollectionTarget(
        customerId: r.partyId,
        name: r.name,
        phone: r.phone,
        balance: r.balance,
        oldestDays: oldest,
        daysSincePay: since,
        overLimit: over,
        score: score.clamp(0, 100).toInt(),
        reasons: reasons,
      ));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  // ═════════════ 4) الشراء الذكي (الموسم + البيع الأخير) ═════════════

  Future<List<BuySuggestion>> buySuggestions() async {
    final db = await erpDb();
    final now = DateTime.now();
    final from = DateTime(now.year - 2, now.month, 1);
    final rows = await db.rawQuery('''
      SELECT p.id AS pid, strftime('%Y-%m', i.invoice_date) AS ym, SUM($_baseQty) AS q
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      JOIN products p ON p.name = ii.product_name
      WHERE $_saved AND i.invoice_date >= ? AND COALESCE(p.is_deleted, 0) = 0
      GROUP BY p.id, ym''', [isoDay(from)]);
    final byProduct = <int, Map<String, double>>{};
    for (final r in rows) {
      if (r['pid'] is! int || r['ym'] == null) continue;
      byProduct.putIfAbsent(r['pid'] as int, () => {})['${r['ym']}'] = d0(r['q']);
    }
    if (byProduct.isEmpty) return const [];
    final info = <int, Map<String, Object?>>{};
    for (final p in await db.rawQuery(
        'SELECT id, name, unit, stock_quantity, cost_price FROM products WHERE COALESCE(is_deleted, 0) = 0')) {
      info[p['id'] as int] = p;
    }
    String ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    // آخر 3 أشهر كاملة + الشهر الجاري حتى اليوم (مُقدّراً لشهر كامل)
    final last3 = [for (var k = 1; k <= 3; k++) ym(DateTime(now.year, now.month - k, 1))];
    final target = DateTime(now.year, now.month, now.day).add(const Duration(days: 15)).month; // الأيام الثلاثون القادمة
    final out = <BuySuggestion>[];
    byProduct.forEach((pid, months) {
      final p = info[pid];
      if (p == null) return;
      final recent = last3.fold<double>(0, (s, k) => s + (months[k] ?? 0.0)) / 3;
      if (recent <= 0) return;
      // معامل الموسم: متوسط هذا الشهر في السنوات السابقة ÷ المتوسط الشهري العام
      final all = months.values.toList();
      final avg = all.fold<double>(0, (s, v) => s + v) / math.max(1, _monthsSpan(months.keys));
      final same = [
        for (final e in months.entries)
          if (int.tryParse(e.key.substring(5)) == target && e.key != ym(now)) e.value
      ];
      var index = 1.0;
      if (same.isNotEmpty && avg > 0) {
        index = (same.fold<double>(0, (s, v) => s + v) / same.length / avg).clamp(0.5, 2.5).toDouble();
      }
      final forecast = recent * index;
      final stock = d0(p['stock_quantity']);
      final need = forecast * 1.2 - stock; // 20% هامش أمان
      final cover = forecast > 0 ? (stock <= 0 ? 0.0 : stock / (forecast / 30)) : null;
      if (need <= 0.0001) return;
      out.add(BuySuggestion(
        productId: pid,
        name: '${p['name']}',
        unit: p['unit'] == 'piece' ? 'قطعة' : (p['unit'] == 'meter' ? 'متر' : '${p['unit'] ?? ''}'),
        stock: stock,
        recentMonthly: recent,
        seasonIndex: index,
        forecast30: forecast,
        suggestQty: need.ceilToDouble(),
        coverDays: cover,
        cost: d0(p['cost_price']),
      ));
    });
    out.sort((a, b) => (a.coverDays ?? 1e9).compareTo(b.coverDays ?? 1e9));
    return out;
  }

  /// عدد الأشهر من أول شهر بيع حتى الشهر الماضي (الأشهر بلا بيع تُحسب صفراً)
  static int _monthsSpan(Iterable<String> keys) {
    if (keys.isEmpty) return 1;
    final ks = keys.toList()..sort();
    final y = int.tryParse(ks.first.substring(0, 4)) ?? 0, m = int.tryParse(ks.first.substring(5)) ?? 1;
    final now = DateTime.now();
    final n = (now.year - y) * 12 + (now.month - m); // بلا الشهر الجاري (غير مكتمل)
    return math.max(1, n);
  }
}

/// مبلغ مختصر: 18.5 مليون، 950 ألف، 1,200
String fmtMoneyCompact(double v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  if (a >= 1e9) return '$sign${(a / 1e9).toStringAsFixed(a >= 1e10 ? 0 : 1)} مليار';
  if (a >= 1e6) return '$sign${(a / 1e6).toStringAsFixed(a >= 1e7 ? 0 : 1)} مليون';
  if (a >= 1e4) return '$sign${(a / 1e3).toStringAsFixed(0)} ألف';
  return '$sign${fmtMoney(a)}';
}
