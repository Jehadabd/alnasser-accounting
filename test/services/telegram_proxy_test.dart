// اختبارات بروكسي تيليجرام (بلا شبكة): قراءة الروابط، القواعد، ومصافحة SOCKS5 على بايتات وهمية.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/telegram_net/telegram_proxy.dart';

/// طرف SOCKS5 وهمي: يعطي ردوداً جاهزة ويسجّل ما كُتب.
class _Fake {
  _Fake(List<int> replies) : _in = List.of(replies);
  final List<int> _in;
  final written = <List<int>>[];
  Future<List<int>> read(int n) async {
    if (_in.length < n) throw const SocketException('انتهت البيانات');
    final out = _in.sublist(0, n);
    _in.removeRange(0, n);
    return out;
  }

  void write(List<int> b) => written.add(b);
}

void main() {
  group('قراءة روابط البروكسي', () {
    test('رابط قنوات تيليجرام tg://socks مع مستخدم', () {
      final c = TelegramProxy.parse('tg://socks?server=1.2.3.4&port=1080&user=ali&pass=p%40ss')!;
      expect((c.type, c.host, c.port, c.user, c.pass), (TgProxyType.socks5, '1.2.3.4', 1080, 'ali', 'p@ss'));
    });

    test('https://t.me/socks بلا مستخدم', () {
      final c = TelegramProxy.parse('https://t.me/socks?server=proxy.example.com&port=443')!;
      expect((c.host, c.port, c.hasAuth), ('proxy.example.com', 443, false));
    });

    test('socks5:// و http:// وعنوان:منفذ', () {
      final a = TelegramProxy.parse('socks5://u:p:q@10.0.0.1:9050')!;
      expect((a.type, a.user, a.pass), (TgProxyType.socks5, 'u', 'p:q'));
      expect(TelegramProxy.parse('http://127.0.0.1:10809')!.type, TgProxyType.http);
      final c = TelegramProxy.parse('127.0.0.1:10808', fallback: TgProxyType.http)!;
      expect((c.type, c.port), (TgProxyType.http, 10808));
      expect(TelegramProxy.parse('localhost:10808')!.host, 'localhost');
    });

    test('روابط غير صالحة وروابط MTProto لا تُقرأ كـ SOCKS', () {
      expect(TelegramProxy.parse(''), isNull);
      expect(TelegramProxy.parse('127.0.0.1:99999'), isNull);
      expect(TelegramProxy.parse('ftp://a:21'), isNull);
      const mt = 'tg://proxy?server=1.2.3.4&port=443&secret=ee00';
      expect(TelegramProxy.parse(mt), isNull);
      expect(TelegramProxy.isMtprotoLink(mt), isTrue);
      expect(TelegramProxy.isMtprotoLink('https://t.me/proxy?server=a&port=1&secret=dd'), isTrue);
      expect(TelegramProxy.isMtprotoLink('tg://socks?server=a&port=1'), isFalse);
    });
  });

  test('الجسر يقبل تيليجرام على 443 فقط', () {
    expect(telegramTargetAllowed('api.telegram.org', 443), isTrue);
    expect(telegramTargetAllowed('API.Telegram.org', 443), isTrue);
    expect(telegramTargetAllowed('api.telegram.org', 80), isFalse);
    expect(telegramTargetAllowed('telegram.org.evil.com', 443), isFalse);
    expect(telegramTargetAllowed('google.com', 443), isFalse);
  });

  group('مصافحة SOCKS5', () {
    test('بلا مستخدم: CONNECT باسم الخادم', () async {
      final f = _Fake([5, 0, 5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      await socks5Connect(f.read, f.write, 'api.telegram.org', 443);
      expect(f.written[0], [5, 1, 0]);
      final req = f.written[1];
      expect(req.sublist(0, 5), [5, 1, 0, 3, 16]);
      expect(String.fromCharCodes(req.sublist(5, 21)), 'api.telegram.org');
      expect(req.sublist(21), [1, 187]); // 443
    });

    test('باسم مستخدم وكلمة سر', () async {
      final f = _Fake([5, 2, 1, 0, 5, 0, 0, 3, 3, 97, 98, 99, 0, 80]);
      await socks5Connect(f.read, f.write, 'api.telegram.org', 443, user: 'u', pass: 'pw');
      expect(f.written[0], [5, 2, 0, 2]);
      expect(f.written[1], [1, 1, 117, 2, 112, 119]);
    });

    test('رفض البروكسي يُشرح بالعربية', () async {
      final f = _Fake([5, 0, 5, 2, 0, 1, 0, 0, 0, 0, 0, 0]);
      expect(() => socks5Connect(f.read, f.write, 'api.telegram.org', 443),
          throwsA(isA<SocketException>().having((e) => e.message, 'm', contains('يمنع'))));
    });

    test('بروكسي يطلب كلمة سر ولم نُعطه', () async {
      final f = _Fake([5, 2]);
      expect(() => socks5Connect(f.read, f.write, 'api.telegram.org', 443),
          throwsA(isA<SocketException>().having((e) => e.message, 'm', contains('كلمة سر'))));
    });
  });
}
