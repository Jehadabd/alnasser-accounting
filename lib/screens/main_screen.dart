// screens/main_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemNavigator (إغلاق آمن متعدد المنصات)
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/telegram_backup_service.dart';
import '../services/telegram_invoice_export_service.dart';
import '../services/dropbox_backup_service.dart'; // ☁️ Dropbox
import 'dart:io';
import '../services/discord_backup_service.dart';
import '../services/upload_targets.dart';
import '../owner/google_drive_service.dart';
import '../owner/owner_access.dart';
import '../services/auth_service.dart'; // 👤
import '../models/app_user.dart'; // 👤 AppPermissions
import '../services/debt_reminders.dart'; // 📅
import 'debt_reminders_screen.dart' show showDueRemindersDialog;
import '../services/reports_service.dart'; // ✅ Added
import '../services/settings_manager.dart'; // ✅ Added
import '../screens/suppliers/suppliers_dashboard_screen.dart'; // ✅ Added
import '../widgets/global_search.dart'; // 🔎 Ctrl+K
import '../services/demo_mode.dart';
import '../services/demo_seeder.dart';
import '../models/app_settings.dart';
import '../widgets/app_side_nav.dart';
import '../widgets/home_destinations.dart';
import '../widgets/user_menu_button.dart'; // 👤
import '../widgets/sync_health_banner.dart'; // 🩺 تنبيهات صحة المزامنة
import '../lan/lan_status_banner.dart';
import '../erp/currency_service.dart' show CurrencyService;
import '../widgets/report_kit.dart' show repMoney, repCanSeeProfit;
import 'custom_range_report_screen.dart';
import '../services/license_service.dart'; // 🔐 نظام التراخيص
// ملاحظة: حُذف استيراد window_manager لأنه كان يعتمد على تهيئة مخصصة في main.dart
// تسبب تعليق التطبيق ومنع ظهور الشاشة. الإغلاق الآن عبر SystemNavigator.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AuthService _authService = AuthService(); // 👤
  final Color _primaryColor = const Color(0xFF6C63FF);

  AppSettings? _appSettings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // تأكد من تهيئة مزود التطبيق لتفعيل دعم Google Drive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().initialize();
      // 🔔 تم نقل فحص التنبيهات إلى main.dart بناءً على طلب المستخدم
      _seedDemoIfNeeded();
      // 📅 مطالبات اليوم (مواعيد المطالبة بالدين) — بعد لحظة حتى تكتمل الرئيسية
      Future.delayed(const Duration(milliseconds: 1500), () async {
        if (!mounted) return;
        await DebtReminders.checkOnStartup(context, showDueRemindersDialog);
      });
    });
  }

  /// 🧪 أول دخول للوضع التجريبي: توليد سنة من البيانات الوهمية (مرة واحدة).
  Future<void> _seedDemoIfNeeded() async {
    if (!DemoMode.isOn || !await DemoSeeder.needsSeed() || !mounted) return;
    final progress = ValueNotifier<double>(0);
    final message = ValueNotifier<String>('تحضير...');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('إنشاء البيانات التجريبية'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('نُنشئ سنة كاملة من القوائم والديون والمشتريات والمصاريف الوهمية. '
                  'قاعدتك الحقيقية لا تُلمس. قد يستغرق ذلك بضع دقائق.'),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, v, __) => LinearProgressIndicator(value: v),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: message,
                builder: (_, m, __) => Text(m, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ]),
          ),
        ),
      ),
    );
    String? error;
    try {
      await DemoSeeder.run((p, m) {
        progress.value = p;
        message.value = m;
      });
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await context.read<AppProvider>().refreshCustomers();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error == null ? '🧪 البيانات التجريبية جاهزة — جرّب كل شيء بحرية' : 'تعذّر إكمال البيانات التجريبية: $error'),
      backgroundColor: error == null ? Colors.green : Colors.red,
    ));
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
            const SnackBar(
              content: Text('✅ تم حفظ النسخة الاحتياطية'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
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



  /// 👤 هل يملك المستخدم الحالي هذه الصلاحية؟ (تُخفى الأزرار التي لا يملكها)
  bool _can(String permissionKey) => _authService.hasPermission(permissionKey);

  // 👤 فحص الصلاحية قبل السماح بالوصول
  bool _checkPermission(String permissionKey) {
    if (!_authService.hasPermission(permissionKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.block, color: Colors.white),
              SizedBox(width: 8),
              Text('ليس لديك صلاحية للوصول إلى هذه الميزة'),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }



  // Modern specific button for targeted features
  // ☁️ رفع البيانات (Telegram/Dropbox) — صار زراً في الشريط العلوي بدل زر في الشبكة
  Future<void> _uploadData() async {
    if (DemoMode.isOn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الوضع التجريبي: رفع البيانات متوقف (البيانات وهمية)'),
      ));
      return;
    }
    if (!_checkPermission(AppPermissions.uploadDatabase)) return;
    final appProvider = context.read<AppProvider>();
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>('جاري تحضير النسخة الاحتياطية...');
    final errorNotifier = ValueNotifier<String?>(''); // لتتبع الأخطاء
    bool uploadSucceeded = false;

    // جلب وقت آخر رفع
    final telegramService = TelegramBackupService();
    final lastUploadTime = await telegramService.getLastUploadTime();
    
    // طباعة معلومات التشخيص
    final diagnostics = await telegramService.getDiagnostics();
    debugPrint('📊 معلومات تشخيص Telegram:');
    diagnostics.forEach((key, value) => debugPrint('   $key: $value'));

    // ابدأ الرفع في مهمة منفصلة وتحديث المؤشر ثم إغلاق الحوار
    if (!mounted) return;
    Future(() async {
      try {
        // متغير لتتبع نجاح إرسال الفواتير لتيليجرام
        bool allInvoicesSentSuccessfully = true;
        List<String> errors = [];
        
        // ☁️ الوجهات المفعّلة بالترتيب المختار في الإعدادات ← النسخ الاحتياطي
        final appSet = await SettingsManager.getAppSettings();
        final targets = UploadTargets.enabledInOrder(appSet, owner: OwnerAccess.enabled);
        // ديسكورد يستلم نسخة مما يُرسل لتيليغرام فقط إن كان مفعّلاً
        TelegramBackupService.mirrorToDiscord = targets.contains(UploadTargets.discord);
        if (targets.isEmpty) errors.add('كل وجهات الرفع مطفأة (الإعدادات ← النسخ الاحتياطي ← وجهات الرفع)');
        for (final target in targets) {
          if (target == UploadTargets.telegram) {
                // 1) رفع قاعدة البيانات إلى Telegram (محلي + تيليجرام فقط)
                // يرمي إن لم تصل القاعدة؛ ويعيد مشاكل غير قاتلة (تقارير PDF لم تُرسل...).
                // الخطأ يُسجَّل ويكمل باقي الوجهات (Dropbox/Discord...) بدل أن يوقفها.
                try {
                  errors.addAll(await appProvider.backupDatabaseToTelegram(
                    onProgress: (p) {
                      progressNotifier.value = p * 0.5; // 50% للرفع الأساسي
                    },
                  ));
                } catch (e) {
                  errors.add('$e'.replaceFirst('Exception: ', ''));
                }

                // 2) إرسال الفواتير إلى Telegram
                final bool isConfigured = await telegramService.isConfigured;
                if (isConfigured) {
                  DateTime? exportAfterDate = lastUploadTime;
          
                  // إذا كان الرفع للمرة الأولى، نسأل المستخدم عن المدى الزمني
                  if (exportAfterDate == null) {
                    statusNotifier.value = 'بانتظار اختيار مدى الفواتير...';
            
                    // الخيارات المتاحة للمستخدم
                    if (!mounted) return;
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
          } else if (target == UploadTargets.dropbox) {
                // 4) رفع النسخة الاحتياطية إلى Dropbox (إذا كان متصلاً)
                final dropboxService = DropboxBackupService();
                final dropboxStatus = await dropboxService.checkAuthStatus();
                if (dropboxStatus == DropboxAuthStatus.authenticated) {
                  statusNotifier.value = 'جاري رفع النسخة إلى Dropbox...';
                  progressNotifier.value = 0.90;
          
                  final dropboxResult = await dropboxService.createAndUploadBackup(
                    // بلا maxBackups: يُستعمل العدد المحفوظ في شاشة Dropbox (كان ثابتاً 20)
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
          } else if (target == UploadTargets.discord) {
            // مع تيليغرام: استلم نسخة من كل ما أُرسل هناك. بدونه: قاعدة البيانات مباشرة
            if (!targets.contains(UploadTargets.telegram)) {
              statusNotifier.value = 'جاري رفع قاعدة البيانات إلى Discord...';
              final discord = DiscordBackupService();
              if (!await discord.isConfigured) {
                errors.add('Discord: الرابط (Webhook) غير مضبوط');
              } else {
                try {
                  final bytes = await GoogleDriveService.instance.zippedDatabase();
                  if (bytes.length > 9.5 * 1024 * 1024) {
                    errors.add('Discord: قاعدة البيانات (${(bytes.length / 1048576).toStringAsFixed(1)} ميغا) أكبر من حد ديسكورد (10 ميغا)');
                  } else {
                    final tmp = File('${Directory.systemTemp.path}${Platform.pathSeparator}alnaser_db_${DateTime.now().millisecondsSinceEpoch}.zip');
                    await tmp.writeAsBytes(bytes, flush: true);
                    final ok = await discord.sendDocument(
                        file: tmp, caption: '💾 قاعدة البيانات — ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}');
                    try {
                      await tmp.delete();
                    } catch (_) {}
                    if (!ok) errors.add('Discord: فشل إرسال قاعدة البيانات');
                  }
                } catch (e) {
                  errors.add('Discord: $e');
                }
              }
            }
          } else if (target == UploadTargets.gdrive) {
            final drive = GoogleDriveService.instance;
            if (!drive.isSupported) continue;
            final st = await drive.status();
            if (!st.signedIn) {
              errors.add('Google Drive: الحساب غير مربوط (الإعدادات ← ميزات المالك)');
            } else {
              try {
                statusNotifier.value = 'جاري رفع قاعدة البيانات إلى Google Drive...';
                await drive.uploadDatabase(onStep: (s) => statusNotifier.value = 'Google Drive: $s');
                statusNotifier.value = 'جاري رفع سجل الديون إلى Google Drive...';
                await drive.uploadDebtsPdf(onStep: (s) => statusNotifier.value = 'Google Drive: $s');
              } catch (e) {
                errors.add('Google Drive: $e');
              }
            }
          }
        }
        TelegramBackupService.mirrorToDiscord = true;

        // 5) حفظ وقت الرفع الحالي فقط إذا نجح إرسال جميع الفواتير
        if (allInvoicesSentSuccessfully && errors.isEmpty && targets.contains(UploadTargets.telegram)) {
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
        debugPrint('Backup error: $e');
        errorNotifier.value = 'خطأ: $e';
        uploadSucceeded = false;
      } finally {
        if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
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

    if (!mounted) return;
    if (result?['success'] == true) {
      // التحقق من حالة Dropbox لعرض رسالة مناسبة
      final dropboxStatus = await DropboxBackupService().checkAuthStatus();
      final okTargets = UploadTargets.enabledInOrder(await SettingsManager.getAppSettings(), owner: OwnerAccess.enabled);
      String successMessage = 'تم رفع البيانات: ${okTargets.map((t) => UploadTargets.labels[t]).join(' ← ')}';
      if (okTargets.contains(UploadTargets.dropbox) && dropboxStatus != DropboxAuthStatus.authenticated) {
        successMessage += '\n(دروب بوكس غير مربوط فتُخطّي)';
      }
      if (!mounted) return;
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
                const Text('حدث خطأ أثناء رفع البيانات (ما نجح من الوجهات الأخرى رُفع فعلاً):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
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
                const Text('• تأكد من ربط الوجهة المذكورة في الخطأ (الإعدادات ← النسخ الاحتياطي)'),
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
  }

  // ═══════════════════════════ الواجهة ═══════════════════════════

  /// تحية + اسم المستخدم + التاريخ (الشهر بالأرقام).
  String get _greetingLine {
    final now = DateTime.now();
    final greet = now.hour < 12 ? 'صباح الخير' : 'مساء الخير';
    final user = _authService.currentUser;
    final name = user == null ? '' : user.shownName.trim();
    String weekday;
    try {
      weekday = DateFormat('EEEE', 'ar').format(now);
    } catch (_) {
      weekday = '';
    }
    final date = DateFormat('yyyy/MM/dd', 'en').format(now);
    return '${name.isEmpty ? greet : '$greet، $name'}   •   $weekday $date';
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF020F2B), Color(0xFF0F3460), Color(0xFF16508A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 10, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 27),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('الناصر',
                          style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800)),
                      Text(_greetingLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 13)),
                    ]),
                  ),
                  if (_authService.hasPermission(AppPermissions.uploadDatabase))
                    IconButton(
                      icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
                      tooltip: 'رفع البيانات (الوجهات والترتيب من الإعدادات)',
                      onPressed: _uploadData,
                    ),
                  const UserMenuButton(),
                ]),
                const SizedBox(height: 14),
                _HomeSearchBar(onTap: () => showGlobalSearch(context)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// شبكة الأزرار: الأعمدة تُحسب من العرض بحيث تمتلئ الصفوف (لا زر يتيم في
  /// صف وحده)، والأقسام في الشاشات العريضة صف واحد ببطاقات عمودية.
  Widget _grid(List<_HomeItem> items, {required bool big, required int startIndex}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      int cols;
      if (big) {
        cols = w >= 1050 ? 3 : (w >= 640 ? 2 : 1);
      } else {
        cols = w >= 1050 ? items.length.clamp(1, 6).toInt() : (w >= 640 ? 3 : 2);
      }
      // توازن الصفوف: 4 عناصر في 3 أعمدة ← عمودان (2+2) بدل (3+1).
      if (items.length > cols && items.length % cols == 1 && cols > 2) cols--;
      const gap = 14.0;
      final cardW = (w - gap * (cols - 1)) / cols;
      final vertical = !big && cardW < 250;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var i = 0; i < items.length; i++)
          SizedBox(
            width: cardW,
            height: big ? 108 : (vertical ? 132 : 94),
            child: _HomeFadeIn(
              index: startIndex + i,
              child: _HomeCard(dest: items[i].dest, onTap: items[i].onTap, big: big, vertical: vertical),
            ),
          ),
      ]);
    });
  }

  Widget _sectionLabel(String t, IconData icon) => Row(children: [
        Icon(icon, size: 20, color: const Color(0xFF0F3460)),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFFE3E9F1))),
      ]);

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

    // 📌 «العمل اليومي» (بطاقات أكبر) ثم «الأقسام» — نفس الصلاحيات والمسارات السابقة
    final daily = <_HomeItem>[
      if (!isDebtsOnly && _can(AppPermissions.posAccess))
        _HomeItem(HomeDests.pos, () {
          if (_checkPermission(AppPermissions.posAccess)) Navigator.pushNamed(context, '/pos');
        }),
      if (!isDebtsOnly && _can(AppPermissions.createInvoice))
        _HomeItem(HomeDests.createInvoice, () {
          if (_checkPermission(AppPermissions.createInvoice)) Navigator.pushNamed(context, '/create_invoice');
        }),
      if (_can(AppPermissions.debtRegister))
        _HomeItem(HomeDests.debtRegister, () {
          if (_checkPermission(AppPermissions.debtRegister)) Navigator.pushNamed(context, '/debt_register');
        }),
      if (!isDebtsOnly && _can(AppPermissions.editInvoices))
        _HomeItem(HomeDests.editInvoices, () {
          if (_checkPermission(AppPermissions.editInvoices)) Navigator.pushNamed(context, '/edit_invoices');
        }),
      if (!isDebtsOnly && _can(AppPermissions.productEntry))
        _HomeItem(HomeDests.productEntry, () {
          if (_checkPermission(AppPermissions.productEntry)) Navigator.pushNamed(context, '/product_entry');
        }),
      if (!isDebtsOnly && _can(AppPermissions.suppliers))
        _HomeItem(HomeDests.suppliers, () {
          if (_checkPermission(AppPermissions.suppliers)) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SuppliersDashboardScreen()));
          }
        }),
    ];
    final sections = <_HomeItem>[
      if (!isDebtsOnly && (_can(AppPermissions.createInvoice) || _can(AppPermissions.salesDocs)))
        _HomeItem(HomeDests.sales, () {
          if (_authService.hasPermission(AppPermissions.createInvoice) ||
              _checkPermission(AppPermissions.salesDocs)) {
            Navigator.pushNamed(context, '/sales_hub');
          }
        }),
      if (!isDebtsOnly &&
          (_can(AppPermissions.itemCard) ||
              _can(AppPermissions.inventoryReports) ||
              _can(AppPermissions.editProducts) ||
              _can(AppPermissions.stockTransfer) ||
              _can(AppPermissions.inventoryDocs)))
        _HomeItem(HomeDests.inventory, () {
          if (_authService.hasPermission(AppPermissions.itemCard) ||
              _authService.hasPermission(AppPermissions.inventoryReports) ||
              _authService.hasPermission(AppPermissions.editProducts) ||
              _authService.hasPermission(AppPermissions.stockTransfer) ||
              _checkPermission(AppPermissions.inventoryDocs)) {
            Navigator.pushNamed(context, '/inventory_hub');
          }
        }),
      if (!isDebtsOnly && _can(AppPermissions.accounting))
        _HomeItem(HomeDests.accounting, () {
          if (_checkPermission(AppPermissions.accounting)) Navigator.pushNamed(context, '/accounting');
        }),
      if (_can(AppPermissions.reports))
        _HomeItem(HomeDests.reports, () {
          if (_checkPermission(AppPermissions.reports)) Navigator.pushNamed(context, '/reports');
        }),
      if (_can(AppPermissions.settings))
        _HomeItem(HomeDests.settings, () {
          if (_checkPermission(AppPermissions.settings)) Navigator.pushNamed(context, '/general_settings');
        }),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmation();
        if (shouldExit && mounted) {
          // إغلاق التطبيق فعلياً عبر كل المنصات (ويندوز/أندرويد).
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        body: Row(
          children: [
            if (_appSettings != null && AppSideNav.shouldShow(context, _appSettings!))
              const AppSideNav(currentRoute: '/main'),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(),
                  // 🩺 تنبيهات صحة المزامنة (لا يظهر شيء ما دام كل شيء سليماً)
                  const SyncHealthBanner(),
                  // 🖧 حالة الاتصال بحاسبة السيرفر (طرفية) أو عدد الطرفيات (سيرفر)
                  const LanStatusBanner(),
                  // 🧪 شريط الوضع التجريبي
                  if (DemoMode.isOn)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDBA74)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.science_rounded, color: Color(0xFFC2410C)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'وضع تجريبي — البيانات وهمية، والمزامنة والشبكة ورفع البيانات متوقفة. للخروج: زر المستخدم ← خروج ← «العودة إلى البيانات الحقيقية»',
                            style: TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                    ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                          children: [
                            // 🔒 أرقام المحل (المبيعات، الربح، الديون) للمدير فقط
                            if (_authService.isAdmin) ...[
                              const _TodayStrip(),
                              const SizedBox(height: 24),
                            ],
                            if (daily.isNotEmpty) ...[
                              _sectionLabel('العمل اليومي', Icons.today_rounded),
                              const SizedBox(height: 12),
                              _grid(daily, big: true, startIndex: 0),
                              const SizedBox(height: 26),
                            ],
                            if (sections.isNotEmpty) ...[
                              _sectionLabel('الأقسام', Icons.dashboard_rounded),
                              const SizedBox(height: 12),
                              _grid(sections, big: false, startIndex: daily.length),
                            ],
                          ],
                        ),
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

// ═══════════════════════════ عناصر الرئيسية ═══════════════════════════

class _HomeItem {
  const _HomeItem(this.dest, this.onTap);
  final HomeDest dest;
  final VoidCallback onTap;
}

/// ظهور متتابع ناعم للبطاقات عند فتح الشاشة.
class _HomeFadeIn extends StatelessWidget {
  const _HomeFadeIn({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final delay = 45.0 * index.clamp(0, 12);
    final total = 320.0 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total.round()),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: c),
      ),
    );
  }
}

/// شريط البحث الشامل (يفتح نافذة البحث — Ctrl+K من أي شاشة).
/// تلميح يتبدّل بهدوء بين ما يمكن البحث عنه، وشرائح توضّح الأنواع، ومفتاح الاختصار.
class _HomeSearchBar extends StatefulWidget {
  const _HomeSearchBar({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<_HomeSearchBar> {
  static const _navy = Color(0xFF0F3460);
  static const _accent = Color(0xFF2F80ED);
  static const _muted = Color(0xFF64748B);

  static const _hints = [
    'ابحث عن عميل، أو مادة بالاسم أو الرمز أو الباركود، أو رقم فاتورة…',
  ];

  bool _hover = false;
  bool _pressed = false;
  int _hint = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_hints.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) setState(() => _hint = (_hint + 1) % _hints.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label: 'البحث الشامل: عميل، مادة، رقم فاتورة',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed ? 0.99 : 1,
              duration: const Duration(milliseconds: 120),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                height: 56,
                padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 10, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _hover ? _accent.withValues(alpha: 0.55) : Colors.white,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_hover ? _accent : Colors.black).withValues(alpha: _hover ? 0.22 : 0.12),
                      blurRadius: _hover ? 24 : 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 640;
                  return Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        gradient: const LinearGradient(
                          colors: [_navy, _accent],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                      ),
                      child: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
                            child: child,
                          ),
                        ),
                        layoutBuilder: (cur, prev) => Stack(
                          alignment: AlignmentDirectional.centerStart,
                          children: [...prev, if (cur != null) cur],
                        ),
                        child: Text(
                          _hints[_hint],
                          key: ValueKey(_hint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 15),
                        ),
                      ),
                    ),
                    if (wide) ...[
                      const _ScopeChip(icon: Icons.person_outline_rounded, label: 'عميل'),
                      const SizedBox(width: 6),
                      const _ScopeChip(icon: Icons.inventory_2_outlined, label: 'مادة'),
                      const SizedBox(width: 6),
                      const _ScopeChip(icon: Icons.receipt_long_outlined, label: 'فاتورة'),
                      const SizedBox(width: 12),
                    ],
                    const _KeyCap('K'),
                    const SizedBox(width: 4),
                    const _KeyCap('Ctrl'),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.tips_and_updates_outlined, size: 15, color: Colors.white.withValues(alpha: 0.7)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'يكفي جزء من الاسم أو آخر أرقام الهاتف • النتائج حسب صلاحياتك • Ctrl+K من أي شاشة',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12),
          ),
        ),
      ]),
    ]);
  }
}

/// شريحة نوع بحث (توضيحية — البحث يشمل الأنواع كلها).
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: const Color(0xFF0F3460)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
      ]),
    );
  }
}

/// مفتاح لوحة مفاتيح صغير (Ctrl / K).
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDE4EE)),
        boxShadow: const [BoxShadow(color: Color(0xFFDDE4EE), offset: Offset(0, 2))],
      ),
      child: Text(label,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
    );
  }
}

/// زر قسم في الرئيسية: أيقونة ملوّنة + اسم + شرح قصير + اختصار لوحة المفاتيح.
class _HomeCard extends StatefulWidget {
  const _HomeCard({required this.dest, required this.onTap, required this.big, this.vertical = false});
  final HomeDest dest;
  final VoidCallback onTap;
  final bool big;

  /// أيقونة فوق الاسم (للبطاقات الضيقة في صف الأقسام).
  final bool vertical;
  @override
  State<_HomeCard> createState() => _HomeCardState();
}

class _HomeCardState extends State<_HomeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.dest;
    final c = d.color;
    final big = widget.big;
    return Semantics(
      button: true,
      label: d.title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _hover ? c.withValues(alpha: 0.22) : const Color(0x0C0F172A),
                blurRadius: _hover ? 22 : 10,
                offset: Offset(0, _hover ? 10 : 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: _hover ? c.withValues(alpha: 0.55) : const Color(0xFFE3E9F1)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Stack(children: [
                // لمسة لون خفيفة في الزاوية
                PositionedDirectional(
                  end: -26,
                  top: -26,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: big ? 96 : 80,
                    height: big ? 96 : 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.withValues(alpha: _hover ? 0.12 : 0.06),
                    ),
                  ),
                ),
                if (widget.vertical)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _hover ? c : c.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(d.icon, color: _hover ? Colors.white : c, size: 26),
                        ),
                        const SizedBox(height: 10),
                        Text(d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                        if (d.subtitle != null)
                          Text(d.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                      ]),
                    ),
                  )
                else
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: big ? 16 : 14),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: big ? 58 : 50,
                      height: big ? 58 : 50,
                      decoration: BoxDecoration(
                        color: _hover ? c : c.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(big ? 18 : 15),
                        boxShadow: _hover
                            ? [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))]
                            : const [],
                      ),
                      child: Icon(d.icon, color: _hover ? Colors.white : c, size: big ? 30 : 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: big ? 17.5 : 15.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E293B),
                              )),
                          if (d.subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(d.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                          ],
                        ],
                      ),
                    ),
                    if (d.shortcut != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _hover ? c : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.withValues(alpha: 0.35)),
                        ),
                        child: Text(d.shortcut!,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800, color: _hover ? Colors.white : c)),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ اليوم بلمحة ═══════════════════════════

/// شريط «اليوم بلمحة» أعلى الرئيسية (لمن يملك صلاحية التقارير): مبيعات اليوم
/// وربحه، الشهر، ديون العملاء، وسعر الدولار — الضغط يفتح التقرير المناسب.
/// يتحدث كل دقيقتين وعند الضغط على ⟳.
class _TodayStrip extends StatefulWidget {
  const _TodayStrip();
  @override
  State<_TodayStrip> createState() => _TodayStripState();
}

class _TodayStripState extends State<_TodayStrip> {
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _month;
  double _ar = 0;
  int _debtors = 0;
  double _usd = 0;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // بعد أول رسم حتى لا يؤخر ظهور الرئيسية
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final rs = ReportsService();
      final today = await rs.getPeriodSummary(startDate: now, endDate: now);
      final month = await rs.getPeriodSummary(startDate: DateTime(now.year, now.month, 1), endDate: now);
      final db = await DatabaseService().database;
      var ar = 0.0;
      var n = 0;
      try {
        final c = await db.rawQuery(
            'SELECT COALESCE(SUM(CASE WHEN current_total_debt > 0 THEN current_total_debt ELSE 0 END), 0) AS ar, '
            'COALESCE(SUM(CASE WHEN current_total_debt > 0 THEN 1 ELSE 0 END), 0) AS n '
            'FROM customers WHERE COALESCE(is_deleted, 0) = 0');
        ar = (c.first['ar'] as num?)?.toDouble() ?? 0;
        n = (c.first['n'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      var usd = 0.0;
      try {
        usd = await CurrencyService.rateAt(db, 'USD', now);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _today = today;
        _month = month;
        _ar = ar;
        _debtors = n;
        _usd = usd;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _n(Map<String, dynamic>? m, String k) => (m?[k] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final profit = repCanSeeProfit();
    final tSales = _n(_today, 'totalSales');
    // 🔐 من مُنع من تقرير اليوم/الشهر لا يرى أرقامه هنا أيضاً
    final day = AuthService().hasPermission(AppPermissions.repDaily);
    final mon = AuthService().hasPermission(AppPermissions.repMonthly);
    final tiles = <Widget>[
      if (day)
      _GlanceTile(
        label: 'مبيعات اليوم',
        value: _loading ? '…' : repMoney(tSales),
        hint: _loading ? '' : '${_n(_today, 'invoiceCount').toInt()} فاتورة • نقد ${repMoney(_n(_today, 'cashSales'))}',
        icon: Icons.point_of_sale_rounded,
        color: const Color(0xFF0F3460),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomRangeReportScreen(from: DateTime.now(), to: DateTime.now()))),
      ),
      if (profit && day)
        _GlanceTile(
          label: 'ربح اليوم',
          value: _loading ? '…' : repMoney(_n(_today, 'netProfit')),
          hint: _loading || tSales <= 0 ? '' : 'هامش ${(_n(_today, 'netProfit') / tSales * 100).toStringAsFixed(1)}%',
          icon: Icons.trending_up_rounded,
          color: const Color(0xFF047857),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomRangeReportScreen(from: DateTime.now(), to: DateTime.now()))),
        ),
      if (mon)
      _GlanceTile(
        label: 'مبيعات الشهر',
        value: _loading ? '…' : repMoney(_n(_month, 'totalSales')),
        hint: _loading
            ? ''
            : (profit ? 'ربح ${repMoney(_n(_month, 'netProfit'))}' : '${_n(_month, 'invoiceCount').toInt()} فاتورة'),
        icon: Icons.calendar_month_rounded,
        color: const Color(0xFF6D28D9),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomRangeReportScreen())),
      ),
      _GlanceTile(
        label: 'ديون العملاء',
        value: _loading ? '…' : repMoney(_ar),
        hint: _loading ? '' : '$_debtors عميل مدين',
        icon: Icons.groups_rounded,
        color: const Color(0xFFC2410C),
        onTap: () => Navigator.pushNamed(context, '/debt_register'),
      ),
      if (_usd > 1)
        _GlanceTile(
          label: 'سعر الدولار',
          value: repMoney(_usd),
          hint: 'دينار لكل \$1',
          icon: Icons.attach_money_rounded,
          color: const Color(0xFFB45309),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.insights_rounded, size: 20, color: Color(0xFF0F3460)),
        const SizedBox(width: 8),
        const Text('اليوم بلمحة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFFE3E9F1))),
        IconButton(
          tooltip: 'تحديث',
          visualDensity: VisualDensity.compact,
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF64748B)),
        ),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        const gap = 12.0;
        final cols = c.maxWidth >= 1000 ? tiles.length : (c.maxWidth >= 620 ? 3 : 2);
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      }),
    ]);
  }
}

class _GlanceTile extends StatelessWidget {
  const _GlanceTile({required this.label, required this.value, required this.hint, required this.icon, required this.color, this.onTap});
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E9F1))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: color, width: 4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
            ),
            const SizedBox(height: 2),
            Text(hint.isEmpty ? ' ' : hint,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
          ]),
        ),
      ),
    );
  }
}
