// screens/add_customer_screen.dart
//
// 👤 إضافة عميل جديد — بشكل البرنامج الموحّد (settings_kit): بطاقة معاينة حيّة تتحدث مع
// الكتابة (الحرف الأول، الاسم، الهاتف بالصيغة الدولية، الدين المبدئي)، ثم أقسام: البيانات
// الأساسية، الحساب، الملاحظات، وزر حفظ ثابت أسفل الشاشة.
// المنطق كما كان حرفياً: التحقق نفسه، تنسيق الهاتف نفسه، قفل الحفظ، ومنع الاسم المكرر.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection; // TextDirection من Flutter (ltr)
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../providers/app_provider.dart';
import '../services/database/business/customer_name_rule.dart';
import '../services/save_lock.dart'; // 🔒 قفل الحفظ
import '../widgets/formatters.dart';
import '../widgets/settings_kit.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  final _initialDebtController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    _initialDebtController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // تنسيق رقم الهاتف للصيغة الدولية
  String _normalizePhoneNumber(String phone) {
    // إزالة كل شيء غير الأرقام
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // إذا بدأ بصفر محلي، استبدله برمز الدولة العراقية
    if (cleaned.startsWith('0')) {
      cleaned = '964${cleaned.substring(1)}';
    }

    // إذا لم يبدأ برمز الدولة، أضف رمز العراق
    if (!cleaned.startsWith('964') && cleaned.length == 10) {
      cleaned = '964$cleaned';
    }

    return cleaned;
  }

  // 🔒 لا يُنفَّذ مرتين مهما كانت سرعة الضغط (القفل قبل أي انتظار)
  Future<void> _saveCustomer() async {
    setState(() => _saving = true);
    try {
      await SaveLock.run(() => _saveCustomerUnlocked(), message: 'جارٍ حفظ العميل…');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCustomerUnlocked() async {
    if (!_formKey.currentState!.validate()) {
      setToast(context, 'الرجاء تصحيح الأخطاء في النموذج قبل الحفظ.', error: true);
      return;
    }
    // تنسيق رقم الهاتف تلقائياً
    String? normalizedPhone;
    if (_phoneController.text.isNotEmpty) {
      normalizedPhone = _normalizePhoneNumber(_phoneController.text);
    }

    final customer = Customer(
      name: _nameController.text,
      phone: normalizedPhone,
      generalNote: _noteController.text.isEmpty ? null : _noteController.text,
      currentTotalDebt: double.tryParse(_initialDebtController.text.replaceAll(',', '')) ?? 0.0,
      address: _addressController.text.isEmpty ? null : _addressController.text,
    );

    try {
      await context.read<AppProvider>().addCustomer(customer);
    } on DuplicateCustomerNameException catch (e) {
      // 🛡️ سجل الديون: لا حسابان بالاسم نفسه
      if (mounted) setToast(context, e.toString(), error: true);
      return;
    }

    if (mounted) {
      var successMessage = 'تم إضافة العميل ${customer.name} بنجاح!';
      if (normalizedPhone != null) successMessage += '\nرقم الهاتف: $normalizedPhone';
      setToast(context, successMessage);
      Navigator.pop(context);
    }
  }

  String _formatNumber(num value) => NumberFormat('#,##0', 'en_US').format(value);

  InputDecoration _dec(String label, String hint, IconData icon, {String? prefixText, String? suffixText}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        suffixText: suffixText,
        prefixIcon: Icon(icon, size: 21),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kSetBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kSetBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kSetBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kSetRed, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kSetRed, width: 1.6),
        ),
      );

  Widget _nameField() => TextFormField(
        controller: _nameController,
        autofocus: true,
        decoration: _dec('اسم العميل', 'أدخل اسم العميل', Icons.person_outline_rounded),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'الرجاء إدخال اسم العميل';
          return null;
        },
        textInputAction: TextInputAction.next,
      );

  Widget _phoneField() => TextFormField(
        controller: _phoneController,
        textDirection: TextDirection.ltr,
        decoration: _dec('رقم الهاتف', '7701234567 (اختياري)', Icons.phone_outlined, prefixText: '+964 '),
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
        validator: (value) {
          if (value != null && value.isNotEmpty) {
            if (!RegExp(r'^\d{10}$').hasMatch(value)) {
              return 'الرجاء إدخال رقم هاتف صحيح (10 أرقام)';
            }
          }
          return null;
        },
        textInputAction: TextInputAction.next,
      );

  Widget _addressField() => TextFormField(
        controller: _addressController,
        decoration: _dec('العنوان', 'المنطقة أو الشارع (اختياري)', Icons.location_on_outlined),
        textInputAction: TextInputAction.next,
      );

  Widget _debtField() => TextFormField(
        controller: _initialDebtController,
        textDirection: TextDirection.ltr,
        decoration: _dec('الدين المبدئي', '0 (اختياري)', Icons.account_balance_wallet_outlined, suffixText: ' دينار'),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          ThousandSeparatorInputFormatter(),
        ],
        validator: (value) {
          if (value != null && value.isNotEmpty) {
            final number = double.tryParse(value.replaceAll(',', ''));
            if (number == null) return 'الرجاء إدخال رقم صحيح';
            if (number < 0) return 'لا يمكن إدخال قيمة سالبة';
          }
          return null;
        },
        textInputAction: TextInputAction.next,
      );

  Widget _noteField() => TextFormField(
        controller: _noteController,
        decoration: _dec('ملاحظات', 'أي شيء يفيد عند التعامل معه (اختياري)', Icons.notes_rounded),
        minLines: 2,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
      );

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'إضافة عميل جديد',
      icon: Icons.person_add_alt_1_rounded,
      subtitle: 'يظهر فوراً في سجل الديون',
      maxWidth: 720,
      bottom: _SaveBar(saving: _saving, onSave: _saveCustomer),
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                _PreviewCard(
                  listenable: Listenable.merge([_nameController, _phoneController, _addressController, _initialDebtController]),
                  name: () => _nameController.text.trim(),
                  phone: () {
                    final t = _phoneController.text;
                    if (t.isEmpty) return '';
                    return '+964 ${t.startsWith('0') ? t.substring(1) : t}';
                  },
                  address: () => _addressController.text.trim(),
                  debt: () => double.tryParse(_initialDebtController.text.replaceAll(',', '')) ?? 0,
                  format: _formatNumber,
                ),
                const SizedBox(height: 14),
                SetCard(
                  title: 'البيانات الأساسية',
                  subtitle: 'الاسم وحده مطلوب — ولا يتكرر في سجل الديون',
                  icon: Icons.badge_outlined,
                  child: LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth > 560;
                    return Column(children: [
                      const SizedBox(height: 10),
                      _nameField(),
                      const SizedBox(height: 14),
                      if (wide)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: _phoneField()),
                          const SizedBox(width: 12),
                          Expanded(child: _addressField()),
                        ])
                      else ...[
                        _phoneField(),
                        const SizedBox(height: 14),
                        _addressField(),
                      ],
                    ]);
                  }),
                ),
                SetCard(
                  title: 'الحساب',
                  subtitle: 'دين سابق على العميل قبل التعامل في البرنامج (اتركه فارغاً إن لم يوجد)',
                  icon: Icons.account_balance_wallet_outlined,
                  color: kSetOrange,
                  child: Column(children: [
                    const SizedBox(height: 10),
                    _debtField(),
                  ]),
                ),
                SetCard(
                  title: 'ملاحظات',
                  icon: Icons.sticky_note_2_outlined,
                  color: kSetMuted,
                  child: Column(children: [
                    const SizedBox(height: 10),
                    _noteField(),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة معاينة: كيف سيظهر العميل في سجل الديون، تتحدث مع الكتابة.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.listenable,
    required this.name,
    required this.phone,
    required this.address,
    required this.debt,
    required this.format,
  });
  final Listenable listenable;
  final String Function() name, phone, address;
  final double Function() debt;
  final String Function(num) format;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: listenable,
        builder: (context, _) {
          final n = name();
          final p = phone();
          final a = address();
          final d = debt();
          final initial = n.isEmpty ? '؟' : n.characters.first;
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [kSetNavy, Color(0xFF1D4E89)],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              boxShadow: [BoxShadow(color: kSetNavy.withValues(alpha: 0.25), blurRadius: 22, offset: const Offset(0, 10))],
            ),
            child: Row(children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Container(
                  key: ValueKey(initial),
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: Text(initial,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.isEmpty ? 'اسم العميل' : n,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: n.isEmpty ? Colors.white54 : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(height: 4),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    _meta(Icons.phone_rounded, p.isEmpty ? 'بلا هاتف' : p, ltr: p.isNotEmpty),
                    if (a.isNotEmpty) _meta(Icons.location_on_rounded, a),
                  ]),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('الدين', style: TextStyle(color: Colors.white60, fontSize: 11.5)),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: d > 0 ? const Color(0xFFFFD5B8) : Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                  child: Text(format(d), textDirection: TextDirection.ltr),
                ),
              ]),
            ]),
          );
        },
      );

  Widget _meta(IconData icon, String text, {bool ltr = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white60),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ),
      ]);
}

/// زر الحفظ ثابت أسفل الشاشة (يبقى ظاهراً مهما طالت الصفحة أو ظهرت لوحة المفاتيح).
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.saving, required this.onSave});
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: kSetBorder)),
          boxShadow: [BoxShadow(color: Color(0x0F0F172A), blurRadius: 16, offset: Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SetPrimaryButton(
                  label: 'حفظ العميل',
                  icon: Icons.person_add_alt_1_rounded,
                  busy: saving,
                  color: kSetGreen,
                  onPressed: onSave,
                ),
              ),
            ),
          ),
        ),
      );
}
