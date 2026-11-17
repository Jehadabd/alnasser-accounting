// اختبارات MTProto الصافية (بلا TDLib ولا شبكة).
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/simplex/simplex_engine.dart' show SimplexException;
import 'package:alnaser/services/telegram_net/tdlib_client.dart';
import 'package:alnaser/services/telegram_net/tdlib_engine.dart';
import 'package:alnaser/services/telegram_net/telegram_mtproto.dart';

void main() {
  group('روابط البروكسي → TDLib', () {
    test('MTProto من القنوات', () {
      final j = TelegramMtproto.proxyJson('tg://proxy?server=1.2.3.4&port=443&secret=ee1234abcd')!;
      expect(j, {
        '@type': 'proxy',
        'server': '1.2.3.4',
        'port': 443,
        'type': {'@type': 'proxyTypeMtproto', 'secret': 'ee1234abcd'},
      });
      expect(TelegramMtproto.proxyJson('https://t.me/proxy?server=a.b&port=8443&secret=dd00')!['server'], 'a.b');
      expect(TelegramMtproto.proxyLabel('tg://proxy?server=a.b&port=8443&secret=dd00'), 'MTProto a.b:8443');
    });

    test('SOCKS5 من القنوات', () {
      final j = TelegramMtproto.proxyJson('tg://socks?server=5.6.7.8&port=1080&user=u&pass=p')!;
      expect(j['type'], {'@type': 'proxyTypeSocks5', 'username': 'u', 'password': 'p'});
    });

    test('روابط ناقصة أو غريبة تُرفض', () {
      expect(TelegramMtproto.proxyJson('tg://proxy?server=1.2.3.4&port=443'), isNull); // بلا secret
      expect(TelegramMtproto.proxyJson('tg://proxy?server=&port=443&secret=aa'), isNull);
      expect(TelegramMtproto.proxyJson('tg://proxy?server=x&port=70000&secret=aa'), isNull);
      expect(TelegramMtproto.proxyJson('https://example.com/proxy?server=x&port=1&secret=aa'), isNull);
      expect(TelegramMtproto.proxyJson('tg://resolve?domain=x'), isNull);
    });
  });

  test('معرّف قناة Bot API → supergroup في TDLib', () {
    expect(TdlibClient.supergroupIdOf(-1001234567890), 1234567890);
    expect(TdlibClient.supergroupIdOf(-123456), isNull); // مجموعة عادية
    expect(TdlibClient.supergroupIdOf(42), isNull);
  });

  test('رسائل الأخطاء بالعربية', () {
    expect(TelegramMtproto.describe(TdError(401, 'ACCESS_TOKEN_INVALID')), 'توكن البوت غير صحيح');
    expect(TelegramMtproto.describe(TdError(403, 'CHAT_WRITE_FORBIDDEN')), contains('مشرفاً'));
    expect(TelegramMtproto.describe(TdError(0, 'انتهت المهلة')), 'انتهت المهلة');
  });

  test('بلا dart-define ولا .env: لا بيانات تطبيق (الميزة لا تعمل بصمت)', () {
    expect(TelegramMtproto.hasCredentials, isFalse);
  });

  group('استخراج ملفات TDLib من الحزمة', () {
    List<int> zip(Map<String, List<int>> files) {
      final a = Archive();
      files.forEach((n, b) => a.addFile(ArchiveFile(n, b.length, b)));
      return ZipEncoder().encode(a)!;
    }

    test('الأربعة من runtimes/win-x64 فقط', () {
      final bytes = zip({
        for (final d in TdlibEngine.dlls) 'runtimes/win-x64/native/$d': [1, 2, d.length],
        'runtimes/win-arm64/native/tdjson.dll': [9],
        'lib/other.dll': [7],
      });
      final out = TdlibEngine.extractDlls(bytes);
      expect(out.keys.toSet(), TdlibEngine.dlls.toSet());
      expect(out['tdjson.dll'], [1, 2, 'tdjson.dll'.length]);
    });

    test('حزمة ناقصة ⇒ خطأ واضح', () {
      final bytes = zip({'runtimes/win-x64/native/tdjson.dll': [1]});
      expect(() => TdlibEngine.extractDlls(bytes), throwsA(isA<SimplexException>()));
    });
  });
}
