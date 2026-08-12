// screens/audit_log_screen.dart
// شاشة سجل التدقيق المالي

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/financial_audit_service.dart';

class AuditLogScreen extends StatefulWidget {
  final int? customerId;
  final String? customerName;
  final String? entityType; // 'customer', 'supplier', 'invoice', 'transaction'

  const AuditLogScreen({
    super.key,
    this.customerId,
    this.customerName,
    this.entityType,
  });

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final FinancialAuditService _auditService = FinancialAuditService();
  List<Map<String, dynamic>> _auditLogs = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      List<Map<String, dynamic>> logs;
      
      if (widget.customerId != null && widget.entityType != null) {
        // جلب سجل التدقيق لعميل/مورد محدد
        logs = await _auditService.getAuditLogForEntity(
          widget.entityType!,
          widget.customerId!,
        );
      } else {
        // جلب آخر 100 عملية
        logs = await _auditService.getRecentAuditLogs(limit: 100);
      }

      setState(() {
        _auditLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في تحميل سجل التدقيق: $e';
        _isLoading = false;
      });
    }
  }


  // ترجمة نوع العملية
  String _translateOperationType(String type) {
    switch (type) {
      case 'invoice_create':
        return 'إنشاء فاتورة';
      case 'invoice_update':
        return 'تعديل فاتورة';
      case 'invoice_delete':
        return 'حذف فاتورة';
      case 'transaction_create':
        return 'إضافة دين يدوي';
      case 'payment_create':
        return 'تسديد دين';
      case 'transaction_update':
        return 'تعديل معاملة';
      case 'transaction_delete':
        return 'حذف معاملة';
      case 'invoice_adjustment':
        return 'تسوية فاتورة';
      case 'customer_balance_update':
        return 'تحديث رصيد';
      case 'data_repair':
        return 'إصلاح بيانات';
      case 'supplier_invoice_create':
        return 'فاتورة مورد جديدة';
      case 'supplier_invoice_update':
        return 'تعديل فاتورة مورد';
      case 'supplier_invoice_delete':
        return 'حذف فاتورة مورد';
      case 'supplier_receipt_create':
        return 'سند قبض مورد';
      case 'supplier_receipt_update':
        return 'تعديل سند قبض';
      case 'supplier_receipt_delete':
        return 'حذف سند قبض';
      default:
        return type;
    }
  }

  // الحصول على أيقونة العملية
  IconData _getOperationIcon(String type) {
    if (type.contains('receipt')) return Icons.payments;
    if (type.contains('supplier')) return Icons.local_shipping;
    if (type.contains('create')) return Icons.add_circle;
    if (type.contains('update')) return Icons.edit;
    if (type.contains('delete')) return Icons.delete;
    if (type.contains('adjustment')) return Icons.tune;
    if (type.contains('balance')) return Icons.account_balance_wallet;
    if (type.contains('repair')) return Icons.build;
    return Icons.history;
  }

  // الحصول على لون العملية
  Color _getOperationColor(String type) {
    if (type.contains('create')) return Colors.green;
    if (type.contains('update')) return Colors.blue;
    if (type.contains('delete')) return Colors.red;
    if (type.contains('adjustment')) return Colors.orange;
    if (type.contains('balance')) return Colors.purple;
    if (type.contains('repair')) return Colors.teal;
    return Colors.grey;
  }

  // تنسيق التاريخ
  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd - HH:mm', 'en_US').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  // عرض تفاصيل السجل
  void _showLogDetails(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getOperationIcon(log['operation_type'] ?? ''),
              color: _getOperationColor(log['operation_type'] ?? ''),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _translateOperationType(log['operation_type'] ?? ''),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('التاريخ', _formatDate(log['created_at'])),
              _buildDetailRow('نوع الكيان', log['entity_type'] ?? '-'),
              _buildDetailRow('معرف الكيان', '${log['entity_id'] ?? '-'}'),
              if (log['notes'] != null && log['notes'].toString().isNotEmpty)
                _buildDetailRow('ملاحظات', log['notes']),
              if (log['old_values'] != null && log['old_values'].toString().isNotEmpty)
                _buildJsonSection('القيم القديمة', log['old_values']),
              if (log['new_values'] != null && log['new_values'].toString().isNotEmpty)
                _buildJsonSection('القيم الجديدة', log['new_values']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // ترجمة مفاتيح JSON إلى العربية
  String _translateKey(String key) {
    final translations = {
      'total_amount': 'الإجمالي',
      'discount': 'الخصم',
      'payment_type': 'نوع الدفع',
      'paid_amount': 'المدفوع',
      'customer_id': 'رقم العميل',
      'customer_name': 'اسم العميل',
      'items_count': 'عدد الأصناف',
      'invoice_id': 'رقم الفاتورة',
      'amount': 'المبلغ',
      'type': 'النوع',
      'balance_before': 'الرصيد قبل',
      'balance_after': 'الرصيد بعد',
      'transaction_id': 'رقم المعاملة',
      'note': 'ملاحظة',
      'old_balance': 'الرصيد القديم',
      'new_balance': 'الرصيد الجديد',
      'quantity': 'الكمية',
      'price': 'السعر',
      'product_name': 'اسم المنتج',
      'loading_fee': 'أجور التحميل',
      'return_amount': 'المرتجع',
    };
    return translations[key] ?? key;
  }

  // تنسيق القيمة (أرقام مع فواصل)
  String _formatValue(dynamic value) {
    if (value == null) return '-';
    if (value is num) {
      return NumberFormat('#,##0.##', 'en_US').format(value);
    }
    // محاولة تحويل النص إلى رقم
    final numValue = num.tryParse(value.toString());
    if (numValue != null) {
      return NumberFormat('#,##0.##', 'en_US').format(numValue);
    }
    // ترجمة بعض القيم النصية
    if (value == 'دين') return 'دين';
    if (value == 'نقد') return 'نقد';
    return value.toString();
  }

  Widget _buildJsonSection(String title, String jsonStr) {
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(jsonStr);
    } catch (e) {
      data = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        if (data != null)
          ...data.entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 16, top: 2),
                child: Text('• ${_translateKey(e.key)}: ${_formatValue(e.value)}'),
              ))
        else
          Text(jsonStr, style: const TextStyle(fontSize: 12)),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final title = widget.customerName != null
        ? 'سجل تدقيق: ${widget.customerName}'
        : 'سجل التدقيق المالي';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadAuditLogs,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF3F51B5)),
            SizedBox(height: 16),
            Text('جاري تحميل سجل التدقيق...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAuditLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_auditLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.customerId != null
                  ? 'لا توجد عمليات مسجلة لهذا العميل'
                  : 'لا توجد عمليات مسجلة بعد',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم تسجيل العمليات المالية تلقائياً',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAuditLogs,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _auditLogs.length,
        itemBuilder: (context, index) {
          final log = _auditLogs[index];
          final operationType = log['operation_type'] ?? '';
          
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getOperationColor(operationType).withOpacity(0.2),
                child: Icon(
                  _getOperationIcon(operationType),
                  color: _getOperationColor(operationType),
                ),
              ),
              title: Text(
                _translateOperationType(operationType),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatDate(log['created_at'])),
                  if (log['notes'] != null && log['notes'].toString().isNotEmpty)
                    Text(
                      log['notes'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _showLogDetails(log),
            ),
          );
        },
      ),
    );
  }
}
