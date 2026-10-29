// خدمة إرسال النسخ الاحتياطية إلى Telegram
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'settings_manager.dart';
import 'database_service.dart';
import '../models/account_statement_item.dart';
import 'pdf_service.dart';
import 'package:path_provider/path_provider.dart';
import 'debt_report_service.dart'; // import DebtReportService
import 'discord_backup_service.dart'; // 🆕 Discord Integration
import 'reports_service.dart';

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
      debugPrint('🔑 استخدام توكن البوت من إعدادات المستخدم');
      return settings.telegramBotToken!;
    }
    
    // ثم تحقق من .env
    try {
      final envToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
      if (envToken != null && envToken.trim().isNotEmpty) {
        return envToken.trim();
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في قراءة TELEGRAM_BOT_TOKEN من .env: $e');
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
      debugPrint('⚠️ خطأ في قراءة TELEGRAM_BOT_TOKEN من .env: $e');
    }
    return '';
  }
  

  /// الحصول على Channel ID من إعدادات المستخدم -> أو بناءً على قسم المحل
  Future<String> _getChannelId() async {
    final settings = await SettingsManager.getAppSettings();
    
    // الأولوية لإعدادات المستخدم (telegramChannelId)
    if (settings.telegramChannelId != null && settings.telegramChannelId!.isNotEmpty) {
      debugPrint('📡 استخدام قناة المستخدم: ${settings.telegramChannelId}');
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
      debugPrint('📤 إرسال ملف إلى القناة: $channelId');
      
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
        debugPrint('✅ تم إرسال الملف بنجاح');
        return TelegramSendResult.ok();
      } else {
        const errorMsg = 'فشل إرسال الملف';
        _lastError = '$errorMsg - كود: ${response.statusCode} - $responseBody';
        debugPrint('❌ $_lastError');
        return TelegramSendResult.error(errorMsg,
            details: responseBody,
            statusCode: response.statusCode);
      }
    } catch (e) {
      _lastError = 'خطأ في إرسال الملف: $e';
      debugPrint('❌ $_lastError');
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
      debugPrint('📤 إرسال رسالة إلى القناة: $channelId');
      
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
        debugPrint('✅ تم إرسال الرسالة بنجاح');
        return TelegramSendResult.ok();
      } else {
        const errorMsg = 'فشل إرسال الرسالة';
        _lastError = '$errorMsg - كود: ${response.statusCode} - $responseBody';
        debugPrint('❌ $_lastError');
        return TelegramSendResult.error(errorMsg,
            details: responseBody,
            statusCode: response.statusCode);
      }
    } catch (e) {
      _lastError = 'خطأ في إرسال الرسالة: $e';
      debugPrint('❌ $_lastError');
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
    final r = await sendMonthlySummaryWithDetails();
    return r.success;
  }

  /// إرسال ملخص شهري إلى Telegram مع تفاصيل الخطأ
  /// ملخص الشهر إلى تيليجرام — بالأرقام نفسها التي تعرضها «التقارير ← الشهر»
  /// (المحرك نفسه ReportsService). كان يحسب بطريقته الخاصة فيختلف عنها:
  /// يطرح الخصم مرتين (total_amount بعد الخصم أصلاً)، ويتجاهل المرتجعات،
  /// ويحسب الربح بكلفة المادة اليوم لا بكلفتها يوم البيع.
  Future<TelegramSendResult> sendMonthlySummaryWithDetails() async {
    _lastError = null;

    if (!await isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة');
    }

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);
      final nf = NumberFormat('#,##0', 'en_US');
      double n(Object? v) => (v as num?)?.toDouble() ?? 0.0;

      // «فواتير هذا الجهاز فقط» من إعدادات التقارير ⇒ مصدر «هذا الجهاز»
      final onlyLocal = await SettingsManager.isReportOnlyLocalInvoices();
      final svc = ReportsService()..reportSourceFilter = onlyLocal ? ReportSource.thisDevice : ReportSource.all;
      final s = await svc.getPeriodSummary(startDate: startOfMonth, endDate: endOfMonth);

      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;

      final invoiceCount = n(s['invoiceCount']).toInt();
      final sales = n(s['totalSales']);
      final cash = n(s['cashSales']);
      final credit = n(s['creditSales']);
      final down = (n(s['paidAmount']) - cash).clamp(0, double.infinity).toDouble();
      final returns = n(s['totalReturns']);
      final netSales = n(s['netSales']);
      final invoiceProfit = n(s['netProfit']);
      final manualDebtCount = n(s['manualDebtCount']).toInt();
      final manualDebt = n(s['totalManualDebt']);
      final manualDebtProfit = n(s['manualDebtProfit']);
      final manualPaymentCount = n(s['manualPaymentCount']).toInt();
      final manualPayment = n(s['totalManualPayment']);
      final grandProfit = invoiceProfit + manualDebtProfit;

      String detailedStats = '';
      if (await SettingsManager.isReportDetailedDivided()) {
        try {
          final facts = await svc.loadFacts(from: startOfMonth, to: endOfMonth);
          final all = await svc.getCategories();
          final cats = facts.byCategory({for (final c in all) c.id: c.name},
              parents: {for (final c in all) c.id: c.parentId}, rollupToRoot: true)
            ..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
          if (cats.isNotEmpty) {
            detailedStats += '\n══════════════════\n';
            detailedStats += '📊 <b>مبيعات الأقسام (تفصيلي):</b>\n';
            detailedStats += '══════════════════\n';
            for (final c in cats) {
              detailedStats += '📦 ${c.name}: ${nf.format(c.netRevenue)} د.ع\n';
            }
          }
        } catch (e) {
          debugPrint('⚠️ مبيعات الأقسام في ملخص الشهر: $e');
        }
      }

      const monthNames = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final monthName = monthNames[now.month - 1];

      final message = '''
📊 <b>ملخص شهر $monthName ${now.year}</b>
🏪 <b>$branchName</b>
📅 من ${startOfMonth.day}/${startOfMonth.month}/${startOfMonth.year} إلى ${now.day}/${now.month}/${now.year}
${onlyLocal ? '🖥️ فواتير هذا الجهاز فقط\n' : ''}
═════════════════
🧾 <b>الفواتير:</b>
═════════════════
💵 نقدية: ${nf.format(cash)} د.ع
📝 آجلة: ${nf.format(credit)} د.ع
   • المدفوع منها عند البيع: ${nf.format(down)} د.ع
↩️ المرتجعات: ${nf.format(returns)} د.ع
─────────────────
📦 <b>المبيعات:</b> $invoiceCount فاتورة | ${nf.format(sales)} د.ع
✅ <b>صافي المبيعات:</b> ${nf.format(netSales)} د.ع

══════════════════
📈 <b>ربح الفواتير:</b> ${nf.format(invoiceProfit)} د.ع
══════════════════

═══════════════════
💳 <b>معاملات إضافة الدين (يدوية):</b>
═══════════════════
   • العدد: $manualDebtCount معاملة
   • المبلغ: ${nf.format(manualDebt)} د.ع
   • الأرباح (${settings.manualDebtProfitPercentage.toStringAsFixed(0)}%): ${nf.format(manualDebtProfit)} د.ع

══════════════════
💵 <b>معاملات تسديد الدين (يدوية):</b>
═════════════════
   • العدد: $manualPaymentCount معاملة
   • المبلغ: ${nf.format(manualPayment)} د.ع
$detailedStats
════════════════
🏆 <b>إجمالي الأرباح الكلي:</b> ${nf.format(grandProfit)} د.ع
═══════════════
''';

      // إرسال عبر Discord أولاً إذا كان متوفراً
      _sendMessageToDiscordInBackground(message);
      return await sendMessageWithDetails(message);
    } catch (e) {
      _lastError = 'خطأ في إعداد الملخص الشهري: $e';
      debugPrint('❌ $_lastError');
      return TelegramSendResult.error('خطأ في إعداد الملخص', details: e.toString());
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
  /// ☁️ يُطفأ من زر «رفع البيانات» إذا أُوقف ديسكورد في الإعدادات
  static bool mirrorToDiscord = true;

  void _sendToDiscordInBackground(File file, String? caption) {
    if (!mirrorToDiscord) return;
    Future.microtask(() async {
      final discordService = DiscordBackupService();
      if (await discordService.isConfigured) {
        discordService.sendDocument(file: file, caption: caption).then((success) {
          if (success) {
            debugPrint('✅ Discord: تم إرسال الملف بنجاح');
          } else {
            debugPrint('⚠️ Discord: فشل إرسال الملف');
          }
        }).catchError((e) {
          debugPrint('❌ Discord: خطأ في الإرسال - $e');
        });
      }
    });
  }

  // 🆕 إرسال رسالة إلى Discord في الخلفية (بدون انتظار)
  void _sendMessageToDiscordInBackground(String text) {
    if (!mirrorToDiscord) return;
    Future.microtask(() async {
      final discordService = DiscordBackupService();
      if (await discordService.isConfigured) {
        discordService.sendMessage(text).then((success) {
          if (success) {
            debugPrint('✅ Discord: تم إرسال الرسالة بنجاح');
          } else {
            debugPrint('⚠️ Discord: فشل إرسال الرسالة');
          }
        }).catchError((e) {
          debugPrint('❌ Discord: خطأ في الإرسال - $e');
        });
      }
    });
  }

  /// 📄 نسخ احتياطي: تقرير الديون (PDF)
  /// يعيد null إن أُرسل (أو لا ديون فلا تقرير)، وإلا نص المشكلة.
  Future<String?> backupDebtRecordsPdf() async {
    try {
      debugPrint('📄 جاري إعداد تقرير الديون للنسخ الاحتياطي...');
      final db = DatabaseService();
      
      // لا حاجة لجلب العملاء هنا، DebtReportService يجلبهم بنفسه باستخدام منطقه الخاص
      // ولكن للتحقق من وجود بيانات فقط:
      final rawData = await db.database.then((d) => d.rawQuery('SELECT count(*) as count FROM customers WHERE current_total_debt > 0'));
      final count = rawData.first['count'] as int? ?? 0;
      
      if (count == 0) {
        debugPrint('ℹ️ لا يوجد عملاء عليهم ديون لإرسال التقرير.');
        return null;
      }
      
      // ✅ استخدام نفس الخدمة المستخدمة في زر "تقرير الديون"
      final pdfBytes = await DebtReportService.generateReportPdf();
      
      // حفظ الملف مؤقتاً
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final file = File('${tempDir.path}/DebtReport_$dateStr.pdf');
      await file.writeAsBytes(pdfBytes);
      
      final sent = await sendDocumentWithDetails(
        file: file,
        caption: '📄 تقرير الديون الشامل - $dateStr',
      );
      if (!sent.success) {
        return 'تقرير الديون (PDF) لم يُرسل: ${sent.errorMessage ?? ''}'
            '${sent.statusCode != null ? ' (كود ${sent.statusCode})' : ''}';
      }
      debugPrint('✅ تم إرسال تقرير الديون بنجاح');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في نسخ تقرير الديون: $e');
      _lastError = 'خطأ في تقرير الديون: $e';
      return 'تقرير الديون (PDF) لم يُرسل: $e';
    }
  }

  /// 📄 نسخ احتياطي: كشوفات الحسابات (PDF)
  /// يعيد null إن أُرسل (أو لا عملاء)، وإلا نص المشكلة.
  Future<String?> backupAccountStatementsPdf() async {
    try {
      debugPrint('📄 جاري إعداد كشوفات الحسابات للنسخ الاحتياطي...');
      final db = DatabaseService();
      final customers = await db.getAllCustomers();
      
      if (customers.isEmpty) {
        debugPrint('ℹ️ لا يوجد عملاء لإرسال كشوفات الحسابات.');
        return null;
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
      
      final sent = await sendDocumentWithDetails(
        file: file,
        caption: '📚 كشوفات حسابات العملاء - $dateStr',
      );
      if (!sent.success) {
        return 'كشوفات الحسابات (PDF) لم تُرسل: ${sent.errorMessage ?? ''}'
            '${sent.statusCode != null ? ' (كود ${sent.statusCode})' : ''}';
      }
      debugPrint('✅ تم إرسال كشوفات الحسابات بنجاح');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في نسخ كشوفات الحسابات: $e');
      _lastError = 'خطأ في كشوفات الحسابات: $e';
      return 'كشوفات الحسابات (PDF) لم تُرسل: $e';
    }
  }
}

