import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kPrimaryColor = Color(0xFF5D5FEF);
const Color kInputFillColor = Color(0xFFF8F9FA);

class ModernTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool isRequired;
  final List<TextInputFormatter>? inputFormatters;
  final Function(String)? onChanged;
  final TextInputType? keyboardType;
  final IconData? icon;

  const ModernTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.isRequired = false,
    this.inputFormatters,
    this.onChanged,
    this.keyboardType,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
             if (icon != null) ...[Icon(icon, size: 14, color: kPrimaryColor), const SizedBox(width: 4)],
             Text(label, style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12)),
             if (isRequired) const Text(' *', style: TextStyle(color: Colors.red)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: kInputFillColor, borderRadius: BorderRadius.circular(12)),
          child: TextFormField(
            controller: controller,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              isDense: true,
            ),
            validator: isRequired ? (val) => val == null || val.isEmpty ? 'مطلوب' : null : null,
          ),
        ),
      ],
    );
  }
}
