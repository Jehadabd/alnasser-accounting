import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import '../models/supplier.dart';
import '../models/supplier_payment.dart';
import '../models/supplier_delegate.dart';
import '../services/purchase_service.dart';

/// Dialog لتسجيل دفعة للمورد (Odoo-Style)
class RegisterPaymentDialog extends StatefulWidget {
  final Supplier supplier;

  const RegisterPaymentDialog({super.key, required this.supplier});

  @override
  State<RegisterPaymentDialog> createState() => _RegisterPaymentDialogState();
}

class _RegisterPaymentDialogState extends State<RegisterPaymentDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _date = DateTime.now();
  String _currency = 'IQD';
  String _paymentMethod = 'cash';
  bool _isSaving = false;
  List<SupplierDelegate> _delegates = [];
  SupplierDelegate? _selectedDelegate;

  @override
  void initState() {
    super.initState();
    _currency = widget.supplier.currency;
    _loadDelegates();
  }

  Future<void> _loadDelegates() async {
    // Wait for frame to access context safely if needed, though initState context is usually fine for read, 
    // but better to use Future.microtask or just await in async wrapper
    WidgetsBinding.instance.addPostFrameCallback((_) async {
       try {
         final list = await context.read<PurchaseService>().getDelegatesForSupplier(widget.supplier.id!);
         if (mounted) setState(() => _delegates = list);
       } catch (e) {
         print('Error loading delegates: $e');
       }
    });
  }

  double get _currentDebt => _currency == 'USD' 
      ? widget.supplier.totalDebtUsd 
      : widget.supplier.totalDebtIqd;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.payments, color: Colors.green, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تسجيل دفعة',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.supplier.name,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Current Balance
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _currentDebt > 0 
                    ? Colors.red.withOpacity(0.1) 
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _currentDebt > 0 
                      ? Colors.red.withOpacity(0.3) 
                      : Colors.green.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الرصيد الحالي:'),
                  Text(
                    '${intl.NumberFormat('#,##0').format(_currentDebt)} $_currency',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _currentDebt > 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Amount
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'المبلغ المدفوع *',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.attach_money),
                suffixText: _currency,
                filled: true,
                fillColor: Colors.grey[50],
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Currency + Payment Method Row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _currency,
                    decoration: const InputDecoration(
                      labelText: 'العملة',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'IQD', child: Text('IQD')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (val) => setState(() => _currency = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('نقداً')),
                      DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                      DropdownMenuItem(value: 'transfer', child: Text('حوالة')),
                    ],
                    onChanged: (val) => setState(() => _paymentMethod = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'التاريخ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(intl.DateFormat('yyyy-MM-dd').format(_date)),
              ),
            ),
            const SizedBox(height: 16),

            // Notes
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _savePayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle),
                    label: const Text('تأكيد الدفع'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _savePayment() async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال مبلغ صحيح'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final payment = SupplierPayment(
        supplierId: widget.supplier.id!,
        delegateId: _selectedDelegate?.id,
        amount: amount,
        currency: _currency,
        paymentMethod: _paymentMethod,
        date: _date,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      await context.read<PurchaseService>().registerPayment(payment);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تسجيل الدفعة: ${intl.NumberFormat('#,##0').format(amount)} $_currency ✓'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }
}
