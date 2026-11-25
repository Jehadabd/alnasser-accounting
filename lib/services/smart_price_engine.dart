// lib/services/smart_price_engine.dart
//
// 🧠 محرك «السعر الذكي» (نمط التسعير 99) — مبني على تحليل 23,259 سطر بيع من فواتير
// المتجر (2026-11). القرار بالترتيب، وأول مصدر متاح يربح:
//
//   1. آخر سعر لهذا الزبون على المادة نفسها بوحدة البيع نفسها خلال 120 يوماً.
//      إن تغيّرت الكلفة منذه تُضاف الزيادة نفسها (يبقى مبلغ ربحه كما هو).
//   2. وإلا: سعر السوق (وسيط آخر 7 بيعات للمادة بالوحدة نفسها) × معامل الزبون.
//      معامل الزبون = وسيط (سعره ÷ سعر السوق وقتها) في آخر 30 سطراً له،
//      مسحوباً نحو 1 ما دام تاريخه قصيراً: 1 + (الوسيط − 1) × ن ÷ (ن + 5).
//   3. وإلا (مادة بلا تاريخ بهذه الوحدة): الكلفة × هامش نطاق الكلفة الفعلي في المتجر.
//   ثم: تقريب لأقرب 250 (أو 50 تحت 2,000)، وأرضية: لا اقتراح تحت الكلفة + 2%.
//
// قواعد صارمة:
//   • وحدة البيع جزء من المفتاح: القطعة لا تختلط بالكرتون ولا المتر باللفة
//     (المرادفات فقط تُدمج: قطعة/piece، متر/meter، لفة/roll).
//   • الفواتير المحفوظة وحدها؛ الفاتورة المعلقة لا تُحسب.
//   • الربط باسم المادة كما في سطور الفواتير (قواعد debt_book لا تحفظ product_id).
//   • لا يكتب المحرك أي بيانات مالية: يقرأ فقط (وفهرس قراءة واحد يُنشأ مرة).
//
// الدقة على تاريخ المتجر نفسه (كل سطر اقتُرح له بما قبله فقط): يقترح لـ 95.8%
// من الأسطر، 55% منها ضمن 5% من السعر الذي باع به الموظف، و74% ضمن 10%.

import 'package:sqflite/sqflite.dart' show Database;

import '../models/product.dart';
import '../models/smart_pricing_models.dart';
import 'database_service.dart';

/// سطر بيع سابق للمادة نفسها بالوحدة نفسها (الأحدث أولاً عند التمرير).
class PriceSale {
  final double price;
  final double? cost;
  final int? customerId;
  final DateTime date;
  const PriceSale({required this.price, this.cost, this.customerId, required this.date});
}

/// نتيجة القرار: السعر ومن أين جاء.
class SmartPriceDecision {
  final double price;
  final String path; // own | market | cold
  final double confidence;
  final String reason;
  const SmartPriceDecision(this.price, this.path, this.confidence, this.reason);
}

/// الرياضيات الخالصة للمحرك (بلا قاعدة بيانات) — تُختبر وحدها.
class SmartPriceMath {
  SmartPriceMath._();

  static const int ownDays = 120;
  static const int marketWindow = 7;
  static const int factorLines = 30;
  static const double factorShrink = 5;
  static const double floorMin = 0.02; // أقل ربح مقبول فوق الكلفة
  static const double floorLift = 0.05; // الاقتراح الخاسر يُرفع إلى الكلفة + 5%
  static const double bigCustomerFactor = 0.97;

  /// هوامش الربح الوسيطة الفعلية على الكلفة حسب نطاقها: (حد أعلى للكلفة، عاديون، كبار).
  static const List<(double, double, double)> bandMargins = [
    (500, 0.97, 0.60),
    (2000, 0.39, 0.25),
    (10000, 0.34, 0.17),
    (50000, 0.20, 0.12),
    (double.infinity, 0.046, 0.042),
  ];

  /// المرادفات المقبولة لوحدة البيع في سطور الفواتير.
  static List<String> unitAliases(String unit) {
    final u = normalizeUnit(unit);
    switch (u) {
      case 'قطعة':
        return const ['قطعة', 'piece', ''];
      case 'متر':
        return const ['متر', 'meter'];
      case 'لفة':
        return const ['لفة', 'roll'];
    }
    return [u];
  }

  static String normalizeUnit(String unit) {
    final u = unit.trim();
    if (u == 'piece' || u.isEmpty) return 'قطعة';
    if (u == 'meter') return 'متر';
    if (u == 'roll') return 'لفة';
    return u;
  }

  static double stepOf(double x) => x >= 2000 ? 250 : 50;

  /// أقرب مضاعف لـ 250 (أو 50 تحت 2,000) — 71% من أسعار المتجر هكذا.
  static double roundPrice(double x) {
    final s = stepOf(x);
    final r = (x / s).round() * s;
    return r < s ? s : r;
  }

  /// للأعلى دائماً (للأرضية: لا تقريب ينزل تحت الكلفة).
  static double roundUp(double x) {
    final s = stepOf(x);
    return (x / s).ceil() * s;
  }

  static double? median(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  /// معامل الزبون من نسبه (الأقدم أولاً). نسب خارج 0.3..3 تُهمل (غالباً خلط وحدات).
  static (double, int) customerFactor(List<double> ratios) {
    final ok = ratios.where((r) => r > 0.3 && r < 3).toList();
    final last = ok.length > factorLines ? ok.sublist(ok.length - factorLines) : ok;
    final n = last.length;
    if (n == 0) return (1.0, 0);
    final m = median(last)!;
    return (1 + (m - 1) * n / (n + factorShrink), n);
  }

  static double bandMargin(double cost, {required bool big}) {
    for (final b in bandMargins) {
      if (cost < b.$1) return big ? b.$3 : b.$2;
    }
    return big ? bandMargins.last.$3 : bandMargins.last.$2;
  }

  /// القرار. [history] الأحدث أولاً، للمادة والوحدة نفسيهما، من الفواتير المحفوظة.
  static SmartPriceDecision? decide({
    required List<PriceSale> history,
    required DateTime now,
    int? customerId,
    double? currentCost,
    double factor = 1.0,
    int factorSamples = 0,
  }) {
    final cost = (currentCost != null && currentCost > 0) ? currentCost : null;
    double? price;
    String path;
    double confidence;
    String reason;

    PriceSale? own;
    if (customerId != null) {
      for (final h in history) {
        if (h.customerId == customerId) {
          if (now.difference(h.date).inDays <= ownDays) own = h;
          break; // آخر شراء له فقط
        }
      }
    }

    if (own != null) {
      price = own.price;
      path = 'own';
      confidence = 85;
      reason = 'آخر سعر لهذا الزبون (${_d(own.date)})';
      final oc = own.cost;
      if (cost != null && oc != null && oc > 0 && (cost - oc).abs() > 0.005 * oc) {
        price = roundPrice(price + (cost - oc));
        reason += ' + فرق الكلفة ${_n(cost - oc)}';
      }
    } else if (history.isNotEmpty) {
      final recent = history.take(marketWindow).map((h) => h.price).toList();
      final ref = median(recent)!;
      price = roundPrice(ref * factor);
      path = 'market';
      confidence = recent.length >= 5 ? 70 : 50;
      reason = 'وسيط آخر ${recent.length} بيعات ${_n(ref)}';
      if ((factor - 1).abs() >= 0.005) {
        reason += ' × معامل الزبون ${factor.toStringAsFixed(2)} ($factorSamples سطراً)';
      }
    } else if (cost != null) {
      final big = factor < bigCustomerFactor;
      final m = bandMargin(cost, big: big);
      price = roundPrice(cost * (1 + m));
      path = 'cold';
      confidence = 30;
      reason = 'مادة بلا مبيعات بهذه الوحدة: الكلفة + ${(m * 100).toStringAsFixed(m < 0.1 ? 1 : 0)}%'
          '${big ? ' (هامش الزبائن الكبار)' : ''}';
    } else {
      return null;
    }

    if (cost != null && price < cost * (1 + floorMin)) {
      price = roundUp(cost * (1 + floorLift));
      reason += ' ← رُفع إلى أرضية الربح (الكلفة + ${(floorLift * 100).round()}%)';
    }
    if (price <= 0) return null;
    return SmartPriceDecision(price, path, confidence, reason);
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _n(double v) {
    final s = v.round().abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return v < 0 ? '−$s' : s;
  }
}

/// المحرك على قاعدة البيانات (قراءة فقط).
class SmartPriceEngine {
  SmartPriceEngine._();
  static final SmartPriceEngine instance = SmartPriceEngine._();

  final DatabaseService _dbService = DatabaseService();
  final Map<int, (DateTime, double, int)> _factorCache = {};
  bool _indexTried = false;

  static const _factorTtl = Duration(minutes: 10);

  Future<SmartPricingResult?> suggest({
    required Product product,
    required String saleType,
    int? customerId,
  }) async {
    final db = await _dbService.database;
    await _ensureIndex(db);
    final unit = SmartPriceMath.normalizeUnit(saleType);
    final aliases = SmartPriceMath.unitAliases(unit);
    final now = DateTime.now();

    double? cost;
    try {
      final c = _dbService.calculateUnitCost(product, unit);
      if (c > 0) cost = c;
    } catch (_) {}

    final rows = await db.rawQuery('''
      SELECT ii.applied_price AS price, ii.actual_cost_price AS ac, ii.cost_price AS cp,
             i.customer_id AS cid, i.invoice_date AS d
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE ii.product_name = ? AND COALESCE(ii.sale_type, '') IN (${aliases.map((_) => '?').join(',')})
        AND i.status = 'محفوظة' AND ii.applied_price > 0
      ORDER BY i.invoice_date DESC, ii.id DESC
      LIMIT 200
    ''', [product.name, ...aliases]);
    final history = <PriceSale>[];
    for (final r in rows) {
      final d = DateTime.tryParse('${r['d']}');
      final p = (r['price'] as num?)?.toDouble();
      if (d == null || p == null || p <= 0) continue;
      final ac = (r['ac'] as num?)?.toDouble();
      final cp = (r['cp'] as num?)?.toDouble();
      final lineCost = (ac != null && ac > 0) ? ac : ((cp != null && cp > 0) ? cp : null);
      history.add(PriceSale(
        price: p,
        // كلفة مسجّلة بوحدة أخرى (لفة بكلفة متر) لا تصلح للمقارنة
        cost: (lineCost != null && p / lineCost < 20) ? lineCost : null,
        customerId: (r['cid'] as num?)?.toInt(),
        date: d,
      ));
    }

    var factor = 1.0;
    var samples = 0;
    if (customerId != null && customerId > 0) {
      try {
        (factor, samples) = await _customerFactor(db, customerId);
      } catch (_) {}
    }

    final dec = SmartPriceMath.decide(
      history: history,
      now: now,
      customerId: customerId,
      currentCost: cost,
      factor: factor,
      factorSamples: samples,
    );
    if (dec == null) return null;
    return SmartPricingResult(
      price: dec.price,
      confidence: dec.confidence,
      source: 'المحرك الذكي',
      reason: dec.reason,
      candidateScores: {dec.price: dec.confidence.round()},
    );
  }

  /// معامل الزبون: سعره ÷ وسيط آخر 7 بيعات للمادة نفسها قبل سطره، في آخر 40 سطراً له.
  Future<(double, int)> _customerFactor(Database db, int customerId) async {
    final cached = _factorCache[customerId];
    if (cached != null && DateTime.now().difference(cached.$1) < _factorTtl) {
      return (cached.$2, cached.$3);
    }
    final lines = await db.rawQuery('''
      SELECT ii.id AS id, ii.invoice_id AS inv, ii.product_name AS name,
             COALESCE(ii.sale_type, '') AS st, ii.applied_price AS price, i.invoice_date AS d
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE i.customer_id = ? AND i.status = 'محفوظة' AND ii.applied_price > 0
      ORDER BY i.invoice_date DESC, ii.id DESC
      LIMIT 40
    ''', [customerId]);
    if (lines.isEmpty) {
      _factorCache[customerId] = (DateTime.now(), 1.0, 0);
      return (1.0, 0);
    }
    final names = {for (final l in lines) '${l['name']}'}.toList();
    final market = await db.rawQuery('''
      SELECT ii.id AS id, ii.invoice_id AS inv, ii.product_name AS name,
             COALESCE(ii.sale_type, '') AS st, ii.applied_price AS price, i.invoice_date AS d
      FROM invoice_items ii JOIN invoices i ON i.id = ii.invoice_id
      WHERE ii.product_name IN (${names.map((_) => '?').join(',')})
        AND i.status = 'محفوظة' AND ii.applied_price > 0
      ORDER BY i.invoice_date DESC, ii.id DESC
    ''', names);
    final byKey = <String, List<Map<String, Object?>>>{};
    for (final m in market) {
      final k = '${m['name']}|${SmartPriceMath.normalizeUnit('${m['st']}')}';
      (byKey[k] ??= []).add(m);
    }
    final ratios = <double>[];
    for (final l in lines.reversed) {
      // الأقدم أولاً
      final k = '${l['name']}|${SmartPriceMath.normalizeUnit('${l['st']}')}';
      final d = '${l['d']}';
      final id = (l['id'] as num).toInt();
      final inv = l['inv'];
      final before = <double>[];
      for (final m in byKey[k] ?? const <Map<String, Object?>>[]) {
        if (m['inv'] == inv) continue;
        final md = '${m['d']}';
        final c = md.compareTo(d);
        if (c > 0 || (c == 0 && (m['id'] as num).toInt() >= id)) continue;
        before.add((m['price'] as num).toDouble());
        if (before.length >= SmartPriceMath.marketWindow) break;
      }
      final ref = SmartPriceMath.median(before);
      if (ref == null || ref <= 0) continue;
      ratios.add((l['price'] as num).toDouble() / ref);
    }
    final f = SmartPriceMath.customerFactor(ratios);
    _factorCache[customerId] = (DateTime.now(), f.$1, f.$2);
    return f;
  }

  /// فهرس قراءة لاسم المادة (مرة واحدة؛ لا يغيّر أي بيانات).
  Future<void> _ensureIndex(Database db) async {
    if (_indexTried) return;
    _indexTried = true;
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoice_items_pname ON invoice_items(product_name, sale_type)');
    } catch (_) {}
  }
}
