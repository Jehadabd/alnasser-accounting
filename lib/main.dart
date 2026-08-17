// main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:get_storage/get_storage.dart';
import 'package:window_manager/window_manager.dart'; // 🪟 التحكم في نافذة Windows
import 'providers/app_provider.dart';
import 'providers/pos_provider.dart';
import 'screens/home_screen.dart';
import 'screens/main_screen.dart';
import 'screens/product_entry_screen.dart';
import 'screens/create_invoice_screen.dart';
import 'screens/edit_invoices_screen.dart';
import 'screens/edit_products_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/reports_screen.dart';
// removed font settings screen import
import 'screens/suppliers_list_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/pos/pos_screen.dart';
import 'services/password_service.dart';
import 'services/database_service.dart';
import 'services/firebase_sync/firebase_sync_service.dart';
import 'screens/password_setup_screen.dart';
import 'screens/general_settings_screen.dart';
import 'screens/login_screen.dart'; // 👤
import 'screens/user_management_screen.dart'; // 👤
import 'services/printing_service_windows.dart';
import 'services/printing_service.dart';
import 'services/printing_service_platform_io.dart';
import 'services/auth_service.dart'; // 👤
import 'services/purchase_service.dart'; // 🆕
import 'services/suppliers_service.dart'; // 🆕 (Fix Provider Error)
import 'services/license_service.dart'; // 🔐
import 'screens/license_screen.dart'; // 🔐
import 'services/alert_service.dart'; // 🔔 Restored
import 'services/font_manager.dart'; // 🔡 Font management
import 'services/ensemble_ai_service.dart'; // 🧠 AI Service
import 'screens/reconciliation_prompt.dart';

import 'package:firebase_core/firebase_core.dart'; // 🆕 Firebase
import 'package:firebase_auth/firebase_auth.dart'; // 🔐 Firebase Authentication
import 'services/firebase_sync/firebase_custom_config.dart'; // 🆕 Firebase Config

/// 🔥 مفتاح الملاح العام — يُستخدم من ReconciliationPrompt وغيرها لإظهار
/// حوارات من خارج شجرة الويدجت.
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة GetStorage
  await GetStorage.init();

  // تهيئة الخطوط العربية
  await FontManager.loadArabicFonts();

  // Force Landscape Orientation on Mobile
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // تحميل ملف .env من عدة مواقع محتملة
  bool envLoaded = false;
  try {
    // محاولة 1: من مجلد التطبيق الحالي (للـ EXE)
    final exeDir = Platform.resolvedExecutable;
    final exePath = exeDir.substring(0, exeDir.lastIndexOf(Platform.pathSeparator));
    final envFile = File('$exePath${Platform.pathSeparator}.env');

    if (await envFile.exists()) {
      await dotenv.load(fileName: envFile.path);
      envLoaded = true;
      print('✅ تم تحميل .env من مجلد التطبيق: ${envFile.path}');
    }
  } catch (e) {
    print('⚠️ فشل تحميل .env من مجلد التطبيق: $e');
  }

  // محاولة 2: من المجلد الافتراضي (للتطوير)
  if (!envLoaded) {
    try {
      await dotenv.load();
      envLoaded = true;
      print('✅ تم تحميل .env من المجلد الافتراضي');
    } catch (e) {
      print('⚠️ ملف .env غير موجود - سيتم استخدام القيم الافتراضية المُضمنة');
    }
  }

  // تهيئة sqflite_common_ffi على الديسكتوب فقط (ويندوز/لينكس/ماك).
  // على أندرويد نترك databaseFactory الافتراضية لمكتبة sqflite + sqlite3_flutter_libs (دعم FTS5).
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  //Ensure Supplier Tables exist (Migration)
  try {
     await SuppliersService().ensureTables();
  } catch (e) {
     print('⚠️ Error ensuring supplier tables: $e');
  }

  // فحص سلامة البيانات المالية (صامت - بدون طباعة)
  try {
    final dbService = DatabaseService();
    await dbService.performQuickIntegrityCheck();
  } catch (e) {
    // تجاهل الخطأ - لا نوقف التطبيق
  }

  // 🪟 تهيئة WindowManager (يحتاجه main_screen للتحكم في إغلاق النافذة).
  // ملاحظة مهمة: نكتفي بـ ensureInitialized فقط — لا نستخدم waitUntilReadyToShow
  // لأنها قد تعلّق التطبيق وتمنع ظهور النافذة. Flutter سيعرض النافذة الافتراضية
  // تلقائياً عند runApp(). هذا يطابق سلوك النسخة الأصلية الشغّالة.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      print('⚠️ فشل تهيئة WindowManager (المتابعة بالنافذة الافتراضية): $e');
    }
  }

  // 🔴 🔥 تهيئة Firebase باستخدام الإعدادات المخصصة إذا كانت متوفرة
  try {
    print('🔥 [main.dart] ════════════════════════════════════════');
    print('🔥 [main.dart] بدء تهيئة Firebase...');
    
    final customOptions = await FirebaseCustomConfig.getCustomOptions();
    if (customOptions != null) {
      print('✅ [main.dart] وجدت إعدادات Firebase المخصصة');
      print('✅ [main.dart] ProjectId: ${customOptions.projectId}');
      print('✅ [main.dart] AppId: ${customOptions.appId}');
      
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: customOptions);
        print('✅ [main.dart] تم تهيئة Firebase بنجاح');
        print('✅ تم تهيئة Firebase بنجاح بالإعدادات المخصصة.');
      } else {
        print('✅ [main.dart] تم تهيئة Firebase مسبقاً (ربما بسبب Hot Restart)');
      }
      
      // 🔐 تسجيل دخول تلقائي لـ Firebase Authentication
      // هذا ضروري لأن قواعد Firestore تتطلب: request.auth != null
      try {
        print('🔐 [main.dart] فحص حالة المصادقة...');
        final currentUser = FirebaseAuth.instance.currentUser;
        
        if (currentUser == null) {
          // لا يوجد مستخدم - قم بتسجيل دخول مجهول
          print('🔐 [main.dart] لا يوجد مستخدم - محاولة تسجيل الدخول المجهول...');
          print('🔐 تسجيل دخول مجهول لـ Firebase...');
          
          final userCredential = await FirebaseAuth.instance.signInAnonymously();
          
          print('✅ [main.dart] تم تسجيل الدخول المجهول بنجاح!');
          print('✅ [main.dart] User UID: ${userCredential.user?.uid}');
          print('✅ [main.dart] isAnonymous: ${userCredential.user?.isAnonymous}');
          print('✅ تم تسجيل الدخول المجهول بنجاح: ${userCredential.user?.uid}');
          
          // ✅ فحص Token
          try {
            final token = await userCredential.user?.getIdToken();
            print('✅ [main.dart] Token موجود وصالح (length: ${token?.length ?? 0})');
          } catch (e) {
            print('❌ [main.dart] فشل الحصول على Token: $e');
          }
          
        } else {
          print('✅ [main.dart] مستخدم Firebase موجود بالفعل');
          print('✅ [main.dart] User UID: ${currentUser.uid}');
          print('✅ [main.dart] isAnonymous: ${currentUser.isAnonymous}');
          print('✅ مستخدم Firebase موجود بالفعل: ${currentUser.uid}');
          
          // ✅ فحص Token للمستخدم الموجود
          try {
            final token = await currentUser.getIdToken();
            print('✅ [main.dart] Token موجود وصالح (length: ${token?.length ?? 0})');
          } catch (e) {
            print('❌ [main.dart] فشل الحصول على Token: $e');
          }
        }
        
        print('🎉 [main.dart] Firebase Authentication جاهز!');
        
      } catch (authError) {
        print('❌ [main.dart] خطأ في تسجيل الدخول لـ Firebase Auth!');
        print('❌ [main.dart] Error Type: ${authError.runtimeType}');
        print('❌ [main.dart] Error: $authError');
        print('⚠️ خطأ في تسجيل الدخول لـ Firebase Auth: $authError');
        print('💡 تأكد من تفعيل Anonymous Authentication في Firebase Console');
        print('💡 [main.dart] تحقق من Firebase Console → Authentication → Sign-in method → Anonymous');
      }
      
    } else {
      print('ℹ️ [main.dart] لم يتم العثور على إعدادات Firebase مخصصة');
      print('ℹ️ لم يتم العثور على إعدادات Firebase مخصصة. سيتم تخطي التهيئة.');
    }
    print('🔥 [main.dart] ════════════════════════════════════════');
  } catch (e, stackTrace) {
    print('❌ [main.dart] خطأ أثناء تهيئة Firebase!');
    print('❌ [main.dart] Error Type: ${e.runtimeType}');
    print('❌ [main.dart] Error: $e');
    print('❌ [main.dart] StackTrace: $stackTrace');
    print('⚠️ خطأ أثناء تهيئة Firebase: $e');
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

  // 🔥 تفعيل نظام المطابقة وحل التعارضات عند التشغيل
  ReconciliationPrompt.start();

  runApp(MyApp(initialRoute: initialRoute));

  // 🔄 بدء المزامنة تلقائياً عند تشغيل التطبيق (بدون الحاجة للدخول لإعدادات المزامنة).
  //    fire-and-forget: لا نُعلّق الإقلاع؛ التهيئة تحدث في الخلفية.
  //    تتم فقط لو الرخصة مفعّلة (لا داعي للمزامنة على شاشة التفعيل).
  if (isLicenseActivated) {
    FirebaseSyncService().initialize().then((ok) {
      if (ok) {
        print('✅ [main.dart] بدأت المزامنة تلقائياً عند الإقلاع');
      } else {
        print('⚠️ [main.dart] تعذّر بدء المزامنة التلقائية (ستُحاول لاحقاً)');
      }
    }).catchError((e) {
      print('⚠️ [main.dart] خطأ في بدء المزامنة التلقائية: $e');
    });
  }
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
        title: 'دفتر ديوني',
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
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar', 'SA'),
        ],
        locale: const Locale('ar', 'SA'),
        routes: {
          '/': (context) => const MainScreen(),
          '/main': (context) => const MainScreen(),
          '/license': (context) => const LicenseScreen(), // 🔐
          '/license_check': (context) => const LicenseCheckScreen(), // 🔐
          '/password_setup': (context) => const PasswordSetupScreen(),
          '/login': (context) => const LoginScreen(), // 👤
          '/user_management': (context) => const UserManagementScreen(), // 👤
          '/general_settings': (context) => const GeneralSettingsScreen(),
          // removed font settings route

          '/debt_register': (context) => const HomeScreen(),
          '/product_entry': (context) => const ProductEntryScreen(),
          '/create_invoice': (context) => const CreateInvoiceScreen(),
          '/edit_invoices': (context) => const EditInvoicesScreen(),
          '/edit_products': (context) => const EditProductsScreen(),
          '/inventory': (context) => const InventoryScreen(),
          '/reports': (context) => const ReportsScreen(),
          '/suppliers': (context) => const SuppliersListScreen(), // 🆕
          '/ai_chat': (context) => const AIChatScreen(),
          '/pos': (context) => const POSScreen(),
        },
        initialRoute: initialRoute,
        navigatorKey: globalNavigatorKey, // ✅ مفتاح الملاح العام
      ),
    );
  }
}
