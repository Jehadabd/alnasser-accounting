// screens/add_customer_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart'; // Import for NumberFormat
import '../widgets/formatters.dart';

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
  final _addressController = TextEditingController(); // This controller is now explicitly used for the address TextFormField

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
      cleaned = '964' + cleaned.substring(1);
    }
    
    // إذا لم يبدأ برمز الدولة، أضف رمز العراق
    if (!cleaned.startsWith('964') && cleaned.length == 10) {
      cleaned = '964' + cleaned;
    }
    
    return cleaned;
  }

  Future<void> _saveCustomer() async {
    if (_formKey.currentState!.validate()) {
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

      // Using the AppProvider to add the customer, assuming it handles DB insertion
      await context.read<AppProvider>().addCustomer(customer);
      
      if (mounted) {
        String successMessage = 'تم إضافة العميل ${customer.name} بنجاح!';
        if (normalizedPhone != null) {
          successMessage += '\nرقم الهاتف: $normalizedPhone';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } else {
      // Show a general error message if form validation fails
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الرجاء تصحيح الأخطاء في النموذج قبل الحفظ.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // Helper to format numbers with thousand separators
  String formatNumber(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    // Define the consistent theme colors for the screen
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor = const Color(0xFF8C9EFF); // Light Indigo Accent (Indigo A200)
    final Color textColor = const Color(0xFF212121); // Dark grey for general text
    final Color lightBackgroundColor = const Color(0xFFF8F8F8); // Very light grey for text field fill
    final Color successColor = Colors.green[600]!; // Green for success messages
    final Color errorColor = Colors.red[700]!; // Red for error messages

    return Theme(
      data: ThemeData(
        // Define color scheme for light theme
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white, // Text/icons on primary color
          secondary: accentColor,
          onSecondary: Colors.black, // Text/icons on secondary color
          surface: Colors.white, // Card/sheet background
          onSurface: textColor, // Text/icons on surface
          background: Colors.white, // Scaffold background
          onBackground: textColor, // Text/icons on background
          error: errorColor,
          onError: Colors.white, // Text/icons on error color
          tertiary: successColor, // Custom color for success, used in SnackBars
        ),
        // Define typography (font family and text styles)
        fontFamily: 'Roboto', // Modern, clean font
        textTheme: TextTheme(
          titleLarge: TextStyle(fontSize: 22.0, fontWeight: FontWeight.bold, color: Colors.white), // AppBar title
          titleMedium: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600, color: textColor), // Section titles
          bodyLarge: TextStyle(fontSize: 16.0, color: textColor), // General body text
          bodyMedium: TextStyle(fontSize: 14.0, color: textColor), // Smaller body text
          labelLarge: TextStyle(fontSize: 16.0, color: Colors.white, fontWeight: FontWeight.w600), // Button text
          labelMedium: TextStyle(fontSize: 14.0, color: Colors.grey[600]), // Input field labels
          bodySmall: TextStyle(fontSize: 12.0, color: Colors.grey[700]), // Hint text / captions
        ),
        // Define input field decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder( // Default border style
            borderRadius: BorderRadius.circular(10.0), // Rounded corners
            borderSide: BorderSide(color: Colors.grey[400]!), // Light grey border
          ),
          enabledBorder: OutlineInputBorder( // Border when enabled and not focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder( // Border when focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: primaryColor, width: 2.0), // Primary color, thicker
          ),
          errorBorder: OutlineInputBorder( // Border when in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0), // Error color, thicker
          ),
          focusedErrorBorder: OutlineInputBorder( // Border when focused and in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(color: Colors.grey[700], fontSize: 15.0), // Label text style
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14.0), // Hint text style
          contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0), // Inner padding
          filled: true, // Enable fill color
          fillColor: lightBackgroundColor, // Light background for fields
        ),
        // Define ElevatedButton theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor, // Button background color
            foregroundColor: Colors.white, // Button text/icon color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0), // Rounded corners
            ),
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0), // Inner padding
            elevation: 4, // Shadow elevation
            textStyle: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold), // Text style
          ),
        ),
        // Define AppBar theme
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor, // AppBar background color
          foregroundColor: Colors.white, // AppBar text/icon color
          centerTitle: true, // Center title
          elevation: 4, // Shadow elevation
          titleTextStyle: TextStyle( // Title text style (inherits from TextTheme.titleLarge)
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إضافة عميل جديد'),
          // The title style is now managed by appBarTheme.titleTextStyle
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24.0), // Increased padding for more spacious look
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم العميل',
                  hintText: 'أدخل اسم العميل',
                  prefixIcon: Icon(Icons.person_outline), // Added an icon
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'الرجاء إدخال اسم العميل';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20.0), // Increased spacing
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  hintText: 'أدخل رقم الهاتف (اختياري)',
                  prefixText: '+964 ',
                  prefixIcon: Icon(Icons.phone_outlined), // Added an icon
                ),
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
              ),
              const SizedBox(height: 20.0), // Increased spacing
              TextFormField(
                controller: _addressController, // Correctly linked to _addressController
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  hintText: 'أدخل عنوان العميل (اختياري)',
                  prefixIcon: Icon(Icons.location_on_outlined), // Added an icon
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20.0), // Increased spacing
              TextFormField(
                controller: _initialDebtController,
                decoration: const InputDecoration(
                  labelText: 'الدين المبدئي',
                  hintText: 'أدخل الدين المبدئي (اختياري)',
                  suffixText: ' دينار', // Added space for better readability
                  prefixIcon: Icon(Icons.money_off_csred_outlined), // Added an icon
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  ThousandSeparatorInputFormatter(),
                ],
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final number = double.tryParse(value.replaceAll(',', ''));
                    if (number == null) {
                      return 'الرجاء إدخال رقم صحيح';
                    }
                    if (number < 0) {
                      return 'لا يمكن إدخال قيمة سالبة';
                    }
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20.0), // Increased spacing
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  hintText: 'أدخل ملاحظات إضافية (اختياري)',
                  prefixIcon: Icon(Icons.notes_outlined), // Added an icon
                ),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 32.0), // Increased spacing before the button
              ElevatedButton.icon(
                onPressed: _saveCustomer,
                icon: const Icon(Icons.person_add_alt_1), // Modern icon
                label: const Text('حفظ العميل'), // Changed text for clarity
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56), // Larger button for better tap target
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}