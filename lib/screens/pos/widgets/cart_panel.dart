import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/pos_provider.dart';
import '../../../services/database_service.dart';

class CartPanel extends StatefulWidget {
  const CartPanel({super.key});

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _paidController = TextEditingController();
  bool _showSuggestions = false;
  
  // Number formatter with thousands separator
  static final _numberFormat = NumberFormat('#,###', 'ar');
  String _formatNumber(num value) => _numberFormat.format(value.toInt());

  @override
  void dispose() {
    _customerController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, provider, child) {
        final cartItems = provider.cartItems;

        return Container(
          color: Colors.white,
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Text('الفاتورة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                        child: Text('${cartItems.length}', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ]),
                    Row(children: [
                      IconButton(onPressed: () => _showQuickInvoicesHistory(context), icon: const Icon(Icons.history, color: Colors.grey, size: 20), tooltip: 'الفواتير السريعة'),
                      if (cartItems.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            provider.clearCart();
                            _customerController.clear();
                            _discountController.clear();
                            _paidController.clear();
                          },
                          child: const Text('مسح', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                    ]),
                  ],
                ),
              ),

              // Customer Name with Autocomplete
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Column(
                  children: [
                    TextField(
                      controller: _customerController,
                      onChanged: (value) {
                        provider.setCustomerName(value);
                        setState(() => _showSuggestions = value.isNotEmpty && provider.filteredCustomers.isNotEmpty);
                      },
                      decoration: InputDecoration(
                        hintText: 'اسم العميل (اختياري)',
                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (_showSuggestions && provider.filteredCustomers.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)]),
                        child: Column(
                          children: provider.filteredCustomers.map((customer) => ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: CircleAvatar(radius: 12, backgroundColor: Colors.blue[50], child: const Icon(Icons.person, size: 14, color: Colors.blue)),
                            title: Text(customer.name, style: const TextStyle(fontSize: 13)),
                            subtitle: customer.currentTotalDebt > 0 ? Text('دين: ${customer.currentTotalDebt.toStringAsFixed(0)}', style: TextStyle(fontSize: 10, color: Colors.orange[700])) : null,
                            onTap: () {
                              _customerController.text = customer.name;
                              provider.selectCustomer(customer);
                              setState(() => _showSuggestions = false);
                            },
                          )).toList(),
                        ),
                      ),
                  ],
                ),
              ),

              // Cart Items Table
              Expanded(
                child: cartItems.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey[200]),
                        const SizedBox(height: 12),
                        Text('لا توجد عناصر', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                      ]))
                    : Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 24, child: Text('ت', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[600]))),
                                const SizedBox(width: 4),
                                Expanded(flex: 14, child: Text('المنتج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[600]))),
                                Expanded(flex: 6, child: Text('العدد', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[600]))),
                                Expanded(flex: 5, child: Text('نوع البيع', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[600]))),
                                Expanded(flex: 5, child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[600]))),
                                const SizedBox(width: 24),
                              ],
                            ),
                          ),
                          // Table Body
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: cartItems.length,
                              itemBuilder: (context, index) {
                                final item = cartItems[index];
                                final units = provider.getProductUnits(item.product);
                                
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                  ),
                                  child: Row(
                                    children: [
                                      // # Index
                                      SizedBox(
                                        width: 24,
                                        child: Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Product Name
                                      Expanded(
                                        flex: 14,
                                        child: Text(
                                          item.product.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                      ),
                                      // Quantity Controls
                                      Expanded(
                                        flex: 6,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            InkWell(
                                              onTap: () => provider.updateQuantity(item.id, -1),
                                              child: Icon(Icons.remove_circle_outline, size: 20, color: Colors.grey[600]),
                                            ),
                                            SizedBox(
                                              width: 28,
                                              child: Text(
                                                '${item.quantity}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () => provider.updateQuantity(item.id, 1),
                                              child: Icon(Icons.add_circle_outline, size: 20, color: Colors.blue[600]),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Unit Type
                                      Expanded(
                                        flex: 5,
                                        child: units.length > 1
                                            ? DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: item.selectedUnit,
                                                  isDense: true,
                                                  isExpanded: true,
                                                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                                                  icon: const Icon(Icons.arrow_drop_down, size: 16),
                                                  items: units.map((u) => DropdownMenuItem(value: u['name'] as String, child: Text(u['name'] as String, style: const TextStyle(fontSize: 11)))).toList(),
                                                  onChanged: (newUnit) {
                                                    if (newUnit != null) {
                                                      final unitData = units.firstWhere((u) => u['name'] == newUnit);
                                                      provider.updateCartItemUnit(
                                                        item.id,
                                                        newUnit,
                                                        (unitData['price'] as num).toDouble(),
                                                        (unitData['quantity'] as num).toInt(),
                                                      );
                                                    }
                                                  },
                                                ),
                                              )
                                            : Text(
                                                item.selectedUnit,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                              ),
                                      ),
                                      // Price (inline editable TextField with auto-save on focus lost)
                                      Expanded(
                                        flex: 5,
                                        child: Focus(
                                          onFocusChange: (hasFocus) {
                                            if (!hasFocus) {
                                              // Save on focus lost
                                            }
                                          },
                                          child: Builder(
                                            builder: (ctx) {
                                              final controller = TextEditingController(text: _formatNumber(item.price));
                                              return TextField(
                                                controller: controller,
                                                keyboardType: TextInputType.number,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue[800]),
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.blue.shade200)),
                                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.blue.shade200)),
                                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.blue.shade400, width: 2)),
                                                ),
                                                onChanged: (value) {
                                                  final newPrice = double.tryParse(value.replaceAll(',', ''));
                                                  if (newPrice != null && newPrice > 0) {
                                                    provider.updateCartItemUnit(item.id, item.selectedUnit, newPrice, item.unitsInLargeUnit);
                                                  }
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      // Delete
                                      SizedBox(
                                        width: 24,
                                        child: IconButton(
                                          onPressed: () => provider.removeFromCart(item.id),
                                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),

              // Summary Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 12)]),
                child: Column(
                  children: [
                    // Payment Toggle
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Expanded(child: GestureDetector(
                          onTap: () => provider.setPaymentType(PaymentType.cash),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: provider.paymentType == PaymentType.cash ? Colors.green : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text('نقد', style: TextStyle(color: provider.paymentType == PaymentType.cash ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 13))),
                          ),
                        )),
                        Expanded(child: GestureDetector(
                          onTap: () => provider.setPaymentType(PaymentType.credit),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: provider.paymentType == PaymentType.credit ? Colors.orange : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text('دين', style: TextStyle(color: provider.paymentType == PaymentType.credit ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold, fontSize: 13))),
                          ),
                        )),
                      ]),
                    ),

                    // Discount + Subtotal Row
                    Row(children: [
                      const Text('الخصم:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _discountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (v) => provider.setDiscount(double.tryParse(v) ?? 0),
                          decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), hintText: '0'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      Text('المجموع: ${_formatNumber(provider.subtotal)}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ]),
                    const SizedBox(height: 6),

                    // Paid Amount (Credit only)
                    if (provider.paymentType == PaymentType.credit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          const Text('المسدد:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _paidController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onChanged: (v) => provider.setPaidAmount(double.tryParse(v) ?? 0),
                              decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), hintText: '0'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Spacer(),
                          Text('المتبقي: ${_formatNumber(provider.remainingAmount)}', style: TextStyle(color: Colors.orange[700], fontWeight: FontWeight.bold, fontSize: 12)),
                        ]),
                      ),

                    // Total
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('الإجمالي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(_formatNumber(provider.total), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: provider.paymentType == PaymentType.cash ? Colors.green[700] : Colors.orange[700])),
                    ]),
                    const SizedBox(height: 10),

                    // Charge Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: cartItems.isEmpty ? null : () async {
                          final success = await provider.processCheckout();
                          if (success && context.mounted) {
                            _customerController.clear();
                            _discountController.clear();
                            _paidController.clear();
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ الفاتورة #${provider.lastInvoiceDisplayNumber ?? provider.lastInvoiceId} بنجاح!'), backgroundColor: Colors.green));
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: provider.paymentType == PaymentType.cash ? Colors.green[600] : Colors.orange[600],
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(provider.paymentType == PaymentType.cash ? Icons.payment : Icons.receipt_long, size: 20),
                          const SizedBox(width: 6),
                          Text(provider.paymentType == PaymentType.cash ? 'دفع نقدي' : 'حفظ كدين', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQuickInvoicesHistory(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => const _QuickInvoicesSheet());
  }
}

class _QuickInvoicesSheet extends StatefulWidget {
  const _QuickInvoicesSheet();
  @override
  State<_QuickInvoicesSheet> createState() => _QuickInvoicesSheetState();
}

class _QuickInvoicesSheetState extends State<_QuickInvoicesSheet> {
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadInvoices(); }

  Future<void> _loadInvoices() async {
    try {
      final db = await DatabaseService().database;
      final result = await db.rawQuery('SELECT id, invoice_number, customer_name, total_amount, payment_type, created_at FROM invoices ORDER BY created_at DESC LIMIT 50');
      setState(() { _invoices = result; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(children: [
        Container(margin: const EdgeInsets.only(top: 10), width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('الفواتير السريعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
        ])),
        const Divider(height: 1),
        Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _invoices.isEmpty ? const Center(child: Text('لا توجد فواتير')) : ListView.builder(
          itemCount: _invoices.length,
          itemBuilder: (context, index) {
            final inv = _invoices[index];
            return ListTile(
              dense: true,
              leading: CircleAvatar(radius: 16, backgroundColor: inv['payment_type'] == 'نقد' ? Colors.green[100] : Colors.orange[100], child: Icon(inv['payment_type'] == 'نقد' ? Icons.payments : Icons.receipt_long, size: 16, color: inv['payment_type'] == 'نقد' ? Colors.green : Colors.orange)),
              title: Text('فاتورة #${inv['invoice_number'] ?? inv['id']}', style: const TextStyle(fontSize: 13)),
              subtitle: Text(inv['customer_name'] ?? 'عميل', style: const TextStyle(fontSize: 11)),
              trailing: Text((inv['total_amount'] as num).toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            );
          },
        )),
      ]),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QuantityButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)), child: Icon(icon, size: 14, color: Colors.grey[700])),
    );
  }
}
