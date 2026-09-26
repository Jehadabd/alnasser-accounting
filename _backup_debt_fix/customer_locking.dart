// lib/services/database/business/customer_locking.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../core/database_helpers.dart';
import '../../license_service.dart';
import 'dart:io';

/// نتيجة محاولة القفل
class LockResult {
  final bool success;
  final String? lockedBy;
  final String? message;
  
  LockResult({required this.success, this.lockedBy, this.message});
}

/// خدمة إدارة الأقفال (Lock Service)
/// تمنع التعديل المتزامن على نفس الموارد (عميل، فاتورة) من قبل مستخدمين مختلفين
class LockService {
  final Future<Database> Function() getDatabase;
  final LicenseService _licenseService = LicenseService();
  
  LockService({required this.getDatabase});
  
  // مدة صلاحية القفل (5 دقائق)
  static const int _lockExpirationMinutes = 5;
  
  // معرف الجهاز الحالي (يتم تحميله مرة واحدة)
  String? _deviceId;
  String? _userName;
  
  /// تهيئة معرف الجهاز
  Future<void> _initMsg() async {
    if (_deviceId == null) {
      _deviceId = await _licenseService.generateDeviceId();
      _userName = Platform.environment['USERNAME'] ?? 'Unknown User';
    }
  }

  /// محاولة حجز مورد (Acquire Lock)
  Future<LockResult> acquireLock({
    required String resourceType, // 'customer' or 'invoice'
    required int resourceId,
  }) async {
    await _initMsg();
    final db = await getDatabase();
    
    try {
      // 1. تنظيف الأقفال المنتهية الصلاحية أولاً
      await _cleanupExpiredLocks(db);
      
      // 2. محاولة الحجز
      final now = DateTime.now();
      final expires = now.add(const Duration(minutes: _lockExpirationMinutes));
      
      await db.insert('resource_locks', {
        'resource_type': resourceType,
        'resource_id': resourceId,
        'locked_by_device_id': _deviceId,
        'locked_by_user_name': _userName,
        'locked_at': now.toIso8601String(),
        'expires_at': expires.toIso8601String(),
      });
      
      return LockResult(success: true);
      
    } catch (e) {
      // إذا فشل الإدراج، فهذا يعني أن المورد محجوز بالفعل (بسبب UNIQUE constraint)
      // نحتاج لمعرفة من حاجزه
      final existingLock = await db.query(
        'resource_locks',
        where: 'resource_type = ? AND resource_id = ?',
        whereArgs: [resourceType, resourceId],
      );
      
      if (existingLock.isNotEmpty) {
        final lock = existingLock.first;
        final lockedByDevice = lock['locked_by_device_id'] as String;
        
        // إذا كان جهازي هو من يحجز، نقوم بتحديث مدة القفل (تمديد)
        if (lockedByDevice == _deviceId) {
           await keepAlive(resourceType: resourceType, resourceId: resourceId);
           return LockResult(success: true);
        }
        
        final lockedByUser = lock['locked_by_user_name'] as String? ?? 'مستخدم آخر';
        return LockResult(
          success: false, 
          lockedBy: lockedByUser,
          message: 'المورد قيد الاستخدام حالياً من قبل $lockedByUser'
        );
      }
      
      return LockResult(success: false, message: 'حدث خطأ أثناء الحجز: $e');
    }
  }
  
  /// تحرير القفل (Release Lock)
  Future<void> releaseLock({
    required String resourceType, 
    required int resourceId,
  }) async {
    await _initMsg();
    final db = await getDatabase();
    
    // نحذف القفل فقط إذا كان تابعاً لهذا الجهاز
    await db.delete(
      'resource_locks',
      where: 'resource_type = ? AND resource_id = ? AND locked_by_device_id = ?',
      whereArgs: [resourceType, resourceId, _deviceId],
    );
  }
  
  /// تمديد صلاحية القفل (Heartbeat)
  /// يجب استدعاء هذه الدالة دورياً طالما المستخدم يعمل على المورد
  Future<bool> keepAlive({
    required String resourceType, 
    required int resourceId,
  }) async {
    await _initMsg();
    final db = await getDatabase();
    
    final expires = DateTime.now().add(const Duration(minutes: _lockExpirationMinutes));
    
    final count = await db.update(
      'resource_locks',
      {'expires_at': expires.toIso8601String()},
      where: 'resource_type = ? AND resource_id = ? AND locked_by_device_id = ?',
      whereArgs: [resourceType, resourceId, _deviceId],
    );
    
    return count > 0;
  }
  
  /// التحقق من حالة القفل
  Future<bool> isLockedByOther({
    required String resourceType, 
    required int resourceId,
  }) async {
    await _initMsg();
    final db = await getDatabase();
    
    await _cleanupExpiredLocks(db); // Clean up first
    
    final result = await db.query(
      'resource_locks',
      columns: ['locked_by_device_id'],
      where: 'resource_type = ? AND resource_id = ?',
      whereArgs: [resourceType, resourceId],
    );
    
    if (result.isEmpty) return false;
    
    final lockedByDevice = result.first['locked_by_device_id'] as String;
    return lockedByDevice != _deviceId;
  }

  /// تنظيف الأقفال المنتهية
  Future<void> _cleanupExpiredLocks(Database db) async {
    final now = DateTime.now().toIso8601String();
    await db.delete(
      'resource_locks',
      where: 'expires_at < ?',
      whereArgs: [now],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Legacy / Helper Methods (توافق مع الكود القديم إن وجد)
  // ═══════════════════════════════════════════════════════════════════════════
  
  // هذه الدوال كانت في النسخة القديمة Memory-based
  // سنقوم بتحويلها لاستخدام قاعدة البيانات
  
  // (سيتم استبدال استخداماتها تدريجياً في InvoiceManager والـ CreateInvoiceScreen)
}
