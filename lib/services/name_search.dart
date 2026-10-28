// lib/services/name_search.dart
//
// 🔤 بحث الأسماء في كل البرنامج: المسافات لا قيمة لها.
//   «إبراهيم محمد العسكر» = «ابراهيممحمدالعسكر» = «إبراهيم     محمد» (جزء من الاسم).
// يتجاهل أيضاً اختلاف الهمزات (أ/إ/آ ← ا)، ة/ه، ى/ي، ؤ/و، ئ/ي في البحث والاقتراحات.
// كل كلمة مكتوبة يجب أن توجد في الاسم بأي ترتيب، والاسم كله يُقارن بلا مسافات.
//
// ملاحظة: هوية الحساب (أي عميل تذهب إليه الفاتورة) تبقى قاعدة CustomerNameRule:
// الاسم بلا مسافات. هذا الملف للبحث والاقتراح فقط ولا يغيّر أي رقم.

import 'database/core/database_helpers.dart';

class NameSearch {
  NameSearch._();

  /// تعبير SQL: العمود بلا مسافات وبحروف موحّدة — يطابق [compact] حرفاً بحرف.
  static String sqlNorm(String col) => "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE("
      "REPLACE(COALESCE($col, ''), ' ', ''), 'أ', 'ا'), 'إ', 'ا'), 'آ', 'ا'), 'ة', 'ه'), 'ى', 'ي'), 'ؤ', 'و'), 'ئ', 'ي'), 'ـ', '')";

  /// النص بلا مسافات وبحروف موحّدة.
  static String compact(String s) => DatabaseHelpers.normalizeArabic(s.trim()).replaceAll(RegExp(r'\s+'), '');

  static String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  /// شرط WHERE (بين قوسين) ووسائطه. [phoneCol] اختياري: يطابق الهاتف بلا مسافات أيضاً.
  /// يعيد null إن كان البحث فارغاً.
  static ({String sql, List<Object?> args})? where(String nameCol, String query, {String? phoneCol}) {
    final q = query.trim();
    if (q.isEmpty) return null;
    final norm = sqlNorm(nameCol);
    final words = q.split(RegExp(r'\s+')).map(compact).where((w) => w.isNotEmpty).toList();
    final parts = <String>[];
    final args = <Object?>[];
    if (words.isNotEmpty) {
      parts.add('(${words.map((_) => "$norm LIKE ? ESCAPE '\\'").join(' AND ')})');
      args.addAll(words.map((w) => '%${_esc(w)}%'));
    }
    if (phoneCol != null) {
      final digits = q.replaceAll(RegExp(r'\s+'), '');
      parts.add("REPLACE(COALESCE($phoneCol, ''), ' ', '') LIKE ? ESCAPE '\\'");
      args.add('%${_esc(digits)}%');
    }
    if (parts.isEmpty) return null;
    return (sql: '(${parts.join(' OR ')})', args: args);
  }

  /// ترتيب: الاسم المطابق تماماً (بلا مسافات) أولاً، ثم ما يبدأ بالمكتوب، ثم الباقي.
  static ({String sql, List<Object?> args}) order(String nameCol, String query) {
    final c = compact(query);
    final norm = sqlNorm(nameCol);
    return (
      sql: "CASE WHEN $norm = ? THEN 0 WHEN $norm LIKE ? ESCAPE '\\' THEN 1 ELSE 2 END, $nameCol",
      args: [c, '${_esc(c)}%'],
    );
  }
}
