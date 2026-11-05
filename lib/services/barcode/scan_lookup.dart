// lib/services/barcode/scan_lookup.dart
//
// 🔎 مادة الرمز المقروء من القارئ أو الكاميرا — مطابقة تامة فقط (لا اقتراحات):
//   1) الباركود الأساسي أو أي باركود إضافي للمادة.
//   2) وإلا رمز المادة (item_code).
//   3) وإلا صيغتا UPC/EAN للرمز نفسه (القارئ قد يضيف صفراً في البداية أو يحذفه).
// لا يُعاد المادة المحذوفة، ولا مادة «للمدير فقط» لغير المدير. حالة الأحرف لا تهم.

import 'package:sqflite/sqflite.dart';

import '../../models/product.dart';
import '../auth_service.dart';

sealed class ScanMatch {
  const ScanMatch();
}

class ScanFound extends ScanMatch {
  const ScanFound(this.product);
  final Product product;
}

/// الرمز مسجّل لأكثر من مادة — يختار المستخدم.
class ScanAmbiguous extends ScanMatch {
  const ScanAmbiguous(this.products);
  final List<Product> products;
}

class ScanNotFound extends ScanMatch {
  const ScanNotFound();
}

class ScanLookup {
  ScanLookup._();

  static bool _adminSafe() {
    try {
      return AuthService().isAdmin;
    } catch (_) {
      return false;
    }
  }

  /// صيغ بديلة لرمز رقمي: EAN-13 يبدأ بصفر ⇔ UPC-A (12 رقماً).
  static List<String> variants(String code) {
    final c = code.trim();
    if (!RegExp(r'^\d+$').hasMatch(c)) return const [];
    if (c.length == 13 && c.startsWith('0')) return [c.substring(1)];
    if (c.length == 12) return ['0$c'];
    return const [];
  }

  /// أرقام المواد المطابقة (بلا تكرار، بالترتيب أعلاه).
  static Future<List<int>> ids(DatabaseExecutor db, String code, {bool? isAdmin}) async {
    final t = code.trim();
    if (t.isEmpty) return const [];
    final hide = (isAdmin ?? _adminSafe())
        ? ''
        : " AND NOT EXISTS (SELECT 1 FROM product_details dd WHERE dd.product_id = p.id AND COALESCE(dd.min_role, '') = 'admin')";
    Future<List<int>> byBarcode(String c) async {
      final r = await db.rawQuery('''
        SELECT p.id FROM products p
        WHERE COALESCE(p.is_deleted, 0) = 0$hide
          AND (TRIM(p.barcode) = ? COLLATE NOCASE
               OR p.id IN (SELECT product_id FROM product_barcodes WHERE TRIM(barcode) = ? COLLATE NOCASE))
        ORDER BY p.id LIMIT 10''', [c, c]);
      return [for (final x in r) (x['id'] as num).toInt()];
    }

    var found = await byBarcode(t);
    if (found.isNotEmpty) return found;
    final r = await db.rawQuery('''
      SELECT DISTINCT p.id FROM products p JOIN product_details d ON d.product_id = p.id
      WHERE COALESCE(p.is_deleted, 0) = 0$hide AND TRIM(d.item_code) = ? COLLATE NOCASE
      ORDER BY p.id LIMIT 10''', [t]);
    found = [for (final x in r) (x['id'] as num).toInt()];
    if (found.isNotEmpty) return found;
    for (final v in variants(t)) {
      found = await byBarcode(v);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  static Future<ScanMatch> find(DatabaseExecutor db, String code) async {
    final list = await ids(db, code);
    if (list.isEmpty) return const ScanNotFound();
    final rows = await db.rawQuery(
        'SELECT * FROM products WHERE id IN (${List.filled(list.length, '?').join(',')}) ORDER BY id', list);
    final products = [for (final r in rows) Product.fromMap(r)];
    if (products.isEmpty) return const ScanNotFound();
    return products.length == 1 ? ScanFound(products.first) : ScanAmbiguous(products);
  }
}
