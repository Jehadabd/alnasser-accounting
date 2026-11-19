// test/services/error_diagnostics_test.dart
//
// 🩺 أداة «تشخيص الأخطاء»: محو الأسرار، تجميع الأخطاء المتشابهة، التقاط أسطر debugPrint،
// قراءة الخروج المفاجئ من native_errors.log، ومطابقة كل خطأ بحلّه، والتقاط الرسائل الحمراء،
// وبوابة «الرفع قبل الإصلاح»، وإصلاح «الرصيد قبل/بعد» بلا مساس بالمبالغ — بكود البرنامج نفسه.
// التشغيل: flutter test test/services/error_diagnostics_test.dart

import 'package:alnaser/services/database/dao/transaction_dao.dart';
import 'package:alnaser/services/diagnostics/error_fixes.dart';
import 'package:alnaser/services/diagnostics/error_journal.dart';
import 'package:alnaser/services/diagnostics/fix_actions.dart';
import 'package:alnaser/services/diagnostics/upload_gate.dart';
import 'package:alnaser/widgets/error_capture_messenger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _fix(String text, {String? source}) => ErrorFixes.match(text, source: source).key;

void main() {
  setUp(ErrorJournal.resetForTest);

  group('محو الأسرار', () {
    test('رموز البوتات والروابط والمفاتيح تُمحى', () {
      const bot = '1234567890:AAH3kfjsdhfkjsdhfkjshdfkjshdfkjsdhfk12';
      final s = ErrorJournal.sanitize(
          'POST https://api.telegram.org/bot$bot/sendDocument failed; access_token=sl.ABCDEFGHIJKLMNOPQRSTUVWXYZ123 '
          'Authorization: Bearer abc.def.ghi key=AIzaSyA1234567890abcdefghijklmnopqrstuv password=hunter2&x=1');
      expect(s, isNot(contains(bot)));
      expect(s, isNot(contains('sl.ABCDEF')));
      expect(s, isNot(contains('AIzaSy')));
      expect(s, isNot(contains('hunter2')));
      expect(s, isNot(contains('abc.def.ghi')));
      expect(s, contains('&x=1'));
    });

    test('النص العادي ومسارات الكود في المكدّس تبقى', () {
      const stack = '#0 FirebaseSyncService._pushCustomers (package:alnaser/services/firebase_sync/firebase_sync_service.dart:2296:11)';
      expect(ErrorJournal.sanitize(stack), stack);
      expect(ErrorJournal.sanitize('فشل رفع عميل محمد أحمد: لا يوجد اتصال'), 'فشل رفع عميل محمد أحمد: لا يوجد اتصال');
    });
  });

  group('التسجيل والتجميع', () {
    test('خطآن يختلفان بالأرقام فقط = مدخل واحد بعددين', () {
      ErrorJournal.recordText(ErrorSource.logged, '❌ فشل رفع الفاتورة 125: SocketException: Connection reset');
      ErrorJournal.recordText(ErrorSource.logged, '❌ فشل رفع الفاتورة 7: SocketException: Connection reset');
      final list = ErrorJournal.entries;
      expect(list, hasLength(1));
      expect(list.first.count, 2);
      expect(list.first.message.startsWith('فشل رفع'), isTrue); // العلامة ❌ أُزيلت
      expect(ErrorJournal.unresolvedCount, 1);
    });

    test('«تم الحل» يعود غير محلول إن تكرّر الخطأ', () {
      ErrorJournal.recordText(ErrorSource.logged, '❌ database is locked');
      final id = ErrorJournal.entries.first.id;
      ErrorJournal.setResolved(id, true);
      expect(ErrorJournal.unresolvedCount, 0);
      ErrorJournal.recordText(ErrorSource.logged, '❌ database is locked');
      expect(ErrorJournal.unresolvedCount, 1);
    });

    test('استثناء مع مكدّس: الرسالة سطرها والتفاصيل المكان والمكدّس', () {
      ErrorJournal.record(
          source: ErrorSource.uncaught, error: StateError('Bad state: No element'), stack: StackTrace.current, context: 'شاشة الفاتورة');
      final e = ErrorJournal.entries.single;
      expect(e.message, contains('No element'));
      expect(e.detail, contains('شاشة الفاتورة'));
    });

    test('ما يُلتقط من debugPrint: ❌ و🔴 دائماً، و⚠️ مع استثناء فقط', () {
      expect(ErrorJournal.looksLikeError('❌ فشلت الاستعادة'), isTrue);
      expect(ErrorJournal.looksLikeError('  🔴 خطأ'), isTrue);
      expect(ErrorJournal.looksLikeError('⚠️ فحص Google Drive: SocketException: Failed host lookup'), isTrue);
      expect(ErrorJournal.looksLikeError('⚠️ رصيد العميل المخزّن ≠ مجموع معاملاته — اعتُمد المجموع'), isFalse);
      expect(ErrorJournal.looksLikeError('✅ تم الحفظ'), isFalse);
    });

    test('السجل لا يتجاوز الحد', () {
      for (var i = 0; i < ErrorJournal.maxEntries + 20; i++) {
        ErrorJournal.recordText(ErrorSource.logged, '❌ خطأ نوع ${String.fromCharCode(0x0627 + (i % 30))}${'ب' * (i ~/ 30)}');
      }
      expect(ErrorJournal.entries.length, lessThanOrEqualTo(ErrorJournal.maxEntries));
    });
  });

  group('الخروج المفاجئ (native_errors.log)', () {
    test('يُقرأ الخروج والعطل الخطير فقط، مجمّعاً', () {
      const log = '''
===== 2026-11-18 20:00:00 start (pid 100) =====

[2026-11-18 20:01:00.120] C++ exception (first chance) code=0xE06D7363 at KERNELBASE.dll+0x1234 thread=5
  stack:
  ...
[2026-11-18 20:05:10.500] FATAL-TYPE exception (first chance) code=0xC0000005 at tdjson.dll+0xabc thread=9
  stack:
  tdjson.dll+0xabc
[2026-11-18 20:05:10.510] UNHANDLED - the app is closing code=0xC0000005 at tdjson.dll+0xabc thread=9
  stack:
  tdjson.dll+0xabc
[2026-11-18 21:00:00.000] UNHANDLED - the app is closing code=0xC0000005 at tdjson.dll+0xabc thread=9
  stack:
''';
      final list = ErrorJournal.parseNative(log);
      expect(list, hasLength(2)); // عطل خطير + خروج (المكرر مُجمّع)، وC++ العادي لا يظهر
      final exit = list.firstWhere((e) => e.message.startsWith('خروج'));
      expect(exit.count, 2);
      expect(exit.last, DateTime(2026, 11, 18, 21));
      expect(ErrorFixes.match(exit.text, source: ErrorSource.native).key, 'crash_tdlib');
    });
  });

  group('دليل الحلول', () {
    test('كل حل له عنوان وخطوات ومفتاح فريد، وكل تعابيره تُبنى', () {
      ErrorFixes.validate();
      final keys = <String>{};
      for (final f in ErrorFixes.all) {
        expect(keys.add(f.key), isTrue, reason: f.key);
        expect(f.title, isNotEmpty);
        expect(f.what, isNotEmpty);
        expect(f.cause, isNotEmpty);
        expect(f.steps, isNotEmpty, reason: f.key);
        expect(f.needles, isNotEmpty, reason: f.key);
        expect(ErrorFixes.categories.any((c) => c.key == f.category), isTrue, reason: f.key);
      }
    });

    test('رسائل حقيقية ⇒ الحل الصحيح', () {
      expect(_fix('DatabaseException(database is locked (code 5 SQLITE_BUSY))'), 'db_locked');
      expect(_fix('DatabaseException(database disk image is malformed)'), 'db_corrupt');
      expect(_fix('DatabaseException(no such column: restored_mark)'), 'db_schema');
      expect(_fix('FileSystemException: Cannot open file, path = C:\\x (OS Error: Access is denied, errno = 5)'), 'disk_access');
      expect(_fix('FileSystemException: writeFrom failed (OS Error: There is not enough space on the disk, errno = 112)'),
          'disk_full');
      expect(_fix('SocketException: Failed host lookup: firestore.googleapis.com (OS Error: No such host is known, errno = 11001)'),
          'net_offline');
      expect(_fix('HandshakeException: Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)'), 'net_tls');
      expect(_fix('TimeoutException after 0:00:30.000000: Future not completed'), 'net_timeout');
      expect(_fix('[cloud_firestore/permission-denied] Missing or insufficient permissions.'), 'fb_rules');
      expect(_fix('رفع تيليجرام فشل: {"ok":false,"error_code":401,"description":"Unauthorized"} telegram'), 'tg_token');
      expect(_fix('Bad Request: chat not found'), 'tg_chat');
      expect(_fix('Too Many Requests: retry after 35'), 'tg_limit');
      expect(_fix('Dropbox: {"error": "invalid_grant"}'), 'dropbox');
      expect(_fix('لا يمكن تعديل هذه المعاملة: رصيد العميل سيصبح -5000 (سالباً). رصيده الحالي 2000.'), 'money_negative');
      expect(_fix('المبلغ أقل من نصف دينار — المبالغ تُحفظ بالدينار الصحيح'), 'money_half');
      expect(_fix('الفترة مثبّتة حتى 2026/10/31 — لا يمكن إضافة أو تعديل أو حذف مستند'), 'money_period');
      expect(_fix('ليس لديك صلاحية تعديل الأسعار (تعديل البضاعة)'), 'perm');
      expect(_fix('A RenderFlex overflowed by 42 pixels on the right.'), 'ui_overflow');
      expect(_fix('setState() called after dispose(): _InvoiceState#1a2b3'), 'ui_disposed');
      expect(_fix('Null check operator used on a null value'), 'code_null');
      expect(_fix('RangeError (index): Invalid value: Not in inclusive range 0..2: 3'), 'code_range');
      expect(_fix("type 'String' is not a subtype of type 'num'"), 'code_type');
      expect(_fix('FormatException: Invalid number (at character 1)'), 'code_format');
    });

    test('ما لا يطابق شيئاً: استثناء تقني ⇒ خلل عام، ونص عادي ⇒ غير معروف', () {
      expect(_fix('FooBarException: something odd'), 'generic_code');
      expect(_fix('حدث شيء غريب'), 'generic_other');
    });

    test('الخروج المفاجئ يُطابَق في قسمه فقط', () {
      expect(_fix('خروج البرنامج — الرمز 0xC0000005 في nvoglv64.dll', source: ErrorSource.native), 'crash_gpu');
      expect(_fix('خروج البرنامج — الرمز 0xC0000005 في debt_book.exe', source: ErrorSource.native), 'crash_generic');
      // رسالة عادية فيها «tdjson» ليست خروجاً مفاجئاً
      expect(_fix('TdError: tdjson not loaded'), 'tdlib');
    });
  });

  group('الرسائل الحمراء للمستخدم', () {
    SnackBar red(String text, {Color? bg = Colors.red, IconData? icon}) => SnackBar(
          backgroundColor: bg,
          content: Row(children: [
            if (icon != null) Icon(icon),
            Expanded(child: Padding(padding: const EdgeInsets.all(4), child: Text(text))),
          ]),
        );

    test('الأحمر أو أيقونة الخطأ = رسالة خطأ، والأخضر لا', () {
      expect(ErrorCaptureMessenger.isError(red('x')), isTrue);
      expect(ErrorCaptureMessenger.isError(red('x', bg: const Color(0xFFB91C1C))), isTrue);
      expect(ErrorCaptureMessenger.isError(red('x', bg: null, icon: Icons.error_outline_rounded)), isTrue);
      expect(ErrorCaptureMessenger.isError(red('x', bg: const Color(0xFF047857))), isFalse);
      expect(ErrorCaptureMessenger.isError(red('x', bg: null)), isFalse);
    });

    test('نص الرسالة يُقرأ من داخل الصفوف والحشوات', () {
      expect(ErrorCaptureMessenger.textOf(red('تعذّر الحفظ', icon: Icons.error).content), 'تعذّر الحفظ');
    });

    test('خطأ البرنامج يُسجَّل، وخطأ الإدخال والصلاحية لا', () {
      ErrorCaptureMessenger.capture(red('تعذّر الحفظ: database is locked'));
      ErrorCaptureMessenger.capture(red('اكتب اسم الزبون'));
      ErrorCaptureMessenger.capture(red('ليس لديك صلاحية لهذه العملية'));
      ErrorCaptureMessenger.capture(red('تم الحفظ', bg: const Color(0xFF047857)));
      final list = ErrorJournal.entries;
      expect(list, hasLength(1));
      expect(list.single.source, ErrorSource.shown);
      expect(ErrorFixes.match(list.single.text, source: list.single.source).key, 'db_locked');
    });
  });

  group('أزرار الإصلاح وبوابة الرفع', () {
    test('كل زر مذكور في دليل الحلول موجود، ولا زر يفتح شاشة ويكتب معاً', () {
      final keys = {for (final a in FixActions.all) a.key};
      expect(keys.length, FixActions.all.length);
      for (final f in [...ErrorFixes.all, ErrorFixes.genericCode, ErrorFixes.genericOther]) {
        for (final k in f.actions) {
          expect(keys.contains(k), isTrue, reason: '${f.key} → $k');
        }
      }
      for (final a in FixActions.all) {
        expect(a.what, isNotEmpty);
        if (a.opens) expect(a.writes, isFalse);
      }
    });

    test('الإصلاح مغلق بلا رفع، ومفتوح بعد رفع ناجح حتى تنتهي المدة', () async {
      UploadGate.setLastOkForTest(null);
      expect(UploadGate.isOpen, isFalse);
      expect(UploadGate.available, isFalse);
      expect(await UploadGate.uploadNow(), isFalse); // لا زر رفع مسجّل ⇒ لا فتح
      expect(UploadGate.isOpen, isFalse);

      Future<bool> fail() async => false;
      UploadGate.register(fail);
      expect(await UploadGate.uploadNow(), isFalse);
      expect(UploadGate.isOpen, isFalse);
      UploadGate.unregister(fail);

      Future<bool> ok() async => true;
      UploadGate.register(ok);
      expect(await UploadGate.uploadNow(), isTrue);
      expect(UploadGate.isOpen, isTrue);
      UploadGate.unregister(ok);
      expect(UploadGate.available, isFalse);

      UploadGate.setLastOkForTest(DateTime.now().subtract(UploadGate.window + const Duration(seconds: 1)));
      expect(UploadGate.isOpen, isFalse);
      UploadGate.setLastOkForTest(null);
    });
  });

  group('إصلاح «الرصيد قبل/بعد»', () {
    sqfliteFfiInit();
    test('الفحص يعدّ بلا كتابة، والإصلاح يصحّح السلسلة ولا يغيّر أي مبلغ', () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, customer_id INTEGER, amount_changed REAL, '
          'balance_before_transaction REAL, new_balance_after_transaction REAL, transaction_date TEXT, is_deleted INTEGER)');
      // ترتيب الكشف بالتاريخ: 3 (أكتوبر) ثم 1 ثم 2 — والمخزّن محسوب بالترتيب القديم 1، 2، 3
      Future<void> tx(int id, double amount, String date, double before, {int deleted = 0}) => db.insert('transactions', {
            'id': id,
            'customer_id': 7,
            'amount_changed': amount,
            'balance_before_transaction': before,
            'new_balance_after_transaction': before + amount,
            'transaction_date': date,
            'is_deleted': deleted,
          });
      await tx(1, 5000, '2026-11-01T10:00:00', 0);
      await tx(2, -2000, '2026-11-02T10:00:00', 5000);
      await tx(3, 10000, '2026-10-01T10:00:00', 3000);
      await tx(4, 99999, '2026-09-01T10:00:00', 0, deleted: 1); // محذوفة: خارج الكشف
      final amountsBefore = await db.rawQuery('SELECT id, amount_changed FROM transactions ORDER BY id');

      expect(await TransactionDao.rechainIn(db, 7, dryRun: true), 3);
      expect(await TransactionDao.rechainIn(db, 7, dryRun: true), 3); // الفحص لم يكتب شيئاً
      expect(await TransactionDao.rechainIn(db, 7), 3);
      expect(await TransactionDao.rechainIn(db, 7, dryRun: true), 0);

      final rows = {for (final r in await db.query('transactions')) r['id']: r};
      expect(rows[3]!['balance_before_transaction'], 0);
      expect(rows[3]!['new_balance_after_transaction'], 10000);
      expect(rows[1]!['balance_before_transaction'], 10000);
      expect(rows[2]!['new_balance_after_transaction'], 13000);
      expect(rows[4]!['balance_before_transaction'], 0); // المحذوفة لم تُلمس
      expect(await db.rawQuery('SELECT id, amount_changed FROM transactions ORDER BY id'), amountsBefore);
      await db.close();
    });
  });
}
