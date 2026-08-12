// screens/person_month_details_screen.dart
import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/person_data.dart'; // Correct import
import '../models/transaction.dart';
import '../services/database_service.dart';
import 'invoice_details_screen.dart';
import 'package:intl/intl.dart';
import 'customer_products_dialog.dart';

class PersonMonthDetailsScreen extends StatefulWidget {
  final Customer customer;
  final int year;
  final int month;

  const PersonMonthDetailsScreen({
    super.key,
    required this.customer,
    required this.year,
    required this.month,
  });

  @override
  State<PersonMonthDetailsScreen> createState() =>
      _PersonMonthDetailsScreenState();
}

class _PersonMonthDetailsScreenState extends State<PersonMonthDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<InvoiceWithProductData> _invoices = [];
  List<DebtTransaction> _transactions = [];
  double _monthProfit = 0.0;
  double _monthSales = 0.0;
  bool _isLoading = true;
 late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);
  @override
  void initState() {
    super.initState();
    _loadMonthDetails();
  }

  Future<void> _loadMonthDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final invoices =
          await _databaseService.getCustomerInvoicesWithProfitForMonth(
        widget.customer.id!,
        widget.year,
        widget.month,
      );
      final transactions =
          await _databaseService.getCustomerTransactionsForMonth(
        widget.customer.id!,
        widget.year,
        widget.month,
      );
      double totalProfit = 0.0;
      double totalSales = 0.0;
      for (final inv in invoices) {
        totalProfit += inv.profit;
        totalSales += inv.totalAmount;
      }
      setState(() {
        _invoices = invoices;
        _transactions = transactions;
        _monthProfit = totalProfit;
        _monthSales = totalSales;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تحميل البيانات: $e'),
          ),
        );
      }
    }
  }

  String _numericMonth(int year, int month) => '${year}-${month.toString().padLeft(2, '0')}';

  void _showCumulativeSales() {
    showDialog(
      context: context,
      builder: (context) => CustomerProductsDialog(
        customerId: widget.customer.id!,
        customerName: widget.customer.name,
        year: widget.year,
        month: widget.month,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthName = _numericMonth(widget.year, widget.month);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          '${widget.customer.name} - ${monthName}',
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF2196F3),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMonthDetails,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2196F3),
              ),
            )
          : _invoices.isEmpty && _transactions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 80,
                        color: Color(0xFFCCCCCC),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'لا توجد تعاملات في هذا الشهر',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMonthDetails,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // ملخص الشهر
                        Card(
                          elevation: 4,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                                color: Colors.green.withOpacity(0.3), width: 1),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.green.withOpacity(0.1),
                                  Colors.green.withOpacity(0.05),
                                ],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.calendar_month,
                                        color: Colors.green,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ملخص الشهر',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'إجمالي المبيعات: ${_fmt(_monthSales)} د.ع',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'إجمالي الربح: ${_fmt(_monthProfit)} د.ع',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF4CAF50),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // زر المبيعات التراكمية للشهر
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showCumulativeSales,
                            icon: const Icon(Icons.analytics),
                            label: const Text('تفصيل المنتجات المشتراة'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_invoices.isNotEmpty) ...[
                          _buildSectionHeader('الفواتير', Icons.receipt_long),
                          const SizedBox(height: 12),
                          ..._invoices.map(
                              (invoiceData) => _buildInvoiceCard(invoiceData)),
                          const SizedBox(height: 20),
                        ],
                        if (_transactions.isNotEmpty) ...[
                          _buildSectionHeader('المعاملات المالية',
                              Icons.account_balance_wallet),
                          const SizedBox(height: 12),
                          ..._transactions.map((transaction) =>
                              _buildTransactionCard(transaction)),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2196F3), size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceCard(InvoiceWithProductData invoiceData) {
    final invoiceId = invoiceData.invoiceId;
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InvoiceDetailsScreen(
                invoiceId: invoiceId,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'فاتورة رقم ${invoiceId}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${invoiceData.invoiceDate.day}/${invoiceData.invoiceDate.month}/${invoiceData.invoiceDate.year}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2196F3),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInvoiceInfo(
                      icon: Icons.trending_up,
                      title: 'الربح',
                      value: '${_fmt(invoiceData.profit)} د.ع',
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInvoiceInfo(
                      icon: Icons.shopping_cart,
                      title: 'الخصم',
                      value: '${_fmt(invoiceData.discount)}',
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildInvoiceInfo(
                      icon: Icons.attach_money,
                      title: 'المجموع',
                      value: '${_fmt(invoiceData.totalAmount)} د.ع',
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
// removed 'paid' and 'remaining' as they are not available directly in simplified view
// unless we fetch full invoice. For now, showing totalAmount is safe.
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(DebtTransaction transaction) {
    final isPositive = transaction.amountChanged > 0;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    transaction.transactionType,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : const Color(0xFFF44336).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${transaction.transactionDate.day}/${transaction.transactionDate.month}/${transaction.transactionDate.year}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isPositive
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFF44336),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTransactionInfo(
                    icon: isPositive ? Icons.add : Icons.remove,
                    title: 'المبلغ',
                    value:
                        '${_fmt(transaction.amountChanged.abs())} د.ع',
                    color: isPositive
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFF44336),
                  ),
                ),
                if (transaction.newBalanceAfterTransaction != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTransactionInfo(
                      icon: Icons.account_balance,
                      title: 'الرصيد الجديد',
                      value:
                          '${_fmt(transaction.newBalanceAfterTransaction!)} د.ع',
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                ],
              ],
            ),
            if (transaction.transactionNote != null) ...[
              const SizedBox(height: 8),
              Text(
                'ملاحظة: ${transaction.transactionNote}',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceInfo({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionInfo({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
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
