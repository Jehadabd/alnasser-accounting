// test/sync_harness/comprehensive_test.dart
//
// 🧪 الاختبار الشامل (طلب المالك 2026-11-11) — يأخذ مزايا الاختبارين: تعدد الأجهزة
// (multi_device_torture_test) وعمق التعديل (compound_edit_torture_test)، على كود
// التطبيق الحقيقي (InvoiceController، AppProvider، CustomerMoney، المرتجع، المزامنة).
//
//   • 3 أجهزة تعمل معاً بلا انتظار للمزامنة (كالواقع)، ومزامنة في أوقات عشوائية.
//   • 50 عميلاً، لكل عميل 10 فواتير (500 فاتورة)، كل فاتورة تُعدَّل 100 مرة (50,000 تعديل)
//     بترتيب عشوائي بين الفواتير والأجهزة.
//   • كل تعديل يركّب 1 إلى 5 تغييرات من 51 (البنود، المجاميع، الدفع، التاريخ)، ومعها
//     في ثلث التعديلات نقل الفاتورة إلى عميل آخر أو تأكيد صاحبها (7 طرق)، وأحياناً حفظ
//     مرتين، أو تثبيت الفترة حول التاريخين، أو تعليق فاتورة محفوظة [*].
//   • لكل عميل 10 معاملات يدوية موزعة على طول الاختبار (دين يدوي، تسديد يدوي، وصل قبض)،
//     وتعديل معاملات يدوية وتحويل نوعها — من جهازها، ومن جهاز آخر [*]، وداخل فترة مثبّتة [*].
//     (حذف معاملة يدوية ليس في التطبيق أصلاً: لا زر له في شاشة العميل.)
//   • تغيير أسماء العملاء من الجهاز المنشئ (ومن غيره [*])، مرتجعات (على الحساب، نقدية،
//     مختلطة، أكثر من المتبقي [*]) وإلغاؤها، فواتير مؤقتة (تعليق ← تعديل ← استكمال ← حذف،
//     والحذف داخل فترة مثبّتة [*])، تعديل/حذف فاتورة الجهاز الآخر [*]، إعادة تشغيل مفاجئة،
//     وانقطاع الإنترنت.
//
// الحكم على كل حفظ بالفلس: سبب رفض من حالة الفاتورة (النموذج المستقل)، وقاعدة الرصيد
// السالب بالرصيد الذي يراه الجهاز نفسه لحظة الحفظ (كما يفعل التطبيق). بعد كل عملية:
// الفاتورة على جهازها = الحقيقة (الإجمالي، المسدد، الخصم، التحميل، التاريخ، النوع،
// العميل، اسمه، كمية كل صنف، دينها في السجل)، ودين العميل المخزّن = مجموع معاملاته على
// الجهاز، ويساوي الحقيقة على الجهاز الذي يعرف كل ما جرى له. بعد كل مزامنة: كل عميل على
// كل جهاز (الدين، المجموع، الاسم)، ومئة فاتورة بالتناوب على كل جهاز، والمخزون. وفي
// النهاية: كل فاتورة على كل جهاز، والدفتر المحاسبي والفحص العميق.
//
// ⏱️ يقيس أين يذهب الوقت (الحفظ، الفحص، انتظار المزامنة…) ويطبعه في الخلاصة.
//
//   سريع (~10 دقائق):  claude_test_comprehensive.bat
//   كامل (ساعات):      claude_test_comprehensive.bat full [seed]
//   أرقام أخرى: --dart-define=DEVICES=3 --dart-define=CUSTOMERS=50 --dart-define=INVOICES_PER_CUSTOMER=10
//               --dart-define=EDITS=100 --dart-define=MANUAL_PER_CUSTOMER=10 --dart-define=SEED=7
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _quick = bool.fromEnvironment('QUICK', defaultValue: false);
const _devices = int.fromEnvironment('DEVICES', defaultValue: 3);
const _customers = int.fromEnvironment('CUSTOMERS', defaultValue: _quick ? 8 : 50);
const _perCust = int.fromEnvironment('INVOICES_PER_CUSTOMER', defaultValue: _quick ? 3 : 10);
const _edits = int.fromEnvironment('EDITS', defaultValue: _quick ? 12 : 100);
const _manualPerCust = int.fromEnvironment('MANUAL_PER_CUSTOMER', defaultValue: _quick ? 3 : 10);
const _maxNew = int.fromEnvironment('NEW_CUSTOMERS', defaultValue: _quick ? 4 : 40);
const _seedArg = int.fromEnvironment('SEED', defaultValue: 0); // 0 = قرعة جديدة كل تشغيل
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 15);

const _progressPath = 'test_results/comprehensive/progress.txt';
const _summaryPath = 'test_results/comprehensive/summary.txt';

String _dur(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}س ${m}د' : '${m}د';
}

/// للتوزيع: ثوانٍ في التشغيل القصير
String _durFine(int seconds) {
  if (seconds < 60) return '$secondsث';
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  return h > 0 ? '$hس $mد' : '$mد $sث';
}

/// شريط تقدّم نصي: [██████░░░░░░░░░░░░░░]
String _bar(double pct) {
  final n = (pct / 5).floor().clamp(0, 20);
  return '[${'█' * n}${'░' * (20 - n)}]';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// أنواع معاملات لا تُعدّ من دين الفاتورة (كما في InvoiceDebtReconciler)
const _nonContribution = {'manual_payment', 'return_payment', 'correction', 'opening_balance'};

/// تغييرات تُركَّب 1 إلى 5 منها في حفظ واحد. [*] = يجب رفض الحفظ إن بقي أثرها.
const _mutations = <String>[
  // البنود (22)
  'أصناف جديدة كلياً', 'إضافة سطر', 'حذف سطر', 'تغيير كمية سطر', 'تغيير سعر سطر',
  'تحويل سطر قطعة↔كرتون', 'كمية كسرية', 'سطر هدية', 'خصم سطر بنسبة', 'خصم سطر بمبلغ',
  'الصنف نفسه في سطرين', 'سطر بلا كمية [*]', 'بند يدوي فقط بلا أصناف',
  'استبدال صنف بآخر', 'عكس ترتيب الأسطر', 'كمية كبيرة جداً', 'كمية صغيرة جداً',
  'سعر بكسر فلس', 'كل الأسطر هدايا مع بند يدوي', 'فاتورة 40 سطراً', 'حذف كل الأسطر إلا واحداً',
  'إلغاء خصومات الأسطر',
  // المجاميع (13)
  'خصم على الفاتورة', 'خصم ≥ الإجمالي [*]', 'خصم سالب [*]', 'خصم = الإجمالي − فلس', 'إلغاء الخصم',
  'أجور تحميل', 'أجور تحميل بكسور', 'أجور تحميل سالبة [*]', 'إلغاء أجور التحميل',
  'خصم وتحميل معاً', 'كسور الدينار', 'فاتورة ضخمة', 'فاتورة صغيرة جداً',
  // الدفع (11)
  'إلى نقد', 'إلى دين', 'تسديد جزئي', 'تسديد كامل', 'تسديد إلا فلس', 'إلغاء التسديد',
  'مسدد > الإجمالي [*]', 'مسدد يزيد فلسين [*]', 'مسدد سالب [*]', 'نقد بمسدد ناقص [*]',
  'تصغير تحت المسدد [*]',
  // التاريخ (5)
  'تاريخ سابق', 'تاريخ اليوم', 'آخر يوم في الشهر السابق', 'أول يوم في الشهر', '29 شباط',
];

const _moves = <String>[
  'تغيير العميل', 'تغيير العميل', 'تغيير العميل', 'تغيير العميل',
  'اسم عميل آخر بمسافات', 'اسم عميل آخر بمسافات',
  'اسم العميل بمسافات زائدة', 'اسم العميل بلا مسافات',
  'العودة إلى العميل الأول', 'اسم فارغ [*]',
];
const _newName = 'اسم عميل جديد';
const _newPrefix = 'عميل شامل جديد';
const _phone = 'هاتف مكتوب على الفاتورة';

const _modifiers = <String>[
  'حفظ بلا تغيير', 'حفظ مرتين متتاليتين', 'تثبيت الفترة حول التاريخين',
  'تعديل داخل فترة مثبّتة [*]', 'تعليق فاتورة محفوظة [*]',
];

class _Inv {
  _Inv(this.dev, this.cust, this.date) : firstCust = cust;
  final String dev;
  String cust;
  String firstCust;
  DateTime date;
  List<Map<String, Object?>> specs = [];
  double extra = 0;
  double discount = 0;
  double fee = 0;
  String ptype = 'دين';
  double paid = 0;
  bool held = false;
  bool deleted = false;
  bool temp = false;
  String? nameField;
  String? phoneField;
  bool incomplete = false;

  double get itemsTotal =>
      specs.fold(0.0, (s, x) => s + ((x['qty'] as double) * _applied(x) * 100).round() / 100) + extra;
  double get finalTotal => itemsTotal + fee - discount;

  _Inv copy() => _Inv(dev, cust, date)
    ..firstCust = firstCust
    ..specs = [for (final s in specs) Map<String, Object?>.from(s)]
    ..extra = extra
    ..discount = discount
    ..fee = fee
    ..ptype = ptype
    ..paid = paid
    ..held = held
    ..deleted = deleted
    ..temp = temp;
}

class _Ret {
  _Ret(this.id, this.inv, this.dev, this.cust, this.credit, this.qty);
  final int id;
  final String inv;
  final String dev;
  final String cust;
  final double credit;
  final double qty;
  bool voided = false;
}

double _applied(Map<String, Object?> s) {
  final p = s['price'] as double;
  if (s['gift'] == true) return 0.0;
  final pct = s['discPct'] as double?;
  if (pct != null) return p * (1 - pct / 100);
  final amt = s['discAmt'] as double?;
  if (amt != null) return p - amt;
  return p;
}

void main() {
  final seed = _seedArg != 0 ? _seedArg : DateTime.now().microsecondsSinceEpoch % 1000000 + 1;
  const totalEdits = _customers * _perCust * _edits;
  test(
      'الاختبار الشامل: $_devices أجهزة × $_customers عميلاً × $_perCust فواتير × $_edits تعديل '
      '($totalEdits تعديل) seed=$seed', () async {
    print('🎲 القرعة: seed=$seed — لإعادة هذا التشغيل بالضبط: --dart-define=SEED=$seed');
    final h = Harness(seed: seed);
    final rnd = Random(seed * 7919 + 11);
    final problems = <String>[];
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    final combos = <String>{};
    var failed = true;
    var done = 0; // تعديلات الفواتير الأساسية المنجزة
    var ops = 0; // كل العمليات (تعديلات + أفعال)
    final sw = Stopwatch()..start();
    final loopWatch = Stopwatch();
    final devs = [for (var i = 1; i <= _devices; i++) 'D$i'];

    // ⏱️ أين يذهب الوقت — حصري: الوقت داخل قياس متداخل لا يُحسب مرتين
    final timing = <String, int>{};
    final timerStack = <Stopwatch>[];
    Future<T> timed<T>(String k, Future<T> Function() f) async {
      if (timerStack.isNotEmpty) timerStack.last.stop();
      final s = Stopwatch()..start();
      timerStack.add(s);
      try {
        return await f();
      } finally {
        s.stop();
        timerStack.removeLast();
        timing[k] = (timing[k] ?? 0) + s.elapsedMicroseconds;
        if (timerStack.isNotEmpty) timerStack.last.start();
      }
    }

    String timingReport() {
      final all = sw.elapsedMicroseconds;
      if (all == 0) return '';
      final measured = timing.values.fold(0, (a, b) => a + b);
      final rows = {...timing, 'غير ذلك (منطق الاختبار، التجهيز)': max(0, all - measured)};
      final keys = rows.keys.toList()..sort((a, b) => rows[b]!.compareTo(rows[a]!));
      return [
        for (final k in keys)
          '  $k: ${_durFine(rows[k]! ~/ 1000000)} (${(rows[k]! * 100 / all).toStringAsFixed(1)}%)'
      ].join('\n');
    }

    double r2(double v) => (v * 100).roundToDouble() / 100;
    void near(String what, Object? got, double want) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() >= 0.005) problems.add('$what = $g والمتوقع ${r2(want)}');
    }

    bool stop() => problems.length >= _maxProblems;

    var reported = 0;
    void flushProblems() {
      for (; reported < problems.length; reported++) {
        print('   ⚠️ مشكلة ${reported + 1}: ${problems[reported]}');
      }
    }

    void live(String phase) {
      flushProblems();
      final p = (done * 100 / totalEdits).clamp(0, 100).toDouble();
      final s = loopWatch.elapsed.inSeconds;
      final eta = done > 0 ? (s * (totalEdits - done) / done).round() : null;
      final line = '${_bar(p)} ${p.toStringAsFixed(1)}% — $done/$totalEdits تعديل — مضى ${_dur(sw.elapsed.inSeconds)}'
          '${eta == null ? '' : ' — المتبقي ≈ ${_dur(eta)}'} — مشاكل=${problems.length} — $phase';
      try {
        File(_progressPath)
          ..createSync(recursive: true)
          ..writeAsStringSync(line);
      } catch (_) {}
    }

    try {
      live('تشغيل $_devices أجهزة…');
      await h.start(_devices);
      live('إنشاء العملاء والأصناف…');

      // ── من يعرف ماذا حتى المزامنة التالية (كما في اختبار تعدد الأجهزة) ──
      final dirty = <String, Set<String>>{};
      void touch(String dev, String cust) => dirty.putIfAbsent(cust, () => <String>{}).add(dev);
      bool knowsAll(String dev, String cust) => (dirty[cust] ?? const <String>{}).every((d) => d == dev);
      final homeOnly = <String, String>{}; // عميل أُنشئ على جهاز ولم يُزامَن
      bool known(String dev, String c) => homeOnly[c] == null || homeOnly[c] == dev;
      final names = <String, String>{};
      final pendingRename = <String, (String, String)>{}; // عميل ← (الجهاز، الاسم القديم)
      String nameOn(String dev, String c) {
        final p = pendingRename[c];
        return (p != null && p.$1 != dev) ? p.$2 : names[c]!;
      }

      /// اسم يمكن كتابته على [dev] بلا لبس (لا تغيير اسم من جهاز آخر في الطريق)
      bool nameSettled(String dev, String c) {
        final p = pendingRename[c];
        return p == null || p.$1 == dev;
      }

      final custs = <String>[];
      List<String> knownCusts(String dev) => custs.where((c) => known(dev, c)).toList();
      for (var k = 0; k < _customers; k++) {
        final name = 'زبون شامل ${k + 1}';
        final dev = devs[rnd.nextInt(devs.length)];
        final c = await h.addCustomer(dev, name, phone: k.isEven ? '07702${345600 + k}' : null);
        if (c != null) {
          custs.add(c);
          names[c] = name;
        }
      }
      const catalog = [('برغي شامل', 250.0, 12), ('أنبوب شامل', 1750.5, null), ('صمام شامل', 4000.0, 6)];
      final prods = <(String, double, int?)>[];
      final prodByName = <String, String>{};
      for (final (name, price, carton) in catalog) {
        final u = await h.addProduct('D1', name, 100000000, carton: carton);
        if (u != null) {
          prods.add((u, price, carton));
          prodByName[name] = u;
        }
      }
      final firstErrs = await h.settle();
      expect(firstErrs, isEmpty, reason: firstErrs.join('\n'));
      expect(custs.length, _customers);
      expect(prods.length, 3);
      final base = [...custs];
      final pipe = prods.firstWhere((p) => p.$3 == null).$1;

      final state = <String, _Inv>{};
      final returns = <_Ret>[];
      final offline = <String>{};
      final synced = <String>{}; // فواتير وصلت كل الأجهزة (موجودة عند آخر مزامنة)
      final manual = <String>[]; // معاملات يدوية (دين، تسديد، وصل)
      final syncedTx = <String>{}; // معاملات يدوية وصلت كل الأجهزة (عند آخر مزامنة)
      var newCustomers = 0;
      var renames = 0;
      var temps = 0;

      // ─────────────────────────── أدوات البنود ───────────────────────────

      Map<String, Object?> randomLine({bool allowSpecial = true}) {
        final (u, price, carton) = prods[rnd.nextInt(prods.length)];
        final large = carton != null && rnd.nextDouble() < 0.35;
        final m = <String, Object?>{
          'prod': u,
          'qty': (1 + rnd.nextInt(5)).toDouble(),
          'large': large,
          'price': large ? price * carton : price,
        };
        if (allowSpecial) {
          final x = rnd.nextDouble();
          if (x < 0.06) {
            m['gift'] = true;
          } else if (x < 0.12) {
            m['discPct'] = [10.0, 20.0, 50.0][rnd.nextInt(3)];
          } else if (x < 0.18) {
            m['discAmt'] = [50.0, 100.0][rnd.nextInt(2)];
          }
        }
        return m;
      }

      Map<String, Object?> pieceOf((String, double, int?) p, double qty) =>
          <String, Object?>{'prod': p.$1, 'qty': qty, 'large': false, 'price': p.$2};

      List<Map<String, Object?>> randomSpecs() => [for (var k = rnd.nextInt(4); k > 0; k--) randomLine()];

      double randomExtra({bool positive = false}) {
        const extras = [0.0, 500.0, 1250.25, 10000.0, 75000.5, 333.33, 250000.0, 3.07];
        final v = extras[rnd.nextInt(extras.length)];
        return (positive && v == 0) ? 1500.0 : v;
      }

      bool hasMoney(_Inv x) => x.itemsTotal > 0.009;

      Map<String, double> baseItems(List<Map<String, Object?>> specs) {
        final out = <String, double>{};
        for (final s in specs) {
          final carton = h.truth.products[s['prod']]!.carton ?? 1;
          final q = (s['qty'] as double) * ((s['large'] == true) ? carton.toDouble() : 1.0);
          out[s['prod'] as String] = (out[s['prod'] as String] ?? 0) + q;
        }
        return out;
      }

      String pname(String? p) => h.truth.products[p]?.name ?? '$p';
      String cname(String? c) => names[c] ?? '$c';

      // ─────────────────────────── النموذج ───────────────────────────

      String? invalidReason(_Inv x, {bool foreign = false, bool locked = false}) {
        if (foreign) return 'فاتورة جهاز آخر';
        if (locked) return 'فترة مثبّتة';
        if (x.nameField != null && x.nameField!.trim().isEmpty) return 'اسم فارغ';
        if (x.incomplete) return 'سطر بلا كمية';
        if (x.discount < 0) return 'خصم سالب';
        if (x.fee < 0) return 'تحميل سالب';
        if (x.paid < 0) return 'مسدد سالب';
        if (x.discount >= x.itemsTotal) return 'خصم ≥ الإجمالي';
        if (x.paid > x.finalTotal + 0.01) return 'مسدد > الإجمالي';
        if (x.ptype == 'نقد' && (x.paid - x.finalTotal).abs() > 0.01) return 'نقد بمسدد ناقص';
        return null;
      }

      Future<Map<String, Object?>> custBalance(String dev, String cust) async =>
          ((await h.d(dev).call('custBalance', {'cust': cust}) as Map?) ?? const {}).cast<String, Object?>();

      Future<double?> localDebt(String dev, String cust) async =>
          ((await timed('قراءة الرصيد قبل الحفظ', () => custBalance(dev, cust)))['debt'] as num?)?.toDouble();

      /// أثر الحفظ على رصيد العميل القديم (InvoiceController.validateDebtChange…)
      double debtDelta(String? inv, _Inv x) {
        final t = inv == null ? null : h.truth.invoices[inv];
        if (t == null) return 0;
        final oldC = t.contribution;
        final newC = x.ptype == 'دين' ? max(0.0, x.finalTotal - x.paid) : 0.0;
        final moves = t.cust != x.cust || (x.nameField?.startsWith(_newPrefix) ?? false);
        return (x.ptype == 'نقد' || moves) ? -oldC : newC - oldC;
      }

      /// قاعدة الرصيد السالب بالرصيد الذي يراه [on] الآن: yes / no / gray (على حد الفلس)
      String verdict(double delta, double? local) {
        if (delta > -0.005 || local == null) return 'no';
        final after = local + delta;
        if (after > -0.005) return 'no';
        if (delta < -0.02 && after < -0.02) return 'yes';
        return 'gray';
      }

      /// دين العميل على [dev]: المخزّن = مجموع معاملاته دائماً؛ ويساوي الحقيقة إن كان
      /// [dev] يعرف كل ما جرى له منذ آخر مزامنة.
      Future<void> verifyCust(String dev, String cust, String label) => timed('فحص بعد كل عملية', () async {
            if (!known(dev, cust)) return;
            var b = await custBalance(dev, cust);
            bool off(Map<String, Object?> m) {
              final d = (m['debt'] as num?)?.toDouble(), s = (m['sum'] as num?)?.toDouble();
              return d == null || s == null || (d - s).abs() >= 0.005;
            }

            if (off(b)) {
              // مزامنة واردة في منتصف كتابتها؟ نعيد القراءة مرة بعد لحظة قبل الحكم
              await Future<void>.delayed(const Duration(milliseconds: 300));
              b = await custBalance(dev, cust);
              if (off(b)) {
                problems.add('$label: دين ${cname(cust)} المخزّن على $dev (${b['debt']}) ≠ مجموع معاملاته (${b['sum']})');
                return;
              }
              count('دين ≠ مجموع لحظياً ثم تطابق');
            }
            final debt = (b['debt'] as num).toDouble();
            if (!knowsAll(dev, cust)) {
              count('فحص الحقيقة مؤجَّل حتى المزامنة');
              return;
            }
            near('$label: دين ${cname(cust)} على $dev', debt, h.truth.balance(cust));
          });

      Future<void> verifyInvoice(String inv, String label, {String? on, bool checkName = false}) =>
          timed(on == null ? 'فحص بعد كل عملية' : 'فحص شامل بعد المزامنة', () async {
            final t = h.truth.invoices[inv]!;
            final x = state[inv]!;
            final dev = on ?? x.dev;
            final r = (await h.d(dev).call('invoiceDetail', {'inv': inv}) as Map?)?.cast<String, Object?>();
            if (r == null) {
              if (t.status == 'محذوفة' && dev != x.dev) return; // حُذفت قبل أن تصل: لا أثر لها
              problems.add('$label: الفاتورة غائبة من $dev');
              return;
            }
            final i = (r['invoice'] as Map).cast<String, Object?>();
            final del = ((i['is_deleted'] as int?) ?? 0) == 1;
            if (t.status == 'محذوفة') {
              if (!del) problems.add('$label/$dev: محذوفة في الحقيقة وما زالت ظاهرة');
            } else {
              if (del) problems.add('$label/$dev: محذوفة في القاعدة والصحيح ${t.status}');
              if (i['status'] != t.status) problems.add('$label/$dev: الحالة ${i['status']} والصحيح ${t.status}');
              near('$label/$dev الإجمالي', i['total_amount'], t.total);
              near('$label/$dev المسدد', i['amount_paid_on_invoice'], t.paid);
              if (i['payment_type'] != t.ptype) problems.add('$label/$dev: النوع ${i['payment_type']} والصحيح ${t.ptype}');
              if (i['cust_uuid'] != t.cust) {
                problems.add('$label/$dev: العميل ${cname(i['cust_uuid'] as String?)} والصحيح ${cname(t.cust)}');
              }
              if (checkName) {
                // اسم غيّره جهاز آخر وفي طريقه إلى هنا: القديم أو الجديد كلاهما صحيح لحظتها
                final ok = {nameOn(dev, t.cust), names[t.cust]};
                if (!ok.contains(i['customer_name'])) {
                  problems.add('$label/$dev: اسم العميل على الفاتورة «${i['customer_name']}» والصحيح «${names[t.cust]}»');
                }
              }
              if (t.status == 'محفوظة') {
                near('$label/$dev الخصم', i['discount'], x.discount);
                near('$label/$dev أجور التحميل', i['loading_fee'], x.fee);
                final d = DateTime.tryParse('${i['invoice_date']}')?.toLocal();
                if (d == null || _day(d) != _day(x.date)) {
                  problems.add('$label/$dev: تاريخ الفاتورة ${i['invoice_date']} والصحيح ${_day(x.date)}');
                }
                final got = <String, double>{};
                for (final it in (r['items'] as List).cast<Map>()) {
                  final p = prodByName[it['product_name']];
                  if (p == null) continue;
                  final ql = (it['quantity_large_unit'] as num?)?.toDouble() ?? 0;
                  final qi = (it['quantity_individual'] as num?)?.toDouble() ?? 0;
                  final u = (it['units_in_large_unit'] as num?)?.toDouble() ?? 1;
                  got[p] = (got[p] ?? 0) + (ql > 0 ? ql * (u == 0 ? 1 : u) : qi);
                }
                for (final p in {...got.keys, ...t.items.keys}) {
                  if (((got[p] ?? 0) - (t.items[p] ?? 0)).abs() > 1e-6) {
                    problems.add('$label/$dev: كمية ${pname(p)} في الفاتورة ${got[p] ?? 0} والصحيح ${t.items[p] ?? 0}');
                    break;
                  }
                }
              }
            }
            final txs = (r['txs'] as List).cast<Map>().where((y) =>
                ((y['del'] as int?) ?? 0) == 0 && !_nonContribution.contains(y['type']));
            final mine = txs.where((y) => y['cust'] == t.cust).fold(0.0, (s, y) => s + (y['amount'] as num).toDouble());
            final others = txs.where((y) => y['cust'] != t.cust).fold(0.0, (s, y) => s + (y['amount'] as num).toDouble());
            near('$label/$dev دين الفاتورة في سجل الديون', mine, t.contribution);
            near('$label/$dev أثرها على عملاء آخرين', others, 0);
          });

      void record(String uuid, _Inv x, String status) {
        final prev = h.truth.invoices[uuid];
        h.truth.invoices[uuid] = TruthInvoice(x.cust, x.dev, x.finalTotal, x.paid, x.ptype, status)
          ..voidedFor = {...?prev?.voidedFor}
          ..items = baseItems(x.specs)
          ..specs = [for (final s in x.specs) Map<String, Object?>.from(s)];
        x.held = status == 'معلقة';
        x.nameField = null;
        x.phoneField = null;
        x.incomplete = false;
        state[uuid] = x;
      }

      Future<String?> save(String? inv, _Inv x, String label, {String? dev, bool locked = false}) async {
        final on = dev ?? x.dev;
        final reason = invalidReason(x, foreign: on != x.dev, locked: locked);
        final oldCust = inv == null ? null : h.truth.invoices[inv]?.cust;
        final delta = debtDelta(inv, x);
        // الرصيد الذي سيحكم به التطبيق: رصيد العميل القديم كما يراه هذا الجهاز الآن
        final local = (reason == null && delta < -0.005 && oldCust != null) ? await localDebt(on, oldCust) : null;
        final neg = verdict(delta, local);
        Map<String, Object?> r;
        try {
          r = (await timed('حفظ الفاتورة', () => h.d(on).call('saveInvoice', {
                'cust': x.nameField == null ? x.cust : null,
                'name': x.nameField,
                'phone': x.phoneField,
                'date': x.date.toIso8601String(),
                'total': x.itemsTotal,
                'paid': x.paid,
                'ptype': x.ptype,
                'inv': inv,
                'items': x.specs,
                'discount': x.discount,
                'loadingFee': x.fee,
                'incomplete': x.incomplete,
                'storedName': rnd.nextBool(),
              })) as Map)
              .cast<String, Object?>();
        } catch (e) {
          r = {'ok': false, 'err': 'استثناء: ${'$e'.split('\n').first}'};
        }
        if (r['ok'] != true) {
          if (reason != null) {
            count('رُفض كما يجب: $reason');
          } else if (neg == 'yes') {
            count('رُفض كما يجب: رصيد العميل القديم يصير سالباً');
          } else if (neg == 'gray') {
            count('رفض على حدّ الفلس (رصيد ≈ صفر)');
          } else {
            // بيانات من جهاز آخر وصلت أثناء الحفظ فغيّرت الرصيد المحلي؟
            final after = (oldCust != null && delta < -0.005) ? await localDebt(on, oldCust) : null;
            if (after != null && verdict(delta, after) != 'no') {
              count('رفض بعد وصول مزامنة أثناء الحفظ');
            } else {
              problems.add('$label: رُفض حفظ سليم (${'${r['err']}'.split('\n').first})');
            }
          }
          return null;
        }
        if (reason != null) {
          problems.add('$label: قُبل حفظ يجب رفضه ($reason) — خصم=${x.discount} مسدد=${x.paid} '
              'إجمالي=${r2(x.finalTotal)} نوع=${x.ptype}');
        } else if (neg == 'yes') {
          if (oldCust != null && !knowsAll(on, oldCust)) {
            count('قبول بعد وصول مزامنة أثناء الحفظ');
          } else {
            problems.add('$label: قُبل تعديل يجعل رصيد ${cname(oldCust)} سالباً (رصيده $local والأثر ${r2(delta)})');
          }
        }
        final uuid = r['uuid'] as String;
        final savedCust = r['cust'] as String?;
        if (x.nameField != null && x.nameField!.startsWith(_newPrefix)) {
          if (savedCust == null || h.truth.customers.containsKey(savedCust)) {
            problems.add('$label: اسم عميل جديد لم يُنشئ حساباً جديداً (${cname(savedCust)})');
            if (savedCust != null && h.truth.customers.containsKey(savedCust)) x.cust = savedCust;
          } else {
            h.truth.customers[savedCust] = TruthCustomer(x.nameField!, on);
            names[savedCust] = x.nameField!;
            custs.add(savedCust);
            homeOnly[savedCust] = on;
            x.cust = savedCust;
            count('عميل جديد أُنشئ بصمت من الفاتورة');
          }
        } else if (savedCust != x.cust) {
          problems.add('$label: حُفظت على ${cname(savedCust)} بدل ${cname(x.cust)}');
          if (savedCust != null && h.truth.customers.containsKey(savedCust)) x.cust = savedCust;
        }
        final savedPaid = (r['paid'] as num?)?.toDouble() ?? x.paid;
        if ((savedPaid - x.paid).abs() > 0.01) problems.add('$label: غيّر التطبيق المسدد بصمت: ${x.paid} ← $savedPaid');
        record(uuid, x, 'محفوظة');
        touch(on, x.cust);
        if (oldCust != null) touch(on, oldCust);
        count(inv == null ? 'فاتورة جديدة' : 'حفظ مقبول');
        return uuid;
      }

      Future<String?> hold(String? inv, _Inv x, String label, {bool expectOk = true}) async {
        final r = (await timed('حفظ الفاتورة', () => h.d(x.dev).call('holdInvoice', {
              'inv': inv,
              'cust': x.cust,
              'total': x.itemsTotal,
              'items': x.specs,
              'ptype': x.ptype,
              'discount': x.discount,
              'loadingFee': x.fee,
              'paid': x.paid,
            })) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          if (expectOk) {
            problems.add('$label: رُفض التعليق (${'${r['err']}'.split('\n').first})');
          } else {
            count('رُفض كما يجب: تعليق فاتورة محفوظة');
          }
          return null;
        }
        if (!expectOk) problems.add('$label: عُلّقت فاتورة محفوظة (يجب رفضه)');
        final uuid = r['uuid'] as String;
        x.date = DateTime.now();
        record(uuid, x, 'معلقة');
        touch(x.dev, x.cust);
        count('تعليق');
        return uuid;
      }

      // ─────────────────────────── التغييرات ───────────────────────────

      String spaced(String n) => '  ${n.replaceAll(' ', '   ')} ';

      void apply(_Inv x, String sc) {
        void keepPaid() {
          if (x.ptype == 'نقد') {
            x.paid = x.finalTotal;
          } else if (x.paid > x.finalTotal) {
            x.paid = r2(max(0.0, x.finalTotal - 0.01));
          }
        }

        void keepDiscount() {
          if (x.discount >= x.itemsTotal) x.discount = 0;
        }

        void ensureMoney() {
          if (!hasMoney(x)) x.extra = 1500;
        }

        Map<String, Object?>? pieceLine({double minApplied = 0}) {
          final l = x.specs
              .where((s) => s['large'] != true && s['gift'] != true && _applied(s) >= minApplied)
              .toList();
          return l.isEmpty ? null : l[rnd.nextInt(l.length)];
        }

        String? otherCustomer({bool typed = false}) {
          final others = knownCusts(x.dev)
              .where((c) => c != x.cust && (!typed || nameSettled(x.dev, c)))
              .toList();
          return others.isEmpty ? null : others[rnd.nextInt(others.length)];
        }

        final now = DateTime.now();
        switch (sc) {
          case 'أصناف جديدة كلياً':
            x.specs = randomSpecs();
            x.extra = randomExtra(positive: x.specs.isEmpty);
          case 'إضافة سطر':
            x.specs.add(randomLine());
          case 'حذف سطر':
            if (x.specs.isNotEmpty) x.specs.removeAt(rnd.nextInt(x.specs.length));
          case 'تغيير كمية سطر':
            if (x.specs.isEmpty) x.specs.add(randomLine(allowSpecial: false));
            x.specs[rnd.nextInt(x.specs.length)]['qty'] = (1 + rnd.nextInt(12)).toDouble();
          case 'تغيير سعر سطر':
            if (x.specs.isEmpty) x.specs.add(randomLine(allowSpecial: false));
            {
              final s = x.specs[rnd.nextInt(x.specs.length)];
              final p = (s['price'] as double) * [0.5, 1.1, 2.0][rnd.nextInt(3)];
              s['price'] = r2(min(5000000.0, max(50.0, p)));
              if ((s['discAmt'] as double? ?? 0) >= (s['price'] as double)) s.remove('discAmt');
            }
          case 'تحويل سطر قطعة↔كرتون':
            {
              final withCarton = x.specs.where((s) => h.truth.products[s['prod']]!.carton != null).toList();
              if (withCarton.isNotEmpty) {
                final s = withCarton[rnd.nextInt(withCarton.length)];
                final carton = h.truth.products[s['prod']]!.carton!;
                final large = s['large'] == true;
                s['large'] = !large;
                s['price'] = large ? (s['price'] as double) / carton : (s['price'] as double) * carton;
                s.remove('discAmt');
              }
            }
          case 'كمية كسرية':
            {
              final s = pieceLine();
              if (s != null) s['qty'] = [0.5, 2.25, 1.75][rnd.nextInt(3)];
            }
          case 'سطر هدية':
            x.specs.add(randomLine(allowSpecial: false)..['gift'] = true);
          case 'خصم سطر بنسبة':
            x.specs.add(randomLine(allowSpecial: false)..['discPct'] = [10.0, 20.0, 50.0][rnd.nextInt(3)]);
          case 'خصم سطر بمبلغ':
            x.specs.add(randomLine(allowSpecial: false)..['discAmt'] = 100.0);
          case 'الصنف نفسه في سطرين':
            {
              final l = randomLine(allowSpecial: false);
              x.specs.add(l);
              x.specs.add(Map<String, Object?>.from(l)..['qty'] = 2.0);
            }
          case 'سطر بلا كمية [*]':
            x.incomplete = true;
          case 'بند يدوي فقط بلا أصناف':
            x.specs = [];
            x.extra = randomExtra(positive: true);
          case 'استبدال صنف بآخر':
            if (x.specs.isNotEmpty) {
              final s = x.specs[rnd.nextInt(x.specs.length)];
              final others = prods.where((p) => p.$1 != s['prod']).toList();
              final (u, price, _) = others[rnd.nextInt(others.length)];
              s['prod'] = u;
              s['large'] = false;
              s['price'] = price;
              s.remove('discAmt');
            }
          case 'عكس ترتيب الأسطر':
            x.specs = x.specs.reversed.toList();
          case 'كمية كبيرة جداً':
            {
              final s = pieceLine();
              if (s != null) {
                s['qty'] = 5000.0;
              } else {
                x.specs.add(pieceOf(prods[rnd.nextInt(prods.length)], 5000.0));
              }
            }
          case 'كمية صغيرة جداً':
            {
              final s = pieceLine(minApplied: 100);
              if (s != null) s['qty'] = 0.01;
            }
          case 'سعر بكسر فلس':
            {
              final l = x.specs.where((s) => s['gift'] != true).toList();
              if (l.isNotEmpty) {
                final s = l[rnd.nextInt(l.length)];
                s['price'] = (s['price'] as double).floorToDouble() + 0.995;
                s.remove('discAmt');
              }
            }
          case 'كل الأسطر هدايا مع بند يدوي':
            if (x.specs.isEmpty) x.specs.add(randomLine(allowSpecial: false));
            for (final s in x.specs) {
              s['gift'] = true;
              s.remove('discPct');
              s.remove('discAmt');
            }
            x.extra = randomExtra(positive: true);
          case 'فاتورة 40 سطراً':
            x.specs = [for (var k = 0; k < 40; k++) randomLine()];
          case 'حذف كل الأسطر إلا واحداً':
            if (x.specs.length > 1) x.specs = [x.specs[rnd.nextInt(x.specs.length)]];
          case 'إلغاء خصومات الأسطر':
            for (final s in x.specs) {
              s.remove('gift');
              s.remove('discPct');
              s.remove('discAmt');
            }
          case 'خصم على الفاتورة':
            x.discount = r2(x.itemsTotal * [0.0, 0.01, 0.05, 0.2][rnd.nextInt(4)]);
          case 'خصم ≥ الإجمالي [*]':
            x.discount = r2(x.itemsTotal) + 1;
          case 'خصم سالب [*]':
            x.discount = -250;
          case 'خصم = الإجمالي − فلس':
            ensureMoney();
            if (x.itemsTotal >= 0.02) x.discount = r2(x.itemsTotal - 0.01);
          case 'إلغاء الخصم':
            x.discount = 0;
          case 'أجور تحميل':
            x.fee = [0.0, 1000.0, 2500.0, 15000.0][rnd.nextInt(4)];
          case 'أجور تحميل بكسور':
            x.fee = [0.01, 0.5, 99.99, 1234.56][rnd.nextInt(4)];
          case 'أجور تحميل سالبة [*]':
            x.fee = -1000;
          case 'إلغاء أجور التحميل':
            x.fee = 0;
          case 'خصم وتحميل معاً':
            x.discount = r2(x.itemsTotal * 0.1);
            x.fee = 5000;
          case 'كسور الدينار':
            x.extra = r2(x.extra + 0.37);
            x.discount = r2(min(x.discount + 0.13, x.itemsTotal * 0.5));
          case 'فاتورة ضخمة':
            x.extra = 987654321.5;
          case 'فاتورة صغيرة جداً':
            x.specs = [];
            x.extra = 0.25;
            x.discount = 0;
            x.fee = 0;
          case 'إلى نقد':
            x.ptype = 'نقد';
          case 'إلى دين':
            x.ptype = 'دين';
            x.paid = 0;
          case 'تسديد جزئي':
            x.ptype = 'دين';
            ensureMoney();
            keepDiscount();
            x.paid = r2(x.finalTotal * [0.1, 0.25, 0.5, 0.9][rnd.nextInt(4)]);
          case 'تسديد كامل':
            x.ptype = 'دين';
            x.paid = x.finalTotal;
          case 'تسديد إلا فلس':
            x.ptype = 'دين';
            ensureMoney();
            keepDiscount();
            x.paid = x.finalTotal >= 0.02 ? r2(x.finalTotal - 0.01) : 0.0;
          case 'إلغاء التسديد':
            if (x.ptype == 'دين') x.paid = 0;
          case 'مسدد > الإجمالي [*]':
            x.ptype = 'دين';
            ensureMoney();
            keepDiscount();
            x.paid = r2(x.finalTotal + 500);
          case 'مسدد يزيد فلسين [*]':
            x.ptype = 'دين';
            ensureMoney();
            keepDiscount();
            x.paid = r2(x.finalTotal) + 0.02;
          case 'مسدد سالب [*]':
            x.ptype = 'دين';
            x.paid = -500;
          case 'نقد بمسدد ناقص [*]':
            ensureMoney();
            keepDiscount();
            x.ptype = 'نقد';
            x.paid = r2(x.finalTotal * 0.5);
          case 'تصغير تحت المسدد [*]':
            ensureMoney();
            keepDiscount();
            x.ptype = 'دين';
            x.paid = x.finalTotal;
            x.specs = [];
            x.extra = r2(max(0.5, x.paid * 0.3));
            x.discount = 0;
            x.fee = 0;
          case 'تاريخ سابق':
            x.date = x.date.subtract(Duration(days: 1 + rnd.nextInt(40)));
            if (now.difference(x.date).inDays > 1000) x.date = now;
          case 'تاريخ اليوم':
            x.date = now;
          case 'آخر يوم في الشهر السابق':
            x.date = DateTime(now.year, now.month, 0, 23, 59, 59);
          case 'أول يوم في الشهر':
            x.date = DateTime(now.year, now.month, 1, 0, 0, 1);
          case '29 شباط':
            x.date = DateTime(2024, 2, 29, 12);
          case 'تغيير العميل':
            {
              final o = otherCustomer();
              if (o != null) x.cust = o;
            }
          case 'اسم عميل آخر بمسافات':
            {
              final o = otherCustomer(typed: true);
              if (o != null) {
                x.cust = o;
                x.nameField = spaced(nameOn(x.dev, o));
              }
            }
          case 'اسم العميل بمسافات زائدة':
            if (nameSettled(x.dev, x.cust)) x.nameField = spaced(nameOn(x.dev, x.cust));
          case 'اسم العميل بلا مسافات':
            if (nameSettled(x.dev, x.cust)) x.nameField = nameOn(x.dev, x.cust).replaceAll(' ', '');
          case 'العودة إلى العميل الأول':
            if (x.firstCust != x.cust && known(x.dev, x.firstCust)) x.cust = x.firstCust;
          case 'اسم فارغ [*]':
            x.nameField = '   ';
          case _newName:
            x.nameField = '$_newPrefix ${++newCustomers}';
          case _phone:
            x.phoneField = '07809${100000 + rnd.nextInt(899999)}';
          default:
            throw StateError('تغيير غير معروف: $sc');
        }
        if (x.specs.length > 80) x.specs = x.specs.sublist(x.specs.length - 80);
        if (!sc.contains('[*]')) {
          ensureMoney();
          keepDiscount();
          keepPaid();
        }
      }

      final safeMutations = _mutations.where((m) => !m.contains('[*]')).toList();

      List<String> pickCompound({bool forHold = false}) {
        final n = const [1, 2, 2, 3, 3, 3, 4, 4, 5][rnd.nextInt(9)];
        final pool = forHold ? safeMutations : _mutations;
        final out = [for (var k = 0; k < n; k++) pool[rnd.nextInt(pool.length)]];
        void put(String s) => out.insert(rnd.nextInt(out.length + 1), s);
        if (forHold) {
          if (rnd.nextDouble() < 0.3) put('تغيير العميل');
          return out;
        }
        final roll = rnd.nextDouble();
        if (roll < 0.0025 && newCustomers < _maxNew) {
          put(_newName);
        } else if (roll < 0.33) {
          put(_moves[rnd.nextInt(_moves.length)]);
        }
        if (rnd.nextDouble() < 0.08) put(_phone);
        return out;
      }

      // ─────────────────────────── تعديل فاتورة ───────────────────────────

      Future<void> editInvoice(String inv, String label) async {
        final cur = state[inv]!;
        final dev = cur.dev;
        final oldCust = cur.cust;
        final mr = rnd.nextDouble();
        final mod = mr < 0.03
            ? _modifiers[0]
            : mr < 0.06
                ? _modifiers[1]
                : mr < 0.10
                    ? _modifiers[2]
                    : mr < 0.12
                        ? _modifiers[3]
                        : mr < 0.14
                            ? _modifiers[4]
                            : null;
        final steps = mod == _modifiers[0] ? const <String>[] : pickCompound();
        final x = cur.copy();
        for (final s in steps) {
          apply(x, s);
        }
        count('تعديل مركّب من ${steps.length} تغييرات');
        for (final s in steps) {
          count('تغيير: $s');
        }
        if (mod != null) count('طريقة الحفظ: $mod');
        combos.add(([...steps]..sort()).join(' + '));
        final tag = '$label [${[...steps, if (mod != null) '⟵ $mod'].join(' + ')}]';
        final newName = x.nameField?.startsWith(_newPrefix) ?? false;
        String? phoneBefore;
        if (x.phoneField != null && !newName && knowsAll(dev, x.cust)) {
          phoneBefore = ((await custBalance(dev, x.cust))['phone'] as String?) ?? '';
        }
        var accepted = false;
        if (mod == _modifiers[4]) {
          await hold(inv, x, tag, expectOk: false);
        } else if (mod == _modifiers[2] || mod == _modifiers[3]) {
          DateTime lock;
          if (mod == _modifiers[3]) {
            lock = _plusDays(DateTime.now(), 1);
          } else {
            final a = _day(cur.date), b = _day(x.date);
            final lo = a.isBefore(b) ? a : b, hi = a.isBefore(b) ? b : a;
            final opts = [_plusDays(lo, -1), lo, _plusDays(lo, 1), hi, _plusDays(hi, 1)];
            lock = opts[rnd.nextInt(opts.length)];
          }
          final locked = _day(cur.date).isBefore(lock) || _day(x.date).isBefore(lock);
          count(locked ? 'التثبيت يمنع هذا التعديل' : 'التثبيت لا يمنع هذا التعديل');
          await h.d(dev).call('setLock', {'date': lock.toIso8601String()});
          try {
            accepted = await save(inv, x, tag, locked: locked) != null;
          } finally {
            await h.d(dev).call('setLock', {'date': null});
          }
        } else {
          accepted = await save(inv, x, tag) != null;
          if (accepted && mod == _modifiers[1]) {
            await save(inv, state[inv]!.copy(), '$tag — الحفظ الثاني');
          }
        }
        if (accepted && phoneBefore != null) {
          final after = (await custBalance(dev, state[inv]!.cust))['phone'] as String?;
          if (phoneBefore.trim().isNotEmpty && after != phoneBefore) {
            problems.add('$tag: هاتف بطاقة العميل تغيّر من $phoneBefore إلى $after');
          }
          if (phoneBefore.trim().isEmpty && (after ?? '').trim().isEmpty) {
            problems.add('$tag: عميل بلا هاتف ولم يُضف الرقم المكتوب إلى بطاقته');
          }
        }
        await verifyInvoice(inv, tag, checkName: accepted);
        await verifyCust(dev, oldCust, tag);
        if (state[inv]!.cust != oldCust) await verifyCust(dev, state[inv]!.cust, tag);
      }

      Future<String?> create(String dev, String cust, String label, {bool temp = false}) async {
        final x = _Inv(dev, cust, DateTime.now())
          ..temp = temp
          ..specs = randomSpecs()
          ..ptype = rnd.nextInt(3) < 2 ? 'دين' : 'نقد';
        x.extra = randomExtra(positive: x.specs.isEmpty);
        // كل الأسطر هدايا بلا بند يدوي = إجمالي صفر: يرفضه التطبيق بحق (التشغيل الأول seed=196248)
        if (!hasMoney(x)) x.extra = 1500;
        x.paid = x.ptype == 'نقد' ? x.finalTotal : (rnd.nextBool() ? 0 : r2(x.finalTotal * 0.3));
        final u = (temp && rnd.nextBool()) ? await hold(null, x, '$label (تعليق جديدة)') : await save(null, x, label);
        if (u != null) {
          await verifyInvoice(u, label, checkName: true);
          await verifyCust(dev, cust, label);
        }
        return u;
      }

      // ─────────────────────────── المعاملات اليدوية ───────────────────────────

      /// معاملة يدوية جديدة من شاشة العميل: دين يدوي، تسديد يدوي، أو وصل قبض.
      Future<void> newManual(String dev, String c, String label) => timed('معاملات يدوية', () async {
            final local = (await custBalance(dev, c))['debt'] as num?;
            final bal = local?.toDouble() ?? 0;
            final w = rnd.nextDouble();
            if (w < 0.45 || bal < 1) {
              final amount = [5000.0, 1250.75, 0.25, 0.01, 250000.0, 33333.33][rnd.nextInt(6)];
              final u = await h.addTx(dev, c, amount);
              if (u == null) {
                problems.add('$label: لم يُحفظ دين يدوي $amount على ${cname(c)}');
              } else {
                manual.add(u);
                count('دين يدوي');
              }
            } else {
              final amount = [r2(bal * 0.4), r2(bal * 0.137), r2(bal)][rnd.nextInt(3)];
              if (amount < 0.01) return;
              if (w < 0.7) {
                final u = await h.addTx(dev, c, -amount);
                if (u == null) {
                  problems.add('$label: لم يُحفظ تسديد يدوي $amount على ${cname(c)} (رصيده $bal)');
                } else {
                  manual.add(u);
                  count('تسديد يدوي');
                }
              } else {
                final discount = rnd.nextDouble() < 0.2;
                final u = await h.d(dev).call('receipt', {
                  'cust': c,
                  'amount': amount,
                  'marker': 'S$ops',
                  if (discount) 'kind': 'discount',
                }) as String?;
                if (u == null) {
                  problems.add('$label: لم يُحفظ وصل سليم بـ$amount على ${cname(c)} (رصيده $bal)');
                } else {
                  h.truth.txs[u] = TruthTx(c, dev, -amount, 'manual_payment');
                  manual.add(u);
                  count(discount ? 'وصل خصم' : 'وصل قبض');
                }
              }
            }
            touch(dev, c);
          }).then((_) => verifyCust(dev, c, '$label (معاملة يدوية)'));

      /// تعديل معاملة يدوية من شاشة العميل (من جهازها، أو من غيره [*]، أو داخل فترة مثبّتة [*]).
      Future<void> editManual(String label) => timed('معاملات يدوية', () async {
            final live = manual.where((u) => !(h.truth.txs[u]?.deleted ?? true)).toList();
            if (live.isEmpty) return;
            final u = live[rnd.nextInt(live.length)];
            final t = h.truth.txs[u]!;
            final w = rnd.nextDouble();
            // جهاز آخر وصلته المعاملة بالمزامنة (الشاشة لا تُظهر له زر التعديل؛ هذا فحص
            // للحماية في قاعدة البيانات نفسها)
            final others = syncedTx.contains(u) ? devs.where((d) => d != t.owner).toList() : const <String>[];
            if (w < 0.12 && others.isNotEmpty) {
              final d = others[rnd.nextInt(others.length)];
              try {
                await h.d(d).call('editTx', {'tx': u, 'amount': t.amount + 1000});
                problems.add('$label: عدّل $d معاملة أنشأها ${t.owner} (يجب رفضه)');
                t.amount += 1000; // يتبع النموذج التطبيق
              } catch (_) {
                count('رُفض كما يجب: تعديل معاملة جهاز آخر');
              }
              touch(d, t.cust);
              return;
            }
            if (!knowsAll(t.owner, t.cust)) return; // رصيد الجهاز غير مكتمل: تعديل التسديد قد يُسيل الرصيد
            final bal = h.truth.balance(t.cust);
            final old = t.amount;
            double next;
            if (old >= 0) {
              next = [r2(old * 0.5), r2(old * 2), r2(old + 0.37), 0.01][rnd.nextInt(4)];
              if (next < 0.01) next = 0.01;
              if (bal + (next - old) < 0) return; // إنقاص دين أكثر من الرصيد
            } else {
              final room = bal + (-old); // أقصى تسديد لا يجعل الرصيد سالباً
              final want = [r2(-old * 0.5), r2(-old * 1.5), r2(-old + 0.37)][rnd.nextInt(3)];
              final abs = min(want, r2(room));
              if (abs < 0.01) return;
              next = -abs;
            }
            final underLock = w < 0.2;
            if (underLock) {
              await h.d(t.owner).call('setLock', {'date': _plusDays(DateTime.now(), 1).toIso8601String()});
            }
            try {
              final r = await h.d(t.owner).call('editTx', {'tx': u, 'amount': next});
              if (r is Map && r['locked'] == true) {
                count('تعديل معاملة على سجل مستعاد (رفضه التطبيق)');
              } else if (underLock) {
                problems.add('$label: عُدّلت معاملة يدوية داخل فترة مثبّتة');
                t.amount = next;
              } else {
                t.amount = next;
                count('تعديل معاملة يدوية');
              }
            } catch (e) {
              if (underLock) {
                count('رُفض كما يجب: تعديل معاملة داخل فترة مثبّتة');
              } else {
                problems.add('$label: رُفض تعديل معاملة يدوية سليم (${'$e'.split('\n').first})');
              }
            } finally {
              if (underLock) await h.d(t.owner).call('setLock', {'date': null});
            }
            touch(t.owner, t.cust);
            await verifyCust(t.owner, t.cust, '$label (تعديل معاملة)');
          });

      /// زر «تحويل نوع المعاملة» (دين ⇄ تسديد) من جهازها.
      Future<void> convertManual(String label) => timed('معاملات يدوية', () async {
            final live = manual.where((u) => !(h.truth.txs[u]?.deleted ?? true)).toList();
            if (live.isEmpty) return;
            final u = live[rnd.nextInt(live.length)];
            final t = h.truth.txs[u]!;
            if (!knowsAll(t.owner, t.cust)) return;
            if (t.amount > 0 && h.truth.balance(t.cust) - 2 * t.amount < 0) return; // تحويل دين إلى تسديد يُسيل الرصيد
            final old = t.amount;
            try {
              final raw = await h.d(t.owner).call('convertTx', {'tx': u});
              final r = (raw as Map).cast<String, Object?>();
              if (r['locked'] == true) return;
              final amt = (r['amount'] as num?)?.toDouble();
              if (amt == null || (amt + old).abs() >= 0.005) {
                problems.add('$label: تحويل نوع معاملة ${r2(old)} أعطى $amt والمتوقع ${r2(-old)}');
              }
              t.amount = amt ?? -old;
              t.type = (r['type'] as String?) ?? (old >= 0 ? 'manual_payment' : 'manual_debt');
              count('تحويل نوع معاملة');
            } catch (e) {
              problems.add('$label: رُفض تحويل نوع معاملة سليم (${'$e'.split('\n').first})');
            }
            touch(t.owner, t.cust);
            await verifyCust(t.owner, t.cust, '$label (تحويل نوع)');
          });

      // ─────────────────────────── مرتجعات ───────────────────────────

      double pipeSold(_Inv x) =>
          x.specs.where((s) => s['prod'] == pipe).fold(0.0, (a, s) => a + (s['qty'] as double));
      double returnedQty(String inv) =>
          returns.where((r) => r.inv == inv && !r.voided).fold(0.0, (a, r) => a + r.qty);

      Future<void> salesReturn(String label) => timed('مرتجعات', () async {
            final cands = state.entries
                .where((e) =>
                    !e.value.temp &&
                    !e.value.deleted &&
                    !e.value.held &&
                    knowsAll(e.value.dev, e.value.cust) &&
                    e.value.specs.any((s) => s['prod'] == pipe && s['gift'] != true))
                .map((e) => e.key)
                .toList();
            if (cands.isEmpty) return;
            final inv = cands[rnd.nextInt(cands.length)];
            final cur = state[inv]!;
            final dev = cur.dev;
            final lines = cur.specs.where((s) => s['prod'] == pipe && s['gift'] != true).toList();
            final price = _applied(lines[rnd.nextInt(lines.length)]);
            final remaining = pipeSold(cur) - returnedQty(inv);
            final over = rnd.nextDouble() < 0.1;
            final qty = over ? max(1.0, remaining.floorToDouble() + 1) : 1.0;
            final expectOk = qty <= remaining + 1e-6;
            final value = price * qty;
            final bal = h.truth.balance(cur.cust);
            var mode = const ['credit', 'cash', 'mixed'][rnd.nextInt(3)];
            if (mode != 'cash' && bal < value + 1) mode = 'cash';
            var cash = 0.0;
            if (mode == 'mixed') {
              cash = r2(value * 0.4);
              if (cash < 0.02 || cash > value - 0.02) mode = 'cash';
            }
            if (mode == 'cash') cash = 0;
            final credit = mode == 'credit' ? value : (mode == 'mixed' ? value - cash : 0.0);
            final kind = mode == 'credit' ? 'على الحساب' : mode == 'cash' ? 'نقدي' : 'مختلط';
            final what = '$label (مرتجع $kind${over ? ' أكثر من المتبقي $remaining [*]' : ''})';
            final r = (await h.d(dev).call('salesReturn', {
              'inv': inv,
              'cust': cur.cust,
              'items': [
                {'prod': pipe, 'qty': qty, 'price': price}
              ],
              'mode': mode,
              'cash': cash,
            }) as Map)
                .cast<String, Object?>();
            if (r['ok'] == true) {
              if (!expectOk) problems.add('$what: قُبل إرجاع أكثر من المتبقي في الفاتورة');
              var sum = 0.0;
              for (final t in (r['txs'] as List).cast<List>()) {
                h.truth.txs[t[0] as String] = TruthTx(cur.cust, dev, (t[1] as num).toDouble(), 'manual_payment');
                sum += (t[1] as num).toDouble();
              }
              if ((sum + credit).abs() > 0.00501) problems.add('$what: أثره على الدين = $sum والمتوقع ${-credit}');
              h.truth.products[pipe]!.movements += qty;
              returns.add(_Ret(r['id'] as int, inv, dev, cur.cust, sum, qty));
              touch(dev, cur.cust);
              count('مرتجع $kind');
            } else if (expectOk) {
              problems.add('$what: رُفض مرتجع سليم (${'${r['err']}'.split('\n').first})');
            } else {
              count('رُفض كما يجب: مرتجع أكثر من المتبقي');
            }
            await verifyInvoice(inv, what);
            await verifyCust(dev, cur.cust, what);
          });

      Future<void> voidReturn(String label) => timed('مرتجعات', () async {
            final active = returns.where((r) => !r.voided).toList();
            final voided = returns.where((r) => r.voided).toList();
            final again = voided.isNotEmpty && (active.isEmpty || rnd.nextDouble() < 0.2);
            if (active.isEmpty && !again) return;
            final rt = again ? voided[rnd.nextInt(voided.length)] : active[rnd.nextInt(active.length)];
            final what = '$label (${again ? 'إلغاء مرتجع ملغى مسبقاً [*]' : 'إلغاء مرتجع'})';
            final v = (await h.d(rt.dev).call('voidSalesReturn', {'id': rt.id}) as Map).cast<String, Object?>();
            if (v['ok'] == true) {
              if (again) problems.add('$what: قُبل إلغاء مرتجع ملغى مسبقاً');
              var sum = 0.0;
              for (final t in (v['txs'] as List).cast<List>()) {
                h.truth.txs[t[0] as String] = TruthTx(rt.cust, rt.dev, (t[1] as num).toDouble(), 'manual_debt');
                sum += (t[1] as num).toDouble();
              }
              if ((sum + rt.credit).abs() >= 0.005) problems.add('$what: أثر الإلغاء $sum والمتوقع ${-rt.credit}');
              h.truth.products[pipe]!.movements -= rt.qty;
              rt.voided = true;
              touch(rt.dev, rt.cust);
              count('إلغاء مرتجع');
            } else if (again) {
              count('رُفض كما يجب: إلغاء مرتجع ملغى');
            } else {
              problems.add('$what: رُفض إلغاء مرتجع (${'${v['err']}'.split('\n').first})');
            }
            await verifyCust(rt.dev, rt.cust, what);
          });

      // ─────────────────────────── فاتورة مؤقتة ───────────────────────────

      Future<void> tempInvoice(String dev, String label) async {
        final cs = knownCusts(dev);
        final u = await create(dev, cs[rnd.nextInt(cs.length)], label, temp: true);
        if (u == null) return;
        count('فاتورة مؤقتة');
        final steps = 1 + rnd.nextInt(5);
        for (var k = 1; k <= steps && !stop(); k++) {
          final cur = state[u]!;
          if (cur.deleted) break;
          final oldCust = cur.cust;
          if (cur.held) {
            final w = rnd.nextDouble();
            if (w < 0.45) {
              final y = cur.copy();
              for (final s in pickCompound(forHold: true)) {
                apply(y, s);
              }
              await hold(u, y, '$label [تعديل وهي معلّقة $k]');
              count('سيناريو: تعديل وهي معلّقة');
            } else if (w < 0.85) {
              final y = cur.copy();
              final st = pickCompound();
              for (final s in st) {
                apply(y, s);
              }
              final ok = await save(u, y, '$label [استكمال المعلّقة $k: ${st.join(' + ')}]') != null;
              count('سيناريو: استكمال المعلّقة');
              await verifyInvoice(u, '$label [استكمال $k]', checkName: ok);
            } else {
              await h.d(dev).call('discardHeld', {'inv': u});
              h.truth.invoices[u]!.status = 'محذوفة';
              cur.deleted = true;
              count('سيناريو: حذف المعلّقة');
            }
            await verifyInvoice(u, '$label [$k]');
            await verifyCust(dev, oldCust, '$label [$k]');
            if (state[u]!.cust != oldCust) await verifyCust(dev, state[u]!.cust, '$label [$k]');
          } else {
            await editInvoice(u, '$label [تعديل $k]');
          }
        }
        final last = state[u]!;
        if (last.deleted) return;
        if (last.held) {
          await h.d(dev).call('discardHeld', {'inv': u});
          count('سيناريو: حذف المعلّقة');
        } else {
          if (rnd.nextDouble() < 0.25) {
            await h.d(dev).call('setLock', {'date': _plusDays(last.date, 1).toIso8601String()});
            try {
              final r = (await h.d(dev).call('deleteInvoice', {'inv': u}) as Map).cast<String, Object?>();
              if (r['ok'] == true) {
                problems.add('$label: حُذفت فاتورة داخل فترة مثبّتة');
                h.truth.invoices[u]!.status = 'محذوفة';
                last.deleted = true;
              } else {
                count('رُفض كما يجب: حذف داخل فترة مثبّتة');
              }
            } finally {
              await h.d(dev).call('setLock', {'date': null});
            }
            await verifyInvoice(u, '$label (حذف داخل فترة مثبّتة)');
            if (last.deleted) return;
          }
          final r = (await h.d(dev).call('deleteInvoice', {'inv': u}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            problems.add('$label: رُفض حذف فاتورة سليمة (${'${r['err']}'.split('\n').first})');
            await verifyInvoice(u, '$label (حذف مرفوض)');
            return;
          }
          count('حذف فاتورة');
        }
        h.truth.invoices[u]!.status = 'محذوفة';
        last.deleted = true;
        touch(dev, last.cust);
        await verifyInvoice(u, '$label (حذف)');
        await verifyCust(dev, last.cust, '$label (حذف)');
      }

      // ─────────────────────────── أسماء وممنوعات ───────────────────────────

      Future<void> rename(String label) async {
        final cands = custs.where((c) => pendingRename[c] == null && known(h.truth.customers[c]!.creator, c)).toList();
        if (cands.isEmpty) return;
        final c = cands[rnd.nextInt(cands.length)];
        final dev = h.truth.customers[c]!.creator;
        final nn = 'زبون شامل معدل ${++renames}';
        final r = (await h.d(dev).call('renameCustomer', {'cust': c, 'name': nn}) as Map).cast<String, Object?>();
        if (r['ok'] != true) {
          problems.add('$label: رُفض تغيير اسم ${cname(c)} إلى $nn على جهازه $dev (${r['err']})');
          return;
        }
        pendingRename[c] = (dev, names[c]!);
        names[c] = nn;
        count('تغيير اسم عميل');
        final b = await custBalance(dev, c);
        if (b['name'] != nn) problems.add('$label: الاسم على $dev بعد التغيير «${b['name']}» والصحيح «$nn»');
      }

      Future<void> forbiddenRename(String label) async {
        final cands = custs.where((c) => homeOnly[c] == null && pendingRename[c] == null).toList();
        if (cands.isEmpty) return;
        final c = cands[rnd.nextInt(cands.length)];
        final creator = h.truth.customers[c]!.creator;
        final others = devs.where((d) => d != creator).toList();
        final d = others[rnd.nextInt(others.length)];
        final r = (await h.d(d).call('renameCustomer', {'cust': c, 'name': 'اسم ممنوع ${++renames}'}) as Map)
            .cast<String, Object?>();
        if (r['ok'] == true) {
          problems.add('$label: غيّر $d اسم ${cname(c)} وأنشأه $creator (يجب رفضه)');
        } else {
          count('رُفض كما يجب: تغيير اسم عميل من غير جهازه');
        }
      }

      Future<void> foreignAttempt(String label) async {
        final cands = synced.where((u) => !state[u]!.deleted && !state[u]!.held).toList();
        if (cands.isEmpty) return;
        final o = cands[rnd.nextInt(cands.length)];
        final owner = state[o]!.dev;
        final others = devs.where((d) => d != owner).toList();
        final d = others[rnd.nextInt(others.length)];
        if (rnd.nextBool()) {
          final x = state[o]!.copy();
          for (final s in pickCompound()) {
            apply(x, s);
          }
          await save(o, x, '$label (تعديل فاتورة ${owner} من $d)', dev: d);
          count('محاولة تعديل فاتورة الجهاز الآخر');
        } else {
          final r = (await h.d(d).call('deleteInvoice', {'inv': o}) as Map).cast<String, Object?>();
          if (r['ok'] == true) {
            problems.add('$label: حذف $d فاتورة أنشأها $owner');
          } else {
            count('رُفض كما يجب: حذف فاتورة الجهاز الآخر');
          }
        }
        await verifyInvoice(o, '$label (فاتورة $owner بعد محاولة $d)');
      }

      // ─────────────────────────── المزامنة ───────────────────────────

      Future<String> uploadDiag(String dev, String tx, String inv) async {
        try {
          final r = (await h.d(dev).call('invoiceDetail', {'inv': inv}) as Map?)?.cast<String, Object?>();
          final i = (r?['invoice'] as Map?)?.cast<String, Object?>();
          final c = h.cloud.collection('invoices')[inv];
          final ct = ((c?['transactions'] as List?) ?? const [])
              .cast<Map>()
              .where((t) => t['transaction_uuid'] == tx)
              .map((t) => '${t['amount_changed']}${t['is_deleted'] == 1 ? ' محذوفة' : ''}')
              .join('،');
          return ' ⟵ تشخيص: الفاتورة على $dev is_synced=${i?['is_synced']} نسخة=${i?['version']} '
              'حالة=${i?['status']}؛ في السحابة: ${c == null ? 'غائبة' : 'نسخة=${c['version']} '
                  'مبلغ المعاملة=${ct.isEmpty ? 'غير موجودة' : ct}'}';
        } catch (e) {
          return ' ⟵ تعذّر التشخيص: $e';
        }
      }

      var windowAt = 0; // فواتير تُفحص على كل الأجهزة بالتناوب
      final closed = <String>{};
      Future<void> syncAndCheck(String label, {bool everything = false}) async {
        live('مزامنة وفحص كل الأجهزة…');
        final e = await timed('مزامنة (انتظار السحابة)', () => h.settle());
        for (final x in e) {
          final m = RegExp(r'^(D\d): .*لم تُرفع: (\S+) .*فاتورة=(inv_\S+)').firstMatch(x);
          problems.add('$label: $x${m == null ? '' : await uploadDiag(m.group(1)!, m.group(2)!, m.group(3)!)}');
        }
        dirty.clear();
        homeOnly.clear();
        pendingRename.clear();
        offline.clear();
        await timed('فحص شامل بعد المزامنة', () async {
          for (final dev in devs) {
            for (final c in custs) {
              if (stop()) return;
              final b = await custBalance(dev, c);
              final want = h.truth.balance(c);
              near('$label: دين ${cname(c)} على $dev', b['debt'], want);
              near('$label: مجموع معاملات ${cname(c)} على $dev', b['sum'], want);
              if (b['name'] != names[c]) problems.add('$label: اسم العميل على $dev «${b['name']}» والصحيح «${names[c]}»');
            }
          }
        });
        final all = state.keys.where((u) => !closed.contains(u)).toList();
        final pick = everything
            ? all
            : [for (var k = 0; k < min(100, all.length); k++) all[(windowAt + k) % all.length]];
        windowAt += 100;
        for (final inv in pick) {
          for (final dev in devs) {
            if (stop()) return;
            await verifyInvoice(inv, '$label (فحص شامل)', on: dev);
          }
          if (state[inv]!.deleted) closed.add(inv);
        }
        synced
          ..clear()
          ..addAll(state.keys.where((u) => !state[u]!.deleted));
        syncedTx
          ..clear()
          ..addAll(manual);
        count('مزامنة وفحص شامل');
      }

      // ═══════════════════════════ التشغيل ═══════════════════════════

      // ── 1) الفواتير: لكل عميل $_perCust فواتير، كل فاتورة على جهاز بالقرعة ──
      live('إنشاء الفواتير…');
      final remaining = <String, int>{};
      final idx = <String, int>{};
      var made = 0;
      for (final c in base) {
        for (var k = 0; k < _perCust && !stop(); k++) {
          final dev = devs[rnd.nextInt(devs.length)];
          made++;
          final u = await create(dev, c, 'إنشاء الفاتورة $made على $dev');
          if (u == null) {
            problems.add('إنشاء الفاتورة $made: رُفضت');
            continue;
          }
          remaining[u] = _edits;
          idx[u] = made;
          if (made % 25 == 0) live('إنشاء الفواتير… $made');
        }
      }
      await syncAndCheck('بعد إنشاء الفواتير');

      // ── 2) العمليات بالقرعة حتى تُستنفد التعديلات ──
      final manualLeft = {for (final c in base) c: _manualPerCust};
      var manualTotal = _customers * _manualPerCust;
      final pending = remaining.keys.toList();
      // المزامنة كل 250–750 عملية (السريع: 60–150)، والأفعال النادرة أكثر في السريع حتى
      // يمر على كل المسارات
      const syncMin = _quick ? 60 : 250, syncSpan = _quick ? 90 : 500;
      const scale = _quick ? 3.0 : 1.0;
      var nextSync = syncMin + rnd.nextInt(syncSpan);
      loopWatch.start();
      while (pending.isNotEmpty && !stop()) {
        ops++;
        if (ops >= nextSync) {
          await syncAndCheck('مزامنة ${stats['مزامنة وفحص شامل'] ?? 0}');
          nextSync = ops + syncMin + rnd.nextInt(syncSpan);
          continue;
        }
        final dev = devs[rnd.nextInt(devs.length)];
        final label = 'عملية $ops';
        // معاملات العملاء اليدوية موزعة على طول الاختبار
        final editsLeft = pending.fold(0, (a, u) => a + remaining[u]!);
        if (manualTotal > 0 && rnd.nextDouble() < manualTotal / (manualTotal + editsLeft)) {
          final cs = manualLeft.keys.where((c) => manualLeft[c]! > 0 && known(dev, c)).toList();
          if (cs.isNotEmpty) {
            final c = cs[rnd.nextInt(cs.length)];
            manualLeft[c] = manualLeft[c]! - 1;
            manualTotal--;
            await newManual(dev, c, label);
            flushProblems();
            continue;
          }
        }
        final w = rnd.nextDouble();
        if (w < 0.008 * scale) {
          await editManual(label);
        } else if (w < 0.011 * scale) {
          await convertManual(label);
        } else if (w < 0.021 * scale) {
          await salesReturn(label);
        } else if (w < 0.025 * scale) {
          await voidReturn(label);
        } else if (w < 0.029 * scale) {
          await timed('فواتير مؤقتة', () => tempInvoice(dev, '$label — فاتورة مؤقتة ${++temps}'));
        } else if (w < 0.032 * scale) {
          await timed('أسماء', () => rename(label));
        } else if (w < 0.033 * scale) {
          await timed('أسماء', () => forbiddenRename(label));
        } else if (w < 0.036 * scale) {
          await timed('فاتورة الجهاز الآخر', () => foreignAttempt(label));
        } else if (w < 0.0368 * scale && !offline.contains(dev)) {
          await timed('إعادة تشغيل', () => h.restart(dev));
          count('إعادة تشغيل مفاجئة');
        } else if (w < 0.0395 * scale) {
          if (offline.remove(dev)) {
            await h.setOnline(dev, true);
            count('عاد الإنترنت');
          } else {
            offline.add(dev);
            await h.setOnline(dev, false);
            count('انقطع الإنترنت');
          }
        } else {
          // تعديل فاتورة: أي فاتورة بقيت لها تعديلات، بالقرعة
          final k = rnd.nextInt(pending.length);
          final inv = pending[k];
          await editInvoice(inv, '$label — الفاتورة ${idx[inv]} (${_edits - remaining[inv]! + 1}/$_edits)');
          remaining[inv] = remaining[inv]! - 1;
          if (remaining[inv] == 0) {
            pending[k] = pending.last;
            pending.removeLast();
          }
          done++;
        }
        flushProblems();
        if (ops % 10 == 0) live('عمليات بالقرعة');
        if (ops % 1000 == 0) {
          final eta = done > 0 ? (loopWatch.elapsed.inSeconds * (totalEdits - done) / done).round() : 0;
          print('… $done/$totalEdits تعديل ($ops عملية) — ${sw.elapsed.inMinutes}د — المتبقي ≈ ${eta ~/ 60}د — '
              'عملاء=${custs.length} تركيبات=${combos.length} — مشاكل=${problems.length}');
        }
      }

      // ── 3) النهاية: مزامنة وكل فاتورة على كل جهاز، والدفتر والفحص العميق ──
      if (!stop()) await syncAndCheck('المزامنة الأخيرة', everything: true);
      live('الدفتر المحاسبي والفحص العميق…');
      if (!stop()) {
        for (final dev in devs) {
          final lc = (await h.d(dev).call('ledgerCheck', const {}, const Duration(minutes: 30)) as Map)
              .cast<String, Object?>();
          for (final p in (lc['problems'] as List).cast<String>()) {
            problems.add('$dev الدفتر المحاسبي: $p');
          }
          final dc = (await h.d(dev).call('deepCheck', const {}, const Duration(minutes: 30)) as Map)
              .cast<String, Object?>();
          if ((dc['errors'] as int) > 0) problems.add('$dev الفحص العميق:\n${dc['text']}');
          print('── $dev الفحص العميق ──\n${dc['text']}');
        }
      }
      for (final e in (await h.deviceErrors()).take(5)) {
        problems.add('خطأ غير ممسوك في التطبيق: ${e.split('\n').take(4).join(' | ')}');
      }

      // ── التقرير ──
      final accepted = stats['حفظ مقبول'] ?? 0;
      final rejected = stats.entries
          .where((e) => e.key.startsWith('رُفض كما يجب') || e.key.startsWith('رفض على حدّ'))
          .fold(0, (a, e) => a + e.value);
      print('══ seed=$seed — $done تعديل مركّب على ${remaining.length} فاتورة ($ops عملية، $temps فاتورة مؤقتة) '
          'و${custs.length} عميلاً على $_devices أجهزة في ${sw.elapsed.inMinutes} دقيقة');
      print('   ${combos.length} تركيبة مختلفة — حفظ مقبول $accepted — رفض صحيح $rejected');
      print('⏱️ أين ذهب الوقت:\n${timingReport()}');
      final keys = stats.keys.toList()..sort();
      for (final k in keys) {
        print('  $k: ${stats[k]}');
      }
      final unseen = [..._mutations, ..._moves.toSet(), _newName, _phone, ..._modifiers]
          .where((s) => !stats.containsKey('تغيير: $s') && !stats.containsKey('طريقة الحفظ: $s'))
          .toList();
      if (unseen.isNotEmpty && !stop()) print('  ⚠️ لم تُجرَّب في هذا التشغيل: ${unseen.join('، ')}');
      flushProblems();
      if (problems.isNotEmpty) {
        print('❌ هنا وقع خطأ — ${problems.length} مشكلة (يتوقف عند $_maxProblems) — seed=$seed:');
        for (final p in problems.take(_maxProblems)) {
          print('  • $p');
        }
        var n = 0;
        for (final c in h.truth.customers.keys) {
          if (n >= 2) break;
          final name = names[c] ?? h.truth.customers[c]!.name;
          if (problems.any((p) => p.contains(name))) {
            print(await h.explain(c));
            n++;
          }
        }
      } else {
        print('✅ لا مشكلة واحدة — seed=$seed.');
      }
      failed = problems.isNotEmpty;
      live(failed ? 'انتهى — هنا وقع خطأ' : 'انتهى — نجح');
      try {
        File(_summaryPath)
          ..createSync(recursive: true)
          ..writeAsStringSync([
            'القرعة: seed=$seed (لإعادته: claude_test_comprehensive.bat full $seed)',
            '$done تعديل مركّب من $totalEdits — ${remaining.length} فاتورة — ${custs.length} عميلاً — '
                '$_devices أجهزة — $ops عملية — ${sw.elapsed.inMinutes} دقيقة',
            '${combos.length} تركيبة مختلفة — حفظ مقبول $accepted — رفض صحيح $rejected — $temps فاتورة مؤقتة',
            'أين ذهب الوقت:',
            timingReport(),
            failed ? 'النتيجة: هنا وقع خطأ — ${problems.length} مشكلة:' : 'النتيجة: نجح — لا مشكلة واحدة',
            for (final p in problems.take(_maxProblems)) '  - ${p.split('\n').first}',
          ].join('\r\n'));
      } catch (_) {}
      expect(problems, isEmpty);
    } finally {
      await h.dispose(keepFiles: failed);
    }
  }, timeout: const Timeout(Duration(hours: 40)));
}
