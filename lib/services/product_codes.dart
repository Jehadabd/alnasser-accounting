// lib/services/product_codes.dart
//
// 🔢 رمز المادة والباركود في شاشة «إنشاء فاتورة»:
//  • ذاكرة مؤقتة: رقم المنتج ← رمز المادة (من بطاقة المادة: product_details.item_code)
//    تُستعمل لعرض الرمز في السطر وطباعته في الفاتورة.
//  • بحث بالرمز / بالباركود يُرجع المرشحين، ثم يرتّبهم البحث الذكي
//    (العلاقات مع مواد الفاتورة الحالية) تماماً كبحث الاسم.
// لا يضيف أي عمود لجداول الفواتير — الرمز يُقرأ من بطاقة المادة وقت العرض/الطباعة.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import 'database_service.dart';
import 'smart_search/smart_search_service.dart';

/// نتيجة بحث: المادة + القيمة التي طابقت (الرمز أو الباركود)
class ProductCodeHit {
  const ProductCodeHit(this.product, this.code);
  final Product product;
  final String code;
}

class ProductCodes {
  ProductCodes._();

  static final Map<int, String> _codes = {};
  static bool _loaded = false;
  static Future<void>? _loading;

  /// رمز المادة لمنتج (null إن لم يُحدد له رمز أو لم تُحمّل الذاكرة بعد)
  static String? codeOf(int? productId) => productId == null ? null : _codes[productId];

  /// يحمّل الرموز مرة واحدة (لا يعيد التحميل إن كانت محمّلة)
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    await refresh();
  }

  /// يعيد قراءة كل الرموز (بعد تعديل بطاقة مادة أو قبل الطباعة)
  static Future<void> refresh() {
    return _loading ??= _doRefresh().whenComplete(() => _loading = null);
  }

  static Future<void> _doRefresh() async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.rawQuery(
          "SELECT product_id, item_code FROM product_details WHERE item_code IS NOT NULL AND TRIM(item_code) != ''");
      _codes
        ..clear()
        ..addEntries(rows
            .where((r) => r['product_id'] is int)
            .map((r) => MapEntry(r['product_id'] as int, '${r['item_code']}'.trim())));
      _loaded = true;
    } catch (e) {
      // جدول بطاقات المواد غير موجود بعد (قاعدة قديمة) ⇒ لا رموز
      debugPrint('⚠️ ProductCodes.refresh: $e');
      _loaded = true;
    }
  }

  /// عدد المرشحين قبل الترتيب الذكي (مثل بحث الاسم الذي يرتّب 300 نتيجة).
  static int _pool(int limit) => limit > 400 ? limit : 400;

  static String _likeEscape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  /// 🔍 بحث برمز المادة: المطابق تماماً أولاً، ثم ما يبدأ بالمكتوب، ثم ما يحتويه.
  /// داخل كل مجموعة يرتّب البحث الذكي حسب علاقة المادة بمواد الفاتورة.
  static Future<List<ProductCodeHit>> searchByCode(String query,
      {List<String>? currentInvoiceProductNames, int limit = 60}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final db = await DatabaseService().database;
      final rows = await db.rawQuery(
        '''SELECT p.*, d.item_code AS _hit_code FROM product_details d
           JOIN products p ON p.id = d.product_id
           WHERE d.item_code LIKE ? ESCAPE '\\'
           ORDER BY LENGTH(d.item_code), d.item_code
           LIMIT ?''',
        ['%${_likeEscape(q)}%', _pool(limit)],
      );
      return (await _rank(rows, q, currentInvoiceProductNames)).take(limit).toList();
    } catch (e) {
      debugPrint('⚠️ ProductCodes.searchByCode: $e');
      return const [];
    }
  }

  /// 🔍 بحث بالباركود: الباركود الأساسي للمادة + الباركودات الإضافية.
  static Future<List<ProductCodeHit>> searchByBarcode(String query,
      {List<String>? currentInvoiceProductNames, int limit = 60}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final db = await DatabaseService().database;
      final like = '%${_likeEscape(q)}%';
      final main = await db.rawQuery(
        '''SELECT p.*, TRIM(p.barcode) AS _hit_code FROM products p
           WHERE p.barcode LIKE ? ESCAPE '\\'
           ORDER BY LENGTH(p.barcode) LIMIT ?''',
        [like, _pool(limit)],
      );
      List<Map<String, Object?>> extra = const [];
      try {
        extra = await db.rawQuery(
          '''SELECT p.*, TRIM(b.barcode) AS _hit_code FROM product_barcodes b
             JOIN products p ON p.id = b.product_id
             WHERE b.barcode LIKE ? ESCAPE '\\'
             ORDER BY LENGTH(b.barcode) LIMIT ?''',
          [like, _pool(limit)],
        );
      } catch (_) {}
      return (await _rank([...main, ...extra], q, currentInvoiceProductNames)).take(limit).toList();
    } catch (e) {
      debugPrint('⚠️ ProductCodes.searchByBarcode: $e');
      return const [];
    }
  }

  /// مطابقة تامة واحدة (للماسح الضوئي / Enter)
  static ProductCodeHit? exact(List<ProductCodeHit> hits, String query) {
    final q = query.trim().toLowerCase();
    for (final h in hits) {
      if (h.code.trim().toLowerCase() == q) return h;
    }
    return null;
  }

  static Future<List<ProductCodeHit>> _rank(
      List<Map<String, Object?>> rows, String q, List<String>? names) async {
    final ql = q.toLowerCase();
    final codeOfId = <int, String>{};
    final exact = <Product>[];
    final prefix = <Product>[];
    final contains = <Product>[];
    for (final r in rows) {
      final id = r['id'];
      if (id is! int || codeOfId.containsKey(id)) continue; // مادة مكررة (عدة باركودات)
      final code = '${r['_hit_code'] ?? ''}'.trim();
      codeOfId[id] = code;
      final p = Product.fromMap(r);
      final cl = code.toLowerCase();
      if (cl == ql) {
        exact.add(p);
      } else if (cl.startsWith(ql)) {
        prefix.add(p);
      } else {
        contains.add(p);
      }
    }
    final smart = SmartSearchService.instance;
    final rankedPrefix = await smart.rankCandidates(prefix, currentInvoiceProductNames: names);
    final rankedContains = await smart.rankCandidates(contains, currentInvoiceProductNames: names);
    return [
      for (final p in [...exact, ...rankedPrefix, ...rankedContains])
        if (p.id != null) ProductCodeHit(p, codeOfId[p.id] ?? ''),
    ];
  }
}

/// ⌨️ إعداد: لغة الكتابة داخل خانة «رمز المادة» إنجليزية تلقائياً (ويندوز)،
/// وتعود اللغة السابقة عند الخروج منها. إعداد هذا الجهاز فقط.
class ItemCodeKeyboard {
  ItemCodeKeyboard._();

  static const _k = 'item_code_force_english_v1';
  static bool forceEnglish = false;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      forceEnglish = p.getBool(_k) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    forceEnglish = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_k, v);
  }
}
