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

  static const stopWords = {
    'تقرير', 'تقارير', 'التقرير', 'التقارير', 'عن', 'في', 'من', 'الى', 'لي', // لا «على»: تصير «علي» بعد التوحيد وهو اسم شائع 'ل', 'و', 'او', 'ثم',
    'كم', 'ما', 'ماذا', 'هو', 'هي', 'هل', 'اريد', 'بدي', 'ابي', 'اعرض', 'اعرضلي', 'عرض', 'اظهر', 'ابحث', 'بحث',
    'شو', 'ايش', 'وين', 'كل', 'جميع', 'مع', 'الي', 'التي', 'الذي', 'هذا', 'هذه', 'هاي', 'هذي', 'ذلك', 'خلال',
    'فتره', 'الفتره', 'سنه', 'السنه', 'عام', 'العام', 'شهر', 'الشهر', 'يوم', 'لسنه', 'بسنه', 'بشهر', 'لشهر',
    'حسب', 'بحسب', 'تبع', 'تبعات', 'خاص', 'خاصه', 'قائمه',
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
    ReportIntent('profit', [
      'ربح', 'ارباح', 'الربح', 'صافي الربح', 'فائده', 'مكسب', 'مكاسب', 'هامش', 'هامش الربح', 'كم ربحت', 'ربحت',
      'الربحيه', 'العائد', 'خساره', 'خسائر',
    ], boost: 0.4),
    ReportIntent('sales', [
      'مبيعات', 'المبيعات', 'بيع', 'بعت', 'كم بعت', 'فواتير', 'فاتوره', 'الغله', 'الوارد', 'الدخل', 'ايراد',
      'ايرادات', 'حركه البيع', 'تقرير يومي', 'تقرير شهري', 'تقرير سنوي', 'يومي', 'شهري', 'سنوي', 'ملخص',
    ], boost: 0.3),
    ReportIntent('income_statement', [
      'قائمه الدخل', 'الارباح والخسائر', 'ارباح وخسائر', 'الربح والخساره', 'صافي الدخل', 'نتيجه النشاط',
    ]),
    ReportIntent('balance_sheet', [
      'الميزانيه', 'الميزانيه العموميه', 'ميزانيه', 'اصول', 'خصوم', 'حقوق الملكيه', 'راس المال', 'المركز المالي',
    ]),
    ReportIntent('trial_balance', [
      'ميزان المراجعه', 'ميزان', 'ارصده الحسابات', 'مدين ودائن', 'مدين', 'دائن', 'الحسابات', 'شجره الحسابات',
    ]),
    ReportIntent('sales_detail', [
      'المبيعات التفصيلي', 'تفصيلي', 'تفاصيل الفواتير', 'كل فاتوره', 'المتبقي', 'المدفوع', 'تصدير الفواتير', 'اكسل',
    ]),
    ReportIntent('expenses', [
      'مصاريف', 'مصروفات', 'مصروف', 'نفقات', 'اين ذهبت الاموال', 'اين راحت الفلوس', 'كهرباء', 'ايجار', 'اجار',
      'رواتب', 'اجور', 'مولده', 'انترنت', 'تحليل المصاريف',
    ], boost: 0.2),
    ReportIntent('vouchers', [
      'سندات', 'سند', 'ملخص السندات', 'السندات المسحوبه', 'كل السندات', 'حركه السندات',
    ], boost: 0.1),
    ReportIntent('vouchers_receipt', [
      'سند قبض', 'سندات قبض', 'سندات القبض', 'قبض', 'مقبوضات', 'المقبوض', 'استلام', 'استلمت',
    ], boost: 0.3),
    ReportIntent('vouchers_payment', [
      'سند صرف', 'سندات صرف', 'سندات الصرف', 'صرف', 'مدفوعات', 'دفعت', 'المدفوع للحسابات',
    ]),
    ReportIntent('vouchers_expense', ['سند مصروف', 'سندات مصروف', 'سندات المصاريف']),
    ReportIntent('vouchers_income', ['سند ايراد', 'سندات ايراد', 'ايرادات اخرى', 'ايراد اخر', 'دخل اخر']),
    ReportIntent('drawings', [
      'مسحوبات', 'مسحوبات المالك', 'سحب المالك', 'سحوبات', 'سحبت', 'سحب', 'سحب شخصي', 'اخذت من الصندوق',
    ], boost: 0.1),
    ReportIntent('receipts_list', [
      'وصل قبض', 'وصولات', 'وصولات القبض', 'وصل', 'تسديد', 'تسديدات', 'دفعات العملاء', 'تحصيل', 'سداد', 'تسديد الديون',
    ]),
    ReportIntent('cash', [
      'حركه الصندوق', 'الصندوق', 'صندوق', 'الصناديق', 'كاش', 'النقد', 'السيوله', 'الخزنه', 'الدرج', 'الوارد والصادر',
    ], boost: 0.3),
    ReportIntent('returns', [
      'مرتجع', 'مرتجعات', 'المرتجعات', 'راجع', 'ارجاع', 'استرجاع', 'ردت', 'رجعت', 'مرتجعات الفواتير',
      'مرتجعات المبيعات', 'سند مرتجع',
    ], boost: 0.3),
    ReportIntent('warranty_returns', [
      'ضمان', 'الضمان', 'كفاله', 'مرتجعات الضمان', 'ارجاع بسبب الضمان', 'عطل', 'معطوب', 'تالف', 'خربان', 'خراب',
      'عيب', 'معيب', 'استبدال', 'تبديل',
    ], boost: 0.15),
    ReportIntent('warranty_hub', [
      'الضمان والصيانه', 'صيانه', 'تصليح', 'اصلاح', 'ضمان', 'وصل ضمان', 'مطالبات الضمان', 'قطع العملاء',
    ]),
    ReportIntent('usd', [
      'دولار', 'الدولار', 'اثر الدولار', 'سعر الدولار', 'سعر الصرف', 'صرف الدولار', 'العمله', 'عمله', 'usd',
      'تغير الدولار', 'فرق العمله', 'اثر سعر الصرف',
    ], boost: 0.3),
    ReportIntent('compare', [
      'مقارنه', 'قارن', 'المقارنه', 'مقابل', 'الفرق', 'نمو', 'تراجع', 'زياده', 'نقصان', 'افضل من', 'اسوا من',
      'مقارنه بالشهر الماضي', 'مقارنه بالسنه الماضيه',
    ], boost: 0.3),
    ReportIntent('trend', [
      'توجهات', 'تحليل التوجهات', 'رسم بياني', 'منحنى', 'اتجاه', 'اوقات الذروه', 'الذروه', 'اكثر ساعه', 'ساعات',
      'ايام الاسبوع', 'موسم', 'مواسم', 'تطور',
    ]),
    ReportIntent('extras', ['ماذا حدث', 'شو صار', 'ملاحظات الفتره', 'ملخص الفتره', 'المال الفعلي', 'تغير الديون']),
    ReportIntent('manual', [
      'خارج الفواتير', 'ديون يدويه', 'تسديدات يدويه', 'معاملات يدويه', 'دين يدوي', 'سجل الديون',
    ]),
    ReportIntent('channels', ['نوع البيع', 'نقدي', 'اجل', 'بالدين', 'كاش واجل', 'قنوات البيع', 'نقد ودين']),
    ReportIntent('top_products', [
      'الاكثر مبيعا', 'اكثر المواد مبيعا', 'افضل المواد', 'اعلى المواد', 'المواد الرائجه', 'اكثر صنف',
    ]),
    ReportIntent('top_customers', ['افضل العملاء', 'اكبر العملاء', 'اكبر الزبائن', 'افضل الزبائن', 'اهم العملاء']),
    ReportIntent('day_close', [
      'اقفال اليوم', 'اقفال', 'تسكير', 'سكر الصندوق', 'عد الدرج', 'مطابقه الدرج', 'نهايه اليوم', 'جرد الصندوق',
    ]),
    ReportIntent('products', [
      'تقارير البضاعه', 'بضاعه', 'مواد', 'ماده', 'اصناف', 'صنف', 'سلع', 'منتجات', 'منتج', 'الاقسام', 'قسم',
    ], boost: 0.1),
    ReportIntent('people', ['تقارير الاشخاص', 'عملاء', 'عميل', 'زبائن', 'زبون', 'اشخاص', 'الناس', 'مشترين']),
    ReportIntent('employees', [
      'موظفين', 'موظف', 'الموظفين', 'مبيعات الموظفين', 'محاسب', 'محاسبين', 'كاشير', 'من باع', 'العمال', 'عامل',
    ], boost: 0.2),
    ReportIntent('hr', ['الموارد البشريه', 'حضور', 'غياب', 'سلف', 'سلفه', 'رواتب الموظفين', 'دوام']),
    ReportIntent('founders', ['مؤسس', 'مؤسسين', 'المؤسسون', 'فني', 'فنيين', 'نقاط', 'جوائز', 'نقاط المؤسسين']),
    ReportIntent('radar', [
      'رادار', 'رادار التاجر', 'تنبيهات', 'بيع تحت الكلفه', 'تحت الكلفه', 'ماذا اشتري', 'الشراء الذكي',
      'المحقق المالي', 'هبوط الربح', 'خصومات',
    ]),
    ReportIntent('control', [
      'رقابه', 'الرقابه', 'عجز', 'عجز الدرج', 'نقطه التعادل', 'تلاعب', 'فواتير انقصت', 'ربحيه الفروع', 'سرقه',
    ]),
    ReportIntent('dashboard', ['لوحه المؤشرات', 'مؤشرات', 'نظره عامه', 'لوحه', 'داشبورد', 'ملخص عام']),
    ReportIntent('inventory', [
      'مخزون', 'المخزون', 'جرد', 'قيمه المخزون', 'كم تساوي البضاعه', 'راس مال البضاعه', 'تقييم المخزون', 'مخزن',
    ], boost: 0.1),
    ReportIntent('stagnant', ['راكده', 'المواد الراكده', 'بضاعه راكده', 'لا تباع', 'ما تنباع', 'بطيئه الحركه']),
    ReportIntent('limits', ['نواقص', 'ناقص', 'نفدت', 'خلصت', 'حد الطلب', 'نفاد', 'نقص المخزون', 'ماذا ينقص']),
    ReportIntent('expiring', ['صلاحيه', 'انتهاء الصلاحيه', 'منتهي', 'منتهيه', 'اكسباير', 'تاريخ الانتهاء']),
    ReportIntent('debts', [
      'ديون', 'الديون', 'دين', 'ارصده الديون', 'المديونين', 'كم لي', 'كم علي', 'ذمم', 'ذمم العملاء', 'الموردين',
    ], boost: 0.1),
    ReportIntent('aging', ['اعمار الديون', 'متاخرين', 'المتاخرين', 'لم يسدد', 'ما سدد', 'ديون قديمه', 'تاخر']),
    ReportIntent('collection', ['نسب التحصيل', 'نسبه التحصيل', 'التحصيل']),
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

  /// هل الكلمة من كلمات التقارير (مثل «ربح» في «ربح أحمد»)؟
  static bool isConcept(String w) => _vocab.contains(w) || _vocab.contains(ArabicNorm.stem(w));

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
