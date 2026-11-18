// test/widgets/dropbox_troubleshoot_test.dart
//
// 🩺 حل مشاكل Dropbox: التعرّف على المشكلة من رسالة الخطأ أو رابط صفحة الخطأ.
// التشغيل: flutter test test/widgets/dropbox_troubleshoot_test.dart

import 'package:alnaser/services/dropbox_backup_service.dart';
import 'package:alnaser/widgets/dropbox_troubleshoot.dart';
import 'package:flutter_test/flutter_test.dart';

String? _k(String t) => DropboxTroubleshoot.match(t, appKey: 'abc12345', appName: 'test')?.key;

void main() {
  test('رابط صفحة «user limit» من شريط العنوان ⇒ مشكلة حد المستخدمين', () {
    const url = 'https://www.dropbox.com/oauth2/authorize_error?client_id=3qcpvyen8wn3cvp'
        '&error_name=check_add_user_increase_limit';
    expect(DropboxTroubleshoot.isErrorPage(url), isTrue);
    expect(_k(url), 'user_limit');
    expect(_k('This app has reached its user limit. Contact the app developer'), 'user_limit');
  });

  test('الكود أو رابط الإعادة بالكود ليس صفحة خطأ', () {
    expect(DropboxTroubleshoot.isErrorPage('sl.AbCdEf123456'), isFalse);
    expect(DropboxTroubleshoot.isErrorPage('http://localhost/?code=abc123&state=x'), isFalse);
  });

  test('رسائل البرنامج وردود Dropbox ⇒ المشكلة الصحيحة', () {
    expect(_k('{"error": "invalid_grant", "error_description": "code doesn\'t exist or has expired"}'), 'code');
    expect(_k('{"error": "invalid_client: Invalid client_id or client_secret"}'), 'bad_app');
    expect(_k('ينقص تطبيق Dropbox إذن files.content.write'), 'scope');
    expect(_k('انتهت صلاحية الاتصال بـ Dropbox — سجّل الدخول من جديد.'), 'expired');
    expect(_k('انقطع الاتصال بـ Dropbox أثناء الرفع (Connection reset)'), 'network');
    expect(_k('المساحة في Dropbox لا تكفي حتى بعد حذف النسخ القديمة'), 'space');
    expect(_k('هذه النسخة من برنامج أحدث أو برنامج آخر'), 'restore');
    expect(_k('رسالة لا علاقة لها'), isNull);
    expect(_k(''), isNull);
  });

  test('الرفع متوقف بلا تطبيق خاص ⇒ مشكلة «لا يوجد تطبيق»، ومفاتيح المطوّر مرفوضة', () {
    expect(_k('الرفع متوقف: أنشئ تطبيق Dropbox خاصاً بمحلك واربطه'), 'no_app');
    expect(_k('هذا مفتاح تطبيق المطوّر ولا يُقبل'), 'no_app');
    expect(DropboxBackupService.isDeveloperKey('3qcpvyen8wn3cvp'), isTrue);
    expect(DropboxBackupService.isDeveloperKey(' yklmvnhmfsz65yh '), isTrue);
    expect(DropboxBackupService.isDeveloperKey('a1b2c3d4e5f6g7h'), isFalse);
  });

  test('كل مشكلة لها عنوان وخطوات', () {
    final list = DropboxTroubleshoot.problems(appKey: 'abc12345', appName: 'test');
    expect(list.map((p) => p.key).toSet().length, list.length);
    for (final p in list) {
      expect(p.title, isNotEmpty);
      expect(p.steps, isNotEmpty);
    }
  });
}
