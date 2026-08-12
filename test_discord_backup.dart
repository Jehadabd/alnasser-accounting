// test_discord_backup.dart
// ملف اختبار بسيط لخدمة Discord Backup

import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'lib/services/discord_backup_service.dart';

void main() async {
  print('🧪 اختبار خدمة Discord Backup');
  print('═══════════════════════════════════════');
  
  // تحميل .env
  try {
    await dotenv.load(fileName: '.env');
    print('✅ تم تحميل ملف .env');
  } catch (e) {
    print('❌ خطأ في تحميل .env: $e');
    return;
  }
  
  // إنشاء خدمة Discord
  final discordService = DiscordBackupService();
  discordService.loadSettings();
  
  print('\n📋 الإعدادات الحالية:');
  print('   • مفعّل: ${discordService.isEnabled}');
  print('   • Webhook URL: ${discordService.webhookUrl ?? "غير محدد"}');
  
  if (!discordService.isEnabled) {
    print('\n⚠️ الخدمة معطلة. يرجى تفعيلها من الإعدادات.');
    return;
  }
  
  if (discordService.webhookUrl == null || discordService.webhookUrl!.isEmpty) {
    print('\n⚠️ Webhook URL غير محدد. يرجى إضافته في الإعدادات.');
    return;
  }
  
  // اختبار الاتصال
  print('\n🔍 اختبار الاتصال...');
  final connected = await discordService.testConnection();
  
  if (connected) {
    print('✅ تم الاتصال بنجاح!');
    
    // اختبار إرسال رسالة
    print('\n📤 إرسال رسالة اختبار...');
    final messageSent = await discordService.sendMessage('🎉 اختبار من تطبيق الناصر - ${DateTime.now()}');
    
    if (messageSent) {
      print('✅ تم إرسال الرسالة بنجاح!');
    } else {
      print('❌ فشل إرسال الرسالة');
    }
    
    // اختبار إرسال ملف (إذا كان موجود)
    final testFile = File('test_file.txt');
    if (await testFile.exists()) {
      print('\n📦 إرسال ملف اختبار...');
      final fileSent = await discordService.sendBackupFile(
        testFile,
        caption: '📄 ملف اختبار - ${DateTime.now()}',
      );
      
      if (fileSent) {
        print('✅ تم إرسال الملف بنجاح!');
      } else {
        print('❌ فشل إرسال الملف');
      }
    }
  } else {
    print('❌ فشل الاتصال. يرجى التحقق من:');
    print('   1. صحة Webhook URL');
    print('   2. اتصال الإنترنت');
    print('   3. أن الـ Webhook لم يتم حذفه من Discord');
  }
  
  print('\n═══════════════════════════════════════');
  print('✅ انتهى الاختبار');
}
