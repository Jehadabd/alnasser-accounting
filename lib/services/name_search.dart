// lib/services/name_search.dart
//
// 🔤 بحث الأسماء في كل البرنامج: الفواصل لا قيمة لها.
//   «جهاد عبد» = «جهادعبد» = «جهاد          عبد» = «جهاد-عبد» = «جهاد_عبد».
// الفواصل المتجاهلة: المسافة (أي عدد)، الشَّرطة -، الشَّرطة السفلية _، النقطة،
// الشرطة المائلة /، الفاصلة (، ,)، والتطويل ـ.
// يتجاهل أيضاً اختلاف الهمزات (أ/إ/آ ← ا)، ة/ه، ى/ي، ؤ/و، ئ/ي.
// كل كلمة مكتوبة يجب أن توجد في الاسم بأي ترتيب، والاسم كله يُقارن بلا فواصل.
//
// ملاحظة: هوية الحساب (أي عميل تذهب إليه الفاتورة) تبقى قاعدة CustomerNameRule:
// الاسم بلا مسافات. هذا الملف للبحث والاقتراح فقط ولا يغيّر أي رقم.

import 'database/core/database_helpers.dart';

class NameSearch {
  NameSearch._();

  /// الفواصل التي لا قيمة لها في البحث (نفسها في [sqlNorm] و[compact]).
  static const List<String> separators = [' ', '-', '_', '.', '/', '،', ',', 'ـ'];

  static const List<List<String>> _letters = [
    ['أ', 'ا'], ['إ', 'ا'], ['آ', 'ا'], ['ة', 'ه'], ['ى', 'ي'], ['ؤ', 'و'], ['ئ', 'ي'],
  ];

  static final RegExp _sepRe = RegExp(r'[\s\-_./،,ـ]+');

  /// تعبير SQL: العمود بلا فواصل وبحروف موحّدة — يطابق [compact] حرفاً بحرف.
  static String sqlNorm(String col) {
    var e = "COALESCE($col, '')";
    for (final s in separators) {
      e = "REPLACE($e, '$s', '')";
    }
    for (final l in _letters) {
      e = "REPLACE($e, '${l[0]}', '${l[1]}')";
    }
    return e;
  }

  /// النص بلا فواصل وبحروف موحّدة.
  static String compact(String s) => DatabaseHelpers.normalizeArabic(s.trim()).replaceAll(_sepRe, '');

  /// كلمات البحث (مقسومة عند أي فاصل) بعد التوحيد.
  static List<String> words(String query) =>
      query.trim().split(_sepRe).map(compact).where((w) => w.isNotEmpty).toList();

  /// هل يطابق [name] البحث [query]؟ (نفس منطق [where] للبحث في الذاكرة)
  static bool matches(String name, String query) {
    final ws = words(query);
    if (ws.isEmpty) return true;
    final n = compact(name);
    return ws.every(n.contains);
  }

  static String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  /// شرط WHERE (بين قوسين) ووسائطه. [phoneCol] اختياري: يطابق الهاتف بلا فواصل أيضاً.
  /// يعيد null إن كان البحث فارغاً.
  static ({String sql, List<Object?> args})? where(String nameCol, String query, {String? phoneCol}) {
    final q = query.trim();
    if (q.isEmpty) return null;
    final norm = sqlNorm(nameCol);
    final ws = words(q);
    final parts = <String>[];
    final args = <Object?>[];
    if (ws.isNotEmpty) {
      parts.add('(${ws.map((_) => "$norm LIKE ? ESCAPE '\\'").join(' AND ')})');
      args.addAll(ws.map((w) => '%${_esc(w)}%'));
    }
    if (phoneCol != null) {
      final digits = q.replaceAll(_sepRe, '');
      if (digits.isNotEmpty) {
        parts.add("REPLACE(REPLACE(COALESCE($phoneCol, ''), ' ', ''), '-', '') LIKE ? ESCAPE '\\'");
        args.add('%${_esc(digits)}%');
      }
    }
    if (parts.isEmpty) return null;
    return (sql: '(${parts.join(' OR ')})', args: args);
  }

  /// ترتيب: الاسم المطابق تماماً (بلا فواصل) أولاً، ثم ما يبدأ بالمكتوب، ثم الباقي.
  static ({String sql, List<Object?> args}) order(String nameCol, String query) {
    final c = compact(query);
    final norm = sqlNorm(nameCol);
    return (
      sql: "CASE WHEN $norm = ? THEN 0 WHEN $norm LIKE ? ESCAPE '\\' THEN 1 ELSE 2 END, $nameCol",
      args: [c, '${_esc(c)}%'],
    );
  }
}
