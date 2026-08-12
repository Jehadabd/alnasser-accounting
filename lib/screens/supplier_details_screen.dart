import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import '../models/supplier.dart';
import '../models/purchase_invoice.dart';
import '../models/supplier_payment.dart';
import '../models/supplier_delegate.dart';
import '../services/purchase_service.dart';
import '../services/suppliers_service.dart';
import 'create_purchase_invoice_screen.dart';
import 'register_payment_dialog.dart';
import 'invoice_details_split_screen.dart';
import 'delegate_details_screen.dart';

class SupplierDetailsScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailsScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> {
  late Supplier _supplier;
  List<PurchaseInvoice> _invoices = [];
  List<SupplierPayment> _payments = [];
  List<SupplierDelegate> _delegates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final purchaseService = context.read<PurchaseService>();
    final suppliersService = context.read<SuppliersService>();
    
    final invoices = await purchaseService.getInvoicesForSupplier(_supplier.id!);
    final payments = await purchaseService.getPaymentsForSupplier(_supplier.id!);
    final delegates = await suppliersService.getDelegates(_supplier.id!);
    
    final suppliers = await purchaseService.getSuppliers(query: _supplier.name);
    final updatedSupplier = suppliers.firstWhere(
      (s) => s.id == _supplier.id,
      orElse: () => _supplier,
    );
    
    if (mounted) {
      setState(() {
        _invoices = invoices;
        _payments = payments;
        _delegates = delegates;
        _supplier = updatedSupplier;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 50
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsGrid(),
                    const SizedBox(height: 32),
                    
                    _buildSectionHeader('المندوبين', Icons.people_outline, 
                      action: TextButton.icon(
                        onPressed: _showAddDelegateDialog,
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const Text('إضافة مندوب'),
                      )
                    ),
                    const SizedBox(height: 16),
                    _buildDelegatesList(),
                    const SizedBox(height: 32),

                    _buildSectionHeader('آخر الفواتير', Icons.receipt_long_outlined),
                    const SizedBox(height: 16),
                    _buildRecentInvoicesList(),
                    const SizedBox(height: 32),
                     
                    _buildSectionHeader('سجل المدفوعات', Icons.payment_outlined),
                    const SizedBox(height: 16),
                    _buildRecentPaymentsList(),
                    const SizedBox(height: 40), // Bottom padding
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200.0,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF0F172A)),
            Positioned(
              right: -50, top: -50,
              child: Icon(Icons.business, size: 200, color: Colors.white.withOpacity(0.05)),
            ),
            Padding(
               padding: const EdgeInsets.all(24.0),
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.end,
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   const SizedBox(height: 40),
                   Row(
                     children: [
                       Container(
                         padding: const EdgeInsets.all(3),
                         decoration: BoxDecoration(
                           color: Colors.white,
                           borderRadius: BorderRadius.circular(50),
                         ),
                         child: CircleAvatar(
                           radius: 32,
                           backgroundColor: const Color(0xFF3B82F6),
                           child: Text(
                             _supplier.name.isNotEmpty ? _supplier.name[0].toUpperCase() : '?',
                             style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                           ),
                         ),
                       ),
                       const SizedBox(width: 16),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(
                               _supplier.name,
                               style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                             ),
                             const SizedBox(height: 4),
                             Row(
                               children: [
                                 if (_supplier.phone != null) ...[
                                   Icon(Icons.phone, size: 14, color: Colors.grey[400]),
                                   const SizedBox(width: 4),
                                   Text(_supplier.phone!, style: TextStyle(color: Colors.grey[400])),
                                   const SizedBox(width: 16),
                                 ],
                                 Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                   decoration: BoxDecoration(
                                     color: Colors.white.withOpacity(0.1),
                                     borderRadius: BorderRadius.circular(4),
                                   ),
                                   child: Text(
                                     _supplier.paymentTerms == 'credit' ? 'آجل' : 'نقدي',
                                     style: const TextStyle(color: Colors.white, fontSize: 12),
                                   ),
                                 ),
                               ],
                             ),
                           ],
                         ),
                       ),
                     ],
                   ),
                 ],
               ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: _editSupplier),
        IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadData),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildStatBox(
            'الرصيد الكلي',
            '${_formatNumber(_supplier.totalDebt)} ${_supplier.currency}',
            Icons.account_balance_wallet,
            _supplier.hasDebt ? Colors.red : Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatBox(
            'الفواتير',
            '${_supplier.totalInvoices}',
            Icons.receipt_long,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatBox(
            'المدفوعات',
            '${_supplier.totalPayments}',
            Icons.payments,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Segoe UI')),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {Widget? action}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const Spacer(),
        if (action != null) action,
      ],
    );
  }

  Widget _buildDelegatesList() {
    if (_delegates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text('لا يوجد مندوبين مرتبطين', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _delegates.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final delegate = _delegates[index];
          return GestureDetector(
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DelegateDetailsScreen(delegate: delegate),
                ),
              );
            },
            child: Container(
              width: 130,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.blue[50],
                    child: Text(delegate.name[0].toUpperCase(), style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(delegate.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (delegate.phone != null)
                    Text(delegate.phone!, maxLines: 1, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentInvoicesList() {
    if (_invoices.isEmpty) {
      return const Center(child: Text('لا توجد فواتير بعد'));
    }
    
    // Show only top 5 recent invoices
    final recentInvoices = _invoices.take(5).toList();

    return Column(
      children: recentInvoices.map((invoice) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[100]!),
          ),
          child: ListTile(
            leading: div(
              child: Icon(Icons.receipt_long, color: Colors.blue[700]),
              color: Colors.blue[50]!,
            ),
            title: Text('فاتورة #${invoice.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(intl.DateFormat('yyyy-MM-dd').format(invoice.date)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_formatNumber(invoice.totalAmount)} ${invoice.currency}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(invoice.statusArabic, style: TextStyle(fontSize: 11, color: _getStatusColor(invoice.status))),
              ],
            ),
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InvoiceDetailsSplitScreen(invoiceId: invoice.id!),
                ),
              );
            },
          ),
        );
      }).toList(),
    );
  }
  Widget div({required Widget child, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: child,
    );
  }

  Widget _buildRecentPaymentsList() {
    if (_payments.isEmpty) return const Center(child: Text('لا توجد مدفوعات'));
    final recent = _payments.take(5).toList();

    return Column(
      children: recent.map((payment) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
           child: ListTile(
            leading: div(child: const Icon(Icons.check, color: Colors.green), color: Colors.green[50]!),
            title: Text('تسديد دفعة', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(intl.DateFormat('yyyy-MM-dd').format(payment.date)),
            trailing: Text('${_formatNumber(payment.amount)} ${payment.currency}', 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.note_add),
                title: const Text('إنشاء فاتورة شراء'),
                onTap: () {
                  Navigator.pop(context);
                  _createInvoice();
                },
              ),
              ListTile(
                leading: const Icon(Icons.payment),
                title: const Text('تسجيل دفعة واصلة'),
                onTap: () {
                  Navigator.pop(context);
                  _registerPayment();
                },
              ),
            ],
          ),
        );
      },
      icon: const Icon(Icons.add),
      label: const Text('إجراء جديد'),
      backgroundColor: const Color(0xFF0F172A),
    );
  }

  void _showAddDelegateDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مندوب جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'اسم المندوب', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              
              final service = context.read<SuppliersService>();
              await service.addDelegate(SupplierDelegate(
                supplierId: _supplier.id!,
                name: nameController.text.trim(),
                phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
              ));
              
              Navigator.pop(context);
              _loadData(); // Refresh
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _createInvoice() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePurchaseInvoiceScreen(preselectedSupplier: _supplier),
      ),
    ).then((_) => _loadData());
  }

  void _registerPayment() {
    showDialog(
      context: context,
      builder: (_) => RegisterPaymentDialog(supplier: _supplier),
    ).then((_) => _loadData());
  }

  void _editSupplier() {
    // Reuse existing logic from Dashboard/List screen if refactored, or implement duplicate here for now
  }

  MaterialColor _getStatusColor(String status) {
    switch (status) {
      case 'draft': return Colors.grey;
      case 'confirmed': return Colors.blue;
      case 'paid': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.blue;
    }
  }

  String _formatNumber(double number) {
    if (number == 0) return '0';
    return intl.NumberFormat("#,##0", "en_US").format(number);
  }
}
