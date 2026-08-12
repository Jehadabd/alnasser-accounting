// lib/services/firebase_sync/firebase_sync_helper.dart
// مساعد لربط عمليات قاعدة البيانات مع Firebase Sync

import 'firebase_sync_service.dart';
import 'firebase_sync_config.dart';

/// مساعد المزامنة عبر Firebase
/// يُستخدم لرفع التغييرات تلقائياً عند حدوثها
class FirebaseSyncHelper {
  static final FirebaseSyncHelper _instance = FirebaseSyncHelper._internal();
  factory FirebaseSyncHelper() => _instance;
  FirebaseSyncHelper._internal();
  
  final FirebaseSyncService _syncService = FirebaseSyncService();
  
  /// هل المزامنة مفعلة؟
  Future<bool> get isEnabled async {
    final configured = await FirebaseSyncConfig.isConfigured();
    final enabled = await FirebaseSyncConfig.isEnabled();
    return configured && enabled;
  }
  
  /// رفع عميل جديد أو محدث
  Future<void> syncCustomer(Map<String, dynamic> customerData) async {
    if (!await isEnabled) return;
    
    try {
      await _syncService.uploadCustomer(customerData);
    } catch (e) {
      print('⚠️ Firebase Sync: فشل رفع العميل: $e');
      // لا نوقف العملية - سيتم المزامنة لاحقاً
    }
  }
  
  /// رفع معاملة جديدة أو محدثة
  Future<void> syncTransaction(Map<String, dynamic> txData, String customerSyncUuid) async {
    if (!await isEnabled) return;
    
    try {
      await _syncService.uploadTransaction(txData, customerSyncUuid);
    } catch (e) {
      print('⚠️ Firebase Sync: فشل رفع المعاملة: $e');
    }
  }
  
  /// الاستماع لأحداث المزامنة
  Stream<String> get syncEvents => _syncService.syncEvents;
}

/// Instance عام للوصول السريع
final firebaseSyncHelper = FirebaseSyncHelper();
