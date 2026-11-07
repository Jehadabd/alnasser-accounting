// test/search/fuzzy_match_test.dart
import 'package:alnaser/services/search/fuzzy_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final names = {
    1: 'كوب ماء',
    2: 'كوب بيبسي',
    3: 'كوب عصير',
    4: 'جهاز انارة',
    5: 'كولا لتر',
    6: 'مصباح ليد 20 واط',
  };
  List<int> s(String q) => FuzzyMatch.search(q, names.entries);

  test('exact prefix still matches with zero errors', () {
    expect(s('كوب'), containsAll([1, 2, 3]));
  });

  test('one wrong letter in a 3-letter word', () {
    expect(s('كوت'), containsAll([1, 2, 3])); // ت بدل ب
  });

  test('extra letter and swapped letters', () {
    expect(s('بيبسس'), contains(2)); // حرف زائد/مختلف
    expect(s('كلوا'), contains(5)); // حرفان مقلوبان
  });

  test('two errors allowed only for long words', () {
    expect(s('مصبااح'), contains(6)); // 6 أحرف: حرف زائد
    expect(s('كز'), isEmpty); // كلمة قصيرة: لا تسامح
  });

  test('all words must match; fewer errors rank first', () {
    final r = s('كوب بيبسي');
    expect(r.first, 2);
    expect(s('كوب جهاز'), isEmpty);
  });

  test('distance bounds', () {
    expect(FuzzyMatch.prefixDistance('كوب', 'كوب', 1), 0);
    expect(FuzzyMatch.prefixDistance('كوت', 'كوب', 1), 1);
    expect(FuzzyMatch.prefixDistance('زيت', 'كوب', 1), isNull);
  });
}
