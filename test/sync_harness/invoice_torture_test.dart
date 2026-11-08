// test/sync_harness/invoice_torture_test.dart
//
// 🔨 اختبار التعذيب: فواتير كثيرة، وكل فاتورة تُعدَّل عشرات المرات بسيناريوهات
// مختلفة — على كود التطبيق الحقيقي (InvoiceController.saveInvoice، الموفِّق،
// CustomerMoney، الحذف، التعليق، إعادة التشغيل المفاجئة، المزامنة).
//
// بعد كل عملية يُقارن ما في قاعدة الجهاز بنموذج «حقيقة» مستقل محسوب هنا:
//   • الفاتورة: الإجمالي، المسدد، النوع، العميل، الحالة.
//   • دين الفاتورة في سجل الديون = المتبقي عليها (للدين) أو صفر، ولا أثر لها
//     على أي عميل آخر.
//   • دين كل عميل المخزّن = مجموع معاملاته = الحقيقة (جهاز واحد).
//   • الحفظ المرفوض (خصم ≥ الإجمالي، مسدد أكبر من الإجمالي…) لا يغيّر شيئاً.
// وفي النهاية: مزامنة كاملة، فحص المخزون، الدفتر المحاسبي، والفحص العميق.
//
//   flutter test test/sync_harness/invoice_torture_test.dart
//   flutter test test/sync_harness/invoice_torture_test.dart --dart-define=INVOICES=120 --dart-define=EDITS=25
//   flutter test test/sync_harness/invoice_torture_test.dart --dart-define=DEVICES=2 --dart-define=SEED=7
//
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _invoices = int.fromEnvironment('INVOICES', defaultValue: 100);
const _edits = int.fromEnvironment('EDITS', defaultValue: 25);
const _customers = int.fromEnvironment('CUSTOMERS', defaultValue: 4);
const _devices = int.fromEnvironment('DEVICES', defaultValue: 1);
const _seed = int.fromEnvironment('SEED', defaultValue: 1);
const _fullEvery = int.fromEnvironment('FULL_EVERY', defaultValue: 250);
const _restarts = bool.fromEnvironment('RESTARTS', defaultValue: true);
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 15);

/// أنواع معاملات لا تُعدّ من دين الفاتورة (كما في InvoiceDebtReconciler)
const _nonContribution = {'manual_payment', 'return_payment', 'correction', 'opening_balance'};

/// حالة الفاتورة كما يراها الاختبار (مدخلات الشاشة)
class _Inv {
  _Inv(this.dev, this.cust);
  final String dev;
  String cust;
  List<Map<String, Object?>> specs = [];
  double itemsTotal = 0;
  double discount = 0;
  double fee = 0;
  String ptype = 'دين';
  double paid = 0;
  bool deleted = false;
  double get finalTotal => itemsTotal + fee - discount;
  _Inv copy() => _Inv(dev, cust)
    ..specs = [for (final s in specs) Map<String, Object?>.from(s)]
    ..itemsTotal = itemsTotal
    ..discount = discount
    ..fee = fee
    ..ptype = ptype
    ..paid = paid;
}

void main() {
  test('تعذيب الفواتير: $_invoices فاتورة × $_edits تعديل، $_customers عملاء، $_devices جهاز، seed=$_seed',
      () async {
    final h = Harness(seed: _seed);
    final rnd = Random(_seed * 7919 + 1);
    final problems = <String>[];
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    var failed = true;
    var op = 0;
    final sw = Stopwatch()..start();

    double r2(double v) => (v * 100).roundToDouble() / 100;
    void near(String what, Object? got, double want) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() > 0.01) problems.add('$what = $g والمتوقع $want');
    }

    final devs = [for (var k = 1; k <= _devices; k++) 'D$k'];

    try {
      await h.start(_devices);

      // ── عملاء وأصناف ──
      final custs = <String>[];
      for (var k = 0; k < _customers; k++) {
        final c = await h.addCustomer(devs[k % devs.length], 'زبون تعذيب ${k + 1}');
        if (c != null) custs.add(c);
      }
      // صنف: (الاسم، سعر القطعة، كرتون)
      const catalog = [('برغي تعذيب', 250.0, 12), ('أنبوب تعذيب', 1750.5, null), ('صمام تعذيب', 4000.0, 6)];
      final prods = <(String, double, int?)>[];
      for (final (name, price, carton) in catalog) {
        final u = await h.addProduct('D1', name, 1000000, carton: carton);
        if (u != null) prods.add((u, price, carton));
      }
      var errs = await h.settle();
      expect(errs, isEmpty, reason: errs.join('\n'));
      expect(custs.length, _customers);

      final state = <String, _Inv>{};

      // ── أدوات ──
      List<Map<String, Object?>> randomSpecs() {
        final n = rnd.nextInt(4); // 0..3 أصناف
        final out = <Map<String, Object?>>[];
        for (var k = 0; k < n; k++) {
          final (u, price, carton) = prods[rnd.nextInt(prods.length)];
          if (out.any((x) => x['prod'] == u)) continue;
          final large = carton != null && rnd.nextDouble() < 0.35;
          final qty = (1 + rnd.nextInt(5)).toDouble();
          out.add({'prod': u, 'qty': qty, 'large': large, 'price': large ? price * carton! : price});
        }
        return out;
      }

      double specsTotal(List<Map<String, Object?>> specs) =>
          specs.fold(0.0, (s, x) => s + (x['qty'] as double) * (x['price'] as double));

      double randomExtra({bool mustBePositive = false}) {
        const extras = [0.0, 500.0, 1250.25, 10000.0, 75000.5, 333.33, 250000.0];
        var v = extras[rnd.nextInt(extras.length)];
        if (mustBePositive && v == 0) v = 1500;
        return v;
      }

      Map<String, double> baseItems(List<Map<String, Object?>> specs) => {
            for (final s in specs)
              s['prod'] as String: (s['qty'] as double) *
                  ((s['large'] == true) ? (h.truth.products[s['prod']]!.carton ?? 1).toDouble() : 1.0)
          };

      bool validInput(_Inv x) {
        if (x.discount < 0 || x.fee < 0 || x.paid < 0) return false;
        if (x.discount >= x.itemsTotal) return false;
        if (x.paid > x.finalTotal + 0.01) return false;
        if (x.ptype == 'نقد' && (x.paid - x.finalTotal).abs() > 0.01) return false;
        return true;
      }

      // دين العملاء قبل الحفظ ← هل يجعل الحفظ رصيد أحدهم سالباً؟ (رفض مشروع)
      bool wouldGoNegative(String? inv, _Inv x) {
        final t = inv == null ? null : h.truth.invoices[inv];
        final oldC = t?.contribution ?? 0.0;
        final newC = x.ptype == 'دين' ? max(0.0, x.finalTotal - x.paid) : 0.0;
        if (t != null && t.cust != x.cust) {
          return h.truth.balance(t.cust) - oldC < -0.01 || h.truth.balance(x.cust) + newC < -0.01;
        }
        return h.truth.balance(x.cust) - oldC + newC < -0.01;
      }

      /// حفظ بمسار الشاشة. المدخلات الخاطئة يجب أن تُرفض، والسليمة أن تُقبل
      /// (إلا إن جعلت رصيد عميل سالباً — رفض مشروع).
      Future<String?> save(String? inv, _Inv x, String label, {bool policyMayReject = false}) async {
        final valid = validInput(x);
        final r = (await h.d(x.dev).call('saveInvoice', {
          'cust': x.cust,
          'total': x.itemsTotal,
          'paid': x.paid,
          'ptype': x.ptype,
          'inv': inv,
          'items': x.specs,
          'discount': x.discount,
          'loadingFee': x.fee,
        }) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          if (valid && policyMayReject) {
            count('رفض فاتورة ضخمة: ${r['err']}');
            return null;
          }
          if (valid && !wouldGoNegative(inv, x)) {
            problems.add('$label: رُفض حفظ سليم (${r['err']})');
          }
          count(valid ? 'رفض لرصيد سالب' : 'رفض مدخلات خاطئة (صحيح)');
          return null;
        }
        if (!valid) {
          problems.add('$label: قُبل حفظ يجب رفضه — خصم=${x.discount} مسدد=${x.paid} '
              'إجمالي=${x.finalTotal} نوع=${x.ptype}');
        }
        final uuid = r['uuid'] as String;
        if (r['cust'] != x.cust) problems.add('$label: حُفظت على عميل آخر ${r['cust']} بدل ${x.cust}');
        final savedPaid = (r['paid'] as num?)?.toDouble() ?? x.paid;
        if ((savedPaid - x.paid).abs() > 0.01) {
          problems.add('$label: غيّر التطبيق المسدد بصمت: ${x.paid} ← $savedPaid');
        }
        final prev = h.truth.invoices[uuid];
        h.truth.invoices[uuid] = TruthInvoice(x.cust, x.dev, r2(x.finalTotal), x.paid, x.ptype, 'محفوظة')
          ..voidedFor = {...?prev?.voidedFor}
          ..items = baseItems(x.specs)
          ..specs = [for (final s in x.specs) Map<String, Object?>.from(s)];
        state[uuid] = x;
        count(inv == null ? 'فاتورة جديدة' : 'تعديل مقبول');
        return uuid;
      }

      /// الفاتورة في قاعدة جهازها = الحقيقة، ودينها في سجل الديون صحيح.
      Future<void> verifyInvoice(String inv, String label) async {
        final t = h.truth.invoices[inv]!;
        final dev = state[inv]!.dev;
        final r = (await h.d(dev).call('invoiceDetail', {'inv': inv}) as Map?)?.cast<String, Object?>();
        if (r == null) {
          problems.add('$label: الفاتورة غائبة من $dev');
          return;
        }
        final i = (r['invoice'] as Map).cast<String, Object?>();
        final del = ((i['is_deleted'] as int?) ?? 0) == 1;
        if (t.status == 'محذوفة') {
          if (!del) problems.add('$label: الفاتورة محذوفة في الحقيقة وما زالت ظاهرة');
        } else {
          if (del) problems.add('$label: الفاتورة محذوفة في القاعدة والصحيح ${t.status}');
          if (i['status'] != t.status) problems.add('$label: الحالة ${i['status']} والصحيح ${t.status}');
          near('$label الإجمالي', i['total_amount'], t.total);
          near('$label المسدد', i['amount_paid_on_invoice'], t.paid);
          if (i['payment_type'] != t.ptype) problems.add('$label: النوع ${i['payment_type']} والصحيح ${t.ptype}');
          if (i['cust_uuid'] != t.cust) problems.add('$label: العميل ${i['cust_uuid']} والصحيح ${t.cust}');
        }
        final txs = (r['txs'] as List).cast<Map>().where((x) =>
            ((x['del'] as int?) ?? 0) == 0 && !_nonContribution.contains(x['type']));
        final mine = txs.where((x) => x['cust'] == t.cust).fold(0.0, (s, x) => s + (x['amount'] as num).toDouble());
        final others = txs.where((x) => x['cust'] != t.cust).fold(0.0, (s, x) => s + (x['amount'] as num).toDouble());
        near('$label دين الفاتورة في سجل الديون', mine, t.contribution);
        near('$label أثر الفاتورة على عملاء آخرين', others, 0);
      }

      /// دين كل عميل (جهاز واحد): المخزّن = مجموع المعاملات = الحقيقة.
      Future<void> verifyBalances(String label) async {
        if (_devices != 1) return;
        final st = (await h.d('D1').call('state') as Map).cast<String, Object?>();
        for (final c in (st['customers'] as List).cast<Map>()) {
          final u = c['uuid'] as String?;
          if (u == null || !h.truth.customers.containsKey(u)) continue;
          final want = h.truth.balance(u);
          near('$label دين ${c['name']} المخزّن', c['debt'], want);
          near('$label مجموع معاملات ${c['name']}', c['sum'], want);
        }
      }

      Future<void> checkpoint(String label) async {
        final e = await h.settle();
        for (final x in e) {
          problems.add('$label: $x');
        }
        count('نقطة فحص كاملة');
      }

      bool stop() => problems.length >= _maxProblems;

      // ── سيناريوهات التعديل ──
      const scenarios = [
        'أصناف جديدة', 'كميات وأسعار', 'خصم', 'أجور تحميل', 'إلى نقد', 'إلى دين', 'تسديد جزئي',
        'تسديد كامل', 'إلغاء التسديد', 'تغيير العميل', 'كسور', 'حفظ بلا تغيير', 'خصم ≥ الإجمالي (يُرفض)',
        'مسدد > الإجمالي (يُرفض)', 'نقد بمسدد ناقص (يُرفض)', 'تصغير تحت المسدد (يُرفض)', 'خصم وتحميل معاً',
        'فاتورة ضخمة', 'فاتورة صغيرة جداً',
      ];

      _Inv mutate(_Inv cur, String sc) {
        final x = cur.copy();
        void keepPaidValid() {
          if (x.ptype == 'نقد') {
            x.paid = r2(x.finalTotal);
          } else if (x.paid > x.finalTotal) {
            x.paid = r2(max(0.0, x.finalTotal));
          }
        }

        void resetDiscountIfNeeded() {
          if (x.discount >= x.itemsTotal) x.discount = 0;
        }

        switch (sc) {
          case 'أصناف جديدة':
            x.specs = randomSpecs();
            x.itemsTotal = r2(specsTotal(x.specs) + randomExtra(mustBePositive: x.specs.isEmpty));
            resetDiscountIfNeeded();
            keepPaidValid();
          case 'كميات وأسعار':
            for (final s in x.specs) {
              s['qty'] = (1 + rnd.nextInt(9)).toDouble();
              s['price'] = r2((s['price'] as double) * [0.5, 1.0, 1.1, 2.0][rnd.nextInt(4)]);
            }
            x.itemsTotal = r2(specsTotal(x.specs) + randomExtra(mustBePositive: x.specs.isEmpty));
            resetDiscountIfNeeded();
            keepPaidValid();
          case 'خصم':
            x.discount = r2(x.itemsTotal * [0.0, 0.01, 0.05, 0.2][rnd.nextInt(4)]);
            keepPaidValid();
          case 'أجور تحميل':
            x.fee = [0.0, 1000.0, 2500.0, 15000.0][rnd.nextInt(4)];
            keepPaidValid();
          case 'خصم وتحميل معاً':
            x.discount = r2(x.itemsTotal * 0.1);
            x.fee = 5000;
            keepPaidValid();
          case 'إلى نقد':
            x.ptype = 'نقد';
            keepPaidValid();
          case 'إلى دين':
            x.ptype = 'دين';
            x.paid = 0;
          case 'تسديد جزئي':
            x.ptype = 'دين';
            x.paid = r2(x.finalTotal * [0.1, 0.25, 0.5, 0.9][rnd.nextInt(4)]);
          case 'تسديد كامل':
            x.ptype = 'دين';
            x.paid = r2(x.finalTotal);
          case 'إلغاء التسديد':
            if (x.ptype == 'دين') x.paid = 0;
          case 'تغيير العميل':
            {
              final others = custs.where((c) => c != x.cust).toList();
              x.cust = others[rnd.nextInt(others.length)];
            }
          case 'كسور':
            x.itemsTotal = r2(x.itemsTotal + 0.37);
            x.discount = r2(min(x.discount + 0.13, x.itemsTotal * 0.5));
            keepPaidValid();
          case 'حفظ بلا تغيير':
            break;
          case 'خصم ≥ الإجمالي (يُرفض)':
            x.discount = x.itemsTotal;
          case 'مسدد > الإجمالي (يُرفض)':
            x.ptype = 'دين';
            x.paid = r2(x.finalTotal + 500);
          case 'نقد بمسدد ناقص (يُرفض)':
            x.ptype = 'نقد';
            x.paid = r2(x.finalTotal * 0.5);
          case 'تصغير تحت المسدد (يُرفض)':
            x.ptype = 'دين';
            x.paid = r2(x.finalTotal);
            x.specs = [];
            x.itemsTotal = r2(max(1.0, x.itemsTotal * 0.3));
            x.discount = 0;
            x.fee = 0;
          case 'فاتورة ضخمة':
            x.itemsTotal = r2(specsTotal(x.specs) + 987654321.5);
            keepPaidValid();
          case 'فاتورة صغيرة جداً':
            x.specs = [];
            x.itemsTotal = 0.25;
            x.discount = 0;
            x.fee = 0;
            keepPaidValid();
        }
        return x;
      }

      // ── الحلقة الرئيسية ──
      for (var n = 0; n < _invoices && !stop(); n++) {
        final dev = devs[n % devs.length];
        final cust = custs[rnd.nextInt(custs.length)];
        String? inv;

        if (rnd.nextDouble() < 0.1) {
          // تبدأ معلّقة ثم تُستكمل بالتعديل الأول
          final total = [3000.0, 12500.5][rnd.nextInt(2)];
          inv = await h.suspendInvoice(dev, cust, total);
          if (inv != null) {
            state[inv] = _Inv(dev, h.truth.invoices[inv]!.cust)
              ..itemsTotal = total
              ..paid = 0
              ..ptype = 'دين';
            count('فاتورة معلّقة');
          }
        } else {
          final x = _Inv(dev, cust)
            ..specs = randomSpecs()
            ..ptype = rnd.nextInt(3) < 2 ? 'دين' : 'نقد';
          x.itemsTotal = r2(specsTotal(x.specs) + randomExtra(mustBePositive: x.specs.isEmpty));
          x.paid = x.ptype == 'نقد' ? x.finalTotal : (rnd.nextBool() ? 0 : r2(x.finalTotal * 0.3));
          inv = await save(null, x, 'فاتورة ${n + 1} (إنشاء)');
        }
        if (inv == null) continue;
        await verifyInvoice(inv, 'فاتورة ${n + 1} (إنشاء)');
        await verifyBalances('فاتورة ${n + 1} (إنشاء)');

        for (var e = 0; e < _edits && !stop(); e++) {
          op++;
          if (op % _fullEvery == 0) await checkpoint('بعد $op عملية');
          if (op % 100 == 0) {
            print('… $op عملية، ${state.length} فاتورة، ${sw.elapsed.inSeconds}ث، مشاكل=${problems.length}');
          }
          final label = 'فاتورة ${n + 1} تعديل ${e + 1}';
          final roll = rnd.nextDouble();
          try {
            if (roll < 0.08) {
              // وصل قبض على عميل (لا يتجاوز نصف دينه)
              final c = custs[rnd.nextInt(custs.length)];
              final bal = h.truth.balance(c);
              if (bal > 1000) {
                final amount = r2((bal * 0.5 / 250).floorToDouble() * 250);
                if (amount > 0) {
                  final u = await h.d(dev).call('receipt', {'cust': c, 'amount': amount, 'marker': 'T$op'}) as String?;
                  if (u != null) {
                    h.truth.txs[u] = TruthTx(c, dev, -amount, 'manual_payment');
                    count('وصل قبض');
                  }
                }
              }
              await verifyBalances('$label (وصل)');
              continue;
            }
            if (roll < 0.12) {
              final c = custs[rnd.nextInt(custs.length)];
              await h.addTx(dev, c, [5000.0, 1250.75][rnd.nextInt(2)]);
              count('دين يدوي');
              await verifyBalances('$label (دين يدوي)');
              continue;
            }
            if (roll < 0.125 && _restarts) {
              await h.restart(dev);
              count('إعادة تشغيل مفاجئة');
              await verifyInvoice(inv, '$label (بعد إعادة التشغيل)');
              await verifyBalances('$label (بعد إعادة التشغيل)');
              continue;
            }
            final sc = scenarios[rnd.nextInt(scenarios.length)];
            count('سيناريو: $sc');
            final x = mutate(state[inv]!, sc);
            // إن رُفض الحفظ فالحقيقة لم تتغير — والتحقق التالي يثبت أن القاعدة لم تتغير أيضاً
            await save(inv, x, '$label [$sc]', policyMayReject: sc == 'فاتورة ضخمة');
            await verifyInvoice(inv, '$label [$sc]');
            await verifyBalances('$label [$sc]');
          } catch (err) {
            problems.add('$label: خطأ من التطبيق: ${'$err'.split('\n').first}');
          }
        }

        // حذف بعض الفواتير في آخر حياتها
        if (!stop() && rnd.nextDouble() < 0.06) {
          final r = (await h.d(dev).call('deleteInvoice', {'inv': inv}) as Map).cast<String, Object?>();
          if (r['ok'] == true) {
            h.truth.invoices[inv]!.status = 'محذوفة';
            state[inv]!.deleted = true;
            count('حذف فاتورة');
          } else {
            count('رفض حذف فاتورة');
          }
          await verifyInvoice(inv, 'فاتورة ${n + 1} (حذف)');
          await verifyBalances('فاتورة ${n + 1} (حذف)');
        }
      }

      // ── النهاية: مزامنة كاملة + كل الفحوص على كل جهاز ──
      if (!stop()) {
        errs = await h.settle();
        problems.addAll(errs.map((e) => 'بعد المزامنة النهائية: $e'));
        for (final dev in devs) {
          final lc = (await h.d(dev).call('ledgerCheck', const {}, const Duration(minutes: 10)) as Map)
              .cast<String, Object?>();
          for (final p in (lc['problems'] as List).cast<String>()) {
            problems.add('$dev الدفتر المحاسبي: $p');
          }
          final dc = (await h.d(dev).call('deepCheck', const {}, const Duration(minutes: 10)) as Map)
              .cast<String, Object?>();
          if ((dc['errors'] as int) > 0) problems.add('$dev الفحص العميق:\n${dc['text']}');
          print('── $dev الفحص العميق ──\n${dc['text']}');
        }
      }

      final uncaught = await h.deviceErrors();
      for (final e in uncaught.take(5)) {
        problems.add('خطأ غير ممسوك: ${e.split('\n').take(4).join(' | ')}');
      }

      print('══ النتيجة: $op عملية على ${state.length} فاتورة في ${sw.elapsed.inSeconds}ث');
      final keys = stats.keys.toList()..sort();
      for (final k in keys) {
        print('  $k: ${stats[k]}');
      }
      if (problems.isNotEmpty) {
        print('❌ هنا وقع خطأ — ${problems.length} مشكلة (أول $_maxProblems):');
        for (final p in problems.take(_maxProblems)) {
          print('  • $p');
        }
        final bad = custs.where((c) => problems.any((p) => p.contains(h.truth.customers[c]!.name))).take(2);
        for (final c in bad) {
          print(await h.explain(c));
        }
      }
      failed = problems.isNotEmpty;
      expect(problems, isEmpty);
    } finally {
      await h.dispose(keepFiles: failed);
    }
  }, timeout: const Timeout(Duration(hours: 4)));
}
