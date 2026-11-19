// screens/login_screen.dart
//
// 🔐 شاشة الدخول — تظهر في كل فتح للبرنامج.
//
//   طبقتان منفصلتان:
//   1) الترخيص (شاشة التفعيل): موافقتنا على تشغيل البرنامج في هذا الجهاز.
//      حسابه من أداة الأدمن، يُكتب مرة واحدة عند التثبيت، ولا يصير مستخدماً.
//   2) المستخدمون (هذه الشاشة + الإعدادات ← الموظفون): حسابات المحل نفسه.
//
//   • أول تشغيل (لا مستخدمين): «إنشاء حساب المدير» باسم وكلمة سر يختارهما
//     صاحب المحل. بعد التفعيل مباشرةً لا يُسأل شيء آخر؛ وإن فرغ جدول
//     المستخدمين لاحقاً يُطلب إثبات ملكية الترخيص (كلمة سره، يتحقق منها
//     السيرفر) — كي لا يصير أي أحد مديراً بمجرد إفراغ الجدول. لا كلمة جوكر.
//   • بعدها: دخول المدير أو الموظف، وكل موظف يرى ما تسمح به صلاحياته فقط.
//   • الوضع التجريبي يُفتح ويُغلق من هنا (لا من الإعدادات).

import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../lan/lan_bootstrap.dart';
import '../lan/lan_settings.dart';
import '../lan/network_settings_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/demo_mode.dart';
import '../services/firebase_sync/firebase_custom_config.dart';
import '../services/firebase_sync/users_sync_service.dart';
import '../services/license_service.dart';
import 'license_screen.dart' show LicenseScreen, openSupportWhatsApp;

enum _Mode { loading, demo, setupAdmin, login, waitUsers }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _navy = Color(0xFF0F3460);
  static const _navyDark = Color(0xFF020F2B);
  static const _accent = Color(0xFF00B4D8);

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _proofController = TextEditingController();
  final AuthService _authService = AuthService();
  final LicenseService _license = LicenseService();

  _Mode _mode = _Mode.loading;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _info;
  List<String> _names = const [];
  bool _stay = true;
  Timer? _waitTimer;
  StreamSubscription<void>? _waitSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (DemoMode.isOn) {
      setState(() => _mode = _Mode.demo);
      return;
    }
    bool hasUsers = true;
    try {
      hasUsers = await _authService.hasAnyUsers();
    } catch (_) {}
    if (!mounted) return;
    if (hasUsers) {
      // 🔓 البقاء مسجلاً للدخول: آخر مستخدم يدخل مباشرة حتى يخرج بنفسه
      final auto = await _authService.restoreSavedLogin();
      if (!mounted) return;
      if (auto != null) {
        Navigator.pushReplacementNamed(context, '/main');
        return;
      }
      _stay = await _authService.stayLoggedIn();
      _usernameController.text = await _authService.lastUsername() ?? '';
      try {
        _names = (await _authService.getAllUsers()).map((u) => u.username).toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _mode = _Mode.login);
    } else {
      _usernameController.text = '';
      // 👥 ⭐ جهاز إضافي: لا يُنشئ مديراً أبداً. حسابات المستخدمين تأتي من الجهاز
      // الرئيسي: عبر حاسبة السيرفر في شبكة المحل (يبحث عنها وحده باستمرار)، أو عبر
      // المزامنة. الخروج الوحيد: «تفعيل بحساب آخر» = جهاز مستقل لشخص آخر.
      final lic = _license.getStoredLicense();
      final extra = lic != null && !lic.isMainDevice;
      final viaSync = extra && lic.isSyncAllowed && await FirebaseCustomConfig.isCustomConfigured();
      if (!mounted) return;
      if (extra) {
        setState(() => _mode = _Mode.waitUsers);
        if (viaSync) _startWaitingForUsers();
        _startSearchingLan(syncAllowed: lic.isSyncAllowed, viaSync: viaSync);
      } else {
        setState(() => _mode = _Mode.setupAdmin);
      }
    }
  }

  // ───────────────── ⭐ جهاز إضافي: اتصال تلقائي بالجهاز الرئيسي ─────────────────

  Timer? _lanTimer;
  bool _joining = false;
  int _lanTries = 0;
  String _lanStatus = 'أبحث عن حاسبة السيرفر على شبكة المحل...';

  /// ⭐ جهاز إضافي بحساب مزامنة: مستقل يعمل عبر الإنترنت — لا يبحث عن حاسبة السيرفر.
  bool _syncMode = false;

  /// وصل ربط المزامنة في هذه الجلسة: يلزم إعادة تشغيل البرنامج ليتصل.
  bool _syncReady = false;

  void _startSearchingLan({required bool syncAllowed, required bool viaSync}) {
    if (kIsWeb) return;
    if (syncAllowed) {
      _syncMode = true;
      final restart = FirebaseCustomConfig.restartRequired;
      setState(() {
        _syncReady = restart;
        _lanStatus = restart
            ? 'وصل إعداد المزامنة ✅ — أعد تشغيل البرنامج ليتصل ويجلب البيانات وحسابات الموظفين.'
            : viaSync
                ? 'متصل بالمزامنة — أنتظر وصول حسابات الموظفين من الجهاز الرئيسي عبر الإنترنت...'
                : 'أنتظر وصول إعداد المزامنة من الجهاز الرئيسي عبر الإنترنت...';
      });
      if (!viaSync && !restart) _startWaitingForSyncLink();
      return;
    }
    Future<void> attempt() async {
      if (_joining || _mode != _Mode.waitUsers) return;
      _joining = true;
      LanSettings? joined;
      try {
        joined = await LanRuntime.autoJoin();
      } catch (_) {}
      // حساب مزامنة وصل إعداده الآن (أرسله الجهاز الرئيسي) ⇒ إعادة تشغيل ليتصل
      var syncArrived = false;
      if (joined == null && syncAllowed && !viaSync) {
        try {
          syncArrived = await FirebaseCustomConfig.isCustomConfigured();
        } catch (_) {}
      }
      _joining = false;
      if (!mounted || _mode != _Mode.waitUsers) return;
      if (joined == null && !syncArrived) {
        setState(() {
          _lanTries++;
          _lanStatus = 'لم أجد حاسبة السيرفر بعد — أعيد البحث تلقائياً كل بضع ثوانٍ.';
        });
        return;
      }
      _stopWaiting();
      final win = Platform.isWindows;
      final j = joined;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(j != null ? '✅ اتصل هذا الجهاز بحاسبة المحل' : '✅ وصل إعداد المزامنة'),
          content: Text(
            '${j != null ? 'ارتبط بحاسبة السيرفر «${j.serverName}» (${j.host}).\n' : 'وصل ربط المزامنة من الجهاز الرئيسي.\n'}'
            '${win ? 'سيُعاد تشغيل البرنامج الآن' : 'سيُغلق البرنامج الآن، افتحه من جديد'}، '
            'ثم ادخل باسمك وكلمة سرك كما أنشأها المدير.',
            style: const TextStyle(height: 1.6),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );
      await LanRuntime.relaunch();
    }

    unawaited(attempt());
    _lanTimer = Timer.periodic(const Duration(seconds: 15), (_) => unawaited(attempt()));
  }

  /// ⭐ جهاز إضافي بحساب مزامنة لم يصله ربطها بعد (أُضيف قبل ضبط المزامنة على الجهاز
  /// الرئيسي): يسأل سيرفر الترخيص — أول ربع ساعة كل دقيقة، ثم كل 5 دقائق — فيصل
  /// الربط وحده حين يضبطه الرئيسي، بلا انتظار التحقق الدوري (كل 4 ساعات).
  void _startWaitingForSyncLink() {
    var busy = false;
    var ticks = 0;
    Future<void> attempt() async {
      if (busy || _syncReady || _mode != _Mode.waitUsers) return;
      busy = true;
      var arrived = false;
      try {
        arrived = await FirebaseCustomConfig.isCustomConfigured();
        if (!arrived && (ticks < 15 || ticks % 5 == 0)) {
          await _license.refreshNow();
          arrived = await FirebaseCustomConfig.isCustomConfigured();
        }
      } catch (_) {}
      ticks++;
      busy = false;
      if (!mounted || _mode != _Mode.waitUsers) return;
      setState(() {
        _lanTries++;
        _syncReady = arrived;
        _lanStatus = arrived
            ? 'وصل إعداد المزامنة ✅ — أعد تشغيل البرنامج ليتصل ويجلب البيانات وحسابات الموظفين.'
            : 'لم يصل إعداد المزامنة بعد — أسأل عنه تلقائياً كل دقيقة.';
      });
    }

    unawaited(attempt());
    _lanTimer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(attempt()));
  }

  /// ⭐ «تفعيل بحساب آخر»: الجهاز يصير مستقلاً لشخص آخر. من جهاز إضافي يُرفض إن
  /// وصل إليه شيء من بيانات المحل (لا تُنقل بيانات محل إلى ترخيص شخص آخر ولا تُحذف).
  Future<void> _activateOtherAccount() async {
    final lic = _license.getStoredLicense();
    final extra = lic != null && !lic.isMainDevice;
    if (extra) {
      var rows = 0;
      try {
        final db = await DatabaseService().database;
        final r = await db.rawQuery(
            'SELECT (SELECT COUNT(*) FROM customers) + (SELECT COUNT(*) FROM invoices) AS n');
        rows = (r.first['n'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      if (!mounted) return;
      if (rows > 0) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('لا يمكن فصل هذا الجهاز هنا'),
            content: Text(
              'وصلت إلى هذا الجهاز بيانات من المحل الحالي ($rows سجل بين عملاء وفواتير). '
              'تفعيله بحساب شخص آخر يكشف له هذه البيانات، ولن أحذفها دون علمك.\n\n'
              'تواصل مع الدعم لفصله بأمان.',
              style: const TextStyle(height: 1.6),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  openSupportWhatsApp();
                },
                icon: const Icon(Icons.support_agent),
                label: const Text('الدعم'),
              ),
            ],
          ),
        );
        return;
      }
    }
    _stopWaiting();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LicenseScreen(accountOnly: true)));
    await _resumeWaiting();
  }

  void _startWaitingForUsers() {
    Future<void> check() async {
      if (_mode != _Mode.waitUsers) return;
      var has = false;
      try {
        has = await _authService.hasAnyUsers();
      } catch (_) {}
      if (!mounted || !has || _mode != _Mode.waitUsers) return;
      _stopWaiting();
      setState(() {
        _mode = _Mode.login;
        _info = 'وصلت حسابات المستخدمين من الجهاز الرئيسي — ادخل باسمك وكلمة سرك.';
      });
    }

    _waitTimer = Timer.periodic(const Duration(seconds: 3), (_) => check());
    _waitSub = UsersSyncService.instance.changes.listen((_) => check());
  }

  void _stopWaiting() {
    _lanTimer?.cancel();
    _lanTimer = null;
    _waitTimer?.cancel();
    _waitTimer = null;
    _waitSub?.cancel();
    _waitSub = null;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _proofController.dispose();
    _stopWaiting();
    super.dispose();
  }

  // ─────────────────────────── الدخول ───────────────────────────

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final user = await _authService.login(_usernameController.text.trim(), _passwordController.text);
    if (!mounted) return;
    if (user != null) {
      Navigator.pushReplacementNamed(context, '/main');
    } else {
      final typed = _usernameController.text.trim();
      final exists = _names.any((n) => n.toLowerCase() == typed.toLowerCase());
      final licAccount = _license.payload?.account ?? '';
      setState(() {
        _isLoading = false;
        if (exists) {
          _errorMessage = 'كلمة السر غير صحيحة.\n'
              'إن كنت المدير ونسيتها: اضغط «نسيت كلمة السر؟» واكتب كلمة سر حساب الترخيص.';
        } else {
          _errorMessage = 'لا يوجد مستخدم باسم «$typed» في هذا البرنامج.\n'
              '${licAccount.isNotEmpty && typed.toLowerCase() == licAccount.toLowerCase() || _names.isNotEmpty ? 'تذكّر: حساب الترخيص (من أداة الأدمن) يفعّل الجهاز فقط، وليس حساب دخول. ' : ''}'
              '${_names.isNotEmpty ? 'اختر اسمك من الأسماء تحت الخانة.' : ''}';
        }
      });
    }
  }

  // ─────────────────────────── إنشاء المدير ───────────────────────────

  Future<void> _createAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // بعد تفعيل الترخيص مباشرةً (في هذه الجلسة) أثبت صاحبه ملكيته للتو.
    // غير ذلك (فرغ جدول المستخدمين لاحقاً لأي سبب): إثبات الملكية أولاً.
    if (!LicenseService.activatedThisSession) {
      final ok = await _proveLicenseOwnership();
      if (ok != true || !mounted) return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    await _finishAdmin(username, password);
  }

  /// 🔑 إثبات ملكية الترخيص: كلمة سر حساب الترخيص المفعَّل على هذا الجهاز
  /// (يتحقق منها السيرفر — يحتاج إنترنت).
  Future<bool?> _proveLicenseOwnership() {
    _proofController.clear();
    String? err;
    bool busy = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> submit() async {
            final secret = _proofController.text;
            if (secret.isEmpty) {
              setD(() => err = 'اكتب كلمة سر حساب الترخيص');
              return;
            }
            setD(() {
              busy = true;
              err = null;
            });
            final c = await _license.checkAccountPassword(secret);
            if (!ctx.mounted) return;
            switch (c.status) {
              case LicensePasswordStatus.ok:
                Navigator.pop(ctx, true);
                return;
              case LicensePasswordStatus.offline:
                setD(() {
                  busy = false;
                  err = 'لا يوجد إنترنت للتحقق من كلمة سر الترخيص. صِل الإنترنت ثم أعد المحاولة.';
                });
                return;
              case LicensePasswordStatus.wrong:
              case LicensePasswordStatus.noLicense:
                setD(() {
                  busy = false;
                  err = 'كلمة السر غير صحيحة';
                });
                return;
              case LicensePasswordStatus.rejected:
                setD(() {
                  busy = false;
                  err = c.message ?? 'رفض سيرفر التراخيص الطلب';
                });
                return;
            }
          }

          final lic = _license.getStoredLicense();
          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.verified_user_outlined, color: Color(0xFF0F3460)),
              SizedBox(width: 8),
              Text('إثبات ملكية الترخيص'),
            ]),
            content: SizedBox(
              width: 400,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'لا يوجد أي مستخدم على هذا الجهاز. لإنشاء حساب مدير جديد اكتب كلمة سر '
                  'حساب الترخيص${lic != null ? ' «${lic.username}»' : ''} (نتحقق منها عبر الإنترنت).',
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _proofController,
                  obscureText: true,
                  autofocus: true,
                  enabled: !busy,
                  onSubmitted: (_) => busy ? null : submit(),
                  decoration: InputDecoration(
                    labelText: 'كلمة سر حساب الترخيص',
                    prefixIcon: const Icon(Icons.key),
                    errorText: err,
                    errorMaxLines: 3,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('تحقّق'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _finishAdmin(String username, String password) async {
    final created = await _authService.createAdmin(username, password);
    if (!mounted) return;
    if (created == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذّر إنشاء حساب المدير';
      });
      return;
    }
    await _authService.login(username, password);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('تم إنشاء حساب المدير. أضف موظفيك من: الإعدادات ← الموظفون والصلاحيات'),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 5),
    ));
    Navigator.pushReplacementNamed(context, '/main');
  }

  // ─────────────────────────── نسيت كلمة السر ───────────────────────────

  Future<void> _showForgotPasswordDialog() async {
    final admin0 = await _authService.adminUser();
    if (!mounted) return;
    final typed = _usernameController.text.trim();
    final usernameController = TextEditingController(
        text: _names.any((n) => n == typed) ? typed : (admin0?.username ?? typed));
    final recoveryController = TextEditingController();
    final newPasswordController = TextEditingController();
    String? err;
    bool busy = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.lock_reset, color: Colors.orange),
            SizedBox(width: 8),
            Text('استعادة كلمة السر'),
          ]),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                '• المدير: اكتب كلمة سر حساب الترخيص (نتحقق منها عبر الإنترنت).\n'
                '• الموظف: يطلب من المدير تغيير كلمة سره من شاشة الموظفين.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: 'اسم المستخدم',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: recoveryController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'كلمة سر حساب الترخيص',
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'كلمة السر الجديدة',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: err,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final user = usernameController.text.trim();
                      final rec = recoveryController.text;
                      final np = newPasswordController.text;
                      if (user.isEmpty || rec.isEmpty || np.isEmpty) {
                        setD(() => err = 'املأ الحقول الثلاثة');
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      var allowed = false;
                      final admin = await _authService.adminUser();
                      if (admin != null && admin.username == user) {
                        final c = await _license.checkAccountPassword(rec);
                        allowed = c.status == LicensePasswordStatus.ok;
                        if (c.status == LicensePasswordStatus.offline) {
                          setD(() {
                            busy = false;
                            err = 'لا يوجد إنترنت للتحقق من كلمة سر الترخيص';
                          });
                          return;
                        }
                        if (c.status == LicensePasswordStatus.rejected || c.status == LicensePasswordStatus.noLicense) {
                          setD(() {
                            busy = false;
                            err = c.message ?? 'الترخيص على هذا الجهاز غير صالح الآن — فعّله من «الترخيص» ثم أعد المحاولة';
                          });
                          return;
                        }
                      }
                      if (!allowed) {
                        setD(() {
                          busy = false;
                          err = admin != null && admin.username != user
                              ? 'الاستعادة للمدير فقط (${admin.username}). الموظف يطلب من المدير تغيير كلمة سره.'
                              : 'كلمة سر حساب الترخيص غير صحيحة';
                        });
                        return;
                      }
                      final ok = await _authService.resetPassword(user, np);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'تم تغيير كلمة السر — ادخل بالكلمة الجديدة' : 'اسم المستخدم غير موجود'),
                        backgroundColor: ok ? Colors.green : Colors.red,
                      ));
                    },
              child: const Text('تغيير كلمة السر'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── الوضع التجريبي ───────────────────────────

  void _enterDemo() {
    _authService.loginDemo();
    Navigator.pushReplacementNamed(context, '/main');
  }

  Future<void> _switchDemo({required bool enable, required String message, bool regenerate = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الوضع التجريبي'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة وإغلاق البرنامج')),
        ],
      ),
    );
    if (ok != true) return;
    await DemoMode.setForNextLaunch(enable);
    if (regenerate) await DemoMode.requestRegenerate();
    exit(0);
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [_navyDark, _navy, Color(0xFF16508A)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Builder(builder: (context) {
              final wide = MediaQuery.of(context).size.width >= 820;
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 860 : 440),
                child: Material(
                  color: Colors.white,
                  elevation: 12,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide) SizedBox(width: 340, child: _brandPanel()),
                        Expanded(child: Padding(padding: const EdgeInsets.all(32), child: _formPanel())),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _brandPanel() {
    final lic = _license.getStoredLicense();
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_navyDark, _navy]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.storefront_rounded, color: _accent, size: 44),
          const SizedBox(height: 12),
          const Text('الناصر',
              style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const Text('المبيعات • الديون • المخزون • المحاسبة',
              style: TextStyle(color: Color(0xFFB8C4DA), fontSize: 13)),
          const SizedBox(height: 28),
          _bullet(Icons.verified_user_outlined, 'كل موظف يدخل باسمه وكلمة سره'),
          _bullet(Icons.tune, 'يرى ما تسمح به صلاحياته فقط'),
          _bullet(Icons.history, 'كل عملية تُسجَّل باسم من قام بها'),
          const Spacer(),
          if (lic != null) ...[
            const Divider(color: Colors.white24),
            Text('الترخيص: ${lic.username}${lic.isMainDevice ? '' : ' (جهاز إضافي)'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (lic.isLifetime)
              const Text('الترخيص: دائم — بلا تاريخ انتهاء', style: TextStyle(color: Colors.white54, fontSize: 12))
            else if (lic.expires.length >= 10)
              Text('صالح حتى: ${lic.expires.substring(0, 10)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _bullet(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(i, color: _accent, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 13.5))),
        ]),
      );

  Widget _formPanel() {
    switch (_mode) {
      case _Mode.loading:
        return const SizedBox(height: 320, child: Center(child: CircularProgressIndicator()));
      case _Mode.demo:
        return _demoPanel();
      case _Mode.waitUsers:
        return _waitUsersPanel();
      case _Mode.setupAdmin:
      case _Mode.login:
        return _credentialsForm();
    }
  }

  /// ⭐ جهاز إضافي ينتظر الجهاز الرئيسي: لا «إنشاء مدير». يبحث عن حاسبة السيرفر
  /// وحده، وبعد عدة محاولات فاشلة فقط يظهر سبب محتمل وإدخال العنوان يدوياً.
  Widget _waitUsersPanel() {
    final stuck = _lanTries >= 3 && !_syncMode;
    final syncStuck = _syncMode && !_syncReady && _lanTries >= 3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('جهاز إضافي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _navy)),
        const SizedBox(height: 8),
        Text(
          'هذا الجهاز مضاف إلى ترخيص المحل. حسابات الموظفين تأتي من الجهاز الرئيسي تلقائياً، '
          'ثم تدخل باسمك وكلمة سرك كما أنشأها المدير. لا تحتاج أن تفعل شيئاً.',
          style: TextStyle(color: Colors.grey[700], height: 1.6),
        ),
        const SizedBox(height: 20),
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _navy.withValues(alpha: 0.12)),
            ),
            child: Row(children: [
              const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: _accent)),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _lanStatus,
                    key: ValueKey(_lanStatus),
                    style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, height: 1.5),
                  ),
                ),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: !stuck
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('تأكد من ثلاثة أشياء:',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                      const SizedBox(height: 6),
                      Text(
                        '• البرنامج مفتوح على حاسبة السيرفر.\n'
                        '• هذا الجهاز على شبكة الواي فاي نفسها (لا شبكة الضيوف).\n'
                        '• جدار الحماية في الحاسبة يسمح بالبرنامج (يضبطه المثبّت تلقائياً).',
                        style: TextStyle(color: Colors.amber.shade900, height: 1.6),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _openManualLan,
                          icon: const Icon(Icons.lan_outlined, size: 18),
                          label: const Text('أدخل عنوان الحاسبة يدوياً'),
                        ),
                      ),
                    ]),
                  ),
                ),
        ),
        if (syncStuck)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Text(
                'تأكد من شيئين:\n'
                '• هذا الجهاز متصل بالإنترنت (أي شبكة، لا يلزم أن تكون شبكة المحل).\n'
                '• المزامنة مضبوطة على الجهاز الرئيسي (الإعدادات ← المزامنة) وفُتح وهو متصل بالإنترنت.',
                style: TextStyle(color: Colors.amber.shade900, height: 1.6),
              ),
            ),
          ),
        if (_syncReady)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: FilledButton.icon(
              onPressed: LanRuntime.relaunch,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(!kIsWeb && Platform.isWindows
                  ? 'إعادة تشغيل البرنامج الآن'
                  : 'إغلاق البرنامج الآن — ثم افتحه من جديد'),
            ),
          ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: _activateOtherAccount,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('تفعيل بحساب آخر (جهاز مستقل لشخص آخر)'),
        ),
      ],
    );
  }

  Future<void> _openManualLan() async {
    _stopWaiting();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NetworkSettingsScreen()));
    await _resumeWaiting();
  }

  /// رجع المستخدم من شاشة أخرى بلا نتيجة ⇒ يكمل الانتظار والبحث كما كان.
  Future<void> _resumeWaiting() async {
    if (!mounted || _mode != _Mode.waitUsers || _lanTimer != null) return;
    final l = _license.getStoredLicense();
    var viaSync = false;
    try {
      viaSync = l != null && l.isSyncAllowed && await FirebaseCustomConfig.isCustomConfigured();
    } catch (_) {}
    if (!mounted || _mode != _Mode.waitUsers) return;
    if (viaSync) _startWaitingForUsers();
    _startSearchingLan(syncAllowed: l?.isSyncAllowed ?? false, viaSync: viaSync);
  }

  Widget _credentialsForm() {
    final setup = _mode == _Mode.setupAdmin;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(setup ? 'إنشاء حساب المدير' : 'تسجيل الدخول',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _navy)),
          const SizedBox(height: 6),
          Text(
            setup
                ? 'أنشئ حساب مدير البرنامج على هذا الجهاز: اختر أي اسم وكلمة سر. '
                    'هذا حساب الدخول اليومي، ومنفصل تماماً عن حساب الترخيص. '
                    'بعدها تضيف موظفيك من: الإعدادات ← الموظفون والصلاحيات.'
                : 'أدخل اسم المستخدم وكلمة السر للمتابعة.',
            style: TextStyle(color: Colors.grey[700], height: 1.5),
          ),
          const SizedBox(height: 24),
          if (_info != null && !setup)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(_info!, style: TextStyle(color: Colors.green[900]))),
              ]),
            ),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
              ]),
            ),
          TextFormField(
            controller: _usernameController,
            autofocus: setup || _usernameController.text.isEmpty,
            decoration: InputDecoration(
              labelText: setup ? 'اسم المدير (تختاره أنت)' : 'اسم المستخدم',
              prefixIcon: Icon(setup ? Icons.admin_panel_settings_outlined : Icons.person_outline),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'أدخل اسم المستخدم' : null,
          ),
          if (!setup && _names.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('المستخدمون:', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              for (final n in _names.take(12))
                ActionChip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text(n),
                  onPressed: () => setState(() {
                    _usernameController.text = n;
                    _passwordController.clear();
                    _errorMessage = null;
                  }),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: !setup && _usernameController.text.isNotEmpty,
            decoration: InputDecoration(
              labelText: setup ? 'كلمة سر المدير' : 'كلمة السر',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return 'أدخل كلمة السر';
              if (setup && val.length < 4) return 'كلمة السر 4 أحرف على الأقل';
              return null;
            },
            onFieldSubmitted: (_) => setup ? null : _login(),
          ),
          if (setup) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة السر',
                prefixIcon: const Icon(Icons.lock_reset),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (val) => val != _passwordController.text ? 'كلمتا السر غير متطابقتين' : null,
              onFieldSubmitted: (_) => _createAdmin(),
            ),
          ],
          if (!setup)
            Row(children: [
              Expanded(
                child: CheckboxListTile(
                  value: _stay,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('ابقَ مسجلاً للدخول على هذا الجهاز'),
                  onChanged: (v) {
                    setState(() => _stay = v ?? true);
                    _authService.setStayLoggedIn(_stay);
                  },
                ),
              ),
              TextButton(
                onPressed: _showForgotPasswordDialog,
                child: const Text('نسيت كلمة السر؟'),
              ),
            ])
          else
            const SizedBox(height: 16),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : (setup ? _createAdmin : _login),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(setup ? 'أنشئ حساب المدير' : 'دخول',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          // 🔐 الخروج يخرج من حساب المستخدم فقط؛ الترخيص لا يُغيَّر من هنا بعد
          //    إنشاء المدير — تصفيره ونقله من الإعدادات ← الحسابات والموظفين فقط.
          // ⭐ الترخيص من هنا: «تفعيل بحساب آخر» فقط (جهاز مستقل لشخص آخر).
          //    إضافة جهاز برمز تتم من شاشة التفعيل الأولى، والربط بحاسبة السيرفر تلقائي.
          if (setup)
            TextButton.icon(
              onPressed: _activateOtherAccount,
              icon: const Icon(Icons.swap_horiz_rounded, color: _navy),
              label: const Text('تفعيل بحساب آخر', style: TextStyle(color: _navy)),
            ),
          // 🧪 زر «تجربة البرنامج ببيانات وهمية» أُزيل بطلب المالك. لوحة الوضع
          //    التجريبي (_demoPanel) باقية فقط ليخرج منها من دخله سابقاً.
        ],
      ),
    );
  }

  Widget _demoPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(Icons.science_outlined, color: Colors.orange, size: 30),
          const SizedBox(width: 8),
          Text('الوضع التجريبي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
        ]),
        const SizedBox(height: 8),
        Text(
          'أنت على قاعدة البيانات التجريبية: بيانات وهمية لسنة كاملة للتجربة والتدريب. '
          'قاعدتك الحقيقية محفوظة كما هي ولا تُلمس.',
          style: TextStyle(color: Colors.grey[700], height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            onPressed: _enterDemo,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('دخول للتجربة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _switchDemo(
            enable: false,
            message: 'سيُغلق البرنامج الآن. افتحه من جديد لتعود إلى بياناتك الحقيقية.',
          ),
          icon: const Icon(Icons.exit_to_app, color: Colors.green),
          label: const Text('العودة إلى البيانات الحقيقية'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _switchDemo(
            enable: true,
            regenerate: true,
            message: 'سيُغلق البرنامج الآن. عند فتحه تُحذف البيانات التجريبية فقط وتُنشأ من جديد.',
          ),
          icon: const Icon(Icons.restart_alt, color: Colors.red),
          label: const Text('إعادة البيانات التجريبية من الصفر', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}
