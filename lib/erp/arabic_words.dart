// lib/erp/arabic_words.dart
//
// 🔤 التفقيط: كتابة المبلغ بالحروف العربية (مثل الإداري: «ألف وخمسون دينار لا غير»).

class ArabicWords {
  ArabicWords._();

  static const List<String> _ones = [
    '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة', 'سبعة', 'ثمانية', 'تسعة',
    'عشرة', 'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر', 'خمسة عشر',
    'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
  ];
  static const List<String> _tens = [
    '', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون', 'ستون', 'سبعون', 'ثمانون', 'تسعون',
  ];
  static const List<String> _hundreds = [
    '', 'مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة', 'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة',
  ];

  /// 0..999
  static String _below1000(int n) {
    final parts = <String>[];
    final h = n ~/ 100;
    final rest = n % 100;
    if (h > 0) parts.add(_hundreds[h]);
    if (rest > 0) {
      if (rest < 20) {
        parts.add(_ones[rest]);
      } else {
        final t = rest ~/ 10;
        final o = rest % 10;
        parts.add(o == 0 ? _tens[t] : '${_ones[o]} و${_tens[t]}');
      }
    }
    return parts.join(' و');
  }

  /// مجموعة (آلاف/ملايين/مليارات) بصيغتها العددية الصحيحة.
  static String _scaled(int count, String one, String two, String plural, String many) {
    if (count == 1) return one;
    if (count == 2) return two;
    if (count >= 3 && count <= 10) return '${_below1000(count)} $plural';
    return '${_below1000(count)} $many';
  }

  /// عدد صحيح موجب إلى كلمات.
  static String integer(int n) {
    if (n == 0) return 'صفر';
    if (n < 0) return 'سالب ${integer(-n)}';
    final parts = <String>[];
    final billions = n ~/ 1000000000;
    final millions = (n ~/ 1000000) % 1000;
    final thousands = (n ~/ 1000) % 1000;
    final rest = n % 1000;
    if (billions > 0) parts.add(_scaled(billions, 'مليار', 'ملياران', 'مليارات', 'مليار'));
    if (millions > 0) parts.add(_scaled(millions, 'مليون', 'مليونان', 'ملايين', 'مليون'));
    if (thousands > 0) parts.add(_scaled(thousands, 'ألف', 'ألفان', 'آلاف', 'ألف'));
    if (rest > 0) parts.add(_below1000(rest));
    return parts.join(' و');
  }

  /// مبلغ بعملة: «فقط مئة وخمسون ألف دينار عراقي لا غير».
  static String money(double amount, {String currency = 'IQD'}) {
    final negative = amount < 0;
    final abs = amount.abs();
    var whole = abs.floor();
    var fraction = ((abs - whole) * 100).round();
    if (fraction == 100) {
      whole += 1;
      fraction = 0;
    }
    final String main;
    final String sub;
    switch (currency) {
      case 'USD':
        main = 'دولار أمريكي';
        sub = 'سنت';
        break;
      default:
        main = 'دينار عراقي';
        sub = 'فلس';
    }
    final b = StringBuffer('فقط ');
    if (negative) b.write('سالب ');
    b.write('${integer(whole)} $main');
    if (fraction > 0) b.write(' و${integer(fraction)} $sub');
    b.write(' لا غير');
    return b.toString();
  }
}
