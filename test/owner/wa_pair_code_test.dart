// test/owner/wa_pair_code_test.dart — رمز ربط الهاتف بخادم الحاسبة
import 'package:alnaser/owner/wa_auto/wa_pair_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const key = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefgh';

  test('ترميز ثم فك يعيد الرابط والمفتاح', () {
    final c = WaPairCode('http://192.168.1.5:8765', key).encode();
    expect(c.startsWith('ALNWA1:'), isTrue);
    expect(c.contains('='), isFalse);
    final d = WaPairCode.decode('  $c\n');
    expect(d?.url, 'http://192.168.1.5:8765');
    expect(d?.key, key);
  });

  test('يرفض غير الشبكة المحلية والمفتاح القصير والنص العشوائي', () {
    expect(WaPairCode.decode(WaPairCode('http://8.8.8.8:8765', key).encode()), isNull);
    expect(WaPairCode.decode(WaPairCode('https://192.168.1.5:8765', key).encode()), isNull);
    expect(WaPairCode.decode(WaPairCode('http://192.168.1.5:8765', 'short').encode()), isNull);
    expect(WaPairCode.decode('http://192.168.1.5:8765'), isNull);
    expect(WaPairCode.decode('ALNWA1:@@@'), isNull);
    expect(WaPairCode.decode(null), isNull);
  });

  test('عناوين الشبكة الخاصة', () {
    expect(WaPairCode.isPrivateHost('10.0.0.7'), isTrue);
    expect(WaPairCode.isPrivateHost('172.20.1.1'), isTrue);
    expect(WaPairCode.isPrivateHost('172.32.1.1'), isFalse);
    expect(WaPairCode.isPrivateHost('192.169.1.1'), isFalse);
  });
}
