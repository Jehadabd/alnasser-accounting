// اختبارات الأجزاء الصافية من التشغيل الآلي لخادم واتساب (بلا شبكة ولا Windows).
import 'package:alnaser/owner/wa_auto/wa_local_server.dart';
import 'package:alnaser/owner/wa_auto/wa_render_deployer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('بصمة Node.js من SHASUMS256.txt', () {
    const h1 = '1111111111111111111111111111111111111111111111111111111111111111';
    const h2 = 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd';
    const sums = '$h1  node-v20.18.1-win-arm64.zip\n'
        '$h2  node-v20.18.1-win-x64.zip\r\n'
        '$h1  node-v20.18.1-win-x64.7z\n';

    test('يأخذ سطر الملف المطلوب بالضبط', () {
      expect(WaLocalServer.hashFor(sums, 'node-v20.18.1-win-x64.zip'), h2);
    });

    test('ملف غير موجود ⇒ null (فلا تنزيل بلا بصمة)', () {
      expect(WaLocalServer.hashFor(sums, 'node-v20.18.1-win-x86.zip'), isNull);
    });

    test('بصمة مشوّهة ⇒ null', () {
      expect(WaLocalServer.hashFor('xyz  node-v20.18.1-win-x64.zip', 'node-v20.18.1-win-x64.zip'), isNull);
      expect(WaLocalServer.hashFor('', 'node-v20.18.1-win-x64.zip'), isNull);
    });
  });

  test('رابط الخادم المحلي', () {
    expect(WaLocalServer.isLocalUrl('http://127.0.0.1:8765'), isTrue);
    expect(WaLocalServer.isLocalUrl('http://localhost:8765'), isTrue);
    expect(WaLocalServer.isLocalUrl('http://127.0.0.1:8080'), isFalse); // الطريقة اليدوية
    expect(WaLocalServer.isLocalUrl('https://alnaser-wa.onrender.com'), isFalse);
  });

  group('رسائل Render', () {
    test('مفتاح خاطئ', () {
      expect(WaRenderDeployer.errorText(401, 'unauthorized'), contains('مفتاح Render غير صحيح'));
    });
    test('طلب بطاقة', () {
      expect(WaRenderDeployer.errorText(402, ''), contains('بطاقة'));
      expect(WaRenderDeployer.errorText(400, 'A credit card is required'), contains('بطاقة'));
    });
    test('صورة لا تُجلب', () {
      expect(WaRenderDeployer.errorText(400, 'image not found'), contains('Public'));
    });
    test('غير ذلك: الرمز والرسالة كما هما', () {
      final t = WaRenderDeployer.errorText(500, 'boom');
      expect(t, contains('500'));
      expect(t, contains('boom'));
    });
    test('حالات النشر', () {
      expect(WaRenderDeployer.statusText('live'), 'يعمل');
      expect(WaRenderDeployer.statusText('build_in_progress'), 'يجلب صورة الخادم');
      expect(WaRenderDeployer.statusText('weird'), 'weird');
    });
  });
}
