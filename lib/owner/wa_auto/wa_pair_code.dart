// lib/owner/wa_auto/wa_pair_code.dart
//
// 🔗 «رمز ربط الهاتف بخادم الحاسبة»: رابط خادم الحاسبة على الشبكة المحلية + مفتاحه، في نص
// واحد يُعرض رمز QR على الحاسبة ويُمسح بكاميرا الهاتف (أو يُلصق).
//   ALNWA1:<base64url( {"u":"http://192.168.1.5:8765","k":"<المفتاح>"} )>
// المفتاح سرّ: من يملك الرمز ويكون على شبكة المحل يستطيع الإرسال من رقم المحل.

import 'dart:convert';

class WaPairCode {
  const WaPairCode(this.url, this.key);
  final String url, key;

  static const _prefix = 'ALNWA1:';

  String encode() =>
      _prefix + base64Url.encode(utf8.encode(jsonEncode({'u': url, 'k': key}))).replaceAll('=', '');

  /// يقبل الرمز كما هو (بمسافات أو أسطر زائدة). null = ليس رمز ربط صالحاً.
  static WaPairCode? decode(String? raw) {
    final t = (raw ?? '').replaceAll(RegExp(r'\s'), '');
    if (!t.startsWith(_prefix)) return null;
    try {
      var b = t.substring(_prefix.length);
      while (b.length % 4 != 0) {
        b += '=';
      }
      final j = jsonDecode(utf8.decode(base64Url.decode(b)));
      if (j is! Map) return null;
      final u = '${j['u'] ?? ''}'.trim();
      final k = '${j['k'] ?? ''}'.trim();
      final uri = Uri.tryParse(u);
      if (uri == null || uri.scheme != 'http' || uri.host.isEmpty || !uri.hasPort) return null;
      if (!isPrivateHost(uri.host)) return null; // الشبكة المحلية فقط
      if (k.length < 24) return null;
      return WaPairCode(u, k);
    } catch (_) {
      return null;
    }
  }

  /// عنوان شبكة محلية خاصة (192.168.x / 10.x / 172.16-31.x).
  static bool isPrivateHost(String h) =>
      h.startsWith('192.168.') || h.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h);
}
