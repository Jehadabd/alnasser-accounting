// test/sync_harness/archive_mark_test.dart
//
// 🗄️ زر «اعتبار الفواتير القديمة مرفوعة» (إعدادات المزامنة) بكود التطبيق الحقيقي:
//   1. في المجموعة جهاز آخر ⇒ يُرفض، والفاتورة غير المرفوعة تبقى «غير مرفوعة» وتصل الجهاز
//      الآخر (مخزونه وديونه صحيحة). كان الزر يعلّمها فلا تصله أبداً.
//   2. الجهاز وحده ⇒ يعلّم فواتيره، ومن ينضم بعده يستلمها بإعادة البث (مخزونه صحيح).
//
// التشغيل: claude_test_gaps.bat
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<int> _isSynced(Harness h, String dev, String inv) async {
  final r = (await h.d(dev).call('sqlRaw', {
    'sql': "SELECT COALESCE(is_synced, 0) AS s FROM invoices WHERE invoice_uuid = '$inv'"
  })) as List;
  return ((r.single as Map)['s'] as num).toInt();
}

Future<void> _report(Harness h, List<String> errs) async {
  if (errs.isEmpty) return;
  print('✗ هنا وقع خطأ:\n${errs.join('\n')}');
  for (final d in h.devices.values) {
    print('──── سجل ${d.name}');
    print(((await d.call('logs', {'n': 60})) as List).join('\n'));
  }
}

void main() {
  test('🗄️ جهاز آخر في المجموعة ⇒ الزر يرفض والفاتورة تصله', () async {
    final h = Harness(seed: 1591);
    try {
      await h.start(2);
      final c = (await h.addCustomer('D1', 'زبون الأرشيف'))!;
      final p = (await h.addProduct('D1', 'مادة الأرشيف', 100))!;
      expect(await h.settle(), isEmpty);

      // فواتير أوفلاين لم تُرفع بعد: نقدية (مخزون فقط) وآجلة (دين)
      await h.setOnline('D1', false);
      final cash = (await h.saveInvoice('D1', c, 3000, 3000, 'نقد', items: [
        {'prod': p, 'qty': 3.0, 'large': false},
      ]))!;
      final credit = (await h.saveInvoice('D1', c, 2000, 0, 'دين', items: [
        {'prod': p, 'qty': 2.0, 'large': false},
      ]))!;

      final r = (await h.d('D1').call('markArchive')) as Map;
      print('  الرد: ${r['refused'] ?? 'عُلِّمت ${r['marked']}'}');
      expect(r['refused'], isNotNull, reason: 'في المجموعة D2: كان يجب الرفض');
      expect(r['marked'], 0);
      expect(await _isSynced(h, 'D1', cash), 0, reason: 'الفاتورة النقدية عُلِّمت «مرفوعة» رغم الرفض');
      expect(await _isSynced(h, 'D1', credit), 0, reason: 'الفاتورة الآجلة عُلِّمت «مرفوعة» رغم الرفض');
      print('✓ رُفض والفاتورتان باقيتان للرفع');

      final errs = await h.settle();
      await _report(h, errs);
      expect(errs, isEmpty);
      print('✓ D2 استلم الفاتورتين: المخزون 95 والدين 2000 على الجهازين');
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('🗄️ الجهاز وحده ⇒ يعلّم، والمنضم بعده يستلم كل الفواتير', () async {
    final h = Harness(seed: 1592);
    try {
      await h.start(1);
      final c = (await h.addCustomer('D1', 'زبون الأرشيف'))!;
      final p = (await h.addProduct('D1', 'مادة الأرشيف', 100))!;
      expect(await h.settle(), isEmpty);

      // أرشيف لم يُرفع: فاتورة نقدية أوفلاين، وكتابتها المنتظرة ضاعت (أُغلق التطبيق)
      await h.setOnline('D1', false);
      final inv = (await h.saveInvoice('D1', c, 4000, 4000, 'نقد', items: [
        {'prod': p, 'qty': 4.0, 'large': false},
      ]))!;
      h.cloud.failQueued('D1');

      final r = (await h.d('D1').call('markArchive')) as Map;
      print('  الرد: ${r['refused'] ?? 'عُلِّمت ${r['marked']}'}');
      expect(r['refused'], isNull, reason: 'الجهاز وحده: كان يجب التعليم');
      expect((r['marked'] as num) >= 1, isTrue);
      expect(await _isSynced(h, 'D1', inv), 1);
      print('✓ الجهاز وحده: عُلِّمت ${r['marked']} فاتورة');

      await h.setOnline('D1', true);
      await h.waitCloudQuiet();
      final absent = !h.cloud.hasDocEndingWith('invoices/$inv');
      print('  الفاتورة ${absent ? 'غائبة عن السحابة قبل الانضمام' : 'موجودة في السحابة قبل الانضمام'}');

      await h.joinNewDevice(); // D2: يطلب إعادة البث
      final errs = await h.settle();
      await _report(h, errs);
      expect(errs, isEmpty);
      print('✓ D2 انضم واستلم الفاتورة${absent ? ' بإعادة البث' : ''}: المخزون 96 على الجهازين');
      expect(await h.deviceErrors(), isEmpty);
      print('\n✅ نجح: الزر لا يُفقد جهازاً آخر فاتورة');
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
