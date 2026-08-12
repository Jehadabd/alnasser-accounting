import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart'; 
import '../models/purchase_invoice.dart';
import '../models/purchase_invoice_item.dart';
import '../services/purchase_service.dart';

class InvoiceDetailsSplitScreen extends StatefulWidget {
  final int invoiceId;

  const InvoiceDetailsSplitScreen({Key? key, required this.invoiceId}) : super(key: key);

  @override
  State<InvoiceDetailsSplitScreen> createState() => _InvoiceDetailsSplitScreenState();
}

class _InvoiceDetailsSplitScreenState extends State<InvoiceDetailsSplitScreen> {
  bool _isLoading = true;
  PurchaseInvoice? _invoice;
  List<PurchaseInvoiceItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final service = context.read<PurchaseService>();
    
    _items = await service.getInvoiceItems(widget.invoiceId);
    _invoice = await service.getInvoiceById(widget.invoiceId);
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_invoice == null) return const Scaffold(body: Center(child: Text('الفاتورة غير موجودة')));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('تفاصيل الفاتورة #${_invoice!.invoiceNumber}', 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Row(
        children: [
          // ⬅️ Left: Attachment (50%)
          Expanded(
            flex: 12,
            child: _buildLeftAttachmentPane(),
          ),
          
          const VerticalDivider(width: 1, color: Colors.black12),

          // ➡️ Right: Data (50%)
          Expanded(
            flex: 10,
            child: _buildRightDataPane(),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftAttachmentPane() {
    final path = _invoice?.attachmentPath;
    if (path == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('لا يوجد ملف مرفق لهذه الفاتورة', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final file = File(path);
    if (!file.existsSync()) {
      return const Center(child: Text('الملف المرفق غير موجود على هذا الجهاز'));
    }

    final ext = path.split('.').last.toLowerCase();
    
    // 📄 PDF Preview
    if (ext == 'pdf') {
      return PdfPreview(
        build: (format) => file.readAsBytes(),
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      );
    }
    
    // 🖼️ Image Preview
    if (['jpg', 'jpeg', 'png'].contains(ext)) {
      return Container(
        color: Colors.black,
        child: InteractiveViewer(
          child: Image.file(file, fit: BoxFit.contain),
        ),
      );
    }

    return Center(child: Text('نوع الملف غير مدعوم للعرض المباشر: $ext'));
  }

  Widget _buildRightDataPane() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummarySection(),
          const SizedBox(height: 32),
          _buildItemsSection(),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ملخص المبالغ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildValueCard('الإجمالي', _invoice!.totalAmount, Colors.blue)),
            const SizedBox(width: 12),
            Expanded(child: _buildValueCard('الواصل', _invoice!.paidAmount, Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _buildValueCard('المتبقي', _invoice!.remainingAmount, Colors.red, isBold: true)),
          ],
        ),
        const SizedBox(height: 12),
        _buildStatusRow(),
      ],
    );
  }

  Widget _buildStatusRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 8),
          const Text('حالة الفاتورة:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _getStatusColor(_invoice!.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _invoice!.statusArabic,
              style: TextStyle(color: _getStatusColor(_invoice!.status), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft': return Colors.grey;
      case 'confirmed': return Colors.blue;
      case 'partial': return Colors.orange;
      case 'paid': return Colors.green;
      default: return Colors.blue;
    }
  }

  Widget _buildValueCard(String title, double value, Color color, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(
            '${_formatNumber(value)} ${_invoice!.currency}',
            style: TextStyle(
              fontSize: 14, 
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600, 
              color: isBold ? color : const Color(0xFF1E293B)
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Colors.blue),
                const SizedBox(width: 12),
                const Text('أصناف الفاتورة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_items.length} أصناف', style: TextStyle(color: Colors.grey[500])),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _items[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                title: Text(item.productName ?? 'منتج غير معروف', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${item.quantity} ${item.unitName} × ${_formatNumber(item.unitPrice)}'),
                trailing: Text(
                  '${_formatNumber(item.totalPrice)} ${_invoice!.currency}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatNumber(double number) {
    return NumberFormat("#,##0", "en_US").format(number);
  }
}
