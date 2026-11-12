// test/sync_harness/invoice_scenarios_test.dart
//
// 🧾 سيناريوهات الفاتورة: آلاف السيناريوهات، كل سيناريو = عميل واحد وفاتورة واحدة تُعدَّل
// مراراً كما يفعل المستخدم في شاشة الفاتورة:
//   تحويل دين ⇄ نقد قبل الحفظ وبعده، تعديل كمية أو سعر، إضافة صنف وحذفه، الخصم، أجور النقل،
//   المبلغ المسدد، تغيير اسم العميل في بطاقته، اسم بمسافات زائدة، نقل الفاتورة لاسم جديد —
//   بكل التركيبات، والحفظ بينها.
//
// الشاشة: قواعدها منقولة سطراً بسطر من create_invoice_screen.dart (ما يحدث للمبلغ المسدد عند
//   الضغط على «نقد» أو «دين»، وعند تغيير الأصناف والخصم وأجور النقل، وحارس الخصم).
// الحفظ: مسار زر «حفظ» الحقيقي (invoice_actions ← InvoiceController.saveInvoice) بكود التطبيق.
//
// بعد كل حفظ يُفحص: إجمالي الفاتورة = الأسطر + النقل − الخصم (بقواعد الدينار الصحيح)، نوع الدفع،
// المسدد (النقد = الإجمالي؛ الدين بين صفر والإجمالي)، دين العميل = مجموع معاملاته = المتبقي
// من الفاتورة، العميل السابق (عند النقل) صفر، سند تعديل الفاتورة النقدية بمبلغ الفرق، المخزون.
// الحفظ المرفوض: لا يتغيّر شيء. وكل 100 سيناريو: الفحص العميق + الدفتر (ذمم كل عميل = سجل الديون).
//
// التشغيل: claude_test_invoice_scenarios.bat [quick|full] [seed]
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:alnaser/utils/iqd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _quick = bool.fromEnvironment('QUICK');
const _seedArg = int.fromEnvironment('SEED');
const _scenarios = int.fromEnvironment('SCENARIOS', defaultValue: _quick ? 300 : 10000);
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 25);

class _Line {
  _Line(this.prod, this.qty, this.price);
  final int prod;
  double qty;
  double price;
  double get total => Iqd.up(qty * price); // InvoiceItem: السطر لأقرب دينار (النصف للأعلى)
  Map<String, Object?> toArg() => {'prodId': prod, 'qty': qty, 'price': price};
}

/// حال شاشة الفاتورة — القواعد منقولة من create_invoice_screen.dart
class _Screen {
  _Screen(this.name, this.ptype, this.items);
  String name;
  String ptype;
  List<_Line> items;
  double discount = 0;
  double fee = 0;
  double paid = 0;
  String? inv; // الفاتورة بعد أول حفظ
  bool get existing => inv != null;

  double r2(double v) => (v * 100).roundToDouble() / 100; // formatNumber: '#,##0.##'
  double get itemsTotal => items.fold(0.0, (s, l) => s + l.total);

  // _guardDiscount: الخصم أقل من نصف (الأصناف + النقل) − 1، ولا سالب
  void guardDiscount() {
    final cur = itemsTotal + fee;
    final maxDiscount = (cur / 2) - 1;
    if (discount > maxDiscount) discount = r2(maxDiscount > 0 ? maxDiscount : 0.0);
    if (discount < 0) discount = 0;
    if (existing && ptype == 'نقد') paid = r2(cur - discount);
  }

  // _updatePaidAmountIfCash
  void updatePaidIfCash() {
    if (ptype == 'نقد') {
      guardDiscount();
      paid = r2(max(0.0, itemsTotal + fee - discount));
    }
  }

  // _recalculateTotals (بعد تغيير الأصناف)
  void recalc() {
    if (ptype == 'نقد') paid = r2(itemsTotal + fee - discount);
  }

  void toCash() {
    ptype = 'نقد';
    updatePaidIfCash();
  }

  void toCredit() {
    ptype = 'دين';
    paid = 0;
  }

  void setDiscount(double v) {
    discount = v;
    // المستمع _onDiscountChanged (فاتورة موجودة نقدية): المسدد = الأصناف − الخصم
    if (existing && ptype == 'نقد') paid = r2(itemsTotal - discount);
    // onChanged: الحارس ثم تحديث المسدد
    guardDiscount();
    updatePaidIfCash();
  }

  void setFee(double v) {
    fee = v;
    guardDiscount();
    updatePaidIfCash();
  }
}

void main() {
  final seed = _seedArg != 0 ? _seedArg : DateTime.now().microsecondsSinceEpoch % 1000000 + 1;
  test('سيناريوهات الفاتورة: $_scenarios سيناريو seed=$seed', () async {
    print('🎲 seed=$seed');
    final h = Harness(seed: seed);
    final rnd = Random(seed * 17 + 3);
    final problems = <String>[];
    final notes = <String>{};
    final stats = <String, int>{};
    final combos = <String>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    final sw = Stopwatch()..start();
    final out = Directory('test_results${Platform.pathSeparator}invoice_scenarios')..createSync(recursive: true);
    final progress = File('${out.path}${Platform.pathSeparator}progress.txt');
    var saves = 0, steps = 0;
    void bad(String p) {
      problems.add(p);
      print('✗ $p');
    }

    var failed = true;
    try {
      await h.start(1);
      const dev = 'D1';
      Future<Map<String, Object?>> scen(String n, [Map<String, Object?> a = const {}]) async {
        final r = await h.d(dev).call('scen', {'op': n, 'args': a}, const Duration(minutes: 3));
        return r is Map ? r.cast<String, Object?>() : {'ok': true, 'value': r};
      }

      double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
      bool near(Object? a, Object? b, [double tol = 0.011]) => (dd(a) - dd(b)).abs() <= tol;
      T pick<T>(List<T> xs) => xs[rnd.nextInt(xs.length)];

      // ── المواد: مخزون كبير حتى لا يمنع النفاد أي حفظ ──
      for (var i = 1; i <= 6; i++) {
        await h.d(dev).call('addProduct', {'name': 'مادة سيناريو $i', 'stock': 1000000});
      }
      final prodRows = ((await scen('prodIds'))['rows'] as List).cast<Map>();
      final prods = [for (final r in prodRows) (r['id'] as num).toInt()];
      final stock0 = {for (final r in prodRows) (r['id'] as num).toInt(): dd(r['stock'])};
      if (prods.length < 6) throw StateError('فشل التجهيز: ${prods.length} مادة');
      final sold = <String, Map<int, double>>{}; // فاتورة ← (مادة ← كمية) كما حُفظت

      Future<void> checkStock(String label) async {
        final rows = ((await scen('prodIds'))['rows'] as List).cast<Map>();
        for (final r in rows) {
          final id = (r['id'] as num).toInt();
          final exp = stock0[id]! - sold.values.fold<double>(0, (s, m) => s + (m[id] ?? 0));
          if (!near(r['stock'], exp, 0.001)) bad('$label: مخزون المادة $id = ${r['stock']} والمتوقع $exp');
        }
      }

      Future<void> deepChecks(String label) async {
        final dc = await h.d(dev).call('deepCheck', {}, const Duration(minutes: 10));
        if (dc is Map && ((dc['errors'] as num?) ?? 0) > 0) {
          bad('$label الفحص العميق: ${'${dc['text']}'.split('\n').take(8).join(' | ')}');
        }
        final lc = await h.d(dev).call('ledgerCheck', {}, const Duration(minutes: 10));
        if (lc is Map) {
          for (final p in ((lc['problems'] as List?) ?? const []).take(5)) {
            bad('$label الدفتر: $p');
          }
        }
        await checkStock(label);
      }

      _Line newLine() => _Line(pick(prods), pick([1.0, 2.0, 3.0, 0.5, 10.0, 2.5]), pick([1000.0, 2500.0, 750.0, 1250.0, 333.5, 99999.0]));

      // سيناريوهات صاحب المحل كما وصفها (تتكرر بقيم مختلفة) ثم التركيبات العشوائية
      const scripted = <List<String>>[
        ['credit', 'cash', 'credit', 'save', 'qty', 'save', 'cash', 'discount', 'save'],
        ['credit', 'cash', 'credit', 'save', 'qty', 'save', 'cash', 'price', 'save'],
        ['credit', 'cash', 'credit', 'save', 'qty', 'save', 'cash', 'paid', 'qty', 'save'],
        ['cash', 'save', 'rename', 'qty', 'save'],
        ['cash', 'save', 'rename', 'credit', 'save'],
        ['cash', 'save', 'rename', 'credit', 'qty', 'save'],
        ['credit', 'save', 'rename', 'cash', 'qty', 'save'],
        ['cash', 'save', 'credit', 'save', 'cash', 'save', 'credit', 'save'],
        ['credit', 'paid', 'save', 'cash', 'credit', 'save', 'cash', 'credit', 'cash', 'save'],
        ['cash', 'save', 'credit', 'cash', 'save', 'credit', 'paid', 'save'],
        ['credit', 'save', 'cash', 'discount', 'credit', 'save', 'cash', 'save'],
        ['cash', 'discount', 'save', 'credit', 'qty', 'save', 'cash', 'fee', 'save'],
        ['credit', 'paid', 'save', 'remove', 'save', 'cash', 'add', 'save'],
        ['cash', 'save', 'moveNew', 'credit', 'save', 'cash', 'save'],
        ['credit', 'save', 'moveNew', 'qty', 'cash', 'save'],
        ['credit', 'save', 'spaces', 'cash', 'save'],
        // 🔁 فاتورة دين سُدّد جزء منها بوصل ثم حُوّلت إلى نقد: الجزء المسدد لا يُقبض مرتين
        ['credit', 'save', 'receipt', 'cash', 'save'],
        ['credit', 'paid', 'save', 'receipt', 'cash', 'save'],
        ['credit', 'save', 'receipt', 'qty', 'cash', 'save', 'qty', 'save'],
        ['credit', 'save', 'receipt', 'receipt', 'cash', 'save', 'cash', 'save'],
        ['credit', 'save', 'receipt', 'cash', 'save', 'add', 'save', 'cash', 'save'],
        ['credit', 'save', 'receipt', 'cash', 'credit', 'cash', 'save'],
        ['credit', 'save', 'receipt', 'rename', 'cash', 'save'],
        ['credit', 'save', 'receipt', 'moveNew', 'cash', 'save'],
      ];
      const ops = ['cash', 'credit', 'qty', 'price', 'add', 'remove', 'discount', 'fee', 'paid', 'rename', 'spaces', 'moveNew', 'receipt'];
      const weights = [14, 14, 12, 8, 6, 6, 9, 5, 9, 6, 3, 3, 7];
      String randomOp() {
        var x = rnd.nextInt(weights.reduce((a, b) => a + b));
        for (var k = 0; k < ops.length; k++) {
          if (x < weights[k]) return ops[k];
          x -= weights[k];
        }
        return 'cash';
      }

      List<String> genSteps() {
        final s = <String>[];
        s.add(rnd.nextBool() ? 'cash' : 'credit');
        for (var k = rnd.nextInt(4); k > 0; k--) {
          final o = randomOp();
          if (!const {'rename', 'spaces', 'moveNew', 'receipt'}.contains(o)) s.add(o);
        }
        s.add('save');
        for (var k = 2 + rnd.nextInt(12); k > 0; k--) {
          s.add(rnd.nextDouble() < 0.25 ? 'save' : randomOp());
        }
        if (s.last != 'save') s.add('save');
        return s;
      }

      for (var sc = 1; sc <= _scenarios; sc++) {
        if (problems.length >= _maxProblems) break;
        final script = sc <= scripted.length * 20 ? scripted[(sc - 1) % scripted.length] : genSteps();
        combos.add(script.join('›'));
        final scr = _Screen('زبون سيناريو $seed-$sc', 'نقد', [newLine(), if (rnd.nextBool()) newLine()]);
        scr.recalc();
        String? cust; // العميل الحالي للفاتورة
        final oldCusts = <String>[]; // عملاء نُقلت منهم الفاتورة: دينهم من هذه الفاتورة صفر
        final receiptsBy = <String, double>{}; // عميل ← ما سدّده بوصولات (كلها لهذه الفاتورة)
        var lastPrepaid = 0.0; // ما سُدّد منها بوصولات كما في الفاتورة المحفوظة
        Map<String, Object?>? last; // آخر حالة محفوظة
        var renames = 0;
        final trail = <String>[];
        // تغيير اسم ينتظر الحفظ الناجح (الحفظ المرفوض لا يُسقطه: الاسم ما زال مكتوباً في الشاشة)
        var pendingMove = false, pendingSpaces = false;

        for (final st in script) {
          steps++;
          final label = 'س$sc ${trail.join('›')}›$st';
          switch (st) {
            case 'cash':
              scr.toCash();
            case 'credit':
              scr.toCredit();
            case 'qty':
              pick(scr.items).qty = pick([1.0, 4.0, 0.5, 7.0, 12.0, 3.0]);
              scr.recalc();
            case 'price':
              pick(scr.items).price = pick([1500.0, 800.0, 2000.0, 333.5, 50.0]);
              scr.recalc();
            case 'add':
              scr.items.add(newLine());
              scr.recalc();
            case 'remove':
              if (scr.items.length > 1) scr.items.removeAt(rnd.nextInt(scr.items.length));
              scr.recalc();
            case 'discount':
              scr.setDiscount(pick([0.0, 500.0, 1250.0, 99.5, scr.itemsTotal / 3, scr.itemsTotal]));
            case 'fee':
              scr.setFee(pick([0.0, 5000.0, 2500.5, 250.0]));
            case 'paid':
              if (scr.ptype == 'دين') {
                final rem = scr.itemsTotal + scr.fee - scr.discount;
                scr.paid = scr.r2(pick([0.0, rem / 2, rem, rem + 1000, 1000.4, rem - 0.5]).clamp(0, double.infinity).toDouble());
              }
            case 'rename':
              if (cust != null) {
                renames++;
                final newName = 'زبون معدّل $seed-$sc-$renames';
                final r = await h.d(dev).call('renameCustomer', {'cust': cust, 'name': newName});
                if (r is Map && r['ok'] == true) {
                  scr.name = newName; // الشاشة تعرض اسم بطاقته عند فتح الفاتورة
                  count('تغيير اسم العميل');
                } else {
                  bad('$label: تعذّر تغيير اسم العميل (${r is Map ? r['err'] : r})');
                }
              }
            case 'spaces':
              if (cust != null) {
                scr.name = '${scr.name.replaceFirst(' ', '  ')} ';
                pendingSpaces = true;
              }
            case 'moveNew':
              if (cust != null) {
                scr.name = 'زبون منقول $seed-$sc-$steps';
                pendingMove = true;
              }
            case 'receipt':
              // وصل قبض منفصل (لا يُربط بفاتورة) لجزء من دين العميل
              if (cust != null) {
                final cd = await scen('custByUuid', {'cust': cust});
                final debt = dd(cd['debt']);
                if (debt >= 1) {
                  final amt = Iqd.down(min(debt, pick([debt, (debt / 2).floorToDouble(), 1000.0, 1.0, 25000.0])));
                  final u = await h.d(dev).call('addTx', {'cust': cust, 'amount': -amt, 'marker': 'وصل سيناريو $sc-$steps'});
                  if (u is String) {
                    receiptsBy[cust!] = (receiptsBy[cust] ?? 0) + amt;
                    count('وصل قبض منفصل');
                  } else {
                    bad('$label: رُفض وصل قبض $amt لعميل دينه $debt');
                  }
                }
              }
            case 'save':
              saves++;
              final before = last;
              // 🔁 المتوقع عند تحويل فاتورة دين إلى نقد بعد وصولات: S = min(دين الفاتورة، الوصولات)
              final priorR = before == null ? 0.0 : dd(before['linked']);
              final rcvNow = cust == null ? 0.0 : (receiptsBy[cust] ?? 0.0);
              final expS = (min(priorR, rcvNow) + 0.0001).floorToDouble(); // دينار صحيح للأدنى، لا يتجاوز دين الفاتورة
              final expectSettle = scr.inv != null && scr.ptype == 'نقد' && !pendingMove && priorR >= 0.5 && expS >= 0.5;
              final expPtype = expectSettle ? 'دين' : scr.ptype;
              final r = await scen('invSave', {
                if (scr.inv != null) 'inv': scr.inv,
                'name': scr.name,
                'items': [for (final l in scr.items) l.toArg()],
                'discount': scr.discount,
                'fee': scr.fee,
                'paid': scr.paid,
                'ptype': scr.ptype,
              });
              if (r['ok'] != true) {
                final stage = '${r['stage']}';
                count('رُفض الحفظ ($stage): ${'${r['err']}'.split('\n').first.characters_(60)}');
                if (stage == 'save' || stage == 'exception' || stage == 'load') {
                  bad('$label: فشل الحفظ بعد اجتياز كل الفحوص ($stage): ${r['err']}');
                }
                // 🔁 التحويل إلى نقد بعد وصولات لا تتجاوز دين الفاتورة يُبقي رصيد العميل صفراً:
                //    رفضه بحجة «رصيد سالب» خطأ (كان يحدث حين سبق فحصُ الدين التسويةَ)
                if (stage == 'debt' && expectSettle && rcvNow <= priorR + 0.001 &&
                    scr.itemsTotal + scr.fee - scr.discount >= expS + 1) {
                  bad('$label: تحويل إلى نقد بعد وصل ${rcvNow.toStringAsFixed(0)} رُفض بحجة دين سالب: ${'${r['err']}'.split('\n').first}');
                }
                // المرفوض لا يغيّر شيئاً
                if (before != null && scr.inv != null) {
                  final now = await scen('invInfo', {'inv': scr.inv});
                  for (final k in const ['total', 'paid', 'ptype', 'discount', 'fee', 'linked']) {
                    if ('${now[k]}' != '${before[k]}') bad('$label: حفظ مرفوض غيّر $k من ${before[k]} إلى ${now[k]}');
                  }
                  final nc = (now['cust'] as Map?)?['debt'], bc = (before['cust'] as Map?)?['debt'];
                  if (!near(nc, bc)) bad('$label: حفظ مرفوض غيّر دين العميل من $bc إلى $nc');
                }
                break;
              }
              // ── المتوقع من حال الشاشة ──
              final fee = Iqd.up(scr.fee);
              final disc = Iqd.down(scr.discount);
              final lines = scr.items.fold<double>(0, (s, l) => s + l.total);
              final total = lines + fee - disc;
              if (r['ptype'] != expPtype) {
                bad('$label: نوع الدفع المحفوظ ${r['ptype']} والمتوقع $expPtype (الشاشة ${scr.ptype}${expectSettle ? '، سُدّد منها $expS بوصولات' : ''})');
              }
              if (!near(r['discount'], disc)) bad('$label: الخصم المحفوظ ${r['discount']} والمتوقع $disc (المكتوب ${scr.discount})');
              if (!near(r['fee'], fee)) bad('$label: أجور النقل المحفوظة ${r['fee']} والمتوقع $fee');
              if (!near(r['total'], total, 0.02)) {
                bad('$label: الإجمالي ${r['total']} والمتوقع $total (أسطر $lines + نقل $fee − خصم $disc)');
              }
              final savedItems = (r['items'] as List).cast<Map>();
              final savedLines = savedItems.fold<double>(0, (s, x) => s + dd(x['total']));
              if (!near(dd(r['total']), savedLines + dd(r['fee']) - dd(r['discount']), 0.02)) {
                bad('$label: الإجمالي ${r['total']} ≠ أسطره $savedLines + النقل − الخصم');
              }
              if (savedItems.length != scr.items.length) bad('$label: حُفظ ${savedItems.length} سطراً والشاشة ${scr.items.length}');
              final paid = dd(r['paid']), t = dd(r['total']);
              if (expPtype == 'نقد') {
                if (!near(paid, t)) bad('$label: فاتورة نقدية مسددها $paid وإجماليها $t');
              } else if (expectSettle) {
                final wantPaid = max(0.0, t - expS);
                if (!near(paid, wantPaid, 1.001)) bad('$label: تحويل بعد وصل $expS: المسدد $paid والمتوقع $wantPaid');
                if (!near(r['prepaid'], min(expS, t), 1.001)) {
                  bad('$label: تحويل بعد وصل $expS: المسدد بوصولات المحفوظ ${r['prepaid']} والمتوقع ${min(expS, t)}');
                }
                count('تحويل إلى نقد بعد وصل ⇒ آجل مسددة بالكامل');
              } else {
                if (paid < -0.001 || paid > t + 0.001) bad('$label: فاتورة دين مسددها $paid خارج [0، $t]');
                final want = min(Iqd.down(scr.paid), t);
                if ((paid - want).abs() > 1.001) bad('$label: المسدد المحفوظ $paid والمكتوب ${scr.paid} (المتوقع $want)');
              }
              final remaining = expPtype == 'نقد' ? 0.0 : t - paid; // دين الفاتورة في حساب العميل
              final wantPrepaid = expPtype == 'نقد' ? 0.0 : (expectSettle ? min(expS, t) : lastPrepaid);
              if (!near(r['prepaid'], wantPrepaid, 1.001)) {
                bad('$label: «سُدّد بوصولات» المحفوظ ${r['prepaid']} والمتوقع $wantPrepaid');
              }
              final c = (r['cust'] as Map?)?.cast<String, Object?>();
              if (c == null) {
                bad('$label: الفاتورة بلا عميل');
                break;
              }
              final newCust = '${c['uuid']}';
              if (cust != null && newCust != cust) {
                if (pendingMove) {
                  count('نقل الفاتورة لعميل جديد');
                } else if (pendingSpaces) {
                  notes.add('اسم العميل بمسافات زائدة نقل الفاتورة إلى عميل آخر («${c['name']}»)');
                } else {
                  bad('$label: الفاتورة انتقلت من عميلها إلى «${c['name']}» دون تغيير الاسم');
                }
                oldCusts.add(cust);
              }
              cust = newCust;
              final rcv = receiptsBy[newCust] ?? 0.0;
              if (!near(c['debt'], remaining - rcv)) {
                bad('$label: دين العميل ${c['debt']} والمتوقع ${remaining - rcv} (دين الفاتورة $remaining − وصولاته $rcv)');
              }
              if (!near(c['txsum'], c['debt'])) bad('$label: دين العميل ${c['debt']} ≠ مجموع معاملاته ${c['txsum']}');
              if (!near(r['linked'], remaining)) bad('$label: معاملات الفاتورة ${r['linked']} والمتبقي $remaining');
              for (final o in oldCusts) {
                final oc = await scen('custByUuid', {'cust': o});
                final orc = receiptsBy[o] ?? 0.0;
                if (oc['exists'] == true && (!near(oc['debt'], -orc) || !near(oc['txsum'], -orc))) {
                  bad('$label: العميل السابق «${oc['name']}» عليه ${oc['debt']} (معاملاته ${oc['txsum']}) والمتوقع ${-orc} (وصولاته) بعد نقل فاتورته');
                }
              }
              // سند تعديل الفاتورة النقدية
              final bf = (r['before'] as Map?)?.cast<String, Object?>();
              if (bf != null) {
                final delta = t - dd(bf['total']);
                final want = bf['payment'] == 'نقد' && r['ptype'] == 'نقد' && delta.abs() >= 0.5;
                final v = (r['voucher'] as Map?)?.cast<String, Object?>();
                if (want != (v != null)) {
                  bad('$label: سند تعديل الفاتورة ${v == null ? 'لم يُنشأ' : 'أُنشئ'} (قبل ${bf['payment']} ${bf['total']}، بعد ${r['ptype']} $t)');
                } else if (v != null) {
                  if (!near(v['amount'], delta.abs())) bad('$label: سند التعديل ${v['amount']} والفرق ${delta.abs()}');
                  if (v['kind'] != (delta < 0 ? 'refund' : 'receipt')) bad('$label: نوع سند التعديل ${v['kind']} والفرق $delta');
                  count('سند تعديل ${delta < 0 ? 'رد' : 'قبض'}');
                }
              }
              // المخزون: هذه الفاتورة تُحسب بأسطرها المحفوظة الآن
              final uuid = r['uuid'] as String;
              final m = <int, double>{};
              for (final x in savedItems) {
                final pid = (x['prodId'] as num?)?.toInt();
                if (pid != null) m[pid] = (m[pid] ?? 0) + dd(x['qty']);
              }
              sold[uuid] = m;
              if (rnd.nextDouble() < 0.1) await checkStock(label);
              // الشاشة بعد الحفظ تعرض ما حُفظ
              scr.inv = uuid;
              scr.ptype = '${r['ptype']}';
              scr.discount = dd(r['discount']);
              scr.fee = dd(r['fee']);
              scr.paid = paid;
              scr.name = '${c['name']}';
              last = r;
              lastPrepaid = dd(r['prepaid']);
              pendingMove = false;
              pendingSpaces = false;
              count('حفظ ${bf == null ? 'جديدة' : 'تعديل'} ${scr.ptype}');
          }
          trail.add(st);
          if (st == 'save') trail.clear();
          if (problems.length >= _maxProblems) break;
        }
        if (sc % 100 == 0 || sc == _scenarios) await deepChecks('بعد السيناريو $sc');
        if (sc % 20 == 0) {
          final line = '$sc/$_scenarios سيناريو — $saves حفظ — مشاكل ${problems.length} — ${sw.elapsed.inMinutes} دقيقة';
          progress.writeAsStringSync(line);
          print('⏳ $line');
        }
      }
      for (final e in (await h.deviceErrors()).take(5)) {
        bad('خطأ غير ممسوك: $e');
      }
      failed = problems.isNotEmpty;
    } finally {
      final keys = stats.keys.toList()..sort();
      final s = StringBuffer()
        ..writeln('سيناريوهات الفاتورة — seed=$seed — ${failed ? 'FAIL' : 'PASS'} — ${sw.elapsed.inMinutes} دقيقة')
        ..writeln('$_scenarios سيناريو (${combos.length} تركيبة مختلفة) — $steps خطوة — $saves حفظ')
        ..writeln('مشاكل: ${problems.length}')
        ..writeAll(problems.take(_maxProblems).map((p) => '  ✗ $p\n'))
        ..writeln('ملاحظات (سلوك يقرّره صاحب المحل):')
        ..writeAll(notes.map((p) => '  ℹ️ $p\n'))
        ..writeln('العمليات:')
        ..writeAll(keys.map((k) => '  $k: ${stats[k]}\n'));
      File('${out.path}${Platform.pathSeparator}summary.txt').writeAsStringSync(s.toString());
      print(s);
      await h.dispose();
    }
    expect(problems, isEmpty);
  }, timeout: const Timeout(Duration(hours: 12)));
}

extension on String {
  String characters_(int n) => length <= n ? this : '${substring(0, n)}…';
}
