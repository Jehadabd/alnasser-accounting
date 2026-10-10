// test/license_v4_test.dart — متجهات مولّدة من سيرفر التراخيص نفسه (Code.gs)
import 'package:flutter_test/flutter_test.dart';
import 'package:alnaser/services/license_v4/ed25519.dart';
import 'package:alnaser/services/license_v4/license_token.dart';

const _vectors = [
  ['2a837e9d7d09be325bc20b178e3764e77f68a1c81a81638f726032d2b62530c5', '', 'cf9de64be005057168c3ff3820f9e09e0059dbd4ca6405078aa094fddaad086e504d2e6bb20126b04b0013086ca26a5264cd4734b78fa8866146f92966e71202'],
  ['3a8623bfd8da27068cbf29fbd47f8998de06f17cead13b8e430cfb9acbf71dd9', 'd8b1d8b3d8a7d984d8a920d8a7d8aed8aad8a8d8a7d8b12078787878787878787878787878', '136e33c295651d831acaaab8f4b8ce00b6251e66dfa7c97013c215733cf0bbc257cb65154177d43377f14271effb4ad0f669aa08501e246fdcf65818d5cda602'],
  ['caa0eb67ed667ee553075e5232ec886b5f71d8399ffd75109705b3f8e11a365c', 'd8b1d8b3d8a7d984d8a920d8a7d8aed8aad8a8d8a7d8b1207878787878787878787878787878787878787878787878787878', '00843a93c6e7f1b353ab39fae51af60d4099a14c653e75638423fedfccfff3d8b289786b173539de2743696c173fb5f3a2f33f96b8923d6fb93a63757c480602'],
  ['b85cc91ba0f06706a322dabf4c6e8c9291d0f240ff4b6b5a65500789e6f60c85', 'd8b1d8b3d8a7d984d8a920d8a7d8aed8aad8a8d8a7d8b120787878787878787878787878787878787878787878787878787878787878787878787878787878', '95eec368cb8adc43669d1b3104e8fcc03d2a58ce6a7f4ed8b285d0c683c77c52362c889f6463b671b71eb93914c2ea546ef14aa67fcbe2b920e616a32cf86101'],
  ['231112ce511685ce68a12c8c4f3d27f28e4b0adf4571010cebef3742e3bc58f7', 'd8b1d8b3d8a7d984d8a920d8a7d8aed8aad8a8d8a7d8b12078787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878', '2b4004834b551dbc4fd8a9121f1b2e3c46835f79f9dc48e58b9357f4f0618e0659e9bf03918cd36f9481a75f898c0c248127240c11145a0d8675af65c83ff904'],
  ['56893a1535aa8cf48c7dc376bfc546ed3760198386640edc460cb38e0c29b95b', '65794a32496a6f304c434a7361574d694f694a7a614739774d534a39', '2bd21ab8e0409b6accff7896f4a8214e47a26333c3f32c00a0f124763e8373c07f839233581462cf3fa9eb9151730399835c71106df478ead143f1a1d393cb08'],
];

const _token = 'eyJ2Ijo0LCJsaWMiOiJzaG9wMSIsImN1cyI6ItmF2K3ZhCDYo9it2YXYryIsImRldiI6IkQ1RDRDMkU1NEQ4ODM3NkZGIiwicm9sZSI6Im1haW4iLCJtb2RlIjoiZnVsbF9zeW5jIiwidHlwZSI6InN1YnNjcmlwdGlvbiIsImV4cCI6MTc5MzkxMjM5OTAwMCwiZ3JjIjoxNzk0MzQ0Mzk5MDAwLCJpYXQiOjE3OTEyODQ5MjgwMjYsImNoayI6MTc5MTM1NjkyODAyNiwib2ZmIjoxNzkxODg5NzI4MDI2LCJmcCI6eyJtZyI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWEiLCJ1dWlkIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYiIsImJiIjoiY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjYyJ9LCJtYXgiOjMsInBoIjoiMDc3MDUyNTI5MDUifQ==.a7pZY6oNlRTibmSnmrl6xKlUw-bd0kVjPIIbi1fj3TrOUMPulpxEfUzHmQG_tWar8X7HriEyjV1Cpl8PoO9gAQ==';
const _tokenPub = '83dd80d64d4164a5b9a27e8917a85f16ac80824c0486c90664b79b2edfcdaff0';

void main() {
  test('Ed25519: server signatures verify', () {
    for (final v in _vectors) {
      expect(Ed25519.verify(Ed25519.hexToBytes(v[2]), Ed25519.hexToBytes(v[1]), Ed25519.hexToBytes(v[0])), isTrue);
    }
  });

  test('Ed25519: tampered signature / message / key rejected', () {
    final v = _vectors[1];
    final sig = Ed25519.hexToBytes(v[2]);
    final msg = Ed25519.hexToBytes(v[1]);
    final pub = Ed25519.hexToBytes(v[0]);
    final badSig = List<int>.from(sig)..[7] ^= 1;
    final badMsg = [...msg, 1];
    final otherPub = Ed25519.hexToBytes(_vectors[2][0]);
    expect(Ed25519.verify(badSig, msg, pub), isFalse);
    expect(Ed25519.verify(sig, badMsg, pub), isFalse);
    expect(Ed25519.verify(sig, msg, otherPub), isFalse);
  });

  test('token from server verifies and decodes', () {
    final p = LicenseToken.verify(_token, publicKeyHex: _tokenPub);
    expect(p, isNotNull);
    expect(p!.account, 'shop1');
    expect(p.mode, 'full_sync');
    expect(p.type, 'subscription');
    expect(p.isMain, isTrue);
    expect(p.customer, 'محل أحمد');
    expect(p.graceUntilMs! - p.expiresMs!, 5 * 24 * 3600 * 1000);
  });

  test('forged token rejected', () {
    final parts = _token.split('.');
    final forgedBody = parts[0].substring(0, parts[0].length - 4) + 'AAAA';
    expect(LicenseToken.verify('$forgedBody.${parts[1]}', publicKeyHex: _tokenPub), isNull);
    expect(LicenseToken.verify(_token, publicKeyHex: _vectors[0][0]), isNull);
  });

  test('fingerprint matching rule', () {
    final a = {'mg': 'A', 'uuid': 'B', 'bb': 'C', 'cpu': 'D'};
    expect(fingerprintMatches(a, {'mg': 'A', 'uuid': 'B', 'bb': 'X', 'cpu': 'Y'}), isTrue);
    expect(fingerprintMatches(a, {'mg': 'A', 'uuid': 'Z', 'bb': 'X', 'cpu': 'Y'}), isFalse);
    expect(fingerprintMatches({'mg': 'A'}, {'mg': 'A'}), isTrue);
    expect(fingerprintMatches({'mg': 'A'}, {'mg': 'B'}), isFalse);
    expect(fingerprintMatches(a, const {}), isFalse);
  });
}
