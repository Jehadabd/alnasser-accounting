// test/sync_harness/features_torture_test.dart
//
// 🧩 الميزات المتبقية من «كل مسارات المال» — قاسٍ وعشوائي مع حالات قصوى، بكود التطبيق نفسه:
//   • مطابقة البنك: مطابقة بجزء عشوائي من الحركات، اعتمادها، رفض اعتماد بفرق، رفض مسودة
//     ثانية، رفض تاريخ قبل آخر مطابقة، إعادة الفتح ثم الاعتماد، حذف المسودة؛ والمطابقة لا
//     تغيّر الدفتر أبداً، والمطابَق سابقاً = ما اعتُمد ولم يُحذف مستنده ولم يتغيّر مبلغه.
//   • كلفة الشحن والتخليص: من الصندوق / إعادة تصنيف مصروف / كلفة فقط، بكسور وصفر وسالب وكمية
//     صفر (تُرفض)؛ أثرها على الصندوق بالضبط، والإلغاء يعيده.
//   • الدفعات وتواريخ الصلاحية: إضافة وحذف وكميات خاطئة (تُرفض)، والبيع لا يمس سجل الدفعات،
//     والتوزيع «الأقرب انتهاءً يخرج أولاً» صحيح دائماً.
//   • المحاسبة الإضافية: السند المركّب (متوازن، غير متوازن، حساب ذمم، سالب، مدين ودائن معاً،
//     دولار بمبلغ لا يطابق) وحذفه مرتين؛ إقفال السنة وإعادة فتحها مع التثبيت؛ إعادة تقييم
//     ذمم الموردين بالدولار وإعادتها في اليوم نفسه وحذفها.
//   • تعديل الفاتورة النقدية: سند الرد/القبض بمبلغ الفرق بالضبط، ولا يحرّك الدفتر (لا ازدواج).
//   • الحذف: لا تُحذف إلا الفاتورة المعلّقة، وحذفها لا يمس الدين؛ غير المعلّقة لا تُمس.
//   • سند القبض المؤرشف: الرصيد بعد = الرصيد الفعلي، والترقيم لا يتكرر.
//
// التشغيل: claude_test_features.bat [quick|full] [seed]
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _quick = bool.fromEnvironment('QUICK');
const _seedArg = int.fromEnvironment('SEED');
const _ops = int.fromEnvironment('OPS', defaultValue: _quick ? 300 : 3000);
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 15);

void main() {
  final seed = _seedArg != 0 ? _seedArg : DateTime.now().microsecondsSinceEpoch % 1000000 + 1;
  test('الميزات المتبقية: $_ops عملية seed=$seed', () async {
    print('🎲 seed=$seed');
    final h = Harness(seed: seed);
    final rnd = Random(seed * 31 + 7);
    final problems = <String>[];
    final notes = <String>{};
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    final sw = Stopwatch()..start();
    final out = Directory('test_results${Platform.pathSeparator}features')..createSync(recursive: true);
    final progress = File('${out.path}${Platform.pathSeparator}progress.txt');
    void bad(String p) {
      problems.add(p);
      print('✗ $p');
    }

    var failed = true;
    try {
      await h.start(1);
      const dev = 'D1';
      Future<Map<String, Object?>> call(String kind, String name, [Map<String, Object?> args = const {}]) async {
        final r = await h.d(dev).call(kind, {'op': name, 'args': args}, const Duration(minutes: 3));
        return r is Map ? r.cast<String, Object?>() : {'ok': true, 'value': r};
      }

      Future<Map<String, Object?>> acct(String n, [Map<String, Object?> a = const {}]) => call('acct', n, a);
      Future<Map<String, Object?>> feat(String n, [Map<String, Object?> a = const {}]) => call('feat', n, a);
      Future<Map<String, Object?>> rest(String n, [Map<String, Object?> a = const {}]) => call('rest', n, a);
      double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
      bool near(Object? a, Object? b, [double tol = 0.011]) => (dd(a) - dd(b)).abs() <= tol;
      T pick<T>(List<T> xs) => xs[rnd.nextInt(xs.length)];

      Future<Map<int, double>> boxes() async =>
          (await acct('boxBalances')).map((k, v) => MapEntry(int.parse(k), dd(v)));
      Future<String> ledger() async => '${(await feat('ledgerPrint'))['print']}';

      // ── التجهيز ──
      final setup = await acct('setup');
      final boxIds = (setup['boxes'] as List).map((x) => (x as num).toInt()).toList();
      final expense = (setup['expense'] as List).map((x) => (x as num).toInt()).toList();
      final revenue = (setup['revenue'] as List).map((x) => (x as num).toInt()).toList();
      final vaccs = (setup['accounts'] as List).map((x) => (x as num).toInt()).toList();
      final boxAcc = (await feat('boxAccounts'))..remove('ok');
      final boxOfAcc = {for (final e in boxAcc.entries) (e.value as num).toInt(): int.parse(e.key)};
      final info = ((await feat('accountsInfo'))['rows'] as List).cast<Map>();
      final free = [
        for (final r in info)
          if ((r['control'] as num? ?? 0) == 0 && !boxOfAcc.containsKey(r['id'])) (r['id'] as num).toInt()
      ];
      final control = [for (final r in info) if ((r['control'] as num? ?? 0) == 1) (r['id'] as num).toInt()];
      if (boxIds.length < 2 || free.length < 3 || expense.isEmpty || revenue.isEmpty) {
        bad('التجهيز: صناديق ${boxIds.length} حسابات ${free.length} مصروف ${expense.length} إيراد ${revenue.length}');
        throw StateError('فشل التجهيز');
      }
      final custs = <String>[];
      for (var i = 1; i <= 4; i++) {
        final u = await h.d(dev).call('addCustomer', {'name': 'زبون الميزات $i'});
        if (u is String) custs.add(u);
      }
      final prods = <String, int>{}; // uuid ← id
      for (var i = 1; i <= 3; i++) {
        final u = await h.d(dev).call('addProduct', {'name': 'مادة الميزات $i', 'stock': 200});
        if (u is String) prods[u] = (dd((await feat('productId', {'uuid': u}))['id'])).toInt();
      }
      final usdSup = (await rest('supAdd', {'name': 'مورد دولار للميزات', 'currency': 'USD'}))['id'];
      if (custs.length < 4 || prods.length < 3 || usdSup == null) {
        bad('التجهيز: زبائن ${custs.length} مواد ${prods.length} مورد $usdSup');
        throw StateError('فشل التجهيز');
      }

      // ── الحقيقة ──
      final cleared = <int, Map<String, double>>{for (final b in boxIds) b: {}}; // صندوق ← حركة مطابقة ← مبلغها
      final vouchers = <int>[]; // سندات حية (تغذّي الصناديق بحركات)
      final landed = <int, (String, int?, double)>{}; // سجل حي ← (طريقته، صندوقه، مبلغه)
      final lotQty = <int, double>{}; // دفعة ← كميتها المسجلة
      final compounds = <int, Map<int, double>>{}; // سند مركّب حي ← أثره على الصناديق
      var closed = false, locked = false;
      final cashInvoices = <String>[];
      var lastReceiptNo = 0;
      var usdBought = false;
      var purchaseNo = 0;

      Future<void> checkAll(String label) async {
        final inv = await acct('acctInvariants');
        for (final p in (inv['problems'] as List).cast<String>()) {
          bad('$label: $p');
        }
        for (final p in ((await feat('compoundCheck'))['problems'] as List).cast<String>()) {
          bad('$label: $p');
        }
        for (final r in ((await feat('bankRecs'))['rows'] as List).cast<Map>()) {
          if (r['status'] == 'final' && !near(r['cleared_balance'], r['statement_balance'])) {
            bad('$label: مطابقة معتمدة ${r['id']} مطابَقها ${r['cleared_balance']} ورصيد كشفها ${r['statement_balance']}');
          }
        }
      }

      Future<void> checkLots(String label) async {
        final l = await feat('lots');
        for (final r in (l['rows'] as List).cast<Map>()) {
          final id = (r['id'] as num).toInt();
          if (lotQty.containsKey(id) && !near(r['qty'], lotQty[id])) {
            bad('$label: كمية الدفعة $id تغيّرت إلى ${r['qty']} (المسجلة ${lotQty[id]}) — سجل الدفعات لا يتغيّر بالبيع');
          }
        }
        final live = {for (final r in (l['rows'] as List).cast<Map>()) (r['id'] as num).toInt()};
        for (final id in lotQty.keys) {
          if (!live.contains(id)) bad('$label: الدفعة $id اختفت دون حذف');
        }
        for (final p in (l['products'] as List).cast<Map>()) {
          final stock = max(0.0, dd(p['stock']));
          final lots = (p['lots'] as List).cast<Map>();
          final total = lots.fold<double>(0, (s, x) => s + dd(x['qty']));
          final rem = lots.fold<double>(0, (s, x) => s + dd(x['remaining']));
          if (!near(rem, min(stock, total), 0.001)) {
            bad('$label: مادة ${p['id']}: مجموع المتبقي $rem والمتوقع ${min(stock, total)} (المخزون $stock، الدفعات $total)');
          }
          for (final x in lots) {
            if (dd(x['remaining']) < -0.0001 || dd(x['remaining']) > dd(x['qty']) + 0.0001) {
              bad('$label: دفعة ${x['id']} متبقيها ${x['remaining']} خارج [0، ${x['qty']}]');
            }
          }
          // الأقرب انتهاءً يخرج أولاً: إن نقصت دفعة فكل ما ينتهي قبلها فارغ
          for (final x in lots) {
            if (dd(x['remaining']) < dd(x['qty']) - 0.0001) {
              for (final y in lots) {
                if ('${y['expiry']}'.compareTo('${x['expiry']}') < 0 && dd(y['remaining']) > 0.0001) {
                  bad('$label: دفعة ${y['id']} تنتهي قبل ${x['id']} وبقي منها ${y['remaining']} بينما نقصت ${x['id']}');
                }
              }
            }
          }
        }
      }

      for (var i = 1; i <= _ops; i++) {
        if (problems.length >= _maxProblems) break;
        final label = '#$i';
        final w = rnd.nextDouble();
        final b = pick(boxIds);

        if (w < 0.12) {
          // ── سند يغذّي الصناديق بحركات (وحذف أحياناً) ──
          if (vouchers.isNotEmpty && rnd.nextDouble() < 0.25) {
            final id = vouchers.removeAt(rnd.nextInt(vouchers.length));
            final r = await acct('voucherDelete', {'id': id});
            if (r['ok'] == true) {
              count('حذف سند');
            }
          } else {
            final type = pick(['receipt', 'payment']);
            final r = await acct('voucher', {
              'type': type,
              'amount': pick([1000.0, 25000.0, 333333.0, 750.0]),
              'box': b,
              'acc': pick(vaccs),
            });
            if (r['ok'] == true) {
              vouchers.add((r['id'] as num).toInt());
              count('سند $type');
            }
          }
        } else if (w < 0.30) {
          // ── مطابقة البنك ──
          final plan = await feat('bankPlan', {'box': b});
          if (plan['ok'] != true) {
            bad('$label: تعذّر فتح مطابقة للصندوق $b (${plan['err']})');
            continue;
          }
          final lines = (plan['lines'] as List).cast<Map>();
          // المطابَق سابقاً (حساب مستقل): ما اعتمده الاختبار وما زال في الدفتر بالمبلغ نفسه —
          // المحذوف مستنده يسقط، والمتغيّر مبلغه يعود غير مطابق
          final book = ((await feat('boxLedgerLines', {'box': b}))['lines'] as Map).cast<String, Object?>();
          final expPrior = cleared[b]!.entries
              .where((e) => book.containsKey(e.key) && near(book[e.key], e.value, 0.006))
              .fold<double>(0, (s, e) => s + e.value);
          if (!near(plan['prior'], expPrior, 0.02)) {
            bad('$label: المطابَق سابقاً للصندوق $b = ${plan['prior']} والمتوقع $expPrior');
          }
          final subset = [for (final l in lines) if (rnd.nextDouble() < 0.6) l];
          final target = dd(plan['prior']) + subset.fold<double>(0, (s, l) => s + dd(l['amount']));
          final before = await ledger();
          final rec = await feat('bankCreate', {'box': b, 'balance': target});
          if (rec['ok'] != true) {
            bad('$label: رُفضت مطابقة سليمة (${rec['err']})');
            continue;
          }
          final id = (rec['id'] as num).toInt();
          final second = await feat('bankCreate', {'box': b, 'balance': 1});
          if (second['ok'] == true) {
            bad('$label: قُبلت مسودة مطابقة ثانية للصندوق نفسه');
            await feat('bankDelete', {'id': second['id']});
          } else {
            count('رُفض كما يجب: مسودة مطابقة ثانية');
          }
          for (final l in subset) {
            await feat('bankToggle', {'id': id, 'key': l['key'], 'mark': true});
          }
          if (lines.length > subset.length) {
            // تعليم حركة زائدة ثم إلغاؤه
            final extra = lines.firstWhere((l) => !subset.contains(l));
            await feat('bankToggle', {'id': id, 'key': extra['key'], 'mark': true});
            await feat('bankToggle', {'id': id, 'key': extra['key'], 'mark': false});
          }
          final st = await feat('bankLoad', {'id': id});
          if (!near(st['difference'], 0, 0.011)) {
            bad('$label: فرق المطابقة ${st['difference']} بعد تعليم الحركات الصحيحة (المطابَق ${st['cleared']} والكشف $target)');
          }
          final unmark = subset.where((l) => dd(l['amount']).abs() >= 0.01).toList();
          if (unmark.isNotEmpty && rnd.nextDouble() < 0.3) {
            final l = pick(unmark);
            await feat('bankToggle', {'id': id, 'key': l['key'], 'mark': false});
            final f = await feat('bankFinalize', {'id': id});
            if (f['ok'] == true) {
              bad('$label: اعتُمدت مطابقة فرقها ${l['amount']}');
            } else {
              count('رُفض كما يجب: اعتماد مطابقة بفرق');
            }
            await feat('bankToggle', {'id': id, 'key': l['key'], 'mark': true});
          }
          if (rnd.nextDouble() < 0.15) {
            final d = await feat('bankDelete', {'id': id});
            if (d['ok'] != true) bad('$label: تعذّر حذف مسودة المطابقة (${d['err']})');
            count('حذف مسودة مطابقة');
          } else {
            final f = await feat('bankFinalize', {'id': id});
            if (f['ok'] != true) {
              bad('$label: رُفض اعتماد مطابقة فرقها صفر (${f['err']})');
              await feat('bankDelete', {'id': id});
              continue;
            }
            for (final l in subset) {
              cleared[b]!['${l['key']}'] = dd(l['amount']);
            }
            count('مطابقة معتمدة');
            if (rnd.nextDouble() < 0.2) {
              final early = await feat('bankCreate', {
                'box': b,
                'balance': 0,
                'date': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
              });
              if (early['ok'] == true) {
                bad('$label: قُبلت مطابقة بتاريخ قبل آخر مطابقة معتمدة');
                await feat('bankDelete', {'id': early['id']});
              } else {
                count('رُفض كما يجب: مطابقة بتاريخ أقدم');
              }
              final ro = await feat('bankReopen', {'id': id});
              if (ro['ok'] != true) {
                bad('$label: تعذّر إعادة فتح آخر مطابقة (${ro['err']})');
              } else {
                final again = await feat('bankFinalize', {'id': id});
                if (again['ok'] != true) bad('$label: تعذّر اعتماد المطابقة بعد إعادة فتحها (${again['err']})');
                count('إعادة فتح مطابقة واعتمادها');
              }
            }
          }
          if (await ledger() != before) bad('$label: مطابقة البنك غيّرت الدفتر');
        } else if (w < 0.42) {
          // ── كلفة الشحن والتخليص ──
          if (landed.isNotEmpty && rnd.nextDouble() < 0.25) {
            final id = pick(landed.keys.toList());
            final (mode, lb, amt) = landed[id]!;
            final b0 = await boxes();
            final r = await feat('landedVoid', {'id': id});
            if (r['ok'] != true) {
              bad('$label: تعذّر إلغاء سجل الشحن (${r['err']})');
              continue;
            }
            landed.remove(id);
            final b1 = await boxes();
            for (final x in boxIds) {
              final exp = (mode == 'box' && x == lb) ? amt : 0.0;
              if (!near(b1[x]! - b0[x]!, exp)) bad('$label: إلغاء الشحن غيّر الصندوق $x بـ${b1[x]! - b0[x]!} والمتوقع $exp');
            }
            final e = ((await feat('landedEntries'))['rows'] as List).cast<Map>();
            if (e.any((x) => x['id'] == id)) bad('$label: سجل الشحن الملغى $id ما زال له قيد');
            count('إلغاء سجل شحن');
            continue;
          }
          final pid = pick(prods.values.toList());
          final qty = pick([10.0, 3.0, 2.5, 0.0, 7.0]);
          final nExtras = 1 + rnd.nextInt(3);
          final extras = [
            for (var k = 0; k < nExtras; k++) {'name': 'مصروف $k', 'amount': pick([150000.0, 2500.5, 1.0, 0.0, -500.0, 33333.0])},
          ];
          final mode = pick(['box', 'reclass', 'none']);
          final missing = rnd.nextDouble() < 0.1;
          final args = {
            'product': pid,
            'name': 'مادة $pid',
            'qty': qty,
            'unitCost': pick([1000.0, 999.75]),
            'extras': extras,
            'mode': mode,
            if (mode == 'box' && !missing) 'box': b,
            if (mode == 'reclass' && !missing) 'acc': expense.first,
          };
          final sum = extras.fold<double>(0, (s, e) => s + dd(e['amount']));
          final valid = qty > 0 &&
              sum > 0 &&
              !extras.any((e) => dd(e['amount']) < 0) &&
              !(missing && mode != 'none');
          final b0 = await boxes();
          final r = await feat('landed', args);
          if (!valid) {
            if (r['ok'] == true) {
              bad('$label: قُبل شحن غير صالح (كمية $qty، مصاريف ${extras.map((e) => e['amount']).toList()}، $mode${missing ? ' بلا صندوق/حساب' : ''})');
              landed[(r['id'] as num).toInt()] = (mode, mode == 'box' ? b : null, dd(r['total']));
            } else {
              count('رُفض كما يجب: شحن غير صالح');
            }
            continue;
          }
          if (r['ok'] != true) {
            bad('$label: رُفض شحن صالح (${r['err']})');
            continue;
          }
          final total = (sum * 100).roundToDouble() / 100;
          if (!near(r['total'], total, 0.006)) bad('$label: مجموع مصاريف الشحن ${r['total']} والمتوقع $total');
          final perUnit = ((total / qty) * 100).roundToDouble() / 100;
          if (!near(r['perUnit'], perUnit, 0.006)) bad('$label: حصة الوحدة ${r['perUnit']} والمتوقع $perUnit');
          final id = (r['id'] as num).toInt();
          landed[id] = (mode, mode == 'box' ? b : null, dd(r['total']));
          final b1 = await boxes();
          for (final x in boxIds) {
            final exp = (mode == 'box' && x == b) ? -dd(r['total']) : 0.0;
            if (!near(b1[x]! - b0[x]!, exp)) bad('$label: شحن ($mode) غيّر الصندوق $x بـ${b1[x]! - b0[x]!} والمتوقع $exp');
          }
          final e = ((await feat('landedEntries'))['rows'] as List).cast<Map>().where((x) => x['id'] == id).toList();
          if (mode == 'none' && e.isNotEmpty) bad('$label: شحن «كلفة فقط» له قيد');
          if (mode != 'none' && (e.isEmpty || !near(e.first['dr'], r['total']))) {
            bad('$label: قيد الشحن ($mode) ${e.isEmpty ? 'غير موجود' : e.first['dr']} والمبلغ ${r['total']}');
          }
          count('شحن $mode');
        } else if (w < 0.52) {
          // ── الدفعات وتواريخ الصلاحية ──
          final pu = pick(prods.keys.toList());
          final pid = prods[pu]!;
          final k = rnd.nextDouble();
          if (k < 0.5) {
            final qty = pick([5.0, 12.5, 100.0, 0.0, -1.0, 40.0]);
            final exp = DateTime.now().add(Duration(days: rnd.nextInt(800) - 400));
            final r = await feat('lotAdd', {'product': pid, 'lotNo': 'L$i', 'expiry': exp.toIso8601String(), 'qty': qty});
            if (qty <= 0) {
              if (r['ok'] == true) {
                bad('$label: قُبلت دفعة بكمية $qty');
                lotQty[(r['id'] as num).toInt()] = qty;
              } else {
                count('رُفض كما يجب: دفعة بكمية صفر أو سالبة');
              }
            } else if (r['ok'] != true) {
              bad('$label: رُفضت دفعة سليمة (${r['err']})');
            } else {
              lotQty[(r['id'] as num).toInt()] = qty;
              count('دفعة جديدة');
            }
          } else if (k < 0.65 && lotQty.isNotEmpty) {
            final id = pick(lotQty.keys.toList());
            final r = await feat('lotRemove', {'id': id});
            if (r['ok'] == true) {
              lotQty.remove(id);
              count('حذف دفعة');
            }
          } else {
            final s0 = dd((await feat('productId', {'uuid': pu}))['stock']);
            final q = (1 + rnd.nextInt(30)).toDouble();
            final r = await rest('pos', {
              'items': [
                {'prod': pu, 'qty': q, 'price': 1000.0},
              ],
              'ptype': 'نقد',
            });
            if (r['ok'] == true) {
              final s1 = dd((await feat('productId', {'uuid': pu}))['stock']);
              if (!near(s0 - s1, q, 0.001)) bad('$label: بيع $q نقص المخزون ${s0 - s1}');
              count('بيع مادة لها دفعات');
            } else {
              notes.add('بيع كاشير رُفض: ${r['err']}');
            }
          }
          await checkLots(label);
        } else if (w < 0.66) {
          // ── السند المركّب ──
          if (compounds.isNotEmpty && rnd.nextDouble() < 0.25) {
            final id = pick(compounds.keys.toList());
            final eff = compounds[id]!;
            final b0 = await boxes();
            final r = await feat('compoundDelete', {'id': id});
            if (r['ok'] != true) {
              if (locked && '${r['err']}'.contains('مثبّت')) {
                count('رُفض كما يجب: حذف سند داخل فترة مثبّتة');
                continue;
              }
              bad('$label: تعذّر حذف سند مركّب (${r['err']})');
              continue;
            }
            compounds.remove(id);
            final b1 = await boxes();
            for (final x in boxIds) {
              if (!near(b1[x]! - b0[x]!, -(eff[x] ?? 0))) bad('$label: حذف السند المركّب غيّر الصندوق $x بـ${b1[x]! - b0[x]!}');
            }
            final again = await feat('compoundDelete', {'id': id});
            if (again['ok'] == true) {
              bad('$label: حُذف السند المركّب نفسه مرتين');
            } else {
              count('رُفض كما يجب: حذف سند مركّب محذوف');
            }
            count('حذف سند مركّب');
            continue;
          }
          final kind = rnd.nextDouble();
          final amt = pick([50000.0, 1250.0, 999999.0, 75.5]);
          final useBox = rnd.nextBool();
          final a1 = useBox ? (boxAcc['$b'] as num).toInt() : pick(free);
          final a2 = pick([...revenue, ...expense, ...free]);
          var lines = <Map<String, Object?>>[
            {'acc': a1, 'dr': amt, 'cr': 0.0},
            {'acc': a2, 'dr': 0.0, 'cr': amt},
          ];
          var valid = true;
          String why = 'متوازن';
          String? date;
          if (kind < 0.10) {
            lines = [lines[0], {'acc': a2, 'dr': 0.0, 'cr': amt - 1}];
            valid = false;
            why = 'غير متوازن';
          } else if (kind < 0.18 && control.isNotEmpty) {
            lines = [lines[0], {'acc': pick(control), 'dr': 0.0, 'cr': amt}];
            valid = false;
            why = 'حساب ذمم';
          } else if (kind < 0.23) {
            lines = [{'acc': a1, 'dr': -amt, 'cr': 0.0}, {'acc': a2, 'dr': 0.0, 'cr': -amt}, {'acc': pick(free), 'dr': 5.0, 'cr': 5.0}];
            valid = false;
            why = 'سالب/مدين ودائن';
          } else if (kind < 0.33) {
            // سطر بالدولار: مبلغه بالدينار = العملة × السعر (أو لا يطابق ⇒ يُرفض)
            final fc = pick([100.0, 37.5]);
            const rate = 1310.0;
            final ok = rnd.nextDouble() < 0.7;
            final iqd = ok ? (fc * rate) : fc * rate + 500;
            lines = [
              {'acc': a1, 'dr': iqd, 'cr': 0.0, 'cur': 'USD', 'fc': fc, 'rate': rate},
              {'acc': a2, 'dr': 0.0, 'cr': iqd},
            ];
            valid = ok;
            why = ok ? 'دولار' : 'دولار لا يطابق السعر';
          } else if (kind < 0.45) {
            date = DateTime(2025, 1 + rnd.nextInt(12), 15).toIso8601String();
            lines = [
              {'acc': a1, 'dr': amt, 'cr': 0.0},
              {'acc': pick([...revenue, ...expense]), 'dr': 0.0, 'cr': amt},
            ];
            valid = !locked;
            why = locked ? 'مؤرخ في سنة مثبّتة' : 'مؤرخ في 2025';
          }
          final b0 = await boxes();
          final r = await feat('compound', {'lines': lines, if (date != null) 'date': date});
          if (!valid) {
            if (r['ok'] == true) {
              bad('$label: قُبل سند مركّب $why');
              compounds[(r['id'] as num).toInt()] = {};
            } else {
              count('رُفض كما يجب: سند مركّب $why');
            }
            continue;
          }
          if (r['ok'] != true) {
            bad('$label: رُفض سند مركّب $why سليم (${r['err']})');
            continue;
          }
          final eff = <int, double>{};
          for (final l in lines) {
            final bx = boxOfAcc[(l['acc'] as num).toInt()];
            if (bx != null) eff[bx] = (eff[bx] ?? 0) + dd(l['dr']) - dd(l['cr']);
          }
          compounds[(r['id'] as num).toInt()] = eff;
          final b1 = await boxes();
          for (final x in boxIds) {
            if (!near(b1[x]! - b0[x]!, eff[x] ?? 0)) {
              bad('$label: سند مركّب ($why) غيّر الصندوق $x بـ${b1[x]! - b0[x]!} والمتوقع ${eff[x] ?? 0}');
            }
          }
          count('سند مركّب $why');
        } else if (w < 0.70) {
          // ── إقفال السنة وإعادة فتحها ──
          if (!closed) {
            final pv = await feat('fiscalPreviewNet', {'year': 2025});
            final c = await feat('fiscalClose', {'year': 2025});
            if (c['ok'] != true) {
              bad('$label: تعذّر إقفال 2025 (${c['err']})');
              continue;
            }
            if (!near(c['net'], pv['net'])) bad('$label: صافي الإقفال ${c['net']} والمعاينة ${pv['net']}');
            final y = await feat('yearProfit', {'year': 2025});
            if (!near(y['net'], 0)) bad('$label: بعد الإقفال بقي في إيرادات ومصاريف 2025: ${y['net']}');
            final dr = await feat('fiscalDrift', {'year': 2025});
            if (!near(dr['drift'], 0)) bad('$label: انحراف بعد الإقفال ${dr['drift']}');
            final again = await feat('fiscalClose', {'year': 2025});
            if (again['ok'] == true) {
              bad('$label: أُقفلت 2025 مرتين');
            } else {
              count('رُفض كما يجب: إقفال السنة مرتين');
            }
            final future = await feat('fiscalClose', {'year': DateTime.now().year});
            if (future['ok'] == true) {
              bad('$label: أُقفلت سنة لم تنتهِ');
            } else {
              count('رُفض كما يجب: إقفال سنة لم تنتهِ');
            }
            closed = true;
            locked = true;
            count('إقفال سنة');
          } else {
            final ro = await feat('fiscalReopen', {'year': 2025});
            if (locked) {
              if (ro['ok'] == true) {
                bad('$label: أُعيد فتح سنة داخل فترة مثبّتة');
                closed = false;
                continue;
              }
              count('رُفض كما يجب: إعادة فتح سنة مثبّتة');
              await feat('setLock', {'date': null});
              locked = false;
            }
            final ro2 = locked ? ro : await feat('fiscalReopen', {'year': 2025});
            if (ro2['ok'] != true) {
              bad('$label: تعذّر إعادة فتح 2025 بعد إلغاء التثبيت (${ro2['err']})');
              continue;
            }
            final pv = await feat('fiscalPreviewNet', {'year': 2025});
            final y = await feat('yearProfit', {'year': 2025});
            if (!near(y['net'], pv['net'])) bad('$label: بعد إعادة الفتح صافي 2025 = ${y['net']} والمعاينة ${pv['net']}');
            closed = false;
            count('إعادة فتح سنة');
          }
        } else if (w < 0.78) {
          // ── إعادة تقييم ذمم الموردين بالدولار ──
          if (!usdBought || rnd.nextDouble() < 0.3) {
            purchaseNo++;
            final r = await rest('supBuy', {
              'sup': usdSup,
              'number': 'FX-$seed-$purchaseNo',
              'currency': 'USD',
              'status': 'confirmed',
              'items': [
                {'prod': pick(prods.keys.toList()), 'qty': pick([3.0, 10.0]), 'price': pick([12.5, 40.0, 7.25])},
              ],
              'paid': 0.0,
            });
            if (r['ok'] != true) {
              bad('$label: رُفضت فاتورة شراء بالدولار (${r['err']})');
              continue;
            }
            usdBought = true;
            count('شراء بالدولار');
          }
          await boxes(); // ترحيل
          final rate = pick([1300.0, 1450.0, 1310.5, 1500.0]);
          final p = await feat('fxPost', {'rate': rate});
          if (p['ok'] != true) {
            bad('$label: تعذّر قيد إعادة التقييم (${p['err']})');
            continue;
          }
          final ap = await feat('apUsd');
          for (final row in (ap['rows'] as List).cast<Map>()) {
            final usd = dd(row['usd']);
            if (usd.abs() < 0.001) continue;
            if ((dd(row['iqd']) - usd * rate).abs() > 1.01) {
              bad('$label: بعد إعادة التقييم بسعر $rate ذمة المورد ${row['sid']} = ${row['iqd']} والمتوقع ${usd * rate} ($usd دولار)');
            }
          }
          if ((ap['fxEntries'] as num) > 1) bad('$label: ${ap['fxEntries']} قيد إعادة تقييم لليوم نفسه — يجب أن يستبدل');
          if (rnd.nextDouble() < 0.3) {
            final d = await feat('fxDelete');
            if (d['ok'] != true) bad('$label: تعذّر حذف قيد إعادة التقييم (${d['err']})');
            final ap2 = await feat('apUsd');
            if ((ap2['fxEntries'] as num) != 0) bad('$label: قيد إعادة التقييم بقي بعد حذفه');
            count('حذف إعادة تقييم');
          }
          count('إعادة تقييم بسعر');
        } else if (w < 0.90) {
          // ── تعديل فاتورة نقدية وسندها ──
          final cu = pick(custs);
          final t0 = pick([10000.0, 25000.0, 7500.0, 120000.0]);
          final b0 = await boxes();
          final s = await h.d(dev).call('saveInvoice', {'cust': cu, 'total': t0, 'ptype': 'نقد', 'paid': t0});
          if (s is! Map || s['ok'] != true) {
            bad('$label: رُفضت فاتورة نقدية سليمة (${s is Map ? s['err'] : s})');
            continue;
          }
          final uuid = s['uuid'] as String;
          cashInvoices.add(uuid);
          final b1 = await boxes();
          final saveDelta = boxIds.fold<double>(0, (a, x) => a + b1[x]! - b0[x]!);
          final snap = await feat('invSnapshot', {'inv': uuid});
          final toCredit = rnd.nextDouble() < 0.2;
          final t1 = toCredit ? t0 : pick([t0 / 2, t0 + 5000, t0, t0 + 0.4, t0 - 1]);
          final ed = await h.d(dev).call('saveInvoice', {
            'cust': cu,
            'inv': uuid,
            'total': t1,
            'ptype': toCredit ? 'دين' : 'نقد',
            'paid': toCredit ? 0.0 : t1,
          });
          if (ed is! Map || ed['ok'] != true) {
            notes.add('تعديل فاتورة نقدية رُفض: ${ed is Map ? ed['err'] : ed}');
            continue;
          }
          final b2 = await boxes();
          final l0 = await ledger();
          final v = await feat('editVoucher', {
            'id': snap['id'],
            'beforeTotal': snap['total'],
            'beforePayment': snap['payment'],
          });
          if (await ledger() != l0) bad('$label: سند تعديل الفاتورة غيّر الدفتر (يُحتسب المبلغ مرتين)');
          final b3 = await boxes();
          for (final x in boxIds) {
            if (!near(b3[x]!, b2[x]!)) bad('$label: سند تعديل الفاتورة حرّك الصندوق $x');
          }
          final delta = dd(v['after']) - dd(snap['total']);
          final expectVoucher = !toCredit && snap['payment'] == 'نقد' && v['afterPayment'] == 'نقد' && delta.abs() >= 0.5;
          if (expectVoucher != (v['voucher'] != null)) {
            bad('$label: سند تعديل الفاتورة ${v['voucher'] == null ? 'لم يُنشأ' : 'أُنشئ'} والفرق $delta (${v['afterPayment']})');
          } else if (expectVoucher) {
            if (!near(v['amount'], delta.abs())) bad('$label: مبلغ سند التعديل ${v['amount']} والفرق ${delta.abs()}');
            if (v['kind'] != (delta < 0 ? 'refund' : 'receipt')) bad('$label: نوع سند التعديل ${v['kind']} والفرق $delta');
            count('سند تعديل ${delta < 0 ? 'رد' : 'قبض'}');
          } else {
            count('تعديل فاتورة بلا سند');
          }
          // الصندوق تحرّك بفرق التعديل مرة واحدة (إن كانت الفاتورة النقدية تحرّكه أصلاً)
          final editDelta = boxIds.fold<double>(0, (a, x) => a + b2[x]! - b1[x]!);
          if (!toCredit) {
            final exp = near(saveDelta, dd(snap['total'])) ? delta : 0.0;
            if (!near(editDelta, exp, 0.02)) bad('$label: تعديل الفاتورة النقدية حرّك الصناديق $editDelta والمتوقع $exp');
          }
          if (!near(saveDelta, dd(snap['total']), 0.02) && !near(saveDelta, 0)) {
            bad('$label: حفظ فاتورة نقدية ${snap['total']} حرّك الصناديق $saveDelta');
          }
        } else if (w < 0.95) {
          // ── الحذف: المعلّقة فقط ──
          final cu = pick(custs);
          final d0 = dd((await feat('custDebt', {'cust': cu}))['debt']);
          final hold = await h.d(dev).call('holdInvoice', {'cust': cu, 'total': pick([5000.0, 80000.0]), 'ptype': 'دين'});
          if (hold is! Map || hold['ok'] != true) {
            bad('$label: رُفض تعليق فاتورة (${hold is Map ? hold['err'] : hold})');
            continue;
          }
          final d1 = dd((await feat('custDebt', {'cust': cu}))['debt']);
          if (!near(d0, d1)) bad('$label: تعليق فاتورة غيّر دين العميل من $d0 إلى $d1');
          await h.d(dev).call('discardHeld', {'inv': hold['uuid']});
          final st = await feat('invoiceState', {'inv': hold['uuid']});
          if (st['exists'] == true && (st['is_deleted'] as num? ?? 0) != 1) bad('$label: الفاتورة المعلّقة لم تُحذف');
          final d2 = dd((await feat('custDebt', {'cust': cu}))['debt']);
          if (!near(d0, d2)) bad('$label: حذف فاتورة معلّقة غيّر دين العميل من $d0 إلى $d2');
          count('حذف فاتورة معلّقة');
          if (cashInvoices.isNotEmpty) {
            final u = pick(cashInvoices);
            final before = await feat('invoiceState', {'inv': u});
            final r = await feat('discardAny', {'inv': u});
            if (r['ok'] != true || (r['deleted'] as num? ?? 0) != 0 || r['status'] != before['status']) {
              bad('$label: محاولة حذف فاتورة غير معلّقة مسّتها (${r['err'] ?? 'حُذفت=${r['deleted']}'})');
            } else {
              count('رُفض كما يجب: حذف فاتورة غير معلّقة');
            }
          }
        } else {
          // ── سند القبض المؤرشف ──
          final cu = pick(custs);
          await h.d(dev).call('addTx', {'cust': cu, 'amount': 10000.0, 'marker': 'دين للسند $i'});
          final debt = dd((await feat('custDebt', {'cust': cu}))['debt']);
          final paid = min(debt, pick([1000.0, 2500.0, 10000.0]));
          if (paid <= 0) continue;
          final r = await feat('legacyReceipt', {'cust': cu, 'paid': paid, 'marker': '$i'});
          if (r['ok'] != true) {
            bad('$label: رُفض تسديد بسند قبض مؤرشف (${r['err']})');
            continue;
          }
          if (!near(r['after'], r['actual'])) bad('$label: سند القبض المؤرشف يقول الرصيد بعد ${r['after']} والفعلي ${r['actual']}');
          if (!near(dd(r['before']) - paid, r['actual'])) bad('$label: الرصيد قبل ${r['before']} − $paid ≠ الفعلي ${r['actual']}');
          final no = (r['number'] as num).toInt();
          if (no <= lastReceiptNo) bad('$label: رقم سند القبض $no لم يتقدّم (السابق $lastReceiptNo)');
          lastReceiptNo = no;
          final all = ((await feat('legacyReceipts'))['rows'] as List).cast<Map>();
          final nums = all.map((x) => x['receipt_number']).toList();
          if (nums.toSet().length != nums.length) bad('$label: أرقام سندات القبض المؤرشفة مكررة');
          count('سند قبض مؤرشف');
        }
        await checkAll(label);
        if (i % 20 == 0) {
          final line = '$i/$_ops — مشاكل ${problems.length} — ${sw.elapsed.inMinutes} دقيقة';
          progress.writeAsStringSync(line);
          print('⏳ $line');
        }
      }
      await checkLots('النهاية');
      for (final e in (await h.deviceErrors()).take(5)) {
        bad('خطأ غير ممسوك: $e');
      }
      failed = problems.isNotEmpty;
    } finally {
      final keys = stats.keys.toList()..sort();
      final s = StringBuffer()
        ..writeln('الميزات المتبقية — seed=$seed — ${failed ? 'FAIL' : 'PASS'} — ${sw.elapsed.inMinutes} دقيقة')
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
  }, timeout: const Timeout(Duration(hours: 6)));
}
