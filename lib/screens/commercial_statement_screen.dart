// screens/commercial_statement_screen.dart
// شاشة كشف الحساب التجاري
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:printing/printing.dart';
import '../models/customer.dart';
import '../services/commercial_statement_service.dart';
import '../services/pdf_service.dart';

/// حوار اختيار الفترة الزمنية
class PeriodSelectionDialog extends StatefulWidget {
  final List<int> availableYears;
  
  const PeriodSelectionDialog({
    super.key,
    required this.availableYears,
  });

  @override
  State<PeriodSelectionDialog> createState() => _PeriodSelectionDialogState();
}

class _PeriodSelectionDialogState extends State<PeriodSelectionDialog> {
  int? _selectedYear;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر الفترة الزمنية', textAlign: TextAlign.center),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.all_inclusive, color: Colors.blue),
                title: const Text('كشف حساب شامل'),
                subtitle: const Text('جميع المعاملات منذ البداية'),
                onTap: () => Navigator.pop(context, {'type': 'all'}),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('أو اختر سنة:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...widget.availableYears.map((year) => _buildYearTile(year)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }

  Widget _buildYearTile(int year) {
    final isExpanded = _selectedYear == year;
    return Column(
      children: [
        ListTile(
          leading: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.indigo),
          title: Text('سنة $year'),
          onTap: () => setState(() => _selectedYear = isExpanded ? null : year),
        ),
        if (isExpanded) ...[
          Padding(
            padding: const EdgeInsets.only(right: 32),
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.green),
              title: const Text('السنة كاملة'),
              onTap: () => Navigator.pop(context, {'type': 'year', 'year': year}),
            ),
          ),
          ...List.generate(12, (index) {
            final month = index + 1;
            return Padding(
              padding: const EdgeInsets.only(right: 32),
              child: ListTile(
                leading: const Icon(Icons.date_range, color: Colors.orange),
                title: Text('شهر $month - $year'),
                onTap: () => Navigator.pop(context, {'type': 'month', 'year': year, 'month': month}),
              ),
            );
          }),
        ],
      ],
    );
  }
}

/// شاشة كشف الحساب التجاري
class CommercialStatementScreen extends StatefulWidget {
  final Customer customer;
  final DateTime? startDate;
  final DateTime? endDate;
  final String periodDescription;

  const CommercialStatementScreen({
    super.key,
    required this.customer,
    this.startDate,
    this.endDate,
    required this.periodDescription,
  });

  @override
  State<CommercialStatementScreen> createState() => _CommercialStatementScreenState();
}

class _CommercialStatementScreenState extends State<CommercialStatementScreen> {
  final CommercialStatementService _service = CommercialStatementService();
  Map<String, dynamic>? _statementData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    try {
      setState(() { _isLoading = true; _error = null; });
      final data = await _service.getCommercialStatement(
        customerId: widget.customer.id!,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );
      if (mounted) setState(() { _statementData = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  String _formatCurrency(num value) => NumberFormat('#,##0', 'en_US').format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('كشف الحساب التجاري - ${widget.customer.name}'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير PDF',
            onPressed: _statementData != null ? _exportPdf : null,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('حدث خطأ: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadStatement, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_statementData == null) return const Center(child: Text('لا توجد بيانات'));

    final entries = _statementData!['entries'] as List<Map<String, dynamic>>;
    final summary = _statementData!['summary'] as Map<String, dynamic>;
    final finalBalance = (_statementData!['finalBalance'] as num).toDouble();

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSummaryCard(summary),
          _buildBalanceWarning(finalBalance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('الفترة: ${widget.periodDescription}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          // عناوين الأعمدة
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: const [
                Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('البيان', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('المبلغ', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('الدين قبل', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('الدين بعد', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ],
            ),
          ),
          // قائمة السطور
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            itemBuilder: (context, index) => _buildEntryRow(entries[index]),
          ),
        ],
      ),
    );
  }


  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final totalDebtInvoices = summary['totalDebtInvoices'] as int? ?? 0;
    final totalCashInvoices = summary['totalCashInvoices'] as int? ?? 0;
    final convertedToCash = summary['convertedToCash'] as int? ?? 0;
    final convertedToDebt = summary['convertedToDebt'] as int? ?? 0;
    final invoiceDebts = (summary['invoiceDebts'] as num?)?.toDouble() ?? 0.0;
    final manualDebts = (summary['manualDebts'] as num?)?.toDouble() ?? 0.0;
    final totalDebts = (summary['totalDebts'] as num?)?.toDouble() ?? 0.0;
    final invoicePayments = (summary['invoicePayments'] as num?)?.toDouble() ?? 0.0;
    final manualPayments = (summary['manualPayments'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (summary['totalPayments'] as num?)?.toDouble() ?? 0.0;
    final remainingBalance = (summary['remainingBalance'] as num?)?.toDouble() ?? 0.0;
    final balanceColor = remainingBalance > 0 ? Colors.red : Colors.green;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('ملخص الحساب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            
            // عدد الفواتير
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('فواتير دين', '$totalDebtInvoices', Colors.blue),
                _buildSummaryItem('فواتير نقد', '$totalCashInvoices', Colors.blueGrey),
              ],
            ),
            // الفواتير المحولة
            if (convertedToCash > 0 || convertedToDebt > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (convertedToCash > 0)
                      _buildSummaryItem('تحولت لنقد', '$convertedToCash', Colors.purple),
                    if (convertedToDebt > 0)
                      _buildSummaryItem('تحولت لدين', '$convertedToDebt', Colors.deepOrange),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            
            // إجمالي الديون
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text('إجمالي الديون', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem('ديون الفواتير', _formatCurrency(invoiceDebts), Colors.orange[700]!),
                      _buildSummaryItem('ديون يدوية', _formatCurrency(manualDebts), Colors.orange[400]!),
                    ],
                  ),
                  const Divider(),
                  Text('المجموع: ${_formatCurrency(totalDebts)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[800])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // إجمالي المدفوعات
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text('إجمالي المدفوعات', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem('مدفوعات الفواتير', _formatCurrency(invoicePayments), Colors.green[700]!),
                      _buildSummaryItem('مدفوعات يدوية', _formatCurrency(manualPayments), Colors.green[400]!),
                    ],
                  ),
                  const Divider(),
                  Text('المجموع: ${_formatCurrency(totalPayments)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[800])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // الرصيد المتبقي
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: remainingBalance > 0 ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: balanceColor, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الرصيد المتبقي:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(_formatCurrency(remainingBalance), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: balanceColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // تم إزالة تنبيه الفرق لأن الرصيد المحسوب من كشف الحساب التجاري 
  // قد يختلف عن رصيد العميل المخزن بسبب توقيت التحديث
  Widget _buildBalanceWarning(double finalBalance) {
    // لا نعرض تنبيه - الرصيد المحسوب هو الصحيح
    return const SizedBox.shrink();
  }

  Widget _buildEntryRow(Map<String, dynamic> entry) {
    final date = entry['date'] as DateTime;
    final description = entry['description'] as String;
    final invoiceAmount = (entry['invoiceAmount'] as num?)?.toDouble() ?? 0.0;
    final netAmount = (entry['netAmount'] as num?)?.toDouble() ?? 0.0;
    final debtBefore = (entry['debtBefore'] as num?)?.toDouble() ?? 0.0;
    final debtAfter = (entry['debtAfter'] as num?)?.toDouble() ?? 0.0;
    final type = entry['type'] as String;
    
    // تحديد المبلغ المعروض:
    // - فاتورة نقد: مبلغ الفاتورة (للعرض فقط)
    // - فاتورة محولة لنقد/لدين: مبلغ الفاتورة الأصلي
    // - فاتورة دين: مبلغ الفاتورة
    // - معاملة يدوية: المبلغ
    double displayAmount;
    if (type == 'cash_invoice' || type == 'converted_to_cash' || type == 'converted_to_debt' || type == 'debt_invoice') {
      displayAmount = invoiceAmount; // مبلغ الفاتورة الأصلي
    } else {
      displayAmount = netAmount.abs(); // صافي التأثير على الدين
    }
    
    Color rowColor = Colors.white;
    Color amountColor = Colors.black;
    if (type == 'cash_invoice') {
      rowColor = Colors.blue[50]!;
      amountColor = Colors.blue[700]!;
    } else if (type == 'converted_to_cash') {
      rowColor = Colors.purple[50]!;
      amountColor = Colors.purple[700]!;
    } else if (type == 'converted_to_debt') {
      rowColor = Colors.deepOrange[50]!;
      amountColor = Colors.deepOrange[700]!;
    } else if (type == 'manual_transaction') {
      rowColor = netAmount < 0 ? Colors.green[50]! : Colors.orange[50]!;
      amountColor = netAmount < 0 ? Colors.green[700]! : Colors.orange[700]!;
    } else if (type == 'debt_invoice') {
      amountColor = Colors.red[700]!;
    }

    return Container(
      color: rowColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(DateFormat('yyyy/MM/dd').format(date), style: const TextStyle(fontSize: 12))),
          Expanded(flex: 3, child: Text(description, style: const TextStyle(fontSize: 12))),
          Expanded(flex: 2, child: Text(_formatCurrency(displayAmount), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: amountColor))),
          Expanded(flex: 2, child: Text(_formatCurrency(debtBefore), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          Expanded(flex: 2, child: Text(_formatCurrency(debtAfter), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: debtAfter > 0 ? Colors.red : Colors.green))),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final pdfService = PdfService();
      final pdf = await pdfService.generateCommercialStatement(
        customer: widget.customer,
        statementData: _statementData!,
        periodDescription: widget.periodDescription,
      );

      if (mounted) Navigator.pop(context);

      if (Platform.isWindows) {
        final safeCustomerName = widget.customer.name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
        final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final fileName = 'كشف_تجاري_${safeCustomerName}_$formattedDate.pdf';
        final directory = Directory('${Platform.environment['USERPROFILE']}/Documents/commercial_statements');
        if (!await directory.exists()) await directory.create(recursive: true);
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdf);
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إنشاء كشف الحساب التجاري وفتحه!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) await Printing.layoutPdf(onLayout: (format) async => pdf);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
