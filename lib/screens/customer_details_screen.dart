// screens/customer_details_screen.dart
import '../services/save_lock.dart'; // 🔒 قفل الحفظ
import 'package:flutter/foundation.dart' show kIsWeb; // 🌐
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database/business/customer_name_rule.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/grouped_transaction.dart'; // ✅ Added
import '../models/verification_result.dart'; // ✅ Added
import '../models/customer_receipt_voucher.dart'; // ✅ Added
import 'add_transaction_screen.dart';
import 'create_invoice_screen.dart';
import '../services/database_service.dart';
import '../services/credit_limit_guard.dart'; // 🚫 سقف الدين
import '../services/receipt_voucher_pdf_service.dart';
import 'package:printing/printing.dart'; // Assume this is for PDF preview on non-Windows
import 'dart:io';
// import 'package:path_provider/path_provider.dart'; // Not directly used in final snippet, but for file operations
// import 'package:share_plus/share_plus.dart'; // Not directly used here
import 'package:intl/intl.dart' hide TextDirection; // TextDirection من Flutter
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'audit_log_screen.dart';
import '../services/password_service.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/logo_service.dart'; // 🖼️ Custom logo loading
import '../services/settings_manager.dart'; // 📋 For company info in WhatsApp message
import '../erp/debts/customer_card_screen.dart';
import '../erp/debts/receipt_screen.dart';
import '../erp/pickers.dart' show PartyLite;
import '../widgets/edit_transaction_dialog.dart'; // ✏️
import 'debt_reminders_screen.dart'; // 📅
import '../accounting/screens/acc_ui.dart' show accAppBar;
import 'statements/customer_statements_screen.dart';
import '../widgets/loading_dialog.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailsScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {

  
  // 📊 المعاملات المجمعة (فواتير مجمعة + معاملات يدوية)
  List<GroupedTransactionItem> _groupedTransactions = [];
  Map<int, String> _invoiceNumberMap = {}; // خريطة ربط معرف الفاتورة برقمها التجاري المنسق
  bool _useGroupedView = true; // استخدام العرض المجمع افتراضياً

  @override
  void initState() {
    super.initState();
    // This is good practice for initial data loading from a provider
    Future.microtask(() async {
      if (!mounted) return;
      await context.read<AppProvider>().selectCustomer(widget.customer);
      await _loadTransactions();
      // 🔒 التحقق التلقائي من الرصيد عند فتح الصفحة
      await _verifyAndAutoFixBalance();
    });
  }
  
  Future<void> _loadTransactions() async {
    if (!mounted) return;
    if (widget.customer.id != null) {
      final fresh = await DatabaseService().getCustomerById(widget.customer.id!);
      if (!mounted) return;
      if (fresh != null) {
        await context.read<AppProvider>().selectCustomer(fresh);
      } else {
        await context.read<AppProvider>().loadCustomerTransactions(widget.customer.id!);
      }
      
      // تحميل المعاملات المجمعة
      try {
        final db = DatabaseService();
        final grouped = await db.getGroupedCustomerTransactions(widget.customer.id!);
        final Map<int, String> invNumbers = {};
        for (var g in grouped) {
          if (g.invoiceId != null && g.invoiceNumber != null) {
            invNumbers[g.invoiceId!] = g.invoiceNumber!;
          }
        }
        if (mounted) {
          setState(() {
            _groupedTransactions = grouped;
            _invoiceNumberMap = invNumbers;
          });
        }
      } catch (e) {
        debugPrint('خطأ في تحميل المعاملات المجمعة: $e');
      }
    }
  }

  /// 🔒 التحقق التلقائي من رصيد العميل وإصلاح الفروقات البسيطة
  /// هذه الدالة تضمن أن الرصيد المعروض = مجموع المعاملات بنسبة 99.9%
  Future<void> _verifyAndAutoFixBalance() async {
    if (!mounted || widget.customer.id == null) return;
    
    try {
      final db = DatabaseService();
      final result = await db.getVerifiedCustomerBalance(widget.customer.id!);
      
      if (result.wasAutoFixed && mounted) {
        // تم إصلاح فرق بسيط تلقائياً - إعادة تحميل البيانات
        await context.read<AppProvider>().selectCustomer(widget.customer);
        await _loadTransactions();
        
        // إظهار رسالة صغيرة (اختياري - يمكن إزالتها للإصلاح الصامت)
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(
        //     content: Text(result.autoFixNote ?? 'تم تصحيح الرصيد تلقائياً'),
        //     duration: const Duration(seconds: 2),
        //     backgroundColor: Colors.green,
        //   ),
        // );
      }
    } catch (e) {
      // تجاهل الأخطاء - لا نريد إيقاف التطبيق
      debugPrint('خطأ في التحقق التلقائي من الرصيد: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Helper to format numbers with thousand separators (no decimals)
  String formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }



  // دالة تنسيق رقم الهاتف للصيغة الدولية
  String _normalizePhoneNumber(String phone) {
    // إزالة كل شيء غير الأرقام أو +
    String cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    
    // إزالة علامة + إذا كانت موجودة
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    
    // إذا بدأ بصفر محلي، استبدله برمز الدولة العراقية
    if (cleaned.startsWith('0')) {
      cleaned = '964${cleaned.substring(1)}';
    }
    
    // إذا لم يبدأ برمز الدولة، أضف رمز العراق
    if (!cleaned.startsWith('964')) {
      cleaned = '964$cleaned';
    }
    
    return cleaned;
  }

  // دالة بناء رسالة الدين
  Future<String> _buildDebtMessage() async {
    final customer = widget.customer;
    final provider = context.read<AppProvider>();
    final currentBalance = provider.selectedCustomer?.currentTotalDebt ?? 0.0;

    // تحميل إعدادات الشركة من الإعدادات
    final appSettings = await SettingsManager.getAppSettings();
    final companyName = appSettings.invoiceDesign.companyName;
    final companyDescription = appSettings.companyDescription;
    final companyAddress = appSettings.invoiceDesign.companyAddress;

    // تنسيق المبلغ
    final amountFormatter = NumberFormat('#,##0', 'en_US');
    final formattedAmount = amountFormatter.format(currentBalance.abs());

    // تحديد تاريخ آخر تحديث من آخر معاملة، وإن لم تتوفر فآخر تعديل للعميل
    final transactions = provider.customerTransactions;
    DateTime? lastTransactionDate;
    for (final t in transactions) {
      if (lastTransactionDate == null || t.transactionDate.isAfter(lastTransactionDate)) {
        lastTransactionDate = t.transactionDate;
      }
    }
    final DateTime lastUpdate = lastTransactionDate ?? customer.lastModifiedAt;
    final dateFormatter = DateFormat('yyyy-MM-dd', 'en_US');
    final formattedLastUpdate = dateFormatter.format(lastUpdate);

    // بناء الرسالة
    final StringBuffer message = StringBuffer();
    message.writeln('السلام عليكم السيد ${customer.name}');
    message.writeln();
    message.writeln('نحن $companyName');
    if (companyDescription.isNotEmpty) {
      message.writeln(companyDescription);
    }
    message.writeln();

    if (currentBalance > 0) {
      message.writeln('لديكم دين بقيمة $formattedAmount د.ع');
    } else if (currentBalance < 0) {
      message.writeln('لديكم رصيد ائتماني بقيمة $formattedAmount د.ع');
    } else {
      message.writeln('رصيدكم الحالي متوازن (صفر د.ع)');
    }

    message.writeln('تاريخ آخر تحديث: $formattedLastUpdate');
    message.writeln();
    message.writeln('الرجاء  مراجعة عنواننا:');
    message.writeln(companyAddress);
    message.writeln();
    message.writeln('نعتذر على الإزعاج');
    message.writeln('مع الشكر والتقدير');

    return message.toString();
  }

  // دالة إرسال رسالة واتساب
  Future<void> _sendWhatsAppMessage() async {
    final provider = context.read<AppProvider>();
    final customer = provider.selectedCustomer ?? widget.customer;
    
    // التحقق من وجود رقم هاتف
    if (customer.phone == null || customer.phone!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد رقم هاتف مسجل للعميل'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // إظهار مؤشر تحميل
    if (mounted) {
      LoadingDialog.show(
        context,
        builder: (context) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(width: 16),
              Text('جاري فتح واتساب...'),
            ],
          ),
        ),
      );
    }

    try {
      // تنسيق رقم الهاتف
      final phoneNumber = _normalizePhoneNumber(customer.phone!);
      
      // بناء رسالة الدين
      final message = await _buildDebtMessage();
      
      // انسخ الرسالة للحافظة مسبقاً كخطة احتياطية في حال لم تُرفق تلقائياً
      await Clipboard.setData(ClipboardData(text: message));

      // ترميز الرسالة للرابط
      final encodedMessage = Uri.encodeComponent(message);

      // إنشاء روابط واتساب بحسب المنصة مع تسلسل محاولات قوي
      final Uri androidDeepLink = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$encodedMessage');
      final Uri apiLink = Uri.parse('https://api.whatsapp.com/send?phone=$phoneNumber&text=$encodedMessage');
      final Uri waMeLink = Uri.parse('https://wa.me/$phoneNumber?text=$encodedMessage');
      final Uri webLink = Uri.parse('https://web.whatsapp.com/send?phone=$phoneNumber&text=$encodedMessage');

      final List<Uri> attempts;
      if (Platform.isAndroid) {
        attempts = [androidDeepLink, apiLink, waMeLink];
      } else if (Platform.isIOS) {
        attempts = [waMeLink, apiLink];
      } else {
        // لسطح المكتب (ويندوز/ماك/لينكس): أعطِ أولوية لتطبيق سطح المكتب إن أمكن
        attempts = [androidDeepLink, waMeLink, apiLink, webLink];
      }

      bool success = false;

      // محاولة خاصة بويندوز لفتح بروتوكول whatsapp:// مباشرة عبر start
      if (Platform.isWindows && !success) {
        try {
          final desktopProtocol = 'whatsapp://send?phone=$phoneNumber&text=$encodedMessage';
          await Process.start('cmd', ['/c', 'start', '""', desktopProtocol]);
          success = true;
        } catch (_) {
          // تجاهل واستمر بالمحاولات الأخرى
        }
      }
      for (final uri in attempts) {
        try {
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (opened) {
            success = true;
            break;
          }
        } catch (_) {
          try {
            final fallbackOpened = await launchUrl(
              uri,
              mode: LaunchMode.platformDefault,
            );
            if (fallbackOpened) {
              success = true;
              break;
            }
          } catch (_) {
            continue;
          }
        }
      }
      
      // إغلاق مؤشر التحميل
      LoadingDialog.hide();
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم فتح واتساب وتهيئة المحادثة. إذا لم تظهر الرسالة، اضغط Ctrl+V للصقها (تم نسخها).'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        // فشل فتح أي رابط — الرسالة موجودة في الحافظة بالفعل
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('تعذر فتح واتساب'),
              content: const Text('لم نتمكن من فتح محادثة واتساب. تم نسخ الرسالة إلى الحافظة، افتح واتساب والصقها يدوياً.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );
        }
      }
      
    } catch (e) {
      // إغلاق مؤشر التحميل في حالة الخطأ
      LoadingDialog.hide();

      // الرسالة منسوخة أصلاً للحافظة
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: ${e.toString()}. تم نسخ الرسالة للحافظة.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// دالة تعديل بيانات العميل
  Future<void> _editCustomerDetails() async {
    final nameController = TextEditingController(text: widget.customer.name);
    final phoneController = TextEditingController(text: widget.customer.phone ?? '');
    final addressController = TextEditingController(text: widget.customer.address ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تعديل معلومات العميل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'الهاتف'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
          ],
        );
      },
    );
    if (result == true && mounted) {
      String? normalizedPhone;
      if (phoneController.text.trim().isNotEmpty) {
        normalizedPhone = _normalizePhoneNumber(phoneController.text.trim());
      }
      
      final provider = context.read<AppProvider>();
      final currentCustomer = provider.selectedCustomer ?? widget.customer;
      
      final updated = currentCustomer.copyWith(
        name: nameController.text.trim(),
        phone: normalizedPhone,
        address: addressController.text.trim(),
        currentTotalDebt: currentCustomer.currentTotalDebt,
        lastModifiedAt: DateTime.now(),
      );
      try {
        await provider.updateCustomer(updated);
      } on DuplicateCustomerNameException catch (e) {
        // 🛡️ سجل الديون: لا حسابان بالاسم نفسه
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
          );
        }
        return;
      }
      
      try {
        final db = DatabaseService();
        await db.updateOldInvoicesWithCustomerIds();
      } catch (_) {}
      
      if (mounted) {
        String message = 'تم تحديث بيانات العميل';
        if (normalizedPhone != null) {
          message += '\nتم تحويل رقم الهاتف إلى: $normalizedPhone';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// دالة حذف العميل مع التحقق والأمان
  Future<void> _handleDeleteCustomer() async {
    final provider = context.read<AppProvider>();
    final customer = provider.selectedCustomer ?? widget.customer;
    final hasDebt = customer.currentTotalDebt > 0.01;
    
    if (hasDebt) {
      final warningConfirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
              const SizedBox(width: 8),
              const Text('تنبيه!', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'هذا العميل عليه دين بقيمة:',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[300]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.monetization_on, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Text(
                      '${NumberFormat('#,##0', 'en_US').format(customer.currentTotalDebt)} د.ع',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'هل أنت متأكد من حذف هذا العميل؟\nسيتم حذف جميع سجلات الديون والمعاملات المرتبطة به.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء', style: TextStyle(color: Colors.grey[700])),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      
      if (warningConfirmed != true || !mounted) return;
      
      final passwordController = TextEditingController();
      final passwordService = PasswordService();
      final passwordVerified = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('أدخل كلمة سر المدير للتأكيد', style: TextStyle(fontSize: 18)),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'كلمة السر',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.lock),
            ),
            onSubmitted: (value) async {
              final isCorrect = await passwordService.verifyPassword(value);
              if (!context.mounted) return;
              Navigator.of(context).pop(isCorrect);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final isCorrect = await passwordService.verifyPassword(passwordController.text);
                if (!context.mounted) return;
                Navigator.of(context).pop(isCorrect);
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      );
      
      if (passwordVerified != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('كلمة السر غير صحيحة أو تم الإلغاء'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تأكيد الحذف',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text(
              'هل أنت متأكد من حذف هذا العميل؟ لا يمكن التراجع عن هذا الإجراء.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('حذف',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );
      
      if (confirmed != true || !mounted) return;
    }
    
    try {
      await provider.deleteCustomer(widget.customer.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم حذف العميل ${widget.customer.name} بنجاح!'),
              backgroundColor: Theme.of(context).colorScheme.tertiary),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openTransaction(Customer customer, {required bool isDebt}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(customer: customer, initialIsDebt: isDebt),
      ),
    );
    // تحديث المعاملات المجمعة بعد العودة من شاشة الإضافة
    if (mounted) {
      await _loadTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define the consistent theme colors for the screen
    const Color primaryColor = Color(0xFF0F3460); // كحلي البرنامج
    const Color accentColor =
        Color(0xFF8C9EFF); // Light Indigo Accent (Indigo A200)
    const Color textColor =
        Color(0xFF212121); // Dark grey for general text
    final Color successColor =
        Colors.green[600]!; // Green for success messages/positive debt
    final Color errorColor =
        Colors.red[700]!; // Red for error messages/negative debt

    return Theme(
      data: ThemeData(
        // Define color scheme for light theme
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          error: errorColor,
          onError: Colors.white,
          tertiary: successColor,
        ),
        fontFamily: 'Cairo', // خط البرنامج (كان Roboto فتظهر العربية بخط النظام)
        scaffoldBackgroundColor: const Color(0xFFF3F6FB),
        textTheme: TextTheme(
          titleLarge: const TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: Colors.white),
          titleMedium: const TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: textColor),
          bodyLarge:
              const TextStyle(fontSize: 16.0, color: textColor),
          bodyMedium:
              const TextStyle(fontSize: 14.0, color: textColor),
          labelLarge: const TextStyle(
              fontSize: 16.0,
              color: Colors.white,
              fontWeight: FontWeight.w600),
          labelMedium: TextStyle(
              fontSize: 14.0, color: Colors.grey[600]),
          bodySmall: TextStyle(
              fontSize: 12.0, color: Colors.grey[700]),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 4,
          titleTextStyle: const TextStyle(
            fontSize: 20.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
            side: const BorderSide(color: Color(0xFFE3E9F1)),
          ),
          margin: EdgeInsets.zero,
        ),
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
      ),
      child: Scaffold(
        appBar: accAppBar(
          widget.customer.name,
          icon: Icons.person_rounded,
          subtitle: 'حساب العميل',
          actions: [
            // 🗂️ بطاقة العميل الموسّعة (سقف، مجموعة، أعمار ديون، مستندات)
            if (widget.customer.id != null)
              IconButton(
                icon: const Icon(Icons.badge_outlined, color: Colors.white),
                tooltip: 'بطاقة العميل',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CustomerCardScreen(customerId: widget.customer.id!)),
                ),
              ),
            // 🧾 وصل قبض (مع حسم وعملة وطباعة)
            if (widget.customer.id != null)
              IconButton(
                icon: const Icon(Icons.payments_outlined, color: Colors.white),
                tooltip: 'وصل قبض',
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptScreen(
                        customer: PartyLite(widget.customer.id!, widget.customer.name, widget.customer.phone,
                            widget.customer.currentTotalDebt),
                      ),
                    ),
                  );
                  if (!context.mounted) return;
                  await context.read<AppProvider>().selectCustomer(widget.customer);
                  if (!context.mounted) return;
                  await context.read<AppProvider>().loadCustomerTransactions(widget.customer.id!);
                },
              ),
            // ✏️ تعديل معلومات العميل
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'تعديل معلومات العميل',
              onPressed: _editCustomerDetails,
            ),
            // 💬 إرسال واتساب
            IconButton(
              icon: const Icon(Icons.message, color: Colors.white),
              tooltip: 'إرسال رسالة واتساب',
              onPressed: _sendWhatsAppMessage,
            ),
            // 📄 كشف الحساب
            IconButton(
              icon: const Icon(Icons.receipt_long, color: Colors.white),
              tooltip: 'كشف الحساب',
              onPressed: () => _openStatements(),
            ),
            // ⋯ المزيد من الخيارات
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              tooltip: 'خيارات إضافية',
              onSelected: (value) {
                switch (value) {
                  case 'commercial_statement':
                    _openStatements(tab: StatementTab.commercial);
                    break;
                  case 'receipt_archive':
                    _showReceiptVouchersArchive();
                    break;
                  case 'customer_receipts':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptsListScreen(
                          customerId: widget.customer.id,
                          customerName: widget.customer.name,
                        ),
                      ),
                    );
                    break;
                  case 'financial_integrity':
                    _showFinancialIntegrityReport();
                    break;
                  case 'audit_log':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AuditLogScreen(
                          customerId: widget.customer.id,
                          customerName: widget.customer.name,
                          entityType: 'customer',
                        ),
                      ),
                    );
                    break;
                  case 'delete_customer':
                    _handleDeleteCustomer();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'commercial_statement',
                  child: Row(
                    children: [
                      Icon(Icons.analytics, color: Colors.blueGrey, size: 20),
                      SizedBox(width: 12),
                      Text('كشف الحساب التجاري'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'customer_receipts',
                  child: Row(
                    children: [
                      Icon(Icons.history_edu, color: Colors.blueGrey, size: 20),
                      SizedBox(width: 12),
                      Text('وصولات القبض لهذا العميل'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'receipt_archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive, color: Colors.blueGrey, size: 20),
                      SizedBox(width: 12),
                      Text('أرشيف سندات القبض القديمة'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'financial_integrity',
                  child: Row(
                    children: [
                      Icon(Icons.verified_user, color: Colors.blueGrey, size: 20),
                      SizedBox(width: 12),
                      Text('فحص السلامة المالية'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'audit_log',
                  child: Row(
                    children: [
                      Icon(Icons.history, color: Colors.blueGrey, size: 20),
                      SizedBox(width: 12),
                      Text('سجل التدقيق المالي'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete_customer',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      SizedBox(width: 12),
                      Text('حذف العميل', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Consumer<AppProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(
                  child: CircularProgressIndicator(
                color: Color(0xFF3F51B5), // Explicitly set color for indicator
              ));
            }

            final customer = provider.selectedCustomer ?? widget.customer;
            final transactions = provider.customerTransactions;

            // 🖥️ الشاشات العريضة: عمود مقروء في الوسط بدل أسطر ممتدة على الشاشة كلها
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
              children: [
                // التحقق من تطابق الرصيد وعرض تنبيه
                Builder(
                  builder: (context) {
                    double calculatedBalance = 0.0;
                    for (var t in transactions) {
                      calculatedBalance += t.amountChanged;
                    }
                    final diff = (calculatedBalance - customer.currentTotalDebt).abs();
                    
                    if (diff > 0.01) {
                      return Container(
                        margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          border: Border.all(color: Colors.orange),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'تنبيه: يوجد اختلاف بين رصيد العميل ومجموع المعاملات.\nالرصيد المسجل: ${formatCurrency(customer.currentTotalDebt)}\nالمجموع الفعلي: ${formatCurrency(calculatedBalance)}',
                                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  // Dialog 1: Check if accounts are correct
                                  final result = await showDialog<String>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('تحقق من الحسابات'),
                                      content: Text(
                                        'يوجد اختلاف بين الرصيد المسجل (${formatCurrency(customer.currentTotalDebt)}) ومجموع المعاملات (${formatCurrency(calculatedBalance)}).\n\nهل أنت متأكد من أن الرصيد المسجل هو الصحيح؟'
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, 'no'),
                                          child: const Text('لا'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, 'yes'),
                                          child: const Text('نعم'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (!context.mounted) return;

                                  if (result == 'yes') {
                                    // User says Recorded Balance is correct -> Add correction transaction
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('إضافة معاملة تصحيحية'),
                                        content: Text(
                                          'سيتم إضافة معاملة بقيمة الفرق (${formatCurrency(customer.currentTotalDebt - calculatedBalance)}) ليصبح مجموع المعاملات مطابقاً للرصيد المسجل.\n\nهل أنت متأكد؟'
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم، أضف المعاملة')),
                                        ],
                                      ),
                                    );

                                    if (confirmed == true && mounted) {
                                      await SaveLock.run(() async {
                                      try {
                                        final db = DatabaseService();
                                        final diffAmount = customer.currentTotalDebt - calculatedBalance;
                                        final targetBalance = customer.currentTotalDebt;
                                        
                                        // 🔧 استخدام دالة التصحيح الخاصة التي تتجاوز التحقق الأمني
                                        await db.insertCorrectionTransaction(
                                          customerId: customer.id!,
                                          correctionAmount: diffAmount,
                                          targetBalance: targetBalance,
                                          note: 'تصحيح رصيد (رصيد افتتاحي سابق)',
                                        );
                                        
                                        // إعادة حساب تسلسل الأرصدة
                                        await db.recalculateCustomerTransactionBalances(customer.id!);
                                        
                                        // Reload customer and transactions to update UI with correct final values
                                        if (!context.mounted) return;
                                        final provider = context.read<AppProvider>();
                                        await provider.selectCustomer(customer);
                                        await _loadTransactions();
                                        
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('تم تصحيح الرصيد بنجاح')),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('خطأ: $e')),
                                          );
                                        }
                                      }
                                    }, message: 'جارٍ التصحيح…');
                                  }
                                  } else if (result == 'no') {
                                    // User says Recorded Balance is WRONG -> Ask to update it to match transactions
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('تحديث الرصيد المسجل'),
                                        content: Text(
                                          'مجموع المعاملات لهذا العميل هو ${formatCurrency(calculatedBalance)}.\n\nهل تريد اعتماد هذا المجموع كرصيد نهائي (بدلاً من ${formatCurrency(customer.currentTotalDebt)})؟'
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم، اعتمد المجموع')),
                                        ],
                                      ),
                                    );

                                    if (confirmed == true && mounted) {
                                      await SaveLock.run(() async {
                                      try {
                                        final provider = context.read<AppProvider>();
                                        final updatedCustomer = customer.copyWith(
                                          currentTotalDebt: calculatedBalance,
                                          lastModifiedAt: DateTime.now(),
                                        );
                                        
                                        await provider.updateCustomer(updatedCustomer, updateBalance: true);
                                        // Force reload to refresh UI
                                        await _loadTransactions();

                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('تم تحديث الرصيد المسجل بنجاح')),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('خطأ: $e')),
                                          );
                                        }
                                      }
                                    }, message: 'جارٍ الحفظ…');
                                  }
                                  }
                                },
                                icon: const Icon(Icons.build, size: 16),
                                label: const Text('حل مشكلة الاختلاف'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.orange[900],
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // التحقق من تزامن سجل المعاملات بشكل شامل
                      // 1. التحقق من آخر معاملة
                      final lastTxBalance = transactions.isNotEmpty ? (transactions.first.newBalanceAfterTransaction ?? 0.0) : 0.0;
                      bool historyMismatch = (calculatedBalance - lastTxBalance).abs() > 0.01;
                      
                      // 2. التحقق من تسلسل جميع المعاملات (balance_before صحيح لكل معاملة)
                      if (!historyMismatch && transactions.isNotEmpty) {
                        // ترتيب المعاملات من الأقدم للأحدث
                        final sortedTx = List.of(transactions)..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
                        double runningBalance = 0.0;
                        for (final tx in sortedTx) {
                          final expectedBefore = runningBalance;
                          final actualBefore = tx.balanceBeforeTransaction ?? 0.0;
                          // إذا كان الفرق أكبر من 0.01، هناك مشكلة في التسلسل
                          if ((expectedBefore - actualBefore).abs() > 0.01) {
                            historyMismatch = true;
                            break;
                          }
                          runningBalance += tx.amountChanged;
                        }
                      }
                      
                      if (historyMismatch) {
                         return Container(
                        margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          border: Border.all(color: Colors.blue),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Colors.blue),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'تنبيه: تسلسل الأرصدة في السجل يحتاج إلى تحديث.\nالمجموع صحيح (${formatCurrency(calculatedBalance)}) ولكن الأرصدة التراكمية غير متزامنة.',
                                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('تحديث السجل'),
                                      content: const Text(
                                        'سيتم إعادة حساب "الرصيد قبل" و "الرصيد بعد" لجميع المعاملات لضمان تسلسل صحيح.\nلن يتم تغيير المبلغ الإجمالي.\n\nهل تريد المتابعة؟'
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم، تحديث')),
                                      ],
                                    ),
                                  );
                                  
                                  if (confirmed == true && mounted) {
                                    await SaveLock.run(() async {
                                    try {
                                      final db = DatabaseService();
                                      // إعادة حساب تسلسل الأرصدة فقط
                                      await db.recalculateCustomerTransactionBalances(customer.id!);
                                      
                                      // تحديث الواجهة
                                      await _loadTransactions();
                                      
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('تم تحديث سجل المعاملات بنجاح')),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('خطأ: $e')),
                                        );
                                      }
                                    }
                                  }, message: 'جارٍ الحفظ…');
                                }
                                },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('تحديث تسلسل الأرصدة'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue[900],
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),
                _buildCustomerHeader(customer, transactions),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                  child: Row(children: [
                    const Icon(Icons.history_rounded, color: _navy, size: 21),
                    const SizedBox(width: 8),
                    const Text('سجل المعاملات',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text)),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('مجمّع'), icon: Icon(Icons.view_agenda_outlined, size: 16)),
                        ButtonSegment(value: false, label: Text('تفصيلي'), icon: Icon(Icons.view_list_rounded, size: 16)),
                      ],
                      selected: {_useGroupedView},
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      onSelectionChanged: (sel) => setState(() => _useGroupedView = sel.first),
                    ),
                  ]),
                ),
                _useGroupedView
                    // 📊 العرض المجمع الجديد
                    ? _groupedTransactions.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text('لا توجد معاملات',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(color: Colors.grey[600])),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 12.0),
                              itemCount: _groupedTransactions.length,
                              itemBuilder: (context, index) {
                                final item = _groupedTransactions[index];
                                return GroupedTransactionListTile(
                                  item: item,
                                  customerId: widget.customer.id!,
                                  onRefresh: () async {
                                    // 🔄 جلب بيانات العميل المحدّثة من قاعدة البيانات
                                    final db = DatabaseService();
                                    final updatedCustomer = await db.getCustomerById(widget.customer.id!);
                                    if (updatedCustomer != null && context.mounted) {
                                      await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                    }
                                    await _loadTransactions();
                                  },
                                );
                              },
                            )
                      // العرض التفصيلي القديم
                      : transactions.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text('لا توجد معاملات',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(color: Colors.grey[600])),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                  vertical: 12.0), // Padding for the list
                              itemCount: transactions.length,
                              itemBuilder: (context, index) {
                                final transaction = transactions[index];
                                return TransactionListTile(
                                  transaction: transaction,
                                  invoiceNumber: _invoiceNumberMap[transaction.invoiceId],
                                  onEdit: (updated) => SaveLock.run(() async {
                                    // 🚫 سقف الدين: تعديل يرفع الرصيد (زيادة دين أو إنقاص تسديد)
                                    final rise = updated.amountChanged - transaction.amountChanged;
                                    if (rise > 0.5) {
                                      final go = await CreditLimitGuard.enforce(
                                        context,
                                        customerId: transaction.customerId,
                                        increase: rise,
                                        what: 'تعديل معاملة — ${widget.customer.name}',
                                      );
                                      if (!go) return;
                                    }
                                    try {
                                      final db = DatabaseService();
                                      final updatedCustomer = await db.updateTransaction(updated);
                                      
                                      // تحديث البيانات بعد التعديل
                                      await _loadTransactions();
                                      
                                      // تحديث المزود والواجهة بالبيانات المحدثة
                                      if (!context.mounted) return;
                                      await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('تم تحديث المعاملة. الدين الحالي: ${formatCurrency(updatedCustomer.currentTotalDebt)}')),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('حدث خطأ: ${e.toString()}'),
                                            backgroundColor: Theme.of(context).colorScheme.error,
                                          ),
                                        );
                                      }
                                    }
                                  }, message: 'جارٍ تعديل المعاملة…'),
                                  onConvertType: (transactionId) async {
                                try {
                                  final db = DatabaseService();
                                  final updatedCustomer = await db.convertTransactionType(transactionId);
                                  // تحديث البيانات بعد التحويل
                                  await _loadTransactions();
                                  
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('تم تحويل نوع المعاملة بنجاح'),
                                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                                      ),
                                    );
                                  }
                                  
                                  // حدث المزود والواجهة بالبيانات المحدثة
                                  if (!context.mounted) return;
                                  await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('تم تحديث المعاملة. الدين الحالي: ${formatCurrency(updatedCustomer.currentTotalDebt)}')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('حدث خطأ: ${e.toString()}'),
                                        backgroundColor: Theme.of(context).colorScheme.error,
                                      ),
                                    );
                                  }
                                }
                              },
                                  onRefresh: () async {
                                    // 🔄 جلب بيانات العميل المحدّثة من قاعدة البيانات
                                    final db = DatabaseService();
                                    final updatedCustomer = await db.getCustomerById(widget.customer.id!);
                                    if (updatedCustomer != null && context.mounted) {
                                      await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                    }
                                    await _loadTransactions();
                                  },
                            );
                          },
                        ),
              ],
            ),
          )));
          },
        ),
      ),
    );
  }

  // ═══════════════════════════ رأس العميل ═══════════════════════════

  static const _navy = Color(0xFF0F3460);
  static const _border = Color(0xFFE3E9F1);
  static const _text = Color(0xFF1E293B);
  static const _muted = Color(0xFF64748B);
  static const _red = Color(0xFFB91C1C);
  static const _green = Color(0xFF047857);

  /// بطاقة العميل أعلى الشاشة: الاسم والتواصل، الرصيد بحالته، آخر حركة دين
  /// وتسديد، والملاحظة بسطور كاملة (كانت في صف واحد فتفيض خارج الشاشة).
  Widget _buildCustomerHeader(Customer customer, List<DebtTransaction> txs) {
    final debt = customer.currentTotalDebt;
    final owes = debt > 0.5;
    final credit = debt < -0.5;
    final color = owes ? _red : (credit ? _green : _muted);
    final status = owes ? 'عليه' : (credit ? 'له (رصيد دائن)' : 'مسدَّد');
    DebtTransaction? lastDebt, lastPay;
    var totalDebt = 0.0, totalPaid = 0.0;
    for (final t in txs) {
      if (t.amountChanged > 0) {
        totalDebt += t.amountChanged;
        if (lastDebt == null || t.transactionDate.isAfter(lastDebt.transactionDate)) lastDebt = t;
      } else if (t.amountChanged < 0) {
        totalPaid += -t.amountChanged;
        if (lastPay == null || t.transactionDate.isAfter(lastPay.transactionDate)) lastPay = t;
      }
    }
    final df = DateFormat('yyyy/MM/dd', 'en');
    final name = customer.name.trim();
    final initial = name.isEmpty ? '؟' : name.substring(0, 1);
    final contact = [
      if ((customer.phone ?? '').trim().isNotEmpty) customer.phone!.trim(),
      if ((customer.address ?? '').trim().isNotEmpty) customer.address!.trim(),
    ];
    Widget fact(IconData icon, String label, String value, {Color? c}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: c ?? _muted),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c ?? _text)),
            ]),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 5, color: color),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withValues(alpha: 0.10),
                child: Text(initial, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customer.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _text)),
                  const SizedBox(height: 4),
                  if (contact.isEmpty)
                    const Text('لا هاتف ولا عنوان — أضفهما من «تعديل»', style: TextStyle(color: _muted))
                  else
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      if ((customer.phone ?? '').trim().isNotEmpty)
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: customer.phone!.trim()));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text('نُسخ رقم الهاتف'), duration: Duration(seconds: 1)));
                          },
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.phone_rounded, size: 16, color: _muted),
                            const SizedBox(width: 4),
                            Text(customer.phone!.trim(),
                                textDirection: TextDirection.ltr, style: const TextStyle(color: _text)),
                          ]),
                        ),
                      if ((customer.address ?? '').trim().isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.location_on_rounded, size: 16, color: _muted),
                          const SizedBox(width: 4),
                          Flexible(child: Text(customer.address!.trim(), style: const TextStyle(color: _text))),
                        ]),
                    ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                  child: Text(status, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
                ),
                const SizedBox(height: 4),
                Text(formatCurrency(debt.abs()),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color)),
                const Text('دينار', style: TextStyle(fontSize: 11.5, color: _muted)),
              ]),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (lastDebt != null)
                fact(Icons.add_circle_outline_rounded, 'آخر دين',
                    '${df.format(lastDebt.transactionDate)} — ${formatCurrency(lastDebt.amountChanged)}',
                    c: _red),
              if (lastPay != null)
                fact(Icons.payments_outlined, 'آخر تسديد',
                    '${df.format(lastPay.transactionDate)} — ${formatCurrency(-lastPay.amountChanged)}',
                    c: _green),
              fact(Icons.trending_up_rounded, 'مجموع ما استدانه', formatCurrency(totalDebt)),
              fact(Icons.price_check_rounded, 'مجموع ما سدّده', formatCurrency(totalPaid)),
              fact(Icons.receipt_long_outlined, 'الحركات', '${txs.length}'),
            ]),
            if ((customer.generalNote ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _editCustomerDetails,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.sticky_note_2_outlined, size: 19, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('ملاحظات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
                        const SizedBox(height: 2),
                        Text(customer.generalNote!.trim(), style: const TextStyle(height: 1.6, color: _text)),
                      ]),
                    ),
                    const Icon(Icons.edit_outlined, size: 16, color: _muted),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _red, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                onPressed: () => _openTransaction(customer, isDebt: true),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('إضافة دين', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                onPressed: () => _openTransaction(customer, isDebt: false),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('تسديد', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
                onPressed: () => _openStatements(),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('كشف الحساب'),
              ),
              // 📅 مواعيد المطالبة بهذا الدين
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                onPressed: customer.id == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DebtRemindersScreen(customerId: customer.id, customerName: customer.name),
                          ),
                        ),
                icon: const Icon(Icons.event_repeat_rounded),
                label: const Text('مواعيد المطالبة'),
              ),
              if ((customer.phone ?? '').trim().isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
                  onPressed: _sendWhatsAppMessage,
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('واتساب'),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  // 🛡️ دالة عرض تقرير السلامة المالية
  Future<void> _showFinancialIntegrityReport() async {
    try {
      // إظهار مؤشر التحميل
      LoadingDialog.show(
        context,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final db = DatabaseService();
      final report = await db.verifyCustomerFinancialIntegrity(widget.customer.id!);

      LoadingDialog.hide(); // إغلاق مؤشر التحميل

      if (!mounted) return;

      // عرض التقرير
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                report.isHealthy ? Icons.check_circle : Icons.warning,
                color: report.isHealthy ? Colors.green : Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                report.isHealthy ? 'البيانات سليمة ✅' : 'يوجد تحذيرات ⚠️',
                style: TextStyle(
                  color: report.isHealthy ? Colors.green[700] : Colors.orange[700],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // معلومات الرصيد
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📊 معلومات الرصيد:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('الرصيد المسجل: ${formatCurrency(report.recordedBalance)} دينار'),
                        Text('الرصيد المحسوب: ${formatCurrency(report.calculatedBalance)} دينار'),
                        Text('عدد المعاملات: ${formatCurrency(report.transactionCount)}'),
                        if ((report.recordedBalance - report.calculatedBalance).abs() > 0.01)
                          Text(
                            'الفرق: ${formatCurrency((report.recordedBalance - report.calculatedBalance).abs())} دينار',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ),
                
                // 📈 ملخص كشف الحساب التجاري
                const SizedBox(height: 12),
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📈 ملخص كشف الحساب التجاري:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('إجمالي الفواتير: ${report.totalInvoices}'),
                                  Text('فواتير دين: ${report.debtInvoices}', style: TextStyle(color: Colors.orange[700])),
                                  Text('فواتير نقد: ${report.cashInvoices}', style: TextStyle(color: Colors.green[700])),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('مبالغ الفواتير: ${formatCurrency(report.totalInvoiceAmount)}'),
                                  Text('المدفوعات: ${formatCurrency(report.totalPayments)}', style: TextStyle(color: Colors.green[700])),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                // المشاكل
                if (report.issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('❌ مشاكل:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...report.issues.map((issue) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $issue', style: const TextStyle(color: Colors.red)),
                  )),
                ],
                
                // التحذيرات
                if (report.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('⚠️ تحذيرات:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ...report.warnings.take(5).map((warning) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $warning', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
                  )),
                  if (report.warnings.length > 5)
                    Text('... و ${report.warnings.length - 5} تحذيرات أخرى', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
                
                // 🔍 مشاكل الفواتير (تفصيلية)
                if (report.invoiceIssues.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.receipt_long, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '🧾 مشاكل في الفواتير (${report.invoiceIssues.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...report.invoiceIssues.map((issue) => Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '📄 فاتورة #${issue.invoiceId} - ${issue.invoiceDate}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  // 🔧 زر الإصلاح
                                  ElevatedButton.icon(
                                    onPressed: () => _showRepairConfirmationDialog(context, issue),
                                    icon: const Icon(Icons.build, size: 14),
                                    label: const Text('إصلاح', style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 28),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                issue.description,
                                style: TextStyle(color: Colors.red[700], fontSize: 12),
                              ),
                              Text(
                                'الفرق: ${NumberFormat('#,##0.##', 'en_US').format(issue.difference)} دينار',
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              if (issue.details.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Material(type: MaterialType.transparency, child: ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding: const EdgeInsets.only(right: 8),
                                  title: const Text('عرض التفاصيل', style: TextStyle(fontSize: 11, color: Colors.blue)),
                                  children: issue.details.map((d) => Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(d, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
                                  )).toList(),
                                )),
                              ],
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
                
                // رسالة النجاح
                if (report.isHealthy && report.issues.isEmpty && report.warnings.isEmpty && report.invoiceIssues.isEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'جميع البيانات المالية لهذا العميل سليمة 100%',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      LoadingDialog.hide(); // إغلاق مؤشر التحميل إن كان مفتوحاً
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فحص السلامة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔧 دالة عرض نافذة تأكيد الإصلاح
  Future<void> _showRepairConfirmationDialog(BuildContext parentContext, InvoiceIssue issue) async {
    final confirmed = await showDialog<bool>(
      context: parentContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
            const SizedBox(width: 8),
            const Text('تأكيد الإصلاح', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // تفاصيل المشكلة
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📄 فاتورة #${issue.invoiceId}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text('التاريخ: ${issue.invoiceDate}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      'المشكلة: ${issue.description}',
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
                    ),
                    Text(
                      'الفرق: ${NumberFormat('#,##0', 'en_US').format(issue.difference)} دينار',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // التحذيرات
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        const Text('تحذيرات مهمة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('• سيتم إضافة معاملة تصحيحية لموازنة الفرق', style: TextStyle(fontSize: 12)),
                    const Text('• هذا الإجراء لا يمكن التراجع عنه', style: TextStyle(fontSize: 12)),
                    const Text('• تأكد من مراجعة الفاتورة يدوياً قبل الإصلاح', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // السؤال
              const Text(
                'هل أنت متأكد من الإصلاح؟\nهل قمت بجميع المراجعات اليدوية؟',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، متأكد'),
          ),
        ],
      ),
    );

    if (confirmed == true && parentContext.mounted) {
      // عرض التحدي الرياضي
      await _showMathChallengeDialog(parentContext, issue);
    }
  }

  // 🧮 دالة عرض التحدي الرياضي
  Future<void> _showMathChallengeDialog(BuildContext parentContext, InvoiceIssue issue) async {
    final random = DateTime.now().millisecondsSinceEpoch;
    final num1 = (random % 10); // رقم من 0 إلى 9
    final num2 = ((random ~/ 10) % 10); // رقم آخر من 0 إلى 9
    final correctAnswer = num1 + num2;
    final answerController = TextEditingController();

    final passed = await showDialog<bool>(
      context: parentContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.calculate, color: Colors.blue[700], size: 28),
            const SizedBox(width: 8),
            const Text('تحدي التأكيد', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'للتأكد من أنك تريد الإصلاح فعلاً،\nأجب على السؤال التالي:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                '$num1 + $num2 = ؟',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: answerController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'أدخل الإجابة',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              onSubmitted: (value) {
                final answer = int.tryParse(value) ?? -1;
                Navigator.pop(context, answer == correctAnswer);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final answer = int.tryParse(answerController.text) ?? -1;
              Navigator.pop(context, answer == correctAnswer);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (passed == true && mounted) {
      // تنفيذ الإصلاح
      await _executeInvoiceRepair(issue);
    } else if (passed == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الإجابة غير صحيحة - تم إلغاء الإصلاح'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 🔧 دالة تنفيذ الإصلاح الفعلي
  Future<void> _executeInvoiceRepair(InvoiceIssue issue) async {
    try {
      // إظهار مؤشر التحميل
      LoadingDialog.show(
        context,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final db = DatabaseService();
      
      // تنفيذ الإصلاح
      final result = await db.repairInvoiceTransactionMismatch(
        invoiceId: issue.invoiceId,
        customerId: widget.customer.id!,
        expectedDifference: issue.difference,
      );

      LoadingDialog.hide(); // إغلاق مؤشر التحميل

      if (!mounted) return;

      if (result['success'] == true) {
        // إعادة تحميل البيانات
        await _loadTransactions();
        if (!mounted) return;
        await context.read<AppProvider>().selectCustomer(widget.customer);
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${result['message']}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // إغلاق نافذة التقرير وإعادة فتحها لعرض النتائج المحدثة
        Navigator.of(context, rootNavigator: true).pop();
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          await _showFinancialIntegrityReport();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${result['message']}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      LoadingDialog.hide(); // إغلاق مؤشر التحميل إن كان مفتوحاً
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الإصلاح: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 📄 دالة عرض أرشيف سندات القبض
  Future<void> _showReceiptVouchersArchive() async {
    try {
      // إظهار مؤشر التحميل
      LoadingDialog.show(
        context,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final db = DatabaseService();
      final receipts = await db.getCustomerReceiptVouchers(widget.customer.id!);

      LoadingDialog.hide(); // إغلاق مؤشر التحميل

      if (!mounted) return;

      // عرض قائمة سندات القبض
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.archive, color: Color(0xFF3F51B5)),
              const SizedBox(width: 12),
              Text('أرشيف سندات القبض (${receipts.length})'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: receipts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد سندات قبض محفوظة',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: receipts.length,
                    itemBuilder: (context, index) {
                      final receipt = receipts[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[100],
                            child: Text(
                              '${receipt.receiptNumber}',
                              style: TextStyle(
                                color: Colors.green[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            '${formatCurrency(receipt.paidAmount)} دينار',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'رقم السند: ${receipt.receiptNumber} | التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(receipt.createdAt)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                'قبل: ${formatCurrency(receipt.beforePayment)} → بعد: ${formatCurrency(receipt.afterPayment)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.print, color: Color(0xFF3F51B5)),
                            tooltip: 'إعادة طباعة السند',
                            onPressed: () => _reprintReceiptVoucher(receipt),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      LoadingDialog.hide(); // إغلاق مؤشر التحميل إن كان مفتوحاً
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل سندات القبض: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 📄 دالة إعادة طباعة سند القبض
  Future<void> _reprintReceiptVoucher(CustomerReceiptVoucher receipt) async {
    try {
      final font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
      // استخدام نفس خط الفاتورة لكلمة الناصر
      final alnaserFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
      // تحميل اللوجو باستخدام خدمة اللوجو
      final logoImage = await LogoService.getLogoImage();
      
      // 👤 المحاسب = من سجّل التسديد (من حركته)، لا من يطبع الآن
      String? recordedBy;
      if (receipt.transactionId != null) {
        try {
          final tr = await (await DatabaseService().database).query('transactions',
              columns: ['created_by_username'], where: 'id = ?', whereArgs: [receipt.transactionId], limit: 1);
          recordedBy = tr.isEmpty ? null : tr.first['created_by_username'] as String?;
        } catch (_) {}
      }
      final pdf = await ReceiptVoucherPdfService.generateReceiptVoucherPdf(
        recordedBy: recordedBy,
        customerName: receipt.customerName,
        beforePayment: receipt.beforePayment,
        paidAmount: receipt.paidAmount,
        afterPayment: receipt.afterPayment,
        dateTime: receipt.createdAt,
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        receiptNumber: receipt.receiptNumber,
      );

      // 🌐 الويب: فتح نافذة الطباعة مباشرة وتجنب استدعاءات Platform
      if (kIsWeb) {
        await Printing.layoutPdf(
          onLayout: (format) async => await pdf.save(),
          name: 'سند_قبض_${receipt.receiptNumber}.pdf',
        );
        return;
      }

      // حفظ PDF في ملف مؤقت وفتحه
      final tempDir = Directory.systemTemp;
      final filePath =
          '${tempDir.path}/receipt_voucher_${receipt.receiptNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'msedge', filePath]);
      } else {
        await Printing.layoutPdf(
          onLayout: (format) async => await pdf.save(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فتح سند القبض للطباعة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في طباعة السند: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 📊 عرض كشف الحساب التجاري
  /// 📄 كشوفات الحساب: شامل / من آخر رصيد صفر / فترة × تفصيلي أو ملخص، والكشف التجاري
  void _openStatements({StatementTab tab = StatementTab.account}) {
    final id = widget.customer.id;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerStatementsScreen(
          customerId: id,
          customerName: widget.customer.name,
          initialTab: tab,
        ),
      ),
    );
  }



}

class TransactionListTile extends StatelessWidget {
  final DebtTransaction transaction;
  final String? invoiceNumber;
  
  // Callbacks for edit and refresh after change
  final Future<void> Function(DebtTransaction updated)? onEdit;
  // Callback for converting transaction type
  final Future<void> Function(int transactionId)? onConvertType;
  // 🔄 Callback لتحديث البيانات عند الرجوع من الفاتورة
  final VoidCallback? onRefresh;

  const TransactionListTile({
    super.key,
    required this.transaction,
    this.invoiceNumber,
    this.onEdit,
    this.onConvertType,
    this.onRefresh,
  });

  // Helper to format numbers with thousand separators
  String _formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final isDebt = transaction.amountChanged > 0;
    final color = isDebt
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary; // Use themed colors
    final icon = isDebt ? Icons.add : Icons.remove;
    final isInvoiceRelated = transaction.invoiceId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0), // Spacing between cards
      elevation: 0,
      child: ListTile(
        onTap: isInvoiceRelated
            ? () => _navigateToInvoiceDetails(
                context, transaction.customerId, transaction.invoiceId!)
            : null,
        leading: CircleAvatar(
          backgroundColor:
              color.withValues(alpha: 0.1), // Lighter background for avatar
          child: Icon(icon, color: color, size: 28), // Larger, themed icon
        ),
        title: Text(
          '${_formatCurrency(transaction.amountChanged.abs())} دينار', // Formatted amount
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                // Themed text style
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرصيد قبل المعاملة: ${_formatCurrency(transaction.balanceBeforeTransaction ?? 0.0)} دينار', // Formatted balance before
              style:
                  Theme.of(context).textTheme.bodyMedium, // Themed text style
            ),
            Text(
              'الرصيد بعد المعاملة: ${_formatCurrency(transaction.newBalanceAfterTransaction ?? 0.0)} دينار', // Formatted balance after
              style:
                  Theme.of(context).textTheme.bodyMedium, // Themed text style
            ),
            if (transaction.transactionNote != null &&
                transaction.transactionNote!.isNotEmpty)
              Text(transaction.transactionNote!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall), // Themed text style
            if ((transaction.createdByUsername ?? '').isNotEmpty)
              Text('👤 ${transaction.createdByUsername}', style: Theme.of(context).textTheme.bodySmall),
            if (isInvoiceRelated)
              Text(
                'مرتبطة بالفاتورة #${invoiceNumber ?? transaction.invoiceId}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600]), // Themed text style
              ),
          ],
        ),
        trailing: SizedBox(
          height: 48, // التزام بارتفاع ListTile القياسي لمنع overflow
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 🔒 المعاملات المرتبطة بالفواتير لا يتم تعديلها من سجل المعاملات لمنع تضارب الحسابات
              if (transaction.isCreatedByMe && !isInvoiceRelated)
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'تعديل المعاملة',
                  onPressed: () async {
                if (onEdit == null) return;
                // ✏️ نافذة التعديل الجديدة (widgets/edit_transaction_dialog.dart)
                final r = await showEditTransactionDialog(context, transaction);
                if (r == null) return;
                final updated = transaction.copyWith(
                  amountChanged: r.amount,
                  transactionNote: r.note,
                  transactionDate: r.date,
                  transactionType: (r.amount >= 0) ? 'manual_debt' : 'manual_payment',
                );
                await onEdit!(updated);
              },
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(transaction.transactionDate),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd HH:mm').format(date); // التاريخ مع الوقت (ساعة:دقيقة)
  }

  void _navigateToInvoiceDetails(
      BuildContext context, int customerId, int invoiceId) async {
    try {
      final db = DatabaseService();
      final invoice = await db.getInvoiceById(invoiceId);
      DebtTransaction? relatedDebtTransaction;
      final transactions = await db.getCustomerTransactions(customerId);
      for (var transaction in transactions) {
        if (transaction.invoiceId == invoiceId &&
            transaction.amountChanged > 0) {
          relatedDebtTransaction = transaction;
          break;
        }
      }

      if (invoice != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateInvoiceScreen(
              existingInvoice: invoice,
              isViewOnly: invoice.status == 'محفوظة',
              relatedDebtTransaction: relatedDebtTransaction,
            ),
          ),
        ).then((_) {
          // 🔄 تحديث البيانات عند الرجوع من الفاتورة
          onRefresh?.call();
        });
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('لم يتم العثور على الفاتورة المطلوبة.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ عند تحميل الفاتورة: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// 📊 Widget لعرض المعاملات المجمعة
// ═══════════════════════════════════════════════════════════════════════════

class GroupedTransactionListTile extends StatelessWidget {
  final GroupedTransactionItem item;
  final VoidCallback onRefresh;
  final int customerId; // إضافة معرف العميل للتنقل للفاتورة

  const GroupedTransactionListTile({
    super.key,
    required this.item,
    required this.onRefresh,
    required this.customerId,
  });

  String _formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    if (item.isInvoice) {
      return _buildInvoiceTile(context);
    } else if (item.isManualDebtGroup) {
      return _buildManualGroupTile(context, isDebt: true, isSync: false);
    } else if (item.isManualPaymentGroup) {
      return _buildManualGroupTile(context, isDebt: false, isSync: false);
    } else if (item.isSyncDebtGroup) {
      return _buildManualGroupTile(context, isDebt: true, isSync: true);
    } else if (item.isSyncPaymentGroup) {
      return _buildManualGroupTile(context, isDebt: false, isSync: true);
    } else {
      return _buildManualTransactionTile(context);
    }
  }

  // 🧾 سطر دفتر: حافة ملونة بنوع الحركة، التاريخ، البيان، المبلغ، والرصيد بعده
  static const _lInk = Color(0xFF1B2433);
  static const _lMuted = Color(0xFF667085);
  static const _lLine = Color(0xFFE4E9F1);
  static const _lDebt = Color(0xFFB42318);
  static const _lPay = Color(0xFF067647);
  static const _lInv = Color(0xFF1D4ED8);
  static const _lSync = Color(0xFF0E7490);

  Widget _ledger(
    BuildContext context, {
    required Color edge,
    required IconData icon,
    required String title,
    String? subtitle,
    List<Widget> badges = const [],
    required String amount,
    required Color amountColor,
    String? amountCaption,
    double? balanceAfter,
    VoidCallback? onTap,
    Widget? action,
    Color? background,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lLine),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: edge),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: edge.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: edge, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _lInk)),
                          ...badges,
                        ]),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: _lMuted, height: 1.4)),
                          ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                      if (amountCaption != null)
                        Text(amountCaption, style: const TextStyle(fontSize: 11.5, color: _lMuted)),
                      Text(amount,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              color: amountColor,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                      if (balanceAfter != null)
                        Text('الرصيد ${_formatCurrency(balanceAfter)}',
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(fontSize: 11.5, color: _lMuted)),
                    ]),
                    if (action != null) ...[const SizedBox(width: 4), action],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      );

  /// بناء بطاقة الفاتورة المجمعة
  Widget _buildInvoiceTile(BuildContext context) {
    final paid = item.isFullyPaid;
    final cash = item.isCashInvoice;
    final edge = paid ? _lPay : (cash ? _lInv : _lDebt);
    final total = item.invoiceTotal ?? 0;
    final sub = [
      _formatDate(item.date),
      'الإجمالي ${_formatCurrency(total)}',
      if ((item.invoicePaid ?? 0) > 0 && !cash) 'مسدد عليها ${_formatCurrency(item.invoicePaid!)}',
    ].join('  •  ');
    return _ledger(
      context,
      edge: edge,
      icon: paid ? Icons.task_alt_rounded : (cash ? Icons.payments_rounded : Icons.receipt_long_rounded),
      title: item.description,
      subtitle: sub,
      badges: [
        _badge(cash ? 'نقد' : 'دين', cash ? _lInv : _lDebt),
        if (item.transactionCount > 1) _badge('${item.transactionCount - 1} تعديل', const Color(0xFF7A5AF8)),
      ],
      amountCaption: paid ? 'مسددة' : (cash ? 'نقد' : 'المتبقي عليه'),
      amount: _formatCurrency(item.amount.abs()),
      amountColor: paid ? _lPay : (item.amount > 0 ? _lDebt : _lPay),
      balanceAfter: item.balanceAfter,
      onTap: () => _showInvoiceDetails(context),
      action: IconButton(
        icon: const Icon(Icons.open_in_new_rounded, size: 19, color: _lMuted),
        tooltip: 'فتح الفاتورة',
        onPressed: () => _navigateToInvoice(context),
      ),
    );
  }

  /// بناء بطاقة المعاملة اليدوية
  Widget _buildManualTransactionTile(BuildContext context) {
    final isDebt = item.amount > 0;
    final c = isDebt ? _lDebt : _lPay;
    return _ledger(
      context,
      edge: c,
      icon: isDebt ? Icons.north_east_rounded : Icons.south_west_rounded,
      title: isDebt ? 'دين' : 'تسديد',
      subtitle: [_formatDate(item.date), if (item.description.trim().isNotEmpty) item.description.trim()].join('  •  '),
      amount: '${isDebt ? '+' : '−'}${_formatCurrency(item.amount.abs())}',
      amountColor: c,
      balanceAfter: item.balanceAfter,
    );
  }

  /// بناء بطاقة مجموعة المعاملات اليدوية أو المزامنة (إضافة دين أو تسديد)
  Widget _buildManualGroupTile(BuildContext context, {required bool isDebt, required bool isSync}) {
    final c = isDebt ? _lDebt : _lPay;
    final title = isDebt ? 'ديون يدوية' : 'تسديدات';
    return _ledger(
      context,
      edge: isSync ? _lSync : c,
      icon: isSync
          ? (isDebt ? Icons.cloud_download_rounded : Icons.cloud_upload_rounded)
          : (isDebt ? Icons.north_east_rounded : Icons.south_west_rounded),
      title: title,
      subtitle: 'آخرها ${_formatDate(item.date)}',
      badges: [
        _badge('${item.transactionCount} معاملة', c),
        if (isSync) _badge('من جهاز آخر', _lSync),
      ],
      amountCaption: 'المجموع',
      amount: '${isDebt ? '+' : '−'}${_formatCurrency(item.amount.abs())}',
      amountColor: c,
      balanceAfter: item.balanceAfter,
      onTap: () => _showManualGroupDetails(context, isDebt: isDebt, isSync: isSync),
      background: isSync ? const Color(0xFFF2FBFD) : null,
      action: const Icon(Icons.chevron_left_rounded, color: _lMuted),
    );
  }

  /// عرض تفاصيل مجموعة المعاملات اليدوية أو المزامنة
  void _showManualGroupDetails(BuildContext context, {required bool isDebt, required bool isSync}) {
    final color = isDebt
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    
    final String title;
    final IconData icon;
    if (isSync) {
      title = isDebt ? 'معاملات المزامنة (إضافة دين)' : 'معاملات المزامنة (تسديد)';
      icon = isDebt ? Icons.cloud_download : Icons.cloud_upload;
    } else {
      title = isDebt ? 'معاملات الإضافة اليدوية' : 'معاملات التسديد اليدوية';
      icon = isDebt ? Icons.add_circle : Icons.remove_circle;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // المقبض
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // العنوان
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: isSync ? Colors.blue : color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            if (isSync) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sync, color: Colors.white, size: 12),
                                    SizedBox(width: 2),
                                    Text(
                                      'من جهاز آخر',
                                      style: TextStyle(fontSize: 10, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${_formatCurrency(item.transactionCount)} معاملة',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // المجموع
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${isDebt ? '+' : ''}${_formatCurrency(item.amount.abs())} دينار',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            // قائمة المعاملات
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: item.transactions.length,
                itemBuilder: (context, index) {
                  final tx = item.transactions[index];
                  final isPositive = tx.amountChanged > 0;
                  final txColor = isPositive ? Colors.red : Colors.green;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    // خلفية مميزة لمعاملات المزامنة
                    color: isSync ? Colors.blue[50] : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSync ? Colors.blue.withValues(alpha: 0.2) : txColor.withValues(alpha: 0.1),
                        radius: 18,
                        child: isSync 
                            ? const Icon(Icons.sync, color: Colors.blue, size: 16)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(color: txColor, fontWeight: FontWeight.bold),
                              ),
                      ),
                      title: Text(
                        '${isPositive ? '+' : ''}${_formatCurrency(tx.amountChanged)} دينار',
                        style: TextStyle(
                          color: txColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTransactionTypeLabel(tx.transactionType),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (tx.transactionNote != null && tx.transactionNote!.isNotEmpty)
                            Text(
                              tx.transactionNote!,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          if ((tx.createdByUsername ?? '').isNotEmpty)
                            Text('👤 ${tx.createdByUsername}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          Text(
                            DateFormat('yyyy/MM/dd HH:mm').format(tx.transactionDate),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'قبل: ${_formatCurrency(tx.balanceBeforeTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          Text(
                            'بعد: ${_formatCurrency(tx.newBalanceAfterTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ملخص
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'المجموع:',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    '${isDebt ? '+' : ''}${_formatCurrency(item.amount.abs())} دينار',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
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

  /// عرض تفاصيل الفاتورة (جميع المعاملات المرتبطة)
  void _showInvoiceDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.45,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // المقبض
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // العنوان
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تفاصيل فاتورة #${item.invoiceNumber ?? item.invoiceId}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'إجمالي الفاتورة: ${_formatCurrency(item.invoiceTotal ?? 0)} دينار',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // المبلغ المتبقي
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.isFullyPaid ? Colors.green[100] : Colors.orange[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.isFullyPaid
                          ? 'مسددة ✓'
                          : 'متبقي: ${_formatCurrency(item.amount.abs())}',
                      style: TextStyle(
                        color: item.isFullyPaid ? Colors.green[800] : Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // زر الذهاب للفاتورة
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // إغلاق الـ BottomSheet
                    _navigateToInvoice(context);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('الذهاب للفاتورة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            // قائمة المعاملات
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: item.transactions.length,
                itemBuilder: (context, index) {
                  final tx = item.transactions[index];
                  final isPositive = tx.amountChanged > 0;
                  final txColor = isPositive ? Colors.red : Colors.green;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: txColor.withValues(alpha: 0.1),
                        radius: 18,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: txColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        '${isPositive ? '+' : ''}${_formatCurrency(tx.amountChanged)} دينار',
                        style: TextStyle(
                          color: txColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTransactionTypeLabel(tx.transactionType),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (tx.transactionNote != null && tx.transactionNote!.isNotEmpty)
                            Text(
                              tx.transactionNote!,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          if ((tx.createdByUsername ?? '').isNotEmpty)
                            Text('👤 ${tx.createdByUsername}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          Text(
                            DateFormat('yyyy/MM/dd HH:mm').format(tx.transactionDate),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'قبل: ${_formatCurrency(tx.balanceBeforeTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          Text(
                            'بعد: ${_formatCurrency(tx.newBalanceAfterTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ملخص
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'صافي المعاملات:',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    '${_formatCurrency(item.amount)} دينار',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: item.amount > 0 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
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

  /// الذهاب مباشرة لشاشة الفاتورة
  void _navigateToInvoice(BuildContext context) async {
    if (item.invoiceId == null) return;
    
    try {
      final db = DatabaseService();
      final invoice = await db.getInvoiceById(item.invoiceId!);
      DebtTransaction? relatedDebtTransaction;
      final transactions = await db.getCustomerTransactions(customerId);
      for (var transaction in transactions) {
        if (transaction.invoiceId == item.invoiceId &&
            transaction.amountChanged > 0) {
          relatedDebtTransaction = transaction;
          break;
        }
      }

      if (invoice != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateInvoiceScreen(
              existingInvoice: invoice,
              isViewOnly: invoice.status == 'محفوظة',
              relatedDebtTransaction: relatedDebtTransaction,
            ),
          ),
        ).then((_) {
          // 🔄 تحديث البيانات عند الرجوع من الفاتورة
          onRefresh();
        });
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('لم يتم العثور على الفاتورة المطلوبة.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ عند تحميل الفاتورة: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _getTransactionTypeLabel(String? type) {
    switch (type) {
      case 'invoice_debt':
      case 'debt_invoice':
        return '📄 إنشاء دين الفاتورة';
      case 'invoice_payment':
        return '💰 تسديد على الفاتورة';
      case 'invoice_adjustment':
        return '✏️ تعديل الفاتورة';
      case 'invoice_discount':
        return '🏷️ خصم على الفاتورة';
      case 'payment_type_change':
        return '🔄 تحويل نوع الدفع';
      case 'manual_payment':
        return '💵 تسديد يدوي';
      case 'manual_debt':
        return '📝 دين يدوي';
      default:
        return '📋 معاملة';
    }
  }
}
