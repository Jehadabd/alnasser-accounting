// lib/services/search/fuzzy_match.dart
//
// 🔤 بحث يتحمّل خطأ حرف أو حرفين في اسم المادة («كوت» ← «كوب»، «بيبسس» ← «بيبسي»،
// «كلوا» ← «كولا»). دالة صافية بلا قاعدة بيانات — تُختبر وحدها.
//
// القاعدة: كل كلمة يكتبها المستخدم يجب أن تطابق بداية كلمة في اسم المادة، مع سماح:
//   كلمة من حرفين أو أقل  ← لا خطأ (تطابق تام للبداية)
//   3–5 أحرف             ← خطأ واحد
//   6 أحرف فأكثر          ← خطأان
// والخطأ: حرف زائد، أو ناقص، أو مختلف، أو حرفان متجاوران مقلوبان.
// النص يُطبَّع قبل المقارنة (أ/إ/آ←ا، ة←ه، ى←ي...) بالطريقة نفسها المستعملة في البحث.

class FuzzyMatch {
  FuzzyMatch._();

  /// الأخطاء المسموحة لكلمة بهذا الطول.
  static int allowedErrors(int len) => len <= 2 ? 0 : (len <= 5 ? 1 : 2);

  /// أقل عدد أخطاء بين [q] وبداية [word] (بطول q-1 .. q+1)، أو null إن تجاوز [maxErr].
  static int? prefixDistance(String q, String word, int maxErr) {
    if (word.startsWith(q)) return 0;
    if (maxErr == 0) return null;
    int? best;
    for (var len = q.length - maxErr; len <= q.length + maxErr; len++) {
      if (len < 1 || len > word.length) continue;
      final d = _osa(q, word.substring(0, len), maxErr);
      if (d != null && (best == null || d < best)) best = d;
      if (best == 1) break;
    }
    return best;
  }

  /// مسافة التحرير (مع قلب حرفين متجاورين) بقطعٍ مبكر عند تجاوز [maxErr].
  static int? _osa(String a, String b, int maxErr) {
    if ((a.length - b.length).abs() > maxErr) return null;
    final n = a.length, m = b.length;
    var prev2 = List<int>.filled(m + 1, 0);
    var prev = List<int>.generate(m + 1, (j) => j);
    var cur = List<int>.filled(m + 1, 0);
    for (var i = 1; i <= n; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= m; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) &&
            prev2[j - 2] + 1 < v) {
          v = prev2[j - 2] + 1;
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > maxErr) return null;
      final t = prev2;
      prev2 = prev;
      prev = cur;
      cur = t;
    }
    final d = prev[m];
    return d <= maxErr ? d : null;
  }

  /// مجموع الأخطاء لمطابقة كل كلمات [queryWords] في [nameWords]، أو null إن لم تطابق كلها.
  static int? match(List<String> queryWords, List<String> nameWords) {
    var total = 0;
    for (final q in queryWords) {
      final maxErr = allowedErrors(q.length);
      int? best;
      for (final w in nameWords) {
        final d = prefixDistance(q, w, maxErr);
        if (d != null && (best == null || d < best)) best = d;
        if (best == 0) break;
      }
      if (best == null) return null;
      total += best;
    }
    return total;
  }

  /// أفضل [limit] نتيجة من [names] (معرّف ← اسم مطبَّع): الأقل أخطاءً ثم الأقصر اسماً.
  /// يشمل المطابق بلا أخطاء أيضاً — المستدعي يدمج النتائج ويزيل التكرار.
  static List<int> search(String normalizedQuery, Iterable<MapEntry<int, String>> names, {int limit = 50}) {
    final qWords = normalizedQuery.split(' ').where((w) => w.isNotEmpty).toList();
    if (qWords.isEmpty) return const [];
    final hits = <(int, int, int)>[]; // (id, errors, nameLength)
    for (final e in names) {
      final words = e.value.split(' ').where((w) => w.isNotEmpty).toList();
      final d = match(qWords, words);
      if (d != null) hits.add((e.key, d, e.value.length));
    }
    hits.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));
    return [for (final h in hits.take(limit)) h.$1];
  }
}
