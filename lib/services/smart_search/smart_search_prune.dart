// lib/services/smart_search/smart_search_prune.dart
//
// ✂️ سقف حجم «المواد التي تُشترى معاً» — دالة صافية (تُختبر وحدها).
//
// لكل مادة تبقى أقوى [keep] علاقة لها (الأكثر تكراراً، ثم الأحدث). العلاقة تبقى إن كانت
// ضمن الأقوى لأيٍّ من طرفيها. والعلاقة الحديثة (آخر [graceDays] يوماً) لا تُحذف أبداً،
// حتى تأخذ العلاقة الجديدة فرصتها لتكبر قبل أن تُقارن بالقديمة.
// النتيجة: حجم الجدول ≤ عدد المواد × [keep] + علاقات الشهر الأخير — مهما طال الاستعمال.
// البحث يرتّب بالأكثر تكراراً، فحذف الأضعف لا يغيّر ما يظهر في أعلى الاقتراحات.

class PruneRow {
  const PruneRow(this.id, this.groupA, this.groupB, this.count, this.updatedAt);
  final int id;

  /// المجموعة الأولى (المادة أ)، والثانية (المادة ب) — أو null إن كان للصف مجموعة واحدة.
  final Object groupA;
  final Object? groupB;
  final int count;
  final String updatedAt;
}

class SmartSearchPrune {
  SmartSearchPrune._();

  /// معرّفات الصفوف التي تُحذف.
  static List<int> idsToDelete(List<PruneRow> rows, {required int keep, required String cutoffIso}) {
    final groups = <Object, List<PruneRow>>{};
    for (final r in rows) {
      groups.putIfAbsent(r.groupA, () => []).add(r);
      if (r.groupB != null) groups.putIfAbsent(r.groupB!, () => []).add(r);
    }
    final kept = <int>{};
    for (final list in groups.values) {
      list.sort((x, y) {
        final c = y.count.compareTo(x.count);
        return c != 0 ? c : y.updatedAt.compareTo(x.updatedAt);
      });
      for (final r in list.take(keep)) {
        kept.add(r.id);
      }
    }
    return [
      for (final r in rows)
        if (!kept.contains(r.id) && r.updatedAt.compareTo(cutoffIso) < 0) r.id,
    ];
  }
}
