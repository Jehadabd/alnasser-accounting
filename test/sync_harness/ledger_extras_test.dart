// test/sync_harness/ledger_extras_test.dart
//
// 💳 مسارات المال الباقية على دين العميل (المرحلة 1 من «كل مسارات المال»):
//   • الاستحقاقات: شيك/ورقة قبض تنزل من الرصيد أو لا تنزل، الأقساط، التحصيل الجزئي
//     والكامل، الارتداد (يعود ما نزل بالضبط)، الإلغاء (يُمنع إن نزل من الرصيد أو حُصّل منه).
//   • مطابقة كشف الحساب مع تسوية الفرق: الرصيد بعدها = المتفق عليه بالضبط.
//   • تسديد دين راجع: ينقص الدين، ويُسجَّل راجعاً بالمبلغ نفسه الذي حُفظ.
// على الكود الحقيقي، جهازان يتزامنان، كل مبلغ متوقَّع بقاعدة الدينار الصحيح.
//
// التشغيل: claude_test_ledger_extras.bat [quick|full] [seed]
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:alnaser/utils/iqd.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _quick = bool.fromEnvironment('QUICK');
const _seedArg = int.fromEnvironment('SEED');
const _ops = int.fromEnvironment('OPS', defaultValue: _quick ? 250 : 2500);
const _perDev = _quick ? 4 : 10;
const _maxProblems = int.fromEnvironment('MAX_PROBLEMS', defaultValue: 15);

class _Due {
  _Due(this.id, this.dev, this.cust, this.kind, this.currency, this.fx, this.amount, this.affects, this.installment);
  final int id;
  final String dev, cust, kind, currency;
  final double fx, amount;
  final bool affects, installment;
  double paid = 0;
  String status = 'open';
}

void main() {
  final seed = _seedArg != 0 ? _seedArg : DateTime.now().microsecondsSinceEpoch % 1000000 + 1;
  test('مسارات الدين الباقية: $_ops عملية seed=$seed', () async {
    print('🎲 seed=$seed — لإعادة هذا التشغيل: --dart-define=SEED=$seed');
    final h = Harness(seed: seed);
    final rnd = Random(seed * 17 + 3);
    final problems = <String>[];
    final stats = <String, int>{};
    void count(String k) => stats[k] = (stats[k] ?? 0) + 1;
    final sw = Stopwatch()..start();
    final out = Directory('test_results${Platform.pathSeparator}ledger_extras')..createSync(recursive: true);
    final progress = File('${out.path}${Platform.pathSeparator}progress.txt');
    void bad(String p) {
      problems.add(p);
      print('✗ $p');
    }

    void near(String what, Object? got, double want) {
      final g = (got as num?)?.toDouble();
      if (g == null || (g - want).abs() > 0.005) bad('$what = $g والمتوقع $want');
    }

    var failed = true;
    try {
      const devs = ['D1', 'D2'];
      await h.start(2);
      final home = <String, String>{};
      final custs = <String, List<String>>{for (final d in devs) d: []};
      var n = 0;
      for (final d in devs) {
        for (var i = 0; i < _perDev; i++) {
          final c = await h.addCustomer(d, 'زبون المستحقات ${++n}');
          if (c == null) continue;
          home[c] = d;
          custs[d]!.add(c);
          // رصيد ابتدائي يسمح بالتسديد والشيكات
          await h.addTx(d, c, 500000);
        }
      }
      var errs = await h.settle();
      if (errs.isNotEmpty) bad('البداية: ${errs.first}');
      final dues = <_Due>[];
      var marker = 0;

      Future<void> verifyCust(String c, String label) async {
        final b = ((await h.d(home[c]!).call('custBalance', {'cust': c}) as Map?) ?? const {}).cast<String, Object?>();
        near('$label: دين العميل على جهازه', b['debt'], h.truth.balance(c));
        near('$label: مجموع معاملاته', b['sum'], h.truth.balance(c));
      }

      /// يتبنّى معاملات الفعل في الحقيقة ويفحص أن مجموعها = المتوقع وعددها كما يجب.
      void adopt(String dev, String label, Map r, double want, {int? countWant}) {
        final txs = (r['txs'] as List).cast<List>();
        var sum = 0.0;
        for (final t in txs) {
          sum += (t[2] as num).toDouble();
          h.truth.txs[t[0] as String] = TruthTx(t[1] as String, dev, (t[2] as num).toDouble(), '${t[3]}');
        }
        near('$label: أثره على الدين', sum, want);
        if (countWant != null && txs.length != countWant) bad('$label: ${txs.length} معاملة والمتوقع $countWant');
      }

      // 🔬 عند أول فرق في المزامنة: تشخيص كامل في ملف (مرة واحدة) — أي جهاز ينقصه ماذا،
      //    هل وصل إلى السحابة، حالة كل جهاز، وآخر سجلّاته.
      var diagDone = false;
      Future<void> diag(String label, List<String> all) async {
        if (diagDone) return;
        diagDone = true;
        final b = StringBuffer()..writeln('🔬 تشخيص المزامنة عند $label — seed=$seed');
        b.writeln('كل الفروق (${all.length}):');
        for (final e in all) {
          b.writeln('  $e');
        }
        final cloudTx = h.cloud.collection('transactions');
        final cloudInv = h.cloud.collection('invoices');
        b.writeln('السحابة: ${cloudTx.length} معاملة، ${cloudInv.length} فاتورة — الحقيقة: ${h.truth.txs.length} معاملة');
        for (final d in devs) {
          final st = (await h.d(d).call('state') as Map).cast<String, Object?>();
          final txs = (st['txs'] as List).cast<Map>();
          final have = {for (final t in txs) t['uuid'] as String?: t};
          b.writeln('══ $d: معلّقة=${st['pending']} استعادة=${st['recovering']} تمهيد=${st['bootstrapping']} '
              'أخطاء=${st['errors']} معاملات=${txs.length}');
          final missing = h.truth.txs.entries.where((e) => !e.value.deleted && !have.containsKey(e.key)).toList();
          b.writeln('   غائبة عنه من الحقيقة: ${missing.length} (منها في السحابة: ${missing.where((e) => cloudTx.containsKey(e.key)).length})');
          for (final e in missing.take(20)) {
            final c = cloudTx[e.key];
            b.writeln('   ✗ ${e.key} ${e.value.amount} نوع=${e.value.type} مالك=${e.value.owner} '
                'عميل=${h.truth.customers[e.value.cust]?.name} '
                'في السحابة=${c == null ? 'لا' : 'نعم del=${c['isDeleted']} من=${c['deviceId']}'}');
          }
          final extra = txs.where((t) => t['uuid'] != null && !h.truth.txs.containsKey(t['uuid']) && (t['del'] ?? 0) == 0).toList();
          b.writeln('   زائدة عنده ليست في الحقيقة: ${extra.length}');
          for (final t in extra.take(10)) {
            b.writeln('   + $t');
          }
          final unUp = txs.where((t) => (t['up'] ?? 0) == 0 && (t['mine'] ?? 1) != 0).length;
          b.writeln('   لم تُرفع: $unUp');
          final errs = (await h.d(d).call('errors') as List).cast<String>();
          for (final e in errs.take(10)) {
            b.writeln('   ❌ ${e.split('\n').take(6).join(' | ')}');
          }
          final logs = (await h.d(d).call('logs', {'n': 3000}) as List).cast<String>();
          final key = RegExp(r'❌|⚠️|Exception|Error|خطأ|فشل|تعذّر|IQD|رُفض|abort', caseSensitive: false);
          final hits = logs.where((l) => key.hasMatch(l) && !l.contains('FTS5')).toList();
          b.writeln('   سجلّ (${hits.length} سطراً مهماً من ${logs.length}):');
          for (final l in hits.skip(hits.length > 60 ? hits.length - 60 : 0)) {
            b.writeln('     ${l.length > 400 ? l.substring(0, 400) : l}');
          }
        }
        final m = RegExp(r'رصيد (.+?) = ').firstMatch(all.first);
        if (m != null) {
          final cu = h.truth.customers.entries.where((e) => e.value.name == m.group(1)).map((e) => e.key).firstOrNull;
          if (cu != null) b.writeln(await h.explain(cu));
        }
        File('${out.path}${Platform.pathSeparator}diag_$seed.txt').writeAsStringSync(b.toString());
        print('🔬 التشخيص: ${out.path}${Platform.pathSeparator}diag_$seed.txt');
      }

      for (var i = 1; i <= _ops; i++) {
        if (problems.length >= _maxProblems) break;
        final dev = devs[rnd.nextInt(2)];
        final c = custs[dev]![rnd.nextInt(custs[dev]!.length)];
        final label = '#$i';
        final bal = h.truth.balance(c);
        final w = rnd.nextDouble();
        if (w < 0.30) {
          // ── إنشاء استحقاق ──
          final kind = const ['cheque_in', 'receivable_note', 'installment'][rnd.nextInt(3)];
          final usd = rnd.nextDouble() < 0.2;
          const fx = 1310.0;
          final amount = usd ? [12.5, 100.0, 33.33][rnd.nextInt(3)] : [100000.0, 25000.5, 9999.0, 1000.75][rnd.nextInt(4)];
          final affect = kind != 'installment' && rnd.nextBool();
          final nInst = kind == 'installment' ? 2 + rnd.nextInt(4) : 1;
          final whole = usd ? amount : Iqd.down(amount);
          final base = usd ? Iqd.down(amount * fx) : whole;
          if (affect && base > bal) continue;
          final r = (await h.rest(dev, 'dueCreate', {
            'kind': kind,
            'cust': c,
            'amount': amount,
            'currency': usd ? 'USD' : 'IQD',
            'fx': usd ? fx : 1.0,
            'n': nInst,
            'affect': affect,
          }) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفض استحقاق سليم (${r['err']})');
            continue;
          }
          adopt(dev, '$label إنشاء ${affect ? 'ينزل من الرصيد' : 'لا ينزل'}', r, affect ? -base : 0.0, countWant: affect ? 1 : 0);
          final parts = (r['dues'] as List).cast<Map>();
          if (parts.length != nInst) bad('$label: ${parts.length} قسط والمتوقع $nInst');
          final sum = parts.fold(0.0, (a, p) => a + (p['amount'] as num).toDouble());
          near('$label: مجموع الأقساط', sum, whole);
          for (final p in parts) {
            if (!usd && !Iqd.isWhole(p['amount'] as num)) bad('$label: قسط بكسور ${p['amount']}');
            dues.add(_Due((p['id'] as num).toInt(), dev, c, kind, usd ? 'USD' : 'IQD', usd ? fx : 1.0,
                (p['amount'] as num).toDouble(), affect, kind == 'installment'));
          }
          count('استحقاق $kind${affect ? ' ينزل' : ''}${usd ? ' دولار' : ''}');
        } else if (w < 0.55) {
          // ── تحصيل جزئي أو كامل ──
          final open = dues.where((d) => d.dev == dev && (d.status == 'open' || d.status == 'partial')).toList();
          if (open.isEmpty) continue;
          final d = open[rnd.nextInt(open.length)];
          final rem = d.amount - d.paid;
          final want = [rem, rem * 0.5, rem + 1000, 0.4][rnd.nextInt(4)];
          final x = d.currency == 'IQD' ? Iqd.down(want) : ((want * 100).roundToDouble() / 100);
          final ok = x > 0 && x <= rem + 0.005;
          final ledger = d.affects ? 0.0 : -(d.currency == 'IQD' ? x : Iqd.down(x * d.fx));
          if (ok && -ledger > h.truth.balance(d.cust) + 0.005) continue;
          final r = (await h.rest(dev, 'dueSettle', {'id': d.id, 'amount': want}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            if (ok) bad('$label: رُفض تحصيل سليم $want من ${d.kind} (${r['err']})');
            if (!ok) count('رُفض كما يجب: تحصيل أكبر من المتبقي أو صفر');
            continue;
          }
          if (!ok) bad('$label: قُبل تحصيل $want والمتبقي $rem');
          adopt(dev, '$label تحصيل', r, ledger);
          d.paid += x;
          near('$label: المحصَّل من الاستحقاق', (r['due'] as Map)['paid'], d.paid);
          d.status = d.paid >= d.amount - 0.005 ? 'closed' : 'partial';
          if ((r['due'] as Map)['status'] != d.status) bad('$label: حالة الاستحقاق ${(r['due'] as Map)['status']} والمتوقع ${d.status}');
          count('تحصيل ${d.paid >= d.amount - 0.005 ? 'كامل' : 'جزئي'}');
          await verifyCust(d.cust, label);
        } else if (w < 0.68) {
          // ── ارتداد: يعود ما نزل بالضبط ──
          final open = dues.where((d) => d.dev == dev && !d.installment && (d.status == 'open' || d.status == 'partial')).toList();
          if (open.isEmpty) continue;
          final d = open[rnd.nextInt(open.length)];
          final rem = d.amount - d.paid;
          final back = d.affects ? (d.currency == 'IQD' ? rem : Iqd.down(rem * d.fx)) : 0.0;
          final r = (await h.rest(dev, 'dueBounce', {'id': d.id}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفض ارتداد سليم (${r['err']})');
            continue;
          }
          adopt(dev, '$label ارتداد', r, back);
          d.status = 'bounced';
          count('ارتداد شيك${d.affects ? ' نازل من الرصيد' : ''}');
          await verifyCust(d.cust, label);
        } else if (w < 0.74) {
          // ── إلغاء: يُمنع إن نزل من الرصيد أو حُصّل منه ──
          final open = dues.where((d) => d.dev == dev && (d.status == 'open' || d.status == 'partial')).toList();
          if (open.isEmpty) continue;
          final d = open[rnd.nextInt(open.length)];
          final allowed = !d.affects && d.paid < 0.005;
          final r = (await h.rest(dev, 'dueCancel', {'id': d.id}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            if (allowed) bad('$label: رُفض إلغاء استحقاق سليم (${r['err']})');
            if (!allowed) count('رُفض كما يجب: إلغاء استحقاق نزل أو حُصّل منه');
            continue;
          }
          if (!allowed) bad('$label: أُلغي استحقاق نزل من الرصيد أو حُصّل منه');
          adopt(dev, '$label إلغاء', r, 0, countWant: 0);
          d.status = 'cancelled';
          count('إلغاء استحقاق');
        } else if (w < 0.87) {
          // ── مطابقة كشف الحساب مع تسوية الفرق ──
          final agreed = [bal, bal + 1500.5, bal - 250.25, max(0.0, bal - 10000), bal + 0.4][rnd.nextInt(5)];
          final want = Iqd.up(agreed);
          final r = (await h.rest(dev, 'reconcile', {'cust': c, 'agreed': agreed}) as Map).cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفضت مطابقة سليمة (${r['err']})');
            continue;
          }
          adopt(dev, '$label مطابقة', r, want - bal, countWant: (want - bal).abs() < 0.005 ? 0 : 1);
          near('$label: الفرق المسجّل في المطابقة', r['diff'], want - bal);
          near('$label: الرصيد المتفق عليه المسجّل', r['agreed'], want);
          count('مطابقة${(want - bal).abs() < 0.005 ? ' بلا فرق' : ' بتسوية'}');
          await verifyCust(c, label);
        } else {
          // ── تسديد دين راجع ──
          final amount = [bal * 0.1, 1250.5, 3000.0, 0.75][rnd.nextInt(4)];
          final tx = Iqd.up(-amount);
          if (tx.abs() < 0.5 || -tx > bal) continue;
          final r = (await h.rest(dev, 'debtReturn', {'cust': c, 'amount': amount, 'marker': ++marker}) as Map)
              .cast<String, Object?>();
          if (r['ok'] != true) {
            bad('$label: رُفض تسديد دين راجع سليم (${r['err']})');
            continue;
          }
          adopt(dev, '$label دين راجع', r, tx, countWant: 1);
          near('$label: المبلغ المسجّل راجعاً', r['returned'], -tx);
          count('تسديد دين راجع');
          await verifyCust(c, label);
        }
        if (i % (_quick ? 50 : 250) == 0 || i == _ops) {
          errs = await h.settle();
          if (errs.isNotEmpty) await diag(label, errs);
          for (final e in errs.take(5)) {
            bad('$label مزامنة: $e');
          }
          for (final d in devs) {
            for (final p in (await h.rest(d, 'invariants') as List).cast<String>()) {
              bad('$label/$d: $p');
            }
          }
        }
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
      final summary = StringBuffer()
        ..writeln('مسارات الدين الباقية — seed=$seed — ${failed ? 'FAIL' : 'PASS'} — ${sw.elapsed.inMinutes} دقيقة')
        ..writeln('مشاكل: ${problems.length}')
        ..writeAll(problems.take(_maxProblems).map((p) => '  ✗ $p\n'))
        ..writeln('العمليات:')
        ..writeAll(keys.map((k) => '  $k: ${stats[k]}\n'));
      File('${out.path}${Platform.pathSeparator}summary.txt').writeAsStringSync(summary.toString());
      print(summary);
      await h.dispose();
    }
    expect(problems, isEmpty);
  }, timeout: const Timeout(Duration(hours: 6)));
}
