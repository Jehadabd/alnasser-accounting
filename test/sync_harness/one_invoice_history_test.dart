// test/sync_harness/one_invoice_history_test.dart
//
// 🧾 فاتورة واحدة بين عميلين — قاعدة بيانات جديدة تُبنى بكود البرنامج نفسه، ثم تُفتح في البرنامج.
//
//   • عميلان، ولكل واحد 100 معاملة يدوية (دين وتسديد)، وكل معاملة تُعدَّل 20 مرة من حوار
//     «تعديل المعاملة» في بطاقة العميل أو زر «تحويل النوع»: المبلغ، كسور الدينار، مبلغ أقل من
//     نصف دينار، دين ⇄ تسديد، تسديد أكبر من الرصيد، الملاحظة، مسحها، التاريخ، الإرجاع للأصل.
//   • فاتورة واحدة تمر بـ 1000 سيناريو تعديل كما في شاشة الفاتورة: نقلها بين الاسمين، تعديل
//     اسم العميل في بطاقته، الكمية، السعر، نوع البيع (قطعة ⇄ كرتون)، إضافة صنف وحذفه، الخصم،
//     أجور النقل، المسدد، نقد ⇄ دين — ثم «حفظ»، وكثيراً «الإرجاع بالعكس» ثم «حفظ».
//   • معاملات العميلين تُعدَّل بين سيناريوهات الفاتورة (لا قبلها كلها)، فيتداخل الاثنان.
//
// بعد كل حفظ وكل تعديل معاملة يُفحص: الإجمالي والخصم والنقل والمسدد ونوع الدفع، صاحب الفاتورة،
// دين كل عميل = معاملاته اليدوية + المتبقي من الفاتورة إن كانت له، الرصيد المخزّن = مجموع
// المعاملات، سند تعديل الفاتورة النقدية، المخزون، الرفض الصحيح (لا يغيّر شيئاً). وكل 100 سيناريو:
// الفحص العميق + الدفتر + سلسلة أرصدة الكشف. وفي النهاية: سجل تعديلات الفاتورة كما تبنيه شاشته.
//
// الناتج: test_results\one_invoice\debt_book.db (نسخة متسقة) + summary.txt
// التثبيت في البرنامج: claude_install_test_db.bat (منفصل، يطلب تأكيدك)
// التشغيل: claude_test_one_invoice.bat
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:alnaser/utils/iqd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _seedArg = int.fromEnvironment('SEED');
const _scenarios = int.fromEnvironment('SCENARIOS', defaultValue: 1000);
const _txPerCustomer = int.fromEnvironment('TXS', defaultValue: 100);
const _editsPerTx = int.fromEnvironment('TX_EDITS', defaultValue: 20);
const _keepProblems = 200;

const _nameA = 'زبون الاختبار الأول';
const _nameB = 'زبون الاختبار الثاني';
const _cartons = [12, 24, 10, 6, 20, 50];

class _Line {
  _Line(this.prod, this.qty, this.price, {this.large = false});
  final int prod;
  double qty;
  double price; // للقطعة، أو للكرتون إن كان [large]
  bool large;
  double get total => Iqd.up(qty * price); // InvoiceItem: السطر لأقرب دينار
  _Line copy() => _Line(prod, qty, price, large: large);
  Map<String, Object?> toArg() => {'prodId': prod, 'qty': qty, 'price': price, if (large) 'large': true};
}

/// حال شاشة الفاتورة — القواعد منقولة من create_invoice_screen.dart (كما في invoice_scenarios_test)
class _Screen {
  _Screen(this.name, this.ptype, this.items);
  String name;
  String ptype;
  List<_Line> items;
  double discount = 0;
  double fee = 0;
  double paid = 0;
  String? inv;
  bool get existing => inv != null;

  double r2(double v) => (v * 100).roundToDouble() / 100;
  double get itemsTotal => items.fold(0.0, (s, l) => s + l.total);

  void guardDiscount() {
    final cur = itemsTotal + fee;
    final maxDiscount = (cur / 2) - 1;
    if (discount > maxDiscount) discount = r2(maxDiscount > 0 ? maxDiscount : 0.0);
    if (discount < 0) discount = 0;
    if (existing && ptype == 'نقد') paid = r2(cur - discount);
  }

  void updatePaidIfCash() {
    if (ptype == 'نقد') {
      guardDiscount();
      paid = r2(max(0.0, itemsTotal + fee - discount));
    }
  }

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
    if (existing && ptype == 'نقد') paid = r2(itemsTotal - discount);
    guardDiscount();
    updatePaidIfCash();
  }

  void setFee(double v) {
    fee = v;
    guardDiscount();
    updatePaidIfCash();
  }
}

/// ما كانت عليه الشاشة وبطاقتا العميلين قبل السيناريو (لـ«الإرجاع بالعكس»)
class _Snap {
  _Snap(_Screen s, Map<String, String> names)
      : items = [for (final l in s.items) l.copy()],
        discount = s.discount,
        fee = s.fee,
        paid = s.paid,
        ptype = s.ptype,
        name = s.name,
        names = Map.of(names);
  final List<_Line> items;
  final double discount, fee, paid;
  final String ptype, name;
  final Map<String, String> names;
}

class _Tx {
  _Tx(this.uuid, this.cust, this.label, this.amount, this.note, this.date)
      : origAmount = amount,
        origNote = note,
        origDate = date;
  final String uuid, cust, label;
  double amount;
  String? note;
  String date;
  final double origAmount;
  final String? origNote;
  final String origDate;
  int edits = 0;
}

void main() {
  final seed = _seedArg != 0 ? _seedArg : DateTime.now().microsecondsSinceEpoch % 1000000 + 1;
  test('فاتورة واحدة بين عميلين: $_scenarios سيناريو، $_txPerCustomer معاملة لكل عميل × $_editsPerTx تعديل — seed=$seed',
      () async {
    print('🎲 seed=$seed');
    final out = Directory('test_results${Platform.pathSeparator}one_invoice').absolute..createSync(recursive: true);
    final sep = Platform.pathSeparator;
    final devDir = Directory('${out.path}${sep}device');
    if (devDir.existsSync()) devDir.deleteSync(recursive: true);
    final dbOut = File('${out.path}${sep}debt_book.db');
    if (dbOut.existsSync()) dbOut.deleteSync();
    final progress = File('${out.path}${sep}progress.txt');

    final h = Harness(seed: seed);
    final rnd = Random(seed * 31 + 7);
    final problems = <String>[];
    var problemCount = 0;
    final notes = <String>{};
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    void bad(String p) {
      problemCount++;
      if (problems.length < _keepProblems) problems.add(p);
      print('✗ $p');
    }

    final sw = Stopwatch()..start();
    var saves = 0, txEdits = 0, cartonSaves = 0;
    Map<String, Object?>? finalHistory;
    String invoiceNo = '';
    var failed = true;
    try {
      const dev = 'D1';
      await h.spawn(dev, dir: devDir.path);
      await h.initDevice(dev);
      Future<Map<String, Object?>> scen(String n, [Map<String, Object?> a = const {}]) async {
        final r = await h.d(dev).call('scen', {'op': n, 'args': a}, const Duration(minutes: 3));
        return r is Map ? r.cast<String, Object?>() : {'ok': true, 'value': r};
      }

      double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
      bool near(Object? a, Object? b, [double tol = 0.011]) => (dd(a) - dd(b)).abs() <= tol;
      T pick<T>(List<T> xs) => xs[rnd.nextInt(xs.length)];

      // ── المواد: مخزون كبير، ولكل مادة كرتون ──
      for (var i = 0; i < _cartons.length; i++) {
        await h.d(dev).call('addProduct', {'name': 'مادة اختبار ${i + 1}', 'stock': 1000000, 'carton': _cartons[i]});
      }
      final prodRows = ((await scen('prodIds'))['rows'] as List).cast<Map>();
      final prods = <int>[];
      final carton = <int, int>{};
      final stock0 = <int, double>{};
      for (final r in prodRows) {
        final id = (r['id'] as num).toInt();
        final m = RegExp(r'(\d+)$').firstMatch('${r['name']}');
        if (m == null) continue;
        prods.add(id);
        carton[id] = _cartons[int.parse(m.group(1)!) - 1];
        stock0[id] = dd(r['stock']);
      }
      if (prods.length != _cartons.length) throw StateError('فشل التجهيز: ${prods.length} مادة');
      var sold = <int, double>{}; // ما تبيعه الفاتورة الآن بالوحدة الأساسية

      Future<void> checkStock(String label) async {
        final rows = ((await scen('prodIds'))['rows'] as List).cast<Map>();
        for (final r in rows) {
          final id = (r['id'] as num).toInt();
          if (!stock0.containsKey(id)) continue;
          final exp = stock0[id]! - (sold[id] ?? 0);
          if (!near(r['stock'], exp, 0.001)) bad('$label: مخزون المادة $id = ${r['stock']} والمتوقع $exp');
        }
      }

      // ── العميلان ──
      final ua = await h.addCustomer(dev, _nameA);
      final ub = await h.addCustomer(dev, _nameB);
      if (ua == null || ub == null) throw StateError('فشل إنشاء العميلين');
      final names = {ua: _nameA, ub: _nameB};
      final tag = {ua: 'أ', ub: 'ب'};
      String other(String c) => c == ua ? ub : ua;
      String? ownerOf(String name) {
        for (final e in names.entries) {
          if (e.value == name.trim()) return e.key;
        }
        return null;
      }

      // ── 100 معاملة يدوية لكل عميل (دين أكثر، وتسديد لا يتجاوز الرصيد) ──
      final txs = <String, _Tx>{};
      for (final c in [ua, ub]) {
        var bal = 0.0;
        for (var i = 1; i <= _txPerCustomer; i++) {
          final debt = i <= 3 || bal < 20000 || rnd.nextDouble() < 0.68;
          final amount = debt
              ? pick([5000.0, 12500.0, 250000.0, 75000.0, 1750.5, 40000.0, 99999.0, 3000.0])
              : -Iqd.down(min(bal * 0.4, pick([10000.0, 25000.0, 7500.0, 60000.0])));
          final note = 'يدوية ${tag[c]}-$i';
          final u = await h.d(dev).call('addTx', {'cust': c, 'amount': amount, 'marker': note}) as String?;
          if (u == null) {
            bad('لم تُحفظ المعاملة $note ($amount)');
            continue;
          }
          final r = await scen('txRow', {'tx': u});
          txs[u] = _Tx(u, c, note, dd(r['amount']), r['note'] as String?, '${r['date']}');
          bal += dd(r['amount']);
          count('معاملة جديدة ${debt ? 'دين' : 'تسديد'}');
        }
      }

      double manualSum(String c) => txs.values.where((t) => t.cust == c).fold(0.0, (s, t) => s + t.amount);

      // طابور تعديل المعاملات: كل معاملة [_editsPerTx] مرة، موزّعة بين سيناريوهات الفاتورة
      final queue = <String>[for (final u in txs.keys) for (var k = 0; k < _editsPerTx; k++) u]..shuffle(rnd);

      // ── الفاتورة ──
      _Line newLine() {
        final p = pick(prods);
        final large = rnd.nextDouble() < 0.25;
        return large
            ? _Line(p, pick([1.0, 2.0, 3.0]), pick([12000.0, 24000.0, 18000.5, 9999.0]), large: true)
            : _Line(p, pick([1.0, 2.0, 3.0, 0.5, 10.0, 2.5]), pick([1000.0, 2500.0, 750.0, 1250.0, 333.5]));
      }

      final scr = _Screen(_nameA, 'دين', [newLine(), newLine()]);
      Map<String, Object?>? last; // آخر حالة محفوظة للفاتورة
      String? owner; // صاحب الفاتورة الآن (من آخر حفظ)
      double remainingNow() => last == null ? 0.0 : (last!['ptype'] == 'نقد' ? 0.0 : dd(last!['total']) - dd(last!['paid']));
      int snapshots = 0;

      Future<void> checkDebts(String lbl) async {
        for (final c in [ua, ub]) {
          final r = await scen('custByUuid', {'cust': c});
          if (r['exists'] != true) {
            bad('$lbl: العميل ${tag[c]} اختفى');
            continue;
          }
          final want = manualSum(c) + (owner == c ? remainingNow() : 0.0);
          if (!near(r['debt'], r['txsum'])) bad('$lbl: «${r['name']}» دينه ${r['debt']} ≠ مجموع معاملاته ${r['txsum']}');
          if (!near(r['debt'], want)) {
            bad('$lbl: «${r['name']}» دينه ${r['debt']} والمتوقع $want (يدوية ${manualSum(c)}'
                '${owner == c ? ' + متبقي الفاتورة ${remainingNow()}' : ''})');
          }
        }
      }

      Future<void> deepChecks(String lbl) async {
        final dc = await h.d(dev).call('deepCheck', {}, const Duration(minutes: 10));
        if (dc is Map && ((dc['errors'] as num?) ?? 0) > 0) {
          bad('$lbl الفحص العميق: ${'${dc['text']}'.split('\n').take(8).join(' | ')}');
        }
        final lc = await h.d(dev).call('ledgerCheck', {}, const Duration(minutes: 10));
        if (lc is Map) {
          for (final p in ((lc['problems'] as List?) ?? const []).take(5)) {
            bad('$lbl الدفتر: $p');
          }
        }
        final cc = await scen('chainCheck', {
          'custs': [ua, ub]
        });
        for (final p in ((cc['problems'] as List?) ?? const []).take(5)) {
          bad('$lbl كشف الحساب: $p');
        }
        await checkStock(lbl);
        await checkDebts(lbl);
      }

      Future<bool> rename(String c, String to, String lbl) async {
        final r = await h.d(dev).call('renameCustomer', {'cust': c, 'name': to});
        if (r is Map && r['ok'] == true) {
          if (scr.name == names[c]) scr.name = to; // الشاشة تعرض اسم بطاقته
          names[c] = to;
          count('تعديل اسم العميل في بطاقته');
          return true;
        }
        bad('$lbl: تعذّر تعديل اسم العميل إلى «$to» (${r is Map ? r['err'] : r})');
        return false;
      }

      Future<void> save(String lbl) async {
        saves++;
        final before = last;
        final hasLarge = scr.items.any((l) => l.large);
        final h0 = scr.inv == null ? null : await scen('invHistory', {'inv': scr.inv});
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
          final err = '${r['err']}'.split('\n').first;
          count('رُفض الحفظ ($stage): ${err.length > 60 ? '${err.substring(0, 60)}…' : err}');
          if (stage == 'save' || stage == 'exception' || stage == 'load') {
            bad('$lbl: فشل الحفظ بعد اجتياز كل الفحوص ($stage): ${r['err']}');
          }
          if (stage == 'validate' && hasLarge) count('رفض تحقق وفيها سطر كرتون');
          if (before != null && scr.inv != null) {
            final now = await scen('invInfo', {'inv': scr.inv});
            for (final k in const ['total', 'paid', 'ptype', 'discount', 'fee', 'linked']) {
              if ('${now[k]}' != '${before[k]}') bad('$lbl: حفظ مرفوض غيّر $k من ${before[k]} إلى ${now[k]}');
            }
          }
          await checkDebts('$lbl (بعد حفظ مرفوض)');
          // الشاشة تبقى بما كُتب فيها: الحفظ التالي يعيد المحاولة (أو الإرجاع يعيدها لما كانت)
          return;
        }
        final fee = Iqd.up(scr.fee);
        final disc = Iqd.down(scr.discount);
        final lines = scr.items.fold<double>(0, (s, l) => s + l.total);
        final total = lines + fee - disc;
        if (r['ptype'] != scr.ptype) bad('$lbl: نوع الدفع المحفوظ ${r['ptype']} والشاشة ${scr.ptype}');
        if (!near(r['discount'], disc)) bad('$lbl: الخصم المحفوظ ${r['discount']} والمتوقع $disc');
        if (!near(r['fee'], fee)) bad('$lbl: أجور النقل المحفوظة ${r['fee']} والمتوقع $fee');
        if (!near(r['total'], total, 0.02)) bad('$lbl: الإجمالي ${r['total']} والمتوقع $total (أسطر $lines + نقل $fee − خصم $disc)');
        final savedItems = (r['items'] as List).cast<Map>();
        if (savedItems.length != scr.items.length) bad('$lbl: حُفظ ${savedItems.length} سطراً والشاشة ${scr.items.length}');
        final savedLarge = savedItems.where((x) => dd(x['qtyL']) > 0).length;
        final wantLarge = scr.items.where((l) => l.large).length;
        if (savedLarge != wantLarge) bad('$lbl: أسطر الكرتون المحفوظة $savedLarge والشاشة $wantLarge');
        if (savedLarge > 0) cartonSaves++;
        final paid = dd(r['paid']), t = dd(r['total']);
        if (scr.ptype == 'نقد') {
          if (!near(paid, t)) bad('$lbl: فاتورة نقدية مسددها $paid وإجماليها $t');
        } else {
          if (paid < -0.001 || paid > t + 0.001) bad('$lbl: فاتورة دين مسددها $paid خارج [0، $t]');
          final want = min(Iqd.down(scr.paid), t);
          if ((paid - want).abs() > 1.001) bad('$lbl: المسدد المحفوظ $paid والمكتوب ${scr.paid}');
        }
        final remaining = scr.ptype == 'نقد' ? 0.0 : t - paid;
        if (!near(r['linked'], remaining)) bad('$lbl: معاملات الفاتورة ${r['linked']} والمتبقي $remaining');
        final c = (r['cust'] as Map?)?.cast<String, Object?>();
        final wantOwner = ownerOf(scr.name);
        if (c == null) {
          bad('$lbl: الفاتورة بلا عميل');
        } else if ('${c['uuid']}' != wantOwner) {
          bad('$lbl: الفاتورة صارت للعميل «${c['name']}» والاسم المكتوب «${scr.name}»');
        }
        final prevOwner = owner;
        owner = c == null ? owner : '${c['uuid']}';
        if (prevOwner != null && owner != prevOwner) count('نقل الفاتورة إلى العميل الآخر');
        // سند تعديل الفاتورة النقدية
        final bf = (r['before'] as Map?)?.cast<String, Object?>();
        if (bf != null) {
          final delta = t - dd(bf['total']);
          final want = bf['payment'] == 'نقد' && r['ptype'] == 'نقد' && delta.abs() >= 0.5;
          final v = (r['voucher'] as Map?)?.cast<String, Object?>();
          if (want != (v != null)) {
            bad('$lbl: سند تعديل الفاتورة ${v == null ? 'لم يُنشأ' : 'أُنشئ'} (قبل ${bf['payment']} ${bf['total']}، بعد ${r['ptype']} $t)');
          } else if (v != null) {
            if (!near(v['amount'], delta.abs())) bad('$lbl: سند التعديل ${v['amount']} والفرق ${delta.abs()}');
            count('سند تعديل ${delta < 0 ? 'رد' : 'قبض'}');
          }
        }
        // المخزون بالأسطر المحفوظة الآن
        final m = <int, double>{};
        for (final x in savedItems) {
          final pid = (x['prodId'] as num?)?.toInt();
          if (pid != null) m[pid] = (m[pid] ?? 0) + dd(x['base']);
        }
        sold = m;
        // الشاشة بعد الحفظ تعرض ما حُفظ
        scr.inv = r['uuid'] as String;
        scr.ptype = '${r['ptype']}';
        scr.discount = dd(r['discount']);
        scr.fee = dd(r['fee']);
        scr.paid = paid;
        if (c != null) scr.name = '${c['name']}';
        last = r;
        count('حفظ ${bf == null ? 'جديدة' : 'تعديل'} ${scr.ptype}');
        await checkDebts(lbl);
        if (rnd.nextDouble() < 0.1) await checkStock(lbl);
        // 📜 السجل: هل أضاف الحفظ نسخة؟
        final h1 = await scen('invHistory', {'inv': scr.inv});
        final s1 = (h1['snapshots'] as num?)?.toInt() ?? 0;
        if (h0 != null) count(s1 > ((h0['snapshots'] as num?)?.toInt() ?? 0) ? 'حفظ تعديل أضاف نسخة للسجل' : 'حفظ تعديل بلا نسخة سجل جديدة');
        snapshots = s1;
      }

      // ── تعديل معاملة يدوية من حوار «تعديل المعاملة» أو زر «تحويل النوع» ──
      Future<void> editTx(String u) async {
        final t = txs[u]!;
        t.edits++;
        txEdits++;
        final lbl = 'معاملة ${t.label} تعديل ${t.edits}';
        final cust = await scen('custByUuid', {'cust': t.cust});
        final sumNow = dd(cust['txsum']);
        final others = sumNow - t.amount;
        final d0 = DateTime.parse(t.date);
        DateTime day(DateTime x, int plusDays) => DateTime(x.year, x.month, x.day + plusDays, x.hour, x.minute, x.second);
        final now = DateTime.now();

        const txKinds = ['up', 'down', 'frac', 'tiny', 'flip', 'convert', 'note', 'clearNote', 'earlier', 'later', 'combo', 'same', 'overpay', 'restore'];
        const txWeights = [10, 10, 6, 3, 8, 6, 8, 4, 7, 5, 8, 4, 4, 7];
        var x = rnd.nextInt(txWeights.reduce((a, b) => a + b));
        var kind = txKinds.last;
        for (var k = 0; k < txKinds.length; k++) {
          if (x < txWeights[k]) {
            kind = txKinds[k];
            break;
          }
          x -= txWeights[k];
        }
        if (t.edits == _editsPerTx) kind = 'restore'; // آخر تعديل: الإرجاع للأصل
        count('تعديل معاملة: $kind');

        if (kind == 'convert') {
          final r = await scen('txConvert', {'tx': u});
          final after = sumNow - 2 * t.amount;
          final expectRefuse = after < sumNow - 0.005 && after < -0.01;
          if (r['ok'] == true) {
            if (expectRefuse) bad('$lbl: قُبل تحويل النوع ورصيد العميل يصير $after');
            if (!near(r['amount'], -t.amount)) bad('$lbl: التحويل جعل المبلغ ${r['amount']} والمتوقع ${-t.amount}');
            t.amount = dd(r['amount']);
          } else {
            if (!expectRefuse) bad('$lbl: رُفض تحويل مسموح (${r['err']})');
            if (!near(r['amount'], t.amount)) bad('$lbl: تحويل مرفوض غيّر المبلغ إلى ${r['amount']}');
            count('رفض صحيح: تحويل يجعل الرصيد سالباً');
          }
          final wantType = t.amount >= 0 ? 'manual_debt' : 'manual_payment';
          if (r['type'] != wantType) bad('$lbl: نوع المعاملة ${r['type']} ومبلغها ${t.amount}');
          await checkDebts(lbl);
          return;
        }

        var amount = t.amount;
        String? note = t.note;
        var date = t.date;
        switch (kind) {
          case 'up':
            amount = t.amount.sign * Iqd.up(t.amount.abs() * pick([1.1, 1.5, 2.0]) + pick([0.0, 500.0]));
          case 'down':
            amount = t.amount.sign * Iqd.up(max(1000.0, t.amount.abs() * pick([0.3, 0.5, 0.9])));
          case 'frac':
            amount = t.amount.sign * (Iqd.down(t.amount.abs()) + pick([0.5, 0.3, 0.75, 0.25]));
          case 'tiny':
            amount = t.amount >= 0 ? 0.3 : -0.3;
          case 'flip':
            amount = -t.amount; // الضغط على «دين» أو «تسديد» في الحوار
          case 'note':
            note = 'ملاحظة ${t.label} ${t.edits}';
          case 'clearNote':
            note = '';
          case 'earlier':
            date = day(d0, -pick([1, 3, 10, 45])).toIso8601String();
          case 'later':
            final l = day(d0, pick([1, 2, 7]));
            date = (l.isAfter(now) ? now : l).toIso8601String();
          case 'combo':
            amount = t.amount.sign * Iqd.up(t.amount.abs() * pick([0.8, 1.2]));
            note = 'معدلة ${t.label} ${t.edits}';
            date = day(d0, -pick([1, 2, 5])).toIso8601String();
          case 'same':
            break;
          case 'overpay':
            amount = -Iqd.up(max(sumNow, 0) + pick([1000.0, 50000.0]) + max(0.0, t.amount)); // تسديد أكبر من الرصيد كله
          case 'restore':
            amount = t.origAmount;
            note = t.origNote;
            date = t.origDate;
        }
        // 💵 كما يحسبه التطبيق: دينار صحيح، والكسر يُقبل فقط إن جعل الرصيد صحيحاً
        final ledger = Iqd.ledgerAmount(amount, others);
        final expectRefuse = (ledger == 0 && amount.abs() > 0.0001) ||
            (others + ledger < sumNow - 0.005 && others + ledger < -0.01);
        final r = await scen('txEdit', {'tx': u, 'amount': amount, 'note': note ?? '', 'date': date});
        if (r['ok'] == true) {
          if (expectRefuse) bad('$lbl ($kind): قُبل تعديل كان يجب رفضه (المبلغ $amount، الرصيد يصير ${others + ledger})');
          if (!near(r['amount'], ledger, 0.001)) bad('$lbl ($kind): المبلغ المحفوظ ${r['amount']} والمتوقع $ledger (المكتوب $amount)');
          final wantType = dd(r['amount']) >= 0 ? 'manual_debt' : 'manual_payment';
          if (r['type'] != wantType) bad('$lbl ($kind): نوع المعاملة ${r['type']} ومبلغها ${r['amount']}');
          if (!DateTime.parse('${r['date']}').isAtSameMomentAs(DateTime.parse(date))) {
            bad('$lbl ($kind): التاريخ المحفوظ ${r['date']} والمختار $date');
          }
          final typed = (note ?? '').trim();
          final stored = (r['note'] as String?) ?? '';
          if (typed.isNotEmpty && stored != typed) bad('$lbl ($kind): الملاحظة المحفوظة «$stored» والمكتوبة «$typed»');
          if (typed.isEmpty && stored.isNotEmpty) {
            notes.add('مسح ملاحظة معاملة من حوار «تعديل المعاملة» لا يُحفظ: تبقى الملاحظة القديمة '
                '(copyWith يتجاهل الملاحظة الفارغة). مثال: «$stored»');
            count('مسح ملاحظة لم يُحفظ');
          }
          t.amount = dd(r['amount']);
          t.note = r['note'] as String?;
          t.date = '${r['date']}';
          if (dd(r['amount']) != amount) count('تقريب المبلغ لدينار صحيح');
        } else {
          if (r['stage'] == 'load') {
            bad('$lbl ($kind): ${r['err']}');
            return;
          }
          if (!expectRefuse) bad('$lbl ($kind): رُفض تعديل مسموح (المبلغ $amount): ${r['err']}');
          if (!near(r['amount'], t.amount, 0.001) || '${r['date']}' != t.date || (r['note'] as String?) != t.note) {
            bad('$lbl ($kind): تعديل مرفوض غيّر المعاملة (المبلغ ${r['amount']}، التاريخ ${r['date']}، الملاحظة ${r['note']})');
          }
          count('رفض صحيح: ${ledger == 0 ? 'أقل من نصف دينار' : 'الرصيد يصير سالباً'}');
        }
        await checkDebts(lbl);
      }

      // ── سيناريوهات الفاتورة ──
      const ops = ['name', 'rename', 'qty', 'price', 'saleType', 'add', 'remove', 'discount', 'fee', 'paid', 'cash', 'credit'];
      const weights = [12, 5, 12, 9, 9, 6, 6, 8, 5, 8, 10, 10];
      String randomOp() {
        var x = rnd.nextInt(weights.reduce((a, b) => a + b));
        for (var k = 0; k < ops.length; k++) {
          if (x < weights[k]) return ops[k];
          x -= weights[k];
        }
        return 'qty';
      }

      Future<void> apply(String op, String lbl) async {
        switch (op) {
          case 'name':
            final cur = ownerOf(scr.name) ?? ua;
            scr.name = names[other(cur)]!; // كتابة اسم العميل الآخر في الفاتورة
          case 'rename':
            final cur = ownerOf(scr.name) ?? ua;
            final base = cur == ua ? _nameA : _nameB;
            await rename(cur, names[cur] == base ? '$base (معدّل)' : base, lbl);
          case 'qty':
            final l = pick(scr.items);
            l.qty = l.large ? pick([1.0, 2.0, 4.0, 5.0]) : pick([1.0, 4.0, 0.5, 7.0, 12.0, 3.0]);
            scr.recalc();
          case 'price':
            final l = pick(scr.items);
            l.price = l.large ? pick([15000.0, 30000.0, 20000.5, 8000.0]) : pick([1500.0, 800.0, 2000.0, 333.5, 50.0]);
            scr.recalc();
          case 'saleType':
            // تغيير نوع البيع للسطر: قطعة ⇄ كرتون (السعر يصير سعر الوحدة الجديدة)
            final l = pick(scr.items);
            final per = carton[l.prod]!;
            if (l.large) {
              l.large = false;
              l.price = Iqd.up(l.price / per);
            } else {
              l.large = true;
              l.price = Iqd.up(l.price * per);
              l.qty = max(1.0, l.qty.roundToDouble());
            }
            count('تغيير نوع البيع ${l.large ? 'إلى كرتون' : 'إلى قطعة'}');
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
          case 'cash':
            scr.toCash();
          case 'credit':
            scr.toCredit();
        }
      }

      final perScenario = <int>[];
      {
        // توزيع تعديلات المعاملات على السيناريوهات بالتساوي تقريباً
        var left = queue.length;
        for (var sc = 0; sc < _scenarios; sc++) {
          final n = (left / (_scenarios - sc)).ceil();
          perScenario.add(n);
          left -= n;
        }
      }
      var qi = 0;

      // الحفظ الأول: فاتورة جديدة باسم العميل الأول
      await save('إنشاء الفاتورة');
      if (scr.inv == null) throw StateError('لم تُحفظ الفاتورة الأولى');

      for (var sc = 1; sc <= _scenarios; sc++) {
        final snap = _Snap(scr, names);
        final steps = <String>[];
        for (var k = 1 + rnd.nextInt(4); k > 0; k--) {
          final op = randomOp();
          steps.add(op);
          await apply(op, 'س$sc ${steps.join('›')}');
        }
        await save('س$sc ${steps.join('›')}›حفظ');
        if (rnd.nextDouble() < 0.2) {
          final op = randomOp();
          steps.add('حفظ›$op');
          await apply(op, 'س$sc ${steps.join('›')}');
          await save('س$sc ${steps.join('›')}›حفظ');
        }
        if (rnd.nextDouble() < 0.45) {
          // ↩️ الإرجاع بالعكس: البطاقتان والشاشة كما كانتا قبل السيناريو، ثم حفظ
          for (final e in snap.names.entries) {
            if (names[e.key] != e.value) await rename(e.key, e.value, 'س$sc إرجاع الاسم');
          }
          scr.items = [for (final l in snap.items) l.copy()];
          scr.discount = snap.discount;
          scr.fee = snap.fee;
          scr.ptype = snap.ptype;
          scr.paid = snap.paid;
          scr.name = snap.name;
          scr.recalc();
          count('إرجاع بالعكس');
          await save('س$sc ${steps.join('›')}›حفظ›إرجاع›حفظ');
        }
        for (var k = 0; k < perScenario[sc - 1] && qi < queue.length; k++) {
          await editTx(queue[qi++]);
        }
        if (sc % 100 == 0 || sc == _scenarios) await deepChecks('بعد السيناريو $sc');
        if (sc % 10 == 0) {
          final line = '$sc/$_scenarios سيناريو — $saves حفظ — $txEdits تعديل معاملة — مشاكل $problemCount — ${sw.elapsed.inMinutes} دقيقة';
          progress.writeAsStringSync(line);
          print('⏳ $line');
        }
      }
      while (qi < queue.length) {
        await editTx(queue[qi++]);
      }
      await deepChecks('النهاية');

      // 📜 السجل النهائي كما تبنيه شاشة «سجل التعديلات»
      finalHistory = await scen('invHistory', {'inv': scr.inv});
      if (((finalHistory['unknown'] as num?) ?? 0) > 0) {
        bad('سجل التعديلات: ${finalHistory['unknown']} نسخة لا تُبنى بدقة (تظهر «غير معروفة»)');
      }
      if (snapshots == 0) bad('سجل التعديلات فارغ بعد $saves حفظ');
      if (cartonSaves == 0) bad('لم يُحفظ أي سطر بالكرتون طوال الاختبار');
      final no = await h.d(dev).call('sqlRaw', {'sql': "SELECT invoice_number AS n FROM invoices WHERE invoice_uuid = '${scr.inv}'"});
      if (no is List && no.isNotEmpty) invoiceNo = '${(no.first as Map)['n'] ?? ''}';
      for (final e in (await h.deviceErrors()).take(5)) {
        bad('خطأ غير ممسوك: $e');
      }
      // 💾 نسخة متسقة من القاعدة (VACUUM INTO) — هي ما يُثبَّت في البرنامج
      await h.d(dev).call('shutdown', {'copyTo': dbOut.path}, const Duration(minutes: 5));
      if (!dbOut.existsSync()) bad('لم تُكتب نسخة القاعدة ${dbOut.path}');
      for (final c in [ua, ub]) {
        final r = await scen('custByUuid', {'cust': c});
        stats['— دين «${names[c]}» في النهاية'] = dd(r['debt']).round();
      }
      failed = problemCount > 0;
    } finally {
      final keys = stats.keys.toList()..sort();
      final s = StringBuffer()
        ..writeln('فاتورة واحدة بين عميلين — seed=$seed — ${failed ? 'FAIL' : 'PASS'} — ${sw.elapsed.inMinutes} دقيقة')
        ..writeln('$_scenarios سيناريو — $saves حفظ للفاتورة — $txEdits تعديل معاملة (${_txPerCustomer * 2} معاملة × $_editsPerTx)')
        ..writeln('الفاتورة: ${invoiceNo.isEmpty ? '؟' : invoiceNo} — العميلان: $_nameA ، $_nameB')
        ..writeln(finalHistory == null
            ? 'سجل التعديلات: لم يُقرأ'
            : 'سجل التعديلات: ${finalHistory!['snapshots']} نسخة (غير معروفة ${finalHistory!['unknown']}) — '
                'أحداث تعديل ${finalHistory!['events']} — سندات تعديل ${finalHistory!['vouchers']} — تسويات ${finalHistory!['adjustments']}')
        ..writeln('القاعدة: ${dbOut.existsSync() ? dbOut.path : 'لم تُكتب'}')
        ..writeln('مشاكل: $problemCount${problemCount > problems.length ? ' (أول ${problems.length})' : ''}')
        ..writeAll(problems.map((p) => '  ✗ $p\n'))
        ..writeln('ملاحظات (سلوك يقرّره صاحب المحل):')
        ..writeAll(notes.map((p) => '  ℹ️ $p\n'))
        ..writeln('العمليات:')
        ..writeAll(keys.map((k) => '  $k: ${stats[k]}\n'));
      File('${out.path}${sep}summary.txt').writeAsStringSync(s.toString());
      print(s);
      await h.dispose();
    }
    expect(problems, isEmpty);
  }, timeout: const Timeout(Duration(hours: 12)));
}
