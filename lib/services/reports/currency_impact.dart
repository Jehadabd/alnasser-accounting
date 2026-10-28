// lib/services/reports/currency_impact.dart
//
// 💱 أثر سعر الدولار على محل يشتري بعض بضاعته بالدولار ويبيع ويُدين بالدينار.
//
// السعر من «العملات وأسعار الصرف» بتاريخه (CurrencyService.rateAt):
//   • قبل الفترة = آخر سعر حتى نهاية اليوم السابق لبدايتها.
//   • بعدها     = آخر سعر حتى نهاية آخر يوم فيها.
//
// «مادة دولارية» = كلفتها مسجّلة بالدولار في بطاقتها (تتبع السعر تلقائياً)، أو آخر
// شراء مؤكد لها كان بالدولار. بضاعة الدينار (تُشترى وتُباع بالدينار) لا أثر عليها.
//
// ما يُحسب:
//   1) ديون العملاء الناتجة عن بضاعة الدولار فقط — تقدير «الأحدث أولاً»: الدين الحالي
//      لكل عميل = آخر ما استدانه (التسديد يذهب للأقدم)، ومن كل فاتورة حصة المواد
//      الدولارية فيها. الدين اليدوي والافتتاحي مجهول المصدر فيُعدّ بالدينار.
//      الخسارة: ما كان يساوي بالدولار وما صار يساويه، وبالدينار: ما يلزمك إضافةً
//      لتعيد شراء البضاعة نفسها.
//   2) ديونك للموردين بالدولار: كم زادت كلفتها بالدينار.
//   3) مخزون مواد الدولار: كم ارتفعت قيمته (كلفة الاستبدال) خلال الفترة.
//   4) مواد تحت الكلفة/هامش ضعيف بكلفة اليوم، وكلفة مسجّلة قديمة أو مشكوك فيها.
// الديون المعروضة هي الأرصدة الحالية (أثر السعر وحده، لا تغيّر الأرصدة).

import 'package:sqflite/sqflite.dart';

import '../../accounting/ledger.dart' show Ledger;
import '../../erp/currency_service.dart' show CurrencyService;

class UsdProductImpact {
  UsdProductImpact({
    required this.productId,
    required this.name,
    required this.unit,
    required this.supplierName,
    required this.lastPurchase,
    required this.usdUnitCost,
    required this.rateAtPurchase,
    required this.costPrice,
    required this.sellingPrice,
    required this.stock,
    this.autoTracked = false,
  });

  final int productId;
  final String name;
  final String unit;
  final String supplierName;
  final DateTime? lastPurchase;

  /// كلفة الوحدة الأساسية بالدولار.
  final double usdUnitCost;
  final double rateAtPurchase;

  /// الكلفة المسجّلة الآن (دينار).
  final double costPrice;
  final double sellingPrice;
  final double stock;

  /// كلفتها مسجّلة بالدولار في بطاقتها فتتبع السعر تلقائياً.
  final bool autoTracked;

  double newCost(double rate) => usdUnitCost * rate;

  /// الكلفة مسجّلة بالرقم الدولاري كأنه دينار (أقرب إليه منها إلى المحوَّل).
  bool get costLooksUnconverted =>
      !autoTracked &&
      usdUnitCost > 0 &&
      rateAtPurchase > 50 &&
      costPrice > 0 &&
      (costPrice - usdUnitCost).abs() < (costPrice - usdUnitCost * rateAtPurchase).abs();

  double costChangePct(double rate) => costPrice > 0 ? (newCost(rate) - costPrice) / costPrice * 100 : 0;
  double marginAt(double rate) => sellingPrice > 0 ? (sellingPrice - newCost(rate)) / sellingPrice * 100 : 0;
  bool belowCost(double rate) => sellingPrice > 0 && sellingPrice < newCost(rate);

  /// تغيّر قيمة المخزون الموجود بين سعرين (كلفة الاستبدال).
  double stockEffect(double before, double after) =>
      (stock > 0 && !costLooksUnconverted) ? stock * usdUnitCost * (after - before) : 0;
}

class UsdSupplierDebt {
  const UsdSupplierDebt(this.id, this.name, this.usd);
  final int id;
  final String name;
  final double usd;
}

class CurrencyImpact {
  CurrencyImpact._({
    required this.from,
    required this.to,
    required this.rateBefore,
    required this.rateAfter,
    required this.rates,
    required this.hasRateHistory,
    required this.receivables,
    required this.debtorCount,
    required this.usdReceivables,
    required this.usdDebtorCount,
    required this.unknownReceivables,
    required this.payablesUsd,
    required this.payablesIqd,
    required this.usdSuppliers,
    required this.products,
    required this.periodUsdPurchases,
    required this.periodUsdPurchasesIqd,
  });

  final DateTime from;
  final DateTime to;
  final double rateBefore;
  final double rateAfter;

  /// الأسعار المسجّلة داخل الفترة (التاريخ، السعر).
  final List<(DateTime, double)> rates;
  final bool hasRateHistory;

  /// كل ديون العملاء الموجبة الحالية (دينار).
  final double receivables;
  final int debtorCount;

  /// الجزء الناتج عن بضاعة الدولار (تقدير الأحدث أولاً).
  final double usdReceivables;
  final int usdDebtorCount;

  /// دين بلا فواتير تفسّره (يدوي/افتتاحي/أقدم من السجل) — يُعدّ بالدينار.
  final double unknownReceivables;

  /// ديون الموردين: بالدولار وبالدينار.
  final double payablesUsd;
  final double payablesIqd;
  final List<UsdSupplierDebt> usdSuppliers;

  /// المواد الدولارية.
  final List<UsdProductImpact> products;

  /// مشتريات مؤكدة بالدولار داخل الفترة.
  final double periodUsdPurchases;
  final double periodUsdPurchasesIqd;

  bool get rateChanged => (rateAfter - rateBefore).abs() > 0.0001;
  bool get rateUp => rateAfter > rateBefore;
  double get changePct => rateBefore > 0 ? (rateAfter - rateBefore) / rateBefore * 100 : 0;

  double get iqdReceivables => (receivables - usdReceivables).clamp(0, double.infinity).toDouble();

  double get receivablesUsdBefore => rateBefore > 0 ? usdReceivables / rateBefore : 0;
  double get receivablesUsdAfter => rateAfter > 0 ? usdReceivables / rateAfter : 0;

  /// ما فقدته ديون بضاعة الدولار من قيمتها بالدولار (%). سالب = ربحت.
  double get receivablesLossPct => rateAfter > 0 ? (1 - rateBefore / rateAfter) * 100 : 0;
  double get receivablesLossUsd => receivablesUsdBefore - receivablesUsdAfter;

  /// بالدينار: ما يلزمك إضافةً لتعيد شراء بضاعة تلك الديون بسعر اليوم.
  double get receivablesLossIqd => rateBefore > 0 ? usdReceivables * (rateAfter / rateBefore - 1) : 0;

  double get payablesUsdIqdBefore => payablesUsd * rateBefore;
  double get payablesUsdIqdAfter => payablesUsd * rateAfter;
  double get payablesIncrease => payablesUsdIqdAfter - payablesUsdIqdBefore;

  /// هل تكفي كل ديونك على الناس (بسعر اليوم) لتسديد ديون الدولار؟
  double get coverage => payablesUsd > 0 ? (rateAfter > 0 ? receivables / rateAfter : 0) / payablesUsd : 0;

  List<UsdProductImpact> get suspicious => [for (final p in products) if (p.costLooksUnconverted) p];
  List<UsdProductImpact> get healthy => [for (final p in products) if (!p.costLooksUnconverted) p];
  List<UsdProductImpact> get autoTracked => [for (final p in products) if (p.autoTracked) p];
  List<UsdProductImpact> get belowCost =>
      [for (final p in healthy) if (p.belowCost(rateAfter)) p]..sort((a, b) => a.marginAt(rateAfter).compareTo(b.marginAt(rateAfter)));
  List<UsdProductImpact> lowMargin(double threshold) => [
        for (final p in healthy)
          if (!p.belowCost(rateAfter) && p.sellingPrice > 0 && p.marginAt(rateAfter) < threshold) p
      ]..sort((a, b) => a.marginAt(rateAfter).compareTo(b.marginAt(rateAfter)));

  /// كلفة مسجّلة أقل من كلفة اليوم (للمواد التي لا تتبع الدولار تلقائياً).
  List<UsdProductImpact> get costOutdated => [
        for (final p in healthy)
          if (!p.autoTracked && p.costChangePct(rateAfter) > 0.5) p
      ]..sort((a, b) => b.costChangePct(rateAfter).compareTo(a.costChangePct(rateAfter)));

  /// تغيّر قيمة مخزون الدولار خلال الفترة (موجب = ارتفعت قيمته).
  double get stockEffect => healthy.fold(0.0, (s, p) => s + p.stockEffect(rateBefore, rateAfter));
  double get usdStockValueNow => healthy.fold(0.0, (s, p) => s + (p.stock > 0 ? p.stock * p.newCost(rateAfter) : 0));

  /// صافي أثر السعر بالدينار: المخزون − (خسارة ديون بضاعة الدولار + زيادة ديون الدولار).
  double get netEffect => stockEffect - receivablesLossIqd - payablesIncrease;

  /// حساسية: أثر ارتفاع إضافي بنسبة [pct]% من سعر اليوم.
  ({double payablesIqd, double receivablesUsd, double stockIqd}) whatIf(double pct) {
    final r2 = rateAfter * (1 + pct / 100);
    return (
      payablesIqd: payablesUsd * (r2 - rateAfter),
      receivablesUsd: rateAfter > 0 && r2 > 0 ? usdReceivables / rateAfter - usdReceivables / r2 : 0,
      stockIqd: healthy.fold(0.0, (s, p) => s + p.stockEffect(rateAfter, r2)),
    );
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static double _d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);

  static Future<double> _rate(DatabaseExecutor db, DateTime at) async {
    try {
      final r = await CurrencyService.rateAt(db, 'USD', at);
      if (r > 0) return r;
    } catch (_) {}
    try {
      return await Ledger.usdRate(db);
    } catch (_) {
      return 0;
    }
  }

  static Future<CurrencyImpact> load(DatabaseExecutor db, {required DateTime from, required DateTime to}) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final before = await _rate(db, start.subtract(const Duration(days: 1)));
    final after = await _rate(db, end);

    final rates = <(DateTime, double)>[];
    var hasHistory = false;
    try {
      final n = await db.rawQuery("SELECT COUNT(*) AS n FROM currency_rates WHERE code = 'USD'");
      hasHistory = _d(n.first['n']) > 1;
      final rows = await db.rawQuery(
          "SELECT rate, rate_date FROM currency_rates WHERE code = 'USD' AND rate_date >= ? AND rate_date <= ? "
          'ORDER BY rate_date, id',
          [_day(start), '${_day(end)}T99']);
      for (final r in rows) {
        final d = DateTime.tryParse('${r['rate_date']}');
        if (d != null) rates.add((d, _d(r['rate'])));
      }
    } catch (_) {}

    // ── مواد الدولار ──
    final products = <int, UsdProductImpact>{};
    final rateCache = <String, double>{};
    Future<double> rateOn(DateTime d) async => rateCache[_day(d)] ??= await _rate(db, d);
    // (أ) كلفتها مسجّلة بالدولار في بطاقتها
    try {
      final rows = await db.rawQuery('''
        SELECT p.id, p.name, p.unit, p.cost_price, p.price1, p.stock_quantity, d.cost_usd
        FROM product_details d JOIN products p ON p.id = d.product_id
        WHERE d.cost_currency = 'USD' AND COALESCE(d.cost_usd, 0) > 0 AND COALESCE(p.is_deleted, 0) = 0''');
      for (final r in rows) {
        final id = (r['id'] as num).toInt();
        products[id] = UsdProductImpact(
          productId: id,
          name: '${r['name'] ?? ''}',
          unit: '${r['unit'] ?? ''}',
          supplierName: '',
          lastPurchase: null,
          usdUnitCost: _d(r['cost_usd']),
          rateAtPurchase: after,
          costPrice: _d(r['cost_price']),
          sellingPrice: _d(r['price1']),
          stock: _d(r['stock_quantity']),
          autoTracked: true,
        );
      }
    } catch (_) {}
    // (ب) آخر شراء مؤكد لها بالدولار (أو تفاصيل المورد للمواد في (أ))
    try {
      final rows = await db.rawQuery('''
        SELECT pii.product_id, pii.unit_price, pii.conversion_factor, pi.date, pi.currency,
               COALESCE(s.name, '') AS supplier_name,
               p.name, p.unit, p.cost_price, p.price1, p.stock_quantity
        FROM purchase_invoice_items pii
        JOIN purchase_invoices pi ON pi.id = pii.invoice_id
        JOIN products p ON p.id = pii.product_id
        LEFT JOIN suppliers s ON s.id = pi.supplier_id
        WHERE pi.status = 'confirmed' AND COALESCE(p.is_deleted, 0) = 0
        ORDER BY pi.date DESC, pii.id DESC''');
      final seen = <int>{};
      for (final r in rows) {
        final id = (r['product_id'] as num).toInt();
        if (!seen.add(id)) continue;
        final date = DateTime.tryParse('${r['date']}');
        final auto = products[id];
        if (auto != null) {
          // مادة تتبع الدولار: نضيف المورد وتاريخ الشراء فقط
          products[id] = UsdProductImpact(
            productId: id,
            name: auto.name,
            unit: auto.unit,
            supplierName: '${r['supplier_name']}',
            lastPurchase: date,
            usdUnitCost: auto.usdUnitCost,
            rateAtPurchase: auto.rateAtPurchase,
            costPrice: auto.costPrice,
            sellingPrice: auto.sellingPrice,
            stock: auto.stock,
            autoTracked: true,
          );
          continue;
        }
        if ('${r['currency']}' != 'USD') continue;
        final cf = _d(r['conversion_factor']);
        final usd = cf > 0 ? _d(r['unit_price']) / cf : _d(r['unit_price']);
        products[id] = UsdProductImpact(
          productId: id,
          name: '${r['name'] ?? ''}',
          unit: '${r['unit'] ?? ''}',
          supplierName: '${r['supplier_name']}',
          lastPurchase: date,
          usdUnitCost: usd,
          rateAtPurchase: await rateOn(date ?? end),
          costPrice: _d(r['cost_price']),
          sellingPrice: _d(r['price1']),
          stock: _d(r['stock_quantity']),
        );
      }
    } catch (_) {}

    // ── ديون العملاء: الكل، والجزء الناتج عن بضاعة الدولار ──
    var ar = 0.0;
    var debtors = 0;
    final debts = <int, double>{};
    try {
      final rows = await db.rawQuery('''
        SELECT id, current_total_debt FROM customers
        WHERE COALESCE(is_deleted, 0) = 0 AND current_total_debt > 0''');
      for (final r in rows) {
        final v = _d(r['current_total_debt']);
        ar += v;
        debtors++;
        debts[(r['id'] as num).toInt()] = v;
      }
    } catch (_) {}
    final split = await _usdShareOfDebts(db, debts, products.keys.toSet());

    // ── ديون الموردين ──
    var apUsd = 0.0, apIqd = 0.0;
    final suppliers = <UsdSupplierDebt>[];
    try {
      final s = await db.rawQuery(
          'SELECT COALESCE(SUM(CASE WHEN total_debt_usd > 0 THEN total_debt_usd ELSE 0 END), 0) AS usd, '
          'COALESCE(SUM(CASE WHEN total_debt_iqd > 0 THEN total_debt_iqd ELSE 0 END), 0) AS iqd FROM suppliers');
      apUsd = _d(s.first['usd']);
      apIqd = _d(s.first['iqd']);
      final top = await db.rawQuery(
          'SELECT id, name, total_debt_usd FROM suppliers WHERE total_debt_usd > 0.009 ORDER BY total_debt_usd DESC LIMIT 10');
      for (final r in top) {
        suppliers.add(UsdSupplierDebt((r['id'] as num).toInt(), '${r['name'] ?? ''}', _d(r['total_debt_usd'])));
      }
    } catch (_) {}

    // ── مشتريات الفترة بالدولار ──
    var pUsd = 0.0, pIqd = 0.0;
    try {
      final rows = await db.rawQuery('''
        SELECT date, total_amount FROM purchase_invoices
        WHERE status = 'confirmed' AND currency = 'USD'
          AND substr(date, 1, 10) >= ? AND substr(date, 1, 10) <= ?''', [_day(start), _day(end)]);
      for (final r in rows) {
        final amt = _d(r['total_amount']);
        pUsd += amt;
        final d = DateTime.tryParse('${r['date']}') ?? end;
        pIqd += amt * await rateOn(d);
      }
    } catch (_) {}

    return CurrencyImpact._(
      from: start,
      to: end,
      rateBefore: before,
      rateAfter: after,
      rates: rates,
      hasRateHistory: hasHistory,
      receivables: ar,
      debtorCount: debtors,
      usdReceivables: split.usd,
      usdDebtorCount: split.customers,
      unknownReceivables: split.unknown,
      payablesUsd: apUsd,
      payablesIqd: apIqd,
      usdSuppliers: suppliers,
      products: products.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      periodUsdPurchases: pUsd,
      periodUsdPurchasesIqd: pIqd,
    );
  }

  /// يقسم دين كل عميل إلى ما جاء من بضاعة الدولار وغيره: الدين الحالي = آخر ما
  /// استدانه (فواتير آجلة: المجموع − المدفوع عليها، ودين يدوي/افتتاحي) من الأحدث،
  /// ومن كل فاتورة حصة المواد الدولارية في بنودها.
  static Future<({double usd, double unknown, int customers})> _usdShareOfDebts(
      DatabaseExecutor db, Map<int, double> debts, Set<int> usdProducts) async {
    if (debts.isEmpty || usdProducts.isEmpty) {
      return (usd: 0.0, unknown: 0.0, customers: 0);
    }
    final ids = debts.keys.toList();
    final ph = List.filled(ids.length, '?').join(',');
    // الأحداث المنشئة للدين لكل عميل
    final events = <int, List<({String date, double amount, int? invoiceId})>>{};
    final invoiceIds = <int>[];
    try {
      final inv = await db.rawQuery('''
        SELECT id, customer_id, invoice_date, total_amount, amount_paid_on_invoice
        FROM invoices
        WHERE customer_id IN ($ph) AND COALESCE(payment_type, '') != 'نقد'
          AND COALESCE(NULLIF(TRIM(status), ''), 'محفوظة') = 'محفوظة'
          AND COALESCE(is_deleted, 0) = 0''', ids);
      for (final r in inv) {
        final debt = _d(r['total_amount']) - _d(r['amount_paid_on_invoice']);
        if (debt <= 0.005) continue;
        final id = (r['id'] as num).toInt();
        invoiceIds.add(id);
        (events[(r['customer_id'] as num).toInt()] ??= []).add((date: '${r['invoice_date']}', amount: debt, invoiceId: id));
      }
    } catch (_) {}
    try {
      final man = await db.rawQuery('''
        SELECT customer_id, transaction_date, amount_changed FROM transactions
        WHERE customer_id IN ($ph) AND invoice_id IS NULL AND amount_changed > 0
          AND transaction_type IN ('manual_debt', 'opening_balance')
          AND COALESCE(is_deleted, 0) = 0''', ids);
      for (final r in man) {
        (events[(r['customer_id'] as num).toInt()] ??= [])
            .add((date: '${r['transaction_date']}', amount: _d(r['amount_changed']), invoiceId: null));
      }
    } catch (_) {}

    // حصة الدولار في كل فاتورة (بمطابقة المادة كما في التقارير: الاسم ثم المعرّف)
    final share = <int, double>{};
    if (invoiceIds.isNotEmpty) {
      try {
        for (var i = 0; i < invoiceIds.length; i += 500) {
          final chunk = invoiceIds.sublist(i, i + 500 > invoiceIds.length ? invoiceIds.length : i + 500);
          final cph = List.filled(chunk.length, '?').join(',');
          final rows = await db.rawQuery('''
            SELECT ii.invoice_id, ii.item_total, COALESCE(pn.id, ii.product_id) AS pid
            FROM invoice_items ii
            LEFT JOIN (SELECT name, MIN(id) AS id FROM products GROUP BY name) pn ON pn.name = ii.product_name
            WHERE ii.invoice_id IN ($cph)''', chunk);
          final all = <int, double>{}, usd = <int, double>{};
          for (final r in rows) {
            final inv = (r['invoice_id'] as num).toInt();
            final t = _d(r['item_total']);
            all[inv] = (all[inv] ?? 0) + t;
            final pid = (r['pid'] as num?)?.toInt();
            if (pid != null && usdProducts.contains(pid)) usd[inv] = (usd[inv] ?? 0) + t;
          }
          for (final e in all.entries) {
            if (e.value > 0) share[e.key] = ((usd[e.key] ?? 0) / e.value).clamp(0.0, 1.0).toDouble();
          }
        }
      } catch (_) {}
    }

    var usdTotal = 0.0, unknown = 0.0;
    var customers = 0;
    for (final e in debts.entries) {
      var remaining = e.value;
      var usdPart = 0.0;
      final list = (events[e.key] ?? [])..sort((a, b) => b.date.compareTo(a.date));
      for (final ev in list) {
        if (remaining <= 0.005) break;
        final take = ev.amount < remaining ? ev.amount : remaining;
        if (ev.invoiceId != null) usdPart += take * (share[ev.invoiceId] ?? 0);
        remaining -= take;
      }
      if (remaining > 0.005) unknown += remaining;
      if (usdPart > 0.5) customers++;
      usdTotal += usdPart;
    }
    return (usd: usdTotal, unknown: unknown, customers: customers);
  }
}
