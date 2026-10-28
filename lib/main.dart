// main.dart
import 'services/product_codes.dart' show ItemCodeKeyboard; // ⌨️
import 'widgets/popup_screens.dart'; // 🪟
import 'services/save_lock.dart'; // 🔒
import 'services/demo_mode.dart'; // 🧪
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐 حراسة الويب
import 'package:flutter/material.dart';
import 'services/database/core/migration_guard.dart' show MigrationGuardException;
import 'widgets/migration_guard_views.dart' show MigrationBlockedApp;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/numeric_date_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:get_storage/get_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'services/error_log.dart'; // 🧯 سجل أخطاء Dart في ملف
import 'widgets/global_side_nav.dart';
import 'providers/app_provider.dart';
import 'providers/pos_provider.dart';
import 'screens/home_screen.dart';
import 'screens/main_screen.dart';
import 'screens/product_entry_screen.dart';
import 'screens/create_invoice_screen.dart';
import 'screens/edit_invoices_screen.dart';
import 'screens/edit_products_screen.dart';
import 'screens/custom_range_report_screen.dart';
import 'screens/reports_screen.dart';
// removed font settings screen import
import 'screens/suppliers/suppliers_dashboard_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/pos/pos_screen.dart';
import 'services/database_service.dart';
import 'services/firebase_sync/firebase_sync_service.dart';
import 'screens/password_setup_screen.dart';
import 'screens/general_settings_screen.dart';
import 'screens/login_screen.dart'; // 👤
import 'screens/user_management_screen.dart'; // 👤
import 'services/printing_service.dart';
// 🌐🔀 مصنع الطباعة المشروط: ويب → Web، أندرويد/ويندوز → io كما كان
// (كان الاستيراد المباشر لـ windows/io يكسر بناء الويب بسبب win32/dart:io)
import 'services/printing_service_factory.dart';
import 'services/auth_service.dart'; // 👤
import 'services/database/business/tx_author.dart';
import 'services/purchase_service.dart'; // 🆕
import 'services/suppliers_service.dart'; // 🆕 (Fix Provider Error)
import 'services/license_service.dart'; // 🔐
import 'screens/license_screen.dart'; // 🔐
import 'screens/license_devices_screen.dart'; // 🔐 الترخيص والأجهزة
import 'services/font_manager.dart'; // 🔡 Font management
import 'services/ensemble_ai_service_factory.dart'; // 🧠 AI Service (مشروط ويب/أصلي)
import 'screens/reconciliation_prompt.dart';
import 'web_db_init.dart'; // 🌐 تهيئة محرك قاعدة البيانات على الويب (مشروط)
import 'lan/lan_bootstrap.dart'; // 🖧 سيرفر/طرفية على الشبكة المحلية
import 'lan/lan_settings.dart';
import 'lan/network_settings_screen.dart';
import 'accounting/screens/accounting_home_screen.dart'; // 🏛️ المحاسبة
import 'org/screens/branches_warehouses_screen.dart'; // 🏢 الفروع والمخازن
import 'inventory/item_card_screen.dart'; // 🗂️ بطاقات المواد
import 'inventory/product_entry_mode.dart'; // ⚙️ الواجهة المختارة لإدخال البضاعة
import 'erp/purchases/purchase_return_screen.dart'; // ↩️ مرتجع المشتريات
import 'widgets/global_shortcuts.dart'; // ⌨️ F1..F8

import 'package:firebase_core/firebase_core.dart'; // 🆕 Firebase
import 'package:firebase_auth/firebase_auth.dart'; // 🔐 Firebase Authentication
import 'services/firebase_sync/firebase_custom_config.dart'; // 🆕 Firebase Config
import 'services/firebase_sync/sync_diagnostics.dart'; // 🩺 تشخيص المصادقة/المزامنة
import 'services/firebase_sync/web_auth_clear.dart'; // 🧹 تنظيف مخزن جلسة المتصفح
import 'erp/dashboard/dashboard_screen.dart';
import 'erp/sales/sales_hub_screen.dart';
import 'erp/debts/debts_hub_screen.dart';
import 'erp/inventory/inventory_hub_screen.dart';
import 'erp/accounting_plus/period_screens.dart' show AccountingPlusHubScreen;
import 'services/seat_service.dart';

/// 🔥 مفتاح الملاح العام — يُستخدم من ReconciliationPrompt وغيرها لإظهار
/// حوارات من خارج شجرة الويدجت.
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

/// 🧭 يتتبع الشاشات المفتوحة للوحة الجانبية العامة
final SideNavObserver sideNavObserver = SideNavObserver();

bool _syncRestartPrompted = false;

/// 🖥️ كل الشاشات المسموحة في الترخيص مستعملة على هذه الحاسبة
class SeatLimitApp extends StatelessWidget {
  const SeatLimitApp({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          backgroundColor: const Color(0xFF020F2B),
          body: Center(
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.desktop_access_disabled_rounded, size: 56, color: Color(0xFFB45309)),
                    const SizedBox(height: 12),
                    const Text('عدد الشاشات المسموح مكتمل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.6)),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: () => exit(0), child: const Text('إغلاق')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

/// 🔄 ربط المزامنة وصل من سيرفر الترخيص (حساب «شامل + مزامنة»): يلزم إعادة التشغيل.
/// إن لم تكن الواجهة جاهزة بعد (التجديد عند الإقلاع) نحاول بعد لحظات.
void _promptRestartForSync([int attempt = 0]) {
  if (_syncRestartPrompted) return;
  final ctx = globalNavigatorKey.currentContext;
  if (ctx == null) {
    if (attempt < 20) Future<void>.delayed(const Duration(seconds: 3), () => _promptRestartForSync(attempt + 1));
    return;
  }
  _syncRestartPrompted = true;
  showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text('🔄 وصل إعداد المزامنة'),
      content: const Text(
        'وصل إعداد المزامنة لحسابك من سيرفر الترخيص. أعد تشغيل البرنامج مرة واحدة '
        'ليتصل ويجلب بيانات المحل عبر الإنترنت.',
        style: TextStyle(height: 1.6),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('لاحقاً')),
        FilledButton(onPressed: () => LanRuntime.relaunch(), child: const Text('إعادة التشغيل الآن')),
      ],
    ),
  );
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 🖥️ رقم الشاشة من برنامج ويندوز (تعدد الشاشات على الحاسبة الواحدة)
  SeatService.parseArgs(args);

  // 🧯 أي خطأ غير مُعالَج يُكتب في alnaser_logs\dart_errors.log (لمعرفة سبب أي خروج مفاجئ)
  await ErrorLog.install();

  // 🚫 لا نسخ تلقائي لأي قاعدة موجودة على الجهاز: المجلد القديم com.example\debt_book
  // يشترك فيه دفتر الديون وشوب مانجر، فكان التثبيت الجديد يسحب بياناتهما.
  // التثبيت الجديد يبدأ بقاعدة فارغة؛ ومن يريد بياناته القديمة يستعيدها يدوياً:
  // الإعدادات ← «استعادة قاعدة البيانات من ملف (.db)».
  // await DataLocationMigration.run();

  // 🧪 الوضع التجريبي يحدد أي قاعدة تُفتح — يُقرأ قبل أي شيء يلمس القاعدة
  await DemoMode.load();

  // تهيئة GetStorage
  await GetStorage.init();

  // تهيئة الخطوط العربية
  await FontManager.loadArabicFonts();

  // إتاحة التحكم باتجاه الشاشة للجوال (أفقي ثابت أو تدوير تلقائي)
  // 🌐 الويب: SystemChrome اتجاهات لا معنى لها في المتصفح — تخطَّ
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    final String storedOrientation = GetStorage().read('screen_orientation') ?? 'landscape';
    if (storedOrientation == 'auto') {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  // تحميل ملف .env من عدة مواقع محتملة
  bool envLoaded = false;
  // 🌐 الويب: لا نظام ملفات — .env يُحمَّل من assets فقط (المحاولة 2 أدناه)
  if (!kIsWeb) {
    try {
      // محاولة 1: من مجلد التطبيق الحالي (للـ EXE)
      final exeDir = Platform.resolvedExecutable;
      final exePath = exeDir.substring(0, exeDir.lastIndexOf(Platform.pathSeparator));
      final envFile = File('$exePath${Platform.pathSeparator}.env');

      if (await envFile.exists()) {
        await dotenv.load(fileName: envFile.path);
        envLoaded = true;
        debugPrint('✅ تم تحميل .env من مجلد التطبيق: ${envFile.path}');
      }
    } catch (e) {
      debugPrint('⚠️ فشل تحميل .env من مجلد التطبيق: $e');
    }
  }

  // محاولة 2: من المجلد الافتراضي (للتطوير)
  if (!envLoaded) {
    try {
      await dotenv.load();
      envLoaded = true;
      debugPrint('✅ تم تحميل .env من المجلد الافتراضي');
    } catch (e) {
      debugPrint('⚠️ ملف .env غير موجود - سيتم استخدام القيم الافتراضية المُضمنة');
    }
  }

  // تهيئة محرك قاعدة البيانات حسب المنصة:
  // 🌐 الويب: SQLite عبر WebAssembly (sqflite_common_ffi_web) — تخزين IndexedDB دائم.
  // 🖥️ الديسكتوب: sqflite_common_ffi كما كان تماماً.
  // 📱 أندرويد: الافتراضي (sqflite + sqlite3_flutter_libs بدعم FTS5) كما كان.
  if (kIsWeb) {
    // 🌐 يُستورد عبر ملف التهيئة المشروط (web_db_init.dart) — لا يعمل import
    // الحزمة مباشرة هنا لأنها تكسر بناء المنصات الأخرى.
    await configureWebDatabase();
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 🖧 وضع الشبكة: الطرفية تتصل بالسيرفر وتستبدل مصنع قاعدة البيانات قبل
  //    أي فتح للقاعدة. عند الفشل نعرض شاشة الاتصال بدل البرنامج.
  if (!kIsWeb && !DemoMode.isOn) {
    final lanError = await LanRuntime.beforeDatabase();
    if (lanError != null) {
      runApp(LanConnectionErrorApp(message: lanError));
      return;
    }
  }

  // 🛡️ فتح القاعدة أولاً (وفيه حارس الهجرة): إن رفض الحارس تحويلها — لأن
  //    التحويل كان سيغيّر رقماً مالياً — تُعرض الفروقات بدل البرنامج، والقاعدة
  //    أُعيدت كما كانت حرفياً.
  if (!kIsWeb && AppNetworkMode.ownsDatabase) {
    try {
      await DatabaseService().database;
    } on MigrationGuardException catch (e) {
      runApp(MigrationBlockedApp(error: e));
      return;
    } catch (e) {
      debugPrint('⚠️ فتح قاعدة البيانات عند البدء: $e');
    }
  }

  //Ensure Supplier Tables exist (Migration)
  try {
     await SuppliersService().ensureTables();
  } catch (e) {
     debugPrint('⚠️ Error ensuring supplier tables: $e');
  }

  // فحص سلامة البيانات المالية (صامت - بدون طباعة) — على مالك القاعدة فقط
  if (AppNetworkMode.ownsDatabase) {
    try {
      final dbService = DatabaseService();
      await dbService.performQuickIntegrityCheck();
    } catch (e) {
      // تجاهل الخطأ - لا نوقف التطبيق
    }
  }

  // 🪟 تهيئة WindowManager (يحتاجه main_screen للتحكم في إغلاق النافذة).
  // 🌐 الويب: لا نوافذ نظام — تخطَّ.
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      debugPrint('⚠️ فشل تهيئة WindowManager (المتابعة بالنافذة الافتراضية): $e');
    }
  }

  // 🔴 🔥 تهيئة Firebase باستخدام الإعدادات المخصصة إذا كانت متوفرة
  try {
    debugPrint('🔥 [main.dart] ════════════════════════════════════════');
    debugPrint('🔥 [main.dart] بدء تهيئة Firebase...');
    
    // 🧪 الوضع التجريبي: لا Firebase إطلاقاً (البيانات الوهمية لا تُرفع)
    final customOptions = DemoMode.isOn ? null : await FirebaseCustomConfig.getCustomOptions();
    if (customOptions != null) {
      debugPrint('✅ [main.dart] وجدت إعدادات Firebase المخصصة');
      debugPrint('✅ [main.dart] ProjectId: ${customOptions.projectId}');
      debugPrint('✅ [main.dart] AppId: ${customOptions.appId}');
      
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: customOptions);
        debugPrint('✅ [main.dart] تم تهيئة Firebase بنجاح');
        debugPrint('✅ تم تهيئة Firebase بنجاح بالإعدادات المخصصة.');
      } else {
        debugPrint('✅ [main.dart] تم تهيئة Firebase مسبقاً (ربما بسبب Hot Restart)');
      }
      
      // 🔐 تسجيل دخول تلقائي لـ Firebase Authentication
      // هذا ضروري لأن قواعد Firestore تتطلب: request.auth != null
      try {
        debugPrint('🔐 [main.dart] فحص حالة المصادقة...');

        // ═══════════════════════════════════════════════════════════════
        // 🌐 استرجاع الجلسة على الويب — سلّم تنازل لا نقطة انهيار
        // ═══════════════════════════════════════════════════════════════
        //
        // المشكلة على iOS (PWA مثبَّت على الشاشة الرئيسية):
        //   • النسخة المستقلة لها مخزن منفصل عن سفاري، فأول تشغيل هو أول
        //     *كتابة*، والثاني هو أول *قراءة* — ولهذا كانت المزامنة تنجح
        //     أول مرة وتفشل بعدها بالضبط.
        //   • وWebKit قد لا يُطلق أي حدث لـ indexedDB.open() بعد إقلاع بارد
        //     للتطبيق المستقل: لا نجاح ولا فشل ولا blocked — يتعلّق صامتاً.
        //     فتنقضي المهلة، وتبقى الجلسة null، ثم يفشل التسجيل المجهول
        //     لأنه يحتاج الكتابة في نفس المخزن المتعلّق ⇒ «فشل الاتصال».
        //
        // الحل: المصادقة هنا **مجهولة**، وقواعد Firestore تشترط
        // `request.auth != null` فقط، ولا مسار وثيقة واحد يعتمد على uid
        // (كلها syncUuid/deviceId/groupId). فحفظ الجلسة لا يشتري شيئاً.
        //
        // لذا: نُبقي LOCAL حيث تعمل (كي لا تتراكم حسابات مجهولة بلا داعٍ)،
        // وننتقل إلى NONE (ذاكرة فقط) فور تعثّرها — فيصير كل تشغيل يسلك
        // مسار التشغيل الأول، وهو المسار الذي يعمل.
        bool webMemoryOnlyAuth = false;
        if (kIsWeb) {
          try {
            await FirebaseAuth.instance
                .setPersistence(Persistence.LOCAL)
                .timeout(const Duration(seconds: 4));
            debugPrint('🔐 [main.dart] استمرارية الجلسة: LOCAL (IndexedDB)');
          } catch (e) {
            webMemoryOnlyAuth = true;
            SyncDiagnostics.log('auth',
                'تعذّر تثبيت الجلسة في IndexedDB — التحوّل إلى ذاكرة فقط: $e');
            try {
              await FirebaseAuth.instance.setPersistence(Persistence.NONE);
            } catch (_) {}
          }
        }

        // 🌐 استرجاع الجلسة غير متزامن — انتظر أول بلاغ حقيقي (بمهلة)
        User? currentUser;
        if (!webMemoryOnlyAuth) {
          try {
            currentUser = await FirebaseAuth.instance.authStateChanges()
                .first
                .timeout(const Duration(seconds: 8));
          } catch (e) {
            SyncDiagnostics.log('auth', '[main/استرجاع الجلسة] $e');
            // 🔀 مسار بديل عند فشل بث الجلسة (TypeError في السفاري): استعلام دوري
            if (e.toString().toLowerCase().contains('typeerror')) {
              for (var i = 0; i < 8; i++) {
                await Future.delayed(const Duration(seconds: 1));
                currentUser = FirebaseAuth.instance.currentUser;
                if (currentUser != null) break;
              }
            }
            currentUser ??= FirebaseAuth.instance.currentUser;

            // 🌐 ما زالت لا جلسة بعد المهلة ⇒ الاسترجاع متعلّق، لا غائب.
            // ننظّف المخزن التالف/المتعلّق ونكمل بذاكرة فقط، فلا ننتظره ثانيةً.
            if (kIsWeb && currentUser == null) {
              SyncDiagnostics.log('auth',
                  'تعليق في استرجاع الجلسة — تنظيف المخزن والمتابعة بذاكرة فقط');
              try {
                await clearWebAuthStorage();
              } catch (_) {}
              try {
                await FirebaseAuth.instance.setPersistence(Persistence.NONE);
              } catch (_) {}
              webMemoryOnlyAuth = true;
            }
          }
        }

        if (currentUser == null) {
          debugPrint('🔐 [main.dart] لا جلسة — تسجيل مجهول (مع إعادة محاولة)...');
          currentUser = await _signInAnonymouslyWithRetry();
        } else {
          debugPrint('✅ [main.dart] جلسة موجودة: ${currentUser.uid}');
          // 🩺 فحص حقيقي: توكن سليم أم مرفوض؟
          try {
            await currentUser.getIdToken(true);
            debugPrint('✅ [main.dart] التوكن سليم ومُجدد');
          } catch (tokenError) {
            debugPrint('⚠️ [main.dart] التوكن غير صالح — جلسة جديدة...');
            SyncDiagnostics.log('auth',
                'انتهت صلاحية الجلسة — يجري إنشاء جلسة جديدة تلقائياً');
            try {
              await FirebaseAuth.instance.signOut();
            } catch (_) {}
            currentUser = await _signInAnonymouslyWithRetry();
          }
        }

        debugPrint('🎉 [main.dart] Firebase Authentication جاهز!');

      } catch (authError) {
        debugPrint('❌ [main.dart] خطأ في تسجيل الدخول لـ Firebase Auth!');
        debugPrint('❌ [main.dart] Error: $authError');
        SyncDiagnostics.logAuth(authError);
      }
      
    } else {
      debugPrint('ℹ️ [main.dart] لم يتم العثور على إعدادات Firebase مخصصة');
      debugPrint('ℹ️ لم يتم العثور على إعدادات Firebase مخصصة. سيتم تخطي التهيئة.');
    }
    debugPrint('🔥 [main.dart] ════════════════════════════════════════');
  } catch (e, stackTrace) {
    debugPrint('❌ [main.dart] خطأ أثناء تهيئة Firebase!');
    debugPrint('❌ [main.dart] Error Type: ${e.runtimeType}');
    debugPrint('❌ [main.dart] Error: $e');
    debugPrint('❌ [main.dart] StackTrace: $stackTrace');
    debugPrint('⚠️ خطأ أثناء تهيئة Firebase: $e');
  }

  // 🔐 نظام الترخيص 4: الترخيص الموقَّع + بصمة الجهاز، قبل اختيار الشاشة الأولى
  await LicenseService.init();
  LicenseService.onLocked = () {
    globalNavigatorKey.currentState?.pushNamedAndRemoveUntil('/license', (route) => false);
  };
  // 🔄 وصل ربط المزامنة من حساب الترخيص أثناء العمل: إعادة تشغيل مرة واحدة ليتصل
  LicenseService.onSyncLinkArrived = () => _promptRestartForSync();

  // 📥 قاعدة مستعادة/مستوردة على جهاز بلا مزامنة: لا «وضع استعادة» ولا قفل سجلات
  await DatabaseService.clearRestoreIfNoSync();

  // 🖥️ حجز شاشة لهذه النسخة ضمن العدد المسموح في الترخيص
  if (!kIsWeb && !DemoMode.isOn) {
    final seatError = await SeatService.claim();
    if (seatError != null) {
      runApp(SeatLimitApp(message: seatError));
      return;
    }
  }

  // 🔐 License check first
  final licenseService = LicenseService();
  final isLicenseActivated = licenseService.isLicenseActivated();

  String initialRoute;

  if (!isLicenseActivated) {
    // لم يتم تفعيل الترخيص - اذهب لشاشة التفعيل
    initialRoute = '/license';
  } else {
    // الترخيص مفعّل - اذهب لشاشة الفحص
    initialRoute = '/license_check';
  }

  // 🔥 تفعيل نظام المطابقة وحل التعارضات عند التشغيل (مالك القاعدة فقط:
  //    المزامنة مع Firebase تعمل على السيرفر وحده، لا على الطرفيات)
  if (AppNetworkMode.ownsDatabase && !DemoMode.isOn && SeatService.isPrimary) ReconciliationPrompt.start();

  await PopupScreens.load(); // 🪟 الشاشات التي تُفتح كنافذة (إعداد هذا الجهاز)
  PopupScreens.rootKey = globalNavigatorKey;
  TxAuthor.currentName = () => AuthService().currentUser?.username; // 👤 من أنشأ المعاملة
  await ItemCodeKeyboard.load(); // ⌨️ رمز المادة بالإنجليزية تلقائياً
  runApp(MyApp(initialRoute: initialRoute));

  // 🖧 السيرفر يبدأ خدمة الطرفيات + الترحيل المحاسبي التلقائي
  //    (الشاشة الأولى وحدها: الشاشات الأخرى على نفس الحاسبة لا تكرر الأعمال الخلفية)
  if (!kIsWeb && !DemoMode.isOn && SeatService.isPrimary) {
    LanRuntime.afterDatabase();
  }

  // 🔄 بدء المزامنة تلقائياً عند تشغيل التطبيق (بدون الحاجة للدخول لإعدادات المزامنة).
  //    fire-and-forget: لا نُعلّق الإقلاع؛ التهيئة تحدث في الخلفية.
  //    تتم فقط لو الرخصة مفعّلة (لا داعي للمزامنة على شاشة التفعيل).
  if (isLicenseActivated && AppNetworkMode.ownsDatabase && !DemoMode.isOn) {
    final license = licenseService.getStoredLicense();
    if (license != null && license.isSyncAllowed) {
      FirebaseSyncService().initialize().then((ok) {
        if (ok) {
          debugPrint('✅ [main.dart] بدأت المزامنة تلقائياً عند الإقلاع');
        } else {
          debugPrint('⚠️ [main.dart] تعذّر بدء المزامنة التلقائية (ستُحاول لاحقاً)');
        }
      }).catchError((e) {
        debugPrint('⚠️ [main.dart] خطأ في بدء المزامنة التلقائية: $e');
      });
    } else {
      debugPrint('ℹ️ [main.dart] المزامنة غير مشمولة لهذا الترخيص (${license?.appMode})');
    }
  }
}

/// 🔐 تسجيل مجهول مع إعادة محاولة تلقائية (3 محاولات بتراخٍ متزايد).
/// مصادقة Google على الويب/PWA قد تهتز لحظياً (شبكة/تغطية) — الإصرار
/// يعالج أغلب حالات "أول مرة يفشل ثم ينجح" ويُسجَّل الفشل للتشخيص.
Future<User?> _signInAnonymouslyWithRetry() async {
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      debugPrint('✅ [main.dart] تسجيل مجهول ناجح (محاولة $attempt): ${cred.user?.uid}');
      return cred.user;
    } catch (e) {
      debugPrint('❌ [main.dart] محاولة $attempt فشلت: $e');
      SyncDiagnostics.log('auth', 'محاولة تسجيل $attempt/3 فشلت — $e');
      if (attempt == 3) {
        SyncDiagnostics.logAuth(e);
        rethrow;
      }
      await Future.delayed(Duration(seconds: attempt * 3));
    }
  }
  return null;
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => POSProvider()),
        ChangeNotifierProvider(create: (_) => PurchaseService()),
        Provider<SuppliersService>(create: (_) => SuppliersService()),
        Provider<PrintingService>(create: (_) => getPlatformPrintingService()),
        // 🧠 AI Services
        Provider<EnsembleAIService>(create: (_) => EnsembleAIService()),
      ],
      child: MaterialApp(
        title: 'الناصر',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Cairo',
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 16),
            bodyMedium: TextStyle(fontSize: 14),
            titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        localizationsDelegates: const [
          // 📅 الأشهر بالأرقام في نوافذ التاريخ (قبل المندوب الافتراضي)
          NumericMonthsLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar', 'SA'),
        ],
        locale: const Locale('ar', 'SA'),
        routes: {
          '/': (context) => const _LicenseGuard(child: MainScreen()),
          '/main': (context) => const _LicenseGuard(child: MainScreen()),
          '/license': (context) => const LicenseScreen(), // 🔐
          '/license_check': (context) => const LicenseCheckScreen(), // 🔐
          '/license_devices': (context) => const _LicenseGuard(child: LicenseDevicesScreen()), // 🔐
          '/password_setup': (context) => const _LicenseGuard(requireLogin: false, child: PasswordSetupScreen()),
          '/login': (context) => const _LicenseGuard(requireLogin: false, child: LoginScreen()), // 👤
          '/user_management': (context) => const _LicenseGuard(child: UserManagementScreen()), // 👤
          '/general_settings': (context) => const _LicenseGuard(child: GeneralSettingsScreen()),
          '/product_entry_classic': (context) => const _LicenseGuard(child: ProductEntryScreen()),
          '/edit_products': (context) => const _LicenseGuard(child: EditProductsScreen()),
          // «التقارير الشهرية» القديمة ← التقارير (هذا الشهر)
          '/inventory': (context) => const _LicenseGuard(child: CustomRangeReportScreen()),
          '/reports': (context) => const _LicenseGuard(child: ReportsScreen()),
          '/ai_chat': (context) => const _LicenseGuard(child: AIChatScreen()),
          '/accounting': (context) => const _LicenseGuard(child: AccountingHomeScreen()), // 🏛️
          '/branches': (context) => const _LicenseGuard(child: BranchesWarehousesScreen()), // 🏢
          '/item_cards': (context) => const _LicenseGuard(child: ItemCardsListScreen()), // 🗂️
          '/network_settings': (context) => const _LicenseGuard(child: NetworkSettingsScreen()), // 🖧
          '/purchase_return': (context) => const _LicenseGuard(child: PurchaseReturnEditorScreen()), // ↩️
          '/dashboard': (context) => const _LicenseGuard(child: DashboardScreen()), // 📈
          '/sales_hub': (context) => const _LicenseGuard(child: SalesHubScreen()), // 🛒
          '/debts_hub': (context) => const _LicenseGuard(child: DebtsHubScreen()), // 💵
          '/inventory_hub': (context) => const _LicenseGuard(child: InventoryHubScreen()), // 📦
          '/accounting_plus': (context) => const _LicenseGuard(child: AccountingPlusHubScreen()), // 🏛️
        },
        // 🪟 الشاشات الست الرئيسية: شاشة كاملة أو نافذة منبثقة حسب الإعدادات ← الواجهة
        // (مكان واحد يشمل أزرار الرئيسية والشريط الجانبي واختصارات F1…F8)
        onGenerateRoute: (settings) {
          final builders = <String, WidgetBuilder>{
            '/pos': (context) => const _LicenseGuard(child: POSScreen()),
            '/create_invoice': (context) => const _LicenseGuard(child: CreateInvoiceScreen()),
            '/debt_register': (context) => const _LicenseGuard(child: HomeScreen()),
            '/edit_invoices': (context) => const _LicenseGuard(child: EditInvoicesScreen()),
            // 🗂️ «إدخال بضاعة» = بطاقة مادة الحديثة؛ الواجهة السابقة تبقى متاحة
            '/product_entry': (context) => const _LicenseGuard(child: ProductEntryRouter()),
            '/suppliers': (context) => const _LicenseGuard(child: SuppliersDashboardScreen()), // 🆕 شاشة موردين واحدة
          };
          final b = builders[settings.name];
          return b == null ? null : PopupScreens.route(settings, b);
        },
        initialRoute: initialRoute,
        navigatorKey: globalNavigatorKey, // ✅ مفتاح الملاح العام
        navigatorObservers: [sideNavObserver, SaveLock.newObserver()],
        // ⌨️ اختصارات لوحة المفاتيح لكل الشاشات (F1 الكاشير، F2 قائمة، F4 المحاسبة...)
        builder: (context, child) =>
            GlobalShortcuts(
              navigatorKey: globalNavigatorKey,
              // 🧭 اللوحة الجانبية مرة واحدة حول كل الشاشات
              // 🔒 غطاء قفل الحفظ فوق كل شيء (يمنع الضغط المزدوج على أي «حفظ»)
              child: SaveLockBarrier(
                child: GlobalSideNav(
                  navigatorKey: globalNavigatorKey,
                  observer: sideNavObserver,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
      ),
    );
  }
}

/// 🛡️ حارس المسارات المركزي: يمنع فتح أو عرض أي شاشة داخلية إلا بترخيص معتمد وموثّق
class _LicenseGuard extends StatelessWidget {
  final Widget child;
  /// 👤 كل الشاشات الداخلية تحتاج مستخدماً مسجّلاً (عدا شاشة الدخول نفسها)
  final bool requireLogin;
  const _LicenseGuard({required this.child, this.requireLogin = true});
  static bool _toLogin = false; // يمنع تكرار التحويل إن أُعيد الرسم قبل الانتقال

  /// شاشات ترخيص «سجل الديون» (الديون، التقارير، الإعدادات ورفع القاعدة)
  static const Set<String> _debtsOnlyRoutes = {
    '/', '/main', '/login', '/password_setup', '/user_management', '/general_settings',
    '/debt_register', '/reports', '/debts_hub', '/license_devices',
  };

  @override
  Widget build(BuildContext context) {
    final licenseService = LicenseService();
    if (!licenseService.isLicenseActivated()) {
      // 🔒 غير مصرح: طرد فوري إلى شاشة الترخيص بدون رسم أي عنصر من الشاشة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.of(context).pushNamedAndRemoveUntil('/license', (route) => false);
        } else {
          Navigator.of(context).pushReplacementNamed('/license');
        }
      });
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FB),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 48, color: Color(0xFF0D47A1)),
              SizedBox(height: 16),
              Text(
                '🔒 يلزم تفعيل الترخيص والمصادقة للوصول إلى النظام',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }
    // 🧩 النمط من الترخيص الموقَّع: «سجل الديون» لا يفتح إلا شاشاته، مهما كان
    //    طريق الوصول إلى المسار (اختصار لوحة مفاتيح، زر داخلي...).
    final lic = licenseService.getStoredLicense();
    final routeName = ModalRoute.of(context)?.settings.name;
    if (lic != null && lic.isDebtsOnly && routeName != null && !_debtsOnlyRoutes.contains(routeName)) {
      return Scaffold(
        appBar: AppBar(title: const Text('غير مشمول في ترخيصك')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'هذه الشاشة غير مشمولة في ترخيص «سجل الديون».\n'
              'للترقية تواصل مع صاحب البرنامج: ${LicenseConfig.supportPhone}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.6),
            ),
          ),
        ),
      );
    }
    if (requireLogin && !AuthService().isLoggedIn) {
      // 🔐 لا مستخدم مسجّل: إلى شاشة الدخول قبل رسم أي بيانات
      if (!_toLogin) {
        _toLogin = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _toLogin = false;
          if (!context.mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        });
      }
      return const Scaffold(backgroundColor: Color(0xFF0F3460), body: SizedBox.shrink());
    }
    return child;
  }
}

