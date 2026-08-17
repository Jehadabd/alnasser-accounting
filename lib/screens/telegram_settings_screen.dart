// lib/screens/telegram_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/settings_manager.dart';
import '../services/telegram_invoice_export_service.dart';
import 'package:url_launcher/url_launcher.dart';

class TelegramSettingsScreen extends StatefulWidget {
  const TelegramSettingsScreen({super.key});

  @override
  State<TelegramSettingsScreen> createState() => _TelegramSettingsScreenState();
}

class _TelegramSettingsScreenState extends State<TelegramSettingsScreen> {
  final _botTokenController = TextEditingController();
  final _channelIdController = TextEditingController();
  
  // Backup flags state
  bool _backupDebtRecordsPdf = true;
  bool _backupAccountStatementsPdf = true;
  bool _reportOnlyLocalInvoices = false;
  bool _reportDetailedDivided = false;

  bool _isLoading = false;
  String? _channelName;
  String? _botName;
  
  // للتحكم في عرض التعليمات
  bool _showBotInstructions = false;
  bool _showChannelInstructions = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final settings = await SettingsManager.getAppSettings();
    final onlyLocal = await SettingsManager.isReportOnlyLocalInvoices();
    final detailed = await SettingsManager.isReportDetailedDivided();
    
    setState(() {
      _botTokenController.text = settings.telegramBotToken ?? '';
      _channelIdController.text = settings.telegramChannelId ?? '';
      _backupDebtRecordsPdf = settings.backupDebtRecordsPdf;
      _backupAccountStatementsPdf = settings.backupAccountStatementsPdf;
      _reportOnlyLocalInvoices = onlyLocal;
      _reportDetailedDivided = detailed;
    });
    // إذا كانت البيانات موجودة، حاول جلب الأسماء بشكل صامت
    if (_botTokenController.text.isNotEmpty) {
      _validateBotToken(silent: true);
    }
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _channelIdController.dispose();
    super.dispose();
  }

  // ... (نفس دوال الاستخراج والتحقق ولكن مع تحديثات طفيفة) ...

  String? _extractBotToken(String input) {
    final regex = RegExp(r'(\d{8,}:[A-Za-z0-9_-]{35,})');
    final match = regex.firstMatch(input);
    return match?.group(1);
  }

  String? _extractChannelId(String input) {
    try {
      final Map<String, dynamic> jsonData = json.decode(input);
      if (jsonData['ok'] == true && jsonData['result'] is List) {
        final results = jsonData['result'] as List;
        for (var update in results) {
          final message = update['channel_post'] ?? update['message'];
          if (message != null && message['chat'] != null) {
            final chatId = message['chat']['id'];
            if (chatId != null) return chatId.toString();
          }
        }
      }
    } catch (_) {}
    
    final regex = RegExp(r'(-100\d{10,13})');
    final match = regex.firstMatch(input);
    if (match != null) return match.group(1);
    
    final negativeRegex = RegExp(r'(-\d{10,})');
    final negativeMatch = negativeRegex.firstMatch(input);
    return negativeMatch?.group(1);
  }

  Future<bool> _validateBotToken({bool silent = false}) async {
    final token = _extractBotToken(_botTokenController.text.trim());
    if (token == null) {
      if (!silent) _showSnackBar('لم يتم العثور على توكن صالح', isError: true);
      return false;
    }

    if (!silent) setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse('https://api.telegram.org/bot$token/getMe'),
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      if (data['ok'] == true) {
        if (mounted) {
          setState(() {
            _botTokenController.text = token;
            _botName = data['result']['first_name'] ?? data['result']['username'];
            _isLoading = false;
          });
        }
        return true;
      } else {
        if (mounted && !silent) { // Added !silent check
             setState(() => _isLoading = false); // Ensure stop loading
             _showSnackBar('التوكن غير صالح: ${data['description']}', isError: true);
        }
        return false;
      }
    } catch (e) {
      if (mounted && !silent) {
         setState(() => _isLoading = false);
         _showSnackBar('خطأ في الاتصال', isError: true);
      }
      return false;
    }
  }

  Future<void> _validateChannelId({bool silent = false}) async {
    // ... similar modernization logic ...
    // للتبسيط في هذا الرد، سنعتمد على الحفظ المباشر والتجربة
    // في التصميم الجديد، سنعتمد على زر "فحص الاتصال" الشامل
  }

  Future<void> _saveSettings() async {
    final token = _botTokenController.text.trim();
    final channelId = _channelIdController.text.trim();

    if (token.isEmpty || channelId.isEmpty) {
      _showSnackBar('الرجاء إكمال جميع الحقول', isError: true);
      return;
    }
    
    setState(() => _isLoading = true);
    
    // حفظ مباشر
    try {
      final updatedSettings = (await SettingsManager.getAppSettings()).copyWith(
        telegramBotToken: _botTokenController.text.trim(),
        telegramChannelId: _channelIdController.text.trim(),
        backupDebtRecordsPdf: _backupDebtRecordsPdf,
        backupAccountStatementsPdf: _backupAccountStatementsPdf,
      );
      await SettingsManager.saveAppSettings(updatedSettings);
      
      await SettingsManager.setReportOnlyLocalInvoices(_reportOnlyLocalInvoices);
      await SettingsManager.setReportDetailedDivided(_reportDetailedDivided);

      _showSnackBar('✅ تم حفظ الإعدادات بنجاح!');
      // فحص الاتصال كجزء من الحفظ
      await _sendTestMessage(silentSuccess: true); 
    } catch (e) {
      _showSnackBar('خطأ في الحفظ: $e', isError: true);
    } finally {
        if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendTestMessage({bool silentSuccess = false}) async {
    final token = _botTokenController.text.trim();
    final channelId = _channelIdController.text.trim();
    
    if (token.isEmpty || channelId.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {
          'chat_id': channelId,
          'text': '✅ اختبار الاتصال من تطبيق إدارة المتجر.\n\nالإعدادات صحيحة وتعمل بنجاح!',
        },
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);
      if (data['ok'] == true) {
        setState(() {
            _channelName = data['result']['chat']['title'];
        });
        if (!silentSuccess) _showSnackBar('✅ تم إرسال رسالة تجريبية بنجاح!');
      } else {
        _showSnackBar('فشل الاتصال: ${data['description']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('خطأ في الإرسال: $e', isError: true);
    }
  }
  
    Future<void> _exportAllInvoices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ تأكيد رفع الأرشيف'),
        content: const Text(
          'سيتم إعادة إنشاء جميع ملفات PDF للفواتير وإرسالها إلى القناة.\nهذه العملية قد تستغرق وقتاً طويلاً.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('بدء الرفع')
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final service = TelegramInvoiceExportService();
      await service.exportAndSendAllInvoices(
        onProgress: (current, total, status) {
          // يمكن إضافة تحديث للواجهة هنا
        },
      );
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('✅ اكتملت العملية');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('خطأ: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('إعدادات النسخ الاحتياطي'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header Image/Icon
            const Icon(Icons.telegram, size: 80, color: Colors.blue),
            const SizedBox(height: 10),
            const Text(
              'ربط مع تيليجرام',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'احصل على نسخ احتياطية وتقارير فورية على قناتك الخاصة',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),

            // Bot Token Section
            _buildSectionCard(
              title: '1. توكن البوت (Bot Token)',
              child: Column(
                children: [
                  TextField(
                    controller: _botTokenController,
                    decoration: InputDecoration(
                      hintText: 'ألصق التوكن هنا...',
                      prefixIcon: const Icon(Icons.vpn_key),
                      suffixIcon: _botName != null 
                        ? const Icon(Icons.check_circle, color: Colors.green) 
                        : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onChanged: (val) {
                       final token = _extractBotToken(val);
                       if (token != null && token != val) {
                         _botTokenController.text = token;
                         _botTokenController.selection = TextSelection.fromPosition(TextPosition(offset: token.length));
                       }
                    },
                  ),
                  if (_botName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('تم التحقق: $_botName', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ),
                  TextButton.icon(
                    onPressed: () => setState(() => _showBotInstructions = !_showBotInstructions),
                    icon: Icon(_showBotInstructions ? Icons.keyboard_arrow_up : Icons.help_outline),
                    label: const Text('كيف أحصل على التوكن؟'),
                  ),
                  if (_showBotInstructions)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          const Text('1. ابحث عن @BotFather في تيليجرام\n2. أرسل /newbot\n3. اتبع التعليمات وانسخ التوكن'),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => _openUrl('https://t.me/BotFather'),
                            child: const Text('فتح BotFather'),
                          )
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Channel ID Section
            _buildSectionCard(
              title: '2. معرف القناة (Channel ID)',
              child: Column(
                children: [
                  TextField(
                    controller: _channelIdController,
                    decoration: InputDecoration(
                      hintText: 'مثال: -100123456789',
                      prefixIcon: const Icon(Icons.public),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                   TextButton.icon(
                    onPressed: () => setState(() => _showChannelInstructions = !_showChannelInstructions),
                    icon: Icon(_showChannelInstructions ? Icons.keyboard_arrow_up : Icons.help_outline),
                    label: const Text('كيف أحصل على المعرف؟'),
                  ),
                  if (_showChannelInstructions)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)),
                      child: const Text('1. أضف البوت كـ Admin في قناتك\n2. أرسل رسالة في القناة\n3. انسخ معرف القناة (يمكنك استخدام بوتات مثل @getidsbot لاستخراجه)'),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 30),
            
            // 🆕 Backup Content Options
            const Text(
              'محتوى النسخ الاحتياطي',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1E2E), // Assuming kPrimaryColor is defined elsewhere or using a direct color
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('إرفاق تقرير الديون (PDF)'),
                    subtitle: const Text('سيتم إرسال ملف PDF يحتوي على قائمة الديون الحالية'),
                    value: _backupDebtRecordsPdf,
                    activeColor: Colors.blue, // Assuming kPrimaryColor is Colors.blue
                    onChanged: (val) => setState(() => _backupDebtRecordsPdf = val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('إرفاق كشوفات الحسابات (PDF)'),
                    subtitle: const Text('سيتم إرسال ملف PDF شامل لكشوفات حسابات جميع العملاء'),
                    value: _backupAccountStatementsPdf,
                    activeColor: Colors.blue, // Assuming kPrimaryColor is Colors.blue
                    onChanged: (val) => setState(() => _backupAccountStatementsPdf = val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('إحصائيات فواتير هذا الجهاز فقط'),
                    subtitle: const Text('استثناء الفواتير التي تمت مزامنتها من حواسيب أخرى من التقارير'),
                    value: _reportOnlyLocalInvoices,
                    activeColor: Colors.blue, 
                    onChanged: (val) => setState(() => _reportOnlyLocalInvoices = val),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('تقرير مفصل ومقسم'),
                    subtitle: const Text('إرسال التقارير بشكل مفصل لكل قسم بدلاً من إجمالي واحد'),
                    value: _reportDetailedDivided,
                    activeColor: Colors.blue, 
                    onChanged: (val) => setState(() => _reportDetailedDivided = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('حفظ وربط الاتصال', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
             
             const SizedBox(height: 10),
             TextButton.icon(
               onPressed: _isLoading ? null : _sendTestMessage,
               icon: const Icon(Icons.send),
               label: const Text('إرسال رسالة تجريبية الآن'),
             ),

            const Divider(height: 40),
            
            // Advanced Actions
            ListTile(
              title: const Text('رفع الأرشيف بالكامل', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('إعادة إرسال جميع الفواتير القديمة للقناة'),
              leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.backup)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _exportAllInvoices,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
