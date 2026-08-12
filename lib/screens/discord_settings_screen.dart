// screens/discord_settings_screen.dart
import 'package:flutter/material.dart';
import '../services/discord_backup_service.dart';

class DiscordSettingsScreen extends StatefulWidget {
  const DiscordSettingsScreen({super.key});

  @override
  State<DiscordSettingsScreen> createState() => _DiscordSettingsScreenState();
}

class _DiscordSettingsScreenState extends State<DiscordSettingsScreen> {
  final _discordService = DiscordBackupService();
  final _webhookController = TextEditingController();
  bool _isEnabled = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _discordService.loadSettings();
    _webhookController.text = _discordService.webhookUrl ?? '';
    _isEnabled = _discordService.isEnabled;
  }

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    if (_webhookController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال Webhook URL')),
      );
      return;
    }

    setState(() => _isTesting = true);

    await _discordService.saveSettings(
      webhookUrl: _webhookController.text,
      enabled: true,
    );

    final connected = await _discordService.testConnection();

    setState(() {
      _isTesting = false;
      if (connected) _isEnabled = true;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(connected ? '✅ تم الاتصال بنجاح!' : '❌ فشل الاتصال'),
        backgroundColor: connected ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _toggleEnabled(bool value) async {
    if (!value) {
      // تعطيل الخدمة
      await _discordService.saveSettings(
        webhookUrl: _webhookController.text,
        enabled: false,
      );
      setState(() => _isEnabled = false);
    } else {
      // تفعيل الخدمة - يتطلب اختبار
      _testAndSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات Discord'),
        backgroundColor: const Color(0xFF5865F2),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // معلومات عن Discord
          Card(
            color: const Color(0xFF5865F2).withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: const Color(0xFF5865F2)),
                      const SizedBox(width: 8),
                      const Text(
                        'كيفية الحصول على Webhook URL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. افتح Discord وأنشئ سيرفر جديد\n'
                    '2. أنشئ قناة نصية (مثلاً: backups)\n'
                    '3. إعدادات القناة → Integrations → Webhooks\n'
                    '4. Create Webhook → انسخ الرابط',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // تفعيل/تعطيل الخدمة
          SwitchListTile(
            title: const Text('تفعيل Discord Backup'),
            subtitle: Text(_isEnabled ? 'مفعّل' : 'معطّل'),
            value: _isEnabled,
            onChanged: _toggleEnabled,
            activeColor: const Color(0xFF5865F2),
          ),
          const SizedBox(height: 16),

          // Webhook URL
          TextField(
            controller: _webhookController,
            decoration: InputDecoration(
              labelText: 'Webhook URL',
              hintText: 'https://discord.com/api/webhooks/...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.link),
            ),
            maxLines: 3,
            enabled: !_isTesting,
          ),
          const SizedBox(height: 24),

          // زر الاختبار والحفظ
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _testAndSave,
            icon: _isTesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_isTesting ? 'جاري الاختبار...' : 'اختبار الاتصال وحفظ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5865F2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
