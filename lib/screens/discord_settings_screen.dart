import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/settings_manager.dart';

class DiscordSettingsScreen extends StatefulWidget {
  const DiscordSettingsScreen({Key? key}) : super(key: key);

  @override
  State<DiscordSettingsScreen> createState() => _DiscordSettingsScreenState();
}

class _DiscordSettingsScreenState extends State<DiscordSettingsScreen> {
  final _webhookUrlController = TextEditingController();
  
  bool _isLoading = false;
  bool _showInstructions = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final url = await SettingsManager.getDiscordWebhookUrl();
    setState(() {
      _webhookUrlController.text = url ?? '';
    });
  }

  @override
  void dispose() {
    _webhookUrlController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _saveSettings() async {
    final url = _webhookUrlController.text.trim();

    if (url.isEmpty || !url.startsWith('http')) {
      _showSnackBar('الرجاء إدخال رابط Webhook صحيح', isError: true);
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      await SettingsManager.setDiscordWebhookUrl(url);
      _showSnackBar('✅ تم حفظ الإعدادات بنجاح!');
      await _sendTestMessage(silentSuccess: true); 
    } catch (e) {
      _showSnackBar('خطأ في الحفظ: $e', isError: true);
    } finally {
        if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendTestMessage({bool silentSuccess = false}) async {
    final url = _webhookUrlController.text.trim();
    if (url.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': '✅ اختبار الاتصال من تطبيق إدارة المتجر.\n\nالإعدادات صحيحة وتعمل بنجاح!'
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!silentSuccess) _showSnackBar('✅ تم إرسال رسالة تجريبية بنجاح!');
      } else {
        _showSnackBar('فشل الاتصال: ${response.statusCode} - ${response.body}', isError: true);
      }
    } catch (e) {
      _showSnackBar('خطأ في الإرسال: $e', isError: true);
    }
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1E2E), // kPrimaryColor
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // kBackgroundColor
      appBar: AppBar(
        title: const Text('إعدادات Discord'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.discord, size: 80, color: Colors.indigo),
                ),
                const SizedBox(height: 20),
                const Text(
                  'تكوين النسخ الاحتياطي عبر Discord',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'قم بإعداد Webhook في سيرفرك على Discord لتلقي التقارير والفواتير.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 40),

                // Webhook URL Section
                _buildSectionCard(
                  title: 'رابط Webhook',
                  child: Column(
                    children: [
                      TextField(
                        controller: _webhookUrlController,
                        decoration: InputDecoration(
                          hintText: 'https://discord.com/api/webhooks/...',
                          prefixIcon: const Icon(Icons.link),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _showInstructions = !_showInstructions),
                        icon: Icon(_showInstructions ? Icons.keyboard_arrow_up : Icons.help_outline),
                        label: const Text('كيف أحصل على رابط Webhook؟'),
                      ),
                      if (_showInstructions)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(8)),
                          child: const Text(
                            '1. افتح إعدادات سيرفر Discord (Server Settings).\n'
                            '2. اذهب إلى Integrations ثم Webhooks.\n'
                            '3. اضغط على New Webhook.\n'
                            '4. قم بتسميته واختيار القناة (Channel) المناسبة.\n'
                            '5. اضغط على زر Copy Webhook URL والصقه هنا.',
                            style: TextStyle(height: 1.5),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 5,
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('حفظ واختبار الاتصال', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => _sendTestMessage(silentSuccess: false),
                    icon: const Icon(Icons.send),
                    label: const Text('إرسال رسالة تجريبية الآن', style: TextStyle(fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
