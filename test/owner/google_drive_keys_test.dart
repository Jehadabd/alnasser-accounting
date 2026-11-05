// test/owner/google_drive_keys_test.dart
//
// قراءة مفتاحَي Google من ملف JSON الذي تنزّله Google Cloud («Download JSON»).

import 'package:alnaser/owner/google_drive_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ملف Desktop app (installed)', () {
    final k = GoogleDriveService.parseClientJson(
        '{"installed":{"client_id":"123-abc.apps.googleusercontent.com","project_id":"p","client_secret":"GOCSPX-xyz",'
        '"redirect_uris":["http://localhost"]}}');
    expect(k, isNotNull);
    expect(k!.$1, '123-abc.apps.googleusercontent.com');
    expect(k.$2, 'GOCSPX-xyz');
  });

  test('ملف web أو الحقول مباشرة', () {
    expect(GoogleDriveService.parseClientJson('{"web":{"client_id":"9.apps.googleusercontent.com","client_secret":"s"}}')?.$2, 's');
    expect(GoogleDriveService.parseClientJson('{"client_id":"9.apps.googleusercontent.com","client_secret":"s"}')?.$1,
        '9.apps.googleusercontent.com');
  });

  test('نص غير صالح أو مفتاح ناقص ⇒ null', () {
    expect(GoogleDriveService.parseClientJson('{"installed":{"client_id":"x","client_secret":"s"}}'), isNull);
    expect(GoogleDriveService.parseClientJson('{"installed":{"client_id":"9.apps.googleusercontent.com"}}'), isNull);
    expect(GoogleDriveService.parseClientJson('ليس JSON'), isNull);
    expect(GoogleDriveService.parseClientJson('{"instal'), isNull);
  });

  test('الحاجة لإعادة الربط: كان مربوطاً بحساب ثم انتهى', () {
    expect(const DriveStatus(configured: true, signedIn: false, email: 'a@b.c').needsRelink, isTrue);
    expect(const DriveStatus(configured: true, signedIn: true, email: 'a@b.c').needsRelink, isFalse);
    expect(const DriveStatus(configured: true, signedIn: false).needsRelink, isFalse);
  });
}
