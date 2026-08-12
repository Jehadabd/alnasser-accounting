// lib/services/database/sync/sync_operations.dart
// عمليات المزامنة

import 'package:sqflite/sqflite.dart';
import 'dart:convert';

/// خدمة عمليات المزامنة
class SyncOperations {
  final Future<Database> Function() getDatabase;

  SyncOperations({required this.getDatabase});

  // ═══════════════════════════════════════════════════════════════════════════
  // حالة المزامنة (Sync State)
  // ═══════════════════════════════════════════════════════════════════════════

  /// جلب حالة المزامنة
  Future<Map<String, dynamic>?> getSyncState() async {
    final db = await getDatabase();
    try {
      final result = await db.query('sync_state', limit: 1);
      if (result.isNotEmpty) {
        return result.first;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// تحديث حالة المزامنة
  Future<void> updateSyncState({
    String? deviceId,
    String? deviceName,
    int? localSequence,
    int? syncedUpToGlobal,
    DateTime? lastSyncAt,
    String? secretKeyHash,
  }) async {
    final db = await getDatabase();
    try {
      final existing = await getSyncState();
      
      final data = <String, dynamic>{};
      if (deviceId != null) data['device_id'] = deviceId;
      if (deviceName != null) data['device_name'] = deviceName;
      if (localSequence != null) data['local_sequence'] = localSequence;
      if (syncedUpToGlobal != null) data['synced_up_to_global'] = syncedUpToGlobal;
      if (lastSyncAt != null) data['last_sync_at'] = lastSyncAt.toIso8601String();
      if (secretKeyHash != null) data['secret_key_hash'] = secretKeyHash;
      
      if (existing != null) {
        await db.update('sync_state', data, where: 'id = 1');
      } else {
        data['id'] = 1;
        data['device_id'] = deviceId ?? 'unknown';
        data['local_sequence'] = localSequence ?? 0;
        data['synced_up_to_global'] = syncedUpToGlobal ?? 0;
        await db.insert('sync_state', data);
      }
    } catch (e) {
      print('Error updating sync state: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // عمليات المزامنة (Sync Operations)
  // ═══════════════════════════════════════════════════════════════════════════

  /// إدراج عملية مزامنة
  Future<int> insertSyncOperation(Map<String, dynamic> operation) async {
    final db = await getDatabase();
    try {
      return await db.insert('sync_operations', operation);
    } catch (e) {
      print('Error inserting sync operation: $e');
      return 0;
    }
  }

  /// جلب العمليات المعلقة
  Future<List<Map<String, dynamic>>> getPendingSyncOperations() async {
    final db = await getDatabase();
    try {
      return await db.query(
        'sync_operations',
        where: "status = 'pending'",
        orderBy: 'local_sequence ASC',
      );
    } catch (e) {
      return [];
    }
  }

  /// تحديث حالة عملية
  Future<void> updateOperationStatus(String operationId, String status) async {
    final db = await getDatabase();
    try {
      await db.update(
        'sync_operations',
        {
          'status': status,
          'uploaded_at': status == 'synced' ? DateTime.now().toIso8601String() : null,
        },
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    } catch (e) {
      print('Error updating operation status: $e');
    }
  }

  /// جلب عملية بالمعرف
  Future<Map<String, dynamic>?> getOperationById(String operationId) async {
    final db = await getDatabase();
    try {
      final result = await db.query(
        'sync_operations',
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );
      return result.isEmpty ? null : result.first;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // العمليات المطبقة (Applied Operations)
  // ═══════════════════════════════════════════════════════════════════════════

  /// تسجيل عملية مطبقة
  Future<void> markOperationAsApplied(String operationId, String deviceId) async {
    final db = await getDatabase();
    try {
      await db.insert('sync_applied_operations', {
        'operation_id': operationId,
        'device_id': deviceId,
        'applied_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // تجاهل الخطأ في حالة التكرار
    }
  }

  /// التحقق من تطبيق العملية
  Future<bool> isOperationApplied(String operationId) async {
    final db = await getDatabase();
    try {
      final result = await db.query(
        'sync_applied_operations',
        where: 'operation_id = ?',
        whereArgs: [operationId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // سجل تدقيق المزامنة (Sync Audit Log)
  // ═══════════════════════════════════════════════════════════════════════════

  /// إدراج سجل تدقيق المزامنة
  Future<int> insertSyncAuditLog({
    required DateTime syncStartTime,
    DateTime? syncEndTime,
    required String syncType,
    int operationsUploaded = 0,
    int operationsDownloaded = 0,
    int operationsApplied = 0,
    int operationsFailed = 0,
    bool success = false,
    String? errorMessage,
    String? affectedCustomers,
    String? warnings,
    required String deviceId,
    String? backupPath,
  }) async {
    final db = await getDatabase();
    try {
      return await db.insert('sync_audit_log', {
        'sync_start_time': syncStartTime.toIso8601String(),
        'sync_end_time': syncEndTime?.toIso8601String(),
        'sync_type': syncType,
        'operations_uploaded': operationsUploaded,
        'operations_downloaded': operationsDownloaded,
        'operations_applied': operationsApplied,
        'operations_failed': operationsFailed,
        'success': success ? 1 : 0,
        'error_message': errorMessage,
        'affected_customers': affectedCustomers,
        'warnings': warnings,
        'device_id': deviceId,
        'backup_path': backupPath,
      });
    } catch (e) {
      print('Error inserting sync audit log: $e');
      return 0;
    }
  }

  /// جلب سجل تدقيق المزامنة
  Future<List<Map<String, dynamic>>> getSyncAuditLogs({int limit = 50}) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'sync_audit_log',
        orderBy: 'sync_start_time DESC',
        limit: limit,
      );
    } catch (e) {
      return [];
    }
  }

  /// جلب آخر عملية مزامنة ناجحة
  Future<Map<String, dynamic>?> getLastSuccessfulSync() async {
    final db = await getDatabase();
    try {
      final result = await db.query(
        'sync_audit_log',
        where: 'success = 1',
        orderBy: 'sync_end_time DESC',
        limit: 1,
      );
      return result.isEmpty ? null : result.first;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // إحصائيات المزامنة
  // ═══════════════════════════════════════════════════════════════════════════

  /// جلب إحصائيات المزامنة
  Future<Map<String, dynamic>> getSyncStats() async {
    final db = await getDatabase();
    try {
      final pendingCount = await db.rawQuery(
        "SELECT COUNT(1) as c FROM sync_operations WHERE status = 'pending'"
      );
      final syncedCount = await db.rawQuery(
        "SELECT COUNT(1) as c FROM sync_operations WHERE status = 'synced'"
      );
      final failedCount = await db.rawQuery(
        "SELECT COUNT(1) as c FROM sync_operations WHERE status = 'failed'"
      );
      final appliedCount = await db.rawQuery(
        "SELECT COUNT(1) as c FROM sync_applied_operations"
      );
      
      return {
        'pending': (pendingCount.first['c'] as int?) ?? 0,
        'synced': (syncedCount.first['c'] as int?) ?? 0,
        'failed': (failedCount.first['c'] as int?) ?? 0,
        'applied': (appliedCount.first['c'] as int?) ?? 0,
      };
    } catch (e) {
      return {};
    }
  }

  /// تنظيف العمليات القديمة
  Future<int> cleanOldSyncData({int daysOld = 30}) async {
    final db = await getDatabase();
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      
      // تنظيف العمليات القديمة
      final deletedOps = await db.delete(
        'sync_operations',
        where: "status = 'synced' AND uploaded_at < ?",
        whereArgs: [cutoffDate.toIso8601String()],
      );
      
      // تنظيف سجل التدقيق القديم
      final deletedLogs = await db.delete(
        'sync_audit_log',
        where: 'sync_end_time < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );
      
      return deletedOps + deletedLogs;
    } catch (e) {
      return 0;
    }
  }
}
