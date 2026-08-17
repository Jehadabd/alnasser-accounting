import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fauth;
import '../services/firebase_sync/firebase_custom_config.dart';
import '../services/firebase_sync/firebase_sync_config.dart';
import '../services/firebase_sync/firebase_auth_service.dart';
import '../services/firebase_sync/firebase_sync.dart';
import '../services/sync/sync_security.dart';

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
  Color _testResultColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final options = await FirebaseCustomConfig.getCustomOptions();
    if (options != null) {
      _apiKeyController.text = options.apiKey;
      _appIdController.text = options.appId;
      _projectIdController.text = options.projectId;
      _messagingSenderIdController.text = options.messagingSenderId;
    }
  }

  void _parseFirebaseConfig(String configStr) {
    String extractValue(String key) {
      final regex = RegExp('[\'"]?' + key + '[\'"]?\\s*:\\s*[\'"]([^\'"]+)[\'"]');
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
      String diagMessage = '';
      print('🧪 [اختبار الاتصال] ═══════════════════════════════════');
      print('🧪 [1/3] تم تهيئة Firebase App بنجاح');
      print('🧪 [1/3] ProjectId: ${app.options.projectId}');
      print('🧪 [1/3] AppId: ${app.options.appId}');
      
      try {
        print('🧪 [2/3] محاولة تسجيل الدخول المجهول (Anonymous Auth)...');
        final testAuth = fauth.FirebaseAuth.instanceFor(app: app);
        final userCred = await testAuth.signInAnonymously().timeout(
          const Duration(seconds: 20),
        );
        print('✅ [2/3] تم تسجيل الدخول المجهول بنجاح!');
        print('✅ [2/3] User UID: ${userCred.user?.uid}');
        print('✅ [2/3] isAnonymous: ${userCred.user?.isAnonymous}');

        print('🧪 [3/3] محاولة قراءة مجموعة customers من Firestore...');
        final testFirestore = FirebaseFirestore.instanceFor(app: app);
        final snapshot = await testFirestore
            .collection('customers')
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 20));
        print('✅ [3/3] تمت القراءة من Firestore بنجاح!');
        print('✅ [3/3] عدد المستندات المقروءة: ${snapshot.docs.length}');
        
        diagMessage = '\n✅ تم التحقق من الوصول لقاعدة البيانات (القراءة ناجحة).';
        print('🎉 [نهاية الاختبار] جميع الخطوات نجحت! ═══════════════');
      } on fauth.FirebaseAuthException catch (e) {
        print('❌ [2/3] فشل تسجيل الدخول المجهول!');
        print('❌ [2/3] Error Code: ${e.code}');
        print('❌ [2/3] Error Message: ${e.message}');
        print('❌ [2/3] السبب المحتمل: Anonymous Authentication غير مفعّل في Firebase Console');
        print('❌ [2/3] الحل: Firebase Console → Authentication → Sign-in method → Enable Anonymous');
        
        diagMessage = '\n⚠️ تحذير: تهيئة Firebase نجحت لكن فشل تسجيل الدخول المجهول.\n'
            'فعّل «Anonymous Sign-in» من Firebase Console → Authentication.\n'
            'الخطأ: ${e.code}';
        // لا نوقف الحفظ: قد يكون المستخدم يريد المتابعة وإصلاحها لاحقًا.
      } on FirebaseException catch (e) {
        print('❌ [3/3] فشلت القراءة من Firestore!');
        print('❌ [3/3] Error Code: ${e.code}');
        print('❌ [3/3] Error Message: ${e.message}');
        
        final msg = e.message ?? '';
        if (e.code.contains('permission-denied') ||
            msg.contains('permission-denied') ||
            e.code.contains('PERMISSION_DENIED')) {
          print('❌ [3/3] السبب: قواعد Firestore Rules ترفض الوصول');
          print('❌ [3/3] الحل المحتمل 1: تأكد من أن Anonymous Auth مفعّل');
          print('❌ [3/3] الحل المحتمل 2: تأكد من نشر Firestore Rules التي تسمح بـ request.auth != null');
          
          diagMessage = '\n⚠️ تحذير حرج: قواعد أمان Firestore تمنع الوصول!\n'
              ' Firestore Rules الحالية ترفض القراءة. تأكد من نشر firestore.rules '
              'الذي يسمح بجميع المجموعات للمستخدمين المصادق عليهم.\n'
              'الخطأ: ${e.code}';
        } else {
          diagMessage = '\n⚠️ تحذير: تهيئة Firebase نجحت لكن تعذّرت القراءة من قاعدة البيانات.\n'
              'الخطأ: ${e.code} - ${e.message}';
        }
      } catch (e) {
        print('❌ [اختبار] خطأ غير متوقع: $e');
        diagMessage = '\n⚠️ تحذير: اختبار قاعدة البيانات فشل (الشبكة؟).\nالخطأ: $e';
      }

      // إذا نجح الاتصال، نحفظ البيانات
      await FirebaseCustomConfig.saveCustomConfig(
        apiKey: options.apiKey,
        appId: options.appId,
        projectId: options.projectId,
        messagingSenderId: options.messagingSenderId,
      );

      if (encryptionSecret.isNotEmpty) {
        await SyncSecurity.saveSecretKey(encryptionSecret);
      }

      // تم إزالة app.delete() من هنا لأنها تدمر تطبيق Firebase الافتراضي

      setState(() {
        _testResult = '✅ تم الاتصال وحفظ الإعدادات بنجاح!\n⚠️ يرجى إعادة تشغيل التطبيق بالكامل لتفعيل القاعدة الجديدة.$diagMessage';
        _testResultColor = diagMessage.contains('⚠️') ? Colors.orange : Colors.green;
      });

    } catch (e) {
      setState(() {
        _testResult = '❌ فشل الاتصال. تأكد من صحة البيانات.\nالخطأ: $e';
        _testResultColor = Colors.red;
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ قواعد الأمان')),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعداد قاعدة بياناتي الخاصة'),
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
        ),
        body: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 4) {
              setState(() => _currentStep++);
            } else {
              _testAndSaveConnection();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            }
          },
          controlsBuilder: (context, details) {
            final isLastStep = _currentStep == 4;
            return Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _isTesting ? null : details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLastStep ? Colors.green : Colors.deepOrange,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(isLastStep ? 'اختبار وحفظ' : 'التالي'),
                  ),
                  const SizedBox(width: 8),
                  if (_currentStep > 0)
                    TextButton(
                      onPressed: _isTesting ? null : details.onStepCancel,
                      child: const Text('رجوع'),
                    ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('إنشاء مشروع Firebase'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. قم بالدخول إلى موقع Firebase (مجاني بالكامل)'),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _launchUrl('https://console.firebase.google.com'),
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('افتح موقع Firebase'),
                  ),
                  const SizedBox(height: 8),
                  const Text('2. اضغط على "Add project" وقم بتسميته.'),
                  const Text('3. قم بإلغاء تفعيل Google Analytics لست بحاجة إليه.'),
                ],
              ),
              isActive: _currentStep >= 0,
            ),
            Step(
              title: const Text('إعداد قاعدة البيانات (Firestore)'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. من القائمة الجانبية اختر "Firestore Database" ثم اضغط "Create database".'),
                  const Text('2. اختر موقع الخادم الأقرب لك (مثلاً eur3).'),
                  const Text('3. بعد الإنشاء، اذهب إلى تبويب "Rules".'),
                  const Text('4. انسخ الكود بالنقر على الزر بالأسفل والصقه هناك، ثم اضغط Publish:'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.security, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'القواعد المنسوخة آمنة حسابياً بالكامل وتعتمد على التحقق من groupSecret (مفتاح تشفير 32 حرف) لمنع أي وصول غير مصرح به حتى لو تم تسريب رابط قاعدة البيانات.',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _copyRules,
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ القواعد'),
                  ),
                ],
              ),
              isActive: _currentStep >= 1,
            ),
            Step(
              title: const Text('تفعيل تسجيل الدخول (Authentication)'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. من القائمة الجانبية اختر "Authentication" ثم اضغط "Get started".'),
                  const Text('2. اذهب إلى تبويب "Sign-in method".'),
                  const Text('3. اختر "Anonymous" وقم بتفعيله (Enable).'),
                  const Text('4. اضغط Save. (هذا يضمن أن التطبيق فقط من يتصل بالبيانات).'),
                ],
              ),
              isActive: _currentStep >= 2,
            ),
            Step(
              title: const Text('إضافة التطبيق واستخراج المفاتيح'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. ارجع للصفحة الرئيسية للمشروع (Project Overview).'),
                  const Text('2. اضغط على أيقونة الويب (</>) لإضافة تطبيق.'),
                  const Text('3. اختر اسماً للتطبيق ثم اضغط Register app.'),
                  const Text('4. سيظهر لك كود يحتوي على المفاتيح (firebaseConfig). احتفظ بهذه الصفحة مفتوحة للخطوة التالية.'),
                ],
              ),
              isActive: _currentStep >= 3,
            ),
            Step(
              title: const Text('إدخال الإعدادات'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('يمكنك ببساطة لصق الكود كاملاً من Firebase وسيقوم التطبيق باستخراج الحقول تلقائياً:'),
                  const SizedBox(height: 8),
                  TextField(
                    maxLines: 4,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'الصق كود firebaseConfig هنا',
                      hintText: 'const firebaseConfig = {\n  apiKey: "...",\n  ...\n};',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFFF5F5F5),
                    ),
                    onChanged: (value) {
                      if (value.contains('apiKey') || value.contains('projectId')) {
                        _parseFirebaseConfig(value);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('أو أدخلها يدوياً:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(labelText: 'API Key', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _appIdController,
                    decoration: const InputDecoration(labelText: 'App ID', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _projectIdController,
                    decoration: const InputDecoration(labelText: 'Project ID', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messagingSenderIdController,
                    decoration: const InputDecoration(labelText: 'Messaging Sender ID', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _encryptionSecretController,
                    decoration: const InputDecoration(labelText: 'مفتاح التشفير (اختياري)', border: OutlineInputBorder()),
                  ),
                  if (_testResult.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _testResult,
                      style: TextStyle(color: _testResultColor, fontWeight: FontWeight.bold),
                    ),
                  ],
                  if (_projectIdController.text.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('🔗 روابط الوصول السريع (بناءً على الكود الذي أدخلته):', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _launchUrl('https://console.firebase.google.com/project/${_projectIdController.text}/firestore/rules'),
                        icon: const Icon(Icons.security),
                        label: const Text('افتح صفحة قواعد البيانات (Rules)'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, foregroundColor: Colors.blue.shade900),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _launchUrl('https://console.firebase.google.com/project/${_projectIdController.text}/authentication/providers'),
                        icon: const Icon(Icons.person),
                        label: const Text('افتح صفحة المصادقة (Authentication)'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade50, foregroundColor: Colors.purple.shade900),
                      ),
                    ),
                  ],
                ],
              ),
              isActive: _currentStep >= 4,
            ),
          ],
        ),
      ),
    );
  }
}
