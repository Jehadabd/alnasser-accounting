// screens/invoice_details_screen.dart
import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../services/database_service.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final int invoiceId;

  const InvoiceDetailsScreen({
    super.key,
    required this.invoiceId,
  });

  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  Invoice? _invoice;
  List<InvoiceItem> _invoiceItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoiceDetails();
  }

  Future<void> _loadInvoiceDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // إزالة الطباعات التشخيصية في الإصدار النهائي

      final invoice = await _databaseService.getInvoiceById(widget.invoiceId);
      final items = await _databaseService.getInvoiceItems(widget.invoiceId);

      setState(() {
        _invoice = invoice;
        _invoiceItems = items;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          'فاتورة رقم ${widget.invoiceId}',
          style: const TextStyle(fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvoiceDetails,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
              ),
            )
          : _invoice == null
              ? const Center(
                  child: Text(
                    'لم يتم العثور على الفاتورة',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadInvoiceDetails,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInvoiceHeader(),
                        const SizedBox(height: 16),
                        _buildInvoiceItems(),
                        const SizedBox(height: 16),
                        _buildInvoiceSummary(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildInvoiceHeader() {
    return Card(
      elevation: 4,
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
                    'فاتورة رقم ${_invoice!.id}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _invoice!.status,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4CAF50),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildHeaderInfo('العميل', _invoice!.customerName),
            if (_invoice!.customerPhone != null)
              _buildHeaderInfo('الهاتف', _invoice!.customerPhone!),
            if (_invoice!.customerAddress != null)
              _buildHeaderInfo('العنوان', _invoice!.customerAddress!),
            _buildHeaderInfo('التاريخ',
                '${_invoice!.invoiceDate.day}/${_invoice!.invoiceDate.month}/${_invoice!.invoiceDate.year}'),
            _buildHeaderInfo('نوع الدفع', _invoice!.paymentType),
            if (_invoice!.installerName != null)
              _buildHeaderInfo('المؤسس', _invoice!.installerName!),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF666666),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2C3E50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceItems() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المنتجات',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 12),
            ..._invoiceItems.map((item) => _buildItemRow(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(InvoiceItem item) {
    final double quantity = item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0;
    final double costPrice = item.actualCostPrice ?? item.costPrice ?? 0.0;
    final double profitPerUnit = item.appliedPrice - costPrice;
    final double totalProfit = profitPerUnit * quantity;
    final double totalSelling = item.appliedPrice * quantity;
    final double profitPercent = totalSelling > 0 ? (totalProfit / totalSelling) * 100.0 : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: totalProfit >= 0 ? Colors.green.withOpacity(0.25) : Colors.red.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ),
              Text(
                '${item.itemTotal.toStringAsFixed(2)} د.ع',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'الكمية: ${quantity.toStringAsFixed(2)} ${item.unit}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                  ),
                ),
              ),
              Text(
                'السعر: ${item.appliedPrice.toStringAsFixed(2)} د.ع',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: totalProfit >= 0 ? Colors.green.withOpacity(0.08) : Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      totalProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: totalProfit >= 0 ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تفاصيل الربح',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: totalProfit >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${profitPercent.toStringAsFixed(1)}%'
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'التكلفة: ${costPrice.toStringAsFixed(2)} د.ع',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                      ),
                    ),
                    Text(
                      'الربح/الوحدة: ${profitPerUnit.toStringAsFixed(2)} د.ع',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: totalProfit >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'الربح الإجمالي: ${totalProfit.toStringAsFixed(2)} د.ع',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: totalProfit >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceSummary() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSummaryRow(
                'المجموع', '${_invoice!.totalAmount.toStringAsFixed(2)} د.ع'),
            if (_invoice!.discount > 0)
              _buildSummaryRow(
                  'الخصم', '${_invoice!.discount.toStringAsFixed(2)} د.ع'),
            if (_invoice!.returnAmount > 0)
              _buildSummaryRow('المرتجع',
                  '${_invoice!.returnAmount.toStringAsFixed(2)} د.ع'),
            const Divider(),
            _buildSummaryRow(
              'المدفوع',
              '${_invoice!.amountPaidOnInvoice.toStringAsFixed(2)} د.ع',
              isTotal: true,
            ),
            if (_invoice!.amountPaidOnInvoice < _invoice!.totalAmount)
              _buildSummaryRow(
                'المتبقي',
                '${(_invoice!.totalAmount - _invoice!.amountPaidOnInvoice).toStringAsFixed(2)} د.ع',
                color: const Color(0xFFF44336),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isTotal = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: const Color(0xFF2C3E50),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: color ?? const Color(0xFF4CAF50),
            ),
          ),
        ],
      ),
    );
  }
}
