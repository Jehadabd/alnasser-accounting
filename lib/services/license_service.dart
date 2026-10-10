// license_service.dart
//
// 🔐 نظام الترخيص — الإصدار 4 (توقيع رقمي + ربط بالجهاز + أجهزة إضافية برمز).
//
// • حساب الترخيص (من أداة الأدمن) يُكتب مرة واحدة في الجهاز الرئيسي. بقية
//   الأجهزة تُضاف برمز يولّده الجهاز الرئيسي، حتى العدد المسموح.
// • السيرفر يعطي كل جهاز «ترخيصاً موقَّعاً» (Ed25519). البرنامج لا يقبل إلا ما
//   يتحقق توقيعه بالمفتاح العام المضمَّن، ولا يقبله إلا إن طابقت بصمة الجهاز
//   البصمة المكتوبة داخله. لذلك لا يمكن: تزوير الترخيص، ولا تغيير نمطه
//   (ديون ← شامل ← مزامنة)، ولا مدّه، ولا نسخه إلى حاسوب آخر.
// • الاشتراك (المزامنة): تحقق يومي عند التشغيل؛ بعد الانتهاء يعمل 5 أيام مع
//   رسالة يومية فيها رقم التواصل، ثم يتوقف حتى التجديد (البيانات تبقى).
//   بلا أي تحقق أكثر من 7 أيام ⇒ يطلب الاتصال بالإنترنت.
// • الدائم: يحاول التحقق شهرياً إن توفر الإنترنت، ولا يُغلق لعدم الاتصال؛
//   يتوقف فقط إن أوقفناه نحن من السيرفر (فك ربط الجهاز / إيقاف الحساب).
// • تراجع ساعة الجهاز قبل آخر تحقق موقَّع ⇒ يُرفض (منع إطالة المدة بتغيير التاريخ).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random, max;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_sync/firebase_custom_config.dart';
import 'firebase_sync/firebase_sync_config.dart';
import 'sync/sync_security.dart';
import 'license_v4/device_fingerprint.dart';
import 'license_v4/license_api.dart';
import 'license_v4/license_config.dart';
import 'license_v4/license_token.dart';

export 'license_v4/license_config.dart' show LicenseConfig;

const int _day = 24 * 3600 * 1000;
const String _appVersion = 'acc-1.0.0-lic4';

enum LicenseState { none, active, warning, grace, expired, offlineTooLong, blocked, clockTampered }

class LicenseStatus {
  const LicenseStatus(this.state, {this.daysLeft, this.message});
  final LicenseState state;
  final int? daysLeft;
  final String? message;
  bool get usable =>
      state == LicenseState.active || state == LicenseState.warning || state == LicenseState.grace;
}

class LicenseService {
  static final LicenseService _instance = LicenseService._internal();
  factory LicenseService() => _instance;
  LicenseService._internal();

  /// ✅ فُعّل الترخيص (أو أُضيف الجهاز) في هذه الجلسة: يسمح بإنشاء حساب المدير
  /// مباشرةً دون طلب كلمة سر الترخيص مرة ثانية.
  static bool activatedThisSession = false;

  /// سبب إيقاف الترخيص — تعرضه شاشة التفعيل
  static String? blockMessage;

  /// أُضيف هذا الجهاز برمز وجاء معه ربط المزامنة (Firebase) من الجهاز الرئيسي:
  /// يلزم إعادة تشغيل البرنامج ليبدأ المزامنة وجلب البيانات والموظفين.
  static bool syncLinkApplied = false;

  /// تُضبط من main.dart: الانتقال لشاشة التفعيل إن توقف الترخيص أثناء العمل
  static void Function()? onLocked;

  static const _kToken = 'alnaser_license_v4';
  static const _kBlock = 'alnaser_license_v4_block';
  static const _kSeen = 'alnaser_license_v4_seen';
  static const _kDaily = 'alnaser_license_v4_daily';
  static const _secure = FlutterSecureStorage();

  static bool _initDone = false;
  static Future<void>? _initFuture;
  static String? _token;
  static LicensePayload? _payload;
  static Map<String, String> _fp = const {};
  static Map<String, dynamic>? _block;
  static Timer? _timer;

  // مخزن حالة الترخيص داخل مجلد بيانات البرنامج نفسه (لا في «المستندات» المشترك)،
  // فلكل برنامج/مستخدم ويندوز حالته الخاصة.
  static GetStorage? _box;
  GetStorage get _storage => _box ?? GetStorage();

  // ═══════════════════════════════ التهيئة ═══════════════════════════════

  /// يُستدعى مرة عند الإقلاع قبل اختيار الشاشة الأولى.
  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    final s = LicenseService();
    try {
      if (!kIsWeb) {
        final dir = await getApplicationSupportDirectory();
        final box = GetStorage('alnaser_license_v4', dir.path);
        await box.initStorage;
        _box = box;
      }
    } catch (e) {
      debugPrint('🔐 [LICENSE] storage: $e');
    }
    try {
      _fp = await DeviceFingerprint.collect();
      _block = s._readJson(_kBlock);
      // كل نسخ الترخيص المحفوظة (مخزن البرنامج ثم المخزن الآمن): يُعتمد أول ترخيص
      // صالح لهذا الجهاز. ترخيص لا يطابق لا يُحذف — قد يكون من نسخة أخرى للبرنامج.
      final tokens = await s._readTokens();
      var applied = false;
      for (final t in tokens) {
        if (s._applyToken(t)) {
          applied = true;
          if (s._storage.read<String>(_kToken) != t) await s._storage.write(_kToken, t);
          break;
        }
      }
      if (!applied) {
        s._applyToken(null);
        if (tokens.isEmpty && GetStorage().read('license_data') != null) {
          blockMessage = 'تحديث نظام الترخيص: فعّل البرنامج مرة واحدة بحساب الترخيص.\nبياناتك محفوظة كما هي.';
        }
      }
      debugPrint('🔐 [LICENSE] init: ${tokens.length} ترخيص محفوظ، ${applied ? 'مفعّل ✓' : 'غير مفعّل'}');
    } catch (e) {
      debugPrint('🔐 [LICENSE] init: $e');
    }
    _initDone = true;
    _timer ??= Timer.periodic(const Duration(hours: 6), (_) => s._backgroundRefresh());
  }

  /// يقبل الترخيص فقط إن كان موقَّعاً من سيرفرنا ولهذا الجهاز.
  bool _applyToken(String? token) {
    if (token == null) {
      _payload = null;
      _token = null;
      return false;
    }
    final p = LicenseToken.verify(token);
    if (p == null) {
      blockMessage = 'ترخيص هذا الجهاز غير صالح — فعّل البرنامج من جديد';
      _payload = null;
      _token = null;
      return false;
    }
    if (_fp.isEmpty) {
      blockMessage = 'تعذّر قراءة بصمة هذا الجهاز، فلا يمكن التحقق من الترخيص.\nأعد تشغيل البرنامج، وإن تكرر تواصل معنا: ${LicenseConfig.supportPhone}';
      _payload = null;
      _token = null;
      return false;
    }
    final parts = ['mg', 'uuid', 'bb', 'cpu', 'bios', 'disk']
        .where((k) => p.fingerprint[k] != null && _fp[k] != null)
        .map((k) => '$k${p.fingerprint[k] == _fp[k] ? '✓' : '✗'}')
        .join(' ');
    debugPrint('🔐 [LICENSE] بصمة الجهاز مقابل الترخيص: $parts');
    if (!fingerprintMatches(p.fingerprint, _fp)) {
      debugPrint('🔐 [LICENSE] البصمة لا تطابق هذا الترخيص');
      blockMessage = 'هذا الترخيص يخص جهازاً آخر. فعّل البرنامج على هذا الجهاز بحساب الترخيص، أو برمز من الجهاز الرئيسي.';
      _payload = null;
      _token = null;
      return false;
    }
    _payload = p;
    _token = token;
    return true;
  }

  // ═══════════════════════════════ الحالة ═══════════════════════════════

  int get _maxSeen => _toInt(_storage.read(_kSeen));

  /// أحدث وقت رآه البرنامج (لكشف إرجاع ساعة الجهاز). يُكتب كل دقيقة على الأكثر.
  void _bumpSeen([int? now]) {
    final n = now ?? DateTime.now().millisecondsSinceEpoch;
    if (n > _maxSeen + 60000) _storage.write(_kSeen, n);
  }

  LicenseStatus evaluate() {
    final p = _payload;
    if (p == null) return LicenseStatus(LicenseState.none, message: blockMessage);
    if (_block != null) {
      return LicenseStatus(LicenseState.blocked, message: '${_block!['message'] ?? 'الترخيص موقوف'}');
    }
    final real = DateTime.now().millisecondsSinceEpoch;
    final floor = max(p.issuedAtMs, _maxSeen);
    if (real < floor - 3600 * 1000) {
      return const LicenseStatus(LicenseState.clockTampered,
          message: 'تاريخ ووقت الجهاز غير صحيحين (أقدم من آخر تحقق من الترخيص).\n'
              'صحّح التاريخ والوقت من إعدادات ويندوز ثم أعد تشغيل البرنامج.');
    }
    final now = max(real, floor);
    _bumpSeen(now);
    final phone = p.supportPhone;
    if (!p.isLifetime) {
      final grc = p.graceUntilMs, exp = p.expiresMs, off = p.offlineUntilMs;
      if (grc != null && now > grc) {
        return LicenseStatus(LicenseState.expired,
            message: '${p.type == 'trial' ? 'انتهت الفترة التجريبية.' : 'انتهى الاشتراك وانتهت مهلة الأيام الخمسة.'}\n'
                'للتجديد تواصل مع صاحب البرنامج (واتساب / اتصال): $phone\n'
                'بعد التجديد اضغط «تحقق من التجديد» — بياناتك محفوظة.');
      }
      if (off != null && now > off) {
        return const LicenseStatus(LicenseState.offlineTooLong,
            message: 'يلزم الاتصال بالإنترنت للتحقق من الاشتراك (مرّ أكثر من 7 أيام بلا تحقق).\n'
                'صِل الإنترنت ثم اضغط «تحقق من التجديد».');
      }
      if (exp != null && now > exp && grc != null) {
        final d = ((grc - now) / _day).ceil().clamp(1, 99);
        return LicenseStatus(LicenseState.grace,
            daysLeft: d,
            message: '⚠️ انتهى اشتراكك.\n'
                'يبقى البرنامج يعمل ${_days(d)} فقط، ثم يتوقف حتى التجديد.\n'
                'للتجديد تواصل مع صاحب البرنامج (واتساب / اتصال): $phone\n'
                'بياناتك محفوظة ولا تُحذف.');
      }
      if (exp != null && exp - now < 3 * _day) {
        final d = ((exp - now) / _day).ceil().clamp(1, 3);
        return LicenseStatus(LicenseState.warning,
            daysLeft: d,
            message: 'تنبيه: ينتهي اشتراكك بعد ${_days(d)}.\n'
                'للتجديد تواصل مع صاحب البرنامج (واتساب / اتصال): $phone');
      }
    }
    return const LicenseStatus(LicenseState.active);
  }

  static String _days(int d) => d == 1 ? 'يوماً واحداً' : (d == 2 ? 'يومين' : '$d أيام');

  bool isLicenseActivated() => evaluate().usable;

  /// الترخيص الحالي إن كان صالحاً للاستعمال الآن (وإلا null).
  LicenseData? getStoredLicense() {
    final p = _payload;
    if (p == null || !evaluate().usable) return null;
    return LicenseData.fromPayload(p);
  }

  /// محتوى الترخيص حتى لو كان موقوفاً (للعرض فقط: اسم الحساب في شاشة التفعيل)
  LicensePayload? get payload => _payload;
  bool get hasStoredToken => _token != null;
  bool get isMainDevice => _payload?.isMain ?? false;

  // ═══════════════════════════════ الفحص عند الإقلاع ═══════════════════════════════

  Future<StartupCheckResult> performStartupCheck() async {
    await init();
    if (_payload == null) {
      return StartupCheckResult(canProceed: false, reason: StartupBlockReason.notActivated, message: blockMessage);
    }
    var st = evaluate();
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = now > _payload!.checkAfterMs || st.state != LicenseState.active;
    if (due) {
      await refreshNow();
      if (_payload == null) {
        return StartupCheckResult(canProceed: false, reason: StartupBlockReason.notActivated, message: blockMessage);
      }
      st = evaluate();
    }
    switch (st.state) {
      case LicenseState.active:
        return StartupCheckResult(canProceed: true);
      case LicenseState.warning:
      case LicenseState.grace:
        final show = _dailyOnce();
        return StartupCheckResult(
          canProceed: true,
          showWarning: show,
          warningMessage: st.message,
          daysLeft: st.daysLeft,
          isGracePeriod: st.state == LicenseState.grace,
        );
      case LicenseState.clockTampered:
        return StartupCheckResult(canProceed: false, reason: StartupBlockReason.clockTampering, message: st.message);
      case LicenseState.expired:
        blockMessage = st.message;
        return StartupCheckResult(canProceed: false, reason: StartupBlockReason.expired, message: st.message);
      case LicenseState.offlineTooLong:
        blockMessage = st.message;
        return StartupCheckResult(canProceed: false, reason: StartupBlockReason.noInternetInGrace, message: st.message);
      case LicenseState.blocked:
        blockMessage = st.message;
        return StartupCheckResult(canProceed: false, reason: StartupBlockReason.serverRejected, message: st.message);
      case LicenseState.none:
        return StartupCheckResult(canProceed: false, reason: StartupBlockReason.notActivated, message: blockMessage);
    }
  }

  /// رسالة الانتهاء/التنبيه مرة واحدة في اليوم
  bool _dailyOnce() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_storage.read(_kDaily) == today) return false;
    _storage.write(_kDaily, today);
    return true;
  }

  Future<void> _backgroundRefresh() async {
    if (_payload == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _payload!.checkAfterMs && evaluate().state == LicenseState.active) return;
    if (!await hasInternetConnection()) return;
    await refreshNow();
    if (!evaluate().usable) onLocked?.call();
  }

  // ═══════════════════════════════ العمليات مع السيرفر ═══════════════════════════════

  /// تفعيل بحساب الترخيص (الجهاز الرئيسي). [move]: نقل الجهاز الرئيسي إلى هذا الجهاز.
  Future<LicenseResult> activateLicense(String username, String password, {bool move = false}) async {
    await init();
    if (_fp.isEmpty) return _noFingerprint();
    final r = await LicenseApi.call({
      'action': 'activate',
      'username': username.trim(),
      'password': password,
      'fp': _fp,
      'name': DeviceFingerprint.deviceName(),
      'appVersion': _appVersion,
      if (move) 'move': true,
    });
    final res = await _handleIssue(r);
    if (res.success) activatedThisSession = true;
    return res;
  }

  /// إضافة هذا الجهاز برمز من الجهاز الرئيسي.
  Future<LicenseResult> redeemPairCode(String code) async {
    await init();
    if (_fp.isEmpty) return _noFingerprint();
    final r = await LicenseApi.call({
      'action': 'pair_redeem',
      'code': code.trim(),
      'fp': _fp,
      'name': DeviceFingerprint.deviceName(),
      'appVersion': _appVersion,
    });
    final res = await _handleIssue(r);
    if (res.success) {
      activatedThisSession = true;
      final cfg = r['cfg'];
      if (cfg is Map && _payload?.syncAllowed == true) await _applySyncLink(Map<String, dynamic>.from(cfg));
    }
    return res;
  }

  /// 🔎 التعرّف على هذا الجهاز من بصمته وحدها: إن كان مفعّلاً على السيرفر
  /// (إعادة تثبيت، أو نسخة أخرى من البرنامج على الحاسوب نفسه) يفتح مباشرة
  /// بلا اسم ولا كلمة سر. لا يعمل على حاسوب غير مفعّل.
  Future<LicenseResult> recoverByFingerprint() async {
    await init();
    if (_fp.isEmpty) return _noFingerprint();
    final r = await LicenseApi.call({
      'action': 'recover',
      'fp': _fp,
      'name': DeviceFingerprint.deviceName(),
      'appVersion': _appVersion,
    });
    final code = '${r['error'] ?? ''}';
    if (code == 'EXPIRED' || code == 'SUSPENDED') blockMessage = '${r['message'] ?? ''}';
    final res = await _handleIssue(r);
    debugPrint('🔐 [LICENSE] recover → ${res.success ? 'OK' : res.error}');
    return res;
  }

  /// يحفظ ربط Firebase (ومفتاح المجموعة) القادم من الجهاز الرئيسي مع رمز الإضافة.
  Future<void> _applySyncLink(Map<String, dynamic> cfg) async {
    try {
      final apiKey = '${cfg['apiKey'] ?? ''}', appId = '${cfg['appId'] ?? ''}';
      final projectId = '${cfg['projectId'] ?? ''}';
      if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) return;
      await FirebaseCustomConfig.saveCustomConfig(
        apiKey: apiKey,
        appId: appId,
        projectId: projectId,
        messagingSenderId: '${cfg['messagingSenderId'] ?? ''}',
        authDomain: cfg['authDomain'] == null ? null : '${cfg['authDomain']}',
      );
      final secret = '${cfg['secret'] ?? ''}';
      if (secret.isNotEmpty) await SyncSecurity.saveSecretKey(secret);
      await FirebaseSyncConfig.setEnabled(true);
      FirebaseCustomConfig.restartRequired = true;
      syncLinkApplied = true;
    } catch (e) {
      debugPrint('🔐 [LICENSE] ربط المزامنة: $e');
    }
  }

  /// ربط Firebase الحالي (يُرسل مع رمز الإضافة ليتصل الجهاز الجديد تلقائياً)
  Future<Map<String, dynamic>?> _currentSyncLink() async {
    if (_payload?.syncAllowed != true) return null;
    try {
      final o = await FirebaseCustomConfig.getCustomOptions();
      if (o == null) return null;
      final secret = await SyncSecurity.readSecretKey();
      return {
        'apiKey': o.apiKey,
        'appId': o.appId,
        'projectId': o.projectId,
        'messagingSenderId': o.messagingSenderId,
        if (o.authDomain != null) 'authDomain': o.authDomain,
        if (secret != null) 'secret': secret,
      };
    } catch (_) {
      return null;
    }
  }

  /// تجديد الترخيص الموقَّع من السيرفر (يومياً للاشتراك، شهرياً للدائم، أو يدوياً).
  Future<LicenseResult> refreshNow() async {
    await init();
    if (_token == null) return LicenseResult(success: false, error: 'NOT_ACTIVATED', message: 'الترخيص غير مفعّل');
    final r = await LicenseApi.call({
      'action': 'refresh',
      'token': _token,
      'fp': _fp,
      'name': DeviceFingerprint.deviceName(),
      'appVersion': _appVersion,
    });
    return _handleIssue(r);
  }

  /// اسم قديم تستعمله شاشة الإعدادات
  Future<LicenseResult> verifyWithServer({bool silent = false}) => refreshNow();

  Future<LicenseResult> _handleIssue(Map<String, dynamic> r) async {
    if (r['ok'] == true && r['token'] is String) {
      final token = r['token'] as String;
      if (!_applyToken(token)) {
        return LicenseResult(success: false, error: 'BAD_TOKEN', message: blockMessage ?? 'استجابة غير موثوقة من السيرفر');
      }
      await _storeToken(token);
      _block = null;
      await _writeJson(_kBlock, null);
      blockMessage = null;
      // وقت السيرفر هو المرجع: يصحّح «أحدث وقت» إن كانت ساعة الجهاز قد قُدّمت خطأً ثم صُحّحت
      await _storage.write(_kSeen, _payload!.issuedAtMs);
      await FirebaseSyncConfig.setEnabled(_payload!.syncAllowed);
      return LicenseResult.fromPayload(_payload!);
    }
    final code = '${r['error'] ?? 'UNKNOWN'}';
    final message = '${r['message'] ?? 'خطأ غير معروف'}';
    if (code == 'REVOKED' || code == 'DEVICE_MISMATCH' || code == 'BAD_TOKEN') {
      if (_token != null) {
        await clearLicense();
        blockMessage = message;
      }
    } else if (code == 'EXPIRED' || code == 'SUSPENDED') {
      if (_token != null) {
        _block = {'code': code, 'message': message, 'at': DateTime.now().millisecondsSinceEpoch};
        await _writeJson(_kBlock, _block);
        blockMessage = message;
      }
    }
    return LicenseResult(
      success: false,
      error: code,
      message: message,
      movesLeft: r['moves_left'] is num ? (r['moves_left'] as num).toInt() : null,
      mainDeviceName: (r['main_name'] is String && (r['main_name'] as String).isNotEmpty) ? r['main_name'] as String : null,
      noInternet: code == 'NETWORK_ERROR',
    );
  }

  LicenseResult _noFingerprint() => LicenseResult(
      success: false,
      error: 'BAD_FINGERPRINT',
      message: 'تعذّر قراءة بصمة هذا الجهاز. أعد تشغيل البرنامج، وإن تكرر تواصل معنا: ${LicenseConfig.supportPhone}');

  /// الجهاز الرئيسي: رمز لإضافة جهاز جديد (صالح دقائق، يُستعمل مرة واحدة).
  Future<PairCodeResult> createPairCode() async {
    if (_token == null) return PairCodeResult(error: 'NOT_ACTIVATED', message: 'الترخيص غير مفعّل');
    final cfg = await _currentSyncLink();
    final r = await LicenseApi.call({'action': 'pair_create', 'token': _token, 'fp': _fp, if (cfg != null) 'cfg': cfg});
    if (r['ok'] == true) {
      return PairCodeResult(
        code: '${r['code']}',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(_toInt(r['expires'])),
        used: _toInt(r['used']),
        max: _toInt(r['max']),
      );
    }
    await _handleIssue(r);
    return PairCodeResult(error: '${r['error']}', message: '${r['message'] ?? ''}');
  }

  /// الجهاز الرئيسي: الأجهزة المرتبطة بالترخيص.
  Future<DevicesResult> listDevices() async {
    if (_token == null) return DevicesResult(error: 'NOT_ACTIVATED', message: 'الترخيص غير مفعّل');
    final r = await LicenseApi.call({'action': 'devices', 'token': _token, 'fp': _fp});
    if (r['ok'] == true) {
      final list = (r['devices'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => LicenseDeviceInfo.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      return DevicesResult(devices: list, max: _toInt(r['max']));
    }
    await _handleIssue(r);
    return DevicesResult(error: '${r['error']}', message: '${r['message'] ?? ''}');
  }

  /// الجهاز الرئيسي: فك ربط جهاز إضافي (يتحرر مكانه).
  Future<LicenseResult> unbindDevice(String deviceId) async {
    if (_token == null) return LicenseResult(success: false, error: 'NOT_ACTIVATED');
    final r = await LicenseApi.call({'action': 'unbind', 'token': _token, 'fp': _fp, 'device_id': deviceId});
    if (r['ok'] == true) return LicenseResult(success: true);
    return LicenseResult(success: false, error: '${r['error']}', message: '${r['message'] ?? ''}');
  }

  /// 🔑 التحقق من كلمة سر حساب الترخيص (عبر السيرفر) — لاستعادة كلمة سر المدير
  /// أو إنشاء مدير جديد إن فرغ جدول المستخدمين.
  Future<LicensePasswordCheck> checkAccountPassword(String password) async {
    if (_token == null) return const LicensePasswordCheck(LicensePasswordStatus.noLicense);
    if (password.isEmpty) return const LicensePasswordCheck(LicensePasswordStatus.wrong);
    final r = await LicenseApi.call({'action': 'verify_owner', 'token': _token, 'fp': _fp, 'password': password});
    if (r['ok'] == true) return const LicensePasswordCheck(LicensePasswordStatus.ok);
    final err = '${r['error'] ?? ''}';
    if (err == 'WRONG_CREDENTIALS') return const LicensePasswordCheck(LicensePasswordStatus.wrong);
    if (err == 'NETWORK_ERROR' || err == 'NOT_CONFIGURED') {
      return const LicensePasswordCheck(LicensePasswordStatus.offline);
    }
    return LicensePasswordCheck(LicensePasswordStatus.rejected, '${r['message'] ?? err}');
  }

  /// فك ربط هذا الجهاز بكلمة سر الترخيص (لنقل البرنامج إلى جهاز آخر).
  Future<LicenseResult> selfUnbindDevice(String password) async {
    if (_token == null) return LicenseResult(success: false, error: 'NOT_ACTIVATED', message: 'الترخيص غير مفعّل');
    final r = await LicenseApi.call({'action': 'release', 'token': _token, 'fp': _fp, 'password': password});
    if (r['ok'] == true) {
      await clearLicense();
      return LicenseResult(success: true, message: 'تم فك ربط هذا الجهاز. يمكنك الآن تفعيل البرنامج على جهاز آخر.');
    }
    return LicenseResult(success: false, error: '${r['error']}', message: '${r['message'] ?? 'فشل فك الربط'}');
  }

  Future<void> clearLicense() async {
    _payload = null;
    _token = null;
    _block = null;
    await _deleteStored();
    await _writeJson(_kBlock, null);
  }

  // ═══════════════════════════════ التخزين ═══════════════════════════════

  /// كل نسخ الترخيص المحفوظة بلا تكرار: مخزن البرنامج أولاً (خاص بهذه النسخة)، ثم المخزن الآمن.
  Future<List<String>> _readTokens() async {
    final out = <String>[];
    void add(String? t) {
      if (t != null && t.isNotEmpty && !out.contains(t)) out.add(t);
    }

    add(_storage.read<String>(_kToken));
    try {
      add(await _secure.read(key: _kToken));
    } catch (_) {}
    if (kIsWeb) {
      try {
        add((await SharedPreferences.getInstance()).getString(_kToken));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _storeToken(String token) async {
    try {
      await _secure.write(key: _kToken, value: token);
    } catch (_) {}
    await _storage.write(_kToken, token);
    if (kIsWeb) {
      try {
        await (await SharedPreferences.getInstance()).setString(_kToken, token);
      } catch (_) {}
    }
  }

  Future<void> _deleteStored() async {
    try {
      await _secure.delete(key: _kToken);
    } catch (_) {}
    await _storage.remove(_kToken);
    if (kIsWeb) {
      try {
        await (await SharedPreferences.getInstance()).remove(_kToken);
      } catch (_) {}
    }
  }

  Map<String, dynamic>? _readJson(String key) {
    final v = _storage.read(key);
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(v) as Map);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _writeJson(String key, Map<String, dynamic>? v) async {
    if (v == null) {
      await _storage.remove(key);
    } else {
      await _storage.write(key, jsonEncode(v));
    }
  }

  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  // ═══════════════════════════════ أدوات عامة ═══════════════════════════════

  Future<bool> hasInternetConnection() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return false;
      if (kIsWeb) return true;
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 6));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return kIsWeb;
    }
  }

  /// معرّف قديم ثابت للجهاز (يستعمله قفل العملاء بين الأجهزة) — غير مرتبط بالترخيص.
  Future<String> generateDeviceId() async {
    try {
      if (kIsWeb) {
        final legacy = GetStorage();
        String? stored = legacy.read<String>('web_device_id');
        if (stored == null || stored.isEmpty) {
          try {
            stored = (await SharedPreferences.getInstance()).getString('web_device_id');
          } catch (_) {}
        }
        if (stored != null && stored.isNotEmpty) return stored;
        final newId = sha256
            .convert(utf8.encode('web_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}'))
            .toString()
            .substring(0, 32);
        await legacy.write('web_device_id', newId);
        try {
          await (await SharedPreferences.getInstance()).setString('web_device_id', newId);
        } catch (_) {}
        return newId;
      }
      final parts = <String>[
        Platform.localHostname,
        Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? 'unknown',
      ];
      if (Platform.isWindows) {
        for (final what in const ['diskdrive', 'baseboard']) {
          try {
            final r = await Process.run('wmic', [what, 'get', 'serialnumber'], runInShell: true);
            if (r.exitCode == 0) {
              parts.add(r.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty && !s.contains('SerialNumber')).join().trim());
            }
          } catch (_) {}
        }
      }
      return sha256.convert(utf8.encode(parts.join('|'))).toString().substring(0, 32);
    } catch (e) {
      final fallback = '${kIsWeb ? "web" : Platform.localHostname}_${DateTime.now().millisecondsSinceEpoch}';
      return sha256.convert(utf8.encode(fallback)).toString().substring(0, 32);
    }
  }
}

// ========== Data Classes ==========

enum LicensePasswordStatus { ok, wrong, offline, rejected, noLicense }

class LicensePasswordCheck {
  const LicensePasswordCheck(this.status, [this.message]);
  final LicensePasswordStatus status;
  final String? message;
}

class LicenseData {
  final String username;
  final String? mainUsername;
  final String? subUsername;
  final String appMode; // 'debts_only', 'full_offline', 'full_sync'
  final String deviceId;
  final String type; // 'lifetime', 'subscription', 'trial'
  final String expires;
  final int? daysLeft;
  final bool isSyncAllowed;
  final String role; // 'main' | 'secondary'
  final String customer;
  final int maxDevices;

  LicenseData({
    required this.username,
    this.mainUsername,
    this.subUsername,
    this.appMode = 'full_offline',
    required this.deviceId,
    required this.type,
    required this.expires,
    this.daysLeft,
    bool? isSyncAllowed,
    this.role = 'main',
    this.customer = '',
    this.maxDevices = 1,
  }) : isSyncAllowed = isSyncAllowed ?? appMode == 'full_sync';

  factory LicenseData.fromPayload(LicensePayload p) {
    final exp = p.expiresMs;
    return LicenseData(
      username: p.account,
      mainUsername: p.account,
      subUsername: p.account,
      appMode: p.mode,
      deviceId: p.deviceId,
      type: p.type,
      expires: exp == null
          ? '2099-12-31T23:59:59.000'
          : DateTime.fromMillisecondsSinceEpoch(exp).toIso8601String(),
      daysLeft: exp == null ? null : ((exp - DateTime.now().millisecondsSinceEpoch) / _day).floor(),
      isSyncAllowed: p.syncAllowed,
      role: p.role,
      customer: p.customer,
      maxDevices: p.maxDevices,
    );
  }

  bool get isDebtsOnly => appMode == 'debts_only';
  bool get isFullOffline => appMode == 'full_offline';
  bool get isFullSync => isSyncAllowed;
  bool get isMainDevice => role == 'main';
  bool get isLifetime => type == 'lifetime';

  String get modeLabel => switch (appMode) {
        'debts_only' => 'سجل الديون',
        'full_offline' => 'التطبيق الشامل (بلا مزامنة)',
        'full_sync' => 'التطبيق الشامل + المزامنة',
        _ => appMode,
      };

  String get typeLabel => switch (type) {
        'lifetime' => 'دائم مدى الحياة',
        'subscription' => 'اشتراك حتى ${expires.substring(0, 10)}',
        'trial' => 'تجريبي حتى ${expires.substring(0, 10)}',
        _ => type,
      };
}

class LicenseResult {
  final bool success;
  final String? type;
  final String appMode;
  final String? mainUsername;
  final String? subUsername;
  final String? expires;
  final int? daysLeft;
  final String? warning;
  final String? error;
  final String? message;
  final bool noInternet;
  final bool? wasRenewed;
  final int? movesLeft;

  /// اسم الحاسبة الرئيسية الحالية (عند MAIN_BOUND_ELSEWHERE)
  final String? mainDeviceName;

  LicenseResult({
    required this.success,
    this.type,
    this.appMode = 'full_offline',
    this.mainUsername,
    this.subUsername,
    this.expires,
    this.daysLeft,
    this.warning,
    this.error,
    this.message,
    this.noInternet = false,
    this.wasRenewed,
    this.movesLeft,
    this.mainDeviceName,
  });

  factory LicenseResult.fromPayload(LicensePayload p) {
    final d = LicenseData.fromPayload(p);
    return LicenseResult(
      success: true,
      type: p.type,
      appMode: p.mode,
      mainUsername: p.account,
      subUsername: p.account,
      expires: d.expires,
      daysLeft: d.daysLeft,
      wasRenewed: true,
    );
  }
}

class PairCodeResult {
  PairCodeResult({this.code, this.expiresAt, this.used = 0, this.max = 0, this.error, this.message});
  final String? code;
  final DateTime? expiresAt;
  final int used;
  final int max;
  final String? error;
  final String? message;
  bool get success => code != null;
}

class LicenseDeviceInfo {
  LicenseDeviceInfo({
    required this.id,
    required this.name,
    required this.role,
    required this.isThis,
    this.firstSeen,
    this.lastSeen,
  });
  final String id;
  final String name;
  final String role;
  final bool isThis;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  bool get isMain => role == 'main';

  factory LicenseDeviceInfo.fromJson(Map<String, dynamic> j) {
    DateTime? t(dynamic v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return LicenseDeviceInfo(
      id: '${j['device_id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      role: '${j['role'] ?? ''}',
      isThis: j['is_this'] == true,
      firstSeen: t(j['first_seen']),
      lastSeen: t(j['last_seen']),
    );
  }
}

class DevicesResult {
  DevicesResult({this.devices = const [], this.max = 0, this.error, this.message});
  final List<LicenseDeviceInfo> devices;
  final int max;
  final String? error;
  final String? message;
  bool get success => error == null;
}

enum StartupBlockReason {
  notActivated,
  expired,
  clockTampering,
  serverRejected,
  noInternetInGrace,
}

class StartupCheckResult {
  final bool canProceed;
  final StartupBlockReason? reason;
  final String? message;
  final bool showWarning;
  final String? warningMessage;
  final int? daysLeft;
  final bool isGracePeriod;

  StartupCheckResult({
    required this.canProceed,
    this.reason,
    this.message,
    this.showWarning = false,
    this.warningMessage,
    this.daysLeft,
    this.isGracePeriod = false,
  });
}
