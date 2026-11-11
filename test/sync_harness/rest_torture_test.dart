// test/sync_harness/rest_torture_test.dart
//
// 🔨 اختبار البقية القاسي — ما لا يمر به الاختبار الشامل، على الكود الحقيقي وجهازين
// يتزامنان:
//   • الكاشير: بيع نقد ودين، خصم مكتوب بكسور، مواد بالقطعة.
//   • وصل القبض المركّب: عدة عملاء في وصل واحد، تسديد وخصم، بالدينار وبالدولار.
//   • قاعدة الرصيد السالب في تعديل المعاملة اليدوية وتحويلها (يجب أن تُرفض).
//   • الموردون: فواتير شراء مسودة ومؤكدة بالدينار والدولار، تعديل مع عكس الأثر،
//     إلغاء (يُمنع إن عليها مرتجع)، دفعات وإلغاؤها، رصيد افتتاحي يستبدل ولا يتراكم،
//     مرتجعات على الدين ونقداً وإلغاؤها — والمخزون يتبعها على الجهازين.
//   • مرتجع مبيعات على الحساب من فاتورة الكاشير.
//   • الاستيراد من Excel: عملاء جدد وموجودون (دمج / مبلغ الملف / الدين الحالي)،
//     موردون بالعملتين، ومواد بكميتها وسعرها.
//   • 🔌 انقطاع مفاجئ: فعل يبدأ ثم يُقتل الجهاز في منتصفه؛ ما حُفظ على القرص هو ما
//     يبقى. بعد إعادة التشغيل: لا شيء نصفه محفوظ ونصفه ضائع، والأرصدة سليمة.
// كل مبلغ يُتوقَّع بقاعدة الدينار الصحيح (lib/utils/iqd.dart) ويُقارن بما حفظه التطبيق.
//
// التشغيل: claude_test_rest.bat [quick|full] [seed]
//   flutter test test/sync_harness/rest_torture_test.dart --dart-define=QUICK=true --dart-define=SEED=123
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:alnaser/utils/iqd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _quick = bool.fromEnvironment('QUICK');
const _seedArg = int.fromEnvironment('SEED');
const _ops = int.fromEnvironment('OPS', defaultValue: _quick ? 400 : 4000);
const _crashes = int.fromEnvironment('CRASHES', defaultValue: _quick ? 8 : 60);
const _perDev = int.fromEnvironment('CUSTOMERS', defaultValue: _quick ? 4 : 12);
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 15);

class _Sup {
  _Sup(this.dev, this.id, this.currency);
  final String dev;
  final int id;
  final String currency;
  double opening = 0;
}

class _PInv {
  _PInv(this.sup, this.id, this.number);
  final _Sup sup;
  final int id;
  final String number;
  String status = 'draft';
  bool cancelled = false;
  double total = 0, paid = 0;
  Map<String, double> items = {};
}

class _PPay {
  _PPay(this.sup, this.id, this.amount);
  final _Sup sup;
  final int id;
  final double amount;
  bool voided = false;
}

class _PRet {
  _PRet(this.sup, this.id, this.inv, this.debt, this.items);
  final _Sup sup;
  final int id;
  final _PInv? inv;
  final double debt;
  final Map<String, double> items;
  bool voided = false;
}

void main() {
  final seed = _seedArg != 0 ? _seedArg : DateTime.now().microsecondsSinceEpoch % 1000000 + 1;
  test('اختبار البقية القاسي: $_ops عملية + $_crashes انقطاعاً seed=$seed', () async {
    print('🎲 seed=$seed — لإعادة هذا التشغيل: --dart-define=SEED=$seed');
    final h = Harness(seed: seed);
    final rnd = Random(seed * 31 + 7);
    final problems = <String>[];
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    var failed = true;
    final sw = Stopwatch()..start();
    final out = Directory('test_results${Platform.pathSeparator}rest')..createSync(recursive: true);
    final progress = File('${out.path}${Platform.pathSeparator}progress.txt');
    void bad(String p) {
      problems.add(p);
      print('✗ $p');
    }

    void near(String what, Object? got, double want, {double tol = 0.005}) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() > tol) bad('$what = $g والمتوقع $want');
    }

    try {
      const devs = ['D1', 'D2'];
      await h.start(2);

      // ─────────────────────────── البداية ───────────────────────────
      final home = <String, String>{}; // عميل ← جهازه الوحيد الذي يعمل عليه
      final custs = <String, List<String>>{for (final d in devs) d: []};
      var nameN = 0;
      for (final d in devs) {
        for (var i = 0; i < _perDev; i++) {
          final c = await h.addCustomer(d, 'زبون البقية ${++nameN}');
          if (c == null) continue;
          home[c] = d;
          custs[d]!.add(c);
        }
      }
      final prods = <String>[];
      const catalog = [('مادة أ', 250.0), ('مادة ب', 1750.0), ('مادة ج', 4000.0), ('مادة د', 33333.0), ('مادة هـ', 500.0)];
      for (final (n, _) in catalog) {
        final p = await h.addProduct(devs[prods.length % 2], 'بقية $n', 100000);
        if (p != null) prods.add(p);
      }
      final price = {for (var i = 0; i < prods.length; i++) prods[i]: catalog[i].$2};
      var errs = await h.settle();
      if (errs.isNotEmpty) bad('البداية: ${errs.first}');

      final sups = <_Sup>[];
      for (final d in devs) {
        for (final cur in const ['IQD', 'IQD', 'USD']) {
          final r = (await h.rest(d, 'supAdd', {'name': 'مورد $d ${sups.length + 1}', 'currency': cur}) as Map);
          if (r['ok'] == true) sups.add(_Sup(d, (r['id'] as num).toInt(), cur));
        }
      }
      final pinvs = <_PInv>[];
      final pays = <_PPay>[];
      final rets = <_PRet>[];
      final posInv = <String, Map<String, Object?>>{}; // فاتورة كاشير بدين ← تفاصيلها (للمرتجع)
      final sretQty = <String, double>{};
      var marker = 0;
      String mk() => 'R${seed}_${++marker}';

      double supBalance(_Sup s) =>
          s.opening +
          pinvs.where((i) => i.sup == s && i.status == 'confirmed' && !i.cancelled).fold(0.0, (a, i) => a + i.total - i.paid) -
          pays.where((p) => p.sup == s && !p.voided).fold(0.0, (a, p) => a + p.amount) -
          rets.where((r) => r.sup == s && !r.voided).fold(0.0, (a, r) => a + r.debt);

      double returnedOn(_PInv inv, String prod) =>
          rets.where((r) => r.inv == inv && !r.voided).fold(0.0, (a, r) => a + (r.items[prod] ?? 0));

      void moveStock(Map<String, double> items, double sign) {
        items.forEach((p, q) => h.truth.products[p]!.movements += sign * q);
      }

      Future<void> verifyLocal(String dev, String label) async {
        final inv = (await h.rest(dev, 'invariants') as List).cast<String>();
        for (final p in inv) {
          bad('$label/$dev: $p');
        }
      }

      Future<void> verifyCust(String c, String label) async {
        final b = ((await h.d(home[c]!).call('custBalance', {'cust': c}) as Map?) ?? const {}).cast<String, Object?>();
        near('$label: دين العميل على جهازه', b['debt'], h.truth.balance(c));
        near('$label: مجموع معاملاته', b['sum'], h.truth.balance(c));
      }

      Future<void> verifySuppliers(String dev, String label) async {
        final st = (await h.rest(dev, 'supState') as List).cast<Map>();
        for (final s in sups.where((s) => s.dev == dev)) {
          final row = st.firstWhere((x) => x['id'] == s.id, orElse: () => const {});
          if (row.isEmpty) {
            bad('$label: المورد ${s.id} غائب من $dev');
            continue;
          }
          near('$label: رصيد المورد ${s.id} (${s.currency})', row[s.currency == 'IQD' ? 'iqd' : 'usd'], supBalance(s),
              tol: s.currency == 'IQD' ? 0.005 : 0.011);
        }
      }

      // ─────────────────────────── الأفعال ───────────────────────────

      String randCust(String dev) => custs[dev]![rnd.nextInt(custs[dev]!.length)];

      List<Map<String, Object?>> cart() => [
            for (var k = 1 + rnd.nextInt(3); k > 0; k--)
              () {
                final p = prods[rnd.nextInt(prods.length)];
                return <String, Object?>{'prod': p, 'qty': (1 + rnd.nextInt(6)).toDouble(), 'price': price[p]};
              }()
          ];

      // 🧾 بيع كاشير
      Future<void> pos(String dev, String label) async {
        final withCust = rnd.nextDouble() < 0.85;
        final c = withCust ? randCust(dev) : null;
        final items = cart();
        final raw = items.fold(0.0, (s, x) => s + (x['qty'] as double) * (x['price'] as double));
        final lines = items.fold(0.0, (s, x) => s + Iqd.up((x['qty'] as double) * (x['price'] as double)));
        final discount = rnd.nextDouble() < 0.4 ? min([250.0, 0.5, 1250.75, raw * 0.07][rnd.nextInt(4)], raw * 0.3) : 0.0;
        final credit = c != null && rnd.nextDouble() < 0.6;
        final headerRaw = max(0.0, raw - discount);
        final paidRaw = credit ? [0.0, (headerRaw * 0.3), headerRaw][rnd.nextInt(3)] : headerRaw;
        final t = Iqd.invoiceTotals(itemsTotal: lines, discount: discount, loadingFee: 0, paid: paidRaw);
        final wantPaid = (paidRaw - headerRaw).abs() <= 0.01 ? t.total : t.paid;
        final r = (await h.rest(dev, 'pos', {'cust': c, 'items': items, 'ptype': credit ? 'دين' : 'نقد', 'discount': discount, 'paid': paidRaw}) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          bad('$label: رُفض بيع كاشير سليم (${r['err']})');
          return;
        }
        near('$label: إجمالي فاتورة الكاشير', r['total'], t.total);
        near('$label: مسدد فاتورة الكاشير', r['paid'], wantPaid);
        near('$label: خصمها', r['discount'], t.discount);
        if (c != null && r['cust'] != c) bad('$label: فاتورة الكاشير على عميل آخر ${r['cust']}');
        final uuid = r['uuid'] as String;
        h.truth.invoices[uuid] = TruthInvoice(c ?? '_بلا_عميل', dev, t.total, wantPaid, credit ? 'دين' : 'نقد', 'محفوظة')
          ..items = {for (final x in items) x['prod'] as String: 0.0};
        for (final x in items) {
          final ti = h.truth.invoices[uuid]!;
          ti.items[x['prod'] as String] = ti.items[x['prod'] as String]! + (x['qty'] as double);
        }
        if (credit) posInv[uuid] = {'cust': c, 'items': items};
        count(credit ? 'كاشير دين' : 'كاشير نقد');
        if (c != null) await verifyCust(c, label);
      }

      // 🧾 وصل قبض مركّب
      Future<void> receipt(String dev, String label, {String? marker2}) async {
        final pool = custs[dev]!.where((c) => h.truth.balance(c) >= 2000).toList()..shuffle(rnd);
        if (pool.isEmpty) return;
        final usd = rnd.nextDouble() < 0.25;
        const fx = 1310.0;
        final lines = <Map<String, Object?>>[];
        final want = <String, (double, double)>{};
        for (final c in pool.take(1 + rnd.nextInt(min(4, pool.length)))) {
          final bal = h.truth.balance(c);
          final payBase = [bal * 0.25, bal * 0.5, 1000.5, bal][rnd.nextInt(4)];
          final disc = rnd.nextDouble() < 0.25 ? min(250.0, bal - payBase).clamp(0.0, 250.0).toDouble() : 0.0;
          final amountFc = usd ? (payBase / fx * 100).floorToDouble() / 100 : payBase;
          final rawBase = usd ? ((amountFc * fx) * 100).roundToDouble() / 100 : amountFc;
          final pay = rawBase > 0 ? -Iqd.up(-rawBase) : 0.0;
          final d = disc > 0 ? -Iqd.up(-disc) : 0.0;
          if (pay + d > bal + 0.001 || (pay <= 0 && d <= 0)) continue;
          lines.add({'cust': c, 'amount': amountFc, 'discount': disc});
          want[c] = (pay, d);
        }
        if (lines.isEmpty) return;
        final mkr = marker2 ?? mk();
        final r = (await h.rest(dev, 'creceipt', {'lines': lines, 'currency': usd ? 'USD' : 'IQD', 'fx': usd ? fx : 1.0, 'marker': mkr}) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          bad('$label: رُفض وصل مركّب سليم (${r['err']})');
          return;
        }
        if ((r['errors'] as List).isNotEmpty) bad('$label: أخطاء أسطر الوصل: ${r['errors']}');
        _adoptReceipt(h, r, dev, want, label, bad, near);
        count('وصل مركّب ${lines.length} عملاء${usd ? ' بالدولار' : ''}');
        for (final c in want.keys) {
          await verifyCust(c, label);
        }
      }

      // 🛡️ الرصيد السالب: تعديل تسديد أو تحويل دين إلى تسديد يتجاوز الرصيد ⇒ يُرفض
      Future<void> negativeRule(String dev, String label) async {
        final c = randCust(dev);
        final bal = h.truth.balance(c);
        final m = mk();
        final r = (await h.rest(dev, 'tx', {'cust': c, 'amount': 5000.0, 'marker': m}) as Map);
        if (r['ok'] != true) {
          bad('$label: لم يُحفظ دين يدوي (${r['err']})');
          return;
        }
        final tx = ((await h.rest(dev, 'byNote', {'marker': m}) as List).cast<List>()).single;
        final u = tx[0] as String;
        h.truth.txs[u] = TruthTx(c, dev, 5000, 'manual_debt');
        final b = bal + 5000;
        if (rnd.nextBool()) {
          // تعديله إلى تسديد أكبر من الرصيد
          try {
            await h.d(dev).call('editTx', {'tx': u, 'amount': -(b + 1000)});
            bad('$label: قُبل تعديل يجعل رصيد العميل سالباً (رصيده $b)');
            h.truth.txs[u]!.amount = -(b + 1000);
          } catch (_) {
            count('رُفض كما يجب: تعديل يجعل الرصيد سالباً');
          }
        } else if (b - 2 * 5000 < -0.01) {
          try {
            await h.d(dev).call('convertTx', {'tx': u});
            bad('$label: قُبل تحويل دين إلى تسديد يجعل الرصيد سالباً (رصيده $b)');
            h.truth.txs[u]!.amount = -5000;
          } catch (_) {
            count('رُفض كما يجب: تحويل يجعل الرصيد سالباً');
          }
        } else {
          await h.d(dev).call('convertTx', {'tx': u});
          h.truth.txs[u]!.amount = -5000;
          count('تحويل دين إلى تسديد (مسموح)');
        }
        await verifyCust(c, label);
      }

      // ↩️ مرتجع مبيعات على الحساب من فاتورة كاشير
      Future<void> salesReturn(String dev, String label) async {
        final mine = posInv.entries.where((e) => home[e.value['cust']] == dev).toList();
        if (mine.isEmpty) return;
        final e = mine[rnd.nextInt(mine.length)];
        final c = e.value['cust'] as String;
        final line = (e.value['items'] as List).cast<Map>()[0];
        final prod = line['prod'] as String;
        final sold = (e.value['items'] as List).cast<Map>().where((x) => x['prod'] == prod).fold(0.0, (a, x) => a + (x['qty'] as double));
        final left = sold - (sretQty['${e.key}|$prod'] ?? 0);
        if (left < 1) return;
        final p = (line['price'] as double);
        final credit = Iqd.down(p * 1);
        if (h.truth.balance(c) < credit) return;
        final r = (await h.rest(dev, 'sret', {'cust': c, 'inv': e.key, 'prod': prod, 'qty': 1.0, 'price': p, 'marker': mk()}) as Map)
            .cast<String, Object?>();
        if (r['ok'] != true) {
          bad('$label: رُفض مرتجع مبيعات سليم (${r['err']})');
          return;
        }
        near('$label: إجمالي المرتجع', r['total'], credit);
        final txs = (await h.rest(dev, 'byNote', {'marker': 'مرتجع مبيعات رقم'}) as List).cast<List>();
        final t = txs.where((x) => x[0] == r['tx']).toList();
        if (t.isEmpty) {
          bad('$label: معاملة المرتجع غائبة');
        } else {
          near('$label: أثر المرتجع على الدين', t.first[2], -credit);
          h.truth.txs[r['tx'] as String] = TruthTx(c, dev, (t.first[2] as num).toDouble(), 'manual_payment');
        }
        h.truth.products[prod]!.movements += 1;
        sretQty['${e.key}|$prod'] = (sretQty['${e.key}|$prod'] ?? 0) + 1;
        count('مرتجع مبيعات');
        await verifyCust(c, label);
      }

      // 🏭 الموردون
      List<Map<String, Object?>> pItems() => [
            for (var k = 1 + rnd.nextInt(3); k > 0; k--)
              <String, Object?>{
                'prod': prods[rnd.nextInt(prods.length)],
                'qty': (1 + rnd.nextInt(20)).toDouble(),
                'price': [100.0, 333.33, 1250.5, 2000.0, 7.25][rnd.nextInt(5)],
              }
          ];

      (double, double, List<double>) expectPurchase(String cur, List<Map<String, Object?>> items, double paidRaw) {
        final raw = items.fold(0.0, (s, x) => s + (x['qty'] as double) * (x['price'] as double));
        if (cur != 'IQD') return (raw, paidRaw, [for (final x in items) (x['qty'] as double) * (x['price'] as double)]);
        final ls = [for (final x in items) Iqd.down((x['qty'] as double) * (x['price'] as double))];
        final total = ls.fold(0.0, (a, b) => a + b);
        var paid = (paidRaw - raw).abs() <= 0.01 ? total : Iqd.up(paidRaw);
        if (paidRaw <= raw + 0.01 && paid > total) paid = total;
        return (total, paid, ls);
      }

      Map<String, double> qtyOf(List<Map<String, Object?>> items) {
        final m = <String, double>{};
        for (final x in items) {
          m[x['prod'] as String] = (m[x['prod'] as String] ?? 0) + (x['qty'] as double);
        }
        return m;
      }

      Future<void> supplier(String dev, String label) async {
        final mine = sups.where((s) => s.dev == dev).toList();
        final s = mine[rnd.nextInt(mine.length)];
        final open = pinvs.where((i) => i.sup == s && !i.cancelled).toList();
        final w = rnd.nextDouble();
        if (w < 0.30 || open.isEmpty) {
          // فاتورة شراء جديدة
          final items = pItems();
          final raw = items.fold(0.0, (a, x) => a + (x['qty'] as double) * (x['price'] as double));
          final status = rnd.nextDouble() < 0.75 ? 'confirmed' : 'draft';
          final paidRaw = [0.0, raw * 0.4, raw][rnd.nextInt(3)];
          final (total, paid, ls) = expectPurchase(s.currency, items, paidRaw);
          final number = 'P-${mk()}';
          final r = (await h.rest(dev, 'supBuy', {'sup': s.id, 'number': number, 'currency': s.currency, 'status': status, 'items': items, 'paid': paidRaw}) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفضت فاتورة شراء سليمة (${r['err']})');
            return;
          }
          near('$label: إجمالي فاتورة الشراء', r['total'], total, tol: 0.011);
          near('$label: مدفوعها', r['paid'], paid, tol: 0.011);
          final got = (r['lines'] as List).map((x) => (x as num).toDouble()).toList();
          for (var k = 0; k < min(got.length, ls.length); k++) {
            near('$label: سطر الشراء $k', got[k], ls[k], tol: 0.011);
          }
          final inv = _PInv(s, (r['id'] as num).toInt(), number)
            ..status = status
            ..total = total
            ..paid = paid
            ..items = qtyOf(items);
          pinvs.add(inv);
          if (status == 'confirmed') moveStock(inv.items, 1);
          count('فاتورة شراء ${s.currency} ${status == 'confirmed' ? 'مؤكدة' : 'مسودة'}');
        } else if (w < 0.48) {
          // تعديل فاتورة مع عكس الأثر
          final inv = open[rnd.nextInt(open.length)];
          final items = pItems();
          final raw = items.fold(0.0, (a, x) => a + (x['qty'] as double) * (x['price'] as double));
          final status = rnd.nextDouble() < 0.8 ? 'confirmed' : 'draft';
          final paidRaw = [0.0, raw * 0.5, raw][rnd.nextInt(3)];
          final (total, paid, _) = expectPurchase(s.currency, items, paidRaw);
          final q = qtyOf(items);
          final hasRet = rets.any((r) => r.inv == inv && !r.voided);
          final allowed = !hasRet ||
              (status == 'confirmed' && inv.status == 'confirmed' && inv.items.keys.every((p) => (q[p] ?? 0) + 1e-9 >= returnedOn(inv, p)));
          final r = (await h.rest(dev, 'supEdit', {'id': inv.id, 'status': status, 'items': items, 'paid': paidRaw}) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            if (allowed) bad('$label: رُفض تعديل فاتورة شراء سليم (${r['err']})');
            if (!allowed) count('رُفض كما يجب: تعديل فاتورة عليها مرتجع');
            return;
          }
          if (!allowed) bad('$label: قُبل تعديل فاتورة شراء عليها مرتجع يمنعه');
          near('$label: إجمالي الفاتورة بعد التعديل', r['total'], total, tol: 0.011);
          near('$label: مدفوعها بعد التعديل', r['paid'], paid, tol: 0.011);
          if (inv.status == 'confirmed') moveStock(inv.items, -1);
          inv
            ..status = status
            ..total = total
            ..paid = paid
            ..items = q;
          if (status == 'confirmed') moveStock(q, 1);
          count('تعديل فاتورة شراء');
        } else if (w < 0.56) {
          // إلغاء فاتورة (يُمنع إن عليها مرتجع)
          final inv = open[rnd.nextInt(open.length)];
          final hasRet = rets.any((r) => r.inv == inv && !r.voided);
          final r = (await h.rest(dev, 'supCancel', {'id': inv.id}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            if (!hasRet) bad('$label: رُفض إلغاء فاتورة شراء سليم (${r['err']})');
            if (hasRet) count('رُفض كما يجب: إلغاء فاتورة عليها مرتجع');
            return;
          }
          if (hasRet) bad('$label: أُلغيت فاتورة شراء عليها مرتجع');
          if (inv.status == 'confirmed') moveStock(inv.items, -1);
          inv.cancelled = true;
          count('إلغاء فاتورة شراء');
        } else if (w < 0.72) {
          // دفعة للمورد
          final bal = supBalance(s);
          if (bal <= 1) return;
          final raw = [bal * 0.3, bal, 1000.5, 7.75][rnd.nextInt(4)];
          final amount = s.currency == 'IQD' ? Iqd.up(raw) : ((raw * 100).roundToDouble() / 100);
          final m = mk();
          final r = (await h.rest(dev, 'supPay', {'sup': s.id, 'amount': raw, 'currency': s.currency, 'marker': m}) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true || r['id'] == null) {
            bad('$label: رُفضت دفعة مورد سليمة (${r['err']})');
            return;
          }
          near('$label: مبلغ الدفعة المحفوظ', r['amount'], amount, tol: 0.011);
          pays.add(_PPay(s, (r['id'] as num).toInt(), amount));
          count('دفعة مورد ${s.currency}');
        } else if (w < 0.78) {
          final live = pays.where((p) => p.sup == s && !p.voided).toList();
          if (live.isEmpty) return;
          final p = live[rnd.nextInt(live.length)];
          final r = (await h.rest(dev, 'supVoidPay', {'id': p.id}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفض إلغاء دفعة (${r['err']})');
            return;
          }
          p.voided = true;
          final again = (await h.rest(dev, 'supVoidPay', {'id': p.id}) as Map).cast<String, Object?>();
          if (again['ok'] == true) bad('$label: أُلغيت الدفعة نفسها مرتين');
          count('إلغاء دفعة مورد');
        } else if (w < 0.84) {
          // الرصيد الافتتاحي: يستبدل ولا يتراكم
          final raw = [0.0, 25000.5, 100000.0, -5000.0, 333.25][rnd.nextInt(5)];
          final r = (await h.rest(dev, 'supOpen', {'sup': s.id, 'amount': raw, 'currency': s.currency}) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفض رصيد افتتاحي (${r['err']})');
            return;
          }
          s.opening = s.currency == 'IQD' ? Iqd.down(raw) : raw;
          count('رصيد افتتاحي للمورد');
        } else if (w < 0.95) {
          // مرتجع مشتريات (على الدين أو نقداً، من فاتورة أو بلا فاتورة)
          final fromInv = rnd.nextBool() ? open.where((i) => i.status == 'confirmed').toList() : <_PInv>[];
          final inv = fromInv.isEmpty ? null : fromInv[rnd.nextInt(fromInv.length)];
          final prod = inv == null ? prods[rnd.nextInt(prods.length)] : inv.items.keys.first;
          final left = inv == null ? 1e9 : (inv.items[prod] ?? 0) - returnedOn(inv, prod);
          if (left < 1) return;
          final qty = min(left, (1 + rnd.nextInt(3)).toDouble());
          final pr = [100.0, 1250.5, 7.25][rnd.nextInt(3)];
          final lineRaw = qty * pr;
          final total = s.currency == 'IQD' ? Iqd.up(lineRaw) : ((lineRaw * 100).roundToDouble() / 100);
          final mode = rnd.nextDouble() < 0.7 ? 'debt' : 'cash';
          final r = (await h.rest(dev, 'supRet', {
            'sup': s.id,
            'inv': inv?.id,
            'currency': s.currency,
            'mode': mode,
            'cash': 0.0,
            'items': [
              {'prod': prod, 'qty': qty, 'price': pr}
            ],
          }) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفض مرتجع مشتريات سليم (${r['err']})');
            return;
          }
          near('$label: إجمالي مرتجع المشتريات', r['total'], total, tol: 0.011);
          rets.add(_PRet(s, (r['id'] as num).toInt(), inv, mode == 'debt' ? total : 0.0, {prod: qty}));
          h.truth.products[prod]!.movements -= qty;
          count('مرتجع مشتريات ${mode == 'debt' ? 'على الدين' : 'نقدي'}');
        } else {
          final live = rets.where((r) => r.sup == s && !r.voided).toList();
          if (live.isEmpty) return;
          final rt = live[rnd.nextInt(live.length)];
          final r = (await h.rest(dev, 'supVoidRet', {'id': rt.id}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفض إلغاء مرتجع مشتريات (${r['err']})');
            return;
          }
          rt.voided = true;
          rt.items.forEach((p, q) => h.truth.products[p]!.movements += q);
          count('إلغاء مرتجع مشتريات');
        }
        await verifySuppliers(dev, label);
      }

      // 📥 الاستيراد من Excel
      Future<void> doImport(String dev, String label) async {
        final kind = const ['customers', 'customers', 'suppliers', 'products'][rnd.nextInt(4)];
        final src = mk();
        if (kind == 'customers') {
          final rows = <List<Object?>>[['الاسم', 'الرصيد']];
          final newOnes = <String, double>{};
          for (var k = 1 + rnd.nextInt(3); k > 0; k--) {
            final n = 'مستورد ${++nameN}';
            final b = [15000.0, 2500.5, -1000.0, 0.0, 777.49][rnd.nextInt(5)];
            rows.add([n, '$b']);
            newOnes[n] = Iqd.up(b);
          }
          final existing = <String, (String, String, double)>{}; // اسم ← (عميل، اختيار، مبلغ)
          for (final c in (custs[dev]!.toList()..shuffle(rnd)).take(rnd.nextInt(3))) {
            final name = h.truth.customers[c]!.name;
            final b = [5000.0, 12500.5, 300.0][rnd.nextInt(3)];
            existing[name] = (c, const ['merge', 'useFile', 'keep'][rnd.nextInt(3)], b);
            rows.add([name, '$b']);
          }
          final r = (await h.rest(dev, 'import', {
            'kind': kind,
            'rows': rows,
            'source': src,
            'actions': {for (final e in existing.entries) e.key: e.value.$2},
          }, const Duration(minutes: 5)) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: فشل استيراد عملاء سليم (${r['err']})');
            return;
          }
          if (r['verified'] != true || (r['problems'] as List).isNotEmpty) bad('$label: الاستيراد لم يتحقق: ${r['problems']}');
          for (final x in (r['custs'] as List).whereType<List>()) {
            final u = x[0] as String, n = x[1] as String;
            h.truth.customers[u] = TruthCustomer(n, dev);
            home[u] = dev;
            custs[dev]!.add(u);
          }
          // المتوقع لكل معاملة جديدة
          final expect = <String, double>{};
          for (final e in newOnes.entries) {
            if (e.value.abs() > 0.0005) expect[e.key] = e.value;
          }
          for (final e in existing.entries) {
            final (c, act, b) = e.value;
            final f = Iqd.up(b);
            final cur = h.truth.balance(c);
            if (act == 'merge') expect[e.key] = f;
            if (act == 'useFile' && (f - cur).abs() > 0.0005) expect[e.key] = f - cur;
          }
          final txs = (r['txs'] as List).cast<List>();
          final byCust = <String, double>{};
          for (final t in txs) {
            final c = t[1] as String;
            byCust[c] = (byCust[c] ?? 0) + (t[2] as num).toDouble();
            h.truth.txs[t[0] as String] = TruthTx(c, dev, (t[2] as num).toDouble(), '${t[3]}');
          }
          String? custOf(String name) =>
              h.truth.customers.entries.where((e) => e.value.name == name).map((e) => e.key).firstOrNull;
          for (final e in expect.entries) {
            near('$label: أثر استيراد «${e.key}»', byCust[custOf(e.key)], e.value);
          }
          for (final c in byCust.keys) {
            final n = h.truth.customers[c]?.name;
            if (n == null || !expect.containsKey(n)) bad('$label: معاملة استيراد غير متوقعة على $n (${byCust[c]})');
          }
          count('استيراد عملاء');
          for (final c in byCust.keys) {
            await verifyCust(c, label);
          }
        } else if (kind == 'suppliers') {
          final rows = <List<Object?>>[['الاسم', 'الرصيد', 'العملة']];
          final want = <String, (String, double)>{};
          for (var k = 1 + rnd.nextInt(2); k > 0; k--) {
            final n = 'مورد مستورد ${mk()}';
            final usd = rnd.nextBool();
            final b = [25000.5, 1000.0, 12.75][rnd.nextInt(3)];
            rows.add([n, '$b', usd ? 'دولار' : 'دينار']);
            want[n] = (usd ? 'USD' : 'IQD', usd ? b : Iqd.down(b));
          }
          final r = (await h.rest(dev, 'import', {'kind': kind, 'rows': rows, 'source': src}, const Duration(minutes: 5)) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: فشل استيراد موردين سليم (${r['err']})');
            return;
          }
          for (final x in (r['sups'] as List).whereType<List>()) {
            final n = x[1] as String;
            final w2 = want[n];
            if (w2 == null) continue;
            if (x[2] != w2.$1) bad('$label: عملة المورد المستورد «$n» ${x[2]} والصحيح ${w2.$1}');
            sups.add(_Sup(dev, (x[0] as num).toInt(), w2.$1)..opening = w2.$2);
          }
          count('استيراد موردين');
          await verifySuppliers(dev, label);
        } else {
          final rows = <List<Object?>>[['المادة', 'السعر', 'الكمية']];
          final want = <String, (double, double)>{};
          for (var k = 1 + rnd.nextInt(2); k > 0; k--) {
            final n = 'مادة مستوردة ${mk()}';
            final pr = [1250.5, 3000.0, 99.49][rnd.nextInt(3)];
            final q = (10 + rnd.nextInt(90)).toDouble();
            rows.add([n, '$pr', '$q']);
            want[n] = (Iqd.up(pr), q);
          }
          final r = (await h.rest(dev, 'import', {'kind': kind, 'rows': rows, 'source': src}, const Duration(minutes: 5)) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: فشل استيراد مواد سليم (${r['err']})');
            return;
          }
          for (final x in (r['prods'] as List).whereType<List>()) {
            final n = x[1] as String;
            final w2 = want[n];
            if (w2 == null) continue;
            near('$label: سعر المادة المستوردة «$n»', x[2], w2.$1);
            near('$label: كميتها', x[3], w2.$2);
            h.truth.products[x[0] as String] = TruthProduct(n, dev, w2.$2, null);
            prods.add(x[0] as String);
            price[x[0] as String] = w2.$1;
          }
          count('استيراد مواد');
        }
      }

      // 🔌 انقطاع مفاجئ في منتصف فعل
      Future<void> crash(String dev, String label) async {
        final kind = const ['tx', 'receipt', 'pos', 'supPay'][rnd.nextInt(4)];
        final m = mk();
        final delay = rnd.nextInt(40);
        final c = randCust(dev);
        Map<String, Object?> args;
        String op;
        double? txAmount;
        final beforeInvs = <String>{};
        switch (kind) {
          case 'tx':
            op = 'tx';
            txAmount = [5000.0, 12500.0][rnd.nextInt(2)];
            args = {'cust': c, 'amount': txAmount, 'marker': m};
          case 'receipt':
            final bal = h.truth.balance(c);
            if (bal < 2000) return;
            op = 'creceipt';
            args = {
              'lines': [
                {'cust': c, 'amount': Iqd.down(bal * 0.5), 'discount': 0.0}
              ],
              'currency': 'IQD',
              'fx': 1.0,
              'marker': m,
            };
          case 'pos':
            op = 'pos';
            final d0 = (await h.d(dev).call('custDetail', {'cust': c}) as Map).cast<String, Object?>();
            for (final i in (d0['invoices'] as List).cast<Map>()) {
              beforeInvs.add(i['invoice_uuid'] as String);
            }
            args = {'cust': c, 'items': cart(), 'ptype': 'دين', 'discount': 0.0, 'paid': 0.0};
          default:
            final mine = sups.where((s) => s.dev == dev && supBalance(s) > 1000 && s.currency == 'IQD').toList();
            if (mine.isEmpty) return;
            op = 'supPay';
            final s = mine[rnd.nextInt(mine.length)];
            args = {'sup': s.id, 'amount': 1000.0, 'currency': 'IQD', 'marker': m};
        }
        await h.rest(dev, 'spawn', {'op': op, 'args': args, 'delayMs': delay});
        await h.restart(dev);
        count('انقطاع أثناء $kind');
        // ما الذي بقي؟ يُتبنّى في الحقيقة كما حُفظ (كله أو لا شيء)، ثم تُفحص الثوابت
        switch (kind) {
          case 'tx':
            final rows = (await h.rest(dev, 'byNote', {'marker': m}) as List).cast<List>();
            if (rows.length > 1) bad('$label: المعاملة نفسها حُفظت ${rows.length} مرات بعد الانقطاع');
            for (final t in rows) {
              near('$label: مبلغ المعاملة بعد الانقطاع', t[2], txAmount!);
              h.truth.txs[t[0] as String] = TruthTx(c, dev, (t[2] as num).toDouble(), 'manual_debt');
            }
            count(rows.isEmpty ? 'انقطاع: لم تُحفظ المعاملة' : 'انقطاع: حُفظت المعاملة');
          case 'receipt':
            final r = await h.rest(dev, 'receiptByNote', {'marker': m});
            if (r is Map) {
              _adoptReceipt(h, r.cast<String, Object?>(), dev, null, label, bad, near);
              count('انقطاع: حُفظ الوصل');
            } else {
              count('انقطاع: لم يُحفظ الوصل');
            }
            // تسديد سُجّل في الدين ولم يُسجَّل سطره في الوصل (أو لا وصل أصلاً) = نصف محفوظ
            final rows = (await h.rest(dev, 'byNote', {'marker': 'وصل قبض رقم'}) as List).cast<List>();
            final known = h.truth.txs.keys.toSet();
            for (final t in rows.where((t) => !known.contains(t[0]) && t[1] == c && t[3] == 0)) {
              bad('$label: تسديد وصل في سجل الديون بلا سطر في الوصل بعد الانقطاع (${t[2]})');
              h.truth.txs[t[0] as String] = TruthTx(c, dev, (t[2] as num).toDouble(), 'manual_payment');
            }
          case 'pos':
            final d1 = (await h.d(dev).call('custDetail', {'cust': c}) as Map).cast<String, Object?>();
            for (final i in (d1['invoices'] as List).cast<Map>()) {
              final u = i['invoice_uuid'] as String;
              if (beforeInvs.contains(u) || h.truth.invoices.containsKey(u)) continue;
              final det = (await h.d(dev).call('invoiceDetail', {'inv': u}) as Map).cast<String, Object?>();
              final items = (args['items'] as List).cast<Map>();
              final lines = items.fold(0.0, (s, x) => s + Iqd.up((x['qty'] as double) * (x['price'] as double)));
              near('$label: إجمالي فاتورة كاشير بعد الانقطاع', (det['invoice'] as Map)['total_amount'], lines);
              final gotItems = (det['items'] as List).length;
              if (gotItems != items.length) bad('$label: فاتورة كاشير بعد الانقطاع بـ$gotItems أسطر من ${items.length} (نصف محفوظة)');
              final ti = TruthInvoice(c, dev, lines, 0, 'دين', 'محفوظة');
              for (final x in items) {
                ti.items[x['prod'] as String] = (ti.items[x['prod'] as String] ?? 0) + (x['qty'] as double);
              }
              h.truth.invoices[u] = ti;
              count('انقطاع: حُفظت فاتورة الكاشير');
            }
          default:
            final r = await h.rest(dev, 'payByNote', {'marker': m});
            if (r is Map) {
              final s = sups.firstWhere((s) => s.id == args['sup'] && s.dev == dev);
              pays.add(_PPay(s, (r['id'] as num).toInt(), (r['amount'] as num).toDouble()));
              count('انقطاع: حُفظت دفعة المورد');
            } else {
              count('انقطاع: لم تُحفظ دفعة المورد');
            }
            await verifySuppliers(dev, label);
        }
        await verifyLocal(dev, '$label (بعد الانقطاع)');
        await verifyCust(c, '$label (بعد الانقطاع)');
      }

      // ─────────────────────────── الحلقة ───────────────────────────
      final crashAt = <int>{for (var k = 0; k < _crashes; k++) 20 + rnd.nextInt(max(1, _ops - 20))};
      final settleEvery = _quick ? 60 : 250;
      for (var i = 1; i <= _ops; i++) {
        if (problems.length >= _maxProblems) break;
        final dev = devs[rnd.nextInt(2)];
        final label = '#$i';
        final w = rnd.nextDouble();
        if (crashAt.contains(i)) {
          await crash(dev, '$label 🔌');
        } else if (w < 0.20) {
          await pos(dev, label);
        } else if (w < 0.32) {
          await receipt(dev, label);
        } else if (w < 0.38) {
          await negativeRule(dev, label);
        } else if (w < 0.42) {
          await salesReturn(dev, label);
        } else if (w < 0.80) {
          await supplier(dev, label);
        } else if (w < 0.85) {
          await doImport(dev, label);
        } else if (w < 0.92) {
          await h.setOnline(dev, rnd.nextBool());
          count('اتصال/انقطاع الشبكة');
        } else {
          // دين يدوي بكسور: يُقرَّب
          final c = randCust(dev);
          final m = mk();
          final amount = [1250.75, 0.5, 99999.5, 3000.0][rnd.nextInt(4)];
          final r = (await h.rest(dev, 'tx', {'cust': c, 'amount': amount, 'marker': m}) as Map);
          if (r['ok'] == true) {
            for (final t in (await h.rest(dev, 'byNote', {'marker': m}) as List).cast<List>()) {
              near('$label: دين يدوي $amount بعد التقريب', t[2], Iqd.up(amount));
              h.truth.txs[t[0] as String] = TruthTx(c, dev, (t[2] as num).toDouble(), 'manual_debt');
            }
            count('دين يدوي');
          } else {
            bad('$label: رُفض دين يدوي ${r['err']}');
          }
          await verifyCust(c, label);
        }
        if (i % settleEvery == 0 || i == _ops) {
          errs = await h.settle();
          for (final e in errs.take(5)) {
            bad('$label مزامنة: $e');
          }
          for (final d in devs) {
            await verifyLocal(d, '$label بعد المزامنة');
            await verifySuppliers(d, '$label بعد المزامنة');
          }
          final dc = <String>[];
          for (final d in devs) {
            final r = (await h.d(d).call('deepCheck', const {}, const Duration(minutes: 5)) as Map).cast<String, Object?>();
            if (((r['errors'] as num?) ?? 0) > 0) dc.add('$d: ${r['text']}');
          }
          for (final e in dc.take(5)) {
            bad('$label الفحص العميق: $e');
          }
        }
        if (i % 20 == 0) {
          final line = '$i/$_ops — مشاكل ${problems.length} — ${sw.elapsed.inMinutes} دقيقة';
          progress.writeAsStringSync(line);
          print('⏳ $line');
        }
      }
      final ue = await h.deviceErrors();
      for (final e in ue.take(5)) {
        bad('خطأ غير ممسوك: $e');
      }
      failed = problems.isNotEmpty;
    } finally {
      final keys = stats.keys.toList()..sort();
      final summary = StringBuffer()
        ..writeln('اختبار البقية القاسي — seed=$seed — ${failed ? 'FAIL' : 'PASS'} — ${sw.elapsed.inMinutes} دقيقة')
        ..writeln('مشاكل: ${problems.length}')
        ..writeAll(problems.take(_maxProblems).map((p) => '  ✗ $p\n'))
        ..writeln('العمليات:')
        ..writeAll(keys.map((k) => '  $k: ${stats[k]}\n'));
      File('${out.path}${Platform.pathSeparator}summary.txt').writeAsStringSync(summary.toString());
      print(summary);
      await h.dispose();
    }
    expect(problems, isEmpty);
  }, timeout: const Timeout(Duration(hours: 12)));
}

/// يتبنّى وصلاً محفوظاً في الحقيقة ويفحصه: رأسه = أسطره، وكل سطر بمبلغه المتوقع.
void _adoptReceipt(Harness h, Map<String, Object?> r, String dev, Map<String, (double, double)>? want, String label,
    void Function(String) bad, void Function(String, Object?, double, {double tol}) near) {
  final lines = (r['lines'] as List).cast<Map>();
  var sumA = 0.0, sumD = 0.0;
  for (final l in lines) {
    final c = l['cust'] as String;
    final a = (l['amount'] as num).toDouble(), d = (l['discount'] as num).toDouble();
    sumA += a;
    sumD += d;
    final w = want?[c];
    if (w != null) {
      near('$label: تسديد الوصل للعميل', a, w.$1);
      near('$label: خصم الوصل للعميل', d, w.$2);
    }
    if (l['pay'] != null) h.truth.txs[l['pay'] as String] = TruthTx(c, dev, -a, 'manual_payment');
    if (l['disc'] != null) h.truth.txs[l['disc'] as String] = TruthTx(c, dev, -d, 'manual_payment');
  }
  near('$label: إجمالي رأس الوصل = أسطره', r['total'], sumA);
  near('$label: خصم رأس الوصل = أسطره', r['disc'], sumD);
  if (want != null && lines.length != want.length) bad('$label: الوصل بـ${lines.length} أسطر من ${want.length}');
}
