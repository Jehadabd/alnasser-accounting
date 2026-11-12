// test/sync_harness/rare_gaps_test.dart
//
// 🧭 نقاط المزامنة النادرة التي لم يمر بها اختبار (تقرير claude_money_coverage.bat) — كل
// سيناريو يصنع الظرف بالضبط بكود التطبيق الحقيقي: مستند سحابي من إصدار قديم أو من جهاز متأخر
// (FakeCloud.putDocNow)، أو بيانات قديمة في القاعدة، أو سباق محجوز (holdNextWrite)، ثم:
//   • كل الأجهزة تطابق «الحقيقة» (settle)، ولا معاملة تضيع ولا تتكرر، ولا خطأ غير ممسوك.
//
//   R1 مستند معاملتي يصل «محذوفاً» (شاهد حذف) ⇒ تُحذف عندي وعند الجميع.
//   R2 نسخة أقدم من معاملتي بكتابتي وصلت بعد تعديلي ⇒ أعيد رفع نسختي.
//   R3 جهاز آخر أعاد بثّ نسخة قديمة من معاملتي ⇒ أعيد رفع نسختي.
//   R4 تعديل المعاملة أثناء «أعد رفع معاملتي» ⇒ لا تُعلَّم «مرفوعة» بالنسخة القديمة.
//   R5 صف دين فاتورة وصل منفصلاً (إصدار قديم) ثم وصلت حزمتها ⇒ يُربط ولا يتكرر.
//   R6 فاتورة آجلة واردة بلا عميل وبلا معاملة دين (إصدار قديم) ⇒ تُصلَح عند الإقلاع.
//   R7 سجل الرفع (WAL) فيه عمليات انقطعت ⇒ لا يُحيي مالاً من السجل (تصحيح p160).
//   R8 استعادة نسخة على جهاز بلا مزامنة ⇒ يُلغى وضع الاستعادة عند الإقلاع.
//
// التشغيل: claude_test_gaps.bat
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

class _Run {
  final List<String> failed = [];
  int passed = 0;
}

Future<void> _scenario(_Run run, String name, int devices, Future<void> Function(Harness h) body,
    {int seed = 160}) async {
  print('\n━━ $name');
  final h = Harness(seed: seed);
  final problems = <String>[];
  try {
    await h.start(devices);
    await body(h);
    problems.addAll(await h.settle());
    problems.addAll(await h.deviceErrors());
  } catch (e, st) {
    problems.add('استثناء: $e\n${st.toString().split('\n').take(4).join('\n')}');
  } finally {
    try {
      await h.dispose();
    } catch (_) {}
  }
  if (problems.isEmpty) {
    run.passed++;
    print('✓ $name');
  } else {
    run.failed.add(name);
    print('✗ هنا وقع خطأ في «$name»:\n  ${problems.join('\n  ')}');
  }
}

Future<void> _stable(Harness h, String stage) async {
  final errs = await h.settle();
  if (errs.isNotEmpty) throw StateError('قبل الظرف النادر ($stage):\n${errs.join('\n')}');
}

Future<List<Map>> _sql(Harness h, String dev, String sql) async =>
    ((await h.d(dev).call('sqlRaw', {'sql': sql})) as List).cast<Map>();

/// مستند المعاملة في السحابة مع تعديل [change] عليه، يُكتب الآن.
void _inject(Harness h, String tx, void Function(Map<String, Object?> d) change) {
  final doc = h.cloud.docEndingWith('transactions/$tx');
  if (doc == null) throw StateError('مستند المعاملة $tx ليس في السحابة');
  final (path, data) = doc;
  change(data);
  h.cloud.putDocNow(path, data);
}

void main() {
  test('🧭 نقاط المزامنة النادرة غير المغطاة', () async {
    final run = _Run();

    await _scenario(run, 'R1 مستند معاملتي يصل «محذوفاً» ⇒ تُحذف عندي وعند الجميع', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R1'))!;
      await h.addTx('D1', c, 1000);
      final t = (await h.addTx('D1', c, 300))!;
      await _stable(h, 'البداية');
      _inject(h, t, (d) {
        d['isDeleted'] = true;
        d['is_deleted'] = 1; // كاتبه ما زال D1
      });
      h.truth.txs[t]!.deleted = true;
    });

    await _scenario(run, 'R2 نسخة أقدم من معاملتي بكتابتي وصلت بعد تعديلي ⇒ أعيد رفع نسختي', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R2'))!;
      final t = (await h.addTx('D1', c, 1000))!;
      await _stable(h, 'البداية');
      await h.editTx('D1', t, 1500);
      await _stable(h, 'بعد التعديل');
      _inject(h, t, (d) {
        d['amountChanged'] = 1000.0;
        d['lastModifiedAt'] = '2020-01-01T00:00:00.000'; // أقدم من آخر رفع لي
      });
    });

    await _scenario(run, 'R3 جهاز أعاد بثّ نسخة قديمة من معاملتي ⇒ أعيد رفع نسختي', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R3'))!;
      final t = (await h.addTx('D1', c, 1000))!;
      await _stable(h, 'البداية');
      await h.editTx('D1', t, 1500);
      await _stable(h, 'بعد التعديل');
      _inject(h, t, (d) {
        d['amountChanged'] = 1000.0;
        d['lastModifiedAt'] = '2020-01-01T00:00:00.000';
        d['deviceId'] = 'rebroadcast'; // إعادة بثّ من جهاز لا يعرف منشئها
        d['originDeviceId'] = 'rebroadcast';
      });
    });

    await _scenario(run, 'R4 تعديل المعاملة أثناء «أعد رفع معاملتي» ⇒ لا تُعلَّم «مرفوعة» بالقديمة', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R4'))!;
      final t = (await h.addTx('D1', c, 500))!;
      await _stable(h, 'البداية');
      h.cloud.holdNextWrite('D1', 'transactions/$t');
      await h.d('D1').call('forceReuploadStart', {'tx': t});
      for (var i = 0; i < 100 && !h.cloud.hasHeld('D1'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!h.cloud.hasHeld('D1')) throw StateError('لم يبدأ «أعد رفع معاملتي»');
      final edit = h.editTx('D1', t, 450); // التعديل والرفع معلّق
      await Future<void>.delayed(const Duration(milliseconds: 500));
      h.cloud.releaseHeld('D1');
      final ok = await h.d('D1').call('forceReuploadAwait', const {}, const Duration(minutes: 2));
      await edit;
      if (ok != true) throw StateError('«أعد رفع معاملتي» فشل: $ok');
    });

    await _scenario(run, 'R5 صف دين فاتورة وصل منفصلاً ثم وصلت حزمتها ⇒ يُربط بها ولا يتكرر', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R5'))!;
      await h.addTx('D1', c, 100);
      await _stable(h, 'البداية');
      await h.setOnline('D1', false);
      final inv = (await h.saveInvoice('D1', c, 3000, 0, 'دين'))!;
      final rows = await _sql(h, 'D1',
          "SELECT transaction_uuid AS u, amount_changed AS a FROM transactions WHERE invoice_sync_uuid = '$inv' AND COALESCE(is_deleted, 0) = 0");
      if (rows.isEmpty) throw StateError('لا صف دين للفاتورة على D1');
      for (final r in rows) {
        await h.d('D2').call('gap', {
          'op': 'legacyInvoiceTx',
          'args': {'cust': c, 'uuid': r['u'], 'amount': r['a'], 'origin': 'dev_D1'},
        });
      }
      final errs = await h.settle(); // تصل الحزمة
      if (errs.isNotEmpty) throw StateError('بعد وصول الحزمة:\n${errs.join('\n')}');
      for (final r in rows) {
        final x = await _sql(h, 'D2',
            "SELECT COUNT(*) AS n, MAX(invoice_sync_uuid) AS inv FROM transactions WHERE transaction_uuid = '${r['u']}'");
        if ((x.first['n'] as num) != 1) throw StateError('صف دين الفاتورة على D2 ${x.first['n']} صفاً والمتوقع واحد');
        if (x.first['inv'] != inv) throw StateError('صف الدين القديم لم يُربط بفاتورته (${x.first['inv']})');
      }
    });

    await _scenario(run, 'R6 فاتورة آجلة واردة بلا عميل وبلا معاملة دين ⇒ تُصلَح عند الإقلاع', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R6'))!;
      final inv = (await h.saveInvoice('D1', c, 2500, 0, 'دين'))!;
      await _stable(h, 'البداية');
      // D2 من إصدار قديم: الفاتورة وصلت وحدها (بلا ربط بالعميل ولا صف دين)
      await _sql(h, 'D2', "UPDATE invoices SET customer_id = NULL WHERE invoice_uuid = '$inv'");
      await _sql(h, 'D2', "DELETE FROM transactions WHERE invoice_sync_uuid = '$inv'");
      await h.d('D2').call('gap', {'op': 'recalc', 'args': {'cust': c}});
      await h.restart('D2');
      final x = await _sql(h, 'D2',
          "SELECT i.customer_id AS cid, (SELECT COUNT(*) FROM transactions t WHERE t.invoice_sync_uuid = i.invoice_uuid "
          "AND COALESCE(t.is_deleted, 0) = 0) AS n FROM invoices i WHERE i.invoice_uuid = '$inv'");
      if (x.first['cid'] == null) throw StateError('الفاتورة لم تُربط بعميلها عند الإقلاع');
      if ((x.first['n'] as num) < 1) throw StateError('لم يُنشأ صف دين الفاتورة عند الإقلاع');
    });

    await _scenario(run, 'R7 سجل الرفع فيه عمليات انقطعت ⇒ لا يُحيي مالاً من السجل', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R7'))!;
      await h.addTx('D1', c, 800);
      await _stable(h, 'البداية');
      final cid = (await _sql(h, 'D1', "SELECT id FROM customers WHERE sync_uuid = '$c'")).first['id'];
      String q(Object v) => jsonEncode(v).replaceAll("'", "''");
      const at = '2026-01-01T00:00:00.000';
      // معاملة وعميل في السجل «بانتظار الرفع» وليسا في القاعدة (حُذفا/دُمجا بعد ذلك)
      await _sql(h, 'D1', 'INSERT INTO sync_wal (id, type, action, sync_uuid, data, checksum, created_at, status) VALUES '
          "('transaction_walghost_1', 'transaction', 'create', 'walghost', '${q({
            'customer_id': cid,
            'amount_changed': 9999.0,
            'transaction_type': 'manual_debt',
            'transaction_date': at,
            'created_at': at,
          })}', 'x', '$at', 0)");
      await _sql(h, 'D1', 'INSERT INTO sync_wal (id, type, action, sync_uuid, data, checksum, created_at, status) VALUES '
          "('customer_walcust_1', 'customer', 'create', 'walcust', '${q({
            'name': 'عميل من السجل',
            'current_total_debt': 5000.0,
            'created_at': at,
            'last_modified_at': at,
          })}', 'x', '$at', 1)");
      await h.restart('D1'); // الإقلاع يسترد السجل
      final tx = await _sql(h, 'D1', "SELECT COUNT(*) AS n FROM transactions WHERE transaction_uuid = 'walghost'");
      if ((tx.first['n'] as num) != 0) throw StateError('أُحييت معاملة 9,999 من سجل الرفع');
      final cu = await _sql(h, 'D1', "SELECT COUNT(*) AS n FROM customers WHERE sync_uuid = 'walcust'");
      if ((cu.first['n'] as num) != 0) throw StateError('أُحيي عميل من سجل الرفع');
      final st = await _sql(h, 'D1', "SELECT id, status FROM sync_wal WHERE id IN ('transaction_walghost_1', 'customer_walcust_1')");
      for (final r in st) {
        if ((r['status'] as num) != 6) throw StateError('عملية السجل ${r['id']} حالتها ${r['status']} والمتوقع «مستردة» (6)');
      }
    });

    print('\n━━ النتيجة: نجح ${run.passed} — ${run.failed.isEmpty ? 'لا إخفاق' : 'هنا وقع خطأ في: ${run.failed.join('، ')}'}');
    expect(run.failed, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 40)));

  test('🧭 R8 استعادة نسخة على جهاز بلا مزامنة ⇒ يُلغى وضع الاستعادة عند الإقلاع', () async {
    final h = Harness(seed: 168);
    try {
      await h.spawn('S1', prefs: const {}, online: false); // محل بلا مزامنة
      final d = h.d('S1');
      double dd(Object? v) => (v as num?)?.toDouble() ?? 0.0;
      Future<double> marked() async => dd(((await d.call('sqlRaw', {
            'sql': 'SELECT (SELECT COUNT(*) FROM transactions WHERE restored_mark = 1) + '
                '(SELECT COUNT(*) FROM invoices WHERE restored_mark = 1) AS n'
          })) as List).cast<Map>().first['n']);

      final c = (await h.addCustomer('S1', 'زبون R8'))!;
      await h.addTx('S1', c, 1000);
      final path = '${h.root.path}${Platform.pathSeparator}r8_backup.db';
      await d.call('backup', {'path': path});
      await h.addTx('S1', c, 500); // بعد النسخة: تُفقد بالاستعادة
      expect(await d.call('liveRestore', {'path': path}, const Duration(minutes: 2)), isTrue);
      expect(await marked(), greaterThan(0), reason: 'الاستعادة لم تَسِم الصفوف');
      final r = (await d.call('gap', {'op': 'clearRestore'})) as Map;
      expect((r['fails'] as List), isEmpty);
      expect(await marked(), 0, reason: 'بقيت صفوف «مستعادة» على جهاز بلا مزامنة');
      await h.addTx('S1', c, 200);
      final b = (await d.call('custBalance', {'cust': c})) as Map;
      expect(dd(b['sum']), 1200, reason: 'الرصيد بعد الاستعادة والإضافة');
      expect(dd(b['debt']), 1200);
      print('✓ R8 الاستعادة على جهاز بلا مزامنة: أُلغي وسم الصفوف، والإضافة بعدها تعمل (1,200)');
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
