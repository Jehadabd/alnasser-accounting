// screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemNavigator (إغلاق آمن متعدد المنصات)
import 'package:intl/intl.dart' hide TextDirection;
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/telegram_backup_service.dart';
import '../services/telegram_invoice_export_service.dart';
import '../services/dropbox_backup_service.dart'; // ☁️ Dropbox
import '../models/customer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/password_service.dart';
import '../screens/general_settings_screen.dart';
import '../services/auth_service.dart'; // 👤
import '../models/app_user.dart'; // 👤 AppPermissions
import '../screens/overdue_debts_screen.dart';
import '../services/debt_report_service.dart';
import '../services/reports_service.dart'; // ✅ Added
import '../services/settings_manager.dart'; // ✅ Added
import '../screens/suppliers/suppliers_dashboard_screen.dart'; // ✅ Added
import 'inventory_menu_screen.dart'; // ✅ Added
import '../services/alert_service.dart'; // 🔔 Added
import '../models/app_settings.dart';
import '../widgets/app_side_nav.dart';
import '../widgets/sync_health_banner.dart'; // 🩺 تنبيهات صحة المزامنة
import '../lan/lan_status_banner.dart';
import '../services/license_service.dart'; // 🔐 نظام التراخيص
// ملاحظة: حُذف استيراد window_manager لأنه كان يعتمد على تهيئة مخصصة في main.dart
// تسبب تعليق التطبيق ومنع ظهور الشاشة. الإغلاق الآن عبر SystemNavigator.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _currentMonthYear = '';
  final PasswordService _passwordService = PasswordService();
  final AuthService _authService = AuthService(); // 👤
  final Color _primaryColor = const Color(0xFF6C63FF);
  final Color _accentColor = const Color(0xFFFFD54F);
  final Color _backgroundColor = const Color(0xFFF5F7FB);

  AppSettings? _appSettings;

  @override
  void initState() {
    super.initState();
    _updateCurrentMonthYear();
    _loadSettings();
    // تأكد من تهيئة مزود التطبيق لتفعيل دعم Google Drive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().initialize();
      // 🔔 تم نقل فحص التنبيهات إلى main.dart بناءً على طلب المستخدم
    });
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.getAppSettings();
    if (mounted) setState(() => _appSettings = settings);
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// رسالة تأكيد الخروج مع خيار النسخ الاحتياطي
  Future<bool> _showExitConfirmation() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.exit_to_app, color: _primaryColor),
              const SizedBox(width: 8),
              const Text('إغلاق التطبيق'),
            ],
          ),
          content: const Text(
            'هل تريد إنشاء نسخة احتياطية قبل الخروج؟',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'exit'),
              child: const Text('خروج بدون نسخ', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, 'backup'),
              icon: const Icon(Icons.backup),
              label: const Text('نسخ ثم خروج'),
            ),
          ],
        ),
      ),
    );
    
    if (result == 'cancel' || result == null) {
      return false; // لا تخرج
    }
    
    if (result == 'backup') {
      // إنشاء نسخة احتياطية
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('جاري إنشاء النسخة الاحتياطية...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }
      
      final db = DatabaseService();
      final backupResult = await db.createLocalBackup();
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (backupResult.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ تم حفظ النسخة الاحتياطية'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${backupResult.message}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      
      // انتظر قليلاً لعرض الرسالة
      await Future.delayed(const Duration(seconds: 1));
    }
    
    return true; // اخرج
  }


  void _updateCurrentMonthYear() {
    final now = DateTime.now();
    _currentMonthYear = DateFormat.yMMMM('ar').format(now);
  }

  // 👤 فحص الصلاحية قبل السماح بالوصول
  bool _checkPermission(String permissionKey) {
    if (!_authService.hasPermission(permissionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.block, color: Colors.white),
              const SizedBox(width: 8),
              Text('ليس لديك صلاحية للوصول إلى هذه الميزة'),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الرجاء إدخال كلمة السر',
            style: TextStyle(fontSize: 20)),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.lock, size: 28),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
          style: const TextStyle(fontSize: 18),
          autofocus: true,
          onSubmitted: (value) async {
            final bool isCorrect = await _passwordService.verifyPassword(value);
            Navigator.of(context).pop(isCorrect);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: () async {
              final bool isCorrect = await _passwordService
                  .verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildFeatureButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = const Color(0xFF6C63FF),
    double fontSize = 40,
    double iconSize = 30,
    double padding = 6,
    double spacing = 4,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: color),
            SizedBox(height: spacing),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern specific button for targeted features
  Widget _buildModernFeatureButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 38, color: color),
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E1E2E),
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 22, 
                  height: 3, 
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.4), 
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final license = LicenseService().getStoredLicense();
    
    // 🔒 حارس الشاشة: إذا لم يكن هناك ترخيص موثّق، نمنع رسم أي عنصر ونطرد المتصفح فوراً
    if (license == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/license', (route) => false);
        }
      });
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FB),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final bool isDebtsOnly = license.isDebtsOnly;
    final screenWidth = MediaQuery.of(context).size.width;

    // 📱 حساب عدد الأعسبة ونسبة الحجم استجابياً حسب حجم الشاشة ونوع الترخيص
    int crossAxisCount;
    double childAspectRatio;
    double gridSpacing;

    if (isDebtsOnly) {
      // 📘 نمط سجل الديون (4 أزرار فقط)
      if (screenWidth < 600) {
        // جوال عمودي: 2 عمود × 2 صفوف (تنسيق أنيق وشاشات كبيرة)
        crossAxisCount = 2;
        childAspectRatio = 1.15;
        gridSpacing = 16.0;
      } else if (screenWidth < 900) {
        // جوال أفقي / تابلت صغير: 4 أزرار بصف واحد
        crossAxisCount = 4;
        childAspectRatio = 1.05;
        gridSpacing = 20.0;
      } else {
        // تابلت كبير / ديسكتوب: 4 أزرار بصف واحد متباعد
        crossAxisCount = 4;
        childAspectRatio = 1.25;
        gridSpacing = 24.0;
      }
    } else {
      // 🏬 التطبيق الكامل (9 أزرار)
      if (screenWidth < 500) {
        crossAxisCount = 2;
        childAspectRatio = 1.05;
        gridSpacing = 14.0;
      } else if (screenWidth < 800) {
        crossAxisCount = 3;
        childAspectRatio = 1.0;
        gridSpacing = 16.0;
      } else if (screenWidth < 1100) {
        crossAxisCount = 4;
        childAspectRatio = 1.05;
        gridSpacing = 20.0;
      } else {
        crossAxisCount = 5;
        childAspectRatio = 1.15;
        gridSpacing = 24.0;
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && mounted) {
          // إغلاق التطبيق فعلياً عبر كل المنصات (ويندوز/أندرويد).
          // استخدمنا SystemNavigator بدل windowManager.destroy() لتجنب
          // الاعتماد على window_manager الذي كان يعليق التطبيق.
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('الناصر', style: TextStyle(fontSize: 24)),
        centerTitle: true,
        backgroundColor: _primaryColor,
        elevation: 0,
        actions: [
          // 👤 Logout button (only if users exist)
          FutureBuilder<bool>(
            future: _authService.hasAnyUsers(),
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'تسجيل الخروج',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('تسجيل الخروج'),
                      content: const Text('هل تريد تسجيل الخروج؟'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('خروج', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _authService.logout();
                    if (mounted) {
                      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Row(
        children: [
          if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
            const AppSideNav(currentRoute: '/main'),
          Expanded(
            child: Column(
              children: [
                // 🩺 تنبيهات صحة المزامنة (لا يظهر شيء ما دام كل شيء سليماً)
                const SyncHealthBanner(),
                // 🖧 حالة الاتصال بحاسبة السيرفر (طرفية) أو عدد الطرفيات (سيرفر)
                const LanStatusBanner(),
                Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: gridSpacing,
          crossAxisSpacing: gridSpacing,
          childAspectRatio: childAspectRatio,
          children: [
            // 💰 POS Button - Only for Full App
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.point_of_sale,
                title: 'الكاشير',
                onTap: () {
                  if (_checkPermission(AppPermissions.posAccess)) {
                    Navigator.pushNamed(context, '/pos');
                  }
                },
                color: const Color(0xFFFF5722), // Vibrant Orange
              ),

            _buildModernFeatureButton(
              icon: Icons.book,
              title: 'سجل الديون',
              onTap: () {
                if (_checkPermission(AppPermissions.debtRegister)) {
                  Navigator.pushNamed(context, '/debt_register');
                }
              },
              color: _primaryColor,
            ),
            
            // 🆕 زر المخزون - Only for Full App
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.inventory_2, // أيقونة المخزون
                title: 'المخزون',
                onTap: () {
                  if (_checkPermission(AppPermissions.productEntry) || _checkPermission(AppPermissions.editProducts)) {
                     Navigator.push(
                       context,
                       MaterialPageRoute(builder: (context) => const InventoryMenuScreen()),
                     );
                  }
                },
                color: const Color(0xFF4CAF50),
              ),

            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.list_alt,
                title: 'إنشاء قائمة',
                onTap: () {
                  if (_checkPermission(AppPermissions.createInvoice)) {
                    Navigator.pushNamed(context, '/create_invoice');
                  }
                },
                color: const Color(0xFF2196F3),
              ),
            
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.edit_note,
                title: 'تعديل القوائم',
                onTap: () {
                  if (_checkPermission(AppPermissions.editInvoices)) {
                    Navigator.pushNamed(context, '/edit_invoices');
                  }
                },
                color: const Color(0xFF795548),
              ),

            _buildModernFeatureButton(
              icon: Icons.cloud_upload,
              title: 'رفع البيانات',
              onTap: () async {
                if (!_checkPermission(AppPermissions.uploadDatabase)) return;
                final progressNotifier = ValueNotifier<double>(0.0);
                final statusNotifier = ValueNotifier<String>('جاري تحضير النسخة الاحتياطية...');
                final errorNotifier = ValueNotifier<String?>(''); // لتتبع الأخطاء
                bool uploadSucceeded = false;

                // جلب وقت آخر رفع
                final telegramService = TelegramBackupService();
                final lastUploadTime = await telegramService.getLastUploadTime();
                
                // طباعة معلومات التشخيص
                final diagnostics = await telegramService.getDiagnostics();
                print('📊 معلومات تشخيص Telegram:');
                diagnostics.forEach((key, value) => print('   $key: $value'));

                // ابدأ الرفع في مهمة منفصلة وتحديث المؤشر ثم إغلاق الحوار
                Future(() async {
                  try {
                    // متغير لتتبع نجاح إرسال الفواتير لتيليجرام
                    bool allInvoicesSentSuccessfully = true;
                    List<String> errors = [];
                    
                    // 1) رفع قاعدة البيانات إلى Telegram (محلي + تيليجرام فقط)
                    await context.read<AppProvider>().backupDatabaseToTelegram(
                      onProgress: (p) {
                        progressNotifier.value = p * 0.5; // 50% للرفع الأساسي
                      },
                    );

                    // 2) إرسال الفواتير إلى Telegram
                    final bool isConfigured = await telegramService.isConfigured;
                    if (isConfigured) {
                      DateTime? exportAfterDate = lastUploadTime;
                      
                      // إذا كان الرفع للمرة الأولى، نسأل المستخدم عن المدى الزمني
                      if (exportAfterDate == null) {
                        statusNotifier.value = 'بانتظار اختيار مدى الفواتير...';
                        
                        // الخيارات المتاحة للمستخدم
                        final rangeChoice = await showDialog<String>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => AlertDialog(
                            title: const Text('أول عملية رفع للفواتير'),
                            content: const Text('يرجى اختيار مدى الفواتير التي ترغب في إرسالها إلى Telegram للمرة الأولى:'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, '24h'),
                                child: const Text('آخر 24 ساعة'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, 'week'),
                                child: const Text('آخر أسبوع'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, 'all'),
                                child: const Text('الكل (قد يستغرق وقتاً)'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, 'cancel'),
                                child: const Text('إلغاء رفع الفواتير', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );

                        if (rangeChoice == 'cancel' || rangeChoice == null) {
                          // تخطي رفع الفواتير ولكن استمر في الباقي
                          exportAfterDate = null; 
                        } else if (rangeChoice == '24h') {
                          exportAfterDate = DateTime.now().subtract(const Duration(days: 1));
                        } else if (rangeChoice == 'week') {
                          exportAfterDate = DateTime.now().subtract(const Duration(days: 7));
                        } else if (rangeChoice == 'all') {
                          exportAfterDate = DateTime(2000); // تاريخ قديم جداً يشمل الكل
                        }
                      }

                      if (exportAfterDate != null) {
                        statusNotifier.value = 'جاري إرسال الفواتير...';
                        final exportService = TelegramInvoiceExportService();
                        final exportResult = await exportService.exportAndSendNewInvoices(
                          afterDate: exportAfterDate,
                          onProgress: (current, total, status) {
                            if (total > 0) {
                              progressNotifier.value = 0.5 + (current / total) * 0.40;
                              statusNotifier.value = status;
                            }
                          },
                        );
                        
                        // التحقق من نجاح إرسال جميع الفواتير
                        if (exportResult.failedCount > 0) {
                          allInvoicesSentSuccessfully = false;
                          errors.add('فشل إرسال ${exportResult.failedCount} فاتورة');
                        }
                      }
                    } else {
                      errors.add('إعدادات Telegram غير مكتملة');
                    }

                    // 3) إرسال الملخص الشهري إلى Telegram
                    if (await telegramService.isConfigured) {
                      statusNotifier.value = 'جاري إرسال الملخص الشهري...';
                      progressNotifier.value = 0.85;
                      final summaryResult = await telegramService.sendMonthlySummaryWithDetails();
                      if (!summaryResult.success) {
                        errors.add('فشل إرسال الملخص الشهري: ${summaryResult.errorMessage}');
                        if (summaryResult.errorDetails != null) {
                          errors.add('التفاصيل: ${summaryResult.errorDetails}');
                        }
                      }
                    }

                    // 4) رفع النسخة الاحتياطية إلى Dropbox (إذا كان متصلاً)
                    final dropboxService = DropboxBackupService();
                    final dropboxStatus = await dropboxService.checkAuthStatus();
                    if (dropboxStatus == DropboxAuthStatus.authenticated) {
                      statusNotifier.value = 'جاري رفع النسخة إلى Dropbox...';
                      progressNotifier.value = 0.90;
                      
                      final dropboxResult = await dropboxService.createAndUploadBackup(
                        maxBackups: 20,
                        onProgress: (p, s) {
                          progressNotifier.value = 0.90 + (p / 1000); // 0.90 - 0.95
                        },
                      );
                      
                      if (dropboxResult.success) {
                        statusNotifier.value = '✅ تم رفع النسخة إلى Dropbox';
                      } else {
                        errors.add('Dropbox: ${dropboxResult.error}');
                      }
                    }

                    // 5) حفظ وقت الرفع الحالي فقط إذا نجح إرسال جميع الفواتير
                    if (allInvoicesSentSuccessfully && errors.isEmpty) {
                      await telegramService.saveLastUploadTime();
                    }
                    
                    progressNotifier.value = 1.0;
                    
                    if (errors.isNotEmpty) {
                      errorNotifier.value = errors.join('\n');
                      uploadSucceeded = false;
                    } else {
                      uploadSucceeded = true;
                    }
                  } catch (e) {
                    print('Backup error: $e');
                    errorNotifier.value = 'خطأ: $e';
                    uploadSucceeded = false;
                  } finally {
                    if (Navigator.of(context, rootNavigator: true).canPop()) {
                      Navigator.of(context, rootNavigator: true).pop({
                        'success': uploadSucceeded,
                        'error': errorNotifier.value,
                      });
                    }
                  }
                });

                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => AlertDialog(
                    title: const Text('رفع قاعدة البيانات'),
                    content: ValueListenableBuilder<double>(
                      valueListenable: progressNotifier,
                      builder: (context, progress, _) => ValueListenableBuilder<String>(
                        valueListenable: statusNotifier,
                        builder: (context, status, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(value: progress <= 0 || progress >= 1 ? null : progress),
                            const SizedBox(height: 12),
                            Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                            const SizedBox(height: 8),
                            Text(status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                if (result?['success'] == true) {
                  // التحقق من حالة Dropbox لعرض رسالة مناسبة
                  final dropboxStatus = await DropboxBackupService().checkAuthStatus();
                  String successMessage = 'تم رفع قاعدة البيانات وإرسال الفواتير بنجاح';
                  if (dropboxStatus == DropboxAuthStatus.authenticated) {
                    successMessage += '\n☁️ تم رفع نسخة إلى Dropbox';
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(successMessage),
                    duration: const Duration(seconds: 4),
                    backgroundColor: Colors.green,
                  ));
                } else {
                  final errorMsg = result?['error'] as String?;
                  // عرض dialog مفصل للخطأ
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text('فشل الإرسال'),
                        ],
                      ),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('حدث خطأ أثناء إرسال البيانات إلى Telegram:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Text(
                                errorMsg ?? 'خطأ غير معروف - تحقق من اتصال الإنترنت',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('الحلول المقترحة:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            const Text('• تأكد من اتصال الإنترنت'),
                            const Text('• تأكد من إعدادات بوت Telegram'),
                            const Text('• حاول مرة أخرى بعد قليل'),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('حسناً'),
                        ),
                      ],
                    ),
                  );
                }
              },
              color: const Color(0xFF0D47A1),
            ),
            _buildModernFeatureButton(
              icon: Icons.settings,
              title: 'الإعدادات',
              onTap: () {
                if (_checkPermission(AppPermissions.settings)) {
                  Navigator.pushNamed(context, '/general_settings');
                }
              },
              color: const Color(0xFF607D8B),
            ),
            
            // تم حذف الزر "الجرد الشهري" من هنا، وسيتم إضافته داخل التقارير
            _buildModernFeatureButton(
              icon: Icons.analytics,
              title: 'التقارير',
              onTap: () async {
                if (!_checkPermission(AppPermissions.reports)) return;
                Navigator.pushNamed(context, '/reports');
              },
              color: const Color(0xFF673AB7),
            ),           
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.factory,
                title: 'الموردون',
                onTap: () {
                  if (_checkPermission(AppPermissions.suppliers)) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SuppliersDashboardScreen(),
                      ),
                    );
                  }
                },
                color: const Color(0xFF455A64),
              ),

            // 📈 لوحة المؤشرات والمراكز الجديدة
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.dashboard_rounded,
                title: 'لوحة المؤشرات',
                onTap: () {
                  if (_checkPermission(AppPermissions.dashboard)) {
                    Navigator.pushNamed(context, '/dashboard');
                  }
                },
                color: const Color(0xFF1B6CA8),
              ),
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.storefront_rounded,
                title: 'المبيعات والمستندات',
                onTap: () {
                  if (_authService.hasPermission(AppPermissions.createInvoice) ||
                      _checkPermission(AppPermissions.salesDocs)) {
                    Navigator.pushNamed(context, '/sales_hub');
                  }
                },
                color: const Color(0xFF0E7C61),
              ),
            _buildModernFeatureButton(
              icon: Icons.request_quote_rounded,
              title: 'التحصيل والديون',
              onTap: () {
                if (_authService.hasPermission(AppPermissions.debtRegister) ||
                    _checkPermission(AppPermissions.collection)) {
                  Navigator.pushNamed(context, '/debts_hub');
                }
              },
              color: const Color(0xFFC0392B),
            ),
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.warehouse_rounded,
                title: 'المخزون',
                onTap: () {
                  if (_authService.hasPermission(AppPermissions.itemCard) ||
                      _authService.hasPermission(AppPermissions.inventoryReports) ||
                      _checkPermission(AppPermissions.inventoryDocs)) {
                    Navigator.pushNamed(context, '/inventory_hub');
                  }
                },
                color: const Color(0xFF5B3CC4),
              ),

            // 🏛️ النسخة المحاسبية
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.account_balance,
                title: 'المحاسبة',
                onTap: () {
                  if (_checkPermission(AppPermissions.accounting)) {
                    Navigator.pushNamed(context, '/accounting');
                  }
                },
                color: const Color(0xFF0F3460),
              ),
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.account_balance_wallet_rounded,
                title: 'المحاسبة المتقدمة',
                onTap: () {
                  if (_checkPermission(AppPermissions.accounting)) {
                    Navigator.pushNamed(context, '/accounting_plus');
                  }
                },
                color: const Color(0xFF16213E),
              ),
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.inventory,
                title: 'بطاقات المواد',
                onTap: () {
                  if (_checkPermission(AppPermissions.itemCard)) {
                    Navigator.pushNamed(context, '/item_cards');
                  }
                },
                color: const Color(0xFF00B4D8),
              ),
            if (!isDebtsOnly)
              _buildModernFeatureButton(
                icon: Icons.warehouse,
                title: 'الفروع والمخازن',
                onTap: () {
                  if (_authService.hasPermission(AppPermissions.stockTransfer) ||
                      _checkPermission(AppPermissions.manageBranches)) {
                    Navigator.pushNamed(context, '/branches');
                  }
                },
                color: const Color(0xFF047857),
              ),
            _buildModernFeatureButton(
              icon: Icons.lan,
              title: 'الشبكة',
              onTap: () {
                if (_checkPermission(AppPermissions.networkSettings)) {
                  Navigator.pushNamed(context, '/network_settings');
                }
              },
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
      ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
