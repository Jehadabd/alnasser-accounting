// خدمة إرسال النسخ الاحتياطية إلى Telegram
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'settings_manager.dart';
import 'database_service.dart';
import '../models/customer.dart';
import '../models/account_statement_item.dart';
import 'pdf_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'debt_report_service.dart'; // import DebtReportService
import 'discord_backup_service.dart'; // 🆕 Discord Integration

/// نتيجة عملية الإرسال مع تفاصيل الخطأ
class TelegramSendResult {
  final bool success;
  final String? errorMessage;
  final String? errorDetails;
  final int? statusCode;
  
  TelegramSendResult({
    required this.success,
    this.errorMessage,
    this.errorDetails,
    this.statusCode,
  });
  
  factory TelegramSendResult.ok() => TelegramSendResult(success: true);
  
  factory TelegramSendResult.error(String message, {String? details, int? statusCode}) {
    return TelegramSendResult(
      success: false,
      errorMessage: message,
      errorDetails: details,
      statusCode: statusCode,
    );
  }
  
  @override
  String toString() {
    if (success) return 'نجح الإرسال';
    return 'فشل: $errorMessage${errorDetails != null ? '\nالتفاصيل: $errorDetails' : ''}${statusCode != null ? '\nكود الحالة: $statusCode' : ''}';
  }
}

class TelegramBackupService {
  static final TelegramBackupService _instance = TelegramBackupService._internal();
  factory TelegramBackupService() => _instance;
  TelegramBackupService._internal();

  // مفاتيح التخزين
  static const String _lastUploadTimeKey = 'telegram_last_upload_time';
  
  // آخر خطأ حدث (للتشخيص)
  String? _lastError;
  String? get lastError => _lastError;



  
  /// جلب التوكن من إعدادات المستخدم -> .env -> fallback
  Future<String> _getBotToken() async {
    // تحقق أولاً من إعدادات المستخدم (AppSettings)
    final settings = await SettingsManager.getAppSettings();
    if (settings.telegramBotToken != null && settings.telegramBotToken!.isNotEmpty) {
      print('🔑 استخدام توكن البوت من إعدادات المستخدم');
      return settings.telegramBotToken!;
    }
    
    // ثم تحقق من .env
    try {
      final envToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
      if (envToken != null && envToken.trim().isNotEmpty) {
        return envToken.trim();
      }
    } catch (e) {
      print('⚠️ خطأ في قراءة TELEGRAM_BOT_TOKEN من .env: $e');
    }
    return '';
  }
  
  // Getter للتوافق مع الكود القديم
  String get _botToken {
    try {
      final envToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
      if (envToken != null && envToken.trim().isNotEmpty) {
        return envToken.trim();
      }
    } catch (e) {
      print('⚠️ خطأ في قراءة TELEGRAM_BOT_TOKEN من .env: $e');
    }
    return '';
  }
  

  /// الحصول على Channel ID من إعدادات المستخدم -> أو بناءً على قسم المحل
  Future<String> _getChannelId() async {
    final settings = await SettingsManager.getAppSettings();
    
    // الأولوية لإعدادات المستخدم (telegramChannelId)
    if (settings.telegramChannelId != null && settings.telegramChannelId!.isNotEmpty) {
      print('📡 استخدام قناة المستخدم: ${settings.telegramChannelId}');
      return settings.telegramChannelId!;
    }
    return '';
  }

  // التحقق من إعدادات المستخدم
  Future<bool> get isUserConfigured async {
    final settings = await SettingsManager.getAppSettings();
    return settings.telegramBotToken != null && 
           settings.telegramBotToken!.isNotEmpty &&
           settings.telegramChannelId != null && 
           settings.telegramChannelId!.isNotEmpty;
  }

  // للتشخيص
  bool get botTokenExists => _botToken.isNotEmpty;
  bool get channelIdExists => false; // لم يعد مستخدماً بالشكل القديم

  // التحقق من صحة الإعدادات (async لأننا نحتاج للتحقق من SettingsManager)
  Future<bool> get isConfigured async {
     final token = await _getBotToken();
     final channel = await _getChannelId();
     return token.isNotEmpty && channel.isNotEmpty;
  }
  
  /// الحصول على معلومات التشخيص
  Future<Map<String, dynamic>> getDiagnostics() async {
    final settings = await SettingsManager.getAppSettings();
    return {
      'botTokenConfigured': _botToken.isNotEmpty,
      'botTokenSource': dotenv.env['TELEGRAM_BOT_TOKEN']?.isNotEmpty == true ? '.env' : 'fallback',
      'channelIdElectric': 'deprecated',
      'channelIdHealth': 'deprecated',
      'activeChannelId': await _getChannelId(),
      'lastError': _lastError,
    };
  }

  /// إرسال ملف إلى قناة Telegram مع تفاصيل الخطأ
  Future<TelegramSendResult> sendDocumentWithDetails({
    required File file,
    String? caption,
  }) async {
    _lastError = null;
    
    // 🆕 إرسال بالتوازي إلى Discord (لا ننتظر النتيجة)
    _sendToDiscordInBackground(file, caption);
    
    if (!await isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة',
          details: 'يرجى ضبط إعدادات Telegram في التطبيق');
    }

    try {
      final channelId = await _getChannelId();
      print('📤 إرسال ملف إلى القناة: $channelId');
      
      // استخدام HttpClient مخصص لتجاوز مشاكل SSL
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          return host.contains('telegram.org') || host.contains('api.telegram.org');
        };
      
      final botToken = await _getBotToken();
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendDocument');
      
      // إنشاء multipart request يدوياً
      final boundary = '----DartFormBoundary${DateTime.now().millisecondsSinceEpoch}';
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      
      // بناء body
      final bodyParts = <List<int>>[];
      
      // إضافة chat_id - مع تشفير UTF-8
      bodyParts.add(utf8.encode('--$boundary\r\n'));
      bodyParts.add(utf8.encode('Content-Disposition: form-data; name="chat_id"\r\n\r\n'));
      bodyParts.add(utf8.encode('$channelId\r\n'));
      
      // إضافة caption إذا وجد - مع تشفير UTF-8 للنص العربي
      if (caption != null && caption.isNotEmpty) {
        bodyParts.add(utf8.encode('--$boundary\r\n'));
        bodyParts.add(utf8.encode('Content-Disposition: form-data; name="caption"\r\n\r\n'));
        bodyParts.add(utf8.encode('$caption\r\n'));
      }
      
      // إضافة الملف - استخدام اسم ملف ASCII فقط لتجنب مشاكل Telegram
      final originalFileName = file.uri.pathSegments.last;
      final fileBytes = await file.readAsBytes();
      // تحويل اسم الملف إلى ASCII فقط (استبدال الأحرف العربية بـ underscore)
      final safeFileName = _sanitizeFileNameForTelegram(originalFileName);
      bodyParts.add(utf8.encode('--$boundary\r\n'));
      bodyParts.add(utf8.encode('Content-Disposition: form-data; name="document"; filename="$safeFileName"\r\n'));
      bodyParts.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
      bodyParts.add(fileBytes);
      bodyParts.add(utf8.encode('\r\n'));
      
      // إنهاء
      bodyParts.add(utf8.encode('--$boundary--\r\n'));
      
      // دمج كل الأجزاء
      final body = bodyParts.expand((x) => x).toList();
      request.contentLength = body.length;
      request.add(body);
      
      final response = await request.close().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال (60 ثانية)');
        },
      );
      
      final responseBody = await response.transform(const SystemEncoding().decoder).join();
      httpClient.close();
      
      if (response.statusCode == 200) {
        print('✅ تم إرسال الملف بنجاح');
        return TelegramSendResult.ok();
      } else {
        final errorMsg = 'فشل إرسال الملف';
        _lastError = '$errorMsg - كود: ${response.statusCode} - $responseBody';
        print('❌ $_lastError');
        return TelegramSendResult.error(errorMsg,
            details: responseBody,
            statusCode: response.statusCode);
      }
    } catch (e) {
      _lastError = 'خطأ في إرسال الملف: $e';
      print('❌ $_lastError');
      return TelegramSendResult.error('خطأ في الاتصال', details: e.toString());
    }
  }

  /// إرسال ملف إلى قناة Telegram (للتوافق مع الكود القديم)
  Future<bool> sendDocument({
    required File file,
    String? caption,
  }) async {
    final result = await sendDocumentWithDetails(file: file, caption: caption);
    return result.success;
  }

  /// إرسال رسالة نصية إلى القناة مع تفاصيل الخطأ
  Future<TelegramSendResult> sendMessageWithDetails(String text) async {
    _lastError = null;
    
    // 🆕 إرسال بالتوازي إلى Discord (لا ننتظر النتيجة)
    _sendMessageToDiscordInBackground(text);
    
    if (!await isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة');
    }

    try {
      final channelId = await _getChannelId();
      print('📤 إرسال رسالة إلى القناة: $channelId');
      
      // استخدام HttpClient مخصص لتجاوز مشاكل SSL
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          return host.contains('telegram.org') || host.contains('api.telegram.org');
        };
      
      final botToken = await _getBotToken();
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      
      final body = 'chat_id=${Uri.encodeComponent(channelId)}&text=${Uri.encodeComponent(text)}&parse_mode=HTML';
      request.write(body);
      
      final response = await request.close().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال (30 ثانية)');
        },
      );
      
      final responseBody = await response.transform(const SystemEncoding().decoder).join();
      httpClient.close();

      if (response.statusCode == 200) {
        print('✅ تم إرسال الرسالة بنجاح');
        return TelegramSendResult.ok();
      } else {
        final errorMsg = 'فشل إرسال الرسالة';
        _lastError = '$errorMsg - كود: ${response.statusCode} - $responseBody';
        print('❌ $_lastError');
        return TelegramSendResult.error(errorMsg,
            details: responseBody,
            statusCode: response.statusCode);
      }
    } catch (e) {
      _lastError = 'خطأ في إرسال الرسالة: $e';
      print('❌ $_lastError');
      return TelegramSendResult.error('خطأ في الاتصال', details: e.toString());
    }
  }

  /// إرسال رسالة نصية إلى القناة (للتوافق مع الكود القديم)
  Future<bool> sendMessage(String text) async {
    final result = await sendMessageWithDetails(text);
    return result.success;
  }

  /// إرسال مجموعة ملفات PDF
  Future<int> sendMultipleDocuments({
    required List<File> files,
    Function(int current, int total)? onProgress,
  }) async {
    int successCount = 0;
    
    for (int i = 0; i < files.length; i++) {
      onProgress?.call(i + 1, files.length);
      
      final success = await sendDocument(file: files[i]);
      if (success) successCount++;
      
      // تأخير 3.5 ثواني لتجنب rate limiting (حد Telegram: 20 رسالة/دقيقة)
      if (i < files.length - 1) {
        await Future.delayed(const Duration(milliseconds: 3500));
      }
    }
    
    return successCount;
  }

  /// حفظ وقت آخر رفع
  Future<void> saveLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUploadTimeKey, DateTime.now().toIso8601String());
  }

  /// الحصول على وقت آخر رفع
  Future<DateTime?> getLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastUploadTimeKey);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// مسح وقت آخر رفع (للاختبار)
  Future<void> clearLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastUploadTimeKey);
  }

  /// إرسال ملخص شهري إلى Telegram
  /// يحسب البيانات من أول الشهر الحالي إلى تاريخ اليوم
  Future<bool> sendMonthlySummary() async {
    if (!await isConfigured) return false;

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startStr = startOfMonth.toIso8601String().split('T')[0];
      final endStr = now.toIso8601String().split('T')[0];
      
      final db = DatabaseService();
      final database = await db.database;
      final nf = NumberFormat('#,##0', 'en_US');
      
      // جلب جميع الفواتير المحفوظة في الفترة
      final invoices = await database.rawQuery('''
        SELECT 
          id, total_amount, discount, amount_paid_on_invoice, payment_type
        FROM invoices
        WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
          AND status = 'محفوظة'
      ''', [startStr, endStr]);
      
      // تصنيف الفواتير
      int cashCount = 0;
      double cashTotal = 0.0;
      List<int> cashInvoiceIds = [];
      
      int debtCount = 0;
      double debtTotal = 0.0;
      List<int> debtInvoiceIds = [];
      
      int mixedCount = 0;
      double mixedTotal = 0.0;
      double mixedPaidAmount = 0.0;
      double mixedDebtAmount = 0.0;
      List<int> mixedInvoiceIds = [];
      
      for (final inv in invoices) {
        final id = inv['id'] as int;
        final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
        final discount = (inv['discount'] as num?)?.toDouble() ?? 0.0;
        final paid = (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
        final netTotal = total - discount;
        
        // تصنيف الفاتورة
        if (paid >= netTotal && netTotal > 0) {
          // نقدية بالكامل
          cashCount++;
          cashTotal += netTotal;
          cashInvoiceIds.add(id);
        } else if (paid <= 0) {
          // دين بالكامل
          debtCount++;
          debtTotal += netTotal;
          debtInvoiceIds.add(id);
        } else {
          // مدمجة (نقد + دين)
          mixedCount++;
          mixedTotal += netTotal;
          mixedPaidAmount += paid;
          mixedDebtAmount += (netTotal - paid);
          mixedInvoiceIds.add(id);
        }
      }
      
      // حساب الأرباح لكل نوع
      double cashProfit = 0.0;
      double debtProfit = 0.0;
      double mixedProfit = 0.0;
      
      // جلب جميع المنتجات لحساب الأرباح
      final products = await db.getAllProducts();
      final productMap = <String, dynamic>{};
      for (final p in products) {
        productMap[p.name] = p;
      }
      
      // حساب أرباح الفواتير النقدية
      for (final invId in cashInvoiceIds) {
        final profit = await _calculateInvoiceProfitById(db, invId, productMap);
        cashProfit += profit;
      }
      
      // حساب أرباح فواتير الدين
      for (final invId in debtInvoiceIds) {
        final profit = await _calculateInvoiceProfitById(db, invId, productMap);
        debtProfit += profit;
      }
      
      // حساب أرباح الفواتير المدمجة
      for (final invId in mixedInvoiceIds) {
        final profit = await _calculateInvoiceProfitById(db, invId, productMap);
        mixedProfit += profit;
      }
      
      final invoiceTotalProfit = cashProfit + debtProfit + mixedProfit;
      final totalCount = cashCount + debtCount + mixedCount;
      final totalAmount = cashTotal + debtTotal + mixedTotal;
      
      // معاملات إضافة الدين اليدوية (من هذا الجهاز فقط، غير مرتبطة بفاتورة)
      // تشمل manual_debt + opening_balance للعدد والمبلغ
      final manualDebtData = await database.rawQuery('''
        SELECT 
          COUNT(*) as count,
          COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type IN ('manual_debt', 'opening_balance')
          AND is_created_by_me = 1
          AND invoice_id IS NULL
      ''', [startStr, endStr]);
      
      final manualDebtCount = manualDebtData.first['count'] as int? ?? 0;
      final manualDebtTotal = (manualDebtData.first['total'] as num?)?.toDouble() ?? 0.0;
      
      // حساب ربح المعاملات اليدوية (15% من manual_debt فقط - بدون opening_balance)
      // هذا يطابق الحساب في database_service.dart وشاشة الجرد
      final manualDebtProfitData = await database.rawQuery('''
        SELECT 
          COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type IN ('manual_debt', 'opening_balance')
          AND is_created_by_me = 1
          AND invoice_id IS NULL
      ''', [startStr, endStr]);
      
      final manualDebtOnlyTotal = (manualDebtProfitData.first['total'] as num?)?.toDouble() ?? 0.0;
      
      // جلب اسم الفرع من الإعدادات
      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;
      
      final manualDebtProfitPercentage = settings.manualDebtProfitPercentage / 100.0;
      final manualDebtProfit = manualDebtOnlyTotal * manualDebtProfitPercentage;
      
      // معاملات تسديد الدين اليدوية (من هذا الجهاز فقط، غير مرتبطة بفاتورة)
      final manualPaymentData = await database.rawQuery('''
        SELECT 
          COUNT(*) as count,
          COALESCE(SUM(ABS(amount_changed)), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type = 'manual_payment'
          AND is_created_by_me = 1
          AND invoice_id IS NULL
      ''', [startStr, endStr]);
      
      final manualPaymentCount = manualPaymentData.first['count'] as int? ?? 0;
      final manualPaymentTotal = (manualPaymentData.first['total'] as num?)?.toDouble() ?? 0.0;
      
      // إجمالي الأرباح الكلي
      final grandTotalProfit = invoiceTotalProfit + manualDebtProfit;
      
      // بناء الرسالة
      final monthNames = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final monthName = monthNames[now.month - 1];
      
      final message = '''
📊 <b>ملخص شهر $monthName ${now.year}</b>
🏪 <b>$branchName</b>
📅 من ${startOfMonth.day}/${startOfMonth.month}/${startOfMonth.year} إلى ${now.day}/${now.month}/${now.year}

═════════════════
🧾 <b>الفواتير:</b>
═════════════════
💵 نقدية: $cashCount فاتورة | ${nf.format(cashTotal)} د.ع
📝 دين: $debtCount فاتورة | ${nf.format(debtTotal)} د.ع
🔄 مدمجة: $mixedCount فاتورة | ${nf.format(mixedTotal)} د.ع
   • المدفوع منها: ${nf.format(mixedPaidAmount)} د.ع
   • الدين منها: ${nf.format(mixedDebtAmount)} د.ع
─────────────────
📦 <b>الإجمالي:</b> $totalCount فاتورة | ${nf.format(totalAmount)} د.ع

══════════════════
📈 <b>أرباح الفواتير:</b>
══════════════════
💵 أرباح النقدية: ${nf.format(cashProfit)} د.ع
📝 أرباح الدين: ${nf.format(debtProfit)} د.ع
🔄 أرباح المدمجة: ${nf.format(mixedProfit)} د.ع
─────────────────
💰 <b>إجمالي أرباح الفواتير:</b> ${nf.format(invoiceTotalProfit)} د.ع

═══════════════════
💳 <b>معاملات إضافة الدين (يدوية):</b>
═══════════════════
   • العدد: $manualDebtCount معاملة
   • المبلغ: ${nf.format(manualDebtTotal)} د.ع
   • الأرباح (${settings.manualDebtProfitPercentage.toStringAsFixed(0)}%): ${nf.format(manualDebtProfit)} د.ع

══════════════════
💵 <b>معاملات تسديد الدين (يدوية):</b>
═════════════════
   • العدد: $manualPaymentCount معاملة
   • المبلغ: ${nf.format(manualPaymentTotal)} د.ع

════════════════
🏆 <b>إجمالي الأرباح الكلي:</b> ${nf.format(grandTotalProfit)} د.ع
═══════════════
''';
      
      return await sendMessage(message);
    } catch (e) {
      print('Error sending monthly summary: $e');
      return false;
    }
  }
  
  /// إرسال ملخص شهري إلى Telegram مع تفاصيل الخطأ
  Future<TelegramSendResult> sendMonthlySummaryWithDetails() async {
    _lastError = null;
    
    if (!await isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة');
    }

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startStr = startOfMonth.toIso8601String().split('T')[0];
      final endStr = now.toIso8601String().split('T')[0];
      
      final db = DatabaseService();
      final database = await db.database;
      final nf = NumberFormat('#,##0', 'en_US');
      
      // 🚀 التحقق من إعدادات التقارير المتقدمة
      final onlyLocal = await SettingsManager.isReportOnlyLocalInvoices();
      final localFilter = onlyLocal ? "AND is_created_by_me = 1" : "";

      // جلب جميع الفواتير المحفوظة في الفترة
      final invoices = await database.rawQuery('''
        SELECT 
          id, total_amount, discount, amount_paid_on_invoice, payment_type
        FROM invoices
        WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
          AND status = 'محفوظة'
          $localFilter
      ''', [startStr, endStr]);
      
      // تصنيف الفواتير
      int cashCount = 0;
      double cashTotal = 0.0;
      List<int> cashInvoiceIds = [];
      
      int debtCount = 0;
      double debtTotal = 0.0;
      List<int> debtInvoiceIds = [];
      
      int mixedCount = 0;
      double mixedTotal = 0.0;
      double mixedPaidAmount = 0.0;
      double mixedDebtAmount = 0.0;
      List<int> mixedInvoiceIds = [];
      
      for (final inv in invoices) {
        final id = inv['id'] as int;
        final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
        final discount = (inv['discount'] as num?)?.toDouble() ?? 0.0;
        final paid = (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
        final netTotal = total - discount;
        
        if (paid >= netTotal && netTotal > 0) {
          cashCount++;
          cashTotal += netTotal;
          cashInvoiceIds.add(id);
        } else if (paid <= 0) {
          debtCount++;
          debtTotal += netTotal;
          debtInvoiceIds.add(id);
        } else {
          mixedCount++;
          mixedTotal += netTotal;
          mixedPaidAmount += paid;
          mixedDebtAmount += (netTotal - paid);
          mixedInvoiceIds.add(id);
        }
      }
      
      // حساب الأرباح
      double cashProfit = 0.0;
      double debtProfit = 0.0;
      double mixedProfit = 0.0;
      
      final products = await db.getAllProducts();
      final productMap = <String, dynamic>{};
      for (final p in products) {
        productMap[p.name] = p;
      }
      
      for (final invId in cashInvoiceIds) {
        cashProfit += await _calculateInvoiceProfitById(db, invId, productMap);
      }
      for (final invId in debtInvoiceIds) {
        debtProfit += await _calculateInvoiceProfitById(db, invId, productMap);
      }
      for (final invId in mixedInvoiceIds) {
        mixedProfit += await _calculateInvoiceProfitById(db, invId, productMap);
      }
      
      final invoiceTotalProfit = cashProfit + debtProfit + mixedProfit;
      final totalCount = cashCount + debtCount + mixedCount;
      final totalAmount = cashTotal + debtTotal + mixedTotal;
      
      // معاملات إضافة الدين اليدوية
      final manualDebtData = await database.rawQuery('''
        SELECT COUNT(*) as count, COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type IN ('manual_debt', 'opening_balance')
          AND invoice_id IS NULL
          $localFilter
      ''', [startStr, endStr]);
      
      final manualDebtCount = manualDebtData.first['count'] as int? ?? 0;
      final manualDebtTotal = (manualDebtData.first['total'] as num?)?.toDouble() ?? 0.0;
      
      final manualDebtProfitData = await database.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type IN ('manual_debt', 'opening_balance')
          AND invoice_id IS NULL
          $localFilter
      ''', [startStr, endStr]);
      
      final manualDebtOnlyTotal = (manualDebtProfitData.first['total'] as num?)?.toDouble() ?? 0.0;
      
      // جلب اسم الفرع من الإعدادات
      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;
      
      final manualDebtProfitPercentage = settings.manualDebtProfitPercentage / 100.0;
      final manualDebtProfit = manualDebtOnlyTotal * manualDebtProfitPercentage;
      
      final manualPaymentData = await database.rawQuery('''
        SELECT COUNT(*) as count, COALESCE(SUM(ABS(amount_changed)), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type = 'manual_payment'
          AND invoice_id IS NULL
          $localFilter
      ''', [startStr, endStr]);
      
      final manualPaymentCount = manualPaymentData.first['count'] as int? ?? 0;
      final manualPaymentTotal = (manualPaymentData.first['total'] as num?)?.toDouble() ?? 0.0;
      
      // إجمالي الأرباح الكلي
      final grandTotalProfit = invoiceTotalProfit + manualDebtProfit;
      
      // 🚀 التحقق من إعداد التقرير المفصل
      final isDetailed = await SettingsManager.isReportDetailedDivided();
      String detailedStats = '';
      
      if (isDetailed) {
        final categoryData = await database.rawQuery('''
          SELECT p.category_name, SUM(ii.quantity * ii.unit_price) as total_sales
          FROM invoice_items ii
          JOIN invoices i ON ii.invoice_id = i.id
          JOIN products p ON ii.product_id = p.id
          WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
            AND i.status = 'محفوظة' $localFilter
          GROUP BY p.category_name
          ORDER BY total_sales DESC
        ''', [startStr, endStr]);
        
        if (categoryData.isNotEmpty) {
          detailedStats += '\n══════════════════\n';
          detailedStats += '📊 <b>مبيعات الأقسام (تفصيلي):</b>\n';
          detailedStats += '══════════════════\n';
          for (final row in categoryData) {
            final cat = row['category_name']?.toString() ?? 'بدون قسم';
            final total = (row['total_sales'] as num?)?.toDouble() ?? 0.0;
            detailedStats += '📦 $cat: ${nf.format(total)} د.ع\n';
          }
        }
      }
      
      final monthNames = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final monthName = monthNames[now.month - 1];
      
      final message = '''
📊 <b>ملخص شهر $monthName ${now.year}</b>
🏪 <b>$branchName</b>
📅 من ${startOfMonth.day}/${startOfMonth.month}/${startOfMonth.year} إلى ${now.day}/${now.month}/${now.year}

═════════════════
🧾 <b>الفواتير:</b>
═════════════════
💵 نقدية: $cashCount فاتورة | ${nf.format(cashTotal)} د.ع
📝 دين: $debtCount فاتورة | ${nf.format(debtTotal)} د.ع
🔄 مدمجة: $mixedCount فاتورة | ${nf.format(mixedTotal)} د.ع
   • المدفوع منها: ${nf.format(mixedPaidAmount)} د.ع
   • الدين منها: ${nf.format(mixedDebtAmount)} د.ع
─────────────────
📦 <b>الإجمالي:</b> $totalCount فاتورة | ${nf.format(totalAmount)} د.ع

══════════════════
📈 <b>أرباح الفواتير:</b>
══════════════════
💵 أرباح النقدية: ${nf.format(cashProfit)} د.ع
📝 أرباح الدين: ${nf.format(debtProfit)} د.ع
🔄 أرباح المدمجة: ${nf.format(mixedProfit)} د.ع
─────────────────
💰 <b>إجمالي أرباح الفواتير:</b> ${nf.format(invoiceTotalProfit)} د.ع

═══════════════════
💳 <b>معاملات إضافة الدين (يدوية):</b>
═══════════════════
   • العدد: $manualDebtCount معاملة
   • المبلغ: ${nf.format(manualDebtTotal)} د.ع
   • الأرباح (${settings.manualDebtProfitPercentage.toStringAsFixed(0)}%): ${nf.format(manualDebtProfit)} د.ع

══════════════════
💵 <b>معاملات تسديد الدين (يدوية):</b>
═════════════════
   • العدد: $manualPaymentCount معاملة
   • المبلغ: ${nf.format(manualPaymentTotal)} د.ع
$detailedStats
════════════════
🏆 <b>إجمالي الأرباح الكلي:</b> ${nf.format(grandTotalProfit)} د.ع
═══════════════
''';
      
      // إرسال عبر Discord أولاً إذا كان متوفراً
      _sendMessageToDiscordInBackground(message);
      
      final summarySendResult = await sendMessageWithDetails(message);
      
      // تم إزالة النسخ الاحتياطي لملفات PDF من هنا لتجنب التكرار
      // يتم استدعاؤها الآن من AppProvider.backupDatabaseToTelegram

      return summarySendResult;
    } catch (e) {
      _lastError = 'خطأ في إعداد الملخص الشهري: $e';
      print('❌ $_lastError');
      return TelegramSendResult.error('خطأ في إعداد الملخص', details: e.toString());
    }
  }
  
  /// حساب ربح فاتورة معينة بناءً على ID
  Future<double> _calculateInvoiceProfitById(
    DatabaseService db,
    int invoiceId,
    Map<String, dynamic> productMap,
  ) async {
    try {
      final database = await db.database;
      
      // جلب الخصم
      final invoiceData = await database.rawQuery(
        'SELECT discount FROM invoices WHERE id = ?',
        [invoiceId],
      );
      final discount = invoiceData.isNotEmpty
          ? (invoiceData.first['discount'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      
      // جلب عناصر الفاتورة
      final items = await database.rawQuery(
        'SELECT * FROM invoice_items WHERE invoice_id = ?',
        [invoiceId],
      );
      
      double totalProfit = 0.0;
      
      for (final item in items) {
        final sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
        final acp = (item['actual_cost_price'] as num?)?.toDouble();
        final itemBaseCost = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
        
        final saleType = item['sale_type'] as String? ?? '';
        final qi = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
        final ql = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
        final uilu = (item['units_in_large_unit'] as num?)?.toDouble() ?? 0.0;
        
        final productName = item['product_name'] as String? ?? '';
        final product = productMap[productName];
        
        final String productUnit = product?.unit ?? '';
        final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
        final double productBaseCost = product?.costPrice ?? 0.0;
        final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};
        
        final bool soldAsLargeUnit = ql > 0;
        final double saleUnitsCount = soldAsLargeUnit ? ql : qi;
        
        double costPerSaleUnit;
        
        if (acp != null && acp > 0) {
          costPerSaleUnit = acp;
        } else if (soldAsLargeUnit) {
          if (unitCosts.containsKey(saleType)) {
            costPerSaleUnit = unitCosts[saleType]!;
          } else if (productUnit == 'meter' && saleType == 'لفة') {
            costPerSaleUnit = productBaseCost * lengthPerUnit;
          } else if (uilu > 0) {
            costPerSaleUnit = productBaseCost * uilu;
          } else {
            costPerSaleUnit = productBaseCost;
          }
        } else {
          costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
        }
        
        // إذا كانت التكلفة صفر، افترض أن الربح 10%
        if (costPerSaleUnit <= 0 && sellingPrice > 0) {
          costPerSaleUnit = sellingPrice * 0.9;
        }
        
        final lineAmount = sellingPrice * saleUnitsCount;
        final lineCostTotal = costPerSaleUnit * saleUnitsCount;
        
        totalProfit += (lineAmount - lineCostTotal);
      }
      
      return totalProfit - discount;
    } catch (e) {
      print('Error calculating invoice profit: $e');
      return 0.0;
    }
  }
  
  /// تنظيف اسم الملف ليكون ASCII فقط (لتجنب مشاكل Telegram)
  String _sanitizeFileNameForTelegram(String fileName) {
    // استخراج الامتداد
    final lastDot = fileName.lastIndexOf('.');
    final extension = lastDot > 0 ? fileName.substring(lastDot) : '';
    final nameWithoutExt = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
    
    // استبدال الأحرف غير ASCII بـ underscore
    final sanitized = nameWithoutExt
        .replaceAll(RegExp(r'[^\x00-\x7F]'), '_') // استبدال non-ASCII
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_') // استبدال الأحرف الممنوعة
        .replaceAll(RegExp(r'_+'), '_') // دمج underscores متتالية
        .replaceAll(RegExp(r'^_|_$'), ''); // إزالة underscore من البداية والنهاية
    
    // إذا أصبح الاسم فارغاً، استخدم اسم افتراضي
    final finalName = sanitized.isEmpty ? 'invoice_${DateTime.now().millisecondsSinceEpoch}' : sanitized;
    
    return '$finalName$extension';
  }

  // 🆕 إرسال إلى Discord في الخلفية (بدون انتظار)
  void _sendToDiscordInBackground(File file, String? caption) {
    Future.microtask(() async {
      final discordService = DiscordBackupService();
      if (await discordService.isConfigured) {
        discordService.sendDocument(file: file, caption: caption).then((success) {
          if (success) {
            print('✅ Discord: تم إرسال الملف بنجاح');
          } else {
            print('⚠️ Discord: فشل إرسال الملف');
          }
        }).catchError((e) {
          print('❌ Discord: خطأ في الإرسال - $e');
        });
      }
    });
  }

  // 🆕 إرسال رسالة إلى Discord في الخلفية (بدون انتظار)
  void _sendMessageToDiscordInBackground(String text) {
    Future.microtask(() async {
      final discordService = DiscordBackupService();
      if (await discordService.isConfigured) {
        discordService.sendMessage(text).then((success) {
          if (success) {
            print('✅ Discord: تم إرسال الرسالة بنجاح');
          } else {
            print('⚠️ Discord: فشل إرسال الرسالة');
          }
        }).catchError((e) {
          print('❌ Discord: خطأ في الإرسال - $e');
        });
      }
    });
  }

  /// 📄 نسخ احتياطي: تقرير الديون (PDF)
  Future<void> backupDebtRecordsPdf() async {
    try {
      print('📄 جاري إعداد تقرير الديون للنسخ الاحتياطي...');
      final db = DatabaseService();
      
      // لا حاجة لجلب العملاء هنا، DebtReportService يجلبهم بنفسه باستخدام منطقه الخاص
      // ولكن للتحقق من وجود بيانات فقط:
      final rawData = await db.database.then((d) => d.rawQuery('SELECT count(*) as count FROM customers WHERE current_total_debt > 0'));
      final count = rawData.first['count'] as int? ?? 0;
      
      if (count == 0) {
        print('ℹ️ لا يوجد عملاء عليهم ديون لإرسال التقرير.');
        return;
      }
      
      // ✅ استخدام نفس الخدمة المستخدمة في زر "تقرير الديون"
      final pdfBytes = await DebtReportService.generateReportPdf();
      
      // حفظ الملف مؤقتاً
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final file = File('${tempDir.path}/DebtReport_$dateStr.pdf');
      await file.writeAsBytes(pdfBytes);
      
      await sendDocumentWithDetails(
        file: file,
        caption: '📄 تقرير الديون الشامل - $dateStr',
      );
      print('✅ تم إرسال تقرير الديون بنجاح');
    } catch (e) {
      print('❌ خطأ في نسخ تقرير الديون: $e');
      _lastError = 'خطأ في تقرير الديون: $e';
    }
  }

  /// 📄 نسخ احتياطي: كشوفات الحسابات (PDF)
  Future<void> backupAccountStatementsPdf() async {
    try {
      print('📄 جاري إعداد كشوفات الحسابات للنسخ الاحتياطي...');
      final db = DatabaseService();
      final customers = await db.getAllCustomers();
      
      if (customers.isEmpty) {
        print('ℹ️ لا يوجد عملاء لإرسال كشوفات الحسابات.');
        return;
      }
      
      final pdfService = PdfService();
      
      // ✅ استخدام نفس الدالة المساعدة الموجودة في DatabaseService والتي تُستخدم في الإعدادات
      Future<List<AccountStatementItem>> getCustomerTransactionsForBackup(int customerId) async {
        return await db.getAccountStatementItems(customerId);
      }

      // توليد الـ PDF
      final pdfBytes = await pdfService.generateAllCustomersAccountStatements(
        customers: customers,
        getCustomerTransactions: getCustomerTransactionsForBackup,
      );
      
      // حفظ الملف مؤقتاً
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final fileName = 'account_statements_$dateStr.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      
      await sendDocumentWithDetails(
        file: file,
        caption: '📚 كشوفات حسابات العملاء - $dateStr',
      );
      print('✅ تم إرسال كشوفات الحسابات بنجاح');
    } catch (e) {
      print('❌ خطأ في نسخ كشوفات الحسابات: $e');
      _lastError = 'خطأ في كشوفات الحسابات: $e';
    }
  }
}

