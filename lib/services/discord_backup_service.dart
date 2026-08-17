import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'settings_manager.dart';

class DiscordBackupService {
  /// التحقق مما إذا كان الديسكورد مُعداً
  Future<bool> get isConfigured async {
    final url = await SettingsManager.getDiscordWebhookUrl();
    return url != null && url.isNotEmpty && url.startsWith('http');
  }

  /// إرسال رسالة نصية بسيطة (أو ملخص) إلى Discord
  Future<bool> sendMessage(String message) async {
    if (!await isConfigured) return false;
    final url = await SettingsManager.getDiscordWebhookUrl();
    
    try {
      // إزالة تنسيقات HTML الخاصة بتيليجرام (<b>, </b>) واستبدالها بتنسيقات Discord (**)
      String discordMessage = message.replaceAll('<b>', '**').replaceAll('</b>', '**');
      // قص الرسالة إذا كانت طويلة جداً (حد ديسكورد 2000 حرف)
      if (discordMessage.length > 2000) {
        discordMessage = '${discordMessage.substring(0, 1990)}...\n(تم قص الرسالة)';
      }

      final response = await http.post(
        Uri.parse(url!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': discordMessage}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ تم الإرسال إلى Discord بنجاح');
        return true;
      } else {
        print('❌ خطأ في الإرسال إلى Discord: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ خطأ استثنائي في Discord: $e');
      return false;
    }
  }

  /// إرسال ملف إلى Discord
  Future<bool> sendDocument({required File file, String? caption}) async {
    if (!await isConfigured) return false;
    final url = await SettingsManager.getDiscordWebhookUrl();

    try {
      print('📤 جاري إرسال ملف إلى Discord...');
      
      final request = http.MultipartRequest('POST', Uri.parse(url!));
      
      if (caption != null && caption.isNotEmpty) {
        String discordCaption = caption.replaceAll('<b>', '**').replaceAll('</b>', '**');
        request.fields['content'] = discordCaption;
      }
      
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('✅ تم إرسال الملف إلى Discord بنجاح');
        return true;
      } else {
        print('❌ خطأ في إرسال الملف إلى Discord: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ خطأ استثنائي في إرسال الملف لـ Discord: $e');
      return false;
    }
  }
}
