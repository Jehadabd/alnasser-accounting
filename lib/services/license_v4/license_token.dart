// lib/services/license_v4/license_token.dart
//
// 🎫 الترخيص الموقَّع: «محتوى.توقيع» (base64url). التوقيع Ed25519 على نص
// المحتوى نفسه؛ لا يُقبل أي ترخيص لم يوقّعه سيرفرنا.

import 'dart:convert';

import 'ed25519.dart';
import 'license_config.dart';

class LicensePayload {
  LicensePayload(this.raw);

  final Map<String, dynamic> raw;

  int get version => _int(raw['v']);
  String get account => '${raw['lic'] ?? ''}';
  String get customer => '${raw['cus'] ?? ''}';
  String get deviceId => '${raw['dev'] ?? ''}';
  String get role => '${raw['role'] ?? ''}';
  String get mode => '${raw['mode'] ?? ''}';
  String get type => '${raw['type'] ?? ''}';

  /// البرنامج الذي صدر له الترخيص: alnasser | shop_manager | '' (حساب قديم يعمل على البرنامجين)
  String get app => '${raw['app'] ?? ''}';

  /// حساب مالك (يفتح ميزات المالك). موقَّع من السيرفر فلا يمكن تفعيله يدوياً.
  bool get isOwner => raw['own'] == 1 || raw['own'] == true;
  int? get expiresMs => _intOrNull(raw['exp']);
  int? get graceUntilMs => _intOrNull(raw['grc']);
  int get issuedAtMs => _int(raw['iat']);
  int get checkAfterMs => _int(raw['chk']);
  int? get offlineUntilMs => _intOrNull(raw['off']);
  int get maxDevices => _int(raw['max']);

  /// 🖥️ عدد الشاشات المسموح على الحاسبة الواحدة (1 إن غاب — تراخيص قديمة)
  int get seats {
    final n = _int(raw['seats']);
    return n < 1 ? 1 : (n > 8 ? 8 : n);
  }
  String get supportPhone => '${raw['ph'] ?? LicenseConfig.supportPhone}';
  Map<String, String> get fingerprint {
    final f = raw['fp'];
    if (f is! Map) return const {};
    return f.map((k, v) => MapEntry('$k', '$v'));
  }

  bool get isLifetime => type == 'lifetime';
  bool get isMain => role == 'main';
  bool get syncAllowed => mode == 'full_sync';

  /// الترخيص لبرنامج آخر؟ (الحسابات القديمة بلا برنامج تُقبل)
  bool get isForOtherApp => app.isNotEmpty && app != LicenseConfig.appId;

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static int? _intOrNull(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
}

class LicenseToken {
  LicenseToken._();

  /// يعيد المحتوى فقط إن كان التوقيع صحيحاً بالمفتاح العام المضمَّن.
  static LicensePayload? verify(String? token, {String? publicKeyHex}) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 2) return null;
    try {
      final sig = base64Url.decode(base64Url.normalize(parts[1]));
      final pub = Ed25519.hexToBytes(publicKeyHex ?? LicenseConfig.publicKeyHex);
      if (!Ed25519.verify(sig, ascii.encode(parts[0]), pub)) return null;
      final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      final map = jsonDecode(json);
      if (map is! Map<String, dynamic>) return null;
      final p = LicensePayload(map);
      return p.version == 4 ? p : null;
    } catch (_) {
      return null;
    }
  }
}

/// نفس قاعدة السيرفر: الجهاز نفسه = تطابق قطعتين على الأقل من البصمة
/// (أو قطعة واحدة إن لم يتوفر غيرها في الطرفين).
bool fingerprintMatches(Map<String, String> stored, Map<String, String> now) {
  var common = 0, same = 0;
  for (final k in const ['mg', 'uuid', 'bb', 'cpu', 'bios', 'disk']) {
    final a = stored[k], b = now[k];
    if (a != null && a.isNotEmpty && b != null && b.isNotEmpty) {
      common++;
      if (a == b) same++;
    }
  }
  if (same >= 2) return true;
  return common == 1 && same == 1;
}
