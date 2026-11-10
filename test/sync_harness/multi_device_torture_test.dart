// test/sync_harness/multi_device_torture_test.dart
//
// 🌪️ تعذيب متعدد الأجهزة — على كود التطبيق الحقيقي (كاختبار التعذيب: InvoiceController،
// CustomerMoney، AppProvider، المرتجع، المزامنة FirebaseSyncService/InvoiceSyncService)
// لكن بلا ترتيب: كل عملية قرعة (أي جهاز، أي عميل، أي فاتورة، أي فعل):
//   • 4 أجهزة، 25 عميلاً، 70,000 عملية (افتراضياً).
//   • فاتورة جديدة، تعديل بأي سيناريو، تعليق/استكمال/حذف، مرتجع، وصل قبض، دين يدوي،
//     محاولة تعديل فاتورة جهاز آخر، تغيير اسم العميل من بطاقته، إعادة تشغيل مفاجئة،
//     جهاز يُقطع عنه الإنترنت ويعمل وحده ثم يعود، ومزامنة في أوقات عشوائية.
//   • بعد كل عملية: الفاتورة على جهازها = الحقيقة، ودين العميل بالفلس — على الجهاز الذي
//     يعرف كل ما جرى لهذا العميل (ما لم يغيّره جهاز آخر لم يُزامَن بعد).
//   • بعد كل مزامنة: كل عميل على كل جهاز (الدين، مجموع المعاملات، الاسم)، وعيّنة فواتير
//     على كل جهاز، والمخزون — بالفلس. وفي النهاية: الدفتر المحاسبي والفحص العميق.
//
//   سريع (~20 دقيقة):  flutter test test/sync_harness/multi_device_torture_test.dart --dart-define=QUICK=true
//   كامل:              flutter test test/sync_harness/multi_device_torture_test.dart
//   قرعة محددة لإعادة خطأ بالضبط: --dart-define=SEED=123456
//   أرقام أخرى: --dart-define=DEVICES=3 --dart-define=CUSTOMERS=40 --dart-define=OPS=137000
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _quick = bool.fromEnvironment('QUICK', defaultValue: false);
const _devices = int.fromEnvironment('DEVICES', defaultValue: 4);
const _customers = int.fromEnvironment('CUSTOMERS', defaultValue: _quick ? 12 : 25);
const _ops = int.fromEnvironment('OPS', defaultValue: _quick ? 3000 : 70000);
const _seedArg = int.fromEnvironment('SEED', defaultValue: 0); // 0 = قرعة جديدة كل تشغيل
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 15);

/// 📊 عداد حي: سطر واحد يُكتب هنا ويعرضه claude_test_multi.bat في النافذة وعنوانها.
const _progressPath = 'test_results/multi/progress.txt';

/// 📋 الخلاصة بنص عادي (يعرضها claude_test_multi.bat في آخر النافذة).
const _summaryPath = 'test_results/multi/summary.txt';

String _dur(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  return h > 0 ? '${h}س ${m}د' : '${m}د';
}

/// أنواع معاملات لا تُعدّ من دين الفاتورة (كما في InvoiceDebtReconciler)
const _nonContribution = {'manual_payment', 'return_payment', 'correction', 'opening_balance'};

/// كل ما يمكن فعله بفاتورة من شاشتها. [*] = يجب أن يرفضه التطبيق.
const _scenarios = <String>[
  'أصناف جديدة كلياً', 'إضافة سطر', 'حذف سطر', 'تغيير كمية سطر', 'تغيير سعر سطر',
  'تحويل سطر قطعة↔كرتون', 'كمية كسرية', 'سطر هدية', 'خصم سطر بنسبة', 'خصم سطر بمبلغ',
  'الصنف نفسه في سطرين', 'سطر بلا كمية [*]', 'بند يدوي فقط بلا أصناف',
  'خصم على الفاتورة', 'خصم ≥ الإجمالي [*]', 'خصم سالب [*]', 'أجور تحميل', 'أجور تحميل سالبة [*]',
  'خصم وتحميل معاً', 'كسور الدينار', 'فاتورة ضخمة', 'فاتورة صغيرة جداً',
  'إلى نقد', 'إلى دين', 'تسديد جزئي', 'تسديد كامل', 'إلغاء التسديد', 'مسدد > الإجمالي [*]',
  'مسدد سالب [*]', 'نقد بمسدد ناقص [*]', 'تصغير تحت المسدد [*]',
  'تغيير العميل', 'اسم العميل بمسافات زائدة', 'اسم عميل جديد', 'اسم فارغ [*]',
  'هاتف مختلف على الفاتورة', 'هاتف لعميل بلا هاتف',
  'تاريخ سابق', 'تعديل داخل فترة مثبّتة [*]',
  'حفظ بلا تغيير', 'حفظ مرتين متتاليتين', 'تعليق فاتورة محفوظة [*]',
];

const _heldScenarios = ['تعديل وهي معلّقة', 'استكمال المعلّقة', 'حذف المعلّقة'];

class _Inv {
  _Inv(this.dev, this.cust, this.date);
  final String dev;
  String cust;
  DateTime date;
  List<Map<String, Object?>> specs = [];
  double extra = 0;
  double discount = 0;
  double fee = 0;
  String ptype = 'دين';
  double paid = 0;
  bool held = false;
  bool deleted = false;
  bool returned = false;
  String? nameField;
  String? phoneField;
  bool incomplete = false;

  /// مبلغ كل سطر بالفلس كما يحفظه التطبيق (InvoiceItem.itemTotalCents).
  double get itemsTotal =>
      specs.fold(0.0, (s, x) => s + ((x['qty'] as double) * _applied(x) * 100).round() / 100) + extra;
  double get finalTotal => itemsTotal + fee - discount;

  _Inv copy() => _Inv(dev, cust, date)
    ..specs = [for (final s in specs) Map<String, Object?>.from(s)]
    ..extra = extra
    ..discount = discount
    ..fee = fee
    ..ptype = ptype
    ..paid = paid
    ..held = held
    ..returned = returned;
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
  test(
      'تعذيب متعدد الأجهزة: $_devices أجهزة × $_customers عميلاً × $_ops عملية بقرعة seed=$seed', () async {
    print('🎲 القرعة: seed=$seed — لإعادة هذا التشغيل بالضبط: --dart-define=SEED=$seed');
    final h = Harness(seed: seed);
    final rnd = Random(seed * 7919 + 3);
    final problems = <String>[];
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    var failed = true;
    var ops = 0;
    final sw = Stopwatch()..start();
    final devs = [for (var i = 1; i <= _devices; i++) 'D$i'];

    double r2(double v) => (v * 100).roundToDouble() / 100;
    void near(String what, Object? got, double want) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() >= 0.005) problems.add('$what = $g والمتوقع ${r2(want)}');
    }

    bool stop() => problems.length >= _maxProblems;

    final loopWatch = Stopwatch(); // يبدأ مع العمليات بالقرعة (التجهيز لا يُحسب في التقدير)
    void live(String phase) {
      final pct = (ops * 100 / _ops).clamp(0, 100).toStringAsFixed(1);
      final done = loopWatch.elapsed.inSeconds;
      final eta = ops > 0 ? (done * (_ops - ops) / ops).round() : null;
      final line = '$pct% — $ops/$_ops عملية — مضى ${_dur(sw.elapsed.inSeconds)}'
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

      // ── من يعرف ماذا (حتى المزامنة التالية) ──
      // dirty[عميل] = الأجهزة التي غيّرت رصيده منذ آخر مزامنة؛ جهاز لا يرى إلا ما فعله هو.
      final dirty = <String, Set<String>>{};
      void touch(String dev, String cust) => dirty.putIfAbsent(cust, () => <String>{}).add(dev);
      bool knowsAll(String dev, String cust) => (dirty[cust] ?? const <String>{}).every((d) => d == dev);
      // عميل أُنشئ على جهاز ولم يُزامَن بعد: لا يعرفه غيره
      final homeOnly = <String, String>{};
      bool known(String dev, String cust) => homeOnly[cust] == null || homeOnly[cust] == dev;
      // اسم العميل: الحقيقة، وتغيير لم يُزامَن بعد (الجهاز، الاسم القديم)
      final names = <String, String>{};
      final pendingRename = <String, (String, String)>{};
      String nameOn(String dev, String cust) {
        final p = pendingRename[cust];
        return (p != null && p.$1 != dev) ? p.$2 : names[cust]!;
      }

      var renames = 0;

      // ── العملاء والأصناف: كل عميل يُنشأ على جهاز بالقرعة ──
      final custs = <String>[];
      for (var k = 0; k < _customers; k++) {
        final name = 'زبون متعدد ${k + 1}';
        final dev = devs[rnd.nextInt(devs.length)];
        final c = await h.addCustomer(dev, name, phone: k.isEven ? '0770987650$k' : null);
        if (c != null) {
          custs.add(c);
          names[c] = name;
        }
      }
      const catalog = [('برغي متعدد', 250.0, 12), ('أنبوب متعدد', 1750.5, null), ('صمام متعدد', 4000.0, 6)];
      final prods = <(String, double, int?)>[];
      for (final (name, price, carton) in catalog) {
        final u = await h.addProduct('D1', name, 100000000, carton: carton);
        if (u != null) prods.add((u, price, carton));
      }
      var errs = await h.settle();
      expect(errs, isEmpty, reason: errs.join('\n'));
      expect(custs.length, _customers);
      final pipe = prods.firstWhere((p) => p.$3 == null).$1;

      final state = <String, _Inv>{};
      var newCustomers = 0;

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

      /// رفض مشروع: الحفظ يُنقص رصيد العميل القديم تحت الصفر (كما في InvoiceController)
      bool wouldGoNegative(String? inv, _Inv x) {
        final t = inv == null ? null : h.truth.invoices[inv];
        final oldC = t?.contribution ?? 0.0;
        final newC = x.ptype == 'دين' ? max(0.0, x.finalTotal - x.paid) : 0.0;
        final moves = t != null && (t.cust != x.cust || (x.nameField?.contains('عميل جديد') ?? false));
        final delta = (x.ptype == 'نقد' || moves) ? -oldC : newC - oldC;
        final base = t?.cust ?? x.cust;
        return delta < -0.01 && h.truth.balance(base) + delta < -0.01;
      }

      Future<Map<String, Object?>> custBalance(String dev, String cust) async =>
          ((await h.d(dev).call('custBalance', {'cust': cust}) as Map?) ?? const {}).cast<String, Object?>();

      /// دين العميل على [dev] — فقط إن كان [dev] يعرف كل ما جرى له منذ آخر مزامنة.
      Future<void> verifyCust(String dev, String cust, String label) async {
        if (!known(dev, cust)) return;
        if (!knowsAll(dev, cust)) {
          count('فحص مؤجَّل حتى المزامنة');
          return;
        }
        final b = await custBalance(dev, cust);
        final want = h.truth.balance(cust);
        near('$label: دين ${names[cust]} المخزّن على $dev', b['debt'], want);
        near('$label: مجموع معاملات ${names[cust]} على $dev', b['sum'], want);
      }

      Future<void> verifyInvoice(String inv, String label, {String? on}) async {
        final t = h.truth.invoices[inv]!;
        final dev = on ?? state[inv]!.dev;
        final r = (await h.d(dev).call('invoiceDetail', {'inv': inv}) as Map?)?.cast<String, Object?>();
        if (r == null) {
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
          if (i['cust_uuid'] != t.cust) problems.add('$label/$dev: العميل ${i['cust_uuid']} والصحيح ${t.cust}');
        }
        final txs = (r['txs'] as List).cast<Map>().where((x) =>
            ((x['del'] as int?) ?? 0) == 0 && !_nonContribution.contains(x['type']));
        final mine = txs.where((x) => x['cust'] == t.cust).fold(0.0, (s, x) => s + (x['amount'] as num).toDouble());
        final others = txs.where((x) => x['cust'] != t.cust).fold(0.0, (s, x) => s + (x['amount'] as num).toDouble());
        near('$label/$dev دين الفاتورة في سجل الديون', mine, t.contribution);
        near('$label/$dev أثرها على عملاء آخرين', others, 0);
      }

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

      Future<String?> save(String? inv, _Inv x, String label,
          {String? dev, bool locked = false, bool policyMayReject = false}) async {
        final on = dev ?? x.dev;
        final reason = invalidReason(x, foreign: on != x.dev, locked: locked);
        final oldCust = inv == null ? null : h.truth.invoices[inv]?.cust;
        // الجهاز لا يرى ما لم يُزامَن من غيره: رصيده المحلي قد يختلف عن الحقيقة فيقبل أو
        // يرفض «الرصيد السالب» بحسب ما يعرفه هو — كلاهما مقبول هنا.
        final localOnly = !knowsAll(on, oldCust ?? x.cust) || !knowsAll(on, x.cust);
        Map<String, Object?> r;
        try {
          r = (await h.d(on).call('saveInvoice', {
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
          }) as Map)
              .cast<String, Object?>();
        } catch (e) {
          r = {'ok': false, 'err': 'استثناء: ${'$e'.split('\n').first}'};
        }
        if (r['ok'] != true) {
          if (reason != null) {
            count('رُفض كما يجب: $reason');
          } else if (policyMayReject || wouldGoNegative(inv, x) || localOnly) {
            count('رفض مشروع: ${'${r['err']}'.split('\n').first}');
          } else {
            problems.add('$label: رُفض حفظ سليم (${r['err']})');
          }
          return null;
        }
        if (reason != null) {
          problems.add('$label: قُبل حفظ يجب رفضه ($reason) — خصم=${x.discount} مسدد=${x.paid} '
              'إجمالي=${r2(x.finalTotal)} نوع=${x.ptype}');
        }
        final uuid = r['uuid'] as String;
        final savedCust = r['cust'] as String?;
        if (x.nameField != null && x.nameField!.contains('عميل جديد')) {
          if (savedCust == null || custs.contains(savedCust)) {
            problems.add('$label: اسم عميل جديد لم يُنشئ حساباً جديداً (${r['cust']})');
          } else {
            h.truth.customers[savedCust] = TruthCustomer(x.nameField!, on);
            names[savedCust] = x.nameField!;
            custs.add(savedCust);
            homeOnly[savedCust] = on;
            x.cust = savedCust;
          }
        } else if (savedCust != x.cust) {
          problems.add('$label: حُفظت على عميل آخر ${names[savedCust] ?? savedCust} بدل ${names[x.cust]}');
        }
        final savedPaid = (r['paid'] as num?)?.toDouble() ?? x.paid;
        if ((savedPaid - x.paid).abs() > 0.01) problems.add('$label: غيّر التطبيق المسدد بصمت: ${x.paid} ← $savedPaid');
        record(uuid, x, 'محفوظة');
        touch(on, x.cust);
        if (oldCust != null) touch(on, oldCust);
        count(inv == null ? 'فاتورة جديدة' : 'تعديل مقبول');
        return uuid;
      }

      Future<String?> hold(String? inv, _Inv x, String label, {bool expectOk = true}) async {
        final r = (await h.d(x.dev).call('holdInvoice', {
          'inv': inv,
          'cust': x.cust,
          'total': x.itemsTotal,
          'items': x.specs,
          'ptype': x.ptype,
          'discount': x.discount,
          'loadingFee': x.fee,
          'paid': x.paid,
        }) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          if (expectOk) problems.add('$label: رُفض التعليق (${r['err']})');
          if (!expectOk) count('رُفض كما يجب: تعليق فاتورة محفوظة');
          return null;
        }
        if (!expectOk) problems.add('$label: عُلّقت فاتورة محفوظة (يجب رفضه)');
        final uuid = r['uuid'] as String;
        record(uuid, x, 'معلقة');
        touch(x.dev, x.cust);
        count('تعليق');
        return uuid;
      }

      /// عملاء يعرفهم [dev] الآن
      List<String> knownCusts(String dev) => custs.where((c) => known(dev, c) && h.truth.visible(c)).toList();

      _Inv mutate(_Inv cur, String sc) {
        final x = cur.copy();
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

        Map<String, Object?>? pieceLine() {
          final l = x.specs.where((s) => s['large'] != true && s['gift'] != true).toList();
          return l.isEmpty ? null : l[rnd.nextInt(l.length)];
        }

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
              s['price'] = r2((s['price'] as double) * [0.5, 1.1, 2.0][rnd.nextInt(3)]);
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
          case 'خصم على الفاتورة':
            x.discount = r2(x.itemsTotal * [0.0, 0.01, 0.05, 0.2][rnd.nextInt(4)]);
          case 'خصم ≥ الإجمالي [*]':
            x.discount = r2(x.itemsTotal) + 1;
          case 'خصم سالب [*]':
            x.discount = -250;
          case 'أجور تحميل':
            x.fee = [0.0, 1000.0, 2500.0, 15000.0][rnd.nextInt(4)];
          case 'أجور تحميل سالبة [*]':
            x.fee = -1000;
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
          case 'إلغاء التسديد':
            if (x.ptype == 'دين') x.paid = 0;
          case 'مسدد > الإجمالي [*]':
            x.ptype = 'دين';
            ensureMoney();
            keepDiscount();
            x.paid = r2(x.finalTotal + 500);
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
          case 'تغيير العميل':
            {
              final others = knownCusts(x.dev).where((c) => c != x.cust).toList();
              if (others.isNotEmpty) x.cust = others[rnd.nextInt(others.length)];
            }
          case 'اسم العميل بمسافات زائدة':
            {
              final n = nameOn(x.dev, x.cust);
              x.nameField = '  ${n.replaceFirst(' ', '   ')} ';
            }
          case 'اسم عميل جديد':
            x.nameField = 'عميل جديد متعدد ${++newCustomers}';
          case 'اسم فارغ [*]':
            x.nameField = '   ';
          case 'هاتف مختلف على الفاتورة':
          case 'هاتف لعميل بلا هاتف':
            x.phoneField = '07809${100000 + rnd.nextInt(899999)}';
          case 'تاريخ سابق':
            x.date = x.date.subtract(Duration(days: 1 + rnd.nextInt(40)));
          default:
            break;
        }
        if (!sc.contains('[*]')) {
          ensureMoney();
          keepDiscount();
          keepPaid();
        }
        return x;
      }

      // ─────────────────────────── الأفعال ───────────────────────────

      Future<String?> create(String dev, String label) async {
        final cs = knownCusts(dev);
        if (cs.isEmpty) return null;
        final x = _Inv(dev, cs[rnd.nextInt(cs.length)], DateTime.now())
          ..specs = randomSpecs()
          ..ptype = rnd.nextInt(3) < 2 ? 'دين' : 'نقد';
        x.extra = randomExtra(positive: x.specs.isEmpty);
        x.paid = x.ptype == 'نقد' ? x.finalTotal : (rnd.nextBool() ? 0 : r2(x.finalTotal * 0.3));
        final u = rnd.nextDouble() < 0.08 ? await hold(null, x, label) : await save(null, x, label);
        if (u != null) {
          await verifyInvoice(u, label);
          await verifyCust(dev, x.cust, label);
        }
        return u;
      }

      Future<void> editInvoice(String inv, String label) async {
        final cur = state[inv]!;
        final dev = cur.dev;
        final oldCust = cur.cust;
        if (cur.held) {
          final sc = _heldScenarios[rnd.nextInt(_heldScenarios.length)];
          count('سيناريو: $sc');
          if (sc == 'تعديل وهي معلّقة') {
            await hold(inv, mutate(cur, 'أصناف جديدة كلياً'), '$label [$sc]');
          } else if (sc == 'استكمال المعلّقة') {
            await save(inv, mutate(cur, 'حفظ بلا تغيير'), '$label [$sc]');
          } else {
            await h.d(dev).call('discardHeld', {'inv': inv});
            h.truth.invoices[inv]!.status = 'محذوفة';
            cur.deleted = true;
            touch(dev, cur.cust);
          }
          await verifyInvoice(inv, '$label [$sc]');
          await verifyCust(dev, cur.cust, '$label [$sc]');
          return;
        }
        final sc = _scenarios[rnd.nextInt(_scenarios.length)];
        count('سيناريو: $sc');
        final x = mutate(cur, sc);
        if (sc == 'تعليق فاتورة محفوظة [*]') {
          await hold(inv, x, '$label [$sc]', expectOk: false);
        } else if (sc == 'تعديل داخل فترة مثبّتة [*]') {
          final tomorrow = DateTime.now().add(const Duration(days: 1));
          await h.d(dev).call('setLock', {'date': DateTime(tomorrow.year, tomorrow.month, tomorrow.day).toIso8601String()});
          try {
            await save(inv, x, '$label [$sc]', locked: true);
          } finally {
            await h.d(dev).call('setLock', {'date': null});
          }
        } else {
          await save(inv, x, '$label [$sc]', policyMayReject: sc == 'فاتورة ضخمة' || cur.returned);
          if (sc == 'حفظ مرتين متتاليتين') {
            await save(inv, state[inv]!.copy(), '$label [$sc — الثانية]');
          }
        }
        await verifyInvoice(inv, '$label [$sc]');
        await verifyCust(dev, oldCust, '$label [$sc]');
        if (state[inv]!.cust != oldCust) await verifyCust(dev, state[inv]!.cust, '$label [$sc]');
      }

      Future<void> receipt(String dev, String label) async {
        final cs = knownCusts(dev);
        if (cs.isEmpty) return;
        final c = cs[rnd.nextInt(cs.length)];
        if (!knowsAll(dev, c)) return; // لا يُسدَّد ما لا يعرف الجهاز رصيده الآن
        final bal = h.truth.balance(c);
        if (bal > 1000) {
          final amount = (bal * [0.1, 0.4, 1.0][rnd.nextInt(3)] / 250).floorToDouble() * 250;
          if (amount <= 0) return;
          final u = await h.d(dev).call('receipt', {'cust': c, 'amount': amount, 'marker': 'M$ops'}) as String?;
          if (u != null) {
            h.truth.txs[u] = TruthTx(c, dev, -amount, 'manual_payment');
            touch(dev, c);
            count('وصل قبض');
          } else {
            count('وصل لم يُحفظ');
          }
        }
        await verifyCust(dev, c, '$label (وصل)');
      }

      Future<void> manualDebt(String dev, String label) async {
        final cs = knownCusts(dev);
        if (cs.isEmpty) return;
        final c = cs[rnd.nextInt(cs.length)];
        await h.addTx(dev, c, [5000.0, 1250.75, 0.25][rnd.nextInt(3)]);
        touch(dev, c);
        count('دين يدوي');
        await verifyCust(dev, c, '$label (دين يدوي)');
      }

      Future<void> salesReturn(String inv, String label) async {
        final cur = state[inv]!;
        final dev = cur.dev;
        final line = cur.specs.where((s) => s['prod'] == pipe && s['gift'] != true && (s['qty'] as double) >= 1);
        if (cur.held || cur.returned || cur.ptype != 'دين' || line.isEmpty) return;
        if (!knowsAll(dev, cur.cust)) return;
        final price = _applied(line.first);
        if (h.truth.balance(cur.cust) <= price + 1) return;
        final r = (await h.d(dev).call('salesReturn', {
          'inv': inv,
          'cust': cur.cust,
          'items': [
            {'prod': pipe, 'qty': 1.0, 'price': price}
          ],
          'mode': 'credit',
        }) as Map)
            .cast<String, Object?>();
        if (r['ok'] == true) {
          var sum = 0.0;
          for (final t in (r['txs'] as List).cast<List>()) {
            h.truth.txs[t[0] as String] = TruthTx(cur.cust, dev, (t[1] as num).toDouble(), 'manual_payment');
            sum += (t[1] as num).toDouble();
          }
          near('$label (مرتجع على الحساب) أثره على الدين', sum, -price);
          h.truth.products[pipe]!.movements += 1;
          cur.returned = true;
          touch(dev, cur.cust);
          count('مرتجع على الحساب');
        } else {
          problems.add('$label: رُفض مرتجع سليم (${r['err']})');
        }
        await verifyInvoice(inv, '$label (مرتجع)');
        await verifyCust(dev, cur.cust, '$label (مرتجع)');
      }

      Future<void> foreignEdit(String dev, String label) async {
        final other = state.entries
            .where((e) => e.value.dev != dev && !e.value.deleted && !e.value.held && known(dev, e.value.cust))
            .map((e) => e.key)
            .toList();
        if (other.isEmpty) return;
        final o = other[rnd.nextInt(other.length)];
        // الفاتورة يجب أن تكون قد وصلت هذا الجهاز: لا تُجرَّب إلا بعد مزامنة
        final r = await h.d(dev).call('invoiceDetail', {'inv': o});
        if (r == null) return;
        final x = mutate(state[o]!, 'أجور تحميل')..fee = 777;
        await save(o, x, '$label (فاتورة جهاز آخر)', dev: dev);
        count('محاولة تعديل فاتورة جهاز آخر');
      }

      /// تغيير اسم العميل من بطاقته. قاعدة المالك (customer_owner_rule.dart): الجهاز الذي
      /// أنشأه فقط — وعلى غيره يجب أن يُرفض ولا يتغير شيء.
      Future<void> renameCustomer(String dev, String label) async {
        final free = knownCusts(dev).where((c) => !pendingRename.containsKey(c) && homeOnly[c] == null);
        final owned = free.where((c) => h.truth.customers[c]!.creator == dev).toList();
        final foreign = free.where((c) => h.truth.customers[c]!.creator != dev).toList();
        if (foreign.isNotEmpty && (owned.isEmpty || rnd.nextDouble() < 0.3)) {
          final c = foreign[rnd.nextInt(foreign.length)];
          final r = (await h.d(dev).call('renameCustomer', {'cust': c, 'name': 'اسم ممنوع ${++renames}'}) as Map)
              .cast<String, Object?>();
          if (r['ok'] == true) {
            problems.add('$label: غيّر $dev اسم ${names[c]} وأنشأه ${h.truth.customers[c]!.creator} (يجب رفضه)');
          } else {
            count('رُفض كما يجب: تغيير اسم عميل جهاز آخر');
          }
          final b = await custBalance(dev, c);
          if (b['name'] != nameOn(dev, c)) problems.add('$label: تغيّر الاسم على $dev رغم الرفض: ${b['name']}');
          return;
        }
        if (owned.isEmpty) return;
        final c = owned[rnd.nextInt(owned.length)];
        final old = names[c]!;
        final nn = 'زبون معدَّل ${++renames}';
        final r = (await h.d(dev).call('renameCustomer', {'cust': c, 'name': nn}) as Map).cast<String, Object?>();
        if (r['ok'] != true) {
          problems.add('$label: رُفض تغيير اسم ${names[c]} إلى $nn على جهازه (${r['err']})');
          return;
        }
        pendingRename[c] = (dev, old);
        names[c] = nn;
        count('تغيير اسم عميل');
        final b = await custBalance(dev, c);
        if (b['name'] != nn) problems.add('$label: الاسم على $dev بعد التغيير ${b['name']} والصحيح $nn');
        await verifyCust(dev, c, '$label (تغيير اسم)');
      }

      Future<void> deleteInvoice(String inv, String label) async {
        final cur = state[inv]!;
        if (cur.held) return;
        final r = (await h.d(cur.dev).call('deleteInvoice', {'inv': inv}) as Map).cast<String, Object?>();
        if (r['ok'] == true) {
          h.truth.invoices[inv]!.status = 'محذوفة';
          cur.deleted = true;
          touch(cur.dev, cur.cust);
          count('حذف فاتورة');
        } else {
          count('رفض حذف: ${'${r['err']}'.split('\n').first}');
        }
        await verifyInvoice(inv, '$label (حذف)');
        await verifyCust(cur.dev, cur.cust, '$label (حذف)');
      }

      /// مزامنة كاملة ثم فحص كل عميل على كل جهاز وعيّنة فواتير على كل جهاز.
      Future<void> syncAndCheck(String label) async {
        final e = await h.settle();
        problems.addAll(e.map((x) => '$label: $x'));
        dirty.clear();
        homeOnly.clear();
        pendingRename.clear();
        for (final dev in devs) {
          for (final c in custs) {
            if (stop()) return;
            if (!h.truth.visible(c)) continue;
            final b = await custBalance(dev, c);
            final want = h.truth.balance(c);
            near('$label: دين ${names[c]} على $dev', b['debt'], want);
            near('$label: مجموع معاملات ${names[c]} على $dev', b['sum'], want);
            if (b['name'] != names[c]) problems.add('$label: اسم العميل على $dev «${b['name']}» والصحيح «${names[c]}»');
          }
        }
        final live = state.keys.where((k) => !state[k]!.deleted).toList()..shuffle(rnd);
        for (final inv in live.take(60)) {
          for (final dev in devs) {
            if (stop()) return;
            await verifyInvoice(inv, '$label (عيّنة)', on: dev);
          }
        }
        count('جولة مزامنة');
      }

      live('فواتير البداية…');
      // ── البداية: 15 فاتورة على كل جهاز ──
      for (final dev in devs) {
        for (var k = 0; k < 15 && !stop(); k++) {
          await create(dev, 'بداية $dev #${k + 1}');
        }
      }
      await syncAndCheck('بعد فواتير البداية');

      // ── العمليات بالقرعة ──
      var sinceSync = 0;
      final offline = <String>{};
      loopWatch.start();
      while (ops < _ops && !stop()) {
        ops++;
        sinceSync++;
        final dev = devs[rnd.nextInt(devs.length)];
        final label = 'عملية $ops على $dev';
        final mine = state.entries.where((e) => e.value.dev == dev && !e.value.deleted).map((e) => e.key).toList();
        final roll = rnd.nextDouble();
        if (roll < 0.10 || mine.isEmpty) {
          await create(dev, '$label (فاتورة جديدة)');
        } else if (roll < 0.16) {
          await receipt(dev, label);
        } else if (roll < 0.20) {
          await manualDebt(dev, label);
        } else if (roll < 0.215) {
          await salesReturn(mine[rnd.nextInt(mine.length)], label);
        } else if (roll < 0.23) {
          await foreignEdit(dev, label);
        } else if (roll < 0.24) {
          await renameCustomer(dev, label);
        } else if (roll < 0.242) {
          await deleteInvoice(mine[rnd.nextInt(mine.length)], label);
        } else if (roll < 0.2435 && !offline.contains(dev)) {
          await h.restart(dev);
          count('إعادة تشغيل مفاجئة');
          for (final inv in mine.take(3)) {
            await verifyInvoice(inv, '$label (بعد إعادة التشغيل)');
          }
        } else if (roll < 0.2465) {
          // يُقطع الإنترنت عن جهاز (أو يعود) — يعمل وحده حتى المزامنة التالية
          if (offline.remove(dev)) {
            await h.setOnline(dev, true);
            count('عاد الإنترنت');
          } else if (offline.length < devs.length - 1) {
            offline.add(dev);
            await h.setOnline(dev, false);
            count('انقطع الإنترنت');
          }
        } else {
          await editInvoice(mine[rnd.nextInt(mine.length)], label);
        }
        // مزامنة في وقت عشوائي (ونادراً ما تتأخر أكثر من 800 عملية)
        if (ops % 25 == 0) live('عمليات بالقرعة');
        if (rnd.nextDouble() < 1 / 350 || sinceSync >= 800) {
          offline.clear(); // settle يعيد الكل متصلاً
          live('مزامنة وفحص كل الأجهزة…');
          await syncAndCheck('مزامنة بعد العملية $ops');
          sinceSync = 0;
        }
        if (ops % 1000 == 0) {
          final s = sw.elapsed.inSeconds;
          final eta = (s * (_ops - ops) / ops).round();
          print('… $ops/$_ops عملية — ${s ~/ 60}د — المتبقي ≈ ${eta ~/ 60}د — فواتير=${state.length} '
              'عملاء=${custs.length} — مشاكل=${problems.length}');
        }
      }

      // ── النهاية ──
      live('المزامنة والفحص النهائي…');
      if (!stop()) {
        await syncAndCheck('المزامنة النهائية');
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

      print('══ seed=$seed — $ops عملية على ${state.length} فاتورة و${custs.length} عميلاً '
          'و${devs.length} أجهزة في ${sw.elapsed.inMinutes} دقيقة');
      final keys = stats.keys.toList()..sort();
      for (final k in keys) {
        print('  $k: ${stats[k]}');
      }
      final unseen = _scenarios.where((s) => !stats.containsKey('سيناريو: $s')).toList();
      if (unseen.isNotEmpty && !stop()) print('  ⚠️ سيناريوهات لم تُجرَّب: ${unseen.join('، ')}');
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
            'القرعة: seed=$seed (لإعادته: claude_test_multi.bat full $seed)',
            '$ops عملية من $_ops — ${state.length} فاتورة — ${custs.length} عميلاً — ${devs.length} أجهزة — ${sw.elapsed.inMinutes} دقيقة',
            failed ? 'النتيجة: هنا وقع خطأ — ${problems.length} مشكلة:' : 'النتيجة: نجح — لا مشكلة واحدة',
            for (final p in problems.take(_maxProblems)) '  - ${p.split('\n').first}',
          ].join('\r\n'));
      } catch (_) {}
      expect(problems, isEmpty);
    } finally {
      await h.dispose(keepFiles: failed);
    }
  }, timeout: const Timeout(Duration(hours: 30)));
}
