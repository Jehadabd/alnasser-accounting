// lib/services/license_v4/ed25519.dart
//
// 🔏 التحقق من توقيع Ed25519 (RFC 8032) — بلا مكتبات خارجية (BigInt + sha512).
//
// سيرفر التراخيص يوقّع ترخيص كل جهاز بمفتاحه الخاص (لا يخرج من Google أبداً).
// البرنامج يحمل المفتاح العام فقط: يستطيع التحقق، ولا يستطيع أحد صنع توقيع.
// أي تعديل على الترخيص (النمط، التاريخ، الجهاز) يُفسد التوقيع فيُرفض.
//
// الاختبار: test/license_v4_test.dart (متجهات مولّدة من السيرفر نفسه).

import 'package:crypto/crypto.dart' as crypto;

class Ed25519 {
  Ed25519._();

  static final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _l =
      (BigInt.one << 252) + BigInt.parse('27742317777372353535851937790883648493');
  static final BigInt _d = _mod(BigInt.from(-121665) * BigInt.from(121666).modInverse(_p));
  static final BigInt _d2 = _mod(_d * BigInt.two);
  static final BigInt _sqrtM1 = BigInt.two.modPow((_p - BigInt.one) ~/ BigInt.from(4), _p);
  static final BigInt _gy = _mod(BigInt.from(4) * BigInt.from(5).modInverse(_p));
  static final List<BigInt> _g = _basePoint();
  static final List<BigInt> _zero = [BigInt.zero, BigInt.one, BigInt.one, BigInt.zero];

  // باقي القسمة في Dart موجب دائماً مع مقسوم عليه موجب
  static BigInt _mod(BigInt a, [BigInt? m]) => a % (m ?? _p);

  static List<BigInt> _basePoint() {
    final x = _recoverX(_gy, 0)!;
    return [x, _gy, BigInt.one, _mod(x * _gy)];
  }

  static BigInt? _recoverX(BigInt y, int sign) {
    if (y >= _p) return null;
    final x2 = _mod((y * y - BigInt.one) * (_d * y * y + BigInt.one).modInverse(_p));
    if (x2 == BigInt.zero) return sign == 1 ? null : BigInt.zero;
    var x = x2.modPow((_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
    if (_mod(x * x - x2) != BigInt.zero) x = _mod(x * _sqrtM1);
    if (_mod(x * x - x2) != BigInt.zero) return null;
    if ((x & BigInt.one).toInt() != sign) x = _p - x;
    return x;
  }

  static List<BigInt> _add(List<BigInt> p, List<BigInt> q) {
    final a = _mod((p[1] - p[0]) * (q[1] - q[0]));
    final b = _mod((p[1] + p[0]) * (q[1] + q[0]));
    final c = _mod(p[3] * _d2 * q[3]);
    final d = _mod(p[2] * BigInt.two * q[2]);
    final e = b - a, f = d - c, g = d + c, h = b + a;
    return [_mod(e * f), _mod(g * h), _mod(f * g), _mod(e * h)];
  }

  static List<BigInt> _mul(BigInt s, List<BigInt> p) {
    var q = _zero;
    while (s > BigInt.zero) {
      if ((s & BigInt.one) == BigInt.one) q = _add(q, p);
      p = _add(p, p);
      s = s >> 1;
    }
    return q;
  }

  static bool _equal(List<BigInt> p, List<BigInt> q) =>
      _mod(p[0] * q[2] - q[0] * p[2]) == BigInt.zero && _mod(p[1] * q[2] - q[1] * p[2]) == BigInt.zero;

  static BigInt _numLE(List<int> b) {
    var n = BigInt.zero;
    for (var i = b.length - 1; i >= 0; i--) {
      n = (n << 8) + BigInt.from(b[i] & 0xff);
    }
    return n;
  }

  static List<BigInt>? _decode(List<int> b) {
    if (b.length != 32) return null;
    final c = List<int>.from(b);
    final sign = (c[31] >> 7) & 1;
    c[31] &= 127;
    final y = _numLE(c);
    final x = _recoverX(y, sign);
    if (x == null) return null;
    return [x, y, BigInt.one, _mod(x * y)];
  }

  /// صحيح فقط إن كان [signature] توقيعاً للرسالة [message] بالمفتاح المقابل لـ [publicKey].
  static bool verify(List<int> signature, List<int> message, List<int> publicKey) {
    try {
      if (signature.length != 64 || publicKey.length != 32) return false;
      final a = _decode(publicKey);
      final r = _decode(signature.sublist(0, 32));
      if (a == null || r == null) return false;
      final s = _numLE(signature.sublist(32, 64));
      if (s >= _l) return false;
      final h = crypto.sha512.convert([...signature.sublist(0, 32), ...publicKey, ...message]).bytes;
      final k = _mod(_numLE(h), _l);
      return _equal(_mul(s, _g), _add(r, _mul(k, a)));
    } catch (_) {
      return false;
    }
  }

  static List<int> hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
