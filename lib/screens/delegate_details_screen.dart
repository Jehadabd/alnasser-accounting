import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import '../models/supplier_delegate.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_service.dart';
import 'invoice_details_split_screen.dart';

class DelegateDetailsScreen extends StatefulWidget {
  final SupplierDelegate delegate;

  const DelegateDetailsScreen({super.key, required this.delegate});

  @override
  State<DelegateDetailsScreen> createState() => _DelegateDetailsScreenState();
}

class _DelegateDetailsScreenState extends State<DelegateDetailsScreen> {
  late SupplierDelegate _delegate;
  List<PurchaseInvoice> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _delegate = widget.delegate;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final purchaseService = context.read<PurchaseService>();
    
    // We need a method to get invoices by delegateId. 
    final invoices = await purchaseService.getInvoicesForDelegate(_delegate.id!);
    
    if (mounted) {
      setState(() {
        _invoices = invoices;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        title: Text(_delegate.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white,
                          child: Text(
                            _delegate.name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _delegate.name,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (_delegate.phone != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.phone, color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                                Text(_delegate.phone!, style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  const Text('سجل الفواتير مع هذا المندوب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  if (_invoices.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.folder_open, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('لا توجد فواتير مرتبطة بهذا المندوب حالياً', style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _invoices.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final invoice = _invoices[index];
                        return ListTile(
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: const Icon(Icons.receipt, color: Colors.blue),
                          title: Text('فاتورة #${invoice.invoiceNumber}'),
                          subtitle: Text(intl.DateFormat('yyyy-MM-dd').format(invoice.date)),
                          trailing: Text('${invoice.totalAmount} ${invoice.currency}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onTap: () {
                             Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => InvoiceDetailsSplitScreen(invoiceId: invoice.id!),
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
