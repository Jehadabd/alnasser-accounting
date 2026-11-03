// lib/inventory/product_lookup.dart
//
// 🔎 البحث عن مادة — قاعدة واحدة لكل البرنامج:
//   • اسم المادة (أو اسمها الثاني): بلا اعتبار للفواصل والهمزات، وكل كلمة بأي ترتيب.
//   • رمز المادة (item_code): جزء منه.
//   • الباركود: الأساسي أو أي باركود إضافي — مطابقة تامة (كما يقرؤه الماسح).
// الرقم الداخلي (id) ليس وسيلة بحث (قرار المالك 2026-11-03): رقم تقني قد يتطابق
// مع جزء من رمز أو سعر فيُظهر مادة غير مقصودة.

import 'package:sqflite/sqflite.dart';

import '../services/auth_service.dart';
import '../services/name_search.dart';

class ProductLookup {
  ProductLookup._();

  /// شرط WHERE (بين قوسين) ووسائطه — [p] اسم جدول المواد و[d] جدول تفاصيلها في الاستعلام.
  /// null إن كان البحث فارغاً.
  static ({String sql, List<Object?> args})? where(String query, {String p = 'p', String d = 'd'}) {
    final t = query.trim();
    if (t.isEmpty) return null;
    final parts = <String>[];
    final args = <Object?>[];
    final byName = NameSearch.where('$p.name', t);
    if (byName != null) {
      parts.add(byName.sql);
      args.addAll(byName.args);
    }
    final bySecond = NameSearch.where('$d.second_name', t);
    if (bySecond != null) {
      parts.add(bySecond.sql);
      args.addAll(bySecond.args);
    }
    parts.add("$d.item_code LIKE ? ESCAPE '\\'");
    args.add('%${t.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%');
    parts.add('$p.barcode = ?');
    args.add(t);
    parts.add('$p.id IN (SELECT product_id FROM product_barcodes WHERE barcode = ?)');
    args.add(t);
    return (sql: '(${parts.join(' OR ')})', args: args);
  }

  /// اقتراحات المواد (الأقرب أولاً): الباركود/الرمز المطابق تماماً، ثم الاسم.
  static Future<List<Map<String, Object?>>> search(DatabaseExecutor db, String query, {int limit = 20}) async {
    final w = where(query);
    if (w == null) return const [];
    final t = query.trim();
    final hide = AuthService().isAdmin ? '' : " AND COALESCE(d.min_role, '') != 'admin'";
    final order = NameSearch.order('p.name', t);
    return db.rawQuery('''
      SELECT p.id, p.name, p.barcode, d.item_code
      FROM products p LEFT JOIN product_details d ON d.product_id = p.id
      WHERE COALESCE(p.is_deleted, 0) = 0 AND ${w.sql}$hide
      ORDER BY CASE WHEN p.barcode = ? OR d.item_code = ?
                      OR p.id IN (SELECT product_id FROM product_barcodes WHERE barcode = ?) THEN 0 ELSE 1 END,
               ${order.sql}
      LIMIT $limit
    ''', [...w.args, t, t, t, ...order.args]);
  }

  /// مادة واحدة بباركود أو رمز مطابق تماماً (للماسح وزر Enter) — null إن لم توجد أو تعددت.
  static Future<Map<String, Object?>?> exact(DatabaseExecutor db, String query) async {
    final t = query.trim();
    if (t.isEmpty) return null;
    final hide = AuthService().isAdmin ? '' : " AND COALESCE(d.min_role, '') != 'admin'";
    final r = await db.rawQuery('''
      SELECT p.id, p.name, p.barcode, d.item_code
      FROM products p LEFT JOIN product_details d ON d.product_id = p.id
      WHERE COALESCE(p.is_deleted, 0) = 0$hide
        AND (p.barcode = ? OR d.item_code = ? OR p.id IN (SELECT product_id FROM product_barcodes WHERE barcode = ?))
      LIMIT 2
    ''', [t, t, t]);
    return r.length == 1 ? r.first : null;
  }
}
