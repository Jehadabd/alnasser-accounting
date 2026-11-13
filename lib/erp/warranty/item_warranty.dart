// lib/erp/warranty/item_warranty.dart
//
// 🛡️ ضمان المادة على سطر الفاتورة.
//
//   • المادة: products.warranty_spec — مدة ضمانها وبدايته، نصاً مضغوطاً:
//       «1y» سنة من تاريخ البيع، «6m:p» ستة أشهر من تاريخ شراء المحل لها،
//       «10d» عشرة أيام، «0» بلا ضمان صراحةً. فارغ = لم يُضبط (= بلا ضمان).
//   • شروط الضمان: products.warranty_terms (نص حر) — تُثبَّت على السطر مع ضمانه
//     (invoice_items.warranty_terms) وتُطبع تحت جدول المواد.
//   • سطر الفاتورة: invoice_items.warranty_spec/warranty_start/warranty_end —
//     تُثبَّت لحظة الحفظ ولا تتغير بعدها ولو تغيّرت مدة ضمان المادة:
//       - الفاتورة الجديدة (أو المعلّقة حين تُحفظ): كل سطورها تُحسب الآن.
//       - تعديل فاتورة محفوظة: السطر القديم يبقى بضمانه كما كان (ولو بلا ضمان)،
//         والسطر المضاف أو الذي تغيّرت مادته يُحسب الآن.
//   • النهاية شاملة: سنة من 2026/11/13 تنتهي 2027/11/12 (آخر يوم يعمل فيه
//     الضمان). وإن لم يوجد اليوم المقابل في الشهر الأخير (31 كانون الثاني + شهر)
//     تنتهي بآخر يوم من ذلك الشهر (28/29 شباط).
//   • دفعات الشراء (ProductBatches): إن كان للدفعة التي تخرج منها أول قطعة في السطر
//     ضمانٌ (أُدخل في فاتورة الشراء) فهو ضمان السطر وشروطه، وإلا ضمان المادة.
//   • «من تاريخ الشراء»: تاريخ فاتورة شراء تلك الدفعة؛ وبلا دفعة: آخر فاتورة شراء
//     مؤكدة للمادة في يوم البيع أو قبله؛ وإن لم توجد يُحسب من تاريخ البيع.
//
// سجل عرض وطباعة فقط: لا مال ولا مخزون ولا قيود.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../inventory/product_batches.dart';

enum WarrantyUnit { day, month, year }

enum WarrantyBasis { sale, purchase }

/// مدة الضمان وبدايته.
class WarrantySpec {
  const WarrantySpec(this.value, this.unit, {this.basis = WarrantyBasis.sale});

  final int value;
  final WarrantyUnit unit;
  final WarrantyBasis basis;

  /// «بلا ضمان» صراحةً (يُرفع للأجهزة الأخرى فيُلغي ضمانها كذلك).
  static const none = WarrantySpec(0, WarrantyUnit.month);

  bool get isNone => value <= 0;

  static const _units = {'d': WarrantyUnit.day, 'm': WarrantyUnit.month, 'y': WarrantyUnit.year};

  /// null = نص فارغ أو غير مفهوم (= لا ضمان).
  static WarrantySpec? parse(Object? raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    if (s == '0') return none;
    final m = RegExp(r'^(\d{1,4})([dmy])(:p)?$').firstMatch(s);
    if (m == null) return null;
    final v = int.parse(m.group(1)!);
    if (v <= 0) return none;
    return WarrantySpec(v, _units[m.group(2)]!,
        basis: m.group(3) == null ? WarrantyBasis.sale : WarrantyBasis.purchase);
  }

  String encode() {
    if (isNone) return '0';
    final u = switch (unit) { WarrantyUnit.day => 'd', WarrantyUnit.month => 'm', WarrantyUnit.year => 'y' };
    return '$value$u${basis == WarrantyBasis.purchase ? ':p' : ''}';
  }

  /// «سنة»، «سنتان»، «3 سنوات»، «18 شهراً»...
  String get label {
    if (isNone) return 'بلا ضمان';
    final (one, two, few, many) = switch (unit) {
      WarrantyUnit.day => ('يوم', 'يومان', 'أيام', 'يوماً'),
      WarrantyUnit.month => ('شهر', 'شهران', 'أشهر', 'شهراً'),
      WarrantyUnit.year => ('سنة', 'سنتان', 'سنوات', 'سنة'),
    };
    if (value == 1) return one;
    if (value == 2) return two;
    if (value <= 10) return '$value $few';
    return '$value $many';
  }

  String get basisLabel => basis == WarrantyBasis.purchase ? 'من تاريخ الشراء' : 'من تاريخ البيع';

  /// آخر يوم يعمل فيه الضمان (شامل) لضمان يبدأ يوم [start].
  DateTime endFrom(DateTime start) {
    final d = DateTime(start.year, start.month, start.day);
    if (unit == WarrantyUnit.day) return DateTime(d.year, d.month, d.day + value - 1);
    final months = unit == WarrantyUnit.year ? value * 12 : value;
    final idx = d.month - 1 + months;
    final y = d.year + idx ~/ 12;
    final m = idx % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    // اليوم المقابل غير موجود في الشهر الأخير ⇒ ينتهي بآخر يوم منه
    if (d.day > lastDay) return DateTime(y, m, lastDay);
    return DateTime(y, m, d.day - 1);
  }

  @override
  bool operator ==(Object other) =>
      other is WarrantySpec && other.value == value && other.unit == unit && other.basis == basis;

  @override
  int get hashCode => Object.hash(value, unit, basis);
}

/// ضمان سطر الفاتورة: الحساب عند الحفظ، وما يُطبع.
class ItemWarranty {
  ItemWarranty._();

  /// أعمدة الطباعة (تصميم الفاتورة ومصمم الفواتير).
  static const String colPeriod = 'warrantyPeriod';
  static const String colStart = 'warrantyStart';
  static const String colEnd = 'warrantyEnd';
  static const Set<String> printColumns = {colPeriod, colStart, colEnd};

  /// «2027-11-12» (المخزَّن).
  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// «2027/11/12» (المعروض والمطبوع).
  static String show(String? stored) {
    final d = DateTime.tryParse((stored ?? '').trim());
    return d == null ? '' : iso(d).replaceAll('-', '/');
  }

  /// نص خلية الطباعة لعمود ضمان، أو null إن لم يكن العمود عمود ضمان.
  static String? cellText(String columnId, {String? spec, String? start, String? end}) {
    if (!printColumns.contains(columnId)) return null;
    final s = WarrantySpec.parse(spec);
    if (s == null || s.isNone || (end ?? '').isEmpty) return '';
    return switch (columnId) {
      colPeriod => s.label,
      colStart => show(start),
      _ => show(end),
    };
  }

  // ───────── الحساب عند الحفظ ─────────

  static bool _colsReady = false;

  /// الأعمدة موجودة؟ (تضيفها ErpSchema.ensure عند التشغيل)
  static Future<bool> _ready(DatabaseExecutor d) async {
    if (_colsReady) return true;
    try {
      final items = (await d.rawQuery('PRAGMA table_info(invoice_items)')).map((r) => r['name']).toSet();
      final products = (await d.rawQuery('PRAGMA table_info(products)')).map((r) => r['name']).toSet();
      _colsReady = items.containsAll(const ['warranty_spec', 'warranty_start', 'warranty_end', 'warranty_terms']) &&
          products.containsAll(const ['warranty_spec', 'warranty_terms']);
    } catch (_) {
      _colsReady = false;
    }
    return _colsReady;
  }

  /// سطور الفاتورة قبل تعديلها (لتثبيت ضمان السطور القديمة).
  static Future<List<Map<String, Object?>>> previousLines(DatabaseExecutor d, int invoiceId) async {
    if (!await _ready(d)) return const [];
    return d.query('invoice_items',
        columns: ['unique_id', 'product_name', 'warranty_spec', 'warranty_start', 'warranty_end', 'warranty_terms'],
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'id');
  }

  /// يضع ضمان كل سطر في خريطته قبل إدراجه (داخل معاملة الحفظ).
  ///
  /// [fresh]: فاتورة جديدة أو معلّقة تُحفظ الآن ⇒ يُحسب ضمان كل سطورها.
  /// وإلا: السطر الموجود قبل التعديل (بمعرّفه، أو بمادته للسطور القديمة بلا
  /// معرّف) يأخذ ضمانه السابق كما هو، والجديد يُحسب.
  ///
  /// لا يرمي أبداً: خلل في قراءة الضمان لا يوقف حفظ فاتورة بيع (يبقى السطر بلا ضمان).
  static Future<void> stampLines(
    DatabaseExecutor d,
    List<Map<String, dynamic>> lines,
    DateTime saleDate, {
    List<Map<String, Object?>> previous = const [],
    bool fresh = true,
  }) async {
    try {
      await _stamp(d, lines, saleDate, previous, fresh);
    } catch (e) {
      debugPrint('⚠️ تعذّر حساب ضمان سطور الفاتورة (حُفظت بلا ضمان): $e');
    }
  }

  static Future<void> _stamp(
    DatabaseExecutor d,
    List<Map<String, dynamic>> lines,
    DateTime saleDate,
    List<Map<String, Object?>> previous,
    bool fresh,
  ) async {
    if (lines.isEmpty || !await _ready(d)) return;
    final unmatched = [...previous];
    Map<String, Object?>? takePrevious(Map<String, dynamic> line) {
      final uid = '${line['unique_id'] ?? ''}';
      final name = '${line['product_name'] ?? ''}'.trim();
      var i = uid.isEmpty ? -1 : unmatched.indexWhere((p) => '${p['unique_id'] ?? ''}' == uid);
      if (i >= 0 && '${unmatched[i]['product_name'] ?? ''}'.trim() != name) {
        unmatched.removeAt(i); // السطر نفسه لكن مادته تغيّرت ⇒ ضمان جديد
        return null;
      }
      if (i < 0) i = unmatched.indexWhere((p) => '${p['product_name'] ?? ''}'.trim() == name);
      return i < 0 ? null : unmatched.removeAt(i);
    }

    final specCache = <String, (WarrantySpec?, String?)>{};
    final purchaseCache = <int, DateTime?>{};
    final batchCache = <int, BatchSet>{};
    final taken = <int, double>{}; // ما أُخذ من كل مادة في هذه الفاتورة قبل السطر (FIFO)
    for (final line in lines) {
      final prev = fresh ? null : takePrevious(line);
      if (prev != null) {
        line['warranty_spec'] = prev['warranty_spec'];
        line['warranty_start'] = prev['warranty_start'];
        line['warranty_end'] = prev['warranty_end'];
        line['warranty_terms'] = prev['warranty_terms'];
        continue;
      }
      final pid = (line['product_id'] as num?)?.toInt();
      final name = '${line['product_name'] ?? ''}'.trim();
      final key = pid != null ? '#$pid' : name;
      var (spec, terms) =
          specCache.containsKey(key) ? specCache[key]! : (specCache[key] = await _productSpec(d, pid, name));
      var start = DateTime(saleDate.year, saleDate.month, saleDate.day);

      // 📦 الدفعة التي تخرج منها أول قطعة في السطر: ضمانها وشروطها يتقدّمان على المادة
      StockBatch? batch;
      if (pid != null) {
        final bs = batchCache[pid] ??= await _batchesOf(d, pid);
        final offset = taken[pid] ?? 0;
        batch = bs.at(offset);
        taken[pid] = offset + _baseQty(line);
      }
      if (batch?.warranty != null && !batch!.warranty!.isNone) {
        spec = batch.warranty;
        terms = batch.terms ?? terms;
      }

      if (spec == null || spec.isNone) {
        line['warranty_spec'] = null;
        line['warranty_start'] = null;
        line['warranty_end'] = null;
        line['warranty_terms'] = null;
        continue;
      }
      if (spec.basis == WarrantyBasis.purchase && pid != null) {
        // من تاريخ شراء الدفعة نفسها؛ وبلا دفعة: آخر فاتورة شراء مؤكدة قبل البيع
        final bought = batch?.date ??
            (purchaseCache.containsKey(pid)
                ? purchaseCache[pid]
                : (purchaseCache[pid] = await _lastPurchase(d, pid, start)));
        if (bought != null) start = DateTime(bought.year, bought.month, bought.day);
      }
      line['warranty_spec'] = spec.encode();
      line['warranty_start'] = iso(start);
      line['warranty_end'] = iso(spec.endFrom(start));
      line['warranty_terms'] = terms;
    }
  }

  /// كمية السطر بالوحدة الأساسية — كدفتر المخزون (StockLedger._itemBaseQty).
  static double _baseQty(Map<String, dynamic> line) {
    final large = (line['quantity_large_unit'] as num?)?.toDouble() ?? 0;
    if (large > 0) {
      final per = (line['units_in_large_unit'] as num?)?.toDouble() ?? 0;
      return large * (per > 0 ? per : 1);
    }
    return (line['quantity_individual'] as num?)?.toDouble() ?? 0;
  }

  static Future<BatchSet> _batchesOf(DatabaseExecutor d, int productId) async {
    final r = await d.query('products', columns: ['sync_uuid'], where: 'id = ?', whereArgs: [productId], limit: 1);
    final u = r.isEmpty ? '' : '${r.first['sync_uuid'] ?? ''}';
    return u.isEmpty ? BatchSet.empty : ProductBatches.of(d, u);
  }

  /// مدة ضمان المادة وشروطه (الشروط null إن كانت فارغة).
  static Future<(WarrantySpec?, String?)> _productSpec(DatabaseExecutor d, int? productId, String name) async {
    const cols = ['warranty_spec', 'warranty_terms'];
    final r = productId != null
        ? await d.query('products', columns: cols, where: 'id = ?', whereArgs: [productId], limit: 1)
        : await d.query('products',
            columns: cols, where: 'name = ? AND COALESCE(is_deleted, 0) = 0', whereArgs: [name], limit: 1);
    if (r.isEmpty) return (null, null);
    final t = '${r.first['warranty_terms'] ?? ''}'.trim();
    return (WarrantySpec.parse(r.first['warranty_spec']), t.isEmpty ? null : t);
  }

  /// 🛡️ «شروط الضمان» تحت جدول المواد: سطر لكل شرط، ومعه المواد التي يخصّها.
  /// [lines]: (اسم المادة، شروطها كما ثُبِّتت على السطر). فارغ إن لم تكن شروط.
  static String termsNote(Iterable<(String, String?)> lines) {
    final byTerms = <String, List<String>>{};
    for (final (name, terms) in lines) {
      final t = (terms ?? '').trim();
      if (t.isEmpty) continue;
      final names = byTerms.putIfAbsent(t, () => []);
      if (!names.contains(name.trim())) names.add(name.trim());
    }
    if (byTerms.isEmpty) return '';
    return [
      for (final e in byTerms.entries) '• ${e.value.join('، ')}: ${e.key.replaceAll('\n', ' ')}',
    ].join('\n');
  }

  /// تاريخ آخر شراء مؤكد للمادة في يوم [onOrBefore] أو قبله.
  static Future<DateTime?> _lastPurchase(DatabaseExecutor d, int productId, DateTime onOrBefore) async {
    try {
      final r = await d.rawQuery(
          'SELECT MAX(substr(pi.date, 1, 10)) AS d FROM purchase_invoices pi '
          'JOIN purchase_invoice_items it ON it.invoice_id = pi.id '
          "WHERE it.product_id = ? AND pi.status = 'confirmed' AND substr(pi.date, 1, 10) <= ?",
          [productId, iso(onOrBefore)]);
      return DateTime.tryParse('${r.first['d'] ?? ''}');
    } catch (_) {
      return null; // جداول الشراء غير موجودة في قاعدة قديمة
    }
  }
}
