import 'dart:convert';
import 'dart:io' show Platform, Process, ProcessStartMode, exit;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fauth;
import '../services/firebase_sync/firebase_custom_config.dart';
import '../services/sync/sync_security.dart';
import '../services/license_service.dart';
import '../widgets/settings_kit.dart';
import '../widgets/setup_guide.dart'; // 🧭 الشرح خطوة بخطوة
import '../services/seat_service.dart';

class FirebaseCustomSetupScreen extends StatefulWidget {
  const FirebaseCustomSetupScreen({super.key});

  @override
  State<FirebaseCustomSetupScreen> createState() => _FirebaseCustomSetupScreenState();
}

class _FirebaseCustomSetupScreenState extends State<FirebaseCustomSetupScreen> {
  int _currentStep = 0;
  
  final _apiKeyController = TextEditingController();
  final _appIdController = TextEditingController();
  final _projectIdController = TextEditingController();
  final _messagingSenderIdController = TextEditingController();
  final _encryptionSecretController = TextEditingController();
  
  bool _isTesting = false;
  String _testResult = '';
  bool _savedNeedsRestart = false;
  static bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  Color _testResultColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final options = await FirebaseCustomConfig.getCustomOptions();
    if (options != null && mounted) {
      // setState: كانت الحقول تُملأ بلا إعادة بناء فلا تظهر الروابط السريعة حتى أول كتابة.
      setState(() {
        _apiKeyController.text = options.apiKey;
        _appIdController.text = options.appId;
        _projectIdController.text = options.projectId;
        _messagingSenderIdController.text = options.messagingSenderId;
        // مشروع مربوط مسبقاً → نفتح مباشرة على خطوة الإعدادات (للتعديل أو إعادة الاختبار).
        if (options.projectId.isNotEmpty) _currentStep = 4;
      });
    }
  }

  void _parseFirebaseConfig(String configStr) {
    String extractValue(String key) {
      final regex = RegExp('[\'"]?$key[\'"]?\\s*:\\s*[\'"]([^\'"]+)[\'"]');
      final match = regex.firstMatch(configStr);
      return match?.group(1) ?? '';
    }

    final apiKey = extractValue('apiKey');
    final appId = extractValue('appId');
    final projectId = extractValue('projectId');
    final messagingSenderId = extractValue('messagingSenderId');
    final encryptionSecret = extractValue('encryptionSecret');

    setState(() {
      if (apiKey.isNotEmpty) _apiKeyController.text = apiKey;
      if (appId.isNotEmpty) _appIdController.text = appId;
      if (projectId.isNotEmpty) _projectIdController.text = projectId;
      if (messagingSenderId.isNotEmpty) _messagingSenderIdController.text = messagingSenderId;
      if (encryptionSecret.isNotEmpty) _encryptionSecretController.text = encryptionSecret;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _appIdController.dispose();
    _projectIdController.dispose();
    _messagingSenderIdController.dispose();
    _encryptionSecretController.dispose();
    super.dispose();
  }

  Future<void> _testAndSaveConnection() async {
    final apiKey = _apiKeyController.text.trim();
    final appId = _appIdController.text.trim();
    final projectId = _projectIdController.text.trim();
    final messagingSenderId = _messagingSenderIdController.text.trim();
    final encryptionSecret = _encryptionSecretController.text.trim();

    if (apiKey.isEmpty || appId.isEmpty || projectId.isEmpty) {
      setState(() {
        _testResult = '❌ يرجى تعبئة جميع الحقول الأساسية (API Key, App ID, Project ID)';
        _testResultColor = Colors.red;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = 'جاري اختبار الاتصال...';
      _testResultColor = Colors.blue;
    });

    try {
      // محاولة التهيئة بتطبيق ثانوي لاختبار الإعدادات
      final options = FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        projectId: projectId,
        messagingSenderId: messagingSenderId.isEmpty ? '000000000000' : messagingSenderId,
      );

      // التأكد من عدم وجود تطبيق اختبار مسبق
      FirebaseApp? app;
      try {
        app = Firebase.app();
      } catch (e) {
        // لا يوجد تطبيق افتراضي بعد
      }

      if (app == null) {
        // بما أنه لا يوجد تطبيق افتراضي، نهيئه كتطبيق افتراضي لتجنب أخطاء مكتبات C++ على ويندوز
        app = await Firebase.initializeApp(options: options);
      } else {
        // إذا كان هناك تطبيق افتراضي، نهيئ تطبيق ثانوي باسم فريد لتجنب الحاجة لحذفه
        // حذف التطبيقات يسبب خطأ FirebaseApp was deleted في التطبيق الافتراضي بسبب ثغرة في FlutterFire
        final uniqueName = 'test_conn_${DateTime.now().millisecondsSinceEpoch}';
        app = await Firebase.initializeApp(
          name: uniqueName,
          options: options,
        );
      }

      // 🔍 اختبار فعلي لقاعدة البيانات: تهيئة Firebase وحدها لا تكفي،
      // فقد تنجح بينما ترفض قواعد الأمان (Firestore Rules) كل القراءة/الكتابة.
      // نختبر: (1) تسجيل دخول مجهول، (2) قراءة فعلية من Firestore.
      // 💾 الحفظ أولاً (بعد نجاح التهيئة): إن انهار اختبار القراءة على ويندوز
      // تبقى الإعدادات محفوظة، وتعمل المزامنة بعد إعادة التشغيل.
      await FirebaseCustomConfig.saveCustomConfig(
        apiKey: options.apiKey,
        appId: options.appId,
        projectId: options.projectId,
        messagingSenderId: options.messagingSenderId,
      );
      if (encryptionSecret.isNotEmpty) {
        await SyncSecurity.saveSecretKey(encryptionSecret);
      }
      // 🔄 الجهاز الرئيسي: يُحفظ الربط في حساب الترخيص فتتصل كل الأجهزة الإضافية
      //    (في أي فرع أو محافظة) عبر الإنترنت وحدها
      await LicenseService().pushSyncLink();

      String diagMessage = '';
      debugPrint('🧪 [اختبار الاتصال] ═══════════════════════════════════');
      debugPrint('🧪 [1/3] تم تهيئة Firebase App بنجاح');
      debugPrint('🧪 [1/3] ProjectId: ${app.options.projectId}');
      debugPrint('🧪 [1/3] AppId: ${app.options.appId}');
      
      try {
        debugPrint('🧪 [2/3] محاولة تسجيل الدخول المجهول (Anonymous Auth)...');
        final testAuth = fauth.FirebaseAuth.instanceFor(app: app);
        final userCred = await testAuth.signInAnonymously().timeout(
          const Duration(seconds: 20),
        );
        debugPrint('✅ [2/3] تم تسجيل الدخول المجهول بنجاح!');
        debugPrint('✅ [2/3] User UID: ${userCred.user?.uid}');
        debugPrint('✅ [2/3] isAnonymous: ${userCred.user?.isAnonymous}');

        // 🔑 انتظار توكن صالح قبل أول قراءة (كبوابة المصادقة في المزامنة):
        // على ويندوز قد تخرج أول قراءة بعد التسجيل المجهول مباشرة بلا توكن،
        // فترفضها القواعد (permission-denied) رغم أنها صحيحة — إنذار كاذب.
        try {
          await userCred.user?.getIdToken(true).timeout(const Duration(seconds: 20));
        } catch (_) {}

        debugPrint('🧪 [3/3] محاولة قراءة مجموعة customers من Firestore...');
        // 🪟 ويندوز: الاختبار عبر واجهة Firestore REST، لا عبر مكتبة C++.
        // مكتبة Firestore على ويندوز أسقطت البرنامج كله (استثناء C++ 0xE06D7363)
        // عند أول قراءة في هذا المعالج على جهاز جديد — بقراءة الوثائق ثم بالعدّ.
        // REST يختبر الأشياء نفسها (المشروع، المصادقة، قواعد الأمان، الحصة)
        // بلا أي خطر على البرنامج، والمزامنة تتصل فعلياً بعد إعادة التشغيل.
        final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
        FirebaseFirestore? testFirestore;
        if (!isWindows) {
          testFirestore = FirebaseFirestore.instanceFor(app: app);
          // على سطح المكتب (لينكس/ماك): بلا تخزين محلي (LevelDB) كما في المزامنة.
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.linux ||
                  defaultTargetPlatform == TargetPlatform.macOS)) {
            try {
              testFirestore.settings = const Settings(persistenceEnabled: false);
            } catch (_) {}
          }
        }
        Future<int> readOnce() async {
          if (isWindows) {
            final token = await userCred.user?.getIdToken();
            return _restReadTest(projectId: options.projectId, idToken: token);
          }
          final q = await testFirestore!
              .collection('customers')
              .limit(1)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 20));
          return q.docs.length;
        }
        int readCount;
        try {
          readCount = await readOnce();
        } on FirebaseException catch (e) {
          if (!e.code.contains('permission-denied')) rethrow;
          // محاولة ثانية بعد لحظة: التوكن قد يصل متأخراً، وقواعد نُشرت للتو تحتاج ثوانيَ لتسري
          await Future.delayed(const Duration(seconds: 3));
          readCount = await readOnce();
        }
        debugPrint('✅ [3/3] تمت القراءة من Firestore بنجاح!${isWindows ? ' (REST)' : ''}');
        debugPrint('✅ [3/3] عدد المستندات المقروءة: $readCount');
        
        diagMessage = '\n✅ تم التحقق من الوصول لقاعدة البيانات (القراءة ناجحة).';
        debugPrint('🎉 [نهاية الاختبار] جميع الخطوات نجحت! ═══════════════');
      } on fauth.FirebaseAuthException catch (e) {
        debugPrint('❌ [2/3] فشل تسجيل الدخول المجهول!');
        debugPrint('❌ [2/3] Error Code: ${e.code}');
        debugPrint('❌ [2/3] Error Message: ${e.message}');
        debugPrint('❌ [2/3] السبب المحتمل: Anonymous Authentication غير مفعّل في Firebase Console');
        debugPrint('❌ [2/3] الحل: Firebase Console → Authentication → Sign-in method → Enable Anonymous');
        
        diagMessage = '\n⚠️ تحذير: تهيئة Firebase نجحت لكن فشل تسجيل الدخول المجهول.\n'
            'فعّل «Anonymous Sign-in» من Firebase Console → Authentication.\n'
            'الخطأ: ${e.code}';
        // لا نوقف الحفظ: قد يكون المستخدم يريد المتابعة وإصلاحها لاحقًا.
      } on FirebaseException catch (e) {
        debugPrint('❌ [3/3] فشلت القراءة من Firestore!');
        debugPrint('❌ [3/3] Error Code: ${e.code}');
        debugPrint('❌ [3/3] Error Message: ${e.message}');
        
        final msg = e.message ?? '';
        if (e.code.contains('permission-denied') ||
            msg.contains('permission-denied') ||
            e.code.contains('PERMISSION_DENIED')) {
          debugPrint('❌ [3/3] السبب: قواعد Firestore Rules ترفض الوصول');
          debugPrint('❌ [3/3] الحل المحتمل 1: تأكد من أن Anonymous Auth مفعّل');
          debugPrint('❌ [3/3] الحل المحتمل 2: تأكد من نشر Firestore Rules التي تسمح بـ request.auth != null');
          
          diagMessage = '\n⚠️ تحذير حرج: قواعد أمان Firestore تمنع الوصول!\n'
              ' Firestore Rules الحالية ترفض القراءة. تأكد من نشر firestore.rules '
              'الذي يسمح بجميع المجموعات للمستخدمين المصادق عليهم.\n'
              'الخطأ: ${e.code}';
        } else if (e.code.contains('resource-exhausted')) {
          diagMessage = '\n⚠️ نفدت حصة Firebase المجانية لهذا اليوم (القراءة/الكتابة).\n'
              'الربط صحيح ومحفوظ، والمزامنة تعمل تلقائياً بعد تجدّد الحصة '
              '(منتصف الليل بتوقيت كاليفورنيا، نحو العاشرة صباحاً بتوقيت بغداد).';
        } else if (e.code.contains('not-found')) {
          diagMessage = '\n⚠️ تحذير: لم تُنشأ قاعدة Firestore في هذا المشروع بعد.\n'
              'من Firebase Console ← Firestore Database ← Create database.\n'
              'الخطأ: ${e.message}';
        } else {
          diagMessage = '\n⚠️ تحذير: تهيئة Firebase نجحت لكن تعذّرت القراءة من قاعدة البيانات.\n'
              'الخطأ: ${e.code} - ${e.message}';
        }
      } catch (e) {
        debugPrint('❌ [اختبار] خطأ غير متوقع: $e');
        diagMessage = '\n⚠️ تحذير: اختبار قاعدة البيانات فشل (الشبكة؟).\nالخطأ: $e';
      }

      // إذا نجح الاتصال، نحفظ البيانات
      // (الحفظ صار قبل الاختبار — أعلاه)

      // تم إزالة app.delete() من هنا لأنها تدمر تطبيق Firebase الافتراضي

      if (_isWindows) FirebaseCustomConfig.restartRequired = true;
      if (!mounted) return;
      setState(() {
        _savedNeedsRestart = true;
        _testResult = '✅ تم الاتصال وحفظ الإعدادات بنجاح!\n⚠️ يرجى إعادة تشغيل التطبيق بالكامل لتفعيل القاعدة الجديدة.$diagMessage';
        _testResultColor = diagMessage.contains('⚠️') ? Colors.orange : Colors.green;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = '❌ فشل الاتصال. تأكد من صحة البيانات.\nالخطأ: $e';
        _testResultColor = Colors.red;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  /// 🪟 يعيد تشغيل البرنامج: نسخة جديدة من الملف نفسه ثم إغلاق هذه.
  Future<void> _restartApp() async {
    try {
      await Process.start(Platform.resolvedExecutable, SeatService.relaunchArgs,
          mode: ProcessStartMode.detached);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر إعادة التشغيل تلقائياً — أغلق البرنامج وافتحه يدوياً ($e)'),
      ));
      return;
    }
    exit(0);
  }

  /// 🪟 اختبار قراءة Firestore عبر REST (بلا مكتبة C++ — انظر الاختبار أعلاه).
  /// يقرأ وثيقة واحدة من customers بتوكن المستخدم المجهول، ويحوّل رمز HTTP
  /// إلى رمز Firebase المعتاد ليعالَج كما تعالَج أخطاء المكتبة.
  Future<int> _restReadTest({required String projectId, String? idToken}) async {
    final uri = Uri.parse('https://firestore.googleapis.com/v1/projects/'
        '${Uri.encodeComponent(projectId)}/databases/(default)/documents/customers?pageSize=1');
    final http.Response res;
    try {
      res = await http.get(uri, headers: {
        if (idToken != null && idToken.isNotEmpty) 'Authorization': 'Bearer $idToken',
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: '$e');
    }
    if (res.statusCode == 200) {
      try {
        final body = jsonDecode(res.body);
        final docs = body is Map ? body['documents'] : null;
        return docs is List ? docs.length : 0;
      } catch (_) {
        return 0;
      }
    }
    String message = 'HTTP ${res.statusCode}';
    try {
      final body = jsonDecode(res.body);
      final err = body is Map ? body['error'] : null;
      if (err is Map && err['message'] != null) message = '${err['message']}';
    } catch (_) {}
    final code = switch (res.statusCode) {
      401 => 'unauthenticated',
      403 => 'permission-denied',
      404 => 'not-found',
      429 => 'resource-exhausted',
      _ => 'unavailable',
    };
    debugPrint('❌ [3/3] REST ${res.statusCode}: $message');
    throw FirebaseException(plugin: 'cloud_firestore', code: code, message: message);
  }

  void _copyRules() {
    const rules = '''rules_version = '2';
 
service cloud.firestore {
  match /databases/{database}/documents {
 
    
    // ═══ كل المجموعات مسموح بها للمستخدمين المصادق عليهم فقط ═══
    // جميع الأجهزة تنتمي لنفس مشروع Firebase (نفس المالك)، لذا نكتفي
    // بالتحقق من المصادقة (request.auth != null) دون قيود إضافية.
 
    
    match /customers/{customerId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /transactions/{transactionId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /devices/{deviceId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /invoices/{invoiceId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /invoice_snapshots/{snapshotId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /invoice_read_acks/{ackId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /sync_operations/{operationId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /transaction_acks/{ackId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /bootstrap_data/{docId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /bootstrap_requests/{docId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /snapshots/{snapshotId} {
      allow read, write: if request.auth != null;
    }
 
    
    match /sync_groups/{groupId} {
      allow read, write: if request.auth != null;
    }
 
    // ═══ مجموعات المطابقة وحل التعارضات ═══
 
    match /reconciliation_sessions/{sessionId} {
      allow read, write: if request.auth != null;
    }
 
    match /live_match_sessions/{sessionId} {
      allow read, write: if request.auth != null;
    }
 
    match /live_peer_state/{stateId} {
      allow read, write: if request.auth != null;
    }
 
    // ═══ قاعدة شاملة احتياطية ═══
    // أي مجموعة أخرى (مستقبلية) مسموحة للمستخدمين المصادق عليهم.
    // هذا يمنع أخطاء permission-denied عند إضافة مجموعات جديدة.
    // ملاحظة: هذا آمن لأن كل الأجهزة تحت نفس مشروع Firebase المُدار من المالك.
    
    // منع الوصول لأي مسار آخر
    match /{document=**} {
      allow read, write: if request.auth != null;
      allow read, write: if false;
    }
  }
}
''';
    Clipboard.setData(const ClipboardData(text: rules));
    setToast(context, 'تم نسخ قواعد الأمان — الصقها في تبويب Rules ثم Publish');
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  static const _fbOrange = Color(0xFFEA580C);
  static const _steps = <(String, String, IconData)>[
    ('إنشاء المشروع', 'حساب Firebase مجاني', Icons.add_box_rounded),
    ('قاعدة البيانات', 'Firestore وقواعد الأمان', Icons.storage_rounded),
    ('تسجيل الدخول', 'تفعيل Anonymous', Icons.how_to_reg_rounded),
    ('إضافة التطبيق', 'استخراج المفاتيح', Icons.web_rounded),
    ('الإعدادات', 'لصق المفاتيح واختبارها', Icons.vpn_key_rounded),
  ];
  bool _showSecret = false;

  SetBannerKind get _testKind {
    if (_testResultColor == Colors.red) return SetBannerKind.error;
    if (_testResultColor == Colors.orange) return SetBannerKind.warn;
    if (_testResultColor == Colors.green) return SetBannerKind.ok;
    return SetBannerKind.info;
  }

  void _goTo(int step) {
    if (_isTesting) return;
    setState(() => _currentStep = step.clamp(0, _steps.length - 1).toInt());
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentStep == _steps.length - 1;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SettingsScaffold(
        title: 'ربط مشروع Firebase الخاص',
        subtitle: 'خمس خطوات — مرة واحدة لكل مجموعة أجهزة',
        icon: Icons.cloud_sync_rounded,
        maxWidth: 860,
        bottom: _bottomBar(isLast),
        children: [
          _stepHeader(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(_currentStep), child: _stepBody(_currentStep)),
          ),
        ],
      ),
    );
  }

  /// مؤشر الخطوات: دوائر مرقّمة متصلة، كل خطوة قابلة للضغط.
  Widget _stepHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kSetBorder),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final compact = c.maxWidth < 560;
        return Row(children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _goTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: i < _currentStep
                            ? kSetGreen
                            : (i == _currentStep ? _fbOrange : const Color(0xFFF1F5F9)),
                        shape: BoxShape.circle,
                        boxShadow: i == _currentStep
                            ? [BoxShadow(color: _fbOrange.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
                            : null,
                      ),
                      child: Icon(
                        i < _currentStep ? Icons.check_rounded : _steps[i].$3,
                        size: 18,
                        color: i <= _currentStep ? Colors.white : kSetMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      compact ? '${i + 1}' : _steps[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == _currentStep ? FontWeight.w800 : FontWeight.w600,
                        color: i == _currentStep ? _fbOrange : kSetMuted,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (i < _steps.length - 1)
              Container(
                width: compact ? 10 : 22,
                height: 2,
                margin: const EdgeInsets.only(bottom: 22),
                color: i < _currentStep ? kSetGreen : kSetBorder,
              ),
          ],
        ]);
      }),
    );
  }

  Widget _bottomBar(bool isLast) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kSetBorder))),
        child: SafeArea(
          top: false,
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Row(children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: _isTesting ? null : () => _goTo(_currentStep - 1),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18), // يُعكس تلقائياً في RTL
                    label: const Text('السابق'),
                  ),
                const Spacer(),
                Text('الخطوة ${_currentStep + 1} من ${_steps.length}',
                    style: const TextStyle(color: kSetMuted, fontSize: 12.5)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 210,
                  child: SetPrimaryButton(
                    label: isLast ? 'اختبار وحفظ الربط' : 'الخطوة التالية',
                    icon: isLast ? Icons.check_circle_outline_rounded : Icons.arrow_forward_rounded,
                    color: isLast ? kSetGreen : _fbOrange,
                    busy: _isTesting,
                    onPressed: isLast ? _testAndSaveConnection : () => _goTo(_currentStep + 1),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  /// رابط صفحة في مشروع المستخدم (أو صفحة Firebase الرئيسية قبل كتابة معرّف المشروع).
  String _fb(String path) {
    final id = _projectIdController.text.trim();
    return id.isEmpty ? 'https://console.firebase.google.com' : 'https://console.firebase.google.com/project/$id/$path';
  }

  bool get _hasProject => _projectIdController.text.trim().isNotEmpty;

  /// يقبل المعرّف أو رابط المشروع كاملاً (https://console.firebase.google.com/project/<id>/...).
  void _onProjectIdTyped(String v) {
    final m = RegExp(r'/project/([a-z0-9-]+)').firstMatch(v);
    if (m != null && m.group(1) != v) {
      _projectIdController.text = m.group(1)!;
      _projectIdController.selection = TextSelection.collapsed(offset: _projectIdController.text.length);
    }
    setState(() {});
  }

  Widget _projectIdField() => TextField(
        controller: _projectIdController,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(
          labelText: 'معرّف المشروع (Project ID)',
          hintText: 'مثال: my-shop-sync-1a2b3',
          helperText: 'أو الصق رابط صفحة المشروع من المتصفح كاملاً',
          prefixIcon: Icon(Icons.folder_open_rounded),
        ),
        onChanged: _onProjectIdTyped,
      );

  Widget _noProjectNote() => _hasProject
      ? const SizedBox.shrink()
      : const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: SetBanner('اكتب «معرّف المشروع» في الخطوة الأولى حتى تفتح الأزرار هنا صفحات مشروعك مباشرة.',
              kind: SetBannerKind.warn),
        );

  Widget _stepBody(int step) {
    final s = _steps[step];
    Widget card(Widget child) => SetCard(
          title: s.$1,
          subtitle: s.$2,
          icon: s.$3,
          color: _fbOrange,
          child: Padding(padding: const EdgeInsets.only(top: 12), child: child),
        );
    switch (step) {
      case 0:
        return card(SetupGuide(color: _fbOrange, steps: [
          const GuideStep(
            'تحتاج حساب Google (مثل Gmail). إن كان عندك تخطَّ هذه الخطوة، وإلا أنشئه من الرابط.',
            links: [GuideLink('إنشاء حساب Google', 'https://accounts.google.com/signup', icon: Icons.person_add_alt_1_rounded)],
          ),
          const GuideStep(
            'افتح موقع Firebase وسجّل الدخول بحساب Google. الخطة المجانية (Spark) تكفي ولا تحتاج بطاقة دفع.',
            links: [GuideLink('افتح Firebase', 'https://console.firebase.google.com', icon: Icons.local_fire_department_rounded)],
          ),
          const GuideStep(
            'اضغط «Create a project / إنشاء مشروع» (أو «Add project»)، واكتب اسماً بالإنجليزي، ثم وافق على الشروط ← «Continue».',
            copies: ['alnaser-shop-sync'],
          ),
          const GuideStep(
            'عند سؤال «Google Analytics» أطفئ المفتاح (لست بحاجة إليه) ← «Create project» وانتظر قليلاً ← «Continue».',
          ),
          GuideStep(
            'انظر إلى شريط العنوان في المتصفح: بعد كلمة /project/ يظهر «معرّف المشروع». انسخ الرابط كاملاً والصقه هنا '
            '(أو اكتب المعرّف وحده) — تصبح كل الأزرار في الخطوات التالية تفتح صفحات مشروعك مباشرة.',
            extra: _projectIdField(),
            note: 'المعرّف يظهر أيضاً في «Project settings / إعدادات المشروع» بجانب «Project ID».',
          ),
        ]));
      case 1:
        return card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _noProjectNote(),
          SetupGuide(color: _fbOrange, steps: [
            GuideStep(
              'افتح صفحة Firestore في مشروعك واضغط «Create database / إنشاء قاعدة بيانات». '
              '(في القائمة الجانبية تجدها في «Databases & Storage» أو «Build» ← «Firestore Database».)',
              links: [GuideLink('افتح Firestore لمشروعي', _fb('firestore'), icon: Icons.storage_rounded)],
            ),
            const GuideStep(
              'إن سألك عن النوع اختر «Standard edition». ثم اختر «الموقع / Location» الأقرب لك (مثل eur3 في أوروبا) ← «Next».',
              note: 'الموقع لا يمكن تغييره لاحقاً، لكن أي موقع يعمل.',
            ),
            const GuideStep('اختر «Start in production mode» ← «Create / إنشاء» وانتظر حتى تظهر الصفحة الفارغة لقاعدة البيانات.'),
            GuideStep(
              'اضغط زر «نسخ القواعد» هنا، ثم افتح تبويب «Rules / القواعد»، احذف كل ما فيه، والصق القواعد مكانه (Ctrl+V) ← «Publish / نشر».',
              links: [GuideLink('افتح صفحة Rules لمشروعي', _fb('firestore/rules'), icon: Icons.security_rounded)],
              extra: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _fbOrange),
                  onPressed: _copyRules,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ القواعد'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          // كان النص يدّعي أن القواعد تتحقق من groupSecret — وهي فعلياً تسمح لأي
          // مستخدم مسجّل الدخول (ولو مجهولاً). النص الآن يصف ما تفعله فعلاً.
          const SetBanner(
            'القواعد تسمح بالقراءة والكتابة لأي جهاز مسجّل الدخول في مشروعك (تسجيل مجهول). '
            'الحماية من البيانات المزوّرة يوفّرها «سرّ المجموعة» مع «الوضع الصارم» في إعدادات المزامنة — '
            'لذلك لا تشارك مفاتيح مشروعك مع أحد.',
            kind: SetBannerKind.warn,
            icon: Icons.shield_outlined,
          ),
        ]));
      case 2:
        return card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _noProjectNote(),
          SetupGuide(color: _fbOrange, steps: [
            GuideStep(
              'افتح صفحة «Authentication / المصادقة» في مشروعك، واضغط «Get started / البدء» إن ظهر.',
              links: [GuideLink('افتح صفحة المصادقة لمشروعي', _fb('authentication/providers'), icon: Icons.how_to_reg_rounded)],
            ),
            const GuideStep('في تبويب «Sign-in method / طريقة تسجيل الدخول» اختر «Anonymous / مجهول» من القائمة.'),
            const GuideStep('فعّل المفتاح «Enable» ← «Save / حفظ». يظهر «Anonymous» في القائمة بحالة «Enabled».'),
          ]),
        ]));
      case 3:
        return card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _noProjectNote(),
          SetupGuide(color: _fbOrange, steps: [
            GuideStep(
              'افتح «إعدادات المشروع» وانزل إلى قسم «Your apps / تطبيقاتك»، واضغط أيقونة الويب </> .',
              links: [GuideLink('افتح إعدادات مشروعي', _fb('settings/general'), icon: Icons.settings_rounded)],
            ),
            const GuideStep(
              'اكتب اسماً للتطبيق (أي اسم) ← لا تفعّل «Firebase Hosting» ← «Register app / تسجيل التطبيق».',
              copies: ['alnaser-desktop'],
            ),
            const GuideStep(
              'يظهر كود فيه «const firebaseConfig = { apiKey: … }». ظلّل الكود كله وانسخه (Ctrl+C) ← اضغط «الخطوة التالية» هنا والصقه في الخانة.',
              note: 'إن أغلقت الصفحة: إعدادات المشروع ← «Your apps» ← اختر التطبيق ← «Config» يظهر الكود نفسه.',
            ),
          ]),
        ]));
      default:
        return _configStep(s);
    }
  }

  Widget _configStep((String, String, IconData) s) {
    Widget field(TextEditingController c, String label, IconData icon) => TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
          onChanged: (_) => setState(() {}),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SetCard(
        title: 'الصق كود firebaseConfig',
        subtitle: 'يستخرج التطبيق الحقول تلقائياً',
        icon: Icons.content_paste_rounded,
        color: _fbOrange,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            maxLines: 5,
            minLines: 3,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'const firebaseConfig = {\n  apiKey: "...",\n  ...\n};',
              fillColor: Color(0xFFF8FAFC),
            ),
            onChanged: (value) {
              if (value.contains('apiKey') || value.contains('projectId')) {
                _parseFirebaseConfig(value);
              }
            },
          ),
        ),
      ),
      SetCard(
        title: 'المفاتيح',
        subtitle: 'أو أدخلها يدوياً',
        icon: s.$3,
        color: _fbOrange,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 560 ? 2 : 1;
            final w = (c.maxWidth - (cols - 1) * 12) / cols;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: w, child: field(_apiKeyController, 'API Key *', Icons.key_rounded)),
              SizedBox(width: w, child: field(_appIdController, 'App ID *', Icons.apps_rounded)),
              SizedBox(width: w, child: field(_projectIdController, 'Project ID *', Icons.folder_open_rounded)),
              SizedBox(width: w, child: field(_messagingSenderIdController, 'Messaging Sender ID', Icons.numbers_rounded)),
            ]);
          }),
          const SizedBox(height: 12),
          TextField(
            controller: _encryptionSecretController,
            obscureText: !_showSecret,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'سرّ المجموعة / مفتاح التشفير (اختياري)',
              helperText: 'نفس السرّ على كل الأجهزة — اتركه فارغاً للإبقاء على السرّ الحالي',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _showSecret ? 'إخفاء' : 'إظهار',
                icon: Icon(_showSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _showSecret = !_showSecret),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _testResult.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(_testResult),
                    padding: const EdgeInsets.only(top: 14),
                    child: SetBanner(_testResult, kind: _testKind),
                  ),
          ),
          if (_savedNeedsRestart && _isWindows) ...[
            const SizedBox(height: 12),
            SetPrimaryButton(
              label: 'إعادة تشغيل البرنامج الآن لتفعيل الربط',
              icon: Icons.restart_alt_rounded,
              color: kSetGreen,
              onPressed: _restartApp,
            ),
          ],
        ]),
      ),
      if (_projectIdController.text.isNotEmpty)
        SetCard(
          title: 'روابط سريعة لمشروعك',
          icon: Icons.link_rounded,
          color: kSetBlue,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Column(children: [
            SetActionRow(
              icon: Icons.security_rounded,
              title: 'صفحة قواعد البيانات (Rules)',
              color: kSetBlue,
              onTap: () => _launchUrl(
                  'https://console.firebase.google.com/project/${_projectIdController.text}/firestore/rules'),
            ),
            SetActionRow(
              icon: Icons.person_rounded,
              title: 'صفحة المصادقة (Authentication)',
              color: const Color(0xFF7C3AED),
              onTap: () => _launchUrl(
                  'https://console.firebase.google.com/project/${_projectIdController.text}/authentication/providers'),
            ),
          ]),
        ),
    ]);
  }
}
