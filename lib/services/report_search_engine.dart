// lib/services/report_search_engine.dart
//
// 🔎 محرّك «البحث الذكي في التقارير» — Dart خالص (بلا واجهة ولا قاعدة بيانات) فيُختبر وحده.
//
//   • ArabicNorm: توحيد الكتابة (أ/إ/آ ← ا، ة ← ه، ى ← ي، التشكيل، الأرقام الهندية…) وجذع خفيف
//     (ال، وال، بال، ات، ين…) — فـ«الأرباح» و«ارباح» و«ربح» تصل إلى الشيء نفسه.
//   • ReportQuery.parse: يستخرج الفترة من الكلام («2025»، «هذه السنة»، «الشهر الماضي»، «شباط 2024»،
//     «أمس»…) ويُبقي الكلمات الباقية للمطابقة.
//   • ReportCatalog: كل تقرير مع مجموعة كلمات ومرادفات بالمعنى (لا كلمة واحدة محددة)،
//     ويرتّبها بالأقرب: تطابق تام، جذع، بداية كلمة، أو خطأ حرف واحد في الكلمات الطويلة.
//   • nameScore: مطابقة اسم (مادة، عميل، موظف…) بنفس التوحيد.
//
// للقراءة فقط — لا يغيّر شيئاً.

/// توحيد النص العربي للمطابقة.
class ArabicNorm {
  ArabicNorm._();

  static final _tashkeel = RegExp('[\u064B-\u0652\u0670\u0640]');
  static final _punct = RegExp(r'''[\s\.,،؛;:!؟\?\-_/\\\(\)\[\]\{\}"'«»<>|+*=#@%&~^`]+''');

  static String normalize(String input) {
    var s = input.toLowerCase().replaceAll(_tashkeel, '');
    final b = StringBuffer();
    for (final r in s.runes) {
      var c = r;
      if (c >= 0x0660 && c <= 0x0669) c = 0x30 + (c - 0x0660); // ٠-٩
      if (c >= 0x06F0 && c <= 0x06F9) c = 0x30 + (c - 0x06F0); // ۰-۹ الفارسية
      switch (c) {
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0622: // آ
        case 0x0671: // ٱ
          c = 0x0627;
          break;
        case 0x0629: // ة
          c = 0x0647;
          break;
        case 0x0649: // ى
        case 0x0626: // ئ
          c = 0x064A;
          break;
        case 0x0624: // ؤ
          c = 0x0648;
          break;
        case 0x06A9: // ک
          c = 0x0643;
          break;
        case 0x06CC: // ی
          c = 0x064A;
          break;
      }
      b.writeCharCode(c);
    }
    s = b.toString().replaceAll(_punct, ' ').replaceAll('\$', ' دولار ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> words(String input) {
    final n = normalize(input);
    return n.isEmpty ? const [] : n.split(' ');
  }

  static const _prefixes = ['وال', 'بال', 'فال', 'كال', 'لل', 'ال'];
  static const _suffixes = ['ات', 'ون', 'ين', 'ان', 'يه', 'ه', 'ي'];

  /// جذع خفيف: بلا «ال» في البداية وبلا جمع/تأنيث في النهاية (إن بقي 3 أحرف على الأقل).
  static String stem(String w) {
    var s = w;
    for (final p in _prefixes) {
      if (s.startsWith(p) && s.length - p.length >= 3) {
        s = s.substring(p.length);
        break;
      }
    }
    for (final x in _suffixes) {
      if (s.endsWith(x) && s.length - x.length >= 3) {
        s = s.substring(0, s.length - x.length);
        break;
      }
    }
    return s;
  }

  /// بلا «ال/وال/بال…» فقط («الأرباح» = «أرباح» تماماً).
  static String bare(String w) {
    for (final p in _prefixes) {
      if (w.startsWith(p) && w.length - p.length >= 2) return w.substring(p.length);
    }
    return w;
  }

  /// مسافة التحرير (لخطأ حرف واحد) — للكلمات القصيرة فقط فلا كلفة.
  static int distance(String a, String b) {
    if (a == b) return 0;
    if ((a.length - b.length).abs() > 1) return 99;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost];
        cur[j] = v.reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// مدى تطابق كلمة من البحث مع كلمة مفتاحية: 3 تام، 2.6 نفس الجذع، 2 بداية كلمة، 1.4 خطأ حرف.
  static double wordMatch(String q, String k) {
    if (q.isEmpty || k.isEmpty) return 0;
    if (q == k || bare(q) == bare(k)) return 3;
    final qs = stem(q), ks = stem(k);
    if (qs == ks) return 2.6;
    if (qs.length >= 3 && ks.length >= 3 && (ks.startsWith(qs) || qs.startsWith(ks))) return 2;
    if (qs.length >= 4 && ks.length >= 4 && distance(qs, ks) <= 1) return 1.4;
    return 0;
  }
}

/// فترة مفهومة من نص البحث.
class ReportPeriod {
  const ReportPeriod(this.from, this.to, this.label, {this.year});
  final DateTime from;
  final DateTime to;
  final String label;

  /// سنة واحدة (لتقارير المادة والعميل التي تعرض السنوات).
  final int? year;

  @override
  String toString() => '$label ($from → $to)';
}

/// نص البحث بعد تحليله: الفترة + الكلمات الباقية + الأرقام.
class ReportQuery {
  ReportQuery._(this.raw, this.normalized, this.period, this.words, this.numbers);

  final String raw;
  final String normalized;
  final ReportPeriod? period;

  /// الكلمات المهمة (بلا كلمات الفترة ولا الكلمات العامة مثل «تقرير، عن، في»).
  final List<String> words;

  /// أرقام في النص (رقم فاتورة أو باركود) غير السنة.
  final List<String> numbers;

  bool get isEmpty => words.isEmpty && numbers.isEmpty && period == null;

  // «على» ليست هنا: تصير «علي» بعد التوحيد وهو اسم شائع.
  static const stopWords = {
    'تقرير', 'تقارير', 'التقرير', 'التقارير', 'عن', 'في', 'من', 'الى', 'لي', 'ل', 'و', 'او', 'ثم', 'يا', 'بس',
    'كم', 'ما', 'ماذا', 'هو', 'هي', 'هل', 'اريد', 'اريد اعرف', 'بدي', 'ابي', 'ابغى', 'ابغي', 'عايز', 'اعرض', 'اعرضلي',
    'عرض', 'اظهر', 'طلعلي', 'طلع', 'جيبلي', 'ورني', 'وريني', 'شوفني', 'اعطني', 'ابحث', 'بحث', 'دورلي', 'اعرف',
    'شو', 'ايش', 'وش', 'شنو', 'شنهو', 'شكد', 'شقد', 'اشكد', 'قديش', 'كام', 'ليش', 'وين', 'منو', 'مين', 'لو', 'رجاء',
    'كل', 'جميع', 'مع', 'الي', 'التي', 'الذي', 'اللي', 'هذا', 'هذه', 'هاي', 'هذي', 'هاد', 'ذلك', 'خلال', 'عندي', 'عندنا',
    'فتره', 'الفتره', 'سنه', 'السنه', 'عام', 'العام', 'شهر', 'الشهر', 'يوم', 'لسنه', 'بسنه', 'بشهر', 'لشهر', 'تاريخ',
    'حسب', 'بحسب', 'تبع', 'تبعات', 'مال', 'خاص', 'خاصه', 'قائمه', 'شاشه', 'صفحه', 'زر', 'report', 'reports', 'show', 'the',
    'of', 'for', 'in', 'my',
  };

  static const _months = <String, int>{
    'كانون الثاني': 1, 'شباط': 2, 'اذار': 3, 'نيسان': 4, 'ايار': 5, 'حزيران': 6, 'تموز': 7, 'اب': 8,
    'ايلول': 9, 'تشرين الاول': 10, 'تشرين الثاني': 11, 'كانون الاول': 12,
    'يناير': 1, 'فبراير': 2, 'مارس': 3, 'ابريل': 4, 'مايو': 5, 'يونيو': 6, 'يوليو': 7, 'اغسطس': 8,
    'سبتمبر': 9, 'اكتوبر': 10, 'نوفمبر': 11, 'ديسمبر': 12,
  };

  static const monthNames = [
    '', 'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول',
    'تشرين الثاني', 'كانون الأول',
  ];

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  static ReportQuery parse(String raw, {DateTime? now}) {
    final today = _d(now ?? DateTime.now());
    var s = ' ${ArabicNorm.normalize(raw)} ';
    ReportPeriod? period;

    bool take(List<String> phrases) {
      for (final p in phrases) {
        final pat = ' $p ';
        if (s.contains(pat)) {
          s = s.replaceFirst(pat, ' ');
          return true;
        }
      }
      return false;
    }

    // ── كلمات الفترة النسبية (الأطول أولاً) ──
    if (take(['السنه الماضيه', 'العام الماضي', 'السنه السابقه', 'العام السابق', 'السنه اللي فاتت', 'سنه الماضيه'])) {
      final y = today.year - 1;
      period = ReportPeriod(DateTime(y, 1, 1), DateTime(y, 12, 31), 'سنة $y', year: y);
    } else if (take(['هذه السنه', 'هذا العام', 'السنه الحاليه', 'العام الحالي', 'هاي السنه', 'هالسنه', 'السنه هذه'])) {
      period = ReportPeriod(DateTime(today.year, 1, 1), today, 'هذه السنة (${today.year})', year: today.year);
    } else if (take(['الشهر الماضي', 'الشهر السابق', 'الشهر اللي فات', 'شهر الماضي'])) {
      final f = DateTime(today.year, today.month - 1, 1);
      period = ReportPeriod(f, DateTime(today.year, today.month, 0), 'الشهر الماضي (${monthNames[f.month]} ${f.year})');
    } else if (take(['هذا الشهر', 'الشهر الحالي', 'هالشهر', 'هاد الشهر', 'الشهر هذا'])) {
      period = ReportPeriod(DateTime(today.year, today.month, 1), today, 'هذا الشهر (${monthNames[today.month]})');
    } else if (take(['الاسبوع الماضي', 'الاسبوع السابق', 'الجمعه الماضيه'])) {
      final ws = DateTime(today.year, today.month, today.day - (today.weekday + 1) % 7 - 7);
      period = ReportPeriod(ws, DateTime(ws.year, ws.month, ws.day + 6), 'الأسبوع الماضي');
    } else if (take(['هذا الاسبوع', 'الاسبوع الحالي', 'هالاسبوع', 'الاسبوع'])) {
      final ws = DateTime(today.year, today.month, today.day - (today.weekday + 1) % 7);
      period = ReportPeriod(ws, today, 'هذا الأسبوع');
    } else if (take(['امس', 'البارحه', 'مبارح', 'يوم امس'])) {
      final y = DateTime(today.year, today.month, today.day - 1);
      period = ReportPeriod(y, y, 'أمس');
    } else if (take(['اليوم', 'هذا اليوم', 'هليوم', 'النهارده'])) {
      period = ReportPeriod(today, today, 'اليوم');
    }

    // ── سنة صريحة: 2000–2099 ──
    int? year;
    final yearRx = RegExp(r' (20\d\d) ');
    final ym = yearRx.firstMatch(s);
    if (ym != null) {
      year = int.parse(ym.group(1)!);
      s = s.replaceFirst(ym.group(0)!, ' ');
    }

    // ── اسم شهر (كانون الثاني، شباط، مارس…) ──
    int? month;
    final keys = _months.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      if (s.contains(' $k ')) {
        month = _months[k];
        s = s.replaceFirst(' $k ', ' ');
        break;
      }
    }

    if (month != null) {
      var y = year ?? period?.year ?? today.year;
      if (year == null && period?.year == null && DateTime(y, month, 1).isAfter(today)) y--;
      final last = DateTime(y, month + 1, 0);
      period = ReportPeriod(DateTime(y, month, 1), last.isAfter(today) ? today : last, '${monthNames[month]} $y');
    } else if (year != null) {
      final end = DateTime(year, 12, 31);
      period = ReportPeriod(DateTime(year, 1, 1), end.isAfter(today) && year == today.year ? today : end, 'سنة $year',
          year: year);
    }

    final words = <String>[];
    final numbers = <String>[];
    for (final w in s.trim().split(' ')) {
      if (w.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(w)) {
        numbers.add(w);
      } else if (!stopWords.contains(w)) {
        words.add(w);
      }
    }
    return ReportQuery._(raw, ArabicNorm.normalize(raw), period, words, numbers);
  }
}

/// تقرير في الفهرس: معرّف + كلمات بالمعنى (جمل قصيرة ومرادفات).
class ReportIntent {
  const ReportIntent(this.id, this.keywords, {this.boost = 0});
  final String id;
  final List<String> keywords;

  /// ترجيح بسيط عند التساوي (التقرير «الأصل» قبل الأعم).
  final double boost;
}

class IntentHit {
  IntentHit(this.intent, this.score);
  final ReportIntent intent;
  final double score;
  String get id => intent.id;
}

/// 📚 فهرس التقارير وكلماتها — المعنى لا الكلمة الحرفية.
class ReportCatalog {
  ReportCatalog._();

  static const intents = <ReportIntent>[
    // ───────────── الربح والمبيعات ─────────────
    ReportIntent('profit', [
      'ربح', 'ارباح', 'الربح', 'الارباح', 'صافي الربح', 'الربح الصافي', 'اجمالي الربح', 'مجمل الربح', 'كم ربحت',
      'ربحت', 'ربحنا', 'نربح', 'رابح', 'مربح', 'مربوح', 'فائده', 'فوائد', 'الفائده', 'مكسب', 'مكاسب', 'كسبت', 'كسبنا',
      'هامش', 'هامش الربح', 'نسبه الربح', 'نسبه الفائده', 'الربحيه', 'العائد', 'المردود', 'الصافي', 'طلعت ربح',
      'شكد ربحت', 'شكد طلعت', 'شقد ربحت', 'قديش ربحت', 'كام كسبت', 'وش ربحت', 'شكد مستفيد', 'استفدت', 'الاستفاده',
      'خساره', 'خسائر', 'خسرت', 'خسرنا', 'خاسر', 'ربح ولا خساره', 'هل انا رابح', 'رابح او خاسر', 'الزبده',
      'ربح المحل', 'ربح الشهر', 'ربح اليوم', 'ربح السنه', 'ارباح المحل', 'profit', 'profits', 'margin', 'gain',
      'net profit', 'loss',
    ], boost: 0.4),
    ReportIntent('sales', [
      'مبيعات', 'المبيعات', 'مبيع', 'بيع', 'البيع', 'بعت', 'بعنا', 'نبيع', 'يبيع', 'بيعات', 'كم بعت', 'شكد بعت',
      'شقد بعت', 'قديش بعت', 'كام بعت', 'وش بعت', 'شكد بايع', 'شكد طلع البيع', 'حركه البيع', 'حركه المحل', 'الشغل',
      'شغل اليوم', 'شلون الشغل', 'شلون البيع', 'كيف البيع', 'البيع ماشي', 'فواتير', 'فاتوره', 'الفواتير', 'الغله',
      'غله', 'الغلة اليوميه', 'الوارد', 'الدخل', 'دخل المحل', 'ايراد', 'ايرادات', 'الايراد', 'المدخول', 'مدخول',
      'الحصيله', 'حصيله', 'الكاش اليومي', 'تقرير يومي', 'تقرير شهري', 'تقرير سنوي', 'تقرير اسبوعي', 'يومي', 'شهري',
      'سنوي', 'اسبوعي', 'ملخص', 'ملخص المبيعات', 'اجمالي المبيعات', 'مجموع المبيعات', 'صافي المبيعات', 'رقم المبيعات',
      'عدد الفواتير', 'متوسط الفاتوره', 'sales', 'sale', 'revenue', 'turnover', 'invoices', 'sold',
    ], boost: 0.3),
    ReportIntent('income_statement', [
      'قائمه الدخل', 'قائمه الارباح', 'الارباح والخسائر', 'ارباح وخسائر', 'الربح والخساره', 'صافي الدخل', 'نتيجه النشاط',
      'حساب الارباح والخسائر', 'بيان الدخل', 'قائمه النتائج', 'الايرادات والمصاريف', 'الدخل والمصروف',
      'income statement', 'profit and loss', 'p&l', 'pnl',
    ]),
    ReportIntent('balance_sheet', [
      'الميزانيه', 'الميزانيه العموميه', 'ميزانيه', 'ميزانيه عموميه', 'اصول', 'الاصول', 'خصوم', 'الخصوم', 'حقوق الملكيه',
      'راس المال', 'راسمال', 'المركز المالي', 'الوضع المالي', 'شكد عندي', 'شكد قيمه المحل', 'قيمه المحل', 'ثروتي',
      'ممتلكات', 'التزامات', 'المطلوبات', 'الموجودات', 'balance sheet', 'assets', 'liabilities', 'equity',
    ]),
    ReportIntent('trial_balance', [
      'ميزان المراجعه', 'ميزان', 'ارصده الحسابات', 'رصيد الحسابات', 'مدين ودائن', 'مدين', 'دائن', 'الحسابات',
      'شجره الحسابات', 'دليل الحسابات', 'الدفتر', 'دفتر الاستاذ', 'القيود', 'قيود', 'قيد', 'اليوميه العامه',
      'trial balance', 'ledger', 'accounts', 'journal',
    ]),
    ReportIntent('sales_detail', [
      'المبيعات التفصيلي', 'تفصيلي', 'تقرير مفصل', 'مفصل', 'بالتفصيل', 'تفاصيل الفواتير', 'كل فاتوره', 'فاتوره فاتوره',
      'المتبقي', 'الباقي على الفواتير', 'المدفوع', 'المسدد', 'تصدير الفواتير', 'اكسل', 'excel', 'تصدير', 'جدول الفواتير',
      'كشف الفواتير', 'قائمه الفواتير', 'سجل الفواتير', 'sales detail', 'invoice list', 'export',
    ]),
    // ───────────── المصاريف والسندات ─────────────
    ReportIntent('expenses', [
      'مصاريف', 'مصروفات', 'مصروف', 'المصاريف', 'نفقات', 'النفقات', 'مصرف', 'صرفيات', 'الصرفيات', 'اين ذهبت الاموال',
      'اين راحت الفلوس', 'وين راحت الفلوس', 'وين صرفت', 'شكد صرفت', 'قديش صرفت', 'كام صرفت', 'الفلوس وين راحت',
      'كهرباء', 'الكهرباء', 'مولده', 'المولده', 'امبيرات', 'ايجار', 'اجار', 'الايجار', 'الاجار', 'رواتب', 'الرواتب',
      'اجور', 'الاجور', 'معاش', 'معاشات', 'انترنت', 'نت', 'ماء', 'مياه', 'نقل', 'اجور نقل', 'بنزين', 'وقود', 'تصليحات',
      'ضيافه', 'نظافه', 'قرطاسيه', 'ضرائب', 'رسوم', 'تحليل المصاريف', 'توزيع المصاريف', 'اكبر المصاريف',
      'expenses', 'expense', 'costs', 'spending', 'bills', 'rent', 'salary', 'salaries', 'electricity',
    ], boost: 0.2),
    ReportIntent('vouchers', [
      'سندات', 'سند', 'السندات', 'ملخص السندات', 'السندات المسحوبه', 'كل السندات', 'حركه السندات', 'سجل السندات',
      'الوصولات والسندات', 'اوراق الصندوق', 'vouchers', 'voucher',
    ], boost: 0.1),
    ReportIntent('vouchers_receipt', [
      'سند قبض', 'سندات قبض', 'سندات القبض', 'سند القبض', 'قبض', 'القبض', 'مقبوضات', 'المقبوضات', 'المقبوض', 'استلام',
      'استلمت', 'قبضت', 'مستلم', 'اموال داخله', 'فلوس داخله', 'دخل للصندوق', 'ايداع', 'ايداعات', 'receipt voucher',
      'receipts', 'cash in',
    ], boost: 0.3),
    ReportIntent('vouchers_payment', [
      'سند صرف', 'سندات صرف', 'سندات الصرف', 'سند الصرف', 'صرف', 'مدفوعات', 'المدفوعات', 'دفعت', 'دفعنا', 'سلمت',
      'اموال خارجه', 'فلوس طالعه', 'خرج من الصندوق', 'طلع من الصندوق', 'payment voucher', 'payments', 'cash out',
    ]),
    ReportIntent('vouchers_expense', [
      'سند مصروف', 'سندات مصروف', 'سندات المصاريف', 'سند المصروف', 'وصولات المصاريف', 'expense voucher',
    ]),
    ReportIntent('vouchers_income', [
      'سند ايراد', 'سندات ايراد', 'سندات الايراد', 'ايرادات اخرى', 'ايراد اخر', 'دخل اخر', 'دخل اضافي', 'ايراد جانبي',
      'other income',
    ]),
    ReportIntent('drawings', [
      'مسحوبات', 'المسحوبات', 'مسحوبات المالك', 'مسحوبات شخصيه', 'سحب المالك', 'سحوبات', 'سحبت', 'سحب', 'سحب شخصي',
      'اخذت من الصندوق', 'اخذت فلوس', 'شكد سحبت', 'شكد اخذت', 'مصروف البيت', 'مصاريف البيت', 'مصروف شخصي',
      'drawings', 'withdrawals', 'owner',
    ], boost: 0.1),
    ReportIntent('receipts_list', [
      'وصل قبض', 'وصولات', 'وصولات القبض', 'وصل', 'الوصولات', 'تسديد', 'تسديدات', 'تسديد الديون', 'سداد', 'السداد',
      'دفعات العملاء', 'دفعه', 'دفعات', 'تحصيل', 'التحصيلات', 'سدد', 'سددوا', 'منو سدد', 'مين سدد', 'من سدد',
      'شكد تسدد', 'الواصل', 'واصل', 'customer receipts', 'collections',
    ], boost: 0.1),
    ReportIntent('cash', [
      'حركه الصندوق', 'الصندوق', 'صندوق', 'الصناديق', 'كاش', 'الكاش', 'النقد', 'النقديه', 'السيوله', 'سيوله', 'الخزنه',
      'خزنه', 'القاصه', 'قاصه', 'الدرج', 'الوارد والصادر', 'شكد بالصندوق', 'شكد بالقاصه', 'رصيد الصندوق', 'فلوس الصندوق',
      'cash', 'cash flow', 'cashbox', 'till', 'drawer',
    ], boost: 0.45),
    // ───────────── المرتجعات والضمان ─────────────
    ReportIntent('returns', [
      'مرتجع', 'مرتجعات', 'المرتجعات', 'المرتجع', 'راجع', 'الراجع', 'رواجع', 'ارجاع', 'استرجاع', 'استرداد', 'ردت', 'رجعت',
      'رجعوا', 'رجع', 'ارجعوا', 'منو رجع', 'شكد رجع', 'شنو رجع', 'مرتجعات الفواتير', 'مرتجعات المبيعات', 'مرتجع مبيعات',
      'سند مرتجع', 'ردود', 'بضاعه راجعه', 'returns', 'return', 'refund', 'refunds', 'credit note',
    ], boost: 0.3),
    ReportIntent('warranty_returns', [
      'ضمان', 'الضمان', 'ضمانات', 'كفاله', 'الكفاله', 'كفالات', 'مرتجعات الضمان', 'مرتجع ضمان', 'ارجاع بسبب الضمان',
      'رجعت بالضمان', 'رجعت بالكفاله', 'عطل', 'عطلان', 'عاطل', 'معطوب', 'معطوبه', 'تالف', 'تالفه', 'خربان', 'خربانه',
      'خراب', 'خربت', 'عيب', 'معيب', 'عيوب', 'مضروب', 'ما يشتغل', 'ميشتغل', 'بايظ', 'خسران', 'استبدال', 'تبديل', 'بدلت',
      'warranty', 'guarantee', 'defective', 'faulty',
    ], boost: 0.15),
    ReportIntent('warranty_hub', [
      'الضمان والصيانه', 'صيانه', 'الصيانه', 'تصليح', 'تصليحات', 'اصلاح', 'صلحت', 'وصل ضمان', 'وصل صيانه',
      'مطالبات الضمان', 'طلبات الضمان', 'قطع العملاء', 'اجهزه بالصيانه', 'ضمان', 'كفاله', 'repair', 'maintenance',
      'service',
    ]),
    // ───────────── تحليل الفترة ─────────────
    ReportIntent('usd', [
      'دولار', 'الدولار', 'دولارات', 'اثر الدولار', 'سعر الدولار', 'سعر الصرف', 'صرف الدولار', 'العمله', 'عمله',
      'العملات', 'تغير الدولار', 'فرق العمله', 'فرق الصرف', 'فرق الدولار', 'اثر سعر الصرف', 'ارتفاع الدولار',
      'نزول الدولار', 'صعد الدولار', 'نزل الدولار', 'البورصه', 'الصرافه', 'اخضر', 'usd', 'dollar', 'exchange rate', 'fx',
    ], boost: 0.3),
    ReportIntent('compare', [
      'مقارنه', 'قارن', 'المقارنه', 'مقارنات', 'مقابل', 'الفرق', 'نمو', 'النمو', 'تراجع', 'زياده', 'نقصان', 'افضل من',
      'اسوا من', 'اكثر من', 'اقل من', 'تحسن', 'تحسنت', 'نزلت', 'زادت', 'قلت', 'مقارنه بالشهر الماضي',
      'مقارنه بالسنه الماضيه', 'هل زاد', 'هل نقص', 'شلون صار مقارنه', 'vs', 'versus', 'compare', 'comparison', 'growth',
    ], boost: 0.3),
    ReportIntent('trend', [
      'توجهات', 'تحليل التوجهات', 'رسم بياني', 'رسم', 'منحنى', 'مخطط', 'اتجاه', 'الاتجاه', 'اوقات الذروه', 'الذروه',
      'وقت الزحمه', 'الزحمه', 'اكثر ساعه', 'ساعات البيع', 'ساعات', 'ايام الاسبوع', 'اي يوم', 'افضل يوم', 'موسم', 'مواسم',
      'الموسم', 'تطور', 'تطور المبيعات', 'chart', 'graph', 'trend', 'trends', 'peak',
    ]),
    ReportIntent('extras', [
      'ماذا حدث', 'شو صار', 'شصار', 'شنو صار', 'ايش صار', 'ملاحظات الفتره', 'ملخص الفتره', 'المال الفعلي', 'تغير الديون',
      'خلاصه', 'الخلاصه', 'شنو الوضع', 'شلون الوضع', 'insights', 'summary',
    ]),
    ReportIntent('manual', [
      'خارج الفواتير', 'ديون يدويه', 'تسديدات يدويه', 'معاملات يدويه', 'دين يدوي', 'سجل الديون', 'معاملات بدون فاتوره',
      'ديون بدون فاتوره', 'قيود يدويه', 'manual',
    ]),
    ReportIntent('channels', [
      'نوع البيع', 'انواع البيع', 'نقدي', 'نقدا', 'اجل', 'الاجل', 'بالاجل', 'بالدين', 'دين ونقد', 'كاش واجل', 'قنوات البيع',
      'نقد ودين', 'طريقه الدفع', 'طرق الدفع', 'channels', 'payment type',
    ]),
    ReportIntent('top_products', [
      'الاكثر مبيعا', 'اكثر المواد مبيعا', 'اكثر ماده', 'افضل المواد', 'اعلى المواد', 'المواد الرائجه', 'اكثر صنف',
      'شنو اكثر شي ينباع', 'شنو ينباع', 'الاكثر طلبا', 'الطلب العالي', 'البضاعه الماشيه', 'الماشي', 'best seller',
      'top products', 'best selling',
    ]),
    ReportIntent('top_customers', [
      'افضل العملاء', 'اكبر العملاء', 'اكبر الزبائن', 'افضل الزبائن', 'اهم العملاء', 'اكثر عميل', 'اكثر زبون',
      'الزبون الذهبي', 'كبار العملاء', 'top customers', 'best customers',
    ]),
    ReportIntent('day_close', [
      'اقفال اليوم', 'اقفال', 'الاقفال', 'تسكير', 'تسكير الصندوق', 'سكرت الصندوق', 'غلق الصندوق', 'عد الدرج',
      'عد الفلوس', 'مطابقه الدرج', 'مطابقه الصندوق', 'نهايه اليوم', 'اخر اليوم', 'جرد الصندوق', 'جرد الدرج', 'عجز ولا زياده',
      'day close', 'closing', 'z report',
    ]),
    ReportIntent('day_close_quick', [
      'اقفال سريع', 'اقفال في دقيقه', 'اقفال بدقيقه', 'اقفال اليوم في دقيقه', 'اقفال مختصر', 'quick close',
    ]),
    // ───────────── الجهات ─────────────
    ReportIntent('products', [
      'تقارير البضاعه', 'تقرير البضاعه', 'بضاعه', 'البضاعه', 'بضايع', 'مواد', 'ماده', 'المواد', 'اصناف', 'صنف', 'الاصناف',
      'سلع', 'سلعه', 'منتجات', 'منتج', 'المنتجات', 'اغراض', 'الاقسام', 'قسم', 'فئه', 'فئات', 'ربح كل ماده',
      'ماده ماده', 'products', 'items', 'goods', 'categories',
    ], boost: 0.1),
    ReportIntent('people', [
      'تقارير الاشخاص', 'عملاء', 'عميل', 'العملاء', 'زبائن', 'زبون', 'الزبائن', 'زباين', 'اشخاص', 'الناس', 'مشترين',
      'مشتري', 'الجماعه', 'كل زبون', 'customers', 'clients', 'people',
    ]),
    ReportIntent('customer_statement', [
      'كشف حساب', 'كشف حساب عميل', 'كشف عميل', 'كشف الزبون', 'كشف', 'كشوفات', 'حساب العميل', 'حساب زبون',
      'statement', 'account statement',
    ]),
    ReportIntent('customers_directory', [
      'دليل العملاء', 'بطاقات العملاء', 'بطاقه عميل', 'مجموعات العملاء', 'مناطق العملاء', 'عناوين العملاء',
      'ارقام العملاء', 'customer directory',
    ]),
    ReportIntent('employees', [
      'موظفين', 'موظف', 'الموظفين', 'مبيعات الموظفين', 'محاسب', 'محاسبين', 'المحاسب', 'كاشير', 'الكاشير', 'من باع',
      'منو باع', 'مين باع', 'العمال', 'عامل', 'عمال', 'الصناع', 'صانع', 'البياع', 'بياع', 'اداء الموظفين', 'staff',
      'employees', 'employee', 'cashier',
    ], boost: 0.2),
    ReportIntent('hr', [
      'الموارد البشريه', 'حضور', 'الحضور', 'غياب', 'الغياب', 'دوام', 'الدوام', 'سلف', 'سلفه', 'السلف', 'رواتب الموظفين',
      'راتب', 'اجازه', 'اجازات', 'بصمه', 'hr', 'attendance', 'payroll',
    ]),
    ReportIntent('founders', [
      'مؤسس', 'مؤسسين', 'المؤسسون', 'المؤسسين', 'فني', 'فنيين', 'الفنيين', 'اسطه', 'اسطوات', 'معلم', 'نقاط المؤسسين',
      'نقاط الفنيين', 'جوائز', 'الجوائز', 'founders', 'technicians', 'installers',
    ]),
    ReportIntent('sellers', [
      'مندوب', 'مندوبين', 'المندوبين', 'عموله', 'عمولات', 'العمولات', 'وكيل', 'وكلاء', 'sales rep', 'commission',
    ]),
    ReportIntent('suppliers', [
      'موردين', 'مورد', 'الموردين', 'الموردون', 'شركات', 'تجار الجمله', 'مشتريات', 'المشتريات', 'شراء', 'اشتريت',
      'فواتير الشراء', 'فاتوره شراء', 'شكد اشتريت', 'suppliers', 'vendors', 'purchases',
    ]),
    ReportIntent('purchase_returns', [
      'مرتجع مشتريات', 'مرتجعات المشتريات', 'ارجاع للمورد', 'رجعت للمورد', 'مرتجع شراء', 'purchase returns',
    ]),
    ReportIntent('supplier_aging', [
      'ديون الموردين', 'ديوني', 'دين الموردين', 'الموردين المتاخرين', 'مستحقات الموردين',
      'payables', 'supplier debts',
    ]),
    // ───────────── المستندات ─────────────
    ReportIntent('sales_returns_list', [
      'سجل المرتجعات', 'سجل المرتجع', 'الغاء مرتجع', 'طباعه مرتجع', 'اعاده طباعه مرتجع', 'مستندات المرتجع',
      'returns log',
    ]),
    ReportIntent('quotes', [
      'عرض سعر', 'عروض الاسعار', 'عروض اسعار', 'عرض اسعار', 'تسعيره', 'تسعير', 'كوتيشن', 'quotation', 'quote',
    ]),
    ReportIntent('orders', [
      'طلبات المبيعات', 'طلبيه', 'طلبيات', 'طلبات', 'حجز', 'حجوزات', 'تسليم جزئي', 'orders', 'order', 'booking',
    ]),
    ReportIntent('open_invoices', [
      'فواتير غير مسدده', 'الفواتير غير المسدده', 'فواتير مفتوحه', 'فواتير اجله', 'الفواتير الاجله', 'الباقي بالفواتير',
      'فواتير عليها باقي', 'ما تسددت', 'غير مدفوعه', 'unpaid invoices', 'open invoices',
    ]),
    ReportIntent('due_items', [
      'استحقاقات', 'الاستحقاقات', 'شيك', 'شيكات', 'صكوك', 'كمبياله', 'كمبيالات', 'اقساط', 'قسط', 'الاقساط',
      'مواعيد الدفع', 'cheques', 'checks', 'installments',
    ]),
    ReportIntent('over_limit', [
      'المتجاوزون للسقف', 'تجاوز السقف', 'سقف الدين', 'حد الدين', 'الحد الائتماني', 'فوق الحد', 'credit limit',
    ]),
    ReportIntent('delivery', [
      'توصيل', 'التوصيل', 'شركات التوصيل', 'دليفري', 'مندوب توصيل', 'طلبات التوصيل', 'شحن', 'delivery', 'shipping',
    ]),
    ReportIntent('loyalty', [
      'ولاء', 'برنامج الولاء', 'نقاط الزبائن', 'نقاط العملاء', 'مكافات', 'اختام', 'بطاقه ولاء', 'loyalty', 'rewards',
    ]),
    ReportIntent('price_checker', [
      'قارئ الاسعار', 'قارئ السعر', 'فحص السعر', 'شكد سعر', 'كم سعر', 'سعر الماده', 'شاشه الاسعار', 'price checker',
    ]),
    // ───────────── لوحات ورقابة ─────────────
    ReportIntent('radar', [
      'رادار', 'رادار التاجر', 'تنبيهات', 'التنبيهات', 'تحذيرات', 'بيع تحت الكلفه', 'تحت الكلفه', 'بيع بخساره',
      'ماذا اشتري', 'شنو اشتري', 'شو اشتري', 'الشراء الذكي', 'اقتراح الشراء', 'المحقق المالي', 'هبوط الربح', 'خصومات',
      'الخصومات', 'السيوله القادمه', 'منو اتابع', 'من اتابع', 'radar', 'alerts', 'insight',
    ]),
    ReportIntent('control', [
      'رقابه', 'الرقابه', 'عجز', 'عجز الدرج', 'العجز', 'نقطه التعادل', 'التعادل', 'تلاعب', 'سرقه', 'اختلاس',
      'فواتير انقصت', 'فواتير معدله', 'تعديلات مشبوهه', 'ربحيه الفروع', 'الفروع', 'control', 'audit', 'fraud',
      'break even',
    ]),
    ReportIntent('dashboard', [
      'لوحه المؤشرات', 'مؤشرات', 'المؤشرات', 'نظره عامه', 'لوحه', 'داشبورد', 'ملخص عام', 'الصوره العامه', 'شلون المحل',
      'وضع المحل', 'dashboard', 'kpi', 'overview',
    ]),
    // ───────────── المخزون ─────────────
    ReportIntent('inventory', [
      'مخزون', 'المخزون', 'جرد', 'الجرد', 'قيمه المخزون', 'قيمه البضاعه', 'كم تساوي البضاعه', 'شكد تسوى البضاعه',
      'شكد قيمه البضاعه', 'راس مال البضاعه', 'تقييم المخزون', 'مخزن', 'المخزن', 'مخازن', 'ستوك', 'الموجود', 'البضاعه الموجوده',
      'inventory', 'stock', 'stock value', 'warehouse',
    ], boost: 0.1),
    ReportIntent('movements', [
      'حركه ماده', 'حركه المواد', 'حركه المخزون', 'دخل وطلع', 'وارد وصادر المخزن', 'كارت الصنف', 'كارت الماده',
      'بطاقه الماده', 'تتبع ماده', 'وين راحت الماده', 'stock movements', 'item card',
    ]),
    ReportIntent('stock_at', [
      'المخزون بتاريخ', 'الجرد بتاريخ', 'رصيد بتاريخ', 'المخزون سابقا', 'المخزون في تاريخ', 'كم كان عندي',
      'stock at date',
    ]),
    ReportIntent('stagnant', [
      'راكده', 'الراكده', 'المواد الراكده', 'بضاعه راكده', 'ركود', 'راكد', 'لا تباع', 'ما تنباع', 'ما ينباع', 'واكفه',
      'بضاعه واكفه', 'نايمه', 'بضاعه نايمه', 'بطيئه الحركه', 'بطيئه البيع', 'ميته', 'dead stock', 'slow moving',
    ]),
    ReportIntent('limits', [
      'نواقص', 'النواقص', 'ناقص', 'نفدت', 'نفذت', 'خلصت', 'خلصان', 'مخلص', 'حد الطلب', 'نفاد', 'نقص المخزون', 'ماذا ينقص',
      'شنو ناقص', 'شو ناقص', 'لازم اطلب', 'اطلب شنو', 'صفر', 'out of stock', 'low stock', 'reorder', 'shortage',
    ]),
    ReportIntent('expiring', [
      'صلاحيه', 'الصلاحيه', 'انتهاء الصلاحيه', 'منتهي', 'منتهيه', 'منتهيه الصلاحيه', 'اكسباير', 'تاريخ الانتهاء',
      'قربت تنتهي', 'خربانه بالتاريخ', 'expiry', 'expired', 'expiring',
    ]),
    // ───────────── الديون ─────────────
    ReportIntent('debts', [
      'ديون', 'الديون', 'دين', 'الدين', 'ارصده الديون', 'المديونين', 'المدينين', 'كم لي', 'شكد الي', 'شكد لي',
      'شكد بالدفتر', 'الدفتر', 'دفتر الديون', 'ذمم', 'الذمم', 'ذمم العملاء', 'الطلب', 'طلباتي بالسوق', 'فلوسي بالسوق',
      'باقي الحساب', 'الحسابات المفتوحه', 'debts', 'debt', 'receivables', 'balances',
    ], boost: 0.1),
    ReportIntent('aging', [
      'اعمار الديون', 'متاخرين', 'المتاخرين', 'لم يسدد', 'ما سدد', 'ما سددوا', 'ديون قديمه', 'ديون ميته',
      'تاخر', 'متاخر', 'ديون معلقه', 'منذ متى', 'aging', 'overdue',
    ]),
    ReportIntent('collection', [
      'نسب التحصيل', 'نسبه التحصيل', 'التحصيل', 'معدل التحصيل', 'كفاءه التحصيل', 'collection rate',
    ]),
  ];

  static final Map<String, List<List<String>>> _kwWords = {
    for (final i in intents) i.id: [for (final k in i.keywords) ArabicNorm.words(k)],
  };

  /// كل كلمة تظهر في أي كلمة مفتاحية (لمعرفة كلمات «المعنى» من كلمات «الاسم»).
  static final Set<String> _vocab = {
    for (final i in intents)
      for (final k in i.keywords)
        for (final w in ArabicNorm.words(k)) ...[w, ArabicNorm.stem(w)],
  };

  /// أسماء شائعة تشبه كلمات التقارير («مالك» من «المالك»، «عمر» من «أعمار») — تبقى أسماءً.
  static const _commonNames = {'علي', 'عمر', 'مالك', 'نور', 'امين', 'صالح', 'كريم', 'سعيد', 'ناصر', 'منصور', 'حامد', 'شاكر'};

  /// هل الكلمة من كلمات التقارير (مثل «ربح» في «ربح أحمد»)؟
  static bool isConcept(String w) =>
      !_commonNames.contains(ArabicNorm.bare(w)) && (_vocab.contains(w) || _vocab.contains(ArabicNorm.stem(w)));

  /// ترتيب التقارير حسب قربها من الكلمات.
  static List<IntentHit> match(ReportQuery q, {int limit = 8}) {
    final words = q.words;
    if (words.isEmpty) return const [];
    final norm = ' ${words.join(' ')} ';
    final hits = <IntentHit>[];
    for (final intent in intents) {
      final phrases = _kwWords[intent.id]!;
      var total = 0.0;
      var matched = 0;
      for (final w in words) {
        var best = 0.0;
        for (final p in phrases) {
          for (final k in p) {
            final m = ArabicNorm.wordMatch(w, k);
            if (m > best) best = m;
          }
        }
        if (best > 0) matched++;
        total += best;
      }
      if (matched == 0) continue;
      // جملة كاملة من كلماته داخل البحث (مثل «سند قبض») ← ترجيح قوي
      var phraseBonus = 0.0;
      for (final p in phrases) {
        if (p.length >= 2 && norm.contains(' ${p.join(' ')} ')) phraseBonus = phraseBonus < 3.5 ? 3.5 : phraseBonus;
      }
      final coverage = matched / words.length;
      final score = (total / words.length) * (0.6 + 0.4 * coverage) + phraseBonus + intent.boost;
      if (score >= 1.2) hits.add(IntentHit(intent, score));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// مطابقة اسم (مادة/عميل/موظف) بكلمات البحث: 0 = لا تطابق.
  /// كل كلمة من البحث يجب أن تطابق كلمة من الاسم (بدايةً أو جذعاً أو احتواءً).
  static double nameScore(List<String> queryWords, String name) => normalizedNameScore(queryWords, ArabicNorm.normalize(name));

  /// مثل nameScore لكن الاسم مُوحَّد مسبقاً (للقوائم الكبيرة: يُوحَّد مرة واحدة عند التحميل).
  static double normalizedNameScore(List<String> queryWords, String n) {
    if (queryWords.isEmpty || n.isEmpty) return 0;
    final parts = n.split(' ');
    var total = 0.0;
    for (final q in queryWords) {
      var best = 0.0;
      for (final p in parts) {
        double m;
        if (p == q) {
          m = 3;
        } else if (p.startsWith(q) || ArabicNorm.stem(p) == ArabicNorm.stem(q)) {
          m = 2.4;
        } else if (q.length >= 3 && p.contains(q)) {
          m = 1.6;
        } else if (q.length >= 4 && p.length >= 4 && ArabicNorm.distance(q, p) <= 1) {
          m = 1.2;
        } else {
          m = 0;
        }
        if (m > best) best = m;
      }
      if (best == 0) return 0; // كلمة لا تطابق ← ليس هو
      total += best;
    }
    // الاسم الأقصر أقرب (أحمد قبل أحمد علي حسن)
    return total / queryWords.length + (n == queryWords.join(' ') ? 2 : 0) - parts.length * 0.05;
  }
}
