// widgets/customer_fields.dart
import 'package:flutter/material.dart';

class CustomerFields extends StatelessWidget {
  final TextEditingController customerNameController;
  final TextEditingController customerPhoneController;
  final TextEditingController customerAddressController;
  final TextEditingController installerNameController;
  final bool isViewOnly;
  final String? Function(String?)? nameValidator;
  final void Function(String) onCustomerNameChanged;

  const CustomerFields({
    Key? key,
    required this.customerNameController,
    required this.customerPhoneController,
    required this.customerAddressController,
    required this.installerNameController,
    required this.isViewOnly,
    required this.nameValidator,
    required this.onCustomerNameChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: customerNameController,
          decoration: const InputDecoration(labelText: 'اسم العميل'),
          validator: nameValidator,
          enabled: !isViewOnly,
          onChanged: onCustomerNameChanged,
        ),
        const SizedBox(height: 16.0),
        TextFormField(
          controller: customerPhoneController,
          decoration: const InputDecoration(labelText: 'رقم الجوال (اختياري)'),
          keyboardType: TextInputType.phone,
          enabled: !isViewOnly,
        ),
        const SizedBox(height: 16.0),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: customerAddressController,
                decoration: const InputDecoration(labelText: 'العنوان (اختياري)'),
                enabled: !isViewOnly,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: installerNameController,
                decoration: const InputDecoration(labelText: 'اسم المؤسس/الفني (اختياري)'),
                enabled: !isViewOnly,
              ),
            ),
          ],
        ),
      ],
    );
  }
} 