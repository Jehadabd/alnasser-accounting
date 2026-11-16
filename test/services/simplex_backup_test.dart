// اختبارات أدوات SimpleX الصافية (بلا محرك ولا شبكة).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/simplex/simplex_backup_service.dart';
import 'package:alnaser/services/simplex/simplex_client.dart';
import 'package:alnaser/services/simplex/simplex_engine.dart';
import 'package:alnaser/services/simplex/simplex_socks.dart';
import 'package:alnaser/services/simplex/upload_route.dart';

void main() {
  group('أمر الإرسال', () {
    test('نص فقط: /_send @id json [ComposedMessage]', () {
      final c = SimplexBackupService.sendCommand(7, text: 'مرحبا');
      expect(c.startsWith('/_send @7 json '), isTrue);
      final j = jsonDecode(c.substring('/_send @7 json '.length)) as List;
      expect(j.single['msgContent'], {'type': 'text', 'text': 'مرحبا'});
      expect(j.single.containsKey('fileSource'), isFalse);
      expect(j.single['mentions'], isEmpty);
    });

    test('ملف مع تعليق: النوع file ومسار الملف', () {
      final c = SimplexBackupService.sendCommand(3, text: 'قاعدة', filePath: r'C:\a b\x.xz');
      final j = jsonDecode(c.substring('/_send @3 json '.length)) as List;
      expect(j.single['msgContent'], {'type': 'file', 'text': 'قاعدة'});
      expect(j.single['fileSource'], {'filePath': r'C:\a b\x.xz'});
    });
  });

  test('رقم الملف من ردّ newChatItems', () {
    final r = {
      'type': 'newChatItems',
      'chatItems': [
        {
          'chatInfo': {'type': 'direct'},
          'chatItem': {
            'file': {'fileId': 42, 'fileName': 'x'}
          }
        }
      ]
    };
    expect(SimplexBackupService.fileIdOf(r), 42);
    expect(SimplexBackupService.fileIdOf({'type': 'newChatItems', 'chatItems': []}), isNull);
  });

  test('HTML تيليجرام → تنسيق SimpleX', () {
    expect(SimplexBackupService.htmlToSimplex('💵 <b>المبيعات:</b> 5 &amp; 6'), '💵 *المبيعات:* 5 & 6');
    expect(SimplexBackupService.htmlToSimplex('<i>x</i><br/><code>y</code>'), '_x_\n`y`');
    expect(SimplexBackupService.htmlToSimplex('a < b'), 'a < b'); // ليست وسماً
  });

  test('تقسيم الرسائل الطويلة على الأسطر بلا فقدان', () {
    final lines = List.generate(500, (i) => 'سطر رقم $i ' * 5);
    final text = lines.join('\n');
    final parts = SimplexBackupService.splitText(text, max: 2000);
    expect(parts.length, greaterThan(1));
    expect(parts.every((p) => p.length <= 2000), isTrue);
    expect(parts.join('\n'), text);
  });

  test('اسم ملف آمن على Windows', () {
    expect(SimplexBackupService.safeName('كشف:حساب?.pdf'), 'كشف_حساب_.pdf');
    expect(SimplexBackupService.safeName('   '), 'file');
  });

  test('بصمة الملف من وصف الإصدار', () {
    const body = 'notes\nSHA2-256(simplex-chat-windows-x86-64)= ${'ab' * 32}\nSHA2-256(other)= ${'cd' * 32}';
    expect(SimplexEngine.hashFromReleaseBody(body, 'simplex-chat-windows-x86-64'), 'ab' * 32);
    expect(SimplexEngine.hashFromReleaseBody('none', 'simplex-chat-windows-x86-64'), isNull);
  });

  test('مسار الرفع: SimpleX داخل runSimplex فقط، ولكل مسار سجله', () async {
    expect(UploadRoute.isSimplex, isFalse);
    expect(UploadRoute.sentTable, 'telegram_sent');
    final inside = await UploadRoute.runSimplex(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5)); // يبقى بعد await
      return (UploadRoute.isSimplex, UploadRoute.sentTable, UploadRoute.lastUploadKey);
    });
    expect(inside, (true, 'simplex_sent', 'simplex_last_upload_time'));
    expect(UploadRoute.isSimplex, isFalse);
    expect(UploadRoute.lastUploadKey, 'telegram_last_upload_time');
  });

  test('خطأ BROKER يُشرح باسم الخادم ونوعه (لا كلمة BROKER وحدها)', () {
    final e = {
      'type': 'errorAgent',
      'agentError': {
        'type': 'BROKER',
        'brokerAddress': 'smp://abc123=@smp8.simplex.im,xyz.onion',
        'brokerErr': {'type': 'TIMEOUT'}
      }
    };
    final d = SimplexClient.describeError(e);
    expect(d, contains('smp8.simplex.im'));
    expect(d, contains('انتهت المهلة'));
    expect(d, isNot(contains('abc123')));
    expect(SimplexClient.isTransient(Exception('SimpleX: $d')), isTrue);
  });

  group('وسيط DNS', () {
    test('عنوان حقيقي من جواب DoH، والجواب المزيّف 0.0.0.0 يُرفض', () {
      const real = '{"Status":0,"Answer":[{"name":"smp4.simplex.im","type":1,"data":"172.236.220.91"}]}';
      const fake = '{"Status":0,"Answer":[{"name":"smp4.simplex.im","type":1,"data":"0.0.0.0"}]}';
      const cname = '{"Answer":[{"type":5,"data":"x.example."},{"type":1,"data":"1.2.3.4"}]}';
      expect(SimplexDns.ipFromDohJson(real), '172.236.220.91');
      expect(SimplexDns.ipFromDohJson(fake), isNull);
      expect(SimplexDns.ipFromDohJson(cname), '1.2.3.4');
      expect(SimplexDns.ipFromDohJson('{"Status":3}'), isNull);
    });

    test('أسماء الخوادم فقط (لا حقن في رابط DoH)', () {
      expect(SimplexDns.validHost('smp4.simplex.im'), isTrue);
      expect(SimplexDns.validHost('a&type=TXT'), isFalse);
      expect(SimplexDns.validHost('-bad.com'), isFalse);
    });

    test('الوسيط يقبل منافذ SimpleX فقط', () {
      expect(SimplexSocks.allowedPorts, {443, 5223});
    });
  });
}
