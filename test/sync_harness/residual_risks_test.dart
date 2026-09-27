// المخاطر المتبقية بعد إصلاحات المزامنة — كل واحدة صارت تُعالَج أو تُكتشف آلياً:
//   1. تعديل سجلات نسخة احتياطية مستعادة قبل أن يلحق الجهاز بالبقية ← مقفل.
//   2. حذف الأصناف وحركات المخزون من السحابة من خارج التطبيق ← تعود وحدها.
//   3. جهاز بإصدار قديم في المجموعة، وساعة جهاز غير مضبوطة ← تنبيه.
//   4. قواعد Firestore ترفض مجموعة ← تنبيه.
//   flutter test test/sync_harness/residual_risks_test.dart
// ignore_for_file: avoid_print

import 'package:alnaser/services/firebase_sync/sync_health.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<List<String>> _healthIds(Harness h, String dev) async =>
    ((await h.d(dev).call('syncHealth')) as List)
        .map((w) => (w as Map)['id'] as String)
        .toList();

Future<List<String>> _healthTitles(Harness h, String dev) async =>
    ((await h.d(dev).call('syncHealth')) as List)
        .map((w) => (w as Map)['title'] as String)
        .toList();

Future<void> _settled(Harness h, String stage) async {
  final errs = await h.settle();
  expect(errs, isEmpty, reason: '$stage:\n${errs.join('\n')}');
}

void main() {
  test('بعد استعادة نسخة احتياطية: السجلات القديمة مقفلة حتى يلحق الجهاز، والجديد مسموح', () async {
    final h = Harness(seed: 21);
    try {
      await h.start(2);
      final c = (await h.addCustomer('D1', 'زبون الاستعادة'))!;
      final t1 = (await h.addTx('D1', c, 1000))!;
      final inv0 = (await h.saveInvoice('D1', c, 400, 0, 'دين'))!;
      await _settled(h, 'البداية');

      await h.backup('D1'); // النسخة: المعاملة 1000
      await h.editTx('D1', t1, 300); // بعد النسخة: صارت 300 عند الجميع
      await _settled(h, 'بعد التعديل');

      // استعادة النسخة القديمة بلا إنترنت: الجهاز يعرض 1000 ولا يستطيع اللحاق
      await h.setOnline('D1', false);
      expect(await h.restoreBackup('D1'), isTrue);
      expect(await _healthIds(h, 'D1'), contains('recovering'));

      // تعديل ما جاء من النسخة: مرفوض (كان يُطبَّق على 1000 ويُنشر للجميع)
      expect(await h.d('D1').call('editTx', {'tx': t1, 'amount': 50}), {'locked': true});
      expect(await h.d('D1').call('convertTx', {'tx': t1}), {'locked': true});
      final del = await h.d('D1').call('deleteCustomer', {'cust': c}) as Map;
      expect(del['locked'], isTrue);
      final rejectedBefore = h.rejectedInvoices;
      expect(await h.saveInvoice('D1', c, 450, 0, 'دين', inv: inv0), isNull);
      expect(h.rejectedInvoices, rejectedBefore + 1);

      // الجديد مسموح: تسديد/دين وفاتورة
      expect(await h.addTx('D1', c, 200), isNotNull);
      expect(await h.saveInvoice('D1', c, 500, 0, 'دين'), isNotNull);

      // يعود الاتصال ← يلحق بالبقية وتنتهي الاستعادة (المعاملة 300 كما عند الجميع)
      await _settled(h, 'بعد اكتمال الاستعادة');
      expect(await _healthIds(h, 'D1'), isNot(contains('recovering')));

      // والآن يُسمح بتعديلها — على قيمتها الصحيحة
      final lockedBefore = h.lockedEdits;
      await h.editTx('D1', t1, 350);
      expect(h.lockedEdits, lockedBefore, reason: 'بعد الاستعادة يجب أن يُقبل التعديل');
      await _settled(h, 'بعد تعديل ما بعد الاستعادة');
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('حذف الأصناف وحركات المخزون من السحابة من خارج التطبيق ← تعود، والجهاز الجديد يحسب الكمية الصحيحة',
      () async {
    final h = Harness(seed: 22);
    try {
      await h.start(2);
      final c = (await h.addCustomer('D1', 'زبون السحابة'))!;
      final p = (await h.addProduct('D1', 'صنف السحابة', 50, carton: 12))!;
      await _settled(h, 'البداية');
      await h.purchase('D2', p, 10);
      await h.adjustStock('D1', p, -3);
      await h.saveInvoice('D2', c, 24, 0, 'دين', items: [
        {'prod': p, 'qty': 2.0, 'large': true}, // 24 قطعة
      ]);
      await _settled(h, 'بعد الحركات');
      final movements = h.cloud.collection('stock_movements').length;

      // 1) حُذفت من لوحة Firebase ثم انضم جهاز جديد: المُجيب يعيدها قبل تنزيله
      h.cloud.clearCollection('products');
      h.cloud.clearCollection('stock_movements');
      await h.joinNewDevice();
      await _settled(h, 'جهاز جديد بعد حذف السحابة');
      expect(h.cloud.collection('products').keys, contains(p));
      expect(h.cloud.collection('stock_movements').length, movements);
      print('الكمية على الجهاز الجديد = ${h.truth.stock(p)} (50 + 10 − 3 − 24)');

      // 2) حُذفت مرة أخرى: أي جهاز يُعاد تشغيله يعيدها وحده (بلا جهاز جديد)
      h.cloud.clearCollection('products');
      h.cloud.clearCollection('stock_movements');
      await h.restart('D2');
      await _settled(h, 'بعد إعادة تشغيل D2');
      expect(h.cloud.collection('products').keys, contains(p));
      expect(h.cloud.collection('stock_movements').length, movements);
      await h.joinNewDevice();
      await _settled(h, 'جهاز جديد ثانٍ');
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('جهاز بإصدار قديم في المجموعة وساعة جهاز غير مضبوطة ← تنبيه يزول بزوال سببه', () async {
    final h = Harness(seed: 23);
    try {
      await h.start(2);
      await _settled(h, 'البداية');
      final now = DateTime.now();

      // جهاز بإصدار قديم ظهر اليوم (لا يكتب رقم البروتوكول)، وآخر لم يظهر منذ شهر
      h.cloud.putDoc('devices/old_pc', {
        'deviceId': 'old_pc',
        'deviceName': 'حاسوب المخزن',
        'lastSeen': now.toIso8601String(),
        'appVersion': '1.0.0',
      });
      h.cloud.putDoc('devices/gone_phone', {
        'deviceId': 'gone_phone',
        'deviceName': 'هاتف قديم مهمل',
        'lastSeen': now.subtract(const Duration(days: 30)).toIso8601String(),
        'appVersion': '1.0.0',
      });
      await h.d('D1').call('checkGroupHealth');
      expect(await _healthIds(h, 'D1'), contains('older_devices'));
      final titles = (await _healthTitles(h, 'D1')).join(' | ');
      expect(titles, contains('حاسوب المخزن'));
      expect(titles, isNot(contains('هاتف قديم مهمل')));
      expect(await _healthIds(h, 'D1'), isNot(contains('this_device_older')));

      // الجهاز حُدّث: يكتب رقم البروتوكول ← يزول التنبيه
      h.cloud.putDoc('devices/old_pc', {
        'deviceId': 'old_pc',
        'deviceName': 'حاسوب المخزن',
        'lastSeen': now.toIso8601String(),
        'syncProtocol': SyncHealth.syncProtocol,
      });
      await h.d('D1').call('checkGroupHealth');
      expect(await _healthIds(h, 'D1'), isNot(contains('older_devices')));

      // جهاز بإصدار أحدث: هذا الجهاز هو القديم
      h.cloud.putDoc('devices/new_pc', {
        'deviceId': 'new_pc',
        'deviceName': 'حاسوب جديد',
        'lastSeen': now.toIso8601String(),
        'syncProtocol': SyncHealth.syncProtocol + 1,
      });
      await h.d('D1').call('checkGroupHealth');
      expect(await _healthIds(h, 'D1'), contains('this_device_older'));

      // ساعة D2 متقدمة 20 دقيقة ← تنبيه؛ تُضبط ← يزول
      await h.d('D2').call('setClockOffset', {'minutes': 20});
      await h.d('D2').call('checkGroupHealth');
      expect(await _healthIds(h, 'D2'), contains('clock'));
      await h.d('D2').call('setClockOffset', {'minutes': 0});
      await h.d('D2').call('checkGroupHealth');
      expect(await _healthIds(h, 'D2'), isNot(contains('clock')));
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('لا اسمان متطابقان لصنفين على جهاز واحد (إضافة وإعادة تسمية) + تنبيه تكرار قديم', () async {
    final h = Harness(seed: 24);
    try {
      await h.start(2);
      final sugar = (await h.addProduct('D1', 'سكر', 10))!;
      await _settled(h, 'البداية');

      // D2 وصله «سكر» من D1: إضافة «سكر» مرة ثانية مرفوضة
      expect(await h.addProduct('D2', 'سكر', 5), isNull);
      // وإعادة تسمية صنف آخر إلى «سكر» مرفوضة
      final rice = (await h.addProduct('D2', 'رز', 7))!;
      expect(await h.d('D2').call('renameProduct', {'prod': rice, 'name': 'سكر'}),
          {'refused': true});
      // وتعديل الصنف نفسه باسمه (أو اسم جديد غير مستعمل) مسموح
      expect(await h.d('D2').call('renameProduct', {'prod': rice, 'name': 'رز بسمتي'}),
          {'refused': false});
      await _settled(h, 'بعد الإضافة وإعادة التسمية');
      expect(h.cloud.collection('products')[sugar]?['name'], 'سكر');

      // تكرار قديم من إصدار سابق ← تنبيه يسمّيه
      await h.d('D1').call('legacyDuplicate', {'name': 'شاي قديم'});
      await h.d('D1').call('legacyDuplicate', {'name': 'شاي قديم'});
      await h.d('D1').call('checkLocalDuplicates');
      expect(await _healthIds(h, 'D1'), contains('local_duplicates'));
      expect((await _healthTitles(h, 'D1')).join(), contains('شاي قديم'));
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('فاتورة نُقلت من عميل ثم حُذف العميل على جهاز آخر ← يختفي على كل الأجهزة', () async {
    final h = Harness(seed: 25);
    try {
      await h.start(3);
      final y = (await h.addCustomer('D1', 'عميل قديم للفاتورة'))!;
      final z = (await h.addCustomer('D1', 'عميل جديد للفاتورة'))!;
      final inv = (await h.saveInvoice('D1', y, 400, 0, 'دين'))!;
      await _settled(h, 'البداية');
      // نقل الفاتورة: عند المالك يبقى لـ y صف تسوية صافيه صفر
      expect(await h.saveInvoice('D1', z, 400, 0, 'دين', inv: inv), inv);
      await _settled(h, 'بعد النقل');
      // حذف y على جهاز لا يعرف ذلك الصف (نُسب عنده لـ z)
      await h.deleteCustomer('D2', y);
      await _settled(h, 'بعد حذف العميل القديم');
      expect(await h.deviceErrors(), isEmpty);
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('قواعد Firestore ترفض مجموعة ← تنبيه، ويزول عند أول رفع ناجح', () {
    const denied = 'permission-denied';
    SyncHealth.reportUploadError(
        'stock_movements', FirebaseException(plugin: 'cloud_firestore', code: denied));
    expect(SyncHealth.warnings.value.map((w) => w.id), contains('rules'));
    // خطأ آخر (انقطاع شبكة) لا يُعدّ رفض قواعد
    SyncHealth.reportUploadError(
        'products', FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
    expect(SyncHealth.warnings.value.where((w) => w.id == 'rules').single.title,
        isNot(contains('الأصناف')));
    SyncHealth.reportUploadOk('stock_movements');
    expect(SyncHealth.warnings.value.map((w) => w.id), isNot(contains('rules')));
  });
}
