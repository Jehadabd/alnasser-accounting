// lib/services/admin_unlocks.dart
//
// 🔓 أقسام إعدادات لا يفتحها إلا صاحب البرنامج (من أداة الأدمن):
//   ai     إعدادات نماذج الذكاء الاصطناعي
//   upload وجهات «رفع البيانات» (تيليغرام، ديسكورد، دروب بوكس، Google Drive، SimpleX)
//   sync   إعدادات المزامنة بين الأجهزة
//   fb     ربط Firebase مخصص
//   web    استضافة ورفع نسخة المتصفح
//
// • حساب المالك (own=1): كلها مفتوحة دائماً، بلا سؤال السيرفر.
// • أي حساب آخر: القسم لا يظهر أصلاً حتى يفتحه الأدمن لهذا الحساب.
// • فتح القسم يطلب من السيرفر ترخيصاً جديداً موقَّعاً لحظتها (unl في الترخيص)،
//   فإغلاقه من الأدمن يسري فوراً — وبلا إنترنت لا يُفتح (الإذن من السيرفر وحده).
// • العمل الآلي لا يتوقف: الرفع والمزامنة تستمر بالإعدادات المحفوظة؛ المقفل هو الإعدادات فقط.

import 'package:flutter/material.dart';

import '../owner/owner_access.dart';
import 'license_service.dart';

class AdminUnlocks {
  AdminUnlocks._();

  static const ai = 'ai';
  static const upload = 'upload';
  static const sync = 'sync';
  static const fb = 'fb';
  static const web = 'web';

  /// يظهر القسم؟ المالك دائماً؛ غيره حسب آخر ترخيص موقَّع من السيرفر.
  static bool visible(String key) {
    if (OwnerAccess.enabled) return true;
    try {
      return LicenseService().payload?.unlocks.contains(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static DateTime? _lastQuiet;

  /// تحديث هادئ للترخيص (مرة كل دقيقة على الأكثر) لتظهر/تختفي الأقسام حسب آخر قرار للأدمن.
  /// يعيد true إن تغيّر شيء يستحق إعادة الرسم.
  static Future<bool> refreshQuietly() async {
    if (OwnerAccess.enabled) return false;
    final now = DateTime.now();
    if (_lastQuiet != null && now.difference(_lastQuiet!) < const Duration(minutes: 1)) return false;
    _lastQuiet = now;
    final before = _snapshot();
    try {
      await LicenseService().refreshNow().timeout(const Duration(seconds: 25));
    } catch (_) {}
    return _snapshot() != before;
  }

  static String _snapshot() {
    try {
      final l = [...?LicenseService().payload?.unlocks]..sort();
      return l.join(',');
    } catch (_) {
      return '';
    }
  }

  /// 🔐 قبل فتح قسم: المالك يمر؛ غيره يسأل السيرفر الآن. false = لا يُفتح (مع رسالة).
  static Future<bool> confirm(BuildContext context, String key) async {
    if (OwnerAccess.enabled) return true;
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    var closed = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 16),
            Expanded(child: Text('جارٍ التحقق من الإذن…')),
          ]),
        ),
      ),
    ).whenComplete(() => closed = true);
    LicenseResult? r;
    try {
      r = await LicenseService().refreshNow().timeout(const Duration(seconds: 25));
    } catch (_) {
      r = null;
    }
    _lastQuiet = DateTime.now();
    if (!closed && nav.canPop()) nav.pop();
    // الإذن من السيرفر الآن فقط: ترخيص قديم محفوظ لا يكفي (لا إنترنت ⇒ لا يُفتح)
    final ok = r != null && r.success && visible(key);
    if (!ok) {
      final offline = r == null || r.noInternet || r.error == 'NETWORK_ERROR';
      messenger?.showSnackBar(SnackBar(
        content: Text(offline
            ? 'هذا القسم يُفتح بإذن من صاحب البرنامج عبر الإنترنت — تحقّق من الاتصال ثم أعد المحاولة'
            : 'هذا القسم مغلق — يفتحه صاحب البرنامج عند الحاجة'),
      ));
    }
    return ok;
  }
}
