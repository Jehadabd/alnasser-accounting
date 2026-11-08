// lib/widgets/edit_customer_dialog.dart
//
// ✏️ تعديل معلومات العميل — بنفس هيكل نوافذ البرنامج (AppDialogShell):
// الاسم (مطلوب)، الهاتف (يُعرض كيف سيُحفظ بالصيغة الدولية)، العنوان.
// لا تغيّر النافذة أي دين: تعيد القيم فقط، والحفظ عند المستدعي.

import 'package:flutter/material.dart';

import 'app_dialog_shell.dart';

const _navy = Color(0xFF0F3460);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _red = Color(0xFFB91C1C);
const _green = Color(0xFF047857);

/// القيم بعد التعديل، أو null عند الإلغاء. [phone] فارغ = حذف الرقم.
Future<({String name, String phone, String address})?> showEditCustomerDialog(
  BuildContext context, {
  required String name,
  String? phone,
  String? address,
  required String Function(String raw) normalizePhone,
}) =>
    showDialog(
      context: context,
      builder: (_) => _EditCustomerDialog(
        name: name,
        phone: phone ?? '',
        address: address ?? '',
        normalizePhone: normalizePhone,
      ),
    );

class _EditCustomerDialog extends StatefulWidget {
  const _EditCustomerDialog({
    required this.name,
    required this.phone,
    required this.address,
    required this.normalizePhone,
  });
  final String name, phone, address;
  final String Function(String raw) normalizePhone;

  @override
  State<_EditCustomerDialog> createState() => _EditCustomerDialogState();
}

class _EditCustomerDialogState extends State<_EditCustomerDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _phone = TextEditingController(text: widget.phone);
  late final _address = TextEditingController(text: widget.address);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  String get _digits => _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
  String? get _nameError => _name.text.trim().isEmpty ? 'الاسم مطلوب' : null;
  String? get _phoneError {
    if (_phone.text.trim().isEmpty) return null;
    if (_digits.length < 10 || _digits.length > 15) return 'رقم غير صالح — مثل 07701234567';
    return null;
  }

  bool get _changed =>
      _name.text.trim() != widget.name.trim() ||
      _phone.text.trim() != widget.phone.trim() ||
      _address.text.trim() != widget.address.trim();

  bool get _valid => _nameError == null && _phoneError == null;

  void _save() {
    if (!_valid) return;
    final raw = _phone.text.trim();
    Navigator.pop(context, (
      name: _name.text.trim(),
      phone: raw.isEmpty ? '' : widget.normalizePhone(raw),
      address: _address.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final raw = _phone.text.trim();
    final preview = raw.isEmpty || _phoneError != null ? null : widget.normalizePhone(raw);
    final initial = _name.text.trim().isEmpty ? '؟' : _name.text.trim().characters.first;
    return AppDialogShell(
      icon: Icons.edit_rounded,
      color: _navy,
      title: 'تعديل معلومات العميل',
      subtitle: 'الاسم والهاتف والعنوان — الدين لا يتغيّر',
      onClose: () => Navigator.pop(context),
      maxWidth: 520,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _navy.withValues(alpha: 0.10),
              child: Text(initial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _navy)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _name.text.trim().isEmpty ? 'عميل بلا اسم' : _name.text.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _field(
            controller: _name,
            label: 'اسم العميل',
            icon: Icons.person_rounded,
            error: _nameError,
            autofocus: true,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _phone,
            label: 'رقم الهاتف',
            hint: '07701234567',
            icon: Icons.phone_rounded,
            error: _phoneError,
            ltr: true,
            keyboard: TextInputType.phone,
            suffix: raw.isEmpty
                ? null
                : IconButton(
                    tooltip: 'حذف الرقم',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(_phone.clear),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Text(
              preview != null
                  ? 'يُحفظ بالصيغة الدولية: $preview'
                  : (raw.isEmpty ? 'بلا رقم — لن يصل للعميل تذكير واتساب' : ''),
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: 12, color: preview != null ? _green : _muted),
            ),
          ),
          const SizedBox(height: 14),
          _field(
            controller: _address,
            label: 'العنوان',
            icon: Icons.location_on_rounded,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size(130, 44)),
          onPressed: _valid && _changed ? _save : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('حفظ'),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? error,
    bool ltr = false,
    bool autofocus = false,
    int maxLines = 1,
    TextInputType? keyboard,
    Widget? suffix,
  }) =>
      TextField(
        controller: controller,
        autofocus: autofocus,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: ltr ? TextDirection.ltr : null,
        textInputAction: maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
        onChanged: (_) => setState(() {}),
        onSubmitted: maxLines == 1 && controller == _address ? (_) => _save() : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          prefixIcon: Icon(icon, color: _navy, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _line)),
          focusedBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _navy, width: 1.6)),
          errorBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _red)),
        ),
      );
}
