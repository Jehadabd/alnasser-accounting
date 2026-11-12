// test/sync_harness/rare_sync_branches_test.dart
//
// 🧭 فروع المزامنة النادرة — سيناريوهات موجّهة لا عشوائية.
// (تعديل معاملة جهاز من جهاز آخر ممنوع في التطبيق — R4 يتحقق من الرفض.)
//
// اختبار الفوضى العشوائي (chaos) نادراً ما يصنع الظروف الدقيقة لهذه الفروع: استعادة نسخة
// احتياطية بعد أن رُفع تعديل، جهاز غير متصل يُحذف عميله على جهاز آخر، تعديل معاملة جهاز من
// جهاز آخر، إعادة تشغيل مفاجئة ومعاملة لم تُرفع، تصادم رقم تسلسل فاتورة بعد استعادة...
// كل سيناريو هنا يصنع ظرفاً واحداً بالضبط على أجهزة حقيقية (كود التطبيق نفسه) ثم يتحقق:
//   • كل الأجهزة متطابقة مع «الحقيقة» (ما فعله المستخدمون): أرصدة، معاملات، فواتير، ظهور.
//   • لا معاملة تضيع ولا تتكرر، ولا خطأ غير ممسوك في أي جهاز.
// أي سيناريو يفشل يُطبع «هنا وقع خطأ» مع السبب، وتستمر بقية السيناريوهات.
//
// التشغيل: claude_test_rare_sync.bat        (cover = مع خريطة الأسطر التي مرّ بها)
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

class _Run {
  final List<String> failed = [];
  int passed = 0;
}

Future<void> _scenario(_Run run, String name, int devices, Future<void> Function(Harness h) body,
    {int seed = 31}) async {
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

/// تثبيت مرحلة وسيطة: كل شيء متطابق قبل الخطوة التالية (وإلا فالخطأ قبل الظرف النادر).
Future<void> _stable(Harness h, String stage) async {
  final errs = await h.settle();
  if (errs.isNotEmpty) throw StateError('قبل الظرف النادر ($stage):\n${errs.join('\n')}');
}

void main() {
  test('🧭 فروع المزامنة النادرة', () async {
    final run = _Run();

    // ═══════════════ المعاملات ═══════════════

    await _scenario(run, 'R1 معاملة حُفظت بعد النسخة الاحتياطية ثم استُعيدت النسخة ← تعود من السحابة', 2,
        (h) async {
      final c = (await h.addCustomer('D1', 'زبون R1'))!;
      await _stable(h, 'البداية');
      await h.backup('D1');
      await h.addTx('D1', c, 1500);
      await h.addTx('D1', c, -400);
      await _stable(h, 'بعد الرفع');
      if (!await h.restoreBackup('D1')) throw StateError('لم تُستعد النسخة');
    });

    await _scenario(run, 'R2 تعديل رُفع ثم استُعيدت نسخة أقدم منه ← يبقى التعديل لا القديم', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R2'))!;
      final t = (await h.addTx('D1', c, 1000))!;
      await _stable(h, 'البداية');
      await h.backup('D1');
      await h.editTx('D1', t, 300);
      await _stable(h, 'بعد التعديل');
      if (!await h.restoreBackup('D1')) throw StateError('لم تُستعد النسخة');
    });

    await _scenario(run, 'R3 حُذف العميل على جهاز آخر وصاحب معاملاته غير متصل ← تُحذف عنده أيضاً', 3,
        (h) async {
      final c = (await h.addCustomer('D1', 'زبون R3'))!;
      await h.addTx('D1', c, 800);
      await h.addTx('D1', c, -800);
      await _stable(h, 'البداية');
      await h.setOnline('D1', false);
      await h.deleteCustomer('D2', c);
      await h.setOnline('D1', true);
    });

    await _scenario(run, 'R4 جهاز آخر لا يستطيع تعديل معاملتي (مرفوض) ولا يتغيّر شيء', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R4'))!;
      final t = (await h.addTx('D1', c, 1200))!;
      await _stable(h, 'البداية');
      try {
        await h.d('D2').call('editTx', {'tx': t, 'amount': 700});
        throw StateError('جهاز آخر عدّل معاملة ليست له — كان يجب أن يُرفض');
      } catch (e) {
        if (!'$e'.contains('أُنشئت على جهاز آخر')) rethrow;
      }
    });

    await _scenario(run, 'R4ب صاحب المعاملة عدّلها والجهاز الآخر غير متصل ثم أُعيد تشغيله', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R4ب'))!;
      final t = (await h.addTx('D1', c, 1200))!;
      await _stable(h, 'البداية');
      await h.setOnline('D2', false);
      await h.editTx('D1', t, 700);
      await h.restart('D2');
      await h.setOnline('D2', true);
    });

    await _scenario(run, 'R5 جهاز آخر استعاد نسخة فيها نسخة قديمة من معاملتي ← لا تمحو تعديلي', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R5'))!;
      final t = (await h.addTx('D1', c, 900))!;
      await _stable(h, 'البداية');
      await h.backup('D2'); // عند D2: المعاملة 900
      await h.editTx('D1', t, 450);
      await _stable(h, 'بعد التعديل');
      if (!await h.restoreBackup('D2')) throw StateError('لم تُستعد النسخة');
    });

    await _scenario(run, 'R6 استعادة نسختين قديمتين على جهازين معاً', 3, (h) async {
      final c1 = (await h.addCustomer('D1', 'زبون R6 أ'))!;
      final c2 = (await h.addCustomer('D2', 'زبون R6 ب'))!;
      await _stable(h, 'البداية');
      await h.backup('D1');
      await h.backup('D2');
      final t1 = (await h.addTx('D1', c1, 2000))!;
      await h.addTx('D2', c2, 3000);
      await h.addTx('D3', c1, -500);
      await _stable(h, 'بعد العمل');
      await h.editTx('D1', t1, 2500);
      await _stable(h, 'بعد التعديل');
      if (!await h.restoreBackup('D1')) throw StateError('لم تُستعد نسخة D1');
      if (!await h.restoreBackup('D2')) throw StateError('لم تُستعد نسخة D2');
    });

    await _scenario(run, 'R7 إعادة تشغيل مفاجئة ومعاملات لم تُرفع بعد (بلا إنترنت) ← تُرفع بعد العودة', 2,
        (h) async {
      final c = (await h.addCustomer('D1', 'زبون R7'))!;
      await _stable(h, 'البداية');
      await h.setOnline('D1', false);
      final t = (await h.addTx('D1', c, 650))!;
      await h.addTx('D1', c, -150);
      await h.editTx('D1', t, 700);
      await h.restart('D1');
      await h.setOnline('D1', true);
    });

    await _scenario(run, 'R8 صاحب المعاملة عدّلها مرتين بلا إنترنت وأُعيد تشغيله، والآخر غير متصل', 3, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R8'))!;
      final t = (await h.addTx('D1', c, 1000))!;
      await _stable(h, 'البداية');
      await h.setOnline('D1', false);
      await h.setOnline('D2', false);
      await h.editTx('D1', t, 200);
      await h.restart('D1');
      await h.editTx('D1', t, 900);
      await h.addTx('D2', c, -100);
      await h.setOnline('D1', true);
      await h.setOnline('D2', true);
    });

    await _scenario(run, 'R9 حذف عميل على جهاز وتسديد له على جهاز غير متصل', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون R9'))!;
      await h.addTx('D1', c, 1000);
      await _stable(h, 'البداية');
      await h.setOnline('D2', false);
      await h.addTx('D2', c, -1000);
      await h.deleteCustomer('D1', c);
      await h.setOnline('D2', true);
    });

    // ═══════════════ سباقات الرفع (كتابة سحابية محجوزة) ═══════════════

    /// ينتظر حتى تُحجز كتابة الجهاز (بدأ رفعها ولم تصل السحابة بعد).
    Future<void> untilHeld(Harness h, String dev) async {
      for (var i = 0; i < 100 && !h.cloud.hasHeld(dev); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!h.cloud.hasHeld(dev)) throw StateError('لم يبدأ رفع $dev');
    }

    await _scenario(run, 'U1 تعديل المعاملة أثناء رفعها ← لا تُعلَّم «مرفوعة» بالنسخة القديمة', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون U1'))!;
      final t = (await h.addTx('D1', c, 500))!;
      await _stable(h, 'البداية');
      h.cloud.holdNextWrite('D1', 'transactions/$t');
      final edit1 = h.editTx('D1', t, 650); // يبدأ الرفع ويُحجز
      await untilHeld(h, 'D1');
      final edit2 = h.editTx('D1', t, 800); // تعديل والرفع الأول معلّق
      await Future<void>.delayed(const Duration(milliseconds: 500));
      h.cloud.releaseHeld('D1');
      await edit1;
      await edit2;
    });

    await _scenario(run, 'U2 «أعد رفع معاملتي» من شاشة المطابقة، ومعه تعديل أثناء الرفع', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون U2'))!;
      final t = (await h.addTx('D1', c, 300))!;
      await _stable(h, 'البداية');
      if (await h.d('D1').call('forceReupload', {'tx': t}) != true) throw StateError('إعادة الرفع فشلت');
      await _stable(h, 'بعد إعادة الرفع');
      h.cloud.holdNextWrite('D1', 'transactions/$t');
      final re = h.d('D1').call('forceReupload', {'tx': t}, const Duration(minutes: 2));
      await untilHeld(h, 'D1');
      final edit = h.editTx('D1', t, 450);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      h.cloud.releaseHeld('D1');
      await re;
      await edit;
    });

    await _scenario(run, 'U3 حُذف العميل على جهاز آخر وصاحب المعاملة عدّلها دون اتصال ← الحذف نهائي', 2,
        (h) async {
      final c = (await h.addCustomer('D1', 'زبون U3'))!;
      final t = (await h.addTx('D1', c, 900))!;
      await _stable(h, 'البداية');
      await h.setOnline('D1', false);
      await h.deleteCustomer('D2', c);
      await h.waitCloudQuiet();
      await h.editTx('D1', t, 950);
      await h.setOnline('D1', true);
    });

    // ═══════════════ الاستعادة من داخل البرنامج وهو يعمل ═══════════════

    await _scenario(run, 'L1 استعادة نسخة من الإعدادات والبرنامج يعمل ← ما حُفظ بعدها يعود من السحابة', 2,
        (h) async {
      final c = (await h.addCustomer('D1', 'زبون L1'))!;
      await h.addTx('D1', c, 1000);
      await _stable(h, 'البداية');
      await h.backup('D1');
      final t = (await h.addTx('D1', c, 2500))!;
      await h.addTx('D2', c, -700);
      await h.editTx('D1', t, 2600);
      await _stable(h, 'بعد العمل');
      if (!await h.liveRestore('D1')) throw StateError('لم تُستعد النسخة');
    });

    await _scenario(run, 'L2 استعادة من الإعدادات ثم عمل جديد فوراً قبل أن يلحق الجهاز', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون L2'))!;
      final t = (await h.addTx('D1', c, 1200))!;
      await _stable(h, 'البداية');
      await h.backup('D1');
      await h.editTx('D1', t, 400);
      await h.saveInvoice('D1', c, 900, 0, 'دين');
      await _stable(h, 'بعد العمل');
      if (!await h.liveRestore('D1')) throw StateError('لم تُستعد النسخة');
      await h.addTx('D1', c, -100); // الجديد مسموح دائماً
    });

    // ═══════════════ الفواتير ═══════════════

    await _scenario(run, 'F1 فاتورة دين عُدّلت ثم استُعيدت نسخة أقدم ← يبقى التعديل', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون F1'))!;
      final inv = (await h.saveInvoice('D1', c, 400, 0, 'دين'))!;
      await _stable(h, 'البداية');
      await h.backup('D1');
      await h.saveInvoice('D1', c, 600, 100, 'دين', inv: inv);
      await _stable(h, 'بعد التعديل');
      if (!await h.restoreBackup('D1')) throw StateError('لم تُستعد النسخة');
    });

    await _scenario(run, 'F2 فاتورة حُفظت بعد النسخة ثم استُعيدت النسخة ← تعود فاتورتي من السحابة', 2,
        (h) async {
      final c = (await h.addCustomer('D1', 'زبون F2'))!;
      await _stable(h, 'البداية');
      await h.backup('D1');
      await h.saveInvoice('D1', c, 750, 250, 'دين');
      await h.saveInvoice('D1', c, 300, 300, 'نقد');
      await _stable(h, 'بعد الرفع');
      if (!await h.restoreBackup('D1')) throw StateError('لم تُستعد النسخة');
    });

    await _scenario(run, 'F3 تصادم رقم تسلسل: فاتورة جديدة بعد استعادة نسخة بلا إنترنت', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون F3'))!;
      await _stable(h, 'البداية');
      await h.backup('D1');
      await h.saveInvoice('D1', c, 500, 0, 'دين'); // رقمها التالي في الشهر
      await _stable(h, 'بعد الرفع');
      await h.setOnline('D1', false);
      if (!await h.restoreBackup('D1')) throw StateError('لم تُستعد النسخة');
      await h.saveInvoice('D1', c, 220, 0, 'دين'); // العدّاد رجع: الرقم نفسه
      await h.setOnline('D1', true);
    });

    await _scenario(run, 'F4 فاتورة جهاز آخر عُدّلت بينما صاحبها غير متصل', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون F4'))!;
      final inv = (await h.saveInvoice('D1', c, 1000, 200, 'دين'))!;
      await _stable(h, 'البداية');
      await h.setOnline('D1', false);
      await h.saveInvoice('D2', c, 1300, 200, 'دين', inv: inv);
      await h.setOnline('D1', true);
    });

    await _scenario(run, 'F5 حذف عميل له فاتورة دين وصاحب الفاتورة غير متصل وعدّلها', 3, (h) async {
      final c = (await h.addCustomer('D1', 'زبون F5'))!;
      final inv = (await h.saveInvoice('D1', c, 800, 0, 'دين'))!;
      await _stable(h, 'البداية');
      await h.setOnline('D1', false);
      await h.deleteCustomer('D2', c);
      await h.saveInvoice('D1', c, 900, 0, 'دين', inv: inv);
      await h.setOnline('D1', true);
    });

    await _scenario(run, 'F6 تحويل فاتورة دين إلى نقد على جهاز وتسديد على جهاز غير متصل', 2, (h) async {
      final c = (await h.addCustomer('D1', 'زبون F6'))!;
      final inv = (await h.saveInvoice('D1', c, 1000, 0, 'دين'))!;
      await _stable(h, 'البداية');
      await h.setOnline('D2', false);
      await h.addTx('D2', c, -300);
      await h.saveInvoice('D1', c, 1000, 1000, 'نقد', inv: inv);
      await h.setOnline('D2', true);
    });

    // ═══════════════ النتيجة ═══════════════
    final total = run.passed + run.failed.length;
    print('\n${run.failed.isEmpty ? '✅ نجح: $total سيناريو نادر، كل الأجهزة متطابقة مع الحقيقة' : '❌ هنا وقع خطأ: ${run.failed.length} من $total — ${run.failed.join('، ')}'}');
    expect(run.failed, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 60)));
}
