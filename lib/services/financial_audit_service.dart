// services/financial_audit_service.dart
// خدمة تسجيل العمليات المالية للتدقيق

import 'dart:convert';
import 'database_service.dart';

class FinancialAuditService {
  final DatabaseService _db = DatabaseService();

  /// تسجيل عملية مالية في سجل التدقيق
  Future<void> logOperation({
    required String operationType,
    required String entityType,
    required int entityId,
    Map<String, dynamic>? oldValues,
    Map<String, dynamic>? newValues,
    String? notes,
  }) async {
    try {
      await _db.insertAuditLog(
        operationType: operationType,
        entityType: entityType,
        entityId: entityId,
        oldValues: oldValues != null ? jsonEncode(oldValues) : null,
        newValues: newValues != null ? jsonEncode(newValues) : null,
        notes: notes,
      );
    } catch (e) {
      print('خطأ في تسجيل عملية التدقيق: $e');
      // لا نرمي استثناء لأن فشل التسجيل لا يجب أن يوقف العملية الأساسية
    }
  }

  /// تسجيل إنشاء فاتورة
  Future<void> logInvoiceCreation(int invoiceId, Map<String, dynamic> invoiceData, {int? customerId}) async {
    // تسجيل للفاتورة
    await logOperation(
      operationType: 'invoice_create',
      entityType: 'invoice',
      entityId: invoiceId,
      newValues: invoiceData,
      notes: 'إنشاء فاتورة جديدة',
    );
    
    // تسجيل للعميل أيضاً إذا كان موجوداً
    if (customerId != null) {
      await logOperation(
        operationType: 'invoice_create',
        entityType: 'customer',
        entityId: customerId,
        newValues: {...invoiceData, 'invoice_id': invoiceId},
        notes: 'إنشاء فاتورة جديدة رقم $invoiceId',
      );
    }
  }

  /// تسجيل تعديل فاتورة
  Future<void> logInvoiceUpdate(
    int invoiceId,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
    {int? customerId}
  ) async {
    // تسجيل للفاتورة
    await logOperation(
      operationType: 'invoice_update',
      entityType: 'invoice',
      entityId: invoiceId,
      oldValues: oldData,
      newValues: newData,
      notes: 'تعديل فاتورة',
    );
    
    // تسجيل للعميل أيضاً إذا كان موجوداً
    if (customerId != null) {
      await logOperation(
        operationType: 'invoice_update',
        entityType: 'customer',
        entityId: customerId,
        oldValues: {...oldData, 'invoice_id': invoiceId},
        newValues: {...newData, 'invoice_id': invoiceId},
        notes: 'تعديل فاتورة رقم $invoiceId',
      );
    }
  }

  /// تسجيل حذف فاتورة
  Future<void> logInvoiceDelete(int invoiceId, Map<String, dynamic> invoiceData) async {
    await logOperation(
      operationType: 'invoice_delete',
      entityType: 'invoice',
      entityId: invoiceId,
      oldValues: invoiceData,
      notes: 'حذف فاتورة',
    );
  }

  /// تسجيل إضافة معاملة دين
  Future<void> logTransactionCreate(int transactionId, Map<String, dynamic> transactionData) async {
    await logOperation(
      operationType: 'transaction_create',
      entityType: 'transaction',
      entityId: transactionId,
      newValues: transactionData,
      notes: 'إضافة معاملة دين',
    );
  }

  /// تسجيل تعديل معاملة
  Future<void> logTransactionUpdate(
    int transactionId,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) async {
    await logOperation(
      operationType: 'transaction_update',
      entityType: 'transaction',
      entityId: transactionId,
      oldValues: oldData,
      newValues: newData,
      notes: 'تعديل معاملة',
    );
  }

  /// تسجيل حذف معاملة
  Future<void> logTransactionDelete(int transactionId, Map<String, dynamic> transactionData) async {
    await logOperation(
      operationType: 'transaction_delete',
      entityType: 'transaction',
      entityId: transactionId,
      oldValues: transactionData,
      notes: 'حذف معاملة',
    );
  }

  /// تسجيل تسوية فاتورة
  Future<void> logInvoiceAdjustment(
    int invoiceId,
    String adjustmentType,
    double amount,
  ) async {
    await logOperation(
      operationType: 'invoice_adjustment',
      entityType: 'invoice',
      entityId: invoiceId,
      newValues: {
        'adjustment_type': adjustmentType,
        'amount': amount,
      },
      notes: 'تسوية فاتورة: $adjustmentType بمبلغ $amount',
    );
  }

  /// تسجيل تحديث رصيد عميل
  Future<void> logCustomerBalanceUpdate(
    int customerId,
    double oldBalance,
    double newBalance,
    String reason,
  ) async {
    await logOperation(
      operationType: 'customer_balance_update',
      entityType: 'customer',
      entityId: customerId,
      oldValues: {'balance': oldBalance},
      newValues: {'balance': newBalance},
      notes: 'تحديث رصيد عميل: $reason',
    );
  }

  /// تسجيل إصلاح بيانات
  Future<void> logDataRepair(String repairType, String details) async {
    await logOperation(
      operationType: 'data_repair',
      entityType: 'system',
      entityId: 0,
      notes: '$repairType: $details',
    );
  }

  /// جلب سجل التدقيق لكيان معين
  Future<List<Map<String, dynamic>>> getAuditLogForEntity(
    String entityType,
    int entityId,
  ) async {
    return await _db.getAuditLogForEntity(entityType, entityId);
  }

  /// جلب سجل التدقيق لفترة زمنية
  Future<List<Map<String, dynamic>>> getAuditLogForPeriod(
    DateTime startDate,
    DateTime endDate,
  ) async {
    return await _db.getAuditLogForPeriod(startDate, endDate);
  }

  /// جلب آخر العمليات المالية
  Future<List<Map<String, dynamic>>> getRecentAuditLogs({int limit = 50}) async {
    return await _db.getRecentAuditLogs(limit: limit);
  }
}
