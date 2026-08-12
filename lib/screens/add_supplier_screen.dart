import 'package:flutter/material.dart';
import '../models/supplier.dart';

class AddSupplierScreen extends StatefulWidget {
  const AddSupplierScreen({Key? key}) : super(key: key);

  @override
  State<AddSupplierScreen> createState() => _AddSupplierScreenState();
}

class _AddSupplierScreenState extends State<AddSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingBalanceController = TextEditingController(text: '0');

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة مورد')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الشركة',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'الاسم مطلوب'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'الهاتف (اختياري)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _openingBalanceController,
                decoration: const InputDecoration(
                  labelText: 'رصيد افتتاحي (اختياري)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                  onPressed: _onSave,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    final opening = double.tryParse(_openingBalanceController.text.trim()) ?? 0;
    final supplier = Supplier(
      companyName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      openingBalance: opening,
      currentBalance: opening,
    );
    Navigator.of(context).pop(supplier);
  }
}


