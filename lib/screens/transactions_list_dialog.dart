// screens/transactions_list_dialog.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';

/// Dialog لعرض قائمة المعاملات (إضافة دين أو تسديد دين)
class TransactionsListDialog extends StatefulWidget {
  final String title;
  final List<String> transactionTypes;
  final DateTime startDate;
  final DateTime endDate;
  final Color themeColor;

  const TransactionsListDialog({
    super.key,
    required this.title,
    required this.transactionTypes,
    required this.startDate,
    required this.endDate,
    required this.themeColor,
  });

  @override
  State<TransactionsListDialog> createState() => _TransactionsListDialogState();

  /// عرض Dialog لمعاملات إضافة الدين
  static Future<void> showDebtAdditions({
    required BuildContext context,
    required DateTime startDate,
    required DateTime endDate,
    required String periodTitle,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => TransactionsListDialog(
        title: 'معاملات إضافة الدين - $periodTitle',
        transactionTypes: ['manual_debt', 'opening_balance'],
        startDate: startDate,
        endDate: endDate,
        themeColor: const Color(0xFFFF5722),
      ),
    );
  }

  /// عرض Dialog لمعاملات تسديد الدين
  static Future<void> showDebtPayments({
    required BuildContext context,
    required DateTime startDate,
    required DateTime endDate,
    required String periodTitle,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => TransactionsListDialog(
        title: 'معاملات تسديد الدين - $periodTitle',
        transactionTypes: ['manual_payment'],
        startDate: startDate,
        endDate: endDate,
        themeColor: const Color(0xFF4CAF50),
      ),
    );
  }
}

class _TransactionsListDialogState extends State<TransactionsListDialog> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');

  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    try {
      final transactions = await _db.getTransactionsWithCustomerName(
        transactionTypes: widget.transactionTypes,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );
      setState(() {
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل المعاملات: $e')),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy-MM-dd HH:mm', 'ar').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String _getTransactionTypeName(String? type) {
    switch (type) {
      case 'manual_debt':
        return 'إضافة دين يدوية';
      case 'opening_balance':
        return 'دين مبدئي';
      case 'manual_payment':
        return 'تسديد دين';
      default:
        return type ?? 'غير محدد';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // العنوان
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.themeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.transactionTypes.contains('manual_payment')
                        ? Icons.remove_circle
                        : Icons.add_circle,
                    color: widget.themeColor,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // عدد المعاملات
            if (!_isLoading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'عدد المعاملات: ${_transactions.length}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'الإجمالي: ${_fmt(_transactions.fold(0.0, (sum, t) => sum + ((t['amount_changed'] as num?)?.toDouble().abs() ?? 0)))} د.ع',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // قائمة المعاملات
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: widget.themeColor),
                    )
                  : _transactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'لا توجد معاملات في هذه الفترة',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final tx = _transactions[index];
                            return _buildTransactionCard(tx, index + 1);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx, int index) {
    final customerName = tx['customer_name'] as String? ?? 'غير معروف';
    final amount = ((tx['amount_changed'] as num?)?.toDouble() ?? 0).abs();
    final balanceBefore = (tx['balance_before_transaction'] as num?)?.toDouble() ?? 0;
    final balanceAfter = (tx['new_balance_after_transaction'] as num?)?.toDouble() ?? 0;
    final note = tx['transaction_note'] as String?;
    final description = tx['description'] as String?;
    final dateStr = tx['transaction_date'] as String?;
    final type = tx['transaction_type'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رقم المعاملة واسم العميل
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.themeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.themeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getTransactionTypeName(type),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_fmt(amount)} د.ع',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.themeColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // تفاصيل الرصيد
            Row(
              children: [
                Expanded(
                  child: _buildBalanceInfo(
                    'الرصيد قبل',
                    balanceBefore,
                    Colors.grey[700]!,
                  ),
                ),
                const Icon(Icons.arrow_forward, color: Colors.grey),
                Expanded(
                  child: _buildBalanceInfo(
                    'الرصيد بعد',
                    balanceAfter,
                    widget.themeColor,
                  ),
                ),
              ],
            ),
            // التاريخ
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  _formatDate(dateStr),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            // الملاحظة
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.amber[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // الوصف
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceInfo(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_fmt(value)} د.ع',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
