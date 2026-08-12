// lib/services/database/dao/audit_dao.dart
// عمليات سجل التدقيق المالي

import 'package:sqflite/sqflite.dart';
import 'dart:convert';

/// DAO لسجل التدقيق المالي
class AuditDao {
  final Future<Database> Function() getDatabase;

  AuditDao({required this.getDatabase});

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال سجل التدقيق المالي (Financial Audit Log)
  // ═══════════════════════════════════════════════════════════════════════════

  /// إدراج سجل تدقيق
  Future<int> insertAuditLog({
    required String operationType,
    required String entityType,
    required int entityId,
    String? oldValues,
    String? newValues,
    String? notes,
  }) async {
    final db = await getDatabase();
    try {
      return await db.insert('financial_audit_log', {
        'operation_type': operationType,
        'entity_type': entityType,
        'entity_id': entityId,
        'old_values': oldValues,
        'new_values': newValues,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('خطأ في إدراج سجل التدقيق: $e');
      return 0;
    }
  }

  /// جلب سجل التدقيق لكيان معين
  Future<List<Map<String, dynamic>>> getAuditLogForEntity(
    String entityType,
    int entityId,
  ) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'financial_audit_log',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل التدقيق: $e');
      return [];
    }
  }

  /// جلب سجل التدقيق لفترة زمنية
  Future<List<Map<String, dynamic>>> getAuditLogForPeriod(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'financial_audit_log',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [
          startDate.toIso8601String(),
          endDate.toIso8601String(),
        ],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل التدقيق للفترة: $e');
      return [];
    }
  }

  /// جلب آخر العمليات المالية
  Future<List<Map<String, dynamic>>> getRecentAuditLogs({int limit = 50}) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'financial_audit_log',
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (e) {
      print('خطأ في جلب آخر العمليات: $e');
      return [];
    }
  }

  /// حذف سجلات التدقيق القديمة (أقدم من 6 أشهر)
  Future<int> cleanOldAuditLogs() async {
    final db = await getDatabase();
    try {
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
      return await db.delete(
        'financial_audit_log',
        where: 'created_at < ?',
        whereArgs: [sixMonthsAgo.toIso8601String()],
      );
    } catch (e) {
      print('خطأ في حذف سجلات التدقيق القديمة: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📸 دوال نسخ الفواتير (Invoice Snapshots)
  // ═══════════════════════════════════════════════════════════════════════════

  /// حفظ نسخة من الفاتورة قبل التعديل
  Future<int> saveInvoiceSnapshot({
    required int invoiceId,
    required String snapshotType,
    String? notes,
    String? createdBy,
  }) async {
    final db = await getDatabase();
    try {
      // جلب بيانات الفاتورة الحالية
      final invoiceMaps = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (invoiceMaps.isEmpty) {
        throw Exception('الفاتورة غير موجودة');
      }
      final invoice = invoiceMaps.first;
      
      // جلب أصناف الفاتورة
      final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      final itemsJson = jsonEncode(items);
      
      // حساب رقم النسخة
      final existingSnapshots = await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'version_number DESC',
        limit: 1,
      );
      final nextVersion = existingSnapshots.isEmpty 
          ? 1 
          : ((existingSnapshots.first['version_number'] as int?) ?? 0) + 1;
      
      return await db.insert('invoice_snapshots', {
        'invoice_id': invoiceId,
        'version_number': nextVersion,
        'snapshot_type': snapshotType,
        'customer_name': invoice['customer_name'],
        'customer_phone': invoice['customer_phone'],
        'customer_address': invoice['customer_address'],
        'invoice_date': invoice['invoice_date'],
        'payment_type': invoice['payment_type'],
        'total_amount': invoice['total_amount'],
        'discount': invoice['discount'],
        'amount_paid': invoice['amount_paid_on_invoice'],
        'loading_fee': invoice['loading_fee'],
        'items_json': itemsJson,
        'created_at': DateTime.now().toIso8601String(),
        'notes': notes,
        'invoice_notes': invoice['notes'],
        'created_by': createdBy,
      });
    } catch (e) {
      print('خطأ في حفظ نسخة الفاتورة: $e');
      return 0;
    }
  }

  /// جلب جميع نسخ فاتورة معينة
  Future<List<Map<String, dynamic>>> getInvoiceSnapshots(int invoiceId) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'version_number ASC',
      );
    } catch (e) {
      print('خطأ في جلب نسخ الفاتورة: $e');
      return [];
    }
  }

  /// التحقق من وجود تعديلات على الفاتورة
  Future<bool> hasInvoiceBeenModified(int invoiceId) async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COUNT(1) as c FROM invoice_snapshots WHERE invoice_id = ?
      ''', [invoiceId]);
      return ((result.first['c'] as int?) ?? 0) > 1;
    } catch (e) {
      return false;
    }
  }

  /// جلب عدد التعديلات على الفاتورة
  Future<int> getInvoiceModificationCount(int invoiceId) async {
    final db = await getDatabase();
    try {
      final result = await db.rawQuery('''
        SELECT COUNT(1) as c FROM invoice_snapshots WHERE invoice_id = ?
      ''', [invoiceId]);
      return (result.first['c'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔒 دوال سجل عمليات الفاتورة (Invoice Logs)
  // ═══════════════════════════════════════════════════════════════════════════

  /// تسجيل عملية على فاتورة
  Future<int> insertInvoiceLog({
    required int invoiceId,
    required String action,
    String? details,
    String? createdBy,
  }) async {
    final db = await getDatabase();
    try {
      return await db.insert('invoice_logs', {
        'invoice_id': invoiceId,
        'action': action,
        'details': details,
        'created_at': DateTime.now().toIso8601String(),
        'created_by': createdBy,
      });
    } catch (e) {
      print('خطأ في تسجيل عملية الفاتورة: $e');
      return 0;
    }
  }

  /// جلب سجل عمليات فاتورة
  Future<List<Map<String, dynamic>>> getInvoiceLogs(int invoiceId) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'invoice_logs',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل عمليات الفاتورة: $e');
      return [];
    }
  }
}
