// test/sync_harness/invoice_torture_test.dart
//
// 🔨 اختبار التعذيب — على كود التطبيق الحقيقي، لا على نسخة منه:
//   • الحفظ: InvoiceController (validateInvoiceData ثم validateDebtChange ثم
//     saveInvoice) بنفس InvoiceInputData الذي تبنيه شاشة الفاتورة.
//   • التعليق والاستكمال والحذف: HeldInvoices.hold / discard، DatabaseService.deleteInvoice.
//   • الوصولات: CustomerMoney.post. الدين اليدوي: AppProvider.addTransaction.
//   • المرتجع: SalesReturnService.create. التثبيت: PeriodLock.
//   • المزامنة: FirebaseSyncService/InvoiceSyncService على سحابة وهمية بين جهازين.
//
// الحجم الافتراضي (طلب المالك):
//   5 عملاء؛ لكل عميل 100 فاتورة على هذا الجهاز (D1) و100 تصل بالمزامنة (من D2)؛
//   كل فاتورة على D1 تُعدَّل 250 مرة، وكل فاتورة على D2 تُعدَّل 25 مرة ويصل
//   تعديلها بالمزامنة. ≈ 125,000 + 12,500 عملية — ساعات (شغّله ليلاً).
//
// بعد كل عملية: الفاتورة في قاعدة جهازها = نموذج «الحقيقة» المستقل، ودينها في
// سجل الديون = المتبقي عليها، ولا أثر لها على عميل آخر، ودين العميل المخزّن =
// مجموع معاملاته = الحقيقة. الحفظ المرفوض لا يغيّر شيئاً. بعد كل جولة مزامنة:
// الجهازان متطابقان مع الحقيقة (العملاء، الفواتير، المخزون). في النهاية: الدفتر
// المحاسبي والفحص العميق على الجهازين.
//
//   تشغيل سريع:  flutter test test/sync_harness/invoice_torture_test.dart --dart-define=QUICK=true
//   التشغيل الكامل: flutter test test/sync_harness/invoice_torture_test.dart
//   أرقام أخرى: --dart-define=CUSTOMERS=4 --dart-define=LOCAL=50 --dart-define=LOCAL_EDITS=100 --dart-define=SEED=7
//
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _quick = bool.fromEnvironment('QUICK', defaultValue: false);
const _customers = int.fromEnvironment('CUSTOMERS', defaultValue: _quick ? 3 : 5);
const _localPer = int.fromEnvironment('LOCAL', defaultValue: _quick ? 4 : 100);
const _syncedPer = int.fromEnvironment('SYNCED', defaultValue: _quick ? 4 : 100);
const _localEdits = int.fromEnvironment('LOCAL_EDITS', defaultValue: _quick ? 30 : 250);
const _syncEdits = int.fromEnvironment('SYNC_EDITS', defaultValue: _quick ? 3 : 25);
const _seed = int.fromEnvironment('SEED', defaultValue: 1);
const _restarts = bool.fromEnvironment('RESTARTS', defaultValue: true);
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 15);

/// أنواع معاملات لا تُعدّ من دين الفاتورة (كما في InvoiceDebtReconciler)
const _nonContribution = {'manual_payment', 'return_payment', 'correction', 'opening_balance'};

/// كل ما يمكن فعله بفاتورة من شاشتها (وما حولها). [*] = يجب أن يرفضه التطبيق.
const _scenarios = <String>[
  // البنود
  'أصناف جديدة كلياً', 'إضافة سطر', 'حذف سطر', 'تغيير كمية سطر', 'تغيير سعر سطر',
  'تحويل سطر قطعة↔كرتون', 'كمية كسرية', 'سطر هدية', 'خصم سطر بنسبة', 'خصم سطر بمبلغ',
  'الصنف نفسه في سطرين', 'سطر بلا كمية [*]', 'بند يدوي فقط بلا أصناف',
  // المجاميع
  'خصم على الفاتورة', 'خصم ≥ الإجمالي [*]', 'خصم سالب [*]', 'أجور تحميل', 'أجور تحميل سالبة [*]',
  'خصم وتحميل معاً', 'كسور الدينار', 'فاتورة ضخمة', 'فاتورة صغيرة جداً',
  // الدفع
  'إلى نقد', 'إلى دين', 'تسديد جزئي', 'تسديد كامل', 'إلغاء التسديد', 'مسدد > الإجمالي [*]',
  'مسدد سالب [*]', 'نقد بمسدد ناقص [*]', 'تصغير تحت المسدد [*]',
  // العميل
  'تغيير العميل', 'اسم العميل بمسافات زائدة', 'اسم عميل جديد', 'اسم فارغ [*]',
  'هاتف مختلف على الفاتورة', 'هاتف لعميل بلا هاتف',
  // التاريخ
  'تاريخ سابق', 'تعديل داخل فترة مثبّتة [*]',
  // دورة الحياة
  'حفظ بلا تغيير', 'حفظ مرتين متتاليتين', 'تعليق فاتورة محفوظة [*]',
];

/// سيناريوهات الفاتورة المعلّقة
const _heldScenarios = ['تعديل وهي معلّقة', 'استكمال المعلّقة', 'حذف المعلّقة'];

class _Inv {
  _Inv(this.dev, this.cust, this.date);
  final String dev;
  String cust;
  DateTime date;
  List<Map<String, Object?>> specs = [];
  double extra = 0; // بند يدوي (صنف اختبار) فوق الأصناف
  double discount = 0;
  double fee = 0;
  String ptype = 'دين';
  double paid = 0;
  bool held = false;
  bool deleted = false;
  bool returned = false;
  // حقول لحفظ واحد فقط
  String? nameField;
  String? phoneField;
  bool incomplete = false;

  /// كما يحفظها التطبيق: مبلغ كل سطر بالفلس (InvoiceItem.itemTotalCents = round(كمية × سعر × 100)).
  /// بلا هذا التقريب يفرق المجموع هنا عن مجموع الأسطر في التطبيق بأجزاء فلس، فيصير
  /// بند الاختبار المكمِّل سالباً (-0.005) ويرفضه التطبيق «ينقص السعر».
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
  test(
      'تعذيب الفواتير: $_customers عملاء × ($_localPer محلية بـ$_localEdits تعديل + '
      '$_syncedPer بالمزامنة بـ$_syncEdits تعديل) seed=$_seed', () async {
    final h = Harness(seed: _seed);
    final rnd = Random(_seed * 7919 + 1);
    final problems = <String>[];
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    var failed = true;
    var ops = 0;
    final sw = Stopwatch()..start();
    final totalOps = _customers * (_localPer * _localEdits + _syncedPer * _syncEdits);

    double r2(double v) => (v * 100).roundToDouble() / 100;
    void near(String what, Object? got, double want) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() > 0.01) problems.add('$what = $g والمتوقع ${r2(want)}');
    }

    bool stop() => problems.length >= _maxProblems;

    try {
      await h.start(2);

      // ── العملاء والأصناف ──
      final custs = <String>[];
      final names = <String, String>{};
      for (var k = 0; k < _customers; k++) {
        final name = 'زبون تعذيب ${k + 1}';
        final c = await h.addCustomer('D1', name, phone: k.isEven ? '0770123450$k' : null);
        if (c != null) {
          custs.add(c);
          names[c] = name;
        }
      }
      // (الاسم، سعر القطعة، كرتون)
      const catalog = [('برغي تعذيب', 250.0, 12), ('أنبوب تعذيب', 1750.5, null), ('صمام تعذيب', 4000.0, 6)];
      final prods = <(String, double, int?)>[];
      for (final (name, price, carton) in catalog) {
        final u = await h.addProduct('D1', name, 100000000, carton: carton);
        if (u != null) prods.add((u, price, carton));
      }
      var errs = await h.settle();
      expect(errs, isEmpty, reason: errs.join('\n'));
      expect(custs.length, _customers);
      final pipe = prods.firstWhere((p) => p.$3 == null).$1; // صنف بالقطعة للمرتجع

      final state = <String, _Inv>{};
      var newCustomers = 0;

      // ── أدوات البنود ──
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
        const extras = [0.0, 500.0, 1250.25, 10000.0, 75000.5, 333.33, 250000.0];
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

      /// لماذا يجب أن يُرفض هذا الحفظ (null = يجب قبوله)
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

      /// رفض مشروع: الحفظ يجعل رصيد عميل سالباً (validateDebtChangeWontCauseNegativeBalance)
      bool wouldGoNegative(String? inv, _Inv x) {
        final t = inv == null ? null : h.truth.invoices[inv];
        final oldC = t?.contribution ?? 0.0;
        final newC = x.ptype == 'دين' ? max(0.0, x.finalTotal - x.paid) : 0.0;
        if (t != null && t.cust != x.cust) {
          return h.truth.balance(t.cust) - oldC < -0.01 || h.truth.balance(x.cust) + newC < -0.01;
        }
        return h.truth.balance(x.cust) - oldC + newC < -0.01;
      }

      Future<Map<String, Object?>> custBalance(String dev, String cust) async =>
          ((await h.d(dev).call('custBalance', {'cust': cust}) as Map?) ?? const {}).cast<String, Object?>();

      Future<void> verifyCust(String dev, String cust, String label) async {
        final b = await custBalance(dev, cust);
        final want = h.truth.balance(cust);
        near('$label: دين ${names[cust] ?? cust} المخزّن على $dev', b['debt'], want);
        near('$label: مجموع معاملات ${names[cust] ?? cust} على $dev', b['sum'], want);
      }

      /// الفاتورة على [on] (افتراضياً جهازها) = الحقيقة، ودينها في سجل الديون صحيح.
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

      /// حفظ بمسار الشاشة على [dev] (افتراضياً جهاز الفاتورة).
      Future<String?> save(String? inv, _Inv x, String label,
          {String? dev, bool locked = false, bool policyMayReject = false}) async {
        final on = dev ?? x.dev;
        final reason = invalidReason(x, foreign: on != x.dev, locked: locked);
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
          } else if (policyMayReject || wouldGoNegative(inv, x)) {
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
            x.cust = savedCust;
          }
        } else if (savedCust != x.cust) {
          problems.add('$label: حُفظت على عميل آخر ${names[savedCust] ?? savedCust} بدل ${names[x.cust]}');
        }
        final savedPaid = (r['paid'] as num?)?.toDouble() ?? x.paid;
        if ((savedPaid - x.paid).abs() > 0.01) problems.add('$label: غيّر التطبيق المسدد بصمت: ${x.paid} ← $savedPaid');
        record(uuid, x, 'محفوظة');
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
        if (!expectOk) {
          problems.add('$label: عُلّقت فاتورة محفوظة (يجب رفضه)');
        }
        final uuid = r['uuid'] as String;
        record(uuid, x, 'معلقة');
        count('تعليق');
        return uuid;
      }

      /// يغيّر نسخة من الفاتورة حسب السيناريو. لا يحفظ.
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
              final others = custs.where((c) => c != x.cust).toList();
              x.cust = others[rnd.nextInt(others.length)];
            }
          case 'اسم العميل بمسافات زائدة':
            if (names[x.cust] != null) x.nameField = '  ${names[x.cust]!.replaceFirst(' ', '   ')} ';
          case 'اسم عميل جديد':
            x.nameField = 'عميل جديد ${++newCustomers}';
          case 'اسم فارغ [*]':
            x.nameField = '   ';
          case 'هاتف مختلف على الفاتورة':
          case 'هاتف لعميل بلا هاتف':
            x.phoneField = '07809${100000 + rnd.nextInt(899999)}';
          case 'تاريخ سابق':
            x.date = x.date.subtract(Duration(days: 1 + rnd.nextInt(40)));
          default:
            break; // حفظ بلا تغيير، حفظ مرتين، التثبيت، تعليق المحفوظة: البيانات كما هي
        }
        // بعد كل تغيير: المسدد والخصم يبقيان منطقيين — إلا في سيناريوهات الرفض [*]
        if (!sc.contains('[*]')) {
          ensureMoney();
          keepDiscount();
          keepPaid();
        }
        return x;
      }

      /// عملية واحدة على فاتورة [inv] بجهازها.
      Future<void> step(String inv, String label) async {
        final cur = state[inv]!;
        final dev = cur.dev;
        final oldCust = cur.cust;
        final roll = rnd.nextDouble();
        ops++;

        // ── عمليات حول الفاتورة ──
        if (roll < 0.03) {
          final c = custs[rnd.nextInt(custs.length)];
          final bal = h.truth.balance(c);
          if (bal > 1000) {
            final amount = (bal * 0.4 / 250).floorToDouble() * 250;
            final u = await h.d(dev).call('receipt', {'cust': c, 'amount': amount, 'marker': 'T$ops'}) as String?;
            if (u != null) {
              h.truth.txs[u] = TruthTx(c, dev, -amount, 'manual_payment');
              count('وصل قبض');
            }
          }
          await verifyCust(dev, c, '$label (وصل)');
          return;
        }
        if (roll < 0.05) {
          final c = custs[rnd.nextInt(custs.length)];
          await h.addTx(dev, c, [5000.0, 1250.75][rnd.nextInt(2)]);
          count('دين يدوي');
          await verifyCust(dev, c, '$label (دين يدوي)');
          return;
        }
        if (roll < 0.065 && !cur.held && !cur.returned && cur.ptype == 'دين') {
          // مرتجع على الحساب من الفاتورة (قطعة واحدة من سطر أنبوب)
          final line = cur.specs.where((s) => s['prod'] == pipe && s['gift'] != true && (s['qty'] as double) >= 1);
          if (line.isNotEmpty && h.truth.balance(cur.cust) > _applied(line.first) + 1) {
            final price = _applied(line.first);
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
              count('مرتجع على الحساب');
            } else {
              problems.add('$label: رُفض مرتجع سليم (${r['err']})');
            }
            await verifyInvoice(inv, '$label (مرتجع)');
            await verifyCust(dev, cur.cust, '$label (مرتجع)');
            return;
          }
        }
        if (roll < 0.07) {
          // تعديل فاتورة الجهاز الآخر من هذا الجهاز ⇒ يجب أن يُرفض
          final other = state.entries
              .where((e) => e.value.dev != dev && !e.value.deleted && !e.value.held)
              .map((e) => e.key)
              .toList();
          if (other.isNotEmpty) {
            final o = other[rnd.nextInt(other.length)];
            final x = mutate(state[o]!, 'أجور تحميل')..fee = 777;
            await save(o, x, '$label (فاتورة جهاز آخر)', dev: dev);
            await verifyInvoice(o, '$label (فاتورة جهاز آخر)', on: dev);
            count('محاولة تعديل فاتورة جهاز آخر');
            return;
          }
        }
        if (roll < 0.0705 && _restarts) {
          await h.restart(dev);
          count('إعادة تشغيل مفاجئة');
          await verifyInvoice(inv, '$label (بعد إعادة التشغيل)');
          await verifyCust(dev, cur.cust, '$label (بعد إعادة التشغيل)');
          return;
        }
        if (roll < 0.0708 && !cur.held) {
          final r = (await h.d(dev).call('deleteInvoice', {'inv': inv}) as Map).cast<String, Object?>();
          if (r['ok'] == true) {
            h.truth.invoices[inv]!.status = 'محذوفة';
            cur.deleted = true;
            count('حذف فاتورة');
          } else {
            count('رفض حذف: ${'${r['err']}'.split('\n').first}');
          }
          await verifyInvoice(inv, '$label (حذف)');
          await verifyCust(dev, cur.cust, '$label (حذف)');
          return;
        }

        // ── فاتورة معلّقة ──
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
          }
          await verifyInvoice(inv, '$label [$sc]');
          await verifyCust(dev, cur.cust, '$label [$sc]');
          return;
        }

        // ── تعديل من شاشة الفاتورة ──
        final sc = _scenarios[rnd.nextInt(_scenarios.length)];
        count('سيناريو: $sc');
        final x = mutate(cur, sc);
        String? phoneBefore; // null = لا فحص للهاتف في هذا السيناريو
        if (sc.startsWith('هاتف')) phoneBefore = ((await custBalance(dev, x.cust))['phone'] as String?) ?? '';
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
          final saved = await save(inv, x, '$label [$sc]', policyMayReject: sc == 'فاتورة ضخمة' || cur.returned);
          if (saved == null) phoneBefore = null; // رُفض: لا شيء يُتوقع على البطاقة
          if (sc == 'حفظ مرتين متتاليتين') {
            await save(inv, state[inv]!.copy(), '$label [$sc — الثانية]');
          }
        }
        if (phoneBefore != null) {
          final after = (await custBalance(dev, x.cust))['phone'] as String?;
          if (phoneBefore.trim().isNotEmpty && after != phoneBefore) {
            problems.add('$label [$sc]: هاتف بطاقة العميل تغيّر من $phoneBefore إلى $after');
          }
          if (phoneBefore.trim().isEmpty && (after ?? '').trim().isEmpty) {
            problems.add('$label [$sc]: عميل بلا هاتف ولم يُضف الرقم المكتوب إلى بطاقته');
          }
        }
        await verifyInvoice(inv, '$label [$sc]');
        await verifyCust(dev, oldCust, '$label [$sc]');
        if (state[inv]!.cust != oldCust) await verifyCust(dev, state[inv]!.cust, '$label [$sc]');
      }

      Future<String?> create(String dev, String cust, String label) async {
        final x = _Inv(dev, cust, DateTime.now())
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

      Future<void> syncAndCrossCheck(String label) async {
        final e = await h.settle();
        problems.addAll(e.map((x) => '$label: $x'));
        for (final inv in state.keys.toList()) {
          if (stop()) break;
          final other = state[inv]!.dev == 'D1' ? 'D2' : 'D1';
          await verifyInvoice(inv, '$label (على الجهاز الآخر)', on: other);
        }
        count('جولة مزامنة');
      }

      void progress() {
        if (ops % 1000 != 0) return;
        final s = sw.elapsed.inSeconds;
        final eta = ops == 0 ? 0 : (s * (totalOps - ops) / ops).round();
        print('… $ops/$totalOps عملية — ${s ~/ 60}د — المتبقي ≈ ${eta ~/ 60}د — مشاكل=${problems.length}');
      }

      // ── 1) الإنشاء: محلية على D1، ثم مزامنة، ثم فواتير D2 (تصل بالمزامنة) ──
      final local = <String>[], synced = <String>[];
      for (final c in custs) {
        for (var k = 0; k < _localPer && !stop(); k++) {
          final u = await create('D1', c, 'إنشاء محلية ${names[c]} #${k + 1}');
          if (u != null) local.add(u);
        }
      }
      await syncAndCrossCheck('بعد إنشاء الفواتير المحلية');
      for (final c in custs) {
        for (var k = 0; k < _syncedPer && !stop(); k++) {
          final u = await create('D2', c, 'إنشاء على الجهاز الآخر ${names[c]} #${k + 1}');
          if (u != null) synced.add(u);
        }
      }
      await syncAndCrossCheck('بعد إنشاء فواتير الجهاز الآخر');

      // ── 2) الجولات: كل فاتورة محلية تُعدَّل مرة في كل جولة؛ وكل بضع جولات
      //       تُعدَّل فواتير الجهاز الآخر مرة وتصل بالمزامنة ──
      final every = max(1, _localEdits ~/ max(1, _syncEdits));
      var syncRounds = 0;
      Future<void> syncRound() async {
        syncRounds++;
        await h.settle();
        for (final inv in synced) {
          if (stop()) break;
          if (state[inv]!.deleted) continue;
          await step(inv, 'جهاز آخر جولة $syncRounds — فاتورة ${synced.indexOf(inv) + 1}');
          progress();
        }
        await syncAndCrossCheck('مزامنة الجولة $syncRounds');
      }

      for (var round = 1; round <= _localEdits && !stop(); round++) {
        for (final inv in local) {
          if (stop()) break;
          if (state[inv]!.deleted) continue;
          await step(inv, 'جولة $round — فاتورة ${local.indexOf(inv) + 1}');
          progress();
        }
        if (round % every == 0 && syncRounds < _syncEdits) await syncRound();
      }
      while (syncRounds < _syncEdits && !stop()) {
        await syncRound();
      }

      // ── 3) النهاية: الدفتر المحاسبي + الفحص العميق على الجهازين ──
      if (!stop()) {
        await syncAndCrossCheck('المزامنة النهائية');
        for (final dev in ['D1', 'D2']) {
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
      print('══ $ops عملية على ${state.length} فاتورة (${local.length} محلية، ${synced.length} بالمزامنة) '
          'في ${sw.elapsed.inMinutes} دقيقة');
      final keys = stats.keys.toList()..sort();
      for (final k in keys) {
        print('  $k: ${stats[k]}');
      }
      final seen = _scenarios.where((s) => !stats.containsKey('سيناريو: $s')).toList();
      if (seen.isNotEmpty && !stop()) print('  ⚠️ سيناريوهات لم تُجرَّب في هذا التشغيل: ${seen.join('، ')}');
      if (problems.isNotEmpty) {
        print('❌ هنا وقع خطأ — ${problems.length} مشكلة (يتوقف عند $_maxProblems):');
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
        print('✅ لا مشكلة واحدة.');
      }
      failed = problems.isNotEmpty;
      expect(problems, isEmpty);
    } finally {
      await h.dispose(keepFiles: failed);
    }
  }, timeout: const Timeout(Duration(hours: 24)));
}
