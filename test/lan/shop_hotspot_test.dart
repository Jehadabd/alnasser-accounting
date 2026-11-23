import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/lan/shop_hotspot.dart';

void main() {
  test('رمز شبكة المتجر: ذهاب وعودة', () {
    const n = ShopNet(ssid: 'متجر الناصر', password: 'AB12cd34!', host: '192.168.137.1', port: 47800, secret: 'K7Q2');
    final back = ShopNet.parse(n.toCode())!;
    expect(back.ssid, n.ssid);
    expect(back.password, n.password);
    expect(back.host, n.host);
    expect(back.port, n.port);
    expect(back.secret, n.secret);
  });

  test('نص غريب ليس رمز شبكة', () {
    expect(ShopNet.parse('WIFI:S:x;T:WPA;P:y;;'), isNull);
    expect(ShopNet.parse('ALNASER-NET:@@@'), isNull);
    expect(ShopNet.parse(null), isNull);
  });
}
