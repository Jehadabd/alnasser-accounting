// license_screen.dart
//
// 🔐 تفعيل البرنامج على هذا الجهاز (نظام الترخيص 4):
//   • الجهاز الرئيسي: حساب الترخيص الذي نعطيه للعميل (مرة واحدة).
//   • جهاز إضافي: رمز يولّده الجهاز الرئيسي (الإعدادات ← أجهزة الترخيص).
// حساب الترخيص منفصل عن حسابات الدخول اليومية (المدير والموظفين): بعد التفعيل
// تفتح شاشة الدخول، وفيها «إنشاء حساب المدير» إن لم يوجد مستخدمون.

import 'dart:io' show Platform, Process, ProcessStartMode, exit;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../lan/lan_bootstrap.dart';
import '../lan/lan_settings.dart';
import '../services/license_service.dart';
import '../services/seat_service.dart';

Future<void> openSupportWhatsApp() async {
  try {
    await launchUrl(Uri.parse(LicenseConfig.whatsappUrl), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  static const _navy = Color(0xFF0F3460);

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _licenseService = LicenseService();

  int _mode = 0; // 0: حساب الترخيص (رئيسي)، 1: رمز جهاز إضافي
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _recovering = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final p = _licenseService.payload;
    if (p != null) {
      _usernameController.text = p.account;
      if (!p.isMain) _mode = 1;
    } else {
      // 🔎 هذا الحاسوب مفعّل مسبقاً؟ (إعادة تثبيت/نسخة أخرى) — يفتح بلا اسم ولا كلمة سر
      _recovering = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryRecover());
    }
  }

  Future<void> _tryRecover() async {
    final r = await _licenseService.recoverByFingerprint();
    if (!mounted) return;
    if (r.success && _licenseService.isLicenseActivated()) {
      if (LicenseService.syncLinkApplied) {
        await _restartForSync();
        return;
      }
      _goIn();
      return;
    }
    setState(() {
      _recovering = false;
      if (r.error == 'EXPIRED' || r.error == 'SUSPENDED') _errorMessage = r.message;
    });
  }

  Widget _recoveringView() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF020F2B), _navy, Color(0xFF16508A)],
          ),
        ),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 18),
                Text('جارٍ التعرّف على هذا الجهاز...', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text('إن كان مفعّلاً من قبل يفتح البرنامج مباشرة', style: TextStyle(color: Colors.black54)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit({bool move = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final result = _mode == 0
        ? await _licenseService.activateLicense(_usernameController.text, _passwordController.text, move: move)
        : await _licenseService.redeemPairCode(_codeController.text);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      final sync = _licenseService.payload?.syncAllowed == true;
      // 1) جهاز إضافي على شبكة حاسبة السيرفر ⇒ يرتبط بها وحده فوراً (طرفية على
      //    قاعدتها مباشرة) — بلا أي سؤال. هذا يسبق المزامنة: نفس المحل = نفس القاعدة.
      if (_mode == 1 && await _autoJoinLan(keepSearching: !sync)) return;
      // 2) لا سيرفر على هذه الشبكة (فرع/محافظة أخرى) + حساب مزامنة ⇒ عبر الإنترنت
      if (LicenseService.syncLinkApplied) {
        await _restartForSync();
        return;
      }
      if (_mode == 1 && sync) {
        await _syncNotReadyYet();
        _goIn();
        return;
      }
      _goIn();
      return;
    }
    if (result.error == 'MAIN_BOUND_ELSEWHERE') {
      await _mainBoundElsewhere(result);
      return;
    }
    setState(() => _errorMessage = result.message ?? 'حدث خطأ غير معروف');
  }

  /// 🖧 جهاز إضافي: يرتبط وحده بحاسبة السيرفر في شبكة المحل (بترخيصه، بلا رمز ربط)،
  /// فيعمل على بياناتها وموظفيها مباشرة.
  /// [keepSearching]: حساب بلا مزامنة — إن لم يجد السيرفر الآن يبقى يبحث عنه عند
  /// كل تشغيل. حساب مزامنة: إن لم يجده يُرجع false فيتصل عبر الإنترنت.
  Future<bool> _autoJoinLan({required bool keepSearching}) async {
    if (kIsWeb) return false;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    LanSettings? joined;
    try {
      joined = await LanRuntime.autoJoin();
    } catch (_) {}
    if (!mounted) return false;
    setState(() => _isLoading = false);
    if (joined == null && !keepSearching) return false;
    if (joined == null) {
      // 🔁 لا سؤال «طرفية أم لا»: الجهاز الإضافي يبقى يبحث عن حاسبة السيرفر عند كل
      // تشغيل ويتصل وحده حين تظهر (مثل الواي فاي المحفوظ)
      await LanRuntime.markPendingJoin();
      if (!mounted) return true;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('✅ أُضيف هذا الجهاز'),
          content: const Text(
            'لم أجد حاسبة السيرفر على هذه الشبكة الآن.\n'
            'سيبقى هذا الجهاز يبحث عنها ويتصل وحده حين تظهر — شغّل البرنامج على حاسبة السيرفر '
            'وتأكد أن الجهازين على نفس الشبكة.',
            style: TextStyle(height: 1.6),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );
      await LanRuntime.relaunch();
      return true;
    }
    final j = joined;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('✅ أُضيف هذا الجهاز وارتبط بحاسبة المحل'),
        content: Text(
          'ارتبط بحاسبة السيرفر «${j.serverName}» (${j.host}).\n'
          'سيُغلق البرنامج الآن. افتحه من جديد، ثم ادخل باسم الموظف وكلمة سره '
          'كما أنشأها المدير على الحاسبة.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
    if (!kIsWeb && Platform.isWindows) {
      try {
        await Process.start(Platform.resolvedExecutable, SeatService.relaunchArgs, mode: ProcessStartMode.detached);
      } catch (_) {}
    }
    exit(0);
  }

  /// حساب مزامنة، لكن ربط Firebase لم يُحفظ في حساب الترخيص بعد
  Future<void> _syncNotReadyYet() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('✅ أُضيف هذا الجهاز'),
        content: const Text(
          'هذا الحساب يشمل المزامنة عبر الإنترنت، لكن إعداد المزامنة لم يصل بعد.\n\n'
          '• افتح البرنامج على الجهاز الرئيسي وهو متصل بالإنترنت: يرسل إعداده تلقائياً.\n'
          '• أو اطلب من الدعم ضبط المزامنة لحسابك.\n\n'
          'عند وصوله يتصل هذا الجهاز وحده (من أي مكان، لا يلزم أن يكون على شبكة المحل) '
          'ويطلب منك إعادة تشغيل البرنامج مرة واحدة.',
          style: TextStyle(height: 1.6),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('متابعة'))],
      ),
    );
  }

  /// جهاز إضافي وصل معه ربط المزامنة: إعادة تشغيل ليتصل ويجلب البيانات والموظفين
  Future<void> _restartForSync() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('✅ أُضيف هذا الجهاز'),
        content: const Text(
          'وصل ربط المزامنة من حساب الترخيص (يعمل عبر الإنترنت من أي مكان).\n'
          'سيُعاد تشغيل البرنامج الآن ليتصل ويجلب بيانات المحل وحسابات الموظفين، '
          'ثم ادخل باسم المستخدم الذي أنشأه لك المدير.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إعادة التشغيل')),
        ],
      ),
    );
    if (!kIsWeb && Platform.isWindows) {
      try {
        await Process.start(Platform.resolvedExecutable, SeatService.relaunchArgs, mode: ProcessStartMode.detached);
        exit(0);
      } catch (_) {}
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // الهاتف لا يعيد تشغيل نفسه: نغلقه، ويفتحه المستخدم فيتصل بالمزامنة
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            content: const Text('سيُغلق البرنامج الآن. افتحه من جديد ليتصل ويجلب البيانات والموظفين.',
                style: TextStyle(height: 1.6)),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
          ),
        );
      }
      exit(0);
    }
    if (mounted) _goIn();
  }

  void _goIn() {
    Navigator.of(context).pushNamedAndRemoveUntil('/license_check', (r) => false);
  }

  Future<void> _mainBoundElsewhere(LicenseResult r) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الحساب مفعّل على حاسبة رئيسية أخرى'),
        content: Text(
          'حساب الترخيص هذا مربوط بحاسبة رئيسية أخرى${r.mainDeviceName != null ? ' (اسمها: ${r.mainDeviceName})' : ''}، '
          'وهذه الحاسبة ليست هي (القطع الداخلية مختلفة).\n\n'
          '• لإضافة هذا الجهاز كجهاز إضافي: اطلب «رمز إضافة جهاز» من الجهاز الرئيسي.\n'
          '• لنقل الترخيص إلى هنا: من الحاسبة الرئيسية ادخل الإعدادات ← الحسابات والموظفون ← '
          '«تصفير الترخيص ونقل الحساب»، ثم سجّل الدخول هنا.\n'
          '• إن تعطّلت الحاسبة الرئيسية أو ضاعت: تواصل معنا ${LicenseConfig.supportPhone}',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'code'), child: const Text('عندي رمز إضافة')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'code') {
      setState(() {
        _mode = 1;
        _errorMessage = null;
      });
    }
  }

  Future<void> _checkRenewal() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final r = await _licenseService.refreshNow();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (r.success && _licenseService.isLicenseActivated()) {
      _goIn();
    } else {
      setState(() => _errorMessage = r.success
          ? (LicenseService.blockMessage ?? 'لم يُجدَّد الترخيص بعد')
          : (r.message ?? 'تعذّر التحقق'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_recovering) return _recoveringView();
    final block = LicenseService.blockMessage;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF020F2B), _navy, Color(0xFF16508A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.verified_user, size: 56, color: _navy),
                          const SizedBox(height: 12),
                          const Text('تفعيل البرنامج على هذا الجهاز',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _navy)),
                          const SizedBox(height: 18),
                          if (block != null) _blockBanner(block),
                          if (_licenseService.isLicenseActivated())
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Text(
                                'هذا الجهاز مفعّل الآن بحساب «${_licenseService.payload?.account ?? ''}». '
                                'التفعيل هنا بحساب آخر، أو بإضافته برمز من جهاز رئيسي، يستبدل ترخيصه الحالي. '
                                'بيانات البرنامج والموظفين لا تتغير.',
                                style: TextStyle(color: Colors.blue.shade900, height: 1.5),
                              ),
                            ),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 0, icon: Icon(Icons.vpn_key), label: Text('الجهاز الرئيسي')),
                              ButtonSegment(value: 1, icon: Icon(Icons.add_to_queue), label: Text('جهاز إضافي')),
                            ],
                            selected: {_mode},
                            onSelectionChanged: _isLoading
                                ? null
                                : (s) => setState(() {
                                      _mode = s.first;
                                      _errorMessage = null;
                                    }),
                          ),
                          const SizedBox(height: 16),
                          if (_mode == 0) ..._accountFields() else ..._codeFields(),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade800, height: 1.5)),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _navy,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isLoading ? null : () => _submit(),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(_mode == 0 ? 'تفعيل' : 'إضافة هذا الجهاز',
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          if (Navigator.of(context).canPop())
                            TextButton.icon(
                              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('رجوع'),
                            ),
                          const SizedBox(height: 18),
                          const Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'للحصول على ترخيص أو تجديده أو إضافة أجهزة:\nواتساب / اتصال ${LicenseConfig.supportPhone}',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.5),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: openSupportWhatsApp,
                                icon: const Icon(Icons.chat, color: Colors.green),
                                label: const Text('واتساب'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message, style: const TextStyle(height: 1.6, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_licenseService.hasStoredToken)
                FilledButton.icon(
                  onPressed: _isLoading ? null : _checkRenewal,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحقق من التجديد'),
                ),
              OutlinedButton.icon(
                onPressed: openSupportWhatsApp,
                icon: const Icon(Icons.chat, color: Colors.green),
                label: const Text('واتساب ${LicenseConfig.supportPhone}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _accountFields() => [
        Text(
          'اكتب حساب الترخيص الذي تسلّمته من الناصر. يُكتب مرة واحدة في الجهاز الرئيسي، '
          'وهو منفصل عن حسابات الدخول اليومية (المدير والموظفين).',
          style: TextStyle(color: Colors.grey.shade700, height: 1.6),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _usernameController,
          textDirection: TextDirection.ltr,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: 'اسم حساب الترخيص',
            prefixIcon: const Icon(Icons.verified_user_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم حساب الترخيص' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _passwordController,
          textDirection: TextDirection.ltr,
          obscureText: _obscurePassword,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: 'كلمة سر الترخيص',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (v) => v == null || v.isEmpty ? 'أدخل كلمة سر الترخيص' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ];

  List<Widget> _codeFields() => [
        Text(
          'في الجهاز الرئيسي: الإعدادات ← الحساب والموظفون ← الترخيص والأجهزة ← «إضافة جهاز»، '
          'ثم اكتب الرمز الذي يظهر هناك (صالح 10 دقائق).',
          style: TextStyle(color: Colors.grey.shade700, height: 1.6),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _codeController,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          enabled: !_isLoading,
          style: const TextStyle(fontSize: 26, letterSpacing: 4, fontWeight: FontWeight.bold),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
            LengthLimitingTextInputFormatter(9),
            TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
          ],
          decoration: InputDecoration(
            hintText: 'ABCD-2345',
            labelText: 'رمز إضافة الجهاز',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (v) {
            final c = (v ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
            return c.length == 8 ? null : 'الرمز 8 خانات (مثل ABCD-2345)';
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ];
}

/// شاشة فحص الترخيص عند كل تشغيل
class LicenseCheckScreen extends StatefulWidget {
  const LicenseCheckScreen({super.key});

  @override
  State<LicenseCheckScreen> createState() => _LicenseCheckScreenState();
}

class _LicenseCheckScreenState extends State<LicenseCheckScreen> {
  final _licenseService = LicenseService();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _performCheck();
  }

  Future<void> _performCheck() async {
    try {
      final result = await _licenseService.performStartupCheck();
      if (!mounted) return;
      if (result.canProceed) {
        if (result.showWarning && result.warningMessage != null) {
          await _showWarningDialog(result.warningMessage!, grace: result.isGracePeriod);
          if (!mounted) return;
        }
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      if (result.reason == StartupBlockReason.clockTampering) {
        setState(() => _errorMessage = result.message ?? 'تاريخ الجهاز غير صحيح');
        return;
      }
      Navigator.of(context).pushReplacementNamed('/license');
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'حدث خطأ: $e');
    }
  }

  Future<void> _showWarningDialog(String message, {required bool grace}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(grace ? Icons.error_outline : Icons.warning_amber, color: grace ? Colors.red : Colors.orange, size: 28),
          const SizedBox(width: 8),
          Text(grace ? 'انتهى الاشتراك' : 'تنبيه الاشتراك'),
        ]),
        content: Text(message, style: const TextStyle(height: 1.6)),
        actions: [
          TextButton.icon(
            onPressed: openSupportWhatsApp,
            icon: const Icon(Icons.chat, color: Colors.green),
            label: const Text('تواصل واتساب'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('فهمت')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF020F2B), Color(0xFF0F3460)],
          ),
        ),
        child: Center(
          child: _errorMessage == null
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    SizedBox(height: 24),
                    Text('جارٍ التحقق من الترخيص...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.event_busy, size: 56, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(height: 1.6)),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() => _errorMessage = null);
                              _performCheck();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
