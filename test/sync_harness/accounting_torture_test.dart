// test/sync_harness/accounting_torture_test.dart
//
// 🏦 الصندوق والمحاسبة (المرحلة 2 من «كل مسارات المال») — قاسٍ وعشوائي مع حالات قصوى:
//   • السندات: قبض، صرف، مصروف، إيراد، تحويل بين صندوقين، حذف — بمبالغ ضخمة وكسور
//     وصفر وسالبة (الصفر والسالب يجب أن يُرفضا).
//   • القيود اليدوية: متوازنة (تُقبل) وغير متوازنة (يجب أن تُرفض)، على الصندوق وعلى غيره، وحذفها.
//   • الرواتب والسلف: سلفة، راتب يخصم السلف المفتوحة، راتب الشهر نفسه مرتين (يُرفض)،
//     سلف أكبر من الراتب.
//   • الأصول الثابتة: شراء من الصندوق أو رصيد افتتاحي، إهلاك شهري، الشهر نفسه مرتين (يُرفض)،
//     إلغاء دورة إهلاك، بيع الأصل وإرجاع البيع، حذفه.
//   • جرد الصندوق: مطابق، عجز، زيادة، ثم الترحيل.
//   • التوصيل: طلبات تُسلَّم وتُرجَع، ثم التسوية: مجموعها = المسلَّم فقط، ولا تُسوّى مرتين.
// بعد كل فعل: رصيد كل صندوق = ما يتوقعه الاختبار، كل قيد متوازن، ميزان المراجعة متوازن،
// لا أسطر يتيمة، كل سند حي له قيده بمبلغه والمحذوف لا قيد له، مجمع الإهلاك لا يتجاوز الكلفة.
//
// التشغيل: claude_test_accounting.bat [quick|full] [seed]
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
  test('الصندوق والمحاسبة: $_ops عملية seed=$seed', () async {
    print('🎲 seed=$seed');
    final h = Harness(seed: seed);
    final rnd = Random(seed * 13 + 5);
    final problems = <String>[];
    final notes = <String>{};
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    final sw = Stopwatch()..start();
    final out = Directory('test_results${Platform.pathSeparator}accounting')..createSync(recursive: true);
    final progress = File('${out.path}${Platform.pathSeparator}progress.txt');
    void bad(String p) {
      problems.add(p);
      print('✗ $p');
    }

    var failed = true;
    try {
      await h.start(1);
      const dev = 'D1';
      Future<Map<String, Object?>> op(String name, [Map<String, Object?> args = const {}]) async {
        final r = await h.d(dev).call('acct', {'op': name, 'args': args}, const Duration(minutes: 3));
        return r is Map ? r.cast<String, Object?>() : {'ok': true, 'value': r};
      }

      final setup = await op('setup');
      final boxes = (setup['boxes'] as List).map((x) => (x as num).toInt()).toList();
      final accs = (setup['accounts'] as List).map((x) => (x as num).toInt()).toList();
      final expense = (setup['expense'] as List).map((x) => (x as num).toInt()).toList();
      if (boxes.length < 2 || accs.length < 3) {
        bad('التجهيز: صناديق ${boxes.length} وحسابات ${accs.length}');
        return;
      }
      final expAcc = expense.isNotEmpty ? expense.first : accs.first;
      final start = (await op('boxBalances')).map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
      final box = {for (final b in boxes) b: start[b] ?? 0.0}; // الحقيقة
      final vouchers = <int, (String, int, int?, double)>{}; // سند ← (نوعه، صندوقه، صندوق التحويل، مبلغه)
      final manuals = <int>{}; // قيود يدوية حية
      final emps = <int, int>{}; // موظف ← راتبه بالفلس
      final paidMonths = <String>{};
      final assets = <int, (String, double, int?)>{}; // أصل ← (تمويله، كلفته، صندوقه)
      final disposed = <int, (double, int?)>{};
      final runs = <int>[];
      var depMonth = 0;

      Future<void> checkAll(String label) async {
        final inv = await op('acctInvariants');
        for (final p in (inv['problems'] as List).cast<String>()) {
          bad('$label: $p');
        }
        notes.addAll((inv['notes'] as List).cast<String>());
        final bal = (await op('boxBalances')).map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
        for (final b in boxes) {
          if (((bal[b] ?? 0) - box[b]!).abs() > 0.005) bad('$label: رصيد الصندوق $b = ${bal[b]} والمتوقع ${box[b]}');
        }
      }

      double pick(List<double> xs) => xs[rnd.nextInt(xs.length)];

      for (var i = 1; i <= _ops; i++) {
        if (problems.length >= _maxProblems) break;
        final label = '#$i';
        final w = rnd.nextDouble();
        final b = boxes[rnd.nextInt(boxes.length)];
        if (w < 0.30) {
          // ── سند ──
          final type = const ['receipt', 'income', 'payment', 'expense', 'transfer'][rnd.nextInt(5)];
          final amount = pick([1000, 25000.5, 0.4, 999999999.75, 0, -50, 3000000]);
          final to = type == 'transfer' ? boxes.firstWhere((x) => x != b) : null;
          final acc = type == 'transfer' ? null : (type == 'expense' ? expAcc : accs[rnd.nextInt(accs.length)]);
          final r = await op('voucher', {'type': type, 'amount': amount, 'box': b, 'toBox': to, 'acc': acc});
          if (amount <= 0) {
            if (r['ok'] == true) bad('$label: قُبل سند $type بمبلغ $amount');
            count('رُفض كما يجب: سند بمبلغ صفر أو سالب');
            continue;
          }
          if (r['ok'] != true) {
            // حساب مقابل لا يناسب نوع السند = قرار التطبيق، لا خطأ
            if ('${r['err']}'.contains('حساب')) {
              notes.add('سند $type رُفض بسبب الحساب المقابل: ${r['err']}');
            } else {
              bad('$label: رُفض سند $type سليم بـ$amount (${r['err']})');
            }
            continue;
          }
          final a = (r['amount'] as num).toDouble();
          if ((a - amount).abs() > 0.005) notes.add('السند يحفظ $amount كـ$a');
          final sign = (type == 'receipt' || type == 'income') ? 1.0 : -1.0;
          box[b] = box[b]! + sign * a;
          if (to != null) box[to] = box[to]! + a;
          vouchers[(r['id'] as num).toInt()] = (type, b, to, a);
          count('سند $type');
        } else if (w < 0.38) {
          // ── حذف سند (ومرة ثانية) ──
          if (vouchers.isEmpty) continue;
          final id = vouchers.keys.elementAt(rnd.nextInt(vouchers.length));
          final (type, vb, to, a) = vouchers[id]!;
          final r = await op('voucherDelete', {'id': id});
          if (r['ok'] != true) {
            notes.add('حذف سند $type رُفض: ${r['err']}');
            continue;
          }
          final sign = (type == 'receipt' || type == 'income') ? 1.0 : -1.0;
          box[vb] = box[vb]! - sign * a;
          if (to != null) box[to] = box[to]! - a;
          vouchers.remove(id);
          count('حذف سند');
          await checkAll('$label بعد الحذف');
          final again = await op('voucherDelete', {'id': id});
          if (again['ok'] == true) notes.add('حذف السند نفسه مرة ثانية لا يرفض (ولا يغيّر الأرصدة إن مرّ الفحص)');
        } else if (w < 0.50) {
          // ── قيد يدوي متوازن أو لا ──
          final x = pick([5000, 1250.5, 77777777]);
          final balanced = rnd.nextDouble() < 0.8;
          final a1 = accs[rnd.nextInt(accs.length)];
          var a2 = accs[rnd.nextInt(accs.length)];
          if (a2 == a1) a2 = accs[(accs.indexOf(a1) + 1) % accs.length];
          final r = await op('manual', {
            'lines': [
              {'acc': a1, 'debit': x, 'credit': 0.0},
              {'acc': a2, 'debit': 0.0, 'credit': balanced ? x : x - 1},
            ]
          });
          if (!balanced) {
            if (r['ok'] == true) bad('$label: قُبل قيد يدوي غير متوازن ($x / ${x - 1})');
            count('رُفض كما يجب: قيد غير متوازن');
            continue;
          }
          if (r['ok'] != true) {
            bad('$label: رُفض قيد يدوي متوازن (${r['err']})');
            continue;
          }
          manuals.add((r['id'] as num).toInt());
          count('قيد يدوي');
          if (rnd.nextDouble() < 0.3) {
            final id = (r['id'] as num).toInt();
            final d = await op('manualDelete', {'id': id});
            if (d['ok'] != true) bad('$label: رُفض حذف قيد يدوي (${d['err']})');
            manuals.remove(id);
            count('حذف قيد يدوي');
          }
        } else if (w < 0.65) {
          // ── الرواتب والسلف ──
          if (emps.length < 3) {
            final salary = (pick([750000, 1250000.5, 400000]) * 100).round();
            final r = await op('hrEmp', {'name': 'موظف ${emps.length + 1}', 'salary': salary});
            if (r['ok'] == true) emps[(r['id'] as num).toInt()] = salary;
            if (r['ok'] != true) bad('$label: لم يُحفظ موظف (${r['err']})');
            continue;
          }
          final e = emps.keys.elementAt(rnd.nextInt(emps.length));
          if (rnd.nextBool()) {
            final fils = (pick([50000, 100000.5, 2000000]) * 100).round();
            final r = await op('hrAdvance', {'emp': e, 'fils': fils, 'box': b, 'acc': expAcc});
            if (r['ok'] != true) {
              bad('$label: رُفضت سلفة (${r['err']})');
              continue;
            }
            box[b] = box[b]! - fils / 100.0;
            count('سلفة');
          } else {
            final month = '2026-${(1 + rnd.nextInt(10)).toString().padLeft(2, '0')}';
            final bonus = (pick([0, 25000, 0.5]) * 100).round();
            final ded = (pick([0, 10000]) * 100).round();
            final r = await op('hrPay', {'emp': e, 'month': month, 'bonus': bonus, 'deduction': ded, 'box': b, 'acc': expAcc});
            final dup = paidMonths.contains('$e|$month');
            if (dup) {
              if (r['ok'] == true) bad('$label: صُرف راتب $month للموظف نفسه مرتين');
              count('رُفض كما يجب: راتب الشهر نفسه مرتين');
              continue;
            }
            if (r['ok'] != true) {
              notes.add('راتب رُفض: ${r['err']}');
              count('راتب مرفوض (سلف أكبر من الراتب أو غيره)');
              continue;
            }
            paidMonths.add('$e|$month');
            box[b] = box[b]! - (r['net'] as num) / 100.0;
            count('راتب');
          }
        } else if (w < 0.80) {
          // ── الأصول الثابتة ──
          final k = rnd.nextDouble();
          if (k < 0.3 || assets.isEmpty) {
            final cost = pick([12000000, 3600000.5, 999]);
            final fromBox = rnd.nextBool();
            final r = await op('asset', {
              'name': 'أصل ${assets.length + 1}',
              'cost': cost,
              'salvage': pick([0, 100000]),
              'life': pick([12, 36, 60]).toInt(),
              'funding': fromBox ? 'box' : 'opening',
              'box': fromBox ? b : null,
            });
            if (r['ok'] != true) {
              notes.add('أصل رُفض: ${r['err']}');
              continue;
            }
            assets[(r['id'] as num).toInt()] = (fromBox ? 'box' : 'opening', cost, fromBox ? b : null);
            if (fromBox) box[b] = box[b]! - cost;
            count('أصل ${fromBox ? 'من الصندوق' : 'افتتاحي'}');
          } else if (k < 0.55) {
            final period = '2025-${(1 + depMonth % 12).toString().padLeft(2, '0')}';
            final r = await op('depRun', {'period': period});
            final again = await op('depRun', {'period': period});
            if (again['ok'] == true) bad('$label: إهلاك الشهر $period رُحّل مرتين');
            if (r['ok'] == true) {
              runs.add((r['id'] as num).toInt());
              depMonth++;
              count('دورة إهلاك');
            } else {
              notes.add('دورة إهلاك $period: ${r['err']}');
            }
          } else if (k < 0.65) {
            if (runs.isEmpty) continue;
            final r = await op('depVoid', {'id': runs.removeLast()});
            if (r['ok'] != true) notes.add('إلغاء دورة إهلاك: ${r['err']}');
            if (r['ok'] == true) count('إلغاء دورة إهلاك');
          } else if (k < 0.85) {
            final live = assets.keys.where((a) => !disposed.containsKey(a)).toList();
            if (live.isEmpty) continue;
            final a = live[rnd.nextInt(live.length)];
            final proceeds = pick([0, 500000, 1250.5]);
            final r = await op('assetDispose', {'id': a, 'proceeds': proceeds, 'box': proceeds > 0 ? b : null});
            if (r['ok'] != true) {
              notes.add('بيع أصل: ${r['err']}');
              continue;
            }
            disposed[a] = (proceeds, proceeds > 0 ? b : null);
            if (proceeds > 0) box[b] = box[b]! + proceeds;
            count('بيع/استبعاد أصل');
            if (rnd.nextBool()) {
              final u = await op('assetUndispose', {'id': a});
              if (u['ok'] == true) {
                if (proceeds > 0) box[b] = box[b]! - proceeds;
                disposed.remove(a);
                count('إرجاع بيع أصل');
              } else {
                notes.add('إرجاع بيع أصل: ${u['err']}');
              }
            }
          } else {
            final a = assets.keys.elementAt(rnd.nextInt(assets.length));
            final before = (await op('boxBalances')).map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
            final r = await op('assetDelete', {'id': a});
            if (r['ok'] == true) {
              final after = (await op('boxBalances')).map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
              final (funding, cost, fb) = assets[a]!;
              for (final x in boxes) {
                final d = (after[x] ?? 0) - (before[x] ?? 0);
                if (d.abs() > 0.005) box[x] = box[x]! + d;
              }
              if (funding == 'box' && fb != null && ((after[fb] ?? 0) - (before[fb] ?? 0) - cost).abs() > 0.005) {
                notes.add('حذف أصل اشتُري من الصندوق بـ$cost لم يُرجع المبلغ للصندوق (فرقه ${(after[fb] ?? 0) - (before[fb] ?? 0)})');
              }
              assets.remove(a);
              disposed.remove(a);
              count('حذف أصل');
            } else {
              count('حذف أصل مرفوض (له إهلاك أو بيع)');
            }
          }
        } else if (w < 0.92) {
          // ── جرد الصندوق ──
          final expected = box[b]!;
          final counted = pick([expected, expected - 2500, expected + 1000.5]).clamp(0.0, double.infinity).toDouble();
          final r = await op('cashCount', {'box': b, 'expected': expected, 'counted': counted});
          if (r['ok'] != true) {
            bad('$label: لم يُحفظ جرد (${r['err']})');
            continue;
          }
          final rv = await op('cashReview', {'id': r['id']});
          if (rv['ok'] != true) {
            notes.add('ترحيل الجرد: ${rv['err']}');
            continue;
          }
          final before = box[b]!;
          final bal = (await op('boxBalances')).map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
          final moved = (bal[b] ?? 0) - before;
          if ((moved - (counted - expected)).abs() > 0.005) {
            bad('$label: ترحيل الجرد حرّك الصندوق $moved والفرق المعدود ${counted - expected}');
          }
          box[b] = bal[b] ?? 0;
          count(counted == expected ? 'جرد مطابق' : 'جرد بفرق');
        } else {
          // ── التوصيل ──
          final orders = [
            for (var k = 1 + rnd.nextInt(5); k > 0; k--)
              {'cod': (pick([25000, 1250.5, 0]) * 100).round(), 'fee': 500000, 'delivered': rnd.nextDouble() < 0.7}
          ];
          final r = await op('delivery', {'company': 'شركة ${rnd.nextInt(1 << 30)}', 'orders': orders});
          if (r['ok'] != true) {
            bad('$label: التوصيل فشل (${r['err']})');
            continue;
          }
          if (r['cod'] != r['expectedCod']) bad('$label: تسوية التوصيل ${r['cod']} والمسلَّم ${r['expectedCod']}');
          if (r['again'] != 0) bad('$label: بقي ${r['again']} طلب غير مُسوّى بعد التسوية');
          count('تسوية توصيل');
        }
        await checkAll(label);
        if (i % 20 == 0) {
          final line = '$i/$_ops — مشاكل ${problems.length} — ${sw.elapsed.inMinutes} دقيقة';
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
        ..writeln('الصندوق والمحاسبة — seed=$seed — ${failed ? 'FAIL' : 'PASS'} — ${sw.elapsed.inMinutes} دقيقة')
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
