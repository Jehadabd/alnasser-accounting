// lib/services/firebase_sync/firebase_cleanup_service.dart
// 🔒 تم تحويل هذه الخدمة إلى واجهة آمنة فوق SmartPipeCleanupService.
//
// سابقاً كانت تحذف المستندات الأقدم من مدة المستخدم دون أي فحص لقراءة
// الأجهزة (ACKs) وبحقول أسماء غير متطابقة مع الرفع الفعلي (uploaded_at).
// الحذف الآن يتم حصرياً عبر المنظف الذكي بشرطين معاً:
//   1) تجاوز المدة التي ضبطها المستخدم في الإعدادات.
//   2) قراءة المستند من كل الأجهزة المؤهلة (فحص ACKs).

import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_sync_config.dart';
import 'smart_pipe_cleanup_service.dart';

class FirebaseCleanupService {
  static const String _lastCleanupKey = 'last_firebase_cleanup_time';
  static const int _cleanupIntervalHours = 24; // مرة واحدة يومياً

  Future<void> runDailyCleanup() async {
    try {
      final isEnabled = await FirebaseSyncSecuritySettings.isAutoCleanupEnabled();
      if (!isEnabled) {
        return; // التنظيف التلقائي معطل من الإعدادات
      }

      final prefs = await SharedPreferences.getInstance();
      final lastCleanupStr = prefs.getString(_lastCleanupKey);

      if (lastCleanupStr != null) {
        final lastCleanup = DateTime.parse(lastCleanupStr);
        final difference = DateTime.now().difference(lastCleanup).inHours;

        if (difference < _cleanupIntervalHours) {
          return;
        }
      }

      print('🧹 FirebaseCleanupService: تشغيل الحذف الذكي الآمن (ACK-gated)...');

      final result = await SmartPipeCleanupService().runManualCleanup();

      await prefs.setString(_lastCleanupKey, DateTime.now().toIso8601String());
      print('✅ FirebaseCleanupService: اكتمل التنظيف الآمن '
          '(معاملات=${result.deletedTransactions}، فواتير=${result.deletedInvoices}، '
          'متروكة بانتظار قراءة=${result.skippedPendingRead}).');
    } catch (e) {
      print('❌ FirebaseCleanupService - خطأ في التنظيف الآمن: $e');
    }
  }
}
