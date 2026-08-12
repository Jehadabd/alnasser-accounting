// services/discord_backup_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as path;

/// خدمة النسخ الاحتياطي إلى Discord عبر Webhook
class DiscordBackupService {
  static final DiscordBackupService _instance = DiscordBackupService._internal();
  factory DiscordBackupService() => _instance;
  DiscordBackupService._internal();

  // إعدادات Discord
  String? _webhookUrl;
  bool _isEnabled = false;

  // Getters
  bool get isEnabled => _isEnabled;
  String? get webhookUrl => _webhookUrl;

  /// تحميل الإعدادات من dotenv
  void loadSettings() {
    _webhookUrl = dotenv.env['DISCORD_WEBHOOK_URL']?.trim();
    _isEnabled = dotenv.env['DISCORD_ENABLED'] == 'true';
  }

  /// حفظ الإعدادات
  Future<void> saveSettings({
    required String webhookUrl,
    required bool enabled,
  }) async {
    _webhookUrl = webhookUrl.trim();
    _isEnabled = enabled;

    // تحديث ملف .env
    try {
      final envFile = File('.env');
      if (await envFile.exists()) {
        String content = await envFile.readAsString();
        content = _updateEnvLine(content, 'DISCORD_WEBHOOK_URL', webhookUrl);
        content = _updateEnvLine(content, 'DISCORD_ENABLED', enabled.toString());
        await envFile.writeAsString(content);
      }
    } catch (e) {
      print('خطأ في حفظ إعدادات Discord: $e');
      rethrow;
    }
  }

  String _updateEnvLine(String content, String key, String value) {
    final lines = content.split('\n');
    bool found = false;
    
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('$key=')) {
        lines[i] = '$key=$value';
        found = true;
        break;
      }
    }
    
    if (!found) {
      lines.add('$key=$value');
    }
    
    return lines.join('\n');
  }

  /// اختبار الاتصال
  Future<bool> testConnection() async {
    if (_webhookUrl == null || _webhookUrl!.isEmpty) {
      return false;
    }

    if (!_webhookUrl!.startsWith('https://discord.com/api/webhooks/') &&
        !_webhookUrl!.startsWith('https://discordapp.com/api/webhooks/')) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_webhookUrl!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': '🔍 اختبار الاتصال من تطبيق الناصر'}),
      ).timeout(const Duration(seconds: 30));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('خطأ في اختبار الاتصال: $e');
      return false;
    }
  }

  /// إرسال ملف النسخة الاحتياطية
  Future<bool> sendBackupFile(File file, {String? caption}) async {
    if (!_isEnabled || _webhookUrl == null) {
      return false;
    }

    try {
      final fileName = path.basename(file.path);
      final fileBytes = await file.readAsBytes();

      final request = http.MultipartRequest('POST', Uri.parse(_webhookUrl!));
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

      request.fields['content'] = caption ?? '📦 نسخة احتياطية - ${DateTime.now()}';

      final response = await request.send().timeout(const Duration(minutes: 5));
      final responseBody = await http.Response.fromStream(response);

      return responseBody.statusCode == 204 || responseBody.statusCode == 200;
    } catch (e) {
      print('خطأ في إرسال الملف إلى Discord: $e');
      return false;
    }
  }

  /// إرسال رسالة نصية
  Future<bool> sendMessage(String text) async {
    if (!_isEnabled || _webhookUrl == null) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_webhookUrl!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': text}),
      ).timeout(const Duration(seconds: 30));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print('خطأ في إرسال الرسالة إلى Discord: $e');
      return false;
    }
  }
}
